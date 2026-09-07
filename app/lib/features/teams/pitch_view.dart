import 'dart:math' as math;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import 'formation.dart';
import 'match_stage.dart';
import 'team_models.dart';

enum PitchPresentation { phone, shareBeforeResult, shareResult }

/// The approved pitch is one perspective drawing with deterministic anchors.
/// How a pitch decides which row a player stands in.
enum PitchLayoutMode {
  /// The match presentation, unchanged: [buildFormation] groups the side and
  /// may move a player into a neighbouring line so a real squad reads as a
  /// shape. Every match screen and every share card uses this.
  matchFormation,

  /// Rows taken **strictly** from each assignment's `assignedPosition`, in the
  /// order GK, DEF, MID, FWD, with empty rows omitted.
  ///
  /// For the Team of Period, where the position is the award itself. Nobody
  /// there was placed by an engine balancing a match -- they were given the
  /// position because it is where they actually played most of the period --
  /// so borrowing a midfielder into defence to make a familiar shape would
  /// redraw the award into something the evidence never said. There is no
  /// minimum defence, no minimum attack, and a period with no goalkeeper
  /// evidence simply has no goalkeeper row.
  exactAssignedPositions,
}

/// Stored assignments remain untouched; [buildFormation] still owns grouping.
class PitchView extends StatelessWidget {
  const PitchView({
    super.key,
    required this.assignments,
    required this.nameOf,
    this.players = const {},
    this.hasNaturalGoalkeeper = true,
    this.layout = PitchLayoutMode.matchFormation,
    this.avatarUrlOf,
    this.ratingOf,
    this.onTapPlayer,
    this.goalsOf,
    this.isMvpOf,
    this.presentation = PitchPresentation.phone,
    this.team = TeamId.a,
    this.pitchKey,
  });

  /// A phone pitch at the width a 390pt screen leaves it. A reference, not a
  /// device constant: every phone size below is solved from the width the pitch
  /// is actually given.
  static const phonePitchWidth = MatchStage.phoneReferenceWidth;
  static const phoneAspectRatio = MatchStage.phonePitchAspect;
  static const phonePitchHeight = phonePitchWidth / phoneAspectRatio;

  /// The size the phone drew a player at before this presentation was
  /// separated from the share raster, expressed at [pitchWidth]. Nothing below
  /// draws one smaller: a crowded lineup shrinks towards this and stops, so no
  /// arrangement comes out of this change worse than it went in.
  static double phoneAvatarFloor(double pitchWidth) =>
      50 * pitchWidth / MatchStage.sharePitchWidth;

  /// The share pitch, at the box [MatchStageSection] gives it. One box for
  /// both share states and for both sides — the card shows two halves of one
  /// field, and two fields of different depths would say otherwise.
  static const shareBeforePitchWidth = MatchStage.sharePitchWidth;
  static const shareBeforePitchHeight = MatchStage.sharePitchHeight;
  static const shareBeforeAspectRatio =
      shareBeforePitchWidth / shareBeforePitchHeight;

  static const shareResultPitchWidth = MatchStage.sharePitchWidth;
  static const shareResultPitchHeight = MatchStage.sharePitchHeight;
  static const shareResultAspectRatio =
      shareResultPitchWidth / shareResultPitchHeight;

  final List<TeamAssignment> assignments;

  /// The profiles behind the participants, where the caller has them. The match
  /// path passes them as it always has; the Team of Period has no current
  /// profile to pass and does not invent one -- it supplies [avatarUrlOf] and
  /// [ratingOf] instead.
  final Map<String, PlayerCoreInputs> players;

  /// Consulted only in [PitchLayoutMode.matchFormation]. The exact layout draws
  /// the goalkeeper row from the assignments themselves, so a squad's natural
  /// goalkeepers are not a question it asks.
  final bool hasNaturalGoalkeeper;
  final PitchLayoutMode layout;

  /// Presentation-only overrides, taking precedence over [players].
  ///
  /// They exist so that a caller who has a face and a rating but no
  /// `PlayerCoreInputs` can draw a player without fabricating a date of birth
  /// and a current primary position to satisfy a constructor. A manufactured
  /// profile would be a lie in the one place this feature must not tell one:
  /// the award's position is historical evidence, not today's profile.
  final String? Function(String participantId)? avatarUrlOf;
  final double? Function(String participantId)? ratingOf;

  final String Function(String userId) nameOf;
  final void Function(TeamAssignment assignment)? onTapPlayer;
  final int Function(String participantId)? goalsOf;
  final bool Function(String participantId)? isMvpOf;
  final PitchPresentation presentation;
  final TeamId team;
  final Key? pitchKey;

  static Key avatarKey(String id) => ValueKey('player-avatar-$id');
  static Key nameKey(String id) => ValueKey('player-name-$id');
  static Key ratingKey(String id) => ValueKey('player-rating-$id');
  static Key goalKey(String id) => ValueKey('player-goal-$id');
  static Key mvpKey(String id) => ValueKey('player-mvp-$id');

  static const _fieldTopLeft = Offset(.0953, .0106);
  static const _fieldTopRight = Offset(.9009, 0);
  static const _fieldBottomRight = Offset(1, .9915);
  static const _fieldBottomLeft = Offset(0, 1);

  /// Projects a normalized point on the approved field plane to the canvas.
  @visibleForTesting
  static Offset projectFieldPoint(Size size, Offset fieldPoint) {
    final topLeft = Offset(
      size.width * _fieldTopLeft.dx,
      size.height * _fieldTopLeft.dy,
    );
    final topRight = Offset(
      size.width * _fieldTopRight.dx,
      size.height * _fieldTopRight.dy,
    );
    final bottomRight = Offset(
      size.width * _fieldBottomRight.dx,
      size.height * _fieldBottomRight.dy,
    );
    final bottomLeft = Offset(
      size.width * _fieldBottomLeft.dx,
      size.height * _fieldBottomLeft.dy,
    );
    final left = Offset.lerp(topLeft, bottomLeft, fieldPoint.dy)!;
    final right = Offset.lerp(topRight, bottomRight, fieldPoint.dy)!;
    return Offset.lerp(left, right, fieldPoint.dx)!;
  }

  @visibleForTesting
  static List<Offset> projectFieldRect(Size size, Rect fieldRect) => [
        projectFieldPoint(size, fieldRect.topLeft),
        projectFieldPoint(size, fieldRect.topRight),
        projectFieldPoint(size, fieldRect.bottomRight),
        projectFieldPoint(size, fieldRect.bottomLeft),
      ];

