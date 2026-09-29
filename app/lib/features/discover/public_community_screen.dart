import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../../core/tokens.dart';
import '../analytics/acquisition_analytics.dart';
import '../profile/profile_screen.dart';
import '../results/result_card.dart';
import '../sharing/public_link.dart';
import '../auth/auth_prompt.dart';
import '../auth/auth_service.dart';
import 'discover_repository.dart';
import 'discover_widgets.dart';
import 'public_community_tabs.dart';
import 'public_match_screen.dart';

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
/// community, how big it is, its football record, what it has played, what it
/// has scheduled and who leads it. Who the members are is not here, and neither
/// is the join code — a code is the credential that a CODE_REQUIRED community
/// is entered with, and publishing it on the page that invites people to join
/// would make the policy decorative.
///
/// **It is the same place, seen by another audience.** The page used to open
/// with a plain app bar over a centred crest and a column of sections, while a
/// member's view of the identical community opened on the Club hero -- so
/// signing in changed what the community looked like rather than what the
/// reader could do there. It is now composed from the primitives the football
/// community screen uses: [ClubHero] over [ClubSheet], the shared
/// [CommunityIdentity] row, [ClubHeroCount] figures, and the one [ResultCard]
/// this product draws a played match with.
///
/// **Under the hero it is [PublicCommunityTabs]**, the same widget a signed-in
/// non-member's community page is built from: the football record, then Latest
/// Results, Upcoming Matches and Top Players, opening on Latest Results. A
/// guest and a signed-in reader who is not a member therefore see one page, and
/// what a session changes is what a tap does — here, joining and registering
/// ask for an account, and nothing else about the page is different.
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

class _PublicCommunityScreenState extends State<PublicCommunityScreen>
    with SingleTickerProviderStateMixin {
  late final DiscoverRepository _repository =
      widget.repository ?? DiscoverRepository();

  late Future<PublicCommunityDetails> _future;

  /// The record and the Top Players, held apart from the community: the two
  /// fail independently, and a football read that fails must not take the
  /// community's name and its fixtures off the page. Null is that failure.
  late Future<PublicCommunityFootball?> _football;

  /// Which tab is showing: Latest Results, Upcoming Matches, Top Players, in
  /// that order. State of this screen and of nothing else -- every fresh page
  /// opens on Latest Results, index 0, and a pull-to-refresh replaces the
  /// futures without touching this, so a reader who pulls down on Top Players
  /// is asking for newer players, not to be sent back to the results.
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    // Built here rather than lazily: a page that fails to load never builds its
    // tabs, and a controller first created inside `dispose` is created on a
    // deactivated element.
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _load() {
    _future = _loadDetails();
    _football = _loadFootball();
  }

  void _refresh() => setState(_load);

  /// The football half, failing alone. A value rather than a rejection: this
  /// future is created before any builder has attached to it, so a rejection
  /// would escape as an unhandled async error before anything could render it.
  Future<PublicCommunityFootball?> _loadFootball() async {
    try {
      return await _repository.fetchCommunityFootball(widget.communityId);
    } catch (_) {
      return null;
    }
  }

  /// The community, and — only once it has actually loaded — the arrival
  /// reported to acquisition analytics, which decides whether this is an
  /// external link arrival worth recording (Wave 3). A failed read reports
  /// nothing.
  Future<PublicCommunityDetails> _loadDetails() async {
    final details = await _repository.fetchCommunityDetails(widget.communityId);
    AcquisitionAnalytics.instance.externalArrivalLoaded(
      PublicLinkTarget(PublicLinkKind.community, widget.communityId),
    );
    return details;
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
      backgroundColor: GoColors.bgHero,
      body: FutureBuilder<PublicCommunityDetails>(
        future: _future,
        builder: (context, snapshot) {
          // A first load, or a retry after a failure, has nothing to show yet.
          // A refresh does: the page stays up and updates when the read lands,
          // rather than the hero and the tabs vanishing under the reader's
          // finger.
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasData) {
            return const _CommunitySkeleton();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Scaffold(
              appBar: AppBar(title: Text(l10n.communityTitle)),
              body: Center(
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
              ),
            );
          }

          final details = snapshot.data!;
          final community = details.community;

          return Column(
            children: [
              SafeArea(
                bottom: false,
                child: ClubHero(
                  // **The same ground a player's record and a played match
                  // open on.** A community is a place in this product, and
                  // the public page is that place seen by somebody who is not
                  // in it -- not a lighter version of it. Drawn, never
                  // photographed: see [StadiumBackdrop].
                  stadium: true,
                  bar: ClubHeroBar(
                    title: l10n.communityTitle,
                    onBack: Navigator.of(context).canPop()
                        ? () => Navigator.of(context).maybePop()
                        : null,
                    // Never the identity menu: there is nobody signed in to
                    // name, and mounting it would read `my_profile` on a page
                    // a guest is entitled to without one.
                  ),
                  identity: CommunityIdentity(
                    community: community,
                    crestSize: 72,
                    onHero: true,
                  ),
                  counts: Row(
                    children: [
                      Flexible(
                        child: ClubHeroCount(
                          value: community.memberCount,
                          label: l10n.membersTitle,
                        ),
                      ),
                      const SizedBox(width: Gap.lg + 2),
                      Flexible(
                        child: ClubHeroCount(
                          value: community.upcomingMatchCount,
                          label: l10n.upcomingMatchesTitle,
                        ),
                      ),
                    ],
                  ),
                  action: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          key: const Key('publicCommunityJoin'),
                          style: ClubHeroButtons.filled,
                          onPressed: () =>
                              _promptSignIn(l10n.authRequiredJoinCommunity),
                          child: Text(l10n.joinCommunityButton),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ClubSheet(
                  child: PublicCommunityTabs(
                    controller: _tabs,
                    matches: details.matches,
                    results: details.results,
                    football: _football,
                    // Only a guest reaches this screen, so the action is always
                    // the sheet -- a member opens the real community page
                    // instead, from the same card on Discover.
                    matchActionLabel: l10n.joinMatchButton,
                    onMatchAction: () =>
                        _promptSignIn(l10n.authRequiredRegisterMatch),
                    onOpenResult: (result) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PublicMatchScreen(
                          matchId: result.matchId,
                          repository: widget.repository,
                          authService: widget.authService,
                        ),
                      ),
                    ),
                    // The public profile, as a name on a public match page
                    // already opens it: `asVisitor` reads the public contracts
                    // only. No new route and no new policy for a guest.
                    onOpenPlayer: (player) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          userId: player.userId,
                          asVisitor: true,
                        ),
                      ),
                    ),
                    onRefresh: _refresh,
                  ),
                ),
              ),
            ],
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
