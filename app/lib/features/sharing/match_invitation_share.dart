import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../analytics/analytics_models.dart';
import 'public_link.dart';
import 'share_card_flow.dart';
import 'share_card_palette.dart';
import 'share_service.dart';

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

  /// One match invitation: a Club share-card picture and the existing
  /// localized invitation text, including the public match link, in one sheet.
  /// No second share action, destination-specific integration, or database read.
  static Future<void> present(
    BuildContext context, {
    required String matchId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required String source,
    String? communityId,
  }) {
    final invitationText = message(
      context,
      matchId: matchId,
      title: title,
      location: location,
      startAt: startAt,
      endAt: endAt,
    );
    return presentShareCard(
      context,
      template: (_) => MatchInvitationCard(
        title: title,
        location: location,
        startAt: startAt,
        endAt: endAt,
      ),
      matchId: matchId,
      communityId: communityId,
      message: ShareMessage(text: invitationText),
      shareType: ShareType.match,
      source: source,
    );
  }
}

/// The visual preview sent with the invitation link. The existing share
/// engine fixes its canvas at 1080x1920 and captures the entire widget as PNG.
/// This is separate from the lineup/results/statistics share templates.
class MatchInvitationCard extends StatelessWidget {
  const MatchInvitationCard({
    super.key,
    required this.title,
    required this.location,
    required this.startAt,
    required this.endAt,
  });

  final String title;
  final String location;
  final DateTime startAt;
  final DateTime endAt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = title.trim().isEmpty ? location.trim() : title.trim();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ShareCardPalette.pitch, ShareCardPalette.pitchDeep],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(72, 96, 72, 88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sports_soccer,
                    color: ShareCardPalette.accent, size: 68),
                const SizedBox(width: 24),
                Text(
                  l10n.appName,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: ShareCardPalette.ink,
                    fontSize: 54,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              l10n.shareMatchInviteLead,
              style: const TextStyle(
                color: ShareCardPalette.inkMuted,
                fontSize: 39,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 52),
            Text(
              name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ShareCardPalette.ink,
                fontSize: 92,
                height: 1.14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 80),
            _InvitationDetail(
              icon: Icons.calendar_today_outlined,
              text: formatDayAndTimeRange(context, startAt, endAt),
            ),
            const SizedBox(height: 44),
            _InvitationDetail(
              icon: Icons.place_outlined,
              text: '${l10n.locationLabel}: ${location.trim()}',
            ),
            const Spacer(),
            Container(
              height: 3,
              color: ShareCardPalette.accent.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 34),
            Text(
              l10n.appName,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: ShareCardPalette.inkMuted,
                fontSize: 38,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationDetail extends StatelessWidget {
  const _InvitationDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: ShareCardPalette.accent, size: 48),
        const SizedBox(width: 30),
        Expanded(
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ShareCardPalette.ink,
              fontSize: 42,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// A small injectable seam for screen tests; the native implementation calls
/// the platform's general share sheet and does not send a WhatsApp message.
typedef ShareMatchText = Future<void> Function(String text);
