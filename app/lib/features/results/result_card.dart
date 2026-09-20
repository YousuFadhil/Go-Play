import 'package:flutter/material.dart';

import '../../core/club_place.dart';
import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import '../profile/player_identity.dart';
import 'score_pair.dart';

/// One played match, drawn the one way this product draws a played match.
///
/// **Why this exists.** Discover showed a visitor and a member the same football
/// in two visibly different cards: one built on the Club card treatment with a
/// crest-less header, a community name above the title and the best player as a
/// face and a pill; the other on a bare Material `Card`, with the community
/// folded into the date line and the best player as a star and a line of text.
/// A reader who signed in watched the same result change shape, which reads as
/// two products rather than two audiences.
///
/// **What is shared is the picture, not the contract.** The authenticated
/// `CompletedMatch` and the public `PublicResult` stay exactly as separate as
/// they were — different reads, different grants, different fields. Each adapts
/// itself into [ResultCardData] at its own call site, and this file has never
/// heard of either. That is the whole of the sharing: one composition, two
/// sources, no merged read model.
@immutable
class ResultCardData {
  const ResultCardData({
    required this.title,
    required this.startAt,
    this.endAt,
    this.communityName,
    this.communityLogoUrl,
    this.location,
    this.teamAScore,
    this.teamBScore,
    this.mvpName,
    this.mvpAvatarUrl,
    this.mvpIsProfessionalGuest = false,
  });

  /// What the match is called. Never empty: a source with no title of its own
  /// passes the community's name, which is what the reader would otherwise be
  /// left without.
  final String title;

  final DateTime startAt;

  /// The finish, where the source knows it. The authenticated feed does and
  /// draws a range; the public contract publishes only the start, and gets the
  /// day on its own rather than a range invented from one end of it.
  final DateTime? endAt;

  /// Whose football this is, or null on a page that has already said so.
  final String? communityName;

  /// Where it was played, where the read carries one.
  ///
  /// **Both contracts already have this and the card used to drop it.** A
  /// result without a ground is the one detail a reader scanning a feed of
  /// them actually uses to place the match, and `public_recent_results`
  /// publishes it exactly as the member's read does.
  final String? location;

  /// The community's picture where the read model carries one. The public
  /// results contract does; the authenticated feed does not, and falls back to
  /// the initials crest [CommunityCrest] draws for every community without a
  /// logo — the same fallback the rest of the product uses.
  final String? communityLogoUrl;

  /// **Both null is a real state, and not an error.** A match can be over and
  /// not yet written up: `0033` made the result optional and nothing obliges an
  /// organizer to record one the moment the whistle goes. That gets words, not
  /// a pair of zeroes — 0–0 is a result somebody recorded and this is not.
  final int? teamAScore;
  final int? teamBScore;

  /// Best on the pitch, where the result named one. A name, never an id.
  final String? mvpName;

  /// Their picture, where the reader is allowed one. The public contract
  /// publishes `mvp_avatar_path` and this is it resolved; null falls back to
  /// the initials the avatar draws for anybody without a photograph.
  final String? mvpAvatarUrl;

  final bool mvpIsProfessionalGuest;

  bool get hasResult => teamAScore != null && teamBScore != null;

  bool get hasMvp => mvpName != null && mvpName!.trim().isNotEmpty;
}

