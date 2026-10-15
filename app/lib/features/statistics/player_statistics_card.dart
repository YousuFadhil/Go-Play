import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../sharing/share_card_palette.dart';
import '../sharing/share_poster.dart';
import '../profile/player_identity.dart';
import 'statistics_period.dart';
import 'statistics_period_selector.dart';

/// Everything the Player Statistics card draws, resolved before it is drawn.
///
/// **The card is handed this and nothing else.** No repository, no session, no
/// period to work out — the screen already knows all of it, and a template that
/// could fetch would be a second place the figures come from, free to disagree
/// with the screen the reader is looking at.
///
/// Six values and an identity. There is no seventh: every figure here is one
/// the Player Statistics screen already shows, and this cycle adds no metric.
@immutable
class PlayerStatisticsCardData {
  const PlayerStatisticsCardData({
    required this.fullName,
    required this.rating,
    required this.period,
    required this.matchesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goals,
    required this.mvpCount,
    this.avatarUrl,
  });

  final String fullName;

  /// Null when the player has set no picture, which is an initials avatar
  /// rather than a broken one — the same fallback every other surface uses.
  final String? avatarUrl;

  /// The **Global** Rating: the value the player holds now, across every
  /// community. It is the same number on all three cards.
  ///
  /// **There is no weekly or monthly rating and this card does not imply one.**
  /// `OP-1` makes the rating system-managed and periodless; a "rating for last
  /// week" is not a figure the product has. So the rating carries the label the
  /// screen already gives it, and the period sits with the counters — which are
  /// the things that actually belong to a week.
  final double rating;

  /// Which stretch the six counters below describe. Comes from the selector
  /// the reader already used; the card never asks again.
  final StatisticsPeriod period;

  /// The six the screen itself shows. The card carried four of them and left
  /// draws and losses out, which made a record of played football that could
  /// not be reconciled: wins and matches without the two results in between.
  final int matchesPlayed;
  final int wins;
  final int draws;
  final int losses;
  final int goals;
  final int mvpCount;
}

/// The Player Statistics share card: one player's period, as a picture.
///
/// **A graphic, not a screenshot.** The statistics screen is a list of cards
/// built to be scrolled and refreshed; this is one image somebody sends to a
/// group chat, so it is composed rather than captured — a single hierarchy
/// running down the frame, six figures given equal weight, and nothing on it
/// that a reader would try to tap.
///
/// **Presentation only.** It takes [PlayerStatisticsCardData] and draws it. It
/// reads no repository, resolves no period and calculates nothing — not even a
/// total — which is what lets the same screen state produce the card and the
/// screen.
///
/// **Laid out in the engine's design units, never the device's.** Every number
/// below is a coordinate on the 1080×1920 surface `ShareCardSurface` fixes, so
/// the card is identical whatever composed it. Nothing here reads
/// `MediaQuery.sizeOf` for a dimension.
///
/// **Right-to-left is inherited, not mirrored by hand.** Rows and text align
/// themselves from the ambient `Directionality`, so the Arabic card is the same
/// hierarchy read the other way rather than a second layout.
class PlayerStatisticsCard extends StatelessWidget {
  const PlayerStatisticsCard({super.key, required this.data});

  final PlayerStatisticsCardData data;

  /// The page margin, in design units.
  static const _margin = 60.0;

  @override
  Widget build(BuildContext context) {
    return SharePosterBackground(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_margin, 56, _margin, 64),
        // **A poster with one white card**, like the profile card: the player's
        // face on its top edge, then name and period, the rating, and the six
        // counters. One wordmark, at the foot. The card is sized by its blocks
        // and centred in what is left.
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 1080 - 2 * _margin,
                    child: _PosterCard(data: data),
                  ),
                ),
              ),
            ),
            const SharePosterWordmark(),
          ],
        ),
      ),
    );
  }
}

