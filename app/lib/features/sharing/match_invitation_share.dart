import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../../infrastructure/platform/native_text_share_service.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_service.dart';
import 'public_link.dart';
import 'share_service.dart';

/// Optional text-sharing seam used by the two invitation entry points.
typedef ShareMatchText = Future<void> Function(String text);

/// A readable invitation with one public URL. The receiving app fetches its
/// Open Graph thumbnail. No image attachment or card-preview screen is used.
class MatchInvitationShare {
  const MatchInvitationShare._();

  static String message(
    BuildContext context, {
    required String matchId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
  }) {
    final l10n = context.l10n;
    final name = title.trim();
    final place = location.trim();
    final url = PublicLink.matchInvitation(
      matchId,
      languageCode: Localizations.localeOf(context).languageCode,
    );
    return [
      name.isEmpty
          ? l10n.shareMatchInviteLead
          : l10n.shareMatchInviteHeading(name),
      '📅 ${formatMatchDay(context, startAt)}',
      // Not formatTimeRange: that wraps the range in a direction isolate for the
      // app's own screens, an invisible control a chat app may lay out
      // differently. The words in the Arabic range fix its order in any app.
      '🕗 ${l10n.shareMatchInviteTime(formatTime(context, startAt), formatTime(context, endAt))}',
      if (place.isNotEmpty) '📍 $place',
      '',
      l10n.shareMatchInviteAction,
      url,
    ].join('\n');
  }

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
    final invitation = message(
      context,
      matchId: matchId,
      title: title,
      location: location,
      startAt: startAt,
      endAt: endAt,
    );
    final outcome = await (shareService ?? NativeTextShareService()).shareText(
      invitation,
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
