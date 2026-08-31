import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
// `show`n, not imported whole: intl exports a `TextDirection` of its own and it
// would shadow Flutter's everywhere in this file.
import 'package:intl/intl.dart' show DateFormat;

import '../../core/l10n.dart';
import '../../core/design.dart';
import '../../core/tokens.dart';

/// The one dark ground a match is presented on, and the pieces that sit on it.
///
/// **One visual language, two surfaces.** The Teams screen and the picture that
/// leaves it are the same composition — a header, then a section per side — and
/// everything that decides how that looks lives here so the two cannot drift.
/// The screen builds it at scale 1; the card builds it larger, on a fixed
/// 1080×1920 canvas, and nothing else about it changes.
///
/// **Dark on purpose, and only here.** The rest of the product is a pale page
/// with white cards, which is right for lists and forms. A lineup is not either:
/// it is a pitch, and a pitch on a pale page reads as a picture pasted onto a
/// document. Going dark is what makes the two teams the screen rather than
/// something on it — so this palette is the Teams feature's own and is not
/// exported to any other screen.
abstract final class MatchStage {
  /// The ground everything sits on. Darker than the app's `primaryDeep`, which
  /// is a fill for headers rather than a page.
  static const ground = Color(0xFF0A2318);

  /// A section: one shade up from the ground, so the two sides read as blocks
  /// without needing a border to say so.
  static const section = Color(0xFF10301F);
  static const sectionEdge = Color(0xFF1C4A31);

  /// The pitch inside a section, and the markings on it.
  static const grass = Color(0xFF216B45);
  static const grassBand = Color(0xFF25744B);
  static const grassLine = Color(0x2EFFFFFF);

  /// Type on the ground.
  static const ink = Color(0xFFEAF6EF);
  static const inkMuted = Color(0xFF9FB8A9);

  /// The bright green a result is said in. It has to carry on a dark ground,
  /// which `primary` does not.
  static const accent = Color(0xFF63E39D);

  /// The winning side's segment of the score strip, against the other's.
  static const wonFill = Color(0xFF15402B);
  static const restFill = Color(0xFF0E2A1D);

  /// The star. Brighter than the app's `warn`, which was chosen against white.
  static const star = Color(0xFFF0C43C);

  /// The badge a goal tally sits on, over grass.
  static const badge = Color(0x1FFFFFFF);
  static const badgeEdge = Color(0x8AFFFFFF);
}

/// The match, above the two sides: whose it is, what it was called, when it was
/// played, and — once there is one — how it finished.
///
/// **Embedded, not a card.** It sits directly on the ground with no surface of
/// its own, which is what stops the result reading as a scoreboard bolted to the
/// top of a lineup. The score is a strip rather than a panel for the same
/// reason: it is one line of the screen, and the pitches below it are the rest.
class MatchStageHeader extends StatelessWidget {
  const MatchStageHeader({
    super.key,
    required this.community,
    required this.title,
    required this.playedAt,
    this.teamAScore,
    this.teamBScore,
    this.scale = 1,
  });

  final String? community;
  final String? title;
  final DateTime? playedAt;

  /// Both null before a result exists, which is the whole of the pre-match
  /// state: the header is then the community, the match and the date, and the
  /// strip below is simply not drawn.
  final int? teamAScore;
  final int? teamBScore;

  final double scale;

  bool get _hasResult => teamAScore != null && teamBScore != null;

