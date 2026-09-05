import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import 'admin_audit_tab.dart';
import 'admin_overview_tab.dart';
import 'admin_repository.dart';
import 'admin_user_detail_screen.dart';

/// What a row lets an administrator do to the record behind it.
enum AdminRowAction {
  /// Nothing. A System Admin account, and the Matches list, which is read-only.
  none,

  /// The record is active and may be suspended. Needs a reason.
  suspend,

  /// The record is suspended and may be restored. Needs only a confirmation.
  reactivate,
}

/// One line of an admin list, already worded.
///
/// The three sections show different records, so each is reduced to a title, a
/// subtitle, a state and the one action that applies to it. Composing that
/// sentence is the screen's job, not the repository's (OP-3).
class _Row {
  const _Row({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.action,
    this.isActive = true,
    this.isSystemAdmin = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final AdminRowAction action;

  /// The authoritative state, straight from `is_active`.
  final bool isActive;

  /// A System Admin account. The normal path may not suspend one -- the
  /// database refuses with `CANNOT_SUSPEND_SYSTEM_ADMIN`, and the screen does
  /// not offer it either.
  final bool isSystemAdmin;
}

/// Stands in for a name the record does not carry.
const _missing = '—';

/// The whole of internal administration: an Overview, and three lists each with
/// a search field.
///
/// Users and Communities can be suspended and restored; Matches is inspection
/// only. Permanent delete is deliberately absent -- suspension is reversible
/// and is what the product asks for. The `admin_delete_*` RPCs still exist in
/// the database, untouched, but nothing here calls them.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, AdminRepository? repository})
      : _repository = repository;

  final AdminRepository? _repository;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final repository = _repository ?? AdminRepository();

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppHeader(
          title: Text(l10n.adminTitle),
          bottom: TabBar(
            // Five labels now, several of them long in Arabic. Scrollable so
            // the last is reachable on a narrow phone rather than crushed to
            // two characters -- a local layout detail, not a redesign.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.adminOverviewTab),
              Tab(text: l10n.adminUsersTab),
              Tab(text: l10n.adminCommunitiesTab),
              Tab(text: l10n.adminMatchesTab),
              Tab(text: l10n.adminAuditTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // First, because it is what an administrator opens this screen to
            // find out. The three lists are what they do about the answer.
            AdminOverviewTab(repository: repository),
            _AdminList(
              load: (search) async => [
                for (final user in await repository.listUsers(search))
                  _Row(
                    id: user.id,
                    title: user.fullName,
                    subtitle: user.email,
                    isActive: user.isActive,
                    isSystemAdmin: user.isSystemAdmin,
                    // A System Admin is protected: no action at all, rather
                    // than a disabled one that invites a second try.
                    action: user.isSystemAdmin
                        ? AdminRowAction.none
                        : user.isActive
                            ? AdminRowAction.suspend
                            : AdminRowAction.reactivate,
                  ),
              ],
              // Only the Users list opens a detail screen: it is the only one
              // the database has an activity summary for. A row's action button
              // handles its own tap, so pressing Suspend does not also open the
              // detail underneath it.
              open: (row) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdminUserDetailScreen(
                    userId: row.id,
                    repository: repository,
                  ),
                ),
              ),
              suspend: repository.suspendUser,
              reactivate: repository.reactivateUser,
              suspendTitle: (name) => l10n.adminSuspendUserConfirmTitle(name),
              suspendBody: l10n.adminSuspendUserConfirmBody,
              reactivateTitle: (name) =>
                  l10n.adminReactivateUserConfirmTitle(name),
              reactivateBody: l10n.adminReactivateUserConfirmBody,
            ),
            _AdminList(
              load: (search) async => [
                for (final community
                    in await repository.listCommunities(search))
                  _Row(
                    id: community.id,
                    title: community.name,
                    subtitle: '${community.ownerName ?? _missing} · '
                        '${community.memberCount} · ${community.matchCount}',
                    isActive: community.isActive,
                    action: community.isActive
                        ? AdminRowAction.suspend
                        : AdminRowAction.reactivate,
                  ),
              ],
              suspend: repository.suspendCommunity,
              reactivate: repository.reactivateCommunity,
              suspendTitle: (name) =>
                  l10n.adminSuspendCommunityConfirmTitle(name),
              suspendBody: l10n.adminSuspendCommunityConfirmBody,
              reactivateTitle: (name) =>
                  l10n.adminReactivateCommunityConfirmTitle(name),
              reactivateBody: l10n.adminReactivateCommunityConfirmBody,
            ),
            // Matches: operational inspection, and nothing else. There is no
            // Suspend Match in the approved model and no delete here any more.
            _AdminList(
              load: (search) async => [
                for (final match in await repository.listMatches(search))
                  _Row(
                    id: match.id,
                    title: match.title ?? '',
                    subtitle: '${match.communityName ?? _missing} · '
                        '${match.location} · ${match.registrationCount}',
                    action: AdminRowAction.none,
                  ),
              ],
            ),
            // The administrative record. Read only -- no delete, no edit, no
            // undo, and no write path in reach of it.
            AdminAuditTab(repository: repository),
          ],
        ),
      ),
    );
  }
}

