import 'dart:math' as math;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
// `show`n, not imported whole: intl exports a `TextDirection` of its own and
// it would shadow Flutter's everywhere in this file.
import 'package:intl/intl.dart' show DateFormat;

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/time_format.dart';
import 'formation.dart';
import 'pitch_view.dart';
import 'team_models.dart';

/// Everything the Team Lineup card draws, resolved before it is drawn.
///
/// **The lineup the reader is looking at, not a second read of it.** The Teams
/// screen has already loaded the stored assignments, the profiles behind them
/// and the name each player is shown under; all of that arrives here and
/// nothing is looked up again.
///
/// **The match is context, never the subject.** A lineup card is about a
/// community's teams; the fixture that produced them earns one quiet line
/// beneath the name, and only where it exists. Nothing here is a placeholder —
/// a field that is null is a line that is not drawn.
///
/// [names] is the resolved display name per participant, and it is passed
/// rather than derived on purpose. The screen's rule — the profile first, the
/// registration second, a dash for somebody neither knows — is `KB-017`
/// reasoning about a player who left after the lineup was stored, and a card
/// that re-derived it could disagree with the pitch behind it.
@immutable
class TeamLineupCardData {
  const TeamLineupCardData({
    required this.lineup,
    required this.players,
    required this.names,
    required this.hasNaturalGoalkeeper,
    this.communityName,
    this.startAt,
    this.endAt,
    this.location,
  });

  /// The stored lineup, both sides, exactly as the screen holds it.
  final List<TeamAssignment> lineup;

  /// The profiles behind the assignments. A player with no entry left the match
  /// after the lineup was stored and is still drawn — `KB-017` records that
  /// they played — from the assignment alone.
  final Map<String, PlayerCoreInputs> players;

  /// Participant id to the name the screen shows for them.
  final Map<String, String> names;

  /// Whether the squad holds anybody who keeps goal (§10.1). Decides whether a
  /// goal row is drawn at all, and is the screen's own answer.
  final bool hasNaturalGoalkeeper;

  /// Whose teams these are — the card's subject and its largest text.
  ///
  /// Nullable because `Match.communityName` is: it is filled by the read that
  /// joins the community, which is the read the Teams screen makes, but the
  /// type admits absence. Where it is absent the heading is simply not drawn
  /// rather than filled with something invented.
  final String? communityName;

  /// The fixture, for the one context line under the name. Any of these may be
  /// missing, and each missing piece is left out rather than stood in for.
  final DateTime? startAt;
  final DateTime? endAt;
  final String? location;

  List<TeamAssignment> of(TeamId team) => [
        for (final assignment in lineup)
          if (assignment.team == team) assignment,
      ];

  /// Whether there is a lineup to picture at all.
  ///
  /// An empty lineup is not a card. The Teams screen shows "not generated yet"
  /// in that state and there is nothing on it to send, so the Share action is
  /// not offered and this is what says so.
  bool get isShareable => lineup.isNotEmpty;
}

/// The Team Lineup share card: the Teams screen, sent as a picture.
///
/// **The screen is the design, and this is the screen.** Three cards were built
/// before this one and each invented a look for the occasion — a chalk board, an
/// editorial poster, a broadcast camera behind the goal. All three were rejected
/// for the same reason, which took three tries to hear: the application already
/// draws these two teams, it draws them well, and a picture of them that looks
/// like something else is a picture of somebody else's product. So nothing here
/// is designed. `PitchView` and `PlayerCard` are the source, and every number on
/// this card is theirs — the grass and the stripe over it, the mown bands, the
/// faint markings, the rounded corner, the rows read attack-first, the white
/// disc with a face in it, the name under the disc and the rating under the
/// name.
///
/// **Two pitches, one each, exactly as the screen stacks them.** The screen
/// gives each side a heading — its name and how many are in it — and its own
/// pitch below that heading; the card does the same thing in the same order. It
/// is also what tells the two sides apart, and it is *all* that tells them
/// apart: the screen has no team colours (`KB-D6` — A and B mean nothing beyond
/// each other), and a card that invented a pair would be answering a question
/// the product does not ask.
///
/// **What is polished, and what is not.** Three things are the card's rather
/// than the screen's, and each is a consequence of the picture being fixed where
/// the screen scrolls. The two pitches are given equal height, because a picture
/// cannot scroll and two panels of different heights read as an accident. Every
/// mark on the card is drawn at one size, solved once from the denser of the two
/// sides, so a five-a-side is drawn large and an eleven-a-side small but no two
/// players are drawn differently. And a name too long for its cell is set on two
/// lines rather than cut, which the screen cannot afford at 82 points wide and a
/// picture can.
///
/// **Composed at card scale.** The card is built in the engine's own 1080×1920
/// units, so what it solves for is a radius — [TeamLineupMetrics] — and the whole of
/// `PlayerCard` is rebuilt around it in the ratios the phone uses. Nothing
/// measures the device it was composed on, and nothing reads the theme: a
/// picture has to be the same file whoever sent it, and every colour here is
/// the value the app's own scheme resolves to, written down.
///
/// **Presentation only.** It takes [TeamLineupCardData] and draws it: no
/// repository, no formation decision of its own, no statistic invented.
/// [buildFormation] decides the rows and who is drawn out of their line, which
/// is the same call the screen makes.
class TeamLineupCard extends StatelessWidget {
  const TeamLineupCard({super.key, required this.data});

