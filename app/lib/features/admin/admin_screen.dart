import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'admin_repository.dart';

/// The whole of internal administration: three lists, each with a search field
/// and a delete action. Deliberately plain — no dashboard, no counts worth
/// looking at, nothing to do but find a record and remove it.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final repository = AdminRepository();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.adminTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.adminUsersTab),
              Tab(text: l10n.adminCommunitiesTab),
              Tab(text: l10n.adminMatchesTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AdminList(
              load: repository.listUsers,
              remove: repository.deleteUser,
              confirmBody: l10n.adminDeleteUserConfirmBody,
            ),
            _AdminList(
              load: repository.listCommunities,
              remove: repository.deleteCommunity,
              confirmBody: l10n.adminDeleteCommunityConfirmBody,
            ),
            _AdminList(
              load: repository.listMatches,
              remove: repository.deleteMatch,
              confirmBody: l10n.adminDeleteMatchConfirmBody,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminList extends StatefulWidget {
  const _AdminList({
    required this.load,
    required this.remove,
    required this.confirmBody,
  });

  final Future<List<AdminRow>> Function(String? search) load;
  final Future<void> Function(String id) remove;
  final String confirmBody;

  @override
  State<_AdminList> createState() => _AdminListState();
}

class _AdminListState extends State<_AdminList> {
  final _searchController = TextEditingController();
  late Future<List<AdminRow>> _future = widget.load(null);
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(() => _future = widget.load(_searchController.text));
  }

  Future<void> _delete(AdminRow row) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminDeleteConfirmTitle(row.title)),
        content: Text(widget.confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminDeleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.remove(row.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.adminDeleted)));
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
          child: FutureBuilder<List<AdminRow>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Center(child: Text(l10n.loadFailed));
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return Center(child: Text(l10n.adminEmpty));
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return ListTile(
                    title: Text(row.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(row.subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      // A System Admin account cannot be removed from here;
                      // that lives outside the app, in SQL.
                      onPressed: _busy || row.isProtected
                          ? null
                          : () => _delete(row),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