  /// The depth a point sits at, for a side that defends the other way.
  ///
  /// **This is the whole of the mirror, and it is deliberately not a mirror of
  /// the canvas.** Turning the canvas over turned Team B's outer trapezoid
  /// upside down with it, so the two sides no longer looked like the same kind
  /// of object. Flipping *depth* instead leaves the pitch the shape it was —
  /// same outline, same perspective, same light — and moves only what is drawn
  /// on it: Team B's goal to the far end, its keeper with it, its attack to the
  /// edge it shares with Team A.
  static double playDepth(double depth, {required bool mirror}) =>
      mirror ? 1 - depth : depth;

  @visibleForTesting
  static Rect playRect(Rect fieldRect, {required bool mirror}) => mirror
      ? Rect.fromLTWH(
          fieldRect.left,
          1 - fieldRect.top - fieldRect.height,
          fieldRect.width,
          fieldRect.height,
        )
      : fieldRect;

  /// Where a row of players may stand, as a fraction of the pitch's depth.
  ///
  /// The band, not the lines in it: the hindmost row sits at [rowNear]
  /// with its own goal behind it, the foremost at [rowFar] against the
  /// edge it shares with the other side, and whatever lines the formation
  /// actually produced are spread evenly between the two. Even spreading is
  /// what stops a seven-a-side from bunching into the shape an eleven-a-side
  /// needs, and it is a projection decision — which line goes where is still
  /// entirely [buildFormation]'s.
  ///
  /// The span is what an eleven-a-side needs: four rows across it leave exactly
  /// the room a face and the name under it take, at the size both were
  /// approved at. Widening it would spend depth the dense case cannot spare;
  /// narrowing it would shrink the faces.
  static const rowNear = .17;
  static const rowFar = .83;

  /// How deep into the half the line across its defending end is drawn.
  ///
  /// The trapezoid's own outline is the boundary at depth `0`; this is the
  /// line inside it that [_PerspectivePitchPainter._markHalf] strokes along
  /// with the penalty area, and it is the one a label actually runs into. The
  /// goal itself stands beyond both, outside the field.
  static const endLineDepth = .036;

  /// The half of the centre circle that falls inside a defending half.
  ///
  /// It is the approved centre circle and not a new one: the full pitch draws
  /// it at the middle of the field with radii .14 by .15, and a half of that
  /// pitch drawn at the same height is the same circle with its depth doubled
  /// and its centre on the halfway edge. So the arc below is `.14` across and
  /// `.30` deep, centred at depth 1, and the half a reader cannot see is the
  /// half that belongs to the side opposite.
  @visibleForTesting
  static List<Offset> projectHalfCenterArc(
    Size size, {
    required bool mirror,
    int segments = 48,
  }) =>
      [
        for (var index = 0; index <= segments; index++)
          projectFieldPoint(
            size,
            Offset(
              .5 + .14 * math.cos(math.pi * index / segments),
              playDepth(1 - .30 * math.sin(math.pi * index / segments),
                  mirror: mirror),
            ),
          ),
      ];

