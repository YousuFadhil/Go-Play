import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// Stands in for a figure that genuinely has no value.
///
/// Used for weekly retention and nothing else. It is **not** a zero: see
/// [_RetentionTile].
const _unavailable = '—';

/// The Platform Admin Overview: is anybody using this, and where.
///
/// **One call, one screen.** Every figure here comes from a single
/// `admin_analytics_overview()` round trip -- not fourteen -- so the dashboard
/// either has all of its numbers or has an error and a retry, and never shows a
/// half-filled page while the rest arrives.
///
/// **Two signals lead, and they lead visually.** Weekly Active Users and
/// Weekly Active Communities are the product's health; the rest is detail that
/// explains them. So those two are large and first, and the sections below are
/// a grid of small tiles. There are no charts in this cycle and no chart
/// package: a figure and its label answer the question being asked.
class AdminOverviewTab extends StatefulWidget {
  const AdminOverviewTab({super.key, required this.repository});

  final AdminRepository repository;

  @override
  State<AdminOverviewTab> createState() => _AdminOverviewTabState();
}

class _AdminOverviewTabState extends State<AdminOverviewTab> {
  late Future<AdminAnalyticsOverview> _future = widget.repository
      .analyticsOverview();

  /// Re-reads. One new call, replacing the old future rather than adding to it.
  void _reload() {
    // Block-bodied: an arrow here returns the assigned Future, which trips
    // `setState() callback argument returned a Future` in debug.
    setState(() {
      _future = widget.repository.analyticsOverview();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<AdminAnalyticsOverview>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState();
        }
        // The same error surface every other admin list uses. A dashboard of
        // zeroes would be worse than no dashboard: it reads as a true answer.
        if (snapshot.hasError || !snapshot.hasData) {
          return ErrorState(onRetry: _reload);
        }

        final overview = snapshot.data!;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              kPageMargin,
              Gap.lg,
              kPageMargin,
              Layout.listBottom,
            ),
            children: [
              _SectionHeading(l10n.adminProductHealthTitle),
              // The two that matter, side by side and larger than everything
              // below them.
              //
              // [IntrinsicHeight] is what lets the two tiles match: they carry
              // labels of different lengths, and without it the shorter one is
              // a shorter card sitting beside a taller one. `stretch` alone
              // cannot do it inside a [ListView] — the row's height is
              // unbounded there, so there is nothing to stretch to.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _HeadlineTile(
                        label: l10n.adminMetricWau,
                        value: '${overview.wau}',
                      ),
                    ),
                    const SizedBox(width: Layout.cardGap),
                    Expanded(
                      child: _HeadlineTile(
                        label: l10n.adminMetricActiveCommunities,
                        value: '${overview.weeklyActiveCommunities}',
                      ),
                    ),
                  ],
                ),
              ),

              _SectionHeading(l10n.adminUserGrowthTitle),
              _MetricGrid(children: [
                _MetricTile(
                  label: l10n.adminMetricTotalUsers,
                  value: '${overview.totalUsers}',
                ),
                _MetricTile(
                  label: l10n.adminMetricNewToday,
                  value: '${overview.newUsersToday}',
                ),
                _MetricTile(
                  label: l10n.adminPeriod7d,
                  value: '${overview.newUsers7d}',
                ),
                _MetricTile(
                  label: l10n.adminPeriod30d,
                  value: '${overview.newUsers30d}',
                ),
              ]),

              _SectionHeading(l10n.adminEngagementTitle),
              _MetricGrid(children: [
                _MetricTile(
                  label: l10n.adminMetricDau,
                  value: '${overview.dau}',
                ),
                _MetricTile(
                  label: l10n.adminMetricWau,
                  value: '${overview.wau}',
                ),
                _MetricTile(
                  label: l10n.adminMetricMau,
                  value: '${overview.mau}',
                ),
                _RetentionTile(overview: overview),
              ]),

              _SectionHeading(l10n.adminFootballActivityTitle),
              _MetricGrid(children: [
                _MetricTile(
                  label: '${l10n.adminMetricMatches} · ${l10n.adminPeriod7d}',
                  value: '${overview.matches7d}',
                ),
                _MetricTile(
                  label: '${l10n.adminMetricMatches} · ${l10n.adminPeriod30d}',
                  value: '${overview.matches30d}',
                ),
                _MetricTile(
                  label:
                      '${l10n.adminMetricRegistrations} · ${l10n.adminPeriod7d}',
                  value: '${overview.registrations7d}',
                ),
                _MetricTile(
                  label:
                      '${l10n.adminMetricRegistrations} · ${l10n.adminPeriod30d}',
                  value: '${overview.registrations30d}',
                ),
                _MetricTile(
                  label: '${l10n.adminMetricResults} · ${l10n.adminPeriod7d}',
                  value: '${overview.results7d}',
                ),
                _MetricTile(
                  label: '${l10n.adminMetricResults} · ${l10n.adminPeriod30d}',
                  value: '${overview.results30d}',
                ),
              ]),

              const SizedBox(height: Gap.xl),
              const _TrackingNotice(),
            ],
          ),
        );
      },
    );
  }
}

