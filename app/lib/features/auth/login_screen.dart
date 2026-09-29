import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import 'auth_service.dart';
import 'email_code_view.dart';
import 'forgot_password_screen.dart';
import 'google_sign_in_button.dart';
import 'register_screen.dart';

/// Signing in.
///
/// No longer the app's home screen — a visitor lands on Discover and arrives
/// here by asking to, or by trying something that needs an account. The
/// behaviour is deliberately untouched by that move: the same fields, the same
/// validation, the same failures, and the same unwind to the root route on
/// success, which the auth gate then answers by swapping the public tree for the
/// signed-in one.
///
/// **One thing it now does that it did not:** when the provider refuses a
/// password sign-in *because the address has not been verified yet* -- a person
/// who registered, never entered the emailed code, and came back later -- it does
/// not say "login failed". It swaps the form for the same six-digit code screen
/// registration shows, for the address that was typed, so they can finish without
/// registering again. That happens only on the provider's own
/// `email_not_confirmed`, which it raises after checking the password: a wrong
/// password or an address nobody registered gets the ordinary failure, and there
/// is no way to reach the code screen from an address alone.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.authService,
    this.passwordResetSucceeded = false,
  });

  /// True when the person has just finished choosing a new password and been
  /// sent here to use it. Shows the confirmation the reset screen cannot: that
  /// screen is gone by the time this one is on top.
  final bool passwordResetSucceeded;

  /// Supplied only by tests, as the registration screen already takes one. Left
  /// null the screen builds the production service, so nothing here knows what
  /// a data provider is.
  final AuthService? authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AuthService _authService = widget.authService ?? AuthService();
  bool _isLoading = false;

  /// Set when the provider said this address is not verified yet. While it is
  /// set the form is replaced by the code screen. It is the address and nothing
  /// else: the password is cleared the moment this is set and is never kept.
  String? _unverifiedEmail;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = context.l10n;
    setState(() => _isLoading = true);
    try {
      await _authService.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
      // AuthGate reacts to the auth state change. The pop matters only when
      // this screen was pushed on top of something — signing in from an
      // invitation — where it has to get out of the way again.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on Failure catch (failure) {
      // Right password, unverified address: carry on where registration left off.
      if (failure is AuthenticationFailure &&
          failure.reason == FailureReason.emailNotConfirmed) {
        // The password has done its job. It is not held for the verification and
        // is not there to be sent again; going back asks for it afresh.
        _passwordController.clear();
        if (mounted) {
          setState(() => _unverifiedEmail = _emailController.text.trim());
        }
        return;
      }
      _showError(switch (failure) {
        NetworkFailure() => l10n.networkError,
        AuthenticationFailure() => l10n.loginFailed,
        _ => l10n.genericError,
      });
    } catch (_) {
      _showError(l10n.genericError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Back from the code screen is the ordinary form, not out of the login screen.
  void _backToLogin() {
    if (mounted) setState(() => _unverifiedEmail = null);
  }

  /// The code was accepted: the account is confirmed and signed in, and the gate
  /// is already on its way to the account check. Like a password sign-in, this
  /// only has to get out of the way if it was pushed over something. Nothing is
  /// counted as a registration: the account was created in an earlier visit, and
  /// a login never counts as a signup.
  void _onEmailVerified() {
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final unverified = _unverifiedEmail;
    if (unverified != null) {
      return PopScope(
        // The app bar's back arrow and the system back both mean "back to the
        // form" here, not "leave the login screen".
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _backToLogin();
        },
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.loginTitle)),
          body: SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.xl),
              child: EmailCodeView(
                purpose: EmailCodePurpose.signup,
                email: unverified,
                authService: _authService,
                onVerified: _onEmailVerified,
                onBack: _backToLogin,
                canResendAtStart: true,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginTitle)),
      // Top-aligned, not centred. Centring a short form on a tall phone banks
      // a screen's worth of empty space above it and leaves the fields floating
      // with nothing to sit under — which is exactly the space Priority 1 asks
      // to be given back.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.xl),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.xxl),
                // The same mark the banner carries, so arriving here from
                // Discover does not feel like leaving the product. It also
                // gives the form something to sit under: the fields used to
                // float in the middle of an empty screen.
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(Gap.lg),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sports_soccer,
                      size: 32,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Text(
                  l10n.loginTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: Gap.xl),
                if (widget.passwordResetSucceeded) ...[
                  _ResetSucceededBanner(message: l10n.passwordResetSuccess),
                  const SizedBox(height: Gap.lg),
                ],
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: l10n.emailLabel,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.emailRequired;
                    }
                    if (!AuthService.isValidEmail(value)) {
                      return l10n.emailInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: Gap.md),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.passwordLabel,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.passwordRequired;
                    }
                    return null;
                  },
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ForgotPasswordScreen(
                                  authService: widget.authService,
                                  // Carried over so it is not typed twice.
                                  initialEmail: _emailController.text.trim(),
                                ),
                              ),
                            ),
                    child: Text(l10n.forgotPasswordLink),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.loginButton),
                ),
                const SizedBox(height: Gap.lg),
                GoogleSignInSection(
                  authService: widget.authService,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: Gap.sm),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RegisterScreen(
                                authService: widget.authService,
                              ),
                            ),
                          ),
                  child: Text(l10n.noAccountPrompt),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line above the fields after a password reset: the change worked, and this
/// is the ordinary login it leads back to.
class _ResetSucceededBanner extends StatelessWidget {
  const _ResetSucceededBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: scheme.onPrimaryContainer),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
