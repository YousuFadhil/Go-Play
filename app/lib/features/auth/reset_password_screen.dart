import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import 'auth_service.dart';

/// Choosing a new password after following a recovery link.
///
/// Shown by the auth gate, not pushed: the session a recovery link creates looks
/// like any other sign-in, so this screen outranks the product for as long as
/// that session is the recovery one. Nothing behind it is reachable, and there
/// is no back button — the two ways out are finishing and cancelling, and both
/// end the session.
///
/// **Finishing signs the person out.** A recovery link proves control of an
/// inbox; it does not prove a product session is wanted. So the password is
/// changed, the session ends, and [onCompleted] returns the person to the
/// ordinary login flow to sign in with what they just chose.
///
/// The password rule is the one every other screen holds
/// ([AuthService.minimumPasswordLength]); it is not restated here.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.authService,
    required this.onCompleted,
    required this.onCancelled,
  });

  final AuthService authService;

  /// The password was changed and the recovery session is over.
  final VoidCallback onCompleted;

  /// The person left without changing it. The recovery session has been ended.
  final VoidCallback onCancelled;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = context.l10n;
    setState(() => _isLoading = true);
    try {
      await widget.authService.completePasswordRecovery(_passwordController.text);
      widget.onCompleted();
    } on Failure catch (failure) {
      _showError(switch (failure) {
        NetworkFailure() => l10n.networkError,
        ValidationFailure() => l10n.passwordTooShort,
        // The recovery session is gone or was never valid: an expired or
        // already-used link. Nothing typed here can fix that.
        AuthenticationFailure() => l10n.resetPasswordLinkExpired,
        _ => l10n.genericError,
      });
    } catch (_) {
      _showError(l10n.genericError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Leaves without changing anything. The session goes with it: a recovery
  /// session that outlived the screen would be a signed-in product session
  /// nobody chose.
  Future<void> _cancel() async {
    setState(() => _isLoading = true);
    try {
      await widget.authService.logout();
    } catch (_) {
      // The provider clears its own copy of the session before it tells the
      // server, so a failure here still leaves nobody signed in locally.
    }
    widget.onCancelled();
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

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.resetPasswordTitle),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.xl),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.xl),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(Gap.lg),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_reset,
                        size: 32,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.xl),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l10n.newPasswordLabel),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.passwordRequired;
                      }
                      if (!AuthService.isValidPassword(value)) {
                        return l10n.passwordTooShort;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: Gap.md),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: true,
                    decoration:
                        InputDecoration(labelText: l10n.confirmPasswordLabel),
                    validator: (value) => value != _passwordController.text
                        ? l10n.passwordsDoNotMatch
                        : null,
                  ),
                  const SizedBox(height: Gap.xl),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.resetPasswordSubmit),
                  ),
                  const SizedBox(height: Gap.sm),
                  TextButton(
                    onPressed: _isLoading ? null : _cancel,
                    child: Text(l10n.cancelButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
