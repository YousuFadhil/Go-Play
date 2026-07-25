import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'create_group_screen.dart';
import 'group_details_screen.dart';
import 'group_models.dart';
import 'group_service.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

typedef _GroupsOverview = ({List<Community> mine, List<Community> discover});

class _GroupsScreenState extends State<GroupsScreen> {
  final _groupService = GroupService();
  late Future<_GroupsOverview> _future;
  String? _joiningId;

  @override
  void initState() {
    super.initState();
    _future = _groupService.fetchGroupsOverview();
  }

  void _refresh() {
    setState(() {
      _future = _groupService.fetchGroupsOverview();
    });
  }

  Future<void> _openCreateGroup() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    if (created == true) _refresh();
  }

  Future<void> _openJoinDialog() async {
    // The dialog is fully self-contained (owns its controller and uses its
    // own context), so no parent BuildContext crosses into the dialog
    // subtree. It returns the joined group id, or null if cancelled.
    final joinedId = await showDialog<String>(
      context: context,
      builder: (_) => _JoinGroupDialog(groupService: _groupService),
    );
    if (joinedId != null) _refresh();
  }

  /// Joins a discoverable public group directly, using its (readable) join
  /// code. Private groups never appear here, so they stay code-only.
  Future<void> _joinPublicGroup(Community group) async {
    setState(() => _joiningId = group.id);
    try {
      await _groupService.joinGroupByCode(group.joinCode);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.joinedGroup)));
      _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.groupJoinFailed)));
    } finally {
      if (mounted) setState(() => _joiningId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.groupsTitle),
        actions: [
          IconButton(
            tooltip: l10n.joinGroupTitle,
            icon: const Icon(Icons.key),
            onPressed: _openJoinDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.createGroupTitle,
        onPressed: _openCreateGroup,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<_GroupsOverview>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorRetry(onRetry: _refresh);
          }

          final mine = snapshot.data?.mine ?? const [];
          final discover = snapshot.data?.discover ?? const [];

          if (mine.isEmpty && discover.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.groupsEmpty, textAlign: TextAlign.center),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (mine.isNotEmpty) ...[
                  _SectionHeader(l10n.myGroupsSection),
                  for (final group in mine)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.groups)),
                      title: Text(group.name),
                      subtitle: group.description == null
                          ? null
                          : Text(
                              group.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: group.isPrivate
                          ? const Icon(Icons.lock_outline)
                          : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GroupDetailsScreen(groupId: group.id),
                        ),
                      ),
                    ),
                ],
                if (discover.isNotEmpty) ...[
                  _SectionHeader(l10n.publicGroupsSection),
                  for (final group in discover)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.public)),
                      title: Text(group.name),
                      subtitle: group.description == null
                          ? null
                          : Text(
                              group.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      // Trailing must be width-bounded, otherwise the button
                      // consumes the whole tile and ListTile fails to lay out.
                      trailing: _joiningId == group.id
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : SizedBox(
                              width: 96,
                              child: FilledButton.tonal(
                                onPressed: _joiningId != null
                                    ? null
                                    : () => _joinPublicGroup(group),
                                child: Text(l10n.joinGroupButton),
                              ),
                            ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.loadFailed),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.retryButton)),
        ],
      ),
    );
  }
}

/// Self-contained "join by code" dialog. It owns its text controller and
/// resolves all inherited widgets (l10n, messenger) through its own context,
/// so nothing from the parent screen leaks into the dialog subtree. Returns
/// the joined group id via [Navigator.pop], or null when dismissed.
class _JoinGroupDialog extends StatefulWidget {
  const _JoinGroupDialog({required this.groupService});

  final GroupService groupService;

  @override
  State<_JoinGroupDialog> createState() => _JoinGroupDialogState();
}

class _JoinGroupDialogState extends State<_JoinGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final groupId =
          await widget.groupService.joinGroupByCode(_controller.text);
      if (mounted) Navigator.of(context).pop(groupId);
    } on GroupNotFoundException {
      _setError(l10n.groupNotFound);
    } on AlreadyMemberException {
      _setError(l10n.alreadyMember);
    } catch (_) {
      _setError(l10n.groupJoinFailed);
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorText = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.joinGroupTitle),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: l10n.joinCodeLabel,
            errorText: _errorText,
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? l10n.joinCodeRequired
              : null,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.joinGroupButton),
        ),
      ],
    );
  }
}