  final TeamLineupCardData data;

  // --- the palette --------------------------------------------------------
  //
  // Every one of these is what `buildAppTheme`'s scheme — seeded 0xFF1B7A43 —
  // actually resolves to, written down rather than read. A card composed from
  // `Theme.of` would be a different file on a device set to dark, and the same
  // lineup has to make the same picture wherever it was sent from.

  /// The page. `ColorScheme.surface`, which is the Teams screen's own
  /// background.
  static const _surface = Color(0xFFF6FBF3);

  /// `onSurface`: the community, and each side's heading.
  static const _ink = Color(0xFF181D18);

  /// `onSurfaceVariant`: the fixture line under the community.
  static const _inkMuted = Color(0xFF414941);

  /// `primary`: the face inside an empty disc, and the product's own mark.
  static const _primary = Color(0xFF306A42);

  /// `outlineVariant`: the hairline above the signature.
  static const _hairline = Color(0xFFC1C9BF);

  /// A Professional Guest's disc, `tertiaryContainer` on `onTertiaryContainer`
  /// — the pair every roster in the app marks a guest with.
  static const _guest = Color(0xFFBEEAF5);
  static const _onGuest = Color(0xFF204D56);

  /// The page margin. [kPageMargin] is 16 on a 360-point phone; this card is
  /// 1080 wide, so the margin is the same margin at the card's scale.
  static const _margin = kPageMargin * 3;

  static const _page = EdgeInsets.symmetric(horizontal: _margin);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ColoredBox(
      color: _surface,
      child: Padding(
        // Deeper than a page margin at both ends. This picture is looked at in
        // a Story, where the app showing it puts its own furniture across the
        // top and bottom of the frame, and the community and the signature are
        // the two things that would sit under it.
        padding: const EdgeInsets.only(top: 44, bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: _page,
              child: _Header(
                name: data.communityName,
                day: _day(context),
                clock: _clock(context),
                place: _place(),
                format: _format(),
              ),
            ),
            const SizedBox(height: 28),
            // The two sides take everything that is left. They are the card.
            Expanded(
              child: Padding(padding: _page, child: _Sheet(data: data)),
            ),
            const SizedBox(height: 22),
            Padding(padding: _page, child: _Signature(label: l10n.appName)),
          ],
        ),
      ),
    );
  }

  /// The day, in the app's own wording, so a lineup card and a match card
  /// cannot describe the same fixture two different ways.
  String? _day(BuildContext context) {
    final start = data.startAt;
    return start == null ? null : formatMatchDay(context, start);
  }

  /// The clock, in the pieces the header sets separately.
  ///
  /// **One meridiem where one will do.** The shared helper writes each end with
  /// its own and isolates the pair, which is right for a list of matches and
  /// wrong on one short line: set in Arabic it puts two "م" in the line and
  /// leaves the reader working out which one is the kick-off. So a match that
  /// starts and ends in the same half of the day is written "8:00–10:00 م", and
  /// only one that crosses noon or midnight is written with both — the one time
  /// the second one carries information. Twelve-hour either way, which is the
  /// product's decision and not the device's.
  ///
  /// **Two pieces, never one string.** A range with a meridiem at each end
  /// cannot be written as one run of text and laid out reliably: the neutral
  /// dash between an Arabic "ص" and the digits after it joins the wrong side,
  /// and the line comes out as "11:00 م 1:00 – ص" whichever direction the
  /// paragraph is given. Handing the header two pieces and letting it place
  /// them left to right is not a workaround for that — it is the only way to
  /// state an order that the text itself does not carry.
  List<String> _clock(BuildContext context) {
    final start = data.startAt;
    if (start == null) return const [];

    final locale = Localizations.localeOf(context).toString();
    final clock = DateFormat('h:mm', locale);
    final half = DateFormat('a', locale);

    final end = data.endAt;
    if (end == null) return ['${clock.format(start)} ${half.format(start)}'];
    if (half.format(start) == half.format(end)) {
      // Safe as one piece: the meridiem is at the end, where an LTR line puts
      // it anyway, and there is nothing neutral between two directions.
      return ['${clock.format(start)}–${clock.format(end)} ${half.format(end)}'];
    }
    return [
      '${clock.format(start)} ${half.format(start)}',
      '${clock.format(end)} ${half.format(end)}',
    ];
  }

  /// Where it is.
  String? _place() {
    final place = data.location?.trim();
    return (place == null || place.isEmpty) ? null : place;
  }

  /// "5 V 5" — the shape of the match, read off the lineup being drawn.
  ///
  /// Counted from what the card actually puts on the pitch rather than from the
  /// stored lineup, because a squad with nobody in goal has its keepers left
  /// out (§10.1) and a line disagreeing with the picture beneath it is worse
  /// than no line. Null where a side is empty: there is no format to name.
  String? _format() {
    int drawn(TeamId team) => data
        .of(team)
        .where((a) =>
            data.hasNaturalGoalkeeper || a.assignedPosition != Position.gk)
        .length;

    final a = drawn(TeamId.a);
    final b = drawn(TeamId.b);
    if (a == 0 || b == 0) return null;
    return '$a V $b';
  }
}

// --- the head -----------------------------------------------------------------

