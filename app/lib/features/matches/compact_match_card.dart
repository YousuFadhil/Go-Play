import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/football_components.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import 'match_card.dart';
import 'match_details_screen.dart';
import 'match_models.dart';

/// A match, drawn for a column rather than for a line.
///
/// Not [MatchCard] made narrower. That card is a *row* — a date tile on one
/// side, the fixture in the middle, a status chip on the other — and a row is
/// the one arrangement that cannot survive halving: the three parts stop
/// fitting beside each other long before the card stops being wide enough to
/// read. This is the same information stacked, which is why it is a separate
/// widget and not a flag on the old one.
///
/// The information is deliberately the same information. A grid is a change of
/// arrangement, not an opportunity to say more about a match than the list said
/// — the fixture, when it is, where it is, and whether anything has happened to
/// it. Capacity is the one line the row card carried that is not here: it is the
/// least useful of the four when scanning, and a compact card has to spend its
/// height on the three that place a match in a reader's week.
class CompactMatchCard extends StatelessWidget {
  const CompactMatchCard({
    super.key,
    required this.match,
    this.showCommunityName = false,
    this.onChanged,
  });

  final Match match;

  /// Home lists matches from several communities and still has to say which.
  final bool showCommunityName;

  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final status = match.effectiveStatus;
    final completed = status == MatchStatus.completed;

    return CompactMatchShell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchDetailsScreen(matchId: match.id),
          ),
        );
        onChanged?.call();
      },
      day: match.startAt,
      completed: completed,
      // Open is the ordinary state and says nothing worth a chip; the other two
      // are the reason a reader looks twice, which is the rule the row card
      // already used.
      badge: status == MatchStatus.open
          ? null
          : GoStatusChip(
              label: matchStatusLabel(context, status),
              tone: status.chipTone,
            ),
      title: match.displayName,
      subtitle: showCommunityName ? match.communityName : null,
      time: formatTimeRange(context, match.startAt, match.endAt),
      location: match.location,
    );
  }
}

/// The shape every compact match card has, whoever is reading it.
///
/// A signed-in player's match and a visitor's come from different models and
/// carry a different closing action, but they are the same object on the same
/// page and a reader must not have to work out which kind they are looking at.
/// The arrangement lives here once so the two cannot drift.
class CompactMatchShell extends StatelessWidget {
  const CompactMatchShell({
    super.key,
    required this.onTap,
    required this.day,
    required this.title,
    required this.time,
    required this.location,
    this.badge,
    this.subtitle,
    this.completed = false,
    this.action,
  });

  final VoidCallback onTap;
  final DateTime day;
  final String title;
  final String time;
  final String location;

  /// The status chip or the seat count — whichever this reader's card carries.
  final Widget? badge;

  /// The community, where the screen is not already about one.
  final String? subtitle;

  final bool completed;

  /// A closing button, on the cards that have one.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: GoColors.surfaceCard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // The card is as tall as the row it sits in, and its content sits
            // at the top of that: a two-line title beside a one-line title must
            // not push the shorter card's date away from its own edge.
            mainAxisSize: MainAxisSize.min,
            children: [
              // A [Wrap] and not a [Row], because the badge beside the date
              // cannot be made narrower: [GoStatusChip] sets its label
              // `softWrap: false` with no ellipsis, so it draws at its natural
              // width whatever it is offered and a `Flexible` around it buys
              // nothing. Given half a phone and the word "Completed" the two do
              // not fit on one line — so the badge takes the next line instead
              // of the card reporting an overflow.
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _CompactDay(day: day, completed: completed),
                  if (badge != null) badge!,
                ],
              ),
              const SizedBox(height: Gap.sm),
              // Two lines, then an ellipsis. A fixture name is the one thing on
              // this card worth wrapping for, and the third line is where a
              // card starts costing more height than the grid saved.
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoType.cardTitle.copyWith(color: GoColors.onSurface),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: GoColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: Gap.sm),
              _CompactLine(icon: Icons.schedule_outlined, text: time),
              const SizedBox(height: Gap.xs),
              _CompactLine(icon: Icons.place_outlined, text: location),
              if (action != null) ...[
                const SizedBox(height: Gap.md),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The date, in the width a column can spare.
///
/// The same three facts the full card's tile carries — weekday, day, month —
/// laid along one line instead of stacked. Stacking cost three lines of height
/// in a card that has about nine, and the tile's whole job here is to be
/// glanced at rather than to be the largest thing on the card.
class _CompactDay extends StatelessWidget {
  const _CompactDay({required this.day, required this.completed});

  final DateTime day;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final background =
        completed ? GoColors.statusCompletedBg : GoColors.statusOpenBg;
    final foreground =
        completed ? GoColors.statusCompletedFg : GoColors.statusOpenFg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.dateTile),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            completed ? Icons.event_available : Icons.calendar_today_outlined,
            size: IconSize.chip,
            color: foreground,
          ),
          const SizedBox(width: Gap.xs),
          // Shortens rather than overflowing, for the locale whose weekday or
          // month is long enough to want the whole card.
          Flexible(
            child: Text(
              formatDayShort(context, day),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: GoType.chip.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// A glyph and a fact, on one line that never wraps.
class _CompactLine extends StatelessWidget {
  const _CompactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child:
              Icon(icon, size: IconSize.meta, color: GoColors.onSurfaceVariant),
        ),
        const SizedBox(width: Gap.xs),
        // The label is what gives, not the glyph beside it. A location too long
        // for the column shortens; it never pushes the card open.
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: GoColors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
