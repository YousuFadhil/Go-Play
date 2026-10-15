import 'package:flutter/material.dart';

import '../../core/club_place.dart' show MowingStripes;
import '../../core/l10n.dart';
import 'share_card_palette.dart';

/// The ground every poster-style share card sits on: the product's green,
/// deepest at the top and fading to near-white at the foot, under soft mowing
/// stripes.
///
/// One place, so the profile card and the two statistics cards cannot drift
/// apart. Takes no colour from the reader's theme.
class SharePosterBackground extends StatelessWidget {
  const SharePosterBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration:
          const BoxDecoration(gradient: ShareCardPalette.posterGradient),
      child: Stack(
        children: [
          const Positioned.fill(
            child: MowingStripes(opacity: 0.06, bands: 8.4),
          ),
          child,
        ],
      ),
    );
  }
}

/// The product's mark, large, at the foot of a poster card.
///
/// Green, because the foot of the poster is nearly white.
class SharePosterWordmark extends StatelessWidget {
  const SharePosterWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        textDirection: TextDirection.ltr,
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: ShareCardPalette.pitch,
            ),
            child: const Icon(
              Icons.sports_soccer,
              size: 58,
              color: ShareCardPalette.ink,
            ),
          ),
          const SizedBox(width: 22),
          Text(
            // The mark reads left to right in both languages: it is a name, and
            // the product is called Go Play in Arabic too.
            context.l10n.appName,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: ShareCardPalette.pitchDeep,
              fontSize: 64,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
            ),
          ),
        ],
      ),
    );
  }
}
