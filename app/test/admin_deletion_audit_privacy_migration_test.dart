import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0099 and its rollback and verification say -- a static review of
/// the files, not a runtime result.
///
/// 0099 makes identifiable audit entries a BLOCKER in the read-only account
/// deletion preview. It cannot be run from a widget test, so these assertions read
/// the text. What they cannot show -- the documents the function returns on the
/// real chain (0017, 0098, 0062, 0096, then 0099) -- the offline run and
/// `supabase/tool/0099_..._verify.sql` show. What they catch is the class of
/// mistake that is invisible in review: a second function quietly redefined, a body
/// that differs from 0096's by more than the one finding, a write, a grant to
/// anon, or the applied 0096 migration edited.
void main() {
  const path0096 =
      '../supabase/migrations/0096_platform_admin_account_preflight.sql';
  const path =
      '../supabase/migrations/0099_admin_deletion_audit_privacy_preflight.sql';
  const rollbackPath =
      '../supabase/rollback/0099_admin_deletion_audit_privacy_preflight_rollback.sql';
  const verifyPath =
      '../supabase/tool/0099_admin_deletion_audit_privacy_preflight_verify.sql';

  const deletion = 'admin_preview_account_deletion';
  const merge = 'admin_preview_account_merge';
  const helper = 'admin_preview_account_snapshot';

  String load(String file) =>
      File(file).readAsStringSync().replaceAll('\r\n', '\n');

  String code(String text) => text
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// With SQL string literals blanked as well.
  String blank(String text) => text.replaceAll(RegExp("'[^']*'"), "''");

  /// The whole `create or replace function public.<name>(...) ... $$;` statement.
  String statementOf(String text, String name) {
    final start = text.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('no $name in the file');
    return text.substring(start, text.indexOf('\n\$\$;', start) + 4);
  }

  /// What PostgreSQL stores as `prosrc`: the text between `as $$` and `$$;`.
  String bodyOf(String statement) => statement.substring(
      statement.indexOf('as \$\$') + 5, statement.length - 3);

  /// The finding codes of one severity in a body: `('CODE', 'SEVERITY', ...`.
  Set<String> codesOf(String body, String severity) =>
      RegExp("\\('([A-Z_]+)',\\s*'$severity'")
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();

  List<String> minus(List<String> a, List<String> b) {
    final remaining = <String, int>{};
    for (final line in b) {
      remaining[line] = (remaining[line] ?? 0) + 1;
    }
    final out = <String>[];
    for (final line in a) {
      if ((remaining[line] ?? 0) > 0) {
        remaining[line] = remaining[line]! - 1;
      } else {
        out.add(line);
      }
    }
    return out;
  }

  int fnv1a32(String text) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(text)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  final sql = load(path);
  final statements = code(sql);
  final executable = blank(statements);
  final sql0096 = load(path0096);

  final body99 = bodyOf(statementOf(sql, deletion));
  final body96 = bodyOf(statementOf(sql0096, deletion));

  group('the files, and the numbering', () {
    test('all three exist under the agreed number and name', () {
      expect(File(path).existsSync(), isTrue);
      expect(File(rollbackPath).existsSync(), isTrue);
      expect(File(verifyPath).existsSync(), isTrue);
    });

    test('0099 is the only migration with that number', () {
      final numbered = Directory('../supabase/migrations')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('0099_'))
          .toList();
      expect(numbered, ['0099_admin_deletion_audit_privacy_preflight.sql']);
    });

    test('the header says why, what changes, what does not, and the order', () {
      final header =
          sql.substring(0, sql.indexOf('create or replace function'));

      for (final line in [
        'Forward-only',
        'actor_email_snapshot',
        'target_label_snapshot',
        'no foreign key leads from the log to `users`',
        'WHAT CHANGES',
        'WHAT DOES NOT CHANGE',
        'AUDIT_LOG_NAMES_SOURCE',
        'stays a CONSTRAINT',
        'It is already applied and is not edited',
        'independent of 0097',
        '0098 only redefines',
        'Review and approve separately before running against the live database',
      ]) {
        expect(header, contains(line), reason: line);
      }
    });
  });

  group('0096 is the applied migration and has not been rewritten', () {
    // These bodies are what is LIVE: the same lengths as `prosrc` on the project,
    // and the hashes the offline run matches against the live md5. A change to the
    // 0096 file moves them.
    for (final pin in <(String, int, int)>[
      (deletion, 11990, 0x70c7c1f9),
      (merge, 10582, 0x9e3aa4bd),
      (helper, 5167, 0xd68cd3af),
    ]) {
      test('${pin.$1}: the body is byte for byte the applied one', () {
        final body = bodyOf(statementOf(sql0096, pin.$1));
        expect(body.length, pin.$2);
        expect(fnv1a32(body), pin.$3);
      });
    }

    test('0096 still says what it said: the audit finding is its CONSTRAINT',
        () {
      expect(codesOf(body96, 'CONSTRAINT'), contains('AUDIT_LOG_APPEND_ONLY'));
      expect(
          codesOf(body96, 'BLOCKER'), isNot(contains('AUDIT_LOG_APPEND_ONLY')));
      expect(sql0096, contains("account. Migration 0096.';"));
    });
  });

  group('0099 replaces one function and nothing else', () {
    test('it creates exactly one function: the deletion preview', () {
      final created =
          RegExp(r'create (?:or replace )?function public\.(\w+)\(([^)]*)\)')
              .allMatches(statements)
              .map((m) => '${m.group(1)}(${m.group(2)!.trim()})')
              .toList();
      expect(created, ['$deletion(p_user_id uuid)']);
      expect(statements, contains('returns jsonb'));
    });

    test('the merge preview and the helper are not redefined', () {
      expect(statements, isNot(contains('function public.$merge(')));
      expect(statements, isNot(contains('function public.$helper(')));
      // ...but the deletion preview still calls the helper, as it did.
      expect(body99, contains('public.$helper(p_user_id)'));
    });

    test('there is no DML, no DDL on data, no audit call and no dynamic SQL',
        () {
      final text = executable.replaceAll('create or replace function', '');
      for (final forbidden in [
        'insert',
        'update',
        'delete',
        'truncate',
        'drop',
        'alter',
        'create',
        'execute format',
        'record_admin_audit',
      ]) {
        // grant/revoke on the one function are the only statements besides it.
        expect(
            RegExp('\\b${RegExp.escape(forbidden)}\\b')
                .hasMatch(blank(code(body99))),
            isFalse,
            reason: forbidden);
      }
      expect(text, isNot(contains('alter table')));
      expect(text, isNot(contains('create table')));
    });

    test('the refusals are the same two codes', () {
      final raised = RegExp(r"raise exception '(\w+)'")
          .allMatches(statements)
          .map((m) => m.group(1)!)
          .toSet();
      expect(raised, {'NOT_AUTHORIZED'});
    });
  });

  group('the hardening is exactly what 0096 left', () {
    test('security definer, STABLE, search_path = public, pg_temp', () {
      final statement = statementOf(sql, deletion);
      expect(statement, contains('security definer'));
      expect(statement, contains('\nstable\n'));
      expect(statement, isNot(contains('volatile')));
      expect(
          RegExp(r'set search_path = ([^\n]+)\n')
              .allMatches(statement)
              .map((m) => m.group(1)!)
              .toList(),
          ['public, pg_temp']);
    });

    test('the caller is checked twice, as the first statement', () {
      final begin = body99.indexOf('\nbegin\n');
      expect(
        body99.substring(begin + 7).trimLeft(),
        startsWith('if not public.is_system_admin()\n'
            '     or not exists (select 1 from public.system_admins sa\n'
            '                     where sa.user_id = auth.uid()) then\n'
            "    raise exception 'NOT_AUTHORIZED';\n"
            '  end if;'),
      );
    });

    test('every relation, function and row type carries its schema', () {
      final text = blank(body99);
      final references = RegExp(r'\b(?:from|join|update|into)\s+([a-z_][\w.]*)')
          .allMatches(text)
          .map((m) => m.group(1)!)
          .where((n) =>
              !n.startsWith('v_') &&
              !n.startsWith('p_') &&
              !{'flagged', 'shared', 'ev', 'f', 'f2', 'sh', 'set'}
                  .contains(n) &&
              !n.startsWith('jsonb_') &&
              !n.startsWith('generate_'))
          .toList();
      for (final reference in references) {
        expect(reference.startsWith('public.') || reference.startsWith('auth.'),
            isTrue,
            reason: '"$reference" is not schema-qualified');
      }
      expect(
        RegExp(r'(?<![.\w])(?:is_system_admin|record_admin_audit|admin_preview_account_snapshot)\(')
            .hasMatch(text),
        isFalse,
      );
    });

    test('the grants are as 0096 gave them, and are not widened', () {
      const fn = 'public.$deletion\\(uuid\\)';
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
      expect(
          RegExp(r'\bgrant\b[^;]*\bto\s+(?:anon|public)\b')
              .hasMatch(executable),
          isFalse);
    });
  });

  group('the one change', () {
    test('AUDIT_LOG_APPEND_ONLY is a BLOCKER of category AUDIT, never softened',
        () {
      expect(codesOf(body99, 'BLOCKER'), contains('AUDIT_LOG_APPEND_ONLY'));
      expect(codesOf(body99, 'CONFLICT'),
          isNot(contains('AUDIT_LOG_APPEND_ONLY')));
      expect(codesOf(body99, 'CONSTRAINT'),
          isNot(contains('AUDIT_LOG_APPEND_ONLY')));
      expect(
          body99,
          contains("('AUDIT_LOG_APPEND_ONLY', 'BLOCKER', 'AUDIT',\n"
              "         (v_counts->>'audit_entries')::bigint, 1),"));
    });

    test('it counts every entry that references the account, actor or target',
        () {
      // The count is the helper's, unchanged: entries, one per row.
      final helperBody = bodyOf(statementOf(sql0096, helper));
      expect(
          helperBody,
          contains("'audit_entries',\n"
              '        (select count(*) from public.admin_audit_log l\n'
              '          where l.actor_user_id = p_user_id or l.target_id = p_user_id),'));
      expect(statements,
          isNot(contains('create or replace function public.$helper(')));
    });

    test('the body differs from 0096\'s by that row and comments, nothing more',
        () {
      final lines96 = body96.split('\n');
      final lines99 = body99.split('\n');

      expect(minus(lines96, lines99), [
        "      ('AUDIT_LOG_APPEND_ONLY', 'CONSTRAINT', 'AUDIT',",
        "         (v_counts->>'audit_entries')::bigint, 3),",
      ]);
      final added = minus(lines99, lines96);
      expect(added.where((l) => !l.trimLeft().startsWith('--')).toList(), [
        "      ('AUDIT_LOG_APPEND_ONLY', 'BLOCKER', 'AUDIT',",
        "         (v_counts->>'audit_entries')::bigint, 1),",
      ]);
      expect(added.where((l) => l.trimLeft().startsWith('--')), hasLength(6));
    });

    test('no other finding moved: same codes, same severities', () {
      for (final severity in ['BLOCKER', 'CONFLICT', 'CONSTRAINT']) {
        final before = codesOf(body96, severity);
        final after = codesOf(body99, severity);
        final expected = switch (severity) {
          'BLOCKER' => {...before, 'AUDIT_LOG_APPEND_ONLY'},
          'CONSTRAINT' => before.difference({'AUDIT_LOG_APPEND_ONLY'}),
          _ => before,
        };
        expect(after, expected, reason: severity);
      }
      // The ones the brief names, by name.
      expect(
          codesOf(body99, 'BLOCKER'),
          containsAll([
            'OWNS_COMMUNITIES',
            'CREATED_MATCHES',
            'MVP_RESULTS_WOULD_CASCADE',
            'HISTORY_WOULD_CASCADE',
            'RATING_ARCHIVE_IMMUTABLE',
            'TARGET_IS_SYSTEM_ADMIN',
            'TARGET_IS_CALLER',
          ]));
      expect(codesOf(body99, 'CONFLICT'), {'UPCOMING_REGISTRATIONS'});
      expect(codesOf(body99, 'CONSTRAINT'),
          {'RATING_HISTORY_IMMUTABLE', 'EVENT_LOGS_NAME_ACCOUNT'});
    });

    test('the contract is unchanged: keys, bounds and preserved records', () {
      expect(
          body99,
          contains(
              "'has_blockers', exists (select 1 from jsonb_array_elements(v_findings) e\n"
              "                             where e->>'severity' = 'BLOCKER'),"));
      expect(body99, isNot(contains('can_proceed')));
      expect(body99, contains("v_limit constant int := 25;"));
      // The audit log is still listed as preserved: it still survives the deletion.
      expect(
          body99,
          contains(
              "('ADMIN_AUDIT_LOG',        (v_counts->>'audit_entries')::bigint)"));
      for (final key in [
        "'personal_data', v_personal",
        "'historical_records', v_historical",
        "'preserved_records', v_preserved",
        "'findings', v_findings",
        "'coverage_notes'",
      ]) {
        expect(body99, contains(key), reason: key);
      }
    });

    test('the function comment says the audit finding blocks', () {
      expect(sql, contains('(a BLOCKER when any entry references it)'));
      expect(sql, contains('Migrations 0096, 0099.'));
    });
  });

  group('the rollback', () {
    final rollback = load(rollbackPath);

    test('it puts the 0096 function back, verbatim, and its comment', () {
      expect(statementOf(rollback, deletion), statementOf(sql0096, deletion));
      expect(rollback, contains("'account. Migration 0096.';"));
      expect(rollback, isNot(contains('Migrations 0096, 0099')));
    });

    test('it drops nothing and changes no data', () {
      final text =
          blank(code(rollback)).replaceAll('create or replace function', '');
      for (final forbidden in [
        'drop',
        'delete',
        'truncate',
        'insert',
        'update',
        'alter',
      ]) {
        expect(
            RegExp('\\b$forbidden\\b')
                .hasMatch(blank(code(bodyOf(statementOf(rollback, deletion))))),
            isFalse,
            reason: forbidden);
        expect(text, isNot(contains('$forbidden table')));
      }
      expect(text, isNot(contains('drop function')));
    });

    test('the grants are the same, and not widened', () {
      expect(rollback, contains('from anon, public;'));
      expect(rollback, contains('to authenticated;'));
      expect(rollback, contains('to service_role;'));
      expect(
          RegExp(r'\bgrant\b[^;]*\bto\s+(?:anon|public)\b')
              .hasMatch(blank(code(rollback))),
          isFalse);
    });
  });

  group('the verification script', () {
    final verifyText = load(verifyPath);
    final verify = code(verifyText);

    test('it is one SELECT and writes nothing', () {
      final text = blank(verify);
      expect(
          RegExp(r'\b(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b',
                  caseSensitive: false)
              .hasMatch(text),
          isFalse);
      expect(RegExp(';').allMatches(text).length, 1);
      expect(verify, contains('order by n, check_name;'));
    });

    test('it pins the hardened state of the function', () {
      expect(
          verify, contains("proconfig = array['search_path=public, pg_temp']"));
      expect(verify, contains("provolatile = 's'"));
      expect(
          verify,
          contains(
              'notexists(select1frompublic.system_adminssawheresa.user_id=auth.uid())'));
      expect(
          verify, contains("has_function_privilege('anon', oid, 'EXECUTE')"));
      expect(verify, contains('public_can_execute'));
    });

    test('it pins the change and that nothing else moved', () {
      expect(
          verify,
          contains(
              "(''AUDIT_LOG_APPEND_ONLY'',''BLOCKER'',''AUDIT'',(v_counts->>''audit_entries'')::bigint,1)"));
      expect(verify, contains("''AUDIT_LOG_APPEND_ONLY'',''CONSTRAINT''"));
      expect(
          verify,
          contains('AUDIT_LOG_APPEND_ONLY=BLOCKER, CREATED_MATCHES=BLOCKER, '
              'EVENT_LOGS_NAME_ACCOUNT=CONSTRAINT, '));
      expect(verify, contains('UPCOMING_REGISTRATIONS=CONFLICT'));
      expect(verify, contains("'%can_proceed%'"));
    });

    test('it pins the merge preview and the helper to the applied bodies', () {
      expect(verify, contains('52aa9c51eb20b4fd46f99874a98cbd8a'));
      expect(verify, contains('99fefffab545f72e72496b5213c59ad5'));
      expect(verify, contains("md5(replace(p.prosrc, E'\\r\\n', E'\\n'))"));
    });

    test('it keeps the audit log closed and the audit writer unreachable', () {
      expect(verify, contains('relrowsecurity'));
      expect(
          verify,
          contains(
              "has_table_privilege('authenticated', 'public.admin_audit_log', 'SELECT')"));
      expect(verify,
          contains('record_admin_audit(text,text,uuid,text,text,jsonb)'));
    });

    test('the order and the baseline are written down', () {
      expect(verifyText, contains('## BASELINE'));
      expect(verifyText, contains('## ORDER'));
      expect(verifyText,
          contains('`0096_..._verify.sql` is still valid afterwards'));
    });
  });
}
