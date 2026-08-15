import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../communities/community_models.dart';
import '../communities/community_repository.dart';
import '../communities/join_community_flow.dart';
import '../auth/auth_service.dart';
import '../members/member_repository.dart';
import '../notifications/push_service.dart';
import '../results/result_entry_screen.dart';
import '../teams/teams_screen.dart';
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
  const _MatchLoaded(this.match, this.registrations, this.myRole);

  final Match match;
  final List<MatchRegistration> registrations;
  final CommunityRole? myRole;
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
  });

  final String matchId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final MatchService? matchService;
  final MemberRepository? memberRepository;
  final CommunityRepository? communityRepository;
  final AuthService? authService;

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
    return _MatchLoaded(
      match,
      results[0] as List<MatchRegistration>,
      results[1] as CommunityRole?,
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

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.matchDetailsTitle)),
      body: FutureBuilder<_MatchView>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _refresh);
          }

          final view = snapshot.data!;
          // Not a member of the community that holds this match. The match is
          // still not shown — the database never sent it — but what is on
          // screen is now the reason and the way past it rather than a failure
          // the reader can do nothing about.
          if (view is _MembershipRequired) {
            return EmptyState(
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

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: Gap.xxl),
              children: [
                _MatchHeader(match: match, registrations: registrations.length),

                // What this player's own position in the match is, and the one
                // thing they can do about it. First, above the roster: it is
                // the only actionable thing on the screen for most readers.
                if (isOpen)
                  _RegistrationPanel(
                    myRegistration: myRegistration,
                    registrationClosed: registrationClosed,
                    startingFull: startingFull,
                    busy: _isActionLoading,
                    onJoin: _join,
                    onWithdraw: _withdraw,
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

                // Whoever created this match used to manage it. Say where the
                // controls went instead of leaving a blank space (PD-07).
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
                  subtitle: '${confirmed.length}/${match.startingPlayers}',
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
                            (position) => _positionLabel(context, position),
                          ),
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
                            (position) => _positionLabel(context, position),
                          ),
                          queuePosition: index + 1,
                          isProfessionalGuest:
                              registration.isProfessionalGuest,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The match itself: what it is called, where and when, and how full it is.
///
/// One panel rather than five [ListTile]s. Location, time and status are not
/// three separate subjects a reader navigates between — they are one answer to
/// "what is this match", and a list of rows made the reader assemble it.
class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.match, required this.registrations});

  final Match match;
  final int registrations;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.lg,
        kPageMargin,
        Gap.sm,
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      match.displayName,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  _StatusPill(
                    label: matchStatusLabel(context, match.effectiveStatus),
                    locked: match.isLocked,
                  ),
                ],
              ),
              if (match.communityName != null) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  match.communityName!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: Gap.md),
              _Fact(
                icon: Icons.place_outlined,
                label: l10n.locationLabel,
                value: match.location,
              ),
              const SizedBox(height: Gap.sm),
              _Fact(
                icon: Icons.schedule_outlined,
                label: l10n.dateLabel,
                value: formatMatchTime(context, match),
              ),
              const SizedBox(height: Gap.sm),
              _Fact(
                icon: Icons.groups_outlined,
                label: l10n.startingPlayersLabel,
                value: '$registrations/${match.maxRegistration}',
              ),
              if (match.description != null &&
                  match.description!.trim().isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                _Fact(
                  icon: Icons.notes_outlined,
                  label: l10n.matchDescriptionLabel,
                  value: match.description!,
                ),
              ],
              if (match.isLocked) ...[
                const SizedBox(height: Gap.md),
                Text(
                  l10n.matchLockedNote,
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

/// One fact about the match: what it is, and what it says.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.locked});

  final String label;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked) ...[
            Icon(Icons.lock_outline, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: Gap.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where this player stands in this match, and the one action that follows.
class _RegistrationPanel extends StatelessWidget {
  const _RegistrationPanel({
    required this.myRegistration,
    required this.registrationClosed,
    required this.startingFull,
    required this.busy,
    required this.onJoin,
    required this.onWithdraw,
  });

  final MatchRegistration? myRegistration;
  final bool registrationClosed;
  final bool startingFull;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final registration = myRegistration;

    final children = <Widget>[];

    if (registration != null) {
      final isConfirmed = registration.status == RegistrationStatus.confirmed;
      children.addAll([
        Row(
          children: [
            Icon(
              isConfirmed ? Icons.check_circle : Icons.hourglass_top,
              // The scheme's own colours, not `Colors.green` and
              // `Colors.orange`: a hard-coded hue ignores the theme and, on a
              // tinted surface, lands somewhere the palette never goes.
              color: isConfirmed ? scheme.primary : scheme.tertiary,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                isConfirmed ? l10n.youAreConfirmed : l10n.youAreReserve,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        // Withdrawing is not the screen's purpose, so it is outlined rather
        // than filled — but it is the only action here, so it spans the card.
        OutlinedButton.icon(
          onPressed: busy ? null : onWithdraw,
          icon: const Icon(Icons.logout, size: 18),
          label: Text(l10n.withdrawMatchButton),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(kButtonHeight),
          ),
        ),
      ]);
    } else if (registrationClosed) {
      children.add(Row(
        children: [
          Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              l10n.errRegistrationClosed,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ));
    } else {
      if (startingFull) {
        children.addAll([
          Text(
            l10n.matchFullNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Gap.md),
        ]);
      }
      children.add(FilledButton.icon(
        onPressed: busy ? null : onJoin,
        icon: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add, size: 18),
        label: Text(l10n.joinMatchButton),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.sm,
        kPageMargin,
        Gap.sm,
      ),
      child: Card(
        color: scheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// One name on a roster. [queuePosition] numbers the reserve queue, which is
/// the order people are promoted in and therefore worth showing.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.name,
    required this.position,
    this.queuePosition,
    this.isProfessionalGuest = false,
  });

  final String name;
  final String position;
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
    final background = isProfessionalGuest
        ? scheme.tertiaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = isProfessionalGuest
        ? scheme.onTertiaryContainer
        : scheme.onSurfaceVariant;

    return ListTile(
      key: isProfessionalGuest ? const Key('guestRow') : null,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: background,
        foregroundColor: foreground,
        child: queuePosition == null
            ? Icon(
                isProfessionalGuest
                    ? Icons.workspace_premium_outlined
                    : Icons.person,
                size: 20,
              )
            : Text(
                '$queuePosition',
                style: theme.textTheme.labelLarge?.copyWith(color: foreground),
              ),
      ),
      title: Text(name),
      subtitle: Text(
        position,
        style: isProfessionalGuest
            ? theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary)
            : null,
      ),
    );
  }
}
