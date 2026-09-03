import 'package:btge/btge.dart';
import 'package:flutter/foundation.dart';

import '../teams/team_models.dart';
import 'football_models.dart';
import 'football_repository.dart';

/// A completed match, adapted once for drawing.
///
/// **This is the screen/domain boundary, and it only goes one way.** The public
/// football read models stay exactly what they are: [CompletedMatchDetail] is
/// not widened, [LineupSlot] gains nothing, and no column is read here that
/// `v_football_match_lineup` was not already sending. What is built is a
/// presentation view of what already arrived — the same lineup expressed in the
/// vocabulary the Match Stage draws in, so the public screen can show a match
/// the way the product shows a match.
///
/// **Nothing private crosses.** A [PlayerCoreInputs] is assembled only from
/// fields [FootballParticipant] already carries — the name, the picture, the two
/// positions and the Global Rating, all of them published by migration `0057`
/// to any signed-in reader. `dateOfBirth` is left null because the view does not
/// send one and a drawing has no use for one; the field exists for
/// [PlayerCoreInputs.toPlayer], which is the engine's door and is never opened
/// from here.
///
/// **Built once per load, used twice.** The board on screen and the picture the
/// Share button sends read the same instance, so what leaves the phone cannot
/// disagree with what the reader was looking at — and tapping Share issues no
/// read, because everything it needs was resolved when the match arrived.
@immutable
class CompletedMatchPresentation {
  const CompletedMatchPresentation({
    required this.lineup,
    required this.players,
    required this.names,
    required this.goals,
    required this.avatarUrls,
    required this.hasNaturalGoalkeeper,
    this.mvpParticipantId,
  });

  /// The stored lineup as the Match Stage understands it, both sides.
  final List<TeamAssignment> lineup;

  /// The profiles behind the registered players in it. A Professional Guest has
  /// no entry and cannot have one: they hold no account for any of these fields
  /// to come from.
  final Map<String, PlayerCoreInputs> players;

  /// Participant id to the name the match sheet gave them.
  final Map<String, String> names;

  /// Goals per participant, and only for those who scored. Somebody absent from
  /// this map scored none — which is why a goalless match carries an empty map
  /// rather than a map of zeroes.
  final Map<String, int> goals;

  /// Every picture the pitch will ask for, resolved so they can be fetched
  /// before a card is composed rather than while it is.
  final Set<String> avatarUrls;

  /// Whether anybody who played keeps goal — §10.1's natural goalkeeper, `GK`
  /// as primary or secondary. Read off the participants' own declared positions
  /// so a player whose rating did not survive the read still counts.
  final bool hasNaturalGoalkeeper;

  /// Who was best on the pitch, or null when nobody was named.
  final String? mvpParticipantId;

  /// Builds the presentation view of one completed match.
  factory CompletedMatchPresentation.of(CompletedMatchDetail detail) {
    final lineup = <TeamAssignment>[];
    final players = <String, PlayerCoreInputs>{};
    final names = <String, String>{};
    final goals = <String, int>{};
    final avatarUrls = <String>{};
    String? mvpParticipantId;
    var hasNaturalGoalkeeper = false;

    for (final slot in detail.lineup) {
      final participant = slot.participant;

      // Which of the two identities this row carries, decided the way the read
      // model decides it: a registered player is a `USER` row with a user id,
      // and everything else is somebody with no account to open. A row naming
      // neither is not a participant and is left out rather than drawn as one.
      final userId = participant.type == ParticipantType.user
          ? participant.userId
          : null;
      final guestId = userId == null ? participant.guestId : null;
      if (userId == null && guestId == null) continue;
      final participantId = userId ?? guestId!;

      lineup.add(TeamAssignment(
        userId: userId,
        professionalGuestId: guestId,
        team: slot.team == FootballTeam.a ? TeamId.a : TeamId.b,
        assignedPosition: _positionOf(slot.assignedPosition),
        // §5.1 defines Out of Position as exactly this basis, and the view
        // already carries the answer. The other two bases name which profile
        // field a position came from, which the public read does not say and
        // nothing on the pitch asks.
        basis: slot.isOutOfPosition ? AssignmentBasis.transition : null,
      ));

      names[participantId] =
          participant.displayName.isEmpty ? '—' : participant.displayName;

      final primary = _positionOf(participant.primaryPosition);
      final secondary = _positionOf(participant.secondaryPosition);
      if (primary == Position.gk || secondary == Position.gk) {
        hasNaturalGoalkeeper = true;
      }

      // A card shows a rating only where there is one to show. Both of these
      // are `NOT NULL` on a profile, so a registered player has them; a guest
      // has neither, and nothing invents either for them.
      final rating = participant.overallRating;
      if (userId != null && primary != null && rating != null) {
        players[participantId] = PlayerCoreInputs(
          userId: userId,
          fullName: names[participantId]!,
          overallRating: rating,
          primaryPosition: primary,
          secondaryPosition: secondary,
          avatarUrl: participant.avatarUrl,
        );
      }

      final avatarUrl = participant.avatarUrl;
      if (userId != null && avatarUrl != null) avatarUrls.add(avatarUrl);

      if (slot.goals > 0) goals[participantId] = slot.goals;
      if (slot.isMvp) mvpParticipantId = participantId;
    }

    // The lineup's own flag is the first authority, because it is keyed by the
    // participant the pitch draws. The match row is the fallback for a match
    // whose MVP was recorded without a lineup surviving to carry the mark.
    mvpParticipantId ??= _identityOf(detail.match.mvp);

    return CompletedMatchPresentation(
      lineup: lineup,
      players: players,
      names: names,
      goals: goals,
      avatarUrls: avatarUrls,
      hasNaturalGoalkeeper: hasNaturalGoalkeeper,
      mvpParticipantId: mvpParticipantId,
    );
  }

  /// Whether there is a stored lineup to draw. False is an ordinary state: a
  /// match can be played and recorded without one having survived.
  bool get hasLineup => lineup.isNotEmpty;

  /// What to call a participant. A dash stands for somebody the match sheet did
  /// not name, which is the same answer the Teams screen gives.
  String nameOf(String participantId) => names[participantId] ?? '—';

  int goalsOf(String participantId) => goals[participantId] ?? 0;

  bool isMvpOf(String participantId) =>
      mvpParticipantId != null && mvpParticipantId == participantId;
}

/// The engine's position, or null for anything else.
///
/// Deliberately tolerant where `positionFromDb` is strict. That one is reading a
/// CHECK-constrained column into a lineup that will be written back, so a value
/// outside the vocabulary is a schema disagreement worth failing on. This one is
/// deciding where to stand a face, and a guest's absent position (migration
/// `0051`) is the ordinary case rather than a fault — the pitch already draws a
/// card with no position, and a drawing is not worth failing a screen for.
Position? _positionOf(String? value) => switch (value) {
      'GK' => Position.gk,
      'DEF' => Position.def,
      'MID' => Position.mid,
      'FWD' => Position.fwd,
      _ => null,
    };

/// Whichever id a participant carries, or null when they carry neither.
String? _identityOf(FootballParticipant? participant) {
  if (participant == null) return null;
  if (participant.type == ParticipantType.user && participant.userId != null) {
    return participant.userId;
  }
  return participant.guestId;
}
