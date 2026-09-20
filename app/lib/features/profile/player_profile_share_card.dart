import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../auth/auth_models.dart';
import '../sharing/share_card_palette.dart';
import 'current_user.dart';
import 'player_identity.dart';
import 'player_record_models.dart';
import 'profile_record_sections.dart';

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
    required this.wins,
    required this.draws,
    required this.losses,
    this.avatarUrl,
    this.form = RecentForm.empty,
    this.achievements = const [],
    this.publicUrl,
  });

  final String fullName;

  /// Null when the player has set no picture. The card draws the app's own
  /// initials avatar, exactly as every other surface does, rather than a gap.
  final String? avatarUrl;

  /// Where they play. One position and not two: this is an identity card, and
  /// the second position is a detail of team generation rather than of who
  /// somebody is.
  final PlayerPosition primaryPosition;

  /// The Global Rating, as it stands. Periodless (`OP-1`) and the same number
  /// the Player Statistics card carries.
  final double rating;

  /// The career, exactly as the profile's own grid states it. **No figure here
  /// is computed for the card** — every one of them is already on the screen
  /// the card was asked for from, which is what keeps "what you can see is what
  /// you can send" true in both directions.
  final int matchesPlayed;
  final int goals;
  final int mvpCount;
  final int wins;
  final int draws;
  final int losses;

  /// The last five results, newest first. Empty for a player who has played
  /// none, and an empty form draws no strip rather than five grey placeholders.
  final RecentForm form;

  /// The achievements already visible on the profile, newest first.
  ///
  /// The profile read is capped at five; the card defensively renders at most
  /// five as well so "what you can see is what you can send" remains true.
  final List<RecentHighlight> achievements;

  /// The public address this card is about — the same link the share message
  /// carries. Printed at the foot so a picture that has been forwarded past the
  /// message still says where the profile is.
  final String? publicUrl;
}

