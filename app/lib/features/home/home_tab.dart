import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../auth/auth_service.dart';
import '../matches/match_card.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import '../notifications/notification_service.dart';
import '../notifications/notifications_screen.dart';

typedef _HomeData = ({String firstName, List<Match> matches, int unread});

/// Home tab: greeting + upcoming matches across all the user's groups.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _matchService = MatchService();
  final _notificationService = NotificationService();
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    String firstName = '';
    if (uid != null) {
      final profile = await client
          .from('users')
          .select('full_name')
          .eq('id', uid)
          .maybeSingle();
      final fullName = (profile?['full_name'] as String?)?.trim() ?? '';
      firstName = fullName.isEmpty ? '' : fullName.split(RegExp(r'\s+')).first;
    }
    final results = await Future.wait([
      _matchService.fetchUpcomingMatches(),
      _notificationService.unreadCount(),
    ]);
    return (
      firstName: firstName,
      matches: results[0] as List<Match>,
      unread: results[1] as int,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          FutureBuilder<_HomeData>(
            future: _future,
            builder: (context, snapshot) {
              final unread = snapshot.data?.unread ?? 0;
              return IconButton(
                tooltip: l10n.notificationsTitle,
                onPressed: _openNotifications,
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              );
            },
          ),
          IconButton(
            tooltip: l10n.logoutLabel,
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().logout(),
          ),
        ],
      ),
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
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

          final data = snapshot.data!;
          final matches = data.matches;

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Formal greeting near the top, before the main content.
                if (data.firstName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      l10n.homeGreeting(data.firstName),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                if (matches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 32),
                        const Icon(Icons.sports_soccer, size: 64),
                        const SizedBox(height: 16),
                        Text(l10n.upcomingMatchesEmpty,
                            textAlign: TextAlign.center),
                      ],
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Text(
                      l10n.upcomingMatchesTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final match in matches)
                    MatchCard(
                      match: match,
                      showGroupName: true,
                      onChanged: _refresh,
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
