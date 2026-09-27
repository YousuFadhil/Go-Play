import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../auth/auth_service.dart';
import '../results/result_models.dart';
import '../results/result_repository.dart';
import 'player_intelligence_adapter.dart';
import 'player_intelligence_repository.dart';
import 'stat_card.dart';
import 'statistics_models.dart';
import 'statistics_period.dart';
import 'statistics_period_selector.dart';
import 'statistics_repository.dart';

/// A player's record: their Global Rating and their six counters, across every
/// community they play in, over the period the reader picked.
///
/// **All Time still reads what it always read, from where it always read it.**
/// `ResultRepository.fetchStatistics` answers the career from `v_user_profile`,
/// and that source is untouched — summing the player's `overall` community
/// records into a second career total would be a rival answer free to disagree
/// with the first.
///
/// **A week and a month are the community records, summed.** Those rows already
/// existed (`0028`) and simply had no reader; the summing across communities is
/// [StatisticsRepository]'s, which is where a product total belongs. This screen
/// asks two repositories because the answer genuinely comes from two places, and
/// each of them keeps its own single port.
///
/// **The rating is not periodic and is not made to look like it.** `OP-1` makes
/// the Global Rating a value the player holds now; there is no such thing as a
/// rating for last week, and the screen does not invent one. It shows the same
/// rating in every period and says so in a note whenever the counters beside it
/// are a period's.
///
/// **Nothing on it is editable, and that is the design rather than an
/// omission.** `OP-1` makes the rating system-managed, and every counter is a
/// consequence of a recorded result, so there is no client write path for any
/// figure here and no control that could offer one.
class PlayerStatisticsScreen extends StatefulWidget {
  const PlayerStatisticsScreen({
    super.key,
    this.userId,
    this.repository,
    this.statistics,
    this.intelligence,
    this.authService,
  });

  /// Whose record to show. Null means the signed-in player, which is the only
  /// way the MVP opens this screen — the parameter exists because the
  /// repository read is already keyed by player, so honouring that costs
  /// nothing and inventing a second entry point later would not.
  final String? userId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ResultRepository? repository;

  /// Likewise. Read only for a bounded period, so a test that only exercises
  /// All Time never has to supply it.
  final StatisticsRepository? statistics;

  /// Recent rating direction. Kept separate from period statistics because it
  /// is a rating-history read, not another counter source.
  final PlayerIntelligenceRepository? intelligence;

  final AuthService? authService;

  @override
  State<PlayerStatisticsScreen> createState() => _PlayerStatisticsScreenState();
}

/// What the screen draws: the six counters for the chosen period, and the one
/// rating there is.
///
/// The two arrive together because the screen shows them together, and they are
/// separate fields because only one of them is a period's.
class _PlayerRecord {
  const _PlayerRecord({
    required this.counters,
    required this.rating,
    required this.ratingTrend,
  });

  _PlayerRecord.career(
    PlayerStatistics career,
    PlayerRatingTrend ratingTrend,
  )   : counters = PlayerPeriodStatistics(
          matchesPlayed: career.matchesPlayed,
          wins: career.wins,
          losses: career.losses,
          draws: career.draws,
          goals: career.goals,
          mvpCount: career.mvpCount,
        ),
        rating = career.currentRating,
        ratingTrend = ratingTrend;

  final PlayerPeriodStatistics counters;
  final double rating;

  /// Global recent rating direction, independent of the selected counter
  /// period. It belongs beside the current Global Rating for the same reason.
  final PlayerRatingTrend ratingTrend;
}

class _PlayerStatisticsScreenState extends State<PlayerStatisticsScreen> {
  late final ResultRepository _results =
      widget.repository ?? ResultRepository();
  late final StatisticsRepository _statistics =
      widget.statistics ?? StatisticsRepository();
  late final PlayerIntelligenceRepository _intelligence =
      widget.intelligence ?? PlayerIntelligenceRepository();
  late final AuthService _auth = widget.authService ?? AuthService();
  StatisticsPeriod _period = StatisticsPeriod.allTime;
  late Future<_PlayerRecord> _statisticsFuture;

