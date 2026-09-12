import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_service.dart';
import '../communities/community_models.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import '../members/member_repository.dart';
import '../profile/player_identity.dart';
import '../results/match_result_card.dart';
import '../results/result_models.dart';
import '../results/result_repository.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import 'match_stage.dart';
import 'played_participants_sheet.dart';
import 'match_stage_board.dart';
import 'team_generation_settings.dart';
import 'team_models.dart';
import 'team_repository.dart';

/// The teams of one match: who is on each side, and — for an owner or admin —
/// the generation that produces them.
///
/// Everything shown here is read back through the application layer. The screen
/// keeps no lineup of its own: generation returns a result, that result is
/// stored, and what is rendered is what a fresh read returns. `KB-017` makes
/// the stored lineup the record of what actually played, so it is the only
/// thing worth showing.
///
/// **No quality metric is displayed.** §5.2 of the Engineering Specification
/// makes the metrics of §15 internal, and surfacing one is a product decision
/// this phase does not carry. `TeamRepository.generateTeams` returns none for
/// the same reason.
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({
    super.key,
    required this.matchId,
    this.teamRepository,
    this.matchService,
    this.memberRepository,
    this.resultRepository,
    this.renderer,
    this.shareService,
  });

  final String matchId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  /// Left null the screen builds the production ones, so nothing here knows
  /// what a data provider is.
  final TeamRepository? teamRepository;
  final MatchService? matchService;
  final MemberRepository? memberRepository;

  /// What the match finished as, when it has. This screen is the one place the
  /// product presents a result alongside the lineup it came from, so it is the
  /// one place that reads it.
  final ResultRepository? resultRepository;

  /// The Share Card Engine's two ports, passed straight through to
  /// [presentShareCard]. Supplied only by tests; this screen composes no card
  /// of its own and adds no renderer, preview or share service.
  final ShareCardRenderer? renderer;
  final ShareService? shareService;

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  late final TeamRepository _teams = widget.teamRepository ?? TeamRepository();
  late final MatchService _matches = widget.matchService ?? MatchService();
  late final MemberRepository _members =
      widget.memberRepository ?? MemberRepository();
  late final ResultRepository _results =
      widget.resultRepository ?? ResultRepository();

  late Future<_TeamsView> _future;

  /// True from the moment a generation is asked for until it has finished, so
  /// a second tap cannot start another one.
  bool _busy = false;

  /// The lineup currently on screen, or null while it loads, after a load
  /// failed, or when none is stored.
  ///
  /// Held beside the future because the Share action sits in the header, above
  /// the `FutureBuilder` that draws the pitch — and the card has to be made of
  /// the lineup the reader is looking at rather than of one read again when
  /// they press.
  _TeamsView? _shown;

  @override
  void initState() {
    super.initState();
    _future = _track(_load());
  }

  /// Whether this screen has already recorded that its teams were viewed, and
  /// that a saved result was put in front of the reader.
  ///
  /// One of each per screen instance. This screen reloads after every roster
  /// edit and after every generation, and none of those is a fresh viewing.
  bool _viewRecorded = false;
  bool _resultViewRecorded = false;

  /// Keeps [_shown] in step with whichever load is current.
  ///
  /// A generation replaces the lineup and reloads, so a result from a load that
  /// has been superseded must not become the card.
  Future<_TeamsView> _track(Future<_TeamsView> load) {
    load.then(
      (view) {
        if (!mounted || _future != load) return;
        _recordViews(view);
        setState(() => _shown = view);
      },
      // Already reported by the builder, which shows the retry.
      onError: (_) {
        if (!mounted || _future != load) return;
        setState(() => _shown = null);
      },
    );
    return load;
  }

  /// Records what this load actually put in front of the reader.
  ///
  /// Called only from [_track]'s success path, so a load that failed records
  /// nothing — and only for the load that is still current, so a superseded
  /// one cannot record a view of a screen that moved on.
  void _recordViews(_TeamsView view) {
    if (!_viewRecorded) {
      _viewRecorded = true;
      ProductAnalytics.instance.track(
        ProductEvent.teamsViewed,
        matchId: widget.matchId,
        communityId: view.match.communityId,
      );
    }

    // **Only when a result actually exists.** A match still to come has none
    // and this screen does not even ask for one; a match that is over but
    // unrecorded loads a null. Either way there is nothing on screen to have
    // viewed, and recording one here would make `result_viewed` a second, worse
    // copy of `teams_viewed`.
    if (!_resultViewRecorded && view.result != null) {
      _resultViewRecorded = true;
      ProductAnalytics.instance.track(
        ProductEvent.resultViewed,
        matchId: widget.matchId,
        communityId: view.match.communityId,
      );
    }
  }

  Future<_TeamsView> _load() async {
    final match = await _matches.fetchMatch(widget.matchId);
    final results = await Future.wait([
      _matches.fetchRegistrations(widget.matchId),
      _members.fetchMyRole(match.communityId),
      _teams.fetchLineup(widget.matchId),
      _teams.fetchConfirmedPlayers(widget.matchId),
      // A match still to come has no result to read, so the round trip is not
      // made. Tolerated on its own when it is: a result the reader cannot see is
      // a summary they do not get, and not a reason to fail a screen that has
      // already loaded the two teams.
      if (match.isCompleted)
        _results.fetchResult(widget.matchId).catchError((Object _) => null),
    ]);
    final registrations = results[0] as List<MatchRegistration>;
    return _TeamsView(
      match: match,
      role: results[1] as CommunityRole?,
      lineup: results[2] as List<TeamAssignment>,
      result: results.length > 4 ? results[4] as MatchResult? : null,
      registrations: {for (final r in registrations) r.participantId: r},
      players: {
        for (final player in results[3] as List<PlayerCoreInputs>)
          player.userId: player,
      },
      confirmedPlayers: registrations
          .where((r) => r.status == RegistrationStatus.confirmed)
          .length,
    );
  }

  /// A block body, not an expression one: `setState` refuses a callback that
  /// returns a Future, and `=> _future = _load()` returns the future it just
  /// assigned.
  void _reload() {
    final load = _load();
    setState(() {
      _future = load;
      // What is on screen is about to be replaced. Until the new lineup lands
      // there is nothing to make a card of.
      _shown = null;
    });
    _track(load);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _positionLabel(AppLocalizations l10n, String position) =>
      switch (position) {
        'GK' => l10n.positionGk,
        'DEF' => l10n.positionDef,
        'MID' => l10n.positionMid,
        'FWD' => l10n.positionFwd,
        _ => position,
      };

  /// The sentence a refused generation gets.
  ///
  /// The branch is on the failure *type*, as OP-5 requires; the reason only
  /// picks between two sentences of the same type. Nothing provider-specific
  /// reaches here to begin with — the Adapter Layer converted it already.
  String _generationError(AppLocalizations l10n, Failure failure) {
    if (failure is AuthorizationFailure) return l10n.errNotAuthorized;
    if (failure is ValidationFailure) {
      return failure.reason == FailureReason.missingPlayerInputs
          ? l10n.errMissingPlayerInputs
          : l10n.errTeamsNotGenerated;
    }
    return l10n.genericError;
  }

  /// Generates the teams and records the result.
  ///
  /// Two deliberate steps: the engine proposes, and [TeamRepository.saveLineup]
  /// makes the proposal the match's lineup. Generation stores nothing on its
  /// own, so without the second step there would be nothing to come back to.
  /// The screen then re-reads rather than rendering what it holds, which is
  /// what keeps the stored lineup the only source of truth.
  Future<void> _generate(_TeamsView view, {required bool replacing}) async {
    if (_busy) return;

    // The screen may have been built before `end_at` and left open until after
    // it passed, so the button being on screen is not evidence that generating
    // is still allowed. `canGenerate` reads the clock, so asking it again here
    // is asking about now.
    //
    // Nothing is generated and nothing is written; the screen is reloaded so
    // what is shown catches up with the match that has since finished. No new
    // dialog: the controls simply will not be there after the reload, which is
    // the same answer the screen would have given had it been built a moment
    // later. The database stays the final authority for a race that lands
    // after this check.
    if (!view.canGenerate) {
      _reload();
      return;
    }

    final l10n = context.l10n;

    // Asking comes before the screen is put to work, so nothing reports itself
    // as running while the question is still on screen. The guard is repeated
    // afterwards because two taps in one frame would raise two dialogs, and
    // only the first answer may start a generation.
    if (replacing && !await _confirmReplace(l10n)) return;
    if (_busy || !mounted) return;

    // Asked again, because the question above can be on screen across `end_at`.
    // The check before the dialog covers a screen left open; this one covers a
    // dialog left open, which is the same race one step further along.
    //
    // Migration `0071` is what actually protects the record -- it refuses a
    // generation onto a completed match whatever the client believes -- so this
    // is not the guarantee. It is what stops the app running a whole BTGE
    // search and a save in order to be told no.
    if (!view.canGenerate) {
      _reload();
      return;
    }

    setState(() => _busy = true);

    try {
      final lineup = await _teams.generateTeams(
        view.match,
        configuration: approvedTeamGeneration,
        historyLookback: approvedHistoryLookback,
        // Regenerating asks for *other* teams. Handing the stored lineup over
        // is what lets the engine offer a different split of equal quality
        // instead of the one already on screen.
        avoiding: replacing ? view.lineup : const [],
      );
      await _teams.saveLineup(widget.matchId, lineup);
      _showMessage(l10n.teamsGenerated);
    } on Failure catch (failure) {
      _showMessage(_generationError(l10n, failure));
    } catch (_) {
      _showMessage(l10n.genericError);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // However it ended, what is shown next comes from a fresh read.
        // Storing a lineup replaces the previous one in two steps, so a save
        // that fails part-way leaves a state only the database knows: keeping
        // the teams on screen would assert a lineup that is no longer there.
        _reload();
      }
    }
  }

  Future<bool> _confirmReplace(AppLocalizations l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.regenerateTeamsConfirmTitle),
        content: Text(l10n.regenerateTeamsConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.regenerateTeamsButton),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Whether there is a lineup to picture right now.
  ///
  /// A match with no stored lineup shows "not generated yet" and has nothing on
  /// it to send, so the action is offered only once there is one.
  bool get _canShare => _shown?.lineup.isNotEmpty ?? false;

  /// Composes the card for what is on screen and hands it to the engine.
  ///
  /// **One button, and the picture follows the screen.** There is no "share
  /// lineup" and no "share result" to choose between: the reader shares what
  /// they are looking at, and what they are looking at already depends on
  /// whether a result exists. Before one, the card is the lineup; after one, it
  /// is the same lineup with the score, the winner and each player's marks on
  /// it. The reader makes no decision the screen has not already made.
  ///
  /// **Every value is already resolved before this runs.** Nothing here reads a
  /// repository, and the names are the ones the pitch is already showing —
  /// [_nameOf] is the screen's rule, applied once, and handed over rather than
  /// re-derived inside a card.
  Future<void> _shareLineup() async {
    final view = _shown;
    if (view == null || view.lineup.isEmpty) return;

    final names = {
      for (final assignment in view.lineup)
        assignment.participantId: _nameOf(view, assignment.participantId),
    };

    // The faces are fetched before the card is composed, not while it is. The
    // engine gives a template two frames to settle, which is ample for layout
    // and nowhere near enough for a network image — so a card composed without
    // this would show a blank disc for every player who has a picture.
    await _precacheFaces(view);
    if (!mounted) return;

    // **One card for both states.** It is the screen itself, so the state the
    // screen is in is the state the picture is in: a score strip and player
    // marks where there is a result, and neither where there is not. There is
    // no second template and nothing for the reader to choose.
    final data = MatchResultCardData(
      lineup: view.lineup,
      players: view.players,
      names: names,
      teamAScore: view.result?.teamAScore,
      teamBScore: view.result?.teamBScore,
      // Keyed by participant, matching `mvpParticipantId` beside it and the
      // lineup this card draws. A guest's goal belongs on the picture for the
      // same reason it belongs in the total: it was one of the goals that made
      // the score.
      goals: {
        for (final tally in view.result?.goals ?? const <GoalTally>[])
          tally.participantId: tally.goals,
      },
      mvpParticipantId: view.result?.mvpUserId,
      communityName: view.match.communityName,
      matchTitle: view.match.displayName,
      playedAt: view.match.startAt,
      hasNaturalGoalkeeper: view.hasNaturalGoalkeeper,
    );

    await presentShareCard(
      context,
      template: (context) => MatchResultCard(data: data),
      // What this card is of, so a share can be counted against the match it
      // came from. Both are already on screen; nothing is fetched for them.
      matchId: widget.matchId,
      communityId: view.match.communityId,
      renderer: widget.renderer,
      shareService: widget.shareService,
    );
  }

  /// Loads the lineup's pictures into the image cache.
  ///
  /// The work is [precacheShareCardFaces]'s, which the public completed-match
  /// screen calls with its own lineup's pictures; what is decided here is
  /// *which* pictures. A Professional Guest holds no account, so there is no
  /// picture of theirs to fetch — the pitch draws them their own way.
  Future<void> _precacheFaces(_TeamsView view) => precacheShareCardFaces(
        context,
        <String>{
          for (final assignment in view.lineup)
            if (!assignment.isProfessionalGuest)
              if (view.players[assignment.participantId]?.avatarUrl
                  case final String url)
                url,
        },
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenScale = matchStageScreenScale(context);

    // **This screen is dark, and it is the only one that is.** A lineup is a
    // pitch, and a pitch on the app's pale page reads as a picture pasted onto a
    // document rather than as the thing the screen is about. So the Club task
    // shell is not used here: the bar, the ground and the sections are the Teams
    // feature's own, and nothing about the other five task screens changes.
    return Scaffold(
      backgroundColor: MatchStage.ground,
      appBar: matchStageAppBar(
        context,
        key: const ValueKey('teams-app-bar'),
        title: l10n.teamsTitle,
        // The one share control on this screen. There is no second one at its
        // foot and none on Match Details.
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: IconButton(
              icon: Icon(Icons.ios_share, size: 34 * screenScale),
              tooltip: l10n.shareTeamLineupAction,
              onPressed: _canShare && !_busy ? _shareLineup : null,
            ),
          ),
        ],
      ),
      body: FutureBuilder<_TeamsView>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _reload);
          }

          final view = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: MatchStageGround(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 20),
                children: view.lineup.isEmpty
                    ? _emptyState(l10n, view)
                    : _generatedTeams(l10n, view),
              ),
            ),
          );
        },
      ),
    );
  }

  /// No lineup stored yet. Whoever may generate one is offered it here; anyone
  /// else is told there is nothing to see, and no control they cannot use.
  List<Widget> _emptyState(AppLocalizations l10n, _TeamsView view) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
          // Explicitly reversed out. This screen is the one dark surface in the
          // product, and the text theme it inherits is the light one — so a
          // colour left to default came out near-black on the deep green and
          // could barely be read. `MatchStage.ink` is the foreground the rest
          // of this screen already uses against the same ground.
          child: Text(
            l10n.teamsEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(color: MatchStage.ink),
          ),
        ),
        // Adding somebody who played, on a match that has no lineup yet.
        //
        // This used to appear only once a lineup existed, which was right while
        // every completed match had arrived here through registration: there was
        // always a roster to generate from, and adding a player was a correction
        // to teams that already existed. A match recorded after the fact starts
        // with nobody in it, so that arrangement left the organizer on an empty
        // screen whose only control was a generation they had no players for.
        //
        // The rule is unchanged and so is the database's: `canEditPlayed` is
        // still an organizer on a match that is over, and
        // `set_completed_match_player` still refuses it on any other.
        if (view.canEditPlayed) ..._playedParticipantsAction(l10n, view),
        // Adding a Professional Guest is not a generation: it is a roster
        // correction, and a completed match is exactly where one is made
        // (0059). Gated on management, as it was before the split.
        if (view.canManageLineup) ..._addGuestAction(l10n, view),
        if (view.canGenerate) ..._generateAction(l10n, view),
      ];

  /// The match itself, and then whatever this reader may do to it.
  ///
  /// The drawing is [MatchStageBoard]'s, and it is the same drawing the public
  /// completed-match screen renders — the header, the two sides and each
  /// player where they played, with the score, the winner and the marks on it
  /// once a result exists. What is appended below it is what this screen has
  /// and the public one must not: the organizer's controls, each still gated on
  /// the role `_TeamsView` read.
  List<Widget> _generatedTeams(
    AppLocalizations l10n,
    _TeamsView view,
  ) =>
      [
        MatchStageBoard(
          lineup: view.lineup,
          players: view.players,
          nameOf: (participantId) => _nameOf(view, participantId),
          hasNaturalGoalkeeper: view.hasNaturalGoalkeeper,
          communityName: view.match.communityName,
          matchTitle: view.match.displayName,
          playedAt: view.match.startAt,
          teamAScore: view.result?.teamAScore,
          teamBScore: view.result?.teamBScore,
          goalsOf: view.goalsOf,
          isMvpOf: view.isMvpOf,
          // Who a card belongs to decides what tapping it does, and the
          // management action wins where there is one.
          //
          //   * owner/admin  -> the manual-override sheet, exactly as before. A
          //                     card is 82 pixels wide and cannot carry a second
          //                     hit target, so the organizer keeps the one they
          //                     came for.
          //   * anybody else -> the player's profile, which is the rule
          //                     everywhere a name is shown.
          //
          // A Professional Guest is neither: `_editPlayer` already returns for
          // one, and they have no profile to open.
          onTapPlayer: _busy
              ? null
              : (assignment) {
                  // Management, not generation. This sheet is the completed
                  // match's correction control -- move, swap, reposition --
                  // so gating it on `canGenerate` would have removed the very
                  // thing 0071 keeps available.
                  if (view.canManageLineup) {
                    _editPlayer(l10n, view, assignment);
                    return;
                  }
                  final userId = assignment.userId;
                  if (userId != null) openPlayerProfile(context, userId);
                },
        ),
        if (view.canEditPlayed) ...[
          const Divider(height: 32),
          ..._playedParticipantsAction(l10n, view),
        ],
        if (view.canManageLineup) ...[
          const Divider(height: 32),
          ..._addGuestAction(l10n, view),
        ],
        if (view.canGenerate) ...[
          const Divider(height: 32),
          ..._generateAction(l10n, view, replacing: true),
        ],
      ];

  /// Adding a Professional Guest without leaving the Teams screen.
  ///
  /// The organizer is looking at the two sides and realises somebody else is
  /// playing; the roster screen is two navigations away. The convenience is the
  /// only new thing here — **where** the guest ends up is not this screen's
  /// answer to give.
  List<Widget> _addGuestAction(AppLocalizations l10n, _TeamsView view) => [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: OutlinedButton.icon(
            key: const Key('teamsAddGuestButton'),
            onPressed: _busy ? null : () => _addGuest(view),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: Text(l10n.addGuestButton),
            style: OutlinedButton.styleFrom(
              foregroundColor: MatchStage.ink,
              side: const BorderSide(color: MatchStage.inkMuted),
            ),
          ),
        ),
      ];

  /// Records that a Professional Guest played a match that is over.
  ///
  /// The name, the side and the position in one sheet, because the factual
  /// lineup row needs all three and a guest has no profile to infer the last two
  /// from. One call, and the pitch is redrawn from the database rather than from
  /// anything assumed here: a guest appears because the lineup now holds them.
  ///
  /// Community players are corrected by their own batch path. The two stay
  /// separate, as the approved boundary requires -- a guest owns no rating and no
  /// statistics, so nothing is detached, reapplied or recalculated for one.
  Future<void> _addPlayedGuest(AppLocalizations l10n) async {
    final entry = await showModalBottomSheet<PlayedGuestEntry>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => PlayedGuestSheet(
        positionLabel: (position) => _positionLabel(l10n, position),
      ),
    );
    if (entry == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _teams.addPlayedProfessionalGuest(
        widget.matchId,
        entry.name,
        team: entry.team,
        position: entry.position,
      );
      if (!mounted) return;
      // Confirmed, and said so: everyone in the record of a played match played
      // it, so there is no reserve outcome to report.
      _showMessage(l10n.guestAddedConfirmed(entry.name));
      setState(() => _busy = false);
      _reload();
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(_guestErrorMessage(l10n, failure));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(l10n.guestActionFailed);
    }
  }

  /// Asks for the guest's name and adds them through the roster.
  ///
  /// **The canonical path, and nothing beside it.** This calls the same
  /// `MatchService.addProfessionalGuest` the roster screen calls, which reaches
  /// the same `add_professional_guest` function; there is no direct write into
  /// Team A or Team B from here and no second RPC. Everything that decides the
  /// outcome stays where it already lives: the owner/admin check, the name
  /// validation, the total capacity, and the priority that puts community
  /// confirmed ahead of community reserve ahead of a guest.
  ///
  /// So this screen does not decide whether the guest plays. The database
  /// answers `confirmed` or `reserve`, the reload re-reads the roster and the
  /// lineup, and `assign_professional_guest_teams` places the guest on a side
  /// only if they are starting. A guest who lands on the reserve list is simply
  /// absent from the pitch until the roster says otherwise — and only a guest
  /// who is on it can be moved or swapped, because only they have a lineup row.
  Future<void> _addGuest(_TeamsView view) async {
    if (_busy) return;
    final l10n = context.l10n;

    // A played match takes the correction instead. `add_professional_guest`
    // would create the guest and a confirmed seat and stop there: on a completed
    // match `recompute_match_status` returns at its own completed branch without
    // ever reaching the placement that puts a guest on a side, so the guest
    // existed and the factual lineup did not know it. Migration `0075` writes
    // the guest, the seat and the lineup row together.
    if (view.match.isCompleted) {
      await _addPlayedGuest(l10n);
      return;
    }

    final name = await _askGuestName(l10n);
    if (name == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final guestId = await _matches.addProfessionalGuest(widget.matchId, name);
      if (!mounted) return;
      // Read back rather than assumed: which list they landed in is the
      // server's answer, and the counts on screen may already be stale.
      final registrations = await _matches.fetchRegistrations(widget.matchId);
      if (!mounted) return;
      final starting = registrations.any((r) =>
          r.professionalGuestId == guestId &&
          r.status == RegistrationStatus.confirmed);
      _showMessage(starting
          ? l10n.guestAddedConfirmed(name)
          : l10n.guestAddedReserve(name));
      setState(() => _busy = false);
      _reload();
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(_guestErrorMessage(l10n, failure));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(l10n.guestActionFailed);
    }
  }

  /// The database's refusal for a Professional Guest operation, in the
  /// organizer's words. The same codes and the same wording the roster screen
  /// shows, because it is the same function refusing.
  String _guestErrorMessage(AppLocalizations l10n, Failure failure) =>
      switch (failure.reason) {
        FailureReason.invalidGuestName => l10n.errInvalidGuestName,
        FailureReason.registrationClosed => l10n.errRegistrationClosed,
        // The completed-match correction's own refusals (migration `0075`). The
        // sheet asks for all three, so these are the server holding the line
        // rather than the organizer's likely mistake.
        FailureReason.invalidTeam => l10n.errLineupRefused,
        FailureReason.invalidPosition => l10n.errLineupRefused,
        FailureReason.matchNotCompleted => l10n.errMatchNotCompleted,
        _ => failure is AuthorizationFailure
            ? l10n.errNotAuthorized
            : l10n.guestActionFailed,
      };

  /// Asks for a guest's name. Returns the trimmed name, or null if cancelled.
  ///
  /// The 2–60 bound is the one the database states, asked here so a mistyped
  /// name is caught before a round trip. `add_professional_guest` still refuses
  /// it if this check is ever wrong — the rule is the server's and this is only
  /// the courtesy.
  ///
  /// No `TextEditingController`: the field's value is kept by the form and read
  /// through `onSaved`. A controller would have to outlive the dialog's exit
  /// animation to avoid being used after disposal, and the name is the only
  /// thing wanted out of it.
  Future<String?> _askGuestName(AppLocalizations l10n) {
    final formKey = GlobalKey<FormState>();
    var name = '';

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.addGuestTitle),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('teamsGuestNameField'),
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l10n.guestNameLabel),
            validator: (value) {
              final entered = (value ?? '').trim();
              return entered.length < 2 || entered.length > 60
                  ? l10n.guestNameInvalid
                  : null;
            },
            onSaved: (value) => name = (value ?? '').trim(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            key: const Key('teamsGuestNameSubmit'),
            onPressed: () {
              final form = formKey.currentState;
              if (form == null || !form.validate()) return;
              form.save();
              Navigator.of(dialogContext).pop(name);
            },
            child: Text(l10n.addGuestButton),
          ),
        ],
      ),
    );
  }

  /// Correcting who played, offered once the match is over.
  ///
  /// A member who turned up and was never registered is missing from the record
  /// `KB-017` makes authoritative, and until the match is played there is no
  /// record to correct — before that a seat is the player's to claim and the
  /// reserve queue decides who holds one. So this appears only on a completed
  /// match, and the database refuses it on any other.
  List<Widget> _playedParticipantsAction(
    AppLocalizations l10n,
    _TeamsView view,
  ) =>
      [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: OutlinedButton.icon(
            key: const Key('editPlayedParticipantsButton'),
            onPressed: _busy ? null : () => _editPlayedParticipants(l10n, view),
            icon: const Icon(Icons.person_add_alt),
            label: Text(l10n.editPlayedParticipantsAction),
            style: OutlinedButton.styleFrom(
              foregroundColor: MatchStage.ink,
              side: const BorderSide(color: MatchStage.inkMuted),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l10n.editPlayedMatchNote,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ];

  /// The one administrative control on this screen.
  ///
  /// It appears only for an owner or admin, and only while the confirmed roster
  /// is one the engine supports: below `OP-2` or above `BTGE-PF-1` there is no
  /// generation to offer, so the button gives way to a sentence saying what the
  /// roster would need. Both bounds are read from the approved configuration
  /// rather than restated here.
  List<Widget> _generateAction(
    AppLocalizations l10n,
    _TeamsView view, {
    bool replacing = false,
  }) {
    if (!view.hasGeneratableRoster) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            l10n.teamsPlayerRangeNote(
              approvedTeamGeneration.minPlayers,
              maxSupportedPlayers,
              view.confirmedPlayers,
            ),
            textAlign: TextAlign.center,
            // The muted foreground for the same dark ground: secondary next to
            // the empty-state line, and still legible against it.
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: MatchStage.inkMuted),
          ),
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: FilledButton.icon(
          onPressed: _busy ? null : () => _generate(view, replacing: replacing),
          icon: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.shuffle),
          label: Text(replacing
              ? l10n.regenerateTeamsButton
              : l10n.generateTeamsButton),
        ),
      ),
    ];
  }

  /// The name to put on a player.
  ///
  /// The confirmed roster is where one comes from. A player who left the match
  /// after the lineup was stored has no profile row left in it, so the
  /// registration is tried next and a dash stands for somebody neither knows —
  /// `KB-017` records that they played, so they are named as best as can be
  /// rather than dropped.
  String _nameOf(_TeamsView view, String userId) =>
      view.players[userId]?.fullName ??
      view.registrations[userId]?.fullName ??
      '—';

  // --- Manual Override (§13) -------------------------------------------------
  //
  // Three operations and nothing else: move a player to the other side, swap
  // two of them, change the position one is playing. The screen chooses which
  // to ask for; `TeamRepository` decides what each one means and writes it, so
  // no lineup reasoning happens here. `BTGE-MO-2` is what makes them possible
  // without the engine, and nothing below reaches for it.

  /// The actions offered on a player, and what each one runs.
  Future<void> _editPlayer(
    AppLocalizations l10n,
    _TeamsView view,
    TeamAssignment assignment,
  ) async {
    if (_busy) return;
    // A Professional Guest is offered all four, on the same terms as anybody
    // else on the pitch.
    //
    // Which side somebody is on and where they stood are both facts about this
    // match rather than about a profile, so both are answerable for a guest.
    // The position is match-scoped and stays that way: no primary or secondary
    // is written, no rating appears, `assignment_basis` stays `GUEST`, and the
    // engine still never sees them.
    //
    // Removing one means something different from removing a player, and it is
    // routed accordingly — see [_removeParticipant].
    final guest = assignment.isProfessionalGuest;
    final action = await showDialog<_PlayerAction>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title:
            Text(l10n.editPlayerTitle(_nameOf(view, assignment.participantId))),
        children: [
          for (final (action, label, icon)
              in <(_PlayerAction, String, IconData)>[
            (_PlayerAction.move, l10n.movePlayerAction, Icons.swap_horiz),
            (_PlayerAction.swap, l10n.swapPlayerAction, Icons.swap_vert),
            (
              _PlayerAction.position,
              l10n.changePositionAction,
              Icons.sports_soccer
            ),
            // For a community player, taking somebody out of the record of who
            // played is a correction to a played match, so it is offered on one
            // and nowhere else. A guest can be taken out in either state: on a
            // match still to come it is the ordinary roster removal, and on one
            // that is over it is the same correction.
            if (view.canEditPlayed || guest)
              (
                _PlayerAction.remove,
                guest
                    ? l10n.removeGuestButton
                    : l10n.removePlayedPlayerAction,
                Icons.person_remove_alt_1,
              ),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.of(dialogContext).pop(action),
            ),
        ],
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _PlayerAction.move:
        await _runEdit(
          l10n,
          // The participant id, not the user id: a guest is moved by the same
          // operation as anybody else, and `userId!` would have thrown on one.
          () => _teams.movePlayer(
            widget.matchId,
            assignment.participantId,
            completedCorrection: view.match.isCompleted,
          ),
        );
      case _PlayerAction.swap:
        await _swap(l10n, view, assignment);
      case _PlayerAction.position:
        await _changePosition(l10n, view, assignment);
      case _PlayerAction.remove:
        await _removeParticipant(l10n, view, assignment);
    }
  }

  /// Takes somebody out of the match from the Teams screen, after asking.
  ///
  /// Three different operations behind one action, because "remove" means three
  /// different things depending on who and when:
  ///
  ///   * a **community player** on a played match — the correction that already
  ///     existed. Every counter, rating and leaderboard entry the match gave
  ///     them is taken back as part of the same write, which is why the
  ///     question is worth asking.
  ///   * a **Professional Guest** on a match still to come — the ordinary
  ///     roster removal, through the same `remove_professional_guest` the
  ///     roster screen calls. The seat goes, the reserve is rebalanced, and the
  ///     guest's lineup row goes with the seat.
  ///   * a **Professional Guest** on a played match — this guest did not
  ///     actually play. That is not what the roster removal means: it keeps the
  ///     lineup row on purpose, because for a played match that row is the
  ///     record of who was on the pitch. So it is its own operation, and it
  ///     refuses rather than quietly editing a recorded result.
  Future<void> _removeParticipant(
    AppLocalizations l10n,
    _TeamsView view,
    TeamAssignment assignment,
  ) async {
    final guest = assignment.isProfessionalGuest;
    final name = _nameOf(view, assignment.participantId);
    // A guest earns no statistic and no rating (migration `0046`), so the
    // player's warning about both being taken back would not be true of them.
    final body = guest
        ? (view.canEditPlayed
            ? l10n.removePlayedGuestConfirmBody(name)
            : l10n.removeGuestConfirmBody(name))
        : l10n.removePlayedPlayerConfirmBody(name);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(guest
            ? l10n.removeGuestConfirmTitle
            : l10n.removePlayedPlayerConfirmTitle),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(guest
                ? l10n.removeGuestButton
                : l10n.removePlayedPlayerAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runEdit(l10n, () {
      if (!guest) {
        return _teams.removePlayedPlayer(widget.matchId, assignment.userId!);
      }
      final guestId = assignment.professionalGuestId!;
      return view.canEditPlayed
          ? _teams.removePlayedProfessionalGuest(widget.matchId, guestId)
          : _matches.removeProfessionalGuest(widget.matchId, guestId);
    });
  }

  /// Corrects who played, for as many community players as it takes.
  ///
  /// **One save, one recalculation.** Every correction to a played match
  /// reverses the ratings and counters it produced and reapplies them, so adding
  /// four players one at a time would do that four times over lineups nobody
  /// played, and a refusal on the fourth would leave the first three standing.
  /// The sheet collects the whole intent and this sends it once, to
  /// `correct_completed_match_players` (migration `0074`), which validates all
  /// of it, recalculates once and rolls all of it back on any refusal. There is
  /// deliberately no loop over `addPlayedPlayer` here.
  ///
  /// The candidates are read when the sheet opens rather than with the screen:
  /// the list is needed only by an organizer correcting a played match, and
  /// reading it for every visitor would be a request for something almost
  /// nobody asks for. Anybody already in the factual lineup is filtered out --
  /// moving somebody who is already recorded is the card's own edit, not an
  /// addition -- and Professional Guests never appear, because they are
  /// corrected by the guest operations that keep their own rules.
  Future<void> _editPlayedParticipants(
    AppLocalizations l10n,
    _TeamsView view,
  ) async {
    if (_busy) return;

    final corrections =
        await showModalBottomSheet<List<CompletedPlayerCorrection>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => PlayedParticipantsSheet(
        positionLabel: (position) => _positionLabel(l10n, position),
        load: () async {
          final members = await _members.fetchMembers(view.match.communityId);
          final inLineup = {for (final a in view.lineup) a.participantId};
          return [
            for (final member in members)
              if (!inLineup.contains(member.userId)) member,
          ];
        },
      ),
    );
    // Nothing chosen, or the sheet dismissed. An empty batch is not sent: `0074`
    // refuses one, and it would otherwise reverse and reapply every rating the
    // match produced for no correction at all.
    if (corrections == null || corrections.isEmpty || !mounted) return;

    await _runEdit(
      l10n,
      () => _teams.correctCompletedPlayers(widget.matchId, corrections),
    );
  }

  /// Asks who on the other side to swap with, then swaps them.
  ///
  /// Everybody on the other side is offered, Professional Guests included. A
  /// swap exchanges two sides and `KB-D6` gives the labels no other meaning, so
  /// which column names a participant has no bearing on whether they can be one
  /// half of it. All four combinations are the same operation: player with
  /// player, player with guest, guest with player, guest with guest.
  Future<void> _swap(
    AppLocalizations l10n,
    _TeamsView view,
    TeamAssignment assignment,
  ) async {
    final others = [
      for (final other in view.lineup)
        if (other.team != assignment.team) other,
    ];
    if (others.isEmpty) {
      _showMessage(l10n.swapNobodyAvailable);
      return;
    }

    final partner = await showDialog<TeamAssignment>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.swapPlayerTitle),
        children: [
          for (final other in others)
            ListTile(
              leading: PlayerAvatar(
                avatarUrl: view.players[other.participantId]?.avatarUrl,
                fullName: _nameOf(view, other.participantId),
                isProfessionalGuest: other.isProfessionalGuest,
              ),
              title: Text(_nameOf(view, other.participantId)),
              // A guest may have no position — an ordinary roster-derived
              // lineup invents none for them — and the row says what they are
              // instead of inventing one here either. A guest recorded by a
              // completed-match correction does carry the position they played,
              // and it is shown like anybody else's. A registered player always
              // carries one: the database refuses a lineup row naming a user
              // without.
              subtitle: Text(
                other.assignedPosition == null
                    ? l10n.professionalGuestLabel
                    : _positionLabel(l10n, other.assignedPosition!.code),
              ),
              onTap: () => Navigator.of(dialogContext).pop(other),
            ),
        ],
      ),
    );
    if (partner == null || !mounted) return;

    await _runEdit(
      l10n,
      // Participant ids on both sides. `userId!` threw for a guest, which is
      // half of why guests could not be swapped at all.
      () => _teams.swapPlayers(
        widget.matchId,
        assignment.participantId,
        partner.participantId,
        completedCorrection: view.match.isCompleted,
      ),
    );
  }

  /// Asks which of the four positions to use, with [current] marked when the
  /// question is about a player who already has one.
  Future<Position?> _askPosition(
    AppLocalizations l10n,
    String title, {
    Position? current,
  }) =>
      showDialog<Position>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(title),
          children: [
            // The four the domain model has. A lineup position is one of these
            // or it is not a position (`BTGE-HC-5`).
            for (final position in Position.values)
              ListTile(
                leading: Icon(position == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(_positionLabel(l10n, position.code)),
                onTap: () => Navigator.of(dialogContext).pop(position),
              ),
          ],
        ),
      );

  /// Asks which position to give the player, then records it.
  Future<void> _changePosition(
    AppLocalizations l10n,
    _TeamsView view,
    TeamAssignment assignment,
  ) async {
    final chosen = await _askPosition(
      l10n,
      l10n.changePositionTitle,
      current: assignment.assignedPosition,
    );
    if (chosen == null || chosen == assignment.assignedPosition || !mounted) {
      return;
    }

    await _runEdit(
      l10n,
      () => _teams.changeAssignedPosition(
        widget.matchId,
        assignment.participantId,
        chosen,
        completedCorrection: view.match.isCompleted,
      ),
    );
  }

  /// Runs one manual edit, with the treatment every write on this screen gets.
  ///
  /// The screen holds no edited lineup of its own at any point: [edit] persists
  /// through the application layer, and what is rendered afterwards comes from
  /// a fresh read — after a refusal as much as after a success, because a
  /// refused edit means the stored lineup is not what the screen was showing it
  /// to be.
  Future<void> _runEdit(
    AppLocalizations l10n,
    Future<void> Function() edit,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await edit();
      _showMessage(l10n.lineupUpdated);
    } on Failure catch (failure) {
      _showMessage(_editError(l10n, failure));
    } catch (_) {
      _showMessage(l10n.genericError);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  /// The sentence a refused edit gets, chosen by failure type (OP-5).
  ///
  /// A [ConflictFailure] on this path is the database refusing the lineup
  /// itself. Its two unique rules are that a player appears once — which an
  /// edit cannot breach, because it only ever rearranges the players already
  /// there — and that no side holds two goalkeepers, which is the one an
  /// organizer can walk into. The sentence states the rule rather than
  /// diagnosing the row.
  ///
  /// A [ValidationFailure] means the edit no longer describes the stored
  /// lineup: somebody else changed it in between.
  ///
  /// Two conflicts get their own sentence. Taking the recorded MVP or a scorer
  /// out of the lineup is refused because the result would then credit somebody
  /// who did not play, and the organizer has to correct the result first — a
  /// sentence saying "the lineup was refused" would leave them guessing which
  /// rule they met. An edit attempted on a match still to come is the other:
  /// correcting who played only makes sense once somebody has.
  String _editError(AppLocalizations l10n, Failure failure) {
    if (failure.reason == FailureReason.resultParticipantRemoved) {
      return l10n.errResultParticipantRemoved;
    }
    if (failure.reason == FailureReason.matchNotCompleted) {
      return l10n.errMatchNotCompleted;
    }
    // The batch correction's own refusal (migration `0074`): the payload was not
    // a batch -- empty, or naming the same player twice. The organizer can fix
    // it, so it gets its own sentence rather than the generic refusal.
    if (failure.reason == FailureReason.invalidChanges) {
      return l10n.errInvalidChanges;
    }
    return switch (failure) {
      AuthorizationFailure() => l10n.errNotAuthorized,
      ConflictFailure() => l10n.errLineupRefused,
      ValidationFailure() => l10n.errLineupNotChanged,
      _ => l10n.genericError,
    };
  }
}

