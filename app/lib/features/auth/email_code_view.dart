import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import 'auth_service.dart';

/// What the code being asked for is for.
enum EmailCodePurpose {
  /// The code from a password-recovery email. Verifying it opens a recovery
  /// session; the auth gate takes the person from there to the reset screen.
  recovery,

  /// The code that completes a sign-up. Verifying it signs the new account in.
  signup,
}

/// Asking for the six-digit code an email carries, for either purpose.
///
/// A body, not a screen: the screen that asked for the email swaps it in for its
/// own form, so the person stays on the route they were on and Back keeps
/// meaning what it meant.
///
/// **What it does on success is nothing, on purpose.** The gate reacts to the
/// session it creates -- to the reset screen for a recovery, through the account
/// check for a sign-up -- and unwinds whatever was pushed. [onVerified] exists
/// only for what the *caller* knows and the gate does not.
///
/// **Recovery never echoes the address.** The request that led here is one anybody
/// can make for any address, and its answer must not depend on it; so the
/// recovery variant says nothing about which address it was for, and a code that
/// is wrong reads exactly like a code for an address that has no account. The
/// sign-up variant shows it -- it is the person's own new account, and a typo in
/// the address is the commonest reason a code never arrives.
///
/// The code is held in the text field and handed to the service, and that is all:
/// it is never stored, never logged, and never part of an error message.
///
/// Sending another is held back for a minute, at the start and after every send.
/// The provider allows about one email an address a minute and refuses the rest,
/// so a button that could be pressed at once would mostly produce a failure; the
/// wait is the provider's own limit shown as a disabled button. It is a
/// convenience, not a guard: whether a request is allowed is the provider's
/// decision, and a refusal is worded as one.
class EmailCodeView extends StatefulWidget {
  const EmailCodeView({
    super.key,
    required this.purpose,
    required this.email,
    required this.authService,
    this.onVerified,
    this.resendDelay = const Duration(seconds: 60),
  });

  final EmailCodePurpose purpose;

  /// The address the email went to, as it was asked for.
  final String email;

  final AuthService authService;

  /// Called after the code was accepted, for what only the caller knows. The
  /// session already exists by then and the gate is already reacting to it.
  final VoidCallback? onVerified;

  /// How long sending another stays disabled. A parameter so a test does not
  /// have to wait a real minute; production uses the default.
  final Duration resendDelay;

  @override
  State<EmailCodeView> createState() => _EmailCodeViewState();
}

class _EmailCodeViewState extends State<EmailCodeView> {
  final _codeController = TextEditingController();
  Timer? _cooldown;
  bool _canResend = false;
  bool _verifying = false;
  bool _sending = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown?.cancel();
    _canResend = false;
    _cooldown = Timer(widget.resendDelay, () {
      if (mounted) setState(() => _canResend = true);
    });
  }

  Future<void> _verify() async {
    final l10n = context.l10n;
    final code = _codeController.text;
    if (!AuthService.isValidEmailCode(code)) {
      setState(() => _codeError = l10n.emailCodeIncomplete);
      return;
    }

    setState(() {
      _verifying = true;
      _codeError = null;
    });
    try {
      switch (widget.purpose) {
        case EmailCodePurpose.recovery:
          await widget.authService
              .verifyRecoveryCode(email: widget.email, code: code);
        case EmailCodePurpose.signup:
          await widget.authService
              .verifySignupCode(email: widget.email, code: code);
      }
      widget.onVerified?.call();
    } on Failure catch (failure) {
      switch (failure) {
        // Wrong, expired, used, or for an address nobody registered: one
        // answer, because the provider gives one.
        case AuthenticationFailure(reason: FailureReason.invalidEmailCode):
          if (mounted) setState(() => _codeError = l10n.emailCodeInvalid);
        case ValidationFailure():
          if (mounted) setState(() => _codeError = l10n.emailCodeIncomplete);
        case NetworkFailure():
          _showMessage(l10n.networkError);
        case InfrastructureFailure(reason: FailureReason.tooManyRequests):
          _showMessage(l10n.tooManyRequests);
        default:
          _showMessage(l10n.genericError);
      }
    } catch (_) {
      _showMessage(l10n.genericError);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    final l10n = context.l10n;
    setState(() => _sending = true);
    try {
      switch (widget.purpose) {
        // Asking again is the same neutral request as the first one.
        case EmailCodePurpose.recovery:
          await widget.authService.requestPasswordReset(widget.email);
        case EmailCodePurpose.signup:
          await widget.authService.resendConfirmation(widget.email);
      }
      _showMessage(l10n.emailCodeResent);
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
    final busy = _verifying || _sending;

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
          l10n.emailCodeTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: Gap.md),
        Text(
          switch (widget.purpose) {
            EmailCodePurpose.recovery => l10n.emailCodeRecoveryBody,
            EmailCodePurpose.signup => l10n.emailCodeSignupBody,
          },
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (widget.purpose == EmailCodePurpose.signup) ...[
          const SizedBox(height: Gap.sm),
          Text(
            l10n.emailCodeSentTo(widget.email),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: Gap.xl),
        TextField(
          controller: _codeController,
          autofocus: true,
          // Read-only rather than disabled while checking, so the keyboard stays
          // up for the person who typed a digit wrong.
          readOnly: _verifying,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.oneTimeCode],
          // A code is not text to be corrected, completed or remembered.
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [_EmailCodeFormatter()],
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: InputDecoration(
            labelText: l10n.emailCodeLabel,
            errorText: _codeError,
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            if (_codeError != null) setState(() => _codeError = null);
          },
          onSubmitted: (_) {
            if (!busy) _verify();
          },
        ),
        const SizedBox(height: Gap.lg),
        FilledButton(
          onPressed: busy ? null : _verify,
          child: _verifying
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.emailCodeVerify),
        ),
        const SizedBox(height: Gap.md),
        OutlinedButton(
          onPressed: _canResend && !busy ? _resend : null,
          child: _sending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.emailCodeResend),
        ),
        if (!_canResend) ...[
          const SizedBox(height: Gap.sm),
          Text(
            l10n.emailCodeResendWait,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: Gap.md),
        TextButton(
          onPressed: _verifying ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.backToLogin),
        ),
      ],
    );
  }
}

/// Keeps a code field to at most six digits, and to the digits the provider
/// expects: an Arabic keyboard's digits are converted, and a space or dash pasted
/// from an email is dropped, instead of being refused.
class _EmailCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = AuthService.normalizeEmailCode(newValue.text);
    if (digits.length > AuthService.emailCodeLength) {
      digits = digits.substring(0, AuthService.emailCodeLength);
    }
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
