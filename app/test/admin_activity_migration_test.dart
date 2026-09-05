import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0068 says — a static review of the file, not a runtime
/// result.
///
/// The migration has not been applied anywhere and cannot be executed from a
/// widget test, so these assertions read the text. That limit is worth stating
/// plainly: this proves the file says the right things, and a live precheck is
/// what proves the database does them. What it catches is the class of mistake
/// that is invisible in review and expensive in production — a gate that moved
/// below a read, a privilege quietly dropped, a backfill added, or the wrong
/// one of two nearly-identical relations read.
void main() {
  const path =
      '../supabase/migrations/0068_platform_admin_user_activity_audit_read.sql';
  final sql = File(path).readAsStringSync();

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with SQL string literals blanked as well. The `comment on`
  /// bodies are statements rather than comment lines, and they legitimately
  /// *name* the things this migration leaves alone — "NOT v_player_statistics"
  /// is the explanation, not a use of it.
  final executable = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  /// One function's own text, header through body.
  ///
  /// Called while the groups are being declared, so it cannot use `expect` —
  /// a matcher outside a test is an `OutsideTestException`. A function that is
  /// missing throws here instead, which fails the file just as loudly.
  String functionBody(String name) {
    final start = statements.indexOf('create or replace function public.$name');
    if (start < 0) throw StateError('0068 does not create $name');
    // The dollar-quote that closes a plpgsql body, escaped: a bare `$` starts
    // an interpolation in Dart.
    final end = statements.indexOf('\n\$\$;', start);
    return statements.substring(start, end == -1 ? statements.length : end);
  }

  group('the migration is 0068 and only 0068', () {
    test('the file is named for the number the brief fixed', () {
      expect(File(path).existsSync(), isTrue);
    });

    test('there is no 0069', () {
      final stragglers = Directory('../supabase/migrations')
          .listSync()
          .map((entry) => entry.uri.pathSegments.last)
          .where((name) => name.startsWith('0069'));
      expect(stragglers, isEmpty);
    });

    test('0062 to 0067 are not edited by it', () {
      // Nothing in this file names another migration's objects in a statement.
      for (final untouchable in [
        'record_admin_audit',
        'admin_suspend_',
        'admin_reactivate_',
        'admin_delete_',
        'admin_list_users',
        'admin_list_communities',
        'admin_analytics_overview',
        'record_product_event',
      ]) {
        expect(executable, isNot(contains(untouchable)),
            reason: '0068 adds three read paths and changes nothing else');
      }
    });
  });

  group('it creates nothing and writes nothing', () {
    test('no table, no index, no constraint', () {
      for (final forbidden in [
        'create table',
        'create index',
        'alter table',
        'add constraint',
        'create type',
        'create view',
        'materialized view',
      ]) {
        expect(statements, isNot(contains(forbidden)));
      }
    });

    test('no DML of any kind, and no backfill', () {
      for (final forbidden in [
        'insert into',
        'delete from',
        'truncate',
        'generate_series',
      ]) {
        expect(statements, isNot(contains(forbidden)));
      }
      // `update` appears nowhere, not even in a privilege list here.
      expect(RegExp(r'^\s*update ', multiLine: true).allMatches(statements),
          isEmpty);
    });

    test('exactly three functions are created', () {
      expect(
        RegExp('create or replace function').allMatches(statements).length,
        3,
      );
    });
  });

  group('every function is gated, definer, and pinned', () {
    const functions = {
      'admin_user_activity_summary': 'admin_user_activity_summary(uuid)',
      'admin_user_activity_timeline':
          'admin_user_activity_timeline(uuid, integer)',
      'admin_list_audit_log': 'admin_list_audit_log(integer)',
    };

    for (final entry in functions.entries) {
      final name = entry.key;
      final signature = entry.value;

      test('$name opens with the System Admin gate', () {
        final body = functionBody(name);
        expect(
          body,
          contains(
              "if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;"),
        );
        // And nothing precedes it. The declared variable is left uninitialised
        // so that no work at all happens before the authorization decision.
        final declare = body.indexOf('declare');
        final gate = body.indexOf('is_system_admin()');
        final begin = body.indexOf('begin');
        expect(begin, lessThan(gate));
        expect(body.substring(declare, begin), isNot(contains(':=')));
      });

      test('$name is a definer with a pinned search path', () {
        final body = functionBody(name);
        expect(body, contains('security definer'));
        expect(body, contains('stable'));
        expect(body, contains('set search_path = public'));
      });

      test('$name is executable by authenticated and service_role only', () {
        expect(
          statements,
          contains('revoke execute on function public.$signature\n  from anon, public;'),
        );
        expect(
          statements,
          contains('grant execute on function public.$signature\n  to authenticated;'),
        );
        expect(
          statements,
          contains('grant execute on function public.$signature\n  to service_role;'),
          reason: '0066 is the reminder: a privilege no migration wrote down '
              'is still one a drop would take away.',
        );
        expect(statements,
            isNot(contains('grant execute on function public.$signature\n  to anon')));
      });
    }
  });

  group('the two protected tables stay protected', () {
    test('no policy is added or removed', () {
      expect(statements, isNot(contains('create policy')));
      expect(statements, isNot(contains('drop policy')));
      expect(statements, isNot(contains('row level security')));
    });

    test('no client is granted anything on product_events', () {
      expect(statements, isNot(contains('grant select on public.product_events')));
      expect(statements, isNot(contains('grant all on public.product_events')));
    });

    test('no client is granted anything on admin_audit_log', () {
      expect(
          statements, isNot(contains('grant select on public.admin_audit_log')));
      expect(statements, isNot(contains('grant all on public.admin_audit_log')));
    });
  });

  group('admin_user_activity_summary', () {
    final body = functionBody('admin_user_activity_summary');

    test('refuses an id with no account', () {
      expect(body, contains("raise exception 'USER_NOT_FOUND'"));
      // After the gate: whether an account exists is itself something only a
      // System Admin may learn.
      expect(
        body.indexOf('is_system_admin()'),
        lessThan(body.indexOf('USER_NOT_FOUND')),
      );
    });

    test('Last Seen is observed activity, never a sign-in timestamp', () {
      expect(body, contains('select max(e.created_at) from events e'));
      // `executable`, not `statements`: the function's own COMMENT says that
      // auth.last_sign_in_at is never read, and that sentence is not a read.
      expect(executable, isNot(contains('last_sign_in_at')));
    });

    test('an active day is a session_started on a local calendar day', () {
      expect(body, contains("e.event_name = 'session_started'"));
      expect(body, contains('count(distinct (e.created_at at time zone v_zone)::date)'));
      expect(body, contains("interval '7 days'"));
      expect(body, contains("interval '30 days'"));
    });

    test('the local day comes from the product\'s one frozen zone', () {
      expect(body, contains('v_zone := statistics_period_zone();'));
      // A second constant would be a second definition of "today", free to
      // drift from the first in silence.
      expect(statements, isNot(contains('Asia/Muscat')));
    });

    test('Matches Played reads the table, not the view that hides suspensions',
        () {
      expect(body, contains('from player_statistics ps'));
      expect(body, contains('coalesce('));
      // `v_player_statistics` carries `where u.is_active`, so a suspended
      // account vanishes from it -- and that is precisely the account this
      // screen exists to inspect.
      expect(executable, isNot(contains('v_player_statistics')));
    });

    test('registrations and withdrawals are tracked event counts', () {
      expect(body, contains("e.event_name = 'match_registered'"));
      expect(body, contains("e.event_name = 'match_withdrawn'"));
      // Never inferred from the table that loses a row on withdrawal.
      expect(body, isNot(contains('from match_registrations')));
    });

    test('community count is current membership', () {
      expect(body, contains('from community_members cm'));
      expect(body, contains('where cm.user_id = p_user_id'));
    });

    test('platforms come back ordered, and as a list rather than a null', () {
      expect(body, contains('array_agg(distinct e.platform order by e.platform)'));
      expect(body, contains("array[]::text[]"));
    });

    test('auth.users is read for the email and nothing else', () {
      expect(body, contains('join auth.users au on au.id = u.id'));
      expect(body, contains('au.email::text'));
      // No other auth column is projected.
      expect(body, isNot(contains('au.raw_')));
      expect(body, isNot(contains('au.phone')));
      expect(body, isNot(contains('au.last_sign_in_at')));
    });
  });

  group('admin_user_activity_timeline', () {
    final body = functionBody('admin_user_activity_timeline');

    test('joins context LEFT so a deleted target cannot erase the event', () {
      expect(body, contains('left join communities c on c.id = pe.community_id'));
      expect(body, contains('left join matches m on m.id = pe.match_id'));
      // An INNER join here would make deleting a community quietly erase a
      // person's history of having been in it.
      expect(body, isNot(contains('join communities c on c.id = pe.community_id\n    where')));
    });

    test('reads product_events, newest first, for the named user only', () {
      expect(body, contains('from product_events pe'));
      expect(body, contains('where pe.user_id = p_user_id'));
      expect(body, contains('order by pe.created_at desc'));
    });

    test('clamps the row count to 1..100', () {
      expect(body,
          contains('v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);'));
      expect(body, contains('limit v_limit'));
    });

    test('does not echo the user id on every row', () {
      final returns = body.substring(
        body.indexOf('returns table ('),
        body.indexOf('language plpgsql'),
      );
      expect(returns, isNot(contains('user_id')));
    });
  });

  group('admin_list_audit_log', () {
    final body = functionBody('admin_list_audit_log');

    test('reads the audit log newest first', () {
      expect(body, contains('from admin_audit_log a'));
      expect(body, contains('order by a.created_at desc'));
    });

    test('clamps the row count to 1..200', () {
      expect(body,
          contains('v_limit := least(greatest(coalesce(p_limit, 100), 1), 200);'));
    });

    test('does not expose the metadata jsonb', () {
      expect(body, isNot(contains('metadata')));
      expect(body, isNot(contains('jsonb')));
    });

    test('does not filter by action', () {
      // The log is append-only and future-safe. A reader that dropped
      // unrecognised entries would hide the ones most worth seeing.
      expect(body, isNot(contains("a.action =")));
      expect(body, isNot(contains('a.action in (')));
    });

    test('returns nine of the ten columns', () {
      final returns = body.substring(
        body.indexOf('returns table ('),
        body.indexOf('language plpgsql'),
      );
      for (final column in [
        'id uuid',
        'actor_user_id uuid',
        'actor_email_snapshot text',
        'action text',
        'target_type text',
        'target_id uuid',
        'target_label_snapshot text',
        'reason text',
        'created_at timestamptz',
      ]) {
        expect(returns, contains(column));
      }
    });
  });
}
