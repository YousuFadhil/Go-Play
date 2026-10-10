import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0102, its rollback and verification, and the `delete-account` Edge Function say --
/// a static review of the files, not a runtime result.
///
/// The migration has not been applied to the shared database. The offline runs (the real migration
/// chain plus 0101 and 0102 in PGlite, on synthetic accounts) and `supabase/tool/0102_..._verify.sql`
/// are what prove the database does what the files say. What THIS catches is the class of mistake
/// that is invisible in review and expensive in production: a gate that moved below a write, football
/// history deleted by a stray statement, an Auth deletion that slipped out of the transaction, a
/// helper granted to a client role, the applied 0101 quietly edited, a merge executor that differs
/// from 0101's by more than the three intended edits.
void main() {
  const path = '../supabase/migrations/0102_account_deletion_engine.sql';
  const path0101 =
      '../supabase/migrations/0101_platform_admin_account_merge.sql';
  const path0099 =
      '../supabase/migrations/0099_admin_deletion_audit_privacy_preflight.sql';
  const rollbackPath =
      '../supabase/rollback/0102_account_deletion_engine_rollback.sql';
  const verifyPath = '../supabase/tool/0102_account_deletion_engine_verify.sql';

  // Git checks these files out with CRLF endings on Windows.
  String load(String file) =>
      File(file).readAsStringSync().replaceAll('\r\n', '\n');

  /// The line without a trailing `-- comment` (a `--` inside a string literal is not one).
  String withoutTrailingComment(String line) {
    var inString = false;
    for (var i = 0; i < line.length - 1; i++) {
      if (line[i] == "'") inString = !inString;
      if (!inString && line[i] == '-' && line[i + 1] == '-') {
        return line.substring(0, i).trimRight();
      }
    }
    return line;
  }

  String code(String text) => text
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .map(withoutTrailingComment)
      .join('\n');

  /// With SQL string literals blanked: `comment on` bodies and message texts name things the
  /// functions do not do.
  String blank(String text) => text.replaceAll(RegExp("'[^']*'"), "''");

  /// Where [token] is in [text]. A bare `indexOf` answers -1 for a token that is missing, and -1
  /// is less than everything: an order check built on it passes when the thing it orders has gone.
  int at(String text, Pattern token, [int start = 0]) {
    final i = text.indexOf(token, start);
    if (i < 0) fail('missing: $token');
    return i;
  }

  int fnv1a32(String text) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(text)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// `create or replace function public.NAME(` up to its closing `$$;`, comments removed.
  String functionOf(String sql, String name) {
    final text = code(sql);
    final start = text.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('no function $name');
    final end = text.indexOf('\n\$\$;', start);
    return text.substring(start, end < 0 ? text.length : end + 4);
  }

  /// The same, comments kept: for the comparison of two versions of one function.
  String rawFunctionOf(String sql, String name) {
    final start = sql.lastIndexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('no function $name');
    return sql.substring(start, sql.indexOf('\n\$\$;', start) + 4);
  }

  final sql = load(path);
  final statements = code(sql);
  final executable = blank(statements);
  final rollback = load(rollbackPath);
  final verify = load(verifyPath);
  final sql0101 = load(path0101);
  final sql0099 = load(path0099);

  final core = functionOf(sql, 'delete_account_core');
  final coreBlank = blank(core);
  final adminDelete = functionOf(sql, 'admin_delete_account');
  final myDelete = functionOf(sql, 'delete_my_account');
  final adminPreview = functionOf(sql, 'admin_preview_account_deletion');
  final myPreview = functionOf(sql, 'preview_my_account_deletion');

  const api = [
    'admin_delete_account(uuid)',
    'delete_my_account()',
    'admin_preview_account_deletion(uuid)',
    'preview_my_account_deletion()',
  ];
  const internal = [
    'delete_account_core(uuid)',
    'account_deletion_blockers(uuid)',
    'account_football_evidence(uuid)',
    'anonymize_user_profile(uuid)',
    'handle_auth_user_deleted()',
    'deleted_player_name()',
  ];

  // ---------------------------------------------------------------------------
  group('the applied migrations are not rewritten', () {
    test('0101, which is live, is byte for byte the applied file', () {
      final text = load(path0101);
      expect(text.length, 79921);
      expect(fnv1a32(text), 3268317902);
    });

    test('0102 is the only migration with its number', () {
      final names = Directory('../supabase/migrations')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('0102_'))
          .toList();
      expect(names, ['0102_account_deletion_engine.sql']);
    });
  });

  // ---------------------------------------------------------------------------
  group('who may delete, decided on the server', () {
    test('the admin route checks System Admin twice, before it reads or writes',
        () {
      expect(adminDelete, contains('security definer'));
      expect(adminDelete, contains('set search_path = public, pg_temp'));
      final gate = at(adminDelete, "raise exception 'NOT_AUTHORIZED'");
      expect(at(adminDelete, 'public.is_system_admin()'), lessThan(gate));
      expect(at(adminDelete, 'from public.system_admins sa'), lessThan(gate));
      expect(at(adminDelete, 'v_caller is null'), lessThan(gate));
      expect(at(adminDelete, 'public.delete_account_core('), greaterThan(gate));
      expect(at(adminDelete, "raise exception 'CANNOT_DELETE_SELF'"),
          lessThan(at(adminDelete, 'public.delete_account_core(')));
    });

    test('the admin preview has the same gate, before anything is read', () {
      final gate = at(adminPreview, "raise exception 'NOT_AUTHORIZED'");
      expect(at(adminPreview, 'public.is_system_admin()'), lessThan(gate));
      expect(at(adminPreview, 'from public.system_admins sa'), lessThan(gate));
      expect(at(adminPreview, 'admin_preview_account_snapshot('),
          greaterThan(gate));
      expect(adminPreview, contains('stable'));
    });

    test('the self route has no argument: the account is auth.uid()', () {
      expect(statements,
          contains('create or replace function public.delete_my_account()'));
      expect(
          statements,
          contains(
              'create or replace function public.preview_my_account_deletion()'));
      for (final body in [myDelete, myPreview]) {
        expect(body, contains('auth.uid()'));
        expect(body, isNot(contains('p_user_id')));
      }
      expect(myDelete, contains("raise exception 'NOT_AUTHENTICATED'"));
      expect(myDelete, contains("raise exception 'ACCOUNT_SUSPENDED'"));
      expect(at(myDelete, 'public.delete_account_core(v_caller)'),
          greaterThan(at(myDelete, "raise exception 'ACCOUNT_SUSPENDED'")));
      expect(myPreview, contains('stable'));
    });

    test('the engine is callable by no client role, whoever asks', () {
      expect(
        statements,
        contains('revoke execute on function public.delete_account_core(uuid)\n'
            '  from anon, authenticated, public;'),
      );
      expect(
          executable, isNot(matches(RegExp(r'grant[^;]*delete_account_core'))));
      expect(core, contains('security definer'));
      expect(core, contains('set search_path = public, pg_temp'));
    });

    test('the four API functions are for signed-in users only', () {
      for (final fn in api) {
        expect(
          statements,
          contains(
              'revoke execute on function public.$fn\n  from anon, public;'),
          reason: fn,
        );
        expect(
          statements,
          contains('grant execute on function public.$fn\n  to authenticated;'),
          reason: fn,
        );
      }
      for (final grant in RegExp(r'grant\b[^;]*;').allMatches(executable)) {
        final text = grant.group(0)!;
        final grantees = text.substring(text.lastIndexOf(RegExp(r'\bto\b')));
        expect(grantees, isNot(matches(RegExp(r'\b(anon|public)\b'))),
            reason: text);
      }
    });

    test('the internal helpers are granted to nobody', () {
      for (final fn in internal) {
        expect(
          statements,
          contains('revoke execute on function public.$fn\n'
              '  from anon, authenticated, public;'),
          reason: fn,
        );
        final name = fn.substring(0, fn.indexOf('('));
        expect(
            executable, isNot(matches(RegExp('grant[^;]*public\\.$name\\b'))),
            reason: '$fn must not be granted to anyone');
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('one transaction, Auth included, and the history is not touched', () {
    test('the Auth user is deleted once, last, by the engine', () {
      expect('delete from auth.users'.allMatches(core).length, 1);
      final authDelete =
          at(core, 'delete from auth.users where id = p_user_id;');
      expect(
          at(core,
              'delete from auth.refresh_tokens where user_id = p_user_id::text;'),
          lessThan(authDelete));
      expect(at(core, 'delete from auth.flow_state where user_id = p_user_id;'),
          lessThan(authDelete));
      // After it: the check that nothing of the account is left in Auth, and the answer.
      final rawTail = core.substring(at(core, 'delete from auth.users'));
      expect(rawTail, contains("raise exception 'AUTH_DELETE_INCOMPLETE'"));
      final tail = coreBlank.substring(at(coreBlank, 'delete from auth.users'));
      expect(
        RegExp(r'\b(insert\s+into|update\s+\w|delete\s+from)\b')
            .allMatches(tail.substring('delete from auth.users'.length)),
        isEmpty,
        reason: 'nothing is written after the Auth delete',
      );
    });

    test('the order of work', () {
      final order = [
        'pg_advisory_xact_lock(hashtextextended(\'goplay.account_lifecycle\', 0))',
        'for update;',
        "raise exception 'DELETE_BLOCKED'",
        "raise exception 'SOURCE_FILES_REMAIN'",
        'v_evidence_before := public.account_football_evidence(p_user_id)',
        'delete from public.match_team_assignments t',
        'delete from public.match_registrations r',
        'perform public.rebalance_roster(',
        'delete from public.community_members where user_id = p_user_id;',
        'delete from public.notifications where user_id = p_user_id;',
        'update public.admin_audit_log a',
        'perform public.anonymize_user_profile(p_user_id)',
        "raise exception 'DELETE_EVIDENCE_CHANGED'",
        "raise exception 'DELETE_INVARIANT_BROKEN'",
        "raise exception 'DELETE_RESIDUAL_DATA'",
        'delete from auth.users where id = p_user_id;',
      ];
      var last = -1;
      for (final token in order) {
        final i = at(core, token);
        expect(i, greaterThan(last), reason: '$token is out of order');
        last = i;
      }
    });

    test(
        'the engine deletes only personal data and withdrawals -- never football',
        () {
      final allowed = {
        'public.match_team_assignments',
        'public.match_registrations',
        'public.community_members',
        'public.notification_push_tokens',
        'public.notification_push_preferences',
        'public.notifications',
        'public.product_activity_last_seen',
        'auth.refresh_tokens',
        'auth.flow_state',
        'auth.users',
      };
      final deleted = RegExp(r'delete\s+from\s+([\w.]+)')
          .allMatches(coreBlank)
          .map((m) => m.group(1)!)
          .toSet();
      expect(deleted, allowed);
      // The two football tables it does delete from, only for matches not yet played.
      for (final table in [
        'match_team_assignments t',
        'match_registrations r'
      ]) {
        final start = at(core, 'delete from public.$table');
        final statement = core.substring(start, at(core, ';', start));
        expect(statement, contains("m.status <> 'completed'"), reason: table);
        expect(statement, contains('m.end_at > now()'), reason: table);
      }
      // Everywhere the engine looks at matches (what it collects to rebalance, what it deletes,
      // what it proves untouched afterwards) it uses the same not-yet-played rule.
      final guards =
          RegExp(r"m\.status <> 'completed'\s+and m\.end_at > now\(\)");
      expect(guards.allMatches(core).length, 6);
      expect('m.status'.allMatches(core).length, 6);
    });

    test('the only update the engine makes to a table is the audit redaction',
        () {
      final updates = RegExp(r'\bupdate\s+([\w.]+)')
          .allMatches(coreBlank)
          .map((m) => m.group(1)!)
          .toList();
      expect(updates, ['public.admin_audit_log']);
    });

    test('the audit redaction empties the two snapshot columns, only to NULL',
        () {
      final start = at(core, 'update public.admin_audit_log a');
      final update = blank(core.substring(start, at(core, ';', start)));
      final set = update.substring(0, update.indexOf(' where '));
      final folded = set
          .replaceAll(RegExp(r'case.*?end', dotAll: true), 'X')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      expect(
          folded,
          'update public.admin_audit_log a set actor_email_snapshot = X, '
          'target_label_snapshot = X');
      expect(set, contains('then null else a.actor_email_snapshot end'));
      expect(set, contains('then null else a.target_label_snapshot end'));
      expect(update.substring(update.indexOf(' where ')),
          contains('a.target_id = p_user_id'));
    });

    test(
        'the engine proves, before the Auth delete, that football did not move',
        () {
      expect(core, contains('public.merge_invariants(p_user_id, p_user_id)'));
      expect(core, contains('public.account_football_evidence(p_user_id)'));
      expect(core, contains('a.actor_email_snapshot is not null'));
      expect(core, contains('a.target_label_snapshot is not null'));
      expect(
          core, contains('public.merge_source_stored_files(p_user_id)) > 0'));
    });

    test('the stand-in carries no identifying column', () {
      final body = functionOf(sql, 'anonymize_user_profile');
      for (final column in [
        'full_name = public.deleted_player_name()',
        "phone = ''",
        'date_of_birth = null',
        'avatar_path = null',
        'default_wilayat_code = null',
        'is_active = false',
        'suspended_at = null',
        'suspension_reason = null',
        'deleted_at = now()',
      ]) {
        expect(body, contains(column), reason: column);
      }
      expect(body, contains('and u.deleted_at is null'),
          reason: 'only ever a live profile');
      expect(
          blank(functionOf(sql, 'deleted_player_name')), contains("''::text"));
      expect(sql, contains('لاعب محذوف / Deleted Player'));
    });

    test('the audit action list gains exactly one value', () {
      final start =
          at(statements, 'add constraint admin_audit_log_action_check');
      final actions = RegExp(r"'([A-Z_]+)'")
          .allMatches(statements.substring(start, at(statements, ');', start)))
          .map((m) => m.group(1)!)
          .toSet();
      final rollbackStart =
          at(rollback, 'add constraint admin_audit_log_action_check');
      final before = RegExp(r"'([A-Z_]+)'")
          .allMatches(rollback.substring(
              rollbackStart, at(rollback, ');', rollbackStart)))
          .map((m) => m.group(1)!)
          .toSet();
      expect(actions.difference(before), {'USER_ACCOUNT_DELETED'});
      expect(before.difference(actions), isEmpty);
    });

    test('the administrator route writes one event and no label or reason', () {
      expect('record_admin_audit('.allMatches(adminDelete).length, 1);
      final start = at(adminDelete, 'record_admin_audit(');
      final call = adminDelete.substring(start, at(adminDelete, ');', start));
      expect(call,
          contains("'USER_ACCOUNT_DELETED', 'USER', p_user_id, null, null"));
      expect(myDelete, isNot(contains('record_admin_audit')),
          reason: 'a user deleting themselves is not an administrative act');
    });
  });

  // ---------------------------------------------------------------------------
  group('nothing is switched off, and nothing is weakened', () {
    test('no trigger is disabled, no setting changed, no policy touched', () {
      for (final word in [
        'session_replication_role',
        'disable trigger',
        'disable row level security',
        'row_security',
        'create policy',
        'alter policy',
        'drop policy',
        'truncate',
        'set local role',
        'security invoker',
      ]) {
        expect(executable, isNot(contains(word)), reason: word);
      }
      expect(executable, isNot(matches(RegExp(r'\bset\s+role\s+(?!=)\w'))));
    });

    test(
        'set_config is the merge executor\'s own bracket, never the deletion code\'s',
        () {
      final merge = blank(code(rawFunctionOf(sql, 'admin_merge_accounts')));
      expect('set_config'.allMatches(executable).length,
          'set_config'.allMatches(merge).length);
      for (final body in [
        core,
        adminDelete,
        myDelete,
        adminPreview,
        myPreview
      ]) {
        expect(body, isNot(contains('set_config')));
      }
    });

    test('the one structural change: users_id_fkey goes, deleted_at comes', () {
      final alters = RegExp(r'alter table public\.users\s+([^;]*);')
          .allMatches(executable)
          .map((m) => m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim())
          .toList();
      expect(alters, [
        'add column if not exists deleted_at timestamptz',
        'drop constraint if exists users_id_fkey',
      ]);
      expect('drop constraint'.allMatches(executable).length, 2,
          reason: 'users_id_fkey, and the audit action check dropped to be '
              're-added with one more action');
    });

    test('the trigger on auth.users anonymises and does nothing else', () {
      final body = functionOf(sql, 'handle_auth_user_deleted');
      expect(body, contains('perform public.anonymize_user_profile(old.id)'));
      expect(
          blank(body), isNot(matches(RegExp(r'\b(insert|delete|update)\b'))));
      expect(
        executable.replaceAll(RegExp(r'\s+'), ' '),
        contains('create trigger auth_user_deleted_anonymize_profile '
            'after delete on auth.users for each row '
            'execute function public.handle_auth_user_deleted();'),
      );
    });

    test('the rating archives are never written', () {
      for (final table in ['rating_history_archive', 'user_rating_archive']) {
        expect(
          executable,
          isNot(matches(RegExp(
              '(insert\\s+into|update|delete\\s+from)\\s+public\\.$table\\b'))),
          reason: table,
        );
      }
    });

    test('no audit entry is ever deleted', () {
      expect(executable,
          isNot(matches(RegExp(r'delete\s+from\s+public\.admin_audit_log\b'))));
    });
  });

  // ---------------------------------------------------------------------------
  group('the merge executor is 0101\'s, plus exactly the three edits', () {
    final now = rawFunctionOf(sql, 'admin_merge_accounts');
    final was = rawFunctionOf(sql0101, 'admin_merge_accounts');

    List<String> lines(String text, {required bool codeOnly}) => text
        .split('\n')
        .where((l) => !codeOnly || !l.trimLeft().startsWith('--'))
        .toList();

    /// Lines of [a] that [b] does not have, counting repeats.
    List<String> minus(List<String> a, List<String> b) {
      final left = [...b];
      final out = <String>[];
      for (final line in a) {
        if (!left.remove(line)) out.add(line);
      }
      return out;
    }

    test('the code differs by the lock, the live-profile check and the delete',
        () {
      final nowCode = lines(now, codeOnly: true);
      final wasCode = lines(was, codeOnly: true);

      expect(minus(wasCode, nowCode), [
        "  perform pg_advisory_xact_lock(hashtextextended('goplay.admin_merge_accounts', 0));",
        '       where u.id in (p_retained_user_id, p_source_user_id)) <> 2 then',
      ]);
      expect(minus(nowCode, wasCode), [
        "  perform pg_advisory_xact_lock(hashtextextended('goplay.account_lifecycle', 0));",
        '       where u.id in (p_retained_user_id, p_source_user_id)',
        '         and u.deleted_at is null) <> 2 then',
        '  delete from public.users where id = p_source_user_id;',
      ]);
    });

    test('the profile is deleted before the Auth user, and only once', () {
      expect(
          'delete from public.users where id = p_source_user_id;'
              .allMatches(now)
              .length,
          1);
      expect(
          at(now, 'delete from public.users where id = p_source_user_id;'),
          lessThan(
              at(now, 'delete from auth.users where id = p_source_user_id;')));
    });

    test('everything else about it is as 0101 left it', () {
      // Same signature line, same security, same grants (create or replace keeps the ACL).
      String head(String f) => f.substring(0, f.indexOf('as \$\$'));
      expect(head(now), head(was));
    });
  });

  // ---------------------------------------------------------------------------
  group('the rollback', () {
    test('it refuses, before changing anything, once an account is deleted',
        () {
      final first = at(rollback,
          "raise exception 'ROLLBACK_REFUSED_DELETED_ACCOUNTS_EXIST'");
      expect(
          "raise exception 'ROLLBACK_REFUSED_DELETED_ACCOUNTS_EXIST'"
              .allMatches(rollback)
              .length,
          2);
      final firstChange =
          at(code(rollback), RegExp(r'\b(drop|alter|create)\b'));
      expect(
          at(code(rollback),
              "raise exception 'ROLLBACK_REFUSED_DELETED_ACCOUNTS_EXIST'"),
          lessThan(firstChange));
      expect(first, greaterThan(0));
      expect(rollback, contains("action = 'USER_ACCOUNT_DELETED'"));
    });

    test(
        'it puts 0101\'s merge executor and 0099\'s deletion preview back verbatim',
        () {
      expect(functionOf(rollback, 'admin_merge_accounts'),
          functionOf(sql0101, 'admin_merge_accounts'));
      expect(functionOf(rollback, 'admin_preview_account_deletion'),
          functionOf(sql0099, 'admin_preview_account_deletion'));
    });

    test('it drops everything 0102 created, and puts users_id_fkey back', () {
      for (final fn in [
        'delete_my_account()',
        'admin_delete_account(uuid)',
        'preview_my_account_deletion()',
        'delete_account_core(uuid)',
        'anonymize_user_profile(uuid)',
        'account_football_evidence(uuid)',
        'account_deletion_blockers(uuid)',
        'deleted_player_name()',
        'handle_auth_user_deleted()',
      ]) {
        expect(rollback, contains('drop function if exists public.$fn;'),
            reason: fn);
      }
      expect(
          rollback,
          contains(
              'drop trigger if exists auth_user_deleted_anonymize_profile on auth.users;'));
      expect(
          rollback,
          contains(
              'add constraint users_id_fkey foreign key (id) references auth.users(id) on delete cascade;'));
      expect(rollback, contains('drop column if exists deleted_at;'));
      expect(code(rollback), isNot(contains('disable trigger')));
    });
  });

  // ---------------------------------------------------------------------------
  group('the verification script', () {
    final text = blank(code(verify));

    test('it is one read-only statement', () {
      expect(';'.allMatches(text).length, 1);
      expect(text.trimRight(), endsWith(';'));
      expect(
        text,
        isNot(matches(RegExp(
            r'\b(insert|update|delete|create|drop|alter|grant|revoke|truncate|set_config|perform)\b'))),
      );
    });

    test('it pins the eleven bodies it must not drift from, and the 0101 ones',
        () {
      expect("src_md5 = '".allMatches(verify).length,
          greaterThanOrEqualTo(11 * 2 + 7 * 2));
      expect(verify, contains('54bd260bb7d073208667a2fc7c656876'));
      expect(verify, contains('5ad5a3749c12802f8312cc92bd359df9'));
    });

    test('it checks the structural change and the data it depended on', () {
      expect(verify, contains('users_id_fkey'));
      expect(verify, contains('every live profile has an Auth user'));
      expect(verify, contains('every deleted account has no Auth user'));
      expect(verify, contains('auth_user_deleted_anonymize_profile'));
    });

    test('it says which older checks go red, by design', () {
      expect(verify, contains('0101'));
      expect(verify, contains('check 13'));
      expect(verify, contains('check 22'));
    });
  });

  // ---------------------------------------------------------------------------
  group('the delete-account Edge Function', () {
    final function = load('../supabase/functions/delete-account/index.ts');
    final adminAdapter =
        load('../app/lib/infrastructure/supabase/supabase_admin_adapter.dart');
    final selfAdapter = load(
        '../app/lib/infrastructure/supabase/supabase_account_deletion_adapter.dart');

    test('both adapters invoke it by the name it is deployed under', () {
      expect(adminAdapter, contains("'delete-account'"));
      expect(selfAdapter, contains("'delete-account'"));
      expect(Directory('../supabase/functions/delete-account').existsSync(),
          isTrue);
    });

    test('it calls the functions this migration defines, with their parameters',
        () {
      for (final name in [
        'admin_preview_account_deletion',
        'preview_my_account_deletion',
        'admin_delete_account',
        'delete_my_account',
      ]) {
        expect(function, contains('"$name"'), reason: name);
        expect(statements, contains('function public.$name('), reason: name);
      }
      expect(function, contains('{ p_user_id: target }'));
      expect(function, contains('p_user_id'));
    });

    test(
        'previews and deletions run as the caller; the service role does the '
        'Storage work only', () {
      for (final call in [
        'asCaller("admin_preview_account_deletion"',
        'asCaller("preview_my_account_deletion"',
        'asCaller("admin_delete_account"',
        'asCaller("delete_my_account"',
      ]) {
        expect(function, contains(call), reason: call);
      }
      expect('env.serviceKey'.allMatches(function).length, 4,
          reason: 'the stored-files list (apikey and bearer), the Storage '
              'delete (apikey and bearer), and nothing else');
      final listStart = at(function, '"merge_source_stored_files"');
      expect(function.substring(listStart, listStart + 120),
          contains('env.serviceKey'));
    });

    test('the tokens it passes through are raised by the database', () {
      for (final token in [
        'NOT_AUTHORIZED',
        'USER_NOT_FOUND',
        'DELETE_BLOCKED',
        'CANNOT_DELETE_SELF',
        'ACCOUNT_SUSPENDED',
        'SOURCE_FILES_REMAIN',
        'NOT_AUTHENTICATED',
      ]) {
        expect(function, contains(token), reason: token);
        expect(statements, contains("raise exception '$token'"), reason: token);
      }
    });

    test('in self mode the picture is removed for the id the database returned',
        () {
      expect(function, contains('const own = doc["user_id"];'));
      expect(myPreview, contains("'user_id', v_uid"));
    });
  });
}
