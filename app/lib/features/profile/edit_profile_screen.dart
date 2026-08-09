import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
// `show`, because `package:intl` also exports a `TextDirection` that would
// shadow the one Flutter's text fields take.
import 'package:intl/intl.dart' show DateFormat;

import '../../core/app_header.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../auth/auth_models.dart';
import '../auth/auth_service.dart';
import 'current_user.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// Everything about a player that a player may change: who they are, how to
/// reach them, the credentials they sign in with, and the inputs the engine
/// reads (§4.1).
///
/// Split out of the profile in Sprint 2.5. The profile is now what a player
/// *is* — a record, read-only — and this is the form behind its Edit button.
/// The two were one screen, which meant opening "me" landed on a page of text
/// fields rather than on a career.
///
/// The two halves are saved by their own calls. The playing inputs are what a
/// refused generation points at; the name and the number are who the player is
/// to everyone else. Writing them together would make every correction of a
/// name a rewrite of the date of birth the engine depends on.
///
/// The rating is still absent. `OP-1` makes it system-managed, so it is neither
/// shown nor writable, and a role still belongs to a community membership and is
/// changed there.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    this.repository,
    this.authService,
    this.imagePicker,
  });

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ProfileRepository? repository;
  final AuthService? authService;
  final ImagePicker? imagePicker;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final ProfileRepository _profiles =
      widget.repository ?? ProfileRepository();
  late final AuthService _auth = widget.authService ?? AuthService();
  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();

  /// The form is seeded from the stored profile rather than rebuilt from it, so
  /// the load is held as state instead of a `FutureBuilder`: what the player
  /// has typed must survive the rebuilds that follow.
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _avatarBusy = false;

  DateTime? _dateOfBirth;
  PlayerPosition? _primaryPosition;
  PlayerPosition? _secondaryPosition;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final profile = await _profiles.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        // What is stored, including a date of birth that is not there yet.
        _dateOfBirth = profile.dateOfBirth;
        _primaryPosition = profile.primaryPosition;
        _secondaryPosition = profile.secondaryPosition;
        _avatarUrl = profile.avatarUrl;
        _fullNameController.text = profile.fullName;
        _phoneController.text = _localPhoneOf(profile.phone);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// The eight digits a player recognises as their number.
  ///
  /// The column holds E.164 (`+968XXXXXXXX`) because that is what a number is
  /// once it is stored; the country code is fixed for the MVP and is shown as a
  /// prefix rather than as something to type.
  String _localPhoneOf(String stored) {
    final digits = AuthService.digitsOnly(stored);
    const code = '968';
    final local = digits.startsWith(code) ? digits.substring(code.length) : digits;
    return local;
  }

  /// The profile as it currently stands, for the header's avatar and name.
  PlayerProfile get _asProfile => PlayerProfile(
        fullName: _fullNameController.text,
        phone: _phoneController.text,
        primaryPosition: _primaryPosition ?? PlayerPosition.mid,
        dateOfBirth: _dateOfBirth,
        secondaryPosition: _secondaryPosition,
        avatarUrl: _avatarUrl,
      );

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
      initialDate:
          _dateOfBirth ?? DateTime(today.year - 25, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() => _dateOfBirth = dateOnly(picked));
    field.didChange(_dateOfBirth);
  }

  /// Saves both halves, and only then reports success.
  ///
  /// The account goes first because it is the one the rest of the app reads by
  /// name: if the playing inputs are refused, the player still sees the name
  /// they just corrected rather than being told nothing was saved when half of
  /// it was.
  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      await _profiles.saveMyAccount(
        fullName: _fullNameController.text,
        phone: AuthService.toOmanE164(_phoneController.text),
      );
      await _profiles.saveMyProfile(
        dateOfBirth: _dateOfBirth!,
        primaryPosition: _primaryPosition!,
        secondaryPosition: _secondaryPosition,
      );
      await CurrentUser.instance.refresh();
      _showMessage(l10n.profileSaved);
    } on Failure catch (failure) {
      _showMessage(_failureMessage(l10n, failure, l10n.profileSaveFailed));
    } catch (_) {
      _showMessage(l10n.genericError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _failureMessage(
    AppLocalizations l10n,
    Failure failure,
    String onInvalid,
  ) =>
      switch (failure) {
        NetworkFailure() => l10n.networkError,
        AuthenticationFailure() || AuthorizationFailure() =>
          l10n.errNotAuthorized,
        ValidationFailure() || ConflictFailure() => onInvalid,
        _ => l10n.genericError,
      };

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- The picture -----------------------------------------------------------

  /// Asks where the picture should come from.
  ///
  /// Both, because they are different moments: a player setting up an account
  /// usually has a photo already, and one being handed the phone at the pitch
  /// does not. Returns null when the sheet is dismissed, which is a decision not
  /// to change the picture rather than a failure.
  Future<ImageSource?> _askImageSource() {
    final l10n = context.l10n;
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.avatarSourceCamera),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.avatarSourceGallery),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Picks an image and stores it as the player's avatar.
  ///
  /// The picker is asked for a bounded image rather than the original: a phone
  /// camera produces several megabytes, the bucket refuses anything over five,
  /// and nothing in this app displays an avatar larger than a list tile.
  Future<void> _changeAvatar() async {
    if (_avatarBusy) return;
    final l10n = context.l10n;

    final source = await _askImageSource();
    if (source == null || !mounted) return;

    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } catch (_) {
      // A camera the device does not have, or a permission the player refused.
      // Both are the same thing to this screen: no picture was chosen.
      _showMessage(l10n.avatarUploadFailed);
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _avatarBusy = true);
    try {
      final url = await _profiles.uploadMyAvatar(
        bytes: await picked.readAsBytes(),
        fileExtension: _extensionOf(picked.name),
      );
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      await CurrentUser.instance.refresh();
      _showMessage(l10n.avatarUpdated);
    } on Failure catch (failure) {
      _showMessage(_failureMessage(l10n, failure, l10n.avatarUploadFailed));
    } catch (_) {
      _showMessage(l10n.avatarUploadFailed);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (_avatarBusy) return;
    final l10n = context.l10n;

    setState(() => _avatarBusy = true);
    try {
      await _profiles.removeMyAvatar();
      if (!mounted) return;
      setState(() => _avatarUrl = null);
      await CurrentUser.instance.refresh();
      _showMessage(l10n.avatarRemoved);
    } on Failure catch (failure) {
      _showMessage(_failureMessage(l10n, failure, l10n.avatarUploadFailed));
    } catch (_) {
      _showMessage(l10n.avatarUploadFailed);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  /// The encoding the bytes are in, taken from what the picker named the file.
  /// Anything unrecognised is treated as JPEG, which is what a phone camera
  /// produces and what the picker re-encodes to when it resizes.
  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return 'jpg';
    final extension = fileName.substring(dot + 1).toLowerCase();
    return const {'png', 'webp', 'jpg', 'jpeg'}.contains(extension)
        ? (extension == 'jpeg' ? 'jpg' : extension)
        : 'jpg';
  }

  // --- The credentials -------------------------------------------------------

  /// Changes the email the account signs in with.
  ///
  /// The message afterwards says a confirmation was sent rather than that the
  /// address has changed: whether the provider requires the new address to be
  /// confirmed is its setting, and claiming the change has landed when it may
  /// not have would be the app asserting something it does not know.
  Future<void> _changeEmail() async {
    final l10n = context.l10n;
    final email = await _askFor(
      title: l10n.changeEmailTitle,
      label: l10n.emailLabel,
      initialValue: _auth.currentUserEmail ?? '',
      keyboardType: TextInputType.emailAddress,
      validator: (value) => AuthService.isValidEmail(value ?? '')
          ? null
          : l10n.emailInvalid,
    );
    if (email == null) return;

    try {
      await _auth.changeEmail(email);
      _showMessage(l10n.emailChangeRequested);
    } on Failure catch (failure) {
      _showMessage(_failureMessage(l10n, failure, l10n.emailInvalid));
    } catch (_) {
      _showMessage(l10n.genericError);
    }
  }

  Future<void> _changePassword() async {
    final l10n = context.l10n;
    final password = await _askFor(
      title: l10n.changePasswordTitle,
      label: l10n.passwordLabel,
      initialValue: '',
      obscure: true,
      confirmLabel: l10n.confirmPasswordLabel,
      confirmMismatch: l10n.passwordsDoNotMatch,
      validator: (value) => AuthService.isValidPassword(value ?? '')
          ? null
          : l10n.passwordTooShort,
    );
    if (password == null) return;

    try {
      await _auth.changePassword(password);
      _showMessage(l10n.passwordChanged);
    } on Failure catch (failure) {
      _showMessage(_failureMessage(l10n, failure, l10n.passwordTooShort));
    } catch (_) {
      _showMessage(l10n.genericError);
    }
  }

  /// One dialog for both credentials: a field, an optional confirmation of it,
  /// and the same validation the screen would apply anywhere else.
  Future<String?> _askFor({
    required String title,
    required String label,
    required String initialValue,
    required String? Function(String?) validator,
    bool obscure = false,
    String? confirmLabel,
    String? confirmMismatch,
    TextInputType? keyboardType,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _CredentialDialog(
        title: title,
        label: label,
        initialValue: initialValue,
        validator: validator,
        obscure: obscure,
        confirmLabel: confirmLabel,
        confirmMismatch: confirmMismatch,
        keyboardType: keyboardType,
      ),
    );
  }

  Future<void> _logOut() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logoutConfirmTitle),
        content: Text(l10n.logoutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.logoutLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await logOut(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      // No statistics shortcut here any more: the profile this was reached
      // from is the career, so the shortcut would point back the way the player
      // just came.
      appBar: AppHeader(title: Text(l10n.editProfileTitle)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
                ? _retry(l10n)
                : _form(l10n),
      ),
    );
  }

  Widget _retry(AppLocalizations l10n) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.loadFailed),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(l10n.retryButton)),
          ],
        ),
      );

  Widget _form(AppLocalizations l10n) {
    final locale = Localizations.localeOf(context).toString();
    final age = _asProfile.age;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _avatarField(l10n),
            const SizedBox(height: 24),

            _sectionTitle(l10n.profilePersonalSection),
            const SizedBox(height: 8),
            TextFormField(
              controller: _fullNameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: l10n.fullNameLabel),
              validator: (value) => (value == null || value.trim().length < 2)
                  ? l10n.fullNameRequired
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: l10n.phoneLabel,
                hintText: l10n.phoneHint,
                // Fixed for the MVP: the player enters the eight local digits.
                prefixText: '${AuthService.omanCallingCode} ',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.phoneRequired;
                }
                return AuthService.isValidOmanLocalPhone(value)
                    ? null
                    : l10n.phoneInvalid;
              },
            ),
            const SizedBox(height: 16),
            // Required before the profile is one the engine accepts (§4.1),
            // which is why an account that has none can still open this screen
            // but cannot save without supplying it.
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
            // The age, on its own row rather than as a note under the date.
            // It is derived from the date of birth and never stored (`KB-C7`) —
            // a stored number is wrong from the next birthday onwards — and it
            // is the figure the engine balances teams on (§15), so it is worth
            // showing plainly rather than in the margin. A profile with no date
            // of birth has no age, and nothing is invented for it (§4.3).
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cake_outlined),
              title: Text(l10n.ageLabel),
              subtitle: Text(age == null ? '—' : l10n.ageYears(age)),
            ),

            const SizedBox(height: 16),
            _sectionTitle(l10n.profileAccountSection),
            const SizedBox(height: 8),
            // Credentials, not profile columns: each is changed by its own
            // action because each is confirmed by the provider in its own way.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alternate_email),
              title: Text(l10n.emailLabel),
              subtitle: Text(_auth.currentUserEmail ?? '—'),
              trailing: TextButton(
                onPressed: _changeEmail,
                child: Text(l10n.changeAction),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: Text(l10n.passwordLabel),
              subtitle: Text(l10n.passwordHiddenNote),
              trailing: TextButton(
                onPressed: _changePassword,
                child: Text(l10n.changeAction),
              ),
            ),

            const SizedBox(height: 16),
            _sectionTitle(l10n.profilePlayingSection),
            const SizedBox(height: 8),

            const SizedBox(height: 8),
            DropdownButtonFormField<PlayerPosition>(
              initialValue: _primaryPosition,
              decoration: InputDecoration(labelText: l10n.positionLabel),
              items: [
                for (final position in PlayerPosition.values)
                  DropdownMenuItem(
                    value: position,
                    child: Text(_positionLabel(position)),
                  ),
              ],
              onChanged: (value) => setState(() {
                _primaryPosition = value;
                // The second position was a second choice. Once the primary
                // becomes it, it is no longer one, so it goes rather than
                // sitting there duplicating the primary.
                if (_secondaryPosition == value) _secondaryPosition = null;
              }),
              validator: (value) =>
                  value == null ? l10n.positionRequired : null,
            ),
            const SizedBox(height: 16),
            // Optional (`BTGE-SC-6`), and never the primary: the primary is
            // left out of the list, and "None" is an offered choice rather than
            // an empty field — choosing it is how a secondary is removed.
            DropdownButtonFormField<PlayerPosition?>(
              initialValue: _secondaryPosition,
              decoration:
                  InputDecoration(labelText: l10n.secondaryPositionLabel),
              items: [
                DropdownMenuItem<PlayerPosition?>(
                  value: null,
                  child: Text(l10n.noSecondaryPosition),
                ),
                for (final position in PlayerPosition.values)
                  if (position != _primaryPosition)
                    DropdownMenuItem<PlayerPosition?>(
                      value: position,
                      child: Text(_positionLabel(position)),
                    ),
              ],
              onChanged: (value) =>
                  setState(() => _secondaryPosition = value),
              validator: (value) =>
                  value != null && value == _primaryPosition
                      ? l10n.secondaryPositionSameAsPrimary
                      : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.saveButton),
            ),
            const SizedBox(height: 8),
            // The second place logout lives, the header menu being the first.
            OutlinedButton.icon(
              onPressed: _logOut,
              icon: const Icon(Icons.logout),
              label: Text(l10n.logoutLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _avatarField(AppLocalizations l10n) => Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              UserAvatar(profile: _asProfile, radius: 48),
              if (_avatarBusy) const CircularProgressIndicator(),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _avatarBusy ? null : _changeAvatar,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.avatarChangeAction),
              ),
              if (_avatarUrl != null)
                TextButton(
                  onPressed: _avatarBusy ? null : _removeAvatar,
                  child: Text(l10n.avatarRemoveAction),
                ),
            ],
          ),
        ],
      );
}

/// A single-field dialog with optional confirmation, used for both credentials.
class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.validator,
    required this.obscure,
    this.confirmLabel,
    this.confirmMismatch,
    this.keyboardType,
  });

  final String title;
  final String label;
  final String initialValue;
  final String? Function(String?) validator;
  final bool obscure;
  final String? confirmLabel;
  final String? confirmMismatch;
  final TextInputType? keyboardType;

  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<_CredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              obscureText: widget.obscure,
              keyboardType: widget.keyboardType,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: widget.label),
              validator: widget.validator,
            ),
            if (widget.confirmLabel != null) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: widget.obscure,
                textDirection: TextDirection.ltr,
                decoration:
                    InputDecoration(labelText: widget.confirmLabel!),
                validator: (value) => value == _controller.text
                    ? null
                    : widget.confirmMismatch,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.saveButton)),
      ],
    );
  }
}
