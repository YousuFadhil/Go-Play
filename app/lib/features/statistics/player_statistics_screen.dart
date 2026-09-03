import 'package:flutter/material.dart';

import '../../core/app_header.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../auth/auth_service.dart';
import '../profile/current_user.dart';
import '../results/result_models.dart';
import '../results/result_repository.dart';
import '../sharing/share_card_flow.dart';
import '../sharing/share_card_renderer.dart';
import '../sharing/share_service.dart';
import 'player_statistics_card.dart';
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
    this.authService,
    this.renderer,
    this.shareService,
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

  final AuthService? authService;

  /// The Share Card Engine's two ports, passed straight through to
  /// [presentShareCard]. Supplied only by tests; nothing in the app passes
  /// them, and this screen composes no card of its own — it hands the engine a
  /// template and the engine does the rest.
  final ShareCardRenderer? renderer;
  final ShareService? shareService;

  @override
  State<PlayerStatisticsScreen> createState() => _PlayerStatisticsScreenState();
}

/// What the screen draws: the six counters for the chosen period, and the one
/// rating there is.
///
/// The two arrive together because the screen shows them together, and they are
/// separate fields because only one of them is a period's.
class _PlayerRecord {
  const _PlayerRecord({required this.counters, required this.rating});

  _PlayerRecord.career(PlayerStatistics career)
      : counters = PlayerPeriodStatistics(
          matchesPlayed: career.matchesPlayed,
          wins: career.wins,
          losses: career.losses,
          draws: career.draws,
          goals: career.goals,
          mvpCount: career.mvpCount,
        ),
        rating = career.currentRating;

  final PlayerPeriodStatistics counters;
  final double rating;
}

class _PlayerStatisticsScreenState extends State<PlayerStatisticsScreen> {
  late final ResultRepository _results = widget.repository ?? ResultRepository();
  late final StatisticsRepository _statistics =
      widget.statistics ?? StatisticsRepository();
  late final AuthService _auth = widget.authService ?? AuthService();
  StatisticsPeriod _period = StatisticsPeriod.allTime;
  late Future<_PlayerRecord> _statisticsFuture;

  /// The figures currently on screen, or null while they are loading or after a
  /// load failed.
  ///
  /// Held beside the future because the Share action lives in the header,
  /// outside the `FutureBuilder` that draws them — and a card must be made of
  /// what the reader is actually looking at rather than of a figure read again
  /// at the moment they press it.
  _PlayerRecord? _shown;

  @override
  void initState() {
    super.initState();
    _statisticsFuture = _track(_load(_period));
  }

  /// Keeps [_shown] in step with whichever load is current.
  ///
  /// The period can change while a read is in flight, so a result is only kept
  /// if it is still the one being awaited — otherwise a slow weekly read
  /// landing after the reader switched to All Time would put a week's figures
  /// behind an All Time card.
  Future<_PlayerRecord> _track(Future<_PlayerRecord> load) {
    load.then(
      (record) {
        if (!mounted || _statisticsFuture != load) return;
        setState(() => _shown = record);
      },
      // Already reported by the builder, which shows the retry.
      onError: (_) {
        if (!mounted || _statisticsFuture != load) return;
        setState(() => _shown = null);
      },
    );
    return load;
  }

  Future<_PlayerRecord> _load(StatisticsPeriod period) async {
    final userId = widget.userId ?? _auth.currentUserId;
    // A record is somebody's, so without a session there is no row to name.
    if (userId == null) throw const AuthenticationFailure();

    // The career read happens whichever period is showing, because it carries
    // the rating and the rating has no period. For All Time it is also the
    // counters, exactly as before.
    final career = await _results.fetchStatistics(userId);
    if (!period.isBounded) return _PlayerRecord.career(career);

    final counters =
        await _statistics.fetchPlayerPeriodStatistics(userId, period);
    return _PlayerRecord(counters: counters, rating: career.currentRating);
  }

  Future<void> _refresh() async {
    final future = _load(_period);
    // A block body, not an arrow: an arrow returns the assigned Future, and
    // setState asserts when its callback returns one.
    setState(() {
      _statisticsFuture = future;
    });
    _track(future);
    // Awaited only so the refresh indicator stays up until the figures land.
    // A failure is swallowed here rather than ignored: the builder below is
    // already showing it.
    await future.then<void>((_) {}, onError: (_) {});
  }

