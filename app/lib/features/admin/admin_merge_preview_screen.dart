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

/// What folding one account into another would collide with -- and nothing else.
///
/// **A preview, structurally.** Choose the account to keep and the account to
/// merge in, and the screen describes the collisions: communities both belong to
/// and the role and ownership conflicts among them, matches both appear in, the
/// statistics that would clash, and what cannot be moved. There is no merge,
/// transfer or confirm control, and none is hidden behind a flag: the file holds
/// one repository call and it returns a description.
///
/// The account the administrator came from is the one to keep; the other is
/// chosen from the Users list, and the two can be swapped. The same account
/// twice is refused before the database is asked.
class AdminMergePreviewScreen extends StatefulWidget {
  const AdminMergePreviewScreen({
    super.key,
    required this.retained,
    this.repository,
  });

  /// The account the administrator opened this from, offered as the one to keep.
  final AdminUserSummary retained;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final AdminRepository? repository;

  @override
  State<AdminMergePreviewScreen> createState() =>
      _AdminMergePreviewScreenState();
}

class _AdminMergePreviewScreenState extends State<AdminMergePreviewScreen> {
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository();

  late AdminUserSummary? _retained = widget.retained;
  AdminUserSummary? _source;
  Future<AdminMergePreview>? _preview;

  bool get _ready =>
      _retained != null && _source != null && _retained!.id != _source!.id;

  Future<void> _pick({required bool retained}) async {
    final other = retained ? _source : _retained;
    final picked = await showModalBottomSheet<AdminUserSummary>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AccountPicker(
        repository: _repository,
        excludeId: other?.id,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (retained) {
        _retained = picked;
      } else {
        _source = picked;
      }
      // A different pair is a different question; the old answer is dropped.
      _preview = null;
    });
  }

  void _swap() {
    setState(() {
      final retained = _retained;
      _retained = _source;
      _source = retained;
      _preview = null;
    });
  }

  void _run() {
    if (!_ready) return;
    final preview = _repository.previewAccountMerge(
      retainedUserId: _retained!.id,
      sourceUserId: _source!.id,
    );
    // The screen builds on the next frame, after this future may already have
    // failed. `FutureBuilder` still sees the failure and shows the retry;
    // `ignore` only stops it being reported a second time as unhandled.
    preview.ignore();
    setState(() {
      _preview = preview;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preview = _preview;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.adminPreviewMergeTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Layout.listBottom),
        children: [
          const AdminReadOnlyBanner(),
          SectionHeading(title: l10n.adminPreviewAccountsTitle),
          SectionCard(children: [
            _Slot(
              key: const Key('adminMergeRetainedSlot'),
              label: l10n.adminMergeRetainedLabel,
              account: _retained,
              onTap: () => _pick(retained: true),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                key: const Key('adminMergeSwap'),
                tooltip: l10n.adminMergeSwap,
                icon: const Icon(Icons.swap_vert),
                onPressed: _retained == null && _source == null ? null : _swap,
              ),
            ),
            _Slot(
              key: const Key('adminMergeSourceSlot'),
              label: l10n.adminMergeSourceLabel,
              account: _source,
              onTap: () => _pick(retained: false),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kPageMargin,
              vertical: Gap.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  key: const Key('adminMergePreviewButton'),
                  onPressed: _ready ? _run : null,
                  child: Text(l10n.adminMergePreviewButton),
                ),
                if (!_ready) ...[
                  const SizedBox(height: Gap.sm),
                  Text(
                    l10n.adminMergeNeedTwo,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (preview != null)
            FutureBuilder<AdminMergePreview>(
              future: preview,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(Gap.xl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: kPageMargin),
                    child: Row(
                      children: [
                        Expanded(child: Text(l10n.loadFailed)),
                        TextButton(
                          key: const Key('adminMergeRetry'),
                          onPressed: _run,
                          child: Text(l10n.retryButton),
                        ),
                      ],
                    ),
                  );
                }
                return _Result(preview: snapshot.data!);
              },
            ),
        ],
      ),
    );
  }
}

