import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import 'auth_service.dart';

/// What registration shows when the account exists but nobody is signed in,
/// because the provider is waiting for the address to be confirmed.
///
/// A body, not a screen: [RegisterScreen] swaps it in for the form so the person
/// stays on the route they were on and Back keeps meaning what it meant.
///
/// It says where the email went and how to carry on, and offers to send it
/// again. **It does not pretend the person is signed in** — there is no session,
/// the gate has not moved, and the only way forward is the link in the email and
/// then the ordinary login.
///
/// Resending is held back for a minute, at the start and after every send. The
/// provider allows about one email a minute and refuses the rest, so a button
/// that could be pressed at once would mostly produce a failure; the wait is the
/// provider's own limit shown as a disabled button instead of an error.
class CheckEmailView extends StatefulWidget {
  const CheckEmailView({
    super.key,
    required this.email,
    required this.authService,
    this.resendDelay = const Duration(seconds: 60),
  });

  final String email;
  final AuthService authService;

  /// How long resending stays disabled. A parameter so a test does not have to
  /// wait a real minute; production uses the default.
  final Duration resendDelay;

  @override
  State<CheckEmailView> createState() => _CheckEmailViewState();
}

class _CheckEmailViewState extends State<CheckEmailView> {
  Timer? _cooldown;
  bool _canResend = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown?.cancel();
    _canResend = false;
    _cooldown = Timer(widget.resendDelay, () {
      if (mounted) setState(() => _canResend = true);
    });
  }

  Future<void> _resend() async {
    final l10n = context.l10n;
    setState(() => _sending = true);
    try {
      await widget.authService.resendConfirmation(widget.email);
      _showMessage(l10n.checkEmailResent);
      if (mounted) setState(_startCooldown);
    } on Failure catch (failure) {
      _showMessage(switch (failure) {
        NetworkFailure() => l10n.networkError,
        InfrastructureFailure(reason: FailureReason.tooManyRequests) =>
          l10n.tooManyRequests,
        _ => l10n.genericError,
      });
      // The provider has just told us to slow down (or nothing was sent), so the
      // button waits again rather than inviting an immediate second attempt.
      if (mounted) setState(_startCooldown);
    } catch (_) {
      _showMessage(l10n.genericError);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMessage(String message) {
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
        Center(
          child: Container(
            padding: const EdgeInsets.all(Gap.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_email_unread_outlined,
              size: 32,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text(
          l10n.checkEmailTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: Gap.md),
        Text(
          l10n.checkEmailBody(widget.email),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: Gap.xl),
        OutlinedButton(
          onPressed: _canResend && !_sending ? _resend : null,
          child: _sending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.checkEmailResend),
        ),
        if (!_canResend) ...[
          const SizedBox(height: Gap.sm),
          Text(
            l10n.checkEmailResendWait,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: Gap.md),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.backToLogin),
        ),
      ],
    );
  }
}
