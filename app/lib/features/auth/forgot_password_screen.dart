import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import 'auth_service.dart';

/// Asking for a password-recovery email.
///
/// **The answer never depends on the address.** Whatever is typed, a request
/// that reaches the provider ends in the same message — "if that email belongs
/// to an account, a link is on its way" — because this is a question anybody can
/// ask without signing in, and a screen that answered differently for a
/// registered address would be a way of finding out who is registered. The
/// provider gives the same answer either way and this screen adds nothing of its
/// own to it.
///
/// What it *does* report is what cannot be about the address: no connection, and
/// the provider limiting how often it will send.
///
/// A legacy account whose email was never a real inbox simply never receives
/// anything; that is by design and looks, from here, exactly like an address
/// that was never registered.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    this.authService,
    this.initialEmail = '',
  });

  /// Supplied only by tests, as the other authentication screens take one.
  final AuthService? authService;

  /// What the person had already typed on the login form, so they do not have to
  /// type it twice.
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);
  late final AuthService _authService = widget.authService ?? AuthService();
  bool _isLoading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = context.l10n;
    setState(() => _isLoading = true);
    try {
      await _authService.requestPasswordReset(_emailController.text);
      if (mounted) setState(() => _sent = true);
    } on Failure catch (failure) {
      _showError(switch (failure) {
        NetworkFailure() => l10n.networkError,
        InfrastructureFailure(reason: FailureReason.tooManyRequests) =>
          l10n.tooManyRequests,
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.forgotPasswordTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.xl),
          child: _sent ? _sentView(context) : _formView(context, theme),
        ),
      ),
    );
  }

  Widget _formView(BuildContext context, ThemeData theme) {
    final l10n = context.l10n;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Gap.xl),
          Text(l10n.forgotPasswordBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Gap.xl),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: l10n.emailLabel),
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
          const SizedBox(height: Gap.xl),
          FilledButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.forgotPasswordSend),
          ),
        ],
      ),
    );
  }

  Widget _sentView(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Gap.xxl),
        Center(
          child: Container(
            padding: const EdgeInsets.all(Gap.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_email_read_outlined,
              size: 32,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text(
          l10n.forgotPasswordSent,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.backToLogin),
        ),
      ],
    );
  }
}
