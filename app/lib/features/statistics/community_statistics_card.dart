import 'package:flutter/material.dart';
import '../../core/club_place.dart' show CommunityCrest;
import '../../core/l10n.dart';
import '../sharing/share_card_palette.dart';
import '../sharing/share_poster.dart';
import '../profile/player_identity.dart';
import 'statistics_models.dart';
import 'statistics_period.dart';
import 'statistics_period_selector.dart';

/// One measure, and the single player at the top of it.
///
/// **First place, and no other place.** The card carries five of these because
/// the Statistics tab ranks five measures; it carries one player each because a
/// picture sent to a group chat is glanced at, and fifteen names is a table
/// somebody has to sit down with. The runner-ups stay on the screen the card was
/// taken from, which is where reading happens.
@immutable
class CommunityStatisticsLeader {
  const CommunityStatisticsLeader({
    required this.kind,
    required this.fullName,
    required this.value,
    this.avatarUrl,
  });

  /// Which board this player is top of.
  final LeaderboardKind kind;

  /// Null for a record that outlived the profile it describes — a soft-deleted
  /// account whose figures stayed. The measure still happened, and the card
  /// says so in the words every other surface uses.
  final String? fullName;

  final String? avatarUrl;

  /// `double` for a rating, `int` for a count, exactly as the board carries it.
  final num value;
}

/// Everything the Community Statistics card draws, resolved before it is drawn.
///
/// **One card where there were two.** The Dashboard's card carried three totals
/// and three leaders; the Leaderboards' card carried five boards three deep.
/// Between them a reader could send two pictures of the same community for two
/// different stretches of time. This is the one card: the three totals, and the
/// one player at the top of each of the five measures.
///
/// The card is handed this and nothing else. No repository, no community id, no
/// period to work out — the tab already has all of it, and a template that could
/// fetch would be a second source for figures the reader is looking at.
@immutable
class CommunityStatisticsCardData {
  const CommunityStatisticsCardData({
    required this.communityName,
    required this.period,
    required this.completedMatches,
    required this.totalPlayers,
    required this.totalGoals,
    this.leaders = const [],
  });

  /// Reads straight off the snapshot the Statistics tab is already showing, so
  /// the card and the screen cannot report different figures.
  ///
  /// **The leaders come from the boards, not from the dashboard's own three.**
  /// They are what is on screen, and the two populations are not the same: a
  /// statistics record survives a player leaving, so the dashboard's top scorer
  /// can be somebody who has left while a board ranks current members only. The
  /// card has to show the community the reader is looking at.
  ///
  /// A measure nobody has achieved yet has no board and therefore no row here.
  /// An absence is left off rather than filled in — a leader at zero was picked
  /// out of a table of ties by nothing.
  factory CommunityStatisticsCardData.of(
    CommunityStatistics statistics, {
    required String communityName,
    required StatisticsPeriod period,
  }) {
    final dashboard = statistics.dashboard;
    return CommunityStatisticsCardData(
      communityName: communityName,
      period: period,
      completedMatches: dashboard.completedMatches,
      totalPlayers: dashboard.totalPlayers,
      totalGoals: dashboard.totalGoals,
      leaders: [
        // `LeaderboardKind.values` order, so the card names the measures in the
        // order the tab lists them.
        for (final kind in LeaderboardKind.values)
          if (statistics.leaderOf(kind) case final entry?)
            CommunityStatisticsLeader(
              kind: kind,
              fullName: entry.fullName,
              avatarUrl: entry.avatarUrl,
              value: entry.value,
            ),
      ],
    );
  }

  final String communityName;

  /// Which stretch every figure below describes. Comes from the selector the
  /// reader already used; the card never asks again.
  final StatisticsPeriod period;

  final int completedMatches;
  final int totalPlayers;
  final int totalGoals;

  /// At most five, one per measure, first place only.
  final List<CommunityStatisticsLeader> leaders;

  /// Whether anybody leads anything yet.
  bool get hasLeaders => leaders.isNotEmpty;
}

