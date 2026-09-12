import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/diagnostics.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import 'arrange_roster_screen.dart';
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

  // Block-bodied on purpose. `setState(() => _future = ...)` hands the
  // framework a closure whose value is the assigned Future, which trips
  // `setState() callback argument returned a Future` in debug. The assignment
  // is the intent; returning it was never meant.
  void _reload() {
    setState(() {
      _future = _load();
    });
  }

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
      RegistrationStatus filter,
      String title,
      bool canRemove,
      bool canAddCommunityPlayer,
      bool canRegisterGuests,
      String communityId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManageRosterScreen(
          matchId: widget.matchId,
          // Unconditional, and not `canRemove`. This screen is already gated on
          // the owner/admin role, and the approved rule is that they manage
          // Professional Guests in every match state — the lock that closes the
          // community roster does not close this.
          canManageGuests: true,
          // The ordinary guest add and removal stop at completion: both are
          // roster operations, and a played match's guests are a record. The
          // Teams screen holds the completed answers -- 0075 writes a guest
          // into the factual lineup, 0059 takes one out. Renaming stays here.
          canRegisterGuests: canRegisterGuests,
          // The same rule about state, for the other kind of participant. It is
          // still not `canRemove`: adding is what the database allows in every
          // ordinary state, removing is what it closes once the match is the
          // record of a match that was played.
          canAddCommunityPlayer: canAddCommunityPlayer,
          // Carried from the match already loaded here rather than re-fetched:
          // the roster screen needs it only to know which community the
          // addable members come from.
          communityId: communityId,
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

  /// Arranging the roster, which is a different question from managing either
  /// list: it is about the boundary between them, so it gets the screen that
  /// shows both.
  ///
  /// Not gated on `canModify`. The approved rule is that an owner or admin
  /// arranges a roster in every match state, and the database enforces exactly
  /// that — a played match keeps its starting list as the record it is, which
  /// is a rule about the outcome and never about who may act.
  Future<void> _arrangeRoster() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ArrangeRosterScreen(matchId: widget.matchId),
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
              return const LoadingState();
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return ErrorState(onRetry: _reload);
            }

            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final (match, registrations) = snapshot.data!;
            final total = registrations.length;
            // CHANGED: the details of a match are editable in every
            // lifecycle state, any number of times, which is the approved
            // contract. `isOpenForChanges` is a question about a *player's*
            // ability to join -- it is false from kickoff onwards -- and using
            // it as the organizer's edit permission is what locked Edit Match
            // out of active and completed matches. Which new times are legal is
            // migration 0074's to answer, and it answers at the database.
            // `_busy` is the only thing that closes this control.
            final canEditDetails = canEditMatchDetails(match, busy: _busy);
            // The ordinary roster path stays a pre-completion one. An owner or
            // admin adds and removes through it while the match is still to
            // come or is being played -- which is new for an active match, and
            // is the approved contract.
            //
            // Once the match is over it is withheld deliberately: who played is
            // then a factual record, and correcting it belongs to the Teams
            // screen's batch path, which reaches
            // `correct_completed_match_players` and recalculates the ratings
            // once. Routing it through the registration functions instead would
            // make the record of who played a side effect of a roster edit.
            final canManageRoster = canAdministerRoster(match, busy: _busy);
            // The same boundary for adding somebody who never registered. The
            // database would still honour `admin_add_player_to_match` on a
            // completed match, and a recorded (historical) one it refuses
            // outright with `MATCH_HISTORICAL`; what decides it here is that a
            // completed match has a canonical correction path of its own.
            final canAddCommunityPlayer =
                canAddCommunityPlayerTo(match, busy: _busy);
            final canRegisterGuests = canAdministerGuestRoster(match);
            // Deletion is time-independent; it will be restricted only once
            // matches can become historical (results, stats, ratings...).
            final canDelete = !_busy;

            return ListView(
              padding: const EdgeInsets.only(bottom: Gap.xxl),
              children: [
                // What is being managed, stated once at the top. An organizer
                // reaches this screen from three places and should not have to
                // remember which match they were looking at.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kPageMargin,
                    Gap.lg,
                    kPageMargin,
                    Gap.sm,
                  ),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.lg),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            match.isLocked
                                ? Icons.lock_outline
                                : Icons.sports_soccer,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: Gap.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  match.displayName,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${matchStatusLabelValue(l10n, match.effectiveStatus)}'
                                  ' • $total/${match.maxRegistration}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                if (match.isLocked) ...[
                                  const SizedBox(height: Gap.sm),
                                  Text(
                                    l10n.matchLockedNote,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SectionCard(
                  padding: EdgeInsets.zero,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(l10n.editMatchTitle),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: canEditDetails,
                      onTap: canEditDetails ? () => _edit(match) : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(l10n.managePlayersTitle),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_busy,
                      onTap: !_busy
                          ? () => _openRoster(
                              RegistrationStatus.confirmed,
                              l10n.managePlayersTitle,
                              canManageRoster,
                              canAddCommunityPlayer,
                              canRegisterGuests,
                              match.communityId)
                          : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.hourglass_top),
                      title: Text(l10n.manageReserveTitle),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_busy,
                      onTap: !_busy
                          ? () => _openRoster(
                              RegistrationStatus.reserve,
                              l10n.manageReserveTitle,
                              canManageRoster,
                              canAddCommunityPlayer,
                              canRegisterGuests,
                              match.communityId)
                          : null,
                    ),
                    ListTile(
                      key: const Key('arrangeRosterEntry'),
                      leading: const Icon(Icons.swap_vert),
                      title: Text(l10n.arrangeRosterTitle),
                      subtitle: Text(l10n.arrangeRosterSubtitle),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_busy,
                      onTap: !_busy ? _arrangeRoster : null,
                    ),
                  ],
                ),
                // Deletion is set apart in its own card, in the error colour,
                // with the consequence written under it. It is the one action
                // here that cannot be undone.
                SectionCard(
                  padding: EdgeInsets.zero,
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.delete_outline,
                        color: canDelete ? scheme.error : null,
                      ),
                      title: Text(
                        l10n.deleteMatchButton,
                        style: canDelete
                            ? TextStyle(color: scheme.error)
                            : null,
                      ),
                      subtitle: Text(l10n.deleteMatchHint),
                      isThreeLine: true,
                      enabled: canDelete,
                      onTap: canDelete ? _deleteMatch : null,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Whether an owner or admin may edit the match's details right now.
