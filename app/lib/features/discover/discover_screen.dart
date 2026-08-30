import 'package:flutter/material.dart';

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
import '../communities/community_repository.dart';
import '../communities/create_community_screen.dart';
import '../communities/join_community_flow.dart';
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
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.repository, this.authService});

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final DiscoverRepository? repository;
  final AuthService? authService;

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

  @override
  void initState() {
    super.initState();
    _future = _repository.fetchOverview();
  }

  bool get _signedIn => _auth.isSignedIn;

  void _refresh() {
    setState(() {
      _future = _repository.fetchOverview();
    });
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
  Future<void> _openCommunity(PublicCommunity community) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _signedIn
            ? CommunityDetailsScreen(communityId: community.id)
            : PublicCommunityScreen(
                communityId: community.id,
                repository: widget.repository,
                authService: widget.authService,
              ),
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
  Future<void> _openMatch(PublicMatch match) async {
    if (!await _allowed(context.l10n.authRequiredRegisterMatch)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MatchDetailsScreen(matchId: match.id)),
    );
    if (mounted) _refresh();
  }

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
          PublicMatchCard(
            match: match,
            actionLabel:
                _signedIn ? l10n.viewMatchAction : l10n.joinMatchButton,
            onAction: () => _openMatch(match),
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
          PublicCommunityCard(
            community: community,
            onOpen: () => _openCommunity(community),
            onJoin: () => _join(community),
            clubStyle: true,
          ),
    ];
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
