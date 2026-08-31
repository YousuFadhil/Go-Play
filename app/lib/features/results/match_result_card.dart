import 'dart:math' as math;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
// `show`n, not imported whole: intl exports a `TextDirection` of its own and it
// would shadow Flutter's everywhere in this file.
import 'package:intl/intl.dart' show DateFormat;

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../teams/formation.dart';
import '../teams/team_lineup_card.dart';
import '../teams/team_models.dart';

/// Everything the Completed Match card draws, resolved before it is drawn.
///
/// **The match the reader is looking at, not a second read of it.** Match
/// Details has already loaded the result, the stored lineup and the name each
/// participant is shown under; all of it arrives here and nothing is looked up
/// again. The card holds no repository and cannot acquire one — the same rule
/// [TeamLineupCardData] follows, and what lets one renderer serve four cards.
///
/// [names] is the resolved display name per participant and is passed rather
/// than derived, for the reason `KB-017` gives: a player who left the community
/// after the lineup was stored still played, and the screen's rule for what to
/// call them is the one the picture must agree with.
@immutable
class MatchResultCardData {
  const MatchResultCardData({
    required this.teamAScore,
    required this.teamBScore,
    required this.lineup,
    required this.names,
    this.avatars = const {},
    this.goals = const {},
    this.mvpParticipantId,
    this.communityName,
    this.matchTitle,
    this.playedAt,
  });

  final int teamAScore;
  final int teamBScore;

  /// The stored lineup, both sides, exactly as the screen holds it.
  final List<TeamAssignment> lineup;

  /// Participant id to the name the screen shows for them.
  final Map<String, String> names;

  /// Participant id to their picture, where they have one. A Professional Guest
  /// never has one — they hold no account — and neither does a player who has
  /// not set one; both are drawn with the app's own figure instead.
  final Map<String, String> avatars;

  /// Goals per participant, and only for those who scored. Somebody absent from
  /// this map scored none — which is why a goalless match carries an empty map
  /// rather than a map of zeroes.
  final Map<String, int> goals;

  /// Who was best on the pitch, or null when nobody was named.
  ///
  /// Null is "nobody was named", never "not loaded": a result with no MVP is a
  /// complete result, so no star is drawn on anybody.
  final String? mvpParticipantId;

  /// Whose match this is, and what it was called. Both sit on the one line of
  /// context above the score; either may be absent, and an absent one is a piece
  /// the line simply does not carry.
  final String? communityName;
  final String? matchTitle;

  /// When it was played. Absent means the line is not drawn rather than filled
  /// with something invented.
  final DateTime? playedAt;

  /// The side that won, or null when the match was drawn.
  ///
  /// The same rule `MatchResult.winner` states, restated here because the card
  /// is handed two numbers rather than a result: it is a picture of a score, and
  /// a picture that had to be given the answer as well as the numbers could be
  /// given one that disagreed with them.
  TeamId? get winner {
    if (teamAScore == teamBScore) return null;
    return teamAScore > teamBScore ? TeamId.a : TeamId.b;
  }

  bool get isDraw => teamAScore == teamBScore;

  List<TeamAssignment> of(TeamId team) => [
        for (final assignment in lineup)
          if (assignment.team == team) assignment,
      ];

  int goalsOf(String participantId) => goals[participantId] ?? 0;

  bool isMvp(String participantId) =>
      mvpParticipantId != null && mvpParticipantId == participantId;

  /// Whether anybody on this card carries a star or a tally, which is what the
  /// solver needs to know before it reserves room under a name.
  bool get hasMarks =>
      mvpParticipantId != null ||
      goals.values.any((count) => count > 0);

  /// Whether there is a match to picture at all.
  ///
  /// A result with nobody in the lineup is not a card. `record_match_result`
  /// refuses to store one (`LINEUP_REQUIRED`), so this is a guard against a
  /// half-loaded screen rather than against a state the database allows.
  bool get isShareable => lineup.isNotEmpty;
}

