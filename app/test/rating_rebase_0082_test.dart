import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The historical rebase, reviewed as text.
///
/// **What this suite is for.** Migration `0082` rewrites every Global Rating
/// and the whole operational audit under them; it cannot be executed from a
/// widget test, and the live proof is the rolled-back transaction recorded in
/// the cycle report. What can be held here is the thing a review would look
/// for: that the rebase delegates to the engine instead of re-implementing it,
/// that it archives before it destroys, that it cannot run twice, that it
/// touches nothing but the rating and its audit, and that the rollback is a
/// real restoration rather than a placeholder.
void main() {
  // Normalised on the way in: Git checks these files out with CRLF endings on
  // Windows and LF on CI, and several assertions below span two lines.
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  final sql = read(
      '../supabase/migrations/0082_rating_engine_0078_historical_rebase.sql');
  final rollback = read(
      '../supabase/rollback/0082_rating_engine_0078_historical_rebase_rollback.sql');
  final engine = read('../supabase/migrations/0078_rating_goal_mvp_values.sql');
  final scoped = read(
      '../supabase/migrations/0081_community_scoped_rating_and_public_results.sql');

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  String executable(String text) => text
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  final statements = executable(sql);
  final rollbackStatements = executable(rollback);

  group('the rebase uses the engine rather than a copy of it', () {
    test('it replays through apply_match_rating_effects', () {
      expect(statements,
          contains('perform apply_match_rating_effects(v_match.id)'));
    });

    test('and states no rating constant of its own', () {
      // Every value the engine applies lives in `0078` and nowhere else. If a
      // constant ever appears here, there are two engines.
      for (final constant in [
        '0.005',
        '0.100',
        '0.010',
        '-0.100',
        '0.070',
        '0.020',
      ]) {
        expect(statements, isNot(contains(constant)), reason: constant);
      }
      // The engine it delegates to still carries them.
      expect(engine, contains("'PARTICIPATION', 0.005"));
      expect(engine, contains("'MVP', 0.020"));
    });

    test('the only value it writes directly is the approved baseline', () {
      expect(statements, contains('update users set overall_rating = 5.000;'));
    });
  });

  group('the replay order is the approved one', () {
    test('every recorded result, oldest first, match id breaking a tie', () {
      expect(
        statements,
        contains('select m.id\n'
            '    from matches m\n'
            '    join match_results r on r.match_id = m.id\n'
            '    order by m.start_at, m.id'),
      );
    });

    test('and the scoped rating replays in exactly the same order', () {
      // The equality contract: both derivations must walk one player's matches
      // the same way, or Global and Community All-Time can differ.
      expect(scoped, contains('order by m.start_at, m.id'));
      expect(scoped, contains('v_rating := 5.000;'));
    });
  });

  group('it archives before it destroys', () {
    test('the history and the ratings are archived first', () {
      final archiveHistory =
          statements.indexOf('insert into rating_history_archive');
      final archiveUsers =
          statements.indexOf('insert into user_rating_archive');
      final clear = statements.indexOf('delete from rating_history;');
      final reset =
          statements.indexOf('update users set overall_rating = 5.000;');

      expect(archiveHistory, isNot(-1));
      expect(archiveUsers, isNot(-1));
      expect(archiveHistory, lessThan(clear));
      expect(archiveUsers, lessThan(clear));
      expect(clear, lessThan(reset));
    });

    test('the archive carries every column a restoration needs', () {
      for (final column in [
        'id uuid not null',
        'entry_no bigint not null',
        'user_id uuid not null',
        'match_id uuid not null',
        'change_reason text not null',
        'delta numeric(5,3) not null',
        'rating_before numeric(5,3) not null',
        'rating_after numeric(5,3) not null',
        'reverses_id uuid',
        'created_at timestamptz not null',
        'rebase_version text not null',
      ]) {
        expect(statements, contains(column), reason: column);
      }
    });

    test('and no foreign key that a deletion could follow into it', () {
      final archive = statements.substring(
        statements.indexOf(
            'create table if not exists public.rating_history_archive'),
        statements.indexOf(
            'create unique index if not exists rating_history_archive_row_idx'),
      );
      expect(archive, isNot(contains('references')));
      expect(archive, isNot(contains('on delete')));
    });

    test('nothing may edit an archived row', () {
      expect(statements, contains('RATING_ARCHIVE_IMMUTABLE'));
      expect(statements,
          contains('before update on public.rating_history_archive'));
      expect(
          statements, contains('before update on public.user_rating_archive'));
    });

    test('and nothing may remove one either', () {
      // A row changed in place and a row that is gone are the same failure:
      // the rebase silently stops being reversible. Both archives refuse the
      // deletion, and the two refusals are told apart by their error.
      expect(statements, contains('RATING_ARCHIVE_UNDELETABLE'));
      expect(statements,
          contains('before delete on public.rating_history_archive'));
      expect(
          statements, contains('before delete on public.user_rating_archive'));
      expect(statements,
          contains('create or replace function public.reject_rating_archive_delete()'));
    });

    test('and the rollback only ever reads the archive', () {
      // Which is why refusing the delete costs it nothing: restoring is a
      // read of the archive and a write of the operational tables.
      expect(rollbackStatements, isNot(contains('delete from rating_history_archive')));
      expect(rollbackStatements, isNot(contains('delete from user_rating_archive')));
      expect(rollbackStatements, isNot(contains('update rating_history_archive')));
      expect(rollbackStatements, isNot(contains('update user_rating_archive')));
      // And no new grant was handed out to make any of that reachable.
      expect(statements, isNot(contains('grant all')));
      for (final table in [
        'rating_rebase_runs',
        'rating_history_archive',
        'user_rating_archive',
      ]) {
        expect(statements, isNot(contains('grant select on public.$table')),
            reason: table);
      }
    });

    test('and no client can read any of it', () {
      for (final table in [
        'rating_rebase_runs',
        'rating_history_archive',
        'user_rating_archive',
      ]) {
        expect(statements,
            contains('alter table public.$table enable row level security;'),
            reason: table);
        expect(
            statements,
            contains(
                'revoke all on public.$table from anon, authenticated, public;'),
            reason: table);
        expect(statements, isNot(contains('create policy')), reason: table);
      }
      expect(
        statements,
        contains(
            'revoke execute on function public.rebase_ratings_to_0078(text)\n'
            '  from anon, authenticated, public;'),
      );
    });
  });

  group('it cannot run twice', () {
    test('a completed run, a run in progress and a stale archive all refuse',
        () {
      expect(
          statements, contains("raise exception 'REBASE_ALREADY_COMPLETED'"));
      expect(statements, contains("raise exception 'REBASE_IN_PROGRESS'"));
      expect(statements,
          contains("raise exception 'REBASE_ARCHIVE_ALREADY_PRESENT'"));
    });

    test('and the marker records what the run did', () {
      for (final column in [
        'archived_history_rows',
        'archived_user_rows',
        'replayed_matches',
        'rebuilt_history_rows',
        'completed_at',
        'rolled_back_at',
        'rolled_back_partial_at',
        'rollback_skipped_rows',
      ]) {
        expect(statements, contains(column), reason: column);
      }
      expect(statements, contains('rebase_version text not null unique'));
    });
  });

  group('it touches nothing but the rating and its audit', () {
    test('no result, goal, lineup, counter or snapshot is written', () {
      for (final table in [
        'match_results',
        'match_goals',
        'match_team_assignments',
        'player_statistics',
        'community_statistics',
        'team_of_period_snapshots',
        'team_of_period_awards',
        'matches',
      ]) {
        expect(statements, isNot(contains('update $table')), reason: table);
        expect(statements, isNot(contains('delete from $table')),
            reason: table);
        expect(statements, isNot(contains('insert into $table')),
            reason: table);
      }
    });

    test('and no earlier migration is edited', () {
      expect(statements, isNot(contains('apply_rating_delta(')));
      expect(
          statements,
          isNot(contains(
              'create or replace function public.apply_match_rating_effects')));
    });
  });

  group('the rollback is a real restoration', () {
    test('it restores every archived row with its own id and entry number', () {
      expect(rollbackStatements, contains('overriding system value'));
      expect(rollbackStatements, contains('a.id, a.entry_no, a.user_id'));
      expect(rollbackStatements, contains('order by a.entry_no'));
    });

    test('it puts the identity sequence past what it restored', () {
      expect(rollbackStatements, contains('setval('));
      expect(
          rollbackStatements,
          contains(
              "pg_get_serial_sequence('public.rating_history', 'entry_no')"));
    });

    test('it restores every archived rating', () {
      expect(rollbackStatements,
          contains('set overall_rating = a.overall_rating'));
    });

    test('it refuses when there is nothing to restore from', () {
      expect(
          rollbackStatements, contains("raise exception 'REBASE_NOT_FOUND'"));
      expect(rollbackStatements,
          contains("raise exception 'REBASE_ARCHIVE_MISSING'"));
      expect(rollbackStatements,
          contains("raise exception 'REBASE_ALREADY_ROLLED_BACK'"));
    });

    test('it never destroys the archive it restores from', () {
      final executed = rollbackStatements
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('--'))
          .join('\n');
      expect(executed, isNot(contains('drop table')));
      expect(executed, isNot(contains('delete from rating_history_archive')));
      expect(executed, isNot(contains('delete from user_rating_archive')));
    });

    test('and it still knows which rows it could not restore', () {
      // A user or a match deleted after the rebase cannot have history
      // restored against it -- `rating_history` has foreign keys to both.
      expect(rollbackStatements, contains('skipped_history_rows'));
      expect(rollbackStatements,
          contains('exists (select 1 from users u where u.id = a.user_id)'));
      expect(rollbackStatements,
          contains('exists (select 1 from matches m where m.id = a.match_id)'));
    });

    test('and touches no result or counter either', () {
      for (final table in [
        'match_results',
        'match_goals',
        'player_statistics',
        'community_statistics',
      ]) {
        expect(rollbackStatements, isNot(contains('update $table')),
            reason: table);
        expect(rollbackStatements, isNot(contains('delete from $table')),
            reason: table);
      }
    });
  });

  group('Global and Community All-Time are the same derivation', () {
    test('both pay exactly who the engine pays', () {
      // `0078` pays participation and the outcome to the lineup, a goal award
      // to every row of `match_goals`, and the MVP award to the result's own
      // `mvp_user_id` -- the last two without requiring a lineup row. The
      // scoped rating's population is the union of those three, which is what
      // makes the two answers equal rather than nearly equal.
      expect(scoped, contains('from match_team_assignments a'));
      expect(scoped, contains('from match_goals g'));
      expect(scoped, contains('select res.mvp_user_id, res.match_id'));
      expect(scoped, contains('if r.played then'));
      expect(scoped, contains('if r.is_mvp then'));

      expect(engine, contains('from match_team_assignments a'));
      expect(engine, contains('from match_goals g'));
      expect(engine, contains('if v_result.mvp_user_id is not null then'));
    });

    test('and both clamp after every delta, from the same baseline', () {
      expect(
        RegExp(r'least\(10\.000, greatest\(0\.000').allMatches(scoped).length,
        4,
      );
      expect(scoped, contains('v_rating := 5.000;'));
      // The Global side clamps inside `apply_rating_delta`, which is where the
      // engine has always done it.
      expect(
        read(
            '../supabase/migrations/0073_rating_precision_and_participation.sql'),
        contains('least(10.000, greatest(0.000, v_before + p_delta))'),
      );
    });

    test('a week and a month stay their own scopes, at their own baseline', () {
      // Period ratings do not inherit anything: each starts at 5.000 over the
      // matches of that period alone.
      expect(scoped, contains("not in ('overall', 'weekly', 'monthly')"));
      expect(scoped,
          contains('public.statistics_period_key(m.start_at, p_period_type)'));
      expect(scoped, contains('= p_period_key'));
      // One baseline statement, inside the per-player loop: nothing carries a
      // rating into a period.
      expect('v_rating := 5.000;'.allMatches(scoped).length, 1);
    });
  });

  group('both migrations stay compatible with the shipped client', () {
    test('0082 changes no contract the application calls', () {
      for (final contract in [
        'record_match_result',
        'player_profile',
        'v_player_statistics',
        'player_recent_form',
        'public_player_profile',
        'community_statistics',
      ]) {
        expect(statements, isNot(contains('function public.$contract(')),
            reason: contract);
      }
      // It adds tables and two functions, and alters nothing that existed
      // before it -- the `alter table`s below are on its own archive tables,
      // which is why the operational ones are named exactly.
      expect(statements, isNot(contains('alter table public.rating_history ')));
      expect(statements, isNot(contains('alter table public.users')));
      expect(statements, isNot(contains('alter table public.match_results')));
    });

    test('0081 is additive too', () {
      final scopedStatements = executable(scoped);
      for (final forbidden in [
        'alter table',
        'drop table',
        'drop function public.player_profile',
        'create policy',
      ]) {
        expect(scopedStatements.toLowerCase(), isNot(contains(forbidden)),
            reason: forbidden);
      }
    });
  });

  group('the correction flow is left intact', () {
    test('the rebase neither redefines nor bypasses it', () {
      // `reverse_match_rating_effects` reads the *operational* history, which
      // after the rebase is the rebuilt one -- so a correction reverses 0078
      // deltas. The rebase must not touch that function.
      expect(
          statements,
          isNot(contains(
              'create or replace function public.reverse_match_rating_effects')));
      expect(
          statements, isNot(contains('perform reverse_match_rating_effects')));
    });

    test('and no archived row can take part in one', () {
      // The archive is a separate table; the reversal reads `rating_history`
      // only. This is what keeps legacy bookkeeping out of the new flow.
      final reversal = read('../supabase/migrations/0022_match_results.sql');
      expect(reversal, contains('from rating_history h'));
      expect(reversal, isNot(contains('rating_history_archive')));
    });
  });

  group('the rebase does not race a writer', () {
    test('it locks the whole evidence set, and locks it first', () {
      final lock = statements.indexOf('lock table');
      final guard = statements.indexOf("raise exception 'REBASE_ALREADY_COMPLETED'");
      final archive = statements.indexOf('insert into rating_history_archive');

      expect(lock, isNot(-1));
      // Before the first guard, and so before the first row of evidence is
      // read: an archive taken under a moving result set would describe a
      // history that never existed.
      expect(lock, lessThan(guard));
      expect(lock, lessThan(archive));

      for (final table in [
        'public.match_goals',
        'public.match_results',
        'public.match_team_assignments',
        'public.matches',
        'public.rating_history',
        'public.users',
      ]) {
        expect(statements.substring(lock, archive), contains(table),
            reason: table);
      }
    });

    test('in the narrowest mode that stops a writer', () {
      // `share row exclusive` conflicts with `row exclusive` -- what every
      // insert, update and delete takes -- and with nothing a reader takes.
      expect(statements, contains('in share row exclusive mode'));
      // The two modes that would also block reading the app's own pages.
      expect(statements, isNot(contains('in access exclusive mode')));
      expect(statements, isNot(contains('in exclusive mode')));
      expect(statements, isNot(contains('lock table public.rating_history in')));
    });

    test('and it never waits unboundedly for them', () {
      expect(statements, contains("set local lock_timeout = '15s'"));
      // Set before the lock is asked for, or it bounds nothing.
      expect(statements.indexOf('set local lock_timeout'),
          lessThan(statements.indexOf('lock table')));
    });

    test('the rollback takes the same locks the same way', () {
      // It rewrites the same tables, so it carries the same hazard.
      expect(rollbackStatements, contains("set local lock_timeout = '15s'"));
      expect(rollbackStatements, contains('in share row exclusive mode'));
      expect(rollbackStatements.indexOf('lock table'),
          lessThan(rollbackStatements.indexOf('delete from rating_history;')));
    });

    test('and both take them in one order, so they cannot deadlock', () {
      String order(String text) {
        final start = text.indexOf('lock table');
        final end = text.indexOf('in share row exclusive mode', start);
        return text.substring(start, end);
      }

      // Alphabetical, and identical in both files.
      expect(order(statements), order(rollbackStatements));
      final names = RegExp(r'public\.(\w+)')
          .allMatches(order(statements))
          .map((m) => m.group(1)!)
          .toList();
      expect(names, names.toList()..sort());
    });
  });

  group('the rollback restores everything, or nothing', () {
    test('an unrestorable row refuses the ordinary rollback', () {
      expect(rollbackStatements,
          contains("raise exception 'REBASE_ROLLBACK_INCOMPLETE'"));
    });

    test('and it refuses before it has written anything', () {
      // The whole point: a refusal leaves the rebased state intact rather than
      // half of each.
      final counted =
          rollbackStatements.indexOf('into v_skipped, v_missing_users');
      final refusal =
          rollbackStatements.indexOf("raise exception 'REBASE_ROLLBACK_INCOMPLETE'");
      final firstWrite = rollbackStatements.indexOf('delete from rating_history;');

      expect(counted, isNot(-1));
      expect(counted, lessThan(refusal));
      expect(refusal, lessThan(firstWrite));
    });

    test('partial recovery is opt-in, never the default', () {
      expect(rollbackStatements, contains('p_allow_partial boolean default false'));
      expect(rollbackStatements, contains('if v_partial and not p_allow_partial then'));
      // Every grant and revoke moved to the new signature with it.
      expect(rollbackStatements,
          contains('public.rollback_rating_rebase(text, boolean)'));
      expect(rollbackStatements,
          isNot(contains('public.rollback_rating_rebase(text)')));
    });

    test('and a partial recovery is never recorded as a rollback', () {
      // `rolled_back_at` is what every other reader trusts -- including the
      // rebase's own one-time guard. A partial restoration gets its own
      // column, so nothing downstream can mistake the two.
      expect(rollbackStatements, contains('set rolled_back_partial_at = now()'));
      expect(rollbackStatements, contains('set rolled_back_at = now()'));
      expect(
        rollbackStatements.indexOf('set rolled_back_partial_at = now()'),
        lessThan(rollbackStatements.indexOf('set rolled_back_at = now()')),
        reason: 'the partial branch is the `if`, the complete one the `else`',
      );
      // And a run already undone either way cannot be undone again.
      expect(rollbackStatements,
          contains('v_run.rolled_back_partial_at is not null'));
    });

    test('the counts it reports name every kind of loss', () {
      for (final column in [
        'skipped_history_rows',
        'skipped_user_rows',
        'missing_users',
        'missing_matches',
        'partial boolean',
      ]) {
        expect(rollbackStatements, contains(column), reason: column);
      }
    });

    test('and the refusals that were already there still are', () {
      for (final refusal in [
        'REBASE_NOT_FOUND',
        'REBASE_NOT_COMPLETED',
        'REBASE_ALREADY_ROLLED_BACK',
        'REBASE_ARCHIVE_MISSING',
      ]) {
        expect(rollbackStatements, contains("raise exception '$refusal'"),
            reason: refusal);
      }
      for (final refusal in [
        'REBASE_ALREADY_COMPLETED',
        'REBASE_IN_PROGRESS',
        'REBASE_ARCHIVE_ALREADY_PRESENT',
      ]) {
        expect(statements, contains("raise exception '$refusal'"),
            reason: refusal);
      }
    });
  });

}
