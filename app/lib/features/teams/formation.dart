import 'package:btge/btge.dart';

import 'team_models.dart';

/// How a stored lineup is arranged on a drawn pitch.
///
/// **This is presentation, and only presentation.** Nothing here is stored,
/// nothing here is sent anywhere, and no player's `assignedPosition` is changed
/// by it — `KB-017` makes the stored lineup the record of what actually played,
/// and a drawing is not allowed to edit that record. What this decides is which
/// *row* a player is drawn in, which is a question the database has no opinion
/// about.
///
/// It is a plain function over plain data, deliberately outside the widget that
/// draws it. The rules below are the Product Owner's and are worth reading and
/// testing on their own; a version of them tangled into a `build` method could
/// only be checked by rendering something.
///
/// The rules, in order:
///
///   1. **Defence** takes defenders first — at least 3 and at most 4. Short of
///      3 it borrows midfielders, then anyone. Beyond 4 the extra defenders are
///      left in the pool and end up in midfield.
///   2. **Attack** then takes forwards — at least 2 and at most 3, borrowing
///      the same way.
///   3. **Midfield** is everyone who is left, laid out at most 4 to a row.
///
/// The minimums are targets rather than guarantees. A five-a-side squad cannot
/// field three at the back and two up front and still have a midfield, so each
/// line takes what the pool can give and stops. Ordering matters and is the
/// Product Owner's: defence is filled before attack, so a thin squad defends.

/// At least this many in defence, when there are bodies for it.
const int kDefenceMin = 3;

/// Never more than this many in defence; the rest drop into midfield.
const int kDefenceMax = 4;

const int kAttackMin = 2;
const int kAttackMax = 3;

/// Midfield wraps after this many, so a large midfield becomes rows of four
/// with the remainder underneath: 5 draws as 4 + 1, and 7 as 4 + 3.
const int kMidfieldPerRow = 4;

/// One team, arranged into the rows a pitch is drawn from — top to bottom.
class PitchFormation {
  const PitchFormation({
    required this.attack,
    required this.midfieldRows,
    required this.defence,
    required this.goalkeepers,
  });

  /// The top row.
  final List<TeamAssignment> attack;

  /// The middle, already split into rows of at most [kMidfieldPerRow]. Empty
  /// when nobody is in midfield — an empty row is never drawn.
  final List<List<TeamAssignment>> midfieldRows;

  /// The bottom outfield row.
  final List<TeamAssignment> defence;

  /// Drawn below the defence, and empty unless the lineup actually names
  /// somebody in goal. A squad with no goalkeeper does not field one, and an
  /// empty goal would draw a position the match did not have.
  final List<TeamAssignment> goalkeepers;

  /// Everyone drawn, in the order they are drawn. Useful to a caller checking
  /// that the arrangement lost nobody.
  List<TeamAssignment> get all => [
        ...attack,
        for (final row in midfieldRows) ...row,
        ...defence,
        ...goalkeepers,
      ];
}

/// Arranges [assignments] into rows.
///
/// [order] decides the order within each row, and defaults to leaving players
/// as they arrived. The pitch passes a name comparison so a row reads the same
/// way on every build.
PitchFormation buildFormation(
  List<TeamAssignment> assignments, {
  Comparator<TeamAssignment>? order,
}) {
  // Whoever is in goal is taken out first and plays no part in the rules below:
  // the Product Owner's minimums are about outfield shape, and a goalkeeper
  // counted as a defender would push a real defender into midfield.
  final goalkeepers = <TeamAssignment>[];
  final pool = <TeamAssignment>[];
  for (final assignment in assignments) {
    if (assignment.assignedPosition == Position.gk) {
      goalkeepers.add(assignment);
    } else {
      pool.add(assignment);
    }
  }

  final defence = _take(
    pool,
    preferred: Position.def,
    fallback: Position.mid,
    min: kDefenceMin,
    max: kDefenceMax,
  );
  final attack = _take(
    pool,
    preferred: Position.fwd,
    fallback: Position.mid,
    min: kAttackMin,
    max: kAttackMax,
  );

  // Whatever survived both passes. That includes defenders beyond the fourth
  // and forwards beyond the third, which is where "move the rest to midfield"
  // happens — they were never removed from the pool, so falling through to here
  // *is* the move.
  final midfield = [...pool];

  if (order != null) {
    defence.sort(order);
    attack.sort(order);
    midfield.sort(order);
    goalkeepers.sort(order);
  }

  return PitchFormation(
    attack: attack,
    midfieldRows: chunkMidfield(midfield),
    defence: defence,
    goalkeepers: goalkeepers,
  );
}

/// Pulls one line out of [pool], removing what it takes.
///
/// [preferred] goes in first, up to [max]. If that leaves the line short of
/// [min] it borrows from [fallback], and then from whoever is left — which is
/// how a squad with no recognised forwards still fields an attack. A pool that
/// runs out simply yields a shorter line; there is nothing to invent.
List<TeamAssignment> _take(
  List<TeamAssignment> pool, {
  required Position preferred,
  required Position fallback,
  required int min,
  required int max,
}) {
  final line = <TeamAssignment>[];

  void drain(bool Function(TeamAssignment) matches, int limit) {
    for (var i = 0; i < pool.length && line.length < limit;) {
      if (matches(pool[i])) {
        line.add(pool.removeAt(i));
      } else {
        i++;
      }
    }
  }

  drain((a) => a.assignedPosition == preferred, max);
  if (line.length < min) {
    drain((a) => a.assignedPosition == fallback, min);
  }
  if (line.length < min) {
    drain((_) => true, min);
  }
  return line;
}

/// Splits a midfield into rows of at most [kMidfieldPerRow], in order.
///
/// Full rows first and the remainder last, which is what the Product Owner's
/// examples describe: five draws as four then one, seven as four then three.
List<List<TeamAssignment>> chunkMidfield(List<TeamAssignment> midfield) {
  final rows = <List<TeamAssignment>>[];
  for (var start = 0; start < midfield.length; start += kMidfieldPerRow) {
    final end = (start + kMidfieldPerRow).clamp(0, midfield.length);
    rows.add(midfield.sublist(start, end));
  }
  return rows;
}
