import 'package:btge/btge.dart';

/// Domain Models for team generation (OP-3).
///
/// The vocabulary is the engine's own: `Position`, `TeamId`,
/// `AssignmentBasis`, `Player`, `MatchSettings` and `MatchHistory` come from
/// `package:btge`, which is pure Dart and knows nothing about any data
/// provider. They are the approved input and output contract of the
/// Engineering Specification §4 and §5, so restating them here would create a
/// second representation of the same entity — which OP-3 forbids.

/// The Core Player Inputs (§4.1) as the profile actually holds them.
///
/// [dateOfBirth] and [secondaryPosition] are nullable because the schema
/// allows them to be. Migration `0018` is explicit that the database must not
/// invent either: §4.3 rejects a missing input rather than substituting a
/// default, and that judgement belongs above the schema. So this model reports
/// what is stored, and what a missing input *means* is decided elsewhere.
class PlayerCoreInputs {
  const PlayerCoreInputs({
    required this.userId,
    required this.fullName,
    required this.overallRating,
    required this.primaryPosition,
    this.dateOfBirth,
    this.secondaryPosition,
    this.avatarUrl,
  });

  final String userId;

  /// Not an engine input. `KB-005` forbids the engine from seeing a name; it
  /// is carried so the application can say *who* a missing input belongs to.
  final String fullName;

  final double overallRating;
  final Position primaryPosition;
  final DateTime? dateOfBirth;

  /// A missing secondary is ordinary input, never an error (`BTGE-SC-6`).
  final Position? secondaryPosition;

  /// Not an engine input either, and for the same reason as [fullName]: the
  /// pitch shows a face beside a name, and `toPlayer` leaves both behind.
  final String? avatarUrl;

  /// True when the player names `GK` as primary or secondary — §10.1's
  /// **natural goalkeeper**, the same test the engine applies.
  ///
  /// The pitch reads it to decide whether a goalkeeper row exists at all: a
  /// squad with nobody who keeps goal does not field one, and drawing an empty
  /// goal would show a position the match did not have.
  bool get isNaturalGoalkeeper =>
      primaryPosition == Position.gk || secondaryPosition == Position.gk;

  /// Whether every input §4.1 marks required is present.
  ///
  /// Only the date of birth can be absent: rating and primary position are
  /// `NOT NULL` in the schema, and a secondary position is not required.
  bool get hasEveryRequiredInput => dateOfBirth != null;

  /// The engine's view of this player (§4.1).
  ///
  /// Throws [StateError] when a required input is absent — the engine must
  /// never be handed an invented one (§4.3). Check [hasEveryRequiredInput]
  /// first; the repository does, and turns the absence into a `Failure`.
  Player toPlayer() {
    final birth = dateOfBirth;
    if (birth == null) {
      throw StateError(
        'Player $userId has no date of birth. §4.3 rejects a missing Core '
        'Player Input rather than substituting a default.',
      );
    }
    return Player(
      id: userId,
      overallRating: overallRating,
      dateOfBirth: birth,
      primaryPosition: primaryPosition,
      secondaryPosition: secondaryPosition,
    );
  }
}

/// One player's place in the lineup stored for a match — the persisted form
/// of §5.1.
///
/// `KB-017` decides what this records: the lineup that **actually played**,
/// including any manual change the organizer made after generation. It is a
/// record of reality, not of the engine's proposal.
class TeamAssignment {
  const TeamAssignment({
    required this.team,
    required this.assignedPosition,
    required this.basis,
    this.userId,
    this.professionalGuestId,
    this.teamManuallyOverridden = false,
  });

  /// The engine's output for one player, as a lineup that can be stored.
  ///
  /// Always a registered user: the engine never sees a Professional Guest
  /// (`BTGE` takes only community players), so nothing it returns can be one.
  TeamAssignment.fromAssignment(PlayerAssignment assignment)
      : userId = assignment.playerId,
        professionalGuestId = null,
        team = assignment.team,
        assignedPosition = assignment.assignedPosition,
        basis = assignment.basis,
        teamManuallyOverridden = false;

  /// Null when this lineup row belongs to a Professional Guest.
  final String? userId;

  /// Null when this lineup row belongs to a registered user. Exactly one of the
  /// two is set, which is the CHECK constraint the table carries.
  final String? professionalGuestId;

  bool get isProfessionalGuest => professionalGuestId != null;

  /// Whichever identity this row carries — the key every screen groups by.
  String get participantId => userId ?? professionalGuestId!;

  /// `A` or `B`, carrying no meaning beyond distinguishing the two sides
  /// (`KB-D6`).
  final TeamId team;

  /// Where they played — optional for a Professional Guest.
  ///
  /// A registered player always has one: the engine names a position for
  /// everybody it places, and the database requires it of any lineup row naming
  /// a user (`0051`).
  ///
  /// For a guest it is optional, and the two cases are different statements. In
  /// an ordinary roster-derived lineup it is null, because a guest has no
  /// profile for a position to be derived against and nothing invents one for
  /// them: null is the **absence** of a position rather than an unknown one. A
  /// completed-match correction, where the organizer states the position the
  /// guest actually played (migration `0075`), records that position here —
  /// evidence about the match, still not a claim about the player's profile.
  /// The field stays nullable because both cases are real.
  ///
  /// `Position` gains no fifth value for this. It is `package:btge`'s enum, and
  /// a participant the engine never sees must not widen the engine's
  /// vocabulary — the same reasoning that made [basis] nullable below.
  final Position? assignedPosition;