/// The Completed Match share card: the Teams screen, after the result is in.
///
/// **It is the lineup card with the match played.** The first version of this
/// was an independent summary — a scoreboard over two name lists — and it was
/// rejected for the reason every rejected lineup card was rejected: the
/// application already draws these two teams, on grass, and a picture of them
/// that looks like something else is a picture of somebody else's product. So
/// the composition here is `TeamLineupCard`'s, down to the shared
/// [TeamLineupPitchPainter], the shared [TeamLineupMetrics] and the shared
/// [TeamLineupPlayerMark]. What a result adds, it adds *inside* that picture.
///
/// Three additions and nothing else:
///
///  * **the score, at the top and large**, over the community and the date,
///    because that is what a finished match is about;
///  * **a winner marked once** — the winning side's heading carries the word and
///    the deep green, and a draw carries neither, so a level match cannot be
///    misread at a glance as a narrow victory for whichever side is drawn first;
///  * **what each player did, on the player** — a ball and a count under the
///    name of whoever scored, a star under the name of whoever was best on the
///    pitch, both together where both apply.
///
/// **Everyone who played is drawn.** Unlike the lineup card, the goalkeeper row
/// is never omitted: that card leaves keepers out when the squad names no
/// natural goalkeeper (§10.1), which is a decision about a formation still to be
/// played. This is the record of a match, and a record that left somebody out
/// would be wrong.
///
/// **Composed at card scale, reading nothing.** Every colour is the value
/// `buildAppTheme`'s scheme resolves to, written down: a card composed on a
/// device set to dark must be the same file as one composed on a device set to
/// light, so nothing here calls `Theme.of`.
class MatchResultCard extends StatelessWidget {
  const MatchResultCard({super.key, required this.data});

  final MatchResultCardData data;

  // --- the palette --------------------------------------------------------
  //
  // `TeamLineupCard`'s, value for value. Two cards of the same match that
  // disagreed about what colour the product is would be worse than either.

  /// The page. `ColorScheme.surface`.
  static const _surface = Color(0xFFF6FBF3);

  /// `onSurface`: the community, the headings, the score.
  static const _ink = Color(0xFF181D18);

  /// `onSurfaceVariant`: the date.
  static const _inkMuted = Color(0xFF414941);

  /// `primary`: the product's own mark.
  static const _primary = Color(0xFF306A42);

  /// `primaryDeep`: the winning side, said once.
  static const _primaryDeep = Color(0xFF123D24);

  /// `outlineVariant`: the hairline above the signature.
  static const _hairline = Color(0xFFC1C9BF);

  /// The page margin. [kPageMargin] is 16 on a 360-point phone; this card is
  /// 1080 wide, so this is the same margin at the card's scale.
  static const _margin = kPageMargin * 3;

  static const _page = EdgeInsets.symmetric(horizontal: _margin);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ColoredBox(
      color: _surface,
      child: Padding(
        // Deeper than a page margin at both ends, exactly as the lineup card is:
        // this picture is looked at in a Story, where the app showing it puts
        // its own furniture across the top and bottom of the frame.
        padding: const EdgeInsets.only(top: 44, bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: _page,
              child: _Head(
                community: data.communityName,
                title: data.matchTitle,
                day: _day(context),
                data: data,
              ),
            ),
            const SizedBox(height: 20),
            // The two sides take everything that is left. They are the card.
            Expanded(
              child: Padding(padding: _page, child: _Sheet(data: data)),
            ),
            const SizedBox(height: 20),
            Padding(padding: _page, child: _Signature(label: l10n.appName)),
          ],
        ),
      ),
    );
  }

  /// The day it was played, written out. A card outlives the week that makes
  /// "Friday" mean something, so the date is stated rather than described.
  String? _day(BuildContext context) {
    final played = data.playedAt;
    if (played == null) return null;
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMMd(locale).format(played);
  }
}

// --- the head -----------------------------------------------------------------

/// The match, compactly, above the two pitches.
///
/// **Not a scoreboard, and that is the point.** An earlier version of this card
/// gave the score its own panel and 130-point numerals, and it was rejected: the
/// subject is the players, and a header that dominates them takes its room
/// straight out of the pitches below — every point of height spent here is a
/// point the solver cannot spend on making a face recognisable.
///
/// So it is two lines. One of context — community, match, date — and one of
/// score, with each side named beside its own number and the winner marked once
/// with a small chip. The score is set at a size that reads at a glance on a
/// phone and no larger.
class _Head extends StatelessWidget {
  const _Head({
    required this.community,
    required this.title,
    required this.day,
    required this.data,
  });

  final String? community;
  final String? title;
  final String? day;
  final MatchResultCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final winner = data.winner;