  @override
  void initState() {
    super.initState();
    _statisticsFuture = _load(_period);
  }

  Future<_PlayerRecord> _load(StatisticsPeriod period) async {
    final userId = widget.userId ?? _auth.currentUserId;
    // A record is somebody's, so without a session there is no row to name.
    if (userId == null) throw const AuthenticationFailure();

    // Current rating and its recent direction are global facts, while the six
    // counters may be period-bound. The independent reads start together so
    // adding intelligence does not serialise the screen.
    final careerFuture = _results.fetchStatistics(userId);
    // Intelligence must never make the existing statistics screen less
    // reliable. If the additive trend read is unavailable, the core career and
    // period counters still render and the trend line is simply absent.
    final trendFuture = _intelligence.fetchRatingTrend(userId).then(
          (value) => value,
          onError: (_) =>
              const PlayerRatingTrend(matchesCount: 0, ratingDelta: 0),
        );

    if (!period.isBounded) {
      final results = await Future.wait([careerFuture, trendFuture]);
      return _PlayerRecord.career(
        results[0] as PlayerStatistics,
        results[1] as PlayerRatingTrend,
      );
    }

    final countersFuture =
        _statistics.fetchPlayerPeriodStatistics(userId, period);
    final results =
        await Future.wait([careerFuture, trendFuture, countersFuture]);
    final career = results[0] as PlayerStatistics;
    return _PlayerRecord(
      counters: results[2] as PlayerPeriodStatistics,
      rating: career.currentRating,
      ratingTrend: results[1] as PlayerRatingTrend,
    );
  }

  Future<void> _refresh() async {
    final future = _load(_period);
    // A block body, not an arrow: an arrow returns the assigned Future, and
    // setState asserts when its callback returns one.
    setState(() {
      _statisticsFuture = future;
    });
    // Awaited only so the refresh indicator stays up until the figures land.
    // A failure is swallowed here rather than ignored: the builder below is
    // already showing it.
    await future.then<void>((_) {}, onError: (_) {});
  }

