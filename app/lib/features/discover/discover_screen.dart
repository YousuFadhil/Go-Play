import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../../core/tokens.dart';
import '../auth/auth_prompt.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import '../communities/community_details_screen.dart';
import '../communities/community_models.dart';
import '../communities/community_repository.dart';
import '../communities/create_community_screen.dart';
import '../communities/join_community_flow.dart';
import '../football/football_community_screen.dart';
import '../football/football_match_screen.dart';
import '../football/football_models.dart';
import '../football/football_repository.dart';
import '../football/football_result_card.dart';
import '../matches/match_details_screen.dart';
import 'discover_models.dart';
import 'discover_repository.dart';
import 'discover_widgets.dart';
import 'public_community_screen.dart';

/// What the app opens on, for everybody.
///
/// The product used to introduce itself with a login form, which asked for a
/// commitment before showing anything worth committing to — and then, once
/// signed in, with a list of the player's own fixtures. Both were the same
/// mistake seen from different sides: a platform for football communities that
/// opened on paperwork. This opens on the matches and the communities
/// themselves, and it is the first screen whether or not anyone is signed in.
///
/// One screen serves both audiences rather than two that would drift. Every read
/// behind it is public (`DiscoverAdapter`) and stays public when a member is
/// looking, because what a member may additionally see belongs to the screens
/// they open from here. Who is looking decides one thing only: what a tap does.
/// A guest is asked for an account; a member is taken to the real thing.
/// Where a community card leads.
///
/// Named as a decision rather than left implicit in a `builder`, because it *is*
/// the decision this cycle exists to fix: a signed-in non-member used to be sent
/// to the member screen and shown an empty one. Separating the choice from the
/// navigation lets the rule be asserted as a rule, without building a
/// destination that would reach the data provider to say so.
enum CommunityDestination {
  /// Signed out: the guest community page, from anonymous reads.
  guestPublic,

  /// A member's own community, management and all.
  memberDetails,

  /// A signed-in non-member: football history, and the way in.
  football,
}

/// Where an upcoming-match card leads.
enum UpcomingMatchDestination {
  /// Signed out: the sign-in gate, unchanged.
  signInGate,

  /// A member's own fixture, on the screen that owns registration.
  memberMatchDetails,

  /// A non-member's. `MatchDetailsScreen` would refuse the read and show a
  /// wall, so the community the match belongs to is the useful destination.
  football,
}

@visibleForTesting
CommunityDestination communityDestinationFor({
  required bool signedIn,
  required bool isMember,
}) {
  if (!signedIn) return CommunityDestination.guestPublic;
  return isMember
      ? CommunityDestination.memberDetails
      : CommunityDestination.football;
}

