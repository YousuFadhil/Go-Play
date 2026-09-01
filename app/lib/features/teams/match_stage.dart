import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
// `show`n, not imported whole: intl exports a `TextDirection` of its own and it
// would shadow Flutter's everywhere in this file.
import 'package:intl/intl.dart' show DateFormat;

import '../../core/l10n.dart';
import '../../core/design.dart';

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
  static const wonFill = Color(0xFF123724);
  static const restFill = Color(0xFF0E2A1D);

  /// The star. Brighter than the app's `warn`, which was chosen against white.
  static const star = Color(0xFFF0C43C);

  /// The badge a goal tally sits on, over grass.
  static const badge = Color(0x0FFFFFFF);
  static const badgeEdge = Color(0x52FFFFFF);
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
    this.share = false,
  });

  final String? community;
  final String? title;
  final DateTime? playedAt;

  /// Both null before a result exists, which is the whole of the pre-match
  /// state: the header is then the community, the match and the date, and the
  /// strip below is simply not drawn.
  final int? teamAScore;
  final int? teamBScore;

  /// Uses the fixed 1080 × 1920 export typography instead of phone metrics.
  final bool share;

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
              fontSize: share ? 28 : 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        if (title != null) ...[
          SizedBox(height: share ? 2 : 0),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            // No tracking: a match name is Arabic as often as not, and tracking
            // breaks the cursive joins.
            style: TextStyle(
              color: MatchStage.ink,
              fontSize: share ? 52 : 18,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
        if (playedAt != null) ...[
          SizedBox(height: share ? 4 : 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: share ? 23 : 11,
                color: MatchStage.inkMuted,
              ),
              SizedBox(width: share ? 10 : 5),
              Flexible(
                child: Text(
                  DateFormat.yMMMMEEEEd(locale).format(playedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MatchStage.inkMuted,
                    fontSize: share ? 24 : 11,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_hasResult) ...[
          SizedBox(height: share ? 18 : 12),
          _ScoreStrip(
            teamA: l10n.teamAName,
            teamB: l10n.teamBName,
            scoreA: teamAScore!,
            scoreB: teamBScore!,
            winner: _winner,
            winnerLabel: l10n.matchResultWinnerLabel,
            share: share,
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
    required this.share,
  });

  final String teamA;
  final String teamB;
  final int scoreA;
  final int scoreB;
  final TeamId? winner;
  final String winnerLabel;
  final bool share;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: share ? 92 : 72,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(share ? 22 : 14),
          border: Border.all(
            color: MatchStage.sectionEdge,
            width: share ? 2 : 1,
          ),
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
                  share: share,
                ),
              ),
              _StripScore(
                scoreA: scoreA,
                scoreB: scoreB,
                winner: winner,
                share: share,
              ),
              Expanded(
                child: _StripSide(
                  label: teamB,
                  won: winner == TeamId.b,
                  winnerLabel: winnerLabel,
                  share: share,
                ),
              ),
            ],
          ),
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
    required this.share,
  });

  final String label;
  final bool won;
  final String winnerLabel;
  final bool share;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: won ? MatchStage.wonFill : MatchStage.restFill,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: share ? 18 : 10,
          vertical: share ? 10 : 7,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (won) ...[
              _WinnerChip(label: winnerLabel, share: share),
              SizedBox(height: share ? 5 : 3),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield,
                  size: share ? 28 : 17,
                  color:
                      MatchStage.inkMuted.withValues(alpha: won ? 0.75 : 0.55),
                ),
                SizedBox(width: share ? 12 : 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MatchStage.ink,
                      fontSize: share ? 24 : 12.5,
                      fontWeight: won ? FontWeight.w700 : FontWeight.w600,
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
    required this.share,
  });

  final int scoreA;
  final int scoreB;
  final TeamId? winner;
  final bool share;

  @override
  Widget build(BuildContext context) {
    Widget numeral(int value, bool won) => Text(
          '$value',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: won ? MatchStage.accent : MatchStage.ink,
            fontSize: share ? 62 : 28,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: share ? -2 : -1,
          ),
        );

    return ColoredBox(
      color: MatchStage.restFill,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: share ? 28 : 14,
          vertical: share ? 10 : 8,
        ),
        child: Center(
          child: Row(
            textDirection: TextDirection.ltr,
            mainAxisSize: MainAxisSize.min,
            children: [
              numeral(scoreA, winner == TeamId.a),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: share ? 16 : 8),
                child: Text(
                  '–',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: MatchStage.inkMuted,
                    fontSize: share ? 46 : 20,
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
  const _WinnerChip({required this.label, required this.share});

  final String label;
  final bool share;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: share ? 14 : 7,
        vertical: share ? 2 : 1,
      ),
      decoration: BoxDecoration(
        color: MatchStage.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(
          color: MatchStage.accent.withValues(alpha: 0.28),
          width: share ? 2 : 1,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: MatchStage.accent,
          fontSize: share ? 18 : 8.5,
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
    this.share = false,
    this.fill = false,
  });

  final String title;
  final bool won;
  final Widget child;
  final bool share;

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
        borderRadius: BorderRadius.circular(share ? 28 : 18),
        border: Border.all(
          color: won
              ? MatchStage.accent.withValues(alpha: 0.24)
              : MatchStage.sectionEdge,
          width: share ? 2 : 1,
        ),
      ),
      padding: EdgeInsets.all(share ? 12 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              share ? 8 : 4,
              share ? 3 : 1,
              share ? 8 : 4,
              share ? 10 : 6,
            ),
            child: Row(
              children: [
                Container(
                  width: share ? 6 : 3,
                  height: share ? 30 : 14,
                  decoration: BoxDecoration(
                    color: won ? MatchStage.accent : MatchStage.inkMuted,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
                SizedBox(width: share ? 14 : 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MatchStage.ink,
                      fontSize: share ? 36 : 14,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
                if (won)
                  Container(
                    width: share ? 42 : 22,
                    height: share ? 42 : 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MatchStage.accent.withValues(alpha: 0.10),
                    ),
                    child: Icon(
                      Icons.emoji_events,
                      size: share ? 25 : 13,
                      color: MatchStage.accent,
                    ),
                  ),
              ],
            ),
          ),
          if (fill) Expanded(child: Center(child: child)) else child,
        ],
      ),
    );
  }
}
