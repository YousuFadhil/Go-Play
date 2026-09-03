import 'package:flutter/material.dart';

import '../../core/l10n.dart';
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

  /// The card's own palette, stated here rather than taken from the app theme:
  /// a picture that leaves the phone must not change because the reader has
  /// dark mode on.
  ///
  /// Deliberately the same greens as the Player Statistics card — the two are
  /// the same product's cards and should be recognisable as a pair. They are
  /// restated rather than shared because a template owns its own composition;
  /// when a third card arrives and all three agree, a brand palette will have
  /// earned its own home.
  static const _pitch = Color(0xFF07341C);
  static const _pitchDeep = Color(0xFF04180E);
  static const _accent = Color(0xFF3DDC84);
  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0xB3FFFFFF);

  static const _margin = 88.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_pitch, _pitchDeep],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _PitchMarkings()),
          Padding(
            padding: const EdgeInsets.fromLTRB(_margin, 96, _margin, 84),
            child: Column(
              children: [
                // **The card opens on the community, not on the product.** It
                // used to carry a large GO PLAY wordmark and an accent bar above
                // the name, which said whose software this is before it said
                // whose football it is. The small mark at the foot is the
                // signature, and one signature is enough.
                //
                // With leaders, fixed gaps down to the totals and the leaders
                // take the rest: before this, four elastic gaps shared the
                // slack and left a band of empty green between every pair.
                //
                // With none, the same fixed block is centred instead — slack
                // above it and below — because pinning it to the top would
                // leave the whole lower half of the frame empty.
                if (!data.hasLeaders) const Spacer(),
                const SizedBox(height: 40),
                _CommunityName(name: data.communityName),
                const SizedBox(height: 28),
                _PeriodBadge(
                  label: StatisticsPeriodSelector.label(
                    context.l10n,
                    data.period,
                  ),
                ),
                const SizedBox(height: 56),
                _Totals(data: data),
                // A community with nothing to show leaves the section out
                // rather than printing three empty rows: an absence stated
                // three times reads as a broken card.
                //
                // Where there are leaders they take the rest of the card and
                // space themselves down it; where there are none the slack
                // goes above and below the totals instead, so the figures sit
                // in the middle of the frame rather than clinging to the top.
                if (data.hasLeaders) ...[
                  const SizedBox(height: 40),
                  Expanded(child: _Leaders(data: data)),
                ] else
                  const Spacer(),
                const SizedBox(height: 28),
                const _Wordmark(size: 30, spacing: 10, muted: true),
              ],
            ),
          ),
        ],
      ),
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
          color: CommunityStatisticsCard._ink,
          fontSize: 88,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: -1.5,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Rule(),
        const SizedBox(height: 44),
        Row(
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
        const SizedBox(height: 44),
        const _Rule(),
      ],
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
            color: CommunityStatisticsCard._ink,
            fontSize: 112,
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: -3,
          ),
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(
              color: CommunityStatisticsCard._inkMuted,
              fontSize: 30,
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
      children: [
        Text(
          l10n.statLeadersTitle.toUpperCase(),
          style: const TextStyle(
            color: CommunityStatisticsCard._accent,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 16),
        // The rows share whatever the card has left, so the section fills its
        // part of the frame instead of sitting in a corner of it.
        //
        // Only the measures somebody actually leads. A row saying "Not yet" on
        // a picture sent to other people is an absence they cannot act on.
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final leader in data.leaders)
                _LeaderRow(
                  label: labelOf(l10n, leader.kind),
                  leader: leader,
                  describeValue: describeOf(l10n, leader.kind),
                ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
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
              radius: 54,
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
                    color: CommunityStatisticsCard._inkMuted,
                    fontSize: 26,
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
                    color: CommunityStatisticsCard._ink,
                    fontSize: 46,
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
                    color: CommunityStatisticsCard._accent,
                    fontSize: 40,
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
      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
      decoration: BoxDecoration(
        color: CommunityStatisticsCard._accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: CommunityStatisticsCard._accent.withValues(alpha: 0.55),
          width: 3,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: CommunityStatisticsCard._accent,
          fontSize: 40,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

/// A hairline separating the totals from everything else.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      color: CommunityStatisticsCard._inkMuted.withValues(alpha: 0.18),
    );
  }
}

/// The Go Play name, as the card's mark.
///
/// Set in letterspaced capitals rather than drawn: the app ships no logo asset.
class _Wordmark extends StatelessWidget {
  const _Wordmark({
    required this.size,
    required this.spacing,
    this.muted = false,
  });

  final double size;
  final double spacing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.appName.toUpperCase(),
      // The mark reads left to right in both languages: it is a name, and the
      // product is called Go Play in Arabic too.
      textDirection: TextDirection.ltr,
      style: TextStyle(
        color: muted
            ? CommunityStatisticsCard._inkMuted
            : CommunityStatisticsCard._ink,
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: spacing,
      ),
    );
  }
}

/// The markings of a pitch, faintly. Drawn rather than photographed: a
/// photograph behind this much text would compete with all of it.
class _PitchMarkings extends StatelessWidget {
  const _PitchMarkings();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PitchPainter());
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = CommunityStatisticsCard._accent.withValues(alpha: 0.10);

    // Behind the community's name, where the player's face sits on the other
    // card — the same geometry, anchored to whatever the card is about.
    final centre = Offset(size.width / 2, size.height * 0.28);
    canvas.drawCircle(centre, size.width * 0.44, paint);
    canvas.drawCircle(centre, size.width * 0.62, paint);
    canvas.drawLine(Offset(0, centre.dy), Offset(size.width, centre.dy), paint);
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) => false;
}
