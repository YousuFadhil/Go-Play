import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import 'auth_service.dart';

/// What a suspended account sees instead of the product.
///
/// Deliberately the smallest screen in the app: what has happened, that nothing
/// has been lost, and the one action still available. There is no appeal form,
/// no support ticket and no contact channel, because none of those exists yet
/// and offering one would promise a reply nobody is going to send.
///
/// **The suspension reason is not shown.** The approved self-profile contract
/// (`my_profile`, migration `0063`) does not return it, and reading it would
/// mean widening a read path this cycle is not allowed to touch.
///
/// Signing out goes through the ordinary [AuthService.logout]; the account is
/// not signed out automatically, because being suspended is not the same as
/// being logged out and the reader should decide when to leave.
class AccountSuspendedScreen extends StatefulWidget {
  const AccountSuspendedScreen({super.key, AuthService? authService})
      : _authService = authService;

  final AuthService? _authService;

  @override
  State<AccountSuspendedScreen> createState() => _AccountSuspendedScreenState();
}

class _AccountSuspendedScreenState extends State<AccountSuspendedScreen> {
  late final AuthService _authService = widget._authService ?? AuthService();
  bool _busy = false;

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _authService.logout();
      // No navigation here: the auth gate is listening to the session and
      // moves the app on its own once there is no longer one.
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: GoColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pause_circle_outline,
                    size: 56, color: GoColors.onSurfaceVariant),
                const SizedBox(height: 20),
                Text(
                  l10n.accountSuspendedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.accountSuspendedBody,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: GoColors.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _signOut,
                  child: Text(l10n.accountSuspendedSignOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the account's state could not be established at all.
///
/// It fails closed on purpose: an unanswered question is not permission to
/// enter the app, so this offers a retry rather than falling through to Home.
class AccountStatusUnavailableScreen extends StatelessWidget {
  const AccountStatusUnavailableScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: GoColors.surface,
      body: SafeArea(
        child: ErrorState(
          message: l10n.accountStatusUnavailable,
          onRetry: onRetry,
        ),
      ),
    );
  }
}
