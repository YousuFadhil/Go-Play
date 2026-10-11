import 'package:flutter/widgets.dart';

import '../../infrastructure/platform/native_text_share_service.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_service.dart';
import 'public_link.dart';

/// A match invitation: one public link, and nothing else, handed to the
/// operating system's text share sheet.
///
/// **The link carries the invitation.** `/share/match/<id>` is answered by a
/// Pages Function with a server-rendered preview (the match's title, when and
/// where, and one Go Play thumbnail), so a chat app builds the card itself from
/// the link; there is no picture to compose and no second item in the share.
/// The words a group sees are the preview's, written in the sharer's language
/// ([PublicLink.matchInvitation]).
///
/// The lineup, result and statistics image shares are separate and unchanged.
class MatchInvitationShare {
  const MatchInvitationShare._();

  /// The link an invitation to [matchId] shares, in the language the screen is
  /// showing.
  static String url(BuildContext context, {required String matchId}) =>
      PublicLink.matchInvitation(
        matchId,
        languageCode: Localizations.localeOf(context).languageCode,
      );

  /// Shares [url] for [matchId] through the text share sheet.
  ///
  /// [shareText] is the seam a screen test supplies; production uses
  /// [NativeTextShareService], which opens the sheet and never sends anything on
  /// the reader's behalf. A failure to open the sheet is thrown to the caller,
  /// which decides what to say; the share is only recorded once the sheet was
  /// shown.
  ///
  /// The `share_used` event is the one the invitation has always recorded (what
  /// was shared, and from which screen); the text sheet cannot say whether the
  /// reader then sent it, so — as on Android for every share — handing it over
  /// is what counts.
  static Future<void> share(
    BuildContext context, {
    required String matchId,
    required String source,
    String? communityId,
    ShareMatchText? shareText,
  }) async {
    final link = url(context, matchId: matchId);
    await (shareText ?? NativeTextShareService().shareText)(link);
    ProductAnalytics.instance.track(
      ProductEvent.shareUsed,
      matchId: matchId,
      communityId: communityId,
      shareType: ShareType.match,
      source: source,
    );
  }
}

/// A small injectable seam for screen tests; the native implementation calls
/// the platform's general share sheet and does not send a WhatsApp message.
typedef ShareMatchText = Future<void> Function(String text);
