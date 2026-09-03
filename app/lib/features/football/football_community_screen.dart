import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import '../communities/community_repository.dart';
import '../communities/community_details_screen.dart';
import '../communities/join_community_flow.dart';
import '../discover/discover_models.dart';
import '../discover/discover_repository.dart';
import '../discover/discover_widgets.dart';
import '../profile/player_identity.dart';
import 'football_match_screen.dart';
import 'football_models.dart';
import 'football_repository.dart';
import 'football_result_card.dart';

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
/// Read only. The one action is joining, and it goes through the flow that
/// already owns that conversation — including asking for the code where the
/// policy requires one, which is the only way a code ever reaches a client.
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
  final FootballRepository? footballRepository;
  final CommunityRepository? communityRepository;

  @override
  State<FootballCommunityScreen> createState() =>
      _FootballCommunityScreenState();
}

/// The public half of the page: identity and what is scheduled. Read through
/// the anonymous discovery models, which a signed-in reader may also use.
typedef _PublicPart = PublicCommunityDetails;

/// The football half: the record, what has been played, and who leads.
///
/// Held apart from the public half rather than merged into one future, because
/// the two fail independently and must be seen to. A football read that fails
/// must not take the community's name and its fixtures off the screen.
typedef _FootballPart = (
  CommunityFootballStats,
  List<CompletedMatch>,
  List<CommunityPlayerStats>,
);

class _FootballCommunityScreenState extends State<FootballCommunityScreen> {
  late final DiscoverRepository _discover =
      widget.discoverRepository ?? DiscoverRepository();
  late final FootballRepository _football =
      widget.footballRepository ?? FootballRepository();
  late final CommunityRepository _communities =
      widget.communityRepository ?? CommunityRepository();