class _AdminList extends StatefulWidget {
  const _AdminList({
    required this.load,
    this.open,
    this.suspend,
    this.reactivate,
    this.suspendTitle,
    this.suspendBody,
    this.reactivateTitle,
    this.reactivateBody,
  });

  final Future<List<_Row>> Function(String? search) load;

  /// What tapping a row does, where a row has somewhere to go. Null on the
  /// lists that have no detail screen, and a row with no destination is not
  /// tappable at all rather than tappable and inert.
  final void Function(_Row row)? open;
  final Future<void> Function(String id, String reason)? suspend;
  final Future<void> Function(String id)? reactivate;
  final String Function(String name)? suspendTitle;
  final String? suspendBody;
  final String Function(String name)? reactivateTitle;
  final String? reactivateBody;

  @override
  State<_AdminList> createState() => _AdminListState();
}

class _AdminListState extends State<_AdminList> {
  final _searchController = TextEditingController();
  late Future<List<_Row>> _future = widget.load(null);

  /// One request at a time. Set before the call and cleared after it, so a
  /// second tap while the first is in flight finds every action disabled.
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(() {
      // Block-bodied: an arrow here returns the assigned Future, which trips
      // `setState() callback argument returned a Future` in debug.
      _future = widget.load(_searchController.text);
    });
  }

  /// Suspends [row] after asking for a reason.
  ///
  /// The dialog refuses to submit a blank reason, so `REASON_REQUIRED` is a
  /// server guarantee the ordinary screen never provokes. Nothing is shown as
  /// succeeding until the RPC has returned.
  Future<void> _suspend(_Row row) async {
    final suspend = widget.suspend;
    if (suspend == null) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _SuspendDialog(
        title: widget.suspendTitle!(row.title),
        body: widget.suspendBody!,
      ),
    );
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      await suspend(row.id, reason);
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.adminSuspendedFeedback)));
      _search();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.genericError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reactivate(_Row row) async {
    final reactivate = widget.reactivate;
    if (reactivate == null) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.reactivateTitle!(row.title)),
        content: Text(widget.reactivateBody!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminReactivateButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await reactivate(row.id);
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.adminReactivatedFeedback)));
      _search();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.genericError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: l10n.adminSearchLabel,
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _search,
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<_Row>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingState();
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return ErrorState(onRetry: _search);
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return EmptyState(
                  icon: Icons.search_off,
                  message: l10n.adminEmpty,
                );
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) => _AdminTile(
                  row: rows[index],
                  busy: _busy,
                  onOpen: widget.open,
                  onSuspend: _suspend,
                  onReactivate: _reactivate,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One record: who it is, what state it is in, and the one thing to do about it.
class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.row,
    required this.busy,
    required this.onOpen,
    required this.onSuspend,
    required this.onReactivate,
  });

  final _Row row;
  final bool busy;

  /// Where this row goes, or null when it goes nowhere.
  final void Function(_Row row)? onOpen;

  final Future<void> Function(_Row row) onSuspend;
  final Future<void> Function(_Row row) onReactivate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final open = onOpen;

    return ListTile(
      // The row opens the record; the trailing button acts on it. A
      // [TextButton] consumes its own tap, so pressing Suspend does not also
      // push the detail screen underneath the dialog it opens.
      onTap: open == null ? null : () => open(row),
      title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // The state, said plainly, on every row that has one to say.
              if (row.action != AdminRowAction.none || row.isSystemAdmin)
                GoStatusChip(
                  label: row.isActive
                      ? l10n.adminStatusActive
                      : l10n.adminStatusSuspended,
                  tone: row.isActive ? GoChipTone.open : GoChipTone.danger,
                ),
              if (row.isSystemAdmin)
                GoStatusChip(
                  label: l10n.adminStatusSystemAdmin,
                  tone: GoChipTone.neutral,
                  icon: Icons.shield_outlined,
                ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: switch (row.action) {
        // A System Admin row, and every Matches row: nothing to press.
        AdminRowAction.none => null,
        AdminRowAction.suspend => TextButton(
            onPressed: busy ? null : () => onSuspend(row),
            child: Text(l10n.adminSuspendButton),
          ),
        AdminRowAction.reactivate => TextButton(
            onPressed: busy ? null : () => onReactivate(row),
            child: Text(l10n.adminReactivateButton),
          ),
      },
    );
  }
}

/// Asks for a reason, and will not return one that is blank.
///
/// Pops the trimmed reason on confirm and null on cancel, so the caller has one
/// thing to test. The database requires a reason for a real suspension; this is
/// what stops the ordinary path ever sending an empty one.
class _SuspendDialog extends StatefulWidget {
  const _SuspendDialog({required this.title, required this.body});

  final String title;
  final String body;

  @override
  State<_SuspendDialog> createState() => _SuspendDialogState();
}

class _SuspendDialogState extends State<_SuspendDialog> {
  final _controller = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: l10n.adminSuspensionReasonLabel,
              errorText: _showError ? l10n.adminSuspensionReasonRequired : null,
            ),
            onChanged: (_) {
              if (_showError) setState(() => _showError = false);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.confirmNo),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.adminSuspendButton),
        ),
      ],
    );
  }
}
