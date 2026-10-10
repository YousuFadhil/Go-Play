import '../../../features/settings/account_deletion_models.dart';

// Conversion from `preview_my_account_deletion` (migration `0102`) to the Domain
// Model. Read defensively: a document this build cannot fully read is treated as
// BLOCKED, never as clear -- inventing a "nothing in the way" is the worse mistake.

int _count(Object? value) => value is num ? value.toInt() : 0;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

MyAccountDeletionPreview myAccountDeletionPreviewFromJson(
  Map<String, dynamic> json,
) {
  final findings = json['findings'];
  final blockers = <String>{
    if (findings is List)
      for (final f in findings)
        if (f is Map && f['severity'] == 'BLOCKER' && f['code'] is String)
          f['code'] as String,
  };
  final owned = _map(json['owned_communities']);
  final items = owned['items'];

  return MyAccountDeletionPreview(
    // An explicit `false` with no blocker finding is the only "clear".
    hasBlockers: json['has_blockers'] != false || blockers.isNotEmpty,
    blockers: blockers,
    ownedCommunities: [
      if (items is List)
        for (final item in items)
          if (item is Map && item['community_id'] is String)
            OwnedCommunity(
              id: item['community_id'] as String,
              name: item['name'] is String ? item['name'] as String : '',
              memberCount: _count(item['member_count']),
            ),
    ],
    ownedTotal: _count(owned['total']),
    upcomingRegistrations: _count(json['upcoming_registrations']),
  );
}
