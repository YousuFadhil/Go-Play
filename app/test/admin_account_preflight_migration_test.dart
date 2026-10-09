import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0096 and its rollback and verification say — a static review
/// of the files, not a runtime result.
///
/// The migration has not been applied to the shared database and cannot be run
/// from a widget test, so these assertions read the text. That limit is worth
/// stating plainly: this proves the files say the right things, and the offline
/// run plus `supabase/tool/0096_..._verify.sql` are what prove the database does
/// them. What it catches is the class of mistake that is invisible in review and
/// expensive in production — a preview that quietly writes, a gate that moved
/// below a read, a list that lost its bound, an internal helper that was granted
/// to a client role.
void main() {
  const path =
      '../supabase/migrations/0096_platform_admin_account_preflight.sql';
  const rollbackPath =
      '../supabase/rollback/0096_platform_admin_account_preflight_rollback.sql';
  const verifyPath =
      '../supabase/tool/0096_platform_admin_account_preflight_verify.sql';

  // Git checks these files out with CRLF endings on Windows.
  String load(String file) =>
      File(file).readAsStringSync().replaceAll('\r\n', '\n');

  String code(String text) => text
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  final sql = load(path);
  final statements = code(sql);

  /// With SQL string literals blanked as well: `comment on` bodies legitimately
  /// name things the functions do not do.
  final executable = statements.replaceAll(RegExp("'[^']*'"), "''");

  const helper = 'admin_preview_account_snapshot';
  const merge = 'admin_preview_account_merge';
  const deletion = 'admin_preview_account_deletion';
  const previews = [merge, deletion];
  const all = [helper, merge, deletion];

  const signatures = {
    helper: 'uuid',
    merge: 'uuid, uuid',
    deletion: 'uuid',
  };

  String functionBody(String name) {
    final start =
        statements.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('0096 does not create $name');
    final end = statements.indexOf('\n\$\$;', start);
    return statements.substring(start, end == -1 ? statements.length : end);
  }

  /// A body with string literals blanked.
  String blank(String body) => body.replaceAll(RegExp("'[^']*'"), "''");

  /// The finding codes of one severity in a body: `('CODE', 'SEVERITY', ...`.
  Set<String> codesOf(String body, String severity) => RegExp(
        "\\('([A-Z_]+)',\\s*'$severity'",
      ).allMatches(body).map((m) => m.group(1)!).toSet();

  group('the migration is 0096 and only 0096', () {
    test('all three files exist under the numbers the brief fixed', () {
      expect(File(path).existsSync(), isTrue);
      expect(File(rollbackPath).existsSync(), isTrue);
      expect(File(verifyPath).existsSync(), isTrue);
    });

    test('it creates exactly three functions, with the agreed signatures', () {
      final created = RegExp(r'create or replace function public\.(\w+)\(')
          .allMatches(statements)
          .map((m) => m.group(1)!)
          .toList();
      expect(created, all);

      for (final entry in signatures.entries) {
        final signature = RegExp('create or replace function public\\.'
                '${entry.key}\\(([^)]*)\\)')
            .firstMatch(statements)!
            .group(1)!;
        final types = signature
            .split(',')
            .map((p) => p.trim().split(' ').last)
            .join(', ');
        expect(types, entry.value, reason: entry.key);
      }
    });

    test('nothing existing is replaced, dropped or created beside them', () {
      for (final forbidden in [
        'drop function',
        'create table',
        'create index',
        'create view',
        'create policy',
        'alter policy',
        'drop policy',
        'create trigger',
        'create type',
        'alter table',
        'alter function',
        'create extension',
      ]) {
        expect(executable, isNot(contains(forbidden)), reason: forbidden);
      }
      for (final untouchable in [
        'is_system_admin',
        'record_admin_audit',
        'admin_delete_user',
        'admin_suspend_user',
        'admin_list_users',
        'admin_get_user_account',
      ]) {
        expect(
          statements,
          isNot(contains('create or replace function public.$untouchable')),
          reason: '$untouchable is unchanged',
        );
      }
    });

    test('every grant and revoke names one of the three functions', () {
      for (final line in executable.split('\n')) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('grant ') || trimmed.startsWith('revoke ')) {
          expect(trimmed,
              contains('execute on function public.admin_preview_account_'));
        }
      }
      expect(executable, isNot(contains('on table')));
    });
  });

  group('it is read only', () {
    test('no DML anywhere', () {
      for (final write in [
        RegExp(r'\binsert\s+into\b'),
        RegExp(r'\bdelete\s+from\b'),
        RegExp(r'\btruncate\b'),
        RegExp(r'\bupdate\s+(?:public\.)?\w+\s+set\b'),
        RegExp(r'\bmerge\s+into\b'),
        RegExp(r'\bcopy\b'),
      ]) {
        expect(write.hasMatch(executable), isFalse, reason: write.pattern);
      }
    });

    test('a preview leaves no audit event: record_admin_audit is never called',
        () {
      expect(executable, isNot(contains('record_admin_audit')));
      expect(executable, isNot(contains('admin_audit_log set')));
      // The audit log is only counted.
      expect(statements, contains('from public.admin_audit_log l'));
    });

    test('there is no dynamic SQL and no role or setting change', () {
      expect(executable, isNot(RegExp(r'\bexecute\b')));
      expect(executable, isNot(contains('set role')));
      expect(executable, isNot(contains('set local')));
      expect(executable, isNot(contains('set_config')));
      expect(executable, isNot(contains('perform ')));
    });

    for (final name in all) {
      test('$name is STABLE, so PostgreSQL itself refuses a write from it', () {
        final body = functionBody(name);
        expect(body, contains('security definer\nstable\nset search_path'));
      });
    }

    test('auth is read, never written; storage is not touched', () {
      expect(executable,
          isNot(RegExp(r'(insert\s+into|update|delete\s+from)\s+auth\.')));
      expect(executable, isNot(contains('storage.')));
      final relations = RegExp(r'auth\.(\w+)')
          .allMatches(executable)
          .map((m) => m.group(1))
          .toSet();
      expect(relations, {'users', 'identities', 'uid'});
    });

    test('nothing sensitive is read from auth or from a token table', () {
      for (final sensitive in [
        'encrypted_password',
        'identity_data',
        'raw_user_meta_data',
        'raw_app_meta_data',
        'recovery_token',
        'confirmation_token',
        'access_token',
        'refresh_token',
        'select *',
      ]) {
        expect(executable, isNot(contains(sensitive)), reason: sensitive);
      }
      // Push tokens are counted, never selected: the column is not named.
      expect(executable, isNot(RegExp(r'\b\w+\.token\b')));
      expect(statements, contains('from public.notification_push_tokens t'));
      // Provider NAMES only.
      expect(
          statements, contains('select distinct i.provider::text as provider'));
    });
  });

  group('who may call', () {
    test('the helper is granted to no client role', () {
      expect(
        executable,
        contains('revoke execute on function public.$helper(uuid)\n'
            '  from anon, authenticated, public;'),
      );
      expect(
        RegExp('grant\\s+execute\\s+on\\s+function\\s+public\\.$helper')
            .hasMatch(executable),
        isFalse,
      );
    });

    for (final name in previews) {
      final args = signatures[name]!;
      test('$name is revoked from anon and public, granted as 0066 and 0095 do',
          () {
        final fn = 'public\\.$name\\($args\\)';
        expect(
            RegExp('revoke execute on function $fn\\s+from anon, public;')
                .hasMatch(statements),
            isTrue);
        expect(
            RegExp('grant execute on function $fn\\s+to authenticated;')
                .hasMatch(statements),
            isTrue);
        expect(
            RegExp('grant execute on function $fn\\s+to service_role;')
                .hasMatch(statements),
            isTrue);
      });
    }

    test('no privilege is granted to anon or to public', () {
      expect(
        RegExp(r'\bgrant\b[^;]*\bto\s+(?:anon|public)\b').hasMatch(executable),
        isFalse,
      );
    });
  });

  group('the gate and the hardening', () {
    for (final name in all) {
      group(name, () {
        final body = functionBody(name);

        test('search_path is public, pg_temp, with pg_temp last', () {
          final configured = RegExp(r'set search_path = ([^\n]+)\n')
              .allMatches(body)
              .map((m) => m.group(1)!)
              .toList();
          expect(configured, ['public, pg_temp']);
        });

        test('the caller is checked twice, as the first statement', () {
          final begin = body.indexOf('\nbegin\n');
          final first = body.substring(begin + 7).trimLeft();
          expect(
            first,
            startsWith('if not public.is_system_admin()\n'
                '     or not exists (select 1 from public.system_admins sa\n'
                '                     where sa.user_id = auth.uid()) then\n'
                "    raise exception 'NOT_AUTHORIZED';\n"
                '  end if;'),
          );
        });

        test('every relation, function and row type carries its schema', () {
          final text = blank(body);
          final references =
              RegExp(r'\b(?:from|join|update|into)\s+([a-z_][\w.]*)')
                  .allMatches(text)
                  .map((m) => m.group(1)!)
                  .where((n) =>
                      // Variables, parameters (`distinct from p_…`), CTEs.
                      !n.startsWith('v_') &&
                      !n.startsWith('p_') &&
                      !{'flagged', 'shared', 'ev', 'f', 'f2', 'sh', 'set'}
                          .contains(n) &&
                      !n.startsWith('jsonb_') &&
                      !n.startsWith('generate_'))
                  .toList();
          for (final reference in references) {
            expect(
              reference.startsWith('public.') || reference.startsWith('auth.'),
              isTrue,
              reason: '$name: "$reference" is not schema-qualified',
            );
          }
          expect(
            RegExp(r'(?<![.\w])(?:is_system_admin|record_admin_audit|admin_preview_account_snapshot)\(')
                .hasMatch(text),
            isFalse,
            reason: '$name calls an unqualified function',
          );
        });
      });
    }

    test('refusals are the three codes and nothing else', () {
      final raised = RegExp(r"raise exception '(\w+)'")
          .allMatches(statements)
          .map((m) => m.group(1)!)
          .toSet();
      expect(raised, {'NOT_AUTHORIZED', 'SAME_ACCOUNT', 'USER_NOT_FOUND'});
    });

    test('merge: the gate, then SAME_ACCOUNT, then the accounts are read', () {
      final body = functionBody(merge);
      final at = [
        body.indexOf("raise exception 'NOT_AUTHORIZED'"),
        body.indexOf("raise exception 'SAME_ACCOUNT'"),
        body.indexOf(
            'public.admin_preview_account_snapshot(p_retained_user_id)'),
        body.indexOf('public.admin_preview_account_snapshot(p_source_user_id)'),
        body.indexOf('from public.community_members a'),
      ];
      for (var i = 0; i < at.length; i++) {
        expect(at[i], greaterThan(-1), reason: 'step $i is present');
        if (i > 0) {
          expect(at[i - 1] < at[i], isTrue,
              reason: 'step $i follows step ${i - 1}');
        }
      }
      expect(body,
          contains('p_retained_user_id is not distinct from p_source_user_id'));
    });

    test('USER_NOT_FOUND comes from the helper, so both previews share it', () {
      expect(
          "raise exception 'USER_NOT_FOUND'"
              .allMatches(functionBody(helper))
              .length,
          1);
      expect(functionBody(merge), isNot(contains("'USER_NOT_FOUND'")));
      expect(functionBody(deletion), isNot(contains("'USER_NOT_FOUND'")));
    });
  });

  group('the contracts', () {
    test('every list is bounded to 25 and carries its true total', () {
      for (final name in previews) {
        final body = functionBody(name);
        expect(body, contains('v_limit constant int := 25;'), reason: name);
        final windows = 'row_number() over'.allMatches(body).length;
        final cuts = RegExp(r'\.rn <= v_limit').allMatches(body).length;
        expect(windows, greaterThan(0), reason: name);
        expect(cuts, windows,
            reason: '$name: every ranked list is cut at the limit');
        expect(body, contains("'limit', v_limit"));
      }
      // The totals are counted over everything, not over the page.
      expect(functionBody(merge), contains("'total', count(*)"));
      expect(functionBody(deletion), contains("'total', v_owned_total"));
    });

    test(
        'the merge blockers are identity, ownership, match collisions and the '
        'immutable archives', () {
      expect(codesOf(functionBody(merge), 'BLOCKER'), {
        'SOURCE_IS_CALLER',
        'RETAINED_IS_CALLER',
        'SOURCE_IS_SYSTEM_ADMIN',
        'RETAINED_IS_SYSTEM_ADMIN',
        'OWNERSHIP_CONFLICT',
        'SHARED_MATCH_COLLISION',
        'RATING_ARCHIVE_IMMUTABLE',
      });
    });

    test(
        'a System Admin is a blocker on BOTH sides of a merge, and as the '
        'account to delete', () {
      final mergeBody = functionBody(merge);
      for (final code in [
        'SOURCE_IS_SYSTEM_ADMIN',
        'RETAINED_IS_SYSTEM_ADMIN'
      ]) {
        expect(codesOf(mergeBody, 'BLOCKER'), contains(code), reason: code);
        expect(codesOf(mergeBody, 'CONFLICT'), isNot(contains(code)));
        expect(codesOf(mergeBody, 'CONSTRAINT'), isNot(contains(code)));
      }
      expect(codesOf(functionBody(deletion), 'BLOCKER'),
          contains('TARGET_IS_SYSTEM_ADMIN'));
      // Read from the account's own row, not from the caller's say-so.
      expect(mergeBody,
          contains("(v_source->'account'->>'is_system_admin')::boolean"));
      expect(mergeBody,
          contains("(v_retained->'account'->>'is_system_admin')::boolean"));
      expect(
          functionBody(helper),
          contains(
              'exists (select 1 from public.system_admins sa where sa.user_id = u.id)'));
    });

    test(
        'the merge conflicts are roles, ownership transfer, matches, '
        'statistics and rating', () {
      expect(codesOf(functionBody(merge), 'CONFLICT'), {
        'SOURCE_OWNS_COMMUNITIES',
        'ROLE_CONFLICT',
        'SHARED_MATCH_PARTICIPATION',
        'SOURCE_CREATED_MATCHES',
        'COMMUNITY_STATISTICS_COLLISION',
        'TEAM_AWARD_COLLISION',
        'PLAYER_STATISTICS_RECOMPUTE',
        'RATING_REPLAY_REQUIRED',
      });
    });

    test(
        'the deletion blockers are the two NO ACTION foreign keys, the cascade '
        'of football history, and who the account is', () {
      expect(codesOf(functionBody(deletion), 'BLOCKER'), {
        'TARGET_IS_CALLER',
        'TARGET_IS_SYSTEM_ADMIN',
        'OWNS_COMMUNITIES',
        'CREATED_MATCHES',
        'MVP_RESULTS_WOULD_CASCADE',
        'HISTORY_WOULD_CASCADE',
        'RATING_ARCHIVE_IMMUTABLE',
      });
    });

    test(
        'historical match evidence is a BLOCKER, never softened to a conflict '
        'or a constraint', () {
      final body = functionBody(deletion);
      expect(codesOf(body, 'BLOCKER'), contains('HISTORY_WOULD_CASCADE'));
      expect(
          codesOf(body, 'CONFLICT'), isNot(contains('HISTORY_WOULD_CASCADE')));
      expect(codesOf(body, 'CONSTRAINT'),
          isNot(contains('HISTORY_WOULD_CASCADE')));
      expect(
          body,
          contains(
              "('HISTORY_WOULD_CASCADE', 'BLOCKER', 'HISTORY', v_history_evidence, 1)"));
      // Only the previews of a *deletion* can cascade.
      expect(functionBody(merge), isNot(contains('HISTORY_WOULD_CASCADE')));
    });

    /// The expression `v_history_evidence` is counted from.
    String evidenceExpression() {
      final body = functionBody(deletion);
      final from = body.indexOf('v_history_evidence :=');
      expect(from, greaterThan(-1), reason: 'the evidence count exists');
      return body.substring(from, body.indexOf(';', from));
    }

    test(
        'HISTORY_WOULD_CASCADE counts registrations, lineup places, goals and '
        'rating entries of COMPLETED matches, and nothing else', () {
      final evidence = evidenceExpression();

      for (final table in [
        'public.match_registrations',
        'public.match_team_assignments',
        'public.match_goals',
        'public.rating_history',
      ]) {
        expect(evidence, contains('from $table'), reason: table);
      }
      // Each of the four is tied to a match, by the application's own rule for
      // "completed": the stored status OR the end having passed.
      const completed = "(m.status = 'completed' or m.end_at <= now())";
      expect(completed.allMatches(evidence).length, 4);
      expect(
          RegExp(r'join public\.matches m on m\.id = ')
              .allMatches(evidence)
              .length,
          4);
    });

    test(
        'memberships, the statistics tables and the MVP cascade are NOT part of '
        'the evidence count', () {
      final evidence = evidenceExpression();

      for (final notEvidence in [
        'community_members', // operational
        'player_statistics', // derived
        'community_statistics', // derived
        'match_results', // MVP_RESULTS_WOULD_CASCADE, counted once, there
        'v_counts', // the old sum of totals
      ]) {
        expect(evidence, isNot(contains(notEvidence)), reason: notEvidence);
      }
      // The old definition is gone: a sum of the cascading totals.
      expect(functionBody(deletion), isNot(contains('v_cascade_history')));
      expect(
          functionBody(deletion),
          isNot(contains(
              "(v_counts->>'memberships')::bigint + (v_counts->>'registrations')::bigint")));
    });

    test('what is erased but is not evidence stays visible in the preview', () {
      final body = functionBody(deletion);

      for (final line in [
        "('COMMUNITY_MEMBERSHIPS',    (v_counts->>'memberships')::bigint,               'CASCADE_DELETE', 1)",
        "('MATCH_REGISTRATIONS',      (v_counts->>'registrations')::bigint,             'CASCADE_DELETE', 1)",
        "('LINEUP_ASSIGNMENTS',       (v_counts->>'lineup_assignments')::bigint,        'CASCADE_DELETE', 1)",
        "('PLAYER_STATISTICS',        (v_counts->>'player_statistics_rows')::bigint,    'CASCADE_DELETE', 1)",
        "('COMMUNITY_STATISTICS',     (v_counts->>'community_statistics_rows')::bigint, 'CASCADE_DELETE', 1)",
      ]) {
        expect(body, contains(line), reason: line);
      }
      // ...and none of them is a finding of its own.
      final findingCodes = {
        ...codesOf(body, 'BLOCKER'),
        ...codesOf(body, 'CONFLICT'),
        ...codesOf(body, 'CONSTRAINT'),
      };
      for (final listed in [
        'COMMUNITY_MEMBERSHIPS',
        'PLAYER_STATISTICS',
        'COMMUNITY_STATISTICS',
      ]) {
        expect(findingCodes, isNot(contains(listed)), reason: listed);
      }
    });

    test(
        'a registration for a match not yet played stays its own CONFLICT, the '
        'exact complement of the evidence rule', () {
      final body = functionBody(deletion);

      expect(codesOf(body, 'CONFLICT'), contains('UPCOMING_REGISTRATIONS'));
      expect(
          codesOf(body, 'BLOCKER'), isNot(contains('UPCOMING_REGISTRATIONS')));
      expect(
          body,
          contains(
              "('UPCOMING_REGISTRATIONS', 'CONFLICT', 'MATCH',\n         (v_counts->>'upcoming_registrations')::bigint, 2)"));
      // The helper's rule is the negation of the evidence rule.
      expect(functionBody(helper),
          contains("and m.end_at > now() and m.status <> 'completed'"));
    });

    test('the header says what is evidence and what is only deleted', () {
      final headerText =
          sql.substring(0, sql.indexOf('create or replace function'));

      expect(headerText, contains('historical match evidence'));
      expect(headerText, contains("status is 'completed' OR the"));
      expect(headerText, contains('WHAT IS DELETED BUT IS NOT A BLOCKER'));
      for (final line in [
        'community memberships -- operational',
        '`player_statistics` and `community_statistics` -- derived',
        'registrations for matches not yet played',
      ]) {
        expect(headerText, contains(line), reason: line);
      }
    });

    test(
        'rating_history is erased by the cascade: listed as history, never as '
        'a preserved record', () {
      final body = functionBody(deletion);
      // Historical: CASCADE_DELETE, like the other rows an account cascades.
      expect(
          body,
          contains(
              "('RATING_HISTORY',           (v_counts->>'rating_entries')::bigint,            'CASCADE_DELETE', 1)"));
      // Preserved: the two archives and the audit log, and nothing else.
      final from = body.indexOf('into v_preserved');
      final preserved =
          body.substring(from, body.indexOf(') as f(code, n)', from));
      final codes = RegExp(r"\('([A-Z_]+)'")
          .allMatches(preserved)
          .map((m) => m.group(1))
          .toSet();
      expect(codes,
          {'RATING_HISTORY_ARCHIVE', 'USER_RATING_ARCHIVE', 'ADMIN_AUDIT_LOG'});
      expect(preserved, isNot(contains('rating_entries')));
    });

    test(
        'RATING_HISTORY_IMMUTABLE is history and says UPDATE only -- it is not '
        'an archive and not a promise that the rows survive', () {
      final body = functionBody(deletion);
      expect(body,
          contains("('RATING_HISTORY_IMMUTABLE', 'CONSTRAINT', 'HISTORY',"));
      expect(
          body,
          isNot(
              contains("'RATING_HISTORY_IMMUTABLE', 'CONSTRAINT', 'ARCHIVE'")));
      // The header says what rating_history is, and is not.
      final headerText =
          sql.substring(0, sql.indexOf('create or replace function'));
      expect(headerText, contains('WHAT `rating_history` IS, AND IS NOT'));
    });

    test(
        'immutable rating archives are BLOCKERs for the account being retired, '
        'never downgraded', () {
      for (final name in previews) {
        final body = functionBody(name);
        expect(codesOf(body, 'BLOCKER'), contains('RATING_ARCHIVE_IMMUTABLE'),
            reason: name);
        expect(codesOf(body, 'CONFLICT'),
            isNot(contains('RATING_ARCHIVE_IMMUTABLE')));
        expect(codesOf(body, 'CONSTRAINT'),
            isNot(contains('RATING_ARCHIVE_IMMUTABLE')));
        // Both archive tables count, so one alone is enough to block.
        expect(body, contains("'rating_archive_rows')::bigint"), reason: name);
        expect(body, contains("'user_rating_archive_rows')::bigint"),
            reason: name);
      }
      // Whose archives: the account that would go, not the one that stays.
      expect(functionBody(merge),
          contains("(v_source->'counts'->>'rating_archive_rows')"));
      expect(functionBody(merge),
          isNot(contains("(v_retained->'counts'->>'rating_archive_rows')")));
    });

    test('safety is not inferred from the rebase rollback column', () {
      // `rating_rebase_runs.rollback_skipped_rows` says a past rollback skipped
      // rows, not that skipping them is safe. No preview reads it.
      expect(executable, isNot(contains('rating_rebase_runs')));
      expect(executable, isNot(contains('rollback_skipped_rows')));
    });

    test(
        'the audit log, the rating history and the event logs stay CONSTRAINTs',
        () {
      for (final name in previews) {
        final constraints = codesOf(functionBody(name), 'CONSTRAINT');
        expect(constraints.any((c) => c.startsWith('AUDIT_LOG')), isTrue,
            reason: name);
      }
      expect(codesOf(functionBody(deletion), 'CONSTRAINT'),
          containsAll(['RATING_HISTORY_IMMUTABLE', 'AUDIT_LOG_APPEND_ONLY']));
    });

    test(
        'the verdict is has_blockers: exactly "some finding is a BLOCKER", and '
        'never named like permission', () {
      for (final name in previews) {
        final body = functionBody(name);
        expect(
          body,
          contains(
              "'has_blockers', exists (select 1 from jsonb_array_elements(v_findings) e\n"
              "                             where e->>'severity' = 'BLOCKER')"),
          reason: name,
        );
        expect(body, isNot(contains('can_proceed')), reason: name);
      }
      expect(statements, isNot(contains('can_proceed')));
    });

    test('the header says has_blockers is not a permission', () {
      final headerText =
          sql.substring(0, sql.indexOf('create or replace function'));
      expect(headerText, contains('`has_blockers`'));
      expect(headerText, contains('does NOT mean a merge or a deletion is'));
      expect(headerText, contains('available, safe or authorised'));
    });

    test('a count that is called a number of records counts records', () {
      // `matches_played` is games; a statistics row is one record. The
      // historical list uses rows.
      final body = functionBody(deletion);
      expect(
          body,
          contains(
              "'PLAYER_STATISTICS',        (v_counts->>'player_statistics_rows')::bigint"));
      expect(
          body,
          isNot(contains(
              "(v_counts->>'matches_played')::bigint + (v_counts->>'community_statistics_rows')")));
      expect(functionBody(helper), contains("'player_statistics_rows'"));
    });

    test('findings are only reported when there is something to report', () {
      for (final name in previews) {
        expect(functionBody(name), contains('where f.n > 0;'), reason: name);
      }
    });

    test('the documents say what they could not see', () {
      for (final name in previews) {
        final body = functionBody(name);
        for (final note in [
          'EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED',
          'STORAGE_OBJECTS_NOT_INSPECTED',
          'AUTH_SESSIONS_NOT_INSPECTED',
        ]) {
          expect(body, contains("'$note'"), reason: '$name: $note');
        }
      }
    });

    test('the merge looks for collisions on exactly the unique keys', () {
      final body = functionBody(merge);
      // community_members (community_id, user_id)
      expect(
          body,
          contains(
              'b.community_id = a.community_id and b.user_id = p_source_user_id'));
      // community_statistics (community_id, period_type, period_key, user_id)
      expect(body, contains('b.period_type = a.period_type'));
      expect(body, contains('b.period_key = a.period_key'));
      // team_of_period_awards (snapshot_id, user_id)
      expect(
          body,
          contains(
              'b.snapshot_id = a.snapshot_id and b.user_id = p_source_user_id'));
      // match evidence: registration, lineup, goals, MVP, rating
      for (final kind in ['REGISTRATION', 'LINEUP', 'GOALS', 'MVP', 'RATING']) {
        expect(body, contains("'$kind'"), reason: kind);
      }
      expect(body, contains('(sh.retained_kinds && sh.source_kinds)'));
    });

    test('the deletion preview follows what the foreign keys do', () {
      final body = functionBody(deletion);
      // CASCADE_DELETE, DETACH, RETAINED_ID are the three treatments.
      final treatments = RegExp(r"'(CASCADE_DELETE|DETACH|RETAINED_ID)'")
          .allMatches(body)
          .map((m) => m.group(1))
          .toSet();
      expect(treatments, {'CASCADE_DELETE', 'DETACH', 'RETAINED_ID'});
      // The MVP cascade is called out, because it deletes a whole result.
      expect(
          body,
          contains(
              "('MVP_RESULTS',              (v_counts->>'mvp_awards')::bigint,                'CASCADE_DELETE'"));
      expect(body, contains("'MVP_RESULTS_WOULD_CASCADE'"));
    });

    test('the helper counts every table that names a player', () {
      final body = functionBody(helper);
      for (final relation in [
        'community_members',
        'communities',
        'matches',
        'match_registrations',
        'match_team_assignments',
        'match_goals',
        'match_results',
        'player_statistics',
        'community_statistics',
        'rating_history',
        'rating_history_archive',
        'user_rating_archive',
        'team_of_period_awards',
        'match_registration_events',
        'community_membership_events',
        'btge_generation_runs',
        'match_participation_state',
        'match_professional_guests',
        'notifications',
        'notification_push_tokens',
        'notification_push_preferences',
        'product_events',
        'admin_audit_log',
      ]) {
        expect(body, contains('public.$relation '), reason: relation);
      }
    });
  });

  group('the rollback', () {
    final rollback = code(load(rollbackPath));

    test('it drops exactly the three functions, previews before the helper',
        () {
      final dropped =
          RegExp(r'drop function if exists public\.(\w+)\(([^)]*)\)')
              .allMatches(rollback)
              .map((m) => '${m.group(1)}(${m.group(2)})')
              .toList();
      expect(dropped, [
        '$merge(uuid, uuid)',
        '$deletion(uuid)',
        '$helper(uuid)',
      ]);
    });

    test('it touches no data', () {
      for (final forbidden in [
        'delete from',
        'truncate',
        'insert into',
        'update ',
        'alter table',
        'drop table',
      ]) {
        expect(rollback, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('the verification script', () {
    final verify = code(load(verifyPath));

    test('it is one SELECT and writes nothing', () {
      expect(
          verify,
          isNot(RegExp(
              r'\b(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b',
              caseSensitive: false)));
      expect(verify, contains('order by n, check_name;'));
    });

    test('it pins the hardened state', () {
      expect(verify, contains("array['search_path=public, pg_temp']"));
      expect(
          verify,
          contains(
              'notexists(select1frompublic.system_adminssawheresa.user_id=auth.uid())'));
      expect(verify, contains("provolatile = 's'"));
    });

    test('it pins the safety rules of the applied bodies', () {
      // The verdict name, the archive blockers and the System Admin blockers.
      expect(
          verify,
          contains(
              "''has_blockers'',exists(select1fromjsonb_array_elements(v_findings)e"));
      expect(verify,
          contains("(''RATING_ARCHIVE_IMMUTABLE'',''BLOCKER'',''ARCHIVE''"));
      expect(verify, contains("(''SOURCE_IS_SYSTEM_ADMIN'',''BLOCKER''"));
      expect(verify, contains("(''RETAINED_IS_SYSTEM_ADMIN'',''BLOCKER''"));
      expect(verify, contains("(''TARGET_IS_SYSTEM_ADMIN'',''BLOCKER''"));
      expect(verify, contains("like '%can_proceed%'"));
    });

    test('it pins the historical-data corrections', () {
      // rating_history is CASCADE_DELETE history and is never a preserved record.
      expect(
          verify,
          contains(
              "(''RATING_HISTORY'',(v_counts->>''rating_entries'')::bigint,''CASCADE_DELETE''"));
      expect(
          verify,
          contains(
              "(''RATING_HISTORY'',(v_counts->>''rating_entries'')::bigint)%"));
      // Cascade history is a blocker; the rating-history finding is history.
      expect(verify,
          contains("(''HISTORY_WOULD_CASCADE'',''BLOCKER'',''HISTORY''"));
      expect(verify,
          contains("(''RATING_HISTORY_IMMUTABLE'',''CONSTRAINT'',''HISTORY''"));
    });

    test('it pins that the blocker counts completed-match evidence only', () {
      // Check 22: the four evidence tables, the completed rule four times, and
      // no memberships, statistics or v_counts in the expression.
      expect(
          verify,
          contains(
              "substring(f.src_compact from 'v_history_evidence:=([^;]*);')"));
      expect(verify, contains("'public.match_registrations'"));
      expect(verify, contains("'public.match_team_assignments'"));
      expect(verify, contains("'public.match_goals'"));
      expect(verify, contains("'public.rating_history'"));
      expect(verify, contains("(m.status=''completed''orm.end_at<=now())"));
      for (final forbidden in [
        'community_members',
        'player_statistics',
        'community_statistics',
        'v_counts',
      ]) {
        expect(verify, contains("e.body not like '%$forbidden%'"),
            reason: forbidden);
      }
      expect(
          verify,
          contains(
              "(''HISTORY_WOULD_CASCADE'',''BLOCKER'',''HISTORY'',v_history_evidence,1)"));
      // Check 23: upcoming registrations stay a separate CONFLICT.
      expect(verify,
          contains("(''UPCOMING_REGISTRATIONS'',''CONFLICT'',''MATCH''"));
    });

    test('the verification order is written down, with the reason', () {
      final text = load(verifyPath);
      expect(text, contains('## VERIFICATION ORDER'));
      expect(text, contains('Apply 0095'));
      expect(text, contains('Apply 0096'));
      expect(
          text, contains('Do NOT run `0095_..._verify.sql` again after 0096'));
      expect(text, contains('check 13 is specific to the 0094 baseline'));
      expect(text, contains('26 `admin_*` functions'));
    });
  });
}
