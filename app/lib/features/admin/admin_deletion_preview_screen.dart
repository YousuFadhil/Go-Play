import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import 'admin_detail_row.dart';
import 'admin_models.dart';
import 'admin_preview_widgets.dart';
import 'admin_repository.dart';

/// What deleting one account would do -- and, when nothing blocks it, the deletion.
///
/// **The preview and the action are one screen on purpose.** It reports, in this order: the
/// verdict and every finding (blockers first), the personal data the account holds, the
/// communities it owns (which block the deletion until ownership moves), the matches it
/// created (which stay), what happens to the football history (kept, shown as Deleted
/// Player), the records nobody can change, and the activity counts. When nothing blocks, one
/// destructive button opens a confirmation that asks for the name of the account, and a
/// single request does the whole thing in the database, in one transaction.
///
/// The screen asks the database; it decides nothing. The database re-reads everything inside
/// its own transaction and refuses, changing nothing, if the preview the administrator saw is
/// no longer true. A failed read offers a retry rather than drawing an empty preview, because
/// "nothing in the way" must never be the answer to "it did not load".
///
/// A deletion that returned has happened, and a failure that may have reached the server is
/// worded as "may or may not have been performed" -- never as "nothing changed" -- so a
/// dropped connection cannot invite a second attempt at something already done.
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

  /// True from the moment the request is sent until it is answered. Nothing else on the
  /// screen acts meanwhile, so a second tap cannot send a second request.
  bool _deleting = false;

  /// True while the confirmation is open, so that two taps in one frame open one dialog.
  bool _confirming = false;
  String? _deletedName;
  Failure? _failure;

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
      _failure = null;
    });
  }

  Future<void> _delete(AdminDeletionPreview preview) async {
    if (_deleting || _confirming) return;
    _confirming = true;
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmDeleteDialog(name: preview.account.fullName),
      );
    } finally {
      _confirming = false;
    }
    if (confirmed != true || !mounted || _deleting || _deletedName != null) {
      return;
    }

    setState(() {
      _deleting = true;
      _failure = null;
    });
    try {
      await _repository.deleteAccount(widget.userId);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _deletedName = preview.account.fullName;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _failure = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deleted = _deletedName;

    if (deleted != null) {
      return Scaffold(
        appBar: AppHeader(title: Text(l10n.adminPreviewDeletionTitle)),
        body: ListView(
          padding: const EdgeInsets.only(bottom: Layout.listBottom),
          children: [
            _DeleteDone(
              name: deleted,
              // True: the account is gone, so the screens behind this one leave too.
              onDone: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
    }

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
          return _Body(
            preview: snapshot.data!,
            deleting: _deleting,
            failure: _failure,
            onDelete: () => _delete(snapshot.data!),
            onCheckAgain: _reload,
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.preview,
    required this.deleting,
    required this.failure,
    required this.onDelete,
    required this.onCheckAgain,
  });

  final AdminDeletionPreview preview;
  final bool deleting;
  final Failure? failure;
  final VoidCallback onDelete;
  final VoidCallback onCheckAgain;

  static GoChipTone _treatmentTone(String? treatment) => switch (treatment) {
        'CASCADE_DELETE' => GoChipTone.danger,
        'DETACH' || 'REMOVED' => GoChipTone.reserve,
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
        const _DeleteNotice(),
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
        _DeleteSection(
          hasBlockers: preview.hasBlockers,
          deleting: deleting,
          failure: failure,
          onDelete: onDelete,
          onCheckAgain: onCheckAgain,
        ),
      ],
    );
  }
}

/// "Deleting is permanent." -- on the screen, before anything is chosen.
class _DeleteNotice extends StatelessWidget {
  const _DeleteNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
      child: Row(
        key: const Key('adminDeleteNotice'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: IconSize.meta,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              context.l10n.adminDeleteNotice,
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

/// The one destructive control, and the words around it.
class _DeleteSection extends StatelessWidget {
  const _DeleteSection({
    required this.hasBlockers,
    required this.deleting,
    required this.failure,
    required this.onDelete,
    required this.onCheckAgain,
  });

  final bool hasBlockers;
  final bool deleting;
  final Failure? failure;
  final VoidCallback onDelete;
  final VoidCallback onCheckAgain;

  static String failureText(AppLocalizations l10n, Failure failure) {
    // The deletion was never attempted: the picture could not be removed first.
    if (failure.reason == FailureReason.avatarCleanupFailed) {
      return l10n.adminDeleteFailedAvatarCleanup;
    }
    final text = switch (failure) {
      ConflictFailure() => l10n.adminDeleteFailedConflict,
      NotFoundFailure() => l10n.adminDeleteFailedNotFound,
      AuthorizationFailure() => l10n.adminDeleteFailedAuthorization,
      ValidationFailure() => l10n.adminDeleteFailedValidation,
      // A dropped connection, a database error, a session that ended: the request may
      // have reached the server and the deletion may have committed.
      _ => l10n.adminDeleteFailedUncertain,
    };
    // The picture goes before the deletion runs, so a deletion that failed afterwards has
    // still cost it. Said as a fact on top of the failure, never instead of it.
    return failure.reason == FailureReason.avatarRemovedFirst
        ? '$text ${l10n.adminDeleteAvatarRemovedNote}'
        : text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final failure = this.failure;
    // After a failed attempt nothing more is offered until the preview has been read
    // again: the server may have refused for a reason the screen no longer reflects, or
    // may even have done the deletion.
    final canDelete = !hasBlockers && !deleting && failure == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.xl, kPageMargin, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null) ...[
            Container(
              key: const Key('adminDeleteFailure'),
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(Gap.sm),
              ),
              child: Text(
                failureText(l10n, failure),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton(
              key: const Key('adminDeleteCheckAgain'),
              onPressed: deleting ? null : onCheckAgain,
              child: Text(l10n.adminMergeCheckAgain),
            ),
            const SizedBox(height: Gap.md),
          ],
          FilledButton(
            key: const Key('adminDeleteExecuteButton'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: canDelete ? onDelete : null,
            child: deleting
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(l10n.adminDeleteRunning),
                    ],
                  )
                : Text(l10n.adminDeleteExecuteButton),
          ),
          if (hasBlockers && !deleting && failure == null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              l10n.adminMergeResolveBlockersFirst,
              key: const Key('adminDeleteWhyNot'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The confirmation: the name of the account that will be deleted has to be typed.
class _ConfirmDeleteDialog extends StatefulWidget {
  const _ConfirmDeleteDialog({required this.name});

  final String name;

  @override
  State<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends State<_ConfirmDeleteDialog> {
  final _controller = TextEditingController();

  bool get _matches => _controller.text.trim() == widget.name.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('adminDeleteConfirmDialog'),
      title: Text(l10n.adminDeleteAccountConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.adminDeleteConfirmBody(widget.name)),
            const SizedBox(height: Gap.md),
            TextField(
              key: const Key('adminDeleteConfirmField'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.adminMergeConfirmField,
                helperText: l10n.adminMergeConfirmTypeLabel(widget.name),
                helperMaxLines: 3,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('adminDeleteConfirmCancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          key: const Key('adminDeleteConfirmAction'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(l10n.adminDeleteConfirmAction),
        ),
      ],
    );
  }
}

/// What happened, once the database has answered: the only thing left on the screen.
class _DeleteDone extends StatelessWidget {
  const _DeleteDone({required this.name, required this.onDone});

  final String name;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Padding(
      key: const Key('adminDeleteDone'),
      padding: const EdgeInsets.all(kPageMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Gap.xl),
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: Gap.md),
          Text(
            l10n.adminDeleteDoneTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            l10n.adminDeleteDoneBody(name),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.xl),
          FilledButton(
            key: const Key('adminDeleteDoneButton'),
            onPressed: onDone,
            child: Text(l10n.adminMergeDoneButton),
          ),
        ],
      ),
    );
  }
}
