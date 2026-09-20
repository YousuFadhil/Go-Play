import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/responsive_grid.dart';
import '../../core/skeleton.dart';
import '../../core/tokens.dart';
import '../auth/auth_prompt.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import '../communities/community_details_screen.dart';
import '../communities/community_repository.dart';
import '../communities/create_community_screen.dart';
import '../communities/join_community_flow.dart';
import '../football/football_community_screen.dart';
import '../football/football_match_screen.dart';
import '../football/football_models.dart';
import '../football/football_repository.dart';
import '../football/football_result_card.dart';
import '../results/result_card.dart';
import '../matches/match_details_screen.dart';
import 'discover_models.dart';
import 'discover_repository.dart';
import 'discover_tabs.dart';
import 'discover_widgets.dart';
import 'public_match_screen.dart';
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

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
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
  /// Which communities the reader has joined. Null for a guest.
  ///
  /// **Separate from the football read, and that separation is the point.**
  /// The two used to travel in one `Future.wait`, which meant a failure in
  /// Latest Results resolved to a feed with no memberships in it -- and a real
  /// member was then routed as a non-member, into the football view, because
  /// the history of somebody else's matches had not loaded. Membership is a
  /// fact about the reader; whether a list of results arrived is not, and the
  /// one must not be able to overwrite the other.
  Future<Set<String>>? _membershipFuture;

  /// What has just been played. Null for a guest.
  Future<_LatestResults>? _resultsFuture;

  /// Which of the three tabs is showing.
  ///
  /// **State of this screen, and of nothing else.** It is not a route
  /// argument, not app state and not persisted: every fresh Discover opens on
  /// Upcoming Matches, which is the approved default. It deliberately survives
  /// a pull-to-refresh, because [_load] replaces the futures and never touches
  /// this -- a reader who pulls down on Latest Results is asking for newer
  /// results, not to be sent back to the fixtures.
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _signedIn => _auth.isSignedIn;

  void _load() {
    _future = _repository.fetchOverview();
    // A guest calls neither. There is no membership to have and no football
    // history they may read, so nothing is constructed to ask with.
    _membershipFuture = _signedIn ? _loadMembership() : null;
    _resultsFuture = _signedIn ? _loadResults() : null;
  }

  /// The reader's joined communities, once per screen load.
  ///
  /// One read for the whole list, not one per card: membership decides where a
  /// card navigates and does not change while the list is on screen, and
  /// `fetchMyCommunities` already answers it in a single request. No database
  /// object was added to support this.
  ///
  /// A failure here falls back to the empty set, which routes every card as a
  /// non-member. That is the conservative direction -- it sends nobody into a
  /// screen that would refuse them -- and it is the *only* thing that may
  /// produce it.
  Future<Set<String>> _loadMembership() async {
    try {
      final communities = widget.communityRepository ??
          (_communities ??= CommunityRepository());
      return {for (final c in await communities.fetchMyCommunities()) c.id};
    } catch (_) {
      return const <String>{};
    }
  }

  /// The football half, failing alone.
  Future<_LatestResults> _loadResults() async {
    try {
      final football = widget.footballRepository ?? FootballRepository();
      return _LatestResults(await football.fetchCompletedMatches(limit: 5));
    } catch (_) {
      // A failure here is a value rather than a rejection: this future is
      // created in `initState`, before any `FutureBuilder` has attached, so a
      // rejection would escape as an unhandled async error before anything
      // could render it.
      return const _LatestResults.failed();
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
                onPrimaryAction: _signedIn ? _createCommunity : _openRegister,
                onLogIn: _openLogin,
              ),
            ),
          ),
          Expanded(
            child: ClubSheet(
              child: Column(
                children: [
                  // **One shell, both readers.** The tabs are outside every
                  // auth branch below them: a guest and a member get the same
                  // three, in the same place, in the same order. What a
                  // session changes is what the cards inside can do.
                  DiscoverTabs(
                    controller: _tabs,
                    labels: [
                      l10n.upcomingMatchesTitle,
                      l10n.latestResultsTitle,
                      l10n.communitiesTitle,
                    ],
                  ),
                  Expanded(
                    child: FutureBuilder<DiscoverOverview>(
                      future: _future,
                      builder: (context, snapshot) {
                        final loading =
                            snapshot.connectionState != ConnectionState.done;
                        final overview =
                            snapshot.hasError ? null : snapshot.data;

                        return TabBarView(
                          controller: _tabs,
                          children: [
                            _tab(
                              key: const Key('discoverTabUpcoming'),
                              loading: loading,
                              overview: overview,
                              children: (o) => _matchesSection(l10n, o),
                            ),
                            _tab(
                              key: const Key('discoverTabResults'),
                              loading: loading,
                              overview: overview,
                              children: (o) => _resultsSection(l10n, o),
                            ),
                            _tab(
                              key: const Key('discoverTabCommunities'),
                              loading: loading,
                              overview: overview,
                              children: (o) => _communitiesSection(l10n, o),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One tab's page: its own scroll view, its own pull-to-refresh.
  ///
  /// The loading and failed states live inside the tab rather than over the
  /// whole sheet, so the control above stays put and a reader can still move
  /// between tabs while the read is in flight.
  Widget _tab({
    required Key key,
    required bool loading,
    required DiscoverOverview? overview,
    required List<Widget> Function(DiscoverOverview) children,
  }) {
    return RefreshIndicator(
      key: key,
      onRefresh: () async => _refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.only(bottom: Layout.listBottom),
        children: [
          // One switcher, so arriving content fades in over the placeholders
          // rather than replacing them in a single frame. 180ms: long enough
          // to read as a transition, short enough that nobody waits for it.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey(
                loading ? 'loading' : (overview == null ? 'failed' : 'loaded'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (loading)
                    const _DiscoverSkeleton()
                  else if (overview == null)
                    _LoadFailed(onRetry: _refresh)
                  else
                    ...children(overview),
                ],
              ),
            ),
          ),
          // **No closing call to action.** One per tab is the same panel
          // three times over, and every one of them was a screen of scrolling
          // away from the football the tab exists for. Creating an account and
          // creating a community are both on the hero, where a reader who
          // wants either is already looking.
        ],
      ),
    );
  }

  /// Latest Results, whoever is reading.
  ///
  /// A guest gets the public contract, which publishes only matches that have
  /// a recorded result. A member gets their own football read, which does not
  /// -- so it is filtered here, in `_FootballFeed`, for the reason the section
  /// exists: a completed match whose result nobody has entered yet is a
  /// completed match, and it is not a Latest Result. A section with two
  /// meanings depending on who is looking at it is the defect this removes.
  List<Widget> _resultsSection(
    AppLocalizations l10n,
    DiscoverOverview overview,
  ) {
    if (_resultsFuture != null) {
      return [
        _FootballFeed(
          future: _resultsFuture!,
          onOpen: _openCompletedMatch,
        ),
      ];
    }
    return _publicResultsSection(l10n, overview);
  }

  List<Widget> _matchesSection(
    AppLocalizations l10n,
    DiscoverOverview overview,
  ) {
    return [
      if (overview.matches.isEmpty)
        DiscoverEmpty(
          icon: Icons.event_outlined,
          message: l10n.discoverNoUpcomingMatches,
        )
      else
        // Two across, and one when two will not fit. The cards used to be a
        // column of full-width rows, which put about two fixtures on a phone
        // screen and made the communities below them something a reader had to
        // go looking for.
        ResponsiveCardGrid(
          maxColumns: 2,
          minCardWidth: GridCard.matchMinWidth,
          padding: const EdgeInsets.symmetric(
            horizontal: Layout.sheetGutter,
            vertical: Gap.xs,
          ),
          children: [
            for (final match in overview.matches)
              _MembershipAware(
                future: _membershipFuture,
                communityId: match.communityId,
                builder: (isMember) => CompactPublicMatchCard(
                  match: match,
                  actionLabel:
                      _signedIn ? l10n.viewMatchAction : l10n.joinMatchButton,
                  onAction: () => _openMatch(match, isMember: isMember),
                ),
              ),
          ],
        ),
    ];
  }

  /// Latest Results, as a visitor sees them.
  ///
  /// Between Upcoming Matches and Communities, which is where the signed-in
  /// feed sits — so the page has one order for both readers. With nothing
  /// scheduled above it, this becomes the first football on the page rather
  /// than leaving a guest with an empty screen.
  List<Widget> _publicResultsSection(
    AppLocalizations l10n,
    DiscoverOverview overview,
  ) {
    return [
      if (overview.results.isEmpty)
        // Nothing played yet is a football state, not a fault.
        DiscoverEmpty(
          icon: Icons.sports_soccer,
          message: l10n.latestResultsEmpty,
        )
      else
        ResultsList<PublicResult>(
          results: overview.results,
          identityOf: (result) => result.matchId,
          toggleKey: const Key('discoverPublicPreviousResultsToggle'),
          itemBuilder: (context, result) => PublicResultCard(
            result: result,
            onOpen: () => _openPublicResult(result),
          ),
        ),
    ];
  }

  /// The public page for a completed match — the one a shared `/match/{id}`
  /// link opens, and the only thing a guest is offered here.
  Future<void> _openPublicResult(PublicResult result) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          // The same repository this screen was built with, so one flow reads
          // through one port -- and a test can hand both ends a fake.
          builder: (_) => PublicMatchScreen(
            matchId: result.matchId,
            repository: widget.repository,
            authService: widget.authService,
          ),
        ),
      );

  List<Widget> _communitiesSection(
    AppLocalizations l10n,
    DiscoverOverview overview,
  ) {
    return [
      if (overview.communities.isEmpty)
        DiscoverEmpty(
          icon: Icons.groups_outlined,
          message: l10n.discoverNoCommunities,
        )
      else
        ResponsiveCardGrid(
          maxColumns: 2,
          minCardWidth: GridCard.communityMinWidth,
          padding: const EdgeInsets.symmetric(
            horizontal: Layout.sheetGutter,
            vertical: Gap.xs,
          ),
          children: [
            for (final community in overview.communities)
              _MembershipAware(
                future: _membershipFuture,
                communityId: community.id,
                builder: (isMember) => CompactPublicCommunityCard(
                  community: community,
                  onOpen: () => _openCommunity(community, isMember: isMember),
                  onJoin: () => _join(community),
                ),
              ),
          ],
        ),
    ];
  }
}

/// The football half of a signed-in reader's Discover.
///
/// Deliberately carries results and nothing else. It used to carry membership
/// too, and that coupling was the defect: a failed football read produced an
/// empty membership set, and a member was routed as a stranger to their own
/// community.
class _LatestResults {
  const _LatestResults(this.matches) : failed = false;

  const _LatestResults.failed()
      : matches = const [],
        failed = true;

  final List<CompletedMatch> matches;
  final bool failed;
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

  final Future<_LatestResults> future;
  final void Function(CompletedMatch) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<_LatestResults>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SkeletonFade(
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
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.failed) {
          return DiscoverEmpty(
            icon: Icons.cloud_off_outlined,
            message: l10n.latestResultsFailed,
          );
        }

        // **Result-bearing only.** A member's football read returns every
        // completed match, including one whose result nobody has written up
        // yet; the public contract returns only matches that have one. A
        // section called Latest Results must not mean two different things
        // depending on who is reading it, so the member's side is narrowed to
        // the public side's meaning. Nothing is fetched to do it -- the flag
        // is already on the row.
        final results = [
          for (final match in snapshot.data!.matches)
            if (match.hasResult) match,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (results.isEmpty)
              // Nothing played yet is a football state, not a fault.
              DiscoverEmpty(
                icon: Icons.sports_soccer,
                message: l10n.latestResultsEmpty,
              )
            else
              ResultsList<CompletedMatch>(
                results: results,
                identityOf: (match) => match.matchId,
                toggleKey: const Key('discoverPreviousResultsToggle'),
                itemBuilder: (context, match) => FootballResultCard(
                  match: match,
                  onOpen: () => onOpen(match),
                ),
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

  /// The reader's joined communities. Null for a guest.
  ///
  /// This is the *only* input to the decision. Whether Latest Results loaded
  /// cannot reach it, which is what stops a football failure from demoting a
  /// member.
  final Future<Set<String>>? future;
  final String communityId;
  final Widget Function(bool isMember) builder;

  @override
  Widget build(BuildContext context) {
    final pending = future;
    if (pending == null) return builder(false);

    return FutureBuilder<Set<String>>(
      future: pending,
      builder: (context, snapshot) =>
          builder(snapshot.data?.contains(communityId) ?? false),
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
          // Both sections arrive as grids now, so both are placeholdered as
          // grids. A column of row-shaped cards here meant the page was drawn
          // one shape and then redrawn another the moment the read landed,
          // which is the jump this skeleton exists to prevent.
          const CompactMatchGridSkeleton(),
          DiscoverSectionHeader(
            title: l10n.communitiesTitle,
            subtitle: l10n.discoverCommunitiesSubtitle,
          ),
          const CompactCommunityGridSkeleton(),
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
