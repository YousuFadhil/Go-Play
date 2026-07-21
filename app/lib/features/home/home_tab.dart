import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../auth/auth_service.dart';
import '../matches/match_card.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';

/// Home tab: upcoming matches across all the user's groups.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _matchService = MatchService();
  late Future<List<Match>> _matchesFuture;

  @override
  void initState() {
    super.initState();
    _matchesFuture = _matchService.fetchUpcomingMatches();
  }

  void _refresh() {
    setState(() {
      _matchesFuture = _matchService.fetchUpcomingMatches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            tooltip: l10n.logoutLabel,
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().logout(),
          ),
        ],
      ),
      body: FutureBuilder<List<Match>>(
        future: _matchesFuture,
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

          final matches = snapshot.data ?? const [];
          if (matches.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sports_soccer, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      l10n.upcomingMatchesEmpty,
                      textAlign: TextAlign.center,
                    ),
                    if (Supabase.instance.client.auth.currentUser?.email
                        case final email?) ...[
                      const SizedBox(height: 8),
                      Text(email, textDirection: TextDirection.ltr),
                    ],
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            ),
          );
        },
      ),
    );
  }
}