///
/// Every lifecycle state, any number of times, which is the approved contract:
/// a future match is a plan, an active one is being played and a completed one
/// is a record, and all three can be described wrongly. Only [busy] closes the
/// control, and only for as long as a save is in flight.
///
/// Deliberately NOT `match.isOpenForChanges`. That getter answers a player's
/// question -- may I still join? -- and is false from kickoff onwards; using it
/// as the organizer's permission is what locked Edit Match out of active and
/// completed matches. Which new times are legal is migration `0074`'s answer,
/// given at the database.
bool canEditMatchDetails(Match match, {required bool busy}) => !busy;

/// Whether the ordinary roster path may be used to add and remove players.
///
/// True while the match is still to come or is being played -- an owner or admin
/// administers the roster through kickoff, which is the approved contract and is
/// new for an active match.
///
/// False once the match is over, deliberately. Who played is then a factual
/// record, and correcting it belongs to the Teams screen's batch path, which
/// reaches `correct_completed_match_players` and recalculates the ratings once.
/// Routing a historical correction through the registration functions would make
/// the record of who played a side effect of a roster edit.
bool canAdministerRoster(Match match, {required bool busy}) =>
    !match.isCompleted && !busy;

/// Whether to offer adding a community member who never registered themselves.
///
/// The same completion boundary as [canAdministerRoster], and one more: a
/// recorded (historical) match refuses registration outright at the database
/// with `MATCH_HISTORICAL`, so the control would be offering a refusal.
bool canAddCommunityPlayerTo(Match match, {required bool busy}) =>
    !match.isHistorical && !match.isCompleted && !busy;

/// Whether the ordinary guest roster operations -- adding a guest and taking one
/// off the roster -- are offered.
///
/// True up to completion, where they are the right operations. False afterwards:
/// a played match's guests are part of the record, and the corrections that keep
/// the factual lineup honest live on the Teams screen instead. Not gated on
/// [busy], because it describes which path is correct rather than whether a save
/// is in flight; the roster screen disables its own controls while it works.
bool canAdministerGuestRoster(Match match) => !match.isCompleted;
