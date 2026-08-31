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

  /// Whose match this is.
  final String? communityName;

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
                day: _day(context),
                data: data,
              ),
            ),
            const SizedBox(height: 26),
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

/// Whose match this was, when, and how it finished.
///
/// The community and the date are one quiet line; the score is the largest thing
/// on the card. That ranking is the difference between this card and the lineup
/// card, where the community is the subject and takes the largest type.
class _Head extends StatelessWidget {
  const _Head({
    required this.community,
    required this.day,
    required this.data,
  });

  final String? community;
  final String? day;
  final MatchResultCardData data;

  @override
  Widget build(BuildContext context) {
    final community = this.community;
    final day = this.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (community != null)
          SizedBox(
            height: 46,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  community,
                  maxLines: 1,
                  // No tracking: the name is Arabic as often as not, and
                  // tracking breaks the cursive joins.
                  style: const TextStyle(
                    color: MatchResultCard._ink,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
        if (day != null) ...[
          const SizedBox(height: 2),
          Text(
            day,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MatchResultCard._inkMuted,
              fontSize: 25,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 14),
        _Scoreline(data: data),
      ],
    );
  }
}

/// The score, and nothing else on its line.
///
/// **Each numeral keeps its own direction; the pair follows the reader's.**
/// Those are two different problems and they need opposite answers. Inside a
/// numeral, digits must never be reordered — so every one is a `Text` with an
/// explicit left-to-right direction. Between the two numerals, the order has to
/// agree with the headings below: in Arabic "الفريق أ" is on the right, so
/// Team A's score belongs on the right too. A card that put the winning team's
/// name on one side and its score on the other would make the reader check.
///
/// This is safe from the reordering that made the lineup card pin its clock,
/// because nothing here is one run of text: the three pieces are three widgets
/// and the row places them, so no bidirectional algorithm gets a say.
class _Scoreline extends StatelessWidget {
  const _Scoreline({required this.data});

  final MatchResultCardData data;

  @override
  Widget build(BuildContext context) {
    final winner = data.winner;

    return Row(
      textDirection: Directionality.of(context),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Numeral(score: data.teamAScore, won: winner == TeamId.a),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            '–',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: MatchResultCard._inkMuted,
              fontSize: 76,
              fontWeight: FontWeight.w300,
              height: 1,
            ),
          ),
        ),
        _Numeral(score: data.teamBScore, won: winner == TeamId.b),
      ],
    );
  }
}

/// One half of the score.
///
/// The winner's numeral is the deep green the app uses for everything decisive;
/// the other is the ordinary ink. On a draw both are ink, which is the whole of
/// the neutral treatment — there is no third colour to invent, because "nobody
/// won" is exactly "neither numeral is picked out".
class _Numeral extends StatelessWidget {
  const _Numeral({required this.score, required this.won});

  final int score;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$score',
      textDirection: TextDirection.ltr,
      style: TextStyle(
        color: won ? MatchResultCard._primaryDeep : MatchResultCard._ink,
        fontSize: 112,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: -4,
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
  static const _headingHeight = 46.0;
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
    final l10n = context.l10n;
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
                    fontSize: 36,
                    fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              if (won) ...[
                const SizedBox(width: 14),
                _WinnerTag(label: l10n.matchResultWinnerLabel),
              ],
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

/// The word, beside the winning side's heading.
///
/// A small filled pill rather than a banner across the card: the score above has
/// already said who won, and this names it for a reader scanning the two
/// headings. Tasteful is the requirement, and one pill is the whole of it.
class _WinnerTag extends StatelessWidget {
  const _WinnerTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
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
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
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
