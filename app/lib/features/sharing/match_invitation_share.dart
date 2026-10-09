import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/time_format.dart';
import 'public_link.dart';

/// Words accompanying a public match link. This shares a navigable invitation,
/// not an image: existing lineup/result/statistics image shares remain separate.
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
    final name = title.trim().isNotEmpty ? title.trim() : location.trim();
    final url = PublicLink.format(PublicLinkKind.match, matchId);
    return [
      l10n.shareMatchInviteLead,
      name,
      formatDayAndTimeRange(context, startAt, endAt),
      '${l10n.locationLabel}: ${location.trim()}',
      url,
    ].join('\n');
  }
}

/// A small injectable seam for screen tests; the native implementation calls
/// the platform's general share sheet and does not send a WhatsApp message.
typedef ShareMatchText = Future<void> Function(String text);
