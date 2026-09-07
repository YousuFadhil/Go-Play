import 'package:btge/btge.dart';

import 'team_of_period_models.dart';

/// Turns a period's evidence into the awarded team.
///
/// **Pure, and deliberately so.** Nothing here reads a clock, a profile, a
/// rating, a database or a widget: the same evidence produces the same team
/// every time, on any device, for every viewer. That is what makes the award a
/// property of the football rather than of who happened to open the screen —
/// and it is what lets migration `0070`'s correction-sensitivity be the *only*
/// way a closed award can change.
///
/// Two rules do most of the work and both are about not letting the wrong thing
/// vote:
///
///   * **Each played side is one observation of shape**, whatever its size, so
///     one eleven-a-side fixture cannot outvote a month of five-a-sides (§7.1).
///   * **A player is only ever awarded a position they actually played** —
///     their Period Primary, or their Period Secondary where that role ran
///     short. A shortage releases the seat rather than filling it with somebody
///     who never stood there (§11).
///
/// Structural nonsense in the evidence is a broken data contract and is thrown,
/// never repaired. A selector that quietly invented a formation when the shape
/// evidence did not add up would turn a bug in the read model into a plausible
/// wrong answer that nobody would ever look at twice.
abstract final class TeamOfPeriodSelector {
  /// Floating comparison tolerance.
  ///
  /// The shares are ratios of small integers and the deficits are differences
  /// of those, so two arithmetically equal values can differ in the last bit.
  /// Without a tolerance that noise would decide a tie — and the tie-break
  /// below exists precisely so the answer is decided by the football and then
  /// by a stated rule, not by binary representation.
  static const _epsilon = 1e-9;

  /// The most players an award may hold, however big the community's matches
  /// were.
  static const _maximumSquad = 11;

  /// Roles in the stable axis order every tie-break falls back to.
  static const _axis = [
    Position.gk,
    Position.def,
    Position.mid,
    Position.fwd,
  ];

