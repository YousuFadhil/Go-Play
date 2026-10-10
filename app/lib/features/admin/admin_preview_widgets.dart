import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import 'admin_detail_row.dart';
import 'admin_models.dart';

/// The words for the codes the preflight previews send (migration `0096`).
///
/// **A code this build does not know renders as itself.** The database may
/// learn a finding before this build does; showing the raw code is unlovely and
/// truthful, and dropping it would hide exactly the thing most worth seeing.
class AdminPreviewLabels {
  const AdminPreviewLabels._();

  static String severity(AppLocalizations l10n, AdminFindingSeverity value) =>
      switch (value) {
        AdminFindingSeverity.blocker => l10n.adminSeverityBlocker,
        AdminFindingSeverity.conflict => l10n.adminSeverityConflict,
        AdminFindingSeverity.constraint => l10n.adminSeverityConstraint,
      };

  static String finding(AppLocalizations l10n, String code) => switch (code) {
        'SOURCE_IS_CALLER' => l10n.adminFindingSourceIsCaller,
        'RETAINED_IS_CALLER' => l10n.adminFindingRetainedIsCaller,
        'SOURCE_IS_SYSTEM_ADMIN' => l10n.adminFindingSourceIsSystemAdmin,
        'RETAINED_IS_SYSTEM_ADMIN' => l10n.adminFindingRetainedIsSystemAdmin,
        'OWNERSHIP_CONFLICT' => l10n.adminFindingOwnershipConflict,
        'SHARED_MATCH_COLLISION' => l10n.adminFindingSharedMatchCollision,
        'SOURCE_OWNS_COMMUNITIES' => l10n.adminFindingSourceOwnsCommunities,
        'ROLE_CONFLICT' => l10n.adminFindingRoleConflict,
        'SHARED_MATCH_PARTICIPATION' =>
          l10n.adminFindingSharedMatchParticipation,
        'SOURCE_CREATED_MATCHES' => l10n.adminFindingSourceCreatedMatches,
        'COMMUNITY_STATISTICS_COLLISION' =>
          l10n.adminFindingCommunityStatisticsCollision,
        'TEAM_AWARD_COLLISION' => l10n.adminFindingTeamAwardCollision,
        'PLAYER_STATISTICS_RECOMPUTE' =>
          l10n.adminFindingPlayerStatisticsRecompute,
        'RATING_REPLAY_REQUIRED' => l10n.adminFindingRatingReplayRequired,
        'RATING_ARCHIVE_IMMUTABLE' => l10n.adminFindingRatingArchiveImmutable,
        'EVENT_LOGS_NAME_SOURCE' => l10n.adminFindingEventLogsNameSource,
        'AUDIT_LOG_NAMES_SOURCE' => l10n.adminFindingAuditLogNamesSource,
        'TARGET_IS_CALLER' => l10n.adminFindingTargetIsCaller,
        'TARGET_IS_SYSTEM_ADMIN' => l10n.adminFindingTargetIsSystemAdmin,
        'OWNS_COMMUNITIES' => l10n.adminFindingOwnsCommunities,
        'CREATED_MATCHES' => l10n.adminFindingCreatedMatches,
        'MVP_RESULTS_WOULD_CASCADE' => l10n.adminFindingMvpResultsWouldCascade,
        'HISTORY_WOULD_CASCADE' => l10n.adminFindingHistoryWouldCascade,
        'UPCOMING_REGISTRATIONS' => l10n.adminFindingUpcomingRegistrations,
        'RATING_HISTORY_IMMUTABLE' => l10n.adminFindingRatingHistoryImmutable,
        'AUDIT_LOG_APPEND_ONLY' => l10n.adminFindingAuditLogAppendOnly,
        'EVENT_LOGS_NAME_ACCOUNT' => l10n.adminFindingEventLogsNameAccount,
        // Merging two accounts (migration `0101`).
        'SHARED_MATCH_NOT_RESOLVABLE' =>
          l10n.adminFindingSharedMatchNotResolvable,
        'SHARED_MATCH_LIMIT_EXCEEDED' =>
          l10n.adminFindingSharedMatchLimitExceeded,
        'SHARED_MATCH_CHOICE_REQUIRED' =>
          l10n.adminFindingSharedMatchChoiceRequired,
        'SOURCE_HAS_STORED_FILES' => l10n.adminFindingSourceHasStoredFiles,
        'RETAINED_RATING_INCONSISTENT' =>
          l10n.adminFindingRetainedRatingInconsistent,
        'RATING_ARCHIVE_MAPPED' => l10n.adminFindingRatingArchiveMapped,
        _ => code,
      };

