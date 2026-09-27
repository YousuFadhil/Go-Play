import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/responsive_grid.dart';
import '../../core/states.dart';
import 'community_insights_adapter.dart';
import 'community_insights_repository.dart';

/// Organizer-only operational view of one community.
///
/// It is intentionally not another Community Statistics tab. Statistics answers
/// what happened on the pitch; this answers whether the community is active and
/// whether match capacity is meeting participation demand.
class CommunityInsightsScreen extends StatefulWidget {
  const CommunityInsightsScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.repository,
  });

  final String communityId;
  final String communityName;
  final CommunityInsightsRepository? repository;

  @override
  State<CommunityInsightsScreen> createState() =>
      _CommunityInsightsScreenState();
}

class _CommunityInsightsScreenState extends State<CommunityInsightsScreen> {
  late final CommunityInsightsRepository _repository =
      widget.repository ?? CommunityInsightsRepository();
  late Future<CommunityInsights> _future = _repository.fetch(widget.communityId);

  Future<void> _refresh() async {
    final next = _repository.fetch(widget.communityId);
    setState(() => _future = next);
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: Text(context.l10n.communityInsightsTitle)),
      body: FutureBuilder<CommunityInsights>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _refresh);
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: _Body(
              communityName: widget.communityName,
              insights: snapshot.data!,
            ),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.communityName,
    required this.insights,
  });

  final String communityName;
  final CommunityInsights insights;

  String _percent(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Layout.sheetGutter,
        Gap.lg,
        Layout.sheetGutter,
        Gap.xxl,
      ),
      children: [
        Text(
          communityName,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: Gap.xs),
        Text(
          l10n.communityInsightsPeriod,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: Gap.lg),
        ResponsiveCardGrid(
          maxColumns: 2,
          minCardWidth: GridCard.communityMinWidth,
          children: [
            _InsightCard(
              icon: Icons.people_outline,
              label: l10n.communityInsightsActiveMembers,
              value:
                  '${insights.activeMembers30d} / ${insights.eligibleMembers}',
            ),
            _InsightCard(
              icon: Icons.pie_chart_outline,
              label: l10n.communityInsightsParticipationRate,
              value: _percent(insights.participationRate30d),
            ),
            _InsightCard(
              icon: Icons.repeat,
              label: l10n.communityInsightsMatchFrequency,
              value: insights.matchesPerWeek.toStringAsFixed(2),
              suffix: l10n.communityInsightsPerWeek,
            ),
            _InsightCard(
              icon: Icons.event_seat_outlined,
              label: l10n.communityInsightsCapacity,
              value: _percent(insights.avgCapacityUtilization),
            ),
            _InsightCard(
              icon: Icons.person_add_alt_1_outlined,
              label: l10n.communityInsightsGuestDependency,
              value: _percent(insights.guestDependency),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        Text(
          l10n.communityInsightsProvisionalNote,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.label,
    required this.value,
    this.suffix,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: Gap.sm),
            Text(value, style: theme.textTheme.headlineSmall),
            if (suffix != null)
              Text(
                suffix!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: Gap.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
