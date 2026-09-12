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
import '../teams/team_repository.dart';

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
    this.canAddCommunityPlayer = false,
    this.canManageGuests = false,
    this.match,
    this.memberRepository,
    this.service,
    this.teamRepository,
  });

  final String matchId;

  /// The match's community — the only place eligible members can come from.
  final String communityId;

  final RegistrationStatus filter;
  final String title;

  /// False once the match is locked (started) or completed: the roster is
  /// then read-only, and taking somebody out of a match that has been played
  /// would be editing the record of who was in it.
  ///
  /// This governs **community players only**. Professional Guests are managed
  /// under [canManageGuests], which the lock does not touch.
  ///
  /// It no longer governs adding. Removing and adding used to share this one
  /// answer on the reasoning that a roster which cannot be shortened cannot be
  /// lengthened either — which is not a rule the database has ever enforced,
  /// and is not the approved one. See [canAddCommunityPlayer].
  final bool canRemove;

  /// Whether the reader may add a community member who has not registered
  /// themselves.
  ///
  /// Separate from [canRemove] because the two answer to separate rules.
  /// `admin_add_player_to_match` (migration `0045`) calls
  /// `register_player_in_match` with `p_enforce_time_lock => false`: an owner
  /// or admin adds somebody in every ordinary match state, a completed one
  /// included, and the database has allowed exactly that all along. Folding the
  /// answer into [canRemove] hid a control the server would have honoured —
  /// which is what left a completed match offering to add a Professional Guest
  /// but not a community player.
  ///
  /// Everything the server enforces about the player being added still applies
  /// and is still the server's to enforce: community membership, the duplicate
  /// rule, total capacity, the overlap check, and the refusal to register
  /// anybody into a recorded (historical) match.
  final bool canAddCommunityPlayer;

  /// Whether the reader may add, rename and remove Professional Guests.
  ///
  /// Deliberately separate from [canRemove]: the approved rule is that an owner
  /// or admin manages guests in *every* match state, including locked and
  /// completed, and the database enforces exactly that. Folding the two
  /// together would hide a control the server would have honoured.
  final bool canManageGuests;

  /// The match this roster belongs to, as the caller already has it.
  ///
  /// **The match rather than a verdict about it, and that is the point.**
  /// [Match.isCompleted] reads the clock, so this one object keeps answering
  /// correctly while the screen sits open: a roster opened during a match that
  /// has since finished stops offering -- and stops sending -- the operations
  /// that belong to a match still in progress. A boolean computed when the
  /// screen opened could not do that, and the ordinary roster functions have no
  /// completion guard of their own to fall back on.
  ///
  /// Null only in older call sites and tests that describe a match still to
  /// come, where every roster operation is the right one anyway.
  final Match? match;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final MemberRepository? memberRepository;
  final MatchService? service;
  final TeamRepository? teamRepository;

  @override
  State<ManageRosterScreen> createState() => _ManageRosterScreenState();
}

class _ManageRosterScreenState extends State<ManageRosterScreen> {
  late final MatchService _service = widget.service ?? MatchService();
  late final MemberRepository _members =
      widget.memberRepository ?? MemberRepository();
  late final TeamRepository _teams = widget.teamRepository ?? TeamRepository();
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

  /// Whether the match has been played, asked of the clock at the moment of
  /// asking rather than when this screen opened.
  ///
  /// The widget's permissions say what this reader may do to a roster; this says
  /// whether what is in front of them is still a roster or has become a record.
  /// Both have to hold, and only this one changes while the screen is open.
  bool get _played => widget.match?.isCompleted ?? false;

  /// Whether the match has started, by the same clock.
  bool get _started => widget.match?.isLocked ?? false;

  /// Whether the factual lineup has been read for this load.
  bool _lineupLoaded = false;

