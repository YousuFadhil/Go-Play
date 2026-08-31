// `TeamId` only: which side won is the result's own vocabulary, and `KB-D6`
// already says what A and B mean. A second enum for the same two sides is what
// OP-3 forbids.
import 'package:btge/btge.dart' show TeamId;
import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/football_components.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import '../communities/community_models.dart';
import '../communities/community_repository.dart';
import '../communities/join_community_flow.dart';
import '../auth/auth_service.dart';
import '../members/member_repository.dart';
import '../notifications/push_service.dart';
import '../results/match_result_card.dart';
import '../results/result_entry_screen.dart';
import '../results/result_models.dart';
import '../results/result_repository.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import '../teams/team_models.dart';
import '../teams/team_repository.dart';
import '../teams/teams_screen.dart';
import '../profile/player_identity.dart';
import 'match_card.dart';
import 'match_management_screen.dart';
import 'match_models.dart';
import 'match_service.dart';

/// The Match Details currently on screen, so a notification for that same match
/// refreshes it instead of stacking a second copy of it.
///
/// A registry rather than a Navigator inspection, because what the caller needs
/// is not "which route is on top" but "is this match already in front of the
/// reader, and how do I make it current" — and the screen is the only thing that
/// knows how to reload itself. The same singleton shape as `PushService` and
/// `PendingInvite`.
///
/// Binding is last-one-wins and unbinding is owner-checked, so two stacked
/// instances cannot have the lower one clear the upper one's registration when
/// it is disposed.
class CurrentMatchDetails {
  CurrentMatchDetails._();

  static final instance = CurrentMatchDetails._();

  Object? _owner;
  String? _matchId;
  VoidCallback? _reload;

  /// The match on screen, or null when Match Details is not open.
  String? get matchId => _matchId;

  void bind(Object owner, String matchId, VoidCallback reload) {
    _owner = owner;
    _matchId = matchId;
    _reload = reload;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _matchId = null;
    _reload = null;
  }

  /// Reloads the open Match Details when it is already showing [matchId].
  ///
  /// Returns whether it did, which is what tells a caller not to navigate.
  bool reloadIfShowing(String matchId) {
    if (_matchId != matchId || _reload == null) return false;
    _reload!();
    return true;
  }
}

/// What one build of Match Details shows.
///
/// Two answers rather than one, because "the match did not load" was covering
/// two different situations that need different screens. A member gets the
/// match; somebody who has not joined the community gets told so and offered
/// the way in. Anything else is still a failure and still reaches [ErrorState]
/// through the [FutureBuilder] — a refusal is not a broken connection, and this
/// is where the two stop being reported as the same thing.
sealed class _MatchView {
  const _MatchView();
}

class _MatchLoaded extends _MatchView {
  const _MatchLoaded(
    this.match,
    this.registrations,
    this.myRole, {
    this.result,
    this.lineup = const [],
  });

  final Match match;
  final List<MatchRegistration> registrations;
  final CommunityRole? myRole;

  /// What the match finished as, or null when it has not been played or nobody
  /// has recorded it yet.
  ///
  /// Read for every reader, not only an organizer: a recorded result is the
  /// community's, and `match_results_select_members` has always let any member
  /// of it read the row. What stays with the owner and the admins is *writing*
  /// one, which is `record_match_result`'s own check and unaffected by this.
  final MatchResult? result;

  /// The stored lineup behind that result — who played and on which side.
  /// Empty for a match with none, which is also a match with no result.
  final List<TeamAssignment> lineup;

  /// Whether there is a completed match with a recorded result to picture.
  ///
  /// Both halves are required. A result with no lineup cannot be drawn — there
  /// would be no teams on the card — and `record_match_result` refuses to store
  /// one, so this is a guard against a partial read rather than against a state
  /// the database allows.
  bool get isShareable => result != null && lineup.isNotEmpty;
}

class _MembershipRequired extends _MatchView {
  const _MembershipRequired(this.access);

