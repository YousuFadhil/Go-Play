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

class _GroupsScreenState extends State<GroupsScreen> {
  final _groupService = GroupService();
  late Future<List<Group>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _groupService.fetchMyGroups();
  }

  void _refresh() {
    setState(() {
      _groupsFuture = _groupService.fetchMyGroups();
    });
  }

  Future<void> _openCreateGroup() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    if (created == true) _refresh();
  }

  Future<void> _openJoinDialog() async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final joined = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        bool isLoading = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() => isLoading = true);
              try {
                await _groupService.joinGroupByCode(controller.text);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } on GroupNotFoundException {
                _showSnack(l10n.groupNotFound);
              } on AlreadyMemberException {
                _showSnack(l10n.alreadyMember);
              } catch (_) {
                _showSnack(l10n.groupJoinFailed);
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => isLoading = false);
                }
              }
            }

            return AlertDialog(
              title: Text(l10n.joinGroupTitle),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: l10n.joinCodeLabel),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l10n.joinCodeRequired
                      : null,
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: isLoading ? null : submit,
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.joinGroupButton),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    if (joined == true) _refresh();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
      body: FutureBuilder<List<Group>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorRetry(onRetry: _refresh);
          }

          final groups = snapshot.data ?? const [];
          if (groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.groupsEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.groups)),
                  title: Text(group.name),
                  subtitle: group.description == null
                      ? null
                      : Text(
                          group.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing:
                      group.isPrivate ? const Icon(Icons.lock_outline) : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupDetailsScreen(groupId: group.id),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
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
