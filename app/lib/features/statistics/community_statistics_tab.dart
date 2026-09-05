import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import 'community_leaderboards_tab.dart' show LeaderboardCard;
import 'community_statistics_card.dart';
import 'stat_card.dart';
import 'statistics_models.dart';
import 'statistics_period.dart';
import 'statistics_period_selector.dart';
import 'statistics_repository.dart';

/// The Statistics tab: what this community has done, and who is ahead in it,
/// over the one period the reader picked.
///
/// **One tab where there were two.** The Dashboard and the Leaderboards were
/// separate destinations with a period selector each, a load each and a Share
/// action each — so a reader could leave one on the month and the other on the
/// week, and the two Share buttons produced two cards of two different stretches
/// of time. Neither of those was a feature. There is one period here, one read,
/// and one card.
///
/// **The old Dashboard's leader tiles are gone, and their absence is the point.**
/// It highlighted the top scorer, the most active player and the most valuable
/// one — three of the same five players the boards below name, with the same
/// figures. The boards say it better, because they say who is second.
///
/// The tab reads conceptually as: the period, what the community did, who led
/// it. Nothing appears twice.
class CommunityStatisticsTab extends StatefulWidget {
  const CommunityStatisticsTab({
    super.key,
    required this.communityId,
    this.communityName,
    this.repository,
    this.renderer,
    this.shareService,
  });

  final String communityId;

  /// What this community is called, for the card that carries these figures.
  ///
  /// Passed in rather than read: the screen hosting this tab already has the
  /// community, and a second round trip for a name it is displaying in its own
  /// title would be a read for something already on screen. Null while it is
  /// not known, and the card cannot be composed until it is — a community's
  /// figures with no community on them belong to nobody.
  final String? communityName;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final StatisticsRepository? repository;

  /// The Share Card Engine's two ports, passed straight through to
  /// [presentShareCard]. Supplied only by tests.
  final ShareCardRenderer? renderer;
  final ShareService? shareService;

  @override
  State<CommunityStatisticsTab> createState() => _CommunityStatisticsTabState();
}

class _CommunityStatisticsTabState extends State<CommunityStatisticsTab> {
  late final StatisticsRepository _statistics =
      widget.repository ?? StatisticsRepository();

  /// The one selected period, and the only one on this tab.
  ///
  /// Opens on All Time — the figures the app has always shown first, and what
  /// both of the tabs this replaces opened on.
  StatisticsPeriod _period = StatisticsPeriod.allTime;

  late Future<CommunityStatistics> _future;

  /// What is on screen, or null while it loads or after a load failed.
  ///
  /// Held beside the future because the Share action sits above the builder
  /// that draws the figures — and a card must be made of what the reader is
  /// looking at rather than of a read taken when they press.
  CommunityStatistics? _shown;

  @override
  void initState() {
    super.initState();
    _future = _track(_load(_period));
  }

  Future<CommunityStatistics> _load(StatisticsPeriod period) =>
      _statistics.fetchCommunityStatistics(widget.communityId, period);

  /// Keeps [_shown] in step with whichever load is current.
  ///
  /// The period can change while a read is in flight, so a result is kept only
  /// if it is still the one being awaited — otherwise a slow weekly read
  /// landing after the reader switched to All Time would put a week's figures
  /// behind an All Time card.
  Future<CommunityStatistics> _track(Future<CommunityStatistics> load) {
    load.then(
      (statistics) {
        if (!mounted || _future != load) return;
        setState(() => _shown = statistics);
      },
      // Already reported by the builder, which shows the retry.
      onError: (_) {
        if (!mounted || _future != load) return;
        setState(() => _shown = null);
      },
    );
    return load;
  }

  Future<void> _refresh() async {
    final future = _load(_period);
    // A block body, not an arrow: an arrow returns the assigned Future, and
    // setState asserts when its callback returns one.
    setState(() {
      _future = future;
    });
    _track(future);
    // Awaited only so the refresh indicator stays up until the figures land. A
    // failure is swallowed here rather than ignored: the builder below is
    // already showing it, and letting it escape would be an unhandled error
    // from a gesture the reader has had an answer to.
    await future.then<void>((_) {}, onError: (_) {});
  }

  /// A different period is a different set of rows, so it is a fresh read
  /// rather than a filter over what is already here — the counters for a week
  /// are different records, not a subset of the running total.
  ///
  /// One call, and the totals, the five boards and the Share action all follow
  /// it: they are three views of the one object this sets loading.
  void _selectPeriod(StatisticsPeriod period) {
    if (period == _period) return;
    final future = _load(period);
    setState(() {
      _period = period;
      _future = future;
      // What is on screen belongs to the period being left. Until the new
      // figures land there is nothing to make a card of.
      _shown = null;
    });
    _track(future);
  }

  /// Whether a card can be made right now: figures on screen, and a community
  /// to put on them.
  bool get _canShare => _shown != null && widget.communityName != null;

