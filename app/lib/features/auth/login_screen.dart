import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/language_toggle.dart';
import 'auth_service.dart';
import 'register_screen.dart';

/// Signing in.
///
/// No longer the app's home screen — a visitor lands on Discover and arrives
/// here by asking to, or by trying something that needs an account. The
/// behaviour is deliberately untouched by that move: the same fields, the same
/// validation, the same failures, and the same unwind to the root route on
/// success, which the auth gate then answers by swapping the public tree for the
/// signed-in one.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authService});

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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
                const Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: LanguageToggle(),
                ),
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
                const SizedBox(height: Gap.xl),
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
