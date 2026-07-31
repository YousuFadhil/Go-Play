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
    required this.userId,
    required this.team,
    required this.assignedPosition,
    required this.basis,
  });

  /// The engine's output for one player, as a lineup that can be stored.
  TeamAssignment.fromAssignment(PlayerAssignment assignment)
      : userId = assignment.playerId,
        team = assignment.team,
        assignedPosition = assignment.assignedPosition,
        basis = assignment.basis;

  final String userId;

  /// `A` or `B`, carrying no meaning beyond distinguishing the two sides
  /// (`KB-D6`).
  final TeamId team;

  final Position assignedPosition;
  final AssignmentBasis basis;

  /// §5.1 defines Out of Position as exactly `basis == transition`. It is
  /// derived rather than stored, so the two can never disagree — which is why
  /// migration `0018` left the column out.
  bool get outOfPosition => basis == AssignmentBasis.transition;
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
