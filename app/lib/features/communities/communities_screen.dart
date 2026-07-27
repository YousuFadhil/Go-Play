import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'create_community_screen.dart';
import 'community_details_screen.dart';
import 'community_models.dart';
import '../invitations/invite_link.dart';
import 'community_errors.dart';
import 'community_repository.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

typedef _CommunitiesOverview = ({
  List<Community> mine,
  List<Community> discover
});

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final _communityRepository = CommunityRepository();
  late Future<_CommunitiesOverview> _future;
  String? _joiningId;

  @override
  void initState() {
    super.initState();
    _future = _communityRepository.fetchCommunitiesOverview();
  }

  void _refresh() {
    setState(() {
      _future = _communityRepository.fetchCommunitiesOverview();
    });
  }

  Future<void> _openCreateCommunity() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateCommunityScreen()),
    );
    if (created == true) _refresh();
  }

  /// Accepting an invitation adds a membership, so the list must reload.
  /// Fallback for an invitation that arrived as text rather than as a tap —
  /// some messaging apps will not make a `goplay://` link tappable. Handing the
  /// token to PendingInvite routes it exactly like a tapped link would.
  Future<void> _openInviteDialog() async {
    final token = await showDialog<String>(
      context: context,
      builder: (_) => const _OpenInviteDialog(),
    );
    if (token != null) PendingInvite.instance.offer(token);
  }

  Future<void> _openJoinDialog() async {
    // The dialog is fully self-contained (owns its controller and uses its
    // own context), so no parent BuildContext crosses into the dialog
    // subtree. It returns the joined community id, or null if cancelled.
    final joinedId = await showDialog<String>(
      context: context,
      builder: (_) => _JoinCommunityDialog(repository: _communityRepository),
    );
    if (joinedId != null) _refresh();
  }

  /// Every community is listed, so Join means two different things: an OPEN
  /// community joins outright, and a CODE_REQUIRED one asks for its code first.
  /// The server decides either way — this only picks which question to ask.
  Future<void> _join(Community community) async {
    final l10n = context.l10n;
    if (community.joinPolicy == JoinPolicy.codeRequired) {
      final joinedId = await showDialog<String>(
        context: context,
        builder: (_) => _JoinCommunityDialog(
          repository: _communityRepository,
          prompt: l10n.joinCodeRequiredPrompt,
        ),
      );
      if (joinedId != null) _refresh();
      return;
    }

    setState(() => _joiningId = community.id);
    try {
      await _communityRepository.joinCommunity(community.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.joinedCommunity)));
      _refresh();
    } on JoinCodeRequiredException {
      // The policy changed under us; ask for the code rather than fail.
      if (!mounted) return;
      setState(() => _joiningId = null);
      final joinedId = await showDialog<String>(
        context: context,
        builder: (_) => _JoinCommunityDialog(
          repository: _communityRepository,
          prompt: l10n.joinCodeRequiredPrompt,
        ),
      );
      if (joinedId != null) _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.communityJoinFailed)));
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
            tooltip: l10n.inviteOpenAction,
            icon: const Icon(Icons.link),
            onPressed: _openInviteDialog,
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
                      trailing:
                          community.joinPolicy == JoinPolicy.codeRequired
                              ? const Icon(Icons.password)
                              : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CommunityDetailsScreen(communityId: community.id),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : SizedBox(
                              width: 96,
                              child: FilledButton.tonal(
                                onPressed: _joiningId != null
                                    ? null
                                    : () => _join(community),
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
  const _JoinCommunityDialog({required this.repository, this.prompt});

  final CommunityRepository repository;

  /// Shown above the field when the dialog was opened because a community's
  /// policy requires the code, rather than from the generic join action.
  final String? prompt;

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
          await widget.repository.joinCommunityByCode(_controller.text);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.prompt != null) ...[
              Text(widget.prompt!),
              const SizedBox(height: 12),
            ],
            TextFormField(
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
          ],
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

/// Takes a pasted invitation link (or the bare token inside one) and returns
/// the token. Validation is local and deliberately shallow: whether the
/// invitation is still good is the landing screen's question to ask.
class _OpenInviteDialog extends StatefulWidget {
  const _OpenInviteDialog();

  @override
  State<_OpenInviteDialog> createState() => _OpenInviteDialogState();
}

class _OpenInviteDialogState extends State<_OpenInviteDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final token = InviteLink.parse(_controller.text);
    if (token == null) {
      setState(() => _errorText = context.l10n.inviteInvalidInput);
      return;
    }
    Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.inviteOpenAction),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: l10n.invitePasteHint,
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.inviteOpenAction),
        ),
      ],
    );
  }
}
