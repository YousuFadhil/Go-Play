import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../communities/community_models.dart';
import '../profile/player_identity.dart';
import '../members/member_repository.dart';
import 'match_card.dart';
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
    this.canManageGuests = false,
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
  ///
  /// This governs **community players only**. Professional Guests are managed
  /// under [canManageGuests], which the lock does not touch.
  final bool canRemove;

  /// Whether the reader may add, rename and remove Professional Guests.
  ///
  /// Deliberately separate from [canRemove]: the approved rule is that an owner
  /// or admin manages guests in *every* match state, including locked and
  /// completed, and the database enforces exactly that. Folding the two
  /// together would hide a control the server would have honoured.
  final bool canManageGuests;

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
      positionLabelValue(l10n, position);

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

  /// The database's refusal for a Professional Guest operation.
  ///
  /// The same shape `_addErrorMessage` has, and for the same reason: the codes
  /// are the ones migration `0047` raises, and only the wording is chosen here.
  String _guestErrorMessage(AppLocalizations l10n, Failure failure) =>
      switch (failure.reason) {
        FailureReason.invalidGuestName => l10n.errInvalidGuestName,
        FailureReason.guestNotFound => l10n.errGuestNotFound,
        FailureReason.registrationClosed => l10n.errRegistrationClosed,
        _ => failure is AuthorizationFailure
            ? l10n.errNotAuthorized
            : l10n.guestActionFailed,
      };

  /// Asks for a guest's name. Returns the trimmed name, or null if cancelled.
  ///
  /// The 2–60 bound is the one the database states; asking here means a
  /// mistyped name is caught before a round trip, and the server still refuses
  /// it if this check is ever wrong.
  Future<String?> _askGuestName(
    String title,
    String confirmLabel, {
    String? initial,
  }) {
    final l10n = context.l10n;
    final controller = TextEditingController(text: initial ?? '');
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('guestNameField'),
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l10n.guestNameLabel),
            validator: (value) {
              final name = (value ?? '').trim();
              return name.length < 2 || name.length > 60
                  ? l10n.guestNameInvalid
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            key: const Key('guestNameSubmit'),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// Re-reads the roster and waits for it, so a caller can act on what came
  /// back rather than on what was on screen before.
  Future<void> _refresh() async {
    final future = _load();
    // Block-bodied for the reason `_reload` states: an arrow body hands
    // `setState` a closure whose value is the assigned Future, which the
    // framework rejects outright.
    if (mounted) {
      setState(() {
        _future = future;
      });
    }
    // Awaited even when unmounted: `_load` is what refreshes
    // `_allRegistrations`, and a caller reading it next must not see the
    // previous roster.
    await future;
  }

  /// Runs a guest mutation and reloads the roster from the server afterwards.
  /// Returns whether the mutation succeeded.
  ///
  /// The reload is the point, not a courtesy. Adding or removing a guest can
  /// promote a community reserve, displace another guest, or change the
  /// starting/reserve split — all of which the database decides. Re-reading is
  /// how this screen shows what actually happened instead of a local guess.
  Future<bool> _guestAction(Future<void> Function() action) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      await _refresh();
      return true;
    } on Failure catch (failure) {
      _showMessage(_guestErrorMessage(l10n, failure));
      // Reloaded on refusal too: GUEST_NOT_FOUND usually means the roster moved
      // under this screen, and the next attempt should see the truth.
      await _refresh();
      return false;
    } catch (_) {
      _showMessage(l10n.guestActionFailed);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGuest() async {
    final l10n = context.l10n;
    final name = await _askGuestName(l10n.addGuestTitle, l10n.addGuestButton);
    if (name == null || !mounted) return;

    String? guestId;
    final added = await _guestAction(() async {
      guestId = await _service.addProfessionalGuest(widget.matchId, name);
    });
    if (!added || !mounted) return;

    // Which list they landed in is read back off the refreshed roster, never
    // predicted from the counts that were on screen: capacity, the
    // community-first ordering and the starting/reserve cut are the server's.
    final seat = _allRegistrations
        .where((r) => r.professionalGuestId == guestId)
        .firstOrNull;
    _showMessage(seat?.status == RegistrationStatus.reserve
        ? l10n.guestAddedReserve(name)
        : l10n.guestAddedConfirmed(name));
  }

  Future<void> _renameGuest(MatchRegistration guest) async {
    final name = await _askGuestName(
      context.l10n.renameGuestTitle,
      context.l10n.renameGuestButton,
      initial: guest.fullName,
    );
    if (name == null || !mounted) return;

    await _guestAction(() => _service.renameProfessionalGuest(
          widget.matchId,
          guest.professionalGuestId!,
          name,
        ));
  }

  Future<void> _removeGuest(MatchRegistration guest) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeGuestConfirmTitle),
        content: Text(l10n.removeGuestConfirmBody(guest.fullName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.removeGuestButton),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _guestAction(() => _service.removeProfessionalGuest(
          widget.matchId,
          guest.professionalGuestId!,
        ));
  }

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
      await _service.removePlayer(widget.matchId, player.userId!);
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
    // Guests hold no user id, so they are simply not part of this question.
    final registered = {
      for (final r in _allRegistrations)
        if (r.userId != null) r.userId,
    };
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
      // Two separate actions because they answer to two separate rules: adding
      // a community member is locked at kickoff, adding a Professional Guest
      // never is.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.canManageGuests)
            FloatingActionButton.extended(
              key: const Key('addGuestButton'),
              heroTag: 'addProfessionalGuest',
              onPressed: _busy ? null : _addGuest,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(l10n.addGuestButton),
            ),
          if (widget.canManageGuests && widget.canRemove)
            const SizedBox(height: Gap.sm),
          if (widget.canRemove)
            FloatingActionButton.extended(
              key: const Key('addPlayerButton'),
              heroTag: 'addCommunityPlayer',
              onPressed: _busy ? null : _addPlayer,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(l10n.addPlayerButton),
            ),
        ],
      ),
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
              final scheme = Theme.of(context).colorScheme;
              return ListTile(
                key: p.isProfessionalGuest
                    ? Key('guestTile_${p.professionalGuestId}')
                    : null,
                // The row's own controls are on the right and stay there. The
                // face is the profile control, because a roster row here is
                // already the remove button's row and taking that gesture for
                // navigation would cost an administrator the thing they came
                // for.
                leading: PlayerIdentityTap(
                  key: Key('identity_${p.participantId}'),
                  userId: p.userId,
                  enabled: !_busy,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        child: Text(
                          '${index + 1}',
                          textAlign: TextAlign.end,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      PlayerAvatar(
                        avatarUrl: p.avatarUrl,
                        fullName: p.fullName,
                        isProfessionalGuest: p.isProfessionalGuest,
                      ),
                    ],
                  ),
                ),
                title: Text(participantLabel(l10n, p)),
                subtitle: Text(
                  participantSubtitle(
                    l10n,
                    p,
                    (position) => _positionLabel(l10n, position),
                  ),
                ),
                // A guest is renamed and removed under the guest rule, which the
                // match lock does not reach; a community player is removed under
                // the roster rule, which it does.
                trailing: p.isProfessionalGuest
                    ? (widget.canManageGuests
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('renameGuest_${p.professionalGuestId}'),
                                tooltip: l10n.renameGuestButton,
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: _busy ? null : () => _renameGuest(p),
                              ),
                              IconButton(
                                key: Key('removeGuest_${p.professionalGuestId}'),
                                tooltip: l10n.removeGuestButton,
                                icon: Icon(Icons.person_remove,
                                    color: scheme.error),
                                onPressed: _busy ? null : () => _removeGuest(p),
                              ),
                            ],
                          )
                        : null)
                    : (widget.canRemove
                        ? IconButton(
                            tooltip: l10n.removePlayerButton,
                            icon: Icon(Icons.person_remove, color: scheme.error),
                            onPressed: _busy ? null : () => _remove(p),
                          )
                        : null),
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
                        // No profile navigation here, deliberately: this row's
                        // tap is the selection, and a picker that opened a
                        // profile instead of choosing somebody would be a
                        // picker that does not pick.
                        leading: PlayerAvatar(
                          avatarUrl: m.avatarUrl,
                          fullName: m.fullName,
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
