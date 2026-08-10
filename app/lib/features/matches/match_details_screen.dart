import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../communities/community_models.dart';
import '../auth/auth_service.dart';
import '../members/member_repository.dart';
import '../results/result_entry_screen.dart';
import '../teams/teams_screen.dart';
import 'match_card.dart';
import 'match_management_screen.dart';
import 'match_models.dart';
import 'match_service.dart';

class MatchDetailsScreen extends StatefulWidget {
  const MatchDetailsScreen({super.key, required this.matchId});

  final String matchId;

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  final _matchService = MatchService();
  final _memberRepository = MemberRepository();
  final _authService = AuthService();
  late Future<(Match, List<MatchRegistration>, CommunityRole?)> _dataFuture;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<(Match, List<MatchRegistration>, CommunityRole?)> _loadData() async {
    final match = await _matchService.fetchMatch(widget.matchId);
    final results = await Future.wait([
      _matchService.fetchRegistrations(widget.matchId),
      _memberRepository.fetchMyRole(match.communityId),
    ]);
    return (
      match,
      results[0] as List<MatchRegistration>,
      results[1] as CommunityRole?,
    );
  }

  void _refresh() {
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
      body: FutureBuilder<(Match, List<MatchRegistration>, CommunityRole?)>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _refresh);
          }

          final (match, registrations, myRole) = snapshot.data!;
          final confirmed = [
            for (final r in registrations)
              if (r.status == RegistrationStatus.confirmed) r,
          ];
          final reserves = [
            for (final r in registrations)
              if (r.status == RegistrationStatus.reserve) r,
          ];
          final myRegistration =
              registrations.where((r) => r.userId == currentUserId).firstOrNull;
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
                          name: registration.fullName,
                          position:
                              _positionLabel(context, registration.position),
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
                          name: registration.fullName,
                          position:
                              _positionLabel(context, registration.position),
                          queuePosition: index + 1,
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
  });

  final String name;
  final String position;
  final int? queuePosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurfaceVariant,
        child: queuePosition == null
            ? const Icon(Icons.person, size: 20)
            : Text(
                '$queuePosition',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
      ),
      title: Text(name),
      subtitle: Text(position),
    );
  }
}
