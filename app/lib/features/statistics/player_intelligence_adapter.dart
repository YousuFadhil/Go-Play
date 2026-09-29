/// Recent rating direction for one player.
///
/// It is deliberately separate from the career counters. Rating history is an
/// audit trail and this is only a read model over it: no second rating is
/// stored, and corrections/reversals are already netted by the database RPC.
class PlayerRatingTrend {
  const PlayerRatingTrend({
    required this.matchesCount,
    required this.ratingDelta,
  });

  final int matchesCount;
  final double ratingDelta;

  bool get hasMatches => matchesCount > 0;
}

/// Narrow read port for Player Intelligence that is not part of the ordinary
/// period statistics contract.
///
/// Keeping this separate means Community Statistics and its test doubles do not
/// gain a dependency on rating-history reads they never use.
abstract interface class PlayerIntelligenceAdapter {
  Future<PlayerRatingTrend> fetchRatingTrend(String userId);
}