/// What an organizer picked from a player's row.
enum _PlayerAction { move, swap, position, remove }

/// Everything one build of the screen needs, read in one pass.
class _TeamsView {
  const _TeamsView({
    required this.match,
    this.result,
    required this.role,
    required this.lineup,
    required this.registrations,
    required this.players,
    required this.confirmedPlayers,
  });

  final Match match;

  /// What the match finished as, or null when it has not been played or nobody
  /// has recorded it yet.
  ///
  /// **The one thing that decides which of this screen's two states is drawn.**
  /// Null is the lineup as it stands; present upgrades the same screen with a
  /// compact summary above the teams and a mark on each player who did
  /// something. Reading it is a member's business — `match_results_select_
  /// members` has always allowed it — and recording one remains the organizer's.
  final MatchResult? result;

  /// The viewer's role in the match's community, or null when they hold none.
  final CommunityRole? role;

  /// The stored lineup; empty when none was saved.
  final List<TeamAssignment> lineup;

  /// The confirmed roster by player id — the seat each player holds.
  final Map<String, MatchRegistration> registrations;

  /// The profiles behind the confirmed seats: the name, the rating and the
  /// picture each card shows, and the natural-goalkeeper test the pitch reads.
  final Map<String, PlayerCoreInputs> players;

  final int confirmedPlayers;