  TeamId? get _winner {
    if (!_hasResult || teamAScore == teamBScore) return null;
    return teamAScore! > teamBScore! ? TeamId.a : TeamId.b;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final title = this.title;
    final community = this.community;
    final playedAt = this.playedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (community != null)
          Text(
            community,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MatchStage.inkMuted,
              fontSize: 12.5 * scale,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        if (title != null) ...[
          SizedBox(height: 2 * scale),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            // No tracking: a match name is Arabic as often as not, and tracking
            // breaks the cursive joins.
            style: TextStyle(
              color: MatchStage.ink,
              fontSize: 21 * scale,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
        if (playedAt != null) ...[
          SizedBox(height: 4 * scale),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 12 * scale,
                color: MatchStage.inkMuted,
              ),
              SizedBox(width: 6 * scale),
              Flexible(
                child: Text(
                  DateFormat.yMMMMEEEEd(locale).format(playedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MatchStage.inkMuted,
                    fontSize: 12.5 * scale,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_hasResult) ...[
          SizedBox(height: 12 * scale),
          _ScoreStrip(
            teamA: l10n.teamAName,
            teamB: l10n.teamBName,
            scoreA: teamAScore!,
            scoreB: teamBScore!,
            winner: _winner,
            winnerLabel: l10n.matchResultWinnerLabel,
            scale: scale,
          ),
        ],
      ],
    );
  }
}

/// The score: two named sides and the numbers between them, as one strip.
///
/// **Each side keeps its own half, and the winner's half is lit.** That is the
/// whole of the winner treatment here — a slightly lighter fill, the name in the
/// accent green, and one small chip. No banner, no trophy across the score, and
/// on a draw neither half is lit, so a level match cannot read at a glance as a
/// narrow win for whichever side is drawn first.
///
/// The row follows the reader's direction so a side's name and its number stay
/// together in both languages; each numeral states its own direction, because
/// digits must never reorder however the paragraph around them resolves.
class _ScoreStrip extends StatelessWidget {
  const _ScoreStrip({
    required this.teamA,
    required this.teamB,
    required this.scoreA,
    required this.scoreB,
    required this.winner,
    required this.winnerLabel,
    required this.scale,
  });

  final String teamA;
  final String teamB;
  final int scoreA;
  final int scoreB;
  final TeamId? winner;
  final String winnerLabel;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: MatchStage.sectionEdge, width: scale),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          // The approved Arabic composition keeps Team A physically left and
          // Team B physically right. Each Arabic label still shapes RTL.
          textDirection: TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _StripSide(
                label: teamA,
                won: winner == TeamId.a,
                winnerLabel: winnerLabel,
                scale: scale,
              ),
            ),
            _StripScore(
              scoreA: scoreA,
              scoreB: scoreB,
              winner: winner,
              scale: scale,
            ),
            Expanded(
              child: _StripSide(
                label: teamB,
                won: winner == TeamId.b,
                winnerLabel: winnerLabel,
                scale: scale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One named side of the strip, with its crest.
class _StripSide extends StatelessWidget {
  const _StripSide({
    required this.label,
    required this.won,
    required this.winnerLabel,
    required this.scale,
  });

  final String label;
  final bool won;
  final String winnerLabel;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: won ? MatchStage.wonFill : MatchStage.restFill,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12 * scale,
          vertical: 10 * scale,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (won) ...[
              _WinnerChip(label: winnerLabel, scale: scale),
              SizedBox(height: 5 * scale),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield,
                  size: 17 * scale,
                  color: won
                      ? MatchStage.accent
                      : MatchStage.inkMuted.withValues(alpha: 0.55),
                ),
                SizedBox(width: 7 * scale),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: won ? MatchStage.accent : MatchStage.ink,
                      fontSize: 13 * scale,
                      fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The two numbers, in the middle of the strip.
class _StripScore extends StatelessWidget {
  const _StripScore({
    required this.scoreA,
    required this.scoreB,
    required this.winner,
    required this.scale,
  });

  final int scoreA;
  final int scoreB;
  final TeamId? winner;
  final double scale;

  @override
  Widget build(BuildContext context) {
    Widget numeral(int value, bool won) => Text(
          '$value',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: won ? MatchStage.accent : MatchStage.ink,
            fontSize: 30 * scale,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -1 * scale,
          ),
        );

    return ColoredBox(
      color: MatchStage.restFill,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 12 * scale,
        ),
        child: Center(
          child: Row(
            textDirection: TextDirection.ltr,
            mainAxisSize: MainAxisSize.min,
            children: [
              numeral(scoreA, winner == TeamId.a),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 9 * scale),
                child: Text(
                  '–',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: MatchStage.inkMuted,
                    fontSize: 22 * scale,
                    fontWeight: FontWeight.w300,
                    height: 1,
                  ),
                ),
              ),
              numeral(scoreB, winner == TeamId.b),
            ],
          ),
        ),
      ),
    );
  }
}

/// The winner's word. One small pill and nothing else.
class _WinnerChip extends StatelessWidget {
  const _WinnerChip({required this.label, required this.scale});

  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 9 * scale,
        vertical: 1.5 * scale,
      ),
      decoration: BoxDecoration(
        color: GoColors.primaryContainer,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: GoColors.onPrimaryContainer,
          fontSize: 9.5 * scale,
          fontWeight: FontWeight.w800,
          height: 1.4,
        ),
      ),
    );
  }
}

/// One side's block: a heading, and the pitch under it.
///
/// **A section, not a floating card.** The heading is marked with a short
/// accent bar rather than boxed, and the pitch sits inside the same dark
/// surface, so a side reads as one thing. The winner earns a trophy disc at the
/// far end of its heading — the second and last place a win is said, after the
/// strip above.
class MatchStageSection extends StatelessWidget {
  const MatchStageSection({
    super.key,
    required this.title,
    required this.won,
    required this.child,
    this.scale = 1,
    this.fill = false,
  });

  final String title;
  final bool won;
  final Widget child;
  final double scale;

  /// Whether the pitch should take whatever height the section is given.
  ///
  /// False on the screen, where the section is as tall as its rows and the page
  /// scrolls. True on a card, which has a fixed height and would otherwise end
  /// with the two sides packed at the top and a band of empty ground under
  /// them.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MatchStage.section,
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(
          color: won
              ? MatchStage.accent.withValues(alpha: 0.35)
              : MatchStage.sectionEdge,
          width: 1 * scale,
        ),
      ),
      padding: EdgeInsets.all(10 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Padding(
            padding:
                EdgeInsets.fromLTRB(4 * scale, 2 * scale, 4 * scale, 8 * scale),
            child: Row(
              children: [
                Container(
                  width: 3 * scale,
                  height: 16 * scale,
                  decoration: BoxDecoration(
                    color: won ? MatchStage.accent : MatchStage.inkMuted,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
                SizedBox(width: 8 * scale),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MatchStage.ink,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
                if (won)
                  Container(
                    width: 26 * scale,
                    height: 26 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MatchStage.accent.withValues(alpha: 0.16),
                    ),
                    child: Icon(
                      Icons.emoji_events,
                      size: 15 * scale,
                      color: MatchStage.accent,
                    ),
                  ),
              ],
            ),
          ),
          if (fill) Expanded(child: child) else child,
        ],
      ),
    );
  }
}
