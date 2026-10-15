import 'package:flutter/material.dart';

import '../../core/club_place.dart' show MowingStripes;
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

  /// The last six results, newest first. Empty for a player who has played
  /// none, and an empty form draws no strip rather than six grey placeholders.
  final RecentForm form;

  /// The achievements already visible on the profile, newest first.
  ///
  /// The profile read is capped at five; the card defensively renders at most
  /// five as well so "what you can see is what you can send" remains true.
  final List<RecentHighlight> achievements;
}

/// The Player Profile share card: who a player is, as a picture.
///
/// **A poster with one white card on it.** The green of the product fills the
/// whole picture, under the same mowing stripes the heroes carry, so the card is
/// recognisable from across a chat list; the player sits on a single white card
/// that overlaps it — face on the edge, then name and position, the career
/// figures, Recent Form and the same Recent Achievements the profile shows.
/// The mark closes the picture. No address is printed on it: a share is the
/// picture and a line of text, never a link.
///
/// It reads as the profile screen does — green ground, round face, white card,
/// figures in a grid — without copying the screen: the screen is a page, this is
/// a picture that has to hold in a thumbnail. The Player Statistics card leads
/// with a period and gives six counters equal weight; the two are different
/// pictures of the same player on purpose, and neither is a variant of the
/// other.
///
/// Laid out in the engine's design units on the 1080×1920 surface
/// `ShareCardSurface` fixes, so the same player produces the same picture on
/// every phone. Right-to-left is inherited from the ambient `Directionality`
/// rather than mirrored by hand, which is what makes the Arabic card the same
/// hierarchy read the other way instead of a second layout.
class PlayerProfileShareCard extends StatelessWidget {
  const PlayerProfileShareCard({super.key, required this.data});

  final PlayerProfileCardData data;

  /// The page margin, in design units.
  static const _margin = 60.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ShareCardPalette.pitchTop,
            ShareCardPalette.pitch,
            ShareCardPalette.pitchDeep,
          ],
          stops: [0, 0.52, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: MowingStripes(opacity: 0.06, bands: 8.4),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(_margin, 56, _margin, 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Masthead(),
                // **The card is sized by what the player has, and centred in
                // what is left.** A player with no achievement and no form gets
                // a shorter card, not one padded out to fill the frame; and the
                // fullest card (five achievements, six results) is scaled down
                // as one piece rather than overflowing the fixed surface.
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
                const _Wordmark(),
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
        const _Ball(size: 76),
        const SizedBox(width: 18),
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

/// The product's ball, in a white disc.
class _Ball extends StatelessWidget {
  const _Ball({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: ShareCardPalette.ink,
      ),
      child: Icon(
        Icons.sports_soccer,
        size: size * 0.66,
        color: ShareCardPalette.pitchDeep,
      ),
    );
  }
}

/// The mark again, large, at the foot of the picture.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        textDirection: TextDirection.ltr,
        children: [
          const _Ball(size: 88),
          const SizedBox(width: 22),
          Text(
            context.l10n.appName,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: ShareCardPalette.ink,
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

/// The card: a white sheet with the player's face on its top edge.
class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.data});

  final PlayerProfileCardData data;

  /// The face's diameter. Half of it stands above the card.
  static const _face = 272.0;

  /// Between two blocks inside the card.
  static const _blockGap = 40.0;

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
            padding: const EdgeInsets.fromLTRB(44, _face / 2 + 30, 44, 48),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // As tall as its blocks, with one gap between them: the distance
              // between the figures and what follows is the same on every card,
              // whether or not the player has form and an achievement.
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 18),
                Center(child: _PositionChip(position: data.primaryPosition)),
                const SizedBox(height: _blockGap),
                _Figures(data: data),
                if (data.form.isNotEmpty) ...[
                  const SizedBox(height: _blockGap),
                  _SectionTitle(l10n.shareCardFormLabel),
                  const SizedBox(height: 16),
                  _FormStrip(form: data.form),
                ],
                if (data.achievements.isNotEmpty) ...[
                  const SizedBox(height: _blockGap),
                  _SectionTitle(l10n.recentAchievementsTitle),
                  const SizedBox(height: 16),
                  _Achievements(achievements: data.achievements),
                ],
              ],
            ),
          ),
        ),
        _CardAvatar(
          avatarUrl: data.avatarUrl,
          fullName: data.fullName,
          size: _face,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: ShareCardPalette.paperInk,
        fontSize: 34,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Where they play. One position and not two: this is an identity card, and the
/// second position is a detail of team generation rather than of who somebody
/// is.
class _PositionChip extends StatelessWidget {
  const _PositionChip({required this.position});

  final PlayerPosition position;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      decoration: BoxDecoration(
        color: ShareCardPalette.paperTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        positionLabel(context.l10n, position),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: ShareCardPalette.paperInk,
          fontSize: 30,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A face on a card: the picture, or the letters of a player who has not set
/// one, in a round frame with a white ring.
///
/// Its own widget rather than the app's avatar because a card must take no
/// colour from the reader's theme — the initials sit on the card's own green at
/// a fixed strength.
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
        shape: BoxShape.circle,
        color: ShareCardPalette.avatarFill,
        border: Border.all(color: ShareCardPalette.paper, width: 10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 36,
            offset: Offset(0, 12),
          ),
        ],
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

/// The career, as the profile's own grid states it: four figures, then the
/// rating beside the player-of-the-match and goal counts.
///
/// **No figure here is computed for the card** — every one of them is already on
/// the screen the card was asked for from, which is what keeps "what you can
/// see is what you can send" true in both directions.
class _Figures extends StatelessWidget {
  const _Figures({required this.data});

  final PlayerProfileCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ShareCardPalette.paperTint,
        borderRadius: BorderRadius.circular(44),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FigureRow(
            cells: [
              _Figure(
                  value: '${data.matchesPlayed}',
                  label: l10n.shareCardStatMatches),
              _Figure(value: '${data.wins}', label: l10n.shareCardStatWins),
              _Figure(value: '${data.losses}', label: l10n.shareCardStatLosses),
              _Figure(value: '${data.draws}', label: l10n.shareCardStatDraws),
            ],
          ),
          const Divider(
            height: 2,
            thickness: 2,
            color: ShareCardPalette.paperLine,
          ),
          _FigureRow(
            cells: [
              _Figure(
                // One decimal place, which is `OP-1`'s presentation rule and
                // what every other surface shows. The disc is the profile
                // screen's own: the rating is the one figure that is a score
                // rather than a count.
                value: data.rating.toStringAsFixed(1),
                label: l10n.statCurrentRating,
                disc: true,
              ),
              _Figure(value: '${data.mvpCount}', label: l10n.shareCardStatMvp),
              _Figure(value: '${data.goals}', label: l10n.shareCardStatGoals),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of cells, divided by hairlines.
class _FigureRow extends StatelessWidget {
  const _FigureRow({required this.cells});

  final List<_Figure> cells;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0)
              const VerticalDivider(
                width: 2,
                thickness: 2,
                color: ShareCardPalette.paperLine,
              ),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }
}

/// One figure and what it counts.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, this.disc = false});

  final String value;
  final String label;

  /// Draw the value in the gold award disc.
  final bool disc;

  @override
  Widget build(BuildContext context) {
    final number = Text(
      value,
      // Left-to-right whatever the card's direction: a number is a number in
      // both languages.
      textDirection: TextDirection.ltr,
      style: TextStyle(
        color: disc ? ShareCardPalette.onAward : ShareCardPalette.paperInk,
        fontSize: disc ? 42 : 64,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 26, 8, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 92,
            child: Center(
              child: disc
                  ? Container(
                      width: 92,
                      height: 92,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: ShareCardPalette.award,
                      ),
                      child: number,
                    )
                  : number,
            ),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: ShareCardPalette.paperMuted,
                fontSize: 27,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
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
    // Six tiles fit the card with their usual scorelines; a run of double-figure
    // scores can be wider, and the strip then scales down as one piece rather
    // than overflowing the fixed surface.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in form.entries) ...[
            if (entry != form.entries.first) const SizedBox(width: 16),
            _FormBadge(entry: entry),
          ],
        ],
      ),
    );
  }
}