/// The Player Profile share card: who a player is, as a picture.
///
/// **An identity card, not a statistics card.** The hierarchy is the approved
/// one: the product's mark, then the player — face, name, position and the
/// three career figures that describe them — then the rating beside the
/// win/loss/draw record, then Recent Form, then the same Recent Achievements
/// the profile shows, and the public address at the foot. The Player Statistics
/// card leads with a
/// period and gives six counters equal weight; the two are different pictures
/// of the same player on purpose, and neither is a variant of the other.
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
  static const _margin = 72.0;

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
            padding: const EdgeInsets.fromLTRB(_margin, 96, _margin, 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Masthead(),
                // **The panel is sized by what the player has, and centred in
                // what is left.** A card for a player with no achievement and
                // no form holds two blocks instead of four; stretching those
                // two over the whole frame put a hand's width of nothing
                // between them. The room the content does not need is split
                // above and below it instead, so every card is balanced and
                // none of them is padded out with something to fill a gap.
                const Spacer(),
                _Panel(data: data),
                const Spacer(),
                if (data.publicUrl != null) _Address(url: data.publicUrl!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The product's mark, and what kind of card this is.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ShareCardPalette.ink,
          ),
          child: const Icon(
            Icons.sports_soccer,
            size: 50,
            color: ShareCardPalette.pitch,
          ),
        ),
        const SizedBox(width: 20),
        // Left to right in both languages: it is a name, and the product is
        // called Go Play in Arabic too.
        Text(
          l10n.appName,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            color: ShareCardPalette.ink,
            fontSize: 48,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const Spacer(),
        Text(
          l10n.playerProfileTitle,
          style: const TextStyle(
            color: ShareCardPalette.inkMuted,
            fontSize: 30,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The card's one panel: everything about the player, inside a single frame.
class _Panel extends StatelessWidget {
  const _Panel({required this.data});

  final PlayerProfileCardData data;

  /// Between two blocks inside the panel.
  static const _blockGap = 72.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(56, 66, 56, 66),
      decoration: BoxDecoration(
        color: ShareCardPalette.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(44),
        border: Border.all(
          color: ShareCardPalette.accent.withValues(alpha: 0.28),
          width: 3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // As tall as its blocks, with one gap between them: the distance
        // between the identity and the record is the same on every card,
        // whether or not the player has form and an achievement to follow it.
        mainAxisSize: MainAxisSize.min,
        children: [
          _Identity(data: data),
          const SizedBox(height: _blockGap),
          _Record(data: data),
          if (data.form.isNotEmpty) ...[
            const SizedBox(height: _blockGap),
            _FormStrip(form: data.form),
          ],
          if (data.achievements.isNotEmpty) ...[
            const SizedBox(height: _blockGap),
            _Achievements(achievements: data.achievements),
          ],
        ],
      ),
    );
  }
}

/// The player: their face, their name, where they play, and their career on
/// one line.
class _Identity extends StatelessWidget {
  const _Identity({required this.data});

  final PlayerProfileCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CardAvatar(
          avatarUrl: data.avatarUrl,
          fullName: data.fullName,
          size: 252,
        ),
        const SizedBox(width: 40),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Scaled down rather than clipped: a long name is still that
              // player's name, and a card that cut it off would be worse than
              // one where it reads slightly smaller.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  data.fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ShareCardPalette.ink,
                    fontSize: 78,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                positionLabel(l10n, data.primaryPosition),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ShareCardPalette.inkMuted,
                  fontSize: 38,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  [
                    '${data.matchesPlayed} ${l10n.shareCardStatMatches}',
                    '${data.goals} ${l10n.shareCardStatGoals}',
                    '${data.mvpCount} ${l10n.shareCardStatMvp}',
                  ].join('   |   '),
                  maxLines: 1,
                  style: TextStyle(
                    color: ShareCardPalette.inkMuted.withValues(alpha: 0.85),
                    fontSize: 32,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A face on a card: the picture, or the letters of a player who has not set
/// one.
///
/// Its own widget rather than the app's avatar because the approved card draws
/// a rounded square, and because a card must take no colour from the reader's
/// theme — the initials sit on the card's own accent at a fixed strength.
class _CardAvatar extends StatelessWidget {
  const _CardAvatar({
    required this.avatarUrl,
    required this.fullName,
    required this.size,
  });

  final String? avatarUrl;
  final String fullName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final initials = initialsOf(fullName);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ShareCardPalette.accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(
          color: ShareCardPalette.accent.withValues(alpha: 0.5),
          width: 3,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: initials.isEmpty
                ? Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: ShareCardPalette.ink,
                  )
                : Text(
                    initials,
                    style: TextStyle(
                      color: ShareCardPalette.ink,
                      fontSize: size * 0.34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          if (url != null)
            Image.network(
              url,
              fit: BoxFit.cover,
              // A picture that will not load leaves the letters showing, which
              // is what an account without one looks like anyway — never a
              // broken-image glyph on a card somebody is about to send.
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

/// The rating, and the record it came out of.
class _Record extends StatelessWidget {
  const _Record({required this.data});

  final PlayerProfileCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _RatingDial(rating: data.rating)),
        Expanded(
          child: _Figure(value: data.wins, label: l10n.shareCardStatWins),
        ),
        Expanded(
          child: _Figure(value: data.losses, label: l10n.shareCardStatLosses),
        ),
        Expanded(
          child: _Figure(value: data.draws, label: l10n.shareCardStatDraws),
        ),
      ],
    );
  }
}

/// The Global Rating, in the ring the approved card gives it.
///
/// The arc is the rating against the scale it is stated on — `OP-1`'s 0 to 10 —
/// so the ring says the same thing as the number inside it rather than a
/// second, prettier one.
class _RatingDial extends StatelessWidget {
  const _RatingDial({required this.rating});

  final double rating;

  static const _max = 10.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 176,
          height: 176,
          child: CustomPaint(
            painter: _DialPainter(rating / _max),
            child: Center(
              child: Text(
                // One decimal place, which is `OP-1`'s presentation rule and
                // what every other surface shows. Left-to-right whatever the
                // card's direction: a number is a number in both languages.
                rating.toStringAsFixed(1),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: ShareCardPalette.ink,
                  fontSize: 60,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            l10n.statCurrentRating,
            maxLines: 1,
            style: const TextStyle(
              color: ShareCardPalette.inkMuted,
              fontSize: 30,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.fraction);

  /// How much of the ring is filled, clamped so a rating outside the scale
  /// cannot draw more than a circle.
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final circle = rect.deflate(stroke / 2);

    canvas.drawArc(
      circle,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = ShareCardPalette.ink.withValues(alpha: 0.18),
    );
    canvas.drawArc(
      circle,
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = ShareCardPalette.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

/// One figure and what it counts.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 176,
          child: Center(
            child: Text(
              '$value',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: ShareCardPalette.ink,
                fontSize: 74,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: ShareCardPalette.inkMuted,
              fontSize: 30,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// The last results, newest first.
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
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.shareCardFormLabel,
          style: const TextStyle(
            color: ShareCardPalette.ink,
            fontSize: 36,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            for (final entry in form.entries) ...[
              if (entry != form.entries.first) const SizedBox(width: 28),
              _FormBadge(entry: entry),
            ],
          ],
        ),
      ],
    );
  }
}

/// One result, as a letter in a disc.
class _FormBadge extends StatelessWidget {
  const _FormBadge({required this.entry});

  final RecentFormEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final outcome = entry.outcome;
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

    final scoreline = entry.scoreline;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 104,
          height: 104,
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
                fontSize: 46,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (scoreline != null) ...[
          const SizedBox(height: 14),
          Text(
            // The player's own goals lead, in both languages: a scoreline is
            // read home-then-away and its order is not the card's.
            scoreline,
            textDirection: TextDirection.ltr,
            maxLines: 1,
            style: const TextStyle(
              color: ShareCardPalette.inkMuted,
              fontSize: 28,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// The same achievements the profile shows, in the same read order.
///
/// A share card keeps all of them rather than silently choosing one, but
/// presents them as compact rows so the fixed 1080x1920 surface stays balanced.
class _Achievements extends StatelessWidget {
  const _Achievements({required this.achievements});

  final List<RecentHighlight> achievements;

  @override
  Widget build(BuildContext context) {
    final visible = achievements.take(5).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.recentAchievementsTitle,
          style: const TextStyle(
            color: ShareCardPalette.ink,
            fontSize: 36,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _AchievementRow(achievement: visible[i]),
        ],
      ],
    );
  }
}

/// One compact achievement row. It uses the same labels and ordering as the
/// profile's achievement cards; only the density changes for the share image.
class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.achievement});

  final RecentHighlight achievement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, title) = switch (achievement.kind) {
      HighlightKind.mvp => (Icons.star, l10n.highlightMvpTitle),
      HighlightKind.teamOfPeriod => (
          Icons.emoji_events,
          switch (achievement.period) {
            HighlightPeriod.week => l10n.teamOfPeriodWeekHeading,
            HighlightPeriod.month => l10n.teamOfPeriodMonthHeading,
            null => l10n.highlightTeamOfPeriodTitle,
          },
        ),
    };
    final community = achievement.communityName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 74,
          height: 74,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ShareCardPalette.award,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 40, color: ShareCardPalette.onAward),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ShareCardPalette.ink,
                  fontSize: 31,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                highlightPeriodLine(context, achievement),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ShareCardPalette.inkMuted,
                  fontSize: 24,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (community != null && community.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  community,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ShareCardPalette.inkMuted.withValues(alpha: 0.8),
                    fontSize: 22,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Where the profile lives, at the foot of the card.
///
/// The address itself and nothing standing for it: there is no public-link QR
/// behaviour in the product, and a code that decodes to nothing would be a
/// picture of a feature rather than a feature.
class _Address extends StatelessWidget {
  const _Address({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        // Left to right in both languages: a URL has one direction.
        url,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        style: const TextStyle(
          color: ShareCardPalette.inkMuted,
          fontSize: 32,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
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