/// Who the teams belong to, and one line of fixture under it.
///
/// **Two lines and no furniture.** The pitches are the card; this says whose
/// they are and stands aside. It is set against the page margin rather than
/// centred, so the community, both headings and both pitches share the one left
/// edge the app's pages are built on — which is the difference between a picture
/// of an application and a poster about one.
///
/// Every part is optional and nothing is stood in for. A card with no fixture is
/// a community and two pitches, and the header is simply one line.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.day,
    required this.clock,
    required this.place,
    required this.format,
  });

  final String? name;
  final String? day;
  final List<String> clock;
  final String? place;
  final String? format;

  /// The room the community is given, whatever it is called.
  ///
  /// Fixed, and the name is scaled into it rather than allowed to set the
  /// height: everything below is measured from what is left, and a header that
  /// grew by a line would take that line off both pitches.
  static const _subjectHeight = 66.0;

  /// And the room the fixture under it is given, for the same reason.
  static const _asideHeight = 36.0;

  @override
  Widget build(BuildContext context) {
    final place = this.place;
    final hasAside = day != null || clock.isNotEmpty || place != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (name case final String name)
          SizedBox(
            height: _subjectHeight,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  name,
                  maxLines: 1,
                  // No tracking: the name is Arabic as often as not, and
                  // tracking breaks the cursive joins.
                  style: const TextStyle(
                    color: TeamLineupCard._ink,
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
        if (hasAside || format != null) ...[
          const SizedBox(height: 6),
          // One line, and it is one line whatever is on it. The venue is
          // trimmed first, because it is the one piece that can be any length;
          // if the rest still will not fit the page — a long day in Arabic and
          // a clock that crosses noon — the whole line is set a little smaller
          // rather than allowed to run off the card or take a second line off
          // both pitches.
          SizedBox(
            height: _asideHeight,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (day case final String day) _Aside(text: day),
                    if (clock.isNotEmpty) ...[
                      if (day != null) const _Dot(),
                      _Clock(parts: clock),
                    ],
                    if (place case final String place) ...[
                      if (day != null || clock.isNotEmpty) const _Dot(),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: _Aside(text: place),
                      ),
                    ],
                    if (format case final String format) ...[
                      if (hasAside) const _Dot(),
                      _Aside(text: format, direction: TextDirection.ltr),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One piece of the fixture line.
class _Aside extends StatelessWidget {
  const _Aside({required this.text, this.direction});

  final String text;

  /// Set only where the piece has an order of its own that the paragraph must
  /// not decide — the clock, and the format's digits.
  final TextDirection? direction;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textDirection: direction,
      style: const TextStyle(
        color: TeamLineupCard._inkMuted,
        fontSize: 27,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ),
    );
  }
}

/// The clock: kick-off, a dash, and the end of the match.
///
/// Laid out as separate pieces in a row that is pinned left to right, so the
/// start is on the left of the dash in every language. A match runs
/// start-then-end whatever the reader's script does, and this is the only
/// arrangement that says so without depending on how a bidirectional paragraph
/// happens to resolve a neutral character between two directions.
class _Clock extends StatelessWidget {
  const _Clock({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.ltr,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, part) in parts.indexed) ...[
          if (index > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: _Aside(text: '–', direction: TextDirection.ltr),
            ),
          _Aside(text: part, direction: TextDirection.ltr),
        ],
      ],
    );
  }
}

/// The punctuation between two pieces of fixture.
///
/// Drawn rather than typed: a middle dot is a neutral character, and a neutral
/// character between an Arabic word and a run of digits is exactly the thing
/// that reorders a line nobody asked to have reordered.
class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0x66414941),
      ),
    );
  }
}

/// The product's signature: a hairline, then a play mark and the name, once, at
/// the foot.
///
/// **A signature, not a masthead.** The card is the community's; the product
/// signs it the way a studio signs a print — small, at the bottom edge, on the
/// same left margin as everything above it. The mark is a play triangle, drawn
/// rather than fetched, so nothing here is an asset that could belong to
/// somebody else.
class _Signature extends StatelessWidget {
  const _Signature({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, thickness: 1, color: TeamLineupCard._hairline),
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
                color: TeamLineupCard._primary,
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
    canvas.drawPath(path, Paint()..color = TeamLineupCard._primary);
  }

  @override
  bool shouldRepaint(covariant _PlayMarkPainter oldDelegate) => false;
}

// --- the two sides ------------------------------------------------------------

