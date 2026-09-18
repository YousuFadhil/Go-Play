import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/time_format.dart';
import '../../core/tokens.dart';
import 'player_record_models.dart';

/// A section's own title, on the page ground rather than inside a card.
///
/// The approved design puts "Recent Form" and "Recent Highlight" above what
/// they name, at the page margin, with an optional action closing the line —
/// so the heading belongs to the page and the card belongs to the content.
class ProfileSectionHeading extends StatelessWidget {
  const ProfileSectionHeading(
    this.text, {
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final String text;

  /// The link that closes the line — "View all" on Recent Form.
  ///
  /// **Drawn only when there is somewhere for it to go.** It is given a
  /// destination on the player's own record and left null everywhere else: a
  /// visitor has no statistics screen to open, and a link that opens nothing is
  /// worse than no link.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        kPageMargin,
        Layout.sectionAbove,
        kPageMargin,
        Layout.sectionBelow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: Gap.sm),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: GoColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The last five results, and what they add up to.
///
/// **Newest first, and the order is the read's rather than this widget's.** The
/// entries arrive in the order the database returned them and are drawn in it;
/// nothing here sorts, which is what stops the screen from having a second
/// opinion about which match is the most recent.
///
/// The row lays itself out from the ambient direction, so the most recent match
/// is on the left in English and on the right in Arabic without this widget
/// naming either language.
class RecentFormSection extends StatelessWidget {
  const RecentFormSection({super.key, required this.form, this.onViewAll});

  final RecentForm form;

  /// Where "View all" goes, on the one reading of the profile that has an
  /// answer. Null draws no link — see [ProfileSectionHeading.actionLabel].
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileSectionHeading(
          l10n.recentFormTitle,
          actionLabel: onViewAll == null ? null : l10n.recentFormViewAll,
          onAction: onViewAll,
        ),
        if (form.isEmpty)
          SectionCard(
            margin: const EdgeInsets.symmetric(horizontal: kPageMargin),
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Text(
                l10n.recentFormEmpty,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: GoColors.onSurfaceVariant,
                ),
              ),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageMargin),
            child: Row(
              children: [
                for (final entry in form.entries) ...[
                  if (entry != form.entries.first)
                    const SizedBox(width: Gap.sm),
                  Expanded(child: _FormTile(entry: entry)),
                ],
                // Five slots whatever the window holds, so four results are
                // four badges at the same width as five rather than four wide
                // ones.
                for (var i = form.entries.length; i < 5; i++) ...[
                  const SizedBox(width: Gap.sm),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One result, as a letter in a disc on a card of its own.
///
/// The letter is localized and the colour is not the only thing carrying the
/// meaning — a reader who cannot tell the green from the red still reads W, D
/// or L. `Semantics` gives the full word to a screen reader, which a single
/// letter would not.
class _FormTile extends StatelessWidget {
  const _FormTile({required this.entry});

  final RecentFormEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final (short, full) = switch (entry.outcome) {
      MatchOutcome.win => (l10n.recentFormWinShort, l10n.recentFormWin),
      MatchOutcome.draw => (l10n.recentFormDrawShort, l10n.recentFormDraw),
      MatchOutcome.loss => (l10n.recentFormLossShort, l10n.recentFormLoss),
    };
    final (background, ink) = switch (entry.outcome) {
      MatchOutcome.win => (GoColors.bgHero, Colors.white),
      MatchOutcome.draw => (
          GoColors.surfaceContainerHighest,
          GoColors.onSurface,
        ),
      MatchOutcome.loss => (GoColors.error, GoColors.onError),
    };
    final scoreline = entry.scoreline;

    return Semantics(
      label: scoreline == null ? full : '$full, $scoreline',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm + 2),
        decoration: BoxDecoration(
          color: GoColors.surfaceCard,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: GoColors.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
              ),
              child: Text(
                short,
                style: TextStyle(
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ),
            if (scoreline != null) ...[
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                // The player's own goals lead in both languages: a scoreline
                // is read home-then-away, and its internal order is not the
                // page's.
                child: Text(
                  scoreline,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: GoColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one recent achievement worth showing, when there is one.
///
/// **There is no empty state, deliberately.** The approved rule is that a
/// player with nothing eligible has no section — so this widget is only ever
/// built with a highlight, and the decision to build it at all belongs to the
/// screen. A card reading "no highlights yet" would be a placeholder for
/// something most players will never have.
class RecentHighlightSection extends StatelessWidget {
  const RecentHighlightSection({super.key, required this.highlight});

  final RecentHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final (icon, title) = switch (highlight.kind) {
      HighlightKind.mvp => (Icons.star, l10n.highlightMvpTitle),
      HighlightKind.teamOfPeriod => (
          Icons.emoji_events,
          switch (highlight.period) {
            HighlightPeriod.week => l10n.teamOfPeriodWeekHeading,
            HighlightPeriod.month => l10n.teamOfPeriodMonthHeading,
            // A stored award always carries its period; null would be a build
            // older than the row, and the general title still says what it is.
            null => l10n.highlightTeamOfPeriodTitle,
          },
        ),
    };
    final community = highlight.communityName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileSectionHeading(l10n.recentHighlightTitle),
        SectionCard(
          margin: const EdgeInsets.symmetric(horizontal: kPageMargin),
          padding: const EdgeInsets.all(Gap.md),
          children: [
            Row(
              children: [
                // The award mark: the product's own warn hue, which is the one
                // amber in the palette and already what a trophy is drawn on.
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: GoColors.warnContainer,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Icon(icon, size: 24, color: GoColors.onWarnContainer),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        highlightPeriodLine(context, highlight),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: GoColors.primary,
                        ),
                      ),
                      if (community != null && community.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          community,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: GoColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// The line under a highlight's title: which period it was, and when.
///
/// "Week 37 • Sep 13, 2026" for a stored Team of the Week, the month alone for
/// a Team of the Month -- naming a month and then dating it to the last day of
/// that same month says one thing twice -- and the date alone for an MVP, which
/// is a match rather than a period.
///
/// The week number is the stored key's ([RecentHighlight.weekNumber]); an award
/// from a database older than `0080` carries none and is dated instead.
String highlightPeriodLine(BuildContext context, RecentHighlight highlight) {
  final day = formatAwardDay(context, highlight.occurredAt);
  final week = highlight.weekNumber;
  if (week != null) return '${context.l10n.highlightWeekNumber(week)} • $day';
  if (highlight.period == HighlightPeriod.month) {
    return formatAwardMonth(context, highlight.occurredAt);
  }
  return day;
}
