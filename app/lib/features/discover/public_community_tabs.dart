import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/skeleton.dart';
import '../../core/tokens.dart';
import '../profile/player_identity.dart';
import '../results/result_card.dart';
import 'discover_models.dart';
import 'discover_repository.dart';
import 'discover_tabs.dart';
import 'discover_widgets.dart';

/// Everything under the hero of a community page, for a reader who is not in
/// it: the football record, then three tabs.
///
/// **One hierarchy, one widget, two screens.** The guest's community page and
/// the signed-in non-member's used to be built separately, and they had drifted
/// into two different pages -- one with the fixtures first, one with a record
/// and a ranking -- so signing in changed what a community *was* rather than
/// what the reader could do in it. Both now hand this widget the same public
/// reads and differ only in what a tap does, which they pass in.
///
/// Read top to bottom: the [FootballRecordBand] (always visible, above the
/// tabs), then Latest Results, Upcoming Matches and Top Players, opening on
/// Latest Results. The record and the players come from the one public football
/// read ([DiscoverRepository.fetchCommunityFootball]); the results and the
/// fixtures come from the community details the screen has already loaded.
///
/// Presentation only. It owns no data, no navigation and no auth policy: the
/// [controller] is the screen's, so the selected tab survives a refresh, and
/// every action arrives as a callback.
class PublicCommunityTabs extends StatelessWidget {
  const PublicCommunityTabs({
    super.key,
    required this.controller,
    required this.matches,
    required this.results,
    required this.football,
    required this.matchActionLabel,
    required this.onMatchAction,
    required this.onOpenResult,
    required this.onRefresh,
    this.onOpenPlayer,
  });

  final TabController controller;

  /// This community's upcoming matches. Never a roster: the public contract
  /// carries how many places are open and nobody's name.
  final List<PublicMatch> matches;

  /// This community's most recent results.
  final List<PublicResult> results;

  /// The record and the Top Players. Null is the football read failing, and
  /// only the football read: it is a value rather than a rejection because the
  /// future is created before any builder has attached to it.
  final Future<PublicCommunityFootball?> football;

  /// What an upcoming match's button says and does. The same for every match:
  /// a reader outside the community is offered the one thing that would change
  /// the answer, which is joining.
  final String matchActionLabel;
  final VoidCallback onMatchAction;

  final void Function(PublicResult result) onOpenResult;

  /// Runs the screen's refresh, for a pull down and for both retry buttons. It
  /// replaces the futures and never touches [controller].
  final VoidCallback onRefresh;

