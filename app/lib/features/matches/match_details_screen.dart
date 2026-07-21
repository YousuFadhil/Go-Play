import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import 'match_card.dart';
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
  late Future<(Match, List<MatchRegistration>)> _dataFuture;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<(Match, List<MatchRegistration>)> _loadData() async {
    final results = await Future.wait([
      _matchService.fetchMatch(widget.matchId),
      _matchService.fetchRegistrations(widget.matchId),
    ]);
    return (results[0] as Match, results[1] as List<MatchRegistration>);
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

  String _registrationErrorMessage(
      AppLocalizations l10n, RegistrationError error) {
    return switch (error) {
      RegistrationError.overlappingMatch => l10n.errOverlappingMatch,
      RegistrationError.matchClosed => l10n.errMatchClosed,
      RegistrationError.alreadyRegistered => l10n.errAlreadyRegistered,
      RegistrationError.notRegistered => l10n.errNotRegistered,
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
    } on RegistrationException catch (e) {
      _showMessage(_registrationErrorMessage(l10n, e.error));
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
    } on RegistrationException catch (e) {
      _showMessage(_registrationErrorMessage(l10n, e.error));
    } catch (_) {
      _showMessage(l10n.withdrawMatchFailed);
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
        _refresh();
      }
    }
  }

  Future<void> _cancelMatch() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.cancelMatchConfirmTitle),
        content: Text(l10n.cancelMatchConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.confirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.confirmYes),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _matchService.cancelMatch(widget.matchId);
      _refresh();
    } catch (_) {
      _showMessage(l10n.matchCancelFailed);
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
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.matchDetailsTitle)),
      body: FutureBuilder<(Match, List<MatchRegistration>)>(
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

          final (match, registrations) = snapshot.data!;
          final confirmed = [
            for (final r in registrations)
              if (r.status == RegistrationStatus.confirmed) r,
          ];
          final reserves = [
            for (final r in registrations)
              if (r.status == RegistrationStatus.reserve) r,
          ];
          final myRegistration = registrations
              .where((r) => r.userId == currentUserId)
              .firstOrNull;
          final isCreator = match.createdBy == currentUserId;
          final isOpen = match.status == MatchStatus.open &&
              match.startAt.isAfter(DateTime.now());
          final isFull = confirmed.length >= match.maxPlayers;

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (match.groupName != null)
                  ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text(match.groupName!),
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
                  leading: const Icon(Icons.info_outline),
                  title: Text(matchStatusLabel(context, match.status)),
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
                          ] else ...[
                            if (isFull) ...[
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
                    '${l10n.playersCountLabel} '
                    '(${confirmed.length}/${match.maxPlayers})',
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

                if (isCreator && match.status == MatchStatus.open)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: _cancelMatch,
                      icon: const Icon(Icons.event_busy),
                      label: Text(l10n.cancelMatchButton),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
