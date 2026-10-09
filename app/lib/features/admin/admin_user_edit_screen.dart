import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import '../auth/auth_models.dart' show PlayerPosition;
import '../auth/auth_service.dart' show AuthService;
import '../locations/wilayat_picker.dart';
import '../locations/wilayat_repository.dart';
import '../profile/profile_models.dart' show ProfileVisibility, dateOnly;
import 'admin_models.dart';
import 'admin_repository.dart';

/// What a position reads as. Shared with the Account data section, so the
/// console says it one way.
String adminPositionLabel(AppLocalizations l10n, PlayerPosition position) =>
    switch (position) {
      PlayerPosition.gk => l10n.positionGk,
      PlayerPosition.def => l10n.positionDef,
      PlayerPosition.mid => l10n.positionMid,
      PlayerPosition.fwd => l10n.positionFwd,
    };

/// The five groups an administrator can edit, one RPC each (migration `0095`).
enum _Group { account, player, privacy, location, push }

/// Edits one account's data and settings, a group at a time.
///
/// **Five groups, five saves.** Each group sets its whole set of columns through
/// its own RPC and carries its own optional reason; there is no "save
/// everything" and no patch call, so what an audit entry says was changed is
/// exactly the group that was saved. The Save button is enabled only while the
/// group differs from what was last read, so a tap is never an empty request --
/// the database would treat one as a no-op anyway, and writes no audit entry.
///
/// Nothing here is authorization. The console leaves the entry out for the
/// administrator's own account and for a System Admin, and the database refuses
/// both regardless; a refusal that arrives anyway is worded, not hidden.
///
/// The avatar, email, password and sign-in method are not editable here.
class AdminUserEditScreen extends StatefulWidget {
  const AdminUserEditScreen({
    super.key,
    required this.account,
    required this.repository,
    this.wilayatRepository,
  });

  /// The account as it was read when the screen was opened.
  final AdminUserAccount account;

  final AdminRepository repository;

  /// The Wilayat reference data; defaults to the app-wide cached instance.
  /// Supplied only by tests.
  final WilayatRepository? wilayatRepository;

  @override
  State<AdminUserEditScreen> createState() => _AdminUserEditScreenState();
}

class _AdminUserEditScreenState extends State<AdminUserEditScreen> {
  late AdminUserAccount _account = widget.account;
  late final WilayatRepository _wilayats =
      widget.wilayatRepository ?? WilayatRepository.shared;

  final _accountForm = GlobalKey<FormState>();

  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final Map<_Group, TextEditingController> _reasons = {
    for (final group in _Group.values) group: TextEditingController(),
  };

  DateTime? _dateOfBirth;
  late PlayerPosition _primary = _account.primaryPosition;
  PlayerPosition? _secondary;
  late ProfileVisibility _visibility = _account.profileVisibility;
  late bool _ageVisible = _account.ageVisible;
  int? _wilayatCode;
  late bool _matchPush = _account.matchPush;
  late bool _communityPush = _account.communityPush;
  late bool _muteAll = _account.muteAll;

  final Set<_Group> _saving = {};

