import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../profile/player_identity.dart';
import '../teams/match_stage.dart';
import '../teams/match_stage_board.dart';
import 'completed_match_presentation.dart';
import 'football_repository.dart';

/// A completed match a signed-in reader is looking at, drawn on the stage.
///
/// **One member adapter, two routes.** `FootballMatchScreen` reached a played
/// match from Discover and drew it here; `MatchDetailsScreen` reached the same
/// match from a community and drew a roster list on a white sheet instead, so
/// a member's own football looked like a different product from a stranger's
/// view of it. This is the drawing both of them mount, extracted rather than
/// copied -- a second adapter is exactly how the two would drift again.
///
/// It is presentation and nothing else: it holds no repository, decides no
/// role and offers no action beyond opening a player. What a reader may *do*
/// with the match belongs to the screen around it.
class MemberMatchStage extends StatelessWidget {
  const MemberMatchStage({
    super.key,
    required this.detail,
    required this.presentation,
    this.onTapPlayer,
  });

  final CompletedMatchDetail detail;
  final CompletedMatchPresentation presentation;

  /// Where a participant's name leads. A Professional Guest has no account and
  /// leads nowhere, which is the callback's own rule rather than a flag here.
  final void Function(String userId)? onTapPlayer;

  @override
  Widget build(BuildContext context) {
    final match = detail.match;
    final open = onTapPlayer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (presentation.hasLineup)
          MatchStageBoard(
            lineup: presentation.lineup,
            players: presentation.players,
            nameOf: presentation.nameOf,
            hasNaturalGoalkeeper: presentation.hasNaturalGoalkeeper,
            communityName: match.communityName,
            matchTitle: match.displayName,
            playedAt: match.startAt,
            teamAScore: match.teamAScore,
            teamBScore: match.teamBScore,
            goalsOf: presentation.goalsOf,
            isMvpOf: presentation.isMvpOf,
            onTapPlayer: open == null
                ? null
                : (assignment) {
                    final userId = assignment.userId;
                    if (userId != null) open(userId);
                  },
          )
        else ...[
          // **No pitch.** An empty one would report that nobody turned up,
          // which is a different claim from "the teams were not saved".
          const SizedBox(height: Gap.md),
          MatchStageHeader(
            community: match.communityName,
            title: match.displayName,
            playedAt: match.startAt,
            teamAScore: match.teamAScore,
            teamBScore: match.teamBScore,
          ),
        ],
        _MatchFacts(detail: detail),
      ],
    );
  }
}

/// When and where it was played, and whether anybody has written it up yet.
///
/// The header already carries the community, the match and the date; this is
/// the rest of what a reader who was not there needs, set in the stage's own
/// muted ink so it belongs to the surface rather than to a document pasted
/// onto it.
class _MatchFacts extends StatelessWidget {
  const _MatchFacts({required this.detail});

  final CompletedMatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final match = detail.match;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!match.hasResult)
          _StageNote(
            l10n.resultPendingLabel,
            color: MatchStage.ink,
            padding: const EdgeInsets.fromLTRB(
              kPageMargin,
              Gap.sm,
              kPageMargin,
              0,
            ),
          ),
        _StageNote(
          formatDayAndTimeRange(context, match.startAt, match.endAt),
          padding: const EdgeInsets.fromLTRB(
            kPageMargin,
            Gap.sm,
            kPageMargin,
            0,
          ),
        ),
        if (match.location.isNotEmpty)
          _StageNote(
            match.location,
            padding: const EdgeInsets.fromLTRB(
              kPageMargin,
              Gap.xs,
              kPageMargin,
              0,
            ),
          ),
      ],
    );
  }
}

/// One line of quiet type on the ground.
class _StageNote extends StatelessWidget {
  const _StageNote(this.text, {required this.padding, this.color});

  final String text;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.3,
            fontWeight: color == null ? FontWeight.w400 : FontWeight.w700,
            color: color ?? Colors.white.withValues(alpha: 0.72),
          ),
        ),
      );
}

/// Opens a participant's football profile, where they have one.
void openMemberMatchPlayer(BuildContext context, String userId) =>
    openPlayerProfile(context, userId);
