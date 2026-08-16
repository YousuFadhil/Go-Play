import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'pitch_view.dart';
import 'team_models.dart';

/// Everything the Team Lineup card draws, resolved before it is drawn.
///
/// **The lineup the reader is looking at, not a second read of it.** The Teams
/// screen has already loaded the stored assignments, the profiles behind them
/// and the name each player is shown under; all of that arrives here and
/// nothing is looked up again.
///
/// [names] is the resolved display name per participant, and it is passed
/// rather than derived on purpose. The screen's rule — the profile first, the
/// registration second, a dash for somebody neither knows — is `KB-017`
/// reasoning about a player who left after the lineup was stored, and a card
/// that re-derived it could disagree with the pitch behind it.
@immutable
class TeamLineupCardData {
  const TeamLineupCardData({
    required this.matchTitle,
    required this.lineup,
    required this.players,
    required this.names,
    required this.hasNaturalGoalkeeper,
  });

  /// What the match is called, so a lineup sent to a group chat says which
  /// match it is. Identity, not a figure: this card carries no statistic that
  /// the Teams screen does not already show.
  final String matchTitle;

  /// The stored lineup, both sides, exactly as the screen holds it.
  final List<TeamAssignment> lineup;

  /// The profiles behind the assignments. A player with no entry left the match
  /// after the lineup was stored and is still drawn — `KB-017` records that
  /// they played — from the assignment alone.
  final Map<String, PlayerCoreInputs> players;

  /// Participant id to the name the screen shows for them.
  final Map<String, String> names;

  /// Whether the squad holds anybody who keeps goal (§10.1). Decides whether
  /// the pitch draws a goal row at all, and is the screen's own answer.
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

/// The Team Lineup share card: who is playing, on a pitch.
///
/// **It reuses the pitch the app already draws.** [PitchView] is the lineup —
/// the formation, the rows, the cards, the out-of-position markers and the
/// guest treatment are all its work and none of it is restated here. Drawing a
/// second pitch for the card would be two pitches free to disagree about what a
/// lineup looks like.
///
/// **Scaled, not widened.** A `PlayerCard` is capped at 82 logical pixels, so a
/// pitch handed the card's full 1080 would draw phone-sized cards marooned in
/// the middle of it. Instead each side is laid out at a phone's width and
/// scaled up, which enlarges the whole composition together — text stays crisp
/// because it is painted at the final scale rather than stretched.
///
/// **Its own theme, fixed.** The pitch takes its accents from the ambient
/// `Theme`, and a picture that leaves the phone must not change because the
/// reader has dark mode on. A light scheme is pinned here for the pitch alone.
///
/// **Presentation only.** It takes [TeamLineupCardData] and draws it: no
/// repository, no formation decision of its own, no statistic invented.
class TeamLineupCard extends StatelessWidget {
  const TeamLineupCard({super.key, required this.data});

  final TeamLineupCardData data;

  /// The card's own palette. The same greens as the Player and Community
  /// cards — the three are one product's cards and should read as a set.
  static const _pitch = Color(0xFF07341C);
  static const _pitchDeep = Color(0xFF04180E);
  static const _accent = Color(0xFF3DDC84);
  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0xB3FFFFFF);

  static const _margin = 72.0;

  /// The width each side's pitch is composed at before being scaled up. A
  /// phone's width, because that is what `PitchView`'s sizes were chosen
  /// against.
  static const _pitchDesignWidth = 390.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_pitch, _pitchDeep],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_margin, 88, _margin, 76),
        child: Column(
          children: [
            const _Wordmark(size: 42, spacing: 14),
            const SizedBox(height: 16),
            Container(width: 124, height: 6, color: _accent),
            const SizedBox(height: 40),
            _MatchTitle(title: data.matchTitle),
            const SizedBox(height: 40),
            // The two sides share what is left, so a lopsided lineup does not
            // give one team more of the card than the other.
            Expanded(
              child: _Side(
                label: l10n.teamAName,
                assignments: data.of(TeamId.a),
                data: data,
              ),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: _Side(
                label: l10n.teamBName,
                assignments: data.of(TeamId.b),
                data: data,
              ),
            ),
            const SizedBox(height: 36),
            const _Wordmark(size: 28, spacing: 10, muted: true),
          ],
        ),
      ),
    );
  }
}

/// Which match this lineup is for.
class _MatchTitle extends StatelessWidget {
  const _MatchTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        title,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: TeamLineupCard._ink,
          fontSize: 66,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: -1,
        ),
      ),
    );
  }
}

/// One team: its name, how many are on it, and its pitch.
class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.assignments,
    required this.data,
  });

  final String label;
  final List<TeamAssignment> assignments;
  final TeamLineupCardData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(width: 8, height: 34, color: TeamLineupCard._accent),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TeamLineupCard._ink,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ),
            Text(
              // How many are on this side — the same count the Teams screen
              // puts beside the team name, and not a figure of this card's own.
              '${assignments.length}',
              style: const TextStyle(
                color: TeamLineupCard._inkMuted,
                fontSize: 38,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _ScaledPitch(assignments: assignments, data: data)),
      ],
    );
  }
}

/// The app's own pitch, composed at a phone's width and enlarged to the card.
///
/// `FittedBox` with `contain` rather than `fitWidth`: the slot's height is
/// fixed by the card, and a tall lineup — many rows — has to shrink to fit
/// rather than run off the bottom of a picture.
class _ScaledPitch extends StatelessWidget {
  const _ScaledPitch({required this.assignments, required this.data});

  final List<TeamAssignment> assignments;
  final TeamLineupCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: TeamLineupCard._pitchDesignWidth,
        child: Theme(
          // Pinned so the card is the same picture for every reader. The pitch
          // reads `primary` for a player's initial and `tertiaryContainer` for
          // a Professional Guest, and both would otherwise follow whatever
          // theme the composing phone happened to be in.
          data: theme.copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1B7A43),
              brightness: Brightness.light,
            ),
          ),
          // `PitchView` builds an `InkWell` per card even with no tap handler,
          // and an ink well wants a `Material` over it. The card has no
          // `Scaffold` to supply one.
          child: Material(
            type: MaterialType.transparency,
            child: PitchView(
              assignments: assignments,
              players: data.players,
              hasNaturalGoalkeeper: data.hasNaturalGoalkeeper,
              // Resolved by the screen. A dash for somebody neither the
              // profiles nor the roster knows, exactly as the pitch behind
              // this card shows them.
              nameOf: (participantId) => data.names[participantId] ?? '—',
              // Nothing on a picture is tappable.
              onTapPlayer: null,
            ),
          ),
        ),
      ),
    );
  }
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