  /// Why a participation cannot be removed from a match (migration `0101`).
  static String dropBlocker(AppLocalizations l10n, String code) =>
      switch (code) {
        'GOALS' => l10n.adminMergeBlockerGoals,
        'MVP' => l10n.adminMergeBlockerMvp,
        'LINEUP_IN_RESULT' => l10n.adminMergeBlockerLineupInResult,
        'CONFIRMED_LINEUP' => l10n.adminMergeBlockerConfirmedLineup,
        'RATING_IN_EFFECT' => l10n.adminMergeBlockerRating,
        _ => code,
      };

  /// The activity counts a snapshot carries, by key. Keys not listed here are
  /// not shown.
  static String count(AppLocalizations l10n, String key) => switch (key) {
        'memberships' => l10n.adminCountMemberships,
        'owned_communities' => l10n.adminCountOwned,
        'created_matches' => l10n.adminCountCreated,
        'registrations' => l10n.adminCountRegistrations,
        'upcoming_registrations' => l10n.adminCountUpcoming,
        'lineup_assignments' => l10n.adminCountLineup,
        'goals_total' => l10n.adminCountGoals,
        'mvp_awards' => l10n.adminCountMvp,
        'matches_played' => l10n.adminCountCareerStats,
        'rating_entries' => l10n.adminCountRatingEntries,
        'rating_archive_rows' => l10n.adminCountRatingArchive,
        'community_statistics_rows' => l10n.adminCountCommunityStatistics,
        'team_of_period_awards' => l10n.adminCountTeamAwards,
        'notifications' => l10n.adminCountNotifications,
        'push_tokens' => l10n.adminCountPushTokens,
        'product_events' => l10n.adminCountActivityEvents,
        'audit_entries' => l10n.adminCountAuditEntries,
        _ => key,
      };

  /// The keys of [count], in the order a reader wants them.
  static const countKeys = [
    'memberships',
    'owned_communities',
    'created_matches',
    'registrations',
    'upcoming_registrations',
    'lineup_assignments',
    'goals_total',
    'mvp_awards',
    'matches_played',
    'rating_entries',
    'rating_archive_rows',
    'community_statistics_rows',
    'team_of_period_awards',
    'notifications',
    'push_tokens',
    'product_events',
    'audit_entries',
  ];

  static String personal(AppLocalizations l10n, String code) => switch (code) {
        'PROFILE' => l10n.adminPersonalProfile,
        'EMAIL_ADDRESS' => l10n.emailLabel,
        'SIGN_IN_IDENTITIES' => l10n.adminPersonalIdentities,
        'PHONE_NUMBER' => l10n.phoneLabel,
        'DATE_OF_BIRTH' => l10n.dateOfBirthLabel,
        'AVATAR' => l10n.adminPersonalAvatar,
        'DEFAULT_LOCATION' => l10n.defaultLocationLabel,
        'PUSH_TOKENS' => l10n.adminCountPushTokens,
        'PUSH_PREFERENCES' => l10n.adminPersonalPushPreferences,
        'NOTIFICATIONS' => l10n.adminCountNotifications,
        'ACTIVITY_EVENTS' => l10n.adminCountActivityEvents,
        _ => code,
      };

