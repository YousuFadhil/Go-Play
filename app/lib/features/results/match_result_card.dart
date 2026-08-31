import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
// `show`n, not imported whole: intl exports a `TextDirection` of its own and it
// would shadow Flutter's everywhere in this file.
import 'package:intl/intl.dart' show DateFormat;

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/time_format.dart';
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

  /// Goals per participant, and only for those who scored. Somebody absent from
  /// this map scored none — which is why a goalless match carries an empty map
  /// rather than a map of zeroes.
  final Map<String, int> goals;

  /// Who was best on the pitch, or null when nobody was named.
  ///
  /// Null is "nobody was named", never "not loaded": a result with no MVP is a
  /// complete result, so the card simply does not draw the line.
  final String? mvpParticipantId;

  /// Whose match this is — the card's smallest heading and its context.
  final String? communityName;

  /// When it was played. Absent means the line is not drawn rather than filled
  /// with something invented.
  final DateTime? playedAt;

  /// The side that won, or null when the match was drawn.
  ///
  /// The same rule [MatchResult.winner] states, restated here because the card
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

  /// Everyone who scored, most goals first and alphabetically within a tally.
  ///
  /// Ordered here rather than in the card so that the order is a property of the
  /// data and testable without a widget. Ties are broken by name so the same
  /// match always makes the same picture.
  List<({String participantId, String name, int goals, TeamId team})>
      get scorers {
    final teams = {
      for (final assignment in lineup) assignment.participantId: assignment.team,
    };
    final rows = [
      for (final entry in goals.entries)
        if (entry.value > 0 && teams.containsKey(entry.key))
          (
            participantId: entry.key,
            name: names[entry.key] ?? '—',
            goals: entry.value,
            team: teams[entry.key]!,
          ),
    ];
    rows.sort((a, b) {
      final byGoals = b.goals.compareTo(a.goals);
      return byGoals != 0 ? byGoals : a.name.compareTo(b.name);
    });
    return rows;
  }

  /// Whether there is a match to picture at all.
  ///
  /// A result with nobody in the lineup is not a card. `record_match_result`
  /// refuses to store one (`LINEUP_REQUIRED`), so this is a guard against a
  /// half-loaded screen rather than against a state the database allows.
  bool get isShareable => lineup.isNotEmpty;
}

/// The Completed Match share card: what the match finished as, sent as a
/// picture.
///
/// **The same world as the lineup card, a different subject.** `TeamLineupCard`
/// pictures two squads, so it is two pitches. This pictures a *result*, so the
/// score is the largest thing on it and the two sides are read as lists beneath
/// it — a pitch says where somebody stood, and where somebody stood is not what
/// a full-time card is about. What the two share is everything that makes them
/// the same product: the app's own surface, the app's own ink, the one page
/// margin, and the same signature at the foot.
///
/// **The winner is said once.** The winning side's panel is filled and its
/// score is set in the deep green the app uses for everything decisive; the
/// other side stays on the page. Nothing else changes — no crown, no laurel, no
/// second colour — because a result is already the strongest statement on the
/// card and decorating it would be saying it twice.
///
/// **A draw is not a quiet win.** Both panels take the same neutral treatment
/// and neither score is emphasised, so a 2–2 cannot be misread at a glance as a
/// narrow victory for whichever side happens to be drawn first.
///
/// **Composed at card scale, reading nothing.** Every colour below is the value
/// `buildAppTheme`'s scheme resolves to, written down: a card composed on a
/// device set to dark must be the same file as one composed on a device set to
/// light, so nothing here calls `Theme.of`.
///
/// **Presentation only.** It takes [MatchResultCardData] and draws it: no
/// repository, no rule of its own about who won, nothing invented for a field
/// that is absent.
class MatchResultCard extends StatelessWidget {
  const MatchResultCard({super.key, required this.data});

  final MatchResultCardData data;

