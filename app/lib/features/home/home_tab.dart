import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../../core/states.dart';
import '../admin/admin_repository.dart';
import '../admin/admin_screen.dart';
import '../auth/auth_service.dart';
import '../discover/discover_widgets.dart';
import '../matches/app_settings.dart';
import '../matches/match_card.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';
import '../notifications/notification_service.dart';
import '../notifications/notifications_screen.dart';
import '../notifications/push_service.dart';

typedef _HomeData = ({String firstName, List<Match> matches, int unread});

/// Home tab: greeting + upcoming matches across all the user's communities.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _matchService = MatchService();
  final _notificationService = NotificationService();
  final _authService = AuthService();
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // A push that lands while Home is already open moves the unread count, and
    // nothing else would tell this screen. The push itself is not rendered —
    // the badge is re-read from the Notification Center, which is the record.
    PushService.instance.foregroundPushes.addListener(_refresh);
  }

  @override
  void dispose() {
    PushService.instance.foregroundPushes.removeListener(_refresh);
    super.dispose();
  }

  Future<_HomeData> _load() async {
    // Refresh the global reserve setting whenever Home loads.
    await AppSettings.load();
    final firstName = await _authService.fetchCurrentUserFirstName();
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
    if (!mounted) return;
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
      appBar: AppHeader(
        title: Text(l10n.homeTitle),
        actions: [
          // Only a System Admin ever sees this. Hiding it is a convenience:
          // every admin RPC checks is_system_admin() server-side regardless.
          FutureBuilder<bool>(
            future: AdminRepository().isSystemAdmin(),
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return IconButton(
                tooltip: l10n.adminTitle,
                icon: const Icon(Icons.shield_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminScreen()),
                ),
              );
            },
          ),
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
          // The profile and logging out are the player's own actions rather
          // than Home's, and they now live in the header's identity menu —
          // where they are on every screen instead of only this one.
        ],
      ),
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SkeletonFade(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  kPageMargin,
                  Gap.lg,
                  kPageMargin,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: 200, height: 22),
                    SizedBox(height: Gap.xl),
                    MatchCardSkeleton(),
                    SizedBox(height: Gap.md),
                    MatchCardSkeleton(),
                  ],
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return ErrorState(onRetry: _refresh);
          }

          final data = snapshot.data!;
          final matches = data.matches;

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: Gap.xl),
              children: [
                // Formal greeting near the top, before the main content.
                if (data.firstName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kPageMargin,
                      Gap.lg,
                      kPageMargin,
                      0,
                    ),
                    child: Text(
                      l10n.homeGreeting(data.firstName),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                if (matches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kPageMargin,
                      Gap.xxl,
                      kPageMargin,
                      0,
                    ),
                    child: DiscoverEmpty(
                      icon: Icons.sports_soccer,
                      message: l10n.upcomingMatchesEmpty,
                    ),
                  )
                else ...[
                  DiscoverSectionHeader(
                    title: l10n.upcomingMatchesTitle,
                    subtitle: l10n.homeUpcomingSubtitle,
                  ),
                  for (final match in matches)
                    MatchCard(
                      match: match,
                      showCommunityName: true,
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
