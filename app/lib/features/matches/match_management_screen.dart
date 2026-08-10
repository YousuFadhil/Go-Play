import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/diagnostics.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import 'edit_match_screen.dart';
import 'manage_roster_screen.dart';
import 'match_card.dart';
import 'match_models.dart';
import 'match_service.dart';

/// Organizer-only hub for managing a match. Reachable only by the creator.
class MatchManagementScreen extends StatefulWidget {
  const MatchManagementScreen({
    super.key,
    required this.matchId,
    this.matchService,
  });

  final String matchId;

  /// Supplied only by tests, exactly as every other screen takes an optional
  /// port. Without it this screen built its own `MatchService` — and so reached
  /// the data provider from a widget test, which is why the delete flow had no
  /// coverage between the RPC and what the user is shown.
  final MatchService? matchService;

  @override
  State<MatchManagementScreen> createState() => _MatchManagementScreenState();
}

class _MatchManagementScreenState extends State<MatchManagementScreen> {
  late final MatchService _service = widget.matchService ?? MatchService();
  late Future<(Match, List<MatchRegistration>)> _future;
  bool _busy = false;

  /// Set when an action changed the match, so callers can refresh/pop.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Match, List<MatchRegistration>)> _load() async {
    final results = await Future.wait([
      _service.fetchMatch(widget.matchId),
      _service.fetchRegistrations(widget.matchId),
    ]);
    return (results[0] as Match, results[1] as List<MatchRegistration>);
  }

  void _reload() => setState(() => _future = _load());

  /// The sentence a refused management action gets.
  ///
  /// While `Diagnostics.verboseErrors` is on the chosen sentence is replaced by
  /// the failure itself and the provider message behind it. That is a
  /// development instrument and nothing else: the branch below is unchanged, so
  /// what the screen *does* still follows the failure type exactly as `OP-5`
  /// requires, and a release build without the flag shows the sentence.
  String _manageError(AppLocalizations l10n, Object e) =>
      Diagnostics.describe(e, _manageSentence(l10n, e));

  String _manageSentence(AppLocalizations l10n, Object e) {
    if (e is AuthorizationFailure) return l10n.errNotAuthorized;
    if (e is Failure) {
      return switch (e.reason) {
        FailureReason.matchCompleted => l10n.errMatchCompleted,
        FailureReason.matchLocked => l10n.errMatchLocked,
        FailureReason.maxBelowRegistered => l10n.errMaxBelowRegistered,
        FailureReason.invalidStartingPlayers => l10n.startingPlayersInvalid,
        _ => l10n.genericError,
      };
    }
    return l10n.genericError;
  }

  Future<bool> _confirm(String title, String body, String confirmLabel,
      {bool destructive = false}) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _deleteMatch() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirm(l10n.deleteMatchConfirmTitle,
        l10n.deleteMatchConfirmBody, l10n.deleteMatchButton,
        destructive: true);
    if (!ok) return;

    // Forgotten first, so a message shown for this attempt cannot be text left
    // over from an earlier one.
    Diagnostics.clear();
    Diagnostics.trace('screen', 'delete ${widget.matchId}');
    setState(() => _busy = true);
    try {
      await _service.deleteMatch(widget.matchId);
    } catch (e) {
      Diagnostics.trace('screen', 'delete failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(_manageError(l10n, e))));
      return;
    }

    // Outside the try on purpose. Leaving this screen is not part of deleting
    // the match, and while it sat inside the catch a pop that threw — on a
    // Navigator the dialog above had already changed — reported the delete as
    // failed after it had succeeded.
    Diagnostics.trace('screen', 'delete ok, leaving');
    if (!mounted) return;
    navigator.pop(true);
  }

  Future<void> _edit(Match match) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditMatchScreen(match: match)),
    );
    if (saved == true) {
      _changed = true;
      _reload();
    }
  }

  Future<void> _openRoster(
      RegistrationStatus filter, String title, bool canRemove) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManageRosterScreen(
          matchId: widget.matchId,
          filter: filter,
          title: title,
          canRemove: canRemove,
        ),
      ),
    );
    if (changed == true) {
      _changed = true;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        appBar: AppHeader(
          title: Text(l10n.matchManagementTitle),
          leading: BackButton(
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: FutureBuilder<(Match, List<MatchRegistration>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.loadFailed),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: _reload, child: Text(l10n.retryButton)),
                  ],
                ),
              );
            }

            final (match, registrations) = snapshot.data!;
            final total = registrations.length;
            // The match locks at kickoff and stays locked until it completes,
            // so roster/detail changes are only possible before the start.
            final canModify = match.isOpenForChanges && !_busy;
            // Deletion is time-independent; it will be restricted only once
            // matches can become historical (results, stats, ratings...).
            final canDelete = !_busy;

            return ListView(
              children: [
                ListTile(
                  leading: Icon(
                      match.isLocked ? Icons.lock_outline : Icons.info_outline),
                  title: Text(match.displayName),
                  subtitle: Text(
                      '${matchStatusLabelValue(l10n, match.effectiveStatus)} • '
                      '$total/${match.maxRegistration}'),
                ),
                if (match.isLocked)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(l10n.matchLockedNote,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(l10n.editMatchTitle),
                  enabled: canModify,
                  onTap: canModify ? () => _edit(match) : null,
                ),
                ListTile(
                  leading: const Icon(Icons.groups),
                  title: Text(l10n.managePlayersTitle),
                  enabled: !_busy,
                  onTap: !_busy
                      ? () => _openRoster(RegistrationStatus.confirmed,
                          l10n.managePlayersTitle, canModify)
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.hourglass_top),
                  title: Text(l10n.manageReserveTitle),
                  enabled: !_busy,
                  onTap: !_busy
                      ? () => _openRoster(RegistrationStatus.reserve,
                          l10n.manageReserveTitle, canModify)
                      : null,
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.delete_forever,
                      color: canDelete
                          ? Theme.of(context).colorScheme.error
                          : null),
                  title: Text(l10n.deleteMatchButton),
                  subtitle: Text(l10n.deleteMatchHint),
                  enabled: canDelete,
                  onTap: canDelete ? _deleteMatch : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
