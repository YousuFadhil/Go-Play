import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0103, its rollback and verification, and the `admin-user-auth` Edge Function say
/// -- a static review of the files, not a runtime result.
///
/// The migration has not been applied to the shared database. The offline runs (the real migration
/// chain plus 0101, 0102 and 0103 in PGlite, on synthetic accounts), the Edge Function's tests against
/// a fake backend, and `supabase/tool/0103_..._verify.sql` are what prove behaviour. What THIS catches
/// is the class of mistake that is invisible in review and expensive in production: a gate that moved
/// below a read, a function that learned to write a credential, an actor that became a parameter, a
/// helper granted to a client role, an audit event that picked up an address, the service role
/// reaching further than the one Admin API call, a password in a log, or an applied migration quietly
/// edited.
void main() {
  const path = '../supabase/migrations/0103_admin_user_auth_management.sql';
  const path0102 = '../supabase/migrations/0102_account_deletion_engine.sql';
  const rollbackPath =
      '../supabase/rollback/0103_admin_user_auth_management_rollback.sql';
  const verifyPath =
      '../supabase/tool/0103_admin_user_auth_management_verify.sql';
  const functionPath = '../supabase/functions/admin-user-auth/index.ts';

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

  /// Where [token] is in [text]. A bare `indexOf` answers -1 for a token that is missing, and -1 is
  /// less than everything: an order check built on it passes when the thing it orders has gone.
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

  String functionOf(String sql, String name) {
    final text = code(sql);
    final start = text.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('no function $name');
    final end = text.indexOf('\n\$\$;', start);
    return text.substring(start, end < 0 ? text.length : end + 4);
  }

  /// The parameter list of a function, as written.
  String signatureOf(String sql, String name) {
    final text = code(sql);
    final start = at(text, 'create or replace function public.$name(');
    return text.substring(start, at(text, '\nreturns', start));
  }

  Set<String> actionsOf(String sql) {
    final text = code(sql);
    final start = at(text, 'add constraint admin_audit_log_action_check');
    return RegExp("'([A-Z_]+)'")
        .allMatches(text.substring(start, at(text, ');', start)))
        .map((m) => m.group(1)!)
        .toSet();
  }

  final sql = load(path);
  final statements = code(sql);
  final executable = blank(statements);
  final rollback = load(rollbackPath);
  final verify = load(verifyPath);
  final edge = load(functionPath);
  final edgeCode =
      code(edge.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), ''));

  final guard = functionOf(sql, 'admin_user_auth_guard');
  final check = functionOf(sql, 'admin_check_user_auth_action');
  const writerNames = [
    'admin_record_user_email_changed',
    'admin_record_user_recovery_sent',
    'admin_record_user_password_set',
  ];
  final writers = {for (final n in writerNames) n: functionOf(sql, n)};
  const api = [
    'admin_check_user_auth_action(uuid, text, text)',
    'admin_record_user_email_changed(uuid, text)',
    'admin_record_user_recovery_sent(uuid, text, boolean)',
    'admin_record_user_password_set(uuid, text)',
  ];
  const internal = ['admin_user_auth_guard(uuid)'];

  // ---------------------------------------------------------------------------
  group('the applied migrations are not rewritten', () {
    test(
        '0095, 0096, 0099, 0101 and 0102, which are live, are the applied files',
        () {
      const pins = {
        '0095_platform_admin_user_account_management': (28992, 1995987755),
        '0096_platform_admin_account_preflight': (44849, 3931011787),
        '0099_admin_deletion_audit_privacy_preflight': (18217, 2680329963),
        '0101_platform_admin_account_merge': (79921, 3268317902),
        '0102_account_deletion_engine': (73548, 1867280444),
      };
      for (final entry in pins.entries) {
        final text = load('../supabase/migrations/${entry.key}.sql');
        expect((text.length, fnv1a32(text)), entry.value, reason: entry.key);
      }
    });

    test('0103 is the only migration with its number', () {
      final names = Directory('../supabase/migrations')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('0103_'))
          .toList();
      expect(names, ['0103_admin_user_auth_management.sql']);
    });
  });

  // ---------------------------------------------------------------------------
  group('who may do what, decided on the server', () {
    test(
        'the guard asks for a session, then System Admin twice, then the target',
        () {
      final session = at(guard, "raise exception 'NOT_AUTHENTICATED'");
      final helper = at(guard, 'public.is_system_admin()');
      final table = at(guard, 'from public.system_admins sa');
      final denied = at(guard, "raise exception 'NOT_AUTHORIZED'");
      final self = at(guard, "raise exception 'CANNOT_MODIFY_SELF'");
      final admin = at(guard, "raise exception 'CANNOT_MODIFY_SYSTEM_ADMIN'");
      final read = at(guard, 'from public.users u');
      final missing = at(guard, "raise exception 'USER_NOT_FOUND'", read);
      expect(session, lessThan(helper));
      expect(helper, lessThan(denied));
      expect(table, lessThan(denied));
      expect(denied, lessThan(self));
      expect(self, lessThan(admin));
      expect(admin, lessThan(read));
      expect(read, lessThan(missing));
      expect(guard, contains('v_caller uuid := auth.uid();'));
      expect(guard, contains('u.deleted_at is null'));
      expect(guard, contains('au.deleted_at is null'));
    });

    test(
        'every public function calls the guard before it reads or writes anything',
        () {
      for (final entry in {'check': check, ...writers}.entries) {
        final body = entry.value;
        final call = at(body, ':= public.admin_user_auth_guard(p_user_id);');
        for (final later in [
          'raise exception',
          'auth.users',
          'auth.identities',
          'record_admin_audit',
        ]) {
          final i = body.indexOf(later);
          if (i >= 0) expect(call, lessThan(i), reason: '${entry.key}: $later');
        }
        expect(body, isNot(contains('auth.uid()')),
            reason: '${entry.key}: the caller is read in the guard, once');
      }
    });

    test(
        'no function takes an actor, and the writers take no action and no metadata',
        () {
      for (final name in [
        'admin_user_auth_guard',
        'admin_check_user_auth_action',
        ...writerNames,
      ]) {
        final signature = signatureOf(sql, name).toLowerCase();
        expect(signature, isNot(contains('actor')), reason: name);
        expect(signature, isNot(contains('caller')), reason: name);
      }
      for (final name in writerNames) {
        final signature = signatureOf(sql, name).toLowerCase();
        expect(signature, isNot(contains('action')), reason: name);
        expect(signature, isNot(contains('metadata')), reason: name);
        expect(signature, isNot(contains('label')), reason: name);
      }
    });

    test('every function is security definer with a fixed search path', () {
      for (final body in [guard, check, ...writers.values]) {
        expect(body, contains('security definer'));
        expect(body, contains('set search_path = public, pg_temp'));
      }
      expect(guard, contains('\nstable\n'));
      expect(check, contains('\nstable\n'));
      for (final body in writers.values) {
        expect(body, isNot(contains('\nstable\n')));
      }
    });

    test(
        'the four API functions are for signed-in users only; the guard for nobody',
        () {
      for (final fn in api) {
        expect(
            statements,
            contains(
                'revoke execute on function public.$fn\n  from anon, public;'),
            reason: fn);
        expect(
            statements,
            contains(
                'grant execute on function public.$fn\n  to authenticated;'),
            reason: fn);
      }
      for (final fn in internal) {
        expect(
            statements,
            contains('revoke execute on function public.$fn\n'
                '  from anon, authenticated, public;'),
            reason: fn);
        expect(executable,
            isNot(matches(RegExp('grant[^;]*admin_user_auth_guard'))));
      }
      for (final grant in RegExp(r'grant\b[^;]*;').allMatches(executable)) {
        final text = grant.group(0)!;
        final grantees = text.substring(text.lastIndexOf(RegExp(r'\bto\b')));
        expect(
            grantees, isNot(matches(RegExp(r'\b(anon|public|service_role)\b'))),
            reason: text);
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('the database decides, records, and changes no credential', () {
    test('nothing here writes auth, sends a request or runs dynamic SQL', () {
      expect(
          executable,
          isNot(matches(
              RegExp(r'\b(insert\s+into|update|delete\s+from)\s+auth\.'))));
      for (final word in [
        'net.http',
        'http_post',
        'pg_net',
        'execute format',
        'session_replication_role',
        'disable trigger',
        'set_config',
        'security invoker',
        'create policy',
        'truncate',
      ]) {
        expect(executable, isNot(contains(word)), reason: word);
      }
      expect(executable, isNot(matches(RegExp(r"\bexecute\s+'"))));
    });

    test(
        'the only DML-free statements: one constraint pair, functions, comments, grants',
        () {
      final starts = RegExp(r'^(\w+(?:\s+\w+){0,3})', multiLine: true)
          .allMatches(executable)
          .map((m) => m.group(1)!.toLowerCase())
          .where((s) => RegExp(
                  r'^(alter table|create or replace function|comment on|revoke|grant|create |drop |insert|update|delete)')
              .hasMatch(s))
          .toList();
      for (final start in starts) {
        expect(
            start,
            anyOf(
                startsWith('alter table'),
                startsWith('create or replace function'),
                startsWith('comment on'),
                startsWith('revoke'),
                startsWith('grant')),
            reason: start);
      }
      expect(
          RegExp(r'\balter table\s+(\S+)')
              .allMatches(executable)
              .map((m) => m.group(1))
              .toSet(),
          {'public.admin_audit_log'});
      expect(
          executable,
          isNot(matches(
              RegExp(r'\bcreate\s+(table|index|trigger|view|extension)\b'))));
      expect('drop constraint'.allMatches(executable).length, 1);
    });

    test('the check and the guard only read', () {
      for (final body in [blank(guard), blank(check)]) {
        expect(
            body,
            isNot(matches(RegExp(
                r'\b(insert\s+into|delete\s+from|update\s+\w|record_admin_audit|perform)\b'))));
      }
    });

    test('a Google identity refuses the change before the address is looked at',
        () {
      final google = at(check, "raise exception 'GOOGLE_LINKED'");
      expect(google, lessThan(at(check, "raise exception 'INVALID_EMAIL'")));
      expect(google, lessThan(at(check, "raise exception 'EMAIL_TAKEN'")));
      expect(check, contains("(v_guard->>'has_google')::boolean"));
      expect(guard, contains("'google' = any (v_providers)"));
    });

    test('the address is validated, normalised and compared case-insensitively',
        () {
      expect(
          check, contains("v_new := lower(btrim(coalesce(p_new_email, '')));"));
      expect(check, contains('char_length(v_new) > 254'));
      expect(
          check, contains(r"[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$"));
      expect(check, contains("if v_new = lower(coalesce(v_current, '')) then"));
      expect(check,
          contains('lower(x.email::text) = v_new and x.id <> p_user_id'));
      expect(
          check, contains('lower(i.email) = v_new and i.user_id <> p_user_id'));
      final order = [
        "raise exception 'INVALID_EMAIL'",
        "raise exception 'EMAIL_UNCHANGED'",
        "raise exception 'EMAIL_TAKEN'",
      ];
      var last = -1;
      for (final token in order) {
        final i = at(check, token);
        expect(i, greaterThan(last), reason: token);
        last = i;
      }
    });

    test('the three actions, and only they, are accepted', () {
      expect(
          check,
          contains(
              "p_action not in ('CHANGE_EMAIL', 'SEND_RECOVERY', 'SET_PASSWORD')"));
    });

    test(
        'each writer records its own action through the existing writer, with a fixed shape',
        () {
      const expected = {
        'admin_record_user_email_changed': (
          'USER_EMAIL_CHANGED',
          "'{}'::jsonb"
        ),
        'admin_record_user_recovery_sent': (
          'USER_RECOVERY_SENT',
          "jsonb_build_object('after_email_change', coalesce(p_after_email_change, false))"
        ),
        'admin_record_user_password_set': ('USER_PASSWORD_SET', "'{}'::jsonb"),
      };
      for (final entry in expected.entries) {
        final body = writers[entry.key]!;
        expect('record_admin_audit('.allMatches(body).length, 1,
            reason: entry.key);
        expect(
            RegExp("'USER_[A-Z_]+'")
                .allMatches(body)
                .map((m) => m.group(0))
                .toList(),
            ["'${entry.value.$1}'"],
            reason: entry.key);
        expect(body, contains(entry.value.$2), reason: entry.key);
        expect(
            body,
            contains(
                "'USER',\n    p_user_id,\n    v_guard->>'full_name',\n    v_reason,"),
            reason:
                '${entry.key}: the target is the validated id; the label is the name');
      }
    });

    test('no event can carry an address, a password or any free-form detail',
        () {
      for (final body in writers.values) {
        // the body, not the header: the function names say `email`, the bodies never read one
        // (`p_after_email_change` is a flag about the mail, not an address)
        final text = blank(body.substring(body.indexOf(r'as $$')))
            .replaceAll('p_after_email_change', '');
        expect(text, isNot(contains('email')),
            reason: 'the writers never read or store an address');
        expect(text, isNot(contains('password')));
        expect(text, isNot(contains('auth.')));
      }
    });

    test('the reason is required and bounded in every writer', () {
      for (final entry in writers.entries) {
        final body = entry.value;
        expect(
            body,
            contains(
                "v_reason text := nullif(btrim(coalesce(p_reason, '')), '');"),
            reason: entry.key);
        expect(body,
            contains('if v_reason is null or char_length(v_reason) > 500 then'),
            reason: entry.key);
        expect(at(body, "raise exception 'INVALID_REASON'"),
            lessThan(at(body, 'record_admin_audit(')),
            reason: entry.key);
      }
    });

    test(
        'the audit action list gains exactly the three names and keeps every other',
        () {
      final before = actionsOf(load(path0102));
      final after = actionsOf(sql);
      expect(after.difference(before),
          {'USER_EMAIL_CHANGED', 'USER_RECOVERY_SENT', 'USER_PASSWORD_SET'});
      expect(before.difference(after), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('the rollback', () {
    test(
        'it refuses, before changing anything, once an event of the new kinds exists',
        () {
      final text = code(rollback);
      final refusal =
          at(text, "raise exception 'ROLLBACK_REFUSED_AUTH_EVENTS_EXIST'");
      final firstChange = at(text, RegExp(r'\b(drop|alter|create)\b'));
      expect(refusal, lessThan(firstChange));
      for (final action in [
        'USER_EMAIL_CHANGED',
        'USER_RECOVERY_SENT',
        'USER_PASSWORD_SET'
      ]) {
        expect(text, contains("'$action'"));
      }
    });

    test(
        'it drops the five functions and puts 0102\'s action list back verbatim',
        () {
      for (final fn in [
        'admin_record_user_password_set(uuid, text)',
        'admin_record_user_recovery_sent(uuid, text, boolean)',
        'admin_record_user_email_changed(uuid, text)',
        'admin_check_user_auth_action(uuid, text, text)',
        'admin_user_auth_guard(uuid)',
      ]) {
        expect(rollback, contains('drop function if exists public.$fn;'),
            reason: fn);
      }
      expect(actionsOf(rollback), actionsOf(load(path0102)));
      expect(code(rollback), isNot(contains('delete from')));
    });
  });

  // ---------------------------------------------------------------------------
  group('the verification script', () {
    final text = blank(code(verify));

    test('it is one read-only statement', () {
      expect(';'.allMatches(text).length, 1);
      expect(
        text,
        isNot(matches(RegExp(
            r'\b(insert|update|delete|create|drop|alter|grant|revoke|truncate|set_config|perform)\b'))),
      );
    });

    test(
        'it pins the five bodies, and checks the list, the grants and the data',
        () {
      expect(RegExp(r"src_md5 = '[0-9a-f]{32}'").allMatches(verify).length, 5);
      expect(verify,
          contains('the audit action list holds exactly the ten actions'));
      expect(verify,
          contains('record_admin_audit is still executable by no client role'));
      expect(
          verify, contains('no event of the three kinds carries an address'));
    });
  });

  // ---------------------------------------------------------------------------
  group('the admin-user-auth Edge Function', () {
    final adapter =
        load('../app/lib/infrastructure/supabase/supabase_admin_adapter.dart');

    test('the adapter invokes it by the name it is deployed under', () {
      expect(adapter, contains("'admin-user-auth'"));
      expect(Directory('../supabase/functions/admin-user-auth').existsSync(),
          isTrue);
    });

    test('it calls the functions this migration defines, with their parameters',
        () {
      for (final name in [
        'admin_check_user_auth_action',
        ...writerNames,
      ]) {
        expect(edge, contains('"$name"'), reason: name);
        expect(statements, contains('function public.$name('), reason: name);
      }
      expect(edge, contains('p_user_id: userId'));
      expect(edge, contains('p_action: SQL_ACTION[action]'));
      expect(edge, contains('p_new_email: newEmail'));
      expect(edge, contains('p_after_email_change'));
      expect(edge, isNot(contains('record_admin_audit')),
          reason: 'only the action-specific writers are called');
    });

    test(
        'every database call is made as the caller; the service role reaches one URL',
        () {
      expect(edgeCode, contains('rpc(fetchFn, env, name, args, jwt)'));
      expect(edgeCode, isNot(contains('env.serviceKey, ')));
      expect('env.serviceKey'.allMatches(edgeCode).length, 2,
          reason: 'apikey and bearer of the one Admin API call');
      final admin = at(edgeCode, '/auth/v1/admin/users/\${id}');
      expect(
          edgeCode
              .substring(edgeCode.lastIndexOf('async function', admin))
              .startsWith('async function adminUpdate'),
          isTrue);
      expect('/auth/v1/admin/'.allMatches(edgeCode).length, 1,
          reason: 'no other Admin API path is reachable');
      expect('fetchFn('.allMatches(edgeCode).length, 3,
          reason: 'rpc, the Admin update, the recovery request');
    });

    test('the Admin API body is one of two fixed shapes, never the request',
        () {
      expect(
          edgeCode,
          contains(
              'payload: { email: string; email_confirm: true } | { password: string }'));
      expect(edgeCode, contains('{ email, email_confirm: true }'));
      expect(edgeCode, contains('{ password },'));
      expect(edgeCode, isNot(matches(RegExp(r'JSON\.stringify\(raw'))));
      expect(edgeCode, isNot(contains('...raw')));
    });

    test('the actor is never read from the request', () {
      final read = RegExp(r'raw\["([a-z_]+)"\]')
          .allMatches(edgeCode)
          .map((m) => m.group(1))
          .toSet();
      expect(read, {
        'action',
        'user_id',
        'reason',
        'redirect_to',
        'new_email',
        'password',
      });
    });

    test('the password and the addresses are in no log', () {
      for (final line
          in edgeCode.split('\n').where((l) => l.contains('console.'))) {
        expect(
            line,
            isNot(matches(RegExp(
                r'\$\{\s*(password|newEmail|email|normalised|current|jwt|env\.|raw|body)'))),
            reason: line);
        expect(line, isNot(contains('console.log')), reason: line);
      }
      expect('console.'.allMatches(edgeCode).length, greaterThan(0));
    });

    test(
        'the recovery email is the standard one: the public endpoint, no code challenge',
        () {
      expect(edgeCode, contains('/auth/v1/recover?redirect_to='));
      expect(edgeCode, contains('apikey: env.anonKey'));
      expect(edgeCode, isNot(contains('code_challenge')));
      expect(edgeCode, isNot(contains('generate_link')));
    });

    test('the tokens it passes through are raised by the database', () {
      for (final token in [
        'NOT_AUTHORIZED',
        'CANNOT_MODIFY_SELF',
        'CANNOT_MODIFY_SYSTEM_ADMIN',
        'USER_NOT_FOUND',
        'GOOGLE_LINKED',
        'EMAIL_TAKEN',
        'EMAIL_UNCHANGED',
        'INVALID_EMAIL',
        'NO_EMAIL',
        'INVALID_ACTION',
        'INVALID_REASON',
      ]) {
        expect(statements, contains("raise exception '$token'"), reason: token);
        expect(edge, contains('$token:'), reason: '$token has a status');
      }
    });

    test('the password rule is the application\'s own', () {
      final auth = load('../app/lib/features/auth/auth_service.dart');
      expect(auth, contains('static const int minimumPasswordLength = 8;'));
      expect(edge, contains('const PASSWORD_MIN = 8;'));
      expect(edge, contains('const PASSWORD_MAX_BYTES = 72;'));
    });
  });
}