/// Both teams, each headed and each on its own pitch — the Teams screen's own
/// arrangement, given a fixed height instead of a scroll.
///
/// **One size for the whole card.** The marks are solved once here, from the
/// denser of the two sides, and both pitches are drawn at that answer. The
/// screen can afford two pitches at different scales because a reader only sees
/// one of them at a time; a picture shows both at once, and a player drawn
/// larger on one side than the other would read as meaning something.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.data});

  final TeamLineupCardData data;

  /// The room a side's heading is given — `titleMedium` at the card's scale,
  /// and the gap under it.
  static const _headingHeight = 48.0;
  static const _headingGap = 12.0;

  /// Between one side and the next. Wider than the gap under a heading, so the
  /// heading reads as belonging to the pitch below it rather than to the pitch
  /// above.
  static const _betweenSides = 26.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = _rowsOf(TeamId.a);
    final b = _rowsOf(TeamId.b);

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
          // A hint is reserved on the card only when somebody on it needs one,
          // so an ordinary lineup does not pay a line of height for a statement
          // nobody is making.
          hasHint: a.movedFrom.isNotEmpty || b.movedFrom.isNotEmpty,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Side(
              title: l10n.teamAName,
              team: TeamId.a,
              rows: a,
              data: data,
              metrics: metrics,
              height: pitchHeight,
            ),
            const SizedBox(height: _betweenSides),
            _Side(
              title: l10n.teamBName,
              team: TeamId.b,
              rows: b,
              data: data,
              metrics: metrics,
              height: pitchHeight,
            ),
          ],
        );
      },
    );
  }

  /// One side, arranged into the rows a pitch is drawn from.
  ///
  /// The same call `PitchView` makes, ordered the same way, so the card and the
  /// screen put the same player in the same row.
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
        if (data.hasNaturalGoalkeeper && formation.goalkeepers.isNotEmpty)
          formation.goalkeepers,
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
class _Side extends StatelessWidget {
  const _Side({
    required this.title,
    required this.team,
    required this.rows,
    required this.data,
    required this.metrics,
    required this.height,
  });

  final String title;
  final TeamId team;
  final _Lines rows;
  final TeamLineupCardData data;
  final TeamLineupMetrics metrics;
  final double height;

  @override
  Widget build(BuildContext context) {
    final count = rows.rows.fold(0, (total, row) => total + row.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _Sheet._headingHeight,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              // The screen's own heading, down to the count in brackets.
              '$title ($count)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: TeamLineupCard._ink,
                fontSize: 38,
                // `titleMedium`, which this theme sets to w600.
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
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
                  // The rows share whatever the pitch has: packed from the top
                  // is the screen's answer because the screen's pitch is as tall
                  // as its rows, and this one is as tall as the card allows.
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
    final player = data.players[assignment.participantId];
    return TeamLineupPlayerMark(
      team: team,
      name: data.names[assignment.participantId] ?? '',
      avatarUrl: player?.avatarUrl,
      rating: player?.overallRating,
      isProfessionalGuest: assignment.isProfessionalGuest,
      movedFrom: rows.movedFrom[assignment.participantId],
      metrics: metrics,
    );
  }
}

// --- how big everything is ----------------------------------------------------

/// The one size every mark on the card is drawn at.
///
/// **`PlayerCard` rebuilt around a radius.** On the phone the avatar is 21
/// points and everything else about a player is fixed against that: the cell is
/// 82 points wide, the gaps are [Gap.xs], the name and the rating are
/// `labelSmall`. None of those absolute numbers survive a move to a 1080-point
/// canvas, but the *ratios* between them are the design, so this solves for the
/// radius the densest row can afford and multiplies the screen's own proportions
/// back out of it.
///
/// **Solved from the denser side, applied to both.** The card is one picture and
/// the two teams in it are the same two teams.
@immutable
class TeamLineupMetrics {
  const TeamLineupMetrics({
    required this.radius,
    required this.cellWidth,
    required this.nameWidth,
    required this.nameSize,
    required this.nameHeight,
    required this.blockHeight,
    required this.nameLines,
    required this.hintSize,
  });

  /// The avatar's radius, and the unit the rest of the card is a multiple of.
  final double radius;

  /// What one player is given across the row, and how wide their name may run
  /// inside it.
  final double cellWidth;
  final double nameWidth;

  final double nameSize;

  /// The room reserved for the name on every mark, so a two-line name never
  /// pushes its own face out of line with the faces beside it.
  final double nameHeight;

  /// The room reserved for the *whole* of what is written under a face — the
  /// name, the rating and the hint — filled from the top.
  ///
  /// One block rather than three, because the slack a short name leaves has to
  /// fall at the foot of everything a player carries and not between a player
  /// and their own rating. Reserving the name alone put a hole under every
  /// one-line name on a card that had bought a second line for somebody else,
  /// and a number floating a line clear of the player it belongs to is a number
  /// that belongs to nobody.
  final double blockHeight;

  final int nameLines;

  /// Zero unless somebody on this card is drawn out of their own line.
  final double hintSize;

  /// How much larger than the phone this card is drawing. The pitch's markings
  /// and its corner are absolute numbers on the screen, and this is what turns
  /// them into the same markings at the card's size.
  double get scale => radius / _appRadius;

  // The Teams screen's own measurements, and the only place they are written
  // down. `PlayerCard`: a 21-point avatar in an 82-point cell, [Gap.xs] above
  // and below it and between the face and the name, with the name and the
  // rating both set in `labelSmall` — 11 points on a 16-point line.
  static const double _appRadius = 21;
  static const double _appCell = 82;
  static const double _appLabel = 11;

  static const double _cellPerRadius = _appCell / _appRadius;
  static const double _gapPerRadius = Gap.xs / _appRadius;
  static const double _labelPerRadius = _appLabel / _appRadius;

  /// As large as the card will ever draw a player: three times the phone's, at
  /// which point the picture is 1080 wide and so is the phone's pitch. Past
  /// that a small lineup would be enlarged for drama, which is the thing every
  /// rejected version of this card did.
  static const double _maxRadius = _appRadius * 3;

