import 'package:flutter/material.dart';

import '../../core/l10n.dart';

/// How a kind of notice looks in the Notification Center.
///
/// **This is the client half of `notification_types`.** The database decides
/// what a type *means* — its priority, its category, whether it is worth a push
/// — and this decides what it *looks like*. The two are separate tables of the
/// same vocabulary, and adding a type means adding a row to each.
///
/// A map rather than a switch, and the reason is the failure it prevents. Three
/// switches over sixteen types — text, icon, colour — drift: a type gets a case
/// in one and is forgotten in the others, and nothing says so. One entry per
/// type cannot be half-added.
class NotificationDisplay {
  const NotificationDisplay({
    required this.icon,
    required this.tone,
    required this.label,
  });

  final IconData icon;
  final NotificationTone tone;

  /// Resolved against the reader's language, not stored.
  ///
  /// `notifications.message` is written by the producing operation inside the
  /// database, which has no idea who will read it — every stored message in the
  /// repository is Arabic. The text below is the notice's real content; the
  /// stored message is only the fallback for a type with no entry here.
  final String Function(AppLocalizations) label;
}

/// What a notice is, in the only three registers the list needs.
///
/// Not one colour per type. Sixteen colours is a legend, not a list — the
/// question a player is answering as they scan is "did I lose something, gain
/// something, or is this just news?"
enum NotificationTone {
  /// Something was taken away.
  alert,

  /// Something was gained.
  positive,

  /// Something changed.
  neutral;

  /// Theme colours rather than fixed ones, so the list follows the app.
  (Color background, Color foreground) colours(ColorScheme scheme) =>
      switch (this) {
        NotificationTone.alert => (
            scheme.errorContainer,
            scheme.onErrorContainer,
          ),
        NotificationTone.positive => (
            scheme.primaryContainer,
            scheme.onPrimaryContainer,
          ),
        NotificationTone.neutral => (
            scheme.secondaryContainer,
            scheme.onSecondaryContainer,
          ),
      };
}

/// Every type registered in `notification_types`, in the same order.
///
/// Ten of these have no producer yet. They are here for the same reason they
/// are in the database registry: so that the branch adding a producer adds a
/// producer and nothing else.
final Map<String, NotificationDisplay> notificationDisplays = {
  // Match lifecycle — the six that exist today.
  'promoted': NotificationDisplay(
    icon: Icons.arrow_upward,
    tone: NotificationTone.positive,
    label: (l10n) => l10n.notifPromoted,
  ),
  'moved_to_reserve': NotificationDisplay(
    icon: Icons.hourglass_top,
    tone: NotificationTone.alert,
    label: (l10n) => l10n.notifMovedToReserve,
  ),
  'removed': NotificationDisplay(
    icon: Icons.person_remove,
    tone: NotificationTone.alert,
    label: (l10n) => l10n.notifRemoved,
  ),
  'match_updated': NotificationDisplay(
    icon: Icons.edit_calendar,
    tone: NotificationTone.neutral,
    label: (l10n) => l10n.notifMatchUpdated,
  ),
  // The business event is "match cancelled"; the type keeps the name its
  // producers write. See migration 0036 §1.
  'match_deleted': NotificationDisplay(
    icon: Icons.delete_forever,
    tone: NotificationTone.alert,
    label: (l10n) => l10n.notifMatchDeleted,
  ),

  // Produced by `create_match` since migration 0039, for every member of the
  // community except the admin who created it.
  'match_created': NotificationDisplay(
    icon: Icons.add_circle_outline,
    tone: NotificationTone.positive,
    label: (l10n) => l10n.notifMatchCreated,
  ),

  // Registered, not yet produced.
  'registration_opened': NotificationDisplay(
    icon: Icons.how_to_reg,
    tone: NotificationTone.positive,
    label: (l10n) => l10n.notifRegistrationOpened,
  ),
  'match_full': NotificationDisplay(
    icon: Icons.group,
    tone: NotificationTone.neutral,
    label: (l10n) => l10n.notifMatchFull,
  ),
  'teams_regenerated': NotificationDisplay(
    icon: Icons.shuffle,
    tone: NotificationTone.neutral,
    label: (l10n) => l10n.notifTeamsRegenerated,
  ),
  'match_starting_soon': NotificationDisplay(
    icon: Icons.alarm,
    tone: NotificationTone.neutral,
    label: (l10n) => l10n.notifMatchStartingSoon,
  ),
  'match_time_changed': NotificationDisplay(
    icon: Icons.schedule,
    tone: NotificationTone.neutral,
    label: (l10n) => l10n.notifMatchTimeChanged,
  ),
  'community_invitation': NotificationDisplay(
    icon: Icons.mail_outline,
    tone: NotificationTone.positive,
    label: (l10n) => l10n.notifCommunityInvitation,
  ),
  'community_join_accepted': NotificationDisplay(
    icon: Icons.verified_user_outlined,
    tone: NotificationTone.positive,
    label: (l10n) => l10n.notifCommunityJoinAccepted,
  ),
  'community_picture_updated': NotificationDisplay(
    icon: Icons.image_outlined,
    tone: NotificationTone.neutral,
    label: (l10n) => l10n.notifCommunityPictureUpdated,
  ),
  'community_description_updated': NotificationDisplay(
    icon: Icons.notes,
    tone: NotificationTone.neutral,
    label: (l10n) => l10n.notifCommunityDescriptionUpdated,
  ),
  'community_settings_updated': NotificationDisplay(
    icon: Icons.tune,
    tone: NotificationTone.neutral,
    label: (l10n) => l10n.notifCommunitySettingsUpdated,
  ),
};