  @visibleForTesting
  static List<Offset> projectCenterCircle(
    Size size, {
    int segments = 64,
  }) =>
      [
        for (var index = 0; index <= segments; index++)
          projectFieldPoint(
            size,
            Offset(
              .5 + .14 * math.cos(2 * math.pi * index / segments),
              .5 + .15 * math.sin(2 * math.pi * index / segments),
            ),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final exact = layout == PitchLayoutMode.exactAssignedPositions;
    // Not built at all in the exact layout. `buildFormation` is where a player
    // may be moved between lines, and the point of the exact layout is that
    // nobody is.
    final formation = exact
        ? null
        : buildFormation(
            assignments,
            order: (a, b) =>
                nameOf(a.participantId).compareTo(nameOf(b.participantId)),
          );
    final approvedDenseRows = exact ? null : _approvedDenseRows();
    final rows = exact
        ? _exactRows()
        : approvedDenseRows ??
            <_FormationRow>[
              if (hasNaturalGoalkeeper && formation!.goalkeepers.isNotEmpty)
                _FormationRow(_Line.goalkeeper, formation.goalkeepers),
              if (formation!.defence.isNotEmpty)
                _FormationRow(_Line.defence, formation.defence),
              for (final row in formation.midfieldRows)
                _FormationRow(_Line.midfield, row),
              if (formation.attack.isNotEmpty)
                _FormationRow(_Line.attack, formation.attack),
            ];
    final visible = [for (final row in rows) ...row.players];

    final phone = presentation == PitchPresentation.phone;
    // Team B defends the far end, on the phone and on the card alike. The
    // opposing half-pitch is the product's one way of drawing a match now, so
    // a picture of that match is a picture of the same thing.
    final mirror = team == TeamId.b;

    return AspectRatio(
      // Each surface keeps its own depth: the phone was given a half's own
      // proportion, and the card keeps the raster it is composed against.
      // Both are halves; one is simply shallower than the other.
      aspectRatio: phone ? phoneAspectRatio : shareBeforeAspectRatio,
      child: SizedBox.expand(
        key: pitchKey ?? const ValueKey('match-pitch'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            // The traced seven-a-side anchors describe one particular match
            // shape, so they are not used for a team whose shape came from the
            // evidence: a seven-player award of two defenders and three
            // midfielders would be poured into a mould cut for a different
            // side.
            final isApprovedSeven = !exact &&
                visible.length == 7 &&
                hasNaturalGoalkeeper &&
                assignments
                        .where((item) => item.assignedPosition == Position.gk)
                        .length ==
                    1;
            final placed = isApprovedSeven
                ? _exactSevenSlots(size, team)
                : _formationSlots(size, rows);
            final dense = visible.length >= 9;
            // One decision, taken once, for every surface.
            //
            // Where the rows stand: hindmost against its own goal, foremost
            // against the edge it shares with the other side, and on Team B
            // that order runs the other way. How large a player is drawn: the
            // largest the room between those rows allows, up to the size the
            // squad's own density was approved at. The card used to answer the
            // second question with a diameter traced off an old raster, which
            // is why its players read as icons on a field rather than as the
            // field's subject.
            final spread = _spreadDownThePitch(placed, size, mirror: mirror);
            final scale = _markScale(size.width, dense, phone: phone);
            final slots = _sized(
              spread,
              size,
              visible.length,
              dense,
              scale,
              mirror: mirror,
              phone: phone,
            );

            return CustomPaint(
              painter: _PerspectivePitchPainter(mirror: mirror),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var index = 0; index < visible.length; index++)
                    _playerAt(
                      visible[index],
                      slots[index],
                      approvedDenseRows == null && formation != null
                          ? formation.movedFrom[visible[index].participantId]
                          : null,
                      dense: dense,
                      badgeScale: scale,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// How large every mark on a player is drawn, on either surface.
  ///
  /// Solved from the pitch's own width against [MatchStage.phoneReferenceWidth]
  /// — the width the approved sizes were quoted at — so a name, a rating pill,
  /// a goal badge and a star all keep the same fraction of the pitch they were
  /// approved at, whether the pitch is 360 points wide on a screen or 966 on a
  /// 1080-wide card. That is the whole of the parity: one set of numbers, read
  /// at whatever scale the surface is.
  ///
  /// **The clamp is a screen concern and stays one.** A small phone needs a
  /// proportionally *larger* badge to stay legible in the hand and a large one
  /// must not grow a pill into a placard, so the phone's ratio is held inside
  /// `[.9, 1.18]`. A share card is looked at as a picture, at whatever size it
  /// is opened; there is no hand-held floor to protect and no ceiling to hold,
  /// and clamping it to 1.18 is exactly what made the card's marks read as
  /// tiny against a pitch nearly three times the phone's width.
  static double _markScale(
    double pitchWidth,
    bool dense, {
    required bool phone,
  }) {
    final ratio = pitchWidth / MatchStage.phoneReferenceWidth;
    return (phone ? ratio.clamp(.9, 1.18) : ratio) * (dense ? .92 : 1.0);
  }

  /// How large a player may be drawn, on either surface.
  ///
  /// **Placement is untouched.** Every centre in [spread] was solved by the
  /// exact-seven contract or by the formation solver and is passed through; all
  /// this decides is how much of the space between those centres a player is
  /// allowed to fill.
  ///
  /// The size wanted is the approved target for the squad's size, read at the
  /// pitch's own scale. The size taken is the largest that still leaves
  /// daylight between neighbours, and the two constraints are read off the
  /// formation that was actually solved rather than assumed from a player
  /// count: the narrowest gap along a row caps the width, the narrowest gap
  /// between rows caps the height, and a lineup that fits neither shrinks to
  /// [phoneAvatarFloor] and no further.
  ///
  /// **The card runs this too, and did not used to.** It scaled a diameter
  /// traced off the old raster instead, which on a pitch of the card's width
  /// came out around a third of the size the same squad is drawn at on a
  /// phone. The floor above is that old traced size: nothing this solves for
  /// the card is smaller than what the card had.
  static List<_PlayerSlot> _sized(
    List<_PlayerSlot> spread,
    Size size,
    int count,
    bool dense,
    double badgeScale, {
    // Not used to place the rows — they arrive placed — but to know which end
    // of the half carries the goal, and so which row's label has to clear it.
    required bool mirror,
    // Only for `bottomLimit` below, which is the one thing the two surfaces
    // still answer differently. Every size above it is the same arithmetic.
    required bool phone,
  }) {
    // The rows arrive already spread down the half; every size below is a
    // function of the room between them.
    final rows = _rowsByDepth(spread, size.height);
    final gapX = _narrowestGapAlongRows(rows, size.width);
    final gapY = _narrowestGapBetweenRows(rows, size.height);

    final wanted = (count <= 7
            ? 55.0
            : count <= 9
                ? 50.0
                : 44.0) *
        size.width /
        MatchStage.phoneReferenceWidth;
    // What a neighbour leaves: along a row, daylight either side of the face;
    // between rows, room for the face *and* the name written under it.
    final nameBlock = (dense ? 18.0 : 24.0) * badgeScale;

    // How far down a label may reach.
    //
    // The bottom of the canvas on most sides: for the side attacking downwards
    // that edge is the halfway line, and a label resting on it costs nothing.
    // On the card's *defending* side it is the line drawn across the end the
    // goal stands in, because at the card's scale a label that reaches it is a
    // name with a white rule through it rather than a name a little low.
    //
    // The phone is not asked this question. It answers it in two steps and is
    // approved answering it that way — seat against the canvas, then lift the
    // one label that lands on a line — and it can, because a phone face is
    // capped by the size its squad was approved at rather than by the room
    // between rows, so the second step always has a point or two to move into.
    final endLine = _clearOfGoalLineAt(size, size.width / 2,
        depth: playDepth(endLineDepth, mirror: true));
    final bottomLimit = !phone && mirror ? endLine : size.height;

    // What the two ends leave, which is a different question from what two
    // rows leave.
    //
    // A side reaches half a face above its hindmost row and half a face plus a
    // name below its foremost, and the band between those rows is fixed. So
    // the room outside the band caps the face too: `.88` because the hindmost
    // face is allowed to overhang the near line by `allowed` below, which is
    // twelve per cent of the very diameter being solved for.
    //
    // The card is the reason this exists. Its face is large enough that the
    // two ends bind before the rows do, and until they were counted the last
    // row's name was drawn through the end line. A phone face is nowhere near
    // large enough for this to bind, which is why the phone is unmoved by it.
    //
    // Solved against the *defending* side's limit whichever side this is, so
    // that both halves come out with the same face. The two sides are mirror
    // images and only one of them has a goal line under its last row; sizing
    // each to its own end would draw Team A's players larger than Team B's,
    // which is the one thing the two halves are not allowed to disagree about.
    final endRoom = ((phone ? size.height : endLine) -
            (rowFar - rowNear) * size.height -
            nameBlock) /
        .88;
    final diameter = math.max(
      phoneAvatarFloor(size.width),
      math.min(
        wanted,
        math.min(
          gapX * .86,
          // Half a point of daylight between a name and the face of the row in
          // front of it. Without it the two are exactly flush by construction
          // — `nameBlock` is precisely what a card takes below its centre —
          // and whether they touch comes down to which way a rounding error
          // fell.
          math.min(gapY - nameBlock - .5, endRoom),
        ),
      ),
    );
    // Wide enough for a name, never wide enough to reach the next player's.
    var markerWidth = math.min(diameter * 2, gapX * .98);

    // Seat the side on the field it is standing on.
    //
    // Both passes below move where a player is *drawn* and neither touches how
    // the side was *solved*: every row keeps its members, its order and its
    // depth relative to the other rows, so the shape a reader reads off the
    // pitch is the shape the formation decided.
    final seated = _clearOfTheGoalLine(
      _seatedOnField(
          spread, size, diameter, nameBlock, markerWidth, bottomLimit),
      size,
      diameter,
      nameBlock,
      mirror: mirror,
    );
    final seatedRows = _rowsByDepth(seated, size.height);
    markerWidth = math.min(
      diameter * 2,
      _narrowestGapAlongRows(seatedRows, size.width) * .98,
    );

    return [
      for (var index = 0; index < spread.length; index++)
        _PlayerSlot(
          seated[index].center,
          diameter,
          spread[index].scale,
          markerWidth,
        ),
    ];
  }

  /// The solved formation, spread down the pitch it is drawn on.
  ///
  /// **Nothing here decides who stands in which line.** The rows arrive already
  /// grouped and already ordered from the back, and all this says is how deep
  /// down the pitch each of those rows is drawn: the hindmost at
  /// [rowNear] with its goal behind it, the foremost at [rowFar]
  /// facing the other side, the rest spread evenly between. Horizontal
  /// position is passed through untouched.
  ///
  /// Spread evenly rather than held at fixed per-line depths because the number
  /// of lines is not fixed — a seven-a-side has three and an eleven-a-side four
  /// — and depths chosen for four leave a side of three standing in a heap at
  /// one end of a pitch they are supposed to be spread across.
  static List<_PlayerSlot> _spreadDownThePitch(
    List<_PlayerSlot> placed,
    Size size, {
    required bool mirror,
  }) {
    if (placed.isEmpty) return placed;
    final rows = _rowIndexesByDepth(placed, size.height);
    final result = [...placed];
    for (var row = 0; row < rows.length; row++) {
      final along = rows.length == 1
          ? (rowNear + rowFar) / 2
          : rowNear + (rowFar - rowNear) * row / (rows.length - 1);
      // Team B runs the other way down its own pitch: hindmost row deepest,
      // attack against the edge it shares with Team A. Flipping the depth here
      // rather than the finished slot is what leaves every measurement after
      // this — touchline, seating, collision — reading true screen positions.
      final depth = playDepth(along, mirror: mirror);
      for (final index in rows[row]) {
        final slot = placed[index];
        result[index] = _PlayerSlot(
          Offset(slot.center.dx, depth * size.height),
          slot.avatarDiameter,
          slot.scale,
        );
      }
    }
    return result;
  }

  /// The rows, as lists of indexes into [placed], hindmost first.
  ///
  /// Indexes rather than points because a slot has to be given back to the
  /// player it was solved for, and two players on the same line share a depth
  /// to sort by. The tie-break on index keeps the grouping deterministic.
  static List<List<int>> _rowIndexesByDepth(
    List<_PlayerSlot> placed,
    double height,
  ) {
    final order = [for (var index = 0; index < placed.length; index++) index]
      ..sort((a, b) {
        final byDepth = placed[a].center.dy.compareTo(placed[b].center.dy);
        return byDepth != 0 ? byDepth : a.compareTo(b);
      });
    final tolerance = height * .05;
    final rows = <List<int>>[];
    for (final index in order) {
      final dy = placed[index].center.dy;
      if (rows.isEmpty ||
          (dy - placed[rows.last.first].center.dy).abs() > tolerance) {
        rows.add([index]);
      } else {
        rows.last.add(index);
      }
    }
    return rows;
  }

  /// The two placement corrections a half-pitch needs, applied in order.
  ///
  /// **Down, so the hindmost row is not standing off the end of the pitch.**
  /// A side is spread across a band that starts a face's width from its own
  /// goal line, and on a small enough surface a face is wider than that. The
  /// whole side moves together by the smallest amount that tucks it back in,
  /// capped by the room the last row has beyond it — so the gaps between rows,
  /// and with them the shape and the size every face is drawn at, are exactly
  /// what they were.
  ///
  /// **In, so the wide rows are not standing off the sides.** The field is a
  /// trapezoid and a row anchored at a fraction of the *canvas* can reach past
  /// a touchline that has already narrowed. Each row that does is drawn
  /// towards its own middle — the whole row, by one factor, so the spacing
  /// inside it stays even and it still reads as the line it is.
  ///
  /// Both surfaces need both: the pitch is the same shape on each, and it is
  /// the shape, not the surface, that either of these answers to.
  static List<_PlayerSlot> _seatedOnField(
    List<_PlayerSlot> placed,
    Size size,
    double diameter,
    double nameBlock,
    double markerWidth,
    // How far down a label may reach. The bottom of the canvas on most sides:
    // for the side attacking downwards that edge is the halfway line, and a
    // label resting on it costs nothing. See [_sized] for the one side and the
    // one surface where it is the goal line instead.
    double bottomLimit,
  ) {
    if (placed.isEmpty) return placed;

    final rows = _rowIndexesByDepth(placed, size.height);
    // Both sides are the same way up on screen now, so both need a face's
    // worth of room at the top and a face plus its name at the bottom.
    final top = placed[rows.first.first].center.dy - diameter / 2;
    final bottom = placed[rows.last.first].center.dy + diameter / 2 + nameBlock;
    // A face may break the end line a little — a keeper drawn wholly below it
    // reads as a defender — but only a little. A name may not.
    final allowed = diameter * .12;
    // Correctable either way: whichever end runs out of room is the end the
    // side is moved away from, so long as the other end has the room to give.
    //
    // The two caps are the same rule read from either end. Moving down, the
    // side may go until the last name reaches the far line and no further —
    // `size.height - bottom`. Moving up, it may go until the first *face*
    // overhangs the near line by the allowance it is granted — `top +
    // allowed`. That upward cap used to read `top - allowed`, which stopped
    // the side a whole allowance short of where it was permitted to stand: on
    // the phone the deficit was small enough that the smaller cap still
    // covered it, and on a card three times as wide, with a name three times
    // as tall hanging under the last row, it was not.
    final overTop = -top - allowed;
    final overBottom = bottom - bottomLimit;
    final shift = overTop > 0
        ? math.min(overTop, bottomLimit - bottom)
        : overBottom > 0
            ? -math.min(overBottom, top + allowed)
            : 0.0;

    final half = markerWidth / 2;
    final result = [...placed];
    for (final row in rows) {
      final dy = placed[row.first].center.dy + shift;
      // A card is a face with a name under it, and it has to fit the field at
      // the narrowest depth it reaches — the top of the face, since the pitch
      // narrows upwards on both sides now.
      final narrowest = dy - diameter / 2;
      final xs = [for (final index in row) placed[index].center.dx]..sort();
      final middle = (xs.first + xs.last) / 2;
      var factor = 1.0;
      if (row.length > 1) {
        final lo = _touchline(size, narrowest, right: false) + half;
        final hi = _touchline(size, narrowest, right: true) - half;
        if (xs.first < lo && middle > xs.first) {
          factor = math.min(factor, (middle - lo) / (middle - xs.first));
        }
        if (xs.last > hi && xs.last > middle) {
          factor = math.min(factor, (hi - middle) / (xs.last - middle));
        }
        // A row is drawn in, never squeezed: past this it would stop looking
        // like the width the formation asked for.
        factor = factor.clamp(.78, 1.0);
      }
      for (final index in row) {
        final slot = placed[index];
        result[index] = _PlayerSlot(
          Offset(middle + (slot.center.dx - middle) * factor, dy),
          slot.avatarDiameter,
          slot.scale,
        );
      }
    }
    return result;
  }

  /// Lifts the row standing on its own goal line clear of it.
  ///
  /// **A name is read; a line drawn under it is not.** A card is a face with a
  /// name below it, so the row nearest the bottom of the canvas is the one
  /// whose label runs into whatever is drawn there. On the side that attacks
  /// downwards that is the halfway edge, and a label resting on it costs
  /// nothing. On the side that *defends* downwards it is the goal line, with
  /// the goal itself immediately beyond — three strokes through the bottom of
  /// a goalkeeper's name.
  ///
  /// So only that side, and only that row, is lifted, by the smallest amount
  /// that puts the label wholly above the line, and never by more than the row
  /// behind it can spare. The keeper stays inside their own penalty area and
  /// in front of their six-yard box, which is where a keeper stands; nothing
  /// else on either side moves.
  static List<_PlayerSlot> _clearOfTheGoalLine(
    List<_PlayerSlot> placed,
    Size size,
    double diameter,
    double nameBlock, {
    required bool mirror,
  }) {
    // Only the side whose goal is at the bottom has a label pointing at it.
    if (!mirror || placed.isEmpty) return placed;
    final rows = _rowIndexesByDepth(placed, size.height);
    if (rows.length < 2) return placed;

    final keepers = rows.last;
    final dy = placed[keepers.first].center.dy;
    var limit = double.infinity;
    for (final index in keepers) {
      limit =
          math.min(limit, _clearOfGoalLineAt(size, placed[index].center.dx));
    }
    final wanted = dy + diameter / 2 + nameBlock - limit;
    if (wanted <= 0) return placed;

    // Never further than the row in front leaves room for.
    final ahead = placed[rows[rows.length - 2].first].center.dy;
    final room = (dy - ahead) - diameter - nameBlock;
    final lift = math.min(wanted, math.max(0.0, room));
    if (lift <= 0) return placed;

    final result = [...placed];
    for (final index in keepers) {
      final slot = placed[index];
      result[index] = _PlayerSlot(
        Offset(slot.center.dx, slot.center.dy - lift),
        slot.avatarDiameter,
        slot.scale,
      );
    }
    return result;
  }

  /// The goal line at one horizontal position, with its own stroke already
  /// taken off it.
  ///
  /// Read off the same projection the painter strokes the line with, so what a
  /// label is kept clear of is the line a reader actually sees rather than the
  /// bottom of the box the pitch was given.
  static double _clearOfGoalLineAt(Size size, double dx, {double depth = 1}) {
    final left = projectFieldPoint(size, Offset(0, depth));
    final right = projectFieldPoint(size, Offset(1, depth));
    final line =
        left.dy + (right.dy - left.dy) * (dx - left.dx) / (right.dx - left.dx);
    return line - math.max(1.8, size.width * .0048) - 1.5;
  }

  /// One touchline, at one depth down the canvas, read off the same projection
  /// the painter draws the field with.
  static double _touchline(Size size, double dy, {required bool right}) {
    final edge = right ? 1.0 : 0.0;
    final top = projectFieldPoint(size, Offset(edge, 0));
    final foot = projectFieldPoint(size, Offset(edge, 1));
    final t = ((dy - top.dy) / (foot.dy - top.dy)).clamp(0.0, 1.0);
    return top.dx + (foot.dx - top.dx) * t;
  }

  /// [placed] grouped into the rows it was drawn as, by depth.
  ///
  /// Grouped rather than taken from the formation because the two slot solvers
  /// disagree about shape — the exact-seven contract carries traced centres
  /// whose depths differ by a point within one row — and what matters here is
  /// which players a reader sees as standing in a line, which is a question
  /// about the drawing and not about the solver.
  static List<List<Offset>> _rowsByDepth(
    List<_PlayerSlot> placed,
    double height,
  ) {
    final sorted = [for (final slot in placed) slot.center]
      ..sort((a, b) => a.dy.compareTo(b.dy));
    final tolerance = height * .05;
    final rows = <List<Offset>>[];
    for (final point in sorted) {
      if (rows.isEmpty || (point.dy - rows.last.first.dy).abs() > tolerance) {
        rows.add([point]);
      } else {
        rows.last.add(point);
      }
    }
    return rows;
  }

  static double _narrowestGapAlongRows(List<List<Offset>> rows, double width) {
    var narrowest = width;
    for (final row in rows) {
      if (row.length < 2) continue;
      final xs = [for (final point in row) point.dx]..sort();
      for (var index = 1; index < xs.length; index++) {
        narrowest = math.min(narrowest, xs[index] - xs[index - 1]);
      }
    }
    return narrowest;
  }

  static double _narrowestGapBetweenRows(
    List<List<Offset>> rows,
    double height,
  ) {
    var narrowest = height;
    for (var index = 1; index < rows.length; index++) {
      narrowest = math.min(
        narrowest,
        rows[index].first.dy - rows[index - 1].first.dy,
      );
    }
    return narrowest;
  }

  /// The three dense contracts are role-shaped, not inferred. Other lineups
  /// retain the existing presentation solver and its Product Owner rules.
  /// The four lines, taken from the assignments and nothing else.
  ///
  /// Empty lines are omitted rather than drawn empty, so a period with no
  /// goalkeeper evidence produces a pitch with no goalkeeper row instead of a
  /// gap where the product would like one to be. Within a line the order is the
  /// caller's: the Team of Period screen hands them over already ranked.
  List<_FormationRow> _exactRows() {
    List<TeamAssignment> at(Position position) => [
          for (final item in assignments)
            if (item.assignedPosition == position) item,
        ];
    final lines = <(_Line, List<TeamAssignment>)>[
      (_Line.goalkeeper, at(Position.gk)),
      (_Line.defence, at(Position.def)),
      (_Line.midfield, at(Position.mid)),
      (_Line.attack, at(Position.fwd)),
    ];
    return [
      for (final (line, players) in lines)
        if (players.isNotEmpty) _FormationRow(line, players),
    ];
  }

  List<_FormationRow>? _approvedDenseRows() {
    if (assignments.length != 11 || !hasNaturalGoalkeeper) return null;
    List<TeamAssignment> at(Position position) => [
          for (final item in assignments)
            if (item.assignedPosition == position) item,
        ]..sort((a, b) =>
            nameOf(a.participantId).compareTo(nameOf(b.participantId)));

    final goalkeepers = at(Position.gk);
    final defence = at(Position.def);
    final midfield = at(Position.mid);
    final attack = at(Position.fwd);
    final approved = goalkeepers.length == 1 &&
        ((defence.length == 4 && midfield.length == 3 && attack.length == 3) ||
            (defence.length == 4 &&
                midfield.length == 4 &&
                attack.length == 2) ||
            (defence.length == 3 &&
                midfield.length == 4 &&
                attack.length == 3));
    if (!approved) return null;
    return [
      _FormationRow(_Line.goalkeeper, goalkeepers),
      _FormationRow(_Line.defence, defence),
      _FormationRow(_Line.midfield, midfield),
      _FormationRow(_Line.attack, attack),
    ];
  }

  Widget _playerAt(
    TeamAssignment assignment,
    _PlayerSlot slot,
    Position? movedFrom, {
    required bool dense,
    required double badgeScale,
  }) {
    final markerWidth =
        slot.markerWidth ?? (dense ? 118.0 : 228.0) * slot.scale;
    return Positioned(
      left: slot.center.dx - markerWidth / 2,
      top: slot.center.dy - slot.avatarDiameter / 2,
      width: markerWidth,
      child: PlayerCard(
        assignment: assignment,
        avatarUrl: avatarUrlOf?.call(assignment.participantId) ??
            players[assignment.participantId]?.avatarUrl,
        rating: ratingOf?.call(assignment.participantId) ??
            players[assignment.participantId]?.overallRating,
        name: nameOf(assignment.participantId),
        movedFrom: movedFrom,
        goals: goalsOf?.call(assignment.participantId) ?? 0,
        isMvp: isMvpOf?.call(assignment.participantId) ?? false,
        avatarDiameter: slot.avatarDiameter,
        layoutScale: slot.scale,
        badgeScale: badgeScale,
        markerWidth: markerWidth,
        dense: dense,
        onTap: onTapPlayer == null ? null : () => onTapPlayer!(assignment),
      ),
    );
  }

  /// The seven-a-side both sides were traced at.
  ///
  /// Each side keeps its own master. The two traces were taken separately and
  /// Team B's came back against a pitch a few points narrower than Team A's,
  /// which means a Team B anchor is a fraction of *that* pitch and has to be
  /// read back as one — reading it against Team A's would move every Team B
  /// player, on a phone as well as on the card, and the phone is settled.
  /// Both pitches are now drawn at Team A's size, and the third of a percent
  /// this leaves between two identically traced faces is a third of a point.
  ///
  /// The traced *depths* are read for the order they put the rows in and
  /// nothing else — [_spreadDownThePitch] decides how deep down the half each
  /// of those rows is actually drawn.
  List<_PlayerSlot> _exactSevenSlots(Size size, TeamId selectedTeam) {
    final sourceWidth = selectedTeam == TeamId.a ? 842.09 : 838.88;
    const sourceHeight = 502.90;
    final sx = size.width / sourceWidth;
    final sy = size.height / sourceHeight;
    final data = selectedTeam == TeamId.a ? _teamASeven : _teamBSeven;
    return [
      for (final point in data)
        _PlayerSlot(
          Offset(point.$1 * sx, point.$2 * sy),
          point.$3 * sx,
          sx,
        ),
    ];
  }

  List<_PlayerSlot> _formationSlots(Size size, List<_FormationRow> rows) {
    final sx = size.width / 842.09;
    final result = <_PlayerSlot>[];
    final midfieldCount =
        rows.where((row) => row.line == _Line.midfield).length;
    var midfieldIndex = 0;
    for (final row in rows) {
      final y = switch (row.line) {
        _Line.goalkeeper => .13,
        _Line.defence => .36,
        _Line.midfield =>
          midfieldCount == 1 ? .60 : (midfieldIndex++ == 0 ? .49 : .66),
        _Line.attack => .82,
      };
      final xs = _xAnchors(row.players.length);
      for (var index = 0; index < row.players.length; index++) {
        result.add(_PlayerSlot(
          Offset(size.width * xs[index], size.height * y),
          50.0 * sx,
          sx,
        ));
      }
    }
    return result;
  }

  static List<double> _xAnchors(int count) => switch (count) {
        1 => const [.50],
        2 => const [.33, .67],
        3 => const [.20, .50, .80],
        4 => const [.13, .38, .62, .87],
        _ => List.generate(count, (index) => (index + 1) / (count + 1)),
      };

  static const _teamASeven = <(double, double, double)>[
    (419.44, 22.47, 83.46),
    (175.48, 188.32, 79.18),
    (408.74, 189.39, 81.32),
    (650.56, 189.39, 74.90),
    (166.92, 368.08, 77.04),
    (410.88, 367.01, 74.90),
    (653.77, 368.08, 74.90),
  ];

  static const _teamBSeven = <(double, double, double)>[
    (417.30, 23.54, 83.46),
    (154.08, 190.46, 77.04),
    (404.46, 190.46, 81.32),
    (651.63, 190.46, 83.46),
    (153.01, 363.80, 79.18),
    (406.60, 363.80, 79.18),
    (651.63, 362.73, 79.18),
  ];
}

enum _Line { goalkeeper, defence, midfield, attack }

class _FormationRow {
  const _FormationRow(this.line, this.players);

  final _Line line;
  final List<TeamAssignment> players;
}

class _PlayerSlot {
  const _PlayerSlot(
    this.center,
    this.avatarDiameter,
    this.scale, [
    this.markerWidth,
  ]);

  final Offset center;
  final double avatarDiameter;
  final double scale;

  /// Null on the share surfaces, where the marker is a fraction of the raster
  /// and has to stay one. Set only by the phone sizing pass.
  final double? markerWidth;
}

class PlayerCard extends StatelessWidget {
  const PlayerCard({
    super.key,
    required this.assignment,
    required this.avatarUrl,
    required this.rating,
    required this.name,
    this.movedFrom,
    this.onTap,
    this.goals = 0,
    this.isMvp = false,
    required this.avatarDiameter,
    required this.layoutScale,
    required this.badgeScale,
    required this.markerWidth,
    required this.dense,
  });

  final TeamAssignment assignment;
  /// Resolved by [PitchView] from its callbacks or its profile map. A null
  /// rating draws no rating badge, which is what a participant the caller knows
  /// nothing numeric about looks like.
  final String? avatarUrl;
  final double? rating;
  final String name;
  final Position? movedFrom;
  final VoidCallback? onTap;
  final int goals;
  final bool isMvp;
  final double avatarDiameter;
  final double layoutScale;

  /// What a badge is drawn at. Separated from [layoutScale] because the phone
  /// sizes a rating pill to be read and the share surfaces size one to fit a
  /// raster, and one number cannot be both.
  final double badgeScale;

  /// The full width this player occupies, which is what the badges anchored to
  /// the edges of the face are measured in from.
  final double markerWidth;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bs = badgeScale;
    // A crowded side gets smaller badges, and only smaller badges. The face
    // and the name under it keep the sizes they were approved at; what was
    // wrong at eleven a side was a rating pill three quarters as wide as the
    // player it belonged to, which is a mark that has stopped annotating its
    // subject and started replacing it.
    final badge = dense ? bs * .92 : bs;
    // Read into a local so the null check below promotes it; a field cannot.
    final avatarUrl = this.avatarUrl;
    final guest = assignment.isProfessionalGuest;
    final nameTop = avatarDiameter + (dense ? 4 : 7) * bs;
    final nameHeight = (dense ? 14.0 : 17.0) * bs;
    // The distance from the face's own edge that a badge hangs off it, so a
    // mark stays attached to its player whatever width the label is given.
    final inset = (markerWidth - avatarDiameter) / 2;
    final body = SizedBox(
      height: nameTop + nameHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                key: PitchView.avatarKey(assignment.participantId),
                width: avatarDiameter,
                height: avatarDiameter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      // The best player wears the mark rather than only
                      // carrying it: a gold ring reads before any badge beside
                      // it does, and it survives a crowd that shrinks badges.
                      color: isMvp
                          ? MatchStage.star
                          : MatchStage.accent.withValues(alpha: .78),
                      width: math.max(1.6, (isMvp ? 3.0 : 2.2) * bs),
                    ),
                    boxShadow: [
                      if (isMvp)
                        BoxShadow(
                          color: MatchStage.star.withValues(alpha: .45),
                          blurRadius: 10 * bs,
                          spreadRadius: 1 * bs,
                        )
                      else
                        BoxShadow(
                          color: const Color(0x66000000),
                          blurRadius: 5 * bs,
                          offset: Offset(0, 2 * bs),
                        ),
                    ],
                  ),
                  child: ClipOval(
                    child: avatarUrl != null && !guest
                        ? Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _fallbackAvatar(guest),
                          )
                        : _fallbackAvatar(guest),
                  ),
                ),
              ),
            ),
          ),
          if (rating != null)
            Positioned(
              left: inset - 7 * badge,
              top: avatarDiameter - (dense ? 20 : 18) * badge,
              child: _RatingBadge(
                participantId: assignment.participantId,
                rating: rating!,
                scale: badge,
              ),
            ),
          // Goals and the MVP star are two badges and stay two badges. A player
          // who did both did two things, and a single combined pill would read
          // as one — so they stack against the same edge of the face, in that
          // order, close enough to belong to it.
          if (goals > 0)
            Positioned(
              right: inset - 8 * badge,
              // Flush with the top of the face, never above it: a badge that
              // overhung the face reached into the row standing behind this
              // one, and the face is what had to shrink to pay for it.
              top: 0,
              child: _GoalBadge(
                participantId: assignment.participantId,
                goals: goals,
                scale: badge,
              ),
            ),
          if (isMvp)
            Positioned(
              right: inset - 8 * badge,
              top: (goals > 0 ? 22.0 : 0.0) * badge,
              child: _MvpBadge(
                participantId: assignment.participantId,
                scale: badge,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: nameTop,
            height: nameHeight,
            child: Text(
              name,
              key: PitchView.nameKey(assignment.participantId),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MatchStage.ink,
                fontSize: (dense ? 12.0 : 12.5) * bs,
                fontWeight: FontWeight.w700,
                height: 1,
                shadows: const [
                  Shadow(color: Color(0xCC000000), blurRadius: 3)
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return body;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18 * layoutScale),
        child: body,
      ),
    );
  }

