import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import 'stat_card.dart';
import 'statistics_models.dart';
import 'statistics_repository.dart';

/// The Community Dashboard: what this community has done, and who leads it.
///
/// It owns its own load rather than joining the details screen's, for one
/// practical reason — a recorded result changes these figures and nothing else
/// on that screen, so the dashboard needs to be refreshable on its own. Pulling
/// down does it.
class CommunityDashboardTab extends StatefulWidget {
  const CommunityDashboardTab({
    super.key,
    required this.communityId,
    StatisticsRepository? repository,
  }) : _repository = repository;

  final String communityId;
  final StatisticsRepository? _repository;

  @override
  State<CommunityDashboardTab> createState() => _CommunityDashboardTabState();
}

class _CommunityDashboardTabState extends State<CommunityDashboardTab> {
  late final StatisticsRepository _repository =
      widget._repository ?? StatisticsRepository();
  late Future<CommunityDashboard> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _repository.fetchDashboard(widget.communityId);
  }

  Future<void> _refresh() async {
    final future = _repository.fetchDashboard(widget.communityId);
    // A block body, not an arrow: `() => _dashboardFuture = future` evaluates
    // to the assigned Future, and setState asserts when its callback returns
    // one.
    setState(() {
      _dashboardFuture = future;
    });
    // Awaited only so the refresh indicator stays up until the figures land.
    // A failure is swallowed here rather than ignored: the builder below is
    // already showing it, and letting it escape would be an unhandled error
    // from a gesture the user has had an answer to.
    await future.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CommunityDashboard>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return ErrorState(onRetry: _refresh);
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: _DashboardBody(dashboard: snapshot.data!),
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.dashboard});

  final CommunityDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final noLeaders = dashboard.topScorer == null &&
        dashboard.mostActivePlayer == null &&
        dashboard.mostMvp == null;

    return ListView(
      // Always scrollable, so pulling down refreshes even when the content is
      // shorter than the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Gap.xxl),
      children: [
        SectionHeading(
          title: l10n.communityStatisticsTitle,
          padding: const EdgeInsets.fromLTRB(
            kPageMargin,
            Gap.lg,
            kPageMargin,
            Gap.sm,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageMargin - 4),
          // The three cards are as tall as the tallest of them, so a label
          // that wraps to two lines does not leave its neighbours short.
          // `IntrinsicHeight` is what gives the stretch a height to work
          // from — inside a ListView the row's vertical extent is otherwise
          // unbounded, and stretching against that is an error rather than a
          // layout.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatCard(
                    icon: Icons.event_available,
                    label: l10n.statCompletedMatches,
                    value: dashboard.completedMatches,
                  ),
                ),
                Expanded(
                  child: StatCard(
                    icon: Icons.group,
                    label: l10n.statTotalPlayers,
                    value: dashboard.totalPlayers,
                  ),
                ),
                Expanded(
                  child: StatCard(
                    icon: Icons.sports_soccer,
                    label: l10n.statTotalGoals,
                    value: dashboard.totalGoals,
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionHeading(title: l10n.statLeadersTitle),
        if (noLeaders)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
            child: EmptyState(
              icon: Icons.emoji_events_outlined,
              message: l10n.statEmptyBody,
            ),
          )
        else
          SectionCard(
            padding: EdgeInsets.zero,
            children: [
              LeaderTile(
                icon: Icons.sports_soccer,
                label: l10n.statTopScorer,
                leader: dashboard.topScorer,
                describeValue: l10n.goalsScoredLabel,
              ),
              LeaderTile(
                icon: Icons.directions_run,
                label: l10n.statMostActivePlayer,
                leader: dashboard.mostActivePlayer,
                describeValue: l10n.statMatchesPlayedValue,
              ),
              LeaderTile(
                icon: Icons.star,
                label: l10n.statMostMvp,
                leader: dashboard.mostMvp,
                describeValue: l10n.statMvpValue,
              ),
            ],
          ),
        FootNote(l10n.statScopeNote),
      ],
    );
  }
}

/// Who leads one measure, or that nobody does yet.
///
/// [describeValue] renders the figure in the measure's own words — goals,
/// matches, or times — so the tile never shows a bare number whose unit the
/// reader has to infer from the label above it.
class LeaderTile extends StatelessWidget {
  const LeaderTile({
    super.key,
    required this.icon,
    required this.label,
    required this.leader,
    required this.describeValue,
  });

  final IconData icon;
  final String label;
  final StatisticLeader? leader;
  final String Function(int) describeValue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final leader = this.leader;

    return ListTile(
      leading: CircleAvatar(
        // A measure nobody leads is drawn quietly. Giving "Not yet" the same
        // coloured disc as a real leader makes an absence look like a result.
        backgroundColor: leader == null
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        foregroundColor: leader == null
            ? scheme.onSurfaceVariant
            : scheme.onPrimaryContainer,
        child: Icon(icon, size: 20),
      ),
      title: Text(label, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        leader == null
            ? l10n.statNoneYet
            // A record can outlive the profile it describes: the account was
            // soft-deleted and its figures stayed. The measure is still true,
            // so the tile keeps it and says who it belonged to as best it can.
            : leader.fullName ?? l10n.statFormerPlayer,
        style: theme.textTheme.titleSmall?.copyWith(
          color: leader == null ? scheme.onSurfaceVariant : scheme.onSurface,
        ),
      ),
      trailing: leader == null
          ? null
          : Text(
              describeValue(leader.value),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
    );
  }
}
