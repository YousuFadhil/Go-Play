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

/// Merge one account into another, for good: first what it would do, then -- only
/// if nothing blocks it -- the merge itself.
///
/// **The preview and the action are one screen on purpose.** Choose the account to
/// keep and the account to merge in; the screen shows what collides, what the merge
/// does by itself, and every match both accounts took part in. For each of those
/// matches the administrator chooses whose participation stays. When nothing blocks
/// the merge and every choice is made, one destructive button opens a confirmation
/// that asks for the name of the account that will be deleted, and a single request
/// does the whole thing in the database, in one transaction.
///
/// The screen asks the database; it decides nothing. The database re-reads
/// everything inside its own transaction and refuses, changing nothing, if the
/// preview the administrator saw is no longer true.
///
/// A merge that returned has happened, and a failure that may have reached the
/// server is worded as "may or may not have been performed" -- never as "nothing
/// changed" -- so a dropped connection cannot invite a second attempt at something
/// already done.
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

  /// The administrator's choice for each shared match, by match id.
  final Map<String, AdminMergeKeep> _choices = {};

  /// True from the moment the request is sent until it is answered. Nothing else
  /// on the screen acts meanwhile, so a second tap cannot send a second request.
  bool _merging = false;

  /// True while the confirmation is open, so that two taps in one frame open one
  /// dialog and not two (confirming both would send the request twice).
  bool _confirming = false;
  AdminMergeResult? _done;
  String _doneRetainedName = '';
  String _doneSourceName = '';
  Failure? _failure;

  bool get _ready =>
      _retained != null && _source != null && _retained!.id != _source!.id;

  Future<void> _pick({required bool retained}) async {
    if (_merging) return;
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
      _forgetPreview();
    });
  }

  void _swap() {
    if (_merging) return;
    setState(() {
      final retained = _retained;
      _retained = _source;
      _source = retained;
      _forgetPreview();
    });
  }

  void _forgetPreview() {
    _preview = null;
    _choices.clear();
    _failure = null;
  }

  void _run() {
    if (!_ready || _merging) return;
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
      // A fresh answer is a fresh question: choices made against the old one go.
      _choices.clear();
      _failure = null;
    });
  }

  void _choose(String matchId, AdminMergeKeep keep) {
    if (_merging) return;
    setState(() => _choices[matchId] = keep);
  }

  Future<void> _merge(AdminMergePreview preview) async {
    if (_merging || _confirming) return;
    _confirming = true;
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmMergeDialog(
          sourceName: preview.source.fullName,
          retainedName: preview.retained.fullName,
        ),
      );
    } finally {
      _confirming = false;
    }
    if (confirmed != true || !mounted || _merging || _done != null) return;

    final resolutions = [
      for (final match in preview.sharedMatches.items)
        AdminMergeResolution(
            matchId: match.matchId, keep: _choices[match.matchId]!),
    ];
    setState(() {
      _merging = true;
      _failure = null;
    });
    try {
      final result = await _repository.mergeAccounts(
        // The accounts the preview was asked about. Choosing another one drops the
        // preview, so these are always the ones on the screen.
        retainedUserId: _retained!.id,
        sourceUserId: _source!.id,
        resolutions: resolutions,
      );
      if (!mounted) return;
      setState(() {
        _merging = false;
        _done = result;
        _doneRetainedName = preview.retained.fullName;
        _doneSourceName = preview.source.fullName;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _merging = false;
        _failure = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final done = _done;

    if (done != null) {
      return Scaffold(
        appBar: AppHeader(title: Text(l10n.adminPreviewMergeTitle)),
        body: ListView(
          padding: const EdgeInsets.only(bottom: Layout.listBottom),
          children: [
            _MergeDone(
              result: done,
              retainedName: _doneRetainedName,
              sourceName: _doneSourceName,
              // The account the request named as the one to keep, not whatever the
              // answer echoes: it is what the caller compares with its own.
              onDone: () => Navigator.of(context).pop(_retained!.id),
            ),
          ],
        ),
      );
    }

    final preview = _preview;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.adminPreviewMergeTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Layout.listBottom),
        children: [
          const _MergeNotice(),
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
                onPressed: (_retained == null && _source == null) || _merging
                    ? null
                    : _swap,
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
                  onPressed: _ready && !_merging ? _run : null,
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
                return _Result(
                  preview: snapshot.data!,
                  choices: _choices,
                  merging: _merging,
                  failure: _failure,
                  onChoose: _choose,
                  onMerge: () => _merge(snapshot.data!),
                  onCheckAgain: _run,
                );
              },
            ),
        ],
      ),
    );
  }
}