  // --- the palette --------------------------------------------------------
  //
  // `TeamLineupCard`'s, value for value. Two cards of the same match that
  // disagreed about what colour the product is would be worse than either.

  /// The page. `ColorScheme.surface`.
  static const _surface = Color(0xFFF6FBF3);

  /// `onSurface`: the community, the names, the scores.
  static const _ink = Color(0xFF181D18);

  /// `onSurfaceVariant`: the date, the positions, everything secondary.
  static const _inkMuted = Color(0xFF414941);

  /// `primary`: the product's own mark.
  static const _primary = Color(0xFF306A42);

  /// The deep green the winning panel is filled with, and the app's own
  /// `primaryDeep`.
  static const _primaryDeep = Color(0xFF123D24);

  /// On that fill.
  static const _onPrimaryDeep = Color(0xFFFFFFFF);

  /// The panel a side that did not win sits on: `surfaceContainerLowest`, the
  /// same white every card in the app is drawn on.
  static const _panel = Color(0xFFFFFFFF);

  /// `outlineVariant`: the hairline above the signature and around a panel.
  static const _hairline = Color(0xFFC1C9BF);

  /// A Professional Guest's marker, `tertiaryContainer` on
  /// `onTertiaryContainer` — the pair every roster in the app marks a guest
  /// with.
  static const _guest = Color(0xFFBEEAF5);
  static const _onGuest = Color(0xFF204D56);

  /// The amber the app reserves for a figure worth noticing. Used for exactly
  /// one thing here: the star beside the best player.
  static const _mvp = Color(0xFFC9A227);

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
        // Deeper than a page margin at both ends, for the reason the lineup
        // card is: this picture is looked at in a Story, where the app showing
        // it puts its own furniture across the top and bottom of the frame.
        padding: const EdgeInsets.only(top: 44, bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: _page,
              child: _Masthead(
                community: data.communityName,
                day: _day(context),
              ),
            ),
            const SizedBox(height: 30),
            Padding(padding: _page, child: _Scoreboard(data: data)),
            const SizedBox(height: 34),
            // The two sides take everything that is left, with the scorers and
            // the best player under them.
            Expanded(
              child: Padding(padding: _page, child: _Body(data: data)),
            ),
            const SizedBox(height: 22),
            Padding(padding: _page, child: _Signature(label: l10n.appName)),
          ],
        ),
      ),
    );
  }

  /// The day, in the app's own wording, so a result card and a match card
  /// cannot describe the same fixture two different ways.
  String? _day(BuildContext context) {
    final played = data.playedAt;
    if (played == null) return null;
    final locale = Localizations.localeOf(context).toString();
    // The long form: a card outlives the week that makes "Friday" mean
    // something, so the date is written out rather than described.
    return DateFormat.yMMMMd(locale).format(played);
  }
}

// --- the head -----------------------------------------------------------------

/// Whose match this was, and when.
///
/// **Small, and above the score.** On the lineup card the community is the
/// subject and takes the largest type on the page. Here the subject is the
/// result, so the community steps down to a heading over it — the same
/// information, correctly ranked for a different picture.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.community, required this.day});

  final String? community;
  final String? day;

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
            height: 48,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  community,
                  maxLines: 1,
                  style: const TextStyle(
                    color: MatchResultCard._ink,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
        if (day != null) ...[
          const SizedBox(height: 4),
          Text(
            day,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MatchResultCard._inkMuted,
              fontSize: 26,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

// --- the score ----------------------------------------------------------------

/// The two sides and what the match finished as — the card's largest statement.
///
/// **Pinned left to right, always.** A score is two numbers in a fixed order
/// either side of a dash, and a bidirectional paragraph will happily reverse
/// them: "3 – 1" set in an Arabic column comes out reading as 1–3, which is not
/// a layout problem but a wrong result. So the row states its own direction, and
/// each side's panel is placed by this widget rather than by the paragraph.
/// Team A is on the left in both languages, which is what the headings say.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.data});

  final MatchResultCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final winner = data.winner;

    // `IntrinsicHeight` is what lets the two panels be the same height without
    // either of them being told what that height is. Stretching inside a row
    // whose own height is decided by its children is a layout that cannot
    // resolve; measuring the taller panel first and stretching to that can. The
    // cost is one extra layout pass over two boxes, paid once per card.
    return IntrinsicHeight(
      child: Row(
        textDirection: TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ScorePanel(
              title: l10n.teamAName,
              score: data.teamAScore,
              won: winner == TeamId.a,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _ScorePanel(
              title: l10n.teamBName,
              score: data.teamBScore,
              won: winner == TeamId.b,
            ),
          ),
        ],
      ),
    );
  }
}