  /// Which rule produced [assignedPosition] — or null for a Professional
  /// Guest.
  ///
  /// §5.1 defines the basis against the player's profile: PRIMARY and SECONDARY
  /// name the field it came from, TRANSITION is the out-of-position marker. A
  /// guest has no profile, so none of the three is true of them. The database
  /// stores `GUEST` for exactly that case and it is read as null here, because
  /// `AssignmentBasis` belongs to `package:btge` and the engine has no such
  /// concept — inventing one there would be a change to the engine for a
  /// participant it never sees.
  final AssignmentBasis? basis;

  /// §5.1 defines Out of Position as exactly `basis == transition`. It is
  /// derived rather than stored, so the two can never disagree — which is why
  /// migration `0018` left the column out. A guest is never out of position:
  /// there is no position of theirs to be out of.
  bool get outOfPosition => basis == AssignmentBasis.transition;

  /// Whether an organizer chose this row's [team] by hand.
  ///
  /// It exists for Professional Guests. A guest is not an engine input, so
  /// nothing generates a side for them: `assign_professional_guest_teams`
  /// alternates them A, B, A, B by the order they were added, and re-runs that
  /// alternation on every lineup write. Without a record that a side was
  /// *chosen*, a guest moved by hand was put straight back by the next save.
  /// This is that record, and migration `0058` is where the alternation learns
  /// to leave it alone.
  ///
  /// False for a community player, always. Their side is the engine's output
  /// and their manual moves are already authoritative — there is nothing
  /// re-deriving it afterwards for a flag to protect them from. The column
  /// carries false for them because the column is not nullable, not because
  /// anything reads it.
  ///
  /// Reset by Generate/Regenerate: a fresh search discards what was adjusted
  /// around the previous one (`BTGE-MO-2`), and the guests re-alternate around
  /// the new teams.
  final bool teamManuallyOverridden;

  /// The same participant, on the other side.
  ///
  /// The whole of a move: `KB-D6` says the two labels distinguish the sides and
  /// carry nothing else, so nothing but [team] changes — the position, the
  /// basis and above all the **identity** are carried across untouched.
  ///
  /// This exists because the identity is the easy thing to lose. Rebuilding an
  /// assignment field by field to move it drops whichever of [userId] and
  /// [professionalGuestId] the author forgot, and for a guest that produced a
  /// row naming nobody — which the table's XOR check refuses and which no test
  /// covered, because the move was never offered for a guest in the first
  /// place. Copying and changing one field cannot express that mistake.
  TeamAssignment movedToOtherTeam({bool manualOverride = false}) =>
      TeamAssignment(
        userId: userId,
        professionalGuestId: professionalGuestId,
        team: team == TeamId.a ? TeamId.b : TeamId.a,
        assignedPosition: assignedPosition,
        basis: basis,
        // A community player's row keeps false: the flag governs the guest
        // alternation, and nothing re-derives a player's side.
        teamManuallyOverridden:
            isProfessionalGuest ? manualOverride : teamManuallyOverridden,
      );

  /// The same participant with a different [assignedPosition].
  ///
  /// Identity-preserving for the same reason as [movedToOtherTeam], and the
  /// side is what stays put here.
  TeamAssignment withPosition(Position position, AssignmentBasis? basis) =>
      TeamAssignment(
        userId: userId,
        professionalGuestId: professionalGuestId,
        team: team,
        assignedPosition: position,
        basis: basis,
        teamManuallyOverridden: teamManuallyOverridden,
      );
}

/// The engine's input contract (§4), assembled from what the schema holds.
///
/// These are the three arguments `BtgeEngine.generate` takes and nothing more.
/// Running the engine is a later milestone; this is the seam it will plug
/// into.
class GenerationInputs {
  const GenerationInputs({
    required this.players,
    required this.settings,
    required this.history,
  });

  /// The generation set (§4.1), one entry per player, ids unique (§4.3).
  final List<Player> players;

  /// Contextual input (§4.2) — the date age is computed as of.
  final MatchSettings settings;

  /// Auxiliary Data (§4.2.1). Empty is the approved `BTGE-DV-5` path, never an
  /// error.
  final MatchHistory history;
}


/// What a completed-match correction says about one player.
///
/// Two actions and no third: either this player played, in which case the
/// record says where, or they did not, in which case there is nothing left to
/// say about them.
enum CompletedPlayerAction { upsert, remove }

/// One statement about one player in the record of a match that has been
/// played, for migration `0074`'s batch correction.
///
/// Several of these are applied together as a single correction: the database
/// validates all of them, projects the lineup they add up to, and recalculates
/// the match's ratings and statistics once from that lineup. A list of these is
/// therefore the whole intent of one edit, not a queue of separate edits.
///
/// The two constructors exist so that the shape cannot be got wrong: a player
/// who played has both a side and a position, and a player who did not has
/// neither. [AssignmentBasis] is deliberately absent — §5.1 makes it a fact
/// about the player's profile, so the database derives it where that profile is
/// authoritative.
class CompletedPlayerCorrection {
  /// This player played, on [team], at [position].
  ///
  /// Also how a player already in the lineup is moved: the lineup row says
  /// where somebody played, and correcting it is that statement made again.
  const CompletedPlayerCorrection.played(
    this.userId, {
    required TeamId this.team,
    required Position this.position,
  }) : action = CompletedPlayerAction.upsert;

  /// This player did not play after all, so the lineup row and the roster seat
  /// both go.
  const CompletedPlayerCorrection.removed(this.userId)
      : action = CompletedPlayerAction.remove,
        team = null,
        position = null;

  /// The community player this correction is about.
  final String userId;

  /// Whether the player is being placed in the lineup or taken out of it.
  final CompletedPlayerAction action;

  /// The side they played on. Null exactly when they are being removed.
  final TeamId? team;

  /// Where they played. Null exactly when they are being removed.
  final Position? position;
}
