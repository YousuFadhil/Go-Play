import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import 'formation.dart';
import 'pitch_view.dart';
import 'team_models.dart';

/// Everything the Team Lineup card draws, resolved before it is drawn.
///
/// **The lineup the reader is looking at, not a second read of it.** The Teams
/// screen has already loaded the stored assignments, the profiles behind them
/// and the name each player is shown under; all of that arrives here and
/// nothing is looked up again.
///
/// **The lineup, and nothing about the match.** No title, no location, no kick
/// off, no community — a lineup is shareable as a football lineup, and the
/// match it happened to be generated for is not part of what it says. There is
/// no field here to carry one.
///
/// [names] is the resolved display name per participant, and it is passed
/// rather than derived on purpose. The screen's rule — the profile first, the
/// registration second, a dash for somebody neither knows — is `KB-017`
/// reasoning about a player who left after the lineup was stored, and a card
/// that re-derived it could disagree with the pitch behind it.
@immutable
class TeamLineupCardData {
  const TeamLineupCardData({
    required this.lineup,
    required this.players,
    required this.names,
    required this.hasNaturalGoalkeeper,
  });

  /// The stored lineup, both sides, exactly as the screen holds it.
  final List<TeamAssignment> lineup;

  /// The profiles behind the assignments. A player with no entry left the match
  /// after the lineup was stored and is still drawn — `KB-017` records that
  /// they played — from the assignment alone.
  final Map<String, PlayerCoreInputs> players;

  /// Participant id to the name the screen shows for them.
  final Map<String, String> names;

  /// Whether the squad holds anybody who keeps goal (§10.1). Decides whether a
  /// goal row is drawn at all, and is the screen's own answer.
  final bool hasNaturalGoalkeeper;

  List<TeamAssignment> of(TeamId team) => [
        for (final assignment in lineup)
          if (assignment.team == team) assignment,
      ];

  /// Whether there is a lineup to picture at all.
  ///
  /// An empty lineup is not a card. The Teams screen shows "not generated yet"
  /// in that state and there is nothing on it to send, so the Share action is
  /// not offered and this is what says so.
  bool get isShareable => lineup.isNotEmpty;
}

/// The Team Lineup share card: both teams, facing each other, on one pitch.
///
/// **One pitch, not two.** A lineup is two sides of the same match, and drawing
/// each on a pitch of its own says they are two separate things. Team A defends
/// the top goal and Team B the bottom, so the two attacks meet at the halfway
/// line the way they would on the day.
///
/// **The formation and the player cards are the app's own.** [buildFormation]
/// decides the rows — including which player is drawn out of their line — and
/// [PlayerCard] draws each one, with the picture, the initial, the Professional
/// Guest treatment and the out-of-position marker it already has. Only the
/// arrangement of the two halves is this card's, because that is the part
/// `PitchView` cannot express: it paints one pitch per team by construction.
///
/// **Scaled, not widened.** A `PlayerCard` is capped at 82 logical pixels, so a
/// pitch handed the card's full 1080 would draw phone-sized cards marooned in
/// the middle of it. The whole pitch is composed at a phone's width and scaled
/// up, which enlarges the composition together — text stays crisp because it is
/// painted at the final scale rather than stretched.
///
/// **Its own theme, fixed.** `PlayerCard` takes its accents from the ambient
/// `Theme`, and a picture that leaves the phone must not change because the
/// reader has dark mode on. A light scheme is pinned here.
///
/// **Presentation only, and match-agnostic.** It takes [TeamLineupCardData] and
/// draws it: no repository, no formation decision of its own, no statistic
/// invented, and nothing identifying the match.
class TeamLineupCard extends StatelessWidget {
  const TeamLineupCard({super.key, required this.data});

  final TeamLineupCardData data;

  /// The card's own palette. The same greens as the Player and Community
  /// cards — the three are one product's cards and should read as a set.
  static const _pitchDark = Color(0xFF07341C);
  static const _pitchDeep = Color(0xFF04180E);
  static const _accent = Color(0xFF3DDC84);
  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0xB3FFFFFF);

  static const _margin = 72.0;

  /// The width the pitch is composed at before being scaled up. A phone's
  /// width, because that is what `PlayerCard`'s sizes were chosen against.
  static const _pitchDesignWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_pitchDark, _pitchDeep],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_margin, 96, _margin, 84),
        child: Column(
          children: [
            const _Wordmark(size: 44, spacing: 14),
            const SizedBox(height: 18),
            Container(width: 132, height: 6, color: _accent),
            const Spacer(),
            Flexible(
              flex: 20,
              child: _ScaledPitch(data: data),
            ),
            const Spacer(),
            const _Wordmark(size: 30, spacing: 10, muted: true),
          ],
        ),
      ),
    );
  }
}

/// The pitch, composed at a phone's width and enlarged to the card.
///
/// `contain` rather than `fitWidth`: a crowded lineup makes a taller pitch, and
/// it has to shrink to fit rather than run off the bottom of a picture. The
/// pitch's height is its content's, so no arrangement can overflow it.
class _ScaledPitch extends StatelessWidget {
  const _ScaledPitch({required this.data});