/// One side of the scoreboard: who they are, and how many they scored.
class _ScorePanel extends StatelessWidget {
  const _ScorePanel({
    required this.title,
    required this.score,
    required this.won,
  });

  final String title;
  final int score;

  /// Whether this side won. False on both panels of a drawn match, which is the
  /// whole of the neutral treatment: there is no third state to draw, because
  /// "nobody won" is exactly "neither panel is filled".
  final bool won;

  @override
  Widget build(BuildContext context) {
    final ink = won ? MatchResultCard._onPrimaryDeep : MatchResultCard._ink;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: won ? MatchResultCard._primaryDeep : MatchResultCard._panel,
        borderRadius: BorderRadius.circular(Radii.lg * 2),
        border: won
            ? null
            : Border.all(color: MatchResultCard._hairline, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: won
                    ? MatchResultCard._onPrimaryDeep
                    : MatchResultCard._inkMuted,
                fontSize: 30,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$score',
              maxLines: 1,
              // Digits, and their own direction: a numeral is the one run of
              // text on this card whose order must not be negotiable.
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: ink,
                fontSize: 132,
                fontWeight: FontWeight.w800,
                height: 1.05,
                letterSpacing: -4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- lineups, scorers, best player --------------------------------------------

/// Everything under the score: who played on each side, who scored, and who was
/// best on the pitch.
///
/// **One column of type, in the order the reader wants it.** The score answers
/// the first question; the two lineups answer "who was that", the scorers "how",
/// and the best player is the last line before the signature. Each part is drawn
/// only where it exists — a goalless match has no scorer list, and a match with
/// nobody named has no best-player line, rather than either having an empty box
/// with a dash in it.
class _Body extends StatelessWidget {
  const _Body({required this.data});

  final MatchResultCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scorers = data.scorers;
    final mvp = data.mvpParticipantId;
    final winner = data.winner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Lineup(
                  title: l10n.teamAName,
                  players: data.of(TeamId.a),
                  data: data,
                  emphasised: winner == TeamId.a,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Lineup(
                  title: l10n.teamBName,
                  players: data.of(TeamId.b),
                  data: data,
                  emphasised: winner == TeamId.b,
                ),
              ),
            ],
          ),
        ),
        if (scorers.isNotEmpty) ...[
          const SizedBox(height: 18),
          _Scorers(label: l10n.matchResultScorersLabel, rows: scorers),
        ],
        if (mvp != null) ...[
          const SizedBox(height: 18),
          _Mvp(label: l10n.mvpLabel, name: data.names[mvp] ?? '—'),
        ],
      ],
    );
  }
}

/// One side's full lineup, as a list of names.
///
/// The heading carries the count, exactly as the Teams screen and the lineup
/// card do, so a reader can see at a glance that both sides are complete.
class _Lineup extends StatelessWidget {
  const _Lineup({
    required this.title,
    required this.players,
    required this.data,
    required this.emphasised,
  });

  final String title;
  final List<TeamAssignment> players;
  final MatchResultCardData data;