  void _selectPeriod(StatisticsPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _statisticsFuture = _load(period);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      // **No share action here.** A player shares themselves from their
      // Profile, which is the one place that composes the unified Player
      // Profile card; a second player-share path would be a second answer to
      // "share me" and a second card to keep in step. This screen is where a
      // player reads their own record by period, and nothing else.
      appBar: AppHeader(title: Text(l10n.playerStatisticsTitle)),
      // The selector sits outside the FutureBuilder so it stays put — and stays
      // usable — while a period loads or fails.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatisticsPeriodSelector(selected: _period, onChanged: _selectPeriod),
          Expanded(
            child: FutureBuilder<_PlayerRecord>(
              future: _statisticsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingState();
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return ErrorState(onRetry: _refresh);
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: _CareerBody(record: snapshot.data!, period: _period),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CareerBody extends StatelessWidget {
  const _CareerBody({required this.record, required this.period});

  final _PlayerRecord record;
  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final statistics = record.counters;

    return ListView(
      // Always scrollable, so pulling down refreshes even when the content is
      // shorter than the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        RatingHeadline(
          rating: record.rating,
          trend: record.ratingTrend,
        ),
        // Two cards a row rather than three: these labels are phrases where the
        // dashboard's are words, and three across leaves them wrapping to three
        // lines on a phone.
        _CardRow(children: [
          StatCard(
            icon: Icons.sports_soccer,
            label: l10n.statMatchesPlayed,
            value: statistics.matchesPlayed,
          ),
          StatCard(
            icon: Icons.emoji_events,
            label: l10n.statWins,
            value: statistics.wins,
          ),
        ]),
        _CardRow(children: [
          StatCard(
            icon: Icons.remove,
            label: l10n.statDraws,
            value: statistics.draws,
          ),
          StatCard(
            icon: Icons.trending_down,
            label: l10n.statLosses,
            value: statistics.losses,
          ),
        ]),
        _CardRow(children: [
          StatCard(
            icon: Icons.scoreboard,
            label: l10n.statGoals,
            value: statistics.goals,
          ),
          StatCard(
            icon: Icons.star,
            label: l10n.statMvpCount,
            value: statistics.mvpCount,
          ),
        ]),
        // Two derived efficiency measures, from the same counters already on
        // screen. They are not persisted and therefore cannot drift from the
        // W/D/L/goals figures above.
        _CardRow(children: [
          _MetricCard(
            icon: Icons.percent,
            label: l10n.statWinRate,
            value: statistics.matchesPlayed == 0
                ? '—'
                : '${(statistics.wins * 100 / statistics.matchesPlayed).toStringAsFixed(1)}%',
          ),
          _MetricCard(
            icon: Icons.speed,
            label: l10n.statGoalsPerMatch,
            value: statistics.matchesPlayed == 0
                ? '—'
                : (statistics.goals / statistics.matchesPlayed)
                    .toStringAsFixed(2),
          ),
        ]),
        if (statistics.matchesPlayed == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              // "yet" belongs to a career that has not started. A player with
              // nine seasons behind them who sat out this week has not played
              // a recorded match *in this period*, which is a different
              // sentence — and the career note about a starting rating would
              // be plainly false for them.
              period.isBounded
                  ? l10n.statPeriodNoMatches
                  : l10n.statNoMatchesYet,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Text(
            _scopeNote(l10n),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      ],
    );
  }

  /// What the figures above cover.
  ///
  /// All Time keeps the note it has always had. A bounded period says which
  /// stretch the counters describe **and** that the rating is not one of them —
  /// the rating is the largest thing on the screen and the reader has just
  /// asked for a week, so leaving it unexplained is the one way this screen
  /// could tell a lie.
  String _scopeNote(AppLocalizations l10n) => switch (period) {
        StatisticsPeriod.allTime => l10n.statCareerNote,
        StatisticsPeriod.weekly =>
          '${l10n.statPeriodWeeklyNote} ${l10n.statPeriodRatingNote}',
        StatisticsPeriod.monthly =>
          '${l10n.statPeriodMonthlyNote} ${l10n.statPeriodRatingNote}',
      };
}

/// A row of equal-height cards.
///
/// `IntrinsicHeight` is what gives the stretch a height to work from — inside a
/// ListView the row's vertical extent is otherwise unbounded, and stretching
/// against that is an error rather than a layout.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final child in children) Expanded(child: child)],
        ),
      ),
    );
  }
}

/// The Global Rating, given the prominence it has in the product.
///
/// Shown to one decimal place because that is `OP-1`'s presentation rule. The
/// stored value carries three (`numeric(5,3)`, migration `0073`) — the engine
/// moves a rating by as little as 0.005 for turning up and 0.010 for a goal
/// (migration `0078`), and a scale that could not hold those would make
/// corrections irreversible — so the decimals beneath are real and deliberately
/// not shown here.
class RatingHeadline extends StatelessWidget {
  const RatingHeadline({
    super.key,
    required this.rating,
    required this.trend,
  });

  final double rating;
  final PlayerRatingTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            Icon(Icons.military_tech,
                size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              rating.toStringAsFixed(1),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.statCurrentRating, style: theme.textTheme.titleMedium),
            if (trend.hasMatches) ...[
              const SizedBox(height: 10),
              _RatingTrendLine(trend: trend),
            ],
          ],
        ),
      ),
    );
  }
}


/// A derived decimal/percentage measure.
///
/// Kept local to Player Statistics so the shared [StatCard] can stay honest:
/// that component represents integer counters on community and player screens,
/// while these values are calculations over those counters.
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.all(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recent rating movement lives inside the rating card rather than as another
/// dashboard tile: it explains the rating, and unlike Win Rate or Goals/Match
/// it does not change when the period selector changes.
class _RatingTrendLine extends StatelessWidget {
  const _RatingTrendLine({required this.trend});

  final PlayerRatingTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = trend.ratingDelta;
    final icon = delta > 0
        ? Icons.trending_up
        : delta < 0
            ? Icons.trending_down
            : Icons.trending_flat;
    final value = delta > 0
        ? '+${delta.toStringAsFixed(2)}'
        : delta.toStringAsFixed(2);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$value · ${context.l10n.statRatingTrend}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
