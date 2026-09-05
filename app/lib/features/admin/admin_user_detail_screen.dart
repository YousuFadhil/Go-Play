import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import '../analytics/analytics_models.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// Stands in for a figure the database genuinely does not have.
///
/// The same dash the Overview uses, and for the same reason: an unknown Last
/// Seen is not a Last Seen of the join date, and an unobserved platform is not
/// "none". Every place it appears carries a spoken form of its own, because a
/// screen reader announcing "dash" tells an administrator nothing.
const _unknown = '—';

/// What the ten stored event names read as.
///
/// The mapping goes through [ProductEvent.fromWireName] rather than a list of
/// string literals here, so the labels cannot drift from the events the product
/// actually records. **A name this build does not know renders as itself** —
/// a row written by a newer release is shown rather than dropped or crashed on.
String _eventLabel(AppLocalizations l10n, String wireName) =>
    switch (ProductEvent.fromWireName(wireName)) {
      ProductEvent.sessionStarted => l10n.adminEventSessionStarted,
      ProductEvent.communityViewed => l10n.adminEventCommunityViewed,
      ProductEvent.communityCreated => l10n.adminEventCommunityCreated,
      ProductEvent.communityJoined => l10n.adminEventCommunityJoined,
      ProductEvent.matchViewed => l10n.adminEventMatchViewed,
      ProductEvent.matchRegistered => l10n.adminEventMatchRegistered,
      ProductEvent.matchWithdrawn => l10n.adminEventMatchWithdrawn,
      ProductEvent.teamsViewed => l10n.adminEventTeamsViewed,
      ProductEvent.resultViewed => l10n.adminEventResultViewed,
      ProductEvent.shareUsed => l10n.adminEventShareUsed,
      null => wireName,
    };

/// The two platforms the product reports about itself, said in the reader's
/// language. Anything else is shown as recorded.
String _platformLabel(AppLocalizations l10n, String platform) =>
    switch (platform) {
      'web' => l10n.adminPlatformWeb,
      'android' => l10n.adminPlatformAndroid,
      _ => platform,
    };

/// One account, in detail: who they are, how much they use this, and what they
/// have been doing.
///
/// **Read only, deliberately.** There is no Suspend or Reactivate here. Those
/// live on the Users list, which is where they have always lived and where the
/// busy flag, the reason dialog and the reload that follows them already are.
/// A second mutation surface would be a second copy of that state, free to
/// disagree with the first about whether an account is currently being
/// suspended — and the reader is one tap from the list either way.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({
    super.key,
    required this.userId,
    this.repository,
  });

  final String userId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final AdminRepository? repository;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

