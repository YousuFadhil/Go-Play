import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../teams/match_stage.dart';
import '../teams/pitch_view.dart';
import '../teams/team_models.dart';

/// Everything the shareable match card draws, resolved before it is drawn.
///
/// **The screen the reader is looking at, not a second read of it.** The Teams
/// screen has already loaded the lineup, the profiles behind it, the name each
/// participant is shown under and — where there is one — the result. All of it
/// arrives here and nothing is looked up again. The card holds no repository and
/// cannot acquire one.
///
/// [names] is the resolved display name per participant and is passed rather
/// than derived, for the reason `KB-017` gives: a player who left the community
/// after the lineup was stored still played, and the screen's rule for what to
/// call them is the one the picture must agree with.
@immutable
class MatchResultCardData {
  const MatchResultCardData({
    required this.lineup,
    required this.players,
    required this.names,
    this.teamAScore,
    this.teamBScore,
    this.goals = const {},
    this.mvpParticipantId,
    this.communityName,
    this.matchTitle,
    this.playedAt,
    this.hasNaturalGoalkeeper = true,
  });

  /// The stored lineup, both sides, exactly as the screen holds it.
  final List<TeamAssignment> lineup;

  /// The profiles behind them: the face and the rating each mark shows. A
  /// player with no entry left the match after the lineup was stored and is
  /// still drawn — `KB-017` records that they played — from the assignment
  /// alone.
  final Map<String, PlayerCoreInputs> players;

  /// Participant id to the name the screen shows for them.
  final Map<String, String> names;

  /// **Both null before a result exists.** That is the whole of the two states:
  /// the same card, with a score strip or without one. It is what lets the one
  /// Share button send whichever the reader is looking at.
  final int? teamAScore;
  final int? teamBScore;

  /// Goals per participant, and only for those who scored. Somebody absent from
  /// this map scored none — which is why a goalless match carries an empty map
  /// rather than a map of zeroes.
  final Map<String, int> goals;

  /// Who was best on the pitch, or null when nobody was named.
  final String? mvpParticipantId;

  final String? communityName;
  final String? matchTitle;
  final DateTime? playedAt;

  /// Whether the squad holds anybody who keeps goal (§10.1) — the screen's own
  /// answer, and the same test [PitchView] applies.
  final bool hasNaturalGoalkeeper;

  bool get hasResult => teamAScore != null && teamBScore != null;

  /// The side that won, or null when the match was drawn or has no result.
  TeamId? get winner {
    if (!hasResult || teamAScore == teamBScore) return null;
    return teamAScore! > teamBScore! ? TeamId.a : TeamId.b;
  }

  bool get isDraw => hasResult && teamAScore == teamBScore;

  List<TeamAssignment> of(TeamId team) => [
        for (final assignment in lineup)
          if (assignment.team == team) assignment,
      ];

  int goalsOf(String participantId) => goals[participantId] ?? 0;

  bool isMvp(String participantId) =>
      mvpParticipantId != null && mvpParticipantId == participantId;

  /// Whether there is anything to picture at all. An empty lineup is not a
  /// card, and the Share action is not offered for one.
  bool get isShareable => lineup.isNotEmpty;
}

/// The match, as a picture: the Teams screen with its navigation taken off.
///
/// **This is the approved direction, and it is deliberately not a poster.** Two
/// earlier versions invented a layout for the occasion — a scoreboard over name
/// lists, then a compact header over shrunken pitches on a pale page — and both
/// were rejected for the same reason. The application draws this match well
/// already; a picture of it that looks like something else is a picture of
/// somebody else's product. So the composition here is the screen's, built from
/// the screen's own widgets: [MatchStageHeader], [MatchStageSection] and
/// [PitchView], on [MatchStage.ground].
///
/// **What changes is the size, and only the size.** Everything is drawn through
/// one `scale`, solved below from the room the two pitches actually have, so the
/// faces on the card are as large as a 1080-wide canvas allows rather than as
/// small as a phone-sized widget happens to be. That is the correction the
/// rejected card needed: it drew players at phone scale in the middle of a large
/// pale margin.
///
/// **No controls.** The Share button belongs to the preview screen around this
/// picture, never inside it.
class MatchResultCard extends StatelessWidget {
  const MatchResultCard({super.key, required this.data});

  final MatchResultCardData data;

  static const sharePitchWidth = 842.09;
  static const shareBeforePitchHeight = 502.90;
  static const shareResultPitchHeight = 502.90;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final stagePresentation = data.hasResult
        ? MatchStagePresentation.shareResult
        : MatchStagePresentation.shareBeforeResult;
    final pitchPresentation = data.hasResult
        ? PitchPresentation.shareResult
        : PitchPresentation.shareBeforeResult;

