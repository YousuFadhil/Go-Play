import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/l10n.dart';

/// The three approved surfaces share one 941-wide source coordinate system.
enum MatchStagePresentation { phone, shareBeforeResult, shareResult }

/// The approved visual tokens and source-raster coordinate system.
abstract final class MatchStage {
  static const referenceWidth = 941.0;
  static const referenceHeight = 1672.0;
  static const canonicalWidth = 1080.0;
  static const canonicalHeight = 1920.0;

  static const ground = Color(0xFF05281D);
  static const section = Color(0xFF0B3A29);
  static const pitchDark = Color(0xFF237A3A);
  static const pitchLight = Color(0xFF3B9B43);
  static const pitchLine = Color(0xB3F5F8F6);
  static const accent = Color(0xFF45DF7C);
  static const ink = Color(0xFFF5F8F6);
  static const inkMuted = Color(0xFFAEC0B5);
  static const rating = Color(0xFF082D22);
  static const star = Color(0xFFF5C451);
  static const goal = Color(0xFFFF6B57);

  // --------------------------------------------------------------------------
  // Phone-only values.
  //
  // Everything above is the approved share raster and is read by
  // `MatchResultCard`; nothing below it is. The phone draws the same match on a
  // surface a hand holds rather than on a 1080×1920 picture, so it is allowed a
  // deeper pitch, a brighter field and a badge that can be read at arm's
  // length — and it is allowed those *here*, as separate values, because
  // changing the ones above would change the shared result image.
  // --------------------------------------------------------------------------

  /// The margin every phone Match Stage element is inset from the screen by.
  static const phoneMargin = 15.0;

  /// Width ÷ height of the phone pitch. Deeper than the share raster's 1.675,
  /// which is the whole of what makes the phone field look like a field.
  static const phonePitchAspect = 1.38;

  /// The phone pitch width every phone size target below is quoted at: a 390pt
  /// screen less [phoneMargin] on each side. Sizes scale with the real width
  /// rather than snapping to this, so a larger screen gets a larger drawing.
  static const phoneReferenceWidth = 360.0;

  static const phonePitchLight = Color(0xFF34C759);
  static const phonePitchDark = Color(0xFF28A74E);

  /// The one dark the phone badges are drawn on, and the score pod under it.
  static const phoneBadge = Color(0xFF0B100D);
  static const phoneScorePod = Color(0xFF060B08);

  /// What a goal is worth saying in: a deep sports orange, and its own colour.
  ///
  /// The three marks a player can carry now answer to three families and not
  /// two — black for the rating, this for goals, [star] for the best player —
  /// so a reader tells them apart before reading any of them. Deep enough to
  /// carry white at better than 5:1, and far enough from [star] that a scorer
  /// is never mistaken for the MVP. The share card keeps [goal].
  static const phoneGoal = Color(0xFFB94A2F);

  /// Team B's mark. Team A's is [accent]; `A` and `B` still mean nothing beyond
  /// telling the two sides apart (`KB-D6`), so this is a neutral grey rather
  /// than a second team colour.
  static const phoneTeamB = Color(0xFF9FB3A6);

  static const canonicalXScale = canonicalWidth / referenceWidth;
  static const canonicalYScale = canonicalHeight / referenceHeight;

  static double xScale(double width) => width / referenceWidth;

  static double yScale(
    MatchStagePresentation presentation,
    double width,
  ) =>
      presentation == MatchStagePresentation.phone
          ? xScale(width)
          : canonicalYScale;
}

/// The exact two-line match header and optional approved result strip.
class MatchStageHeader extends StatelessWidget {
  const MatchStageHeader({
    super.key,
    required this.community,
    required this.title,
    required this.playedAt,
    this.teamAScore,
    this.teamBScore,
    this.presentation = MatchStagePresentation.phone,
  });

  final String? community;
  final String? title;
  final DateTime? playedAt;
  final int? teamAScore;
  final int? teamBScore;
  final MatchStagePresentation presentation;

