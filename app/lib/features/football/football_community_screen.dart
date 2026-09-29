import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import '../communities/community_repository.dart';
import '../communities/community_details_screen.dart';
import '../communities/join_community_flow.dart';
import '../discover/discover_repository.dart';
import '../discover/discover_widgets.dart';
import '../discover/public_community_tabs.dart';
import '../profile/player_identity.dart';
import 'football_match_screen.dart';
import 'football_repository.dart';

/// A community, as a signed-in player who is not in it may read it.
///
/// This is the screen that closes the gap Cycle 1 left open. A signed-in
/// non-member used to be sent to `CommunityDetailsScreen` — a screen built
/// entirely out of member reads — where the roster came back empty, the matches
/// came back empty and the two statistics tabs came back empty, and the reader
/// was left to conclude the community was deserted rather than that they were
/// not in it. Nothing was leaking; the screen was simply answering a question it
/// could not answer.
///
/// It is deliberately **not** a reduced `CommunityDetailsScreen`. That screen is
/// a member's place to manage a community; this one answers what a visitor is
/// entitled to ask — who they are, what they have played, and how it went — from
/// reads that are theirs to make. Duplicating the tabs and hiding half of them
/// would leave a shell whose behaviour depended on failures.
///
/// **It is the same page a guest reads.** Under the hero it is
/// [PublicCommunityTabs], the widget `PublicCommunityScreen` is built from: the
/// football record, then Latest Results, Upcoming Matches and Top Players,
/// opening on Latest Results. Both audiences are handed the same public reads —
/// including the record and the Top 11, which come from the narrow contract of
/// migration `0093` and not from the authenticated football views — so signing
/// in changes what a tap does, never what the community shows. It used to be a
/// second page with a different order, a different Top Players list and a
/// results list that could contain a match nobody had written up yet.
///
/// What a session *does* change is what the buttons do: a result opens the
/// signed-in match screen, a player opens the signed-in profile, and joining
/// goes through the flow that already owns that conversation — including asking
/// for the code where the policy requires one, which is the only way a code ever
/// reaches a client.
class FootballCommunityScreen extends StatefulWidget {
  const FootballCommunityScreen({
    super.key,
    required this.communityId,
    this.discoverRepository,
    this.footballRepository,
    this.communityRepository,
  });

  final String communityId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final DiscoverRepository? discoverRepository;

  /// Only for the signed-in match screen a result opens. The page itself reads
  /// nothing from it: the football on this page is the public contract.
  final FootballRepository? footballRepository;
  final CommunityRepository? communityRepository;

  @override
  State<FootballCommunityScreen> createState() =>
      _FootballCommunityScreenState();
}

class _FootballCommunityScreenState extends State<FootballCommunityScreen>
    with SingleTickerProviderStateMixin {
  late final DiscoverRepository _discover =
      widget.discoverRepository ?? DiscoverRepository();
  late final CommunityRepository _communities =
      widget.communityRepository ?? CommunityRepository();

  /// The public half of the page: identity, what is scheduled and what has been
  /// played.
  late Future<PublicCommunityDetails> _publicFuture;

  /// The football half: the record and the Top Players.
  ///
  /// Held apart from the public half rather than merged into one future,
  /// because the two fail independently and must be seen to. A football read
  /// that fails must not take the community's name and its fixtures off the
  /// screen. Null is the football half failing, and only the football half.
  late Future<PublicCommunityFootball?> _footballFuture;

  /// Which tab is showing: Latest Results, Upcoming Matches, Top Players, in
  /// that order. State of this screen and of nothing else — see
  /// `PublicCommunityScreen`, which holds it the same way for the same reason.
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
    _publicFuture = _discover.fetchCommunityDetails(widget.communityId);
    _footballFuture = _loadFootball();
  }

  Future<PublicCommunityFootball?> _loadFootball() async {
    try {
      return await _discover.fetchCommunityFootball(widget.communityId);
    } catch (_) {
      // Same reason as Discover: this future is created in `initState`, so a
      // rejection would escape before a builder could render it. Null is the
      // football half failing, and only the football half.
      return null;
    }
  }

  void _refresh() => setState(_load);

  /// Joining is the one write this screen offers, and it is not this screen's
  /// to define: the shared flow asks for the code when the server says one is
  /// needed, which is how a CODE_REQUIRED community stays code-required.
  ///
  /// On success the reader is a member, and this screen is the wrong one for
  /// them: it is the non-member view, and it would go on offering a Join button
  /// for a community they have just joined. So it is **replaced** rather than
  /// refreshed — replaced rather than pushed, so Back does not return to a
  /// stale page that describes a membership state that has ended.
  ///
  /// A cancelled or failed join changes nothing and leaves the reader here.
  Future<void> _join() async {
    final navigator = Navigator.of(context);
    final joined = await runJoinCommunity(
      context,
      repository: _communities,
      communityId: widget.communityId,
    );
    if (!joined || !mounted) return;

    await navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => CommunityDetailsScreen(communityId: widget.communityId),
      ),
    );
  }

  Future<void> _openMatch(String matchId) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FootballMatchScreen(
            matchId: matchId,
            repository: widget.footballRepository,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: GoColors.bgHero,
      body: FutureBuilder<PublicCommunityDetails>(
        future: _publicFuture,
        builder: (context, snapshot) {
          // A first load, or a retry after a failure, has nothing to show yet.
          // A refresh does: the page stays up and updates when the read lands.
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Scaffold(
              appBar: AppBar(title: Text(l10n.communityTitle)),
              body: ErrorState(onRetry: _refresh),
            );
          }

          final details = snapshot.data!;
          final community = details.community;

          return Column(
            children: [
              SafeArea(
                bottom: false,
                child: ClubHero(
                  // The same ground, and the same crest, as the guest's page:
                  // this is the same community seen by a reader who happens to
                  // be signed in, not a different place.
                  stadium: true,
                  bar: ClubHeroBar(
                    title: l10n.communityTitle,
                    onBack: () => Navigator.of(context).maybePop(),
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
                          key: const Key('footballCommunityJoin'),
                          style: ClubHeroButtons.filled,
                          onPressed: _join,
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
                    football: _footballFuture,
                    // The card shows what a fixture is; the action is the way
                    // in.
                    //
                    // It used to push `MatchDetailsScreen`, which is
                    // membership-gated and would have refused this reader —
                    // sending somebody from a read-only screen into a wall.
                    // There is no public upcoming-match detail screen and this
                    // cycle does not add one, so the useful offer is the one
                    // thing that would change the answer: joining.
                    matchActionLabel: l10n.joinCommunityButton,
                    onMatchAction: _join,
                    onOpenResult: (result) => _openMatch(result.matchId),
                    onOpenPlayer: (player) =>
                        openPlayerProfile(context, player.userId),
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