  /// The awarded team for [window], chosen from [candidates].
  ///
  /// [candidates] may arrive in any order and in any number; the order of the
  /// input can never reach the output.
  static TeamOfPeriod select({
    required TeamOfPeriodWindow window,
    required List<TeamOfPeriodCandidate> candidates,
  }) {
    _validateWindow(window);

    // No football, no award, and nothing to derive it from. Asked before the
    // size and the shape, because both would be a median and a mean of nothing.
    if (window.qualifyingMatchCount == 0) {
      return TeamOfPeriod(
        window: window,
        state: TeamOfPeriodState.noQualifyingMatches,
        targetSize: 0,
        initialSlotCounts: _emptySlots(),
        finalSlotCounts: _emptySlots(),
        selected: const [],
      );
    }

    // The size and the shape are properties of the football that was played,
    // so they are derived before anybody is considered for selection. Who
    // turned out often enough to be eligible cannot change how big the sides
    // were or how they were filled -- which is why these are computed here
    // rather than inside the branch below, and why a period with nobody
    // eligible still reports the shape it actually had.
    final targetSize = targetSquadSize(window.teamSizeObservations);
    final shares = periodShares(window.positionShapeObservations);
    final initialSlots = allocateSlots(shares: shares, targetSize: targetSize);

    final eligible = [
      for (final candidate in candidates)
        if (candidate.eligible) candidate,
    ];

    // Matches were played and nobody played enough of them. The threshold is
    // the database's and is not lowered to manufacture a team.
    //
    // The initial shape is still reported and the final one is empty, because
    // that is the truth of it: the period asked for this team and no player
    // qualified to fill any of it. Reporting a shape of zeros would have said
    // the period had no shape, which is a different and false statement.
    if (eligible.isEmpty) {
      return TeamOfPeriod(
        window: window,
        state: TeamOfPeriodState.insufficientEligiblePlayers,
        targetSize: targetSize,
        initialSlotCounts: Map.unmodifiable(initialSlots),
        finalSlotCounts: _emptySlots(),
        selected: const [],
      );
    }

    // Ranked once, and every phase below reads this one order. Sorting per role
    // would be the same comparison run repeatedly; doing it once is also what
    // guarantees the input order cannot survive into the output.
    final ranked = [...eligible]..sort(compareCandidates);

    final assigned = <String, Position>{};
    final filled = {for (final role in _axis) role: 0};

    // Phase 1 -- Period Primary.
    //
    // A player has exactly one Period Primary, so no role can take a Primary
    // that another role was owed and the axis order is presentational rather
    // than consequential here.
    for (final role in _axis) {
      _fill(
        ranked: ranked,
        assigned: assigned,
        filled: filled,
        role: role,
        upTo: initialSlots[role]!,
        matches: (candidate) => candidate.periodPrimaryPosition == role,
      );
    }

    // Phase 2 -- Period Secondary.
    //
    // Only where a role's Primaries ran out. A Period Secondary exists only
    // because the player actually played there during the period; nothing
    // invents one from a profile.
    for (final role in _axis) {
      _fill(
        ranked: ranked,
        assigned: assigned,
        filled: filled,
        role: role,
        upTo: initialSlots[role]!,
        matches: (candidate) => candidate.periodSecondaryPosition == role,
      );
    }

    // Phase 3 -- the seats the shape asked for and the players could not fill.
    //
    // They are released rather than filled with somebody who never played the
    // role. Where they go instead is decided by the same proportional rule that
    // shaped the team, restricted to roles that still have a real Primary
    // candidate left -- so a shortage in one role deepens a role the period
    // actually played, and never conjures one it did not.
    while (assigned.length < targetSize) {
      final role = _reallocationRole(
        ranked: ranked,
        assigned: assigned,
        filled: filled,
        shares: shares,
        targetSize: targetSize,
      );
      if (role == null) break;

      _fill(
        ranked: ranked,
        assigned: assigned,
        filled: filled,
        role: role,
        upTo: filled[role]! + 1,
        matches: (candidate) => candidate.periodPrimaryPosition == role,
      );
    }

    final selected = [
      for (final candidate in ranked)
        if (assigned.containsKey(candidate.userId))
          TeamOfPeriodSelection(
            candidate: candidate,
            assignedPosition: assigned[candidate.userId]!,
          ),
    ]..sort((a, b) {
        // GK, DEF, MID, FWD, and the approved ranking within each role. Never
        // the sequence the phases happened to run in: a team that listed its
        // Secondary pick-ups last would be reporting how it was computed rather
        // than what it is.
        final axis = a.assignedPosition.axisIndex
            .compareTo(b.assignedPosition.axisIndex);
        return axis != 0 ? axis : compareCandidates(a.candidate, b.candidate);
      });

    return TeamOfPeriod(
      window: window,
      state: TeamOfPeriodState.selected,
      targetSize: targetSize,
      initialSlotCounts: Map.unmodifiable(initialSlots),
      finalSlotCounts: Map.unmodifiable(filled),
      selected: List.unmodifiable(selected),
    );
  }

  // --- Squad size ------------------------------------------------------------

