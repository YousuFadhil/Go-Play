import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../profile/player_identity.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import 'community_statistics_card.dart';
import 'stat_card.dart';
import 'statistics_models.dart';
import 'statistics_period.dart';
import 'statistics_period_selector.dart';
import 'statistics_repository.dart';

/// The Community Dashboard: what this community has done, and who leads it,
/// over the period the reader picked.
///
/// It owns its own load rather than joining the details screen's, for one
/// practical reason — a recorded result changes these figures and nothing else
/// on that screen, so the dashboard needs to be refreshable on its own. Pulling
/// down does it.
///
/// **The period is this tab's state, not the screen's.** The dashboard and the
/// leaderboards are two separate loads that already refresh independently, and
/// a reader looking at a board for the month has said nothing about what the
/// dashboard should show. Each surface remembers its own choice, and each opens
/// on All Time — the figures the app has always shown first.
class CommunityDashboardTab extends StatefulWidget {
  const CommunityDashboardTab({
    super.key,
    required this.communityId,
    this.communityName,
    StatisticsRepository? repository,
    this.renderer,
    this.shareService,
  }) : _repository = repository;

  final String communityId;

  /// What this community is called, for the card that carries these figures.
  ///
  /// Passed in rather than read: the screen hosting this tab already has the
  /// community, and a second read for a name it is displaying in its own title
  /// would be a round trip for something already on screen. Null while it is
  /// not known, and the card cannot be composed until it is — a community's
  /// figures with no community on them belong to nobody.
  final String? communityName;

  final StatisticsRepository? _repository;

  /// The Share Card Engine's two ports, passed straight through to
  /// [presentShareCard]. Supplied only by tests; this tab composes no card of
  /// its own and adds no renderer, preview or share service.
  final ShareCardRenderer? renderer;
  final ShareService? shareService;

  @override
  State<CommunityDashboardTab> createState() => _CommunityDashboardTabState();
}

class _CommunityDashboardTabState extends State<CommunityDashboardTab> {
  late final StatisticsRepository _repository =
      widget._repository ?? StatisticsRepository();
  StatisticsPeriod _period = StatisticsPeriod.allTime;
  late Future<CommunityDashboard> _dashboardFuture;

  /// The figures currently on screen, or null while they load or after a load
  /// failed. Held beside the future because the Share action sits above the
  /// `FutureBuilder` that draws them — and a card must be made of what the
  /// reader is looking at rather than of a figure read again when they press.
  CommunityDashboard? _shown;

  @override
  void initState() {
    super.initState();
    _dashboardFuture =
        _track(_repository.fetchDashboard(widget.communityId, _period));
  }

  /// Keeps [_shown] in step with whichever load is current.
  ///
  /// The period can change while a read is in flight, so a result is kept only
  /// if it is still the one being awaited — otherwise a slow weekly read
  /// landing after the reader switched to All Time would put a week's figures
  /// behind an All Time card.
  Future<CommunityDashboard> _track(Future<CommunityDashboard> load) {
    load.then(
      (dashboard) {
        if (!mounted || _dashboardFuture != load) return;
        setState(() => _shown = dashboard);
      },
      // Already reported by the builder, which shows the retry.
      onError: (_) {
        if (!mounted || _dashboardFuture != load) return;
        setState(() => _shown = null);
      },
    );
    return load;
  }

  Future<void> _refresh() async {
    final future = _repository.fetchDashboard(widget.communityId, _period);
    // A block body, not an arrow: `() => _dashboardFuture = future` evaluates
    // to the assigned Future, and setState asserts when its callback returns
    // one.
    setState(() {
      _dashboardFuture = future;
    });
    _track(future);
    // Awaited only so the refresh indicator stays up until the figures land.
    // A failure is swallowed here rather than ignored: the builder below is
    // already showing it, and letting it escape would be an unhandled error
    // from a gesture the user has had an answer to.
    await future.then<void>((_) {}, onError: (_) {});
  }

  /// A different period is a different set of figures, so it is a fresh read
  /// rather than a filter over what is already here — the counters for a week
  /// are different rows, not a subset of the running total.
  void _selectPeriod(StatisticsPeriod period) {
    if (period == _period) return;
    final future = _repository.fetchDashboard(widget.communityId, period);
    setState(() {
      _period = period;
      _dashboardFuture = future;
      // The figures on screen belong to the period being left. Until the new
      // ones land there is nothing to make a card of.
      _shown = null;
    });
    _track(future);
  }

  /// Whether a card can be made right now: figures on screen, and a community
  /// to put on them.
  bool get _canShare => _shown != null && widget.communityName != null;

  /// Composes the card for what is on screen and hands it to the engine.
  ///
  /// **Every figure is already resolved before this runs.** Nothing here reads
  /// a repository, and the period is the Dashboard's own — this tab keeps its
  /// period separately from the Leaderboards, and sharing does not change that.
  Future<void> _share() async {
    final dashboard = _shown;
    final name = widget.communityName;
    if (dashboard == null || name == null) return;

    final data = CommunityStatisticsCardData.of(
      dashboard,
      communityName: name,
      period: _period,
    );

    // The leaders' pictures are fetched before the card is composed, not while
    // it is. The engine gives a template two frames to settle, which is ample
    // for layout and nowhere near enough for a network image — so a card
    // composed without this would show initials for players who have photos.
    await _precacheLeaders(dashboard);
    if (!mounted) return;

    await presentShareCard(
      context,
      template: (context) => CommunityStatisticsCard(data: data),
      renderer: widget.renderer,
      shareService: widget.shareService,
    );
  }

