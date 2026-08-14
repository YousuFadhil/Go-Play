import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../communities/community_models.dart';
import '../members/member_repository.dart';
import 'match_models.dart';
import 'match_service.dart';

/// Organizer view of a match roster (confirmed players or reserve list),
/// with the ability to remove a player. Removing a confirmed player promotes
/// the first reserve automatically (handled server-side).
///
/// It is also where an owner/admin adds a member who has not registered
/// themselves. That belongs here rather than on Match Details because this is
/// already the roster-editing screen: it is reached only through the
/// admin-gated management hub, it already removes players, and it already
/// reports back whether anything changed.
class ManageRosterScreen extends StatefulWidget {
  const ManageRosterScreen({
    super.key,
    required this.matchId,
    required this.communityId,
    required this.filter,
    required this.title,
    required this.canRemove,
    this.memberRepository,
    this.service,
  });

  final String matchId;

  /// The match's community — the only place eligible members can come from.
  final String communityId;

  final RegistrationStatus filter;
  final String title;

  /// False once the match is locked (started) or completed: the roster is
  /// then read-only. The same answer governs adding, because a roster that
  /// cannot be shortened cannot be lengthened either.
  final bool canRemove;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final MemberRepository? memberRepository;
  final MatchService? service;

  @override
  State<ManageRosterScreen> createState() => _ManageRosterScreenState();
}

class _ManageRosterScreenState extends State<ManageRosterScreen> {
  late final MatchService _service = widget.service ?? MatchService();
  late final MemberRepository _members =
      widget.memberRepository ?? MemberRepository();
  late Future<List<MatchRegistration>> _future;
  bool _busy = false;
  bool _changed = false;

  /// Everyone registered, whichever list they are in.
  ///
  /// Kept alongside the filtered view because the two questions differ: the
  /// list shows one status, while "who may still be added" has to exclude
  /// **both** — a reserve player is registered, and offering them again would
  /// be offering a duplicate the database would refuse.
  List<MatchRegistration> _allRegistrations = const [];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MatchRegistration>> _load() async {
    final all = await _service.fetchRegistrations(widget.matchId);
    _allRegistrations = all;
    return [
      for (final r in all)
        if (r.status == widget.filter) r
    ];
  }

  // Block-bodied on purpose. `setState(() => _future = _load())` hands the
  // framework a closure whose value is the assigned Future, which trips
  // `setState() callback argument returned a Future` in debug. The assignment
  // is the intent; returning it was never meant.
  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  String _positionLabel(AppLocalizations l10n, String position) =>
      switch (position) {
        'GK' => l10n.positionGk,
        'DEF' => l10n.positionDef,
        'MID' => l10n.positionMid,
        'FWD' => l10n.positionFwd,
        _ => position,
      };

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// The database's refusal, said about the player rather than to the reader.
  ///
  /// The existing `err*` strings are second person — "You are already
  /// registered" — which is the wrong sentence when an admin is adding somebody
  /// else. The codes are the same ones registration has always raised; only the
  /// wording differs, so nothing here is a new error taxonomy.
  String _addErrorMessage(AppLocalizations l10n, Failure failure) =>
      switch (failure.reason) {
        FailureReason.alreadyRegistered => l10n.errPlayerAlreadyRegistered,
        FailureReason.overlappingMatch => l10n.errPlayerOverlappingMatch,
        FailureReason.notCommunityMember => l10n.errPlayerNotCommunityMember,
        FailureReason.registrationClosed => l10n.errRegistrationClosed,
        FailureReason.matchClosed => l10n.errMatchClosed,
        FailureReason.matchLocked => l10n.errMatchLocked,
        _ => failure is AuthorizationFailure
            ? l10n.errNotAuthorized
            : l10n.addPlayerFailed,
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

  /// Everyone in the community who is not already in the match.
  ///
  /// This is the whole of the client-side eligibility rule, deliberately.
  /// Membership and "already registered" are answerable from data the screen
  /// already has; overlap, capacity and lifecycle are not, and re-deriving them
  /// here would be a second copy of the registration rules drifting out of step
  /// with the one in the database. The server refuses those, and the refusal is
  /// shown — including when the list went stale between opening and confirming.
  List<CommunityMember> _eligible(List<CommunityMember> members) {
    final registered = {for (final r in _allRegistrations) r.userId};
    return [
      for (final m in members)
        if (!registered.contains(m.userId)) m
    ];
  }

  Future<void> _addPlayer() async {
    final l10n = context.l10n;
    final selected = await showModalBottomSheet<CommunityMember>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AddPlayerSheet(
        title: l10n.addPlayerButton,
        emptyMessage: l10n.addPlayerEmpty,
        load: () async => _eligible(await _members.fetchMembers(widget.communityId)),
        positionLabel: (position) => _positionLabel(l10n, position),
      ),
    );
    if (selected == null || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.addPlayerConfirmTitle),
        content: Text(l10n.addPlayerConfirmBody(selected.fullName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.addPlayerButton),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final status =
          await _service.addPlayerToMatch(widget.matchId, selected.userId);
      _changed = true;
      // Which list they landed in is the server's answer, not a guess from the
      // counts on screen — those may already be stale.
      _showMessage(status == RegistrationStatus.confirmed
          ? l10n.playerAddedConfirmed(selected.fullName)
          : l10n.playerAddedReserve(selected.fullName));
      _reload();
    } on Failure catch (failure) {
      _showMessage(_addErrorMessage(l10n, failure));
      // Reload even on refusal: ALREADY_REGISTERED usually means the roster
      // moved under the picker, and the next attempt should see the truth.
      _reload();
    } catch (_) {
      _showMessage(l10n.addPlayerFailed);
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
      floatingActionButton: widget.canRemove
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _addPlayer,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(l10n.addPlayerButton),
            )
          : null,
      body: FutureBuilder<List<MatchRegistration>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError) {
            return ErrorState(onRetry: _reload);
          }

          final players = snapshot.data ?? const [];
          if (players.isEmpty) {
            return EmptyState(
              icon: Icons.person_outline,
              message: l10n.rosterEmpty,
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

/// The member picker. Loading, error and empty are the screens' existing
/// states, so it looks like the rest of the app rather than like a new system.
class _AddPlayerSheet extends StatefulWidget {
  const _AddPlayerSheet({
    required this.title,
    required this.emptyMessage,
    required this.load,
    required this.positionLabel,
  });

  final String title;
  final String emptyMessage;
  final Future<List<CommunityMember>> Function() load;
  final String Function(String position) positionLabel;

  @override
  State<_AddPlayerSheet> createState() => _AddPlayerSheetState();
}

class _AddPlayerSheetState extends State<_AddPlayerSheet> {
  late Future<List<CommunityMember>> _future = widget.load();

  void _retry() {
    setState(() {
      _future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<CommunityMember>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LoadingState();
                  }
                  if (snapshot.hasError) {
                    return ErrorState(onRetry: _retry);
                  }

                  final members = snapshot.data ?? const [];
                  if (members.isEmpty) {
                    return EmptyState(
                      icon: Icons.person_outline,
                      message: widget.emptyMessage,
                    );
                  }

                  return ListView.builder(
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final m = members[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline, size: 20),
                        ),
                        title: Text(m.fullName),
                        subtitle: Text(widget.positionLabel(m.position)),
                        onTap: () => Navigator.of(context).pop(m),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
