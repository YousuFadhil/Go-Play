import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../profile/current_user.dart';
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

/// The Team Lineup share card: a football poster with a real pitch inside it.
///
/// **Editorial first, tactical second — and both, not one of them.** The card
/// before this one drew a correct tactical board and nothing else, and a
/// correct tactical board still reads as a piece of an application. What a
/// football graphic has that a board does not is a *composition*: a masthead, a
/// subject set at poster scale, one quiet line of context, a dominant image and
/// a signature at the foot. The lineup is the image. Everything here is that
/// arrangement.
///
/// **A cinematic ground rather than a panel.** The card is painted before
/// anything is laid on it — a near-black base, a low emerald pool where the
/// pitch sits, one soft light from above, a vignette and a fine grain. It is
/// deliberately not a flat colour: a flat colour is what makes an image look
/// like a screen rather than a print, and the grain is what stops a phone's
/// gradient from banding once a messaging app has re-compressed it.
///
/// **The pitch has no frame.** Its markings are drawn straight onto the ground
/// and fade towards the two goal ends, so the eye reads a pitch receding into
/// the composition instead of a bordered widget sitting on top of it. The
/// geometry is a real pitch's, in a real pitch's proportions; the fade is the
/// only liberty taken with it.
///
/// **The two sides are told apart by colour, not by a caption.** Team A is the
/// brand's green and Team B is ice, on the ring around every player, on their
/// rating and on the label naming their half. One glance answers "who is on
/// which side", which is a question a lineup graphic exists to answer.
///
/// **The community is the subject and Go Play is the signature.** The largest
/// text on the card names whose teams these are; the product signs the bottom
/// edge at a quarter of that size. The fixture, where it exists, is one line
/// between them, set as a ledger of day, clock and place rather than as a row
/// out of a database.
///
/// **Composed at card scale.** The card is built in the engine's own 1080×1920
/// units, so a 5px line is 5px in the file that leaves the phone — thick enough
/// to survive what a messaging app does to a picture. Nothing measures the
/// device it was composed on.
///
/// **The formation is the app's, the presentation is the card's.**
/// [buildFormation] decides the rows, the wrapping and who is drawn out of
/// their line — none of that is restated here. What the card does not reuse is
/// `PlayerCard` or `PlayerAvatar`: both belong to the Teams screen, are built
/// for a phone and carry Material's own look, which is the exact look a shared
/// picture must not have. The card composes its own player mark from the same
/// formation data rather than changing a shared widget.
///
/// **Presentation only.** It takes [TeamLineupCardData] and draws it: no
/// repository, no formation decision of its own, no statistic invented.
class TeamLineupCard extends StatelessWidget {
  const TeamLineupCard({super.key, required this.data});

  final TeamLineupCardData data;

  // --- the palette ------------------------------------------------------------

  /// Reserved for Team A, the rating it carries and the brand's own mark.
  static const _accent = Color(0xFF3DDC84);

