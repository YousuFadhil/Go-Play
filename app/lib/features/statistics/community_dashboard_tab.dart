import 'package:flutter/material.dart';

import '../../core/l10n.dart';
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
    final l10n = context.l10n;

    return FutureBuilder<CommunityDashboard>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.loadFailed),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _refresh,
                  child: Text(l10n.retryButton),
                ),
              ],
            ),
          );
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionHeader(title: l10n.communityStatisticsTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    icon: Icons.sports_soccer,
                    label: l10n.statTotalMatches,
                    value: dashboard.totalMatches,
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
                    icon: Icons.scoreboard,
                    label: l10n.statTotalGoals,
                    value: dashboard.totalGoals,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SectionHeader(title: l10n.statLeadersTitle),
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
        if (noLeaders)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.statEmptyBody,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Text(
            l10n.statScopeNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
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
    final leader = this.leader;

    return ListTile(
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(label),
      subtitle: Text(
        leader == null
            ? l10n.statNoneYet
            // A record can outlive the profile it describes: the account was
            // soft-deleted and its figures stayed. The measure is still true,
            // so the tile keeps it and says who it belonged to as best it can.
            : leader.fullName ?? l10n.statFormerPlayer,
      ),
      trailing: leader == null ? null : Text(describeValue(leader.value)),
    );
  }
}
