import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0095 and its rollback say — a static review of the files, not
/// a runtime result.
///
/// The migration has not been applied to the shared database and cannot be run
/// from a widget test, so these assertions read the text. That limit is worth
/// stating plainly: this proves the file says the right things, and a check on
/// the database itself (`supabase/tool/0095_..._verify.sql`) is what proves the
/// database does them. What it catches is the class of mistake that is invisible
/// in review and expensive in production — a gate that moved below a write, a
/// privilege quietly widened, a before-and-after copy of a phone number slipped
/// into the audit metadata, or a no-op that stopped being one.
void main() {
  const path =
      '../supabase/migrations/0095_platform_admin_user_account_management.sql';
  const rollbackPath = '../supabase/rollback/'
      '0095_platform_admin_user_account_management_rollback.sql';

  // Newlines are normalised on the way in: Git checks these files out with CRLF
  // endings on Windows and several assertions span two lines.
  String load(String file) =>
      File(file).readAsStringSync().replaceAll('\r\n', '\n');

  final sql = load(path);

  /// The file without comment lines, so an assertion about what the migration
  /// *does* is never satisfied by prose describing what it does not.
  String code(String text) => text
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  final statements = code(sql);

  /// The same, with SQL string literals blanked as well. `comment on` bodies are
  /// statements, and they legitimately *name* things this migration leaves alone.
  final executable = statements.replaceAll(RegExp("'[^']*'"), "''");

  const writers = [
    'admin_update_user_account',
    'admin_update_user_player_profile',
    'admin_update_user_privacy',
    'admin_update_user_default_wilayat',
    'admin_update_user_push_preferences',
  ];
  const reader = 'admin_get_user_account';

  /// One function's own text, header through body.
  String functionBody(String name) {
    final start =
        statements.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('0095 does not create $name');
    final end = statements.indexOf('\n\$\$;', start);
    return statements.substring(start, end == -1 ? statements.length : end);
  }

  /// The signature each function must have, exactly: name, then arguments.
  const signatures = {
    'admin_get_user_account': 'uuid',
    'admin_update_user_account': 'uuid, text, text, text',
    'admin_update_user_player_profile': 'uuid, date, text, text, text',
    'admin_update_user_privacy': 'uuid, text, boolean, text',
    'admin_update_user_default_wilayat': 'uuid, smallint, text',
    'admin_update_user_push_preferences':
        'uuid, boolean, boolean, boolean, text',
  };

  /// Positions of [needles] inside [body], failing loudly on a missing one.
  List<int> positions(String body, List<String> needles) => [
        for (final needle in needles)
          () {
            final at = body.indexOf(needle);
            if (at < 0) throw StateError('missing: $needle');
            return at;
          }(),
      ];

  group('the migration is 0095 and only 0095', () {
    test('both files exist under the numbers the brief fixed', () {
      expect(File(path).existsSync(), isTrue);
      expect(File(rollbackPath).existsSync(), isTrue);
    });

    test('exactly six functions are created, with the agreed signatures', () {
      final created = RegExp(r'create or replace function public\.(\w+)\(')
          .allMatches(statements)
          .map((m) => m.group(1)!)
          .toList();
      expect(created, [reader, ...writers]);

      for (final entry in signatures.entries) {
        final comment = RegExp(
          'comment on function public\\.${entry.key}\\(([^)]*)\\)',
        ).firstMatch(statements);
        expect(comment, isNotNull, reason: '${entry.key} has a comment');
        expect(comment!.group(1), entry.value);
      }
    });

    test('nothing existing is replaced, dropped or created beside them', () {
      expect(executable, isNot(contains('drop function')));
      expect(executable, isNot(contains('create table')));
      expect(executable, isNot(contains('create index')));
      expect(executable, isNot(contains('create view')));
      expect(executable, isNot(contains('create policy')));
      expect(executable, isNot(contains('alter policy')));
      expect(executable, isNot(contains('drop policy')));
      expect(executable, isNot(contains('create trigger')));
      expect(executable, isNot(contains('create type')));
      // The functions this migration is told not to change are called, never
      // defined.
      for (final untouchable in [
        'is_system_admin',
        'record_admin_audit',
        'admin_suspend_user',
        'admin_reactivate_user',
        'admin_list_users',
        'admin_list_audit_log',
        'complete_my_player_profile',
      ]) {
        expect(
          statements,
          isNot(contains('create or replace function public.$untouchable')),
          reason: '$untouchable is unchanged',
        );
      }
    });

    test('no table privilege, no column grant, no RLS statement', () {
      expect(executable, isNot(contains('on public.users')));
      expect(executable, isNot(contains('on table')));
      expect(executable, isNot(contains('row level security')));
      // Every grant and revoke names a function.
      for (final line in executable.split('\n')) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('grant ') || trimmed.startsWith('revoke ')) {
          expect(trimmed, contains('execute on function public.admin_'));
        }
      }
    });
  });

  group('the audit action', () {
    test('the CHECK is replaced with the four existing values plus one', () {
      expect(
        statements,
        contains('drop constraint if exists admin_audit_log_action_check'),
      );
      final add = RegExp(
        r"add constraint admin_audit_log_action_check check \(action in \(([^)]*)\)\)",
      ).firstMatch(statements);
      expect(add, isNotNull);
      final values = RegExp(r"'(\w+)'")
          .allMatches(add!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
      expect(values, [
        'USER_SUSPENDED',
        'USER_REACTIVATED',
        'COMMUNITY_SUSPENDED',
        'COMMUNITY_REACTIVATED',
        'USER_PROFILE_UPDATED',
      ]);
    });

    test('the only table touched is admin_audit_log, and only that constraint',
        () {
      final alters = RegExp(r'alter table ([\w.]+)')
          .allMatches(executable)
          .map((m) => m.group(1))
          .toList();
      expect(alters, ['public.admin_audit_log', 'public.admin_audit_log']);
      expect(executable, isNot(contains('admin_audit_log_target_type_check')));
    });

    test('every write records that action, against a USER, and no other', () {
      for (final name in writers) {
        final body = functionBody(name);
        expect(body, contains("'USER_PROFILE_UPDATED'"), reason: name);
        expect(body, contains("'USER',"), reason: name);
        expect(
          RegExp("'(USER|COMMUNITY)_(SUSPENDED|REACTIVATED)'").hasMatch(body),
          isFalse,
          reason: '$name records no suspension event',
        );
      }
    });
  });

  group('the read', () {
    final body = functionBody(reader);

    test('the gate is the first statement and USER_NOT_FOUND follows it', () {
      final at = positions(body, [
        'if not is_system_admin() then raise exception \'NOT_AUTHORIZED\'',
        "raise exception 'USER_NOT_FOUND'",
        'return query',
      ]);
      expect(at[0] < at[1] && at[1] < at[2], isTrue);
    });

    test('it writes nothing and has no self or System Admin restriction', () {
      for (final forbidden in [
        'insert into',
        'update users',
        'delete from',
        'record_admin_audit',
        'CANNOT_MODIFY',
        'auth.uid()',
      ]) {
        expect(body, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(body, contains('stable'));
    });

    test('one row per account: the provider names are a scalar subquery', () {
      expect(body, contains('array_agg(distinct'));
      expect(body, contains('from auth.identities i'));
      expect(body, contains('where i.user_id = u.id'));
      expect(body, isNot(contains('join auth.identities')));
      expect(body, isNot(contains('left join auth.identities')));
    });

    test('nothing sensitive is read from auth', () {
      for (final sensitive in [
        'identity_data',
        'encrypted_password',
        'raw_user_meta_data',
        'raw_app_meta_data',
        'recovery_token',
        'confirmation_token',
        'access_token',
        'refresh_token',
        'phone_confirmed_at',
        'i.id',
        'select *',
      ]) {
        expect(body, isNot(contains(sensitive)), reason: sensitive);
      }
      // The auth columns it does read.
      for (final read in [
        'au.email::text',
        'au.email_confirmed_at',
        'au.last_sign_in_at',
      ]) {
        expect(body, contains(read));
      }
    });

    test('push switches fall back to the column defaults', () {
      expect(body, contains('coalesce(np.match_push, true)'));
      expect(body, contains('coalesce(np.community_push, true)'));
      expect(body, contains('coalesce(np.mute_all, false)'));
      expect(body, contains('left join notification_push_preferences np'));
    });

    test('it returns the agreed columns in the agreed order', () {
      final table =
          RegExp(r'returns table \(([^)]*)\)').firstMatch(body)!.group(1)!;
      final columns = RegExp(r'^\s*(\w+) ', multiLine: true)
          .allMatches(table)
          .map((m) => m.group(1)!)
          .toList();
      expect(columns, [
        'id',
        'full_name',
        'phone',
        'email',
        'date_of_birth',
        'primary_position',
        'secondary_position',
        'profile_visibility',
        'age_visible',
        'default_wilayat_code',
        'avatar_path',
        'is_active',
        'suspended_at',
        'suspension_reason',
        'is_system_admin',
        'match_push',
        'community_push',
        'mute_all',
        'sign_in_providers',
        'email_confirmed_at',
        'last_sign_in_at',
        'created_at',
      ]);
    });
  });

  group('every write', () {
    for (final name in writers) {
      group(name, () {
        final body = functionBody(name);

        // Four writers collect the columns that would change and stop when there
        // are none. The Default Location is one column, so it compares it
        // directly; the effect is the same, and it is asserted the same way.
        final noopTest = name == 'admin_update_user_default_wilayat'
            ? 'p_wilayat_code is not distinct from v_user.default_wilayat_code'
            : 'cardinality(v_changed) = 0';

        test('checks run in the agreed order, each before any write', () {
          final at = positions(body, [
            "raise exception 'NOT_AUTHORIZED'",
            "raise exception 'CANNOT_MODIFY_SELF'",
            "raise exception 'CANNOT_MODIFY_SYSTEM_ADMIN'",
            "raise exception 'USER_NOT_FOUND'",
            noopTest,
            'perform record_admin_audit(',
          ]);
          for (var i = 1; i < at.length; i++) {
            expect(at[i - 1] < at[i], isTrue,
                reason: '$name: step $i comes after step ${i - 1}');
          }
        });

        test('the gate is the first statement of the body', () {
          final begin = body.indexOf('\nbegin\n');
          expect(
            body.substring(begin + 7).trimLeft(),
            startsWith('if not is_system_admin() then'),
          );
        });

        test('the guards read the right things', () {
          expect(body, contains('if p_user_id = auth.uid() then'));
          expect(
            body,
            contains('exists (select 1 from system_admins sa '
                'where sa.user_id = p_user_id)'),
          );
          // Locked, so two administrators cannot interleave.
          expect(
              body,
              contains(
                  'select * into v_user from users u where u.id = p_user_id for update'));
        });

        test('validation sits between the lock and the no-op test', () {
          final at = positions(body, [
            "raise exception 'USER_NOT_FOUND'",
            "raise exception 'INVALID_",
            noopTest,
          ]);
          expect(at[0] < at[1] && at[1] < at[2], isTrue);
        });

        test('nothing changed: it returns before any UPDATE or audit row', () {
          final noop = body.indexOf(noopTest);
          final write = [
            body.indexOf('update users set'),
            body.indexOf('insert into notification_push_preferences'),
          ].where((i) => i >= 0).reduce((a, b) => a < b ? a : b);
          final audit = body.indexOf('perform record_admin_audit(');
          expect(body.substring(noop, noop + 120), contains('return;'));
          expect(noop < write, isTrue);
          expect(write < audit, isTrue);
        });

        test('the audit metadata is changed_fields and nothing else', () {
          final audit =
              body.substring(body.indexOf('perform record_admin_audit('));
          final keys = RegExp(r"jsonb_build_object\(\s*'(\w+)'")
              .allMatches(audit)
              .map((m) => m.group(1))
              .toList();
          expect(keys, ['changed_fields']);
          // One key: no second pair after it.
          expect(
              RegExp(r"'changed_fields',\s*to_jsonb\([^)]*\)\s*\)\s*\);")
                  .hasMatch(audit),
              isTrue);
          for (final value in [
            'before',
            'after',
            'old_',
            'new_',
            'v_user.phone',
            'v_phone',
            'p_phone',
            'p_date_of_birth'
          ]) {
            expect(audit, isNot(contains(value)),
                reason: 'the audit call carries no values ($value)');
          }
        });

        test('the audit write has no exception handler', () {
          expect(body, isNot(contains('exception when')));
        });

        test('the reason is optional and defaulted', () {
          expect(body, contains('p_reason text default null'));
          expect(
              body,
              contains(
                  "v_reason text := nullif(btrim(coalesce(p_reason, '')), '')"));
        });

        test('it works the same on a suspended account', () {
          expect(body, isNot(contains('is_active')));
          expect(body, isNot(contains('ACCOUNT_SUSPENDED')));
        });
      });
    }
  });

  group('validation, by group', () {
    test('name and phone are complete_my_player_profile\'s rules', () {
      final body = functionBody('admin_update_user_account');
      expect(body, contains('char_length(v_name) < 2'));
      expect(body, contains("v_phone !~ '^\\+968[0-9]{8}\$'"));
      expect(body, contains("raise exception 'INVALID_FULL_NAME'"));
      expect(body, contains("raise exception 'INVALID_PHONE'"));
      // Both null arguments are invalid, not "leave unchanged".
      expect(body, contains("btrim(coalesce(p_full_name, ''))"));
      expect(body, contains("btrim(coalesce(p_phone, ''))"));
    });

    test('a null date of birth is valid; a non-null one is bounded', () {
      final body = functionBody('admin_update_user_player_profile');
      expect(body, contains('p_date_of_birth is not null'));
      expect(body, contains("p_date_of_birth < date '1900-01-01'"));
      expect(body, contains('p_date_of_birth > v_today'));
      expect(body, contains("(now() at time zone 'Asia/Muscat')::date"));
      // `complete_my_player_profile` refuses null; this must not.
      expect(body, isNot(contains('p_date_of_birth is null')));
      expect(body, contains("raise exception 'INVALID_DATE_OF_BIRTH'"));
    });

    test('positions: primary required, secondary optional and different', () {
      final body = functionBody('admin_update_user_player_profile');
      expect(body, contains("v_primary not in ('GK', 'DEF', 'MID', 'FWD')"));
      expect(body, contains('v_secondary is not null'));
      expect(body, contains("v_secondary not in ('GK', 'DEF', 'MID', 'FWD')"));
      expect(body, contains('v_secondary = v_primary'));
      expect(body, contains("raise exception 'INVALID_POSITION'"));
    });

    test('privacy: the two tokens, and no null', () {
      final body = functionBody('admin_update_user_privacy');
      expect(body, contains('p_profile_visibility is null'));
      expect(body, contains("not in ('EVERYONE', 'COMMUNITY_MEMBERS')"));
      expect(body, contains('p_age_visible is null'));
      expect(body, contains("raise exception 'INVALID_SETTINGS'"));
    });

    test('Wilayat: null clears, otherwise it must exist', () {
      final body = functionBody('admin_update_user_default_wilayat');
      expect(body, contains('p_wilayat_code is not null'));
      expect(
          body,
          contains(
              'not exists (select 1 from wilayats w where w.code = p_wilayat_code)'));
      expect(body, contains("raise exception 'INVALID_WILAYAT'"));
      expect(
          body,
          contains(
              'p_wilayat_code is not distinct from v_user.default_wilayat_code'));
    });

    test('push preferences: no null switch', () {
      final body = functionBody('admin_update_user_push_preferences');
      expect(
        body,
        contains('p_match_push is null or p_community_push is null '
            'or p_mute_all is null'),
      );
      expect(body, contains("raise exception 'INVALID_SETTINGS'"));
    });

    test('the error codes raised are the agreed set and nothing else', () {
      final raised = RegExp(r"raise exception '(\w+)'")
          .allMatches(statements)
          .map((m) => m.group(1)!)
          .toSet();
      expect(raised, {
        'NOT_AUTHORIZED',
        'CANNOT_MODIFY_SELF',
        'CANNOT_MODIFY_SYSTEM_ADMIN',
        'USER_NOT_FOUND',
        'INVALID_FULL_NAME',
        'INVALID_PHONE',
        'INVALID_DATE_OF_BIRTH',
        'INVALID_POSITION',
        'INVALID_WILAYAT',
        'INVALID_SETTINGS',
      });
    });
  });

  group('push preferences with no row', () {
    final body = functionBody('admin_update_user_push_preferences');

    test('the effective values are the row, or the column defaults', () {
      expect(body, contains('v_has_row := found;'));
      expect(
          body,
          contains(
              'case when v_has_row then v_prefs.match_push else true end'));
      expect(
          body,
          contains(
              'case when v_has_row then v_prefs.community_push else true end'));
      expect(body,
          contains('case when v_has_row then v_prefs.mute_all else false end'));
    });

    test('only the fields that differ from them are listed', () {
      expect(body, contains('p_match_push is distinct from v_current_match'));
      expect(body,
          contains('p_community_push is distinct from v_current_community'));
      expect(body, contains('p_mute_all is distinct from v_current_mute'));
    });

    test('the defaults really are the column defaults of 0036', () {
      final table = load('../supabase/migrations/0036_push_notifications.sql');
      expect(table, contains('match_push boolean not null default true'));
      expect(table, contains('community_push boolean not null default true'));
      expect(table, contains('mute_all boolean not null default false'));
    });

    test('a change is an upsert, which is also how a row comes to exist', () {
      expect(body, contains('insert into notification_push_preferences'));
      expect(body, contains('on conflict (user_id) do update set'));
    });
  });

  group('privileges', () {
    for (final entry in signatures.entries) {
      test('${entry.key} is revoked from anon and public, granted as 0066 does',
          () {
        final args = entry.value;
        final fn = 'public.${entry.key}\\($args\\)';
        expect(
          RegExp('revoke execute on function $fn\\s+from anon, public;')
              .hasMatch(statements),
          isTrue,
          reason: 'revoke',
        );
        expect(
          RegExp('grant execute on function $fn\\s+to authenticated;')
              .hasMatch(statements),
          isTrue,
          reason: 'authenticated',
        );
        expect(
          RegExp('grant execute on function $fn\\s+to service_role;')
              .hasMatch(statements),
          isTrue,
          reason: 'service_role',
        );
      });

      test('${entry.key} is security definer with search_path = public', () {
        final body = functionBody(entry.key);
        expect(body, contains('security definer'));
        expect(body, contains('set search_path = public'));
      });

      test('${entry.key} has a comment', () {
        expect(
          statements,
          contains(
              'comment on function public.${entry.key}(${entry.value}) is'),
        );
      });
    }

    test('no privilege is granted to anon, to public, or to a table', () {
      expect(executable, isNot(contains('to anon')));
      expect(executable, isNot(contains('to public')));
      expect(
        RegExp(r'grant\s+(?!execute)').hasMatch(executable),
        isFalse,
      );
    });
  });

  group('no service role, no write to auth or storage', () {
    test('the migration never mentions a key or a privileged client', () {
      expect(executable, isNot(contains('service_role_key')));
      expect(executable, isNot(contains('SUPABASE_SERVICE')));
      expect(executable, isNot(contains('set role')));
      expect(executable, isNot(contains('set local role')));
    });

    test('auth is read, never written; storage is not touched', () {
      expect(executable, isNot(RegExp(r'insert\s+into\s+auth\.')));
      expect(executable, isNot(RegExp(r'update\s+auth\.')));
      expect(executable, isNot(RegExp(r'delete\s+from\s+auth\.')));
      expect(executable, isNot(RegExp(r'alter\s+table\s+auth\.')));
      expect(executable, isNot(contains('storage.')));
      // The only two auth relations that appear are the two it reads.
      final relations = RegExp(r'auth\.(\w+)')
          .allMatches(executable)
          .map((m) => m.group(1))
          .toSet();
      expect(relations, {'users', 'identities', 'uid'});
    });

    test('it is not a dynamic SQL author', () {
      expect(executable, isNot(contains('execute format')));
      expect(executable, isNot(RegExp(r'\bexecute\s+[a-z_]+\s*;')));
    });
  });

  group('the rollback', () {
    final rollback = load(rollbackPath);
    final rollbackCode = code(rollback);

    test('it stops, before anything else, if any USER_PROFILE_UPDATED exists',
        () {
      final guard = rollbackCode.indexOf("action = 'USER_PROFILE_UPDATED'");
      final raise = rollbackCode.indexOf("raise exception");
      final firstDrop = rollbackCode.indexOf('drop function');
      final constraint = rollbackCode.indexOf('drop constraint');
      expect(guard, greaterThan(-1));
      expect(raise, greaterThan(guard));
      expect(raise, lessThan(firstDrop));
      expect(raise, lessThan(constraint));
      expect(rollbackCode, contains('ROLLBACK_REFUSED'));
      expect(rollbackCode, contains('Nothing was changed'));
    });

    test('it never deletes, truncates or updates anything', () {
      expect(rollbackCode, isNot(contains('delete from')));
      expect(rollbackCode, isNot(contains('truncate')));
      expect(rollbackCode, isNot(RegExp(r'\bupdate\s+public\.')));
      expect(rollbackCode, isNot(contains('drop table')));
      expect(rollbackCode, isNot(contains('drop column')));
    });

    test('it drops exactly the six functions, by signature', () {
      final dropped =
          RegExp(r'drop function if exists public\.(\w+)\(([^)]*)\)')
              .allMatches(rollbackCode)
              .map((m) => '${m.group(1)}(${m.group(2)})')
              .toList();
      expect(dropped, [
        for (final entry in signatures.entries) '${entry.key}(${entry.value})',
      ]);
    });

    test('it restores the four-value CHECK of 0062', () {
      final add = RegExp(
        r"add constraint admin_audit_log_action_check check \(action in \(([^)]*)\)\)",
      ).firstMatch(rollbackCode);
      expect(add, isNotNull);
      final values = RegExp(r"'(\w+)'")
          .allMatches(add!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
      expect(values, [
        'USER_SUSPENDED',
        'USER_REACTIVATED',
        'COMMUNITY_SUSPENDED',
        'COMMUNITY_REACTIVATED',
      ]);
    });
  });
}
