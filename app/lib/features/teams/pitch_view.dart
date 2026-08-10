import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
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
  });

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

  @override
  Widget build(BuildContext context) {
    final formation = buildFormation(
      assignments,
      // A stable order, so a row does not reshuffle between builds.
      order: (a, b) => nameOf(a.userId).compareTo(nameOf(b.userId)),
    );

    final rows = <List<TeamAssignment>>[
      if (formation.attack.isNotEmpty) formation.attack,
      ...formation.midfieldRows,
      if (formation.defence.isNotEmpty) formation.defence,
      if (hasNaturalGoalkeeper && formation.goalkeepers.isNotEmpty)
        formation.goalkeepers,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kPageMargin,
        vertical: Gap.sm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: CustomPaint(
          painter: _PitchPainter(
            grass: const Color(0xFF2E7D4F),
            stripe: const Color(0xFF35895A),
            lines: Colors.white.withValues(alpha: 0.28),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.lg),
            child: Column(
              children: [
                for (final row in rows)
                  _PitchRow(
                    line: row,
                    players: players,
                    nameOf: nameOf,
                    onTapPlayer: onTapPlayer,
                  ),
              ],
            ),
          ),
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
    required this.onTapPlayer,
  });

  final List<TeamAssignment> line;
  final Map<String, PlayerCoreInputs> players;
  final String Function(String userId) nameOf;
  final void Function(TeamAssignment assignment)? onTapPlayer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm, horizontal: Gap.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final assignment in line)
            Flexible(
              child: PlayerCard(
                assignment: assignment,
                player: players[assignment.userId],
                name: nameOf(assignment.userId),
                onTap: onTapPlayer == null
                    ? null
                    : () => onTapPlayer!(assignment),
              ),
            ),
        ],
      ),
    );
  }
}

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
    this.onTap,
  });

  final TeamAssignment assignment;

  /// Null for somebody who left the match after the lineup was stored. They are
  /// still drawn — `KB-017` records that they played — with what is left of
  /// them, which is the position they held.
  final PlayerCoreInputs? player;

  /// What to write under the face. Resolved by the caller, because a player who
  /// left the match has no profile left to read it from.
  final String name;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final avatarUrl = player?.avatarUrl;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 82),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
                foregroundImage:
                    avatarUrl == null ? null : NetworkImage(avatarUrl),
                // Swallowed: a picture that will not load is not worth an error,
                // and the child shows through instead of a broken image.
                onForegroundImageError: avatarUrl == null ? null : (_, __) {},
                child: const Icon(Icons.person, size: 21),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  // A hard shadow, so a pale name stays readable over a pale
                  // stripe without darkening the pitch for everyone.
                  shadows: const [
                    Shadow(blurRadius: 2, color: Color(0x99000000)),
                  ],
                ),
              ),
              if (player != null)
                Text(
                  // One decimal, which is `OP-1`'s presentation scale.
                  player!.overallRating.toStringAsFixed(1),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              // §5.1's out-of-position marker, kept from the list this replaced:
              // it is the one thing about an assignment a reader cannot infer
              // from where the card sits — and now that the rows above are a
              // drawing rather than the stored positions, it is the only thing
              // on the pitch that still reports one.
              if (assignment.outOfPosition)
                Text(
                  l10n.teamsOutOfPosition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.errorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
