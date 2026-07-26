import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../communities/community_details_screen.dart';
import '../communities/community_errors.dart';
import '../matches/match_details_screen.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import 'invitation_models.dart';
import 'invitation_repository.dart';
import 'invite_link.dart';

/// Where an invitation lands. Shows what is being offered before anyone commits
/// to it — which is why the preview works signed out — and then joins the
/// community and, for a Type B invitation, registers for the match.
///
/// Joining and registering are separate outcomes: a registration that fails
/// leaves the membership in place and says why.
class InviteLandingScreen extends StatefulWidget {
  const InviteLandingScreen({super.key, required this.token});

  final String token;

  @override
  State<InviteLandingScreen> createState() => _InviteLandingScreenState();
}

class _InviteLandingScreenState extends State<InviteLandingScreen> {
  final _invitations = InvitationRepository();
  final _authService = AuthService();
  late Future<InviteLinkPreview> _previewFuture;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _previewFuture = _invitations.previewInviteLink(widget.token);
  }

  void _reload() {
    setState(() {
      _previewFuture = _invitations.previewInviteLink(widget.token);
    });
  }

  /// Signing in happens on top of this screen so the invitation survives it.
  Future<void> _signIn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (mounted && _authService.currentUserId != null) _reload();
  }

  Future<void> _join(InviteLinkPreview preview) async {
    final l10n = context.l10n;
    // Clearing the pending invitation swaps this screen out from under us, so
    // both handles are taken while the context is still alive.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isJoining = true);
    try {
      final result = await _invitations.redeemInviteLink(widget.token);
      if (!mounted) return;
      final message = _outcomeMessage(l10n, preview, result);

      // Handing the invitation back leaves the app on its normal first screen,
      // and the destination is pushed on top of it so Back still works.
      PendingInvite.instance.clear();

      // A failed registration still leaves a member, so the community is the
      // honest destination; a successful one goes straight to the match.
      navigator.push(MaterialPageRoute(
        builder: (_) => result.joinedMatch && result.matchId != null
            ? MatchDetailsScreen(matchId: result.matchId!)
            : CommunityDetailsScreen(communityId: result.communityId),
      ));
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on CommunityActionException catch (e) {
      _showError(_actionErrorMessage(l10n, e.error));
      _reload();
    } catch (_) {
      _showError(l10n.inviteLoadError);
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  /// Redemption is idempotent, so someone who was already in says so rather
  /// than being congratulated on joining something they were already part of.
  String _outcomeMessage(
      AppLocalizations l10n, InviteLinkPreview preview, InviteRedemption result) {
    if (result.matchId == null) {
      return preview.isMember
          ? l10n.inviteAlreadyMemberNote
          : l10n.inviteJoinedCommunityOnly;
    }
    if (preview.isRegistered) return l10n.inviteAlreadyRegisteredNote;
    if (result.registrationStatus == RegistrationStatus.confirmed) {
      return l10n.inviteJoinedConfirmed;
    }
    if (result.registrationStatus == RegistrationStatus.reserve) {
      return l10n.inviteJoinedReserve;
    }
    final reason = result.registrationFailure;
    if (reason == null) return l10n.inviteJoinedButNotRegistered;
    return '${l10n.inviteJoinedButNotRegistered} '
        '${_registrationErrorMessage(l10n, reason)}';
  }

  String _registrationErrorMessage(
      AppLocalizations l10n, RegistrationError error) {
    return switch (error) {
      RegistrationError.overlappingMatch => l10n.errOverlappingMatch,
      RegistrationError.matchClosed => l10n.errMatchClosed,
      RegistrationError.alreadyRegistered => l10n.errAlreadyRegistered,
      RegistrationError.notRegistered => l10n.errNotRegistered,
      RegistrationError.registrationClosed => l10n.errRegistrationClosed,
      RegistrationError.matchLocked => l10n.errMatchLocked,
      RegistrationError.notCommunityMember => l10n.errNotCommunityMember,
    };
  }

  String _actionErrorMessage(
      AppLocalizations l10n, CommunityActionError error) {
    return switch (error) {
      CommunityActionError.inviteNotFound => l10n.inviteNotFound,
      CommunityActionError.inviteRevoked => l10n.inviteRevoked,
      CommunityActionError.inviteExpired => l10n.inviteExpired,
      CommunityActionError.inviteMatchDeleted => l10n.inviteMatchDeleted,
      _ => l10n.genericError,
    };
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
      body: FutureBuilder<InviteLinkPreview>(
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
          if (!preview.isUsable) {
            return _Message(
              icon: Icons.link_off,
              text: switch (preview.state) {
                InviteLinkState.revoked => l10n.inviteRevoked,
                InviteLinkState.expired => l10n.inviteExpired,
                InviteLinkState.matchDeleted => l10n.inviteMatchDeleted,
                _ => l10n.inviteNotFound,
              },
            );
          }
          return _InviteBody(
            preview: preview,
            isJoining: _isJoining,
            isSignedIn: _authService.currentUserId != null,
            onJoin: () => _join(preview),
            onSignIn: _signIn,
          );
        },
      ),
    );
  }
}

class _InviteBody extends StatelessWidget {
  const _InviteBody({
    required this.preview,
    required this.isJoining,
    required this.isSignedIn,
    required this.onJoin,
    required this.onSignIn,
  });

  final InviteLinkPreview preview;
  final bool isJoining;
  final bool isSignedIn;
  final VoidCallback onJoin;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.groups,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              preview.communityName ?? '',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            if (preview.hasMatch) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(preview.matchTitle ?? '',
                          style: theme.textTheme.titleMedium),
                      if (preview.matchLocation != null) ...[
                        const SizedBox(height: 8),
                        _Line(
                          icon: Icons.place_outlined,
                          text: preview.matchLocation!,
                        ),
                      ],
                      if (preview.matchStartAt != null) ...[
                        const SizedBox(height: 8),
                        _Line(
                          icon: Icons.event_outlined,
                          text: DateFormat.yMMMEd(locale)
                              .format(preview.matchStartAt!),
                        ),
                        const SizedBox(height: 8),
                        _Line(
                          icon: Icons.schedule_outlined,
                          text: formatTimeRange(
                            context,
                            preview.matchStartAt!,
                            preview.matchEndAt ?? preview.matchStartAt!,
                          ),
                        ),
                      ],
                      if (preview.seatsRemaining != null) ...[
                        const SizedBox(height: 8),
                        _Line(
                          icon: Icons.event_seat_outlined,
                          text: l10n
                              .inviteSeatsRemaining(preview.seatsRemaining!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Said before the button, not after: someone who taps expecting a
              // starting place and lands on the reserve list was misled.
              if (preview.wouldBeReserve) ...[
                const SizedBox(height: 12),
                _Note(text: l10n.inviteWouldBeReserve),
              ],
            ],
            if (preview.isMember) ...[
              const SizedBox(height: 12),
              _Note(text: l10n.inviteAlreadyMemberNote),
            ],
            if (preview.isRegistered) ...[
              const SizedBox(height: 12),
              _Note(text: l10n.inviteAlreadyRegisteredNote),
            ],
            const SizedBox(height: 32),
            if (!isSignedIn) ...[
              Text(l10n.inviteSignInFirst,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: isJoining ? null : (isSignedIn ? onJoin : onSignIn),
              child: isJoining
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(preview.hasMatch
                      ? l10n.inviteJoinAndRegister
                      : l10n.inviteJoinCommunity),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
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
            Icon(icon,
                size: 48, color: Theme.of(context).colorScheme.outline),
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
