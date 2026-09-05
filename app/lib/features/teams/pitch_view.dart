import 'dart:math' as math;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import 'formation.dart';
import 'match_stage.dart';
import 'team_models.dart';

enum PitchPresentation { phone, shareBeforeResult, shareResult }

/// The approved pitch is one perspective drawing with deterministic anchors.
/// Stored assignments remain untouched; [buildFormation] still owns grouping.
class PitchView extends StatelessWidget {
  const PitchView({
    super.key,
    required this.assignments,
    required this.players,
    required this.hasNaturalGoalkeeper,
    required this.nameOf,
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
      50 * pitchWidth / shareBeforePitchWidth;

  static const shareBeforePitchWidth = 842.09;
  static const shareBeforePitchHeight = 502.90;
  static const shareBeforeAspectRatio =
      shareBeforePitchWidth / shareBeforePitchHeight;
  static const shareBeforeAvatarDiameter = 83.46;

  static const shareResultPitchWidth = 842.09;
  static const shareResultPitchHeight = 502.90;
  static const shareResultAspectRatio =
      shareResultPitchWidth / shareResultPitchHeight;
  static const shareResultAvatarDiameter = 83.46;

  final List<TeamAssignment> assignments;
  final Map<String, PlayerCoreInputs> players;
  final bool hasNaturalGoalkeeper;
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
    final formation = buildFormation(
      assignments,
      order: (a, b) =>
          nameOf(a.participantId).compareTo(nameOf(b.participantId)),
    );
    final approvedDenseRows = _approvedDenseRows();
    final rows = approvedDenseRows ??
        <_FormationRow>[
          if (hasNaturalGoalkeeper && formation.goalkeepers.isNotEmpty)
            _FormationRow(_Line.goalkeeper, formation.goalkeepers),
          if (formation.defence.isNotEmpty)
            _FormationRow(_Line.defence, formation.defence),
          for (final row in formation.midfieldRows)
            _FormationRow(_Line.midfield, row),
          if (formation.attack.isNotEmpty)
            _FormationRow(_Line.attack, formation.attack),
        ];
    final visible = [for (final row in rows) ...row.players];

    final phone = presentation == PitchPresentation.phone;

    return AspectRatio(
      // The phone field is deeper than the share raster's, and that is the
      // whole of what makes it read as a field rather than as a strip of grass.
      // Only this ratio differs; the projection, the anchors and the formation
      // solver below are the same drawing at a different depth.
      aspectRatio: phone ? phoneAspectRatio : shareBeforeAspectRatio,
      child: SizedBox.expand(
        key: pitchKey ?? const ValueKey('match-pitch'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final isApprovedSeven = visible.length == 7 &&
                hasNaturalGoalkeeper &&
                assignments
                        .where((item) => item.assignedPosition == Position.gk)
                        .length ==
                    1;
            final placed = isApprovedSeven
                ? _exactSevenSlots(size, team)
                : _formationSlots(size, rows);
            final dense = visible.length >= 9;
            final slots = phone
                ? _phoneSized(placed, size, visible.length, dense)
                : placed;
            // Null on the share surfaces, where a badge is still a fraction of
            // the slot it hangs off — and Team B's slots are traced from a
            // marginally narrower master, so a scale solved from the pitch
            // rather than from the slot would move that side's badges.
            final phoneBadgeScale =
                phone ? _phoneBadgeScale(size.width, dense) : null;

            return CustomPaint(
              painter: _PerspectivePitchPainter(phone: phone),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var index = 0; index < visible.length; index++)
                    _playerAt(
                      visible[index],
                      slots[index],
                      approvedDenseRows == null
                          ? formation.movedFrom[visible[index].participantId]
                          : null,
                      dense: dense,
                      phoneBadgeScale: phoneBadgeScale,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// How large a badge is drawn on a phone.
  ///
  /// Solved from the pitch's own width so a larger screen gets a larger badge,
  /// and clamped so a small one still gets a legible rating rather than a
  /// proportionally correct smudge. At the reference width this is 1, which is
  /// what puts the rating pill at its approved 22 points.
  static double _phoneBadgeScale(double pitchWidth, bool dense) =>
      (pitchWidth / MatchStage.phoneReferenceWidth).clamp(.9, 1.18) *
      (dense ? .92 : 1.0);

  /// The phone's own answer to how large a player may be drawn.
  ///
  /// **Placement is untouched.** Every centre in [placed] was solved by the
  /// exact-seven contract or by the formation solver and is passed through; all
  /// this decides is how much of the space between those centres a player is
  /// allowed to fill, which the share raster decided by scaling a traced
  /// diameter and which a phone cannot afford to.
  ///
  /// The size wanted is the approved target for the squad's size. The size
  /// taken is the largest that still leaves daylight between neighbours, and
  /// the two constraints are read off the formation that was actually solved
  /// rather than assumed from a player count: the narrowest gap along a row
  /// caps the width, the narrowest gap between rows caps the height, and a
  /// lineup that fits neither shrinks to [phoneAvatarFloor] and no further.
  static List<_PlayerSlot> _phoneSized(
    List<_PlayerSlot> placed,
    Size size,
    int count,
    bool dense,
  ) {
    final rows = _rowsByDepth(placed, size.height);
    final gapX = _narrowestGapAlongRows(rows, size.width);
    final gapY = _narrowestGapBetweenRows(rows, size.height);
    final badgeScale = _phoneBadgeScale(size.width, dense);

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
    final diameter = math.max(
      phoneAvatarFloor(size.width),
      math.min(wanted, math.min(gapX * .86, gapY - nameBlock)),
    );
    // Wide enough for a name, never wide enough to reach the next player's.
    var markerWidth = math.min(diameter * 2, gapX * .98);

    // Seat the side on the field it is standing on.
    //
    // Both passes below move where a player is *drawn* and neither touches how
    // the side was *solved*: every row keeps its members, its order and its
    // depth relative to the other rows, so the shape a reader reads off the
    // pitch is the shape the formation decided.
    final seated =
        _seatedOnField(placed, size, diameter, nameBlock, markerWidth);
    final seatedRows = _rowsByDepth(seated, size.height);
    markerWidth = math.min(
      diameter * 2,
      _narrowestGapAlongRows(seatedRows, size.width) * .98,
    );

    return [
      for (var index = 0; index < placed.length; index++)
        _PlayerSlot(
          seated[index].center,
          diameter,
          placed[index].scale,
          markerWidth,
        ),
    ];
  }

  /// The two phone-only placement corrections, applied in order.
  ///
  /// **Down, so the front row is not standing off the top of the pitch.** The
  /// exact-seven contract anchors its keeper a couple of traced points from the
  /// goal line, which was a keeper's whole head when a face was twenty points
  /// across and is a third of one now that it is fifty-five. The whole side
  /// moves down together by the smallest amount that tucks it back in, capped
  /// by the room the last row has under it — so the gaps between rows, and with
  /// them the shape and the size every face is drawn at, are exactly what they
  /// were.
  ///
  /// **In, so the wide rows are not standing off the sides.** The field is a
  /// trapezoid and a back four anchored at a fraction of the *canvas* can reach
  /// past a touchline that has already narrowed. Each row that does is drawn
  /// towards its own middle — the whole row, by one factor, so the spacing
  /// inside it stays even and it still reads as the line it is.
  static List<_PlayerSlot> _seatedOnField(
    List<_PlayerSlot> placed,
    Size size,
    double diameter,
    double nameBlock,
    double markerWidth,
  ) {
    if (placed.isEmpty) return placed;

    // Rows, as lists of indexes into [placed]. Indexes rather than points
    // because a slot has to be given back to the player it was solved for, and
    // two players standing on the same line have the same depth to sort by.
    final order = [for (var index = 0; index < placed.length; index++) index]
      ..sort((a, b) {
        final byDepth = placed[a].center.dy.compareTo(placed[b].center.dy);
        return byDepth != 0 ? byDepth : a.compareTo(b);
      });
    final tolerance = size.height * .05;
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

    final top = placed[rows.first.first].center.dy - diameter / 2;
    final bottom = placed[rows.last.first].center.dy + diameter / 2 + nameBlock;
    // A face may break the goal line a little — a keeper drawn wholly below it
    // reads as a defender — but only a little.
    final allowed = diameter * .12;
    final shift = math.max(0.0, math.min(-top - allowed, size.height - bottom));

    final half = markerWidth / 2;
    final result = [...placed];
    for (final row in rows) {
      final dy = placed[row.first].center.dy + shift;
      final xs = [for (final index in row) placed[index].center.dx]..sort();
      final middle = (xs.first + xs.last) / 2;
      var factor = 1.0;
      if (row.length > 1) {
        final lo = _touchline(size, dy, right: false) + half;
        final hi = _touchline(size, dy, right: true) - half;
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
    required double? phoneBadgeScale,
  }) {
    final markerWidth =
        slot.markerWidth ?? (dense ? 118.0 : 228.0) * slot.scale;
    final badgeScale =
        phoneBadgeScale ?? (dense ? slot.scale * .84 : slot.scale);
    return Positioned(
      left: slot.center.dx - markerWidth / 2,
      top: slot.center.dy - slot.avatarDiameter / 2,
      width: markerWidth,
      child: PlayerCard(
        assignment: assignment,
        player: players[assignment.participantId],
        name: nameOf(assignment.participantId),
        movedFrom: movedFrom,
        goals: goalsOf?.call(assignment.participantId) ?? 0,
        isMvp: isMvpOf?.call(assignment.participantId) ?? false,
        avatarDiameter: slot.avatarDiameter,
        layoutScale: slot.scale,
        badgeScale: badgeScale,
        markerWidth: markerWidth,
        dense: dense,
        presentation: presentation,
        onTap: onTapPlayer == null ? null : () => onTapPlayer!(assignment),
      ),
    );
  }

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
    required this.player,
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
    required this.presentation,
  });

  final TeamAssignment assignment;
  final PlayerCoreInputs? player;
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
  final PitchPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final sx = layoutScale;
    final bs = badgeScale;
    final compact = presentation == PitchPresentation.phone;
    // A crowded side gets smaller badges, and only smaller badges. The face
    // and the name under it keep the sizes they were approved at; what was
    // wrong at eleven a side was a rating pill three quarters as wide as the
    // player it belonged to, which is a mark that has stopped annotating its
    // subject and started replacing it.
    final badge = compact && dense ? bs * .92 : bs;
    final avatarUrl = player?.avatarUrl;
    final guest = assignment.isProfessionalGuest;
    final nameTop = compact
        ? avatarDiameter + (dense ? 4 : 7) * bs
        : avatarDiameter + 4 * sx;
    final nameHeight =
        compact ? (dense ? 14.0 : 17.0) * bs : (dense ? 18 : 20) * sx;
    // The distance from the face's own edge that a badge hangs off it. The
    // share raster measures this from the marker; the phone measures it from
    // the face, because the marker is no longer a fixed multiple of one.
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
                      // On a phone the best player wears the mark rather than
                      // only carrying it: a gold ring reads before any badge
                      // beside it does. The share card is unchanged and keeps
                      // the one accent ring for everybody.
                      color: compact && isMvp
                          ? MatchStage.star
                          : MatchStage.accent.withValues(alpha: .78),
                      width: compact
                          ? math.max(1.6, (isMvp ? 3.0 : 2.2) * bs)
                          : math.max(1, 1.6 * sx),
                    ),
                    boxShadow: compact
                        ? [
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
                          ]
                        : null,
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
          if (player != null)
            Positioned(
              left: compact ? inset - 7 * badge : (dense ? 24 : 64) * sx,
              top: avatarDiameter - (compact ? (dense ? 20 : 18) : 20) * badge,
              child: _RatingBadge(
                participantId: assignment.participantId,
                rating: player!.overallRating,
                scale: badge,
                compact: compact,
              ),
            ),
          // Goals and the MVP star are two badges and stay two badges. A player
          // who did both did two things, and a single combined pill would read
          // as one — so they stack against the same edge of the face, in that
          // order, close enough to belong to it.
          if (goals > 0)
            Positioned(
              right: compact ? inset - 8 * badge : (dense ? 22 : 44) * sx,
              // Flush with the top of the face on a phone, never above it: a
              // badge that overhung the face reached into the row standing
              // behind this one, and the face is what had to shrink to pay
              // for it.
              top: compact ? 0 : -2 * badge,
              child: _GoalBadge(
                participantId: assignment.participantId,
                goals: goals,
                scale: badge,
                compact: compact,
              ),
            ),
          if (isMvp)
            Positioned(
              right: compact ? inset - 8 * badge : (dense ? 22 : 44) * sx,
              top: compact
                  ? (goals > 0 ? 22.0 : 0.0) * badge
                  : (goals > 0 ? 20 : -2) * badge,
              child: _MvpBadge(
                participantId: assignment.participantId,
                scale: badge,
                compact: compact,
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
                fontSize: compact
                    ? (dense ? 12.0 : 12.5) * bs
                    : (dense ? 14 : 15) * sx,
                fontWeight: FontWeight.w700,
                height: 1,
                shadows: compact
                    ? const [Shadow(color: Color(0xCC000000), blurRadius: 3)]
                    : const [Shadow(color: Color(0x99000000), blurRadius: 2)],
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
        borderRadius: BorderRadius.circular(18 * sx),
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

/// The number, and only ever the number. [compact] changes what it is drawn on
/// and nothing about what it says.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({
    required this.participantId,
    required this.rating,
    required this.scale,
    required this.compact,
  });

  final String participantId;
  final double rating;
  final double scale;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        key: PitchView.ratingKey(participantId),
        constraints: BoxConstraints(minWidth: (compact ? 36 : 42) * scale),
        height: 22 * scale,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: (compact ? 8 : 6) * scale),
        decoration: BoxDecoration(
          // Near-black on a phone. The dark green it used to wear was a green
          // pill on a green pitch, and the number inside it was the thing
          // hardest to read on the whole surface.
          color: compact
              ? MatchStage.phoneBadge
              : MatchStage.rating.withValues(alpha: .90),
          borderRadius: BorderRadius.circular(11 * scale),
          border: Border.all(
            color: compact
                ? Colors.white.withValues(alpha: .30)
                : MatchStage.inkMuted.withValues(alpha: .55),
            width: math.max(.6, .8 * scale),
          ),
          boxShadow: compact
              ? [
                  BoxShadow(
                    color: const Color(0x73000000),
                    blurRadius: 4 * scale,
                    offset: Offset(0, 1.5 * scale),
                  ),
                ]
              : null,
        ),
        child: Text(
          rating.toStringAsFixed(1),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: MatchStage.ink,
            fontSize: (compact ? 12 : 14) * scale,
            fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
            height: 1,
          ),
        ),
      );
}

class _MvpBadge extends StatelessWidget {
  const _MvpBadge({
    required this.participantId,
    required this.scale,
    required this.compact,
  });