  /// Loads whatever leader pictures exist into the image cache.
  ///
  /// Best effort by design, and issued together because the three are
  /// independent: a picture that will not load is not an error anywhere else in
  /// the app either, and the avatar falls back to initials. `onError` is what
  /// keeps that true — without a handler `precacheImage` reports the failure to
  /// `FlutterError`, turning a missing photograph into an app-level error.
  Future<void> _precacheLeaders(CommunityDashboard dashboard) async {
    final urls = <String>{
      for (final leader in [
        dashboard.topScorer,
        dashboard.mostActivePlayer,
        dashboard.mostMvp,
      ])
        if (leader?.avatarUrl != null) leader!.avatarUrl!,
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
        // Share sits beside the period rather than in the screen's app bar,
        // and that is the point: the bar belongs to the community screen and
        // its tabs, while this figure set and this period belong to the
        // Dashboard alone. The Leaderboards keep their own period and get no
        // Share action from this.
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
          child: FutureBuilder<CommunityDashboard>(
            future: _dashboardFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingState();
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return ErrorState(onRetry: _refresh);
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: _DashboardBody(
                  dashboard: snapshot.data!,
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

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.dashboard, required this.period});

  final CommunityDashboard dashboard;
  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final noLeaders = dashboard.topScorer == null &&
        dashboard.mostActivePlayer == null &&
        dashboard.mostMvp == null;

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
          // The three cards are as tall as the tallest of them, so a label
          // that wraps to two lines does not leave its neighbours short.
          // `IntrinsicHeight` is what gives the stretch a height to work
          // from — inside a ListView the row's vertical extent is otherwise
          // unbounded, and stretching against that is an error rather than a
          // layout.
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
        if (noLeaders)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
            child: EmptyState(
              icon: Icons.emoji_events_outlined,
              // "yet" is only true of All Time. A quiet week in a community
              // that has played for a year is not a community waiting for its
              // first result, and telling the reader it is would read as a bug.
              message: period.isBounded
                  ? l10n.statPeriodEmptyBody
                  : l10n.statEmptyBody,
            ),
          )
        else
          SectionCard(
            padding: EdgeInsets.zero,
            children: [
              LeaderTile(
                icon: Icons.sports_soccer,
                label: l10n.statTopScorer,
                leader: dashboard.topScorer,
                describeValue: l10n.goalsScoredLabel,
              ),
              LeaderTile(
                icon: Icons.directions_run,
                label: l10n.statMostActivePlayer,
                leader: dashboard.mostActivePlayer,
                describeValue: l10n.statMatchesPlayedValue,
              ),
              LeaderTile(
                icon: Icons.star,
                label: l10n.statMostMvp,
                leader: dashboard.mostMvp,
                describeValue: l10n.statMvpValue,
              ),
            ],
          ),
        // The scope note is true of every period — it says what a figure counts,
        // not what stretch it covers. The period note says the stretch, and only
        // where there is one: "all time" needs no explaining.
        if (period == StatisticsPeriod.weekly)
          FootNote(l10n.statPeriodWeeklyNote)
        else if (period == StatisticsPeriod.monthly)
          FootNote(l10n.statPeriodMonthlyNote),
        FootNote(l10n.statScopeNote),
      ],
    );
  }
}

/// Who leads one measure, or that nobody does yet.
///
/// [describeValue] renders the figure in the measure's own words — goals,
/// matches, or times — so the tile never shows a bare number whose unit the
/// reader has to infer from the label above it.
class LeaderTile extends StatelessWidget {
  const LeaderTile({
    super.key,
    required this.icon,
    required this.label,
    required this.leader,
    required this.describeValue,
  });

  final IconData icon;
  final String label;
  final StatisticLeader? leader;
  final String Function(int) describeValue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final leader = this.leader;

    return ListTile(
      leading: CircleAvatar(
        // A measure nobody leads is drawn quietly. Giving "Not yet" the same
        // coloured disc as a real leader makes an absence look like a result.
        backgroundColor: leader == null
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        foregroundColor: leader == null
            ? scheme.onSurfaceVariant
            : scheme.onPrimaryContainer,
        child: Icon(icon, size: 20),
      ),
      title: Text(label, style: theme.textTheme.bodyMedium),
      // The leading disc stays the measure's icon: it says which figure this
      // tile is, and a measure nobody leads has no player to draw. The player
      // goes where the player's name already was.
      subtitle: leader == null
          ? Text(
              l10n.statNoneYet,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            )
          : _LeaderIdentity(leader: leader),
      trailing: leader == null
          ? null
          : Text(
              describeValue(leader.value),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
    );
  }
}

/// Who leads a measure: their face, their name, and the way into their profile.
///
/// **A record can outlive the profile it describes.** A soft-deleted account
/// keeps its figures and loses its `users` row, so the name arrives null and
/// the tile says so — and offers nothing to open, because there is nothing
/// behind it. That is `userId: null` here rather than a link certain to be
/// refused.
class _LeaderIdentity extends StatelessWidget {
  const _LeaderIdentity({required this.leader});

  final StatisticLeader leader;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final named = leader.fullName != null;

    return PlayerIdentityTap(
      key: Key('leaderIdentity_${leader.userId}'),
      userId: named ? leader.userId : null,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerAvatar(
              avatarUrl: leader.avatarUrl,
              fullName: leader.fullName,
              radius: 12,
            ),
            const SizedBox(width: Gap.sm),
            Flexible(
              child: Text(
                leader.fullName ?? l10n.statFormerPlayer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
