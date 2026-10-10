import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import '../analytics/analytics_models.dart';
import '../locations/wilayat_models.dart';
import '../locations/wilayat_picker.dart' show wilayatArabic;
import '../locations/wilayat_repository.dart';
import '../profile/profile_models.dart' show ProfileVisibility;
import 'admin_deletion_preview_screen.dart';
import 'admin_detail_row.dart';
import 'admin_merge_preview_screen.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'admin_user_edit_screen.dart';

/// Stands in for a figure the database genuinely does not have.
///
/// The same dash the Overview uses, and for the same reason: an unknown Last
/// Seen is not a Last Seen of the join date, and an unobserved platform is not
/// "none". Every place it appears carries a spoken form of its own, because a
/// screen reader announcing "dash" tells an administrator nothing.
const _unknown = '—';

/// What a stored event reads as, with the detail the row carries.
///
/// The mapping goes through [ProductEvent.fromWireName] rather than a list of
/// string literals here, so the labels cannot drift from the events the product
/// actually records. **A name this build does not know renders as itself** —
/// a row written by a newer release is shown rather than dropped or crashed on.
///
/// [accountId] is the account the screen is about: a view whose target is that
/// same account is the player looking at themselves.
String _eventLabel(
  AppLocalizations l10n,
  AdminUserActivityEvent event,
  String accountId,
) =>
    switch (ProductEvent.fromWireName(event.eventName)) {
      ProductEvent.sessionStarted => l10n.adminEventSessionStarted,
      ProductEvent.communityViewed => l10n.adminEventCommunityViewed,
      ProductEvent.communityCreated => l10n.adminEventCommunityCreated,
      ProductEvent.communityJoined => l10n.adminEventCommunityJoined,
      ProductEvent.matchViewed => l10n.adminEventMatchViewed,
      ProductEvent.matchRegistered => l10n.adminEventMatchRegistered,
      ProductEvent.matchWithdrawn => l10n.adminEventMatchWithdrawn,
      ProductEvent.teamsViewed => l10n.adminEventTeamsViewed,
      ProductEvent.resultViewed => l10n.adminEventResultViewed,
      ProductEvent.shareUsed => _shareLabel(l10n, event.shareType),
      ProductEvent.publicLinkOpened => l10n.adminEventPublicLinkOpened,
      ProductEvent.profileViewed => event.targetUserId == accountId
          ? l10n.adminEventViewedOwnProfile
          : l10n.adminEventViewedPlayerProfile(_targetName(l10n, event)),
      ProductEvent.playerStatisticsViewed =>
        event.targetUserId == null || event.targetUserId == accountId
            ? l10n.adminEventViewedPlayerStatistics
            : l10n.adminEventViewedPlayerStatisticsOf(_targetName(l10n, event)),
      null => event.eventName,
    };

/// Who a view was about, or the "no longer available" every deleted label on
/// this screen reads as. The uuid is never shown.
String _targetName(AppLocalizations l10n, AdminUserActivityEvent event) =>
    event.targetUserName ?? l10n.adminAuditUnavailable;

/// What a share was of. A share recorded without a kind -- or with one this
/// build does not know -- keeps the plain label it always had.
String _shareLabel(AppLocalizations l10n, String? shareType) =>
    switch (ShareType.fromWireName(shareType)) {
      ShareType.playerProfile => l10n.adminEventSharedPlayerProfile,
      ShareType.playerStatistics => l10n.adminEventSharedPlayerStatistics,
      ShareType.community => l10n.adminEventSharedCommunity,
      ShareType.match => l10n.adminEventSharedMatch,
      ShareType.lineup => l10n.adminEventSharedLineup,
      ShareType.result => l10n.adminEventSharedResult,
      null => l10n.adminEventShareUsed,
    };

/// The two platforms the product reports about itself, said in the reader's
/// language. Anything else is shown as recorded.
String _platformLabel(AppLocalizations l10n, String platform) =>
    switch (platform) {
      'web' => l10n.adminPlatformWeb,
      'android' => l10n.adminPlatformAndroid,
      _ => platform,
    };

/// One account, in detail: who they are, what their data says, how much they use
/// this, and what they have been doing.
///
/// **No Suspend or Reactivate here, deliberately.** Those live on the Users
/// list, which is where they have always lived and where the busy flag, the
/// reason dialog and the reload that follows them already are. A second
/// mutation surface would be a second copy of that state, free to disagree with
/// the first about whether an account is currently being suspended — and the
/// reader is one tap from the list either way.
///
/// The one thing this screen can open is the account editor (migration `0095`),
/// and only for an account the database will let be edited: not the
/// administrator's own, and not a System Admin's.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({
    super.key,
    required this.userId,
    this.repository,
    this.wilayatRepository,
  });

  final String userId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final AdminRepository? repository;

  /// The Wilayat reference data, for naming a Default Location; defaults to the
  /// app-wide cached instance. Supplied only by tests.
  final WilayatRepository? wilayatRepository;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

