/// Core input models — the approved input contract, Specification §4.
///
/// Nothing here knows about Supabase, PostgreSQL, Flutter, or any schema.
/// The database is an adapter layer implemented elsewhere.
library;

/// The position vocabulary. Specification `BTGE-HC-5`.
///
/// Positions lie on the pitch axis `GK — DEF — MID — FWD` (§9.2). The axis is
/// not a tactical model; it is the ordering amateur players recognise when
/// asked to fill in somewhere (`KB-C2`).
enum Position {
  gk('GK', 0),
  def('DEF', 1),
  mid('MID', 2),
  fwd('FWD', 3);

  const Position(this.code, this.axisIndex);

  /// Stable wire code. Matches the vocabulary already used by the app.
  final String code;

  /// Position on the pitch axis, used for transition distance.
  final int axisIndex;

  /// Steps along the pitch axis between two positions. Specification §9.2.
  int distanceTo(Position other) => (axisIndex - other.axisIndex).abs();

  static Position fromCode(String code) => Position.values.firstWhere(
        (p) => p.code == code,
        orElse: () => throw ArgumentError.value(code, 'code', 'Unknown position'),
      );
}

/// One player in the generation set.
///
/// Carries the four **Core Player Inputs** of §4.1 and nothing else. There is
/// deliberately no name, no role, no tenure and no community standing here:
/// `KB-005` forbids the engine from knowing them.
class Player {
  const Player({
    required this.id,
    required this.overallRating,
    required this.dateOfBirth,
    required this.primaryPosition,
    this.secondaryPosition,
  });

  /// Unique within the generation set (§4.3).
  final String id;

  /// Single scalar strength value. The scale is `OP-1` and is deliberately not
  /// fixed here — the engine treats rating as an opaque number and never
  /// assumes a range.
  final double overallRating;

  /// Age is always derived from this, never stored as a number (`KB-C7`).
  final DateTime dateOfBirth;

  final Position primaryPosition;

  /// May be absent. A missing secondary is normal input, never an error
  /// (`BTGE-SC-6`).
  final Position? secondaryPosition;

  /// Completed years between birth and [asOf]. Specification §15.
  int ageAt(DateTime asOf) {
    var age = asOf.year - dateOfBirth.year;
    final hadBirthday = asOf.month > dateOfBirth.month ||
        (asOf.month == dateOfBirth.month && asOf.day >= dateOfBirth.day);
    if (!hadBirthday) age -= 1;
    return age;
  }

  /// True when the player is a **natural goalkeeper** — `GK` as primary or
  /// secondary. Specification §10.1.
  bool get isNaturalGoalkeeper =>
      primaryPosition == Position.gk || secondaryPosition == Position.gk;

  @override
  String toString() => 'Player($id, ${primaryPosition.code}'
      '${secondaryPosition == null ? '' : '/${secondaryPosition!.code}'}, '
      'r=$overallRating)';
}

/// Contextual input. Specification §4.2.
class MatchSettings {
  const MatchSettings({required this.matchDate});

  /// Age is computed as of this date. Read in the device's local time,
  /// consistent with `DD-11` — the caller supplies it already resolved.
  final DateTime matchDate;
}

/// A past match, reduced to what Diversity is permitted to see.
///
/// Where a match was manually adjusted, this is the lineup that **actually
/// played** (`BTGE-AX-5`, `KB-017`) — reality, not learning.
class PastMatch {
  PastMatch({required this.playedAt, required Iterable<Set<String>> teams})
      : teams = List.unmodifiable(teams.map(Set<String>.unmodifiable));

  final DateTime playedAt;

  /// Player ids per team. Two teams in practice, but the shape does not
  /// constrain it.
  final List<Set<String>> teams;

  /// Unordered player-id pairs that were teammates in this match.
  Set<String> teammatePairs() {
    final pairs = <String>{};
    for (final team in teams) {
      final ids = team.toList()..sort();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          pairs.add('${ids[i]}|${ids[j]}');
        }
      }
    }
    return pairs;
  }
}

/// **Auxiliary Data.** Specification §4.2.1.
///
/// Not a player evaluation input (`KB-016`). It may be consulted only during
/// Diversity optimization (priority 5), only after priorities 1–4 are already
/// satisfied, and only as a deterministic tie-breaker. It must never influence
/// rating, position assignment, age balancing or team strength — the engine
/// enforces this structurally by passing history no further than the diversity
/// stage.
class MatchHistory {
  MatchHistory(Iterable<PastMatch> matches)
      : _matches = List.unmodifiable(
          matches.toList()..sort((a, b) => b.playedAt.compareTo(a.playedAt)),
        );

  const MatchHistory.empty() : _matches = const [];

  final List<PastMatch> _matches;

  bool get isEmpty => _matches.isEmpty;

  /// Pairs that appeared together inside the lookback window.
  ///
  /// [lastNMatches] and [within] are `OP-6` and are supplied by configuration —
  /// the engine never invents a window (`BTGE-DV-4`).
  Set<String> pairsInWindow({
    required DateTime asOf,
    int? lastNMatches,
    Duration? within,
  }) {
    var scoped = _matches;
    if (within != null) {
      final cutoff = asOf.subtract(within);
      scoped = scoped.where((m) => !m.playedAt.isBefore(cutoff)).toList();
    }
    if (lastNMatches != null && scoped.length > lastNMatches) {
      scoped = scoped.sublist(0, lastNMatches);
    }
    return scoped.fold(<String>{}, (acc, m) => acc..addAll(m.teammatePairs()));
  }
}

/// Team label. Carries no meaning beyond distinguishing the two sides
/// (`KB-D6`).
enum TeamId { a, b }

/// Which step of the assignment chain produced a position. Specification §5.1.
enum AssignmentBasis {
  /// Step 1 — the player's declared main position.
  primary,

  /// Step 2 — the declared secondary. Not penalised (`BTGE-PT-2`).
  secondary,

  /// Steps 3 and 4 — a logical fallback or an emergency placement. This is the
  /// only basis that counts as out-of-position.
  transition,
}

/// Which branch of §10 applied, counting natural goalkeepers.
enum GoalkeeperMode { none, single, even, surplus }