  /// Team B. Not a second hue competing with the brand — the same graphic
  /// language in a cold neutral, so the two sides separate without the card
  /// gaining a colour it does not own.
  static const _ice = Color(0xFFDDE9F1);

  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0xC2FFFFFF);
  static const _inkFaint = Color(0x8AFFFFFF);

  /// The safe margin the type is set against. Everything the reader must
  /// *read* lives inside it.
  static const _margin = 72.0;

  /// The pitch is allowed outside it, and deliberately. Held to the text
  /// column, the pitch's touchlines line up with the type and the whole thing
  /// reads as a panel inside a card; taken almost to the edge of the frame, it
  /// reads as the picture the card is *of*.
  static const _bleed = 24.0;

  static const _page = EdgeInsets.symmetric(horizontal: _margin);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fixture = _fixture(context);
    final place = _place();
    final format = _format();

    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: CustomPaint(painter: _AtmospherePainter()),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 62, bottom: 54),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: _page,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Masthead(),
                    const SizedBox(height: 32),
                    if (data.communityName case final String name) ...[
                      _Subject(name: name),
                      const SizedBox(height: 18),
                    ],
                    if (fixture.isNotEmpty || place != null || format != null)
                      _ContextLine(
                        parts: fixture,
                        place: place,
                        format: format,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _bleed),
                  child: _PitchStage(data: data),
                ),
              ),
              const SizedBox(height: 24),
              Padding(padding: _page, child: _Signature(label: l10n.appName)),
            ],
          ),
        ),
      ],
    );
  }

  /// When the match is, in the app's own wording.
  ///
  /// The day and the clock, each formatted by the helper the rest of the
  /// product uses, so a lineup card and a match card cannot describe the same
  /// fixture two different ways. Returned as parts rather than as one joined
  /// string because the header punctuates them itself.
  List<String> _fixture(BuildContext context) => [
        if (data.startAt case final DateTime start)
          formatMatchDay(context, start),
        if (data.startAt case final DateTime start)
          if (data.endAt case final DateTime end)
            formatTimeRange(context, start, end)
          else
            formatTime(context, start),
      ];

  /// Where it is — set on its own line under the day.
  ///
  /// Underneath rather than alongside, because a venue's full name is longer
  /// than a date and a clock put together, and crowded onto one line it takes
  /// the date's room with it: the header's first line is the one piece of
  /// context a reader always wants, and it is not allowed to be trimmed to make
  /// space for the second.
  String? _place() {
    final place = data.location?.trim();
    return (place == null || place.isEmpty) ? null : place;
  }

  /// "5 v 5" — the shape of the match, read off the lineup being drawn.
  ///
  /// Counted from what the card actually puts on the pitch rather than from the
  /// stored lineup, because a squad with nobody in goal has its keepers left
  /// out (§10.1) and a tag disagreeing with the picture beneath it is worse
  /// than no tag. Null where a side is empty: there is no format to name.
  String? _format() {
    int drawn(TeamId team) => data
        .of(team)
        .where((a) =>
            data.hasNaturalGoalkeeper || a.assignedPosition != Position.gk)
        .length;

    final a = drawn(TeamId.a);
    final b = drawn(TeamId.b);
    if (a == 0 || b == 0) return null;
    return '$a v $b';
  }
}

