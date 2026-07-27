import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../communities/community_details_screen.dart';
import '../communities/community_errors.dart';
import '../communities/community_models.dart';
import '../communities/community_repository.dart';
import 'invite_link.dart';

/// Where an invitation lands. Shows which community is being offered before
/// anyone commits to it — which is why the preview works signed out — and then
/// joins and opens it.
///
/// Joining is all it does. Matches are browsed and registered for afterwards,
/// by the player themselves.
class InviteLandingScreen extends StatefulWidget {
  const InviteLandingScreen({super.key, required this.code});

  final String code;

  @override
  State<InviteLandingScreen> createState() => _InviteLandingScreenState();
}

class _InviteLandingScreenState extends State<InviteLandingScreen> {
  final _communities = CommunityRepository();
  final _authService = AuthService();
  late Future<CommunityInvitePreview> _previewFuture;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _previewFuture = _communities.previewInvite(widget.code);
  }

  void _reload() {
    setState(() {
      _previewFuture = _communities.previewInvite(widget.code);
    });
  }

  /// Signing in happens on top of this screen so the invitation survives it.
  Future<void> _signIn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (mounted && _authService.currentUserId != null) _reload();
  }

  Future<void> _join(CommunityInvitePreview preview) async {
    final l10n = context.l10n;
    // Clearing the pending invitation swaps this screen out from under us, so
    // both handles are taken while the context is still alive.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isJoining = true);
    try {
      final communityId = await _communities.joinCommunityByCode(widget.code);
      if (!mounted) return;

      PendingInvite.instance.clear();
      navigator.push(MaterialPageRoute(
        builder: (_) => CommunityDetailsScreen(communityId: communityId),
      ));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.joinedCommunity)),
      );
    } on AlreadyMemberOfCommunityException {
      // Already in: still the right destination, just a different sentence.
      if (!mounted) return;
      final id = preview.communityId;
      PendingInvite.instance.clear();
      if (id != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => CommunityDetailsScreen(communityId: id),
        ));
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.alreadyMemberOfCommunity)),
      );
    } on CommunityNotFoundException {
      _showError(l10n.inviteNotFound);
      _reload();
    } catch (_) {
      _showError(l10n.communityJoinFailed);
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isSignedIn = _authService.currentUserId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inviteTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.inviteTitle,
          // Dismissing the invitation is all that is needed: this screen is not
          // a pushed route, it is what the gate chose to show.
          onPressed: PendingInvite.instance.clear,
        ),
      ),
      body: FutureBuilder<CommunityInvitePreview>(
        future: _previewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.wifi_off,
              text: l10n.inviteLoadError,
              action: FilledButton(
                onPressed: _reload,
                child: Text(l10n.retryButton),
              ),
            );
          }

          final preview = snapshot.data!;
          if (!preview.isValid) {
            return _Message(icon: Icons.link_off, text: l10n.inviteNotFound);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.groups, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    preview.communityName ?? '',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (preview.isMember) ...[
                    const SizedBox(height: 16),
                    Text(l10n.inviteAlreadyMemberNote,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 32),
                  if (!isSignedIn) ...[
                    Text(l10n.inviteSignInFirst,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    onPressed: _isJoining
                        ? null
                        : (isSignedIn ? () => _join(preview) : _signIn),
                    child: _isJoining
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(preview.isMember
                            ? l10n.inviteOpenCommunity
                            : l10n.inviteJoinCommunity),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