  bool get hasResult => teamAScore != null && teamBScore != null;

  TeamId? get winner {
    if (!hasResult || teamAScore == teamBScore) return null;
    return teamAScore! > teamBScore! ? TeamId.a : TeamId.b;
  }

  @override
  Widget build(BuildContext context) =>
      presentation == MatchStagePresentation.phone ? _phone(context) : _share();

  /// The phone header: the same three facts, with the whitespace the share
  /// raster reserves for a 1672-tall canvas taken back out of them.
  ///
  /// Laid out as a column rather than as a fraction of the 941-wide masters, so
  /// the title and the score capsule sit at a size a screen reads at instead of
  /// at a size a picture is cropped to. The two keys the rest of the product
  /// finds this by — `match-header` for the block of facts, `result-strip` for
  /// the capsule — still name exactly what they named before.
  Widget _phone(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final date = playedAt == null
        ? null
        : DateFormat.yMMMMEEEEd(locale).format(playedAt!);
    final hasContext = community != null || date != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MatchStage.phoneMargin,
            10,
            MatchStage.phoneMargin,
            0,
          ),
          child: Column(
            key: const ValueKey('match-header'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Text(
                  title!,
                  key: const ValueKey('match-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MatchStage.ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              if (hasContext) ...[
                const SizedBox(height: 5),
                Text.rich(
                  TextSpan(
                    children: [
                      if (community != null)
                        TextSpan(
                          text: community,
                          style: const TextStyle(color: MatchStage.accent),
                        ),
                      if (community != null && date != null)
                        const TextSpan(
                          text: '  ·  ',
                          style: TextStyle(color: MatchStage.inkMuted),
                        ),
                      if (date != null)
                        TextSpan(
                          text: date,
                          style: const TextStyle(color: MatchStage.inkMuted),
                        ),
                    ],
                  ),
                  key: const ValueKey('match-context-line'),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasResult) ...[
          const SizedBox(height: 13),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MatchStage.phoneMargin,
            ),
            child: _PhoneScoreStrip(
              key: const ValueKey('result-strip'),
              teamA: context.l10n.teamAName,
              teamB: context.l10n.teamBName,
              scoreA: teamAScore!,
              scoreB: teamBScore!,
              winner: winner,
            ),
          ),
        ],
      ],
    );
  }

  Widget _share() => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sx = MatchStage.xScale(width);
          final sy = MatchStage.yScale(presentation, width);
          final totalSourceHeight = hasResult ? 265.0 : 170.0;

          return SizedBox(
            width: width,
            height: totalSourceHeight * sy,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: width,
                  height: 170 * sy,
                  child: SizedBox(
                    key: const ValueKey('match-header'),
                    child: _MatchInfo(
                      community: community,
                      title: title,
                      playedAt: playedAt,
                      sx: sx,
                      sy: sy,
                    ),
                  ),
                ),
                if (hasResult)
                  Positioned(
                    left: 51 * sx,
                    top: 178 * sy,
                    width: 839 * sx,
                    height: 87 * sy,
                    child: _ScoreStrip(
                      teamA: context.l10n.teamAName,
                      teamB: context.l10n.teamBName,
                      scoreA: teamAScore!,
                      scoreB: teamBScore!,
                      winner: winner,
                      sx: sx,
                      sy: sy,
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

class _MatchInfo extends StatelessWidget {
  const _MatchInfo({
    required this.community,
    required this.title,
    required this.playedAt,
    required this.sx,
    required this.sy,
  });

  final String? community;
  final String? title;
  final DateTime? playedAt;
  final double sx;
  final double sy;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final date = playedAt == null
        ? null
        : DateFormat.yMMMMEEEEd(locale).format(playedAt!);

    return Stack(
      children: [
        if (title != null)
          Positioned(
            left: 24 * sx,
            right: 24 * sx,
            top: 46 * sy,
            child: Text(
              title!,
              key: const ValueKey('match-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MatchStage.ink,
                fontSize: 49 * sx,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        if (community != null || date != null)
          Positioned(
            left: 24 * sx,
            right: 24 * sx,
            top: 119 * sy,
            child: Text.rich(
              TextSpan(
                children: [
                  if (community != null)
                    TextSpan(
                      text: community,
                      style: const TextStyle(color: MatchStage.accent),
                    ),
                  if (community != null && date != null)
                    const TextSpan(
                      text: '  ·  ',
                      style: TextStyle(color: MatchStage.inkMuted),
                    ),
                  if (date != null)
                    TextSpan(
                      text: date,
                      style: const TextStyle(color: MatchStage.inkMuted),
                    ),
                ],
              ),
              key: const ValueKey('match-context-line'),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22 * sx,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
      ],
    );
  }
}

/// The phone result strip: `Team A   6 – 4   Team B`, and nothing else.
///
/// One capsule, one near-black pod holding both numerals, and the winner said
/// in accent green rather than with a trophy — the icon was a third thing to
/// read in a strip whose whole job is to be read at a glance.
///
/// **The row reads in the reader's own direction.** Team A is always the
/// leading side and Team B the trailing one, which in Arabic puts Team A on the
/// right and in English on the left — the order the team sections below already
/// use, so a reader meets the two sides in the same order twice.
///
/// The pairing is carried by the layout, not by a string: the labels and the
/// two numerals are four separate children of two rows that flip together, so
/// Team A's numeral moves to Team A's end and can never end up under Team B's
/// name. Each numeral keeps its own [TextDirection.ltr] so that a two-digit
/// score stays a two-digit score in either locale.
class _PhoneScoreStrip extends StatelessWidget {
  const _PhoneScoreStrip({
    super.key,
    required this.teamA,
    required this.teamB,
    required this.scoreA,
    required this.scoreB,
    required this.winner,
  });

  final String teamA;
  final String teamB;
  final int scoreA;
  final int scoreB;
  final TeamId? winner;

  @override
  Widget build(BuildContext context) => Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0A3928),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: MatchStage.accent.withValues(alpha: .28),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _PhoneStripLabel(label: teamA, won: winner == TeamId.a),
            ),
            _PhoneScorePod(
              scoreA: scoreA,
              scoreB: scoreB,
              winner: winner,
            ),
            Expanded(
              child: _PhoneStripLabel(label: teamB, won: winner == TeamId.b),
            ),
          ],
        ),
      );
}

class _PhoneStripLabel extends StatelessWidget {
  const _PhoneStripLabel({required this.label, required this.won});

  final String label;
  final bool won;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          label,
          // The reader's own direction, so a truncated name loses its tail
          // rather than its head. The share strip keeps its pinned direction.
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: won ? MatchStage.accent : MatchStage.ink,
            fontSize: 15,
            fontWeight: won ? FontWeight.w800 : FontWeight.w600,
            height: 1,
          ),
        ),
      );
}