/// The rule across the top of the card.
///
/// An editorial masthead and nothing more: a hairline the width of the page
/// with its first stretch in the brand's colour. It is what tells the eye the
/// picture has a top edge, which is the job a heading would otherwise be given
/// — and a heading above the community's name is exactly what this card must
/// not have.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 132, height: 6, color: TeamLineupCard._accent),
        Expanded(
          child: Container(
            height: 6,
            color: TeamLineupCard._ink.withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}

/// Whose teams these are. The largest thing on the card.
class _Subject extends StatelessWidget {
  const _Subject({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    // Wrapped at the page width first and scaled down second: a long community
    // name becomes two lines of poster type rather than one line of small type.
    // No letter-spacing — the name may be Arabic, where tracking breaks the
    // cursive joins.
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 1080 - TeamLineupCard._margin * 2,
            ),
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: TeamLineupCard._ink,
                fontSize: 104,
                fontWeight: FontWeight.w800,
                height: 1.02,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The fixture, as a dateline under the subject.
///
/// The day and the clock on one line, punctuated by a small accent diamond,
/// with the shape of the match set at the far end of it; the venue on a second
/// line, quieter. Everything on it is optional and nothing is stood in for —
/// the block simply carries fewer lines.
class _ContextLine extends StatelessWidget {
  const _ContextLine({
    required this.parts,
    required this.place,
    required this.format,
  });

  final List<String> parts;
  final String? place;
  final String? format;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final (index, part) in parts.indexed) ...[
                    if (index > 0) const _Diamond(),
                    Flexible(
                      child: Text(
                        part,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TeamLineupCard._inkMuted,
                          fontSize: 32,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (format case final String tag) ...[
              const SizedBox(width: 20),
              Text(
                tag,
                // A count against a count: it runs the same way in both
                // languages.
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: TeamLineupCard._accent,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ],
          ],
        ),
        if (place case final String place) ...[
          const SizedBox(height: 6),
          Text(
            place,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: TeamLineupCard._inkFaint,
              fontSize: 29,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }
}

/// The punctuation between two pieces of context.
class _Diamond extends StatelessWidget {
  const _Diamond();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: 9,
          height: 9,
          color: TeamLineupCard._accent.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// The product's signature: a hairline, then the name, once, at the foot.
class _Signature extends StatelessWidget {
  const _Signature({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          height: 2,
          child: CustomPaint(painter: _HairlinePainter()),
        ),
        const SizedBox(height: 20),
        // The mark and the tick beside it are one thing and it reads left to
        // right, so the row is pinned rather than inherited: an Arabic card
        // would otherwise put the tick after the name.
        Row(
          textDirection: TextDirection.ltr,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: TeamLineupCard._accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              label.toUpperCase(),
              // A name, not a sentence: it reads left to right in both
              // languages, and Latin capitals are the one place tracking is
              // safe.
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: TeamLineupCard._inkFaint,
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: 7,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A rule that fades out at both ends, so the foot of the card closes without
/// a line that stops dead.
class _HairlinePainter extends CustomPainter {
  const _HairlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          [
            const Color(0x00FFFFFF),
            const Color(0x24FFFFFF),
            const Color(0x24FFFFFF),
            const Color(0x00FFFFFF),
          ],
          const [0.0, 0.22, 0.78, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _HairlinePainter oldDelegate) => false;
}

// --- the pitch ----------------------------------------------------------------

/// The room the pitch is given, and the pitch built to fill it.
///
/// The proportions are held and the size is not: the stage takes the height the
/// composition leaves it — a community with a two-line name leaves less — and
/// derives the width from that. Everything drawn inside is measured from the
/// resolved size rather than from a constant, so the pitch is never a fixed
/// drawing squeezed into a variable box.
class _PitchStage extends StatelessWidget {
  const _PitchStage({required this.data});

  final TeamLineupCardData data;

  /// Width over height — a 68 by 92 metre pitch, which is inside the laws' own
  /// range and is the widest the composition will take.
  ///
  /// The height of the frame is what limits this pitch, not its width: a
  /// narrower pitch would leave a gutter down both sides of the card and put
  /// the touchlines back where the type is, which is precisely what makes a
  /// pitch read as a panel. At this proportion it reaches the edges of the
  /// picture and stops being a panel at all.
  static const _ratio = 0.74;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(constraints.maxHeight, constraints.maxWidth / _ratio);
        final width = height * _ratio;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: _Pitch(data: data, size: Size(width, height)),
          ),
        );
      },
    );
  }
}

/// One pitch, both teams, facing each other across the halfway line.
class _Pitch extends StatelessWidget {
  const _Pitch({required this.data, required this.size});

  final TeamLineupCardData data;
  final Size size;

  /// Room between the touchline and the outermost player, so nobody is drawn
  /// standing on a marking.
  static const _insetX = 26.0;
  static const _insetY = 46.0;

  /// The halfway line's own room. Without it the two attacks meet exactly on
  /// the line — no overlap, but no air either, and the one place on the card
  /// where the two teams touch is the place that most needs to be legible.
  static const _midGutter = 16.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final a = _Half.of(data, TeamId.a, towardsTop: true);
    final b = _Half.of(data, TeamId.b, towardsTop: false);

    final rows = math.max(1, math.max(a.rows.length, b.rows.length));
    final columns = math.max(
      1,
      [...a.rows, ...b.rows].fold(1, (m, row) => math.max(m, row.length)),
    );

    final metrics = _MarkMetrics.resolve(
      cellWidth: (size.width - _insetX * 2) / columns,
      rowHeight: (size.height - _insetY * 2 - _midGutter * 2) / 2 / rows,
      hasHint: a.hasHint || b.hasHint,
    );

    return CustomPaint(
      painter: const _PitchPainter(),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _insetX,
              vertical: _insetY,
            ),
            child: Column(
              children: [
                // Team A defends the top goal, so its rows run the other way:
                // the goal first and the attack last, meeting Team B's attack
                // at the halfway line.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _midGutter),
                    child: a.build(data, metrics, TeamLineupCard._accent),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: _midGutter),
                    child: b.build(data, metrics, TeamLineupCard._ice),
                  ),
                ),
              ],
            ),
          ),
          // On the grass and clear of it: inside the touchline, outside the
          // penalty areas — which occupy the middle 59% of each end — and above
          // the goal rows, which are centred.
          PositionedDirectional(
            start: 40,
            top: 24,
            child: _TeamLabel(
              label: l10n.teamAName,
              tint: TeamLineupCard._accent,
            ),
          ),
          PositionedDirectional(
            start: 40,
            bottom: 24,
            child: _TeamLabel(
              label: l10n.teamBName,
              tint: TeamLineupCard._ice,
            ),
          ),
        ],
      ),
    );
  }
}

/// One team's half of the pitch, already arranged into rows.
///
/// [towardsTop] is which goal the team defends. It reverses the row order and
/// nothing else: the formation itself — who is in attack, how the midfield
/// wraps, who is drawn out of their line — is [buildFormation]'s and is not
/// touched.
class _Half {
  const _Half({required this.rows, required this.movedFrom});

