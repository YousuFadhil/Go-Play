import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import 'admin_repository.dart';

/// One line of an admin list, already worded. The three sections show
/// different records, so each is reduced to a title, a subtitle and the id to
/// delete — enough to find a record and remove it, which is all these screens
/// are for. Composing that sentence is the screen's job, not the repository's.
class _Row {
  const _Row({
    required this.id,
    required this.title,
    required this.subtitle,
    this.isProtected = false,
  });

  final String id;
  final String title;
  final String subtitle;

  /// A System Admin account, which the app may not delete.
  final bool isProtected;
}

/// Stands in for a name the record does not carry.
const _missing = '—';

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
        appBar: AppHeader(
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
              load: (search) async => [
                for (final user in await repository.listUsers(search))
                  _Row(
                    id: user.id,
                    title: user.fullName,
                    subtitle: user.email,
                    isProtected: user.isSystemAdmin,
                  ),
              ],
              remove: repository.deleteUser,
              confirmBody: l10n.adminDeleteUserConfirmBody,
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
                  ),
              ],
              remove: repository.deleteCommunity,
              confirmBody: l10n.adminDeleteCommunityConfirmBody,
            ),
            _AdminList(
              load: (search) async => [
                for (final match in await repository.listMatches(search))
                  _Row(
                    id: match.id,
                    title: match.title ?? '',
                    subtitle: '${match.communityName ?? _missing} · '
                        '${match.location} · ${match.registrationCount}',
                  ),
              ],
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

  final Future<List<_Row>> Function(String? search) load;
  final Future<void> Function(String id) remove;
  final String confirmBody;

  @override
  State<_AdminList> createState() => _AdminListState();
}

class _AdminListState extends State<_AdminList> {
  final _searchController = TextEditingController();
  late Future<List<_Row>> _future = widget.load(null);
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

  Future<void> _delete(_Row row) async {
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
