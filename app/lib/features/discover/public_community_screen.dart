import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../../core/tokens.dart';
import '../results/result_card.dart';
import '../auth/auth_prompt.dart';
import '../auth/auth_service.dart';
import 'discover_models.dart';
import 'discover_repository.dart';
import 'discover_widgets.dart';
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
/// community, how big it is, and what it has scheduled. Who the members are is
/// not here, and neither is the join code — a code is the credential that a
/// CODE_REQUIRED community is entered with, and publishing it on the page that
/// invites people to join would make the policy decorative.
///
/// **It is the same place, seen by another audience.** The page used to open
/// with a plain app bar over a centred crest and a column of sections, while a
/// member's view of the identical community opened on the Club hero -- so
/// signing in changed what the community looked like rather than what the
/// reader could do there. It is now composed from the primitives the football
/// community screen uses: [ClubHero] over [ClubSheet], the shared
/// [CommunityIdentity] row, [ClubHeroCount] figures, and the one [ResultCard]
/// this product draws a played match with. What is *on* the page is unchanged:
/// the same public reads, the same four things, and no member content anywhere.
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
      backgroundColor: GoColors.bgHero,
      body: FutureBuilder<PublicCommunityDetails>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
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
                  child: RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsetsDirectional.only(
                        bottom: Layout.listBottom,
                      ),
                      children: [
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
                              // Only a guest reaches this screen, so the
                              // action is always the sheet -- a member opens
                              // the real community page instead, from the
                              // same card on Discover.
                              actionLabel: l10n.joinMatchButton,
                              onAction: () =>
                                  _promptSignIn(l10n.authRequiredRegisterMatch),
                            ),
                        // **The football that has already been played.** A
                        // community with nothing scheduled used to leave a
                        // visitor with a crest and an empty list; its results
                        // are public, were always openable by id, and are what
                        // the page is about the rest of the week.
                        DiscoverSectionHeader(
                          title: l10n.latestResultsTitle,
                          subtitle: l10n.latestResultsSubtitle,
                        ),
                        if (details.results.isEmpty)
                          DiscoverEmpty(
                            icon: Icons.sports_soccer,
                            message: l10n.latestResultsEmpty,
                          )
                        else
                          ResultsList<PublicResult>(
                            results: details.results,
                            identityOf: (result) => result.matchId,
                            toggleKey: const Key(
                                'publicCommunityPreviousResultsToggle'),
                            itemBuilder: (context, result) => PublicResultCard(
                              result: result,
                              showCommunityName: false,
                              onOpen: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PublicMatchScreen(
                                    matchId: result.matchId,
                                    repository: widget.repository,
                                    authService: widget.authService,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
