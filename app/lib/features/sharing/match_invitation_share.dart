import 'package:flutter/material.dart';

import '../../infrastructure/platform/native_text_share_service.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_service.dart';
import 'public_link.dart';
import 'share_service.dart';

/// Optional text-sharing seam used by the two invitation entry points.
typedef ShareMatchText = Future<void> Function(String text);

/// A single public URL. The receiving app fetches its Open Graph thumbnail;
/// no image attachment or card-preview screen is part of a match invitation.
class MatchInvitationShare {
  const MatchInvitationShare._();

  static String message(
    BuildContext context, {
    required String matchId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
  }) =>
      PublicLink.matchInvitation(
        matchId,
        languageCode: Localizations.localeOf(context).languageCode,
      );

  static Future<void> present(
    BuildContext context, {
    required String matchId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required String source,
    String? communityId,
    NativeTextShareService? shareService,
  }) async {
    final url = message(
      context,
      matchId: matchId,
      title: title,
      location: location,
      startAt: startAt,
      endAt: endAt,
    );
    final outcome = await (shareService ?? NativeTextShareService()).shareText(
      url,
    );
    if (outcome != ShareOutcome.dismissed) {
      ProductAnalytics.instance.track(
        ProductEvent.shareUsed,
        matchId: matchId,
        communityId: communityId,
        shareType: ShareType.match,
        source: source,
      );
    }
  }
}
