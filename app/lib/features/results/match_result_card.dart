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

  static const horizontalPadding = 40.0;
  static const sharePitchWidth = 950.0;
  static const shareBeforePitchHeight = 610.0;
  static const shareResultPitchHeight = 580.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final stagePresentation = data.hasResult
        ? MatchStagePresentation.shareResult
        : MatchStagePresentation.shareBeforeResult;
    final pitchPresentation = data.hasResult
        ? PitchPresentation.shareResult
        : PitchPresentation.shareBeforeResult;

    return DecoratedBox(
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
            top: -130,
            right: -125,
            child: Icon(
              Icons.sports_soccer,
              size: 430,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Positioned(
            top: -150,
            left: -150,
            child: Icon(
              Icons.sports_soccer,
              size: 410,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: data.hasResult ? 46 : 54),
                MatchStageHeader(
                  community: data.communityName,
                  title: data.matchTitle,
                  playedAt: data.playedAt,
                  teamAScore: data.teamAScore,
                  teamBScore: data.teamBScore,
                  presentation: stagePresentation,
                ),
                SizedBox(height: data.hasResult ? 20 : 26),
                _side(
                  l10n.teamAName,
                  TeamId.a,
                  data.of(TeamId.a),
                  stagePresentation,
                  pitchPresentation,
                ),
                SizedBox(height: data.hasResult ? 22 : 26),
                _side(
                  l10n.teamBName,
                  TeamId.b,
                  data.of(TeamId.b),
                  stagePresentation,
                  pitchPresentation,
                ),
                const Spacer(),
                SizedBox(
                  height: data.hasResult ? 100 : 120,
                  child: const _Signature(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
        ),
      );
}

/// The centered, secondary-weight share-card signature.
class _Signature extends StatelessWidget {
  const _Signature();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: Color(0x3845DF7C),
        ),
        Spacer(),
        Row(
          textDirection: TextDirection.ltr,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sports_soccer,
              size: 42,
              color: MatchStage.accent,
            ),
            SizedBox(width: 12),
            Text.rich(
              TextSpan(
                text: 'GO ',
                children: [
                  TextSpan(
                    text: 'PLAY',
                    style: TextStyle(color: MatchStage.ink),
                  ),
                ],
              ),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: MatchStage.accent,
                fontSize: 46,
                fontWeight: FontWeight.w800,
                fontStyle: FontStyle.italic,
                letterSpacing: -1,
                height: 1,
              ),
            ),
          ],
        ),
        Spacer(),
      ],
    );
  }
}
