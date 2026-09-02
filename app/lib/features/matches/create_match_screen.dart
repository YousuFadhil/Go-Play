import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'app_settings.dart';
import '../../core/club_task.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/tokens.dart';
import 'match_service.dart';

class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({
    super.key,
    required this.communityId,
    this.matchService,
  });

  final String communityId;

  /// Supplied by widget tests; production construction stays on [MatchService].
  final MatchService? matchService;

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _startingPlayersController = TextEditingController(text: '14');
  late final MatchService _matchService = widget.matchService ?? MatchService();

  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isLoading = false;

  /// Whether the organizer is recording a fixture the community has already
  /// played rather than scheduling one (migration `0054`).
  ///
  /// One screen and two temporal rules, not two screens: everything else about
  /// creating a match — the name, the venue, the squad size, who is allowed to
  /// do it — is the same question in both cases, and a second form would be the
  /// same form with one line changed.
  bool _isHistorical = false;

  /// Where this community has played before, newest first.
  ///
  /// A community plays the same handful of pitches over and over, and typing
  /// one out every time is the cost this saves. It is a **convenience over the
  /// matches that already exist**, not a venue feature: nothing is stored, no
  /// table is added, and what a tap does is fill in the same free-text field
  /// the organizer could have typed themselves.
  late final Future<List<String>> _recent = _loadRecentLocations();

  /// The distinct locations of this community's matches, most recently used
  /// first, capped at a handful.
  ///
  /// One read of the matches this community already has — the same
  /// `fetchCommunityMatches` the community screen uses, already ordered by
  /// `start_at` descending — so this costs one query and never one per
  /// location.
  ///
  /// Case and surrounding space decide *duplication* only. The spelling kept is
  /// the one from the most recent match, so a pitch entered as "al amerat
  /// pitch" last week and "Al Amerat Pitch" yesterday is offered once, as
  /// yesterday's reader would recognise it.
  ///
  /// A failure here is not a failure of the screen: the field is a text field
  /// with or without suggestions, so the read is swallowed and nothing is
  /// offered.
  Future<List<String>> _loadRecentLocations() async {
    const limit = 6;
    try {
      final matches =
          await _matchService.fetchCommunityMatches(widget.communityId);
      final seen = <String>{};
      final recent = <String>[];
      for (final match in matches) {
        final location = match.location.trim();
        if (location.isEmpty) continue;
        if (!seen.add(location.toLowerCase())) continue;
        recent.add(location);
        if (recent.length == limit) break;
      }
      return recent;
    } catch (_) {
      return const [];
    }
  }

  /// The chips under the location field, when there are any to show.
  ///
  /// Compact on purpose: a wrap of short chips under the field rather than a
  /// list or a second screen, so the ordinary case — type a new place — is
  /// untouched and the common case is one tap.
  Widget _recentLocations() => FutureBuilder<List<String>>(
        future: _recent,
        builder: (context, snapshot) {
          final locations = snapshot.data ?? const <String>[];
          if (locations.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: [
                  for (final location in locations)
                    ActionChip(
                      key: Key('recentLocation_$location'),
                      label: Text(location),
                      onPressed: () {
                        _locationController.text = location;
                        // The caret follows the text, so the organizer can edit
                        // what they just chose instead of typing in front of it.
                        _locationController.selection =
                            TextSelection.collapsed(offset: location.length);
                      },
                    ),
                ],
              ),
            ),
          );
        },
      );

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

  /// The window the date picker offers, which is the whole of what the two
  /// modes change about picking a day: a fixture still to come is somewhere in
  /// the next year, one already played is somewhere in the last one.
  ///
  /// The bounds are the picker's manners rather than the rule. What decides
  /// whether a schedule is acceptable is [_validateSchedule], and after that
  /// `create_match` — a day inside the window can still carry times that are
  /// not, which is exactly what happens when today is picked in either mode.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = _isHistorical ? now.subtract(const Duration(days: 365)) : now;
    final last = _isHistorical ? now : now.add(const Duration(days: 365));
    final initial = _date ?? now;
    final picked = await showDatePicker(
      context: context,
      // Clamped rather than trusted: a day chosen in one mode can sit outside
      // the other's window, and `showDatePicker` asserts on an initial date it
      // was not given room for.
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Switches between scheduling a match and recording one that was played.
  ///
  /// The day is cleared, because it is the one field whose acceptable range the
  /// two modes disagree about: a date picked for next Friday is not a date a
  /// match was played on, and carrying it across would leave the organizer
  /// looking at a schedule the form is about to refuse. The times are kept —
  /// matches kick off at the same hour whenever they are entered.
  void _setHistorical(bool value) {
    if (value == _isHistorical) return;
    setState(() {
      _isHistorical = value;
      _date = null;
    });
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

  void _stepStartingPlayers(int delta) {
    final current = int.tryParse(_startingPlayersController.text) ?? 14;
    final next = (current + delta).clamp(4, 30);
    _startingPlayersController.text = '$next';
    setState(() {});
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
    // The one question the two modes answer differently, and the same branch
    // `create_match` takes: an ordinary match is entirely ahead of now, a
    // recorded one entirely behind it. Everything above this line — both ends
    // present, the end after the start, the twelve-hour bound — is asked of
    // both, because none of it is about when the match is.
    if (_isHistorical) {
      if (!end.isBefore(DateTime.now())) return l10n.historicalNotPastError;
    } else {
      if (!start.isAfter(DateTime.now())) return l10n.startInPastError;
    }
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
        FailureReason.historicalNotPast => l10n.historicalNotPastError,
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
        isHistorical: _isHistorical,
      );
      if (mounted) {
        // A recorded match is only half entered when it is created: nobody is
        // registered for it and nobody can be, so the organizer is told where
        // the rest of it is done rather than left on a match with an empty
        // roster and no way to fill it.
        if (_isHistorical) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.historicalMatchRecorded)),
          );
        }
        Navigator.of(context).pop(true);
      }
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
      appBar: ClubTaskBar(title: l10n.createMatchTitle),
      body: ClubTaskBody(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Layout.cardInner),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _titleController,
                        decoration:
                            InputDecoration(labelText: l10n.matchTitleLabel),
                        maxLength: 60,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? l10n.matchTitleRequired
                                : null,
                      ),
                      TextFormField(
                        controller: _locationController,
                        decoration:
                            InputDecoration(labelText: l10n.locationLabel),
                        maxLength: 100,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? l10n.locationRequired
                                : null,
                      ),
                      _recentLocations(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Layout.cardGap),
              // What kind of match this is, above the schedule it governs. It
              // sits here and not at the foot of the form because it changes
              // which dates the picker below will even offer.
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      value: _isHistorical,
                      onChanged: _isLoading ? null : _setHistorical,
                      secondary: const Icon(Icons.history),
                      title: Text(l10n.historicalMatchToggleLabel),
                    ),
                    if (_isHistorical)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          Layout.cardInner,
                          0,
                          Layout.cardInner,
                          Layout.cardInner,
                        ),
                        child: Text(
                          l10n.historicalMatchToggleNote,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Layout.cardGap),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: Text(l10n.dateLabel),
                      subtitle: Text(_date == null
                          ? '—'
                          : DateFormat.yMMMEd(locale).format(_date!)),
                      onTap: _pickDate,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: Text(l10n.startTimeLabel),
                      subtitle: Text(_startTime?.format(context) ?? '—'),
                      onTap: () => _pickTime(isStart: true),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: Text(l10n.endTimeLabel),
                      subtitle: Text(_endTime?.format(context) ?? '—'),
                      onTap: () => _pickTime(isStart: false),
                    ),
                    if (_isHistorical) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(Layout.cardInner),
                        child: Text(
                          l10n.historicalMatchDateNote,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Layout.cardGap),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Layout.cardInner),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _startingPlayersController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.startingPlayersLabel,
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          // 4 is the approved OP-2 minimum match size (2 v 2),
                          // the same bound the database and update_match enforce.
                          final parsed = int.tryParse(value ?? '');
                          if (parsed == null || parsed < 4 || parsed > 30) {
                            return l10n.startingPlayersInvalid;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: Gap.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => _stepStartingPlayers(-2),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.square(Layout.tapMin),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Icon(Icons.remove, size: 19),
                          ),
                          const SizedBox(width: Gap.sm),
                          FilledButton(
                            onPressed: () => _stepStartingPlayers(2),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.square(Layout.tapMin),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Icon(Icons.add, size: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: Gap.md),
                      SegmentedCapacityIndicator(
                        registered: 0,
                        starting: int.tryParse(
                              _startingPlayersController.text,
                            ) ??
                            0,
                        reserve: AppSettings.reservePlayers,
                        showLabel: false,
                      ),
                      const SizedBox(height: Gap.sm),
                      // Maximum registration is derived, never entered.
                      Text(
                        l10n.capacityAutoNote(
                          AppSettings.reservePlayers,
                          AppSettings.maxRegistrationFor(
                            int.tryParse(_startingPlayersController.text) ?? 0,
                          ),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: ClubActionBar(
        child: FilledButton(
          onPressed: _isLoading ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(Layout.buttonHeight),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isHistorical
                  ? l10n.recordHistoricalMatchButton
                  : l10n.createMatchButton),
        ),
      ),
    );
  }
}