/// The Community Statistics share card: a community's period, as a picture.
///
/// **Composed, not captured.** The Dashboard is a scrolling screen with three
/// cards and three tiles on it; this is one image for a group chat, so it is
/// built as a single hierarchy — the community's name, the three totals given
/// equal weight, and the players who led it.
///
/// **Presentation only.** It takes [CommunityStatisticsCardData] and draws it.
/// It reads no repository, resolves no period and calculates nothing.
///
/// **Laid out in the engine's design units, never the device's.** Every number
/// below is a coordinate on the 1080×1920 surface `ShareCardSurface` fixes.
///
/// **Right-to-left is inherited, not mirrored by hand**, so the Arabic card is
/// the same hierarchy read the other way.
class CommunityStatisticsCard extends StatelessWidget {
  const CommunityStatisticsCard({super.key, required this.data});

  final CommunityStatisticsCardData data;

  static const _margin = 60.0;

  @override
  Widget build(BuildContext context) {
    return SharePosterBackground(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_margin, 56, _margin, 64),
        child: Column(
          children: [
            // **The card opens on the community, not on the product.** One
            // white card carries the community, its period, its totals and its
            // leaders, like the player's profile card; the mark closes the
            // picture. The card is sized by what the community has and centred
            // in what is left, and the fullest one is scaled down as a piece
            // rather than overflowing the fixed surface.
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 1080 - 2 * _margin,
                    child: _PosterCard(data: data),
                  ),
                ),
              ),
            ),
            const SharePosterWordmark(),
          ],
        ),
      ),
    );
  }
}

/// The card: a white sheet with the community's crest on its top edge.
class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.data});

  final CommunityStatisticsCardData data;

  /// The crest's diameter. Half of it stands above the card.
  static const _crest = 220.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _crest / 2),
          child: Container(
            padding: const EdgeInsets.fromLTRB(44, _crest / 2 + 28, 44, 48),
            decoration: BoxDecoration(
              color: ShareCardPalette.paper,
              borderRadius: BorderRadius.circular(68),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x47000000),
                  blurRadius: 80,
                  offset: Offset(0, 36),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CommunityName(name: data.communityName),
                const SizedBox(height: 22),
                Center(
                  child: _PeriodBadge(
                    label: StatisticsPeriodSelector.label(
                      context.l10n,
                      data.period,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                _Totals(data: data),
                // A community with nothing to show leaves the section out
                // rather than printing three empty rows: an absence stated
                // three times reads as a broken card.
                if (data.hasLeaders) ...[
                  const SizedBox(height: 36),
                  _Leaders(data: data),
                ],
              ],
            ),
          ),
        ),
        CommunityCrest(name: data.communityName, size: _crest),
      ],
    );
  }
}

/// Whose community this is.
class _CommunityName extends StatelessWidget {
  const _CommunityName({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    // Scaled down rather than clipped: a long community name is still that
    // community's name.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        name,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: ShareCardPalette.paperInk,
          fontSize: 72,
          fontWeight: FontWeight.w800,
          height: 1.15,
          letterSpacing: -1.4,
        ),
      ),
    );
  }
}

/// The three community totals, across.
///
/// Equal blocks: none of the three is the headline, and sizing one larger would
/// be a claim about which of a community's numbers matters that the product
/// does not make.
class _Totals extends StatelessWidget {
  const _Totals({required this.data});

  final CommunityStatisticsCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      decoration: BoxDecoration(
        color: ShareCardPalette.paperTint,
        borderRadius: BorderRadius.circular(44),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Total(
              value: data.completedMatches,
              label: l10n.shareCardStatMatches,
            ),
          ),
          Expanded(
            child: _Total(
              value: data.totalPlayers,
              label: l10n.shareCardStatPlayers,
            ),
          ),
          Expanded(
            child: _Total(
              value: data.totalGoals,
              label: l10n.shareCardStatGoals,
            ),
          ),
        ],
      ),
    );
  }
}

