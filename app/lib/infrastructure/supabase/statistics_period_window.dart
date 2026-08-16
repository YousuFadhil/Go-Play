import '../../features/statistics/statistics_period.dart';

/// The database's period vocabulary, restated on the client side of the wire.
///
/// `community_statistics` keys every record by `(period_type, period_key)`, and
/// migration `0028` fixes both: the type is one of `overall`, `weekly` or
/// `monthly`, and the key is `'overall'`, an ISO week (`2026-W31`) or a month
/// (`2026-08`) — all three derived from the match's start in **Asia/Muscat**,
/// which `statistics_period_zone()` marks FROZEN.
///
/// **This does not compute a statistic, and it does not decide which week a
/// match belongs to.** Every counter was bucketed by the database when the
/// result was recorded, and nothing here re-buckets anything. What this answers
/// is only *which of the buckets already stored is the current one* — the
/// question a `where period_key = ?` has to carry, and the one the client
/// cannot ask any other way: `statistics_period_key()` is deliberately revoked
/// from `authenticated` (`0028` §9), and this cycle adds no database object to
/// expose it.
///
/// It is therefore provider-specific and lives here, behind the adapter, with
/// the column names and the table name. No domain model and no widget knows
/// that a period has a key at all.
///
/// **The zone is a fixed offset, not a lookup.** Oman has observed UTC+04:00
/// without daylight saving for the whole life of any data this reads, so the
/// offset is stated rather than carried in a time-zone package — which is also
/// why this file adds no dependency. If that ever stops being true, this
/// constant and the database's `statistics_period_zone()` have to move
/// together, and the database is the authority.
abstract final class StatisticsPeriodWindow {
  static const _muscatOffset = Duration(hours: 4);

  /// The `period_type` column value for [period].
  ///
  /// `overall` is a period like any other in that table, with a fixed key —
  /// which is why All Time is a value here rather than the absence of a filter.
  static String periodType(StatisticsPeriod period) => switch (period) {
        StatisticsPeriod.weekly => 'weekly',
        StatisticsPeriod.monthly => 'monthly',
        StatisticsPeriod.allTime => 'overall',
      };

  /// The `period_key` of the period [period] names right now.
  ///
  /// [now] is injectable so a test can name an instant rather than wait for
  /// one; production passes nothing and gets the clock.
  static String periodKey(StatisticsPeriod period, {DateTime? now}) {
    if (period == StatisticsPeriod.allTime) return 'overall';

    final local = _muscatWallClock(now);
    return switch (period) {
      StatisticsPeriod.weekly => _isoWeekKey(local),
      StatisticsPeriod.monthly =>
        '${_pad(local.year, 4)}-${_pad(local.month, 2)}',
      StatisticsPeriod.allTime => 'overall',
    };
  }

  /// The half-open interval `[from, to)` in UTC that [period] covers, or null
  /// for All Time — which covers everything and therefore filters nothing.
  ///
  /// Used for the completed-match count, which is a fact about matches and so
  /// cannot come from the counters (see `CommunityDashboard`). The boundaries
  /// are derived from the same wall clock as [periodKey], so a match counted in
  /// a week is a match whose counters landed in that week's records.
  static ({DateTime from, DateTime to})? bounds(
    StatisticsPeriod period, {
    DateTime? now,
  }) {
    if (period == StatisticsPeriod.allTime) return null;

    final local = _muscatWallClock(now);
    final (start, end) = switch (period) {
      StatisticsPeriod.weekly => (
          // ISO weeks start on Monday. `weekday` is 1..7 with Monday at 1.
          _midnight(local).subtract(Duration(days: local.weekday - 1)),
          _midnight(local)
              .subtract(Duration(days: local.weekday - 1))
              .add(const Duration(days: 7)),
        ),
      StatisticsPeriod.monthly => (
          DateTime.utc(local.year, local.month),
          // Month 13 rolls into January of the next year, which `DateTime.utc`
          // normalizes; no branch on December is needed.
          DateTime.utc(local.year, local.month + 1),
        ),
      StatisticsPeriod.allTime => (local, local),
    };

    // Both are Muscat wall clocks expressed as UTC values; subtracting the
    // offset turns each into the instant it actually names.
    return (
      from: start.subtract(_muscatOffset),
      to: end.subtract(_muscatOffset),
    );
  }

  /// The Muscat wall clock at [now], carried as a UTC `DateTime` so that every
  /// calculation above is plain arithmetic with no local zone in it.
  static DateTime _muscatWallClock(DateTime? now) =>
      (now ?? DateTime.now()).toUtc().add(_muscatOffset);

  static DateTime _midnight(DateTime local) =>
      DateTime.utc(local.year, local.month, local.day);

  /// `to_char(..., 'IYYY-"W"IW')`, computed the way ISO-8601 defines it: a week
  /// belongs to the year that owns its Thursday, so both the year and the number
  /// are taken from that Thursday rather than from the day itself. Without it,
  /// the days either side of New Year land in the wrong year's week — which is
  /// exactly where the database and the client would silently disagree.
  static String _isoWeekKey(DateTime local) {
    final date = _midnight(local);
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final dayOfYear =
        thursday.difference(DateTime.utc(thursday.year)).inDays + 1;
    final week = (dayOfYear - 1) ~/ 7 + 1;
    return '${_pad(thursday.year, 4)}-W${_pad(week, 2)}';
  }

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');
}
