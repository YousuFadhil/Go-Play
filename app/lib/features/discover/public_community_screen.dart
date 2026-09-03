import '../../core/club_place.dart';
import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../auth/auth_prompt.dart';
import '../auth/auth_service.dart';
import 'discover_repository.dart';
import 'discover_widgets.dart';

/// A community, as a visitor sees it before signing in.
///
/// Not a reduced [CommunityDetailsScreen] with half its tabs hidden. That screen
/// is built out of a member's reads — the roster, the join code, the dashboard,
/// the leaderboards — and every one of them would fail without a session; hiding
/// them would leave a shell whose loading behaviour depended on failures. This
/// asks the public read model the one question a guest is entitled to ask, and
/// answers it completely.
///
/// What a guest is shown is therefore the whole of what this screen has: the
/// community, how big it is, and what it has scheduled. Who the members are is
/// not here, and neither is the join code — a code is the credential that a
/// CODE_REQUIRED community is entered with, and publishing it on the page that
/// invites people to join would make the policy decorative.
class PublicCommunityScreen extends StatefulWidget {
  const PublicCommunityScreen({
    super.key,
    required this.communityId,
    this.repository,
    this.authService,
  });

  final String communityId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final DiscoverRepository? repository;
  final AuthService? authService;

  @override
  State<PublicCommunityScreen> createState() => _PublicCommunityScreenState();
}

class _PublicCommunityScreenState extends State<PublicCommunityScreen> {
  late final DiscoverRepository _repository =
      widget.repository ?? DiscoverRepository();

  late Future<PublicCommunityDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.fetchCommunityDetails(widget.communityId);
  }

  void _refresh() {
    setState(() {
      _future = _repository.fetchCommunityDetails(widget.communityId);
    });
  }

  Future<void> _promptSignIn(String reason) => requireSignIn(
        context,
        reason: reason,
        authService: widget.authService,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      // A plain AppBar, not the AppHeader: that bar carries the signed-in
      // player's name and picture, and there is nobody here to name.
      appBar: AppBar(title: Text(l10n.communityTitle)),
      body: FutureBuilder<PublicCommunityDetails>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _CommunitySkeleton();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 32,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: Gap.md),
                    Text(l10n.loadFailed, textAlign: TextAlign.center),
                    const SizedBox(height: Gap.lg),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(l10n.retryButton),
                    ),
                  ],
                ),
              ),
            );
          }

          final details = snapshot.data!;
          final community = details.community;

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: Gap.xxl),
              children: [
                // A header block rather than a hero: this screen already has an
                // app bar, and a second banner under it would be two headers
                // arguing. The mark is what carries the identity here.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.xl,
                    Gap.lg,
                    Gap.xl,
                    Gap.sm,
                  ),
                  child: Column(
                    children: [
                      // The community's own shape: a rounded square, the
                      // same 72 across the circular mark used to be.
                      CommunityCrest(
                        name: community.name,
                        logoUrl: community.logoUrl,
                        size: 72,
                      ),
                      const SizedBox(height: Gap.md),
                      Text(
                        community.name,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (community.description != null &&
                          community.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: Gap.sm),
                        Text(
                          community.description!,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                      const SizedBox(height: Gap.md),
                      Center(child: CommunityCounts(community: community)),
                      const SizedBox(height: Gap.lg),
                      FilledButton(
                        onPressed: () =>
                            _promptSignIn(l10n.authRequiredJoinCommunity),
                        child: Text(l10n.joinCommunityButton),
                      ),
                    ],
                  ),
                ),
                DiscoverSectionHeader(
                  title: l10n.upcomingMatchesTitle,
                  subtitle: l10n.discoverMatchesSubtitle,
                ),
                if (details.matches.isEmpty)
                  DiscoverEmpty(
                    icon: Icons.event_outlined,
                    message: l10n.discoverNoUpcomingMatches,
                  )
                else
                  for (final match in details.matches)
                    PublicMatchCard(
                      match: match,
                      showCommunityName: false,
                      // Only a guest reaches this screen, so the action is
                      // always the sheet — a member opens the real community
                      // page instead, from the same card on Discover.
                      actionLabel: l10n.joinMatchButton,
                      onAction: () =>
                          _promptSignIn(l10n.authRequiredRegisterMatch),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The shape of a community page, before it arrives.
class _CommunitySkeleton extends StatelessWidget {
  const _CommunitySkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonFade(
      child: Padding(
        padding: EdgeInsets.fromLTRB(kPageMargin, Gap.lg, kPageMargin, 0),
        child: Column(
          children: [
            Skeleton(width: 72, height: 72, radius: Radii.pill),
            SizedBox(height: Gap.md),
            Skeleton(width: 180, height: 20),
            SizedBox(height: Gap.sm),
            Skeleton(width: 240, height: 12),
            SizedBox(height: Gap.lg),
            Skeleton.expand(height: kButtonHeight),
            SizedBox(height: Gap.xxl),
            MatchCardSkeleton(),
            SizedBox(height: Gap.md),
            MatchCardSkeleton(),
          ],
        ),
      ),
    );
  }
}