@visibleForTesting
UpcomingMatchDestination upcomingMatchDestinationFor({
  required bool signedIn,
  required bool isMember,
}) {
  if (!signedIn) return UpcomingMatchDestination.signInGate;
  return isMember
      ? UpcomingMatchDestination.memberMatchDetails
      : UpcomingMatchDestination.football;
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    this.repository,
    this.authService,
    this.footballRepository,
    this.communityRepository,
  });

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final DiscoverRepository? repository;
  final AuthService? authService;

  /// The football history a signed-in reader is shown. Never constructed for a
  /// guest — see [_FootballFeed].
  final FootballRepository? footballRepository;

  /// Used to read which communities the signed-in reader has joined, once per
  /// screen load rather than once per card.
  final CommunityRepository? communityRepository;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late final DiscoverRepository _repository =
      widget.repository ?? DiscoverRepository();
  late final AuthService _auth = widget.authService ?? AuthService();

  /// Built lazily: a guest never joins anything, and constructing this reaches
  /// the data provider's client.
  CommunityRepository? _communities;

  late Future<DiscoverOverview> _future;

  /// The signed-in half of the page, and null for a guest.
  ///
  /// Null is load-bearing rather than tidy: a guest must not reach the football
  /// history views at all — Cycle 2 granted them to `authenticated` and to
  /// nobody else — so for a signed-out reader there is no future here to fail,
  /// and no repository constructed to fail it with.
  Future<_SignedInFeed>? _signedInFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _signedIn => _auth.isSignedIn;

  void _load() {
    _future = _repository.fetchOverview();
    _signedInFuture = _signedIn ? _loadSignedIn() : null;
  }

  /// The two reads a signed-in reader adds: what has just been played, and
  /// which communities they are already in.
  ///
  /// Joined communities are fetched **once per screen load**, not once per card.
  /// Membership decides where a card navigates, and asking that question per
  /// card would be one round trip per row for an answer that does not change
  /// while the list is on screen. `fetchMyCommunities` already answers it in a
  /// single read, so no database object was added to support this.
  Future<_SignedInFeed> _loadSignedIn() async {
    try {
      final football = widget.footballRepository ?? FootballRepository();
      final communities =
          widget.communityRepository ?? (_communities ??= CommunityRepository());
      final results = await Future.wait([
        football.fetchCompletedMatches(limit: 5),
        communities.fetchMyCommunities(),
      ]);
      return _SignedInFeed(
        results: results[0] as List<CompletedMatch>,
        joinedCommunityIds: {
          for (final c in results[1] as List<Community>) c.id,
        },
      );
    } catch (_) {
      // A failure here is a value, not a rejection, and that is deliberate.
      //
      // This future is created in `initState`, before any `FutureBuilder` has
      // attached to it, so a rejection would escape as an unhandled async error
      // before anything could render it. Returning a failed *feed* keeps the
      // section's failure inside the section: the two builders below read it,
      // Latest Results shows its own error state, and the public content on
      // either side of it is untouched.
      return const _SignedInFeed.failed();
    }
  }

  void _refresh() {
    setState(_load);
  }

  /// Straight to the form, with no sheet in between: somebody who tapped
  /// "create account" or "log in" has already answered the question the sheet
  /// asks.
  Future<void> _openRegister() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RegisterScreen(authService: widget.authService),
        ),
      );

  Future<void> _openLogin() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoginScreen(authService: widget.authService),
        ),
      );

  /// The gate, for a guest.
  ///
  /// Returns false when the caller must stop. A successful sign-in unwinds to
  /// the root route and the auth gate rebuilds the app around it, so a true from
  /// here is only ever the "already signed in" case — which is exactly when the
  /// caller should carry on.
  Future<bool> _allowed(String reason) => requireSignIn(
        context,
        reason: reason,
        authService: widget.authService,
      );

  /// A member opens the real community page; a guest opens the public one.
  ///
  /// The public page is not a lesser version of the real one — it answers a
  /// different question, from reads a guest is entitled to. Showing it to a
  /// member would be showing them less than they are owed, which is why this
  /// branches rather than always taking the safe path.
  Future<void> _openCommunity(
    PublicCommunity community, {
    required bool isMember,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => switch (communityDestinationFor(
          signedIn: _signedIn,
          isMember: isMember,
        )) {
          CommunityDestination.guestPublic => PublicCommunityScreen(
              communityId: community.id,
              repository: widget.repository,
              authService: widget.authService,
            ),
          CommunityDestination.memberDetails =>
            CommunityDetailsScreen(communityId: community.id),
          CommunityDestination.football => FootballCommunityScreen(
              communityId: community.id,
              discoverRepository: widget.repository,
              footballRepository: widget.footballRepository,
              communityRepository: widget.communityRepository,
            ),
        },
      ),
    );
    // Membership may have changed behind that screen, and the counts on this
    // one are read from the same rows.
    if (mounted) _refresh();
  }

  /// Registering happens on the match's own screen, which already owns every
  /// rule about it — capacity, the reserve queue, whether the match is locked.
  /// A card is not the place to restate any of that, so a member is taken there
  /// rather than registered from here.
  Future<void> _openMatch(PublicMatch match, {required bool isMember}) async {
    if (!await _allowed(context.l10n.authRequiredRegisterMatch)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => switch (upcomingMatchDestinationFor(
          signedIn: _signedIn,
          isMember: isMember,
        )) {
          // The gate above has already run for a guest, so this arm is only
          // reached once they are signed in; it is listed for exhaustiveness.
          UpcomingMatchDestination.signInGate ||
          UpcomingMatchDestination.memberMatchDetails =>
            MatchDetailsScreen(matchId: match.id),
          UpcomingMatchDestination.football => FootballCommunityScreen(
              communityId: match.communityId,
              discoverRepository: widget.repository,
              footballRepository: widget.footballRepository,
              communityRepository: widget.communityRepository,
            ),
        },
      ),
    );
    if (mounted) _refresh();
  }

  /// A completed match opens the read-only football screen, for everybody
  /// signed in. Membership decides nothing here: football that has been played
  /// reads the same whoever is looking.
  Future<void> _openCompletedMatch(CompletedMatch match) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FootballMatchScreen(
            matchId: match.matchId,
            repository: widget.footballRepository,
          ),
        ),
      );

  Future<void> _join(PublicCommunity community) async {
    if (!await _allowed(context.l10n.authRequiredJoinCommunity)) return;
    if (!mounted) return;

    // No join policy is passed: the public read model does not carry one, and
    // it is not missing information — the server answers `NeedsJoinCode` and
    // the shared flow asks for the code, which is the same conversation one
    // round trip later.
    final joined = await runJoinCommunity(
      context,
      repository: _communities ??= CommunityRepository(),
      communityId: community.id,
    );
    if (joined && mounted) _refresh();
  }

  Future<void> _createCommunity() async {
    if (!await _allowed(context.l10n.authRequiredCreateCommunity)) return;
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateCommunityScreen()),
    );
    if (created == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: GoColors.bgHero,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: FutureBuilder<DiscoverOverview>(
              future: _future,
              builder: (context, snapshot) => DiscoverHero(
                signedIn: _signedIn,
                overview: snapshot.hasError ? null : snapshot.data,
                onPrimaryAction:
                    _signedIn ? _createCommunity : _openRegister,
                onLogIn: _openLogin,
              ),
            ),
          ),
          Expanded(
            child: ClubSheet(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: FutureBuilder<DiscoverOverview>(
                  future: _future,
                  builder: (context, snapshot) {
                    final loading =
                        snapshot.connectionState != ConnectionState.done;
                    final overview = snapshot.hasError ? null : snapshot.data;

                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsetsDirectional.only(
                        bottom: Layout.listBottom,
                      ),
                      children: [
                        // One switcher for all three states, so arriving content
                        // fades in over the placeholders rather than replacing them
                        // in a single frame. 180ms: long enough to read as a
                        // transition, short enough that nobody waits for it.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: KeyedSubtree(
                            key: ValueKey(
                              loading
                                  ? 'loading'
                                  : (overview == null ? 'failed' : 'loaded'),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (loading)
                                  const _DiscoverSkeleton()
                                else if (overview == null)
                                  _LoadFailed(onRetry: _refresh)
                                else ...[
                                  ..._matchesSection(l10n, overview),
                                  // Latest Results sits between Upcoming and
                                  // Communities, and only for a signed-in
                                  // reader. Its own builder, so a football
                                  // read that fails takes this section down
                                  // and nothing else: the public content above
                                  // and below it has already arrived and must
                                  // not disappear because authenticated
                                  // history did not.
                                  if (_signedInFuture != null)
                                    _FootballFeed(
                                      future: _signedInFuture!,
                                      onOpen: _openCompletedMatch,
                                    ),
                                  ..._communitiesSection(l10n, overview),
                                ],
                              ],
                            ),
                          ),
                        ),
                        DiscoverCta(
                          signedIn: _signedIn,
                          onCreateAccount: _openRegister,
                          onCreateCommunity: _createCommunity,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _matchesSection(
    AppLocalizations l10n,
    DiscoverOverview overview,
  ) {
    return [
      DiscoverSectionHeader(
        title: l10n.upcomingMatchesTitle,
        subtitle: l10n.discoverMatchesSubtitle,
      ),
      if (overview.matches.isEmpty)
        DiscoverEmpty(
          icon: Icons.event_outlined,
          message: l10n.discoverNoUpcomingMatches,
        )
      else
        for (final match in overview.matches)
          _MembershipAware(
            future: _signedInFuture,
            communityId: match.communityId,
            builder: (isMember) => PublicMatchCard(
              match: match,
              actionLabel:
                  _signedIn ? l10n.viewMatchAction : l10n.joinMatchButton,
              onAction: () => _openMatch(match, isMember: isMember),
            ),
          ),
    ];
  }

  List<Widget> _communitiesSection(
    AppLocalizations l10n,
    DiscoverOverview overview,
  ) {
    return [
      DiscoverSectionHeader(
        title: l10n.communitiesTitle,
        subtitle: l10n.discoverCommunitiesSubtitle,
      ),
      if (overview.communities.isEmpty)
        DiscoverEmpty(
          icon: Icons.groups_outlined,
          message: l10n.discoverNoCommunities,
        )
      else
        for (final community in overview.communities)
          _MembershipAware(
            future: _signedInFuture,
            communityId: community.id,
            builder: (isMember) => PublicCommunityCard(
              community: community,
              onOpen: () => _openCommunity(community, isMember: isMember),
              onJoin: () => _join(community),
              clubStyle: true,
            ),
          ),
    ];
  }
}

/// What a signed-in reader's Discover adds to the public page.
///
/// Two facts from one load: what has just been played, and which communities
/// this reader is already in. They travel together because both are needed
/// before a single card can decide where it navigates, and splitting them would
/// mean two loading states for one section of the page.
class _SignedInFeed {
  const _SignedInFeed({
    required this.results,
    required this.joinedCommunityIds,
  }) : failed = false;

  /// The football read did not come back.
  ///
  /// Membership is unknown in this state, so every card is built as a
  /// non-member — the reading that sends nobody into a screen that would
  /// refuse them.
  const _SignedInFeed.failed()
      : results = const [],
        joinedCommunityIds = const {},
        failed = true;

  final bool failed;

  final List<CompletedMatch> results;

  /// Read once per screen load. Membership decides where a card goes, and the
  /// answer does not change while the list is on screen.
  final Set<String> joinedCommunityIds;
}

/// Latest Results: the signed-in section, and its own failure.
///
/// Rendered under a builder of its own so that the football read fails alone.
/// The public overview above and below it has already arrived by the time this
/// runs, and a reader whose football history could not load should still see
/// what is coming and which communities exist.
///
/// A guest never reaches this widget: `_signedInFuture` is null for them, so
/// there is no future to build and no football repository constructed.
class _FootballFeed extends StatelessWidget {
  const _FootballFeed({required this.future, required this.onOpen});

  final Future<_SignedInFeed> future;
  final void Function(CompletedMatch) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<_SignedInFeed>(
      future: future,
      builder: (context, snapshot) {
        final header = DiscoverSectionHeader(
          title: l10n.latestResultsTitle,
          subtitle: l10n.latestResultsSubtitle,
        );

        if (snapshot.connectionState != ConnectionState.done) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SkeletonFade(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: kPageMargin),
                  child: Column(
                    children: [
                      MatchCardSkeleton(),
                      SizedBox(height: Gap.md),
                      MatchCardSkeleton(),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.failed) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              DiscoverEmpty(
                icon: Icons.cloud_off_outlined,
                message: l10n.latestResultsFailed,
              ),
            ],
          );
        }

        final results = snapshot.data!.results;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (results.isEmpty)
              // Nothing played yet is a football state, not a fault.
              DiscoverEmpty(
                icon: Icons.sports_soccer,
                message: l10n.latestResultsEmpty,
              )
            else
              for (final match in results)
                FootballResultCard(
                  match: match,
                  onOpen: () => onOpen(match),
                ),
          ],
        );
      },
    );
  }
}

