import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/infrastructure/supabase/statistics_period_window.dart';

/// How a period becomes the two columns `community_statistics` is keyed by.
///
/// This is the seam where a domain value meets the database's vocabulary, and
/// it is the one place in the app that has to agree with something written in
/// SQL: `statistics_period_key()` in migration `0028`, which buckets every
/// counter in Asia/Muscat and is marked FROZEN there. A disagreement here does
/// not fail — it quietly reads a different week than the one the counters were
/// written into — so the cases below are the ones where the two could most
/// easily drift apart.
void main() {
  /// Named instants, all UTC, so a test says which moment it means rather than
  /// depending on where it runs.
  DateTime utc(int y, int m, int d, [int h = 0, int min = 0]) =>
      DateTime.utc(y, m, d, h, min);

  group('period type', () {
    test('each period names its column value, All Time included', () {
      // `overall` is a period like any other in that table, with a fixed key.
      // All Time is a filter, not the absence of one.
      expect(StatisticsPeriodWindow.periodType(StatisticsPeriod.weekly),
          'weekly');
      expect(StatisticsPeriodWindow.periodType(StatisticsPeriod.monthly),
          'monthly');
      expect(StatisticsPeriodWindow.periodType(StatisticsPeriod.allTime),
          'overall');
    });

    test('All Time has the fixed key the check constraint requires', () {
      // `community_statistics_period_coherent` allows `('overall', 'overall')`
      // and nothing else for that type.
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.allTime,
            now: utc(2026, 8, 15)),
        'overall',
      );
    });
  });

  group('the key of the current period', () {
    test('a month is YYYY-MM', () {
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.monthly,
            now: utc(2026, 8, 15, 9)),
        '2026-08',
      );
    });

    test('a week is the ISO week, zero padded', () {
      // 15 August 2026 is a Saturday; its Thursday is the 13th, in week 33.
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.weekly,
            now: utc(2026, 8, 15, 9)),
        '2026-W33',
      );
    });

    test('an early week keeps its leading zero', () {
      // The database writes `IW`, which is always two digits. `2026-W1` would
      // not even satisfy the table's check constraint.
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.weekly,
            now: utc(2026, 1, 2, 9)),
        '2026-W01',
      );
    });

    test('a week belongs to the year that owns its Thursday', () {
      // 1 January 2027 is a Friday, so it is still 2026's fifty-third week —
      // `IYYY` is not the calendar year, and taking it from `year` would put
      // this read in a key that does not exist.
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.weekly,
            now: utc(2027, 1, 1, 9)),
        '2026-W53',
      );
      // And the last Thursday of that year is the same week.
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.weekly,
            now: utc(2026, 12, 31, 9)),
        '2026-W53',
      );
    });

    test('a year that begins on a Thursday begins in its own first week', () {
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.weekly,
            now: utc(2026, 1, 1, 9)),
        '2026-W01',
      );
    });
  });

  group('Asia/Muscat, and not the reader\'s clock', () {
    test('the late evening in UTC is already tomorrow in Muscat', () {
      // 20:00 UTC on Sunday 16 August is 00:00 on Monday the 17th in Muscat,
      // which is a new ISO week. A UTC reading would ask for week 33 while the
      // database had written the match into week 34.
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.weekly,
            now: utc(2026, 8, 16, 20)),
        '2026-W34',
      );
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.weekly,
            now: utc(2026, 8, 16, 19, 59)),
        '2026-W33',
      );
    });

    test('and can already be next month', () {
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.monthly,
            now: utc(2026, 8, 31, 20)),
        '2026-09',
      );
      expect(
        StatisticsPeriodWindow.periodKey(StatisticsPeriod.monthly,
            now: utc(2026, 8, 31, 19, 59)),
        '2026-08',
      );
    });
  });

  group('the window a completed match is counted in', () {
    test('All Time has no bounds, because it excludes nothing', () {
      expect(
        StatisticsPeriodWindow.bounds(StatisticsPeriod.allTime,
            now: utc(2026, 8, 15)),
        isNull,
      );
    });

    test('a week runs Monday to Monday, in Muscat', () {
      final bounds = StatisticsPeriodWindow.bounds(StatisticsPeriod.weekly,
          now: utc(2026, 8, 15, 9))!;

      // Monday 10 August 00:00 Muscat is Sunday 9 August 20:00 UTC.
      expect(bounds.from, utc(2026, 8, 9, 20));
      expect(bounds.to, utc(2026, 8, 16, 20));
      expect(bounds.to.difference(bounds.from), const Duration(days: 7));
    });

    test('a month runs from the first to the first, in Muscat', () {
      final bounds = StatisticsPeriodWindow.bounds(StatisticsPeriod.monthly,
          now: utc(2026, 8, 15, 9))!;

      expect(bounds.from, utc(2026, 7, 31, 20));
      expect(bounds.to, utc(2026, 8, 31, 20));
    });

    test('December rolls into January rather than into month thirteen', () {
      final bounds = StatisticsPeriodWindow.bounds(StatisticsPeriod.monthly,
          now: utc(2026, 12, 15, 9))!;

      expect(bounds.from, utc(2026, 11, 30, 20));
      expect(bounds.to, utc(2026, 12, 31, 20));
    });

    test('the window and the key describe the same stretch', () {
      // The two are used together — the counters come back by key and the match
      // count by window — so an instant inside the window must produce the key
      // the window was built for, at both ends of it.
      final now = utc(2026, 8, 15, 9);
      for (final period in [
        StatisticsPeriod.weekly,
        StatisticsPeriod.monthly,
      ]) {
        final bounds = StatisticsPeriodWindow.bounds(period, now: now)!;
        final key = StatisticsPeriodWindow.periodKey(period, now: now);

        expect(StatisticsPeriodWindow.periodKey(period, now: bounds.from), key);
        expect(
          StatisticsPeriodWindow.periodKey(
              period, now: bounds.to.subtract(const Duration(minutes: 1))),
          key,
        );
        // And the instant the window ends belongs to the next period, which is
        // what makes the interval half-open rather than a range that counts a
        // midnight match twice.
        expect(
          StatisticsPeriodWindow.periodKey(period, now: bounds.to),
          isNot(key),
        );
      }
    });
  });

  group('the period value itself', () {
    test('only the two windows are bounded', () {
      expect(StatisticsPeriod.weekly.isBounded, isTrue);
      expect(StatisticsPeriod.monthly.isBounded, isTrue);
      expect(StatisticsPeriod.allTime.isBounded, isFalse);
    });

    test('there are exactly three, and All Time is the default the app opens on',
        () {
      // The screens all start here. A fourth period, or a different default,
      // would change what every statistics surface shows on open.
      expect(StatisticsPeriod.values, hasLength(3));
      expect(StatisticsPeriod.values, contains(StatisticsPeriod.allTime));
    });
  });
}
