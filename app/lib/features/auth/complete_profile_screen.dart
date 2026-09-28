import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// `intl` exports a `TextDirection` of its own; the fields below mean Flutter's.
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../profile/profile_models.dart';
import 'auth_models.dart';
import 'auth_service.dart';

/// The player profile an account arrives without.
///
/// An account that signed in with Google has a name and an email and nothing
/// football-shaped, and the database no longer invents the rest (migration
/// `0092`). Until the person gives it they are neither suspended nor a player,
/// and the auth gate shows this screen instead of either.
///
/// It asks for exactly what registration asks for once an identity exists — full
/// name, Oman phone, date of birth, primary position and an optional secondary —
/// and under the same rules, which live in [AuthService] and are not restated
/// here. **There is no email and no password**: the account has its credentials
/// already, and asking again would only suggest it did not.
///
/// The name starts as whatever the sign-in provider supplied, when it supplied
/// one, and is the person's to change: it is what every roster will show.
///
/// Finishing does not navigate. It tells the gate ([onCompleted]), which asks
/// the database what the account is now and lets the player in only if the
/// answer is "active" — this screen never decides that for itself.
class CompletePlayerProfileScreen extends StatefulWidget {
  const CompletePlayerProfileScreen({
    super.key,
    required this.authService,
    required this.onCompleted,
  });

  final AuthService authService;

  /// The profile exists now (or already did). The gate re-checks the account.
  final VoidCallback onCompleted;

  @override
  State<CompletePlayerProfileScreen> createState() =>
      _CompletePlayerProfileScreenState();
}

class _CompletePlayerProfileScreenState
    extends State<CompletePlayerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController =
      TextEditingController(text: widget.authService.suggestedFullName ?? '');
  final _phoneController = TextEditingController();
  PlayerPosition? _position;
  PlayerPosition? _secondaryPosition;
  DateTime? _dateOfBirth;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
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

  /// Same bounds as registration: nothing after today, and no minimum or maximum
  /// age, because no approved document sets one.
  Future<void> _pickDateOfBirth(FormFieldState<DateTime> field) async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dateOfBirth ?? DateTime(today.year - 25, today.month, today.day),
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
      await widget.authService.completePlayerProfile(
        fullName: _fullNameController.text,
        localPhone: _phoneController.text,
        dateOfBirth: _dateOfBirth!,
        position: _position!,
        secondaryPosition: _secondaryPosition,
      );
      widget.onCompleted();
    } on Failure catch (failure) {
      switch (failure) {
        // The account has a profile already - a second tap, or it was finished
        // elsewhere. That is the outcome this screen exists for, so the gate is
        // simply asked again rather than the person being told it failed.
        case ConflictFailure():
          widget.onCompleted();
        case NetworkFailure():
          _showError(l10n.networkError);
        case ValidationFailure():
          _showError(l10n.profileDetailsInvalid);
        default:
          _showError(l10n.genericError);
      }
    } catch (_) {
      _showError(l10n.genericError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Leaving without finishing. Ordinary sign-out; the gate follows the session.
  Future<void> _signOut() async {
    setState(() => _isLoading = true);
    try {
      await widget.authService.logout();
    } catch (_) {
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
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.completeProfileTitle),
        automaticallyImplyLeading: false,
      ),
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
                  Text(
                    l10n.completeProfileBody,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Gap.xl),
                  TextFormField(
                    controller: _fullNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: l10n.fullNameLabel),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.fullNameRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: Gap.lg),
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
                      // Fixed Oman country code; the person types only the 8
                      // digits.
                      prefixText: '${AuthService.omanCallingCode} ',
                    ),
                    validator: (value) {
                      final digits = AuthService.digitsOnly(value ?? '');
                      if (digits.isEmpty) return l10n.phoneRequired;
                      if (!AuthService.isValidOmanLocalPhone(digits)) {
                        return l10n.phoneInvalid;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: Gap.lg),
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
                  const SizedBox(height: Gap.lg),
                  DropdownButtonFormField<PlayerPosition>(
                    initialValue: _position,
                    decoration: InputDecoration(labelText: l10n.positionLabel),
                    items: [
                      for (final position in PlayerPosition.values)
                        DropdownMenuItem(
                          value: position,
                          child: Text(_positionLabel(position)),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _position = value;
                      // Once the primary becomes it, the second position is no
                      // longer a second choice, so it goes.
                      if (_secondaryPosition == value) {
                        _secondaryPosition = null;
                      }
                    }),
                    validator: (value) =>
                        value == null ? l10n.positionRequired : null,
                  ),
                  const SizedBox(height: Gap.lg),
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
                  const SizedBox(height: Gap.xl),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.completeProfileSubmit),
                  ),
                  const SizedBox(height: Gap.sm),
                  TextButton(
                    onPressed: _isLoading ? null : _signOut,
                    child: Text(l10n.logoutLabel),
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
