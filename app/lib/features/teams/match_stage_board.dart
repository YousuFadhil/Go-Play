import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'match_stage.dart';
import 'pitch_view.dart';
import 'team_models.dart';

/// The Match Stage as a whole surface, rather than as the parts of one.
///
/// [MatchStageHeader] and [MatchStageSection] were already shared between the
/// Teams screen and the share card, but the *composition* of them was not: the
/// dark ground, the bar over it, the gap between the header and the first team,
/// the padding around each section and the pitch inside it all lived inside
/// `TeamsScreen`. A second screen showing the same match could reuse the pieces
/// and still arrive somewhere else, which is exactly what the public football
/// screen did — the same header over two lists of names.
///
/// So the arrangement moves here, and the two screens that show a match now
/// differ in what they may *do* with it rather than in what it looks like.
/// Nothing in this file reads a repository, knows a role, or offers an action:
/// it is handed a lineup and draws it. Which lineup, whether the reader may
/// touch it, and what happens when they do are decided by the screen above.

/// The scale every Match Stage surface is drawn at.
///
/// The approved masters are 941 wide (`MatchStage.referenceWidth`) and
/// everything on this surface is a fraction of that, so a phone of any width
/// gets the same drawing at a different size. Shared as one function because two
/// screens computing it separately is two chances to disagree.
double matchStageScreenScale(BuildContext context) =>
    MediaQuery.sizeOf(context).width / MatchStage.referenceWidth;

/// The bar that belongs over the dark ground.
///
/// A function rather than a widget because [Scaffold.appBar] wants a
/// [PreferredSizeWidget], and the height here is a function of the screen's
/// width — which a `preferredSize` getter cannot see. Returning the [AppBar]
/// itself keeps the preferred size the real one.
///
/// [actions] is where a screen puts what it is allowed to offer, and is the only
/// seam through which anything on this bar differs between the two callers.
AppBar matchStageAppBar(
  BuildContext context, {
  Key? key,
  required String title,
  List<Widget> actions = const [],
}) {
  final screenScale = matchStageScreenScale(context);
  return AppBar(
    key: key,
    toolbarHeight: 82 * screenScale,
    backgroundColor: MatchStage.ground,
    foregroundColor: Colors.white,
    iconTheme: const IconThemeData(color: Colors.white),
    actionsIconTheme: const IconThemeData(color: Colors.white),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    leadingWidth: 82 * screenScale,
    titleSpacing: 0,
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 35 * screenScale,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: MatchStage.ink,
      ),
    ),
    leading: IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: Icon(Icons.arrow_back, size: 34 * screenScale),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    ),
    actions: actions,
  );
}

/// The dark ground a match is drawn on.
///
/// The watermark is the one decoration on it: a ball, large, cropped by the
/// corner and barely lighter than what it sits on. It says "football" without
/// competing with a single player.
class MatchStageGround extends StatelessWidget {
  const MatchStageGround({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF063126), MatchStage.ground],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              key: const ValueKey('match-stage-ball-right'),
              top: -72,
              right: -64,
              child: Icon(
                Icons.sports_soccer,
                size: 230,
                color: Colors.white.withValues(alpha: 0.055),
              ),
            ),
            Positioned(
              key: const ValueKey('match-stage-ball-left'),
              top: -82,
              left: -84,
              child: Icon(
                Icons.sports_soccer,
                size: 210,
                color: Colors.white.withValues(alpha: 0.045),
              ),
            ),
            child,
          ],
        ),
      );
}

/// One match, drawn: the header, then Team A, then Team B.
///
/// **The result is not a second state to build, it is these same three things
/// with the scores present.** [teamAScore] and [teamBScore] both null is a
/// lineup that has not been played yet; both present grows the score strip in
/// the header, marks the winning side and puts each player's goals and the MVP
/// star on the pitch. There is no branch here that a caller has to know about —
/// passing the scores is the whole of it, which is what stops the Teams screen
/// and the public football screen from drifting into two different ideas of
/// what a finished match looks like.
class MatchStageBoard extends StatelessWidget {
  const MatchStageBoard({
    super.key,
    required this.lineup,
    required this.players,
    required this.nameOf,
    required this.hasNaturalGoalkeeper,
    this.communityName,
    this.matchTitle,
    this.playedAt,
    this.teamAScore,
    this.teamBScore,
    this.goalsOf,
    this.isMvpOf,
    this.onTapPlayer,
  });