  /// Whether this is the winning side. It buys the heading the deep green and
  /// nothing else: the names on both sides are set identically, because the
  /// players who lost were still there.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    // Alphabetical, which is the one order that does not imply a ranking. The
    // stored lineup's order is a formation decision and would read here as one.
    final sorted = [...players]..sort((a, b) => (data.names[a.participantId] ?? '')
        .compareTo(data.names[b.participantId] ?? ''));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$title (${players.length})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: emphasised
                ? MatchResultCard._primaryDeep
                : MatchResultCard._inkMuted,
            fontSize: 27,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        for (final assignment in sorted)
          _PlayerLine(
            name: data.names[assignment.participantId] ?? '—',
            goals: data.goals[assignment.participantId] ?? 0,
            isProfessionalGuest: assignment.isProfessionalGuest,
            isMvp: assignment.participantId == data.mvpParticipantId,
          ),
      ],
    );
  }
}

/// One player in a lineup: their name, and what they did.
///
/// The goal count sits with the player rather than only in the scorer list,
/// because the first place a reader looks for "did he score" is his own name.
/// The list below is the summary, not the record.
class _PlayerLine extends StatelessWidget {
  const _PlayerLine({
    required this.name,
    required this.goals,
    required this.isProfessionalGuest,
    required this.isMvp,
  });

  final String name;
  final int goals;
  final bool isProfessionalGuest;
  final bool isMvp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isMvp) ...[
            const Icon(Icons.star_rounded, size: 24, color: MatchResultCard._mvp),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: MatchResultCard._ink,
                fontSize: 24,
                fontWeight: isMvp ? FontWeight.w700 : FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
          if (isProfessionalGuest) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: MatchResultCard._guest,
                borderRadius: BorderRadius.circular(Radii.sm * 2),
              ),
              child: const Icon(
                Icons.workspace_premium_outlined,
                size: 18,
                color: MatchResultCard._onGuest,
              ),
            ),
          ],
          if (goals > 0) ...[
            const SizedBox(width: 8),
            _GoalTally(goals: goals),
          ],
        ],
      ),
    );
  }
}

/// How many a player scored, as a mark rather than a sentence.
///
/// A ball and a numeral, pinned left to right so the count never lands on the
/// wrong side of its own glyph. One goal is drawn the same way as four — the
/// number carries it, and four balls in a row would set differently on every
/// line of the card.
class _GoalTally extends StatelessWidget {
  const _GoalTally({required this.goals});

  final int goals;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.ltr,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.sports_soccer,
          size: 20,
          color: MatchResultCard._primary,
        ),
        const SizedBox(width: 4),
        Text(
          '$goals',
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            color: MatchResultCard._primary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Who scored, in one run across the foot of the lineups.
class _Scorers extends StatelessWidget {
  const _Scorers({required this.label, required this.rows});

  final String label;
  final List<({String participantId, String name, int goals, TeamId team})> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, thickness: 1, color: MatchResultCard._hairline),
        const SizedBox(height: 12),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: MatchResultCard._inkMuted,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 22,
          runSpacing: 6,
          children: [
            for (final row in rows)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bounded rather than flexible. A `Wrap` hands its children
                  // unbounded width, and a `Flexible` inside a row that has no
                  // width to share is a layout assertion rather than a long
                  // name — so the cap is stated, and it is what makes the run
                  // wrap instead of overflowing.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MatchResultCard._ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  _GoalTally(goals: row.goals),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// The best player on the pitch, where one was named.
class _Mvp extends StatelessWidget {
  const _Mvp({required this.label, required this.name});

  final String label;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 34, color: MatchResultCard._mvp),
        const SizedBox(width: 10),
        Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: MatchResultCard._inkMuted,
            fontSize: 23,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MatchResultCard._ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

// --- the signature ------------------------------------------------------------

/// The product's signature: a hairline, then a play mark and the name, once, at
/// the foot.
///
/// `TeamLineupCard._Signature`, reproduced rather than shared. The two cards
/// sign identically today and must go on doing so, but a signature lifted into
/// a common file would be an invitation to give it a parameter — and the one
/// thing this mark may never be is configurable.
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
        const SizedBox(height: 18),
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