  /// Below this a player stops being one, and the card would be better off
  /// crowded than illegible. Reached only by a lineup larger than the product
  /// supports.
  static const double _minRadius = 17.0;

  /// How much of a cell a name may use. The remainder is the gutter between one
  /// name and the next, and it is why two long names cannot touch.
  static const double _nameShare = 0.90;

  /// The hint under a moved player, against the name beside it.
  static const double _hintShare = 0.82;

  /// The room a goal tally and a best-player star take under a name, against
  /// that name's own size. Generous by a little: a badge that overflowed its
  /// block would be a layout error in a picture somebody was about to send.
  static const double _marksShare = 1.75;

  static TeamLineupMetrics solve(
    BuildContext context, {
    required double width,
    required double height,
    required int columns,
    required int rows,
    required Iterable<String> names,
    required bool hasHint,
    // Whether any player on this card carries a goal tally or a best-player
    // star. Reserved the same way the hint is, and for the same reason: the
    // block under a face is one fixed height on every mark, so room that is not
    // asked for here is room the badges would overflow.
    bool hasMarks = false,
  }) {
    // What the pitch keeps for itself, in the screen's own proportions: the
    // Gap.lg above and below the rows, the Gap.sm at each end of one. Taken at
    // the largest radius so the answer does not depend on itself.
    const inset = _maxRadius / _appRadius;
    final innerWidth =
        math.max(1.0, width - Gap.sm * inset * 2 - Gap.sm * inset * 2);
    final innerHeight = math.max(1.0, height - Gap.lg * inset * 2);

    // One measurement for the whole card: what a line of *these* names actually
    // occupies on the engine that will draw them. Android's fallback face for
    // Arabic is taller than the 1.2 the style asks for, and a block reserved
    // from the arithmetic is a block that overflows into a picture somebody was
    // about to send.
    final lineHeight = _PlayerName.measuredLineHeight(context, names);

    final cell = innerWidth / math.max(1, columns);

    // Two lines cost every mark on the card a line of height, so the question
    // is asked once, of the whole lineup, at the size a single line would be
    // drawn — and only bought if somebody actually needs it.
    TeamLineupMetrics at(double radius, int lines) {
      final name = radius * _labelPerRadius;
      final line = (name * lineHeight).ceilToDouble();
      final hint =
          hasHint ? (name * _hintShare * lineHeight).ceilToDouble() * 1.3 : 0.0;
      // The badge pill: a glyph a little larger than the type, its own padding,
      // and the gap that attaches it to the name. Measured against the name
      // size rather than the line, because that is what it is drawn from.
      final marks = hasMarks ? (name * _marksShare).ceilToDouble() : 0.0;
      return TeamLineupMetrics(
        radius: radius,
        cellWidth: cell,
        nameWidth: cell * _nameShare,
        nameSize: name,
        nameHeight: line * lines,
        blockHeight: line * lines + line + hint + marks,
        nameLines: lines,
        hintSize: hasHint ? name * _hintShare : 0,
      );
    }

    double heightAt(double radius, int lines) =>
        radius * _gapPerRadius * 2 // the cell's own padding
        +
        radius * 2 // the face
        +
        radius * _gapPerRadius // face to name
        +
        at(radius, lines).blockHeight;

    bool fits(double radius, int lines) =>
        columns * radius * _cellPerRadius <= innerWidth &&
        rows * heightAt(radius, lines) <= innerHeight;

    // Down half a point at a time from the largest the card allows. Linear and
    // bounded, and it lands on the same answer every time — a picture that
    // solved its own layout by search would still have to be the same file
    // twice.
    //
    // The first radius that fits is not the answer if somebody's name would
    // have to be cut to reach it. A name is what a lineup is *for*, so the
    // search keeps going: a step smaller either buys the second line the long
    // name needs, or sets the type small enough that it no longer needs one.
    // The largest one-line answer is kept only as the floor case — a lineup so
    // dense that neither ever happens.
    TeamLineupMetrics? cut;
    for (var radius = _maxRadius; radius > _minRadius; radius -= 0.5) {
      if (!fits(radius, 1)) continue;
      final candidate = at(radius, 1);
      // Would any name have to be cut to be set on one line here? Asked at this
      // radius rather than at the largest, because it is this radius the names
      // will be drawn at.
      final needsTwo = _PlayerName.anyNeedsTwoLines(
        context,
        names,
        size: candidate.nameSize,
        maxWidth: candidate.nameWidth,
      );
      if (!needsTwo) return candidate;
      if (fits(radius, 2)) return at(radius, 2);
      cut ??= candidate;
    }

    return cut ?? at(_minRadius, 1);
  }
}

// --- one player ---------------------------------------------------------------

/// A player on the pitch: their face, their name and their rating.
///
/// `PlayerCard`, at the card's scale and without the parts of it that only a
/// screen has. What is kept is everything a reader sees: the white disc with the
/// face in it, the picture over the disc where there is one, the light-on-dark
/// name with its hard shadow, the rating to one decimal under the name, and the
/// tertiary disc and premium badge that mark a Professional Guest on every
/// roster in the app. What is dropped is the `InkWell` — a picture has nothing
/// to tap.
class TeamLineupPlayerMark extends StatelessWidget {
  const TeamLineupPlayerMark({
    super.key,
    required this.team,
    required this.name,
    required this.metrics,
    this.avatarUrl,
    this.rating,
    this.isProfessionalGuest = false,
    this.movedFrom,
    this.goals = 0,
    this.isMvp = false,
  });