  final String participantId;
  final double scale;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        key: PitchView.mvpKey(participantId),
        width: 20 * scale,
        height: 20 * scale,
        decoration: BoxDecoration(
          // Gold, filled, on a phone — the same gold as the ring the face
          // wears, so the two read as one mark rather than as two decorations
          // that happened to land on the same player.
          color: compact
              ? MatchStage.star
              : MatchStage.ground.withValues(alpha: .82),
          shape: BoxShape.circle,
          border: Border.all(
            color: compact
                ? Colors.white.withValues(alpha: .45)
                : MatchStage.star.withValues(alpha: .82),
            width: math.max(.6, .8 * scale),
          ),
          boxShadow: compact
              ? [
                  BoxShadow(
                    color: const Color(0x73000000),
                    blurRadius: 4 * scale,
                    offset: Offset(0, 1.5 * scale),
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.star_rounded,
          color: compact ? MatchStage.phoneBadge : MatchStage.star,
          size: 15 * scale,
        ),
      );
}

class _GoalBadge extends StatelessWidget {
  const _GoalBadge({
    required this.participantId,
    required this.goals,
    required this.scale,
    required this.compact,
  });

  final String participantId;
  final int goals;
  final double scale;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        key: PitchView.goalKey(participantId),
        height: 20 * scale,
        padding: EdgeInsets.symmetric(horizontal: (compact ? 5 : 4) * scale),
        decoration: BoxDecoration(
          // Restrained on a phone: the same near-black the rating wears, with
          // the ball in white. The orange said "alarm" beside a gold star that
          // was already saying "look here".
          color: compact
              ? MatchStage.phoneBadge
              : MatchStage.rating.withValues(alpha: .58),
          borderRadius: BorderRadius.circular(10 * scale),
          border: Border.all(
            color: compact
                ? Colors.white.withValues(alpha: .30)
                : MatchStage.goal.withValues(alpha: .82),
            width: math.max(.6, .8 * scale),
          ),
          boxShadow: compact
              ? [
                  BoxShadow(
                    color: const Color(0x73000000),
                    blurRadius: 4 * scale,
                    offset: Offset(0, 1.5 * scale),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Phone: "3 ⚽", the count read first. Share: the order the
            // approved raster has, untouched.
            if (compact && goals > 1) ...[
              _count(),
              SizedBox(width: 2 * scale),
            ],
            Icon(
              Icons.sports_soccer,
              color: compact ? MatchStage.ink : MatchStage.goal,
              size: (compact ? 12 : 13) * scale,
            ),
            if (!compact && goals > 1) ...[
              SizedBox(width: 2 * scale),
              _count(),
            ],
          ],
        ),
      );