  /// The Professional Guests this match's stored lineup actually holds, by id.
  ///
  /// **The authoritative question about a played match, and the only one.** After
  /// completion a guest is a participant because `match_team_assignments` says
  /// so -- not because their registration is confirmed, not because of where they
  /// sit in `registration_order`. A guest may hold a confirmed seat and have
  /// played nothing, which is what a historical reserve is; production holds such
  /// rows today and they are legitimate.
  ///
  /// Read once per load of this screen and only for a played match, because it is
  /// only there that it decides anything. Empty before completion, where nothing
  /// consults it.
  Set<String> _playedGuestIds = const {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MatchRegistration>> _load() async {
    final all = await _service.fetchRegistrations(widget.matchId);
    _allRegistrations = all;
    // One read, not one per row, and only where the answer can be needed: a
    // played match's guest removals are decided by the factual lineup, and a
    // match that has merely started may become one while this screen is open.
    if (_played || _started) await _loadPlayedGuestIds();
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

  /// Reads which guests the stored lineup names.
  ///
  /// Separate from [_load] so the rare case can be covered too: a match that was
  /// still to come when the screen opened and finished while it stayed open,
  /// where no read happened because none could have been needed yet.
  Future<void> _loadPlayedGuestIds() async {
    final lineup = await _teams.fetchLineup(widget.matchId);
    _playedGuestIds = {
      for (final assignment in lineup)
        if (assignment.professionalGuestId != null)
          assignment.professionalGuestId!,
    };
    _lineupLoaded = true;
  }

  /// Whether the ordinary roster may still be administered.
  ///
  /// The permission the caller computed, **and** a match that has not become a
  /// record since. Used for the controls and again inside every handler, so a
  /// stale screen cannot send what it would no longer be allowed to offer.
  bool get _mayAdministerRoster => widget.canRemove && !_played;

  bool get _mayAddCommunityPlayer => widget.canAddCommunityPlayer && !_played;

  bool get _mayAddGuest => widget.canManageGuests && !_played;

  /// Refuses an action the match has outgrown since the screen was built.
  ///
  /// Returns true when the caller must stop. The screen reloads so what is shown
  /// catches up with the match that has since finished, and the organizer is
  /// told why nothing happened -- the same shape the Teams screen uses for the
  /// generation it can no longer offer, and the same sentence the database would
  /// give for a refusal of this kind. The server stays the final authority for a
  /// race that lands after this check.
  bool _refuseIfPlayed(AppLocalizations l10n) {
    if (!_played) return false;
    _showMessage(l10n.errMatchCompleted);
    _reload();
    return true;
  }

  /// Whether this guest may be taken off the roster from here.
  ///
  /// Up to completion, yes: that is what the roster removal is for. Afterwards
  /// only if the stored lineup does not name them -- a guest who did not play is
  /// a roster row and nothing more, and production holds plenty of them. A guest
  /// the lineup does name is a recorded participant, and the removal that
  /// understands that lives on the Teams screen.
  bool _mayRemoveFromRoster(MatchRegistration participant) {
    if (!_played) return true;
    final guestId = participant.professionalGuestId;
    return guestId != null && !_playedGuestIds.contains(guestId);
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
    if (_refuseIfPlayed(l10n)) return;
    final name = await _askGuestName(l10n.addGuestTitle, l10n.addGuestButton);
    if (name == null || !mounted) return;
    // Asked again after the dialog: the name was typed while the clock ran, and
    // `add_professional_guest` on a played match seats a guest the factual
    // lineup never hears about -- which is what `add_played_professional_guest`
    // exists to do properly, from the Teams screen.
    if (_refuseIfPlayed(l10n)) return;

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
    // A guest the stored lineup names is a recorded participant: this removal
    // would free their seat and leave the lineup row standing. The Teams
    // screen's historical removal takes both, with the guard that protects a
    // recorded scorer or best player. The lineup is read here when the match
    // finished after this screen opened and no read had been needed yet.
    if (_played && !_lineupLoaded) {
      await _loadPlayedGuestIds();
      if (!mounted) return;
    }
    if (!_mayRemoveFromRoster(guest)) {
      _showMessage(l10n.errMatchCompleted);
      _reload();
      return;
    }
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
    // `remove_player` has no completion guard of its own: it would delete the
    // seat, promote a reserve and notify them both about a match that is over,
    // while the player stayed in the recorded lineup. Who played a completed
    // match is corrected from the Teams screen instead.
    if (_refuseIfPlayed(l10n)) return;
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

  /// Adds everybody the organizer picked, one canonical call each.
  ///
  /// The picker opens once and closes once. Adding six players used to mean six
  /// trips through it — pick, confirm, add, reload, reopen — and the per-player
  /// confirmation is gone with it: the count on the button is the confirmation,
  /// and it is asked before the batch rather than six times during it.
  ///
  /// **Sequential, deliberately.** Every addition still goes through
  /// `MatchService.addPlayerToMatch` → `admin_add_player_to_match` →
  /// `register_player_in_match`, so membership, the duplicate rule, capacity,
  /// the overlap check, the historical guard and the confirmed/reserve decision
  /// are all still the database's and all still applied per player. Firing them
  /// at once would race exactly the check that decides the last seat: two
  /// additions could both read a roster with one place left. In order, each one
  /// sees what the one before it did.
  ///
  /// **Partial success is the expected outcome, not an error.** A player with a
  /// clashing match is refused while the other five are added, and the five
  /// stand — there is no batch to roll back, because there was never a batch in
  /// the database, only five accepted registrations. What each refusal *said*
  /// is kept and shown, deduplicated, rather than one SnackBar per failure.
  Future<void> _addPlayers() async {
    final l10n = context.l10n;
    if (_refuseIfPlayed(l10n)) return;
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AddPlayerSheet(
        title: l10n.addPlayerButton,
        emptyMessage: l10n.addPlayerEmpty,
        load: () async =>
            _eligible(await _members.fetchMembers(widget.communityId)),
        positionLabel: (position) => _positionLabel(l10n, position),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    // The sheet was open while the clock ran. `admin_add_player_to_match` turns
    // the time lock off deliberately, so the database would accept these onto a
    // match that has since finished -- as registrations with no factual lineup
    // row, which is the state this feature exists to stop producing.
    if (_refuseIfPlayed(l10n)) return;

    setState(() => _busy = true);

    final added = <RegistrationStatus>[];

    // **Two separate quantities, and they are not the same number.** How many
    // players were refused is one count; how many different things there are to
    // say about it is another. Three players refused for the same clash are
    // three failures and one sentence — counting the sentences would have
    // reported one, which is untrue about the roster and about what the
    // organizer has left to do.
    var failed = 0;
    // Insertion-ordered and de-duplicated, for the *wording* only: two players
    // refused for the same reason say it once.
    final reasons = <String>{};

    for (final userId in picked) {
      try {
        added.add(await _service.addPlayerToMatch(widget.matchId, userId));
      } on Failure catch (failure) {
        failed++;
        reasons.add(_addErrorMessage(l10n, failure));
      } catch (_) {
        failed++;
        reasons.add(l10n.addPlayerFailed);
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (added.isNotEmpty) _changed = true;

    _showMessage(_batchSummary(l10n, added, failed, reasons));

    // Once, after the batch, rather than after each player. A stale picker is
    // still the server's to refuse, and this is what lets the next attempt see
    // what the batch actually did.
    _reload();
  }

  /// What the batch did, in one sentence plus what was refused.
  ///
  /// [failed] is a count of **players**; [reasons] is the set of distinct
  /// sentences explaining why. The counts in the summary come from the former
  /// and the wording from the latter, so five players refused for one reason
  /// read as five failures and one explanation.
  String _batchSummary(
    AppLocalizations l10n,
    List<RegistrationStatus> added,
    int failed,
    Set<String> reasons,
  ) {
    final explanation = reasons.join(' ');
    if (added.isEmpty) {
      return '${l10n.playersAddedNone(failed)} $explanation'.trim();
    }
    if (failed == 0) {
      // How many, and not which list each landed in. That is the server's
      // answer and it is already on screen: the reload below puts each of them
      // under Players or under Reserve, which says it better than a sentence
      // summarising a split would.
      return l10n.playersAddedSummary(added.length);
    }
    return '${l10n.playersAddedPartial(added.length, failed)} $explanation'
        .trim();
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
      // Two separate actions because they answer to two separate rules — but
      // both are now the *same* rule about state: an owner or admin adds either
      // kind of participant in every ordinary match state. What still separates
      // them is who they are, not when it is.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_mayAddGuest)
            FloatingActionButton.extended(
              key: const Key('addGuestButton'),
              heroTag: 'addProfessionalGuest',
              onPressed: _busy ? null : _addGuest,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(l10n.addGuestButton),
            ),
          if (_mayAddGuest && _mayAddCommunityPlayer)
            const SizedBox(height: Gap.sm),
          if (_mayAddCommunityPlayer)
            FloatingActionButton.extended(
              key: const Key('addPlayerButton'),
              heroTag: 'addCommunityPlayer',
              onPressed: _busy ? null : _addPlayers,
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
                              // Before completion, the roster removal is the
                              // right one for any guest. After it, only for a
                              // guest the factual lineup does not hold: taking
                              // one who played off the roster here would free a
                              // seat and leave their lineup row standing, which
                              // is what `remove_played_professional_guest` on
                              // the Teams screen exists to do properly -- with
                              // the scorer and best-player guard that protects
                              // the recorded result.
                              if (_mayRemoveFromRoster(p))
                                IconButton(
                                  key: Key(
                                      'removeGuest_${p.professionalGuestId}'),
                                  tooltip: l10n.removeGuestButton,
                                  icon: Icon(Icons.person_remove,
                                      color: scheme.error),
                                  onPressed:
                                      _busy ? null : () => _removeGuest(p),
                                ),
                            ],
                          )
                        : null)
                    : (_mayAdministerRoster
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

  /// Who is chosen, by user id.
  ///
  /// Ids rather than members so the set survives a reload of the list without
  /// having to match objects, and so the order below is the list's order rather
  /// than the order things were tapped in — the batch is sent in the order the
  /// organizer sees, which is what makes the reserve outcome predictable.
  final _selected = <String>{};

  void _toggle(String userId) => setState(() {
        if (!_selected.remove(userId)) _selected.add(userId);
      });

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
                      final selected = _selected.contains(m.userId);
                      return ListTile(
                        // No profile navigation here, deliberately: this row's
                        // tap is the selection, and a picker that opened a
                        // profile instead of choosing somebody would be a
                        // picker that does not pick.
                        //
                        // The avatar, the name and the position are as they
                        // were. What is new is that the row remembers being
                        // chosen instead of closing the sheet.
                        leading: PlayerAvatar(
                          avatarUrl: m.avatarUrl,
                          fullName: m.fullName,
                        ),
                        title: Text(m.fullName),
                        subtitle: Text(widget.positionLabel(m.position)),
                        selected: selected,
                        trailing: Checkbox(
                          key: Key('pick_${m.userId}'),
                          value: selected,
                          onChanged: (_) => _toggle(m.userId),
                        ),
                        onTap: () => _toggle(m.userId),
                      );
                    },
                  );
                },
              ),
            ),
            // One tap starts the batch, and it says how many it is about to
            // add. Disabled until something is chosen, so the sheet cannot send
            // an empty batch.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('addSelectedPlayersButton'),
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                              _selected.toList(growable: false),
                            ),
                    child: Text(
                      context.l10n.addSelectedPlayersButton(_selected.length),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
