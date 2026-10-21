import 'package:btge/btge.dart';

import 'team_models.dart';

/// What dropping one player onto another does on the Teams screen pitch.
///
/// Three existing operations and nothing new: the drag only decides which one
/// the organizer meant, from where the two players stand.
enum PitchSwapKind {
  /// Same team, same position: the two exchange places inside their line.
  /// Presentation only -- the stored order of that line, nothing else.
  sideSwap,

  /// Same team, different positions: `TeamRepository.swapAssignedPositions`.
  positionSwap,

  /// Different teams: `TeamRepository.swapPlayers`.
  teamSwap,
}

/// The outcome of dropping [dragged] onto [target], or null when [target] is
/// not a valid drop for it.
///
/// | Drop target                                  | Result         |
/// |----------------------------------------------|----------------|
/// | the same player                              | null           |
/// | other team                                   | [PitchSwapKind.teamSwap] |
/// | same team, either has no position            | null           |
/// | same team, same position                     | [PitchSwapKind.sideSwap] |
/// | same team, different position                | [PitchSwapKind.positionSwap] |
///
/// A Professional Guest in an ordinary lineup has no position: across the
/// teams that is no obstacle (a team swap keeps everybody's position, null
/// included), and on the same team there is no line and no position of theirs
/// to exchange. Empty space is not a player and never reaches this.
PitchSwapKind? resolvePitchSwap(
  TeamAssignment dragged,
  TeamAssignment target,
) {
  if (dragged.participantId == target.participantId) return null;
  if (dragged.team != target.team) return PitchSwapKind.teamSwap;
  final from = dragged.assignedPosition;
  final to = target.assignedPosition;
  if (from == null || to == null) return null;
  return from == to ? PitchSwapKind.sideSwap : PitchSwapKind.positionSwap;
}

/// One line of the pitch: a team's players at one position.
typedef PitchLine = ({TeamId team, Position position});

/// Every line of [lineup], each in the order the pitch draws it ([order] is
/// [lineOrderThenName] with the screen's names). A participant without a
/// position stands in no line.
Map<PitchLine, List<String>> displayedLines(
  List<TeamAssignment> lineup,
  Comparator<TeamAssignment> order,
) {
  final grouped = <PitchLine, List<TeamAssignment>>{};
  for (final assignment in lineup) {
    final position = assignment.assignedPosition;
    if (position == null) continue;
    grouped.putIfAbsent(
        (team: assignment.team, position: position), () => []).add(assignment);
  }
  return {
    for (final MapEntry(:key, :value) in grouped.entries)
      key: [for (final a in value..sort(order)) a.participantId],
  };
}

/// The line orders to store after [firstId] and [secondId] swapped, so each
/// stands in the other's **exact place** -- line and side -- rather than where
/// the name would put them.
///
/// [before] is the lineup as it was drawn when the drag began, and [after] the
/// lineup as stored once the swap was written (the same list for a side swap,
/// which moves nobody between lines). Only the lines somebody arrived in are
/// returned, each in full, because those are the only ones whose drawing would
/// otherwise fall back to the name; a line that only lost somebody keeps the
/// relative order it had.
///
/// For each returned line the players who were already there keep their
/// order, and an arrival takes the index its counterpart held: in the same line
/// when the counterpart stood in it (a position swap, or a team swap between
/// two players of the same position), otherwise the index the counterpart held
/// in their own line, clamped to the line's length. Anybody else who arrived
/// without being dragged -- a Professional Guest the database re-sided -- goes
/// to the end, in drawing order.
Map<PitchLine, List<String>> lineOrdersAfterSwap({
  required List<TeamAssignment> before,
  required List<TeamAssignment> after,
  required String firstId,
  required String secondId,
  required Comparator<TeamAssignment> order,
}) {
  final oldLines = displayedLines(before, order);
  final newLines = displayedLines(after, order);

  PitchLine? lineOf(Map<PitchLine, List<String>> lines, String id) {
    for (final MapEntry(:key, :value) in lines.entries) {
      if (value.contains(id)) return key;
    }
    return null;
  }

  final counterpart = {firstId: secondId, secondId: firstId};
  final result = <PitchLine, List<String>>{};

  for (final id in [firstId, secondId]) {
    final line = lineOf(newLines, id);
    if (line == null || result.containsKey(line)) continue;

    final members = newLines[line]!;
    final previous = oldLines[line] ?? const <String>[];

    // A side swap: both were here and both still are. They exchange indices.
    if (previous.contains(firstId) &&
        previous.contains(secondId) &&
        members.contains(firstId) &&
        members.contains(secondId)) {
      final swapped = [
        for (final member in previous)
          if (members.contains(member)) member,
      ];
      final i = swapped.indexOf(firstId);
      final j = swapped.indexOf(secondId);
      swapped[i] = secondId;
      swapped[j] = firstId;
      result[line] = [
        ...swapped,
        for (final member in members)
          if (!swapped.contains(member)) member,
      ];
      continue;
    }

    final stayed = [
      for (final member in previous)
        if (members.contains(member)) member,
    ];

    // The dragged pair first, by the index each is to take, so an earlier
    // insertion cannot shift a later one off its place.
    final arrivals = <(String, int)>[];
    for (final arriving in [firstId, secondId]) {
      if (!members.contains(arriving) || stayed.contains(arriving)) continue;
      final other = counterpart[arriving]!;
      final otherLine = lineOf(oldLines, other);
      final index = otherLine == null
          ? stayed.length
          : oldLines[otherLine]!.indexOf(other);
      arrivals.add((arriving, index));
    }
    arrivals.sort((a, b) => a.$2.compareTo(b.$2));

    final ordered = [...stayed];
    for (final (arriving, index) in arrivals) {
      ordered.insert(index.clamp(0, ordered.length), arriving);
    }
    for (final member in members) {
      if (!ordered.contains(member)) ordered.add(member);
    }
    result[line] = ordered;
  }

  return result;
}
