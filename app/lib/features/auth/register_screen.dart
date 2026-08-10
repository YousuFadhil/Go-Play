import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// `intl` exports a `TextDirection` of its own; the fields below mean Flutter's.
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../profile/profile_models.dart';
import 'auth_models.dart';
import 'auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.authService});

  /// Supplied only by tests, as the repositories take an optional port. Left
  /// null the screen builds the production service, so nothing here knows what
  /// a data provider is.
  final AuthService? authService;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AuthService _authService = widget.authService ?? AuthService();
  PlayerPosition? _position;
  PlayerPosition? _secondaryPosition;
  DateTime? _dateOfBirth;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
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

  /// Opens the date picker and records what came back.
  ///
  /// [lastDate] is today: a date of birth that has not happened yet is refused
  /// by never being offered. Nothing else is bounded — no approved document
  /// sets a minimum or maximum age, and the picker is not the place to invent
  /// one.
  Future<void> _pickDateOfBirth(FormFieldState<DateTime> field) async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(today.year - 25, today.month,
          today.day),
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() => _dateOfBirth = dateOnly(picked));
    field.didChange(_dateOfBirth);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = context.l10n;
    setState(() => _isLoading = true);
    try {
      await _authService.register(
        email: _emailController.text,
        localPhone: _phoneController.text,
        password: _passwordController.text,
        fullName: _fullNameController.text,
        position: _position!,
        dateOfBirth: _dateOfBirth!,
        secondaryPosition: _secondaryPosition,
      );
      // On success the session is active; AuthGate navigates to Home.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on Failure catch (failure) {
      _showError(switch (failure) {
        NetworkFailure() => l10n.networkError,
        // The only conflict sign-up can hit is an address already registered.
        ConflictFailure() => l10n.emailAlreadyUsed,
        AuthenticationFailure() => l10n.registerFailed,
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
    final locale = Localizations.localeOf(context).toString();

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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.phoneLabel,
                      hintText: l10n.phoneHint,
                      // Fixed Oman country code; user types only the 8 digits.
                      prefixText: '${AuthService.omanCallingCode} ',
                    ),
                    validator: (value) {
                      final digits = AuthService.digitsOnly(value ?? '');
                      if (digits.isEmpty) {
                        return l10n.phoneRequired;
                      }
                      if (!AuthService.isValidOmanLocalPhone(digits)) {
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
                  // A date, picked rather than typed. §4.1 makes it a required
                  // Core Player Input, so it is a field of the form and the
                  // form refuses to submit without it.
                  FormField<DateTime>(
                    initialValue: _dateOfBirth,
                    validator: (value) =>
                        value == null ? l10n.dateOfBirthRequired : null,
                    builder: (field) => InkWell(
                      onTap: () => _pickDateOfBirth(field),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: l10n.dateOfBirthLabel,
                          errorText: field.errorText,
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                        child: Text(field.value == null
                            ? l10n.selectDateLabel
                            : DateFormat.yMMMd(locale).format(field.value!)),
                      ),
                    ),
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
                    onChanged: (value) => setState(() {
                      _position = value;
                      // The second position was a second choice. Once the
                      // primary becomes it, it is no longer one, so it goes
                      // rather than sitting there duplicating the primary.
                      if (_secondaryPosition == value) {
                        _secondaryPosition = null;
                      }
                    }),
                    validator: (value) =>
                        value == null ? l10n.positionRequired : null,
                  ),
                  const SizedBox(height: 16),
                  // Optional (`BTGE-SC-6`), and never the primary: the primary
                  // is left out of the list, and "None" is an offered choice
                  // rather than an empty field.
                  DropdownButtonFormField<PlayerPosition?>(
                    initialValue: _secondaryPosition,
                    decoration: InputDecoration(
                      labelText: l10n.secondaryPositionLabel,
                    ),
                    items: [
                      DropdownMenuItem<PlayerPosition?>(
                        value: null,
                        child: Text(l10n.noSecondaryPosition),
                      ),
                      for (final position in PlayerPosition.values)
                        if (position != _position)
                          DropdownMenuItem<PlayerPosition?>(
                            value: position,
                            child: Text(_positionLabel(position)),
                          ),
                    ],
                    onChanged: (value) =>
                        setState(() => _secondaryPosition = value),
                    validator: (value) => value != null && value == _position
                        ? l10n.secondaryPositionSameAsPrimary
                        : null,
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
