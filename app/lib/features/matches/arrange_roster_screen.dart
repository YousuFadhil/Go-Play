import 'package:flutter/material.dart';

import '../../core/club_task.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../profile/player_identity.dart';
import 'match_card.dart';
import 'match_models.dart';
import 'match_service.dart';

/// The owner/admin arrangement of a match's participants: who starts, who
/// waits, and in what order.
///
/// This is the one screen where the starting list and the reserve list are seen
/// together, because the operations it offers are about the boundary between
/// them. [ManageRosterScreen] keeps its two filtered views — adding, removing
/// and renaming are questions about one list at a time — and nothing about them
/// changes here.
///
/// ## What this screen is allowed to decide
///
/// Nothing. Two operations leave it:
///
///   * an **order** — every participant of the match, exactly once, starting
///     participants first;
///   * a **swap** — two seats exchanging places.
///
/// Neither carries a starting/reserve seat, because neither may. The server
/// derives the split by cutting the order at the match's starting-player count,
/// so a full starting list cannot gain a participant however the lists are
/// dragged about: reordering inside a list leaves the first `startingPlayers`
/// positions holding the same people, and a swap moves two values without
/// creating one.
///
/// ## Professional Guests
///
/// A guest is a seat like any other here, which is the point. They can be moved
/// into the starting list by swapping them with a community player, and once an
/// administrator has done so nothing displaces them automatically — not a
/// community player waiting on the reserve, and not a withdrawal from the
/// starting list, which fills the seat it actually vacated. All of that is the
/// database's; this screen only offers the move.
///
/// A guest never reaches team generation from here. Moving one between the
/// lists is a roster change, and the server's existing reconciliation decides
/// what it means for a stored lineup.
class ArrangeRosterScreen extends StatefulWidget {
  const ArrangeRosterScreen({
    super.key,
    required this.matchId,
    this.service,
  });

  final String matchId;

  /// Supplied only by tests, exactly as every other screen takes an optional
  /// port.
  final MatchService? service;

  @override
  State<ArrangeRosterScreen> createState() => _ArrangeRosterScreenState();
}

class _ArrangeRosterScreenState extends State<ArrangeRosterScreen> {
  late final MatchService _service = widget.service ?? MatchService();
  late Future<(Match, List<MatchRegistration>)> _future;

  /// The two lists as drawn. They are a *rendering* of what the server last
  /// returned, split by the status it wrote and kept in the order it sent —
  /// never a second opinion about either. A drag rearranges them so the tile
  /// lands where it was dropped, and the reload that follows replaces them
  /// with the server's answer whether it agrees or not.
  List<MatchRegistration> _starting = const [];
  List<MatchRegistration> _reserve = const [];

  /// The seat waiting for a partner to swap with, if any. Tap-to-swap exists
  /// alongside drag-to-swap because the same operation has to be reachable
  /// without a pointer that can hold a drag.
  String? _selectedId;

