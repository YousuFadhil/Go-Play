import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import 'match_stage.dart';
import 'formation.dart';
import 'team_models.dart';

/// One team drawn on a pitch rather than listed.
///
/// The rows run the way a team sheet is read: attack at the top, midfield in the
/// middle, defence at the back and the goalkeeper in goal. Which player is drawn
/// in which row is [buildFormation]'s decision, not this widget's — the rules are
/// the Product Owner's, they are worth testing on their own, and a version of
/// them living inside `build` could only be checked by rendering something.
///
/// **Nothing here changes a stored position.** `KB-017` makes the stored lineup
/// the record of what actually played; this arranges that record for reading and
/// writes nothing back. A defender drawn in midfield because the team had five
/// of them is still a defender in the database, and still shows their own badge.
class PitchView extends StatelessWidget {
  const PitchView({
    super.key,
    required this.assignments,
    required this.players,
    required this.hasNaturalGoalkeeper,
    required this.nameOf,
    this.onTapPlayer,
    this.goalsOf,
    this.isMvpOf,
  });

  /// Fixed approved geometry. The page scrolls; the pitch never stretches to
  /// absorb formation rows.
  static const aspectRatio = 1.9;
  static const avatarDiameterFraction = 0.10;
  static const minAvatarDiameter = 34.0;
  static const maxAvatarDiameter = 76.0;

  /// This team's stored assignments, in any order.
  final List<TeamAssignment> assignments;

  /// The profiles behind them, by player id. A player who left the match after
  /// the lineup was stored has no entry and is drawn from the assignment alone.
  final Map<String, PlayerCoreInputs> players;

  /// Whether the match's squad holds anybody who keeps goal (§10.1).
  ///
  /// A lineup can name a goalkeeper only if the squad had one, so this is
  /// belt-and-braces: the goal row is drawn when both this is true and somebody
  /// is actually assigned to it.
  final bool hasNaturalGoalkeeper;

  /// What to call a player. The profile is the first source and the roster the
  /// second, and neither is this widget's to look up — a player who left the
  /// match after the lineup was stored is in neither, and the caller decides
  /// what stands in for them.
  final String Function(String userId) nameOf;

  final void Function(TeamAssignment assignment)? onTapPlayer;

  /// What each player did, once a result has been recorded.
  ///
  /// **Both null until there is one, which is what makes this screen adapt.**
  /// A lineup drawn before the match has nothing to say about goals or a best
  /// player; the same pitch drawn afterwards has both, on the players
  /// themselves. Left null the cards are exactly what they were, so nothing
  /// about the pre-match pitch changes.
  ///
  /// Functions rather than maps because the caller already holds the result and
  /// this widget has no business learning what a `MatchResult` is.
  final int Function(String participantId)? goalsOf;
  final bool Function(String participantId)? isMvpOf;

  @override
  Widget build(BuildContext context) {
    final formation = buildFormation(
      assignments,
      // A stable order, so a row does not reshuffle between builds.
      order: (a, b) =>
          nameOf(a.participantId).compareTo(nameOf(b.participantId)),
    );

    final rows = <List<TeamAssignment>>[
      if (formation.attack.isNotEmpty) formation.attack,
      ...formation.midfieldRows,
      if (formation.defence.isNotEmpty) formation.defence,
      if (hasNaturalGoalkeeper && formation.goalkeepers.isNotEmpty)
        formation.goalkeepers,
    ];

    return AspectRatio(
      key: const ValueKey('match-pitch'),
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: LayoutBuilder(
          builder: (context, box) {
            final avatarDiameter =
                (box.maxWidth * avatarDiameterFraction).clamp(
              minAvatarDiameter,
              maxAvatarDiameter,
            );
            final playerScale = avatarDiameter / 36;

            return CustomPaint(
              painter: const _PitchPainter(
                grass: MatchStage.grass,
                stripe: MatchStage.grassBand,
                lines: MatchStage.grassLine,
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var index = 0; index < rows.length; index++)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment(
                          0,
                          rows.length == 1
                              ? 0
                              : -1 + (2 * index / (rows.length - 1)),
                        ),
                        child: _PitchRow(
                          line: rows[index],
                          players: players,
                          nameOf: nameOf,
                          movedFrom: formation.movedFrom,
                          onTapPlayer: onTapPlayer,
                          goalsOf: goalsOf,
                          isMvpOf: isMvpOf,
                          scale: playerScale,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The pitch under the players: mown stripes, a touchline, a halfway line with
/// its centre circle, and a penalty area at each end.
///
/// Painted rather than assembled from widgets because none of it is
/// interactive and all of it is geometry. The markings are deliberately faint —
/// they are there to say "this is a pitch", and anything stronger competes with
/// the names sitting on top of them.
class _PitchPainter extends CustomPainter {
  const _PitchPainter({
    required this.grass,
    required this.stripe,
    required this.lines,
  });

  final Color grass;
  final Color stripe;
  final Color lines;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = grass);

    // Mown bands across the pitch. Six is enough to read as stripes at any
    // height this view is given.
    const bands = 6;
    final bandHeight = size.height / bands;
    final stripePaint = Paint()..color = stripe;
    for (var i = 0; i < bands; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * bandHeight, size.width, bandHeight),
        stripePaint,
      );
    }

    final line = Paint()
      ..color = lines
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final inset = rect.deflate(10);
    canvas.drawRect(inset, line);

    // Halfway line and centre circle.
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(inset.left, middle),
      Offset(inset.right, middle),
      line,
    );
    canvas.drawCircle(
      Offset(size.width / 2, middle),
      size.width * 0.13,
      line,
    );

    // A penalty area at each end, scaled to the pitch so it holds its
    // proportions whatever height the team needs.
    final boxWidth = inset.width * 0.44;
    final boxHeight = (inset.height * 0.16).clamp(18.0, 64.0);
    final boxLeft = inset.left + (inset.width - boxWidth) / 2;
    canvas.drawRect(
      Rect.fromLTWH(boxLeft, inset.top, boxWidth, boxHeight),
      line,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        boxLeft,
        inset.bottom - boxHeight,
        boxWidth,
        boxHeight,
      ),
      line,
    );
  }

  @override
  bool shouldRepaint(_PitchPainter oldDelegate) =>
      oldDelegate.grass != grass ||
      oldDelegate.stripe != stripe ||
      oldDelegate.lines != lines;
}

/// One line of the pitch. The players spread evenly across it, so the shape of
/// the row is the shape of the line.
class _PitchRow extends StatelessWidget {
  const _PitchRow({
    required this.line,
    required this.players,
    required this.nameOf,
    required this.movedFrom,
    required this.onTapPlayer,
    this.goalsOf,
    this.isMvpOf,
    required this.scale,
  });

