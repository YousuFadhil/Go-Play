import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'statistics_models.dart';
import 'statistics_period.dart';
import 'statistics_period_selector.dart';

/// What the Community Leaderboards share card is a picture of.
///
/// **The boards are taken as given.** [boards] is the repository's output,
/// entry for entry and in its order — the card never sorts, never re-ranks and
/// never recomputes a place. Cycle B1 settled that order (value, then how
/// recently the measure was achieved, then name, then id) and settled that
/// competition rank comes from the value alone; a card that re-derived either
/// would be a second opinion about who is leading.
class CommunityLeaderboardsCardData {
  const CommunityLeaderboardsCardData({
    required this.communityName,
    required this.period,
    required this.boards,
  });

  /// Composes the card from what the tab is showing.
  ///
  /// [boards] arrives exactly as `StatisticsRepository.fetchLeaderboards`
  /// returned it. This constructor exists to name that fact, not to transform
  /// anything.
  factory CommunityLeaderboardsCardData.of(
    List<Leaderboard> boards, {
    required String communityName,
    required StatisticsPeriod period,
  }) =>
      CommunityLeaderboardsCardData(
        communityName: communityName,
        period: period,
        boards: boards,
      );

  final String communityName;

  /// The period the reader had selected. The card is a picture of that choice,
  /// not of a default.
  final StatisticsPeriod period;

  /// Whichever boards the repository built. A measure nobody has yet achieved
  /// produces no board at all, which is why [entriesFor] answers with an empty
  /// list rather than this being indexed directly.
  final List<Leaderboard> boards;

  /// The rows for [kind], or empty where the repository built no board for it.
  ///
  /// Empty is a state the card draws rather than a section it drops: the
  /// contract is five categories, and a reader comparing two cards should find
  /// the same five headings on both.
  List<LeaderboardEntry> entriesFor(LeaderboardKind kind) {
    for (final board in boards) {
      if (board.kind == kind) return board.entries;
    }
    return const [];
  }
}

/// The Community Leaderboards, as one picture.
///
/// A different card from the Community Statistics one, deliberately: that card
/// answers "how is this community doing" with totals and three leaders, and
/// this one answers "who is ahead, in each of the five things we rank". They
/// share a palette because they are the same product's cards; they share no
/// content, and neither is a variant of the other.
class CommunityLeaderboardsCard extends StatelessWidget {
  const CommunityLeaderboardsCard({super.key, required this.data});

  final CommunityLeaderboardsCardData data;

  /// The card's own palette, stated here rather than taken from the app theme:
  /// a picture that leaves the phone must not change because the reader has
  /// dark mode on. The same greens as the other two cards.
  static const _pitch = Color(0xFF07341C);
  static const _pitchDeep = Color(0xFF04180E);
  static const _accent = Color(0xFF3DDC84);
  static const _ink = Color(0xFFFFFFFF);
  static const _inkMuted = Color(0xB3FFFFFF);

  static const _margin = 76.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_pitch, _pitchDeep],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_margin, 92, _margin, 72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 132, height: 6, color: _accent)),
            const SizedBox(height: 44),
            _Heading(
              communityName: data.communityName,
              title: l10n.leaderboardsTab,
            ),
            const SizedBox(height: 26),
            Center(
              child: _PeriodBadge(
                label: l10n.shareCardPeriodBadge(
                  StatisticsPeriodSelector.shareLabel(l10n, data.period),
                ),
              ),
            ),
            const SizedBox(height: 40),
            // Five sections sharing the remaining height equally, so the card
            // scans as one table rather than five panels of whatever height
            // their contents happened to want.
            for (final kind in LeaderboardKind.values)
              Expanded(
                child: _Section(
                  title: _kindLabel(l10n, kind),
                  entries: data.entriesFor(kind),
                ),
              ),
            const SizedBox(height: 20),
            // The only branding, and the only place it appears.
            const Center(child: _Wordmark()),
          ],
        ),
      ),
    );
  }

  /// The labels the Leaderboards tab already uses. The card names the five
  /// measures the same way the screen does.
  static String _kindLabel(AppLocalizations l10n, LeaderboardKind kind) =>
      switch (kind) {
        LeaderboardKind.highestRated => l10n.leaderboardHighestRated,
        LeaderboardKind.topScorer => l10n.leaderboardTopScorer,
        LeaderboardKind.mostMvp => l10n.leaderboardMostMvp,
        LeaderboardKind.mostActive => l10n.leaderboardMostActive,
        LeaderboardKind.mostWins => l10n.leaderboardMostWins,
      };
}

/// Whose leaderboards these are.
class _Heading extends StatelessWidget {
  const _Heading({required this.communityName, required this.title});

  final String communityName;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _inkMutedOf,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 14),
        // Two lines before it ellipsizes: community names in Arabic are often
        // long, and a name cut at one line is the commonest way a card like
        // this stops being about anybody.
        Text(
          communityName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: CommunityLeaderboardsCard._ink,
            fontSize: 66,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }

  static const _inkMutedOf = CommunityLeaderboardsCard._inkMuted;
}

/// One measure, and up to three players on it.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.entries});

  final String title;

  /// Exactly as supplied. Not sorted here, and not truncated here either — the
  /// repository already decided the board is three deep.
  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Container(width: 8, height: 30, color: CommunityLeaderboardsCard._accent),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CommunityLeaderboardsCard._accent,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (entries.isEmpty)
          // The category stays. A dash says the measure has not happened to
          // anybody yet, which is a fact about the community rather than a gap
          // in the card — and it keeps the five headings comparable between two
          // cards from different weeks.
          const Padding(
            padding: EdgeInsets.only(left: 24),
            child: Text(
              '—',
              style: TextStyle(
                color: CommunityLeaderboardsCard._inkMuted,
                fontSize: 34,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          for (final entry in entries) _Row(entry: entry),
      ],
    );
  }
}

/// One player's place on one board.
class _Row extends StatelessWidget {
  const _Row({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The rank the repository supplied. Equal values share a rank, so two
          // rows here can legitimately both read 1 — that is competition
          // ranking, not a mistake, and the card prints what it was given.
          SizedBox(
            width: 62,
            child: Text(
              '${entry.rank}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CommunityLeaderboardsCard._inkMuted,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CommunityLeaderboardsCard._ink,
                fontSize: 38,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Text(
            _value(entry.value),
            style: const TextStyle(
              color: CommunityLeaderboardsCard._ink,
              fontSize: 38,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /// A rating keeps its decimal; a count is a whole number. The same rule the
  /// board on screen applies, so a figure does not change shape when it is
  /// shared.
  static String _value(num value) =>
      value is int ? '$value' : value.toStringAsFixed(1);
}

/// Which period the boards describe.
class _PeriodBadge extends StatelessWidget {
  const _PeriodBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 14),
      decoration: BoxDecoration(
        color: CommunityLeaderboardsCard._accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: CommunityLeaderboardsCard._accent.withValues(alpha: 0.55),
          width: 3,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: CommunityLeaderboardsCard._ink,
          fontSize: 30,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The product's name, once, at the foot.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.appName.toUpperCase(),
      // The mark reads left to right in both languages: it is a name, and the
      // product is called Go Play in Arabic too.
      textDirection: TextDirection.ltr,
      style: const TextStyle(
        color: CommunityLeaderboardsCard._inkMuted,
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: 10,
      ),
    );
  }
}