  /// Football history and the preserved records.
  static String history(AppLocalizations l10n, String code) => switch (code) {
        'COMMUNITY_MEMBERSHIPS' => l10n.adminCountMemberships,
        'MATCH_REGISTRATIONS' => l10n.adminCountRegistrations,
        'LINEUP_ASSIGNMENTS' => l10n.adminCountLineup,
        'GOAL_RECORDS' => l10n.adminCountGoalRows,
        'MVP_RESULTS' => l10n.adminCountMvp,
        'PLAYER_STATISTICS' => l10n.adminHistCareerStatistics,
        'COMMUNITY_STATISTICS' => l10n.adminCountCommunityStatistics,
        'RATING_HISTORY' => l10n.adminCountRatingEntries,
        'RECORDED_RESULTS' => l10n.adminHistRecordedResults,
        'PROFESSIONAL_GUESTS_ADDED' => l10n.adminHistGuestsAdded,
        'TEAM_OF_PERIOD_AWARDS' => l10n.adminCountTeamAwards,
        'REGISTRATION_EVENTS' => l10n.adminHistRegistrationEvents,
        'MEMBERSHIP_EVENTS' => l10n.adminHistMembershipEvents,
        'GENERATION_RUNS' => l10n.adminHistGenerationRuns,
        'CONFIRMED_LINEUPS' => l10n.adminHistConfirmedLineups,
        'ACTIVITY_EVENTS' => l10n.adminCountActivityEvents,
        'RATING_HISTORY_ARCHIVE' => l10n.adminHistRatingHistoryArchive,
        'USER_RATING_ARCHIVE' => l10n.adminHistUserRatingArchive,
        'ADMIN_AUDIT_LOG' => l10n.adminCountAuditEntries,
        _ => code,
      };

  static String treatment(AppLocalizations l10n, String? code) =>
      switch (code) {
        'CASCADE_DELETE' => l10n.adminTreatmentCascadeDelete,
        'DETACH' => l10n.adminTreatmentDetach,
        'RETAINED_ID' => l10n.adminTreatmentRetainedId,
        _ => code ?? '',
      };

  static String evidence(AppLocalizations l10n, String code) => switch (code) {
        'REGISTRATION' => l10n.adminEvidenceRegistration,
        'LINEUP' => l10n.adminEvidenceLineup,
        'GOALS' => l10n.adminEvidenceGoals,
        'MVP' => l10n.adminEvidenceMvp,
        'RATING' => l10n.adminEvidenceRating,
        _ => code,
      };

  static String coverage(AppLocalizations l10n, String code) => switch (code) {
        'EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED' =>
          l10n.adminCoverageGenerationEvidence,
        'STORAGE_OBJECTS_NOT_INSPECTED' => l10n.adminCoverageStorage,
        'AUTH_SESSIONS_NOT_INSPECTED' => l10n.adminCoverageSessions,
        _ => code,
      };

  static String role(AppLocalizations l10n, String role) => switch (role) {
        'owner' => l10n.roleOwner,
        'admin' => l10n.roleAdmin,
        'player' => l10n.rolePlayer,
        _ => role,
      };
}

/// "Read only." on every preview, so no reader mistakes one for a control.
class AdminReadOnlyBanner extends StatelessWidget {
  const AdminReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: IconSize.meta,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              context.l10n.adminPreviewReadOnlyNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-line verdict: nothing blocks, or how many things do.
///
/// **Not a green light.** "No blockers found" describes this preview, which does
/// not see everything and which authorises nothing, so it is drawn neutral and
/// never in the colour of "open". The read-only banner above it says in words
/// that no merge or deletion is made available by it.
class AdminVerdict extends StatelessWidget {
  const AdminVerdict({
    super.key,
    required this.hasBlockers,
    required this.findings,
  });

  final bool hasBlockers;
  final List<AdminPreviewFinding> findings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final blockers = findings
        .where((f) => f.severity == AdminFindingSeverity.blocker)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: GoStatusChip(
          key: const Key('adminPreviewVerdict'),
          label: hasBlockers
              ? l10n.adminPreviewVerdictBlocked(blockers)
              : l10n.adminPreviewVerdictClear,
          tone: hasBlockers ? GoChipTone.danger : GoChipTone.neutral,
        ),
      ),
    );
  }
}

/// Every finding, blockers first, each with its severity and its count.
class AdminFindingsList extends StatelessWidget {
  const AdminFindingsList({super.key, required this.findings});

  final List<AdminPreviewFinding> findings;

