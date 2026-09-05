import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import 'admin_community_inspection_screen.dart';
import 'admin_detail_row.dart';
import 'admin_match_inspection_screen.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'admin_user_detail_screen.dart';

/// How many rows a page is, matching the database's own default.
///
/// A short page is how the screen knows it has reached the end: the RPC clamps
/// to 100 and returns at most what was asked for, so fewer than this means
/// there is no more.
const int _pageSize = 50;

/// The records behind one Overview figure.
///
/// One screen for fifteen metrics, because they differ in what a row looks like
/// and in nothing else: all four families load a page, append it, and stop when
/// a short page comes back. Fifteen screens would be fifteen copies of that
/// paging, free to disagree about when a list has ended.
///
/// **The list must agree with the number that opened it.** That is the
/// database's job — every function in `0069` reproduces its metric's population
/// exactly, deleted records included — and this screen's job is not to undo it.
/// So a row whose entity has been deleted is rendered rather than skipped, with
/// a localized "no longer available" where the name would be and no navigation
/// on it. Filtering those out here would make the list shorter than the card.
class AdminAnalyticsDrilldownScreen extends StatefulWidget {
  const AdminAnalyticsDrilldownScreen({
    super.key,
    required this.metric,
    required this.title,
    this.value,
    this.repository,
  });

  final AdminDrilldownMetric metric;

  /// The card's own label, passed in rather than re-derived, so the destination
  /// is titled exactly as the thing that was tapped.
  final String title;

  /// The card's own value, shown beneath the title so the reader can see at a
  /// glance whether the list they are scrolling adds up to it.
  final String? value;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final AdminRepository? repository;

  @override
  State<AdminAnalyticsDrilldownScreen> createState() =>
      _AdminAnalyticsDrilldownScreenState();
}

class _AdminAnalyticsDrilldownScreenState
    extends State<AdminAnalyticsDrilldownScreen> {
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository();

  /// The rows loaded so far, of whichever of the four shapes this metric has.
  /// Held as `Object` because the screen's paging does not care which, and the
  /// renderer switches on the type it actually got.
  final List<Object> _rows = [];

  bool _loading = true;
  bool _failed = false;

  /// True once a short page has come back. Until then there may be more.
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  /// The repository call this metric's family answers with.
  Future<List<Object>> _fetch(int offset) async =>
      switch (widget.metric.kind) {
        AdminDrilldownKind.users =>
          await _repository.drilldownUsers(widget.metric, offset: offset),
        AdminDrilldownKind.communities =>
          await _repository.drilldownCommunities(widget.metric, offset: offset),
        AdminDrilldownKind.matches =>
          await _repository.drilldownMatches(widget.metric, offset: offset),
        AdminDrilldownKind.registrations => await _repository
            .drilldownRegistrations(widget.metric, offset: offset),
      };

  Future<void> _loadMore() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });

    try {
      // The offset is the number of rows already held, so a page cannot be
      // requested twice or skipped.
      final page = await _fetch(_rows.length);
      if (!mounted) return;
      setState(() {
        _rows.addAll(page);
        _exhausted = page.length < _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // The rows already loaded stay on screen. A failed *next* page is not a
      // reason to throw away the page the reader is looking at.
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// Starts again from nothing, for the retry on a failed first page.
  void _reload() {
    setState(() {
      _rows.clear();
      _exhausted = false;
    });
    _loadMore();
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(
        title: Text(widget.title),
        // The figure this list is of, under the label it came from.
        bottom: widget.value == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: kPageMargin,
                    right: kPageMargin,
                    bottom: Gap.sm,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      widget.value!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
      ),
      body: _body(l10n),
    );
  }

  Widget _body(AppLocalizations l10n) {
    // The very first page, still in flight.
    if (_rows.isEmpty && _loading) return const LoadingState();

    // The very first page failed. Nothing to show but the retry.
    if (_rows.isEmpty && _failed) return ErrorState(onRetry: _reload);

    if (_rows.isEmpty) {
      // A metric with genuinely nobody in it. Reached by a zero-valued card,
      // and by Weekly Retention when there was no previous-week cohort — both
      // of which are ordinary states and not faults.
      return EmptyState(
        icon: Icons.search_off,
        message: l10n.adminDrilldownEmpty,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: Layout.listBottom),
      itemCount: _rows.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index < _rows.length) return _row(_rows[index]);
        return _footer(l10n);
      },
    );
  }

  /// What sits under the last row: a way to ask for more, a retry for a page
  /// that failed, or nothing once the list is complete.
  Widget _footer(AppLocalizations l10n) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(Gap.lg),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (_exhausted && !_failed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Center(
        child: TextButton(
          onPressed: _loadMore,
          child: Text(_failed ? l10n.retryButton : l10n.adminDrilldownLoadMore),
        ),
      ),
    );
  }

  Widget _row(Object row) => switch (row) {
        AdminDrilldownUser user => _UserRow(
            user: user,
            metric: widget.metric,
            onOpen: user.exists
                ? () => _open(AdminUserDetailScreen(
                      userId: user.userId,
                      repository: _repository,
                    ))
                : null,
          ),
        AdminDrilldownCommunity community => _CommunityRow(
            community: community,
            onOpen: () => _open(AdminCommunityInspectionScreen(
              communityId: community.communityId,
              repository: _repository,
            )),
          ),
        AdminDrilldownMatch match => _MatchRow(
            match: match,
            showScore: widget.metric.showsScore,
            onOpen: () => _open(AdminMatchInspectionScreen(
              matchId: match.matchId,
              repository: _repository,
            )),
          ),
        AdminDrilldownRegistration registration => _RegistrationRow(
            registration: registration,
            onOpenUser: registration.userExists
                ? () => _open(AdminUserDetailScreen(
                      userId: registration.userId!,
                      repository: _repository,
                    ))
                : null,
            onOpenMatch: registration.matchExists
                ? () => _open(AdminMatchInspectionScreen(
                      matchId: registration.matchId!,
                      repository: _repository,
                    ))
                : null,
          ),
        // Unreachable: `_fetch` returns exactly the four shapes above.
        _ => const SizedBox.shrink(),
      };
}

