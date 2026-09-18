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

    test('and it counts what it could not restore rather than failing', () {
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
}