  final List<List<TeamAssignment>> rows;
  final Map<String, Position> movedFrom;

  bool get hasHint => movedFrom.isNotEmpty;

  static _Half of(
    TeamLineupCardData data,
    TeamId team, {
    required bool towardsTop,
  }) {
    final formation = buildFormation(
      data.of(team),
      // A stable order, so a row does not reshuffle between builds.
      order: (a, b) => (data.names[a.participantId] ?? '')
          .compareTo(data.names[b.participantId] ?? ''),
    );

    // `buildFormation` returns rows top-down for a team attacking upwards:
    // attack, midfield, defence, goal.
    final lines = <List<TeamAssignment>>[
      if (formation.attack.isNotEmpty) formation.attack,
      ...formation.midfieldRows,
      if (formation.defence.isNotEmpty) formation.defence,
      if (data.hasNaturalGoalkeeper && formation.goalkeepers.isNotEmpty)
        formation.goalkeepers,
    ];

    return _Half(
      rows: towardsTop ? lines.reversed.toList() : lines,
      movedFrom: formation.movedFrom,
    );
  }

  Widget build(TeamLineupCardData data, _MarkMetrics metrics, Color tint) {
    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: _PitchRow(
              row: row,
              data: data,
              metrics: metrics,
              movedFrom: movedFrom,
              tint: tint,
            ),
          ),
      ],
    );
  }
}

/// One line of the pitch. The players spread evenly across it, so the shape of
/// the row is the shape of the line.
class _PitchRow extends StatelessWidget {
  const _PitchRow({
    required this.row,
    required this.data,
    required this.metrics,
    required this.movedFrom,
    required this.tint,
  });

  final List<TeamAssignment> row;
  final TeamLineupCardData data;
  final _MarkMetrics metrics;
  final Map<String, Position> movedFrom;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final assignment in row)
          SizedBox(
            width: metrics.cellWidth,
            child: Center(
              child: TeamLineupPlayerMark(
                // Resolved by the screen. A dash for somebody neither the
                // profiles nor the roster knows.
                name: data.names[assignment.participantId] ?? '—',
                radius: metrics.radius,
                nameSize: metrics.nameSize,
                nameWidth: metrics.nameWidth,
                ratingSize: metrics.ratingSize,
                hintSize: metrics.hintSize,
                // The initials come from the **profile**, never from the
                // resolved name: somebody who left the match after the lineup
                // was stored has no profile and a dash for a name, and
                // lettering a disc with a dash is not initials.
                fullName: data.players[assignment.participantId]?.fullName,
                avatarUrl: data.players[assignment.participantId]?.avatarUrl,
                rating: data.players[assignment.participantId]?.overallRating,
                isProfessionalGuest: assignment.isProfessionalGuest,
                movedFrom: movedFrom[assignment.participantId],
                tint: tint,
              ),
            ),
          ),
      ],
    );
  }
}

/// How large a player is drawn, decided once for the whole card.
///
/// **One size for everybody, chosen by the densest row.** A per-player
/// `scaleDown` — what the card did before — gives a five-a-side keeper a
/// different size from the defender beside them, and a graphic whose elements
/// are almost the same size is a graphic that looks accidental. So the size is
/// solved once against the tightest cell either team produces, and every mark
/// on the card is that size.
///
/// **Five-a-side and eleven-a-side are not the same drawing.** Nothing here is
/// a scale factor applied to a fixed design: fewer rows and shorter rows leave
/// a larger cell, which resolves to a larger face, a larger name and a larger
/// rating. A crowded lineup resolves the other way and stays inside its row.
@immutable
class _MarkMetrics {
  const _MarkMetrics({
    required this.radius,
    required this.nameSize,
    required this.ratingSize,
    required this.hintSize,
    required this.cellWidth,
  });

  final double radius;
  final double nameSize;
  final double ratingSize;
  final double hintSize;
  final double cellWidth;

  /// A face this large stops reading as a photograph on a poster.
  static const _maxRadius = 58.0;

  /// And below this it stops reading as a face at all. A lineup denser than the
  /// engine can produce is drawn at this size and allowed to be tight rather
  /// than shrunk into illegibility.
  static const _minRadius = 22.0;

  /// The badge sits over the foot of the circle and hangs below it by half its
  /// own height.
  double get badgeHeight => ratingSize * 1.72;
  double get badgeOverhang => badgeHeight * 0.5;

