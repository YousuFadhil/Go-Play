import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import '../teams/pitch_view.dart';
import '../teams/team_models.dart';
import 'statistics_repository.dart';
import 'team_of_period_card.dart';
import 'team_of_period_models.dart';

/// The Team of the Week and the Team of the Month, on one pitch.
///
/// **Its own period, always.** The Statistics tab behind it may be showing All
/// Time, or the week now running; this screen is about the last week or month
/// that *finished*, which the database resolves and this never recomputes. The
/// two selectors share no state, and the heading always names the resolved
/// range rather than the word "weekly" — a reader should never have to work out
/// which week they are looking at.
class TeamOfPeriodScreen extends StatefulWidget {
  const TeamOfPeriodScreen({
    super.key,
    required this.communityId,
    this.communityName,
    this.communityLogoUrl,
    this.repository,
    this.renderer,
    this.shareService,
  });

  final String communityId;
  final String? communityName;

  /// Presentation only, and already loaded: `Community.logoUrl` travels down
  /// from the details screen rather than being read again for the card.
  final String? communityLogoUrl;

  /// Injected by tests. Production builds the default.
  final StatisticsRepository? repository;
  final ShareCardRenderer? renderer;
  final ShareService? shareService;

  @override
  State<TeamOfPeriodScreen> createState() => _TeamOfPeriodScreenState();
}

class _TeamOfPeriodScreenState extends State<TeamOfPeriodScreen> {
  late final StatisticsRepository _repository =
      widget.repository ?? StatisticsRepository();

  /// The week, by default and on every open. A month is a deliberate second
  /// question rather than the one the screen answers first.
  TeamOfPeriodKind _kind = TeamOfPeriodKind.weekly;
  late Future<_TeamOfPeriodView> _future = _load(_kind);

  Future<_TeamOfPeriodView> _load(TeamOfPeriodKind kind) async {
    final award = await _repository.fetchTeamOfPeriod(widget.communityId, kind);

    // Identities only for the players who were actually selected, and only when
    // there are any. A period nobody qualified for asks nothing of `users`.
    final ids = [for (final entry in award.selected) entry.userId];
    final identities = ids.isEmpty
        ? const <String, TeamOfPeriodPlayerIdentity>{}
        : await _repository.fetchTeamOfPeriodPlayerIdentities(ids);

    return _TeamOfPeriodView(award: award, identities: identities);
  }

  /// The snapshot a picture may be taken of.
  ///
  /// Set only when a load finishes, and cleared the instant the reader asks
  /// for a different period. That is the whole of the share discipline: the
  /// card is a picture of what is on screen, so while a month is loading there
  /// is nothing to picture and the button is off. A stale week must never
  /// leave the phone under a month's heading.
  _TeamOfPeriodView? _shareable;

  bool get _canShare {
    final view = _shareable;
    return view != null &&
        view.award.state == TeamOfPeriodState.selected &&
        view.award.selected.isNotEmpty &&
        widget.communityName != null;
  }

  Future<void> _share() async {
    final view = _shareable;
    final community = widget.communityName;
    if (view == null || community == null) return;

    // Composed from the snapshot already in hand: no award is fetched again,
    // no selector runs again, no identity is looked up again, and the period
    // is the one the database resolved.
    final data = TeamOfPeriodCardData.of(
      view.award,
      communityName: community,
      communityLogoUrl: widget.communityLogoUrl,
      identities: view.identities,
      nameOf: (userId) =>
          view.identities[userId]?.fullName ??
          context.l10n.teamOfPeriodPlayerFallback,
    );

    // Two frames is all the engine gives a template to settle, which is ample
    // for layout and nowhere near enough for a network image. Best effort: a
    // face or a crest that will not load falls back rather than failing the
    // card.
    await precacheShareCardFaces(context, data.imageUrls);
    if (!mounted) return;

    await presentShareCard(
      context,
      template: (_) => TeamOfPeriodCard(data: data),
      communityId: widget.communityId,
      renderer: widget.renderer,
      shareService: widget.shareService,
    );
  }

  void _select(TeamOfPeriodKind kind) {
    if (kind == _kind) return;
    // The future is replaced in the same frame as the selection, so the old
    // team cannot be painted for even one frame under the new heading. A month
    // shown under a week's dates is the one mistake this screen must not make.
    setState(() {
      _kind = kind;
      _shareable = null;
      _future = _load(kind);
    });
  }

