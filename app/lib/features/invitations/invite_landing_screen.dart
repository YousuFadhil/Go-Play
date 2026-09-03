import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/tokens.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../communities/community_details_screen.dart';
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
  const InviteLandingScreen({
    super.key,
    required this.code,
    this.communityRepository,
    this.authService,
  });

  final String code;

  /// Supplied only by tests; production retains the existing repositories.
  final CommunityRepository? communityRepository;
  final AuthService? authService;

  @override
  State<InviteLandingScreen> createState() => _InviteLandingScreenState();
}

class _InviteLandingScreenState extends State<InviteLandingScreen> {
  late final CommunityRepository _communities =
      widget.communityRepository ?? CommunityRepository();
  late final AuthService _authService = widget.authService ?? AuthService();
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
      final outcome = await _communities.joinCommunityByCode(widget.code);
      if (!mounted) return;

      switch (outcome) {
        case JoinedCommunity(:final communityId):
          PendingInvite.instance.clear();
          navigator.push(MaterialPageRoute(
            builder: (_) => CommunityDetailsScreen(communityId: communityId),
          ));
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.joinedCommunity)),
          );
        case AlreadyMember():
          // Already in: still the right destination, just a different
          // sentence. The id comes from the preview, since joining returned
          // none.
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
        case NeedsJoinCode():
          // Unreachable: the invitation carries the code.
          _showError(l10n.communityJoinFailed);
      }
    } on NotFoundFailure {
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

    return FutureBuilder<CommunityInvitePreview>(
        future: _previewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _stateScaffold(
              l10n,
              const Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return _stateScaffold(
              l10n,
              _Message(
                icon: Icons.wifi_off,
                text: l10n.inviteLoadError,
                action: FilledButton(
                  onPressed: _reload,
                  child: Text(l10n.retryButton),
                ),
              ),
            );
          }

          final preview = snapshot.data!;
          if (!preview.isValid) {
            return _stateScaffold(
              l10n,
              _Message(icon: Icons.link_off, text: l10n.inviteNotFound),
            );
          }

          return Scaffold(
            backgroundColor: GoColors.bgHero,
            body: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: ClubHero(
                    bar: ClubHeroBar(
                      title: l10n.inviteTitle,
                      onBack: PendingInvite.instance.clear,
                    ),
                    identity: Column(
                      children: [
                        CommunityCrest(
                          name: preview.communityName ?? '',
                          logoUrl: preview.communityLogoUrl,
                          size: 66,
                          onHero: true,
                        ),
                        const SizedBox(height: Gap.md),
                        Text(
                          preview.communityName ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ClubSheet(
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        Layout.sheetGutter - 4,
                        Gap.md,
                        Layout.sheetGutter - 4,
                        Gap.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (preview.isMember) ...[
                            Text(
                              l10n.inviteAlreadyMemberNote,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: Gap.md),
                          ],
                          if (!isSignedIn) ...[
                            Text(
                              l10n.inviteSignInFirst,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: Gap.md),
                          ],
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                Layout.buttonHeight,
                              ),
                            ),
                            onPressed: _isJoining
                                ? null
                                : (isSignedIn
                                    ? () => _join(preview)
                                    : _signIn),
                            child: _isJoining
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    preview.isMember
                                        ? l10n.inviteOpenCommunity
                                        : l10n.inviteJoinCommunity,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
    );
  }

  Widget _stateScaffold(AppLocalizations l10n, Widget body) => Scaffold(
        appBar: AppBar(
          title: Text(l10n.inviteTitle),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.inviteTitle,
            // Dismissing the invitation is all that is needed: this screen is
            // not a pushed route, it is what the gate chose to show.
            onPressed: PendingInvite.instance.clear,
          ),
        ),
        body: body,
      );
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