/// "Merging is permanent." -- on the screen, before anything is chosen.
class _MergeNotice extends StatelessWidget {
  const _MergeNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
      child: Row(
        key: const Key('adminMergeNotice'),
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
              context.l10n.adminMergeNotice,
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

/// The merge preview itself, once it has been read, and the means to act on it.
class _Result extends StatelessWidget {
  const _Result({
    required this.preview,
    required this.choices,
    required this.merging,
    required this.failure,
    required this.onChoose,
    required this.onMerge,
    required this.onCheckAgain,
  });

  final AdminMergePreview preview;
  final Map<String, AdminMergeKeep> choices;
  final bool merging;
  final Failure? failure;
  final void Function(String matchId, AdminMergeKeep keep) onChoose;
  final VoidCallback onMerge;
  final VoidCallback onCheckAgain;

  List<({String label, int value})> _planRows(AppLocalizations l10n) {
    final plan = preview.plan;
    return [
      (
        label: l10n.adminMergePlanCommunitiesTransferred,
        value: plan.communitiesTransferred
      ),
      (
        label: l10n.adminMergePlanMembershipsMoved,
        value: plan.membershipsMoved
      ),
      (
        label: l10n.adminMergePlanMembershipsMerged,
        value: plan.membershipsMerged
      ),
      (label: l10n.adminMergePlanRolesUpgraded, value: plan.rolesUpgraded),
      (
        label: l10n.adminMergePlanRegistrationsMoved,
        value: plan.registrationsMoved
      ),
      (
        label: l10n.adminMergePlanLineupPlacesMoved,
        value: plan.lineupPlacesMoved
      ),
      (label: l10n.adminMergePlanGoalRowsMoved, value: plan.goalRowsMoved),
      (label: l10n.adminMergePlanMvpAwardsMoved, value: plan.mvpAwardsMoved),
      (label: l10n.adminMergePlanTeamAwardsMoved, value: plan.teamAwardsMoved),
      (
        label: l10n.adminMergePlanCreatedMatches,
        value: plan.createdMatchesReattributed
      ),
    ].where((row) => row.value > 0).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final retained = preview.retained;
    final source = preview.source;
    final counts = [
      for (final key in AdminPreviewLabels.countKeys)
        if (retained.count(key) > 0 || source.count(key) > 0) key,
    ];
    final planRows = _planRows(l10n);
    final unchosen = [
      for (final match in preview.sharedMatches.items)
        if (!choices.containsKey(match.matchId)) match,
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
                      tone: GoChipTone.reserve,
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
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Layout.cardInner,
                vertical: Gap.md,
              ),
              child: Text(
                '${l10n.adminMergeChoiceTitle}. ${l10n.adminMergeChoiceHelp}',
                key: const Key('adminMergeChoiceHelp'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            for (final match in preview.sharedMatches.items)
              _SharedMatchChoice(
                match: match,
                retainedName: retained.fullName,
                sourceName: source.fullName,
                choice: choices[match.matchId],
                enabled: !merging,
                onChoose: (keep) => onChoose(match.matchId, keep),
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
        SectionHeading(title: l10n.adminMergePlanTitle),
        SectionCard(
          key: const Key('adminMergePlan'),
          children: [
            for (final row in planRows)
              AdminDetailRow(label: row.label, value: '${row.value}'),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Layout.cardInner,
                vertical: Gap.md,
              ),
              child: Text(
                l10n.adminMergePlanFootnote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
        AdminCoverageNotes(notes: preview.coverageNotes),
        _ExecuteSection(
          preview: preview,
          missingChoices: unchosen.length,
          merging: merging,
          failure: failure,
          onMerge: onMerge,
          onCheckAgain: onCheckAgain,
        ),
      ],
    );
  }
}

/// One shared match: what each account holds in it, and the choice of which stays.
class _SharedMatchChoice extends StatelessWidget {
  const _SharedMatchChoice({
    required this.match,
    required this.retainedName,
    required this.sourceName,
    required this.choice,
    required this.enabled,
    required this.onChoose,
  });

  final AdminSharedMatch match;
  final String retainedName;
  final String sourceName;
  final AdminMergeKeep? choice;
  final bool enabled;
  final ValueChanged<AdminMergeKeep> onChoose;

  String _reasons(AppLocalizations l10n, List<String> codes) =>
      codes.map((c) => AdminPreviewLabels.dropBlocker(l10n, c)).join(', ');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      key: Key('adminSharedMatch_${match.matchId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Layout.cardInner,
            0,
            Layout.cardInner,
            Gap.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: [
                  ChoiceChip(
                    key: Key('adminMergeChoice_${match.matchId}_retained'),
                    label: Text(l10n.adminMergeKeepRetained(retainedName)),
                    selected: choice == AdminMergeKeep.retained,
                    onSelected: enabled && match.canKeepRetained
                        ? (_) => onChoose(AdminMergeKeep.retained)
                        : null,
                  ),
                  ChoiceChip(
                    key: Key('adminMergeChoice_${match.matchId}_source'),
                    label: Text(l10n.adminMergeKeepSource(sourceName)),
                    selected: choice == AdminMergeKeep.source,
                    onSelected: enabled && match.canKeepSource
                        ? (_) => onChoose(AdminMergeKeep.source)
                        : null,
                  ),
                ],
              ),
              // Keeping the retained side removes the source's, and so it is the
              // source's side that explains why that choice is closed.
              if (!match.canKeepRetained)
                _Held(
                  key: Key('adminMergeHeld_${match.matchId}_source'),
                  text: l10n.adminMergeHeldBy(
                    sourceName,
                    _reasons(l10n, match.sourceDropBlockers),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              if (!match.canKeepSource)
                _Held(
                  key: Key('adminMergeHeld_${match.matchId}_retained'),
                  text: l10n.adminMergeHeldBy(
                    retainedName,
                    _reasons(l10n, match.retainedDropBlockers),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Held extends StatelessWidget {
  const _Held({super.key, required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Gap.xs),
        child: Text(
          text,
          style: style?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// The one destructive control, and the words around it.
class _ExecuteSection extends StatelessWidget {
  const _ExecuteSection({
    required this.preview,
    required this.missingChoices,
    required this.merging,
    required this.failure,
    required this.onMerge,
    required this.onCheckAgain,
  });

  final AdminMergePreview preview;
  final int missingChoices;
  final bool merging;
  final Failure? failure;
  final VoidCallback onMerge;
  final VoidCallback onCheckAgain;

  static String failureText(AppLocalizations l10n, Failure failure) {
    // The merge was never attempted: the picture could not be removed first.
    if (failure.reason == FailureReason.avatarCleanupFailed) {
      return l10n.adminMergeFailedAvatarCleanup;
    }
    final text = switch (failure) {
      ConflictFailure() => l10n.adminMergeFailedConflict,
      NotFoundFailure() => l10n.adminMergeFailedNotFound,
      AuthorizationFailure() => l10n.adminMergeFailedAuthorization,
      ValidationFailure() => l10n.adminMergeFailedValidation,
      // A dropped connection, a database error, a session that ended: the request
      // may have reached the server and the merge may have committed.
      _ => l10n.adminMergeFailedUncertain,
    };
    // The picture goes before the merge runs, so a merge that failed afterwards has
    // still cost it. Said as a fact on top of the failure, never instead of it.
    return failure.reason == FailureReason.avatarRemovedFirst
        ? '$text ${l10n.adminMergeAvatarRemovedNote}'
        : text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final blocked = preview.hasBlockers;
    final failure = this.failure;
    // After a failed attempt nothing more is offered until the preview has been
    // read again: the server may have refused for a reason the choices no longer
    // answer, or may even have done the merge.
    final canMerge =
        !blocked && missingChoices == 0 && !merging && failure == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.xl, kPageMargin, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null) ...[
            Container(
              key: const Key('adminMergeFailure'),
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
              key: const Key('adminMergeCheckAgain'),
              onPressed: merging ? null : onCheckAgain,
              child: Text(l10n.adminMergeCheckAgain),
            ),
            const SizedBox(height: Gap.md),
          ],
          FilledButton(
            key: const Key('adminMergeExecuteButton'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: canMerge ? onMerge : null,
            child: merging
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
                      Text(l10n.adminMergeRunning),
                    ],
                  )
                : Text(l10n.adminMergeExecuteButton),
          ),
          if (!canMerge && !merging && failure == null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              blocked
                  ? l10n.adminMergeResolveBlockersFirst
                  : l10n.adminMergeNeedChoices(missingChoices),
              key: const Key('adminMergeWhyNot'),
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
class _ConfirmMergeDialog extends StatefulWidget {
  const _ConfirmMergeDialog({
    required this.sourceName,
    required this.retainedName,
  });

  final String sourceName;
  final String retainedName;

  @override
  State<_ConfirmMergeDialog> createState() => _ConfirmMergeDialogState();
}

class _ConfirmMergeDialogState extends State<_ConfirmMergeDialog> {
  final _controller = TextEditingController();

  bool get _matches => _controller.text.trim() == widget.sourceName.trim();

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
      key: const Key('adminMergeConfirmDialog'),
      title: Text(l10n.adminMergeConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.adminMergeConfirmBody(
                  widget.sourceName, widget.retainedName),
            ),
            const SizedBox(height: Gap.md),
            TextField(
              key: const Key('adminMergeConfirmField'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.adminMergeConfirmField,
                helperText: l10n.adminMergeConfirmTypeLabel(widget.sourceName),
                helperMaxLines: 3,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('adminMergeConfirmCancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          key: const Key('adminMergeConfirmAction'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(l10n.adminMergeConfirmAction),
        ),
      ],
    );
  }
}

/// What happened, once the database has answered: the only thing left on the screen.
class _MergeDone extends StatelessWidget {
  const _MergeDone({
    required this.result,
    required this.retainedName,
    required this.sourceName,
    required this.onDone,
  });

  final AdminMergeResult result;
  final String retainedName;
  final String sourceName;
  final VoidCallback onDone;

  static String _rating(double value) => value.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final before = result.ratingBefore;
    final after = result.ratingAfter;

    return Padding(
      key: const Key('adminMergeDone'),
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
            l10n.adminMergeDoneTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            l10n.adminMergeDoneBody(sourceName, retainedName),
            textAlign: TextAlign.center,
          ),
          if (before != null && after != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              l10n.adminMergeDoneRating(
                retainedName,
                _rating(before),
                _rating(after),
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Gap.xl),
          FilledButton(
            key: const Key('adminMergeDoneButton'),
            onPressed: onDone,
            child: Text(l10n.adminMergeDoneButton),
          ),
        ],
      ),
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
