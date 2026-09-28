import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static contract for migration 0090 (Wave 4 operational hardening).
///
/// Reviewed before it is applied to the shared live project, so what it may and
/// may not do is pinned here against the file itself.
void main() {
  const path = '../supabase/migrations/0090_wave4_operational_hardening.sql';
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');

  // Comment lines stripped: the prose names what the SQL refuses to store.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');
  final flat = statements.replaceAll(RegExp(r'\s+'), ' ');

  String tableBody(String name) {
    final start = statements.indexOf('create table public.$name (');
    if (start < 0) throw StateError('$name is not created');
    final end = statements.indexOf('\n);', start);
    if (end < 0) throw StateError('$name table body is not closed');
    return statements.substring(start, end);
  }

  String functionBody(String name) {
    final start =
        statements.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('$name is not created');
    final end = statements.indexOf('\n\$\$;', start);
    if (end < 0) throw StateError('$name body is not closed');
    return statements.substring(start, end);
  }

  String flatFunction(String name) =>
      functionBody(name).replaceAll(RegExp(r'\s+'), ' ');

  Set<String> parametersOf(String name) {
    final body = functionBody(name);
    final close = body.indexOf(')\nreturns');
    return RegExp(r'\b(p_[a-z_]+)\b')
        .allMatches(body.substring(0, close))
        .map((m) => m.group(1)!)
        .toSet();
  }

  List<String> columnsOf(String table) =>
      RegExp(r'^\s{2}([a-z_]+)\s', multiLine: true)
          .allMatches(tableBody(table))
          .map((m) => m.group(1)!)
          .where((name) => name != 'constraint')
          .toList();

  // Names that must never be a column of an operational evidence table.
  const identityColumns = [
    'user_id',
    'email',
    'phone',
    'full_name',
    'name',
    'ip',
    'ip_address',
    'device_id',
    'cookie',
    'session_id',
    'token',
    'push_token',
    'message',
    'body',
    'stack',
    'stack_trace',
    'error_message',
  ];

  test('0090 is the one Wave 4 migration', () {
    final names = Directory('../supabase/migrations')
        .listSync()
        .map((entry) => entry.uri.pathSegments.last)
        .toList();
    expect(names.where((n) => n.startsWith('0090')),
        ['0090_wave4_operational_hardening.sql']);
    expect(names.where((n) => RegExp(r'^\d{14}_').hasMatch(n)), isEmpty,
        reason: 'the CLI timestamp name was reconciled, not kept beside it');
  });

  test('creates exactly the three Wave 4 tables', () {
    final created = RegExp(r'create table public\.([a-z_]+) \(')
        .allMatches(statements)
        .map((m) => m.group(1))
        .toSet();
    expect(created, {
      'push_dispatch_outcomes',
      'telemetry_ingest_windows',
      'client_runtime_events',
    });
  });

  test('adds no foreign key, policy or backfill anywhere', () {
    expect(flat, isNot(contains('foreign key (')));
    expect(RegExp(r'references\s+public\.').hasMatch(flat), isFalse);
    expect(flat, isNot(contains('create policy')));
    expect(statements, isNot(contains('generate_series')));
    expect(
        RegExp(r'insert into public\.[a-z_]+ (\([^)]*\) )?select')
            .hasMatch(flat),
        isFalse);
    expect(RegExp(r'\bupdate public\.').hasMatch(flat), isFalse);
  });

  group('push dispatch outcomes', () {
    test('has only transport columns: no user, token, message or response', () {
      expect(columnsOf('push_dispatch_outcomes'), [
        'attempt_no',
        'notification_id',
        'occurred_at',
        'outcome',
        'priority',
        'token_count',
        'sent_count',
        'stale_count',
        'failed_count',
      ]);
      for (final column in identityColumns) {
        expect(columnsOf('push_dispatch_outcomes'), isNot(contains(column)));
      }
      expect(
          tableBody('push_dispatch_outcomes'),
          contains(
              'attempt_no bigint generated always as identity primary key'));
    });

    test('bounds outcomes, priorities and counts', () {
      final body =
          tableBody('push_dispatch_outcomes').replaceAll(RegExp(r'\s+'), ' ');
      expect(
        body,
        contains("check (outcome in ( 'not_found', 'suppressed', 'no_devices', "
            "'unrenderable', 'dispatched', 'internal_error' ))"),
      );
      expect(
          body,
          contains(
              "check (priority is null or priority in ('high', 'medium', 'low'))"));
      expect(
          body,
          contains('token_count >= 0 and sent_count >= 0 and stale_count >= 0 '
              'and failed_count >= 0'));
      expect(
        body,
        contains("when outcome = 'dispatched' then token_count >= 1 and "
            'token_count = sent_count + stale_count + failed_count else '
            'sent_count = 0 and stale_count = 0 and failed_count = 0 end'),
      );
    });

    test('is RLS-closed to clients, readable by the service role only', () {
      expect(
          flat,
          contains(
              'alter table public.push_dispatch_outcomes enable row level security;'));
      expect(
          flat,
          contains(
              'revoke all on table public.push_dispatch_outcomes from anon, authenticated, public;'));
      expect(
          flat,
          contains(
              'revoke all on sequence public.push_dispatch_outcomes_attempt_no_seq from anon, authenticated, public;'));
      expect(
          flat,
          contains(
              'grant select on table public.push_dispatch_outcomes to service_role;'));
      expect(
        RegExp(r'grant [^;]*on table public\.push_dispatch_outcomes to [^;]*(anon|authenticated)')
            .hasMatch(flat),
        isFalse,
      );
    });

    test('the writer is service-role only and validates the closed shape', () {
      expect(parametersOf('record_push_dispatch_outcome_v1'), {
        'p_notification_id',
        'p_outcome',
        'p_priority',
        'p_token_count',
        'p_sent_count',
        'p_stale_count',
        'p_failed_count',
      });
      final body = flatFunction('record_push_dispatch_outcome_v1');
      expect(body, contains('returns void'));
      expect(body, contains('security definer'));
      expect(body, contains("set search_path = ''"));
      expect(body, contains("raise exception 'INVALID_PUSH_OUTCOME'"));
      expect(
          body,
          contains(
              'p_token_count <> p_sent_count + p_stale_count + p_failed_count'));
      // It never reads notification content -- it reads nothing at all.
      expect(body, isNot(contains('notifications')));
      expect(body, isNot(contains(' from ')));
      expect(
        flat,
        contains(
            'revoke execute on function public.record_push_dispatch_outcome_v1( '
            'uuid, text, text, integer, integer, integer, integer ) '
            'from public, anon, authenticated;'),
      );
      expect(
        flat,
        contains(
            'grant execute on function public.record_push_dispatch_outcome_v1( '
            'uuid, text, text, integer, integer, integer, integer ) to service_role;'),
      );
    });
  });

  group('client runtime evidence', () {
    test('has no identity, PII or raw error field', () {
      expect(columnsOf('client_runtime_events'), [
        'event_no',
        'run_id',
        'event_type',
        'occurred_at',
        'platform',
        'app_version',
        'build_sha',
        'category',
        'fingerprint',
        'context_code',
      ]);
      for (final column in identityColumns) {
        expect(columnsOf('client_runtime_events'), isNot(contains(column)));
      }
    });

    test('bounds every value and constrains both event shapes', () {
      final body =
          tableBody('client_runtime_events').replaceAll(RegExp(r'\s+'), ' ');
      expect(body, contains("check (event_type in ('run_started', 'error'))"));
      expect(body, contains("check (platform in ('web', 'android', 'ios'))"));
      expect(
          body,
          contains(
              r"check (app_version ~ '^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$')"));
      expect(body, contains(r"check (build_sha ~ '^[0-9a-f]{40}$')"));
      expect(body,
          contains("category in ('flutter_framework', 'platform_unhandled')"));
      expect(body, contains(r"fingerprint ~ '^[0-9a-f]{16}$'"));
      expect(body, contains(r"context_code ~ '^[A-Za-z0-9_]{1,64}$'"));
      expect(
        body,
        contains("( event_type = 'run_started' and category is null and "
            'fingerprint is null and context_code is null ) or ( '
            "event_type = 'error' and category is not null and fingerprint is "
            'not null )'),
      );
    });

    test('allows exactly one run_started per run and indexes the analysis', () {
      expect(
        flat,
        contains(
            'create unique index client_runtime_events_one_start_per_run_key '
            'on public.client_runtime_events (run_id) '
            "where event_type = 'run_started';"),
      );
      expect(
          flat,
          contains(
              'on public.client_runtime_events (event_type, occurred_at desc);'));
      expect(
        flat,
        contains('on public.client_runtime_events ( fingerprint, app_version, '
            "platform, occurred_at desc ) where event_type = 'error';"),
      );
    });

    test('is RLS-closed to clients, with no client table grant', () {
      expect(
          flat,
          contains(
              'alter table public.client_runtime_events enable row level security;'));
      expect(
          flat,
          contains(
              'revoke all on table public.client_runtime_events from anon, authenticated, public;'));
      expect(
        RegExp(r'grant [^;]*on table public\.client_runtime_events to [^;]*(anon|authenticated)')
            .hasMatch(flat),
        isFalse,
      );
    });

    test('run start takes only platform, version and a Git SHA', () {
      expect(parametersOf('start_client_runtime_v1'),
          {'p_platform', 'p_app_version', 'p_build_sha'});
      final body = flatFunction('start_client_runtime_v1');
      expect(body, contains('returns uuid'));
      expect(body, contains("p_platform not in ('web', 'android', 'ios')"));
      expect(body,
          contains(r"p_app_version !~ '^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$'"));
      expect(body, contains(r"p_build_sha !~ '^[0-9a-f]{40}$'"));
      expect(
          body,
          contains(
              "if not public.consume_telemetry_budget_v1('client_run') then"));
      expect(body, contains('v_run_id := gen_random_uuid();'));
      expect(body, contains('return v_run_id;'));
      expect(body, contains("set search_path = ''"));
    });

    test('error report copies the build from the run and never accepts it', () {
      expect(parametersOf('report_client_error_v1'),
          {'p_run_id', 'p_category', 'p_fingerprint', 'p_context_code'});
      final body = flatFunction('report_client_error_v1');
      expect(
          body,
          contains(
              "where e.run_id = p_run_id and e.event_type = 'run_started';"));
      expect(body, contains("raise exception 'CLIENT_RUN_NOT_FOUND'"));
      expect(
          body, contains('v_run.platform, v_run.app_version, v_run.build_sha'));
      expect(
          body,
          contains(
              "if not public.consume_telemetry_budget_v1('client_error') then"));
      // The missing run is refused before any budget is consumed.
      expect(
          body.indexOf('CLIENT_RUN_NOT_FOUND'),
          lessThan(
              body.indexOf("consume_telemetry_budget_v1('client_error')")));
      expect(body, contains("set search_path = ''"));
    });

    test('both public writers revoke PUBLIC and grant the three roles', () {
      for (final signature in [
        'start_client_runtime_v1(text, text, text)',
        'report_client_error_v1(uuid, text, text, text)',
      ]) {
        expect(
            flat,
            contains(
                'revoke execute on function public.$signature from public;'));
        expect(
          flat,
          contains('grant execute on function public.$signature '
              'to anon, authenticated, service_role;'),
        );
      }
    });
  });

  group('telemetry circuit breaker', () {
    test('stores no caller identity', () {
      expect(columnsOf('telemetry_ingest_windows'),
          ['channel', 'minute_bucket', 'accepted_count']);
      expect(
          flat,
          contains(
              'constraint telemetry_ingest_windows_pkey primary key (channel, minute_bucket)'));
      expect(
          flat,
          contains(
              'alter table public.telemetry_ingest_windows enable row level security;'));
      expect(
          flat,
          contains(
              'revoke all on table public.telemetry_ingest_windows from anon, authenticated, public;'));
    });

    test('has fixed approved channels and limits that no caller supplies', () {
      expect(parametersOf('consume_telemetry_budget_v1'), {'p_channel'});
      final body = flatFunction('consume_telemetry_budget_v1');
      expect(body, contains("when 'acquisition_open' then 120"));
      expect(body, contains("when 'client_run' then 120"));
      expect(body, contains("when 'client_error' then 240"));
      expect(body, contains("raise exception 'INVALID_TELEMETRY_CHANNEL'"));
    });

    test('consumes one unit atomically and refuses at the limit', () {
      final body = flatFunction('consume_telemetry_budget_v1');
      expect(
        body,
        contains('on conflict (channel, minute_bucket) do update set '
            'accepted_count = w.accepted_count + 1 where w.accepted_count < v_limit '
            'returning w.accepted_count into v_accepted;'),
      );
      expect(body, contains('if v_accepted is null then return false;'));
      expect(body,
          contains("v_bucket timestamptz := date_trunc('minute', now());"));
      expect(body, contains("set search_path = ''"));
    });

    test('is not executable by any client role', () {
      expect(
        flat,
        contains(
            'revoke execute on function public.consume_telemetry_budget_v1(text) '
            'from public, anon, authenticated;'),
      );
      expect(
        RegExp(r'grant execute on function public\.consume_telemetry_budget_v1')
            .hasMatch(flat),
        isFalse,
      );
    });

    test('the Wave 3 anonymous writer keeps its signature and gains the budget',
        () {
      expect(parametersOf('record_anonymous_public_link_open'),
          {'p_kind', 'p_platform', 'p_app_version'});
      expect(
        flat,
        contains(
            'create or replace function public.record_anonymous_public_link_open( '
            'p_kind text, p_platform text default null, '
            'p_app_version text default null ) returns uuid'),
      );
      expect(
          statements, isNot(contains('record_anonymous_public_link_open_v2')));

      final body = flatFunction('record_anonymous_public_link_open');
      // The Wave 3 contract, unchanged.
      expect(
          body,
          contains(
              "if auth.uid() is not null then raise exception 'ANONYMOUS_ONLY';"));
      expect(body, contains("when 'player' then 'public_link_player'"));
      expect(body, contains("p_platform not in ('web', 'android')"));
      expect(body, contains('v_acquisition_id := gen_random_uuid();'));
      // And the breaker, before the insert.
      expect(
        body,
        contains(
            "if not public.consume_telemetry_budget_v1('acquisition_open') "
            "then raise exception 'TELEMETRY_RATE_LIMITED';"),
      );
      expect(body.indexOf("consume_telemetry_budget_v1('acquisition_open')"),
          lessThan(body.indexOf('insert into public.product_events')));
      // Same audience: anon + service_role, never authenticated.
      expect(
        flat,
        contains(
            'revoke execute on function public.record_anonymous_public_link_open(text, text, text) '
            'from public, authenticated;'),
      );
      expect(
        flat,
        contains(
            'grant execute on function public.record_anonymous_public_link_open(text, text, text) '
            'to anon, service_role;'),
      );
    });
  });

  test('every SECURITY DEFINER function pins an empty search_path', () {
    final definers = RegExp(
      r'create or replace function public\.([a-z0-9_]+)\([^$]*?security definer\s+set search_path = ([^\n]+)',
    ).allMatches(statements).toList();
    expect(definers.map((m) => m.group(1)).toSet(), {
      'record_push_dispatch_outcome_v1',
      'consume_telemetry_budget_v1',
      'record_anonymous_public_link_open',
      'start_client_runtime_v1',
      'report_client_error_v1',
    });
    for (final m in definers) {
      expect(m.group(2)!.trim(), "''", reason: m.group(1));
    }
  });
}