  final TeamLineupCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: TeamLineupCard._pitchDesignWidth,
        child: Theme(
          // Pinned so the card is the same picture for every reader.
          // `PlayerCard` reads `primary` for a player's initial and
          // `tertiaryContainer` for a Professional Guest, and both would
          // otherwise follow whatever theme the composing phone was in.
          data: theme.copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1B7A43),
              brightness: Brightness.light,
            ),
          ),
          // `PlayerCard` builds an `InkWell`, and an ink well wants a
          // `Material` over it. The card has no `Scaffold` to supply one.
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: CustomPaint(
                painter: _FullPitchPainter(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TeamLabel(label: l10n.teamAName),
                      // Team A defends the top goal, so its rows run the other
                      // way: the goal first and the attack last, meeting Team
                      // B's attack at the halfway line.
                      ..._Half(
                        assignments: data.of(TeamId.a),
                        data: data,
                        towardsTop: true,
                      ).rows(),
                      const SizedBox(height: Gap.sm),
                      ..._Half(
                        assignments: data.of(TeamId.b),
                        data: data,
                        towardsTop: false,
                      ).rows(),
                      _TeamLabel(label: l10n.teamBName),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One team's half of the pitch.
///
/// [towardsTop] is which goal the team defends. It reverses the row order and
/// nothing else: the formation itself — who is in attack, how the midfield
/// wraps, who is drawn out of their line — is [buildFormation]'s and is not
/// touched.
class _Half {
  const _Half({
    required this.assignments,
    required this.data,
    required this.towardsTop,
  });

  final List<TeamAssignment> assignments;
  final TeamLineupCardData data;
  final bool towardsTop;

  List<Widget> rows() {
    final formation = buildFormation(
      assignments,
      // The same stable order the pitch uses, so a row does not reshuffle
      // between builds.
      order: (a, b) => (data.names[a.participantId] ?? '')
          .compareTo(data.names[b.participantId] ?? ''),
    );

    // `buildFormation` returns rows top-down for a team attacking upwards:
    // attack, midfield, defence, goal.
    final lines = <List<TeamAssignment>>[
      if (formation.attack.isNotEmpty) formation.attack,
      ...formation.midfieldRows,
      if (formation.defence.isNotEmpty) formation.defence,
      if (data.hasNaturalGoalkeeper && formation.goalkeepers.isNotEmpty)
        formation.goalkeepers,
    ];

    final ordered = towardsTop ? lines.reversed.toList() : lines;
    return [
      for (final line in ordered)
        _PitchLine(line: line, data: data, movedFrom: formation.movedFrom),
    ];
  }
}

/// One line of the pitch. The players spread evenly across it, so the shape of
/// the row is the shape of the line.
class _PitchLine extends StatelessWidget {
  const _PitchLine({
    required this.line,
    required this.data,
    required this.movedFrom,
  });

  final List<TeamAssignment> line;
  final TeamLineupCardData data;
  final Map<String, Position> movedFrom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs, horizontal: Gap.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final assignment in line)
            Flexible(
              child: PlayerCard(
                assignment: assignment,
                player: data.players[assignment.participantId],
                // Resolved by the screen. A dash for somebody neither the
                // profiles nor the roster knows, exactly as the pitch behind
                // this card shows them.
                name: data.names[assignment.participantId] ?? '—',
                movedFrom: movedFrom[assignment.participantId],
                // Nothing on a picture is tappable.
                onTap: null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Which side a half belongs to, written on the grass.
class _TeamLabel extends StatelessWidget {
  const _TeamLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 3,
          // A hard shadow, so the label stays readable over a pale stripe
          // without darkening the pitch for everyone — the same treatment the
          // player names on the pitch already use.
          shadows: [Shadow(blurRadius: 2, color: Color(0x99000000))],
        ),
      ),
    );
  }
}

/// A full pitch: mown bands, a touchline, a halfway line with its centre
/// circle, and a penalty area at each end.
///
/// Painted rather than assembled from widgets because none of it is interactive
/// and all of it is geometry. The markings are deliberately faint — they are
/// there to say "this is a pitch", and anything stronger competes with the
/// names sitting on top of them.
class _FullPitchPainter extends CustomPainter {
  static const _grass = Color(0xFF2E7D4F);
  static const _stripe = Color(0xFF35895A);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = _grass);

    // Mown bands across the pitch. Eight on a full pitch, where the team view
    // uses six on a half.
    const bands = 8;
    final bandHeight = size.height / bands;
    final stripePaint = Paint()..color = _stripe;
    for (var i = 0; i < bands; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * bandHeight, size.width, bandHeight),
        stripePaint,
      );
    }

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final inset = rect.deflate(10);
    canvas.drawRect(inset, line);

    // The halfway line, where the two teams meet.
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
    // proportions whatever height the lineup needs.
    final boxWidth = inset.width * 0.44;
    final boxHeight = (inset.height * 0.12).clamp(18.0, 72.0);
    final boxLeft = inset.left + (inset.width - boxWidth) / 2;
    canvas.drawRect(
      Rect.fromLTWH(boxLeft, inset.top, boxWidth, boxHeight),
      line,
    );
    canvas.drawRect(
      Rect.fromLTWH(boxLeft, inset.bottom - boxHeight, boxWidth, boxHeight),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _FullPitchPainter oldDelegate) => false;
}

/// The Go Play name, as the card's mark.
class _Wordmark extends StatelessWidget {
  const _Wordmark({
    required this.size,
    required this.spacing,
    this.muted = false,
  });

  final double size;
  final double spacing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.appName.toUpperCase(),
      // The mark reads left to right in both languages: it is a name, and the
      // product is called Go Play in Arabic too.
      textDirection: TextDirection.ltr,
      style: TextStyle(
        color: muted ? TeamLineupCard._inkMuted : TeamLineupCard._ink,
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: spacing,
      ),
    );
  }
}