  /// Whether this reader may manage the lineup at all.
  ///
  /// `PD-07`: management is a community role, never a creator privilege, and
  /// migration `0018` gates writing a lineup on the same `admin` role through
  /// `is_match_community_admin`. The database remains what enforces it; this
  /// only decides what is shown.
  ///
  /// This is the broad capability, and it is deliberately separate from
  /// [canGenerate] below. It used to be the same getter, which is how a
  /// completed match still offered Regenerate -- and why narrowing that one
  /// getter would have taken the completed-match correction controls with it,
  /// since several of them are gated on "is this an organizer?" and nothing
  /// more.
  bool get canManageLineup => role?.atLeast(CommunityRole.admin) ?? false;

  /// Whether BTGE Generate / Regenerate may be offered.
  ///
  /// An organizer, **and** a match that has not been played. A generation is
  /// the engine proposing teams; once the match is over the lineup is the
  /// record of who was actually on the pitch, and proposing a different one
  /// would overwrite history with a guess. Migration `0071` refuses it at the
  /// database, and this is what stops the product offering a refusal.
  ///
  /// `match.isCompleted` reads the clock, so this is answered afresh every time
  /// it is asked -- which is what makes it usable as the tap-time check in
  /// `_generate` and not merely as a build-time one.
  bool get canGenerate => canManageLineup && !match.isCompleted;

