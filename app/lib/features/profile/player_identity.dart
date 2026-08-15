import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/l10n.dart';
import 'profile_screen.dart';

/// How a participant is presented, wherever one appears.
///
/// The approved rule is one sentence: **a registered Community Player is drawn
/// with their face beside their name and opens their Player Profile; a
/// Professional Guest is drawn as one and opens nothing.** This file is that
/// sentence as code, so the twelve screens that show a participant cannot
/// answer it differently.
///
/// Three things live here and nothing else:
///
///   * [PlayerAvatar] — the face, including the guest treatment;
///   * [openPlayerProfile] — the one navigation, into the one Player Profile;
///   * [PlayerIdentityTap] — a tap target for the identity *alone*, used where
///     the row itself already belongs to a management action.
///
/// There is no participant model here and no data of any kind. Every caller
/// already holds a name, an optional picture and whichever identity the row
/// carries; this decides only what those look like and what happens when the
/// reader touches them.

/// A participant's face.
///
/// **Community player.** Delegates to [UserAvatar], which is the app's existing
/// avatar: the stored picture when there is one, the player's initials when
/// there is not, and a person icon when there is not even a name. Reusing it is
/// what makes a face the same object in a roster, on a pitch and in the header,
/// rather than three drawings that happen to be round.
///
/// **Professional Guest.** Never delegates, and never takes a URL. A guest has
/// no account and therefore no picture, so there is nothing to load and nothing
/// that could be loaded by mistake — the tertiary disc and the badge icon are
/// the whole of it, and they are the same treatment the roster has used to mark
/// a guest since they were introduced.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    this.avatarUrl,
    this.fullName,
    this.isProfessionalGuest = false,
    this.radius = 18,
  });

  /// Where the player's picture is. Null when they have not set one — which is
  /// an initials avatar, not a broken one.
  final String? avatarUrl;

  /// The participant's own name, used for initials. For a guest it is not read
  /// at all: a guest is marked as a guest, not lettered.
  final String? fullName;

  final bool isProfessionalGuest;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (isProfessionalGuest) {
      final scheme = Theme.of(context).colorScheme;
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.tertiaryContainer,
        foregroundColor: scheme.onTertiaryContainer,
        child: Icon(Icons.workspace_premium_outlined, size: radius * 1.1),
      );
    }

    return UserAvatar(
      avatarUrl: avatarUrl,
      fullName: fullName,
      radius: radius,
    );
  }
}

/// Opens [userId]'s Player Profile — the existing screen, told whose record to
/// read.
///
/// The one navigation, deliberately. `ProfileScreen` is the Player Profile and
/// there is no second implementation of it; a caller that wanted its own would
/// be a caller that could get visibility wrong.
///
/// **Nothing here decides whether the profile may be read.** That is
/// `player_profile` (migration `0043`) answering against the caller's own
/// session, and `ProfileScreen` wording the refusal when the answer is no. A
/// name being tappable is not a claim that the record behind it is readable —
/// it is an offer to ask, and the server is what answers.
Future<void> openPlayerProfile(BuildContext context, String userId) =>
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
    );

/// A tap target around a participant's identity, and only their identity.
///
/// Used where the row already belongs to something else — a drag handle, a
/// remove button, a swap selection, a goal stepper. Making the whole row
/// navigate in those places would take the management gesture away, so the
/// avatar and the name become the profile control and the rest of the row keeps
/// what it had.
///
/// [userId] null renders the child untouched and unlabelled, which is what a
/// Professional Guest gets: they have no profile, so there is nothing to offer
/// and no affordance suggesting there is.
class PlayerIdentityTap extends StatelessWidget {
  const PlayerIdentityTap({
    super.key,
    required this.userId,
    required this.child,
    this.enabled = true,
    this.borderRadius,
  });

  /// Whose profile to open. Null for a Professional Guest.
  final String? userId;

  /// False while the screen is busy, so a profile cannot be opened out from
  /// under a write that is still running.
  final bool enabled;

  final BorderRadius? borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final id = userId;
    if (id == null || !enabled) return child;

    return Semantics(
      button: true,
      label: context.l10n.openPlayerProfileAction,
      child: InkWell(
        borderRadius: borderRadius ?? BorderRadius.circular(999),
        onTap: () => openPlayerProfile(context, id),
        child: child,
      ),
    );
  }
}