  /// The room a name is given: its own cell, less a gutter wide enough to read
  /// as a gap. Two long names in neighbouring cells both trim to their own
  /// share and the space between them is what tells the reader they are two
  /// names rather than one long one.
  double get nameWidth => cellWidth - 34;

  /// The whole mark, top of the photograph to the foot of the last line.
  double get height =>
      radius * 2 + badgeOverhang + 8 + nameSize * 1.2 + hintSize * 1.5;

  factory _MarkMetrics.resolve({
    required double cellWidth,
    required double rowHeight,
    required bool hasHint,
  }) {
    // Largest first, and the first size that fits both ways wins. A whole
    // pixel at a time: the answer feeds a photograph's diameter, and a
    // fractional radius buys nothing a reader can see.
    for (var radius = _maxRadius; radius > _minRadius; radius -= 1) {
      final candidate = _at(radius, cellWidth, hasHint);
      if (candidate.height <= rowHeight && radius * 2 + 12 <= cellWidth) {
        return candidate;
      }
    }
    return _at(_minRadius, cellWidth, hasHint);
  }

  static _MarkMetrics _at(double radius, double cellWidth, bool hasHint) {
    return _MarkMetrics(
      radius: radius,
      nameSize: (radius * 0.60).clamp(19.0, 34.0).toDouble(),
      ratingSize: (radius * 0.46).clamp(16.0, 26.0).toDouble(),
      hintSize: hasHint ? (radius * 0.38).clamp(13.0, 20.0).toDouble() : 0.0,
      cellWidth: cellWidth,
    );
  }
}

/// One player on the pitch: their face, their name and what they are rated.
///
/// **A graphic element, not a list row.** The card's own mark rather than
/// `PlayerCard` or `PlayerAvatar`: those are the Teams screen's, are built for
/// a phone and carry Material's colours, which is the look a shared picture
/// must not have. What is here instead is a photograph ringed in its team's
/// colour, lifted off the grass by a shadow, with the rating set into a solid
/// badge across the foot of the circle — the way a football graphic has always
/// written a number on a player.
///
/// **The rating stays.** It is the one figure this product has that a lineup
/// graphic can carry, and it is drawn as a badge rather than as a line of text
/// so that it reads as part of the player instead of as metadata under them.
///
/// **A player without a photograph is not a lesser player.** The same ring, the
/// same shadow, the same badge; their initials in their team's colour where
/// their profile gives initials, and the game's own mark where it does not. A
/// dash is never lettered into a disc: somebody who left the match after the
/// lineup was stored has no profile to take initials from.
class TeamLineupPlayerMark extends StatelessWidget {
  const TeamLineupPlayerMark({
    super.key,
    required this.name,
    required this.tint,
    required this.radius,
    required this.nameSize,
    required this.nameWidth,
    required this.ratingSize,
    required this.hintSize,
    this.fullName,
    this.avatarUrl,
    this.rating,
    this.isProfessionalGuest = false,
    this.movedFrom,
  });

  /// The name the screen resolved, drawn under the face.
  final String name;

  /// The name on the **profile**, and the only source of initials. Null for
  /// somebody with no profile, and never read for a Professional Guest.
  final String? fullName;

  final String? avatarUrl;
  final double? rating;
  final bool isProfessionalGuest;

  /// Set where the drawing put a player in a line their position does not name.
  final Position? movedFrom;

  /// Their team's colour.
  final Color tint;

  /// The measurements the card solved for this lineup — the same for every
  /// player on it, so no two marks are drawn at different sizes.
  final double radius;
  final double nameSize;
  final double nameWidth;
  final double ratingSize;

  /// Zero where no player on this card was moved out of their line, which is
  /// what keeps a row from reserving space for a hint nobody needs.
  final double hintSize;

  @override
  Widget build(BuildContext context) {
    final rating = this.rating;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: radius * 2 + 16,
          height: radius * 2 + ratingSize * 0.86,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              _Face(
                radius: radius,
                tint: tint,
                avatarUrl: avatarUrl,
                fullName: fullName,
                isProfessionalGuest: isProfessionalGuest,
              ),
              if (rating != null)
                Positioned(
                  bottom: 0,
                  child: _RatingBadge(
                    rating: rating,
                    tint: tint,
                    size: ratingSize,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _PlayerName(text: name, maxWidth: nameWidth, size: nameSize),
        if (movedFrom case final Position position)
          if (hintSize > 0)
            _MovedFromHint(position: position, tint: tint, size: hintSize),
      ],
    );
  }
}

