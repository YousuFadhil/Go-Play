import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0101 and its rollback and verification say -- a static review of
/// the files, not a runtime result.
///
/// The migration has not been applied to the shared database. The offline run (the
/// real migration chain in PGlite, with an independent oracle for the rating
/// replay) and `supabase/tool/0101_..._verify.sql` are what prove the database does
/// what the files say. What THIS catches is the class of mistake that is invisible
/// in review and expensive in production: a trigger switched off, a gate that
/// moved below a read, an Auth deletion that slipped out of the transaction, a
/// helper granted to a client role, an applied migration quietly edited, a
/// "guard" that changed an existing function by more than the guard.
void main() {
  const path = '../supabase/migrations/0101_platform_admin_account_merge.sql';
  const rollbackPath =
      '../supabase/rollback/0101_platform_admin_account_merge_rollback.sql';
  const verifyPath =
      '../supabase/tool/0101_platform_admin_account_merge_verify.sql';
  const path0096 =
      '../supabase/migrations/0096_platform_admin_account_preflight.sql';

  // Git checks these files out with CRLF endings on Windows.
  String load(String file) =>
      File(file).readAsStringSync().replaceAll('\r\n', '\n');

  /// The line without a trailing `-- comment` (a `--` inside a string literal is
  /// not one).
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

  /// With SQL string literals blanked: `comment on` bodies and message texts name
  /// things the functions do not do.
  String blank(String text) => text.replaceAll(RegExp("'[^']*'"), "''");

  /// Where [token] is in [text]. A bare `indexOf` answers -1 for a token that is
  /// missing, and -1 is less than everything: an order check built on it passes
  /// when the thing it orders has gone.
  int at(String text, Pattern token, [int start = 0]) {
    final i = text.indexOf(token, start);
    if (i < 0) fail('missing: $token');
    return i;
  }

  int lastAt(String text, Pattern token, [int? start]) {
    final i = text.lastIndexOf(token, start);
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

  /// `create or replace function public.NAME(` up to its closing `$$;`, comments
  /// removed.
  String functionOf(String sql, String name) {
    final text = code(sql);
    final start = at(text, 'create or replace function public.$name(');
    if (start < 0) throw StateError('no function $name');
    final end = at(text, '\n\$\$;', start);
    return text.substring(start, end < 0 ? text.length : end + 4);
  }

  final sql = load(path);
  final statements = code(sql);
  final executable = blank(statements);
  final rollback = load(rollbackPath);
  final verify = load(verifyPath);
  final sql0096 = load(path0096);

  const merge = 'admin_merge_accounts';
  const preview = 'admin_preview_account_merge';
  const helpers = [
    'merge_skips_lifecycle',
    'merge_rating_scope_excludes',
    'merge_shared_matches',
    'merge_participation_blockers',
    'merge_invariants',
    'merge_source_stored_files',
  ];
  const helperArgs = {
    'merge_skips_lifecycle': 'uuid',
    'merge_rating_scope_excludes': 'uuid',
    'merge_shared_matches': 'uuid, uuid',
    'merge_participation_blockers': 'uuid, uuid',
    'merge_invariants': 'uuid, uuid',
    'merge_source_stored_files': 'uuid',
  };
  const guarded = [
    'capture_match_registration_event',
    'capture_community_membership_event',
    'advance_match_participation_revision',
    'apply_rating_delta',
  ];

  final mergeBody = functionOf(sql, merge);
  final mergeBlank = blank(mergeBody);

  // ---------------------------------------------------------------------------
  group('the applied migrations are not rewritten', () {
    // These are the files as they were applied; the pin is the text, not a
    // promise. A change to any of them is a change to history.
    for (final pin in <(String, int, int)>[
      ('0095_platform_admin_user_account_management', 28992, 1995987755),
      ('0096_platform_admin_account_preflight', 44849, 3931011787),
      ('0099_admin_deletion_audit_privacy_preflight', 18217, 2680329963),
    ]) {
      test('${pin.$1} is byte for byte the applied file', () {
        final text = load('../supabase/migrations/${pin.$1}.sql');
        expect(text.length, pin.$2);
        expect(fnv1a32(text), pin.$3);
      });
    }

    test('0101 is the only migration with its number', () {
      final names = Directory('../supabase/migrations')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('0101_'))
          .toList();
      expect(names, ['0101_platform_admin_account_merge.sql']);
    });

    test('and it names the migrations it builds on', () {
      expect(sql, contains('0096'));
      expect(sql, contains('0099'));
      expect(sql, contains('0100'));
    });
  });

  // ---------------------------------------------------------------------------
  group('who may merge', () {
    test('the executor is a definer with a pinned search_path', () {
      expect(mergeBody, contains('security definer'));
      expect(mergeBody, contains('set search_path = public, pg_temp'));
      expect(mergeBody, contains('returns jsonb'));
    });

    test('the System Admin gate is checked twice, before any read or lock', () {
      final gate = at(mergeBody, "raise exception 'NOT_AUTHORIZED'");
      expect(gate, greaterThan(0));
      expect(at(mergeBody, 'public.is_system_admin()'), lessThan(gate));
      expect(at(mergeBody, 'from public.system_admins sa'), lessThan(gate));
      expect(at(mergeBody, 'v_caller is null'), lessThan(gate));
      // Nothing is read, and no lock is taken, before the gate has answered.
      expect(at(mergeBody, 'from public.users'), greaterThan(gate));
      expect(at(mergeBody, 'pg_advisory_xact_lock'), greaterThan(gate));
      expect(at(mergeBody, 'for update'), greaterThan(gate));
    });

    test('the same account, and the administrator, are refused before locking',
        () {
      final lock = at(mergeBody, 'pg_advisory_xact_lock');
      for (final token in [
        "raise exception 'SAME_ACCOUNT'",
        "raise exception 'CANNOT_MERGE_SELF'",
        "raise exception 'RESOLUTIONS_INVALID'",
      ]) {
        expect(mergeBody, contains(token));
        expect(at(mergeBody, token), lessThan(lock), reason: token);
      }
    });

    test('the executor is for signed-in users and service_role only', () {
      expect(
        statements,
        contains('revoke execute on function public.$merge(uuid, uuid, jsonb)\n'
            '  from anon, public;'),
      );
      expect(
        statements,
        contains('grant execute on function public.$merge(uuid, uuid, jsonb)\n'
            '  to authenticated;'),
      );
      // Only the roles after `to` are the grantees; `public.` in a function name
      // is a schema.
      for (final grant in RegExp(r'grant\b[^;]*;').allMatches(executable)) {
        final text = grant.group(0)!;
        final grantees = text.substring(lastAt(text, RegExp(r'\bto\b')));
        expect(grantees, isNot(matches(RegExp(r'\b(anon|public)\b'))),
            reason: text);
      }
    });

    test('the internal helpers are not callable by any client role', () {
      for (final helper in helpers) {
        expect(
          statements,
          contains('revoke execute on function public.$helper'
              '(${helperArgs[helper]})\n  from anon, authenticated, public;'),
          reason: helper,
        );
        // The one helper with a grant is the stored-files list, and only to the
        // service role the Edge Function runs as.
        final grants = RegExp('grant[^;]*public\\.$helper[^;]*;')
            .allMatches(executable)
            .map((m) => m.group(0)!)
            .toList();
        if (helper == 'merge_source_stored_files') {
          expect(grants, hasLength(1));
          expect(grants.single, endsWith(' to service_role;'));
        } else {
          expect(grants, isEmpty,
              reason: '$helper must not be granted to anyone');
        }
      }
    });

    test('the mapping table is closed to every client role', () {
      expect(
          statements,
          contains(
              'alter table public.account_merge_map enable row level security;'));
      expect(
        statements,
        contains('revoke all on table public.account_merge_map '
            'from anon, authenticated, public;'),
      );
      expect(executable, isNot(contains('create policy')));
    });

    test('the mapping holds two ids and nothing that names a person', () {
      final start = statements
          .indexOf('create table if not exists public.account_merge_map');
      final table = statements.substring(start, at(statements, ');', start));
      for (final word in ['name', 'email', 'phone', 'token', 'password']) {
        expect(table, isNot(contains(word)), reason: word);
      }
      expect(table, contains('source_user_id'));
      expect(table, contains('retained_user_id'));
    });
  });

  // ---------------------------------------------------------------------------
  group('one transaction, Auth included', () {
    test('the Auth row is deleted exactly once, by the executor itself', () {
      expect('delete from auth.users'.allMatches(statements).length, 1);
      expect(
          'delete from auth.users where id = p_source_user_id;'
              .allMatches(mergeBody)
              .length,
          1);
    });

    test('what has no foreign key to the Auth user is removed by name, first',
        () {
      final authDelete = at(mergeBody, 'delete from auth.users');
      final tokens = at(mergeBody,
          'delete from auth.refresh_tokens where user_id = p_source_user_id::text;');
      final flows = at(mergeBody,
          'delete from auth.flow_state where user_id = p_source_user_id;');
      expect(tokens, greaterThan(0));
      expect(flows, greaterThan(0));
      expect(tokens, lessThan(authDelete));
      expect(flows, lessThan(authDelete));
    });

    test('it checks, after the delete, that nothing of the source is left', () {
      final authDelete = at(mergeBody, 'delete from auth.users');
      final check = at(mergeBody, "raise exception 'AUTH_DELETE_INCOMPLETE'");
      expect(check, greaterThan(authDelete));
      final tail = mergeBody.substring(authDelete);
      for (final table in [
        'public.users',
        'auth.identities',
        'auth.sessions',
        'auth.refresh_tokens',
        'auth.flow_state',
      ]) {
        expect(tail, contains(table), reason: table);
      }
    });

    test(
        'after the Auth delete nothing is written but the switches being reset',
        () {
      final tail =
          blank(mergeBody.substring(at(mergeBody, 'delete from auth.users')));
      final writes = RegExp(
          r'(insert\s+into|delete\s+from|update\s+[\w.]+\s+set|perform\s+(?!set_config))');
      // The delete itself and the two cleanup deletes before it are not "after".
      expect(writes.allMatches(tail.substring('delete from auth.users'.length)),
          isEmpty);
    });

    test('the audit event, the mapping and the invariants come before it', () {
      final authDelete = at(mergeBody, 'delete from auth.users');
      for (final token in [
        "'USER_ACCOUNTS_MERGED'",
        'insert into public.account_merge_map',
        "raise exception 'MERGE_INVARIANT_BROKEN'",
        "raise exception 'MERGE_RESIDUAL_REFERENCE'",
        "raise exception 'MERGE_UNHANDLED_REFERENCE'",
        "raise exception 'MERGE_BLOCKED'",
      ]) {
        expect(mergeBody, contains(token), reason: token);
        expect(at(mergeBody, token), lessThan(authDelete), reason: token);
      }
    });

    test('exactly one audit event, and its payload names no person', () {
      expect("record_admin_audit(".allMatches(mergeBody).length, 1);
      final start = at(mergeBody, 'record_admin_audit(');
      final call = mergeBody.substring(start, at(mergeBody, ');', start));
      for (final word in [
        'email',
        'phone',
        'full_name',
        'access_token',
        'refresh_token',
        'password',
      ]) {
        expect(call, isNot(contains(word)), reason: word);
      }
      expect(call, contains("'source_user_id'"));
      // The counts say how many push tokens went, never what they were.
      expect(call, contains("'push_tokens_invalidated'"));
    });

    test('no second system is asked, and nothing commits or rolls back', () {
      for (final word in [
        'net.http',
        'http_post',
        'http_get',
        'dblink',
        'pg_background',
        'auth.admin',
        'functions/v1',
        'storage.',
        'pg_sleep',
        'commit',
        'rollback',
        'savepoint',
        'execute ',
      ]) {
        expect(mergeBlank, isNot(contains(word)), reason: word);
      }
    });

    test('the only exception handler re-raises as a refusal', () {
      expect('when others'.allMatches(statements).length, 1);
      expect(
        mergeBody,
        matches(RegExp(
            r"when others then\s+raise exception 'RESOLUTIONS_INVALID'")),
      );
    });

    test(
        'merges are serialised and every row it changes is locked in a fixed '
        'order', () {
      expect('pg_advisory_xact_lock('.allMatches(mergeBody).length, 1);
      expect(
          'for update;'.allMatches(mergeBody).length, greaterThanOrEqualTo(3));
      final users = at(mergeBody, 'from public.users u');
      final communities = at(mergeBody, 'from public.communities c');
      final matches = at(mergeBody, 'from public.matches m');
      expect(users, greaterThan(0));
      expect(communities, greaterThan(users));
      expect(matches, greaterThan(communities));
    });

    test('a reference the function has not heard of stops the merge', () {
      expect(
          mergeBody, contains("raise exception 'MERGE_UNHANDLED_REFERENCE'"));
      for (final known in [
        'communities.owner_id',
        'match_goals.user_id',
        'match_results.mvp_user_id',
        'match_registrations.user_id',
        'rating_history.user_id',
        'system_admins.user_id',
      ]) {
        expect(mergeBody, contains(known), reason: known);
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('nothing is switched off, and nothing is weakened', () {
    test('no trigger is disabled, no row security bypassed, no policy touched',
        () {
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
        'session authorization',
        'create trigger',
        'drop trigger',
        'alter table public.match_registrations',
        'alter table public.community_members',
        'alter table public.rating_history',
        'alter table public.user_rating_archive',
      ]) {
        expect(executable, isNot(contains(word)), reason: word);
      }
      // `set role = ...` in an UPDATE is a column; the SQL command is `set role x`.
      expect(executable, isNot(matches(RegExp(r'\bset\s+role\s+(?!=)\w'))));
    });

    test(
        'every switch is transaction-local, and armed for this transaction '
        'only', () {
      final calls = RegExp(r'set_config\(').allMatches(executable).length;
      final local =
          RegExp(r'set_config\([^;]*,\s*true\);').allMatches(executable).length;
      expect(calls, greaterThan(0));
      expect(local, calls, reason: 'no set_config may be session-wide');
      expect(
          executable, isNot(matches(RegExp(r'set_config\([^;]*,\s*false\)'))));
      expect(
        executable,
        isNot(matches(RegExp(r'set\s+(local\s+)?goplay\.'))),
      );

      for (final helper in [
        'merge_skips_lifecycle',
        'merge_rating_scope_excludes',
      ]) {
        final body = functionOf(sql, helper);
        expect(body, contains("v_flag <> 'tx:' || txid_current()::text"),
            reason:
                '$helper honours the switch only inside the transaction that '
                'armed it');
        expect(body, isNot(contains('security definer')));
        expect(body, contains('stable'));
        for (final write in ['insert', 'update', 'delete']) {
          expect(blank(body), isNot(contains('$write ')), reason: helper);
        }
      }
    });

    test('the lifecycle switch is limited to the two accounts being merged',
        () {
      final body = functionOf(sql, 'merge_skips_lifecycle');
      expect(body, contains('goplay.account_merge_users'));
      expect(body, contains('string_to_array(v_users'));
    });

    test(
        'the switches are armed after the gate and the locks, before the first '
        'write, and cleared at the end', () {
      final arm = at(mergeBody, "set_config('goplay.account_merge', 'tx:'");
      final firstWrite =
          RegExp(r'\b(insert\s+into|update\s+public|delete\s+from)\b')
              .firstMatch(mergeBlank)!
              .start;
      expect(
          arm, greaterThan(at(mergeBody, "raise exception 'NOT_AUTHORIZED'")));
      expect(arm, greaterThan(at(mergeBody, 'pg_advisory_xact_lock')));
      expect(arm, greaterThan(lastAt(mergeBody, 'for update;', arm)));
      expect(arm, lessThan(firstWrite));
      // Armed while only reads happen (the preview, again), so nothing the switch
      // stands aside for can fire before the blockers have been checked.
      expect(firstWrite,
          greaterThan(at(mergeBody, "raise exception 'MERGE_BLOCKED'")));

      final authDelete = at(mergeBody, 'delete from auth.users');
      expect(lastAt(mergeBody, "set_config('goplay.account_merge', ''"),
          greaterThan(authDelete));
      expect(lastAt(mergeBody, "set_config('goplay.account_merge_users', ''"),
          greaterThan(authDelete));
    });

    test('the rating archive tables are never written', () {
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
      expect(
        executable,
        isNot(matches(RegExp(r'delete\s+from\s+public\.admin_audit_log\b'))),
      );
      expect(statements, contains("'USER_ACCOUNTS_MERGED'"));
    });

    test(
        'the only change to an audit entry empties the two snapshot columns '
        'of those that name the source', () {
      final updates = RegExp(r'update\s+public\.admin_audit_log\b[^;]*;')
          .allMatches(mergeBlank)
          .map((m) => m.group(0)!)
          .toList();
      expect(updates, hasLength(1), reason: 'one statement, in one place');
      final update = updates.single;
      final set = update.substring(0, update.indexOf(' where '));

      // The two columns that identify a person, and nothing else, and only to NULL.
      // With each `case ... end` folded to X, the whole assignment list is these two.
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
      // Scoped to the source, as actor or as target, and nobody else.
      final where = update.substring(update.indexOf(' where '));
      expect(where, contains('a.actor_user_id = p_source_user_id'));
      expect(where, contains('a.target_id = p_source_user_id'));
      expect(where, isNot(contains('p_retained_user_id')));
      // After the checks and the writes it depends on, before the event and the delete.
      final redaction = at(mergeBody, 'update public.admin_audit_log a');
      expect(redaction,
          greaterThan(at(mergeBody, "raise exception 'MERGE_BLOCKED'")));
      expect(redaction, lessThan(at(mergeBody, 'record_admin_audit(')));
      expect(redaction, lessThan(at(mergeBody, 'delete from auth.users')));
      // And the last look refuses if any snapshot of the source is left.
      final look = at(mergeBody, "raise exception 'MERGE_RESIDUAL_REFERENCE'");
      final last =
          lastAt(mergeBody, 'a.actor_email_snapshot is not null', look);
      expect(last, greaterThan(redaction));
      expect(mergeBody.substring(redaction, look),
          contains('a.target_label_snapshot is not null'));
    });

    test('the number redacted is reported, and the event carries no name', () {
      expect(mergeBody, contains("'audit_entries_redacted', c_audit_redacted"));
      expect(
          "'audit_entries_redacted', c_audit_redacted"
              .allMatches(mergeBody)
              .length,
          2,
          reason: 'in the audit payload and in the answer');
    });

    test('the audit action list gains exactly one value and loses none', () {
      final rollbackActions = RegExp(r"'([A-Z_]+)'")
          .allMatches(rollback.substring(
              at(rollback, 'add constraint admin_audit_log_action_check')))
          .map((m) => m.group(1)!)
          .toSet();
      final start =
          at(statements, 'add constraint admin_audit_log_action_check');
      final actions = RegExp(r"'([A-Z_]+)'")
          .allMatches(statements.substring(start, at(statements, ');', start)))
          .map((m) => m.group(1)!)
          .toSet();
      expect(actions.difference(rollbackActions), {'USER_ACCOUNTS_MERGED'});
      expect(rollbackActions.difference(actions), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('the existing functions are the originals plus one guard', () {
    final lifecycleGuard = RegExp(r"  if public\.merge_skips_lifecycle\(\n"
        r"       case when tg_op = 'DELETE' then old\.user_id else new\.user_id end\) then\n"
        r"    if tg_op = 'DELETE' then\n"
        r"      return old;\n"
        r"    end if;\n"
        r"    return new;\n"
        r"  end if;\n\n");
    final ratingGuard =
        RegExp(r"  if public\.merge_rating_scope_excludes\(p_user_id\) then\n"
            r"    return;\n"
            r"  end if;\n\n");

    for (final name in guarded) {
      test('$name: take the guard out and the rollback\'s body is what is left',
          () {
        final now = functionOf(sql, name);
        final original = functionOf(rollback, name);
        final guard =
            name == 'apply_rating_delta' ? ratingGuard : lifecycleGuard;

        expect(guard.allMatches(now).length, 1, reason: 'exactly one guard');
        expect(guard.allMatches(original), isEmpty,
            reason: 'the original has none');
        expect(now.replaceFirst(guard, '').trim(), original.trim());
      });

      test('$name: security, search_path and signature are unchanged', () {
        final now = functionOf(sql, name);
        final original = functionOf(rollback, name);
        String head(String f) => f.substring(0, at(f, 'as \$\$'));
        expect(head(now), head(original));
      });
    }

    test('the guards call nothing but the two settings readers', () {
      for (final name in guarded) {
        final now = functionOf(sql, name);
        final calls = RegExp(r'public\.merge_\w+\(')
            .allMatches(now)
            .map((m) => m.group(0)!)
            .toSet();
        expect(
          calls,
          {
            name == 'apply_rating_delta'
                ? 'public.merge_rating_scope_excludes('
                : 'public.merge_skips_lifecycle('
          },
          reason: name,
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('the preview', () {
    final previewBody = functionOf(sql, preview);

    test('it is still read only, and still checks the System Admin twice', () {
      expect(previewBody, contains('security definer'));
      expect(previewBody, contains('stable'));
      expect(previewBody, contains('set search_path = public, pg_temp'));
      expect(previewBody, contains('public.is_system_admin()'));
      expect(previewBody, contains('from public.system_admins sa'));
      expect(
          blank(previewBody),
          isNot(
              matches(RegExp(r'\b(insert\s+into|update\s+\w|delete\s+from)'))));
      expect(previewBody, isNot(contains('set_config')));
    });

    test('the audit entries and the stored picture are told, not blockers', () {
      // The Product Owner's decision of 2026-10-10: the merge redacts the audit
      // snapshots itself, and the Edge Function removes the picture first.
      expect(previewBody, contains("('AUDIT_LOG_NAMES_SOURCE', 'CONSTRAINT'"));
      expect(previewBody, contains("('SOURCE_HAS_STORED_FILES', 'CONSTRAINT'"));
      expect(
          previewBody, isNot(contains("('AUDIT_LOG_NAMES_SOURCE', 'BLOCKER'")));
      expect(previewBody,
          isNot(contains("('SOURCE_HAS_STORED_FILES', 'BLOCKER'")));
    });

    test('and so are the cases the product rules forbid', () {
      for (final code in [
        'SHARED_MATCH_NOT_RESOLVABLE',
        'TEAM_AWARD_COLLISION',
        'RETAINED_RATING_INCONSISTENT',
        'SOURCE_IS_SYSTEM_ADMIN',
        'RETAINED_IS_SYSTEM_ADMIN',
        'SOURCE_IS_CALLER',
        'RETAINED_IS_CALLER',
      ]) {
        expect(previewBody, contains("'$code'"), reason: code);
      }
    });

    test('the archives are a stated constraint, not a blocker', () {
      expect(previewBody, contains("('RATING_ARCHIVE_MAPPED', 'CONSTRAINT'"));
    });

    test('it is the same document version the screen reads', () {
      expect(previewBody, contains("'version', 2"));
    });
  });

  // ---------------------------------------------------------------------------
  group('the rollback', () {
    test('it refuses, before changing anything, once a merge has happened', () {
      const refusal = "raise exception 'ROLLBACK_REFUSED_MERGES_EXIST'";
      final refusals = refusal.allMatches(code(rollback)).length;
      expect(refusals, 2,
          reason: 'one for the mapping, one for the audit entry');
      final last = lastAt(code(rollback), refusal);
      expect(at(code(rollback), 'drop function'), greaterThan(last));
      expect(
          at(code(rollback), 'create or replace function'), greaterThan(last));
      expect(rollback, contains('account_merge_map'));
      expect(rollback, contains("action = 'USER_ACCOUNTS_MERGED'"));
    });

    test('it puts the 0096 preview back, verbatim', () {
      expect(functionOf(rollback, preview), functionOf(sql0096, preview));
    });

    test('it drops everything 0101 created, and only that', () {
      for (final fn in [merge, ...helpers]) {
        final args = fn == merge ? 'uuid, uuid, jsonb' : helperArgs[fn];
        expect(rollback, contains('drop function if exists public.$fn($args);'),
            reason: fn);
      }
      expect(
          rollback, contains('drop table if exists public.account_merge_map;'));
      final drops =
          RegExp(r'drop (function|table)').allMatches(code(rollback)).length;
      expect(drops, helpers.length + 1 + 1);
    });

    test(
        'it refuses to be called on a source whose picture is still stored, '
        'but only at the two points that matter', () {
      // Early, before any write, for a direct call that skipped the Edge Function...
      final early = at(mergeBody, "raise exception 'SOURCE_FILES_REMAIN'");
      final firstWrite =
          RegExp(r'\b(insert\s+into|update\s+public|delete\s+from)\b')
              .firstMatch(mergeBlank)!
              .start;
      expect(early, lessThan(firstWrite));
      expect(
          early, greaterThan(at(mergeBody, "raise exception 'MERGE_BLOCKED'")));
      // ...and again at the last look, for a picture that arrived in between.
      final look = at(mergeBody, "raise exception 'MERGE_RESIDUAL_REFERENCE'");
      expect(
          mergeBody.substring(0, look).lastIndexOf('merge_source_stored_files'),
          greaterThan(early));
    });

    test('the stored-files list is read only, bounded, and about one folder',
        () {
      final body = functionOf(sql, 'merge_source_stored_files');
      expect(body, contains('security definer'));
      expect(body, contains('stable'));
      expect(body, contains('set search_path = public, pg_temp'));
      expect(body, contains("s.bucket_id = 'avatars'"));
      expect(body, contains("split_part(s.name, '/', 1) = p_user_id::text"));
      expect(body, contains('limit 1000'));
      expect(
          blank(body), isNot(matches(RegExp(r'\b(insert|update|delete)\b'))));
      // Nothing else in the migration reads Storage.
      expect('storage.objects'.allMatches(executable).length, 1);
    });

    test('it runs again without error, and disables nothing', () {
      expect(code(rollback), isNot(contains('disable trigger')));
      expect(code(rollback), isNot(contains('session_replication_role')));
      expect(rollback, contains('to_regclass'));
    });
  });

  // ---------------------------------------------------------------------------
  group('the Edge Function the app calls', () {
    final function =
        load('../supabase/functions/admin-merge-accounts/index.ts');
    final adapter =
        load('../app/lib/infrastructure/supabase/supabase_admin_adapter.dart');

    test('the adapter invokes it by the name it is deployed under', () {
      expect(adapter, contains("'admin-merge-accounts'"));
      expect(
          Directory('../supabase/functions/admin-merge-accounts').existsSync(),
          isTrue);
    });

    test('it calls exactly the three functions this migration defines', () {
      for (final name in [
        'admin_preview_account_merge',
        'admin_merge_accounts',
        'merge_source_stored_files',
      ]) {
        expect(function, contains(name), reason: name);
        expect(statements, contains('function public.$name('), reason: name);
      }
    });

    test('and speaks the parameter names the RPC defines', () {
      // Each as the function builds it, and each declared by the migration.
      for (final entry in {
        'p_retained_user_id': 'p_retained_user_id: input.retained',
        'p_source_user_id': 'p_source_user_id: input.source',
        'p_resolutions': 'p_resolutions: input.resolutions',
        'p_user_id': '{ p_user_id: source }',
      }.entries) {
        expect(function, contains(entry.value), reason: entry.key);
        expect(statements, contains(entry.key), reason: entry.key);
      }
    });

    test('the error tokens it passes through are raised by the database', () {
      for (final token in [
        'NOT_AUTHORIZED',
        'USER_NOT_FOUND',
        'MERGE_BLOCKED',
        'RESOLUTION_REQUIRED',
        'RESOLUTION_BLOCKED',
        'RESOLUTION_UNKNOWN_MATCH',
        'SOURCE_FILES_REMAIN',
      ]) {
        expect(function, contains(token), reason: token);
        expect(statements, contains("raise exception '$token'"), reason: token);
      }
    });

    test('the Storage call removes by exact name from the avatars bucket only',
        () {
      expect(function, contains('/storage/v1/object/\${BUCKET}'));
      expect(function, contains('const BUCKET = "avatars";'));
      expect(function, contains('JSON.stringify({ prefixes: before })'));
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

    test('it pins the neighbours it must not move', () {
      expect(verify, contains('b34fcb36'));
      expect(verify, contains('99fefffa'));
    });

    test('it says what changes in the older checks, by design', () {
      expect(verify, contains('0096'));
      expect(verify, contains('0099'));
    });

    test(
        'it asks whether the Auth deletion is possible, not only whether the '
        'code says so', () {
      expect(verify, contains('auth.users'));
      expect(verify, contains('delete'));
      expect(verify, contains('exactly once'));
    });
  });
}