  final List<TeamAssignment> line;
  final Map<String, PlayerCoreInputs> players;
  final String Function(String userId) nameOf;

  /// Who on this pitch is drawn away from the line their position names, from
  /// [PitchFormation.movedFrom]. Presentation state; it changes no assignment.
  final Map<String, Position> movedFrom;

  final void Function(TeamAssignment assignment)? onTapPlayer;

  final int Function(String participantId)? goalsOf;
  final bool Function(String participantId)? isMvpOf;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 5 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final assignment in line)
            Flexible(
              child: PlayerCard(
                assignment: assignment,
                player: players[assignment.participantId],
                name: nameOf(assignment.participantId),
                movedFrom: movedFrom[assignment.participantId],
                goals: goalsOf?.call(assignment.participantId) ?? 0,
                isMvp: isMvpOf?.call(assignment.participantId) ?? false,
                scale: scale,
                onTap:
                    onTapPlayer == null ? null : () => onTapPlayer!(assignment),
              ),
            ),
        ],
      ),
    );
  }
}

/// The position a card actually holds, on a card the drawing has moved.
///
/// A pill rather than a line of text, and a different shape from the
/// out-of-position marker beside it, because the two say different things and a
/// reader has to be able to tell at a glance which one they are looking at. The
/// arrow is what turns a position name into a statement: on its own, "Forward"
/// sitting under a card in the midfield row could be read as a label for the
/// row, and the arrow says the player belongs a line above where they are drawn.
///
/// Compact by necessity — the card is 82 logical pixels wide — so the pill
/// carries the position and nothing else, and the whole sentence is on the
/// [Semantics] node for anybody who is not reading it by eye.
/// A player on the pitch: their face, their name and their rating.
///
/// Set light-on-dark, because it now sits on grass rather than on the app's
/// surface. The rating is shown because the Product Owner asked for it on this
/// card; it stays read-only here as everywhere else, `OP-1` making it
/// system-managed.
class PlayerCard extends StatelessWidget {
  const PlayerCard({
    super.key,
    required this.assignment,
    required this.player,
    required this.name,
    this.movedFrom,
    this.onTap,
    this.goals = 0,
    this.isMvp = false,
    this.scale = 1,
  });

  final TeamAssignment assignment;

  /// Null for somebody who left the match after the lineup was stored. They are
  /// still drawn — `KB-017` records that they played — with what is left of
  /// them, which is the position they held.
  final PlayerCoreInputs? player;

  /// What to write under the face. Resolved by the caller, because a player who
  /// left the match has no profile left to read it from.
  final String name;

  /// The position [assignment] actually holds, when this card has been drawn in
  /// a line that does not name it. Null when the card is where its position
  /// says, which is every card on an ordinary pitch.
  ///
  /// Presentation state, handed down from [PitchFormation.movedFrom]. It is not
  /// read from [assignment] and it does not change it: `assignedPosition` is
  /// still `FWD` for a forward drawn here, and the badge below is the card
  /// saying so out loud.
  final Position? movedFrom;