  /// Which side this player is on. Nothing about the mark is drawn from it —
  /// the pitch they are on is what says whose they are, exactly as on the
  /// screen — but a picture of two teams should be able to say which of them it
  /// is drawing.
  final TeamId team;

  /// The name the screen resolved, drawn under the face.
  final String name;

  final String? avatarUrl;
  final double? rating;
  final bool isProfessionalGuest;

  /// Set where the drawing put a player in a line their position does not name.
  final Position? movedFrom;

  /// How many this player scored, and whether they were named best on the
  /// pitch.
  ///
  /// **Both are zero and false on a lineup card, which is why they have those
  /// defaults.** A lineup is drawn before the match; there is nothing to say
  /// about goals or a best player yet, and `TeamLineupCard` passes neither. The
  /// Completed Match card is the same picture taken afterwards, so it passes
  /// both and the mark grows the two small badges below.
  final int goals;
  final bool isMvp;

  /// The sizes the card solved once, for every player on it.
  final TeamLineupMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final rating = this.rating;
    final radius = metrics.radius;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: Gap.xs * metrics.scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Face(
            radius: radius,
            avatarUrl: avatarUrl,
            isProfessionalGuest: isProfessionalGuest,
          ),
          SizedBox(height: Gap.xs * metrics.scale),
          // The name, the rating and the hint are one block, given the room the
          // card reserved and filled from the top. A player whose name takes
          // one line where the card reserved two leaves the slack at the foot
          // of everything they carry, rather than between their own name and
          // their own rating.
          SizedBox(
            height: metrics.blockHeight,
            child: Column(
              children: [
                _PlayerName(
                  text: name,
                  maxWidth: metrics.nameWidth,
                  size: metrics.nameSize,
                  lines: metrics.nameLines,
                ),
                // What this player did, attached to the name rather than placed
                // near it: the two badges sit directly under the last line of
                // the name and share its centre, so a star and a tally read as
                // belonging to that player and not to the one beside them.
                //
                // Under rather than inline because a cell is as wide as the
                // densest row allows and a name is Arabic as often as Latin —
                // an inline star would take its room out of the name, and the
                // name is what identifies the player.
                if (isMvp || goals > 0)
                  _PlayerMarks(
                    goals: goals,
                    isMvp: isMvp,
                    size: metrics.nameSize,
                  ),
                if (rating != null)
                  Text(
                    // One decimal, which is `OP-1`'s presentation scale.
                    rating.toStringAsFixed(1),
                    // Western digits, as everywhere a rating is written in this
                    // product.
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: const Color(0xD9FFFFFF),
                      fontSize: metrics.nameSize,
                      height: 1.2,
                      shadows: const [
                        Shadow(blurRadius: 4, color: Color(0x99000000)),
                      ],
                    ),
                  ),
                // What this player's position actually is, when the drawing has
                // put them somewhere else. The mark carries no position
                // otherwise — the row it sits in is what says it — so without
                // this a forward moved down to keep the attack smaller than the
                // midfield would read as a midfielder and nothing in the
                // picture would disagree.
                if (movedFrom case final Position position)
                  if (metrics.hintSize > 0)
                    _MovedFromHint(position: position, metrics: metrics),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What a player did in the match, under their name: a star if they were best
/// on the pitch, a ball and a number if they scored.
///
/// **Small, and on their own ground.** Both badges sit on the same near-white
/// pill the pitch already uses for a moved-position hint, because a gold star
/// and a dark numeral both need something other than grass behind them to hold
/// their shape at this size. The pill is what makes them legible in a picture
/// that will be looked at on a phone, at a third of the size it was drawn.
///
/// **Both, cleanly, when both apply.** They are one row in one pill — a player
/// who was best on the pitch *and* scored twice reads as "⭐ ⚽2" rather than as
/// two competing marks. The row is pinned left to right so the ball never lands
/// on the far side of its own count.
class _PlayerMarks extends StatelessWidget {
  const _PlayerMarks({
    required this.goals,
    required this.isMvp,
    required this.size,
  });

  final int goals;
  final bool isMvp;

  /// The name's size, which everything here is a proportion of, so the badges
  /// stay in step with the type on a dense card and on a sparse one.
  final double size;

  /// The amber the app reserves for a figure worth noticing.
  static const _mvp = Color(0xFFC9A227);

  @override
  Widget build(BuildContext context) {
    final glyph = size * 1.15;

    return Container(
      margin: EdgeInsets.only(top: size * 0.22),
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.42,
        vertical: size * 0.1,
      ),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        // The star comes first and the tally second in both languages: this is
        // a run of marks, not a sentence, and a reader scanning a pitch should
        // find them in the same place on every player.
        textDirection: TextDirection.ltr,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMvp)
            Icon(Icons.star_rounded, size: glyph * 1.15, color: _mvp),
          if (isMvp && goals > 0) SizedBox(width: size * 0.3),
          if (goals > 0) ...[
            Icon(
              Icons.sports_soccer,
              size: glyph,
              color: TeamLineupCard._primary,
            ),
            SizedBox(width: size * 0.16),
            Text(
              '$goals',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: TeamLineupCard._primary,
                fontSize: size,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The player's face: a white disc with their picture on it, or with the app's
/// own figure where there is none.
///
/// `PlayerCard`'s `CircleAvatar`, drawn the same way and falling back the same
/// way. A Professional Guest keeps their own disc and their own badge — they
/// hold no account, so there is no picture of theirs to load and no chance of
/// loading somebody else's.
class _Face extends StatelessWidget {
  const _Face({
    required this.radius,
    required this.avatarUrl,
    required this.isProfessionalGuest,
  });

  final double radius;
  final String? avatarUrl;
  final bool isProfessionalGuest;

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final url = avatarUrl;
    final hasPicture = !isProfessionalGuest && url != null;

    final fallback = Center(
      child: Icon(
        isProfessionalGuest ? Icons.workspace_premium_outlined : Icons.person,
        size: radius,
        color: isProfessionalGuest
            ? TeamLineupCard._onGuest
            : TeamLineupCard._primary,
      ),
    );

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isProfessionalGuest ? TeamLineupCard._guest : Colors.white,
        // Not the screen's: a disc sitting on printed grass needs an edge that
        // a disc sitting under a phone's own elevation does not.
        boxShadow: [
          BoxShadow(
            color: const Color(0x59000000),
            blurRadius: radius * 0.3,
            offset: Offset(0, radius * 0.08),
          ),
        ],
      ),
      child: ClipOval(
        child: hasPicture
            ? Image.network(
                url,
                width: diameter,
                height: diameter,
                fit: BoxFit.cover,
                // A picture that will not load is not an error and not a hole:
                // it is the same player, drawn the way a player without one is
                // drawn. The screen swallows the failure too.
                errorBuilder: (_, __, ___) => fallback,
                frameBuilder: (_, child, frame, wasSynchronous) =>
                    frame == null && !wasSynchronous ? fallback : child,
              )
            : fallback,
      ),
    );
  }
}

/// The position a player actually holds, on a mark the drawing has moved.
///
/// `PitchView`'s own badge: a white pill, a caret in the brand's green, and the
/// position beside it. Kept as a pill rather than reduced to text, because the
/// screen's pill is what a reader of this product already recognises.
class _MovedFromHint extends StatelessWidget {
  const _MovedFromHint({required this.position, required this.metrics});

  final Position position;
  final TeamLineupMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = metrics.hintSize;

    return Container(
      margin: EdgeInsets.only(top: size * 0.2),
      padding: EdgeInsets.symmetric(horizontal: size * 0.55, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xEBFFFFFF),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.north,
            size: size,
            color: TeamLineupCard._primary,
          ),
          SizedBox(width: size * 0.2),
          Flexible(
            child: Text(
              positionLabelOf(l10n, position),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: TeamLineupCard._primary,
                fontSize: size,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A player's name, set as large as its own cell allows.
///
/// **One line at full size, then a smaller line, then two lines, then — and
/// only then — an ellipsis.** In that order, because that is the order a
/// typesetter would try. The screen stops at the first step and trims, which is
/// all it can do at 82 points wide; a picture has the room to do better, and
/// "عبدالرحمن بن سليمان الحارثي" over two lines is a player a reader can
/// identify where "عبدالرحمن بن سليمان الحـ…" is not.
///
/// **The room is fixed and the name sits at the top of it.** The card reserves
/// the same block on every mark, so whether this particular name takes one line
/// or two, a two-line name never pushes its own face out of line with the
/// players either side of it.
///
/// Set white with a hard shadow, which is the screen's own treatment for a name
/// on grass. Nothing is tracked or capitalised: a name here is Arabic as often
/// as it is Latin.
class _PlayerName extends StatelessWidget {
  const _PlayerName({
    required this.text,
    required this.maxWidth,
    required this.size,
    this.lines = 1,
  });

  final String text;
  final double maxWidth;
  final double size;

  /// How many lines this card reserved room for.
  final int lines;

  /// Below this a name stops being readable in a picture somebody will look at
  /// on a phone, so it ellipsizes instead of shrinking further.
  static const _floor = 17.0;

  /// How far a name may be shrunk before a second line is the better answer.
  /// Much past this and one name is visibly smaller than the ten around it,
  /// which reads as a mistake rather than as a fit.
  static const _comfort = 0.84;

  /// The name's own style at [at], merged onto whatever the card is set in, so
  /// that a measurement and the text it measures cannot disagree.
  ///
  /// `labelSmall` in white with a hard shadow — `PlayerCard`'s, so that a pale
  /// name stays readable over a pale mown stripe without the grass having to be
  /// darkened for everybody.
  static TextStyle styleAt(BuildContext context, double at) =>
      DefaultTextStyle.of(context).style.merge(
            TextStyle(
              color: Colors.white,
              fontSize: at,
              fontWeight: FontWeight.w700,
              height: 1.2,
              shadows: const [Shadow(blurRadius: 4, color: Color(0xBF000000))],
            ),
          );

  /// What one line of this style occupies, per point of type.
  ///
  /// Laid out at a reference size and divided back down, so the answer is the
  /// engine's own leading rather than the one the style asked for — and laid
  /// out with the card's own names, because the answer is not the same for
  /// every script. A line of Arabic set through a fallback face is taller than
  /// the 1.2 the style asks for, and a block reserved from the arithmetic is a
  /// block that overflows on the device where that face lives.
  static double measuredLineHeight(
    BuildContext context,
    Iterable<String> names,
  ) {
    const probe = 40.0;
    var tallest = _comfortLineHeight;
    for (final text in {'Ag', ...names}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: styleAt(context, probe)),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: TextScaler.noScaling,
      )..layout();
      tallest = math.max(tallest, painter.height / probe);
    }
    return tallest;
  }

  /// Never less than the leading the style asks for: a measurement that came
  /// back short would reserve less room than the text takes.
  static const _comfortLineHeight = 1.2;

  /// Whether [text] fits [maxLines] lines of [maxWidth] at [at].
  static bool _fits(
    BuildContext context,
    String text,
    double at,
    double maxWidth,
    int maxLines,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: styleAt(context, at)),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: maxWidth);
    return !painter.didExceedMaxLines && painter.width <= maxWidth;
  }

  /// Whether any of these names would have to be cut, or shrunk past comfort,
  /// to be set on one line of [maxWidth] at [size].
  ///
  /// The question the card asks once, before it decides whether to buy a second
  /// line for every mark on it.
  static bool anyNeedsTwoLines(
    BuildContext context,
    Iterable<String> names, {
    required double size,
    required double maxWidth,
  }) {
    final comfort = math.max(_floor, size * _comfort);
    for (final name in names) {
      if (!_fits(context, name, comfort, maxWidth, 1)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    var chosen = size;
    var used = 1;

    if (!_fits(context, text, size, maxWidth, 1)) {
      // Smaller, a point at a time, while one line still reads as one of the
      // card's names rather than as a footnote.
      final comfort = math.max(_floor, size * _comfort);
      var settled = false;
      for (var at = size - 1; at >= comfort; at -= 1) {
        if (_fits(context, text, at, maxWidth, 1)) {
          chosen = at;
          settled = true;
          break;
        }
      }

      if (!settled && lines >= 2) {
        // Two lines, as large as two lines can be set here.
        for (var at = size; at >= _floor; at -= 1) {
          if (_fits(context, text, at, maxWidth, 2)) {
            chosen = at;
            used = 2;
            settled = true;
            break;
          }
        }
      }

      // Nothing fits: the floor, the reserved lines, and an ellipsis.
      if (!settled) {
        chosen = math.min(size, comfort);
        used = lines;
      }
    }

    return SizedBox(
      width: maxWidth,
      child: Text(
        text,
        maxLines: used,
        softWrap: used > 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: styleAt(context, chosen),
      ),
    );
  }
}

// --- the grass ----------------------------------------------------------------

/// The pitch under the players: mown stripes, a touchline, a halfway line with
/// its centre circle, and a penalty area at each end.
///
/// `PitchView`'s painter, and deliberately nothing more. The proportions — six
/// bands, a centre circle at 0.13 of the width, a box 0.44 wide and 0.16 deep —
/// are copied unchanged, because they are what a reader of this app already
/// recognises as its pitch. The absolute ones are the phone's, so [scale] turns
/// a 10-point inset and a 2-point line into the same inset and the same line at
/// the size the card is drawn.
///
/// The markings are faint on purpose: they are there to say "this is a pitch",
/// and anything stronger competes with the names sitting on top of them.
///
/// **Public because two cards are drawn on this grass.** The Completed Match
/// card is the Teams screen after the result is in, so it stands on the same
/// pitch as the lineup card rather than on a second one that would drift from
/// it. Painting is all it does — it knows nothing about either card.
class TeamLineupPitchPainter extends CustomPainter {
  const TeamLineupPitchPainter({required this.scale});

  final double scale;

  /// The Teams screen's own three colours, unchanged.
  static const _grass = Color(0xFF2E7D4F);
  static const _stripe = Color(0xFF35895A);
  static const _lines = Color(0x47FFFFFF); // white at 0.28

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = _grass);

    // Mown bands across the pitch. Six is enough to read as stripes at any
    // height this view is given.
    const bands = 6;
    final bandHeight = size.height / bands;
    final stripePaint = Paint()..color = _stripe;
    for (var i = 0; i < bands; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * bandHeight, size.width, bandHeight),
        stripePaint,
      );
    }

    final line = Paint()
      ..color = _lines
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale;

    final inset = rect.deflate(10 * scale);
    canvas.drawRect(inset, line);

    // Halfway line and centre circle.
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(inset.left, middle),
      Offset(inset.right, middle),
      line,
    );
    canvas.drawCircle(Offset(size.width / 2, middle), size.width * 0.13, line);

    // A penalty area at each end, scaled to the pitch so it holds its
    // proportions whatever height the team needs.
    final boxWidth = inset.width * 0.44;
    final boxHeight =
        (inset.height * 0.16).clamp(18.0 * scale, 64.0 * scale);
    final boxLeft = inset.left + (inset.width - boxWidth) / 2;
    canvas.drawRect(
      Rect.fromLTWH(boxLeft, inset.top, boxWidth, boxHeight),
      line,
    );
    canvas.drawRect(
      Rect.fromLTWH(boxLeft, inset.bottom - boxHeight, boxWidth, boxHeight),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant TeamLineupPitchPainter oldDelegate) =>
      oldDelegate.scale != scale;
}
