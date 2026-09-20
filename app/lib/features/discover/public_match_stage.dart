import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../teams/match_stage_board.dart';
import '../teams/team_models.dart';
import 'discover_models.dart';

/// A completed match a visitor is reading, drawn the way this product draws a
/// completed match.
///
/// **The defect this closes.** A guest opened a played match onto a white
/// sheet with two name lists under a pair of score cards, while a member
/// opened the same match onto the pitch: the ground, the two elevens, the
/// goals on the players, the MVP mark. Two audiences were looking at the same
/// football and seeing two different products.
///
/// **The contracts stay apart; only the drawing is shared.** This adapts the
/// public read into the presentation model [MatchStageBoard] already takes,
/// and [PublicCompletedMatch] is not mentioned anywhere inside the stage. No
/// public field is invented and none is borrowed from the member's read:
///
///   * **the rating is absent, and stays absent.** A rating is not public, so
///     `ratingOf` is left null and the cards simply carry no rating mark --
///     rather than a zero, which would be a claim;
///   * **the goalkeeper row is decided from the lineup that was stored.** The
///     member's route asks the *profiles* whether anybody keeps goal (§10.1),
///     and the public contract has no profiles; what it does have is where
///     each player actually stood, so a goalkeeper position in the stored
///     lineup is what puts a goalkeeper on the pitch here;
///   * **a name leads somewhere exactly when the page it leads to exists.**
///     `playerId` is published only for a registered player whose public
///     profile is available -- the database decides that -- and a tap does
///     nothing for anybody else.
///
/// It is read-only by construction: there is no management action to expose
/// because this widget takes none.
class PublicMatchStage extends StatelessWidget {
  const PublicMatchStage({
    super.key,
    required this.match,
    this.onOpenPlayer,
  });

  final PublicCompletedMatch match;

  /// Where a registered player's name leads. Null leaves every card inert.
  final void Function(String playerId)? onOpenPlayer;

  /// A stable key per lineup row, and which side of [TeamAssignment] it goes
  /// on.
  ///
  /// A registered player whose profile is not published still played, and is
  /// still a registered player: they keep a user id so the pitch draws them as
  /// one. The id is synthetic in that case and is never handed to navigation
  /// -- [_profileIds] decides that separately, from the published `playerId`
  /// alone.
  static String _participantId(PublicLineupEntry entry, int index) =>
      entry.playerId ??
      (entry.isProfessionalGuest ? 'guest-$index' : 'player-$index');

  List<TeamAssignment> get _lineup => [
        for (final (index, entry) in match.lineup.indexed)
          TeamAssignment(
            team: entry.team == 'A' ? TeamId.a : TeamId.b,
            assignedPosition: _positionOf(entry.assignedPosition),
            // `AssignmentBasis` belongs to the engine, and the engine never
            // saw this match. Null is what the member's route stores for a
            // row it cannot attribute either.
            basis: null,
            userId:
                entry.isProfessionalGuest ? null : _participantId(entry, index),
            professionalGuestId:
                entry.isProfessionalGuest ? _participantId(entry, index) : null,
          ),
      ];

  static Position? _positionOf(String? stored) => switch (stored) {
        'GK' => Position.gk,
        'DEF' => Position.def,
        'MID' => Position.mid,
        'FWD' => Position.fwd,
        _ => null,
      };

  Map<String, PublicLineupEntry> get _byParticipant => {
        for (final (index, entry) in match.lineup.indexed)
          _participantId(entry, index): entry,
      };

  /// Only the ids the contract actually published, so a tap can never reach a
  /// profile the database declined to make public.
  Map<String, String> get _profileIds => {
        for (final (index, entry) in match.lineup.indexed)
          if (entry.playerId != null)
            _participantId(entry, index): entry.playerId!,
      };

  /// Whether the stored lineup fielded a goalkeeper.
  bool get _hasGoalkeeper =>
      match.lineup.any((e) => e.assignedPosition == 'GK');

  @override
  Widget build(BuildContext context) {
    final entries = _byParticipant;
    final profiles = _profileIds;
    final open = onOpenPlayer;

    return MatchStageBoard(
      lineup: _lineup,
      // The public read produces no profile objects; the two callbacks below
      // carry everything the cards need.
      players: const {},
      nameOf: (id) => entries[id]?.displayName ?? '—',
      avatarUrlOf: (id) => entries[id]?.avatarUrl,
      // Deliberately absent: see the class comment.
      ratingOf: null,
      hasNaturalGoalkeeper: _hasGoalkeeper,
      communityName: match.communityName,
      matchTitle: match.title,
      playedAt: match.startAt,
      teamAScore: match.teamAScore,
      teamBScore: match.teamBScore,
      goalsOf: (id) => entries[id]?.goals ?? 0,
      isMvpOf: (id) => entries[id]?.isMvp ?? false,
      onTapPlayer: open == null
          ? null
          : (assignment) {
              final playerId = profiles[assignment.participantId];
              if (playerId != null) open(playerId);
            },
    );
  }
}