  @override
  void initState() {
    super.initState();
    for (final group in _Group.values) {
      _fill(group, _account);
    }
    // The label of an existing Default Location. Not worth an error: without
    // the catalog the field shows a dash and still works.
    if (_wilayatCode != null) {
      _wilayats.load().then<void>((_) {
        if (mounted) setState(() {});
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    for (final controller in _reasons.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // --- The form follows the last read ---------------------------------------

  /// Puts [account]'s values for [group] into the form.
  void _fill(_Group group, AdminUserAccount account) {
    switch (group) {
      case _Group.account:
        _fullName.text = account.fullName;
        _phone.text = account.phone.startsWith(AuthService.omanCallingCode)
            ? account.phone.substring(AuthService.omanCallingCode.length)
            : account.phone;
      case _Group.player:
        _dateOfBirth =
            account.dateOfBirth == null ? null : dateOnly(account.dateOfBirth!);
        _primary = account.primaryPosition;
        _secondary = account.secondaryPosition;
      case _Group.privacy:
        _visibility = account.profileVisibility;
        _ageVisible = account.ageVisible;
      case _Group.location:
        _wilayatCode = account.defaultWilayatCode;
      case _Group.push:
        _matchPush = account.matchPush;
        _communityPush = account.communityPush;
        _muteAll = account.muteAll;
    }
  }

  /// Whether [group] differs from what was last read.
  bool _dirty(_Group group) => switch (group) {
        _Group.account => _fullName.text.trim() != _account.fullName ||
            AuthService.toOmanE164(_phone.text) != _account.phone,
        _Group.player => !_sameDate(_dateOfBirth, _account.dateOfBirth) ||
            _primary != _account.primaryPosition ||
            _secondary != _account.secondaryPosition,
        _Group.privacy => _visibility != _account.profileVisibility ||
            _ageVisible != _account.ageVisible,
        _Group.location => _wilayatCode != _account.defaultWilayatCode,
        _Group.push => _matchPush != _account.matchPush ||
            _communityPush != _account.communityPush ||
            _muteAll != _account.muteAll,
      };

  static bool _sameDate(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return dateOnly(a) == dateOnly(b);
  }

  // --- Saving ----------------------------------------------------------------

  /// Runs one group's RPC, then re-reads the account so the form follows what
  /// the database now holds.
  ///
  /// The re-read is its own step: a save that succeeded is reported as saved
  /// even if the read after it fails, because telling an administrator nothing
  /// was saved when it was is the worse mistake. Only the saved group is
  /// refilled, so edits sitting unsaved in another group are not thrown away.
  Future<void> _save(
    _Group group,
    Future<void> Function(String reason) call,
  ) async {
    if (_saving.contains(group)) return;

    final l10n = context.l10n;
    setState(() => _saving.add(group));
    try {
      var saved = false;
      try {
        await call(_reasons[group]!.text);
        saved = true;
      } on Failure catch (failure) {
        _showMessage(_failureMessage(l10n, failure));
      } catch (_) {
        _showMessage(l10n.genericError);
      }
      if (!saved) return;

      _reasons[group]!.clear();
      try {
        final fresh = await widget.repository.userAccount(_account.id);
        if (mounted) {
          setState(() {
            _account = fresh;
            _fill(group, fresh);
          });
        }
      } catch (_) {
        // Keeps the previous read; the group stays enabled, and saving it again
        // is a no-op the database does not audit.
      }
      _showMessage(l10n.adminEditSaved);
    } finally {
      if (mounted) setState(() => _saving.remove(group));
    }
  }

  Future<void> _saveAccount() async {
    if (!_accountForm.currentState!.validate()) return;
    await _save(
      _Group.account,
      (reason) => widget.repository.updateUserAccount(
        _account.id,
        fullName: _fullName.text.trim(),
        phone: AuthService.toOmanE164(_phone.text),
        reason: reason,
      ),
    );
  }

  Future<void> _savePlayer() => _save(
        _Group.player,
        (reason) => widget.repository.updateUserPlayerProfile(
          _account.id,
          dateOfBirth: _dateOfBirth,
          primaryPosition: _primary,
          secondaryPosition: _secondary,
          reason: reason,
        ),
      );

  Future<void> _savePrivacy() => _save(
        _Group.privacy,
        (reason) => widget.repository.updateUserPrivacy(
          _account.id,
          visibility: _visibility,
          ageVisible: _ageVisible,
          reason: reason,
        ),
      );

  Future<void> _saveLocation() => _save(
        _Group.location,
        (reason) => widget.repository.updateUserDefaultWilayat(
          _account.id,
          wilayatCode: _wilayatCode,
          reason: reason,
        ),
      );

  Future<void> _savePush() => _save(
        _Group.push,
        (reason) => widget.repository.updateUserPushPreferences(
          _account.id,
          matchPush: _matchPush,
          communityPush: _communityPush,
          muteAll: _muteAll,
          reason: reason,
        ),
      );

  String _failureMessage(AppLocalizations l10n, Failure failure) =>
      switch (failure) {
        NetworkFailure() => l10n.networkError,
        // The database refused who may be edited: the administrator's own
        // account, a System Admin's, or a caller who is no longer one.
        AuthenticationFailure() ||
        AuthorizationFailure() =>
          l10n.adminEditNotAllowed,
        ValidationFailure() => l10n.adminEditInvalid,
        NotFoundFailure() => l10n.adminEditUserNotFound,
        _ => l10n.genericError,
      };

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Pickers ----------------------------------------------------------------

  /// [lastDate] is today and [firstDate] is 1900-01-01: the range the database
  /// accepts, so a date it would refuse is never offered.
  Future<void> _pickDateOfBirth() async {
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
  }

  Future<void> _chooseLocation() async {
    final picked = await showWilayatPicker(
      context,
      repository: _wilayats,
      selectedCode: _wilayatCode,
    );
    if (picked == null || !mounted) return;
    setState(() => _wilayatCode = picked);
  }

  // --- Layout ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.adminAccountEditAction)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Layout.listBottom),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kPageMargin, Gap.lg, kPageMargin, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_account.fullName, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: Gap.xs),
                  Text(
                    _account.email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _accountGroup(l10n),
            _playerGroup(l10n),
            _privacyGroup(l10n),
            _locationGroup(l10n),
            _pushGroup(l10n),
          ],
        ),
      ),
    );
  }

  /// A titled card holding one group's fields, its reason and its Save.
  Widget _group({
    required AppLocalizations l10n,
    required _Group group,
    required String title,
    required List<Widget> fields,
    required VoidCallback onSave,
  }) {
    final saving = _saving.contains(group);
    final canSave = _dirty(group) && !saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(title: title),
        SectionCard(children: [
          Padding(
            padding: const EdgeInsets.all(Layout.cardInner),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...fields,
                const SizedBox(height: Gap.md),
                TextField(
                  key: Key('adminEditReason_${group.name}'),
                  controller: _reasons[group],
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: l10n.adminEditReasonLabel,
                    helperText: l10n.adminEditReasonHelp,
                  ),
                ),
                const SizedBox(height: Gap.md),
                FilledButton(
                  key: Key('adminEditSave_${group.name}'),
                  onPressed: canSave ? onSave : null,
                  child: saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.saveButton),
                ),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  Widget _accountGroup(AppLocalizations l10n) => _group(
        l10n: l10n,
        group: _Group.account,
        title: l10n.adminEditGroupAccount,
        onSave: _saveAccount,
        fields: [
          Form(
            key: _accountForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('adminEditFullName'),
                  controller: _fullName,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.fullNameLabel),
                  onChanged: (_) => setState(() {}),
                  validator: (value) =>
                      (value == null || value.trim().length < 2)
                          ? l10n.fullNameRequired
                          : null,
                ),
                const SizedBox(height: Gap.md),
                TextFormField(
                  key: const Key('adminEditPhone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: l10n.phoneLabel,
                    hintText: l10n.phoneHint,
                    prefixText: '${AuthService.omanCallingCode} ',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.phoneRequired;
                    }
                    return AuthService.isValidOmanLocalPhone(value)
                        ? null
                        : l10n.phoneInvalid;
                  },
                ),
              ],
            ),
          ),
        ],
      );

  Widget _playerGroup(AppLocalizations l10n) {
    final locale = Localizations.localeOf(context).toString();

    return _group(
      l10n: l10n,
      group: _Group.player,
      title: l10n.adminEditGroupPlayer,
      onSave: _savePlayer,
      fields: [
        // Optional: an account that never gave a date of birth stays editable,
        // and clearing one is a deliberate act with its own control.
        InkWell(
          key: const Key('adminEditDateOfBirth'),
          onTap: _pickDateOfBirth,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.dateOfBirthLabel,
              suffixIcon: _dateOfBirth == null
                  ? const Icon(Icons.calendar_today)
                  : IconButton(
                      key: const Key('adminEditClearDateOfBirth'),
                      tooltip: l10n.adminEditClearDateOfBirth,
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dateOfBirth = null),
                    ),
            ),
            child: Text(
              _dateOfBirth == null
                  ? l10n.selectDateLabel
                  : DateFormat.yMMMd(locale).format(_dateOfBirth!),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        InputDecorator(
          decoration: InputDecoration(labelText: l10n.positionLabel),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<PlayerPosition>(
              key: const Key('adminEditPrimary'),
              isExpanded: true,
              value: _primary,
              items: [
                for (final position in PlayerPosition.values)
                  DropdownMenuItem(
                    value: position,
                    child: Text(adminPositionLabel(l10n, position)),
                  ),
              ],
              onChanged: (value) => setState(() {
                if (value == null) return;
                _primary = value;
                // The secondary was a second choice; once the primary becomes
                // it, it is no longer one, so it goes rather than duplicating
                // the primary.
                if (_secondary == value) _secondary = null;
              }),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        // Never the primary: the primary is left out of the list, and "None" is
        // an offered choice -- choosing it is how a secondary is removed.
        InputDecorator(
          decoration: InputDecoration(labelText: l10n.secondaryPositionLabel),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<PlayerPosition?>(
              key: const Key('adminEditSecondary'),
              isExpanded: true,
              value: _secondary,
              items: [
                DropdownMenuItem<PlayerPosition?>(
                  value: null,
                  child: Text(l10n.noSecondaryPosition),
                ),
                for (final position in PlayerPosition.values)
                  if (position != _primary)
                    DropdownMenuItem<PlayerPosition?>(
                      value: position,
                      child: Text(adminPositionLabel(l10n, position)),
                    ),
              ],
              onChanged: (value) => setState(() => _secondary = value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _privacyGroup(AppLocalizations l10n) => _group(
        l10n: l10n,
        group: _Group.privacy,
        title: l10n.settingsPrivacySection,
        onSave: _savePrivacy,
        fields: [
          InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.adminAccountProfileVisibilityLabel,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ProfileVisibility>(
                key: const Key('adminEditVisibility'),
                isExpanded: true,
                value: _visibility,
                items: [
                  DropdownMenuItem(
                    value: ProfileVisibility.everyone,
                    child: Text(l10n.profileVisibilityEveryone),
                  ),
                  DropdownMenuItem(
                    value: ProfileVisibility.communityMembersOnly,
                    child: Text(l10n.profileVisibilityCommunityMembers),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _visibility = value);
                },
              ),
            ),
          ),
          SwitchListTile(
            key: const Key('adminEditAgeVisible'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.adminAccountAgeVisibleLabel),
            value: _ageVisible,
            onChanged: (value) => setState(() => _ageVisible = value),
          ),
        ],
      );

  Widget _locationGroup(AppLocalizations l10n) => _group(
        l10n: l10n,
        group: _Group.location,
        title: l10n.defaultLocationLabel,
        onSave: _saveLocation,
        fields: [
          WilayatField(
            key: const Key('adminEditDefaultLocation'),
            label: l10n.defaultLocationLabel,
            valueText: _wilayatCode == null
                ? null
                : _wilayats.cached?.nameOf(
                      _wilayatCode,
                      arabic: wilayatArabic(context),
                    ) ??
                    '—',
            emptyText: l10n.wilayatNotSet,
            onTap: _chooseLocation,
            onClear: _wilayatCode == null
                ? null
                : () => setState(() => _wilayatCode = null),
            clearTooltip: l10n.defaultLocationClear,
          ),
        ],
      );

  Widget _pushGroup(AppLocalizations l10n) => _group(
        l10n: l10n,
        group: _Group.push,
        title: l10n.settingsNotificationsSection,
        onSave: _savePush,
        fields: [
          SwitchListTile(
            key: const Key('adminEditMatchPush'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.pushMatchLabel),
            value: _matchPush,
            onChanged: (value) => setState(() => _matchPush = value),
          ),
          SwitchListTile(
            key: const Key('adminEditCommunityPush'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.pushCommunityLabel),
            value: _communityPush,
            onChanged: (value) => setState(() => _communityPush = value),
          ),
          SwitchListTile(
            key: const Key('adminEditMuteAll'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.pushMuteAllLabel),
            value: _muteAll,
            onChanged: (value) => setState(() => _muteAll = value),
          ),
        ],
      );
}
