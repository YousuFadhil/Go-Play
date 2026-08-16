import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../profile/player_identity.dart';
import 'statistics_models.dart';
import 'statistics_period.dart';
import 'statistics_period_selector.dart';

/// Everything the Community Statistics card draws, resolved before it is drawn.
///
/// **A summary, not the Dashboard.** Six figures and a name: the three totals,
/// and the three players who lead a measure. The five leaderboards are not here
/// and are not meant to be — a board is a ranking somebody reads, and this is a
/// picture somebody sends.
///
/// The card is handed this and nothing else. No repository, no community id, no
/// period to work out — the Dashboard already has all of it, and a template
/// that could fetch would be a second source for figures the reader is looking
/// at.
@immutable
class CommunityStatisticsCardData {
  const CommunityStatisticsCardData({
    required this.communityName,
    required this.period,
    required this.completedMatches,
    required this.totalPlayers,
    required this.totalGoals,
    this.topScorer,
    this.mostActivePlayer,
    this.mostMvp,
  });

  /// Reads the figures straight off the model the Dashboard is already showing,
  /// so the card and the screen cannot report different numbers.
  CommunityStatisticsCardData.of(
    CommunityDashboard dashboard, {
    required this.communityName,
    required this.period,
  })  : completedMatches = dashboard.completedMatches,
        totalPlayers = dashboard.totalPlayers,
        totalGoals = dashboard.totalGoals,
        topScorer = dashboard.topScorer,
        mostActivePlayer = dashboard.mostActivePlayer,
        mostMvp = dashboard.mostMvp;

  final String communityName;

  /// Which stretch every figure below describes. Comes from the selector the
  /// reader already used; the card never asks again.
  final StatisticsPeriod period;

  final int completedMatches;
  final int totalPlayers;
  final int totalGoals;

  /// Null where the measure has not happened yet — the same absence the
  /// Dashboard carries, and for the same reason: a leader at zero was picked
  /// out of a table of ties by nothing. A measure nobody leads is left off the
  /// card rather than filled in.
  final StatisticLeader? topScorer;
  final StatisticLeader? mostActivePlayer;
  final StatisticLeader? mostMvp;

  /// Whether anybody leads anything yet.
  bool get hasLeaders =>
      topScorer != null || mostActivePlayer != null || mostMvp != null;
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
                const _Wordmark(size: 44, spacing: 14),
                const SizedBox(height: 18),
                Container(width: 132, height: 6, color: _accent),
                const Spacer(flex: 2),
                _CommunityName(name: data.communityName),
                const SizedBox(height: 30),
                _PeriodBadge(
                  label: StatisticsPeriodSelector.label(
                    context.l10n,
                    data.period,
                  ),
                ),
                const Spacer(flex: 2),
                _Totals(data: data),
                const Spacer(flex: 2),
                // A community with nothing to show leaves the section out
                // rather than printing three empty rows: an absence stated
                // three times reads as a broken card.
                if (data.hasLeaders) _Leaders(data: data),
                if (data.hasLeaders) const Spacer(flex: 2),
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
      mainAxisSize: MainAxisSize.min,
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
        const SizedBox(height: 36),
        // Only the measures somebody actually leads. A row saying "Not yet" on
        // a picture sent to other people is an absence they cannot act on.
        if (data.topScorer != null)
          _LeaderRow(
            label: l10n.statTopScorer,
            leader: data.topScorer!,
            describeValue: l10n.goalsScoredLabel,
          ),
        if (data.mostActivePlayer != null)
          _LeaderRow(
            label: l10n.statMostActivePlayer,
            leader: data.mostActivePlayer!,
            describeValue: l10n.statMatchesPlayedValue,
          ),
        if (data.mostMvp != null)
          _LeaderRow(
            label: l10n.statMostMvp,
            leader: data.mostMvp!,
            describeValue: l10n.statMvpValue,
          ),
      ],
    );
  }
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
  final StatisticLeader leader;
  final String Function(int) describeValue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Row(
        children: [
          // The app's own avatar, at card scale. Its fallback is the app's —
          // initials, and a figure where there is not even a name.
          PlayerAvatar(
            avatarUrl: leader.avatarUrl,
            fullName: leader.fullName,
            radius: 54,
          ),
          const SizedBox(width: 28),
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
              ],
            ),
          ),
          const SizedBox(width: 20),
          Text(
            describeValue(leader.value),
            style: const TextStyle(
              color: CommunityStatisticsCard._accent,
              fontSize: 40,
              fontWeight: FontWeight.w800,
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