/// The name of a group of figures.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(
          top: Layout.sectionAbove,
          bottom: Layout.sectionBelow,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

/// A wrapping row of small tiles, two to a line on a phone.
///
/// [Wrap] rather than a `GridView`: the sections have four and six tiles, the
/// page is already a [ListView], and a nested scrollable would be a scroll
/// inside a scroll for no gain.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - Layout.cardGap) / 2;
        return Wrap(
          spacing: Layout.cardGap,
          runSpacing: Layout.cardGap,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// The shared shape of every figure on this page.
class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.emphasised = false});

  final Widget child;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(Layout.cardInner),
      decoration: BoxDecoration(
        color: emphasised
            ? scheme.primaryContainer
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Radii.card),
        border: emphasised
            ? null
            : Border.all(color: scheme.outlineVariant, width: 1),
      ),
      child: child,
    );
  }
}

/// One of the two Product Health figures.
class _HeadlineTile extends StatelessWidget {
  const _HeadlineTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onPrimaryContainer;

    return _Tile(
      emphasised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.displaySmall?.copyWith(
              color: onContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: onContainer),
          ),
        ],
      ),
    );
  }
}

/// One figure, and what it is.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.footnote,
    this.semanticValue,
  });

  final String label;
  final String value;

  /// A line under the figure, for a figure that needs one.
  final String? footnote;

  /// What a screen reader should say instead of [value], for a figure whose
  /// printed form is a symbol rather than a word.
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            semanticsLabel: semanticValue,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              footnote!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Weekly retention, which is the one figure that can genuinely be absent.
///
/// **An em dash, never 0%.** A null percentage means there was no previous-week
/// cohort — nobody had a session in the week before last, so there is nobody
/// who could have come back. Printing 0% would state that a cohort existed and
/// none of them returned, which is a different and much worse claim about the
/// product. The dash is given a spoken form of its own, because a screen reader
/// announcing "dash" tells the administrator nothing.
class _RetentionTile extends StatelessWidget {
  const _RetentionTile({required this.overview});

  final AdminAnalyticsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final percent = overview.weeklyRetentionPercent;

    return _MetricTile(
      label: l10n.adminMetricWeeklyRetention,
      value: percent == null ? _unavailable : '${_trim(percent)}%',
      semanticValue: percent == null ? l10n.adminMetricUnavailable : null,
      // What the percentage is made of, so a figure computed from four people
      // is not read as the same evidence as one computed from four hundred.
      footnote: l10n.adminRetentionBasis(
        overview.retentionReturningUsers,
        overview.retentionPreviousWeekUsers,
      ),
    );
  }

  /// `40.0` reads better as `40`; `37.5` keeps its half.
  static String _trim(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';
}

/// Where the figures above begin, said once and quietly.
///
/// **Not a warning and not a modal.** It is a fact about the data an
/// administrator is reading — behavioural metrics start at this release, and
/// nothing before it was invented to fill the gap — and it belongs at the foot
/// of the page in the same ink as a caption.
class _TrackingNotice extends StatelessWidget {
  const _TrackingNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: IconSize.meta, color: muted),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            context.l10n.adminAnalyticsNotice,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}
