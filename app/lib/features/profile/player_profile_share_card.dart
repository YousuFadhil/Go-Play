import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../auth/auth_models.dart';
import '../sharing/share_card_palette.dart';
import 'player_identity.dart';
import 'player_record_models.dart';

/// Everything the Player Profile card draws, resolved before it is drawn.
///
/// **The card is handed this and nothing else** — the same contract
/// `PlayerStatisticsCardData` has. Whatever is on it was already on the screen
/// that asked for the card, so a picture and the profile behind it cannot
/// disagree, and the template reads no repository.
@immutable
class PlayerProfileCardData {
  const PlayerProfileCardData({
    required this.fullName,
    required this.primaryPosition,
    required this.rating,
    required this.matchesPlayed,
    required this.goals,
    required this.mvpCount,
    this.avatarUrl,
    this.form = RecentForm.empty,
  });

  final String fullName;

  /// Null when the player has set no picture. The card draws the app's own
  /// initials avatar, exactly as every other surface does, rather than a gap.
  final String? avatarUrl;

  /// Where they play. One position and not two: this is an identity card, and
  /// a secondary position is a detail of team generation rather than of who
  /// somebody is.
  final PlayerPosition primaryPosition;

  /// The Global Rating, as it stands. Periodless (`OP-1`) and the same number
  /// the Player Statistics card carries.
  final double rating;

  /// **Three indicators, and there is no fourth.** The approved brief asks for
  /// "only a small number of high-value football indicators", which is what
  /// keeps this card from becoming the Player Statistics card with a different
  /// background: that one shows six counters for a chosen period, this one
  /// shows who a player is and the three career figures a stranger would
  /// actually read.
  final int matchesPlayed;
  final int goals;
  final int mvpCount;

  /// The last five results, newest first. Empty for a player who has played
  /// none, and an empty form draws no strip rather than five grey placeholders.
  final RecentForm form;
}

/// The Player Profile share card: who a player is, as a picture.
///
/// **An identity card, not a statistics card.** The hierarchy runs face →
/// name → position → rating, and the figures sit beneath it as support. The
/// Player Statistics card leads with a period and gives six counters equal
/// weight; the two are different pictures of the same player on purpose, and
/// neither is a variant of the other.
///
/// Laid out in the engine's design units on the 1080×1920 surface
/// `ShareCardSurface` fixes, so the same player produces the same picture on
/// every phone. Right-to-left is inherited from the ambient `Directionality`
/// rather than mirrored by hand, which is what makes the Arabic card the same
/// hierarchy read the other way instead of a second layout.
class PlayerProfileShareCard extends StatelessWidget {
  const PlayerProfileShareCard({super.key, required this.data});

  final PlayerProfileCardData data;

  /// The page margin, in design units. The statistics card's, so two cards
  /// from the same product have the same edge.
  static const _margin = 88.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ShareCardPalette.pitch, ShareCardPalette.pitchDeep],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _PitchMarkings()),
          Padding(
            padding: const EdgeInsets.fromLTRB(_margin, 96, _margin, 84),
            child: Column(
              children: [
                const Spacer(flex: 3),
                _Identity(data: data),
                const Spacer(flex: 2),
                _Rating(rating: data.rating),
                const Spacer(flex: 2),
                // Drawn only when there is form to draw. A player with no
                // completed matches gets a card about who they are, which is
                // still a complete card — an empty strip would be the one thing
                // on it that says nothing.
                if (data.form.isNotEmpty) ...[
                  _FormStrip(form: data.form),
                  const Spacer(flex: 2),
                ],
                _Indicators(data: data),
                const Spacer(flex: 4),
                const _Wordmark(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The player: their face, their name, and where they play.
class _Identity extends StatelessWidget {
  const _Identity({required this.data});

  final PlayerProfileCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ShareCardPalette.accent,
          ),
          child: Theme(
            // Pinned, so the same player produces the same picture whatever
            // the reader's own theme is. See [ShareCardPalette.avatarSeed].
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: ShareCardPalette.avatarSeed,
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
              color: ShareCardPalette.ink,
              fontSize: 80,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 28),
        _Badge(
          // "Position · Forward" rather than a bare "Forward": on a card that
          // leaves the app the word alone does not say what it qualifies —
          // the same reason the statistics card writes "Period · Weekly".
          label: '${l10n.shareCardPositionLabel} · '
              '${positionLabel(l10n, data.primaryPosition)}',
        ),
      ],
    );
  }
}