/// One total and what it counts.
class _Total extends StatelessWidget {
  const _Total({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: ShareCardPalette.paperInk,
            fontSize: 96,
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: -2,
          ),
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(
              color: ShareCardPalette.paperMuted,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Who led the community, and on what.
class _Leaders extends StatelessWidget {
  const _Leaders({required this.data});

  final CommunityStatisticsCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.statLeadersTitle.toUpperCase(),
          style: const TextStyle(
            color: ShareCardPalette.resultWin,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 10),
        // Only the measures somebody actually leads. A row saying "Not yet" on
        // a picture sent to other people is an absence they cannot act on.
        for (final leader in data.leaders)
          _LeaderRow(
            label: labelOf(l10n, leader.kind),
            leader: leader,
            describeValue: describeOf(l10n, leader.kind),
          ),
      ],
    );
  }

  /// What to call a measure. The Statistics tab's own board titles, so the card
  /// and the screen name the five things the same way.
  static String labelOf(AppLocalizations l10n, LeaderboardKind kind) =>
      switch (kind) {
        LeaderboardKind.highestRated => l10n.leaderboardHighestRated,
        LeaderboardKind.topScorer => l10n.leaderboardTopScorer,
        LeaderboardKind.mostMvp => l10n.leaderboardMostMvp,
        LeaderboardKind.mostActive => l10n.leaderboardMostActive,
        LeaderboardKind.mostWins => l10n.leaderboardMostWins,
      };

  /// The figure in the measure's own words, so a row never shows a bare number
  /// whose unit the reader has to infer from the label above it.
  ///
  /// A rating keeps its one decimal (`OP-1`) and is written on its own: it is
  /// the player's rating, not a count of anything, and "5.0 rating" would be
  /// the only row on the card claiming a unit that does not exist.
  static String Function(num) describeOf(
    AppLocalizations l10n,
    LeaderboardKind kind,
  ) =>
      switch (kind) {
        LeaderboardKind.highestRated => (value) =>
            (value as double).toStringAsFixed(1),
        LeaderboardKind.topScorer => (value) =>
            l10n.goalsScoredLabel(value.toInt()),
        LeaderboardKind.mostMvp => (value) => l10n.statMvpValue(value.toInt()),
        LeaderboardKind.mostActive => (value) =>
            l10n.statMatchesPlayedValue(value.toInt()),
        LeaderboardKind.mostWins => (value) =>
            l10n.leaderboardWinsValue(value.toInt()),
      };
}

/// One leader: the measure, their face, their name, and the figure in the
/// measure's own words.
class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.label,
    required this.leader,
    required this.describeValue,
  });

  final String label;
  final CommunityStatisticsLeader leader;

  /// Takes a `num` because one of the five measures is a rating and the other
  /// four are counts, and the row draws whichever it is given.
  final String Function(num) describeValue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // The app's own avatar, at card scale. Its fallback is the app's —
          // initials, and a figure where there is not even a name.
          Theme(
            // **Pinned, so the same community produces the same picture.** A
            // leader without a photograph falls back to a `CircleAvatar`,
            // which takes its colours from the ambient scheme — so without
            // this a reader in dark mode shared a pale lilac disc on a green
            // football card while a reader in light mode shared a green one.
            // It changes nothing in the app: this Theme exists only inside the
            // card being composed.
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1B7A43),
                brightness: Brightness.light,
              ),
            ),
            child: PlayerAvatar(
              avatarUrl: leader.avatarUrl,
              fullName: leader.fullName,
              radius: 48,
            ),
          ),
          const SizedBox(width: 24),
          // The figure goes *under* the name rather than opposite it. Across
          // the row it sat an arm's length of empty green away from the player
          // it belongs to; beside the name it stole the room the name needed
          // and long names were cut off. Stacked, it is unmistakably this
          // player's figure and the name keeps the full width of the card.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ShareCardPalette.paperMuted,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  // A record can outlive the profile it describes: a
                  // soft-deleted account keeps its figures and loses its name.
                  // The measure still happened, and the card says so with the
                  // same words every other surface uses.
                  leader.fullName ?? l10n.statFormerPlayer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ShareCardPalette.paperInk,
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  describeValue(leader.value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ShareCardPalette.resultWin,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Which period every figure on the card describes.
class _PeriodBadge extends StatelessWidget {
  const _PeriodBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      decoration: BoxDecoration(
        color: ShareCardPalette.paperTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: ShareCardPalette.pitchDeep,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