  /// Where a Top Players row leads. Null leaves the rows plain.
  final void Function(PublicCommunityTopPlayer player)? onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<PublicCommunityFootball?>(
      future: football,
      builder: (context, snapshot) {
        final data = snapshot.hasError ? null : snapshot.data;
        // Placeholders only when there is nothing to show yet. A refresh keeps
        // the football that is already on screen until the new read lands, so a
        // pull down does not blank the record and the ranking under the reader's
        // finger.
        final loading =
            snapshot.connectionState != ConnectionState.done && data == null;

        return Column(
          children: [
            // **Above the tabs, and always there.** It is not one of them: the
            // record describes the community whichever tab is open.
            if (loading)
              const _RecordSkeleton()
            else if (data == null)
              _RecordFailed(onRetry: onRefresh)
            else
              FootballRecordBand(record: data.record),
            DiscoverTabs(
              controller: controller,
              labels: [
                l10n.latestResultsTitle,
                l10n.upcomingMatchesTitle,
                l10n.topPlayersTitle,
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: controller,
                children: [
                  _panel(
                    key: const Key('communityTabResults'),
                    children: _resultsPanel(l10n),
                  ),
                  _panel(
                    key: const Key('communityTabUpcoming'),
                    children: _upcomingPanel(l10n),
                  ),
                  _panel(
                    key: const Key('communityTabPlayers'),
                    children: _playersPanel(context, l10n, loading, data),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// One tab's page: its own scroll view and its own pull-to-refresh, so a tab
  /// that is short still pulls and one that is long still scrolls.
  Widget _panel({required Key key, required List<Widget> children}) {
    return RefreshIndicator(
      key: key,
      onRefresh: () async => onRefresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.only(bottom: Layout.listBottom),
        children: children,
      ),
    );
  }

  List<Widget> _resultsPanel(AppLocalizations l10n) {
    if (results.isEmpty) {
      // Nothing played yet is a football state, not a fault.
      return [
        DiscoverEmpty(
          icon: Icons.sports_soccer,
          message: l10n.latestResultsEmpty,
        ),
      ];
    }
    return [
      ResultsList<PublicResult>(
        results: results,
        identityOf: (result) => result.matchId,
        toggleKey: const Key('publicCommunityPreviousResultsToggle'),
        itemBuilder: (context, result) => PublicResultCard(
          result: result,
          // The community is already named at the top of the screen.
          showCommunityName: false,
          onOpen: () => onOpenResult(result),
        ),
      ),
    ];
  }

  List<Widget> _upcomingPanel(AppLocalizations l10n) {
    if (matches.isEmpty) {
      return [
        DiscoverEmpty(
          icon: Icons.event_outlined,
          message: l10n.discoverNoUpcomingMatches,
        ),
      ];
    }
    return [
      for (final match in matches)
        PublicMatchCard(
          match: match,
          showCommunityName: false,
          actionLabel: matchActionLabel,
          onAction: onMatchAction,
        ),
    ];
  }

  List<Widget> _playersPanel(
    BuildContext context,
    AppLocalizations l10n,
    bool loading,
    PublicCommunityFootball? data,
  ) {
    if (loading) return [const _PlayersSkeleton()];

    if (data == null) {
      return [
        DiscoverEmpty(
          icon: Icons.cloud_off_outlined,
          message: l10n.latestResultsFailed,
          action: OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.retryButton),
          ),
        ),
      ];
    }

    if (data.topPlayers.isEmpty) {
      return [
        DiscoverEmpty(
          icon: Icons.emoji_events_outlined,
          message: l10n.topPlayersEmpty,
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Layout.sheetGutter + Gap.xs,
          Gap.xs,
          Layout.sheetGutter + Gap.xs,
          Gap.sm,
        ),
        child: Text(
          l10n.topPlayersSubtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
      // Ranks are the row's place in the list, one to eleven, exactly as the
      // database ordered it. Nothing here sorts.
      for (var i = 0; i < data.topPlayers.length; i++)
        TopPlayerRow(
          key: Key('topPlayerRow_${data.topPlayers[i].userId}'),
          rank: i + 1,
          player: data.topPlayers[i],
          onOpen: onOpenPlayer == null
              ? null
              : () => onOpenPlayer!(data.topPlayers[i]),
        ),
    ];
  }
}

/// The four figures of a community's football record, as one band.
///
/// Deliberately **not four cards**. It is a single surface with four figures on
/// it and hairlines between them, so the record reads as a summary of the
/// community rather than as four things to look at. The figure is the loud part
/// and the label the quiet one, in that order, in every arrangement.
///
/// **It measures before it decides**, in the way [DiscoverTabs] does. Four
/// columns across a phone are right while every label still fits its column on
/// at most two lines without a word being broken. When one does not -- a narrow
/// screen, a large text size, a longer translation -- the band becomes a
/// two-by-two rather than shrinking the labels into unreadability, and every
/// label stays whole in both languages.
class FootballRecordBand extends StatelessWidget {
  const FootballRecordBand({super.key, required this.record});

  final PublicCommunityFootballRecord record;

  /// Below this a column is too tight to read whatever it holds.
  static const _minColumn = 72.0;
  static const _cellPadding = 6.0;

  /// Whether four columns fit in [width] for these [labels] in [style].
  ///
  /// Public to the library so a test can ask the rule directly.
  static bool fitsOneRow(
    BuildContext context, {
    required List<String> labels,
    required double width,
    required TextStyle style,
  }) {
    final column = width / labels.length;
    if (column < _minColumn) return false;
    final inner = column - _cellPadding * 2;

    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    for (final label in labels) {
      // At most two lines...
      final whole = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 2,
      )..layout(maxWidth: inner);
      final tooLong = whole.didExceedMaxLines;
      whole.dispose();
      if (tooLong) return false;

      // ...and no word cut in half to get there.
      for (final word in label.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final tooWide = painter.width > inner;
        painter.dispose();
        if (tooWide) return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle(fontSize: 11);

    final metrics = [
      _Metric(
        key: const Key('recordCompletedMatches'),
        value: record.completedMatches,
        label: l10n.completedMatchesTitle,
      ),
      _Metric(
        key: const Key('recordPlayers'),
        value: record.players,
        label: l10n.statPlayersWithRecord,
      ),
      _Metric(
        key: const Key('recordGoals'),
        value: record.goals,
        label: l10n.statGoals,
      ),
      _Metric(
        key: const Key('recordMvps'),
        value: record.mvpCount,
        label: l10n.statMvps,
      ),
    ];

    return _BandSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final oneRow = fitsOneRow(
            context,
            labels: [for (final m in metrics) m.label],
            width: constraints.maxWidth,
            style: labelStyle,
          );

          Widget cell(_Metric m) => _MetricCell(metric: m, style: labelStyle);

          if (oneRow) {
            return Row(
              key: const Key('recordOneRow'),
              children: [
                for (var i = 0; i < metrics.length; i++) ...[
                  if (i > 0) const _Hairline.vertical(),
                  Expanded(child: cell(metrics[i])),
                ],
              ],
            );
          }

          return Column(
            key: const Key('recordTwoByTwo'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: cell(metrics[0])),
                  const _Hairline.vertical(),
                  Expanded(child: cell(metrics[1])),
                ],
              ),
              const _Hairline.horizontal(),
              Row(
                children: [
                  Expanded(child: cell(metrics[2])),
                  const _Hairline.vertical(),
                  Expanded(child: cell(metrics[3])),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Metric {
  const _Metric({required this.key, required this.value, required this.label});

  final Key key;
  final int value;
  final String label;
}

/// The single rounded surface the record sits on, placed on the sheet with the
/// same gutter the tab bar under it uses.
class _BandSurface extends StatelessWidget {
  const _BandSurface({required this.child, this.height});

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('communityFootballRecord'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        Layout.sheetGutter,
        Gap.md,
        Layout.sheetGutter,
        0,
      ),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: GoColors.surfaceCard,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: GoColors.borderCardOutlined),
        ),
        child: child,
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric, required this.style});

  final _Metric metric;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label: '${metric.label} ${metric.value}',
      child: ExcludeSemantics(
        child: Padding(
          key: metric.key,
          padding: const EdgeInsets.symmetric(
            horizontal: FootballRecordBand._cellPadding,
            vertical: Gap.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A figure may shrink a little before it overflows; a label never
              // does. Numbers survive being smaller and words do not.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${metric.value}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: GoColors.primaryDeep,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                metric.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: style,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline.vertical() : vertical = true;
  const _Hairline.horizontal() : vertical = false;

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: vertical ? 1 : double.infinity,
      height: vertical ? 34 : 1,
      child: const ColoredBox(color: GoColors.borderCardOutlined),
    );
  }
}

/// The band's shape before it arrives, so nothing jumps when it lands.
class _RecordSkeleton extends StatelessWidget {
  const _RecordSkeleton();

  @override
  Widget build(BuildContext context) {
    return _BandSurface(
      height: 74,
      child: SkeletonFade(
        child: Row(
          children: List.generate(
            4,
            (_) => const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Skeleton(width: 34, height: 18),
                  SizedBox(height: Gap.sm),
                  Skeleton(width: 48, height: 9),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The football failing alone: the record's place says so and offers a retry,
/// and everything else on the page stays exactly as it was.
class _RecordFailed extends StatelessWidget {
  const _RecordFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return _BandSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 20, color: scheme.error),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                l10n.latestResultsFailed,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              key: const Key('recordRetry'),
              onPressed: onRetry,
              child: Text(l10n.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the Top Players list.
///
/// Rank, picture, name, three counters, rating -- the row this list has always
/// been, with the rank added. **The first three places are lifted, not
/// recoloured**: they sit on a white card and their badge steps from the
/// primary green down to its container, all from the tokens the rest of the
/// product already uses. Places four onward are the plain row.
///
/// Every row is a registered player: the statistics are keyed by user, and a
/// Professional Guest has no user, so a guest cannot reach this list at all.
/// [onOpen] is null when the reader has nowhere to go from a player, which
/// leaves the row plain rather than tappable to nothing.
class TopPlayerRow extends StatelessWidget {
  const TopPlayerRow({
    super.key,
    required this.rank,
    required this.player,
    this.onOpen,
  });

  /// The place, one to eleven.
  final int rank;
  final PublicCommunityTopPlayer player;
  final VoidCallback? onOpen;

  bool get _lifted => rank <= 3;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.sheetGutter,
        vertical: 3,
      ),
      child: Material(
        color: _lifted ? GoColors.surfaceCard : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: _lifted
              ? const BorderSide(color: GoColors.borderCardOutlined)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.sm + 2,
            ),
            child: Row(
              children: [
                _RankBadge(rank: rank),
                const SizedBox(width: Gap.md),
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              _lifted ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      // Each counter is an item of its own, and the items wrap
                      // as whole units. On a narrow phone -- and in Arabic,
                      // whose labels are longer -- the three do not fit one
                      // line, and running them together as one string cut the
                      // last of them off with an ellipsis. A counter that
                      // moves to the next line is still readable; one that is
                      // clipped is not.
                      Wrap(
                        spacing: Gap.md,
                        children: [
                          for (final counter in [
                            '${l10n.statMatchesPlayed} ${player.matchesPlayed}',
                            '${l10n.statGoals} ${player.goals}',
                            '${l10n.statMvps} ${player.mvpCount}',
                          ])
                            Text(
                              counter,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
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
        ),
      ),
    );
  }
}

/// The place a player holds, drawn stepping down from the primary green for the
/// first three and quiet after that.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (rank) {
      1 => (GoColors.primary, GoColors.onPrimary),
      2 => (GoColors.primaryMid, GoColors.onPrimary),
      3 => (GoColors.primaryContainer, GoColors.onPrimaryContainer),
      _ => (GoColors.surfaceContainerHighest, GoColors.onSurfaceVariant),
    };

    return CircleAvatar(
      radius: 14,
      backgroundColor: background,
      child: Text(
        '$rank',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
      ),
    );
  }
}

/// The Top Players tab before it arrives.
class _PlayersSkeleton extends StatelessWidget {
  const _PlayersSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonFade(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.sheetGutter + Gap.md,
          vertical: Gap.sm,
        ),
        child: Column(
          children: List.generate(
            5,
            (_) => const Padding(
              padding: EdgeInsets.symmetric(vertical: Gap.sm),
              child: Row(
                children: [
                  Skeleton(width: 28, height: 28, radius: Radii.pill),
                  SizedBox(width: Gap.md),
                  Skeleton(width: 36, height: 36, radius: Radii.pill),
                  SizedBox(width: Gap.md),
                  Expanded(child: Skeleton.line(width: 0.6)),
                  SizedBox(width: Gap.md),
                  Skeleton(width: 52, height: 22, radius: Radii.pill),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