    final context_ = [
      if (community case final String name) name,
      if (title case final String name) name,
      if (day case final String value) value,
    ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (context_.isNotEmpty)
          SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context_,
                  maxLines: 1,
                  // No tracking: the community is Arabic as often as not, and
                  // tracking breaks the cursive joins.
                  style: const TextStyle(
                    color: MatchResultCard._inkMuted,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        // Team, score, dash, score, team — one row that follows the reader's
        // direction, so a side's name and its number stay together in both
        // languages. Each numeral states its own direction, because digits must
        // never reorder however the paragraph around them resolves.
        Row(
          textDirection: Directionality.of(context),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _ScoreSide(
                label: l10n.teamAName,
                score: data.teamAScore,
                won: winner == TeamId.a,
                winnerLabel: l10n.matchResultWinnerLabel,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '–',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: MatchResultCard._inkMuted,
                  fontSize: 44,
                  fontWeight: FontWeight.w300,
                  height: 1,
                ),
              ),
            ),
            Expanded(
              child: _ScoreSide(
                label: l10n.teamBName,
                score: data.teamBScore,
                won: winner == TeamId.b,
                winnerLabel: l10n.matchResultWinnerLabel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One side of the compact score: the team, its number, and — for the winner
/// only — the word.
///
/// The winner's number is the deep green the app uses for everything decisive;
/// the other is the ordinary ink. On a draw both are ink and neither carries the
/// chip, which is the whole of the neutral treatment: there is no third colour
/// to invent, because "nobody won" is exactly "neither side is picked out".
class _ScoreSide extends StatelessWidget {
  const _ScoreSide({
    required this.label,
    required this.score,
    required this.won,
    required this.winnerLabel,
  });

  final String label;
  final int score;
  final bool won;
  final String winnerLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: won
                ? MatchResultCard._primaryDeep
                : MatchResultCard._inkMuted,
            fontSize: 27,
            fontWeight: won ? FontWeight.w800 : FontWeight.w600,
            height: 1.2,
          ),
        ),
        Text(
          '$score',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: won ? MatchResultCard._primaryDeep : MatchResultCard._ink,
            fontSize: 64,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -2,
          ),
        ),
        if (won) ...[
          const SizedBox(height: 4),
          _WinnerChip(label: winnerLabel),
        ],
      ],
    );
  }
}

/// The winner's marker. One small pill, and no celebration graphics.
class _WinnerChip extends StatelessWidget {
  const _WinnerChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: MatchResultCard._primaryDeep,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

// --- the two sides ------------------------------------------------------------

/// Both teams, each headed and each on its own pitch.
///
/// `TeamLineupCard`'s own arrangement and its own arithmetic: the marks are
/// solved once, from the denser of the two sides, and both pitches are drawn at
/// that answer. A picture shows both at once, and a player drawn larger on one
/// side than the other would read as meaning something.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.data});

  final MatchResultCardData data;

  /// The room a side's heading is given, and the gap under it.
  static const _headingHeight = 40.0;
  static const _headingGap = 10.0;

  /// Between one side and the next. Wider than the gap under a heading, so the
  /// heading reads as belonging to the pitch below it rather than the one above.
  static const _betweenSides = 22.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = _rowsOf(TeamId.a);
    final b = _rowsOf(TeamId.b);
    final winner = data.winner;

    return LayoutBuilder(
      builder: (context, box) {
        final pitchHeight =
            (box.maxHeight - (_headingHeight + _headingGap) * 2 - _betweenSides)
                    .clamp(0.0, double.infinity) /
                2;

        final metrics = TeamLineupMetrics.solve(
          context,
          width: box.maxWidth,
          height: pitchHeight,
          columns: math.max(_widest(a), _widest(b)),
          rows: math.max(a.length, b.length),
          names: [
            for (final assignment in data.lineup)
              data.names[assignment.participantId] ?? '',
          ],
          hasHint: a.movedFrom.isNotEmpty || b.movedFrom.isNotEmpty,
          // Room under every name for a star and a tally, bought once for the
          // whole card if anybody on it carries either.
          hasMarks: data.hasMarks,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Side(
              title: l10n.teamAName,
              rows: a,
              data: data,
              metrics: metrics,
              height: pitchHeight,
              won: winner == TeamId.a,
            ),
            const SizedBox(height: _betweenSides),
            _Side(
              title: l10n.teamBName,
              rows: b,
              data: data,
              metrics: metrics,
              height: pitchHeight,
              won: winner == TeamId.b,
            ),
          ],
        );
      },
    );
  }

  /// One side, arranged into the rows a pitch is drawn from.
  ///
  /// The same call `PitchView` and the lineup card make, ordered the same way,
  /// so all three put the same player in the same row.
  ///
  /// **The goalkeeper row is always included.** The lineup card omits it when
  /// nobody in the squad keeps goal naturally, which is a judgement about a
  /// formation that has still to be played. This is the record of a match, and
  /// everybody who was on the pitch belongs on the picture of it.
  _Lines _rowsOf(TeamId team) {
    final formation = buildFormation(
      data.of(team),
      order: (x, y) => (data.names[x.participantId] ?? '')
          .compareTo(data.names[y.participantId] ?? ''),
    );

    return _Lines(
      rows: [
        if (formation.attack.isNotEmpty) formation.attack,
        ...formation.midfieldRows,
        if (formation.defence.isNotEmpty) formation.defence,
        if (formation.goalkeepers.isNotEmpty) formation.goalkeepers,
      ],
      movedFrom: formation.movedFrom,
    );
  }

  static int _widest(_Lines lines) => lines.rows.fold(
        1,
        (widest, row) => math.max(widest, row.length),
      );
}