/// The photograph, ringed and lifted off the grass.
class _Face extends StatelessWidget {
  const _Face({
    required this.radius,
    required this.tint,
    required this.avatarUrl,
    required this.fullName,
    required this.isProfessionalGuest,
  });

  final double radius;
  final Color tint;
  final String? avatarUrl;
  final String? fullName;
  final bool isProfessionalGuest;

  /// What sits behind a photograph that has not loaded, and under one that has.
  static const _base = Color(0xFF0D1614);

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _base,
        border: Border.all(
          color: tint.withValues(alpha: 0.88),
          width: (radius * 0.075).clamp(2.5, 4.5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xB3000000),
            blurRadius: radius * 0.55,
            offset: Offset(0, radius * 0.16),
          ),
        ],
      ),
      child: ClipOval(child: _content(diameter)),
    );
  }

  Widget _content(double diameter) {
    final fallback = _Fallback(
      radius: radius,
      tint: tint,
      initials: isProfessionalGuest ? null : _initials(),
      isProfessionalGuest: isProfessionalGuest,
    );

    final url = avatarUrl;
    if (isProfessionalGuest || url == null) return fallback;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          // A picture that will not load is not an error and not a hole: it is
          // the same player, drawn the way a player without one is drawn.
          errorBuilder: (_, __, ___) => fallback,
          frameBuilder: (_, child, frame, wasSynchronous) =>
              frame == null && !wasSynchronous ? fallback : child,
        ),
        // A scrim across the foot, so the badge that crosses it keeps its edge
        // whatever the photograph happens to be.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x8C000000), Color(0x00000000)],
                stops: [0.0, 0.45],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Initials, or nothing.
  ///
  /// [initialsOf] is the product's rule — first word and last — and is reused
  /// rather than restated. What is added here is the refusal: a "name" holding
  /// no letter and no digit yields no initials, which is what stops a player
  /// the screen could only call "—" from being lettered with a dash.
  String? _initials() {
    final name = fullName;
    if (name == null) return null;
    final initials = initialsOf(name);
    final hasLetter = RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(initials);
    return hasLetter ? initials : null;
  }
}

/// What fills a face with no photograph behind it.
class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.radius,
    required this.tint,
    required this.initials,
    required this.isProfessionalGuest,
  });

  final double radius;
  final Color tint;
  final String? initials;
  final bool isProfessionalGuest;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint.withValues(alpha: 0.20),
            tint.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Center(
        child: switch ((isProfessionalGuest, initials)) {
          // A guest is marked as a guest, never lettered: they have no account
          // and no name of their own on this card.
          (true, _) => Icon(
              Icons.workspace_premium_outlined,
              size: radius * 0.95,
              color: tint.withValues(alpha: 0.92),
            ),
          (false, final String initials) => Text(
              initials,
              maxLines: 1,
              // No tracking: these initials are Arabic as often as not.
              style: TextStyle(
                color: tint,
                fontSize: radius * 0.74,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          // No profile, so no initials — the game's own mark rather than a
          // figure borrowed from an address book.
          (false, null) => Icon(
              Icons.sports_soccer,
              size: radius * 0.85,
              color: tint.withValues(alpha: 0.55),
            ),
        },
      ),
    );
  }
}