/// The position, or the period on the other card: a pill under the name.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
      decoration: BoxDecoration(
        color: ShareCardPalette.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ShareCardPalette.accent.withValues(alpha: 0.55),
          width: 3,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: ShareCardPalette.accent,
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

/// The Global Rating, given the size it has in the product.
class _Rating extends StatelessWidget {
  const _Rating({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // One decimal place, which is `OP-1`'s presentation rule and what
          // every other surface shows. Left-to-right whatever the card's
          // direction: a number is a number in both languages.
          rating.toStringAsFixed(1),
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            color: ShareCardPalette.ink,
            fontSize: 196,
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: -6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.statCurrentRating.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ShareCardPalette.inkMuted,
            fontSize: 34,
            fontWeight: FontWeight.w600,
            letterSpacing: 6,
          ),
        ),
      ],
    );
  }
}

/// The last five results, newest first.
///
/// **Newest first is the reading direction, not the list order.** The entries
/// arrive newest first and are drawn in that order into a `Row`, which lays
/// itself out from the ambient direction — so the most recent match is on the
/// left in English and on the right in Arabic, and nothing here says the word
/// Arabic.
class _FormStrip extends StatelessWidget {
  const _FormStrip({required this.form});

  final RecentForm form;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.shareCardFormLabel.toUpperCase(),
          style: const TextStyle(
            color: ShareCardPalette.inkMuted,
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: 5,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final entry in form.entries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: _FormBadge(outcome: entry.outcome),
              ),
          ],
        ),
      ],
    );
  }
}

/// One result, as a letter in a disc.
class _FormBadge extends StatelessWidget {
  const _FormBadge({required this.outcome});

  final MatchOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (letter, background, ink) = switch (outcome) {
      MatchOutcome.win => (
          l10n.recentFormWinShort,
          ShareCardPalette.accent,
          ShareCardPalette.pitchDeep,
        ),
      MatchOutcome.draw => (
          l10n.recentFormDrawShort,
          ShareCardPalette.inkMuted,
          ShareCardPalette.pitchDeep,
        ),
      // A loss is drawn rather than filled: three filled discs of three
      // different colours would read as a traffic light, and the card is not
      // grading the player.
      MatchOutcome.loss => (
          l10n.recentFormLossShort,
          const Color(0x00000000),
          ShareCardPalette.inkMuted,
        ),
    };

    return Container(
      width: 96,
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: Border.all(
          color: outcome == MatchOutcome.loss
              ? ShareCardPalette.inkMuted.withValues(alpha: 0.45)
              : const Color(0x00000000),
          width: 3,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          letter,
          maxLines: 1,
          style: TextStyle(
            color: ink,
            fontSize: 44,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// The three career figures, side by side.
class _Indicators extends StatelessWidget {
  const _Indicators({required this.data});

  final PlayerProfileCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Rule(),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Indicator(
                value: data.matchesPlayed,
                label: l10n.shareCardStatMatches,
              ),
            ),
            Expanded(
              child: _Indicator(
                value: data.goals,
                label: l10n.shareCardStatGoals,
              ),
            ),
            Expanded(
              child: _Indicator(
                value: data.mvpCount,
                label: l10n.shareCardStatMvp,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const _Rule(),
      ],
    );
  }
}

/// One figure and what it counts.
class _Indicator extends StatelessWidget {
  const _Indicator({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            color: ShareCardPalette.ink,
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
              color: ShareCardPalette.inkMuted,
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

/// A hairline separating the figures from everything else.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Container(
        height: 2,
        color: ShareCardPalette.inkMuted.withValues(alpha: 0.18),
      );
}

/// The Go Play name, as the card's mark. The statistics card's, at the same
/// size and in the same place, because it is the same product signing the same
/// kind of picture.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.appName.toUpperCase(),
      // Left to right in both languages: it is a name, and the product is
      // called Go Play in Arabic too.
      textDirection: TextDirection.ltr,
      style: const TextStyle(
        color: ShareCardPalette.inkMuted,
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: 10,
      ),
    );
  }
}

/// The markings of a pitch, faintly — the statistics card's, so two cards from
/// one product share a background rather than each inventing one.
class _PitchMarkings extends StatelessWidget {
  const _PitchMarkings();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PitchPainter());
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = ShareCardPalette.accent.withValues(alpha: 0.10);

    final centre = Offset(size.width / 2, size.height * 0.34);
    canvas.drawCircle(centre, size.width * 0.42, paint);
    canvas.drawCircle(centre, size.width * 0.60, paint);
    canvas.drawLine(
      Offset(0, centre.dy),
      Offset(size.width, centre.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) => false;
}
