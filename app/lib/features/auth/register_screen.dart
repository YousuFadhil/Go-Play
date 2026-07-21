import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import 'auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  PlayerPosition? _position;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _positionLabel(PlayerPosition position) {
    final l10n = context.l10n;
    return switch (position) {
      PlayerPosition.gk => l10n.positionGk,
      PlayerPosition.def => l10n.positionDef,
      PlayerPosition.mid => l10n.positionMid,
      PlayerPosition.fwd => l10n.positionFwd,
    };
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = context.l10n;
    setState(() => _isLoading = true);
    try {
      await _authService.register(
        phone: _phoneController.text,
        password: _passwordController.text,
        fullName: _fullNameController.text,
        position: _position!,
      );
      // On success the session is active; AuthGate navigates to Home.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      _showError(e.statusCode == '422' || e.message.contains('already')
          ? l10n.phoneAlreadyUsed
          : l10n.registerFailed);
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
      appBar: AppBar(title: Text(l10n.registerTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _fullNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l10n.fullNameLabel,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.fullNameRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: l10n.phoneLabel,
                      hintText: l10n.phoneHint,
                    ),
                    validator: (value) {
                      final normalized =
                          AuthService.normalizePhone(value ?? '');
                      if (normalized.isEmpty) {
                        return l10n.phoneRequired;
                      }
                      if (!AuthService.isValidPhone(normalized)) {
                        return l10n.phoneInvalid;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
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
                      if (value.length < 8) {
                        return l10n.passwordTooShort;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<PlayerPosition>(
                    initialValue: _position,
                    decoration: InputDecoration(
                      labelText: l10n.positionLabel,
                    ),
                    items: [
                      for (final position in PlayerPosition.values)
                        DropdownMenuItem(
                          value: position,
                          child: Text(_positionLabel(position)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _position = value),
                    validator: (value) =>
                        value == null ? l10n.positionRequired : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.registerButton),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed:
                        _isLoading ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.haveAccountPrompt),
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
