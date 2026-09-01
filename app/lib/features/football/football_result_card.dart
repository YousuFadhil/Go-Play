import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import '../profile/player_identity.dart';
import 'football_models.dart';

/// A completed match, as a line in a list.
///
/// The counterpart of `PublicMatchCard`: that card is about a match that is
/// coming and therefore leads with places left; this one is about a match that
/// has been played and leads with how it finished. The two sit in the same
/// Discover sheet, so the frame is deliberately the same — the Club card, the
/// same margins, the same radius — and only the contents differ.
///
/// It shows what the read model already knows and computes nothing. In
/// particular it does **not** total the scorers: attributed goals and the
/// recorded score are two different facts, and a card that added the first up
/// and presented it as the second would be inventing one.
class FootballResultCard extends StatelessWidget {
  const FootballResultCard({
    super.key,
    required this.match,
    required this.onOpen,
    this.showCommunityName = true,
  });

  final CompletedMatch match;
  final VoidCallback onOpen;

  /// False on a community's own page, where every match belongs to the
  /// community already named at the top of the screen.
  final bool showCommunityName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, 0, kPageMargin, Gap.md),
      child: Material(
        color: GoColors.surfaceCard,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(Radii.card),
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showCommunityName)
                            Text(
                              match.communityName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: GoColors.primaryDeep,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          Text(
                            match.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatDayAndTimeRange(
                                context, match.startAt, match.endAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    _Score(match: match),
                  ],
                ),
                if (match.mvp != null) ...[
                  const SizedBox(height: Gap.md),
                  _MvpLine(mvp: match.mvp!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The score, or the honest absence of one.
///
/// A match can be over and not yet written up — `0033` made the MVP optional and
/// nothing obliges an organizer to record a score the moment the whistle goes.
/// That state gets words rather than a pair of zeroes, because 0–0 is a result
/// somebody recorded and this is not.
class _Score extends StatelessWidget {
  const _Score({required this.match});

  final CompletedMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (!match.hasResult) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.xs,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(
          l10n.resultPendingLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.xs,
      ),
      decoration: BoxDecoration(
        color: GoColors.statusOpenBg,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Text(
        // Left to right whatever the reader's language: a score is a pair of
        // numbers read in the order they were scored, not a phrase.
        '${match.teamAScore} - ${match.teamBScore}',
        textDirection: TextDirection.ltr,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: GoColors.primaryDeep,
        ),
      ),
    );
  }
}

/// Best on the pitch, where one was named.
///
/// Drawn with the same face-and-name treatment every participant gets, and
/// deliberately not tappable here: a card in a list opens the match, and a
/// second target inside it would compete with that. The profile is one tap
/// further in, on the match screen, where a name is a row of its own.
class _MvpLine extends StatelessWidget {
  const _MvpLine({required this.mvp});

  final FootballParticipant mvp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Row(
      children: [
        PlayerAvatar(
          avatarUrl: mvp.avatarUrl,
          fullName: mvp.displayName,
          isProfessionalGuest: mvp.type == ParticipantType.professionalGuest,
          radius: 12,
        ),
        const SizedBox(width: Gap.sm),
        Flexible(
          child: Text(
            mvp.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: Gap.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 1),
          decoration: BoxDecoration(
            color: GoColors.statusOpenBg,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Text(
            l10n.mvpLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: GoColors.primaryDeep,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
