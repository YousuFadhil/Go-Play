import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'match_models.dart';
import 'match_service.dart';

/// Organizer edits an existing match. Registrations are kept; the server
/// handles reserve demotion if the player limit shrinks and notifies players.
class EditMatchScreen extends StatefulWidget {
  const EditMatchScreen({super.key, required this.match});

  final Match match;

  @override
  State<EditMatchScreen> createState() => _EditMatchScreenState();
}

class _EditMatchScreenState extends State<EditMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _startingPlayersController;
  late final TextEditingController _maxRegistrationController;
  late final TextEditingController _descriptionController;
  final _service = MatchService();

  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final m = widget.match;
    _titleController = TextEditingController(text: m.title ?? '');
    _locationController = TextEditingController(text: m.location);
    _startingPlayersController =
        TextEditingController(text: m.startingPlayers.toString());
    _maxRegistrationController =
        TextEditingController(text: m.maxRegistration.toString());
    _descriptionController = TextEditingController(text: m.description ?? '');
    _date = DateTime(m.startAt.year, m.startAt.month, m.startAt.day);
    _startTime = TimeOfDay.fromDateTime(m.startAt);
    _endTime = TimeOfDay.fromDateTime(m.endAt);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _startingPlayersController.dispose();
    _maxRegistrationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = _date.isBefore(now) ? _date : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: first,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
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

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;

    final start = _combine(_date, _startTime);
    var end = _combine(_date, _endTime);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    if (end.difference(start) > const Duration(hours: 12)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.endAfterStartError)));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _service.updateMatch(
        matchId: widget.match.id,
        title: _titleController.text,
        location: _locationController.text,
        startAt: start,
        endAt: end,
        startingPlayers: int.parse(_startingPlayersController.text),
        maxRegistration: int.parse(_maxRegistrationController.text),
        description: _descriptionController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.matchUpdatedSaved)));
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.matchUpdateFailed)));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.editMatchTitle)),
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
                  maxLength: 60,
                  decoration:
                      InputDecoration(labelText: l10n.matchTitleLabel),
                ),
                TextFormField(
                  controller: _locationController,
                  maxLength: 100,
                  decoration: InputDecoration(labelText: l10n.locationLabel),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l10n.locationRequired
                      : null,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(l10n.dateLabel),
                  subtitle: Text(DateFormat.yMMMEd(locale).format(_date)),
                  onTap: _pickDate,
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule),
                        title: Text(l10n.startTimeLabel),
                        subtitle: Text(_startTime.format(context)),
                        onTap: () => _pickTime(isStart: true),
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_outlined),
                        title: Text(l10n.endTimeLabel),
                        subtitle: Text(_endTime.format(context)),
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
                  validator: (value) {
                    final parsed = int.tryParse(value ?? '');
                    if (parsed == null || parsed < 2 || parsed > 30) {
                      return l10n.startingPlayersInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _maxRegistrationController,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: l10n.maxRegistrationLabel),
                  validator: (value) {
                    final parsed = int.tryParse(value ?? '');
                    if (parsed == null || parsed < 2 || parsed > 60) {
                      return l10n.maxRegistrationInvalid;
                    }
                    final starting =
                        int.tryParse(_startingPlayersController.text);
                    if (starting != null && parsed < starting) {
                      return l10n.capacityInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  maxLength: 300,
                  maxLines: 3,
                  decoration: InputDecoration(
                      labelText: l10n.matchDescriptionLabel),
                ),
                const SizedBox(height: 8),
                Text(l10n.reducePlayersNote,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
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
        ),
      ),
    );
  }
}
