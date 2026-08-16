import 'dart:math' as math;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../profile/player_identity.dart';
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

/// The Team Lineup share card: a tactical board, not a screenshot.
///
/// **Chalk on a dark ground.** The pitch is *drawn* — white line work on a
/// blue-black field, with the markings a real pitch has: touchlines, a halfway
/// line and centre circle, a penalty area, a goal area, a penalty spot and arc
/// and a goal at each end. It is not a green rectangle with a tint, because a
/// filled green box is the one thing every template in this category already
/// is. The geometry is the football identity; the colour is not.
///
/// **The community is the subject and Go Play is the signature.** The largest
/// text on the card names whose teams these are; the product signs the bottom
/// edge at a fifth of that size. The fixture, where it exists, is one quiet
/// line between them.
///
/// **Composed at card scale.** Earlier versions laid the pitch out at a phone's
/// width and enlarged it, which made every stroke and every type size a
/// consequence of a scale factor rather than a decision. Here the pitch is
/// built in the engine's own 1080×1920 units, so a 5px line is 5px in the file
/// that leaves the phone — thick enough to survive what a messaging app does to
/// a picture. A `scaleDown` remains as a safety valve for a lineup with more
/// rows than the frame can hold; it never scales anything up.
///
/// **The formation is the app's, the presentation is the card's.**
/// [buildFormation] decides the rows, the wrapping and who is drawn out of
/// their line — none of that is restated here. What this card does not reuse is
/// `PlayerCard`: that widget belongs to the Teams screen, is capped at 82
/// logical pixels and is styled for a phone, so the card composes its own mark
/// from the same formation data rather than changing a shared widget.
///
/// **Its own theme, pinned.** [PlayerAvatar] falls back to a `CircleAvatar`,
/// which takes its colours from the ambient scheme; without pinning, a reader
/// in dark mode would share a different picture of the same lineup.
///
/// **Presentation only.** It takes [TeamLineupCardData] and draws it: no
/// repository, no formation decision of its own, no statistic invented.
class TeamLineupCard extends StatelessWidget {
  const TeamLineupCard({super.key, required this.data});

  final TeamLineupCardData data;

  // --- the Chalk palette ------------------------------------------------------

  /// A blue-black ground rather than a green one. Green stops being the card's
  /// identity and becomes what it is on a real graphic: one accent, spent on
  /// the data.
  static const _ground = Color(0xFF0B1014);
  static const _groundDeep = Color(0xFF070A0D);

  /// The line work. Chalk, not paint.
  static const _chalk = Color(0xFFFFFFFF);

  /// Reserved for figures and the brand tick, and used nowhere else.
  static const _accent = Color(0xFF3DDC84);

  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0x8CFFFFFF);

  /// The safe margin. Everything the reader must read lives inside it.
  static const _margin = 80.0;

  /// The pitch, in the engine's own units. 920 × 1440 is a shade under a real
  /// pitch's 68:105, which keeps it recognisable as a pitch rather than a
  /// portrait box that happens to have lines on it.
  static const _pitchWidth = 920.0;
  static const _pitchHeight = 1440.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final context_ = _matchContext(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_ground, _groundDeep],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_margin, _margin, _margin, _margin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.communityName case final String name) ...[
              _Subject(name: name),
              const SizedBox(height: 18),
              Container(width: 120, height: 6, color: _accent),
            ],
            if (context_ != null) ...[
              const SizedBox(height: 18),
              Text(
                context_,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _inkMuted,
                  fontSize: 34,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
            const SizedBox(height: 44),
            Expanded(child: _Pitch(data: data)),
            const SizedBox(height: 36),
            _Signature(label: l10n.appName),
          ],
        ),
      ),
    );
  }

  /// The fixture, as one line, or null when there is nothing worth writing.
  ///
  /// Built from the app's own match wording rather than a format invented here,
  /// so a lineup card and a match card cannot describe the same fixture two
  /// different ways. The location joins on the same separator the helper
  /// already uses between the day and the clock.
  String? _matchContext(BuildContext context) {
    final parts = <String>[
      if (data.startAt case final DateTime start)
        if (data.endAt case final DateTime end)
          formatDayAndTimeRange(context, start, end)
        else
          formatMatchDay(context, start),
      if (data.location case final String place)
        if (place.trim().isNotEmpty) place.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }
}

/// Whose teams these are. The largest thing on the card.
class _Subject extends StatelessWidget {
  const _Subject({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    // Scaled down rather than clipped: a long community name is still that
    // community's name. No letter-spacing — the name may be Arabic, where
    // tracking breaks the cursive joins.
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: TeamLineupCard._ink,
              fontSize: 88,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }
}

/// The product's signature: a tick of accent and the name, once, at the bottom.
class _Signature extends StatelessWidget {
  const _Signature({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 24, color: TeamLineupCard._accent),
        const SizedBox(width: 14),
        Text(
          label.toUpperCase(),
          // A name, not a sentence: it reads left to right in both languages,
          // and Latin capitals are the one place tracking is safe.
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            color: TeamLineupCard._inkMuted,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
        ),
      ],
    );
  }
}

