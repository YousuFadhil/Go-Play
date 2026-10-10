import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/time_format.dart';

/// A small invitation preview: facts only, no player roster, logo or URL.
///
/// The public match link travels in the share payload, not in the image.
/// Rendered on the existing fixed 1080x1920 ShareCardSurface.
class MatchInvitationPreview extends StatelessWidget {
  const MatchInvitationPreview({
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
    final name = title.trim().isEmpty ? location.trim() : title.trim();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B4930), Color(0xFF04291D)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 78, vertical: 130),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            const Icon(
              Icons.sports_soccer_outlined,
              color: Color(0xFF57D58A),
              size: 176,
            ),
            const SizedBox(height: 74),
            Text(
              name,
              key: const ValueKey('invite-preview-title'),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 78,
                height: 1.18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 85),
            const Divider(color: Color(0xFF57D58A), thickness: 3),
            const SizedBox(height: 65),
            Text(
              formatDayAndTimeRange(context, startAt, endAt),
              key: const ValueKey('invite-preview-time'),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 47,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 50),
            Text(
              '${context.l10n.locationLabel}: ${location.trim()}',
              key: const ValueKey('invite-preview-location'),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 45,
                height: 1.28,
                color: Color(0xFFCFEBDB),
              ),
            ),
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}
