import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/rating_format.dart';
import 'package:go_play/features/results/weighted_rating.dart';

void main() {
  test('neutral prior and frozen first-match golden values', () {
    expect(weightedRating([]), 5);
    expect(weightedRating([const RatedMatch(MatchOutcome.win)]),
        closeTo(5.2578687127024715, 1e-12));
    expect(weightedRating([const RatedMatch(MatchOutcome.loss)]),
        closeTo(4.660699062233589, 1e-12));
  });

  test('recurrence equals independent normalised closed-form weighting', () {
    final matches = List.generate(
        120,
        (i) => RatedMatch(MatchOutcome.values[i % 3],
            goals: i % 11, mvp: i % 7 == 0));
    const q = 26 / 27;
    final n = matches.length;
    var numerator = 70 * math.pow(q, n);
    var denominator = 14 * math.pow(q, n);
    var sum = 70.0;
    for (var i = 0; i < n; i++) {
      final w = math.pow(q, n - 1 - i);
      numerator += w * matches[i].score;
      denominator += w;
      sum += matches[i].score;
    }
    expect(weightedRating(matches),
        closeTo((sum / (14 + n) + numerator / denominator) / 2, 1e-12));
  });

  test(
      'more goals and MVP improve each outcome without saturating at seven goals',
      () {
    for (final outcome in MatchOutcome.values) {
      var previous = -1.0;
      for (final goals in [0, 1, 2, 7, 8, 100, 1000000]) {
        final score = RatedMatch(outcome, goals: goals).score;
        final mvp = RatedMatch(outcome, goals: goals, mvp: true).score;
        expect(score, greaterThan(previous));
        expect(mvp, greaterThan(score));
        expect(mvp, lessThan(10));
        previous = score;
      }
    }
    expect(() => const RatedMatch(MatchOutcome.win, goals: -1).score,
        throwsArgumentError);
  });

  test(
      'eighty wins and twenty losses never become ten; recent results weigh more',
      () {
    final wins = List.filled(
        80, const RatedMatch(MatchOutcome.win, goals: 1000, mvp: true));
    final losses = List.filled(20, const RatedMatch(MatchOutcome.loss));
    expect(weightedRating([...wins, ...losses]), lessThan(10));
    expect(weightedRating([...losses, ...wins]), lessThan(10));
    expect(weightedRating([...losses, ...wins]),
        greaterThan(weightedRating([...wins, ...losses])));
  });

  test(
      'rounding cannot invent a perfect rating, and ordering retains three decimals',
      () {
    expect(storedWeightedRating(9.99999), 9.999);
    expect(formatPlayerRating(9.949), '9.9');
    expect(formatPlayerRating(9.951), '9.9');
    expect(formatPlayerRating(9.999), '9.9');
    expect(formatPlayerRating(10), '10.0'); // historical/community exact ten
    expect(formatPlayerRating(5.258), '5.3');
    expect(storedWeightedRating(5.2511),
        greaterThan(storedWeightedRating(5.2501)));
  });
}