/// Builds a card once the reader's membership in [communityId] is known.
///
/// While the answer is still in flight — or for a guest, who has no membership
/// to have — the card is built as a non-member. That is the safe default in
/// both directions: a guest is gated by the sign-in prompt before any
/// navigation happens, and a member who taps in the first moments of a load
/// reaches the football view rather than a screen that would refuse them.
class _MembershipAware extends StatelessWidget {
  const _MembershipAware({
    required this.future,
    required this.communityId,
    required this.builder,
  });

  final Future<_SignedInFeed>? future;
  final String communityId;
  final Widget Function(bool isMember) builder;

  @override
  Widget build(BuildContext context) {
    final pending = future;
    if (pending == null) return builder(false);

    return FutureBuilder<_SignedInFeed>(
      future: pending,
      builder: (context, snapshot) => builder(
        snapshot.data?.joinedCommunityIds.contains(communityId) ?? false,
      ),
    );
  }
}

/// The strip above the banner: who is looking.
///
/// The identity menu is here because Discover has no [AppHeader] to put it in —
/// the banner is this screen's header — and a signed-in player must be able to
/// reach their profile, their settings and sign out from the screen the app
/// opens on, not only from the two behind it.
///
/// The language control that used to sit at the other end of this strip is
/// gone. The app follows the device now, and the one place to say otherwise is
/// the Settings screen — reachable from the same menu on the left of this row.
class DiscoverTopBar extends StatelessWidget {
  const DiscoverTopBar({super.key, required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    // Nothing to show a visitor: without a session there is no identity menu,
    // and an empty bar would only push the banner down the page.
    if (!signedIn) return const SizedBox(height: Gap.sm);

    return const Padding(
      padding: EdgeInsets.fromLTRB(Gap.sm, Gap.sm, kPageMargin, Gap.sm),
      child: Row(children: [CurrentUserMenu()]),
    );
  }
}

/// The shape of the page, before the page arrives.
///
/// Both sections are placeholdered, headers included, so the banner does not
/// sit alone over a void while the read is in flight and nothing jumps when it
/// lands.
class _DiscoverSkeleton extends StatelessWidget {
  const _DiscoverSkeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SkeletonFade(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiscoverSectionHeader(
            title: l10n.upcomingMatchesTitle,
            subtitle: l10n.discoverMatchesSubtitle,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: kPageMargin),
            child: Column(
              children: [
                MatchCardSkeleton(),
                SizedBox(height: Gap.md),
                MatchCardSkeleton(),
              ],
            ),
          ),
          DiscoverSectionHeader(
            title: l10n.communitiesTitle,
            subtitle: l10n.discoverCommunitiesSubtitle,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: kPageMargin),
            child: Column(
              children: [
                CommunityCardSkeleton(),
                SizedBox(height: Gap.md),
                CommunityCardSkeleton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The page still shows its banner and its call to action when the lists cannot
/// be read: the product is describable without a working connection, and a
/// visitor who arrived on a bad one should still be able to sign up.
///
/// This is the one panel on the page that is *allowed* to look like something
/// went wrong, which is why the empty states no longer resemble it.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.xxl,
        kPageMargin,
        Gap.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(Gap.xl),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined, size: 32, color: scheme.error),
            const SizedBox(height: Gap.md),
            Text(
              l10n.loadFailed,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: Gap.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}
