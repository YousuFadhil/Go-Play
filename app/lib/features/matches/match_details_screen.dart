import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
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
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.loadFailed),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: Text(l10n.retryButton),
                  ),
                ],
              ),
            );
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    match.displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (canManage)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: OutlinedButton.icon(
                      onPressed: _openManagement,
                      icon: const Icon(Icons.settings),
                      label: Text(l10n.matchManagementTitle),
                    ),
                  ),
                // Whoever created this match used to manage it. Say where the
                // controls went instead of leaving a blank space (PD-07).
                if (!canManage && match.createdBy == currentUserId)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(
                      l10n.matchManageOrganizersOnly,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (match.communityName != null)
                  ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text(match.communityName!),
                  ),
                ListTile(
                  leading: const Icon(Icons.place),
                  title: Text(l10n.locationLabel),
                  subtitle: Text(match.location),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(l10n.dateLabel),
                  subtitle: Text(formatMatchTime(context, match)),
                ),
                ListTile(
                  leading: Icon(
                      match.isLocked ? Icons.lock_outline : Icons.info_outline),
                  title: Text(matchStatusLabel(context, match.effectiveStatus)),
                  subtitle: Text(match.isLocked
                      ? l10n.matchLockedNote
                      : '${registrations.length}/${match.maxRegistration}'),
                ),
                if (match.description != null && match.description!.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.notes),
                    title: Text(l10n.matchDescriptionLabel),
                    subtitle: Text(match.description!),
                  ),
                ListTile(
                  leading: const Icon(Icons.groups_2),
                  title: Text(l10n.teamsTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openTeams,
                ),
                if (canManage && match.isCompleted)
                  ListTile(
                    leading: const Icon(Icons.scoreboard),
                    title: Text(l10n.matchResultTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openResult,
                  ),

                // Player status card + join/withdraw actions.
                if (isOpen)
                  Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (myRegistration != null) ...[
                            Row(
                              children: [
                                Icon(
                                  myRegistration.status ==
                                          RegistrationStatus.confirmed
                                      ? Icons.check_circle
                                      : Icons.hourglass_top,
                                  color: myRegistration.status ==
                                          RegistrationStatus.confirmed
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    myRegistration.status ==
                                            RegistrationStatus.confirmed
                                        ? l10n.youAreConfirmed
                                        : l10n.youAreReserve,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _isActionLoading ? null : _withdraw,
                              child: Text(l10n.withdrawMatchButton),
                            ),
                          ] else if (registrationClosed) ...[
                            Text(l10n.errRegistrationClosed),
                          ] else ...[
                            if (startingFull) ...[
                              Text(l10n.matchFullNote),
                              const SizedBox(height: 12),
                            ],
                            FilledButton(
                              onPressed: _isActionLoading ? null : _join,
                              child: _isActionLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(l10n.joinMatchButton),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // Confirmed roster.
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '${l10n.startingPlayersLabel} '
                    '(${confirmed.length}/${match.startingPlayers})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final registration in confirmed)
                  ListTile(
                    dense: true,
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(registration.fullName),
                    subtitle:
                        Text(_positionLabel(context, registration.position)),
                  ),

                // Reserve queue, in promotion order.
                if (reserves.isNotEmpty) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '${l10n.reserveListTitle} (${reserves.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final (index, registration) in reserves.indexed)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(registration.fullName),
                      subtitle:
                          Text(_positionLabel(context, registration.position)),
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