  Widget _fallbackAvatar(bool guest) => ColoredBox(
        color: Colors.white,
        child: Icon(
          guest ? Icons.workspace_premium_outlined : Icons.person,
          color: const Color(0xFF237A4D),
          size: avatarDiameter * .55,
        ),
      );
}

/// The number, and only ever the number.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({
    required this.participantId,
    required this.rating,
    required this.scale,
  });

  final String participantId;
  final double rating;
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        key: PitchView.ratingKey(participantId),
        constraints: BoxConstraints(minWidth: 36 * scale),
        height: 22 * scale,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 8 * scale),
        decoration: BoxDecoration(
          // Near-black. The dark green it used to wear was a green pill on a
          // green pitch, and the number inside it was the thing hardest to
          // read on the whole surface.
          color: MatchStage.phoneBadge,
          borderRadius: BorderRadius.circular(11 * scale),
          border: Border.all(
            color: Colors.white.withValues(alpha: .30),
            width: math.max(.6, .8 * scale),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x73000000),
              blurRadius: 4 * scale,
              offset: Offset(0, 1.5 * scale),
            ),
          ],
        ),
        child: Text(
          rating.toStringAsFixed(1),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: MatchStage.ink,
            fontSize: 12 * scale,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      );
}

class _MvpBadge extends StatelessWidget {
  const _MvpBadge({
    required this.participantId,
    required this.scale,
  });