/// The card itself: the Club card treatment, and the same one everywhere.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.data,
    required this.onOpen,
    this.showCommunityName = true,
  });

  final ResultCardData data;
  final VoidCallback onOpen;

  /// False on a community's own page, where every match on it belongs to the
  /// community already named at the top. The crest goes with the name: a mark
  /// repeating the identity of the page it is on is decoration.
  final bool showCommunityName;

  bool get _showsCommunity =>
      showCommunityName &&
      data.communityName != null &&
      data.communityName!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, 0, kPageMargin, Gap.md),
      child: Material(
        color: GoColors.surfaceCard,
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // **Measured, because the score cannot be allowed to push.**
                // The scoreline carries two team names under two figures and
                // is wider in Arabic than in English; on a 320px phone, with a
                // crest beside it, its natural width was one pixel more than
                // the row had. It is given at most a share of the line and
                // scales down inside it rather than overflowing, and the
                // title keeps the rest.
                LayoutBuilder(builder: (context, constraints) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_showsCommunity) ...[
                        CommunityCrest(
                          name: data.communityName!,
                          logoUrl: data.communityLogoUrl,
                          size: 32,
                        ),
                        const SizedBox(width: Gap.sm),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showsCommunity)
                              Text(
                                data.communityName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: GoColors.primaryDeep,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              data.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            // When, and where, as one string and one
                            // ellipsis.
                            //
                            // **Two flexible halves was the wrong shape.**
                            // They split the line evenly and truncated *both*
                            // into nothing on a 320px Arabic phone --
                            // `الجمع... · Al Se...` said neither when nor
                            // where. As one string the date is drawn whole,
                            // because it is short and bounded, and the ground
                            // is what gives way: the approved priority, in
                            // the order the reader needs it.
                            Text(
                              [
                                data.endAt == null
                                    ? formatDayShort(context, data.startAt)
                                    : formatDayAndTimeRange(
                                        context, data.startAt, data.endAt!),
                                if (data.location != null &&
                                    data.location!.trim().isNotEmpty)
                                  data.location!,
                              ].join('  \u00b7  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      ConstrainedBox(
                        // **The title outranks the scoreline.** At 0.46 the
                        // score took almost half a 320px card and the match
                        // was left as `Friday foo...`; the pair scales down
                        // inside whatever it is given, so the identity keeps
                        // the room and the score stays legible.
                        constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.38),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: _Score(data: data),
                        ),
                      ),
                    ],
                  );
                }),
                if (data.hasMvp) ...[
                  const SizedBox(height: Gap.md),
                  _MvpLine(data: data),
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
class _Score extends StatelessWidget {
  const _Score({required this.data});

  final ResultCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (!data.hasResult) {
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

    // Each number under its own team's name. "2 - 3" alone does not say which
    // side scored which, and on an Arabic page it reads as though it might be
    // the other way round.
    return ScorePair(
      teamAScore: data.teamAScore!,
      teamBScore: data.teamBScore!,
    );
  }
}

/// Best on the pitch, where one was named.
///
/// Deliberately not tappable: a card in a list opens the match, and a second
/// target inside it would compete with that. The profile is one tap further in,
/// on the match screen, where a name is a row of its own.
class _MvpLine extends StatelessWidget {
  const _MvpLine({required this.data});

  final ResultCardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Row(
      children: [
        PlayerAvatar(
          avatarUrl: data.mvpAvatarUrl,
          fullName: data.mvpName!,
          isProfessionalGuest: data.mvpIsProfessionalGuest,
          radius: 12,
        ),
        const SizedBox(width: Gap.sm),
        Flexible(
          child: Text(
            data.mvpName!,
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

/// The newest three, and the rest of what is already loaded behind one control.
///
/// **Three, not one.** "What has just been played" is a section, and a section
/// showing a single card under a heading reads as though the rest failed to
/// arrive. Three is the approved answer, and "View all results" opens the rest
/// of the list that is *already in memory* — the same rows the overview fetched.
/// It is local state and nothing else: no page, no second read, no pagination.
class ResultsList<T> extends StatefulWidget {
  const ResultsList({
    super.key,
    required this.results,
    required this.identityOf,
    required this.itemBuilder,
    required this.toggleKey,
    this.initiallyVisible = 3,
  });

  /// Newest first, exactly as the repository returned them. Never re-ordered
  /// here.
  final List<T> results;

  /// What makes one of these the same result across a refresh.
  final String Function(T) identityOf;

  final Widget Function(BuildContext, T) itemBuilder;

  final Key toggleKey;

  final int initiallyVisible;

  @override
  State<ResultsList<T>> createState() => _ResultsListState<T>();
}

class _ResultsListState<T> extends State<ResultsList<T>> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ResultsList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A refresh that replaced the feed did not expand it: showing "all" of a
    // different list is showing something nobody asked for.
    final before = oldWidget.results.map(oldWidget.identityOf).toList();
    final now = widget.results.map(widget.identityOf).toList();
    if (_expanded && !_sameFeed(before, now)) _expanded = false;
  }

  static bool _sameFeed(List<String> before, List<String> now) {
    if (before.length != now.length) return false;
    for (var i = 0; i < now.length; i++) {
      if (now[i] != before[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = widget.results;
    final visible =
        _expanded ? results : results.take(widget.initiallyVisible).toList();
    // A disclosure that reveals nothing is noise.
    final hasMore = results.length > widget.initiallyVisible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final result in visible) widget.itemBuilder(context, result),
        if (hasMore)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(kPageMargin, 0, kPageMargin, Gap.sm),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: widget.toggleKey,
                // Local state only: no read, no reload, no repository. The
                // results are the ones already handed to this widget.
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: IconSize.action,
                ),
                label: Text(
                  _expanded ? l10n.showFewerResults : l10n.viewAllResults,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
