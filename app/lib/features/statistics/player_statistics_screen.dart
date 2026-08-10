import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../auth/auth_service.dart';
import '../results/result_models.dart';
import '../results/result_repository.dart';
import 'stat_card.dart';

/// A player's record: their Global Rating and their six career counters, across
/// every community they play in.
///
/// **It adds no data layer of its own.** `ResultRepository.fetchStatistics`
/// already reads exactly these seven figures — it was built with the rating
/// engine and had no screen until now — so this is a reader for something that
/// already existed rather than a second path to it.
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
    this.authService,
  });

  /// Whose record to show. Null means the signed-in player, which is the only
  /// way the MVP opens this screen — the parameter exists because the
  /// repository read is already keyed by player, so honouring that costs
  /// nothing and inventing a second entry point later would not.
  final String? userId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ResultRepository? repository;
  final AuthService? authService;

  @override
  State<PlayerStatisticsScreen> createState() => _PlayerStatisticsScreenState();
}

class _PlayerStatisticsScreenState extends State<PlayerStatisticsScreen> {
  late final ResultRepository _results = widget.repository ?? ResultRepository();
  late final AuthService _auth = widget.authService ?? AuthService();
  late Future<PlayerStatistics> _statisticsFuture;

  @override
  void initState() {
    super.initState();
    _statisticsFuture = _load();
  }

  Future<PlayerStatistics> _load() async {
    final userId = widget.userId ?? _auth.currentUserId;
    // A record is somebody's, so without a session there is no row to name.
    if (userId == null) throw const AuthenticationFailure();
    return _results.fetchStatistics(userId);
  }

  Future<void> _refresh() async {
    final future = _load();
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(title: Text(l10n.playerStatisticsTitle)),
      body: FutureBuilder<PlayerStatistics>(
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
            child: _CareerBody(statistics: snapshot.data!),
          );
        },
      ),
    );
  }
}

class _CareerBody extends StatelessWidget {
  const _CareerBody({required this.statistics});

  final PlayerStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ListView(
      // Always scrollable, so pulling down refreshes even when the content is
      // shorter than the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        RatingHeadline(rating: statistics.currentRating),
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
        if (statistics.matchesPlayed == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              l10n.statNoMatchesYet,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Text(
            l10n.statCareerNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      ],
    );
  }
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
/// stored value carries two — the engine moves a rating by 0.05 for a goal, and
/// a scale that could not hold that would make corrections irreversible — so
/// the second decimal is real and deliberately not shown here.
class RatingHeadline extends StatelessWidget {
  const RatingHeadline({super.key, required this.rating});

  final double rating;

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
          ],
        ),
      ),
    );
  }
}