/// The rating, as a solid badge across the foot of the photograph.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({
    required this.rating,
    required this.tint,
    required this.size,
  });

  final double rating;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.44, vertical: size * 0.36),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Text(
        rating.toStringAsFixed(1),
        // Western digits, as everywhere a rating is written in this product.
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: const Color(0xFF04140C),
          fontSize: size,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

/// The position a player actually holds, on a mark the drawing has moved.
///
/// The same statement `PitchView` makes on the phone, at the card's scale and
/// without its container: a caret and a word, because a pill around two small
/// words is the kind of chrome that makes a picture look like an interface.
class _MovedFromHint extends StatelessWidget {
  const _MovedFromHint({
    required this.position,
    required this.tint,
    required this.size,
  });

  final Position position;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.arrow_upward_rounded,
          size: size * 1.05,
          color: tint.withValues(alpha: 0.9),
        ),
        SizedBox(width: size * 0.2),
        Flexible(
          child: Text(
            positionLabelOf(l10n, position),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: TeamLineupCard._inkMuted,
              fontSize: size,
              fontWeight: FontWeight.w600,
              height: 1.1,
              shadows: const [
                Shadow(blurRadius: 6, color: Color(0xCC000000)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A player's name, set as large as its own cell allows.
///
/// **Space first, size second, ellipsis last.** The name is measured at the
/// size the composition chose and, where it does not fit its cell, is stepped
/// down a point at a time to a floor. Only a name that will not fit even at the
/// floor is trimmed — and it is trimmed rather than allowed to run into the
/// player beside it. Nothing is tracked out or capitalised, because a name here
/// is Arabic as often as it is Latin.
class _PlayerName extends StatelessWidget {
  const _PlayerName({
    required this.text,
    required this.maxWidth,
    required this.size,
  });

  final String text;
  final double maxWidth;
  final double size;

  /// Below this a name stops being readable in a picture somebody will look at
  /// on a phone, so it ellipsizes instead of shrinking further.
  static const _floor = 18.0;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;

    TextStyle styled(double at) => base.merge(
          TextStyle(
            color: TeamLineupCard._ink,
            fontSize: at,
            fontWeight: FontWeight.w700,
            height: 1.2,
            shadows: const [Shadow(blurRadius: 8, color: Color(0xCC000000))],
          ),
        );

    var chosen = math.max(_floor, size);
    for (var at = size; at >= _floor; at -= 1) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: styled(at)),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: TextScaler.noScaling,
      )..layout();
      chosen = at;
      if (painter.width <= maxWidth) break;
    }

    return SizedBox(
      width: maxWidth,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: styled(chosen),
      ),
    );
  }
}

/// Which side a half belongs to, written in the corner of the grass.
class _TeamLabel extends StatelessWidget {
  const _TeamLabel({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 30, color: tint),
        const SizedBox(width: 12),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: TeamLineupCard._ink.withValues(alpha: 0.92),
            fontSize: 31,
            fontWeight: FontWeight.w800,
            height: 1.1,
            // No tracking: `teamAName` is "الفريق أ" in Arabic.
            shadows: const [Shadow(blurRadius: 8, color: Color(0xCC000000))],
          ),
        ),
      ],
    );
  }
}

/// The ground the whole card is printed on.
///
/// Four things, in order: a near-black base that is warmer at the top than at
/// the foot; a light from above the frame; a pool of emerald under the pitch;
/// and a vignette drawing the corners down. Then a fine grain over all of it —
/// which is what keeps a gradient this large from banding once a messaging app
/// has re-compressed the picture, and what stops the ground reading as a flat
/// fill. The grain is seeded, so the same lineup makes the same file twice.
class _AtmospherePainter extends CustomPainter {
  const _AtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [Color(0xFF0C1215), Color(0xFF070B0E), Color(0xFF04070A)],
          const [0.0, 0.52, 1.0],
        ),
    );

    // The light: above the frame and slightly cool, the way a floodlight falls.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.5, -size.height * 0.06),
          size.height * 0.52,
          const [Color(0x2A9FE9C6), Color(0x00000000)],
        ),
    );

    // The pitch's own atmosphere, pooled low.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.5, size.height * 0.72),
          size.height * 0.55,
          const [Color(0x3312B36E), Color(0x00000000)],
        ),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          size.height * 0.62,
          const [Color(0x00000000), Color(0x00000000), Color(0x99000000)],
          const [0.0, 0.55, 1.0],
        ),
    );

    final grain = math.Random(20260816);
    final paint = Paint();
    for (var i = 0; i < 2200; i++) {
      paint.color = Color.fromRGBO(
        255,
        255,
        255,
        0.008 + grain.nextDouble() * 0.022,
      );
      canvas.drawCircle(
        Offset(
          grain.nextDouble() * size.width,
          grain.nextDouble() * size.height,
        ),
        1.2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) => false;
}

/// The pitch itself, drawn onto the ground rather than into a frame.
///
/// Real markings in real proportions, taken from a 68 × 105 metre pitch: the
/// penalty area is 40.3 × 16.5, the goal area 18.3 × 5.5, the centre circle
/// 9.15 in radius and the penalty spot 11 from the goal line. Getting these
/// right is most of what separates a football graphic from a rectangle with a
/// circle in it.
///
/// **No box and no fill.** The line work fades towards both goal ends, so the
/// pitch dissolves into the composition instead of ending at a border, and the
/// only fill is a breath of emerald with no edge to it. Strokes are 4–6px in
/// the engine's own units, which is what survives a messaging app's
/// re-compression; a hairline would not.
class _PitchPainter extends CustomPainter {
  const _PitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final field = (Offset.zero & size).deflate(3);
    final w = field.width;
    final h = field.height;