  /// The stored lineup, both sides. Split by [team] below rather than taken as
  /// two lists, so the two can never be assembled from different reads.
  final List<TeamAssignment> lineup;

  /// The profiles behind the assignments: the face and the rating each card
  /// shows. A participant with no entry is still drawn from the assignment
  /// alone — `KB-017` records that they played.
  final Map<String, PlayerCoreInputs> players;

  /// What to call a participant. The caller's rule, applied once and handed
  /// over, because who a lineup row belongs to is a question about that
  /// screen's data and not about this drawing.
  final String Function(String participantId) nameOf;

  /// Whether anybody in the squad keeps goal (§10.1). The pitch draws a
  /// goalkeeper position only when this holds.
  final bool hasNaturalGoalkeeper;

  final String? communityName;
  final String? matchTitle;
  final DateTime? playedAt;

  /// Both null until a result exists. See the class comment.
  final int? teamAScore;
  final int? teamBScore;

  final int Function(String participantId)? goalsOf;
  final bool Function(String participantId)? isMvpOf;

  /// What tapping a player does, or null for a board nobody may touch. This is
  /// the one place the two callers legitimately differ, and it is a callback
  /// rather than a capability flag on purpose: this widget cannot be told a
  /// role, so it cannot be the thing that gets a role check wrong.
  final void Function(TeamAssignment assignment)? onTapPlayer;

  bool get hasResult => teamAScore != null && teamBScore != null;

  /// The side that won, or null when the match was drawn or has no result.
  TeamId? get winner {
    if (!hasResult || teamAScore == teamBScore) return null;
    return teamAScore! > teamBScore! ? TeamId.a : TeamId.b;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenScale = matchStageScreenScale(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The one header, in both states. Before a result it is the community,
        // the match and the date; after one it grows the score strip, and
        // nothing else about the surface changes.
        SizedBox(height: 8 * screenScale),
        MatchStageHeader(
          community: communityName,
          title: matchTitle,
          playedAt: playedAt,
          teamAScore: teamAScore,
          teamBScore: teamBScore,
        ),
        SizedBox(height: (hasResult ? 17 : 50) * screenScale),
        _section(
          context,
          title: l10n.teamAName,
          team: TeamId.a,
          bottomGap: hasResult ? 14 : 28,
          screenScale: screenScale,
        ),
        _section(
          context,
          title: l10n.teamBName,
          team: TeamId.b,
          bottomGap: 20,
          screenScale: screenScale,
        ),
      ],
    );
  }

  /// One side: heading, winner mark and pitch inside a single dark block, so a
  /// team reads as one thing rather than as a title floating over a detached
  /// pitch.
  ///
  /// `A` and `B` distinguish the two sides and mean nothing else (`KB-D6`), so
  /// neither is presented as the stronger or the first-choice team.
  Widget _section(
    BuildContext context, {
    required String title,
    required TeamId team,
    required double bottomGap,
    required double screenScale,
  }) {
    final assignments = [
      for (final assignment in lineup)
        if (assignment.team == team) assignment,
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        21 * screenScale,
        0,
        22 * screenScale,
        bottomGap * screenScale,
      ),
      child: MatchStageSection(
        title: title,
        won: winner == team,
        team: team,
        child: PitchView(
          assignments: assignments,
          players: players,
          hasNaturalGoalkeeper: hasNaturalGoalkeeper,
          nameOf: nameOf,
          // Null before a result exists, which leaves every card exactly what
          // it was. The same pitch, drawn after the match, carries what each
          // player did on the player.
          goalsOf: hasResult ? goalsOf : null,
          isMvpOf: hasResult ? isMvpOf : null,
          team: team,
          pitchKey: ValueKey(
            team == TeamId.a ? 'team-a-pitch' : 'team-b-pitch',
          ),
          onTapPlayer: onTapPlayer,
        ),
      ),
    );
  }
}
