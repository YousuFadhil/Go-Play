import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../invitations/my_invitations_screen.dart';
import 'create_community_screen.dart';
import 'community_details_screen.dart';
import 'community_models.dart';
import 'group_service.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

typedef _CommunitiesOverview = ({List<Community> mine, List<Community> discover});

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final _groupService = GroupService();
  late Future<_CommunitiesOverview> _future;
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

  Future<void> _openCreateCommunity() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateCommunityScreen()),
    );
    if (created == true) _refresh();
  }

  /// Accepting an invitation adds a membership, so the list must reload.
  Future<void> _openInvitations() async {
    final joined = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MyInvitationsScreen()),
    );
    if (joined == true) _refresh();
  }

  Future<void> _openJoinDialog() async {
    // The dialog is fully self-contained (owns its controller and uses its
    // own context), so no parent BuildContext crosses into the dialog
    // subtree. It returns the joined community id, or null if cancelled.
    final joinedId = await showDialog<String>(
      context: context,
      builder: (_) => _JoinCommunityDialog(groupService: _groupService),
    );
    if (joinedId != null) _refresh();
  }

  /// Joins a discoverable public community directly, using its (readable) join
  /// code. Private communities never appear here, so they stay code-only.
  Future<void> _joinPublicCommunity(Community community) async {
    setState(() => _joiningId = community.id);
    try {
      await _groupService.joinGroupByCode(community.joinCode);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.joinedCommunity)));
      _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.communityJoinFailed)));
    } finally {
      if (mounted) setState(() => _joiningId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.communitiesTitle),
        actions: [
          IconButton(
            tooltip: l10n.myInvitationsTitle,
            icon: const Icon(Icons.mail_outline),
            onPressed: _openInvitations,
          ),
          IconButton(
            tooltip: l10n.joinCommunityTitle,
            icon: const Icon(Icons.key),
            onPressed: _openJoinDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.createCommunityTitle,
        onPressed: _openCreateCommunity,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<_CommunitiesOverview>(
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
                child: Text(l10n.communitiesEmpty, textAlign: TextAlign.center),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (mine.isNotEmpty) ...[
                  _SectionHeader(l10n.myCommunitiesSection),
                  for (final community in mine)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.groups)),
                      title: Text(community.name),
                      subtitle: community.description == null
                          ? null
                          : Text(
                              community.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: community.isPrivate
                          ? const Icon(Icons.lock_outline)
                          : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CommunityDetailsScreen(communityId: community.id),
                        ),
                      ),
                    ),
                ],
                if (discover.isNotEmpty) ...[
                  _SectionHeader(l10n.publicCommunitiesSection),
                  for (final community in discover)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.public)),
                      title: Text(community.name),
                      subtitle: community.description == null
                          ? null
                          : Text(
                              community.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      // Trailing must be width-bounded, otherwise the button
                      // consumes the whole tile and ListTile fails to lay out.
                      trailing: _joiningId == community.id
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
                                    : () => _joinPublicCommunity(community),
                                child: Text(l10n.joinCommunityButton),
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
/// the joined community id via [Navigator.pop], or null when dismissed.
class _JoinCommunityDialog extends StatefulWidget {
  const _JoinCommunityDialog({required this.groupService});

  final GroupService groupService;

  @override
  State<_JoinCommunityDialog> createState() => _JoinCommunityDialogState();
}

class _JoinCommunityDialogState extends State<_JoinCommunityDialog> {
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
      final communityId =
          await widget.groupService.joinGroupByCode(_controller.text);
      if (mounted) Navigator.of(context).pop(communityId);
    } on CommunityNotFoundException {
      _setError(l10n.communityNotFound);
    } on AlreadyMemberOfCommunityException {
      _setError(l10n.alreadyMemberOfCommunity);
    } catch (_) {
      _setError(l10n.communityJoinFailed);
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
      title: Text(l10n.joinCommunityTitle),
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
              : Text(l10n.joinCommunityButton),
        ),
      ],
    );
  }
}
