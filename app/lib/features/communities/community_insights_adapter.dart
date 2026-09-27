/// Organizer-facing Community Intelligence for the rolling last 30 days.
///
/// Every value is derived from existing current-state evidence. Participation
/// and capacity are provisional until Actual Participation evidence exists.
class CommunityInsights {
  const CommunityInsights({
    required this.eligibleMembers,
    required this.activeMembers30d,
    required this.participationRate30d,
    required this.matches30d,
    required this.matchesPerWeek,
    required this.avgCapacityUtilization,
    required this.guestDependency,
  });

  final int eligibleMembers;
  final int activeMembers30d;
  final double? participationRate30d;
  final int matches30d;
  final double matchesPerWeek;
  final double? avgCapacityUtilization;
  final double? guestDependency;
}

abstract interface class CommunityInsightsAdapter {
  Future<CommunityInsights> fetch(String communityId);
}
