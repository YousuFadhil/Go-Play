import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/l10n.dart';
import 'match_models.dart';
import 'match_service.dart';

/// Organizer view of a match roster (confirmed players or reserve list),
/// with the ability to remove a player. Removing a confirmed player promotes
/// the first reserve automatically (handled server-side).
class ManageRosterScreen extends StatefulWidget {
  const ManageRosterScreen({
    super.key,
    required this.matchId,
    required this.filter,
    required this.title,
    required this.canRemove,
  });

  final String matchId;
  final RegistrationStatus filter;
  final String title;

  /// False once the match is locked (started) or completed: the roster is
  /// then read-only.
  final bool canRemove;

  @override
  State<ManageRosterScreen> createState() => _ManageRosterScreenState();
}

class _ManageRosterScreenState extends State<ManageRosterScreen> {
  final _service = MatchService();
  late Future<List<MatchRegistration>> _future;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MatchRegistration>> _load() async {
    final all = await _service.fetchRegistrations(widget.matchId);
    return [
      for (final r in all)
        if (r.status == widget.filter) r
    ];
  }

  void _reload() => setState(() => _future = _load());

  String _positionLabel(AppLocalizations l10n, String position) =>
      switch (position) {
        'GK' => l10n.positionGk,
        'DEF' => l10n.positionDef,
        'MID' => l10n.positionMid,
        'FWD' => l10n.positionFwd,
        _ => position,
      };

  Future<void> _remove(MatchRegistration player) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removePlayerConfirmTitle),
        content: Text(l10n.removePlayerConfirmBody(player.fullName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.removePlayerButton),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _service.removePlayer(widget.matchId, player.userId);
      _changed = true;
      _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.genericError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(
        title: Text(widget.title),
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(_changed),
        ),
      ),
      body: FutureBuilder<List<MatchRegistration>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
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

          final players = snapshot.data ?? const [];
          if (players.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.rosterEmpty, textAlign: TextAlign.center),
              ),
            );
          }

          return ListView.builder(
            itemCount: players.length,
            itemBuilder: (context, index) {
              final p = players[index];
              return ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(p.fullName),
                subtitle: Text(_positionLabel(l10n, p.position)),
                trailing: widget.canRemove
                    ? IconButton(
                        tooltip: l10n.removePlayerButton,
                        icon: Icon(Icons.person_remove,
                            color: Theme.of(context).colorScheme.error),
                        onPressed: _busy ? null : () => _remove(p),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