/// The pitch: the card's dominant mass.
///
/// A fixed 920 × 1440 box so the markings hold a pitch's proportions whatever
/// the lineup is, with the rows sharing the height between them. `scaleDown`
/// only ever shrinks — a lineup with more rows than the frame can hold gives up
/// size rather than running off the bottom of the picture.
class _Pitch extends StatelessWidget {
  const _Pitch({required this.data});

  final TeamLineupCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Theme(
        data: theme.copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1B7A43),
            brightness: Brightness.light,
          ),
        ),
        child: SizedBox(
          width: TeamLineupCard._pitchWidth,
          height: TeamLineupCard._pitchHeight,
          child: CustomPaint(
            painter: _ChalkPitchPainter(),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
                  child: Column(
                    children: [
                      // Team A defends the top goal, so its rows run the other
                      // way: the goal first and the attack last, meeting Team
                      // B's attack at the halfway line.
                      ..._Half(
                        assignments: data.of(TeamId.a),
                        data: data,
                        towardsTop: true,
                      ).rows(),
                      ..._Half(
                        assignments: data.of(TeamId.b),
                        data: data,
                        towardsTop: false,
                      ).rows(),
                    ],
                  ),
                ),
                // On the grass, in the corners — clear of the penalty areas,
                // which occupy the middle 59% of each end.
                PositionedDirectional(
                  start: 26,
                  top: 22,
                  child: _TeamLabel(label: l10n.teamAName),
                ),
                PositionedDirectional(
                  start: 26,
                  bottom: 22,
                  child: _TeamLabel(label: l10n.teamBName),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One team's half of the pitch.
///
/// [towardsTop] is which goal the team defends. It reverses the row order and
/// nothing else: the formation itself — who is in attack, how the midfield
/// wraps, who is drawn out of their line — is [buildFormation]'s and is not
/// touched.
class _Half {
  const _Half({
    required this.assignments,
    required this.data,
    required this.towardsTop,
  });

  final List<TeamAssignment> assignments;
  final TeamLineupCardData data;
  final bool towardsTop;

  List<Widget> rows() {
    final formation = buildFormation(
      assignments,
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

    final ordered = towardsTop ? lines.reversed.toList() : lines;
    return [
      for (final line in ordered)
        Expanded(
          child: _PitchLine(
            line: line,
            data: data,
            movedFrom: formation.movedFrom,
          ),
        ),
    ];
  }
}

/// One line of the pitch. The players spread evenly across it, so the shape of
/// the row is the shape of the line.
class _PitchLine extends StatelessWidget {
  const _PitchLine({
    required this.line,
    required this.data,
    required this.movedFrom,
  });

  final List<TeamAssignment> line;
  final TeamLineupCardData data;
  final Map<String, Position> movedFrom;

  /// The room one mark gets, so a long name ellipsizes inside its own share of
  /// the line instead of running into the player beside it.
  ///
  /// Without a bound the name is measured unconstrained — `scaleDown` then
  /// shrinks the whole mark rather than trimming the text, and four long names
  /// across a defensive line meet in the middle with no gutter between them.
  /// Capped, because a lone goalkeeper should not be given the width of the
  /// pitch to write a name across.
  double _markWidth() {
    const usable = TeamLineupCard._pitchWidth - 32;
    const gutter = 18.0;
    return math.min(320, usable / line.length - gutter);
  }

  @override
  Widget build(BuildContext context) {
    final width = _markWidth();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final assignment in line)
          // Each line shrinks on its own where a dense formation gives it less
          // height than a mark needs, so one crowded row never costs the whole
          // pitch its size.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: width,
              child: _PlayerMark(
                assignment: assignment,
                player: data.players[assignment.participantId],
                // Resolved by the screen. A dash for somebody neither the
                // profiles nor the roster knows.
                name: data.names[assignment.participantId] ?? '—',
                movedFrom: movedFrom[assignment.participantId],
              ),
            ),
          ),
      ],
    );
  }
}

/// One player on the board: their face, their name and what they are rated.
///
/// The card's own mark rather than `PlayerCard`, which the Teams screen owns
/// and which is built for a phone. The rating rides the ring around the photo —
/// the arc's sweep is the rating — so a figure the product already has becomes
/// the ornament instead of a second number competing with the name.
class _PlayerMark extends StatelessWidget {
  const _PlayerMark({
    required this.assignment,
    required this.player,
    required this.name,
    this.movedFrom,
  });

  final TeamAssignment assignment;

  /// Null for somebody who left the match after the lineup was stored, and for
  /// a Professional Guest. They are still drawn — `KB-017` records that they
  /// played — with what is left of them.
  final PlayerCoreInputs? player;

  final String name;
  final Position? movedFrom;

  /// The photo's radius, in card units.
  static const _radius = 46.0;

  /// Room for the ring outside it.
  static const _ring = 7.0;

