import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/analytics/analytics_models.dart';

/// What migration 0069 says — a static review of the file, not a runtime
/// result.
///
/// The migration has not been applied anywhere and cannot be executed from a
/// widget test, so these assertions read the text. That limit is worth stating:
/// this proves the file says the right things, and a live precheck is what
/// proves the database does them.
///
/// Most of what is checked here is **count fidelity** — that each list
/// reproduces the population its Overview figure counted. Those are the
/// mistakes that would be invisible in review and in production alike, because
/// a drill-down that silently drops rows still looks like a perfectly good
/// list.
void main() {
  const path = '../supabase/migrations/0069_platform_admin_analytics_drilldown.sql';
  final sql = File(path).readAsStringSync();
  final overview = File(
    '../supabase/migrations/0067_platform_admin_product_analytics.sql',
  ).readAsStringSync();

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with SQL string literals blanked. A `comment on` body is a
  /// statement rather than a comment line, and these legitimately *name* the
  /// things the migration leaves alone.
  final executable = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  /// One function's own text, header through body.
  ///
  /// Called while the groups are declared, so it throws rather than using
  /// `expect` — a matcher outside a test is an `OutsideTestException`.
  String functionBody(String name) {
    final start = statements.indexOf('create or replace function public.$name');
    if (start < 0) throw StateError('0069 does not create $name');
    // The dollar-quote that closes a plpgsql body, escaped: a bare `$` starts
    // an interpolation in Dart.
    final end = statements.indexOf('\n\$\$;', start);
    return statements.substring(start, end == -1 ? statements.length : end);
  }

  const signatures = {
    'admin_analytics_users': 'admin_analytics_users(text, integer, integer)',
    'admin_analytics_communities':
        'admin_analytics_communities(text, integer, integer)',
    'admin_analytics_matches':
        'admin_analytics_matches(text, integer, integer)',
    'admin_analytics_registrations':
        'admin_analytics_registrations(integer, integer, integer)',
    'admin_get_community_inspection': 'admin_get_community_inspection(uuid)',
    'admin_get_match_inspection': 'admin_get_match_inspection(uuid)',
  };

  group('the migration is 0069 and only 0069', () {
    test('the file exists under the number the brief fixed', () {
      expect(File(path).existsSync(), isTrue);
    });

    // No "there is no 0070" test here, deliberately.
    //
    // 0068's suite carried the equivalent assertion and this cycle had to
    // delete it: "the cycle added exactly one migration" is true of a diff and
    // not of the repository, so as a permanent test it only guarantees that
    // the next correct change breaks it. That is checked at review instead.
    test('exactly one migration file carries this number', () {
      final numbered = Directory('../supabase/migrations')
          .listSync()
          .map((entry) => entry.uri.pathSegments.last)
          .where((name) => name.startsWith('0069'))
          .toList();
      expect(numbered, hasLength(1));
    });

    test('it creates nothing and writes nothing', () {
      for (final forbidden in [
        'create table',
        'create index',
        'alter table',
        'create type',
        'create view',
        'materialized view',
        'insert into',
        'delete from',
        'truncate',
        'generate_series',
      ]) {
        expect(statements, isNot(contains(forbidden)));
      }
      expect(RegExp(r'^\s*update ', multiLine: true).allMatches(statements),
          isEmpty);
    });

    test('it changes no policy and no RLS', () {
      expect(statements, isNot(contains('create policy')));
      expect(statements, isNot(contains('drop policy')));
      expect(statements, isNot(contains('row level security')));
    });

    test('it redefines nothing from 0062 to 0068', () {
      for (final untouchable in [
        'admin_analytics_overview',
        'record_product_event',
        'record_admin_audit',
        'admin_suspend_',
        'admin_reactivate_',
        'admin_delete_',
        'admin_list_users',
        'admin_list_communities',
        'admin_user_activity_summary',
        'admin_list_audit_log',
        'statistics_period_zone()\nreturns',
      ]) {
        expect(executable, isNot(contains(untouchable)),
            reason: '0069 adds six read paths and changes nothing else');
      }
    });

    test('it creates exactly six functions', () {
      expect(
        RegExp('create or replace function').allMatches(statements).length,
        6,
      );
    });
  });

  group('every function is gated, definer, pinned and granted narrowly', () {
    for (final entry in signatures.entries) {
      final name = entry.key;
      final signature = entry.value;

      test('$name opens with the System Admin gate', () {
        final body = functionBody(name);
        expect(
          body,
          contains(
              "if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;"),
        );
        // And nothing precedes it: the declared variables carry no
        // initializer, so no work at all happens before the decision.
        final begin = body.indexOf('begin');
        final gate = body.indexOf('is_system_admin()');
        expect(begin, lessThan(gate));
        final declare = body.indexOf('declare');
        if (declare >= 0) {
          expect(body.substring(declare, begin), isNot(contains(':=')));
        }
      });

      test('$name is a stable definer with a pinned search path', () {
        final body = functionBody(name);
        expect(body, contains('security definer'));
        expect(body, contains('stable'));
        expect(body, contains('set search_path = public'));
      });

      test('$name executes for authenticated and service_role only', () {
        expect(statements, contains('revoke execute on function'));
        expect(statements, contains('public.$signature'));
        expect(statements, contains('to authenticated;'));
        expect(statements, contains('to service_role;'));
        expect(
          statements,
          isNot(contains('grant execute on function public.$signature\n  to anon')),
        );
      });
    }

    test('the revoke and both grants appear once per function', () {
      // Six functions, so six of each. A missing service_role grant is the
      // 0066 regression, and it is invisible until a drop takes the ACL.
      expect(RegExp('revoke execute on function').allMatches(statements).length, 6);
      expect(RegExp('to authenticated;').allMatches(statements).length, 6);
      expect(RegExp('to service_role;').allMatches(statements).length, 6);
    });

    test('no table privilege is granted to any client role', () {
      for (final table in [
        'public.product_events',
        'public.admin_audit_log',
        'auth.users',
      ]) {
        expect(statements, isNot(contains('grant select on $table')));
        expect(statements, isNot(contains('grant all on $table')));
      }
    });
  });

  group('admin_analytics_users reproduces its metrics exactly', () {
    final body = functionBody('admin_analytics_users');

    test('accepts exactly the eight approved metric names', () {
      for (final metric in AdminDrilldownMetric.values
          .where((m) => m.kind == AdminDrilldownKind.users)) {
        expect(body, contains("'${metric.wireName}'"),
            reason: '${metric.name} is not accepted by the RPC');
      }
      expect(body, contains("raise exception 'INVALID_ADMIN_ANALYTICS_METRIC'"));
    });

    test('clamps the page and refuses a negative offset', () {
      expect(body, contains('least(greatest(coalesce(p_limit, 50), 1), 100)'));
      expect(body, contains('greatest(coalesce(p_offset, 0), 0)'));
      expect(body, contains('limit v_limit offset v_offset'));
    });

    test('activity is session_started, exactly as 0067 defines it', () {
      expect(body, contains("pe.event_name = 'session_started'"));
      // The same thirty-day horizon the Overview reads over.
      expect(body, contains("and pe.created_at >= now() - interval '30 days'"));
      expect(body, isNot(contains('last_sign_in_at')));
    });

    test('the calendar day comes from the frozen zone, not a second constant',
        () {
      expect(body, contains('statistics_period_zone()'));
      expect(sql, isNot(contains('Asia/Muscat')));
      // Character for character what 0067 computes.
      const dayStart =
          "date_trunc('day', now() at time zone statistics_period_zone())";
      expect(body, contains(dayStart));
      expect(overview, contains(dayStart));
    });

    test('the retention windows are 0067\'s, character for character', () {
      for (final window in [
        "s.created_at >= now() - interval '14 days'",
        "s.created_at <  now() - interval '7 days'",
      ]) {
        expect(body, contains(window));
        expect(overview, contains(window),
            reason: 'the cohort must be the one the Overview counted');
      }
      // And the returned flag is the same predicate, applied per row.
      expect(body, contains("and s.created_at >= now() - interval '7 days'"));
    });

    test('a deleted account is kept, not joined away', () {
      // count(distinct s.user_id) counted it, so the list must contain it.
      expect(body, contains('left join users u on u.id = t.user_id'));
      expect(body, contains('left join auth.users au on au.id = t.user_id'));
      // Asked line by line. `left join users u ...` trivially contains the
      // substring `join users u ...`, so a plain negative `contains` could
      // never fail and would be a test that proves nothing.
      final innerJoins =
          RegExp(r'^\s*join (users|auth\.users) ', multiLine: true)
              .allMatches(body);
      expect(innerJoins, isEmpty,
          reason: 'an inner join here would drop the deleted accounts the '
              'Overview counted');
    });

    test('no suspended-user filter is added', () {
      // The Overview counts every account; adding `and u.is_active` here would
      // make the list disagree with the card.
      expect(body, isNot(contains('and u.is_active')));
      expect(body, isNot(contains('where u.is_active')));
    });

    test('auth.users is read for the email only', () {
      expect(body, contains('au.email::text'));
      for (final column in ['au.raw_', 'au.phone', 'au.encrypted_']) {
        expect(body, isNot(contains(column)));
      }
    });
  });

  group('admin_analytics_communities copies the WAC definition', () {
    final body = functionBody('admin_analytics_communities');

    test('all four qualifying branches are present', () {
      expect(body, contains('from matches m'));
      expect(body, contains('from match_registrations r'));
      expect(body, contains('from match_results res'));
      expect(body,
          contains("pe.event_name in ('match_registered', 'match_withdrawn')"));
    });

    test('no viewing event makes a community active', () {
      for (final viewing in [
        'community_viewed',
        'community_joined',
        'community_created',
        'match_viewed',
        'teams_viewed',
        'result_viewed',
        'share_used',
      ]) {
        expect(body, isNot(contains(viewing)),
            reason: 'looking at a community is not activity in it');
      }
    });

    test('the event branch keeps 0067\'s inner join to communities', () {
      // Elsewhere a missing entity is preserved. Here it is not, because the
      // Overview does not count it either -- fidelity means copying the
      // definition rather than improving it.
      expect(body, contains('join communities c on c.id = pe.community_id'));
      expect(overview, contains('join communities c on c.id = pe.community_id'));
    });

    test('each community appears once', () {
      expect(body, contains('group by a.community_id'));
    });

    test('no current-is_active filter is added', () {
      expect(body, isNot(contains('and c.is_active')));
      expect(body, isNot(contains('where c.is_active')));
    });

    test('only its own metric is accepted', () {
      expect(body, contains("p_metric <> 'weekly_active_communities'"));
      expect(body, contains("raise exception 'INVALID_ADMIN_ANALYTICS_METRIC'"));
    });
  });

  group('admin_analytics_matches keeps matches and results apart', () {
    final body = functionBody('admin_analytics_matches');

    test('accepts exactly the four approved metric names', () {
      for (final metric in AdminDrilldownMetric.values
          .where((m) => m.kind == AdminDrilldownKind.matches)) {
        expect(body, contains("'${metric.wireName}'"));
      }
    });

    test('match metrics filter the match, result metrics filter the result',
        () {
      expect(body, contains('(not v_results and m.created_at >= v_since)'));
      expect(body, contains('(v_results and res.created_at >= v_since)'));
      // The one mistake this function could make invisibly: a match organised
      // long ago and written up this week belongs to the results list.
      expect(body, contains("v_results := p_metric in ('results_7d', 'results_30d')"));
    });

    test('a match with no result still lists in a matches metric', () {
      expect(body, contains('left join match_results res on res.match_id = m.id'));
    });

    test('the community join cannot drop a counted match', () {
      expect(body, contains('left join communities c on c.id = m.community_id'));
    });
  });

  group('admin_analytics_registrations lists events, not people', () {
    final body = functionBody('admin_analytics_registrations');

    test('there is no DISTINCT anywhere', () {
      // The Overview counts events. One player registering three times is
      // three rows, and de-duplicating would make the list shorter than the
      // number above it with nothing to explain the gap.
      expect(body.toLowerCase(), isNot(contains('distinct')));
    });

    test('it reads the events themselves', () {
      expect(body, contains('from product_events pe'));
      expect(body, contains("where pe.event_name = 'match_registered'"));
      expect(body, contains('pe.id'));
    });

    test('only the two windows the Overview shows are accepted', () {
      expect(body, contains('p_period_days not in (7, 30)'));
      expect(body, contains("raise exception 'INVALID_ADMIN_ANALYTICS_METRIC'"));
    });

    test('every context join is LEFT', () {
      for (final join in [
        'left join users u on u.id = pe.user_id',
        'left join auth.users au on au.id = pe.user_id',
        'left join matches m on m.id = pe.match_id',
        'left join communities c on c.id = coalesce(pe.community_id, m.community_id)',
      ]) {
        expect(body, contains(join),
            reason: 'product_events has no foreign keys; a deleted target must '
                'leave the event standing');
      }
    });
  });

  group('the two inspection functions', () {
    test('community inspection refuses an unknown id, after the gate', () {
      final body = functionBody('admin_get_community_inspection');
      expect(body, contains("raise exception 'COMMUNITY_NOT_FOUND'"));
      expect(
        body.indexOf('is_system_admin()'),
        lessThan(body.indexOf('COMMUNITY_NOT_FOUND')),
      );
    });

    test('community inspection never exposes the join code', () {
      final body = functionBody('admin_get_community_inspection');
      expect(body, isNot(contains('join_code')));
    });

    test('match inspection refuses an unknown id, after the gate', () {
      final body = functionBody('admin_get_match_inspection');
      expect(body, contains("raise exception 'MATCH_NOT_FOUND'"));
      expect(
        body.indexOf('is_system_admin()'),
        lessThan(body.indexOf('MATCH_NOT_FOUND')),
      );
    });

    test('neither grants the caller a community role', () {
      // Inspection is a read. Nothing here inserts a membership or calls the
      // role helper in a way that could create one.
      for (final name in [
        'admin_get_community_inspection',
        'admin_get_match_inspection',
      ]) {
        final body = functionBody(name);
        expect(body, isNot(contains('insert into community_members')));
        expect(body, isNot(contains('has_community_role')));
      }
    });

    test('both keep a deleted neighbour from hiding the record', () {
      final match = functionBody('admin_get_match_inspection');
      for (final join in [
        'left join communities c on c.id = m.community_id',
        'left join users creator on creator.id = m.created_by',
        'left join match_results res on res.match_id = m.id',
        'left join users mvp on mvp.id = res.mvp_user_id',
      ]) {
        expect(match, contains(join));
      }
      expect(
        functionBody('admin_get_community_inspection'),
        contains('left join users o on o.id = c.owner_id'),
      );
    });
  });

  group('the analytics contract is unchanged', () {
    test('there are still exactly ten product events', () {
      expect(ProductEvent.values.length, 10);
    });

    test('0069 records no event and adds no event name', () {
      expect(statements, isNot(contains('record_product_event')));
      for (final event in ProductEvent.values) {
        // The two the WAC branch legitimately reads are the exception; no
        // other event name appears in a statement at all.
        if (event == ProductEvent.matchRegistered ||
            event == ProductEvent.matchWithdrawn ||
            event == ProductEvent.sessionStarted) {
          continue;
        }
        expect(statements, isNot(contains("'${event.wireName}'")));
      }
    });
  });
}
