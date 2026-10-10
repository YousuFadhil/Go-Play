import 'share_card_renderer.dart';
import 'public_link.dart';

/// The public link that takes an invited player to this match.
///
/// The small preview image is attached independently by the invitation-only
/// platform adapter. Other social share cards do not receive text or links.
abstract final class MatchInvitationShare {
  static String link(String matchId) =>
      PublicLink.format(PublicLinkKind.match, matchId);
}

/// Injectable boundary for one OS share carrying one PNG and its match link.
typedef ShareMatchInvitation = Future<void> Function(
  String link,
  ShareCardImage preview,
);
