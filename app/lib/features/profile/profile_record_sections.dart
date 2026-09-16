import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import '../../core/tokens.dart';
import 'player_record_models.dart';

/// The last five results, and what they add up to.
///
/// **Newest first, and the order is the read's rather than this widget's.** The
/// entries arrive in the order the database returned them and are drawn in it;
/// nothing here sorts, which is what stops the screen from having a second
/// opinion about which match is the most recent.
///
/// The three figures beneath are counted from the same five entries, so the
/// summary cannot describe a different window than the badges above it.
class RecentFormSection extends StatelessWidget {
  const RecentFormSection({super.key, required this.form});

  final RecentForm form;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SectionCard(
      // The default padding is vertical only, because the cards that use it
      // are lists of `ListTile`s that bring their own inset. This one draws
      // its own content, so it supplies the inset itself.
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        _SectionHeading(l10n.recentFormTitle),
        const SizedBox(height: Gap.md),
        if (form.isEmpty)
          Text(
            l10n.recentFormEmpty,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          Row(
            children: [
              for (final entry in form.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: Gap.sm),
                  child: _FormBadge(outcome: entry.outcome),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              // The short labels, not the career card's: "Matches played"
              // appears above this section describing a different window, and
              // one screen saying it twice about two windows would be one
              // label too many.
              Expanded(
                child: _Figure(
                  value: form.matches,
                  label: l10n.shareCardStatMatches,
                ),
              ),
              Expanded(
                child: _Figure(
                  value: form.goals,
                  label: l10n.shareCardStatGoals,
                ),
              ),
              Expanded(
                child: _Figure(
                  value: form.wins,
                  label: l10n.shareCardStatWins,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            l10n.recentFormNote(form.matches),
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// One result, as a letter in a disc.
///
/// The letter is localized and the colour is not the only thing carrying the
/// meaning — a reader who cannot tell the green from the grey still reads W, D
/// or L. `Semantics` gives the full word to a screen reader, which a single
/// letter would not.
class _FormBadge extends StatelessWidget {
  const _FormBadge({required this.outcome});

  final MatchOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    final (short, full) = switch (outcome) {
      MatchOutcome.win => (l10n.recentFormWinShort, l10n.recentFormWin),
      MatchOutcome.draw => (l10n.recentFormDrawShort, l10n.recentFormDraw),
      MatchOutcome.loss => (l10n.recentFormLossShort, l10n.recentFormLoss),
    };
    final (background, ink) = switch (outcome) {
      MatchOutcome.win => (GoColors.bgHero, Colors.white),
      MatchOutcome.draw => (scheme.surfaceContainerHighest, scheme.onSurface),
      MatchOutcome.loss => (
          scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          scheme.onSurfaceVariant,
        ),
    };

    return Semantics(
      label: full,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
        ),
        child: Text(
          short,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ),
    );
  }
}

/// One figure of the recent-window summary.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontSize: 20,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
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
    final scheme = Theme.of(context).colorScheme;

    final (icon, title) = switch (highlight.kind) {
      HighlightKind.mvp => (Icons.star, l10n.highlightMvpTitle),
      HighlightKind.teamOfPeriod => (
          Icons.emoji_events,
          l10n.highlightTeamOfPeriodTitle,
        ),
    };
    final community = highlight.communityName;

    return SectionCard(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        _SectionHeading(l10n.recentHighlightTitle),
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: GoColors.bgHero,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: Colors.white),
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
                  if (community != null && community.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      l10n.highlightInCommunity(community),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A section's own title, at the weight the profile's cards already use.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      );
}