  /// Whether to offer the corrections that only a played match can take.
  ///
  /// The same role, and one more condition: adding somebody to the record of who
  /// played, or taking them out of it, is a correction to history. Before the
  /// match is over there is no history to correct — the roster is the players'
  /// own to join and leave — and `set_completed_match_player` refuses it, so
  /// offering the control would be offering a refusal.
  bool get canEditPlayed => canManageLineup && match.isCompleted;

  /// Whether anybody in the squad keeps goal — §10.1's natural goalkeeper,
  /// `GK` as primary or secondary.
  ///
  /// The pitch draws a goalkeeper position only when this holds. It is the same
  /// test the engine applies when it decides whether to create a goalkeeper slot
  /// at all, so the two agree by construction rather than by coincidence.
  bool get hasNaturalGoalkeeper =>
      players.values.any((player) => player.isNaturalGoalkeeper);

  /// How many [participantId] scored, and whether they were named best on the
  /// pitch. Both are the absence of a mark before a result exists.
  int goalsOf(String participantId) {
    final result = this.result;
    if (result == null) return 0;
    return result.goalsBy(participantId);
  }

  bool isMvpOf(String participantId) =>
      result?.mvpUserId != null && result!.mvpUserId == participantId;

  /// Whether the picture that leaves this screen carries a result.
  bool get hasResult => result != null;

  /// Whether the confirmed roster is one the engine accepts (`BTGE-PF-2`).
  bool get hasGeneratableRoster =>
      confirmedPlayers >= approvedTeamGeneration.minPlayers &&
      confirmedPlayers <= maxSupportedPlayers;
}