  void _selectPeriod(StatisticsPeriod period) {
    if (period == _period) return;
    final future = _load(period);
    setState(() {
      _period = period;
      _statisticsFuture = future;
      // The figures on screen belong to the period being left. Until the new
      // ones land there is nothing to make a card of, so the Share action goes
      // quiet rather than offering last period's numbers under this period's
      // name.
      _shown = null;
    });
    _track(future);
  }

  /// Whether a card can be made right now.
  ///
  /// Two things have to be true and neither is about sharing: there must be
  /// figures on screen, and the player's own name and picture must be known.
  /// The identity comes from the session's held profile, which is this screen's
  /// player — it is opened for the signed-in player and for nobody else (see
  /// [PlayerStatisticsScreen.userId]).
  bool get _canShare =>
      _shown != null && CurrentUser.instance.profile.value != null;

  /// Composes the card for what is on screen and hands it to the engine.
  ///
  /// **Every figure is already resolved before this runs.** Nothing here reads
  /// a repository, and the period is the one the reader selected — the card is
  /// a picture of this screen's current state, not a second query for it.
  Future<void> _share() async {
    final record = _shown;
    final profile = CurrentUser.instance.profile.value;
    if (record == null || profile == null) return;

    final data = PlayerStatisticsCardData(
      fullName: profile.fullName,
      avatarUrl: profile.avatarUrl,
      rating: record.rating,
      period: _period,
      // All six, the same six the screen above is showing. The card used to
      // take four and leave draws and losses behind, which made its record of
      // played football impossible to reconcile.
      matchesPlayed: record.counters.matchesPlayed,
      wins: record.counters.wins,
      draws: record.counters.draws,
      losses: record.counters.losses,
      goals: record.counters.goals,
      mvpCount: record.counters.mvpCount,
    );

    // The picture is fetched before the card is composed, not while it is.
    // The engine gives a template two frames to settle, which is plenty for
    // layout and nowhere near enough for a network image — so a card composed
    // without this would show the initials of a player who has a photo.
    await _precacheAvatar(profile.avatarUrl);
    if (!mounted) return;

    await presentShareCard(
      context,
      template: (context) => PlayerStatisticsCard(data: data),
      renderer: widget.renderer,
      shareService: widget.shareService,
    );
  }

  /// Loads the player's picture into the image cache, if they have one.
  ///
  /// Best effort by design: a picture that will not load is not an error
  /// anywhere else in the app either, and the avatar falls back to initials —
  /// so a failure here costs the card its photograph and nothing more.
  ///
  /// `onError` is what makes that true. Without a handler `precacheImage`
  /// reports the failure to `FlutterError`, so an avatar the network could not
  /// fetch would surface as an app-level error for something the card already
  /// has an answer to.
  Future<void> _precacheAvatar(String? url) async {
    if (url == null) return;
    await precacheImage(NetworkImage(url), context, onError: (_, __) {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppHeader(
        title: Text(l10n.playerStatisticsTitle),
        // In the header, where a screen's own action belongs, and beside the
        // period selector rather than below the figures — sharing is something
        // done *to* this screen, not another figure on it.
        //
        // Listening to the held profile so the action appears as soon as the
        // player's identity is known, without this screen reading it again.
        actions: [
          ValueListenableBuilder(
            valueListenable: CurrentUser.instance.profile,
            builder: (context, _, __) => IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: l10n.shareMyStatisticsAction,
              // Disabled rather than hidden while the figures load: an action
              // that comes and goes as periods change reads as a bug, and a
              // card of figures that are not on screen yet would be a card of
              // nothing.
              onPressed: _canShare ? _share : null,
            ),
          ),
        ],
      ),
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
        RatingHeadline(rating: record.rating),
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
              // "yet" belongs to a career that has not started. A player with
              // nine seasons behind them who sat out this week has not played
              // a recorded match *in this period*, which is a different
              // sentence — and the career note about a starting rating would
              // be plainly false for them.
              period.isBounded ? l10n.statPeriodNoMatches : l10n.statNoMatchesYet,
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
