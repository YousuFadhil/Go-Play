import 'package:flutter/material.dart';

import '../../core/club_task.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import '../profile/player_identity.dart';
import '../teams/match_stage.dart';
import 'football_models.dart';
import 'football_repository.dart';

/// A completed match, as anybody signed in may read it.
///
/// **Read only, and structurally so.** There is no register button, no team
/// generation, no result entry, no roster arrangement and no delete — not
/// hidden behind a role check, but absent from the file. A reader who is not in
/// this community reaches this screen from Discover, and viewing football that
/// has been played must not be a way to acquire a capability that membership
/// grants. The screen holds a [FootballRepository] and nothing else; there is no
/// write path in reach of it.
///
/// The visual language is the one the Teams screen already established:
/// [MatchStageHeader] for the scoreline and [MatchStageSection] for each side.
/// Reused rather than restated, so a match reads the same whether a member is
/// looking at their own or a visitor is looking at somebody else's.
class FootballMatchScreen extends StatefulWidget {
  const FootballMatchScreen({
    super.key,
    required this.matchId,
    this.repository,
  });

  final String matchId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final FootballRepository? repository;

  @override
  State<FootballMatchScreen> createState() => _FootballMatchScreenState();
}

class _FootballMatchScreenState extends State<FootballMatchScreen> {
  late final FootballRepository _football =
      widget.repository ?? FootballRepository();

  late Future<CompletedMatchDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _football.fetchMatchDetail(widget.matchId);
  }

  void _refresh() {
    setState(() {
      _future = _football.fetchMatchDetail(widget.matchId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: ClubTaskBar(
        title: l10n.footballMatchTitle,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: FutureBuilder<CompletedMatchDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _refresh);
          }
          return _Loaded(detail: snapshot.data!);
        },
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.detail});

  final CompletedMatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final match = detail.match;

    return ClubTaskBody(
      // Horizontal padding is zero because every row and card below already
      // carries `kPageMargin`; the gutter would otherwise be applied twice.
      padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The scoreline, in the Teams screen's own header. It takes nullable
          // scores already, which is exactly the "played but not written up"
          // state this screen has to be able to show.
          MatchStageHeader(
            community: match.communityName,
            title: match.displayName,
            playedAt: match.startAt,
            teamAScore: match.teamAScore,
            teamBScore: match.teamBScore,
          ),

          if (!match.hasResult)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kPageMargin,
                Gap.md,
                kPageMargin,
                0,
              ),
              child: Text(
                l10n.resultPendingLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              kPageMargin,
              Gap.md,
              kPageMargin,
              0,
            ),
            child: Text(
              formatDayAndTimeRange(context, match.startAt, match.endAt),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (match.location.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kPageMargin,
                Gap.xs,
                kPageMargin,
                0,
              ),
              child: Text(
                match.location,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),

          if (match.mvp != null) ...[
            const SizedBox(height: Gap.lg),
            SectionHeading(title: l10n.mvpLabel),
            _ParticipantRow(participant: match.mvp!),
          ],

          const SizedBox(height: Gap.lg),

          // The saved lineup where there is one, and the roster where there is
          // not. A match can be played and recorded without a lineup surviving,
          // and an empty pitch would report that as though nobody turned up.
          if (detail.lineup.isNotEmpty) ...[
            _TeamBlock(
              title: l10n.teamAName,
              slots: detail.teamA,
              won: _won(match, isTeamA: true),
            ),
            const SizedBox(height: Gap.md),
            _TeamBlock(
              title: l10n.teamBName,
              slots: detail.teamB,
              won: _won(match, isTeamA: false),
            ),
          ] else ...[
            SectionHeading(title: l10n.rosterTitle),
            FootNote(
              l10n.lineupUnavailable,
              padding: const EdgeInsets.fromLTRB(
                kPageMargin,
                0,
                kPageMargin,
                Gap.sm,
              ),
            ),
            if (detail.roster.isEmpty)
              EmptyState(
                icon: Icons.groups_outlined,
                message: l10n.latestResultsEmpty,
              )
            else
              for (final entry in detail.roster)
                _ParticipantRow(participant: entry.participant),
          ],
        ],
      ),
    );
  }

  /// Which side won, for the section's own emphasis. False for both when the
  /// result is not recorded or the match was drawn — there is nothing to mark.
  bool _won(CompletedMatch match, {required bool isTeamA}) {
    final a = match.teamAScore;
    final b = match.teamBScore;
    if (!match.hasResult || a == null || b == null || a == b) return false;
    return isTeamA ? a > b : b > a;
  }
}

/// One side of the stored lineup.
class _TeamBlock extends StatelessWidget {
  const _TeamBlock({
    required this.title,
    required this.slots,
    required this.won,
  });

  final String title;
  final List<LineupSlot> slots;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return MatchStageSection(
      title: title,
      won: won,
      child: Column(
        children: [
          for (final slot in slots)
            _ParticipantRow(
              participant: slot.participant,
              position: slot.assignedPosition,
              goals: slot.goals,
              isMvp: slot.isMvp,
            ),
        ],
      ),
    );
  }
}

/// A participant, drawn the one way the product draws participants.
///
/// A registered player opens their hardened football profile; a Professional
/// Guest opens nothing. That distinction is not restated here — it is
/// [PlayerIdentityTap]'s, which renders its child untouched and unlabelled when
/// there is no user id. Passing `participant.userId` through is the whole of the
/// rule, and a guest's is null.
class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    this.position,
    this.goals = 0,
    this.isMvp = false,
  });

  final FootballParticipant participant;
  final String? position;
  final int goals;
  final bool isMvp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isGuest = participant.type == ParticipantType.professionalGuest;

    return PlayerIdentityTap(
      userId: participant.userId,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kPageMargin,
          vertical: Gap.sm,
        ),
        child: Row(
          children: [
            PlayerAvatar(
              avatarUrl: participant.avatarUrl,
              fullName: participant.displayName,
              isProfessionalGuest: isGuest,
              radius: 16,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    participant.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (position != null)
                    Text(
                      position!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (isMvp)
              const Padding(
                padding: EdgeInsetsDirectional.only(end: Gap.sm),
                child: Icon(
                  Icons.workspace_premium_outlined,
                  size: IconSize.row,
                  color: GoColors.primaryDeep,
                ),
              ),
            // The goals the read model attributed to this participant, and
            // nothing derived from them. Zero is drawn as nothing rather than
            // as "0 goals", which would be a fact nobody is asserting.
            if (goals > 0)
              Text(
                l10n.goalsShort(goals),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: GoColors.primaryDeep,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
