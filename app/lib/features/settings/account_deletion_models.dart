/// A community the signed-in user owns, as the deletion screen lists it.
class OwnedCommunity {
  const OwnedCommunity({
    required this.id,
    required this.name,
    required this.memberCount,
  });

  final String id;
  final String name;
  final int memberCount;
}

/// What stands in the way of the signed-in user deleting their own account
/// (migration `0102`, `preview_my_account_deletion`).
///
/// A statement about this preview only: the database asks again, inside its own
/// transaction, when the deletion is requested. [hasBlockers] is therefore read
/// defensively -- anything but an explicit "no" counts as blocked.
class MyAccountDeletionPreview {
  const MyAccountDeletionPreview({
    required this.hasBlockers,
    required this.blockers,
    required this.ownedCommunities,
    required this.ownedTotal,
    required this.upcomingRegistrations,
  });

  final bool hasBlockers;

  /// The codes of the findings that block: `OWNS_COMMUNITIES`,
  /// `TARGET_IS_SYSTEM_ADMIN`, `ACCOUNT_SUSPENDED`.
  final Set<String> blockers;

  /// The communities the user owns, at most the first 25, by name.
  final List<OwnedCommunity> ownedCommunities;
  final int ownedTotal;

  /// Places in matches not yet played, which the deletion gives up.
  final int upcomingRegistrations;

  bool get ownsCommunities => blockers.contains('OWNS_COMMUNITIES');
  bool get isSystemAdmin => blockers.contains('TARGET_IS_SYSTEM_ADMIN');
  bool get isSuspended => blockers.contains('ACCOUNT_SUSPENDED');
}