/// One side's rows, and who on it is drawn away from their own line.
@immutable
class _Lines {
  const _Lines({required this.rows, required this.movedFrom});

  final List<List<TeamAssignment>> rows;
  final Map<String, Position> movedFrom;

  int get length => rows.length;
}

/// A heading and the pitch under it.
///
/// The heading is where a win is said: the side's name, how many were in it,
/// and — for the winner only — the word. Said once, in one place, in the app's
/// own deep green. Nothing on the pitch itself changes, because the players who
/// lost were still there and drawing them differently would say otherwise.
class _Side extends StatelessWidget {
  const _Side({
    required this.title,
    required this.rows,
    required this.data,
    required this.metrics,
    required this.height,
    required this.won,
  });

  final String title;
  final _Lines rows;
  final MatchResultCardData data;
  final TeamLineupMetrics metrics;
  final double height;
  final bool won;

  @override
  Widget build(BuildContext context) {
    final count = rows.rows.fold(0, (total, row) => total + row.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _Sheet._headingHeight,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  // The screen's own heading, down to the count in brackets.
                  '$title ($count)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: won
                        ? MatchResultCard._primaryDeep
                        : MatchResultCard._ink,
                    fontSize: 31,
                    fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _Sheet._headingGap),
        SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md * metrics.scale),
            child: CustomPaint(
              painter: TeamLineupPitchPainter(scale: metrics.scale),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: Gap.lg * metrics.scale,
                  horizontal: Gap.sm * metrics.scale,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final row in rows.rows)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final assignment in row)
                            SizedBox(
                              width: metrics.cellWidth,
                              child: _markFor(assignment),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _markFor(TeamAssignment assignment) {
    final id = assignment.participantId;
    return TeamLineupPlayerMark(
      team: assignment.team,
      name: data.names[id] ?? '',
      avatarUrl: data.avatars[id],
      // No rating. A result card is about what happened in this match, and a
      // player's standing across every other one is a different subject.
      isProfessionalGuest: assignment.isProfessionalGuest,
      movedFrom: rows.movedFrom[id],
      goals: data.goalsOf(id),
      isMvp: data.isMvp(id),
      metrics: metrics,
    );
  }
}

// --- the signature ------------------------------------------------------------

/// The product's signature: a hairline, then a play mark and the name, once, at
/// the foot.
///
/// `TeamLineupCard`'s, reproduced rather than shared. The two cards sign
/// identically today and must go on doing so, but a signature lifted into a
/// common file would be an invitation to give it a parameter — and the one thing
/// this mark may never be is configurable.
class _Signature extends StatelessWidget {
  const _Signature({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, thickness: 1, color: MatchResultCard._hairline),
        const SizedBox(height: 16),
        // The mark and the name are one thing and it reads left to right, so
        // the row is pinned rather than inherited: an Arabic card would
        // otherwise put the triangle after the name and point it backwards.
        Row(
          textDirection: TextDirection.ltr,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 15,
              height: 17,
              child: CustomPaint(painter: _PlayMarkPainter()),
            ),
            const SizedBox(width: 12),
            Text(
              label.toUpperCase(),
              // A name, not a sentence: it reads left to right in both
              // languages, and Latin capitals are the one place tracking is
              // safe.
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: MatchResultCard._primary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The play triangle that signs the card.
class _PlayMarkPainter extends CustomPainter {
  const _PlayMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = MatchResultCard._primary);
  }

  @override
  bool shouldRepaint(covariant _PlayMarkPainter oldDelegate) => false;
}