  @override
  Widget build(BuildContext context) {
    final rating = player?.overallRating;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: (_radius + _ring) * 2,
          height: (_radius + _ring) * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The ring is drawn only where there is a rating to draw. A guest
              // holds no rating and is not given a hollow one.
              if (rating != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RatingRingPainter(rating: rating),
                  ),
                ),
              PlayerAvatar(
                avatarUrl: player?.avatarUrl,
                // The initials come from the **profile**, not from the name
                // the screen resolved. Somebody who left the match after the
                // lineup was stored has no profile, and their resolved name is
                // a dash — lettering the disc with it would draw that dash
                // twice, once in the circle and once under it. No profile, no
                // initials: the avatar falls back to its figure instead.
                fullName: player?.fullName,
                isProfessionalGuest: assignment.isProfessionalGuest,
                radius: _radius,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: TeamLineupCard._ink,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1.15,
            // No letter-spacing: these names are Arabic as often as not.
            shadows: [Shadow(blurRadius: 6, color: Color(0xCC000000))],
          ),
        ),
        if (rating != null) ...[
          const SizedBox(height: 2),
          Text(
            rating.toStringAsFixed(1),
            // Western digits, as everywhere a rating is written in this
            // product.
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: TeamLineupCard._accent,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1.1,
              shadows: [Shadow(blurRadius: 6, color: Color(0xCC000000))],
            ),
          ),
        ],
        if (movedFrom case final Position position) ...[
          const SizedBox(height: 4),
          _MovedFromBadge(position: position),
        ],
      ],
    );
  }
}

/// The rating, as the ring around a player's photograph.
///
/// A full sweep is 10. The track behind it is what makes a low rating read as a
/// short arc rather than as a missing one.
class _RatingRingPainter extends CustomPainter {
  const _RatingRingPainter({required this.rating});

  final double rating;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 3,
    );

    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = TeamLineupCard._chalk.withValues(alpha: 0.22),
    );

    final sweep = (rating.clamp(0, 10) / 10) * 2 * math.pi;
    if (sweep <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = TeamLineupCard._accent,
    );
  }

  @override
  bool shouldRepaint(covariant _RatingRingPainter oldDelegate) =>
      oldDelegate.rating != rating;
}

/// The position a player actually holds, on a mark the drawing has moved.
///
/// The same statement `PitchView` makes on the phone, at the card's scale: the
/// arrow is what turns a position name into "they belong a line above this".
class _MovedFromBadge extends StatelessWidget {
  const _MovedFromBadge({required this.position});

  final Position position;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: TeamLineupCard._chalk.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: TeamLineupCard._chalk.withValues(alpha: 0.30),
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.north, size: 18, color: TeamLineupCard._inkMuted),
          const SizedBox(width: 4),
          Text(
            positionLabelOf(l10n, position),
            maxLines: 1,
            style: const TextStyle(
              color: TeamLineupCard._inkMuted,
              fontSize: 21,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Which side a half belongs to, written in the corner of the pitch.
class _TeamLabel extends StatelessWidget {
  const _TeamLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 4, height: 22, color: TeamLineupCard._accent),
        const SizedBox(width: 12),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: TeamLineupCard._ink,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.1,
            // No tracking: `teamAName` is "الفريق أ" in Arabic.
            shadows: [Shadow(blurRadius: 6, color: Color(0xCC000000))],
          ),
        ),
      ],
    );
  }
}

/// A pitch, drawn in chalk.
///
/// Real markings in real proportions, taken from a 68 × 105 metre pitch: the
/// penalty area is 40.3 × 16.5, the goal area 18.3 × 5.5, the centre circle
/// 9.15 in radius and the penalty spot 11 from the goal line. Getting these
/// right is most of what separates a football graphic from a rectangle with a
/// circle in it.
///
/// **No fill and no stripes.** The ground shows through, so the pitch is line
/// work over the card rather than a panel sitting on it. Strokes are 4–6px in
/// the engine's own units, which is what survives a messaging app's
/// re-compression; a hairline would not.
class _ChalkPitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final touchline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = TeamLineupCard._chalk.withValues(alpha: 0.38);

    final marking = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = TeamLineupCard._chalk.withValues(alpha: 0.26);

    final field = Rect.fromLTWH(0, 0, size.width, size.height).deflate(3);
    final w = field.width;
    final h = field.height;

    canvas.drawRect(field, touchline);

    // The halfway line and the centre circle, where the two teams meet.
    final middle = field.center.dy;
    canvas.drawLine(
      Offset(field.left, middle),
      Offset(field.right, middle),
      marking,
    );
    canvas.drawCircle(Offset(field.center.dx, middle), w * 0.135, marking);
    canvas.drawCircle(
      Offset(field.center.dx, middle),
      5,
      Paint()..color = TeamLineupCard._chalk.withValues(alpha: 0.26),
    );

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
      canvas.drawCircle(
        spot,
        5,
        Paint()..color = TeamLineupCard._chalk.withValues(alpha: 0.26),
      );

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
          top ? edge - 14 : edge,
          goalWidth,
          14,
        ),
        touchline,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChalkPitchPainter oldDelegate) => false;
}
