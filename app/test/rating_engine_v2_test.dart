import 'dart:io';

import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/results/rating_rules.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/infrastructure/supabase/mappers/result_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/team_mapper.dart';

/// The Rating Engine, from both sides — and from two migrations.
///
/// **What is current and what is history.** `0073` gave the engine its v2
/// *shape*: three-decimal precision, a participation entry, a draw entry, and
/// the reason vocabulary the audit is written in. `0078` then set what each
/// reason is worth and is the authoritative definition in force, so the Dart
/// mirror is held to `0078` and the group reviewing `0073`'s text is a review
/// of history — it says what that migration contained and is deliberately not
/// updated when the values move.
///
/// The Dart mirror (`ratingRules` / `ratingDeltasFor`) is exercised as
/// arithmetic; both migrations are reviewed as text, as every migration in this
/// repository is. The integration suite holds the mirror and the live database
/// to each other whenever the fixture accounts exist; the contract test at the
/// end of this file does it statically, from `0078`'s own text, so an
/// unavailable fixture can never leave the two unchecked.
void main() {
  TeamAssignment at(String userId, TeamId team) => TeamAssignment(
        userId: userId,
        team: team,
        assignedPosition: Position.mid,
        basis: null,
      );

  /// A two-a-side match: p and q on Team A, x and y on Team B.
  final lineup = [
    at('p', TeamId.a),
    at('q', TeamId.a),
    at('x', TeamId.b),
    at('y', TeamId.b),
  ];

  MatchResult result(int a, int b,
          {Map<String, int> goals = const {}, String? mvp}) =>
      MatchResult(
        matchId: 'm1',
        teamAScore: a,
        teamBScore: b,
        mvpUserId: mvp,
        goals: [
          for (final e in goals.entries)
            GoalTally(userId: e.key, goals: e.value),
        ],
      );

  double total(MatchResult r, String id, [List<TeamAssignment>? on]) =>
      ratingDeltasFor(r, on ?? lineup)
          .where((d) => d.userId == id)
          .fold(0.0, (sum, d) => sum + d.delta);

  group('the current values (0078)', () {
    test('win only is +0.105', () {
      expect(total(result(2, 1), 'p'), closeTo(0.105, 1e-9));
    });

    test('draw only is +0.015', () {
      expect(total(result(1, 1), 'p'), closeTo(0.015, 1e-9));
    });

    test('loss only is -0.095', () {
      expect(total(result(2, 1), 'x'), closeTo(-0.095, 1e-9));
    });

    test('win and one goal is +0.115', () {
      expect(total(result(2, 1, goals: {'p': 1}), 'p'), closeTo(0.115, 1e-9));
    });

    test('win and five goals is +0.155', () {
      expect(total(result(5, 1, goals: {'p': 5}), 'p'), closeTo(0.155, 1e-9));
    });

    test('win and seven goals reaches the cap: +0.175', () {
      expect(total(result(7, 1, goals: {'p': 7}), 'p'), closeTo(0.175, 1e-9));
    });

    test('win and eight goals is still +0.175: the cap holds', () {
      expect(total(result(8, 1, goals: {'p': 8}), 'p'), closeTo(0.175, 1e-9));
    });

    test('loss and five goals is -0.045', () {
      expect(total(result(1, 5, goals: {'p': 5}), 'p'), closeTo(-0.045, 1e-9));
    });

    test('loss, five goals and the MVP is -0.025', () {
      expect(
        total(result(1, 5, goals: {'p': 5}, mvp: 'p'), 'p'),
        closeTo(-0.025, 1e-9),
      );
    });

    test('the MVP alone is worth +0.020', () {
      final mvpOnly = ratingDeltasFor(result(2, 1, mvp: 'p'), lineup)
          .where((d) => d.userId == 'p' && d.reason == RatingChangeReason.mvp)
          .single;
      expect(mvpOnly.delta, closeTo(0.020, 1e-9));
    });

    test('a winner who did nothing else still outranks the best loser', () {
      // The invariant the values exist to keep, at its hardest case: the
      // losing side's best possible match is a capped seven goals and the MVP.
      // Team A wins 7-1 here, so `p` is the plain winner and `x` the loser who
      // did everything a loser can.
      final match = result(7, 1, goals: {'x': 7}, mvp: 'x');
      final winner = total(match, 'p');
      final loser = total(match, 'x');
      expect(winner, closeTo(0.105, 1e-9));
      expect(loser, closeTo(-0.005, 1e-9));
      expect(winner, greaterThan(loser));
    });

    test('the Dart mirror carries exactly the approved constants', () {
      expect(ratingRules.participation, 0.005);
      expect(ratingRules.win, 0.10);
      expect(ratingRules.draw, 0.01);
      expect(ratingRules.loss, -0.10);
      expect(ratingRules.goal, 0.01);
      expect(ratingRules.goalCap, 0.07);
      expect(ratingRules.mvp, 0.02);
    });
  });

  group('the order, and who is paid', () {
    test('participation, then outcome, then goal, then MVP', () {
      final reasons = [
        for (final d
            in ratingDeltasFor(result(2, 1, goals: {'p': 1}, mvp: 'p'), lineup))
          if (d.userId == 'p') d.reason,
      ];
      expect(reasons, [
        RatingChangeReason.participation,
        RatingChangeReason.win,
        RatingChangeReason.goal,
        RatingChangeReason.mvp,
      ]);
    });

    test('a draw writes a participation and a draw entry for everyone', () {
      final deltas = ratingDeltasFor(result(1, 1), lineup);
      for (final id in ['p', 'q', 'x', 'y']) {
        expect(
          [
            for (final d in deltas)
              if (d.userId == id) d.reason
          ],
          [RatingChangeReason.participation, RatingChangeReason.draw],
          reason: id,
        );
      }
    });

    test('a player named twice is paid participation once', () {
      final doubled = [...lineup, at('p', TeamId.a)];
      final entries = ratingDeltasFor(result(2, 1), doubled).where((d) =>
          d.userId == 'p' && d.reason == RatingChangeReason.participation);
      expect(entries, hasLength(1));
      expect(total(result(2, 1), 'p', doubled), closeTo(0.105, 1e-9));
    });
  });

  group('the clamp, and what the audit records', () {
    /// Each step clamped, as `apply_rating_delta` does, returning the movement
    /// actually applied at each step — which is what `rating_history.delta`
    /// stores.
    List<double> applied(double start, Iterable<double> steps) {
      var rating = start;
      final out = <double>[];
      for (final step in steps) {
        final after = clampRating(rating + step);
        out.add(after - rating);
        rating = after;
      }
      return out;
    }

    test('9.980 and a win stops at 10.000 and records only what moved', () {
      final steps = [
        for (final d in ratingDeltasFor(result(2, 1), lineup))
          if (d.userId == 'p') d.delta
      ];
      expect(applyRatingDeltas(9.98, steps), closeTo(10.0, 1e-9));
      final moved = applied(9.98, steps);
      expect(moved[0], closeTo(0.005, 1e-9), reason: 'participation');
      expect(moved[1], closeTo(0.015, 1e-9), reason: 'the win, clamped');
      expect(moved.fold(0.0, (a, b) => a + b), closeTo(0.02, 1e-9));
    });

    test('a loss near zero never goes below 0.000', () {
      final steps = [
        for (final d in ratingDeltasFor(result(2, 1), lineup))
          if (d.userId == 'x') d.delta
      ];
      expect(applyRatingDeltas(0.05, steps), closeTo(0.0, 1e-9));
      final moved = applied(0.05, steps);
      expect(moved[1], closeTo(-0.055, 1e-9), reason: 'only what was there');
    });

    test('an undo restores the rating exactly from the stored deltas', () {
      final steps = [
        for (final d
            in ratingDeltasFor(result(2, 1, goals: {'p': 2}, mvp: 'p'), lineup))
          if (d.userId == 'p') d.delta
      ];
      final moved = applied(6.4, steps);
      // Reversal applies each stored delta negated, most recent first.
      final after = applyRatingDeltas(6.4, steps);
      final restored =
          applyRatingDeltas(after, [for (final d in moved.reversed) -d]);
      expect(restored, closeTo(6.4, 1e-9));
    });
  });

  test('two players, the same record at different volumes', () {
    // Result and participation only. Four matches at 2W 2L against two at
    // 1W 1L: turning up more is worth something, and exactly this much.
    final win = total(result(2, 1), 'p');
    final loss = total(result(2, 1), 'x');
    expect(2 * win + 2 * loss, closeTo(0.020, 1e-9));
    expect(win + loss, closeTo(0.010, 1e-9));
  });

  group('reading v2 history back', () {
    test('both new reasons map, and the old ones still do', () {
      expect(ratingChangeReasonFromDb('PARTICIPATION'),
          RatingChangeReason.participation);
      expect(ratingChangeReasonFromDb('DRAW'), RatingChangeReason.draw);
      for (final (db, reason) in [
        ('WIN', RatingChangeReason.win),
        ('LOSS', RatingChangeReason.loss),
        ('GOAL', RatingChangeReason.goal),
        ('MVP', RatingChangeReason.mvp),
        ('REVERSAL', RatingChangeReason.reversal),
      ]) {
        expect(ratingChangeReasonFromDb(db), reason);
      }
    });

    test('a reason nothing knows is still refused, as before', () {
      expect(() => ratingChangeReasonFromDb('BONUS'),
          throwsA(isA<InfrastructureFailure>()));
    });

    test('a three-decimal rating keeps its third decimal', () {
      expect(ratingFromDb('5.105'), 5.105);
      expect(ratingFromDb(5.105), 5.105);
      // A pre-v2 value is the same number at the new precision.
      expect(ratingFromDb('5.320'), ratingFromDb('5.32'));
    });

    test('the football screen still shows two decimals', () {
      final source = File(
        'lib/features/football/football_community_screen.dart',
      ).readAsStringSync();
      expect(source, contains('overallRating.toStringAsFixed(2)'));
      expect(6.487.toStringAsFixed(2), '6.49');
    });
  });

  // **History, not current behaviour.** This group reviews the file `0073`
  // shipped: its values were superseded by `0078` and these assertions are
  // deliberately left as they are, because what a historical migration
  // contained does not change.
  group('what migration 0073 says', () {
    const path =
        '../supabase/migrations/0073_rating_precision_and_participation.sql';
    final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');
    final code =
        sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
    String fn(String name) {
      final start = code.indexOf('create or replace function public.$name(');
      return code.substring(start, code.indexOf('\n\$\$;', start));
    }

    const views = [
      'v_community_members',
      'v_user_profile',
      'v_player_statistics',
      'v_match_registrations',
      'v_match_teams',
      'v_football_match_lineup',
      'v_football_match_participants',
      'v_football_community_player_stats',
    ];
    const invoker = {
      'v_community_members',
      'v_user_profile',
      'v_player_statistics',
      'v_match_registrations',
      'v_match_teams',
    };

    /// One recreated view's statement. The invoker views put a newline after
    /// the name (`… public.v_x\nwith (security_invoker = on) as`) and the
    /// football views a space, so the name is matched on a word boundary.
    String view(String v) {
      final match = RegExp('create view public\\.$v\\b').firstMatch(code);
      if (match == null) throw StateError('0073 does not recreate $v');
      return code.substring(match.start, code.indexOf(';\n', match.start));
    }

    test('it drops exactly the eight views, by name, never cascade', () {
      for (final v in views) {
        expect(code, contains('drop view public.$v;'), reason: v);
      }
      expect(RegExp('drop view').allMatches(code).length, 8);
      expect(code.toLowerCase(), isNot(contains('cascade')));
    });

    test('it widens four columns and recalculates nothing', () {
      expect(code, contains('alter column overall_rating type numeric(5,3)'));
      for (final c in ['delta', 'rating_before', 'rating_after']) {
        expect(code, contains('alter column $c type numeric(5,3)'), reason: c);
      }
      expect(code, isNot(contains('numeric(4,2)')));
      expect(code, isNot(contains('numeric(4,3)')));
      expect(RegExp(r'^\s*update ', multiLine: true).allMatches(code).length, 1,
          reason: 'only the one inside apply_rating_delta');
    });

    test('the reason check admits the two new reasons', () {
      expect(code,
          contains('drop constraint rating_history_change_reason_check;'));
      expect(code, isNot(contains('drop constraint if exists')));
      expect(
          code,
          contains("'PARTICIPATION', 'WIN', 'DRAW', 'LOSS', 'GOAL', "
              "'MVP', 'REVERSAL'"));
    });

    test('apply_rating_delta clamps at three decimals and stores what moved',
        () {
      final body = fn('apply_rating_delta');
      expect(body, contains('v_before numeric(5,3);'));
      expect(body, contains('v_after numeric(5,3);'));
      expect(
          body, contains('least(10.000, greatest(0.000, v_before + p_delta))'));
      expect(body, contains('v_after - v_before'));
      expect(body, contains('if p_user_id is null then return; end if;'));
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
    });

    test('apply_match_rating_effects ran the four steps in 0073\'s order', () {
      // The values below are 0073's own and are not the engine's current ones
      // -- see the `0078` group at the end of this file.
      final body = fn('apply_match_rating_effects');
      final order = [
        "'PARTICIPATION', 0.005",
        "'DRAW', 0.010",
        "'WIN', 0.100",
        "'LOSS', -0.100",
        "'GOAL', least(0.100, 0.020 * r.goals)",
        "'MVP', 0.050",
      ];
      for (final step in order) {
        expect(body, contains(step), reason: step);
      }
      expect(body.indexOf("'PARTICIPATION'"), lessThan(body.indexOf("'DRAW'")));
      expect(body.indexOf("'LOSS'"), lessThan(body.indexOf("'GOAL'")));
      expect(body.indexOf("'GOAL'"), lessThan(body.indexOf("'MVP'")));
      // Guests receive nothing, and participation is paid once per player.
      expect(RegExp('a.user_id is not null').allMatches(body).length, 2);
      expect(body, contains('g.user_id is not null'));
      expect(body, contains('group by a.user_id\n    order by a.user_id'));
    });

    test('each view comes back with its setting, comment and privileges', () {
      for (final v in views) {
        final text = view(v);
        expect(text.contains('security_invoker = on'), invoker.contains(v),
            reason: '$v security_invoker');
        expect(code, contains('comment on view public.$v is'), reason: v);
        expect(code, contains('grant select on public.$v to authenticated;'),
            reason: v);
        expect(code, isNot(contains('on public.$v to anon')), reason: v);
      }
    });

    test('recreation neither broadens nor narrows who can read a view', () {
      for (final v in views) {
        // anon loses everything explicitly, the view is never granted to
        // public, and authenticated keeps exactly one SELECT grant.
        expect(RegExp('revoke all on public\\.$v from anon\\b').hasMatch(code),
            isTrue,
            reason: '$v revokes anon');
        expect(
            RegExp('grant [a-z, ]+ on public\\.$v to [^;]*\\b(anon|public)\\b')
                .hasMatch(code),
            isFalse,
            reason: '$v grants nothing to anon or public');
        expect(
            RegExp('grant select on public\\.$v to authenticated;')
                .allMatches(code)
                .length,
            1,
            reason: '$v authenticated select');
      }
      // The football views were never invoker views: no options clause at all,
      // so neither `on` nor an explicit `off` was introduced.
      for (final v in views.where((v) => !invoker.contains(v))) {
        expect(view(v), startsWith('create view public.$v as\n'), reason: v);
        expect(view(v), isNot(contains('security_invoker')), reason: v);
      }
      expect(invoker, {
        'v_community_members',
        'v_user_profile',
        'v_player_statistics',
        'v_match_registrations',
        'v_match_teams',
      });
    });

    test('no read model narrows the rating any more', () {
      for (final v in [
        'v_player_statistics',
        'v_football_community_player_stats'
      ]) {
        expect(
            view(v),
            contains(
                'coalesce(u.overall_rating, 5.0)::numeric(5,3) as overall_rating'),
            reason: v);
      }
    });

    test('corrections, PFS and Team of Period are left alone', () {
      expect(code, isNot(contains('reverse_match_rating_effects')));
      for (final untouched in [
        'period_form_score_v1',
        'period_goal_form_v1',
        'period_xi_required_matches',
        'community_period_xi',
      ]) {
        expect(code, isNot(contains(untouched)), reason: untouched);
      }
      expect(code, isNot(contains('grant execute')));
    });
  });

  // --------------------------------------------------------------------------
  // The current contract: the Dart mirror against migration 0078's own text.
  //
  // This is what makes "the Dart constants are the database's constants" a
  // checked fact rather than an intention. It runs everywhere, with no fixture
  // accounts and no network, so an unavailable integration environment cannot
  // leave the two unchecked -- and it reads the numbers out of the migration
  // rather than restating them, so a future migration that changes a value
  // fails here until the mirror follows it.
  group('what migration 0078 says, and what Dart must match', () {
    const path = '../supabase/migrations/0078_rating_goal_mvp_values.sql';
    final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');
    final code =
        sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

    /// The number `0078` passes `apply_rating_delta` for [reason].
    double valueFor(String reason) {
      final match = RegExp("'$reason',\\s*(-?[0-9.]+)").firstMatch(code);
      if (match == null) throw StateError('0078 does not apply $reason');
      return double.parse(match.group(1)!);
    }

    test('it is still the migration the database runs', () {
      // 0078 replaces the whole of apply_match_rating_effects, which is what
      // makes it the authoritative definition rather than a patch on one line.
      expect(
          code,
          contains(
              'create or replace function public.apply_match_rating_effects('));
      expect(code, contains('security definer'));
      expect(code, contains('set search_path = public'));
      expect(
        code,
        contains(
            'revoke execute on function public.apply_match_rating_effects(uuid)'),
      );
    });

    test('every constant in the Dart mirror is the one 0078 applies', () {
      expect(ratingRules.participation, valueFor('PARTICIPATION'));
      expect(ratingRules.draw, valueFor('DRAW'));
      expect(ratingRules.win, valueFor('WIN'));
      expect(ratingRules.loss, valueFor('LOSS'));
      expect(ratingRules.mvp, valueFor('MVP'));
    });

    test('and so are the goal award and its cap', () {
      final goal =
          RegExp(r"'GOAL', least\((-?[0-9.]+), (-?[0-9.]+) \* r.goals\)")
              .firstMatch(code);
      expect(goal, isNotNull, reason: '0078 must cap the goal award');
      expect(ratingRules.goalCap, double.parse(goal!.group(1)!));
      expect(ratingRules.goal, double.parse(goal.group(2)!));
    });

    test('the approved values, written out once', () {
      // The Product Owner's list, so a reader of this suite can check the file
      // against the decision without opening the migration.
      expect(valueFor('PARTICIPATION'), 0.005);
      expect(valueFor('WIN'), 0.100);
      expect(valueFor('DRAW'), 0.010);
      expect(valueFor('LOSS'), -0.100);
      expect(valueFor('MVP'), 0.020);
      expect(ratingRules.goal, 0.010);
      expect(ratingRules.goalCap, 0.070);
    });

    test('nothing in it backfills or recomputes a stored rating', () {
      for (final forbidden in [
        'update rating_history',
        'update users',
        'delete from',
        'truncate',
      ]) {
        expect(code.toLowerCase(), isNot(contains(forbidden)),
            reason: forbidden);
      }
    });
  });
}