class _PhoneScorePod extends StatelessWidget {
  const _PhoneScorePod({
    required this.scoreA,
    required this.scoreB,
    required this.winner,
  });

  final int scoreA;
  final int scoreB;
  final TeamId? winner;

  @override
  Widget build(BuildContext context) {
    Widget numeral(int value, bool won) => Text(
          '$value',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: won ? MatchStage.accent : MatchStage.ink,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        );

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MatchStage.phoneScorePod,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: MatchStage.accent.withValues(alpha: .38),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          numeral(scoreA, winner == TeamId.a),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 9),
            child: Text(
              '–',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: MatchStage.inkMuted,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
          numeral(scoreB, winner == TeamId.b),
        ],
      ),
    );
  }
}

class _ScoreStrip extends StatelessWidget {
  const _ScoreStrip({
    required this.teamA,
    required this.teamB,
    required this.scoreA,
    required this.scoreB,
    required this.winner,
    required this.sx,
    required this.sy,
  });

  final String teamA;
  final String teamB;
  final int scoreA;
  final int scoreB;
  final TeamId? winner;
  final double sx;
  final double sy;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        key: const ValueKey('result-strip'),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xB30B3A29), Color(0xA605281D)],
          ),
          borderRadius: BorderRadius.circular(16 * sx),
          border: Border.all(
            color: MatchStage.accent.withValues(alpha: 0.55),
            width: 1.2 * sx,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15 * sx),
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              Expanded(
                child: _StripSide(
                  label: teamA,
                  won: winner == TeamId.a,
                  sx: sx,
                ),
              ),
              SizedBox(
                width: 300 * sx,
                child: _StripScore(
                  scoreA: scoreA,
                  scoreB: scoreB,
                  winner: winner,
                  sx: sx,
                  sy: sy,
                ),
              ),
              Expanded(
                child: _StripSide(
                  label: teamB,
                  won: winner == TeamId.b,
                  sx: sx,
                ),
              ),
            ],
          ),
        ),
      );
}