    // The grass: a radial breath, so it has no edge of its own. Strong enough
    // that the pitch is a lit field rather than a rectangle drawn on the dark,
    // which is most of what stops it reading as a container.
    canvas.drawRect(
      field,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(field.center.dx, field.center.dy),
          h * 0.66,
          const [Color(0x3D18C77A), Color(0x1A18C77A), Color(0x00000000)],
          const [0.0, 0.58, 1.0],
        ),
    );

    /// White, at [alpha] through the middle of the pitch and weaker towards
    /// both goals. The fade is what removes the frame: the four corners of the
    /// touchline arrive at the edge of the card already half gone.
    Shader fade(double alpha) => ui.Gradient.linear(
          Offset(0, field.top),
          Offset(0, field.bottom),
          [
            Colors.white.withValues(alpha: alpha * 0.18),
            Colors.white.withValues(alpha: alpha * 0.80),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: alpha * 0.80),
            Colors.white.withValues(alpha: alpha * 0.18),
          ],
          const [0.0, 0.20, 0.5, 0.80, 1.0],
        );

    /// The same thing across the pitch, for the two lines that run that way.
    Shader across(double alpha) => ui.Gradient.linear(
          Offset(field.left, 0),
          Offset(field.right, 0),
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ],
          const [0.0, 0.22, 0.78, 1.0],
        );

    final touchline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..shader = fade(0.42);

    final goalLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..shader = across(0.42);

    final marking = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..shader = fade(0.32);

    final dot = Paint()..shader = fade(0.32);

    // Four lines rather than a rectangle, each fading out towards its own two
    // ends. A rectangle closes, and anything that closes around a picture is a
    // border; four lines that dissolve before they meet are a pitch that
    // carries on past the frame.
    canvas.drawLine(field.topLeft, field.bottomLeft, touchline);
    canvas.drawLine(field.topRight, field.bottomRight, touchline);
    canvas.drawLine(field.topLeft, field.topRight, goalLine);
    canvas.drawLine(field.bottomLeft, field.bottomRight, goalLine);

    // The halfway line and the centre circle, where the two teams meet — and
    // the strongest line on the pitch, because the fade is at its full value
    // there.
    final middle = field.center.dy;
    canvas.drawLine(
      Offset(field.left, middle),
      Offset(field.right, middle),
      marking,
    );
    canvas.drawCircle(Offset(field.center.dx, middle), w * 0.135, marking);
    canvas.drawCircle(Offset(field.center.dx, middle), 6, dot);

    // Both ends: penalty area, goal area, penalty spot, the arc off the box,
    // and the goal itself outside the touchline.
    final penaltyWidth = w * 0.59;
    final penaltyDepth = h * 0.157;
    final goalAreaWidth = w * 0.27;
    final goalAreaDepth = h * 0.052;
    final goalWidth = w * 0.108;
    final spotFromLine = h * 0.105;

    for (final top in [true, false]) {
      final edge = top ? field.top : field.bottom;
      final sign = top ? 1.0 : -1.0;

      Rect box(double boxWidth, double depth) => Rect.fromLTWH(
            field.center.dx - boxWidth / 2,
            top ? edge : edge - depth,
            boxWidth,
            depth,
          );

      canvas.drawRect(box(penaltyWidth, penaltyDepth), marking);
      canvas.drawRect(box(goalAreaWidth, goalAreaDepth), marking);

      final spot = Offset(field.center.dx, edge + sign * spotFromLine);
      canvas.drawCircle(spot, 6, dot);

      // The D: the part of the centre-circle-sized arc that falls outside the
      // penalty area. Swept from the spot, clipped to beyond the box.
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(
          field.left,
          top ? edge + penaltyDepth : field.top,
          w,
          top ? h : h - penaltyDepth,
        ),
      );
      canvas.drawArc(
        Rect.fromCircle(center: spot, radius: w * 0.135),
        0,
        sign * math.pi,
        false,
        marking,
      );
      canvas.restore();

      // The goal, standing outside the touchline.
      canvas.drawRect(
        Rect.fromLTWH(
          field.center.dx - goalWidth / 2,
          top ? edge - 15 : edge,
          goalWidth,
          15,
        ),
        touchline,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) => false;
}