  /// How many this player scored, and whether they were named best on the
  /// pitch. Zero and false before a result exists, which is every card on a
  /// pre-match pitch — so the marks below are drawn only once there is a result
  /// to draw them from.
  final int goals;
  final bool isMvp;

  /// How much larger than the phone this card is drawn. See [PitchView.scale].
  final double scale;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = player?.avatarUrl;
    final isGuest = assignment.isProfessionalGuest;

    // Wider than it was: the approved direction puts the player first, and a
    // recognisable face needs the room. Every measurement below is a multiple of
    // the same avatar radius, so the card holds its proportions at any scale.
    final radius = 18.0 * scale;

    // The ink is there only where there is something to tap. A card with no
    // `onTap` is a card in a picture, and an `InkWell` there wants a `Material`
    // ancestor a share card has no reason to carry.
    final body = Padding(
      padding: EdgeInsets.symmetric(
        vertical: 2 * scale,
        horizontal: 2 * scale,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A Professional Guest is marked on the pitch as they are on every
          // roster: the tertiary disc and the badge, never a picture. Before
          // this they shared the plain white disc with a player who had left
          // the match, which said the same thing about two different people.
          CircleAvatar(
            radius: radius,
            backgroundColor:
                isGuest ? theme.colorScheme.tertiaryContainer : Colors.white,
            foregroundColor: isGuest
                ? theme.colorScheme.onTertiaryContainer
                : theme.colorScheme.primary,
            // A guest holds no account, so there is no picture of theirs to
            // load and no chance of loading somebody else's.
            foregroundImage:
                avatarUrl == null || isGuest ? null : NetworkImage(avatarUrl),
            // Swallowed: a picture that will not load is not worth an error,
            // and the child shows through instead of a broken image.
            onForegroundImageError:
                avatarUrl == null || isGuest ? null : (_, __) {},
            child: Icon(
              isGuest ? Icons.workspace_premium_outlined : Icons.person,
              size: radius,
            ),
          ),
          SizedBox(height: 3 * scale),
          // The name, and the star beside it.
          //
          // **Inline, because the star belongs to the player and not to a
          // badge.** The approved direction puts it immediately after the
          // name, where a reader takes the two in together; the goal tally
          // sits below with the rating, where a number belongs among
          // numbers.
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5 * scale,
                    height: 1.25,
                    // A hard shadow, so a pale name stays readable over a
                    // pale stripe without darkening the pitch for everyone.
                    shadows: const [
                      Shadow(blurRadius: 2, color: Color(0x99000000)),
                    ],
                  ),
                ),
              ),
              if (isMvp) ...[
                SizedBox(width: 3 * scale),
                Icon(
                  Icons.star_rounded,
                  size: 14 * scale,
                  color: MatchStage.star,
                  shadows: const [
                    Shadow(blurRadius: 2, color: Color(0x99000000)),
                  ],
                ),
              ],
            ],
          ),
          if (player != null)
            Text(
              // One decimal, which is `OP-1`'s presentation scale.
              player!.overallRating.toStringAsFixed(1),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 10.5 * scale,
                height: 1.3,
              ),
            ),
          // What this player scored, under the rating: a number among
          // numbers. Drawn only where there is one — a tally of zero is the
          // absence of a badge, not a badge of none.
          if (goals > 0) _GoalBadge(goals: goals, scale: scale),
          // What this player's position actually is, when the drawing has
          // put them somewhere else. The card carries no position text
          // otherwise — the row it sits in is what says it — so without
          // this badge a forward moved down to keep the attack smaller than
          // the midfield would read as a midfielder and nothing on screen
          // would disagree.
          // Formation corrections remain data, not presentation chrome.
          // The approved Teams view shows face, name, rating and result
          // markers only.
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 86 * scale),
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(Radii.sm * scale),
              child: body,
            ),
    );
  }
}

/// What a player scored, under their rating.
///
/// **The count first, then the ball**, which is the approved direction's own
/// order and reads as a tally rather than as a sentence. The row is pinned left
/// to right so it lands the same way in both languages, and the badge sits on
/// its own dark ground because a number on grass has nothing to hold its edge.
///
/// The star is not here — it sits beside the name, where the player is.
class _GoalBadge extends StatelessWidget {
  const _GoalBadge({required this.goals, required this.scale});

  final int goals;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Semantics(
      label: l10n.goalsScoredLabel(goals),
      excludeSemantics: true,
      child: Container(
        margin: EdgeInsets.only(top: 2 * scale),
        padding: EdgeInsets.symmetric(
          horizontal: 5.5 * scale,
          vertical: 0.75 * scale,
        ),
        decoration: BoxDecoration(
          color: MatchStage.badge,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: MatchStage.badgeEdge, width: 1),
        ),
        child: Row(
          textDirection: TextDirection.ltr,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$goals',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10 * scale,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            SizedBox(width: 3 * scale),
            Icon(
              Icons.sports_soccer,
              size: 9.5 * scale,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ],
        ),
      ),
    );
  }
}