  final String participantId;
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        key: PitchView.mvpKey(participantId),
        width: 20 * scale,
        height: 20 * scale,
        decoration: BoxDecoration(
          // Gold, filled — the same gold as the ring the face wears, so the
          // two read as one mark rather than as two decorations that happened
          // to land on the same player.
          color: MatchStage.star,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: .45),
            width: math.max(.6, .8 * scale),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x73000000),
              blurRadius: 4 * scale,
              offset: Offset(0, 1.5 * scale),
            ),
          ],
        ),
        child: Icon(
          Icons.star_rounded,
          color: MatchStage.phoneBadge,
          size: 15 * scale,
        ),
      );
}

class _GoalBadge extends StatelessWidget {
  const _GoalBadge({
    required this.participantId,
    required this.goals,
    required this.scale,
  });

  final String participantId;
  final int goals;
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        key: PitchView.goalKey(participantId),
        height: 20 * scale,
        padding: EdgeInsets.symmetric(horizontal: 5 * scale),
        decoration: BoxDecoration(
          // A goal gets its own colour. Sharing the rating's black meant the
          // two marks on a player's face were told apart only by reading them,
          // which is one job too many for a badge; a deep sports orange is
          // seen before it is read. Not gold — that is the best player, and a
          // scorer is not automatically one.
          color: MatchStage.goalMark,
          borderRadius: BorderRadius.circular(10 * scale),
          border: Border.all(
            color: Colors.white.withValues(alpha: .38),
            width: math.max(.6, .8 * scale),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x73000000),
              blurRadius: 4 * scale,
              offset: Offset(0, 1.5 * scale),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "3 ⚽" — the count is read first, because how many is the thing
            // a reader wants from this badge.
            if (goals > 1) ...[
              _count(),
              SizedBox(width: 2 * scale),
            ],
            Icon(
              Icons.sports_soccer,
              // White on the orange. The ball used to be drawn in
              // [MatchStage.goal] against a dark pill; on this pill that would
              // be orange on orange.
              color: MatchStage.ink,
              size: 12 * scale,
            ),
          ],
        ),
      );

  Widget _count() => Text(
        '$goals',
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: MatchStage.ink,
          fontSize: 12 * scale,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      );
}