  Widget _count() => Text(
        '$goals',
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: MatchStage.ink,
          fontSize: (compact ? 12 : 13) * scale,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      );
}

class _PerspectivePitchPainter extends CustomPainter {
  const _PerspectivePitchPainter({this.phone = false});

  /// Whether this is the phone field. The projection, the anchors and every
  /// marking below are the same either way; what differs is the grass, the
  /// weight of the paint on it, and whether the field is given a shadow to
  /// stand on.
  final bool phone;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _closedPath(PitchView.projectFieldRect(
      size,
      const Rect.fromLTWH(0, 0, 1, 1),
    ));

    // What the field stands on. Drawn under the grass and slightly below it,
    // so the near edge lifts off the dark ground instead of being cut out of
    // it — which is most of what makes a flat drawing look like a plane.
    if (phone) {
      canvas.drawPath(
        path.shift(Offset(0, size.height * .022)),
        Paint()
          ..color = const Color(0x8C000000)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.max(4, size.height * .035),
          ),
      );
    }

    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: phone
              ? const [MatchStage.phonePitchLight, MatchStage.phonePitchDark]
              : const [MatchStage.pitchLight, MatchStage.pitchDark],
        ).createShader(Offset.zero & size),
    );
    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: phone ? .07 : .035);
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
      ..color = phone
          ? Colors.white.withValues(alpha: .70)
          : MatchStage.pitchLine.withValues(alpha: .48)
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          math.max(phone ? 1.3 : 1.0, size.width * (phone ? .0034 : .0025));
    // The edge of the field, said once and said clearly. Everything inside it
    // is drawn at the weight above; this is the boundary, and on a phone it is
    // what separates grass from ground.
    if (phone) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: .82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.8, size.width * .0048),
      );
    }
    canvas.drawPath(path, line);
    canvas.drawPath(
      _closedPath(PitchView.projectFieldRect(
        size,
        const Rect.fromLTWH(.018, .018, .964, .964),
      )),
      line,
    );
    canvas.drawLine(
      PitchView.projectFieldPoint(size, const Offset(.018, .5)),
      PitchView.projectFieldPoint(size, const Offset(.982, .5)),
      line,
    );
    canvas.drawPath(
      _openPath(PitchView.projectCenterCircle(size)),
      line,
    );
    for (final area in const [
      Rect.fromLTWH(.32, .018, .36, .152),
      Rect.fromLTWH(.32, .83, .36, .152),
      Rect.fromLTWH(.41, .018, .18, .062),
      Rect.fromLTWH(.41, .92, .18, .062),
    ]) {
      canvas.drawPath(
        _closedPath(PitchView.projectFieldRect(size, area)),
        line,
      );
    }
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
      oldDelegate.phone != phone;
}
