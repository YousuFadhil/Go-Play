import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import 'auth_service.dart';

/// "Continue with Google", and the "or" that sets it apart from the form above.
///
/// One action for both people who arrive here: somebody whose Google address
/// matches an account they already have, who is signed in to it, and somebody
/// new, who is signed in and then asked for the player profile Google cannot
/// give. Which of the two it is is decided after the redirect returns, by the
/// account itself, so this button neither asks nor needs to know.
///
/// It asks [AuthService] and nothing else. The provider's own redirect flow does
/// the rest; when it comes back the session changes and the auth gate moves the
/// app on, exactly as it does for a password sign-in.
class GoogleSignInSection extends StatefulWidget {
  const GoogleSignInSection({
    super.key,
    this.authService,
    this.enabled = true,
  });

  /// Supplied only by tests, as the screens that hold this take one. Left null
  /// the production service is built when the button is *tapped*, not when it is
  /// drawn: drawing a login form must not need a data provider to exist.
  final AuthService? authService;

  /// False while the form above is busy, so two sign-ins cannot start at once.
  final bool enabled;

  @override
  State<GoogleSignInSection> createState() => _GoogleSignInSectionState();
}

class _GoogleSignInSectionState extends State<GoogleSignInSection> {
  bool _busy = false;

  Future<void> _start() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await (widget.authService ?? AuthService()).signInWithGoogle();
    } on Failure catch (failure) {
      _showError(switch (failure) {
        NetworkFailure() => l10n.networkError,
        _ => l10n.googleSignInFailed,
      });
    } catch (_) {
      _showError(l10n.googleSignInFailed);
    } finally {
      // On Android the browser is now in front and this screen is still here
      // when the person comes back. On the web the page has already navigated
      // away and this never runs.
      if (mounted) setState(() => _busy = false);
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Text(
                l10n.authOrDivider,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: Gap.md),
        OutlinedButton.icon(
          onPressed: widget.enabled && !_busy ? _start : null,
          icon: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.g_mobiledata, size: 28),
          label: Text(l10n.continueWithGoogle),
        ),
      ],
    );
  }
}
