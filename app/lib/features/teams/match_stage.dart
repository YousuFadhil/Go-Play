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
  Widget build(BuildContext context) => LayoutBuilder(
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
  Widget build(BuildContext context) => LayoutBuilder(
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

class _TeamHeading extends StatelessWidget {
  const _TeamHeading({required this.title, required this.sx});

  final String title;
  final double sx;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MatchStage.ink,
              fontSize: 35 * sx,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          SizedBox(width: 15 * sx),
          Container(
            width: 42 * sx,
            height: 5 * sx,
            decoration: BoxDecoration(
              color: MatchStage.accent,
              borderRadius: BorderRadius.circular(4 * sx),
            ),
          ),
        ],
      );
}
