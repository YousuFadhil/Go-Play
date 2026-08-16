import 'package:btge/btge.dart';
import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../communities/community_models.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import '../members/member_repository.dart';
import '../profile/player_identity.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import 'pitch_view.dart';
import 'team_lineup_card.dart';
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

  /// Keeps [_shown] in step with whichever load is current.
  ///
  /// A generation replaces the lineup and reloads, so a result from a load that
  /// has been superseded must not become the card.
  Future<_TeamsView> _track(Future<_TeamsView> load) {
    load.then(
      (view) {
        if (!mounted || _future != load) return;
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

  Future<_TeamsView> _load() async {
    final match = await _matches.fetchMatch(widget.matchId);
    final results = await Future.wait([
      _matches.fetchRegistrations(widget.matchId),
      _members.fetchMyRole(match.communityId),
      _teams.fetchLineup(widget.matchId),
      _teams.fetchConfirmedPlayers(widget.matchId),
    ]);
    final registrations = results[0] as List<MatchRegistration>;
    return _TeamsView(
      match: match,
      role: results[1] as CommunityRole?,
      lineup: results[2] as List<TeamAssignment>,
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
    final l10n = context.l10n;

    // Asking comes before the screen is put to work, so nothing reports itself
    // as running while the question is still on screen. The guard is repeated
    // afterwards because two taps in one frame would raise two dialogs, and
    // only the first answer may start a generation.
    if (replacing && !await _confirmReplace(l10n)) return;
    if (_busy || !mounted) return;
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

  /// Composes the lineup card for what is on screen and hands it to the engine.
  ///
  /// **Every value is already resolved before this runs.** Nothing here reads a
  /// repository, and the names are the ones the pitch is already showing —
  /// [_nameOf] is the screen's rule, applied once, and handed over rather than
  /// re-derived inside a card.
  Future<void> _shareLineup() async {
    final view = _shown;
    if (view == null || view.lineup.isEmpty) return;

    final data = TeamLineupCardData(
      // `displayName`, not `title`: a match need not be named, and the app
      // already answers that with its location. The card uses the same
      // headline the match is listed under everywhere else rather than a
      // fallback of its own.
      matchTitle: view.match.displayName,
      lineup: view.lineup,
      players: view.players,
      names: {
        for (final assignment in view.lineup)
          assignment.participantId: _nameOf(view, assignment.participantId),
      },
      hasNaturalGoalkeeper: view.hasNaturalGoalkeeper,
    );

    // The faces are fetched before the card is composed, not while it is. The
    // engine gives a template two frames to settle, which is ample for layout
    // and nowhere near enough for a network image — so a card composed without
    // this would show a blank disc for every player who has a picture.
    await _precacheFaces(view);
    if (!mounted) return;

    await presentShareCard(
      context,
      template: (context) => TeamLineupCard(data: data),
      renderer: widget.renderer,
      shareService: widget.shareService,
    );
  }

  /// Loads the lineup's pictures into the image cache.
  ///
  /// Best effort, and issued together because they are independent. A picture
  /// that will not load is not an error anywhere else in the app either, and
  /// the pitch already falls back to a plain disc. `onError` is what keeps that
  /// true: without a handler `precacheImage` reports the failure to
  /// `FlutterError`, turning a missing photograph into an app-level error.
  ///
  /// A Professional Guest holds no account, so there is no picture of theirs to
  /// fetch — the pitch draws them their own way.
  Future<void> _precacheFaces(_TeamsView view) async {
    final urls = <String>{
      for (final assignment in view.lineup)
        if (!assignment.isProfessionalGuest)
          if (view.players[assignment.participantId]?.avatarUrl
              case final String url)
            url,
    };
    if (urls.isEmpty) return;

    await Future.wait([
      for (final url in urls)
        precacheImage(NetworkImage(url), context, onError: (_, __) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(
        title: Text(l10n.teamsTitle),
        // In the header, where a screen's own action belongs. Disabled rather
        // than hidden while the lineup loads or when none is stored: an action
        // that comes and goes as teams are regenerated reads as a bug.
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.shareTeamLineupAction,
            onPressed: _canShare && !_busy ? _shareLineup : null,
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
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: view.lineup.isEmpty
                  ? _emptyState(l10n, view)
                  : _generatedTeams(l10n, view),
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
          child: Text(l10n.teamsEmpty, textAlign: TextAlign.center),
        ),
        if (view.canGenerate) ..._generateAction(l10n, view),
      ];

  List<Widget> _generatedTeams(AppLocalizations l10n, _TeamsView view) => [
        ..._teamSection(l10n, view, l10n.teamAName, TeamId.a),
        ..._teamSection(l10n, view, l10n.teamBName, TeamId.b),
        if (view.canEditPlayed) ...[
          const Divider(height: 32),
          ..._addPlayerAction(l10n, view),
        ],
        if (view.canGenerate) ...[
          const Divider(height: 32),
          ..._generateAction(l10n, view, replacing: true),
        ],
      ];

  /// Correcting who played, offered once the match is over.
  ///
  /// A member who turned up and was never registered is missing from the record
  /// `KB-017` makes authoritative, and until the match is played there is no
  /// record to correct — before that a seat is the player's to claim and the
  /// reserve queue decides who holds one. So this appears only on a completed
  /// match, and the database refuses it on any other.
  List<Widget> _addPlayerAction(AppLocalizations l10n, _TeamsView view) => [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _addPlayer(l10n, view),
            icon: const Icon(Icons.person_add_alt),
            label: Text(l10n.addPlayedPlayerAction),
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
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: FilledButton.icon(
          onPressed:
              _busy ? null : () => _generate(view, replacing: replacing),
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

  /// One side of the lineup: its label, then the pitch it lines up on.
  ///
  /// `A` and `B` distinguish the two sides and mean nothing else (`KB-D6`), so
  /// neither is presented as the stronger or the first-choice team.
  List<Widget> _teamSection(
    AppLocalizations l10n,
    _TeamsView view,
    String title,
    TeamId team,
  ) {
    final assignments = [
      for (final assignment in view.lineup)
        if (assignment.team == team) assignment,
    ];

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          '$title (${assignments.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      PitchView(
        assignments: assignments,
        players: view.players,
        hasNaturalGoalkeeper: view.hasNaturalGoalkeeper,
        nameOf: (userId) => _nameOf(view, userId),
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
                if (view.canGenerate) {
                  _editPlayer(l10n, view, assignment);
                  return;
                }
                final userId = assignment.userId;
                if (userId != null) openPlayerProfile(context, userId);
              },
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
    // Every action below — move, swap, change position, remove — is a manual
    // override of the engine's output, and the engine only ever places
    // registered players. A Professional Guest is placed by the roster, is not
    // a generation input, and has no profile for a position change to be
    // derived against, so their card is shown and not edited here.
    if (assignment.isProfessionalGuest) return;
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
            // Taking somebody out of the record of who played is a correction to
            // a played match, so it is offered on one and nowhere else.
            if (view.canEditPlayed)
              (
                _PlayerAction.remove,
                l10n.removePlayedPlayerAction,
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
          () => _teams.movePlayer(widget.matchId, assignment.userId!),
        );
      case _PlayerAction.swap:
        await _swap(l10n, view, assignment);
      case _PlayerAction.position:
        await _changePosition(l10n, assignment);
      case _PlayerAction.remove:
        await _removePlayer(l10n, view, assignment);
    }
  }

  /// Takes a player out of the record of who played, after asking.
  ///
  /// The question is worth asking because the consequence is not local: every
  /// counter, rating and leaderboard entry the match produced for them is taken
  /// back as part of the same write.
  Future<void> _removePlayer(
    AppLocalizations l10n,
    _TeamsView view,
    TeamAssignment assignment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removePlayedPlayerConfirmTitle),
        content: Text(l10n.removePlayedPlayerConfirmBody(
          _nameOf(view, assignment.participantId),
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.removePlayedPlayerAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runEdit(
      l10n,
      () => _teams.removePlayedPlayer(widget.matchId, assignment.userId!),
    );
  }

  /// Adds a community member to the record of who played.
  ///
  /// The list is read when the dialog opens rather than with the screen: it is
  /// needed only by an admin correcting a played match, and reading it for
  /// everyone who opens the Teams screen would be a request per visit for a
  /// list almost nobody asks for.
  Future<void> _addPlayer(AppLocalizations l10n, _TeamsView view) async {
    if (_busy) return;
    setState(() => _busy = true);

    final List<CommunityMember> members;
    try {
      members = await _members.fetchMembers(view.match.communityId);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _showMessage(l10n.loadFailed);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final inLineup = {for (final a in view.lineup) a.participantId};
    final candidates = [
      for (final member in members)
        if (!inLineup.contains(member.userId)) member,
    ];
    if (candidates.isEmpty) {
      _showMessage(l10n.addPlayedPlayerNobodyAvailable);
      return;
    }

    final member = await showDialog<CommunityMember>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.addPlayedPlayerAction),
        children: [
          for (final candidate in candidates)
            ListTile(
              // A picker's row belongs to its selection: tapping is choosing
              // this player, not reading about them. The face is here because
              // recognising somebody is what the list is for.
              leading: PlayerAvatar(
                avatarUrl: candidate.avatarUrl,
                fullName: candidate.fullName,
              ),
              title: Text(candidate.fullName),
              onTap: () => Navigator.of(dialogContext).pop(candidate),
            ),
        ],
      ),
    );
    if (member == null || !mounted) return;

    final team = await _askTeam(l10n);
    if (team == null || !mounted) return;

    final position = await _askPosition(l10n, l10n.choosePositionTitle);
    if (position == null || !mounted) return;

    await _runEdit(
      l10n,
      () => _teams.addPlayedPlayer(
        widget.matchId,
        member.userId,
        team: team,
        position: position,
      ),
    );
  }

  Future<TeamId?> _askTeam(AppLocalizations l10n) => showDialog<TeamId>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(l10n.chooseTeamTitle),
          children: [
            for (final (team, label) in [
              (TeamId.a, l10n.teamAName),
              (TeamId.b, l10n.teamBName),
            ])
              ListTile(
                leading: const Icon(Icons.groups_2),
                title: Text(label),
                onTap: () => Navigator.of(dialogContext).pop(team),
              ),
          ],
        ),
      );

  /// Asks which player on the other side to swap with, then swaps them.
  Future<void> _swap(
    AppLocalizations l10n,
    _TeamsView view,
    TeamAssignment assignment,
  ) async {
    final others = [
      for (final other in view.lineup)
        // A guest is not a swap partner: `swapPlayers` exchanges two registered
        // players, and offering one here would produce a refusal at the port.
        if (other.team != assignment.team && !other.isProfessionalGuest) other,
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
              ),
              title: Text(_nameOf(view, other.participantId)),
              // Non-null by construction: `others` above excludes Professional
              // Guests, and a lineup row naming a registered player always
              // carries a position — the database refuses one that does not.
              subtitle:
                  Text(_positionLabel(l10n, other.assignedPosition!.code)),
              onTap: () => Navigator.of(dialogContext).pop(other),
            ),
        ],
      ),
    );
    if (partner == null || !mounted) return;

    await _runEdit(
      l10n,
      () => _teams.swapPlayers(
        widget.matchId,
        assignment.userId!,
        partner.userId!,
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
        assignment.userId!,
        chosen,
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
    required this.role,
    required this.lineup,
    required this.registrations,
    required this.players,
    required this.confirmedPlayers,
  });

  final Match match;

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

  /// Whether to offer the generation controls.
  ///
  /// `PD-07`: management is a community role, never a creator privilege, and
  /// migration `0018` gates writing a lineup on the same `admin` role through
  /// `is_match_community_admin`. The database remains what enforces it; this
  /// only decides what is shown.
  bool get canGenerate => role?.atLeast(CommunityRole.admin) ?? false;

  /// Whether to offer the corrections that only a played match can take.
  ///
  /// The same role, and one more condition: adding somebody to the record of who
  /// played, or taking them out of it, is a correction to history. Before the
  /// match is over there is no history to correct — the roster is the players'
  /// own to join and leave — and `set_completed_match_player` refuses it, so
  /// offering the control would be offering a refusal.
  bool get canEditPlayed => canGenerate && match.isCompleted;

  /// Whether anybody in the squad keeps goal — §10.1's natural goalkeeper,
  /// `GK` as primary or secondary.
  ///
  /// The pitch draws a goalkeeper position only when this holds. It is the same
  /// test the engine applies when it decides whether to create a goalkeeper slot
  /// at all, so the two agree by construction rather than by coincidence.
  bool get hasNaturalGoalkeeper =>
      players.values.any((player) => player.isNaturalGoalkeeper);

  /// Whether the confirmed roster is one the engine accepts (`BTGE-PF-2`).
  bool get hasGeneratableRoster =>
      confirmedPlayers >= approvedTeamGeneration.minPlayers &&
      confirmedPlayers <= maxSupportedPlayers;
}