  /// The median actual side size, `.5` rounded up, capped at eleven.
  ///
  /// Integer arithmetic throughout: `(a + b + 1) ~/ 2` is the mean of the two
  /// middle values with a half rounded up, and it cannot drift the way a double
  /// division and a `round()` can.
  ///
  /// The median rather than the mean, because one eleven-a-side fixture in a
  /// month of five-a-sides should not stretch the award to eight — `[5,5,5,11]`
  /// is a community that plays five-a-side and once played a big game.
  static int targetSquadSize(List<int> observations) {
    if (observations.isEmpty) return 0;

    final sorted = [...observations]..sort();
    final middle = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle] + 1) ~/ 2;

    return median > _maximumSquad ? _maximumSquad : median;
  }

  // --- Shape -----------------------------------------------------------------

  /// Each role's share of the period, as the mean of the per-side shares.
  ///
  /// **Every usable side counts once.** A side's share is computed within that
  /// side — three defenders out of six known players is a half — and the period
  /// share is the arithmetic mean of those. Weighting by team size or by how
  /// many players had a known position would hand the biggest fixture the
  /// loudest voice, which is the whole thing this avoids.
  ///
  /// Sides where nobody's position was recorded say nothing about shape and are
  /// skipped. They still counted toward the squad size, because they were still
  /// played.
  static Map<Position, double> periodShares(
    List<PositionShapeObservation> observations,
  ) {
    final usable = [
      for (final observation in observations)
        if (observation.hasKnownPositions) observation,
    ];
    if (usable.isEmpty) return {for (final role in _axis) role: 0};

    return {
      for (final role in _axis)
        role: usable.fold<double>(
              0,
              (total, observation) => total + observation.shareOf(role),
            ) /
            usable.length,
    };
  }

  /// [targetSize] seats distributed across the roles the period actually
  /// played.
  ///
  /// Largest-remaining-deficit apportionment, one seat at a time: the role
  /// furthest below the share it is owed takes the next seat. It is a technical
  /// rule for splitting an integer number of seats by a set of proportions, not
  /// a football judgement and not a score anybody sees.
  ///
  /// Two constraints, and no others. A team has one goalkeeper at most, and a
  /// role the period never played takes no seat at all — there is no minimum
  /// defence, no minimum attack, and nothing borrowed to satisfy a renderer.
  static Map<Position, int> allocateSlots({
    required Map<Position, double> shares,
    required int targetSize,
  }) {
    final allocated = _emptySlots();
    if (targetSize <= 0) return allocated;

    for (var seat = 0; seat < targetSize; seat++) {
      Position? best;
      var bestDeficit = 0.0;

      for (final role in _axis) {
        final share = shares[role] ?? 0;
        if (share <= _epsilon) continue;
        if (role == Position.gk && allocated[role]! >= 1) continue;

        final deficit = share * targetSize - allocated[role]!;
        if (best == null || deficit > bestDeficit + _epsilon) {
          best = role;
          bestDeficit = deficit;
          continue;
        }
        // Within the tolerance the two are the same deficit, so the stated
        // tie-break decides: the larger share, then the axis. `_axis` is walked
        // in order, so reaching here with an equal share means `best` is
        // already the earlier role and keeping it *is* the axis rule.
        if ((deficit - bestDeficit).abs() <= _epsilon &&
            share > (shares[best] ?? 0) + _epsilon) {
          best = role;
          bestDeficit = deficit;
        }
      }

      if (best == null) {
        // Valid evidence always leaves a role able to take a seat: the shares
        // are a mean over sides that had at least one known position, so at
        // least one role is above zero, and only GK is capped. Reaching here
        // means the evidence contradicts itself.
        throw StateError(
          'no role can take seat ${seat + 1} of $targetSize: the period shape '
          'evidence does not support the squad size derived from it',
        );
      }
      allocated[best] = allocated[best]! + 1;
    }

    return allocated;
  }

  // --- Ranking ---------------------------------------------------------------

  /// The approved order, and the only order.
  ///
  ///     period form score        desc
  ///  -> participation rate       desc
  ///  -> MVP count                desc
  ///  -> capped goal contribution desc
  ///  -> user id                  asc
  ///
  /// Nothing else may enter it. In particular **not the current overall
  /// rating**: it is a live global number that a match played after the period
  /// would move, and an award for a week that has closed must not change
  /// because of football played since. Not raw goals either — the capped
  /// contribution above is the goal evidence, so a single nine-goal afternoon
  /// cannot outrank a period of steady scoring.
  ///
  /// The user id is a last resort and never a preference. It exists so that two
  /// players who are genuinely level produce the same order on every device
  /// rather than whichever the list happened to hold first.
  static int compareCandidates(
    TeamOfPeriodCandidate a,
    TeamOfPeriodCandidate b,
  ) {
    final form = _descending(a.periodFormScore, b.periodFormScore);
    if (form != 0) return form;

    final participation = _descending(a.participationRate, b.participationRate);
    if (participation != 0) return participation;

    if (a.mvpCount != b.mvpCount) return b.mvpCount.compareTo(a.mvpCount);

    final goalForm =
        _descending(a.goalFormContributionTotal, b.goalFormContributionTotal);
    if (goalForm != 0) return goalForm;

    return a.userId.compareTo(b.userId);
  }

  /// Larger first, with the same tolerance the apportionment uses, so a
  /// difference no larger than floating noise falls through to the next rung
  /// rather than deciding the award.
  static int _descending(double a, double b) {
    if ((a - b).abs() <= _epsilon) return 0;
    return b.compareTo(a);
  }

  // --- Selection helpers -----------------------------------------------------

  /// Takes the best-ranked unselected candidates [matches] accepts into [role]
  /// until it holds [upTo].
  static void _fill({
    required List<TeamOfPeriodCandidate> ranked,
    required Map<String, Position> assigned,
    required Map<Position, int> filled,
    required Position role,
    required int upTo,
    required bool Function(TeamOfPeriodCandidate) matches,
  }) {
    for (final candidate in ranked) {
      if (filled[role]! >= upTo) return;
      if (assigned.containsKey(candidate.userId)) continue;
      if (!matches(candidate)) continue;

      assigned[candidate.userId] = role;
      filled[role] = filled[role]! + 1;
    }
  }

  /// Which role a released seat should go to, or null when none can take one.
  ///
  /// Restricted to roles that still have an unselected candidate whose Period
  /// **Primary** is that role: a reallocated seat is only worth having if
  /// somebody actually played there most. Among those, the same proportional
  /// deficit the initial allocation used, measured against what the role has
  /// actually been awarded.
  static Position? _reallocationRole({
    required List<TeamOfPeriodCandidate> ranked,
    required Map<String, Position> assigned,
    required Map<Position, int> filled,
    required Map<Position, double> shares,
    required int targetSize,
  }) {
    Position? best;
    var bestDeficit = 0.0;

    for (final role in _axis) {
      if (role == Position.gk && filled[role]! >= 1) continue;

      final hasCandidate = ranked.any((candidate) =>
          !assigned.containsKey(candidate.userId) &&
          candidate.periodPrimaryPosition == role);
      if (!hasCandidate) continue;

      final deficit = (shares[role] ?? 0) * targetSize - filled[role]!;
      if (best == null || deficit > bestDeficit + _epsilon) {
        best = role;
        bestDeficit = deficit;
        continue;
      }
      if ((deficit - bestDeficit).abs() <= _epsilon &&
          (shares[role] ?? 0) > (shares[best] ?? 0) + _epsilon) {
        best = role;
        bestDeficit = deficit;
      }
    }

    return best;
  }

  static Map<Position, int> _emptySlots() => {for (final role in _axis) role: 0};

  // --- Evidence validation ---------------------------------------------------

  /// Refuses evidence that cannot be true, rather than working around it.
  ///
  /// Every check here is a statement the read model already guarantees, so a
  /// failure means the contract is broken somewhere upstream — and a selector
  /// that smoothed it over would produce a team that looked entirely reasonable
  /// and was built on a lie.
  static void _validateWindow(TeamOfPeriodWindow window) {
    if (window.qualifyingMatchCount < 0) {
      throw ArgumentError.value(
        window.qualifyingMatchCount,
        'qualifyingMatchCount',
        'a period cannot hold a negative number of matches',
      );
    }

    for (final size in window.teamSizeObservations) {
      if (size <= 0) {
        throw ArgumentError.value(
          size,
          'teamSizeObservations',
          'a side that fielded nobody is not an observation',
        );
      }
    }

    for (final observation in window.positionShapeObservations) {
      final counts = {
        'gk': observation.gk,
        'def': observation.def,
        'mid': observation.mid,
        'fwd': observation.fwd,
        'unassigned': observation.unassigned,
        'teamSize': observation.teamSize,
      };
      for (final entry in counts.entries) {
        if (entry.value < 0) {
          throw ArgumentError.value(
            entry.value,
            entry.key,
            'a side cannot hold a negative number of players',
          );
        }
      }
      if (observation.teamSize <= 0) {
        throw ArgumentError.value(
          observation.teamSize,
          'teamSize',
          'a side that fielded nobody is not an observation',
        );
      }
      if (observation.known + observation.unassigned != observation.teamSize) {
        throw StateError(
          'a side of ${observation.teamSize} does not account for its players: '
          '${observation.known} positioned and ${observation.unassigned} '
          'unassigned',
        );
      }
    }

    if (window.qualifyingMatchCount == 0) return;

    // Past this point the period says it holds football, so it must be able to
    // describe it.
    if (window.teamSizeObservations.isEmpty) {
      throw StateError(
        'the period reports ${window.qualifyingMatchCount} qualifying matches '
        'and no played side at all',
      );
    }
    if (!window.positionShapeObservations.any((o) => o.hasKnownPositions)) {
      throw StateError(
        'the period reports ${window.qualifyingMatchCount} qualifying matches '
        'and no player whose position was recorded',
      );
    }
  }
}
