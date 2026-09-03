import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/tokens.dart';
import '../profile/player_identity.dart';

/// One member of a community, as a card in a grid.
///
/// Replaces the [ListTile] the roster used, which spent a full line of the
/// screen on a face and two short words. Three of these fit across a phone, so a
/// roster a reader used to scroll now reads as a squad.
///
/// **Four things, and deliberately only four.** A face, a name, a position, and
/// a role where there is one. Not a rating, not a record, not when they joined,
/// and no controls: the reason this is a roster and not a management screen is
/// that everything which *acts* on a member lives in Member Management, and a
/// card carrying a button here would be a second place to do it.
class CommunityMemberCard extends StatelessWidget {
  const CommunityMemberCard({
    super.key,
    required this.userId,
    required this.fullName,
    required this.positionLabel,
    this.avatarUrl,
    this.roleLabel,
  });

  final String userId;
  final String fullName;

  /// Already localized by the caller, which is where the position words live.
  final String positionLabel;

  final String? avatarUrl;

  /// Owner or Admin. Null for a player, which is most of a roster — the absence
  /// is the ordinary case and it is what keeps the grid quiet.
  final String? roleLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: GoColors.surfaceCard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // The whole card, as the whole tile did before it. A name in a roster is
        // a player and a player has a record; nothing else on this card claims
        // the tap, because nothing else on it is a control.
        onTap: () => openPlayerProfile(context, userId),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // A circle, because a circle is a person in this product and a
              // community's crest is a rounded square. The two appear beside
              // each other often enough that the shape carries the difference.
              PlayerAvatar(
                  avatarUrl: avatarUrl, fullName: fullName, radius: 22),
              const SizedBox(height: Gap.sm),
              // Two lines at a size that is still a name. An Arabic name is
              // routinely longer than the column and wrapping it is the
              // approved answer — shrinking the type until it fits would make
              // the roster unreadable to keep it tidy.
              Text(
                fullName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: GoColors.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                positionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  color: GoColors.onSurfaceVariant,
                ),
              ),
              // The badge is what makes card heights differ, so the space it
              // would occupy is held whether or not there is one. A roster with
              // one owner among eleven players otherwise draws one card taller
              // than the rest of its row.
              const SizedBox(height: Gap.sm),
              SizedBox(
                height: _roleSlotHeight,
                child: roleLabel == null
                    ? null
                    : Align(
                        alignment: Alignment.topCenter,
                        child: GoRoleChip(label: roleLabel!),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The height a [GoRoleChip] draws at: its 10.5px label at 1.6 line height,
  /// plus the 3px it is padded by above and below.
  static const double _roleSlotHeight = 23;
}
