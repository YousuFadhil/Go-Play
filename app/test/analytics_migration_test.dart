import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/analytics/analytics_models.dart';

/// What migration 0067 says — a static review of the file, not a runtime
/// result.
///
/// The migration has not been applied anywhere and cannot be executed from a
/// widget test, so these assertions read the text. That is a real limit and is
/// worth stating plainly: this suite proves the file says the right things, and
/// a live precheck is what proves the database does them. What it does catch is
/// the class of mistake that is invisible in review and expensive in
/// production — a privilege silently dropped, a backfill quietly added, a
/// timezone constant duplicated, an event name that stopped matching the enum.
void main() {
  final sql = File(
    '../supabase/migrations/0067_platform_admin_product_analytics.sql',
  ).readAsStringSync();

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with every SQL string literal blanked as well.
  ///
  /// A `comment on ...` body is a statement, not a comment line, and this
  /// migration's comments legitimately *name* the things it does not touch —
  /// "the legacy admin_delete_* RPCs hard-delete" is the reason the table has
  /// no foreign key. Asking "does this file reference admin_delete_" against
  /// the raw text would find that sentence and call it a violation. What
  /// matters is whether the migration *executes* anything against those, so the
  /// prose is removed before the question is asked.
  final executable = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  /// Just the `create table` body, for the questions that are only about the
  /// column definitions. `references` in particular appears legitimately in the
  /// `revoke` further down, so asking about it has to be scoped here.
  final tableBody = sql.substring(
    sql.indexOf('create table if not exists public.product_events ('),
    sql.indexOf('\n);'),
  );

  group('product_events is shaped as approved', () {
    test('carries exactly the ten approved event names, and no eleventh', () {
      // Sourced from the enum rather than retyped, so this test cannot drift
      // from the application while appearing to agree with it.
      for (final event in ProductEvent.values) {
        expect(
          tableBody,
          contains("'${event.wireName}'"),
          reason: '${event.name} is missing from the CHECK constraint',
        );
      }

      // And nothing else. Counted inside the constraint itself -- bounded at
      // the next column, so the platform CHECK below it is not swept in -- so
      // any name the enum does not have would push this past ten.
      final check = tableBody.substring(
        tableBody.indexOf('product_events_event_name_check'),
        tableBody.indexOf('community_id uuid,'),
      );
      final quoted = RegExp("'[a-z_]+'").allMatches(check).length;
      expect(quoted, ProductEvent.values.length);
    });

    test('platform admits null, web and android only', () {
      expect(
        tableBody,
        contains("check (platform is null or platform in ('web', 'android'))"),
      );
    });

    test('has no foreign key on the user, community or match id', () {
      // The legacy admin_delete_* RPCs hard-delete. A FK here would either
      // block one of them or silently rewrite the activity record.
      expect(tableBody, isNot(contains('references')));
      expect(tableBody, isNot(contains('on delete')));
    });

    test('records nothing that identifies a device or a person beyond the id',
        () {
      for (final forbidden in [
        'ip_address',
        'user_agent',
        'device_id',
        'fingerprint',
        'metadata',
        'jsonb',
        'session_id',
      ]) {
        expect(tableBody, isNot(contains(forbidden)),
            reason: 'the approved schema has no room for $forbidden');
      }
    });

    test('created_at is the database clock, not the caller', () {
      expect(tableBody, contains('created_at timestamptz not null default now()'));
    });

    test('indexes the four scans the Overview performs', () {
      for (final index in [
        'product_events (user_id, created_at desc)',
        'product_events (event_name, created_at desc)',
        'product_events (community_id, created_at desc)',
        'product_events (match_id, created_at desc)',
      ]) {
        expect(statements, contains(index));
      }
    });
  });

  group('no client reaches the table', () {
    test('row-level security is on', () {
      expect(statements,
          contains('alter table public.product_events enable row level security'));
    });

    test('and there is not a single policy', () {
      // RLS with no policy denies every client role every row for every
      // command. A policy here would be the one thing that could open it.
      expect(statements, isNot(contains('create policy')));
      expect(statements, isNot(contains('drop policy')));
    });

    test('direct table privileges are revoked from anon and authenticated', () {
      expect(
        statements,
        contains(
            'revoke all on public.product_events from anon, authenticated, public;'),
      );
      // Named individually as well, because `all` leaves a reader working out
      // what it covered -- and TRUNCATE is not filtered by RLS at all.
      expect(
        statements,
        contains('revoke select, insert, update, delete, truncate, references, trigger'),
      );
    });

    test('and no grant on the table follows', () {
      expect(statements, isNot(contains('grant select on public.product_events')));
      expect(statements, isNot(contains('grant insert on public.product_events')));
      expect(statements, isNot(contains('grant all on public.product_events')));
    });
  });

  group('record_product_event', () {
    test('takes the actor from auth.uid(), never from an argument', () {
      expect(statements, contains('v_user_id := auth.uid();'));
      // The vulnerability this rules out: a client-controlled id written into a
      // table the client cannot otherwise touch. Asked of the statements, not
      // of the file -- the comment above the function says there is no such
      // parameter, and that sentence is not a parameter.
      expect(statements, isNot(contains('p_user_id')));
    });

    test('refuses a caller with no session and a suspended one', () {
      expect(statements, contains("raise exception 'NOT_AUTHENTICATED'"));
      expect(statements, contains('if not is_current_user_active() then'));
      expect(statements, contains("raise exception 'ACCOUNT_SUSPENDED'"));
    });

    test('refuses an unapproved event name and platform', () {
      expect(statements, contains("raise exception 'INVALID_ANALYTICS_EVENT'"));
      expect(statements, contains("raise exception 'INVALID_ANALYTICS_PLATFORM'"));
    });

    test('inserts the derived user, and lets the column default set the time',
        () {
      expect(
        statements,
        contains('user_id, event_name, community_id, match_id, platform, app_version'),
      );
      expect(statements, contains('v_user_id,'));
      expect(statements, isNot(contains('created_at)')));
    });

    test('is executable by authenticated and service_role, and by nobody else',
        () {
      const fn = 'public.record_product_event(text, uuid, uuid, text, text)';
      expect(statements, contains('revoke execute on function\n  $fn\n  from anon, public;'));
      expect(statements, contains('grant execute on function\n  $fn\n  to authenticated;'));
      expect(
        statements,
        contains('grant execute on function\n  $fn\n  to service_role;'),
        reason: '0066 is the reminder: a privilege no migration wrote down is '
            'still a privilege a drop would take away.',
      );
    });
  });

  group('admin_analytics_overview', () {
    /// Everything from the function's own header to the end of its body.
    final overview = sql.substring(
      sql.indexOf('create or replace function public.admin_analytics_overview()'),
    );

    test('opens with the System Admin gate, before any other work', () {
      expect(overview, contains("if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;"));

      // And nothing precedes it. The declared variable is deliberately left
      // uninitialised so that not even the day boundary is computed before the
      // authorization decision is made.
      expect(overview, contains('  v_day_start timestamptz;\n'));
      expect(
        overview.indexOf('is_system_admin()'),
        lessThan(overview.indexOf('statistics_period_zone()')),
        reason: 'the gate must be the first executable statement',
      );
    });

    test('buckets the day with the product\'s one frozen time zone', () {
      expect(overview, contains('statistics_period_zone()'));
      // A second constant would be a second definition of "today" that could
      // drift from the first without anything failing.
      expect(sql, isNot(contains('Asia/Muscat')));
      expect(sql, isNot(contains("at time zone 'UTC'")));
    });

    test('never treats a sign-in timestamp as activity', () {
      // One timestamp per account cannot describe a period, and reading it as
      // activity would count somebody who signed in a year ago as active today.
      // The header explains that at length, which is why this asks the
      // statements rather than the file.
      expect(statements, isNot(contains('last_sign_in_at')));
      expect(statements, isNot(contains('auth.users')));
    });

    test('measures activity by session_started and nothing else', () {
      expect(overview, contains("pe.event_name = 'session_started'"));
      expect(overview, contains('count(distinct s.user_id)'));
    });

    test('counts registrations from the events, not from the table that '
        'loses a withdrawn row', () {
      expect(overview, contains("pe.event_name = 'match_registered'"));
      // `match_registrations` may still be read -- but only for Weekly Active
      // Communities, where a surviving row is honest evidence that a community
      // was busy. It must not be what registration *counts* are made of.
      final registrationCounts = RegExp(
        r'count\(\*\) from match_registrations',
      ).allMatches(overview);
      expect(registrationCounts, isEmpty);
    });

    test('an active community means real football, never a page view', () {
      final wac = overview.substring(
        overview.indexOf('active_communities as ('),
        overview.indexOf('  select\n    (select count(*) from users)'),
      );
      expect(wac, contains('from matches m'));
      expect(wac, contains('from match_registrations r'));
      expect(wac, contains('from match_results res'));
      expect(wac, contains("pe.event_name in ('match_registered', 'match_withdrawn')"));

      // The seven that must not make a community active.
      for (final viewing in [
        'community_viewed',
        'community_joined',
        'community_created',
        'match_viewed',
        'teams_viewed',
        'result_viewed',
        'share_used',
      ]) {
        expect(wac, isNot(contains(viewing)),
            reason: 'looking at a community is not activity in it');
      }
    });

    test('retention compares the previous week with the current one', () {
      expect(overview, contains("s.created_at >= now() - interval '14 days'"));
      expect(overview, contains("s.created_at <  now() - interval '7 days'"));
      // The overlap: the same user, present in both windows.
      expect(overview, contains('where s.user_id = p.user_id'));
      expect(overview, contains("and s.created_at >= now() - interval '7 days'"));
    });

    test('reports NULL, not zero, when there was no previous cohort', () {
      expect(
        overview,
        contains('when (select count(*) from previous_week) = 0 then null::numeric'),
        reason: 'no cohort to return is not a cohort that failed to return',
      );
    });

    test('exposes counts only -- never a row of product_events', () {
      expect(overview, isNot(contains('pe.id')));
      expect(overview, isNot(contains('select pe.*')));
    });

    test('is executable by authenticated and service_role, and by nobody else',
        () {
      const fn = 'public.admin_analytics_overview()';
      expect(statements, contains('revoke execute on function $fn from anon, public;'));
      expect(statements, contains('grant execute on function $fn to authenticated;'));
      expect(statements, contains('grant execute on function $fn to service_role;'));
    });
  });

  group('nothing is backfilled and nothing is rewritten', () {
    test('there is exactly one INSERT, and it is the writer\'s own VALUES', () {
      final inserts = RegExp(r'insert into ').allMatches(statements).toList();
      expect(inserts.length, 1,
          reason: 'the only write in this migration is record_product_event');
      expect(statements, contains('insert into product_events ('));
      // A VALUES insert, not an `insert ... select` from a business table --
      // which is exactly what a backfill would look like.
      expect(statements, isNot(contains('insert into product_events (\n    select')));
      expect(statements, contains('  values (\n    v_user_id,'));
    });

    test('no existing row is updated or deleted', () {
      expect(statements, isNot(contains('delete from')));
      expect(statements, isNot(contains('truncate table')));
      // `update` appears only in the privilege list being revoked.
      final updates = RegExp(r'^\s*update ', multiLine: true)
          .allMatches(statements);
      expect(updates, isEmpty);
    });

    test('no fabricated session, withdrawal or registration', () {
      // The three inventions that would each be plausible and each be a lie.
      expect(statements, isNot(contains("'session_started', now()")));
      expect(statements, isNot(contains('from match_registrations r\n      where true')));
      expect(statements, isNot(contains('generate_series')));
    });

    test('touches no other table, view, policy or RPC', () {
      for (final forbidden in [
        'alter table public.users',
        'alter table public.communities',
        'alter table public.matches',
        'create or replace view',
        'drop function',
        'admin_list_users',
        'admin_suspend_',
        'admin_delete_',
        'record_admin_audit',
      ]) {
        // `executable`, not `statements`: the table's own COMMENT explains that
        // the legacy admin_delete_* RPCs are the reason there is no foreign
        // key, and naming them in that sentence is not touching them.
        expect(executable, isNot(contains(forbidden)),
            reason: '0067 adds analytics and changes nothing else');
      }
    });

    test('creates no cron job, materialized view or edge function', () {
      for (final forbidden in [
        'materialized view',
        'cron.schedule',
        'pg_cron',
        'create publication',
      ]) {
        expect(statements, isNot(contains(forbidden)));
      }
    });
  });
}
