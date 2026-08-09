import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import 'package:intl/intl.dart';

import 'app_settings.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import 'match_service.dart';

class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({super.key, required this.communityId});

  final String communityId;

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _startingPlayersController = TextEditingController(text: '14');
  final _matchService = MatchService();

  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _startingPlayersController.dispose();
    super.dispose();
  }

  DateTime? _combine(DateTime? date, TimeOfDay? time) {
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ??
          const TimeOfDay(hour: 20, minute: 0),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String? _validateSchedule() {
    final l10n = context.l10n;
    final start = _combine(_date, _startTime);
    var end = _combine(_date, _endTime);
    if (start == null || end == null) return l10n.dateTimeRequired;
    // A match ending past midnight rolls into the next day.
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    if (end.difference(start) > const Duration(hours: 12)) {
      return l10n.endAfterStartError;
    }
    if (!start.isAfter(DateTime.now())) return l10n.startInPastError;
    return null;
  }

  /// What to tell the organizer when `create_match` refuses.
  ///
  /// The screen asks the same questions before it sends, so most of these are
  /// only reachable when the two disagree — a title of one character passes
  /// "not empty" here and fails `char_length(trim(...)) >= 2` there, and a
  /// start time still in the future when it was picked can be in the past by
  /// the time the request lands. The database is the one that has to be right,
  /// so what it refuses is what the organizer is told.
  String _createError(AppLocalizations l10n, Object e) {
    if (e is AuthorizationFailure) return l10n.errNotAuthorized;
    if (e is Failure) {
      return switch (e.reason) {
        FailureReason.invalidTitle => l10n.errInvalidTitle,
        FailureReason.invalidLocation => l10n.errInvalidLocation,
        FailureReason.startInPast => l10n.startInPastError,
        FailureReason.invalidTimeRange => l10n.endAfterStartError,
        FailureReason.invalidStartingPlayers => l10n.startingPlayersInvalid,
        FailureReason.communityInactive => l10n.errCommunityInactive,
        _ => l10n.matchCreateFailed,
      };
    }
    return l10n.matchCreateFailed;
  }

  Future<void> _submit() async {
    final scheduleError = _validateSchedule();
    final formValid = _formKey.currentState!.validate();
    if (scheduleError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(scheduleError)));
      return;
    }
    if (!formValid) return;

    final start = _combine(_date, _startTime)!;
    var end = _combine(_date, _endTime)!;
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

    setState(() => _isLoading = true);
    try {
      await _matchService.createMatch(
        communityId: widget.communityId,
        title: _titleController.text,
        location: _locationController.text,
        startAt: start,
        endAt: end,
        startingPlayers: int.parse(_startingPlayersController.text),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_createError(context.l10n, e))),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.createMatchTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(labelText: l10n.matchTitleLabel),
                  maxLength: 60,
                  textInputAction: TextInputAction.next,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l10n.matchTitleRequired
                      : null,
                ),
                TextFormField(
                  controller: _locationController,
                  decoration: InputDecoration(labelText: l10n.locationLabel),
                  maxLength: 100,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l10n.locationRequired
                      : null,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(l10n.dateLabel),
                  subtitle: Text(_date == null
                      ? '—'
                      : DateFormat.yMMMEd(locale).format(_date!)),
                  onTap: _pickDate,
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule),
                        title: Text(l10n.startTimeLabel),
                        subtitle: Text(_startTime?.format(context) ?? '—'),
                        onTap: () => _pickTime(isStart: true),
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_outlined),
                        title: Text(l10n.endTimeLabel),
                        subtitle: Text(_endTime?.format(context) ?? '—'),
                        onTap: () => _pickTime(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _startingPlayersController,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: l10n.startingPlayersLabel),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    // 4 is the approved OP-2 minimum match size (2 v 2), the
                    // same bound the database and update_match enforce.
                    final parsed = int.tryParse(value ?? '');
                    if (parsed == null || parsed < 4 || parsed > 30) {
                      return l10n.startingPlayersInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                // Maximum registration is derived, never entered.
                Text(
                  l10n.capacityAutoNote(
                    AppSettings.reservePlayers,
                    AppSettings.maxRegistrationFor(
                        int.tryParse(_startingPlayersController.text) ?? 0),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
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
                      : Text(l10n.createMatchButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