/// One of the two accounts being compared, or the prompt to choose it.
class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.label,
    required this.account,
    required this.onTap,
  });

  final String label;
  final AdminUserSummary? account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.cardInner,
          vertical: Gap.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    account?.fullName ?? l10n.adminMergeChoose,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (account != null)
                    Text(
                      account!.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

/// A searchable list of accounts to choose from. Reads through the same
/// `admin_list_users` the Users tab does, so it shows the same people.
class _AccountPicker extends StatefulWidget {
  const _AccountPicker({required this.repository, this.excludeId});

  final AdminRepository repository;
  final String? excludeId;

  @override
  State<_AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends State<_AccountPicker> {
  final _controller = TextEditingController();
  late Future<List<AdminUserSummary>> _future = _load();

  Future<List<AdminUserSummary>> _load() {
    final query = _controller.text.trim();
    final users = widget.repository
        .listUsers(query.isEmpty ? null : query)
        .then((users) => [
              for (final user in users)
                if (user.id != widget.excludeId) user,
            ]);
    // See `_run` in the screen above: a search that fails before the next frame
    // is still shown as failed, and not also reported as unhandled.
    users.ignore();
    return users;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kPageMargin,
                0,
                kPageMargin,
                Gap.sm,
              ),
              child: TextField(
                key: const Key('adminMergeSearch'),
                controller: _controller,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: l10n.adminSearchLabel,
                  hintText: l10n.adminMergeSearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
                onSubmitted: (_) => setState(() => _future = _load()),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<AdminUserSummary>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LoadingState();
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return ErrorState(
                      onRetry: () => setState(() => _future = _load()),
                    );
                  }
                  final users = snapshot.data!;
                  if (users.isEmpty) {
                    return Center(child: Text(l10n.adminPickerNoResults));
                  }
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return ListTile(
                        key: Key('adminMergePick_${user.id}'),
                        title: Text(user.fullName),
                        subtitle: Text(user.email),
                        onTap: () => Navigator.of(context).pop(user),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The merge preview itself, once it has been read.
class _Result extends StatelessWidget {
  const _Result({required this.preview});

  final AdminMergePreview preview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final retained = preview.retained;
    final source = preview.source;
    final counts = [
      for (final key in AdminPreviewLabels.countKeys)
        if (retained.count(key) > 0 || source.count(key) > 0) key,
    ];
    final collisionKinds = [
      for (final entry in preview.collisionsByKind.entries)
        if (entry.value > 0) entry,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminVerdict(
          hasBlockers: preview.hasBlockers,
          findings: preview.findings,
        ),
        AdminFindingsList(findings: preview.findings),
        AdminPreviewAccountCard(
          label: l10n.adminMergeRetainedLabel,
          account: retained,
        ),
        AdminPreviewAccountCard(
          label: l10n.adminMergeSourceLabel,
          account: source,
        ),
        if (counts.isNotEmpty) ...[
          SectionHeading(title: l10n.adminPreviewActivityTitle),
          SectionCard(children: [
            _CountsHeader(
              retained: l10n.adminPreviewRetainedColumn,
              source: l10n.adminPreviewSourceColumn,
            ),
            for (final key in counts)
              _CountsRow(
                label: AdminPreviewLabels.count(l10n, key),
                retained: retained.count(key),
                source: source.count(key),
              ),
          ]),
        ],
        SectionHeading(
          title: l10n.adminPreviewOverlapTitle,
          count: preview.overlappingCommunities.total,
        ),
        if (preview.overlappingCommunities.total > 0)
          SectionCard(children: [
            for (final overlap in preview.overlappingCommunities.items)
              AdminPreviewEntry(
                title: overlap.name,
                detail: '${l10n.adminPreviewRetainedColumn}: '
                    '${AdminPreviewLabels.role(l10n, overlap.retainedRole)}'
                    ' · ${l10n.adminPreviewSourceColumn}: '
                    '${AdminPreviewLabels.role(l10n, overlap.sourceRole)}',
                tags: [
                  if (overlap.sourceOwns)
                    (
                      label: l10n.adminPreviewTagSourceOwns,
                      tone: GoChipTone.danger,
                    ),
                  if (overlap.retainedOwns)
                    (
                      label: l10n.adminPreviewTagRetainedOwns,
                      tone: GoChipTone.neutral,
                    ),
                  if (overlap.roleConflict)
                    (
                      label: l10n.adminPreviewTagRoleConflict,
                      tone: GoChipTone.reserve,
                    ),
                ],
              ),
            AdminBoundedNote(
              shown: preview.overlappingCommunities.items.length,
              total: preview.overlappingCommunities.total,
            ),
          ]),
        SectionHeading(
          title: l10n.adminPreviewSourceOwnedTitle,
          count: preview.sourceOwnedCommunities.total,
        ),
        if (preview.sourceOwnedCommunities.total > 0)
          SectionCard(children: [
            for (final community in preview.sourceOwnedCommunities.items)
              AdminPreviewEntry(
                title: community.name,
                detail: community.retainedIsMember
                    ? '${l10n.adminPreviewRetainedColumn}: '
                        '${AdminPreviewLabels.role(l10n, community.retainedRole ?? '')}'
                    : l10n.adminPreviewRetainedNotMember,
              ),
            AdminBoundedNote(
              shown: preview.sourceOwnedCommunities.items.length,
              total: preview.sourceOwnedCommunities.total,
            ),
          ]),
        SectionHeading(
          title: l10n.adminPreviewSharedMatchesTitle,
          count: preview.sharedMatches.total,
        ),
        if (preview.sharedMatches.total > 0)
          SectionCard(children: [
            if (collisionKinds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Layout.cardInner,
                  vertical: Gap.md,
                ),
                child: Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  children: [
                    for (final kind in collisionKinds)
                      GoStatusChip(
                        label:
                            '${AdminPreviewLabels.evidence(l10n, kind.key.toUpperCase())}'
                            ' · ${kind.value}',
                        tone: GoChipTone.danger,
                      ),
                  ],
                ),
              ),
            for (final match in preview.sharedMatches.items)
              AdminPreviewEntry(
                title: match.title,
                detail: [
                  if (match.communityName != null) match.communityName!,
                  if (match.startAt != null)
                    formatMuscatMatchDay(context, match.startAt!),
                ].join(' · '),
                lines: [
                  '${l10n.adminPreviewRetainedColumn}: '
                      '${match.retainedEvidence.map((e) => AdminPreviewLabels.evidence(l10n, e)).join(', ')}',
                  '${l10n.adminPreviewSourceColumn}: '
                      '${match.sourceEvidence.map((e) => AdminPreviewLabels.evidence(l10n, e)).join(', ')}',
                ],
                tags: [
                  if (match.collision)
                    (
                      label: l10n.adminPreviewCollision,
                      tone: GoChipTone.danger,
                    ),
                ],
              ),
            AdminBoundedNote(
              shown: preview.sharedMatches.items.length,
              total: preview.sharedMatches.total,
            ),
          ]),
        if (preview.communityStatisticsCollisions > 0 ||
            preview.teamAwardCollisions > 0) ...[
          SectionHeading(title: l10n.adminPreviewStatisticsTitle),
          SectionCard(children: [
            if (preview.communityStatisticsCollisions > 0)
              AdminDetailRow(
                label: l10n.adminCountCommunityStatistics,
                value: '${preview.communityStatisticsCollisions}',
              ),
            if (preview.teamAwardCollisions > 0)
              AdminDetailRow(
                label: l10n.adminCountTeamAwards,
                value: '${preview.teamAwardCollisions}',
              ),
          ]),
        ],
        AdminCoverageNotes(notes: preview.coverageNotes),
      ],
    );
  }
}

/// "Keep | Merge in" over the two columns of counts.
class _CountsHeader extends StatelessWidget {
  const _CountsHeader({required this.retained, required this.source});

  final String retained;
  final String source;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardInner,
        vertical: Gap.sm,
      ),
      child: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          SizedBox(
              width: 72,
              child: Text(retained, style: style, textAlign: TextAlign.end)),
          SizedBox(
              width: 72,
              child: Text(source, style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _CountsRow extends StatelessWidget {
  const _CountsRow({
    required this.label,
    required this.retained,
    required this.source,
  });

  final String label;
  final int retained;
  final int source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardInner,
        vertical: Gap.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
              width: 72,
              child: Text('$retained', style: value, textAlign: TextAlign.end)),
          SizedBox(
              width: 72,
              child: Text('$source', style: value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