/// One result, as a letter in a disc on a tinted tile.
class _FormBadge extends StatelessWidget {
  const _FormBadge({required this.entry});

  final RecentFormEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (letter, background, ink) = switch (entry.outcome) {
      MatchOutcome.win => (
          l10n.recentFormWinShort,
          ShareCardPalette.resultWin,
          ShareCardPalette.ink,
        ),
      MatchOutcome.draw => (
          l10n.recentFormDrawShort,
          ShareCardPalette.resultDraw,
          ShareCardPalette.onResultDraw,
        ),
      MatchOutcome.loss => (
          l10n.recentFormLossShort,
          ShareCardPalette.resultLoss,
          ShareCardPalette.ink,
        ),
    };

    final scoreline = entry.scoreline;

    return Container(
      width: 132,
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 18),
      decoration: BoxDecoration(
        color: ShareCardPalette.paperTint,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: background),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                letter,
                maxLines: 1,
                style: TextStyle(
                  color: ink,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (scoreline != null) ...[
            const SizedBox(height: 12),
            Text(
              // The player's own goals lead, in both languages: a scoreline is
              // read home-then-away and its order is not the card's.
              scoreline,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              style: const TextStyle(
                color: ShareCardPalette.paperMuted,
                fontSize: 26,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The same achievements the profile shows, in the same read order.
///
/// A share card keeps all of them rather than silently choosing one, but
/// presents them as compact rows on one tinted block so the fixed 1080x1920
/// surface stays balanced.
class _Achievements extends StatelessWidget {
  const _Achievements({required this.achievements});

  final List<RecentHighlight> achievements;

  @override
  Widget build(BuildContext context) {
    final visible = achievements.take(5).toList(growable: false);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      decoration: BoxDecoration(
        color: ShareCardPalette.paperTint,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _AchievementRow(achievement: visible[i]),
          ],
        ],
      ),
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
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ShareCardPalette.award,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 38, color: ShareCardPalette.onAward),
        ),
        const SizedBox(width: 22),
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
                  color: ShareCardPalette.paperInk,
                  fontSize: 30,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                highlightPeriodLine(context, achievement),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ShareCardPalette.resultWin,
                  fontSize: 23,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (community != null && community.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  community,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ShareCardPalette.paperMuted,
                    fontSize: 22,
                    height: 1.15,
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