  void _retry() {
    // A block body, not an arrow: an arrow would return the assignment's value
    // -- a Future -- to setState, which asserts against exactly that.
    setState(() {
      _shareable = null;
      _future = _load(_kind);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.communityName ?? l10n.teamOfPeriodTitle),
        actions: [
          IconButton(
            key: const ValueKey('team-of-period-share'),
            // Present but disabled rather than absent, so the action does not
            // appear and vanish as the reader switches period. There is
            // nothing to picture while a period is loading, when the read
            // failed, when nobody played and when nobody qualified.
            onPressed: _canShare ? _share : null,
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.shareCardShareAction,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kPageMargin,
              Gap.lg,
              kPageMargin,
              Gap.sm,
            ),
            child: SegmentedButton<TeamOfPeriodKind>(
              segments: [
                ButtonSegment(
                  value: TeamOfPeriodKind.weekly,
                  label: Text(l10n.teamOfPeriodWeekTab),
                ),
                ButtonSegment(
                  value: TeamOfPeriodKind.monthly,
                  label: Text(l10n.teamOfPeriodMonthTab),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _select(selection.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<_TeamOfPeriodView>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingState();
                }
                if (snapshot.hasError) {
                  return ErrorState(onRetry: _retry);
                }
                // The snapshot is adopted as the shareable one only once it is
                // the thing on screen. Assigning during build is why it is
                // scheduled: the button belongs to the frame after this one.
                final view = snapshot.data!;
                if (!identical(_shareable, view)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _shareable = view);
                  });
                }
                return _TeamOfPeriodBody(view: view);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The award and the faces to draw it with.
class _TeamOfPeriodView {
  const _TeamOfPeriodView({required this.award, required this.identities});

  final TeamOfPeriod award;
  final Map<String, TeamOfPeriodPlayerIdentity> identities;
}

class _TeamOfPeriodBody extends StatelessWidget {
  const _TeamOfPeriodBody({required this.view});

  final _TeamOfPeriodView view;

  /// The resolved period, spelled out.
  ///
  /// Never a bare "Weekly": the whole point of the heading is that a reader can
  /// tell one week from another. The dates are the ones the database resolved
  /// and are only formatted here.
  static String periodLabel(BuildContext context, TeamOfPeriodWindow window) {
    final l10n = context.l10n;
    return switch (window.kind) {
      TeamOfPeriodKind.weekly => '${l10n.teamOfPeriodWeekHeading} · '
          '${formatAwardWeek(context, window.periodStart, window.periodEnd)}',
      TeamOfPeriodKind.monthly => '${l10n.teamOfPeriodMonthHeading} · '
          '${formatAwardMonth(context, window.periodStart)}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final award = view.award;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Gap.xxl),
      children: [
        SectionHeading(
          title: periodLabel(context, award.window),
          padding: const EdgeInsets.fromLTRB(
            kPageMargin,
            Gap.sm,
            kPageMargin,
            Gap.md,
          ),
        ),
        switch (award.state) {
          // No football, so no team and no pitch. The period is still named
          // above, which is the answer the reader came for.
          TeamOfPeriodState.noQualifyingMatches => Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
              child: EmptyState(
                icon: Icons.event_busy_outlined,
                message: l10n.teamOfPeriodNoMatches,
              ),
            ),
          // Matches were played and nobody played enough of them. The bar is
          // stated rather than softened.
          TeamOfPeriodState.insufficientEligiblePlayers => Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
              child: EmptyState(
                icon: Icons.groups_outlined,
                message: l10n.teamOfPeriodNoEligible(
                  award.window.requiredMatches,
                ),
              ),
            ),
          TeamOfPeriodState.selected => _AwardPitch(view: view),
        },
        if (award.state == TeamOfPeriodState.selected)
          FootNote(l10n.teamOfPeriodCurrentRatingNote),
      ],
    );
  }
}

/// The selected team on one pitch.
///
/// One side, never two: this is an award rather than a fixture, so there is no
/// Team A and no opponent. A team smaller than the period asked for is drawn
/// smaller — nothing pads it with blanks, because a missing seat is evidence
/// that nobody qualified for it rather than a hole to fill.
class _AwardPitch extends StatelessWidget {
  const _AwardPitch({required this.view});

  final _TeamOfPeriodView view;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final award = view.award;

    // Presentation-only assignments, built to reuse the pitch's established
    // participant vocabulary and never written anywhere. `basis` is null on
    // purpose: a Period Primary is not an `AssignmentBasis`, and calling it one
    // would put historical award evidence into a field that means how an engine
    // placed somebody in a match.
    final assignments = [
      for (final entry in award.selected)
        TeamAssignment(
          userId: entry.userId,
          team: TeamId.a,
          assignedPosition: entry.assignedPosition,
          basis: null,
        ),
    ];
    final byId = {for (final entry in award.selected) entry.userId: entry};

    String nameOf(String userId) =>
        view.identities[userId]?.fullName ?? l10n.teamOfPeriodPlayerFallback;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
          child: PitchView(
            pitchKey: const ValueKey('team-of-period-pitch'),
            assignments: assignments,
            // The award's own rows, strictly. No formation borrowing.
            layout: PitchLayoutMode.exactAssignedPositions,
            nameOf: nameOf,
            avatarUrlOf: (userId) => view.identities[userId]?.avatarUrl,
            // Presentation only, and the note under the pitch says so. It is
            // the player's rating today rather than what they held that week.
            ratingOf: (userId) => byId[userId]?.candidate.currentOverallRating,
            goalsOf: (userId) => byId[userId]?.candidate.goals ?? 0,
            isMvpOf: (userId) => (byId[userId]?.candidate.mvpCount ?? 0) > 0,
            onTapPlayer: (assignment) {
              final entry = byId[assignment.participantId];
              if (entry == null) return;
              showPlayerPeriodDetail(
                context,
                selection: entry,
                name: nameOf(entry.userId),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// What one awarded player did during the period.
///
/// **Not their profile.** Every figure here is about this period and comes from
/// the evidence the award was decided on, so nothing is read when it opens.
///
/// The Period Form Score is deliberately absent. It is the selector's internal
/// measure of form, on a scale nobody has been shown and nothing explains; put
/// on a card beside goals and wins it would read as a score the player earned,
/// and the first question would be what a good one is.
Future<void> showPlayerPeriodDetail(
  BuildContext context, {
  required TeamOfPeriodSelection selection,
  required String name,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _PlayerPeriodDetail(
        selection: selection,
        name: name,
      ),
    );

class _PlayerPeriodDetail extends StatelessWidget {
  const _PlayerPeriodDetail({required this.selection, required this.name});

  final TeamOfPeriodSelection selection;
  final String name;

  static String positionLabel(AppLocalizations l10n, Position position) =>
      switch (position) {
        Position.gk => l10n.positionGk,
        Position.def => l10n.positionDef,
        Position.mid => l10n.positionMid,
        Position.fwd => l10n.positionFwd,
      };

  String _percent(BuildContext context, double ratio) =>
      '${(ratio * 100).round()}%';

  String _decimal(double value) => value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final candidate = selection.candidate;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          kPageMargin,
          0,
          kPageMargin,
          Gap.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleLarge),
            const SizedBox(height: Gap.xs),
            Text(
              '${l10n.teamOfPeriodAwardedPosition}: '
              '${positionLabel(l10n, selection.assignedPosition)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Gap.lg),
            for (final (label, value) in [
              // Labelled "current" wherever it appears, because it is the one
              // figure here that is not about the period.
              (l10n.teamOfPeriodCurrentRating,
                  _decimal(candidate.currentOverallRating)),
              (l10n.teamOfPeriodMatchesPlayed, '${candidate.matchesPlayed}'),
              (
                l10n.teamOfPeriodParticipation,
                _percent(context, candidate.participationRate)
              ),
              (l10n.teamOfPeriodGoals, '${candidate.goals}'),
              (
                l10n.teamOfPeriodGoalsPerMatch,
                _decimal(candidate.goalsPerMatch)
              ),
              (
                l10n.teamOfPeriodRecord,
                '${candidate.wins} / ${candidate.draws} / ${candidate.losses}'
              ),
              (l10n.teamOfPeriodWinRate, _percent(context, candidate.winRate)),
              (
                l10n.teamOfPeriodPointsPerGame,
                _decimal(candidate.pointsPerGame)
              ),
              (l10n.teamOfPeriodMvpCount, '${candidate.mvpCount}'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodyMedium),
                    ),
                    Text(
                      value,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Gap.sm),
            FootNote(l10n.teamOfPeriodCurrentRatingNote),
          ],
        ),
      ),
    );
  }
}