  bool _busy = false;
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
    final match = results[0] as Match;
    final roster = results[1] as List<MatchRegistration>;
    // Split by the status the server wrote, in the order it sent. A played
    // match can legitimately hold more confirmed participants than it has
    // starting slots — `set_completed_match_player` says so — and that is shown
    // as it is rather than cut to fit.
    _starting = [
      for (final r in roster)
        if (r.status == RegistrationStatus.confirmed) r
    ];
    _reserve = [
      for (final r in roster)
        if (r.status == RegistrationStatus.reserve) r
    ];
    return (match, roster);
  }

  // Block-bodied for the reason the other roster screens state: an arrow body
  // hands `setState` a closure whose value is the assigned Future, which the
  // framework rejects outright.
  Future<void> _refresh() async {
    final future = _load();
    if (mounted) {
      setState(() {
        _future = future;
      });
    }
    await future;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// The database's refusal, worded.
  ///
  /// `ROSTER_MISMATCH` is the one that carries real information: the order sent
  /// named every participant the arranger could see, and the server's
  /// participants are no longer that set. Somebody registered, somebody
  /// withdrew, or another administrator arranged it first — and the order was
  /// refused rather than applied to a roster nobody looked at.
  String _errorMessage(AppLocalizations l10n, Failure failure) =>
      switch (failure.reason) {
        FailureReason.rosterChanged => l10n.errRosterChanged,
        FailureReason.invalidSwap => l10n.errInvalidSwap,
        FailureReason.matchNotFound => l10n.genericError,
        _ => failure is AuthorizationFailure
            ? l10n.errNotAuthorized
            : l10n.genericError,
      };

  /// Runs one arrangement and re-reads the roster afterwards, refusal or not.
  ///
  /// The reload is the point rather than a courtesy: an arrangement can promote
  /// somebody, demote somebody, move a guest on or off the pitch and clear a
  /// stored lineup, and every one of those is the server's decision. Re-reading
  /// is how this screen shows what happened instead of what it asked for.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      await _refresh();
      _showMessage(l10n.arrangeSaved);
    } on Failure catch (failure) {
      _showMessage(_errorMessage(l10n, failure));
      await _refresh();
    } catch (_) {
      _showMessage(l10n.genericError);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Every seat of the match exactly once, starting participants first. This is
  /// the whole of what an order operation sends, and the server checks it
  /// against its own participants before it writes anything.
  List<String> get _wholeOrder => [
        for (final r in _starting) r.registrationId,
        for (final r in _reserve) r.registrationId,
      ];

  /// [newIndex] is the destination in the list as it will be, which is what
  /// `onReorderItem` reports: it has already been adjusted for the item being
  /// lifted out at [oldIndex].
  Future<void> _reorder(bool starting, int oldIndex, int newIndex) async {
    if (_busy) return;
    if (newIndex == oldIndex) return;

    setState(() {
      _selectedId = null;
      final list = starting ? [..._starting] : [..._reserve];
      list.insert(newIndex, list.removeAt(oldIndex));
      if (starting) {
        _starting = list;
      } else {
        _reserve = list;
      }
    });

    await _run(() => _service.setRosterOrder(widget.matchId, _wholeOrder));
  }

  /// Tap-to-swap: the first tap picks a seat, the second names its partner.
  /// Tapping the same seat again puts it back.
  Future<void> _tap(MatchRegistration participant) async {
    if (_busy) return;
    final selected = _selectedId;
    if (selected == null) {
      setState(() => _selectedId = participant.registrationId);
      return;
    }
    if (selected == participant.registrationId) {
      setState(() => _selectedId = null);
      return;
    }
    await _swap(selected, participant.registrationId);
  }

  Future<void> _swap(String first, String second) async {
    if (first == second) return;
    setState(() => _selectedId = null);
    await _run(() => _service.swapParticipants(widget.matchId, first, second));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: ClubTaskBar(
        title: l10n.arrangeRosterTitle,
        onBack: () => Navigator.of(context).pop(_changed),
      ),
      body: FutureBuilder<(Match, List<MatchRegistration>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ClubTaskBody(child: LoadingState());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ClubTaskBody(child: ErrorState(onRetry: () {
              setState(() {
                _future = _load();
              });
            }));
          }

          final (match, roster) = snapshot.data!;
          if (roster.isEmpty) {
            return ClubTaskBody(child: EmptyState(
              icon: Icons.person_outline,
              message: l10n.rosterEmpty,
            ));
          }

          return ClubTaskBody(
            padding: const EdgeInsetsDirectional.only(bottom: Gap.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ModeCard(match: match),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    kPageMargin, Gap.sm, kPageMargin, Gap.sm),
                child: Text(
                  l10n.arrangeRosterHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              if (_selectedId != null) _selectionBanner(l10n),
              _sectionHeader(
                l10n.arrangeStartingSection(
                    _starting.length, match.startingPlayers),
                Icons.sports_soccer,
              ),
              _list(_starting, starting: true, emptyMessage: l10n.arrangeStartingEmpty),
              _sectionHeader(
                l10n.arrangeReserveSection(_reserve.length),
                Icons.hourglass_top,
              ),
              _list(_reserve, starting: false, emptyMessage: l10n.arrangeReserveEmpty),
            ],
            ),
          );
        },
      ),
    );
  }

  Widget _selectionBanner(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final selected = [..._starting, ..._reserve]
        .where((r) => r.registrationId == _selectedId)
        .firstOrNull;
    if (selected == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          kPageMargin, Gap.xs, kPageMargin, Gap.sm),
      child: Container(
        key: const Key('arrangeSelectionBanner'),
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          children: [
            Icon(Icons.swap_vert, color: scheme.onSecondaryContainer, size: 20),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                l10n.arrangeSelectedHint(participantLabel(l10n, selected)),
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              key: const Key('arrangeClearSelection'),
              onPressed: () => setState(() => _selectedId = null),
              child: Text(l10n.arrangeClearSelection),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          kPageMargin, Gap.lg, kPageMargin, Gap.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: Gap.sm),
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    List<MatchRegistration> participants, {
    required bool starting,
    required String emptyMessage,
  }) {
    if (participants.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: kPageMargin, vertical: Gap.sm),
        child: Text(
          emptyMessage,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return ReorderableListView.builder(
      key: Key(starting ? 'startingList' : 'reserveList'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // The tile body carries a drag of its own — the cross-list swap — so the
      // reorder gesture is given an explicit handle instead of the whole row.
      // Two drags on one widget is the one arrangement that cannot work.
      buildDefaultDragHandles: false,
      itemCount: participants.length,
      onReorderItem: (oldIndex, newIndex) =>
          _reorder(starting, oldIndex, newIndex),
      itemBuilder: (context, index) =>
          _tile(participants[index], index, starting: starting),
    );
  }

  Widget _tile(
    MatchRegistration participant,
    int index, {
    required bool starting,
  }) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedId == participant.registrationId;
    final key = Key('arrangeTile_${participant.registrationId}');

    Widget row({bool highlighted = false}) => Material(
          color: selected
              ? scheme.secondaryContainer
              : highlighted
                  ? scheme.primaryContainer
                  : Colors.transparent,
          child: ListTile(
            onTap: _busy ? null : () => _tap(participant),
            // Every other gesture on this row is already spoken for — the body
            // starts a drag, the row selects for a swap, the handle reorders —
            // so the face is what opens a profile and nothing is taken away to
            // make room for it.
            leading: PlayerIdentityTap(
              key: Key('identity_${participant.participantId}'),
              userId: participant.userId,
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
                    avatarUrl: participant.avatarUrl,
                    fullName: participant.fullName,
                    isProfessionalGuest: participant.isProfessionalGuest,
                  ),
                ],
              ),
            ),
            title: Text(participantLabel(l10n, participant)),
            subtitle: Text(
              participantSubtitle(
                l10n,
                participant,
                (position) => positionLabelValue(l10n, position),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('arrangeSwap_${participant.registrationId}'),
                  tooltip: selected
                      ? l10n.arrangeClearSelection
                      : (_selectedId == null
                          ? l10n.arrangeSelectAction
                          : l10n.arrangeSwapAction),
                  icon: Icon(selected ? Icons.close : Icons.swap_horiz),
                  onPressed: _busy ? null : () => _tap(participant),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: l10n.arrangeReorderHandle,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: Gap.sm),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    // Dropping one participant onto another is the swap, in either direction
    // and across either boundary. The seat ids are what travel, because a seat
    // is what an arrangement is over — a community player and a guest are the
    // same kind of thing to this operation.
    return DragTarget<String>(
      key: key,
      onWillAcceptWithDetails: (details) =>
          !_busy && details.data != participant.registrationId,
      onAcceptWithDetails: (details) =>
          _swap(details.data, participant.registrationId),
      builder: (context, candidate, rejected) => LongPressDraggable<String>(
        data: participant.registrationId,
        maxSimultaneousDrags: _busy ? 0 : 1,
        feedback: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: SizedBox(
            width: MediaQuery.of(context).size.width - (kPageMargin * 2),
            child: row(),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: row()),
        child: row(highlighted: candidate.isNotEmpty),
      ),
    );
  }
}

/// Which ordering the match is under, said plainly and once.
///
/// An arrangement is a state the organizer should be able to see they are in,
/// because it is permanent for the match: after the first change, registration
/// order stops deciding anything and does not come back. Saying so before the
/// first drag is cheaper than explaining it afterwards.
class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final manual = match.rosterOrderMode == RosterOrderMode.manual;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          kPageMargin, Gap.lg, kPageMargin, Gap.xs),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    manual ? Icons.tune : Icons.schedule,
                    color: scheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      manual
                          ? l10n.arrangeModeManual
                          : l10n.arrangeModeRegistration,
                      key: const Key('arrangeModeLabel'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xs),
              Text(
                manual
                    ? l10n.arrangeModeManualHelp
                    : l10n.arrangeModeRegistrationHelp,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              // A played match is arranged like any other — the approved rule is
              // that an owner or admin manages one in every state — but its
              // starting list is a record of who played and is not re-cut. The
              // difference is worth one sentence rather than a disabled screen.
              if (match.isCompleted) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  l10n.arrangeCompletedNote,
                  key: const Key('arrangeCompletedNote'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