/// One pitch, drawn one way.
///
/// There is no surface flag here any more. The card used to be given a duller
/// green, thinner stripes, a greyer line and no shadow — a second pitch design
/// maintained beside the approved one, and the reason a share card read as an
/// older picture of the same match rather than as the same picture. What the
/// phone was approved with is what both surfaces are drawn with; the only
/// thing that differs between them is how large the canvas is, and every
/// weight below is already a fraction of that.
class _PerspectivePitchPainter extends CustomPainter {
  const _PerspectivePitchPainter({this.mirror = false});

  /// Whether this side defends the far end, which is Team B's everywhere.
  ///
  /// **It changes the markings and nothing else.** The outline, the
  /// perspective, the grass, the stripes and the light are drawn identically
  /// for both sides — two pitches that look like the same kind of object —
  /// and all this decides is which end of that object carries the goal.
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    // The outline every side shares. No orientation of any kind reaches it:
    // Team A and Team B are the same shape, lit the same way, and a reader
    // should be able to tell them apart only by what is drawn inside.
    final path = _closedPath(
      PitchView.projectFieldRect(size, const Rect.fromLTWH(0, 0, 1, 1)),
    );

    // What the field stands on. Drawn under the grass and offset downwards,
    // the way the one light above would cast it, so the edge lifts off the
    // dark ground instead of being cut out of it — which is most of what makes
    // a flat drawing look like a plane. Downwards on both sides: a shadow
    // thrown upwards on one of them would put a second light in the room.
    canvas.drawPath(
      path.shift(Offset(0, size.height * .022)),
      Paint()
        ..color = const Color(0x8C000000)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(4, size.height * .035),
        ),
    );

    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          // One light, over the reader's shoulder, for both sides. The field
          // *geometry* is what opposes; the light falling on it does not, and
          // a pitch lit from below reads as a photograph turned upside down
          // rather than as the far half of the same match.
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MatchStage.phonePitchLight, MatchStage.phonePitchDark],
        ).createShader(Offset.zero & size),
    );
    final stripe = Paint()..color = Colors.white.withValues(alpha: .07);
    for (var index = 1; index < 6; index += 2) {
      canvas.drawPath(
        _closedPath(PitchView.projectFieldRect(
          size,
          Rect.fromLTWH(0, index / 6, 1, 1 / 6),
        )),
        stripe,
      );
    }
    canvas.restore();

    final line = Paint()
      ..color = Colors.white.withValues(alpha: .70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.3, size.width * .0034);
    // The edge of the field, said once and said clearly. Everything inside it
    // is drawn at the weight above; this is the boundary, and it is what
    // separates grass from ground.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: .82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.8, size.width * .0048),
    );
    canvas.drawPath(path, line);

    _markHalf(canvas, size, line);
  }

  /// One defending half, in the whole pitch's own vocabulary.
  ///
  /// **Every value here is an approved one, read at twice the depth.** A half
  /// drawn at the height a whole pitch was drawn at is that pitch with its
  /// depth doubled, so the penalty area the share card puts at `.018` deep and
  /// `.152` tall is here at `.036` and `.304`, the goal area likewise, and the
  /// centre circle becomes the arc on the facing edge. Nothing is invented and
  /// no proportion is re-derived from a rulebook: the drawing is the approved
  /// drawing, with the half nobody on this side defends left off.
  ///
  /// What that leaves is a field a reader can only read one way — a goal at
  /// the outer end, midfield at the facing one — which is the whole point of
  /// showing halves at all.
  void _markHalf(Canvas canvas, Size size, Paint line) {
    // Depth, flipped for the side that defends the far end. Only the markings
    // below read through this; the outline above never does.
    Offset at(double x, double depth) => PitchView.projectFieldPoint(
          size,
          Offset(x, PitchView.playDepth(depth, mirror: mirror)),
        );
    Path box(Rect rect) => _closedPath(PitchView.projectFieldRect(
          size,
          PitchView.playRect(rect, mirror: mirror),
        ));

    // The inner line the pitch has always carried, on the three sides that are
    // really boundaries. It stops short of the facing edge deliberately: that
    // edge is the middle of a football field, not the side of one, and a
    // second line along it would say the opposite.
    canvas.drawPath(
      _openPath([at(.018, 1), at(.018, .036), at(.982, .036), at(.982, 1)]),
      line,
    );

    // The penalty area and the six-yard box, at the end this side defends.
    canvas.drawPath(box(const Rect.fromLTWH(.32, .036, .36, .304)), line);
    canvas.drawPath(box(const Rect.fromLTWH(.41, .036, .18, .124)), line);

    // The goal, drawn behind its own line the way a goal is. Outside the
    // field, so it reaches nothing a player is drawn with.
    canvas.drawPath(box(const Rect.fromLTWH(.446, -.028, .108, .028)), line);

    // And the half of the centre circle this side owns, curving in from the
    // facing edge. The half that is missing is the argument: it says the edge
    // it sits on is the middle of a pitch and not the end of one.
    canvas.drawPath(
      _openPath(PitchView.projectHalfCenterArc(size, mirror: mirror)),
      line,
    );
  }

  static Path _closedPath(List<Offset> points) => _openPath(points)..close();

  static Path _openPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _PerspectivePitchPainter oldDelegate) =>
      oldDelegate.mirror != mirror;
}