    return LayoutBuilder(builder: (context, constraints) {
      final sx = constraints.maxWidth / MatchStage.referenceWidth;
      final sy = constraints.maxHeight / MatchStage.referenceHeight;
      final firstTop = data.hasResult ? 282.0 : 220.0;
      final secondTop = data.hasResult ? 903.0 : 855.0;

      return DecoratedBox(
        key: const ValueKey('match-card-background'),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF063126), MatchStage.ground],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              key: const ValueKey('share-header-ball-left'),
              top: -70 * sy,
              left: -115 * sx,
              child: Icon(
                Icons.sports_soccer,
                size: 255 * sx,
                color: Colors.white.withValues(alpha: .035),
              ),
            ),
            Positioned(
              key: const ValueKey('share-header-ball-right'),
              top: -95 * sy,
              right: -105 * sx,
              child: Icon(
                Icons.sports_soccer,
                size: 405 * sx,
                color: Colors.white.withValues(alpha: .045),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: constraints.maxWidth,
              height: (data.hasResult ? 265 : 170) * sy,
              child: MatchStageHeader(
                community: data.communityName,
                title: data.matchTitle,
                playedAt: data.playedAt,
                teamAScore: data.teamAScore,
                teamBScore: data.teamBScore,
                presentation: stagePresentation,
              ),
            ),
            Positioned(
              left: 21 * sx,
              top: firstTop * sy,
              width: 898 * sx,
              height: 607 * sy,
              child: _side(
                l10n.teamAName,
                TeamId.a,
                data.of(TeamId.a),
                stagePresentation,
                pitchPresentation,
              ),
            ),
            Positioned(
              left: 21 * sx,
              top: secondTop * sy,
              width: 898 * sx,
              height: 607 * sy,
              child: _side(
                l10n.teamBName,
                TeamId.b,
                data.of(TeamId.b),
                stagePresentation,
                pitchPresentation,
              ),
            ),
            Positioned(
              left: 0,
              top: 1538 * sy,
              width: constraints.maxWidth,
              height: 134 * sy,
              child: const _Signature(),
            ),
          ],
        ),
      );
    });
  }

  Widget _side(
    String title,
    TeamId team,
    List<TeamAssignment> assignments,
    MatchStagePresentation stagePresentation,
    PitchPresentation pitchPresentation,
  ) =>
      MatchStageSection(
        title: title,
        won: data.winner == team,
        team: team,
        presentation: stagePresentation,
        child: PitchView(
          assignments: assignments,
          players: data.players,
          // Everyone who played is drawn. The screen may leave a keeper out
          // when the squad names no natural goalkeeper (§10.1), which is a
          // judgement about a formation still to be played; a record of a match
          // that left somebody out would be wrong.
          hasNaturalGoalkeeper: data.hasResult || data.hasNaturalGoalkeeper,
          nameOf: (id) => data.names[id] ?? '—',
          goalsOf: data.hasResult ? data.goalsOf : null,
          isMvpOf: data.hasResult ? data.isMvp : null,
          presentation: pitchPresentation,
          team: team,
          pitchKey: ValueKey(
            team == TeamId.a ? 'team-a-pitch' : 'team-b-pitch',
          ),
        ),
      );
}

/// Exact 941×134 source footer, scaled only by its containing region.
class _Signature extends StatelessWidget {
  const _Signature();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final sx = constraints.maxWidth / MatchStage.referenceWidth;
          final sy = constraints.maxHeight / 134;
          return SizedBox.expand(
            key: const ValueKey('share-footer'),
            child: CustomPaint(
              painter: const _FooterPainter(),
              child: Stack(
                children: [
                  Positioned(
                    key: const ValueKey('share-footer-stripes-left'),
                    left: 54 * sx,
                    top: 35 * sy,
                    width: 237 * sx,
                    height: 48 * sy,
                    child: const CustomPaint(
                      painter: _StripeGroupPainter(),
                    ),
                  ),
                  Positioned(
                    key: const ValueKey('share-footer-stripes-right'),
                    left: 650 * sx,
                    top: 35 * sy,
                    width: 237 * sx,
                    height: 48 * sy,
                    child: const CustomPaint(
                      painter: _StripeGroupPainter(mirrored: true),
                    ),
                  ),
                  Positioned(
                    key: const ValueKey('share-footer-logo'),
                    left: 319 * sx,
                    top: 32 * sy,
                    width: 295 * sx,
                    height: 60 * sy,
                    child: const FittedBox(
                      fit: BoxFit.contain,
                      child: Row(
                        textDirection: TextDirection.ltr,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'G',
                            style: TextStyle(
                              color: MatchStage.accent,
                              fontSize: 66,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              height: 1,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 2),
                            child: Icon(
                              Icons.sports_soccer,
                              size: 56,
                              color: MatchStage.ink,
                            ),
                          ),
                          Text(
                            ' PLAY',
                            style: TextStyle(
                              color: MatchStage.ink,
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 1,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _StripeGroupPainter extends CustomPainter {
  const _StripeGroupPainter({this.mirrored = false});

  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final direction = mirrored ? -1.0 : 1.0;
    final origin = mirrored ? size.width : 0.0;
    for (var index = 0; index < 9; index++) {
      final progress = index / 8;
      final x = origin + direction * size.width * (.04 + progress * .88);
      final paint = Paint()
        ..color = MatchStage.accent.withValues(alpha: .62 - progress * .38)
        ..strokeWidth = size.height * .16
        ..strokeCap = StrokeCap.square;
      canvas.drawLine(
        Offset(x, size.height * .13),
        Offset(x + direction * size.width * .085, size.height * .87),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StripeGroupPainter oldDelegate) =>
      oldDelegate.mirrored != mirrored;
}

class _FooterPainter extends CustomPainter {
  const _FooterPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = MatchStage.accent.withValues(alpha: .28)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height * .08),
        Offset(size.width, size.height * .08), line);
    canvas.drawLine(Offset(0, size.height * .92),
        Offset(size.width, size.height * .92), line);
  }

  @override
  bool shouldRepaint(covariant _FooterPainter oldDelegate) => false;
}