/// The card: a white sheet with the player's face on its top edge.
class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.data});

  final PlayerStatisticsCardData data;

  /// The face's diameter. Half of it stands above the card.
  static const _face = 256.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _face / 2),
          child: Container(
            padding: const EdgeInsets.fromLTRB(44, _face / 2 + 28, 44, 48),
            decoration: BoxDecoration(
              color: ShareCardPalette.paper,
              borderRadius: BorderRadius.circular(68),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x47000000),
                  blurRadius: 80,
                  offset: Offset(0, 36),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Scaled down rather than clipped: a long name is still that
                // player's name, and a card that cut it off would be worse than
                // one where it reads slightly smaller.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    data.fullName,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ShareCardPalette.paperInk,
                      fontSize: 72,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: _PeriodBadge(
                    // "Period · Weekly" rather than a bare "Weekly": on a card
                    // that leaves the app the word alone does not say what it
                    // qualifies.
                    label: l10n.shareCardPeriodBadge(
                      StatisticsPeriodSelector.shareLabel(l10n, data.period),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _Rating(rating: data.rating, label: l10n.statCurrentRating),
                const SizedBox(height: 28),
                _Counters(data: data),
              ],
            ),
          ),
        ),
        // The existing avatar, at card scale, with a white ring. Its fallback
        // is the app's own — initials, and a figure where there is not even a
        // name — so a player without a picture gets the card everyone else
        // gets rather than a gap.
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ShareCardPalette.paper,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 36,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Theme(
            // **Pinned, so the same player produces the same picture.** The
            // avatar's fallback disc is a `CircleAvatar`, which takes its
            // colours from the ambient scheme — so without this a reader in
            // dark mode shared a different image of the same figures than a
            // reader in light mode. It changes nothing in the app: this Theme
            // exists only inside the card being composed.
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: ShareCardPalette.avatarSeed,
                brightness: Brightness.light,
              ),
            ),
            child: PlayerAvatar(
              avatarUrl: data.avatarUrl,
              fullName: data.fullName,
              radius: _face / 2 - 10,
            ),
          ),
        ),
      ],
    );
  }
}

/// Which period the counters below describe.
///
/// It sits with the player rather than over the figures because it qualifies
/// all six of them at once — and deliberately *not* beside the rating, which
/// is the one thing on this card that no period applies to.
class _PeriodBadge extends StatelessWidget {
  const _PeriodBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      decoration: BoxDecoration(
        color: ShareCardPalette.paperTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: ShareCardPalette.pitchDeep,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// The Global Rating, given the size it has in the product.
///
/// One decimal place, which is `OP-1`'s presentation rule and the same thing
/// the statistics screen shows. The label is the screen's own wording, so the
/// reader of the card and the reader of the screen are told the same thing
/// about what this number is.
class _Rating extends StatelessWidget {
  const _Rating({required this.rating, required this.label});

  final double rating;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: ShareCardPalette.paperTint,
        borderRadius: BorderRadius.circular(44),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: ShareCardPalette.paperInk,
              fontSize: 160,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: -5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ShareCardPalette.paperMuted,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: 5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The six figures, two by three.
///
/// Equal blocks rather than a ranked list: none of these is the headline — the
/// rating above is — and sizing one of them larger would be a claim about
/// which of a player's numbers matters that the product does not make.
///
/// A `Row` of two, three times, so the reading order comes from the ambient
/// direction: Matches and Wins swap sides in Arabic without a line of code
/// about Arabic.
class _Counters extends StatelessWidget {
  const _Counters({required this.data});

  final PlayerStatisticsCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: ShareCardPalette.paperTint,
        borderRadius: BorderRadius.circular(44),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Two columns, three rows, in the order the screen reads them: what
          // was played, then how it went, then what came of it.
          _CounterRow(
            left: _Counter(
              value: data.matchesPlayed,
              label: l10n.shareCardStatMatches,
            ),
            right: _Counter(value: data.wins, label: l10n.shareCardStatWins),
          ),
          const _Rule(),
          _CounterRow(
            left: _Counter(value: data.draws, label: l10n.shareCardStatDraws),
            right:
                _Counter(value: data.losses, label: l10n.shareCardStatLosses),
          ),
          const _Rule(),
          _CounterRow(
            left: _Counter(value: data.goals, label: l10n.shareCardStatGoals),
            right: _Counter(value: data.mvpCount, label: l10n.shareCardStatMvp),
          ),
        ],
      ),
    );
  }
}

/// Two figures side by side, each taking half the width whatever its label.
class _CounterRow extends StatelessWidget {
  const _CounterRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          Expanded(child: right),
        ],
      );
}

/// One figure and what it counts.
class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: ShareCardPalette.paperInk,
              fontSize: 72,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -2,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              style: const TextStyle(
                color: ShareCardPalette.paperMuted,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A hairline between two rows of counters.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      color: ShareCardPalette.paperLine,
    );
  }
}