class _StripSide extends StatelessWidget {
  const _StripSide({
    required this.label,
    required this.won,
    required this.sx,
  });

  final String label;
  final bool won;
  final double sx;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: won
            ? MatchStage.accent.withValues(alpha: 0.07)
            : Colors.transparent,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 22 * sx),
          child: Row(
            textDirection: TextDirection.ltr,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (won) ...[
                Icon(
                  Icons.emoji_events_outlined,
                  key: const ValueKey('winner-trophy'),
                  size: 25 * sx,
                  color: MatchStage.accent,
                ),
                SizedBox(width: 28 * sx),
              ],
              Flexible(
                child: Text(
                  label,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MatchStage.ink,
                    fontSize: 31 * sx,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _StripScore extends StatelessWidget {
  const _StripScore({
    required this.scoreA,
    required this.scoreB,
    required this.winner,
    required this.sx,
    required this.sy,
  });

  final int scoreA;
  final int scoreB;
  final TeamId? winner;
  final double sx;
  final double sy;

  @override
  Widget build(BuildContext context) {
    Widget numeral(int value, bool won) => Container(
          width: 108 * sx,
          height: 75 * sy,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: won
                  ? const [Color(0xFF08752F), Color(0xFF0B4B2C)]
                  : const [Color(0xB30B3A29), Color(0xB305281D)],
            ),
            borderRadius: BorderRadius.circular(14 * sx),
            border: Border.all(
              color: MatchStage.accent.withValues(alpha: won ? 0.8 : 0.35),
              width: 1.2 * sx,
            ),
          ),
          child: Text(
            '$value',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: MatchStage.ink,
              fontSize: 55 * sx,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        );

    return Row(
      textDirection: TextDirection.ltr,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        numeral(scoreA, winner == TeamId.a),
        SizedBox(
          width: 43 * sx,
          child: Center(
            child: Text(
              '–',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: MatchStage.ink,
                fontSize: 35 * sx,
                fontWeight: FontWeight.w400,
                height: 1,
              ),
            ),
          ),
        ),
        numeral(scoreB, winner == TeamId.b),
      ],
    );
  }
}

/// One exact team-card region from the approved 941-wide masters.
class MatchStageSection extends StatelessWidget {
  const MatchStageSection({
    super.key,
    required this.title,
    required this.won,
    required this.child,
    this.team = TeamId.a,
    this.presentation = MatchStagePresentation.phone,
  });

  static const sourceWidth = 898.0;
  static const sourceHeight = 607.0;

  final String title;
  final bool won;
  final Widget child;
  final TeamId team;
  final MatchStagePresentation presentation;

  @override
  Widget build(BuildContext context) =>
      presentation == MatchStagePresentation.phone ? _phone() : _share();