  final MatchAccessContext access;
}

class MatchDetailsScreen extends StatefulWidget {
  const MatchDetailsScreen({
    super.key,
    required this.matchId,
    this.matchService,
    this.memberRepository,
    this.communityRepository,
    this.authService,
    this.resultRepository,
    this.teamRepository,
    this.renderer,
    this.shareService,
    this.downloader,
  });

  final String matchId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final MatchService? matchService;
  final MemberRepository? memberRepository;
  final CommunityRepository? communityRepository;
  final AuthService? authService;

  /// The result and the lineup behind the completed-match card. Optional for
  /// the same reason every other port here is: production builds its own.
  final ResultRepository? resultRepository;
  final TeamRepository? teamRepository;

  /// The share card engine's two seams, forwarded to [presentShareCard].
  /// Supplied only by tests; this screen composes no card of its own.
  final ShareCardRenderer? renderer;
  final ShareService? shareService;
  final ShareCardDownloader? downloader;

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  late final MatchService _matchService = widget.matchService ?? MatchService();
  late final MemberRepository _memberRepository =
      widget.memberRepository ?? MemberRepository();
  late final CommunityRepository _communityRepository =
      widget.communityRepository ?? CommunityRepository();
  late final AuthService _authService = widget.authService ?? AuthService();
  late final ResultRepository _resultRepository =
      widget.resultRepository ?? ResultRepository();
  late final TeamRepository _teamRepository =
      widget.teamRepository ?? TeamRepository();
  late Future<_MatchView> _dataFuture;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    CurrentMatchDetails.instance.bind(this, widget.matchId, _refresh);
    // A push that lands while this screen is open moves the roster — a
    // promotion, a removal, a rebalance — and nothing else would tell it. The
    // same signal Home already listens to, read the same way: re-fetch from the
    // database rather than trust the push, which is a pointer and not a record.
    PushService.instance.foregroundPushes.addListener(_refresh);
  }

  @override
  void dispose() {
    PushService.instance.foregroundPushes.removeListener(_refresh);
    CurrentMatchDetails.instance.unbind(this);
    super.dispose();
  }

  Future<_MatchView> _loadData() async {
    final Match match;
    try {
      match = await _matchService.fetchMatch(widget.matchId);
    } on Failure catch (failure) {
      final access = await _accessContextFor(failure);
      if (access != null && access.membershipRequired) {
        return _MembershipRequired(access);
      }
      rethrow;
    }

    final results = await Future.wait([
      _matchService.fetchRegistrations(widget.matchId),
      _memberRepository.fetchMyRole(match.communityId),
    ]);
    final registrations = results[0] as List<MatchRegistration>;
    final role = results[1] as CommunityRole?;

    // A match still to come has no result and no lineup worth the round trip,
    // so the two extra reads are made only once there is something to have
    // recorded. `isCompleted` is the derived answer rather than the stored
    // status, which is the same rule `v_completed_matches` applies.
    if (!match.isCompleted) {
      return _MatchLoaded(match, registrations, role);
    }

    // Issued together because they are independent, and tolerated separately
    // because neither is the match. A recorded result the reader cannot see is
    // a card they do not get; it is not a reason to fail a screen that has
    // already loaded the fixture and the roster.
    final played = await Future.wait([
      _resultRepository.fetchResult(widget.matchId).catchError(
            (Object _) => null,
          ),
      _teamRepository.fetchLineup(widget.matchId).catchError(
            (Object _) => const <TeamAssignment>[],
          ),
    ]);

    return _MatchLoaded(
      match,
      registrations,
      role,
      result: played[0] as MatchResult?,
      lineup: played[1] as List<TeamAssignment>,
    );
  }

  /// Asks *why* the match did not load, but only when the answer could be
  /// membership.
  ///
  /// `matches_select_community_members` (migration `0007`) filters the row out
  /// for a non-member, so the read fails as "there is no such match"
  /// ([NotFoundFailure]) or, where the policy refused the statement outright, as
  /// [AuthorizationFailure]. Those two are worth a second question. A dropped
  /// connection or a database fault is not: the match may well be readable, and
  /// asking would only turn one failure into two.
  ///
  /// Returns null when the question does not apply or could not be answered, in
  /// which case the original failure stands and the screen reports it.
  Future<MatchAccessContext?> _accessContextFor(Failure failure) async {
    if (failure is! NotFoundFailure && failure is! AuthorizationFailure) {
      return null;
    }
    try {
      return await _matchService.fetchAccessContext(widget.matchId);
    } on Failure catch (_) {
      return null;
    }
  }

  void _refresh() {
    // Guarded: this is now reached from a listener as well as from the widget
    // tree, and a push can arrive between dispose and the last frame.
    if (!mounted) return;
    setState(() {
      _dataFuture = _loadData();
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Every registration failure ends the same way, with a sentence, so the
  /// reason is free to choose which one. [fallback] covers a failure the
  /// registration RPCs do not name.
  String _registrationErrorMessage(
      AppLocalizations l10n, Failure failure, String fallback) {
    return switch (failure.reason) {
      FailureReason.overlappingMatch => l10n.errOverlappingMatch,
      FailureReason.matchClosed => l10n.errMatchClosed,
      FailureReason.alreadyRegistered => l10n.errAlreadyRegistered,
      FailureReason.notRegistered => l10n.errNotRegistered,
      FailureReason.registrationClosed => l10n.errRegistrationClosed,
      FailureReason.matchLocked => l10n.errMatchLocked,
      FailureReason.notCommunityMember => l10n.errNotCommunityMember,
      _ => fallback,
    };
  }

  /// Joins the community that holds this match, then opens the match.
  ///
  /// The existing flow, unchanged and not re-implemented: an OPEN community
  /// joins outright, one that requires its code asks for it, and being already a
  /// member is a normal answer. All this adds is what to do afterwards — reload,
  /// which is what turns the membership notice into the match.
  Future<void> _joinCommunity(MatchAccessContext access) async {
    final communityId = access.communityId;
    if (communityId == null || _isActionLoading) return;

    setState(() => _isActionLoading = true);
    final joined = await runJoinCommunity(
      context,
      repository: _communityRepository,
      communityId: communityId,
      joinPolicy: access.joinPolicy,
    );
    if (!mounted) return;
    setState(() => _isActionLoading = false);
    if (joined) _refresh();
  }

  Future<void> _join() async {
    final l10n = context.l10n;
    setState(() => _isActionLoading = true);
    try {
      final status = await _matchService.registerForMatch(widget.matchId);
      _showMessage(status == RegistrationStatus.confirmed
          ? l10n.joinedConfirmed
          : l10n.joinedReserve);
    } on Failure catch (failure) {
      _showMessage(
          _registrationErrorMessage(l10n, failure, l10n.joinMatchFailed));
    } catch (_) {
      _showMessage(l10n.joinMatchFailed);
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
        _refresh();
      }
    }
  }

  Future<void> _withdraw() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.withdrawConfirmTitle),
        content: Text(l10n.withdrawConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.withdrawMatchButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await _matchService.withdrawFromMatch(widget.matchId);
    } on Failure catch (failure) {
      _showMessage(
          _registrationErrorMessage(l10n, failure, l10n.withdrawMatchFailed));
    } catch (_) {
      _showMessage(l10n.withdrawMatchFailed);
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
        _refresh();
      }
    }
  }

  Future<void> _openManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MatchManagementScreen(matchId: widget.matchId),
      ),
    );
    if (!mounted) return;
    // The match may have been deleted from the management screen.
    try {
      await _matchService.fetchMatch(widget.matchId);
      _refresh();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// The teams of this match. Reading a lineup is a member's business, so the
  /// way in is offered to everyone who can already see the match; which
  /// controls the Teams screen then shows is its own decision.
  void _openTeams() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamsScreen(matchId: widget.matchId),
      ),
    );
  }

  /// The result of this match. Offered once the match has been played and only
  /// to an owner or admin — recording one is match management, and a match still
  /// to come has no result to enter. The database enforces the role; this only
  /// decides what is shown.
  /// A saved result closes the entry form and reports here, which is the screen
  /// that can actually show what changed. The form used to announce the save
  /// over itself and stay put, leaving the organizer to find their way back to
  /// see it — so the confirmation now arrives on the same screen as the result
  /// it is confirming.
  Future<void> _openResult() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResultEntryScreen(matchId: widget.matchId),
      ),
    );
    if (!mounted) return;

    // The reload comes first. Announcing the save over stale figures would be
    // the same mistake in a different place.
    _refresh();
    if (saved == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.resultSaved)));
    }
  }

  /// What to call each participant of the stored lineup.
  ///
  /// The roster's own rule, applied once and shared by the summary on screen and
  /// the card that leaves it, so the two can never name the same player
  /// differently. A participant with no seat left on the roster is a dash rather
  /// than an invented name: `KB-017` makes the lineup the record that somebody
  /// played, and it outlives their registration.
  Map<String, String> _resolveNames(
    AppLocalizations l10n,
    _MatchLoaded loaded,
  ) {
    final byParticipant = {
      for (final registration in loaded.registrations)
        registration.participantId: registration,
    };
    return {
      for (final assignment in loaded.lineup)
        assignment.participantId: switch (
            byParticipant[assignment.participantId]) {
          final MatchRegistration registration =>
            participantLabel(l10n, registration),
          _ => '—',
        },
    };
  }

  /// Composes the completed-match card for what is on screen and hands it to
  /// the engine.
  ///
  /// **Offered to every reader who can see the match, and it changes nothing.**
  /// A card is a picture of what the community already agreed happened; making
  /// one is not an edit, and the reader who takes it has no more authority
  /// afterwards than before. Recording or correcting the result stays behind
  /// `canManage` and behind `record_match_result`'s own check, which this does
  /// not touch.
  ///
  /// **Every value is already resolved before this runs.** Nothing here reads a
  /// repository: the result and the lineup arrived with the screen's own load,
  /// and the names are the ones the roster above is already showing — the same
  /// [participantLabel] rule, applied once and handed over rather than
  /// re-derived inside a card that could then disagree with the list behind it.
  Future<void> _shareResult(_MatchLoaded loaded) async {
    final result = loaded.result;
    if (result == null || loaded.lineup.isEmpty) return;
    final l10n = context.l10n;

    final avatars = {
      for (final registration in loaded.registrations)
        if (registration.avatarUrl case final String url)
          registration.participantId: url,
    };

    final data = MatchResultCardData(
      teamAScore: result.teamAScore,
      teamBScore: result.teamBScore,
      lineup: loaded.lineup,
      names: _resolveNames(l10n, loaded),
      avatars: avatars,
      goals: {
        for (final tally in result.goals) tally.userId: tally.goals,
      },
      mvpParticipantId: result.mvpUserId,
      communityName: loaded.match.communityName,
      // The day it was played, which for every match — recorded or scheduled —
      // is when it started.
      playedAt: loaded.match.startAt,
    );

    // The faces are fetched before the card is composed, not while it is. The
    // engine gives a template two frames to settle, which is ample for layout
    // and nowhere near enough for a network image — so a card composed without
    // this would show a blank disc for every player who has a picture. The
    // Teams screen does the same thing before its own card, for the same
    // reason.
    await _precacheFaces(avatars.values);
    if (!mounted) return;

    await presentShareCard(
      context,
      template: (context) => MatchResultCard(data: data),
      renderer: widget.renderer,
      shareService: widget.shareService,
      downloader: widget.downloader,
    );
  }

  /// Loads the lineup's pictures into the image cache.
  ///
  /// Best effort, and issued together because they are independent. A picture
  /// that will not load is not an error anywhere else in the app either, and the
  /// mark already falls back to a plain disc. `onError` is what keeps that true:
  /// without a handler `precacheImage` reports the failure to `FlutterError`,
  /// turning a missing photograph into an app-level error.
  Future<void> _precacheFaces(Iterable<String> urls) async {
    final unique = urls.toSet();
    if (unique.isEmpty) return;
    await Future.wait([
      for (final url in unique)
        precacheImage(NetworkImage(url), context, onError: (_, __) {}),
    ]);
  }

  String _positionLabel(BuildContext context, String position) {
    final l10n = context.l10n;
    return switch (position) {
      'GK' => l10n.positionGk,
      'DEF' => l10n.positionDef,
      'MID' => l10n.positionMid,
      'FWD' => l10n.positionFwd,
      _ => position,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentUserId = _authService.currentUserId;

    return FutureBuilder<_MatchView>(
      future: _dataFuture,
      builder: (context, snapshot) {
        // These states have no match data from which to construct the Club
        // hero. They retain the existing task header, including its visible
        // way back, while the loaded state below is the approved Club place.
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppHeader(title: Text(l10n.matchDetailsTitle)),
            body: const LoadingState(),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppHeader(title: Text(l10n.matchDetailsTitle)),
            body: ErrorState(onRetry: _refresh),
          );
        }

        final view = snapshot.data!;
        // Not a member of the community that holds this match. The match is
        // still not shown — the database never sent it — but what is on screen
        // is now the reason and the way past it rather than a failure the reader
        // can do nothing about.
        if (view is _MembershipRequired) {
          return Scaffold(
            appBar: AppHeader(title: Text(l10n.matchDetailsTitle)),
            body: EmptyState(
              icon: Icons.lock_outline,
              title: l10n.matchMembershipRequiredTitle,
              message: view.access.communityName == null
                  ? l10n.matchMembershipRequiredBodyUnnamed
                  : l10n.matchMembershipRequiredBody(
                      view.access.communityName!,
                    ),
              action: FilledButton.icon(
                onPressed:
                    _isActionLoading ? null : () => _joinCommunity(view.access),
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: Text(l10n.joinCommunityButton),
              ),
            ),
          );
        }

        final loaded = view as _MatchLoaded;
          final match = loaded.match;
          final registrations = loaded.registrations;
          final myRole = loaded.myRole;
          final confirmed = [
            for (final r in registrations)
              if (r.status == RegistrationStatus.confirmed) r,
          ];
          final reserves = [
            for (final r in registrations)
              if (r.status == RegistrationStatus.reserve) r,
          ];
          // `userId` is null on a Professional Guest's seat, and so is
          // `currentUserId` when nobody is signed in — comparing them without
          // the guard would match a signed-out reader to a guest.
          final myRegistration = registrations
              .where((r) => r.userId != null && r.userId == currentUserId)
              .firstOrNull;
          // Management is a community role now, not a creator privilege
          // (PD-07). The server enforces it; this only decides what is shown.
          final canManage = myRole?.atLeast(CommunityRole.admin) ?? false;
          // Registration is possible until kickoff or until the cap is hit.
          final registrationClosed =
              registrations.length >= match.maxRegistration;
          final isOpen = match.isOpenForChanges;
          // Starting places taken -> further sign-ups join the reserve.
          final startingFull = confirmed.length >= match.startingPlayers;

        return Scaffold(
          // The sheet rides up over the same green ground as the hero. Keeping
          // the scaffold green is what lets its rounded corners reveal the hero
          // rather than a pale page behind it.
          backgroundColor: GoColors.bgHero,
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: ClubHero(
                  bar: ClubHeroBar(
                    title: l10n.matchDetailsTitle,
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  identity: _MatchHeroIdentity(match: match),
                ),
              ),
              Expanded(
                child: ClubSheet(
                  child: RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: Gap.xxl),
                      children: [

                        // What this player's own position in the match is, and
                        // the one thing they can do about it. First, above the
                        // roster: it is the only actionable thing on the screen
                        // for most readers.
                        if (isOpen)
                          RegistrationStateView(
                            myRegistration: myRegistration,
                            registrationClosed: registrationClosed,
                            startingFull: startingFull,
                            busy: _isActionLoading,
                            onJoin: _join,
                            onWithdraw: _withdraw,
                            // Counts, not rules. Every one of these was already
                            // worked out above for the roster below; the capacity
                            // bar is a second reading of the same numbers rather
                            // than a second opinion about them.
                            confirmedCount: confirmed.length,
                            startingPlayers: match.startingPlayers,
                            reserveAllowance:
                                match.maxRegistration - match.startingPlayers,
                            status: match.effectiveStatus,
                          ),

                        // What the match finished as, for every reader who can
                        // see the match. Above the roster, because on a played
                        // match the result is what the reader came for.
                        if (match.isCompleted)
                          _ResultSummary(
                            result: loaded.result,
                            names: _resolveNames(l10n, loaded),
                            onShare: loaded.isShareable
                                ? () => _shareResult(loaded)
                                : null,
                          ),

                        if ((match.description?.trim().isNotEmpty ?? false) ||
                            match.isLocked ||
                            match.isHistorical)
                          SectionCard(
                            children: [
                              if (match.description?.trim().isNotEmpty ?? false)
                                ListTile(
                                  leading: const Icon(Icons.notes_outlined),
                                  title: Text(l10n.matchDescriptionLabel),
                                  subtitle: Text(match.description!),
                                ),
                              // A match nobody could have joined says so.
                              // Without it a recorded fixture reads as an
                              // ordinary one whose roster nobody filled.
                              if (match.isHistorical)
                                ListTile(
                                  leading: const Icon(Icons.history),
                                  title: Text(l10n.historicalMatchBadge),
                                  subtitle:
                                      Text(l10n.historicalMatchToggleNote),
                                ),
                              if (match.isLocked)
                                ListTile(
                                  leading: const Icon(Icons.lock_outline),
                                  title: Text(l10n.matchLockedNote),
                                ),
                            ],
                          ),

                        SectionCard(
                          padding: EdgeInsets.zero,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.groups_2_outlined),
                              title: Text(l10n.teamsTitle),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _openTeams,
                            ),
                            if (canManage && match.isCompleted)
                              ListTile(
                                leading: const Icon(Icons.scoreboard_outlined),
                                title: Text(l10n.matchResultTitle),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _openResult,
                              ),
                            if (canManage)
                              ListTile(
                                leading: const Icon(Icons.tune),
                                title: Text(l10n.matchManagementTitle),
                                subtitle: Text(l10n.matchManagementSubtitle),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _openManagement,
                              ),
                          ],
                        ),

                        // Whoever created this match used to manage it. Say
                        // where the controls went instead of leaving a blank
                        // space (PD-07).
                        if (!canManage && match.createdBy == currentUserId)
                          FootNote(
                            l10n.matchManageOrganizersOnly,
                            padding: const EdgeInsets.fromLTRB(
                              kPageMargin,
                              Gap.xs,
                              kPageMargin,
                              0,
                            ),
                          ),

                        SectionHeading(
                          title: l10n.startingPlayersLabel,
                          subtitle:
                              '${confirmed.length}/${match.startingPlayers}',
                        ),
                        if (confirmed.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: kPageMargin,
                            ),
                            child: EmptyState(
                              icon: Icons.person_outline,
                              message: l10n.matchRosterEmpty,
                            ),
                          )
                        else
                          SectionCard(
                            padding: EdgeInsets.zero,
                            children: [
                              for (final registration in confirmed)
                                _PlayerRow(
                                  name: participantLabel(l10n, registration),
                                  position: participantSubtitle(
                                    l10n,
                                    registration,
                                    (position) =>
                                        _positionLabel(context, position),
                                  ),
                                  userId: registration.userId,
                                  avatarUrl: registration.avatarUrl,
                                  isProfessionalGuest:
                                      registration.isProfessionalGuest,
                                ),
                            ],
                          ),

                        // Reserve queue, in promotion order.
                        if (reserves.isNotEmpty) ...[
                          SectionHeading(
                            title: l10n.reserveListTitle,
                            count: reserves.length,
                          ),
                          SectionCard(
                            padding: EdgeInsets.zero,
                            children: [
                              for (final (index, registration) in reserves.indexed)
                                _PlayerRow(
                                  name: participantLabel(l10n, registration),
                                  position: participantSubtitle(
                                    l10n,
                                    registration,
                                    (position) =>
                                        _positionLabel(context, position),
                                  ),
                                  userId: registration.userId,
                                  avatarUrl: registration.avatarUrl,
                                  queuePosition: index + 1,
                                  isProfessionalGuest:
                                      registration.isProfessionalGuest,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What a played match finished as: the score, who scored, who was best on the
/// pitch, and the way to send it.
///
/// **A report, not a form.** Everything here is read-only for every reader.
/// Correcting any of it is the Result screen's job and stays behind the
/// organizer's role; this is the same information offered to the people it
/// happened to.
///
/// A completed match with nothing recorded says so rather than showing an empty
/// scoreboard — the match is over and the result simply has not been entered
/// yet, which is a state the reader can understand and, if they run the
/// community, act on from the row below.
class _ResultSummary extends StatelessWidget {
  const _ResultSummary({
    required this.result,
    required this.names,
    required this.onShare,
  });

  final MatchResult? result;

  /// Participant id to the name the roster above is showing for them. Handed in
  /// rather than derived, so the summary and the list below it agree.
  final Map<String, String> names;

  /// Null when there is nothing to picture, which disables the action rather
  /// than hiding it behind a second rule.
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = this.result;

    if (result == null) {
      return SectionCard(
        children: [
          ListTile(
            leading: const Icon(Icons.scoreboard_outlined),
            title: Text(l10n.matchResultTitle),
            subtitle: Text(l10n.matchResultNotRecorded),
          ),
        ],
      );
    }

    final scorers = [
      for (final tally in result.goals)
        if (names.containsKey(tally.userId)) tally,
    ]..sort((a, b) => b.goals.compareTo(a.goals));

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(Layout.cardInner),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The score, pinned left to right. Two numbers in a fixed order
              // either side of a dash is exactly the run a bidirectional
              // paragraph will reverse, and a reversed score is a wrong result
              // rather than an untidy line.
              Row(
                textDirection: TextDirection.ltr,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ScoreHalf(
                    label: l10n.teamAName,
                    score: result.teamAScore,
                    won: result.winner == TeamId.a,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                    child: Text(
                      '–',
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  _ScoreHalf(
                    label: l10n.teamBName,
                    score: result.teamBScore,
                    won: result.winner == TeamId.b,
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(
                result.isDraw
                    ? l10n.matchResultDrawLabel
                    : l10n.matchResultWinnerLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (scorers.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.sports_soccer),
            title: Text(l10n.matchResultScorersLabel),
            subtitle: Text(
              [
                for (final tally in scorers)
                  '${names[tally.userId] ?? '—'} (${tally.goals})',
              ].join('، '),
            ),
          ),
        if (result.mvpUserId != null)
          ListTile(
            leading: const Icon(Icons.star_rounded),
            title: Text(l10n.mvpLabel),
            subtitle: Text(names[result.mvpUserId] ?? '—'),
          ),
        // Offered to everyone who reached this screen. Membership is what the
        // database already required to read the match at all, so there is no
        // second permission to ask about here.
        ListTile(
          leading: const Icon(Icons.ios_share),
          enabled: onShare != null,
          title: Text(l10n.shareMatchResultAction),
          trailing: const Icon(Icons.chevron_right),
          onTap: onShare,
        ),
      ],
    );
  }
}

/// One side of the score line.
class _ScoreHalf extends StatelessWidget {
  const _ScoreHalf({
    required this.label,
    required this.score,
    required this.won,
  });

  final String label;
  final int score;
  final bool won;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$score',
          textDirection: TextDirection.ltr,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: won ? GoColors.primaryDeep : GoColors.onSurface,
          ),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// The match's identity and facts inside the Club hero.
///
/// This is a presentation of data Match Details already holds. It deliberately
/// owns no status or registration decisions: [Match.effectiveStatus] and the
/// screen's registration calculations remain the existing sources of truth.
class _MatchHeroIdentity extends StatelessWidget {
  const _MatchHeroIdentity({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommunityCrest(
          name: match.communityName ?? match.displayName,
          size: 54,
          onHero: true,
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      match.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  GoStatusChip(
                    label: matchStatusLabel(context, match.effectiveStatus),
                    tone: match.effectiveStatus.chipTone,
                    icon: match.isLocked ? Icons.lock_outline : null,
                  ),
                ],
              ),
              if (match.communityName != null) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  match.communityName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
              const SizedBox(height: Gap.sm),
              _HeroFact(
                icon: Icons.place_outlined,
                label: l10n.locationLabel,
                value: match.location,
              ),
              const SizedBox(height: Gap.xs),
              _HeroFact(
                icon: Icons.schedule_outlined,
                label: l10n.dateLabel,
                // The existing formatter isolates the time range, keeping its
                // numeric order correct inside an Arabic fact line.
                value: formatMatchTime(context, match),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One concise fact on the dark Match Details hero.
class _HeroFact extends StatelessWidget {
  const _HeroFact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(icon, size: IconSize.chip, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One participant on a roster. [queuePosition] numbers the reserve queue,
/// which is the order people are promoted in and therefore worth showing.
///
/// A registered player is their face, their name, and a tap that opens their
/// Player Profile. Nothing else claims this row — it is a read-only list — so
/// the whole tile is the control.
///
/// A Professional Guest is drawn as one and taps to nothing. They have no
/// account and therefore no record to open, and offering a tap that leads
/// nowhere would be worse than offering none.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.name,
    required this.position,
    this.userId,
    this.avatarUrl,
    this.queuePosition,
    this.isProfessionalGuest = false,
  });

  final String name;
  final String position;

  /// Whose profile this row opens. Null for a Professional Guest, which is the
  /// same thing as saying there is no profile.
  final String? userId;

  final String? avatarUrl;
  final int? queuePosition;

  /// A Professional Guest is a stand-in for this match only, and the roster has
  /// to say so at a glance rather than only in the name. The avatar carries the
  /// tertiary colour and a distinct icon, which is the difference a reader sees
  /// before they read anything.
  final bool isProfessionalGuest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final userId = this.userId;

    return ListTile(
      key: isProfessionalGuest ? const Key('guestRow') : null,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The queue position kept its place rather than its disc: it is what
          // says who is promoted next, and the face now occupies the circle it
          // used to sit in.
          if (queuePosition != null) ...[
            SizedBox(
              width: 18,
              child: Text(
                '$queuePosition',
                textAlign: TextAlign.end,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: Gap.sm),
          ],
          PlayerAvatar(
            avatarUrl: avatarUrl,
            fullName: name,
            isProfessionalGuest: isProfessionalGuest,
          ),
        ],
      ),
      title: Text(name),
      subtitle: Text(
        position,
        style: isProfessionalGuest
            ? theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary)
            : null,
      ),
      onTap: userId == null ? null : () => openPlayerProfile(context, userId),
    );
  }
}