/// One person in a user-shaped metric.
class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.metric,
    required this.onOpen,
  });

  final AdminDrilldownUser user;
  final AdminDrilldownMetric metric;

  /// Null when the account has been deleted, which is what disables the tap.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final returned = user.returnedInCurrentWeek;

    return ListTile(
      onTap: onOpen,
      // A deleted account is named as gone rather than by its uuid, which
      // identifies nothing an administrator can act on.
      title: Text(
        user.fullName ?? l10n.adminAuditUnavailable,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user.email != null)
            Text(user.email!, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (user.lastSeenAt != null)
            Text(
              '${l10n.adminMetricLastSeen}: '
              '${formatMatchDay(context, user.lastSeenAt!)}',
            ),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              if (user.isActive != null)
                GoStatusChip(
                  label: user.isActive!
                      ? l10n.adminStatusActive
                      : l10n.adminStatusSuspended,
                  tone: user.isActive!
                      ? GoChipTone.open
                      : GoChipTone.danger,
                ),
              // Retention only. Null here would be a different claim from
              // false, so the chip is absent rather than negative.
              if (metric.showsReturn && returned != null)
                GoStatusChip(
                  label:
                      returned ? l10n.adminReturned : l10n.adminDidNotReturn,
                  tone: returned ? GoChipTone.open : GoChipTone.neutral,
                ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: onOpen == null ? null : const Icon(Icons.chevron_right),
    );
  }
}

/// One community in Weekly Active Communities.
class _CommunityRow extends StatelessWidget {
  const _CommunityRow({required this.community, required this.onOpen});

  final AdminDrilldownCommunity community;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ListTile(
      onTap: onOpen,
      title: Text(
        community.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${community.ownerName ?? adminUnknownValue} · '
            '${community.memberCount} · ${community.matchCount}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (community.lastActivityAt != null)
            Text('${l10n.adminMetricLastActivity}: '
                '${formatMatchDay(context, community.lastActivityAt!)}'),
          const SizedBox(height: Gap.xs),
          GoStatusChip(
            label: community.isActive
                ? l10n.adminStatusActive
                : l10n.adminStatusSuspended,
            tone: community.isActive ? GoChipTone.open : GoChipTone.danger,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

/// One match, in a matches or a results metric.
class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.match,
    required this.showScore,
    required this.onOpen,
  });

  final AdminDrilldownMatch match;

  /// Whether this metric is about results, in which case the score is the
  /// point. A matches list legitimately holds matches nobody has written up.
  final bool showScore;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ListTile(
      onTap: onOpen,
      title: Text(
        match.title ?? match.location,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${match.communityName ?? l10n.adminAuditUnavailable} · '
            '${match.location}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${formatMatchDay(context, match.startAt)} · ${match.status}',
          ),
          if (showScore && match.hasScore) ...[
            const SizedBox(height: Gap.xs),
            // Isolated left-to-right: a score runs A-then-B in every language.
            Text(
              '\u2066${match.scoreA} - ${match.scoreB}\u2069',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

/// One `match_registered` event.
///
/// The row is the person — an administrator reading a registration list is
/// asking who registered — and the match is a second, explicitly labelled way
/// out. Both are disabled independently, because either can have been deleted
/// while the event that named it stands.
class _RegistrationRow extends StatelessWidget {
  const _RegistrationRow({
    required this.registration,
    required this.onOpenUser,
    required this.onOpenMatch,
  });

  final AdminDrilldownRegistration registration;
  final VoidCallback? onOpenUser;
  final VoidCallback? onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ListTile(
      onTap: onOpenUser,
      title: Text(
        registration.fullName ?? l10n.adminAuditUnavailable,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${registration.matchTitle ?? l10n.adminAuditUnavailable} · '
            '${registration.communityName ?? l10n.adminAuditUnavailable}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${formatMatchDay(context, registration.createdAt)} · '
            '${formatTime(context, registration.createdAt)}',
          ),
        ],
      ),
      isThreeLine: true,
      trailing: onOpenMatch == null
          ? null
          : TextButton(
              onPressed: onOpenMatch,
              child: Text(l10n.adminOpenMatch),
            ),
    );
  }
}