  static GoChipTone _tone(AdminFindingSeverity severity) => switch (severity) {
        AdminFindingSeverity.blocker => GoChipTone.danger,
        AdminFindingSeverity.conflict => GoChipTone.reserve,
        AdminFindingSeverity.constraint => GoChipTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(title: l10n.adminPreviewFindingsTitle),
        if (findings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
            child: Text(l10n.adminPreviewNothingInTheWay),
          )
        else
          SectionCard(children: [
            for (final finding in findings)
              Padding(
                key: Key('adminFinding_${finding.code}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: Layout.cardInner,
                  vertical: Gap.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GoStatusChip(
                            label: AdminPreviewLabels.severity(
                                l10n, finding.severity),
                            tone: _tone(finding.severity),
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(
                            AdminPreviewLabels.finding(l10n, finding.code),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Text(
                      '${finding.count}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
          ]),
      ],
    );
  }
}

/// "Showing 25 of 32" under a list the database bounded; nothing when it shows
/// everything.
class AdminBoundedNote extends StatelessWidget {
  const AdminBoundedNote({super.key, required this.shown, required this.total});

  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (shown >= total) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Layout.cardInner,
        Gap.xs,
        Layout.cardInner,
        Gap.md,
      ),
      child: Text(
        context.l10n.adminPreviewShowing(shown, total),
        key: const Key('adminPreviewBounded'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A row with a title, a line of detail and optional chips -- the shape every
/// community and match entry in a preview takes.
class AdminPreviewEntry extends StatelessWidget {
  const AdminPreviewEntry({
    super.key,
    required this.title,
    this.detail,
    this.lines = const [],
    this.tags = const [],
  });

  final String title;
  final String? detail;

  /// Further lines, each already worded.
  final List<String> lines;
  final List<({String label, GoChipTone tone})> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardInner,
        vertical: Gap.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(detail!, style: muted),
          ],
          for (final line in lines) ...[
            const SizedBox(height: 2),
            Text(line, style: muted),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xs,
              children: [
                for (final tag in tags)
                  GoStatusChip(label: tag.label, tone: tag.tone),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// What the previews could not see, in the words the database used for it.
class AdminCoverageNotes extends StatelessWidget {
  const AdminCoverageNotes({super.key, required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(title: l10n.adminPreviewCoverageTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.xs),
                  child: Text(
                    '• ${AdminPreviewLabels.coverage(l10n, note)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One account of a preview: who it is, how they sign in and how much of the
/// database names them. The optional [label] says what role the account plays
/// ("Account to keep"); [counts] adds the activity rows.
class AdminPreviewAccountCard extends StatelessWidget {
  const AdminPreviewAccountCard({
    super.key,
    required this.account,
    this.label,
  });

  final AdminPreviewAccount account;
  final String? label;

  static String _provider(AppLocalizations l10n, String provider) =>
      switch (provider) {
        'email' => l10n.emailLabel,
        'google' => l10n.adminProviderGoogle,
        _ => provider,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) SectionHeading(title: label!),
        Padding(
          padding: EdgeInsets.fromLTRB(
            kPageMargin,
            label == null ? Gap.lg : 0,
            kPageMargin,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(account.fullName, style: theme.textTheme.titleLarge),
              const SizedBox(height: Gap.xs),
              Text(
                account.email,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.xs,
                runSpacing: Gap.xs,
                children: [
                  GoStatusChip(
                    label: account.isActive
                        ? l10n.adminStatusActive
                        : l10n.adminStatusSuspended,
                    tone:
                        account.isActive ? GoChipTone.open : GoChipTone.danger,
                  ),
                  if (account.isSystemAdmin)
                    GoStatusChip(
                      label: l10n.adminStatusSystemAdmin,
                      tone: GoChipTone.reserve,
                    ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(children: [
          AdminDetailRow(
            label: l10n.adminAccountSignInMethodsLabel,
            value: account.signInProviders.isEmpty
                ? adminUnknownValue
                : account.signInProviders
                    .map((p) => _provider(l10n, p))
                    .join(' · '),
            unknown: account.signInProviders.isEmpty,
          ),
          if (account.rating != null)
            AdminDetailRow(
              label: l10n.adminPreviewRating,
              value: account.rating!.toStringAsFixed(1),
            ),
        ]),
      ],
    );
  }
}