/// The two reads this screen makes, kept together.
typedef _Detail = (AdminUserActivitySummary, List<AdminUserActivityEvent>);

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository();

  late Future<_Detail> _future = _load();

  /// Both RPCs, issued together and failing together.
  ///
  /// One future rather than two, so the screen has one loading state and one
  /// retry. A half-loaded detail — figures present, timeline showing an error
  /// of its own — would be two things for an administrator to reason about
  /// where the useful answer is "this did not load, try again".
  Future<_Detail> _load() async {
    final results = await Future.wait([
      _repository.userActivitySummary(widget.userId),
      _repository.userActivityTimeline(widget.userId),
    ]);
    return (
      results[0] as AdminUserActivitySummary,
      results[1] as List<AdminUserActivityEvent>,
    );
  }

  void _reload() {
    // Block-bodied: an arrow here returns the assigned Future, which trips
    // `setState() callback argument returned a Future` in debug.
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.adminUserActivityTitle)),
      body: FutureBuilder<_Detail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _reload);
          }

          final (summary, timeline) = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.only(bottom: Layout.listBottom),
            children: [
              _Identity(summary: summary),

              SectionHeading(title: l10n.adminActivityTitle),
              SectionCard(children: [
                _DetailRow(
                  label: l10n.adminMetricJoined,
                  value: formatMatchDay(context, summary.createdAt),
                ),
                _DetailRow(
                  label: l10n.adminMetricLastSeen,
                  // Null means the product has never observed this account.
                  // Showing the join date instead would be a fact the database
                  // did not state.
                  value: summary.lastSeenAt == null
                      ? _unknown
                      : '${formatMatchDay(context, summary.lastSeenAt!)} '
                          '• ${formatTime(context, summary.lastSeenAt!)}',
                  unknown: summary.lastSeenAt == null,
                ),
                _DetailRow(
                  label: '${l10n.adminMetricActiveDays} · '
                      '${l10n.adminPeriod7d}',
                  value: '${summary.activeDays7d}',
                ),
                _DetailRow(
                  label: '${l10n.adminMetricActiveDays} · '
                      '${l10n.adminPeriod30d}',
                  value: '${summary.activeDays30d}',
                ),
                _DetailRow(
                  label: l10n.adminMetricSessions,
                  value: '${summary.sessionsTotal}',
                ),
                _DetailRow(
                  label: l10n.adminMetricPlatforms,
                  value: summary.platforms.isEmpty
                      ? _unknown
                      : [
                          for (final platform in summary.platforms)
                            _platformLabel(l10n, platform),
                        ].join(' · '),
                  unknown: summary.platforms.isEmpty,
                ),
                _DetailRow(
                  label: l10n.adminMetricAppVersion,
                  value: summary.latestAppVersion ?? _unknown,
                  unknown: summary.latestAppVersion == null,
                ),
              ]),

              SectionHeading(title: l10n.communityFootballTitle),
              SectionCard(children: [
                _DetailRow(
                  label: l10n.adminCommunitiesTab,
                  value: '${summary.communityCount}',
                ),
                _DetailRow(
                  label: l10n.adminMetricRegistrations,
                  value: '${summary.trackedRegistrations}',
                ),
                _DetailRow(
                  label: l10n.adminMetricMatchesPlayed,
                  value: '${summary.matchesPlayed}',
                ),
                _DetailRow(
                  label: l10n.adminMetricWithdrawals,
                  value: '${summary.trackedWithdrawals}',
                ),
              ]),

              // The same sentence the Overview closes with, because it is the
              // same fact and two wordings of it would invite the reader to
              // wonder which applied here. Registrations, withdrawals and
              // sessions above are tracked figures; Matches Played is not, and
              // is historically complete.
              FootNote(l10n.adminAnalyticsNotice),

              SectionHeading(title: l10n.adminRecentActivityTitle),
              if (timeline.isEmpty)
                EmptyState(
                  icon: Icons.history_toggle_off,
                  message: l10n.adminActivityEmpty,
                )
              else
                SectionCard(children: [
                  for (final event in timeline) _ActivityRow(event: event),
                ]),
            ],
          );
        },
      ),
    );
  }
}

/// Who this is, and what state their account is in.
class _Identity extends StatelessWidget {
  const _Identity({required this.summary});

  final AdminUserActivitySummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary.fullName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Gap.xs),
          Text(
            summary.email,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Gap.md),
          GoStatusChip(
            label: summary.isActive
                ? l10n.adminStatusActive
                : l10n.adminStatusSuspended,
            tone: summary.isActive ? GoChipTone.open : GoChipTone.danger,
          ),
          // Why, when there is a why. Shown only for a suspended account: a
          // reason left over from a suspension that has since been lifted would
          // read as a current one.
          if (!summary.isActive && summary.suspensionReason != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              summary.suspensionReason!,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

/// A label and the figure beside it.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.unknown = false,
  });

  final String label;
  final String value;

  /// Whether [value] is the dash standing in for something the database does
  /// not have, rather than a figure. Only affects how it is spoken.
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardInner,
        vertical: Gap.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Text(
            value,
            textAlign: TextAlign.end,
            semanticsLabel: unknown ? context.l10n.adminMetricUnavailable : null,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One thing the account did: what, where, and when.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});

  final AdminUserActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    // What this event was about, as far as anything can still say.
    //
    // A label the join could not resolve means the community or match has been
    // deleted -- `product_events` holds no foreign keys, so the id outlives the
    // row. The reader is told that in words. **The uuid is never shown**: it is
    // not a name, it identifies nothing an administrator can act on, and
    // putting one on screen would be worse than saying nothing.
    final context_ = <String>[
      if (event.communityId != null)
        event.communityName ?? l10n.adminAuditUnavailable,
      if (event.matchId != null) event.matchTitle ?? l10n.adminAuditUnavailable,
      if (event.platform != null) _platformLabel(l10n, event.platform!),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardInner,
        vertical: Gap.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _eventLabel(l10n, event.eventName),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                formatTime(context, event.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [formatMatchDay(context, event.createdAt), ...context_]
                .join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