  late Future<_PublicPart> _publicFuture;
  late Future<_FootballPart?> _footballFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _publicFuture = _discover.fetchCommunityDetails(widget.communityId);
    _footballFuture = _loadFootball();
  }

  /// The three football reads, together. They are one section of the page and
  /// are useless in pieces, so they succeed or fail as one — but separately from
  /// the public half above them.
  Future<_FootballPart?> _loadFootball() async {
    try {
      return await _readFootball();
    } catch (_) {
      // Same reason as Discover: this future is created in `initState`, so a
      // rejection would escape before a builder could render it. Null is the
      // football half failing, and only the football half.
      return null;
    }
  }

  Future<_FootballPart> _readFootball() async {
    final results = await Future.wait([
      _football.fetchCommunityStats(widget.communityId),
      _football.fetchCompletedMatches(
        communityId: widget.communityId,
        limit: 5,
      ),
      _football.fetchCommunityPlayerStats(widget.communityId),
    ]);
    return (
      results[0] as CommunityFootballStats,
      results[1] as List<CompletedMatch>,
      results[2] as List<CommunityPlayerStats>,
    );
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
          builder: (_) => FootballMatchScreen(matchId: matchId),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: GoColors.bgHero,
      body: FutureBuilder<_PublicPart>(
        future: _publicFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
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
                  bar: ClubHeroBar(
                    title: l10n.communityTitle,
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  identity: _Identity(community: community),
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
                  child: RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsetsDirectional.only(
                        bottom: Layout.listBottom,
                      ),
                      children: [
                        ..._upcomingSection(l10n, details),
                        // The football half renders under its own builder, so a
                        // failure here leaves everything above it standing.
                        FutureBuilder<_FootballPart?>(
                          future: _footballFuture,
                          builder: (context, football) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _footballSections(l10n, football),
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

  List<Widget> _upcomingSection(AppLocalizations l10n, _PublicPart details) => [
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
            // The card shows what a fixture is; the action is the way in.
            //
            // It used to push `MatchDetailsScreen`, which is membership-gated
            // and would have refused this reader — sending somebody from a
            // read-only screen into a wall. There is no public upcoming-match
            // detail screen and this cycle does not add one, so the useful
            // offer is the one thing that would change the answer: joining.
            PublicMatchCard(
              match: match,
              showCommunityName: false,
              actionLabel: l10n.joinCommunityButton,
              onAction: _join,
            ),
      ];

  List<Widget> _footballSections(
    AppLocalizations l10n,
    AsyncSnapshot<_FootballPart?> snapshot,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return [
        DiscoverSectionHeader(title: l10n.footballRecordTitle),
        const Padding(
          padding: EdgeInsets.all(Gap.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (snapshot.hasError || snapshot.data == null) {
      return [
        DiscoverSectionHeader(title: l10n.footballRecordTitle),
        DiscoverEmpty(
          icon: Icons.cloud_off_outlined,
          message: l10n.latestResultsFailed,
        ),
      ];
    }

    final (stats, results, players) = snapshot.data!;
    return [
      DiscoverSectionHeader(title: l10n.footballRecordTitle),
      _RecordRow(stats: stats),
      DiscoverSectionHeader(title: l10n.recentResultsTitle),
      if (results.isEmpty)
        DiscoverEmpty(
          icon: Icons.sports_soccer,
          message: l10n.latestResultsEmpty,
        )
      else
        for (final match in results)
          FootballResultCard(
            match: match,
            showCommunityName: false,
            onOpen: () => _openMatch(match.matchId),
          ),
      DiscoverSectionHeader(
        title: l10n.topPlayersTitle,
        subtitle: l10n.topPlayersSubtitle,
      ),
      if (players.isEmpty)
        DiscoverEmpty(
          icon: Icons.emoji_events_outlined,
          message: l10n.topPlayersEmpty,
        )
      else
        for (final player in rankTopPlayers(players))
          _PlayerRow(player: player),
    ];
  }
}

/// The approved order for Top Players.
///
/// Rating first, then goals, then MVPs, then the name. This invents no measure
/// and weights nothing: every value is one the product already computes, and the
/// name is there so that two players who are equal on all three do not swap
/// places between two reads of the same list. A ranking that is not stable is
/// not a ranking.
///
/// Exposed rather than private so the rule can be tested as a rule, without
/// pumping a screen to find out what order it drew.
List<CommunityPlayerStats> rankTopPlayers(
  List<CommunityPlayerStats> players, {
  int take = 5,
}) {
  final ranked = [...players]..sort((a, b) {
      final byRating = b.overallRating.compareTo(a.overallRating);
      if (byRating != 0) return byRating;
      final byGoals = b.goals.compareTo(a.goals);
      if (byGoals != 0) return byGoals;
      final byMvp = b.mvpCount.compareTo(a.mvpCount);
      if (byMvp != 0) return byMvp;
      return a.displayName.compareTo(b.displayName);
    });
  return ranked.take(take).toList();
}

class _Identity extends StatelessWidget {
  const _Identity({required this.community});

  final PublicCommunity community;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CommunityCrest(name: community.name, logoUrl: community.logoUrl),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                community.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (community.description?.trim().isNotEmpty ?? false)
                Text(
                  community.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white70),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The community's football record: the four figures Cycle 2 publishes.
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.stats});

  final CommunityFootballStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, 0, kPageMargin, Gap.md),
      child: Row(
        children: [
          _Figure(
              value: stats.completedMatches, label: l10n.completedMatchesTitle),
          _Figure(value: stats.players, label: l10n.statPlayersWithRecord),
          _Figure(value: stats.goals, label: l10n.statGoals),
          _Figure(value: stats.mvpCount, label: l10n.statMvps),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: GoColors.primaryDeep,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One line of the Top Players list.
///
/// Every row is a registered player: the statistics relation is keyed by user
/// and a Professional Guest has no user, so a guest cannot reach this list at
/// all. The row therefore always opens a profile — there is no guest case to
/// handle here, and inventing one would suggest guests belong in a ranking.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});

  final CommunityPlayerStats player;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => openPlayerProfile(context, player.userId),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kPageMargin,
          vertical: Gap.sm,
        ),
        child: Row(
          children: [
            PlayerAvatar(
              avatarUrl: player.avatarUrl,
              fullName: player.displayName,
              radius: 18,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${l10n.statMatchesPlayed} ${player.matchesPlayed}'
                    '  ·  ${l10n.statGoals} ${player.goals}'
                    '  ·  ${l10n.statMvps} ${player.mvpCount}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.xs,
              ),
              decoration: BoxDecoration(
                color: GoColors.statusOpenBg,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                player.overallRating.toStringAsFixed(2),
                textDirection: TextDirection.ltr,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GoColors.primaryDeep,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