/// The two reads this screen makes, kept together.
typedef _Detail = (AdminUserActivitySummary, List<AdminUserActivityEvent>);

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository();

  late final WilayatRepository _wilayats =
      widget.wilayatRepository ?? WilayatRepository.shared;

  late Future<_Detail> _future = _load();

  /// The Account data section reads on its own, so its failure -- or a database
  /// that does not have `admin_get_user_account` yet -- cannot take the rest of
  /// the screen with it. A failure is carried as null rather than thrown, which
  /// is also what keeps an error that lands before the section is built from
  /// being reported as unhandled.
  late Future<AdminUserAccount?> _accountFuture = _loadAccount();

  Future<AdminUserAccount?> _loadAccount() async {
    try {
      return await _repository.userAccount(widget.userId);
    } catch (_) {
      return null;
    }
  }

  void _reloadAccount() {
    setState(() {
      _accountFuture = _loadAccount();
    });
  }

  /// Opens the editor, then reads the section again: whatever was saved there
  /// is what the section should now say.
  Future<void> _edit(AdminUserAccount account) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminUserEditScreen(
          account: account,
          repository: _repository,
          wilayatRepository: widget.wilayatRepository,
        ),
      ),
    );
    if (mounted) _reloadAccount();
  }

  /// The merge screen, with this account offered as the one to keep. It answers
  /// with the id of the account that survived when a merge was performed, and with
  /// nothing otherwise: a preview changes nothing, so nothing is reloaded.
  ///
  /// This account may be either of the two (the administrator can swap them), so
  /// after a merge it is read again if it survived and left if it was merged away.
  Future<void> _previewMerge(AdminUserAccount account) async {
    final survivor = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => AdminMergePreviewScreen(
          retained: AdminUserSummary(
            id: account.id,
            fullName: account.fullName,
            email: account.email,
            isSystemAdmin: account.isSystemAdmin,
            isActive: account.isActive,
          ),
          repository: _repository,
        ),
      ),
    );
    if (!mounted || survivor == null) return;
    if (survivor == account.id) {
      _reload();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// The deletion screen for this account: what it would do and, when nothing blocks it,
  /// the deletion. It answers `true` when the account was deleted, and nothing otherwise.
  /// A deleted account has no screen of its own to come back to, so this one leaves too.
  Future<void> _previewDeletion(AdminUserAccount account) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AdminDeletionPreviewScreen(
          userId: account.id,
          repository: _repository,
        ),
      ),
    );
    if (!mounted || deleted != true) return;
    Navigator.of(context).pop();
  }

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
      _accountFuture = _loadAccount();
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

              _AccountSection(
                future: _accountFuture,
                currentUserId: _repository.currentUserId,
                wilayats: _wilayats,
                onEdit: _edit,
                onPreviewMerge: _previewMerge,
                onPreviewDeletion: _previewDeletion,
                onRetry: _reloadAccount,
              ),

              SectionHeading(title: l10n.adminActivityTitle),
              SectionCard(children: [
                _DetailRow(
                  label: l10n.adminMetricJoined,
                  value: formatMuscatMatchDay(context, summary.createdAt),
                ),
                _DetailRow(
                  label: l10n.adminMetricLastSeen,
                  // Null means the product has never observed this account.
                  // Showing the join date instead would be a fact the database
                  // did not state.
                  value: summary.lastSeenAt == null
                      ? _unknown
                      : '${formatMuscatMatchDay(context, summary.lastSeenAt!)} '
                          '• ${formatMuscatTime(context, summary.lastSeenAt!)}',
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
                  label: l10n.adminMetricTrackedRegistrations,
                  value: '${summary.trackedRegistrations}',
                ),
                _DetailRow(
                  label: l10n.adminMetricMatchesPlayed,
                  value: '${summary.matchesPlayed}',
                ),
                _DetailRow(
                  label: l10n.adminMetricTrackedWithdrawals,
                  value: '${summary.trackedWithdrawals}',
                ),
              ]),

              // The same sentence the Overview closes with, because it is the
              // same fact and two wordings of it would invite the reader to
              // wonder which applied here. Registrations, withdrawals and
              // sessions above are tracked figures over retained activity;
              // Last Seen survives retention; Matches Played is not a tracked
              // figure, and is historically complete.
              FootNote(l10n.adminAnalyticsNotice),

              SectionHeading(title: l10n.adminRecentActivityTitle),
              if (timeline.isEmpty)
                EmptyState(
                  icon: Icons.history_toggle_off,
                  message: l10n.adminActivityEmpty,
                )
              else
                SectionCard(children: [
                  for (final event in timeline)
                    _ActivityRow(event: event, accountId: summary.userId),
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
            semanticsLabel:
                unknown ? context.l10n.adminMetricUnavailable : null,
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
  const _ActivityRow({required this.event, required this.accountId});

  final AdminUserActivityEvent event;

  /// The account this screen is about, which is what makes a view "own".
  final String accountId;

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
                  _eventLabel(l10n, event, accountId),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                formatMuscatTime(context, event.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [formatMuscatMatchDay(context, event.createdAt), ...context_]
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

/// The account's own data and settings, read on their own (migration `0095`).
///
/// Three states and no more: reading, failed with a retry, and the data. The
/// failure is a compact row rather than the full-screen error state, because
/// the rest of the screen is working and must stay readable beside it.
class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.future,
    required this.currentUserId,
    required this.wilayats,
    required this.onEdit,
    required this.onPreviewMerge,
    required this.onPreviewDeletion,
    required this.onRetry,
  });

  final Future<AdminUserAccount?> future;

  /// The signed-in administrator, so the editor can be left out for their own
  /// account. Null when it cannot be told, in which case the database is what
  /// refuses.
  final String? currentUserId;

  final WilayatRepository wilayats;
  final void Function(AdminUserAccount account) onEdit;
  final void Function(AdminUserAccount account) onPreviewMerge;
  final void Function(AdminUserAccount account) onPreviewDeletion;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(title: l10n.adminAccountDataTitle),
        FutureBuilder<AdminUserAccount?>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(Gap.lg),
                child: Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final account = snapshot.data;
            if (account == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
                child: Row(
                  children: [
                    Expanded(child: Text(l10n.loadFailed)),
                    TextButton(
                      key: const Key('adminAccountRetry'),
                      onPressed: onRetry,
                      child: Text(l10n.retryButton),
                    ),
                  ],
                ),
              );
            }
            return _AccountData(
              account: account,
              isSelf: currentUserId != null && currentUserId == account.id,
              wilayats: wilayats,
              onEdit: () => onEdit(account),
              onPreviewMerge: () => onPreviewMerge(account),
              onPreviewDeletion: () => onPreviewDeletion(account),
            );
          },
        ),
      ],
    );
  }
}