  /// The phone side: a marked heading, and then the pitch.
  ///
  /// **The dark card is gone.** It was a section-coloured block with an accent
  /// border, and on a phone it put a second dark surface between the dark
  /// ground and the one thing on the page anybody came to look at. Taking it
  /// out gives the pitch both the card's inset and the reader's attention, and
  /// costs nothing that told the two sides apart — the heading and its
  /// indicator already do that, and do it in less than a tenth of the height.
  ///
  /// The share card keeps the card, and keeps it in [_share] below.
  Widget _phone() {
    final isTeamA = team == TeamId.a;

    return Column(
      key: ValueKey(isTeamA ? 'team-a-section' : 'team-b-section'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Align(
            alignment: Alignment.centerRight,
            child: _TeamHeading(title: title, sx: 1, phoneTeam: team),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: constraints.maxWidth / MatchStage.phonePitchAspect,
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _share() => LayoutBuilder(
        builder: (context, constraints) {
          final sx = constraints.maxWidth / sourceWidth;
          final sy = presentation == MatchStagePresentation.phone
              ? sx
              : MatchStage.canonicalYScale;
          final isTeamA = team == TeamId.a;
          final pitchLeft = (isTeamA ? 25.68 : 27.82) * sx;
          final pitchTop = (isTeamA ? 87.74 : 96.30) * sy;
          final pitchWidth = (isTeamA ? 842.09 : 838.88) * sx;
          final pitchHeight = 502.90 * sy;

          return SizedBox(
            key: ValueKey(isTeamA ? 'team-a-section' : 'team-b-section'),
            width: constraints.maxWidth,
            height: sourceHeight * sy,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: MatchStage.section,
                      borderRadius: BorderRadius.circular(19 * sx),
                      border: Border.all(
                        color: MatchStage.accent.withValues(alpha: 0.35),
                        width: 1.1 * sx,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 14 * sy,
                  right: 32.37 * sx,
                  child: _TeamHeading(title: title, sx: sx),
                ),
                Positioned(
                  left: pitchLeft,
                  top: pitchTop,
                  width: pitchWidth,
                  height: pitchHeight,
                  child: child,
                ),
              ],
            ),
          );
        },
      );
}

/// "Team A", "Team B" — the words, and nothing beside them.
///
/// There used to be a short green bar tucked against each heading. It has been
/// withdrawn, and withdrawn here rather than at either of the places that draw
/// this: the Teams screen and the shared result card render the same heading,
/// so a removal made on one of them would have left the other with a decoration
/// nothing else on the page still answered to.
///
/// Nothing replaces it. The heading is anchored by its own end, so taking the
/// bar out shortens the row without moving the words a reader is looking for.
///
/// [phoneTeam] is the one exception, and it is a phone exception: with the dark
/// card withdrawn, the heading is the only thing left saying which side this
/// is, so it carries a small mark — emerald for A, neutral grey for B. The
/// share card passes nothing and gets the words alone, exactly as before.
class _TeamHeading extends StatelessWidget {
  const _TeamHeading({
    required this.title,
    required this.sx,
    this.phoneTeam,
  });

  final String title;
  final double sx;
  final TeamId? phoneTeam;

  @override
  Widget build(BuildContext context) {
    final team = phoneTeam;
    final isTeamA = team == TeamId.a;
    final label = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: MatchStage.ink,
        fontSize: team == null ? 35 * sx : 16.5,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.rtl,
      children: [
        if (team != null) ...[
          Container(
            key: ValueKey(
              isTeamA ? 'team-a-indicator' : 'team-b-indicator',
            ),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: isTeamA ? MatchStage.accent : MatchStage.phoneTeamB,
              shape: BoxShape.circle,
              boxShadow: isTeamA
                  ? [
                      BoxShadow(
                        color: MatchStage.accent.withValues(alpha: .55),
                        blurRadius: 7,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: label),
        ],
        // The share heading keeps exactly one child, and keeps it a bare
        // `Text`: the removal of the decorative bar is asserted through the
        // shape of this row, and a wrapper added for the phone's benefit would
        // have quietly stood in for the thing that was withdrawn.
        if (team == null) label,
      ],
    );
  }
}
