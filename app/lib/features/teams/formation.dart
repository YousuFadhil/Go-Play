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
///   4. **The attack is never drawn as large as the midfield.** A team whose
///      top row would hold as many players as its middle rows drops attackers
///      into midfield until it does not — see [_thinAttack].
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
    this.movedFrom = const {},
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

  /// Players drawn in a line their stored position does not name, and the
  /// position that stored assignment actually holds. Keyed by user id, which is
  /// unique within one team's lineup.
  ///
  /// **Presentation state, and nothing else.** No `TeamAssignment` is altered to
  /// produce it: `assignedPosition` still says what the database says, and this
  /// is only the drawing admitting where it put the card. Nothing reads it to
  /// decide anything — the pitch reads it to *say* something.
  ///
  /// It is not [TeamAssignment.outOfPosition] and must not be confused with it.
  /// That marker reports what the *engine* decided — a player put in a position
  /// neither of their own (`AssignmentBasis.transition`) — and is a fact about
  /// the lineup. This reports what the *pitch* decided, and is a fact about the
  /// picture. A forward drawn in midfield is out of line here while being
  /// perfectly in position there, which is exactly why a second marker was
  /// needed rather than a reuse of the first.
  ///
  /// Populated for forwards drawn in midfield, which is the displacement the
  /// reader has no other way to detect: the card carries no position text, so
  /// the row is the only thing saying what a player is, and without this a
  /// forward moved down by [_thinAttack] would be indistinguishable from a
  /// midfielder. Other displacements the rules have always made — the fifth
  /// defender falling into midfield, a midfielder borrowed into defence — are
  /// deliberately not marked: they are approved, long-standing behaviour and
  /// widening the marker to them is a product decision this does not take.
  final Map<String, Position> movedFrom;

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

  _thinAttack(attack, midfield);

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
    // Read off the finished midfield rather than recorded as players are moved:
    // the question is "which cards ended up in a line their position does not
    // name", and the answer is a property of where they ended up. A forward
    // that reached midfield by overflowing the attack's cap is in exactly the
    // situation a forward moved by `_thinAttack` is in, and marking one but not
    // the other would put two identical cards side by side saying different
    // things.
    movedFrom: {
      for (final assignment in midfield)
        if (assignment.assignedPosition == Position.fwd)
          assignment.userId: Position.fwd,
    },
  );
}

/// Moves attackers down into midfield until the top row is the smaller of the
/// two.
///
/// **This is drawing, and only drawing.** It moves nobody in the database, sends
/// nothing anywhere, changes no `assignedPosition`, drops no player and resizes
/// no team: the same people are on the pitch afterwards, one row lower. A
/// forward moved here is still a forward in the stored lineup and still carries
/// their own out-of-position marker, exactly as the fifth defender drawn in
/// midfield has always been.
///
/// The rule is `displayed FWD < displayed MID`. Each move takes one off the top
/// row and adds one to the middle, so the gap closes by two a time and the loop
/// stops at the first arrangement that satisfies it — the fewest players moved,
/// rather than an attack emptied on principle.
///
/// **One shape it cannot satisfy, and does not pretend to.** When the attack and
/// the midfield are *both* empty there is nobody to move and `0 < 0` is false.
/// That happens only when every outfield player was absorbed by the back line —
/// a side of at most four outfield players, which the 2 v 2 minimum (`OP-2`)
/// allows. Emptying the defence to manufacture a midfield would be inventing a
/// second rule to satisfy the first, and hiding a player to avoid the question
/// is not on the table, so such a team is drawn as it always was: one line of
/// defenders, with no attack row and no midfield row for the rule to compare.
void _thinAttack(
  List<TeamAssignment> attack,
  List<TeamAssignment> midfield,
) {
  // Last first, so the forward the engine listed first keeps the top row.
  while (attack.isNotEmpty && attack.length >= midfield.length) {
    midfield.add(attack.removeLast());
  }
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