/// Every field `admin_get_user_account` returns, and the way into the editor.
class _AccountData extends StatelessWidget {
  const _AccountData({
    required this.account,
    required this.isSelf,
    required this.wilayats,
    required this.onEdit,
    required this.onPreviewMerge,
    required this.onPreviewDeletion,
  });

  final AdminUserAccount account;
  final bool isSelf;
  final WilayatRepository wilayats;
  final VoidCallback onEdit;
  final VoidCallback onPreviewMerge;
  final VoidCallback onPreviewDeletion;

  /// A moment, as the Users screens write one: the Oman day and time.
  String _moment(BuildContext context, DateTime value) =>
      '${formatMuscatMatchDay(context, value)} '
      '• ${formatMuscatTime(context, value)}';

  /// How a sign-in method reads. A method this build does not know is shown as
  /// the provider named it, rather than hidden.
  String _providerLabel(AppLocalizations l10n, String provider) =>
      switch (provider) {
        'email' => l10n.emailLabel,
        'google' => l10n.adminProviderGoogle,
        _ => provider,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final suspended = !account.isActive;
    final canEdit = !isSelf && !account.isSystemAdmin;

    String onOff(bool value) =>
        value ? l10n.adminAccountOn : l10n.adminAccountOff;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.md),
            child: Center(
              // Display only: nothing in the console writes or removes it.
              child: UserAvatar(
                avatarUrl: account.avatarUrl,
                fullName: account.fullName,
                radius: 32,
              ),
            ),
          ),
          AdminDetailRow(label: l10n.fullNameLabel, value: account.fullName),
          AdminDetailRow(label: l10n.phoneLabel, value: account.phone),
          AdminDetailRow(label: l10n.emailLabel, value: account.email),
          AdminDetailRow(
            label: l10n.adminAccountActiveLabel,
            value: suspended ? l10n.adminAccountNo : l10n.adminAccountYes,
          ),
          if (suspended && account.suspendedAt != null)
            AdminDetailRow(
              label: l10n.adminStatusSuspended,
              value: formatMuscatMatchDay(context, account.suspendedAt!),
            ),
          if (suspended && account.suspensionReason != null)
            AdminDetailRow(
              label: l10n.adminSuspensionReasonLabel,
              value: account.suspensionReason!,
            ),
          if (account.isSystemAdmin)
            AdminDetailRow(
              label: l10n.adminStatusSystemAdmin,
              value: l10n.adminAccountYes,
            ),
          AdminDetailRow(
            label: l10n.dateOfBirthLabel,
            value: account.dateOfBirth == null
                ? l10n.adminAccountNotSet
                : DateFormat.yMMMd(locale).format(account.dateOfBirth!),
          ),
          AdminDetailRow(
            label: l10n.positionLabel,
            value: adminPositionLabel(l10n, account.primaryPosition),
          ),
          AdminDetailRow(
            label: l10n.secondaryPositionLabel,
            value: account.secondaryPosition == null
                ? l10n.noSecondaryPosition
                : adminPositionLabel(l10n, account.secondaryPosition!),
          ),
          AdminDetailRow(
            label: l10n.adminAccountProfileVisibilityLabel,
            value: switch (account.profileVisibility) {
              ProfileVisibility.everyone => l10n.profileVisibilityEveryone,
              ProfileVisibility.communityMembersOnly =>
                l10n.profileVisibilityCommunityMembers,
            },
          ),
          AdminDetailRow(
            label: l10n.adminAccountAgeVisibleLabel,
            value:
                account.ageVisible ? l10n.adminAccountYes : l10n.adminAccountNo,
          ),
          _DefaultLocationRow(account: account, wilayats: wilayats),
          AdminDetailRow(
            label: l10n.pushMatchLabel,
            value: onOff(account.matchPush),
          ),
          AdminDetailRow(
            label: l10n.pushCommunityLabel,
            value: onOff(account.communityPush),
          ),
          AdminDetailRow(
            label: l10n.pushMuteAllLabel,
            value: onOff(account.muteAll),
          ),
          AdminDetailRow(
            label: l10n.adminAccountSignInMethodsLabel,
            value: account.signInProviders.isEmpty
                ? adminUnknownValue
                : [
                    for (final provider in account.signInProviders)
                      _providerLabel(l10n, provider),
                  ].join(' · '),
            unknown: account.signInProviders.isEmpty,
          ),
          AdminDetailRow(
            label: l10n.adminAccountEmailConfirmedLabel,
            value: account.emailConfirmedAt == null
                ? l10n.adminAccountEmailNotConfirmed
                : _moment(context, account.emailConfirmedAt!),
          ),
          AdminDetailRow(
            label: l10n.adminAccountLastSignInLabel,
            value: account.lastSignInAt == null
                ? l10n.adminAccountNeverSignedIn
                : _moment(context, account.lastSignInAt!),
          ),
          AdminDetailRow(
            label: l10n.adminAccountCreatedLabel,
            value: _moment(context, account.createdAt),
          ),
        ]),
        if (canEdit)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kPageMargin,
              vertical: Gap.sm,
            ),
            child: OutlinedButton.icon(
              key: const Key('adminAccountEdit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.adminAccountEditAction),
            ),
          )
        else
          // Why there is no editor, rather than an editor that cannot be used.
          // The database refuses both cases regardless of what is shown here.
          FootNote(
            isSelf
                ? l10n.adminEditUnavailableSelf
                : l10n.adminEditUnavailableSystemAdmin,
          ),
        // Read-only previews (migration `0096`). Offered for every account,
        // including the administrator's own and a System Admin's: seeing why a
        // deletion or merge is blocked is the point, and they change nothing.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kPageMargin,
            vertical: Gap.xs,
          ),
          child: OutlinedButton.icon(
            key: const Key('adminAccountPreviewMerge'),
            onPressed: onPreviewMerge,
            icon: const Icon(Icons.merge_type),
            label: Text(l10n.adminPreviewMergeAction),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kPageMargin,
            vertical: Gap.xs,
          ),
          child: OutlinedButton.icon(
            key: const Key('adminAccountPreviewDeletion'),
            onPressed: onPreviewDeletion,
            icon: const Icon(Icons.person_remove_outlined),
            label: Text(l10n.adminPreviewDeletionAction),
          ),
        ),
      ],
    );
  }
}

/// The Default Location by name. The code is a key and is never shown; when the
/// catalog cannot be read the row says it has nothing to show.
class _DefaultLocationRow extends StatelessWidget {
  const _DefaultLocationRow({required this.account, required this.wilayats});

  final AdminUserAccount account;
  final WilayatRepository wilayats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final code = account.defaultWilayatCode;

    if (code == null) {
      return AdminDetailRow(
        label: l10n.defaultLocationLabel,
        value: l10n.adminAccountNotSet,
      );
    }

    return FutureBuilder<WilayatCatalog>(
      future: wilayats.load(),
      builder: (context, snapshot) {
        final name = snapshot.data?.nameOf(
          code,
          arabic: wilayatArabic(context),
        );
        return AdminDetailRow(
          label: l10n.defaultLocationLabel,
          value: name ?? adminUnknownValue,
          unknown: name == null,
        );
      },
    );
  }
}
