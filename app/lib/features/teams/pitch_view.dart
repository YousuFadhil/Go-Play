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

  static const phonePitchWidth = 350.0;
  static const phoneAspectRatio =
      shareBeforePitchWidth / shareBeforePitchHeight;
  static const phonePitchHeight = phonePitchWidth / phoneAspectRatio;
  static const phoneAvatarDiameter = 50 * phonePitchWidth / 842.09;

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

    return AspectRatio(
      aspectRatio: shareBeforeAspectRatio,
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
            final slots = isApprovedSeven
                ? _exactSevenSlots(size, team)
                : _formationSlots(size, rows);
            final dense = visible.length >= 9;

            return CustomPaint(
              painter: const _PerspectivePitchPainter(),
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
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
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
  }) {
    final markerWidth = (dense ? 118.0 : 228.0) * slot.scale;
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
          (presentation == PitchPresentation.phone ? 50.0 : 50.0) * sx,
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
  const _PlayerSlot(this.center, this.avatarDiameter, this.scale);

  final Offset center;
  final double avatarDiameter;
  final double scale;
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
  final bool dense;
  final PitchPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final sx = layoutScale;
    final badgeScale = dense ? sx * .84 : sx;
    final compact = presentation == PitchPresentation.phone;
    final avatarUrl = player?.avatarUrl;
    final guest = assignment.isProfessionalGuest;
    final nameTop = avatarDiameter + (compact ? 3 : 4) * sx;
    final nameHeight = (dense ? 18 : 20) * sx;
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
                      color: MatchStage.accent.withValues(alpha: .78),
                      width: math.max(1, 1.6 * sx),
                    ),
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
              left: (dense ? 24 : 64) * sx,
              top: avatarDiameter - 20 * badgeScale,
              child: _RatingBadge(
                participantId: assignment.participantId,
                rating: player!.overallRating,
                scale: badgeScale,
              ),
            ),
          if (goals > 0)
            Positioned(
              right: (dense ? 22 : 44) * sx,
              top: -2 * badgeScale,
              child: _GoalBadge(
                participantId: assignment.participantId,
                goals: goals,
                scale: badgeScale,
              ),
            ),
          if (isMvp)
            Positioned(
              right: (dense ? 22 : 44) * sx,
              top: (goals > 0 ? 20 : -2) * badgeScale,
              child: _MvpBadge(
                participantId: assignment.participantId,
                scale: badgeScale,
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
                fontSize: (dense ? 14 : 15) * sx,
                fontWeight: FontWeight.w700,
                height: 1,
                shadows: const [
                  Shadow(color: Color(0x99000000), blurRadius: 2),
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
        constraints: BoxConstraints(minWidth: 42 * scale),
        height: 22 * scale,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 6 * scale),
        decoration: BoxDecoration(
          color: MatchStage.rating.withValues(alpha: .90),
          borderRadius: BorderRadius.circular(11 * scale),
          border: Border.all(
            color: MatchStage.inkMuted.withValues(alpha: .55),
            width: math.max(.6, .8 * scale),
          ),
        ),
        child: Text(
          rating.toStringAsFixed(1),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: MatchStage.ink,
            fontSize: 14 * scale,
            fontWeight: FontWeight.w600,
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
          color: MatchStage.ground.withValues(alpha: .82),
          shape: BoxShape.circle,
          border: Border.all(
            color: MatchStage.star.withValues(alpha: .82),
            width: math.max(.6, .8 * scale),
          ),
        ),
        child: Icon(
          Icons.star_rounded,
          color: MatchStage.star,
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
        padding: EdgeInsets.symmetric(horizontal: 4 * scale),
        decoration: BoxDecoration(
          color: MatchStage.rating.withValues(alpha: .58),
          borderRadius: BorderRadius.circular(10 * scale),
          border: Border.all(
            color: MatchStage.goal.withValues(alpha: .82),
            width: math.max(.6, .8 * scale),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sports_soccer,
              color: MatchStage.goal,
              size: 13 * scale,
            ),
            if (goals > 1) ...[
              SizedBox(width: 2 * scale),
              Text(
                '$goals',
                style: TextStyle(
                  color: MatchStage.ink,
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ],
        ),
      );
}

class _PerspectivePitchPainter extends CustomPainter {
  const _PerspectivePitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = _closedPath(PitchView.projectFieldRect(
      size,
      const Rect.fromLTWH(0, 0, 1, 1),
    ));
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MatchStage.pitchLight, MatchStage.pitchDark],
        ).createShader(Offset.zero & size),
    );
    final stripe = Paint()..color = Colors.white.withValues(alpha: .035);
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
      ..color = MatchStage.pitchLine.withValues(alpha: .48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size.width * .0025);
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
  bool shouldRepaint(covariant _PerspectivePitchPainter oldDelegate) => false;
}
