import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/analytics/analytics_models.dart';
import 'package:go_play/features/teams/team_generation_settings.dart';
import 'package:go_play/infrastructure/supabase/supabase_failure_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Static contract for migration 0091 (UAT stabilization, round 1).
///
/// The migration is not applied anywhere by this suite and cannot be executed
/// from a widget test, so these assertions read the file. They pin what it may
/// and may not do before it is reviewed for the shared Supabase project:
/// the two activity events and their target, the retention function that is
/// defined but never run or scheduled, and the three lifecycle relaxations.
void main() {
  const path = '../supabase/migrations/0091_uat_stabilization_round1.sql';
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');

  // Comment lines stripped: the prose names what the SQL refuses to do.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  // And with every string literal blanked, for questions about what executes.
  final executable = statements
      .split('\n')
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  String flat(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

  String functionBody(String name) {
    final start =
        statements.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('$name is not created');
    final end = statements.indexOf('\n\$\$;', start);
    if (end < 0) throw StateError('$name body is not closed');
    return statements.substring(start, end);
  }

  group('the file', () {
    test('is 0091, once, and the CLI timestamp name was reconciled', () {
      final names = [
        for (final entry in Directory('../supabase/migrations').listSync())
          entry.uri.pathSegments.last,
      ];
      expect(names.where((n) => n.startsWith('0091')),
          ['0091_uat_stabilization_round1.sql']);
      expect(names.where((n) => RegExp(r'^\d{14}_').hasMatch(n)), isEmpty);
    });

    test('alters no football history table and deletes from none', () {
      for (final table in const [
        'matches',
        'match_results',
        'match_goals',
        'match_team_assignments',
        'match_registrations',
        'rating_history',
        'user_ratings',
        'player_statistics',
        'community_statistics',
        'team_of_period_awards',
        'team_of_period_snapshots',
      ]) {
        expect(executable, isNot(contains('alter table public.$table ')),
            reason: table);
        expect(executable, isNot(contains('delete from public.$table ')),
            reason: table);
        expect(executable, isNot(contains('delete from $table ')),
            reason: table);
        expect(executable, isNot(contains('truncate public.$table')),
            reason: table);
        expect(executable, isNot(contains('truncate table public.$table')),
            reason: table);
      }
    });
  });

  group('activity: profile_viewed and player_statistics_viewed', () {
    test('the CHECK carries both new names and every earlier one', () {
      final check = statements.substring(
        statements.indexOf('add constraint product_events_event_name_check'),
        statements.indexOf(
            'drop constraint if exists product_events_target_shape_check'),
      );
      for (final event in ProductEvent.values) {
        expect(check, contains("'${event.wireName}'"), reason: event.name);
      }
      // Wave 3's own event is kept in the table's list...
      expect(check, contains("'public_link_signup_completed'"));
      expect(RegExp("'[a-z_]+'").allMatches(check).length, 14);
    });

    test('the writer accepts them, and still cannot write the signup event',
        () {
      final body = functionBody('record_product_event');
      final guard = body.substring(
        body.indexOf('if p_event_name is null or p_event_name not in ('),
        body.indexOf("raise exception 'INVALID_ANALYTICS_EVENT'"),
      );
      expect(guard, contains("'profile_viewed'"));
      expect(guard, contains("'player_statistics_viewed'"));
      expect(guard, isNot(contains("'public_link_signup_completed'")));
      expect(RegExp("'[a-z_]+'").allMatches(guard).length,
          ProductEvent.values.length);
    });

    test('the enum names are the two the database accepts', () {
      expect(ProductEvent.profileViewed.wireName, 'profile_viewed');
      expect(ProductEvent.playerStatisticsViewed.wireName,
          'player_statistics_viewed');
      expect(ProductEvent.fromWireName('profile_viewed'),
          ProductEvent.profileViewed);
      expect(ProductEvent.fromWireName('player_statistics_viewed'),
          ProductEvent.playerStatisticsViewed);
    });

    test('target_user_id is nullable, has no foreign key and no snapshot', () {
      expect(statements,
          contains('add column if not exists target_user_id uuid;'));
      final flatStatements = flat(executable);
      expect(flatStatements, isNot(contains('target_user_id uuid not null')));
      expect(flatStatements, isNot(contains('references public.users')));
      expect(flatStatements, isNot(contains('references users')));
      // No name or email is copied onto the event: the one column added to
      // product_events is the id.
      final added = RegExp(r'add column if not exists ([a-z_]+)')
          .allMatches(flatStatements)
          .map((m) => m.group(1))
          .toList();
      expect(added, ['target_user_id']);
      expect(flatStatements, isNot(contains('target_email')));
    });

    test('a view always names a target, and nothing else does', () {
      final check = flat(statements.substring(
        statements.indexOf('add constraint product_events_target_shape_check'),
        statements
            .indexOf('drop function if exists public.record_product_event'),
      ));
      expect(
          check,
          contains(
              "event_name in ('profile_viewed', 'player_statistics_viewed') "
              'and target_user_id is not null'));
      expect(
          check,
          contains(
              "event_name not in ('profile_viewed', 'player_statistics_viewed') "
              'and target_user_id is null'));
    });

    test('record_product_event is replaced, not overloaded', () {
      expect(
        flat(statements),
        contains('drop function if exists public.record_product_event( '
            'text, uuid, uuid, text, text, text, text );'),
      );
      expect(
        'create or replace function public.record_product_event('
            .allMatches(statements)
            .length,
        1,
      );
      final body = flat(functionBody('record_product_event'));
      expect(
          body, contains('p_target_user_id uuid default null ) returns void'));
      // The actor is still the session; no parameter names one.
      expect(body, contains('v_user_id := auth.uid();'));
      expect(body, isNot(contains('p_user_id')));
      expect(body, contains("raise exception 'INVALID_ANALYTICS_TARGET'"));
    });

    test('its privileges are restated after the drop', () {
      final grants = flat(statements);
      const signature =
          'public.record_product_event(text, uuid, uuid, text, text, text, text, uuid)';
      expect(grants,
          contains('revoke execute on function $signature from anon, public;'));
      expect(grants,
          contains('grant execute on function $signature to authenticated;'));
      expect(grants,
          contains('grant execute on function $signature to service_role;'));
      expect(grants, isNot(contains('$signature to anon')));
    });

    test('the Admin timeline returns the viewed player and the share detail',
        () {
      expect(
          statements,
          contains(
              'drop function if exists public.admin_user_activity_timeline(uuid, integer);'));
      final body = flat(functionBody('admin_user_activity_timeline'));
      for (final column in const [
        'target_user_id uuid',
        'target_user_name text',
        'share_type text',
        'source text',
      ]) {
        expect(body, contains(column), reason: column);
      }
      // LEFT, so a deleted target leaves the event standing.
      expect(body, contains('left join users tu on tu.id = pe.target_user_id'));
      expect(body, isNot(contains('inner join')));
      expect(body, isNot(contains('metadata')));
      expect(body, contains("if not is_system_admin() then raise exception"));

      final grants = flat(statements);
      expect(
          grants,
          contains('revoke execute on function '
              'public.admin_user_activity_timeline(uuid, integer) '
              'from anon, public;'));
      expect(
          grants,
          contains('grant execute on function '
              'public.admin_user_activity_timeline(uuid, integer) '
              'to authenticated;'));
    });

    test('the client sends a target only when there is one', () {
      final adapter = File(
        'lib/infrastructure/supabase/supabase_analytics_adapter.dart',
      ).readAsStringSync();
      expect(
          adapter,
          contains(
              "if (targetUserId != null) 'p_target_user_id': targetUserId"));
    });

    test('share types resolve for the timeline, and an unknown one is null',
        () {
      for (final type in ShareType.values) {
        expect(ShareType.fromWireName(type.wireName), type);
      }
      expect(ShareType.fromWireName(null), isNull);
      expect(ShareType.fromWireName('something_later'), isNull);
    });
  });

  group('retention: logic only, never run, never scheduled', () {
    final body = functionBody('run_retention_cleanup_v1');
    final flatBody = flat(body);

    // table -> (timestamp column, interval, cutoff variable)
    const approved = {
      'product_events': ('created_at', '12 months', 'v_product_events_cutoff'),
      'client_runtime_events': (
        'occurred_at',
        '90 days',
        'v_client_runtime_cutoff'
      ),
      'push_dispatch_outcomes': (
        'occurred_at',
        '90 days',
        'v_push_outcomes_cutoff'
      ),
      'notifications': ('created_at', '90 days', 'v_notifications_cutoff'),
      'match_registration_events': (
        'occurred_at',
        '24 months',
        'v_registration_events_cutoff'
      ),
      'community_membership_events': (
        'occurred_at',
        '24 months',
        'v_membership_events_cutoff'
      ),
      'admin_audit_log': ('created_at', '24 months', 'v_admin_audit_cutoff'),
      'btge_generation_runs': (
        'generated_at',
        '12 months',
        'v_btge_runs_cutoff'
      ),
      'telemetry_ingest_windows': (
        'minute_bucket',
        '1 day',
        'v_telemetry_windows_cutoff'
      ),
    };

    test('each approved cutoff is pinned exactly', () {
      approved.forEach((table, rule) {
        final (column, interval, variable) = rule;
        expect(flatBody,
            contains("$variable timestamptz := v_now - interval '$interval';"),
            reason: table);
        expect(
          RegExp('delete from public\\.$table (\\w+) where \\1\\.$column '
                  '< $variable;')
              .hasMatch(flatBody),
          isTrue,
          reason: '$table must be deleted by $column < $variable',
        );
      });
    });

    test('every cutoff is measured from one now()', () {
      expect(flatBody, contains('v_now timestamptz := now();'));
      expect(RegExp(r'now\(\)').allMatches(body).length, 1,
          reason: 'a single reference time for the whole run');
    });

    test('it deletes from exactly the nine approved tables', () {
      final deleted = RegExp(r'delete from public\.([a-z_]+)')
          .allMatches(body)
          .map((m) => m.group(1))
          .toSet();
      expect(deleted, approved.keys.toSet());
    });

    test('Last Seen is rolled up before product_events is deleted', () {
      final rollup =
          body.indexOf('insert into public.product_activity_last_seen as s');
      final delete = body.indexOf('delete from public.product_events pe');
      expect(rollup, greaterThan(0));
      expect(rollup, lessThan(delete));
      expect(
          flatBody,
          contains(
              'set last_seen_at = greatest(s.last_seen_at, excluded.last_seen_at)'));
    });

    test('no client may run it', () {
      final grants = flat(statements);
      expect(
          grants,
          contains(
              'revoke execute on function public.run_retention_cleanup_v1() '
              'from public, anon, authenticated;'));
      expect(
          grants,
          contains(
              'grant execute on function public.run_retention_cleanup_v1() '
              'to service_role;'));
      expect(grants, isNot(contains('run_retention_cleanup_v1() to anon')));
      expect(grants,
          isNot(contains('run_retention_cleanup_v1() to authenticated')));
      expect(flatBody, contains('security definer'));
      expect(flatBody, contains("set search_path = ''"));
    });

    test('no dynamic SQL and no external call', () {
      expect(body, isNot(contains('execute ')));
      expect(body, isNot(contains('format(')));
      for (final call in const ['http', 'net.', 'pg_net', 'dblink']) {
        expect(body, isNot(contains(call)), reason: call);
      }
    });

    test('the migration neither schedules it nor runs it', () {
      final lower = executable.toLowerCase();
      expect(lower, isNot(contains('cron')));
      expect(lower, isNot(contains('create extension')));
      expect(lower, isNot(contains('schedule')));
      // Named only where it is created, described and granted.
      final mentions =
          RegExp(r'run_retention_cleanup_v1\(\)').allMatches(statements).length;
      expect(mentions, 4);
      expect(statements, isNot(contains('perform public.run_retention')));
      expect(statements, isNot(contains('select public.run_retention')));
      expect(statements, isNot(contains('from public.run_retention')));
    });

    test('adds no index', () {
      expect(executable, isNot(contains('create index')));
      expect(executable, isNot(contains('create unique index')));
    });

    test('the Last Seen rollup is unreachable by any client', () {
      final flatStatements = flat(statements);
      expect(
          flatStatements,
          contains(
              'alter table public.product_activity_last_seen enable row level security;'));
      expect(
          flatStatements,
          contains('revoke all on table public.product_activity_last_seen '
              'from anon, authenticated, public;'));
      expect(
          flatStatements,
          contains(
              'grant select on table public.product_activity_last_seen to service_role;'));
      expect(flatStatements, isNot(contains('create policy')));
    });

    test('both Last Seen readers read through the rollup', () {
      for (final name in const [
        'admin_user_activity_summary',
        'admin_analytics_users_v2',
      ]) {
        final reader = flat(functionBody(name));
        expect(reader, contains('greatest('), reason: name);
        expect(reader, contains('from product_activity_last_seen ls'),
            reason: name);
        expect(
            reader, contains("if not is_system_admin() then raise exception"),
            reason: name);
      }
    });
  });

  group('match lifecycle', () {
    test('a normal match may be active; one that has ended is refused', () {
      final body = flat(functionBody('create_match'));
      expect(
          body,
          contains(
              "if p_end_at <= now() then raise exception 'MATCH_ALREADY_ENDED';"));
      expect(body, isNot(contains("'START_IN_PAST'")));
      // The historical path is exactly as it was.
      expect(
          body,
          contains(
              "if v_historical then if p_end_at > now() then raise exception 'HISTORICAL_NOT_PAST';"));
      expect(
          body,
          contains('if not has_community_role(p_community_id, auth.uid(), '
              "'admin') then raise exception 'NOT_AUTHORIZED';"));
    });

    test('the client asks the same question before it sends', () {
      final screen = File('lib/features/matches/create_match_screen.dart')
          .readAsStringSync();
      expect(
          screen,
          contains(
              'if (!end.isAfter(DateTime.now())) return l10n.matchAlreadyEndedError;'));
      expect(
          SupabaseFailureMapper.from(const PostgrestException(
                  message: 'error: MATCH_ALREADY_ENDED', code: 'P0001'))
              .reason,
          FailureReason.matchAlreadyEnded);
    });

    test('nobody registers into a played match; kickoff locks only self', () {
      final body = functionBody('register_player_in_match');
      final flatReg = flat(body);
      final historical = body.indexOf("raise exception 'MATCH_HISTORICAL'");
      final closed = body.indexOf("raise exception 'MATCH_CLOSED'");
      final locked = body.indexOf("raise exception 'MATCH_LOCKED'");
      expect(historical, lessThan(closed));
      expect(closed, lessThan(locked));
      // MATCH_CLOSED is for every caller: not inside the time-lock flag.
      expect(
          flatReg,
          contains("if v_match.status = 'completed' or v_match.end_at <= now() "
              "then raise exception 'MATCH_CLOSED'; end if;"));
      expect(
          flatReg,
          contains('if p_enforce_time_lock and v_match.start_at <= now() then '
              "raise exception 'MATCH_LOCKED';"));
      // Every other rule is still there.
      for (final token in const [
        'COMMUNITY_INACTIVE',
        'ACCOUNT_SUSPENDED',
        'NOT_COMMUNITY_MEMBER',
        'ALREADY_REGISTERED',
        'REGISTRATION_CLOSED',
        'OVERLAPPING_MATCH',
      ]) {
        expect(flatReg, contains("raise exception '$token'"), reason: token);
      }
      expect(flatReg, contains('perform rebalance_roster(p_match_id);'));
      // Still reachable only through its two wrappers.
      final grants = flat(statements);
      expect(
          grants,
          contains(
              'revoke execute on function public.register_player_in_match(uuid, uuid, boolean) '
              'from anon, authenticated, public;'));
      expect(
          grants,
          contains(
              'grant execute on function public.register_player_in_match(uuid, uuid, boolean) '
              'to service_role;'));
    });

    test('keeps one canonical registration helper and existing wrappers', () {
      final flatStatements = flat(statements);
      const obsoleteDrop =
          'drop function if exists public.register_player_in_match(uuid, uuid);';
      const canonicalCreate =
          'create or replace function public.register_player_in_match(';

      expect(flatStatements, contains(obsoleteDrop));
      expect(
        statements.indexOf(
            'drop function if exists public.register_player_in_match(uuid, uuid);'),
        lessThan(statements.indexOf(canonicalCreate)),
      );
      expect(
        RegExp(
          r'create or replace function public\.register_player_in_match\s*\(',
        ).allMatches(statements),
        hasLength(1),
      );
      expect(
        flatStatements,
        isNot(contains(
            'drop function if exists public.register_player_in_match(uuid, uuid, boolean);')),
      );

      // 0091 changes the shared transaction only; the authorization wrappers
      // remain the effective definitions from 0065.
      expect(
          statements, isNot(contains('function public.register_for_match(')));
      expect(statements,
          isNot(contains('function public.admin_add_player_to_match(')));

      final wrapperMigration = File(
        '../supabase/migrations/0065_platform_admin_community_suspension_enforcement.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final flatWrappers = flat(wrapperMigration);
      expect(
        flatWrappers,
        contains(
            'return register_player_in_match(p_match_id, auth.uid(), true);'),
      );
      expect(
        flatWrappers,
        contains(
            'return register_player_in_match(p_match_id, p_user_id, false);'),
      );

      for (final entry in Directory('../supabase/migrations').listSync()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        final match = RegExp(r'^(\d{4})_').firstMatch(name);
        if (match == null) continue;
        final number = int.parse(match.group(1)!);
        if (number <= 65 || number >= 91) continue;
        final later = entry.readAsStringSync().replaceAll('\r\n', '\n');
        expect(
          later,
          isNot(contains(
              'create or replace function public.register_for_match(')),
          reason: name,
        );
        expect(
          later,
          isNot(contains(
              'create or replace function public.admin_add_player_to_match(')),
          reason: name,
        );
      }
    });

    test('a completed match reopens only without a result and not historical',
        () {
      final body = flat(functionBody('update_match'));
      expect(
          body,
          contains('if v_played then if not v_becomes_completed then '
              'if v_match.is_historical or exists ( select 1 from match_results '
              "mr where mr.match_id = p_match_id ) then raise exception "
              "'MATCH_COMPLETED'; end if; v_reopening := true;"));
      // Active -> future is still refused.
      expect(
          body,
          contains(
              "if not (v_becomes_completed or v_becomes_active) then raise exception 'MATCH_LOCKED';"));
    });

    test('a reopen clears the confirmation and keeps the lineup revision', () {
      final body = functionBody('update_match');
      final reopen = flat(body.substring(
        body.indexOf('elsif v_reopening then'),
        body.indexOf('elsif v_becomes_active then'),
      ));
      expect(
          reopen,
          contains(
              'update match_participation_state set confirmed_revision = null, '
              'confirmed_at = null, confirmed_by = null'));
      expect(reopen, isNot(contains('lineup_revision')));
      // Status restored by count; registrations and lineup untouched.
      expect(reopen, contains("then 'full' else 'open' end"));
      for (final forbidden in const [
        'rebalance_roster',
        'recompute_match_status',
        'reconcile_match_lineup',
        'delete from',
        'match_team_assignments',
        'update match_registrations',
      ]) {
        expect(reopen, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('ratings, statistics, goals and results are never touched', () {
      final body = flat(functionBody('update_match'));
      for (final forbidden in const [
        'detach_match_effects',
        'attach_match_effects',
        'player_statistics',
        'rating',
        'match_goals',
        'delete from match_results',
        'update match_results',
      ]) {
        expect(body, isNot(contains(forbidden)), reason: forbidden);
      }
      // A completed edit that stays completed is exactly as before.
      expect(
          body,
          contains("if v_becomes_completed then update matches set status = "
              "'completed' where id = p_match_id and status <> 'completed';"));
      expect(
          executable, isNot(contains('function public.record_match_result(')));
    });
  });

  group('recent six', () {
    test('BTGE history lookback is still exactly five', () {
      expect(approvedHistoryLookback, 5);
    });
  });
}
