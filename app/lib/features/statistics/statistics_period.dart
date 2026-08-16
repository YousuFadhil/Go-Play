/// Which stretch of history a set of statistics describes.
///
/// The statistics table has held three periods per player since migration
/// `0028` — the running total, the week and the month — and until now the app
/// read only the first. This is the one value that says which of them a screen
/// is asking for, and it carries no database vocabulary: `period_type`,
/// `'overall'` and the shape of a period key are the provider's business and
/// live in the Supabase adapter alone (OP-3).
///
/// **A period is not a time zone.** Which week a match falls in is decided by
/// the database, in Asia/Muscat, and frozen there — nothing above this layer
/// re-derives it, and no screen may.
enum StatisticsPeriod {
  /// The current ISO week.
  weekly,

  /// The current calendar month.
  monthly,

  /// Everything, from the first recorded result onwards. The period the app
  /// has always shown, and still the one it opens on.
  allTime;

  /// True for the two periods that name a window rather than the whole record.
  ///
  /// The distinction is real in more than one place — a period record exists
  /// only for a period the player actually played in, and the Global Rating has
  /// no periodic form — so it is stated once here rather than as a comparison
  /// against `allTime` repeated at each site.
  bool get isBounded => this != StatisticsPeriod.allTime;
}
