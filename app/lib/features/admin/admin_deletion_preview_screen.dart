import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import 'admin_detail_row.dart';
import 'admin_models.dart';
import 'admin_preview_widgets.dart';
import 'admin_repository.dart';

/// What deleting one account would touch -- and nothing else.
///
/// **A preview, structurally.** There is no delete, anonymise, transfer or
/// confirm control on this screen, and none is hidden behind a flag: the file
/// holds one repository call and it returns a description. The database function
/// beneath it is `stable`, writes no audit event, and refuses anyone who is not a
/// System Admin.
///
/// It reports, in this order: the verdict and every finding (blockers first),
/// the personal data the account holds, the communities it owns (which block the
/// delete until ownership moves), the matches it created (the same), the football
/// history the delete would erase or detach, the records nobody can change, and
/// the activity counts. A failed read offers a retry rather than drawing an empty
/// preview, because "nothing in the way" must never be the answer to "it did not
/// load".
class AdminDeletionPreviewScreen extends StatefulWidget {
  const AdminDeletionPreviewScreen({
    super.key,
    required this.userId,
    this.repository,
  });

  final String userId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final AdminRepository? repository;

  @override
  State<AdminDeletionPreviewScreen> createState() =>
      _AdminDeletionPreviewScreenState();
}

class _AdminDeletionPreviewScreenState
    extends State<AdminDeletionPreviewScreen> {
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository();

  late Future<AdminDeletionPreview> _future = _load();

  Future<AdminDeletionPreview> _load() {
    final preview = _repository.previewAccountDeletion(widget.userId);
    // A retry builds on the next frame, after this may already have failed.
    // `FutureBuilder` still shows the failure; `ignore` only stops it being
    // reported a second time as unhandled.
    preview.ignore();
    return preview;
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.adminPreviewDeletionTitle)),
      body: FutureBuilder<AdminDeletionPreview>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _reload);
          }
          return _Body(preview: snapshot.data!);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.preview});

  final AdminDeletionPreview preview;

  static GoChipTone _treatmentTone(String? treatment) => switch (treatment) {
        'CASCADE_DELETE' => GoChipTone.danger,
        'DETACH' => GoChipTone.reserve,
        _ => GoChipTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final account = preview.account;
    final statuses = preview.createdMatchesByStatus.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final counts = [
      for (final key in AdminPreviewLabels.countKeys)
        if (account.count(key) > 0) key,
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: Layout.listBottom),
      children: [
        const AdminReadOnlyBanner(),
        AdminPreviewAccountCard(account: account),
        AdminVerdict(
          hasBlockers: preview.hasBlockers,
          findings: preview.findings,
        ),
        AdminFindingsList(findings: preview.findings),
        SectionHeading(title: l10n.adminPreviewPersonalTitle),
        SectionCard(children: [
          for (final record in preview.personalData)
            AdminDetailRow(
              label: AdminPreviewLabels.personal(l10n, record.code),
              value: '${record.records}',
            ),
        ]),
        SectionHeading(
          title: l10n.adminPreviewOwnedTitle,
          count: preview.ownedCommunities.total,
        ),
        if (preview.ownedCommunities.total > 0)
          SectionCard(children: [
            for (final community in preview.ownedCommunities.items)
              AdminPreviewEntry(
                title: community.name,
                detail: l10n.adminPreviewOwnedRow(
                  community.memberCount,
                  community.otherAdminCount,
                  community.matchCount,
                ),
                tags: [
                  if (!community.isActive)
                    (label: l10n.adminStatusSuspended, tone: GoChipTone.danger),
                ],
              ),
            AdminBoundedNote(
              shown: preview.ownedCommunities.items.length,
              total: preview.ownedCommunities.total,
            ),
          ]),
        SectionHeading(
          title: l10n.adminPreviewCreatedTitle,
          count: preview.createdMatches.total,
        ),
        if (preview.createdMatches.total > 0)
          SectionCard(children: [
            if (statuses.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Layout.cardInner,
                  vertical: Gap.md,
                ),
                child: Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  children: [
                    for (final status in statuses)
                      GoStatusChip(label: '${status.key} · ${status.value}'),
                  ],
                ),
              ),
            for (final match in preview.createdMatches.items)
              AdminPreviewEntry(
                title: match.title,
                detail: [
                  if (match.communityName != null) match.communityName!,
                  if (match.startAt != null)
                    formatMuscatMatchDay(context, match.startAt!),
                ].join(' · '),
                tags: [
                  if (match.hasResult)
                    (
                      label: l10n.adminPreviewHasResult,
                      tone: GoChipTone.completed,
                    ),
                ],
              ),
            AdminBoundedNote(
              shown: preview.createdMatches.items.length,
              total: preview.createdMatches.total,
            ),
          ]),
        if (preview.historicalRecords.isNotEmpty) ...[
          SectionHeading(title: l10n.adminPreviewHistoricalTitle),
          SectionCard(children: [
            for (final record in preview.historicalRecords)
              AdminPreviewEntry(
                title:
                    '${AdminPreviewLabels.history(l10n, record.code)} · ${record.records}',
                tags: [
                  (
                    label: AdminPreviewLabels.treatment(l10n, record.treatment),
                    tone: _treatmentTone(record.treatment),
                  ),
                ],
              ),
          ]),
        ],
        if (preview.preservedRecords.isNotEmpty) ...[
          SectionHeading(title: l10n.adminPreviewPreservedTitle),
          SectionCard(children: [
            for (final record in preview.preservedRecords)
              AdminDetailRow(
                label: AdminPreviewLabels.history(l10n, record.code),
                value: '${record.records}',
              ),
          ]),
        ],
        if (counts.isNotEmpty) ...[
          SectionHeading(title: l10n.adminPreviewActivityTitle),
          SectionCard(children: [
            for (final key in counts)
              AdminDetailRow(
                label: AdminPreviewLabels.count(l10n, key),
                value: '${account.count(key)}',
              ),
          ]),
        ],
        AdminCoverageNotes(notes: preview.coverageNotes),
      ],
    );
  }
}
