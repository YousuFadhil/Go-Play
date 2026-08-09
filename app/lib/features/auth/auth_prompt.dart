import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import 'auth_service.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// The gate between browsing and doing.
///
/// A guest may look at everything and change nothing, so the question "may this
/// happen?" is asked in exactly one place rather than at each of the five
/// actions that have to ask it: joining a community, registering for a match,
/// creating either, and opening a profile.
///
/// [reason] is the sentence explaining why the sheet appeared. It is required
/// because "you need an account" on its own tells a visitor nothing about what
/// they were in the middle of, and the caller is the only one that knows.
///
/// [authService] is supplied only by tests, exactly as the repositories take an
/// optional port. Left null the production one is built, so nothing that calls
/// this has to know what a session is made of.
///
/// Returns true when the caller may proceed. In practice a successful sign-in
/// rarely returns to the caller at all: both auth screens unwind to the root
/// route, and the auth gate then replaces the public tree with the signed-in
/// one. Callers must therefore check `mounted` before touching their own
/// context afterwards, exactly as they would after any other await across a
/// navigation.
Future<bool> requireSignIn(
  BuildContext context, {
  required String reason,
  AuthService? authService,
}) async {
  final auth = authService ?? AuthService();
  if (auth.isSignedIn) return true;

  final choice = await showModalBottomSheet<_AuthChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _SignInPrompt(reason: reason),
  );
  if (choice == null || !context.mounted) return false;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => switch (choice) {
        _AuthChoice.register => RegisterScreen(authService: authService),
        _AuthChoice.login => LoginScreen(authService: authService),
      },
    ),
  );

  return auth.isSignedIn;
}

enum _AuthChoice { register, login }

/// Creating an account is offered first and as the filled button.
///
/// Somebody who reached this sheet was browsing without a session, which makes
/// "new here" the likelier of the two — and the sprint's whole point is that the
/// app asks for an account when there is finally something to gain by having
/// one, rather than at the door.
class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xs, Gap.xl, Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.authRequiredTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              reason,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gap.xl),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_AuthChoice.register),
              child: Text(l10n.registerButton),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(_AuthChoice.login),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(kButtonHeight),
              ),
              child: Text(l10n.loginButton),
            ),
          ],
        ),
      ),
    );
  }
}
