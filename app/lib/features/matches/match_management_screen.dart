import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'edit_match_screen.dart';
import 'manage_roster_screen.dart';
import 'match_card.dart';
import 'match_models.dart';
import 'match_service.dart';

/// Organizer-only hub for managing a match. Reachable only by the creator.
class MatchManagementScreen extends StatefulWidget {
  const MatchManagementScreen({super.key, required this.matchId});

  final String matchId;

  @override
  State<MatchManagementScreen> createState() => _MatchManagementScreenState();
}

class _MatchManagementScreenState extends State<MatchManagementScreen> {
  final _service = MatchService();
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

  String _manageError(AppLocalizations l10n, Object e) {
    if (e is ManageException) {
      return switch (e.error) {
        ManageError.matchCompleted => l10n.errMatchCompleted,
        ManageError.notOrganizer => l10n.errNotOrganizer,
        ManageError.maxBelowRegistered => l10n.errMaxBelowRegistered,
        ManageError.invalidCapacity => l10n.capacityInvalid,
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
    setState(() => _busy = true);
    try {
      await _service.deleteMatch(widget.matchId);
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
          SnackBar(content: Text(_manageError(l10n, e))));
    }
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
      RegistrationStatus filter, String title) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManageRosterScreen(
          matchId: widget.matchId,
          filter: filter,
          title: title,
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
        appBar: AppBar(
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
            // Completed matches are read-only; anything else can be managed
            // and deleted (registered players are notified on delete).
            final canModify = !match.isCompleted && !_busy;
            final canDelete = canModify;

            return ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(match.displayName),
                  subtitle: Text(
                      '${matchStatusLabelValue(l10n, match.effectiveStatus)} • '
                      '$total/${match.maxRegistration}'),
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
                          l10n.managePlayersTitle)
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.hourglass_top),
                  title: Text(l10n.manageReserveTitle),
                  enabled: !_busy,
                  onTap: !_busy
                      ? () => _openRoster(RegistrationStatus.reserve,
                          l10n.manageReserveTitle)
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
