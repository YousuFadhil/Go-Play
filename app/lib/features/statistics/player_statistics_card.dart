import 'package:flutter/material.dart';

import '../../core/l10n.dart';
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

  /// The card's own palette, stated here rather than taken from the app theme.
  ///
  /// A share card is a picture that leaves the phone: it must not change
  /// because the reader has dark mode on. The green is the app's own seed
  /// colour, dark enough to sit behind white text.
  static const _pitch = Color(0xFF07341C);
  static const _pitchDeep = Color(0xFF04180E);
  static const _accent = Color(0xFF3DDC84);
  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0xB3FFFFFF);

  /// The page margin, in design units.
  static const _margin = 88.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_pitch, _pitchDeep],
        ),
      ),
      child: Stack(
        children: [
          // The only ornament: a faint centre circle and halfway line, the
          // markings of a pitch rather than a picture of one. Geometry keeps
          // the card readable where a photograph would fight the text on it.
          const Positioned.fill(child: _PitchMarkings()),
          Padding(
            padding: const EdgeInsets.fromLTRB(_margin, 96, _margin, 84),
            // One wordmark, at the foot. The card used to carry it twice —
            // once large at the top and once muted at the bottom — which read
            // as the product signing its own picture twice. The rule the accent
            // bar used to sit under now opens the card on its own.
            child: Column(
              children: [
                Container(width: 132, height: 6, color: _accent),
                const Spacer(flex: 3),
                _Identity(data: data),
                const Spacer(flex: 2),
                _Rating(rating: data.rating, label: l10n.statCurrentRating),
                // Two counters became six, so the block below is taller and the
                // slack around it is redistributed rather than the padding
                // grown: identity and rating keep the upper third, the grid
                // takes the middle, and the wordmark keeps a clear foot.
                const Spacer(flex: 3),
                _Counters(data: data),
                const Spacer(flex: 4),
                const _Wordmark(size: 30, spacing: 10, muted: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The player: their face, their name, and which stretch this card is about.
class _Identity extends StatelessWidget {
  const _Identity({required this.data});

  final PlayerStatisticsCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The existing avatar, at card scale. Its fallback is the app's own —
        // initials, and a figure where there is not even a name — so a player
        // without a picture gets the card everyone else gets rather than a gap.
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: PlayerStatisticsCard._accent,
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
                seedColor: const Color(0xFF1B7A43),
                brightness: Brightness.light,
              ),
            ),
            child: PlayerAvatar(
              avatarUrl: data.avatarUrl,
              fullName: data.fullName,
              radius: 176,
            ),
          ),
        ),
        const SizedBox(height: 44),
        // Scaled down rather than clipped: a long name is still that player's
        // name, and a card that cut it off would be worse than one where it
        // reads slightly smaller.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            data.fullName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PlayerStatisticsCard._ink,
              fontSize: 80,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 28),
        _PeriodBadge(
          // "Period · Weekly" rather than a bare "Weekly": on a card that
          // leaves the app the word alone does not say what it qualifies.
          label: l10n.shareCardPeriodBadge(
            StatisticsPeriodSelector.shareLabel(l10n, data.period),
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
      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
      decoration: BoxDecoration(
        color: PlayerStatisticsCard._accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: PlayerStatisticsCard._accent.withValues(alpha: 0.55),
          width: 3,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: PlayerStatisticsCard._accent,
          fontSize: 40,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            color: PlayerStatisticsCard._ink,
            fontSize: 196,
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: -6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: PlayerStatisticsCard._inkMuted,
            fontSize: 34,
            fontWeight: FontWeight.w600,
            letterSpacing: 6,
          ),
        ),
      ],
    );
  }
}

/// The six figures, two by three.
///
/// Equal blocks rather than a ranked list: none of these four is the headline —
/// the rating above is — and sizing one of them larger would be a claim about
/// which of a player's numbers matters that the product does not make.
///
/// A `Row` of two, twice, so the reading order comes from the ambient
/// direction: Matches and Wins swap sides in Arabic without a line of code
/// about Arabic.
class _Counters extends StatelessWidget {
  const _Counters({required this.data});

  final PlayerStatisticsCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Rule(),
        const SizedBox(height: 28),
        // Two columns, three rows, in the order the screen reads them: what was
        // played, then how it went, then what came of it.
        _CounterRow(
          left: _Counter(
            value: data.matchesPlayed,
            label: l10n.shareCardStatMatches,
          ),
          right: _Counter(value: data.wins, label: l10n.shareCardStatWins),
        ),
        const SizedBox(height: 32),
        _CounterRow(
          left: _Counter(value: data.draws, label: l10n.shareCardStatDraws),
          right: _Counter(value: data.losses, label: l10n.shareCardStatLosses),
        ),
        const SizedBox(height: 32),
        _CounterRow(
          left: _Counter(value: data.goals, label: l10n.shareCardStatGoals),
          right: _Counter(value: data.mvpCount, label: l10n.shareCardStatMvp),
        ),
        const SizedBox(height: 28),
        const _Rule(),
      ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: PlayerStatisticsCard._ink,
            // 104 when there were four of these. Six rows of that height do not
            // fit the frame, and the answer is the figure's own scale rather
            // than a smaller margin: at 88 the grid still leads the lower half
            // of the card and the numbers still read at a glance.
            fontSize: 88,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -2,
          ),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(
              color: PlayerStatisticsCard._inkMuted,
              fontSize: 32,
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
            ),
          ),
        ),
      ],
    );
  }
}

/// A hairline separating the counters from everything else.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      color: PlayerStatisticsCard._inkMuted.withValues(alpha: 0.18),
    );
  }
}

/// The Go Play name, as the card's mark.
///
/// Set in letterspaced capitals rather than drawn: the app ships no logo asset,
/// and inventing one here would be deciding the brand's visual identity inside
/// a statistics feature.
class _Wordmark extends StatelessWidget {
  const _Wordmark({
    required this.size,
    required this.spacing,
    this.muted = false,
  });

  final double size;
  final double spacing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.appName.toUpperCase(),
      // The mark reads left to right in both languages: it is a name, not a
      // sentence, and the product is called Go Play in Arabic too.
      textDirection: TextDirection.ltr,
      style: TextStyle(
        color: muted
            ? PlayerStatisticsCard._inkMuted
            : PlayerStatisticsCard._ink,
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: spacing,
      ),
    );
  }
}

/// The markings of a pitch, faintly.
///
/// A centre circle and a halfway line, positioned so the circle sits behind the
/// player. It is drawn rather than photographed: the card has to stay readable,
/// and a photograph behind this much text would compete with all of it.
class _PitchMarkings extends StatelessWidget {
  const _PitchMarkings();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PitchPainter());
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = PlayerStatisticsCard._accent.withValues(alpha: 0.10);

    // Behind the player, so the face sits in the centre circle.
    final centre = Offset(size.width / 2, size.height * 0.34);
    canvas.drawCircle(centre, size.width * 0.42, paint);
    canvas.drawCircle(centre, size.width * 0.60, paint);
    canvas.drawLine(
      Offset(0, centre.dy),
      Offset(size.width, centre.dy),
      paint,
    );
  }

  // The markings depend on nothing but the size the painter is given, and the
  // card is always the same size, so a repaint is never needed.
  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) => false;
}