  /// Composes the one card for what is on screen and hands it to the engine.
  ///
  /// **Nothing is read here, and the period is not asked for again.** The
  /// figures are the ones already loaded and the period is the one the selector
  /// above is showing; sharing is a picture of the current state rather than a
  /// second query for it.
  Future<void> _share() async {
    final statistics = _shown;
    final name = widget.communityName;
    if (statistics == null || name == null) return;

    final data = CommunityStatisticsCardData.of(
      statistics,
      communityName: name,
      period: _period,
    );

    // The leaders' pictures are fetched before the card is composed, not while
    // it is. The engine gives a template two frames to settle, which is ample
    // for layout and nowhere near enough for a network image — so a card
    // composed without this would show initials for players who have photos.
    await _precacheLeaders(data);
    if (!mounted) return;

    await presentShareCard(
      context,
      template: (context) => CommunityStatisticsCard(data: data),
      // The community this card is of. Already held by the tab; nothing is
      // read for it.
      communityId: widget.communityId,
      renderer: widget.renderer,
      shareService: widget.shareService,
    );
  }

  /// Loads whatever leader pictures exist into the image cache.
  ///
  /// Best effort by design, and issued together because they are independent: a
  /// picture that will not load is not an error anywhere else in the app
  /// either, and the avatar falls back to initials. `onError` is what keeps
  /// that true — without a handler `precacheImage` reports the failure to
  /// `FlutterError`, turning a missing photograph into an app-level error.
  Future<void> _precacheLeaders(CommunityStatisticsCardData data) async {
    final urls = <String>{
      for (final leader in data.leaders)
        if (leader.avatarUrl != null) leader.avatarUrl!,
    };
    if (urls.isEmpty) return;

    await Future.wait([
      for (final url in urls)
        precacheImage(NetworkImage(url), context, onError: (_, __) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // The selector sits outside the FutureBuilder so it stays put — and stays
    // usable — while a period loads or fails. A control that vanishes into a
    // spinner is one the reader cannot use to get out of the state they are in.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatisticsPeriodSelector(
                selected: _period,
                onChanged: _selectPeriod,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, Gap.md, Gap.sm, 0),
              child: IconButton(
                key: const Key('shareCommunityStatisticsButton'),
                icon: const Icon(Icons.ios_share),
                tooltip: l10n.shareCommunityStatisticsAction,
                // Disabled rather than hidden while the figures load: an action
                // that comes and goes as periods change reads as a bug.
                onPressed: _canShare ? _share : null,
              ),
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder<CommunityStatistics>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingState();
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return ErrorState(onRetry: _refresh);
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: _StatisticsBody(
                  statistics: snapshot.data!,
                  period: _period,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The totals, then the boards. In that order and only once each.
class _StatisticsBody extends StatelessWidget {
  const _StatisticsBody({required this.statistics, required this.period});

  final CommunityStatistics statistics;
  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dashboard = statistics.dashboard;
    final boards = statistics.boards;
    final showsRating =
        boards.any((board) => board.kind == LeaderboardKind.highestRated);

    return ListView(
      // Always scrollable, so pulling down refreshes even when the content is
      // shorter than the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Gap.xxl),
      children: [
        SectionHeading(
          title: l10n.communityStatisticsTitle,
          padding: const EdgeInsets.fromLTRB(
            kPageMargin,
            Gap.lg,
            kPageMargin,
            Gap.sm,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageMargin - 4),
          // The three cards are as tall as the tallest of them, so a label that
          // wraps to two lines does not leave its neighbours short.
          // `IntrinsicHeight` is what gives the stretch a height to work from —
          // inside a ListView the row's vertical extent is otherwise unbounded,
          // and stretching against that is an error rather than a layout.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatCard(
                    icon: Icons.event_available,
                    label: l10n.statCompletedMatches,
                    value: dashboard.completedMatches,
                  ),
                ),
                Expanded(
                  child: StatCard(
                    icon: Icons.group,
                    label: l10n.statTotalPlayers,
                    value: dashboard.totalPlayers,
                  ),
                ),
                Expanded(
                  child: StatCard(
                    icon: Icons.sports_soccer,
                    label: l10n.statTotalGoals,
                    value: dashboard.totalGoals,
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionHeading(title: l10n.statLeadersTitle),
        // Every board was empty, which means nothing has happened here yet
        // rather than that something is wrong. One message says so once,
        // instead of five empty cards saying it five times.
        if (boards.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
            child: EmptyState(
              icon: Icons.leaderboard_outlined,
              // A period with no results is not a community with no results:
              // "yet" is only true of All Time, and a quiet week in a community
              // that has played for a year is not a community waiting for its
              // first match.
              message: period.isBounded
                  ? l10n.leaderboardsPeriodEmpty
                  : l10n.leaderboardsEmpty,
            ),
          )
        else
          // The same card the Leaderboards tab drew, runner-ups and all. What
          // the share card leaves out it leaves out because it is a picture;
          // the screen is where somebody is reading, and second place is worth
          // reading.
          for (final board in boards) LeaderboardCard(board: board),
        // Which stretch the counted figures cover. Said before the rating note,
        // because in a bounded period the two together are the whole answer:
        // the counters are this week's, and the rating is not a week's figure
        // at all.
        if (period == StatisticsPeriod.weekly)
          FootNote(l10n.statPeriodWeeklyNote)
        else if (period == StatisticsPeriod.monthly)
          FootNote(l10n.statPeriodMonthlyNote),
        // Said once, and only when a rating is actually on screen: the figure
        // is the player's rating everywhere, not their rating here.
        if (showsRating) FootNote(l10n.leaderboardRatingNote),
        FootNote(l10n.statScopeNote),
      ],
    );
  }
}
