import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import 'statistics_period.dart';

/// The control that says which stretch of history is on screen.
///
/// One selector, used by all three statistics surfaces, so that switching to a
/// week means the same thing and looks the same wherever it is done.
///
/// **Material's own `SegmentedButton`, not a hand-built row of chips.** It gives
/// the selection its check mark, its focus and keyboard handling, and its
/// semantics — a radio group, announced as one — for nothing, and it takes the
/// app's theme without being told to. A bespoke control would have to be taught
/// each of those and would be the only one in the app that behaves slightly
/// differently.
///
/// **Text that shrinks rather than a row that overflows.** Three localized
/// labels on a narrow phone are the one thing that can break this control, and
/// Arabic's are the longer set. The icons are dropped and each label is allowed
/// to scale down before it is allowed to clip, so the control fits a 320-point
/// screen in both languages instead of painting a yellow stripe.
class StatisticsPeriodSelector extends StatelessWidget {
  const StatisticsPeriodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final StatisticsPeriod selected;
  final ValueChanged<StatisticsPeriod> onChanged;

  /// The order the periods are offered in: narrowest first, so the control
  /// reads as a zoom out and the default sits where the eye ends up.
  static const _order = [
    StatisticsPeriod.weekly,
    StatisticsPeriod.monthly,
    StatisticsPeriod.allTime,
  ];

  static String label(AppLocalizations l10n, StatisticsPeriod period) =>
      switch (period) {
        StatisticsPeriod.weekly => l10n.statPeriodWeekly,
        StatisticsPeriod.monthly => l10n.statPeriodMonthly,
        StatisticsPeriod.allTime => l10n.statPeriodAllTime,
      };

  /// The same period, named for a share card rather than for this control.
  ///
  /// Only All Time differs, and only in Arabic. The segment on screen says
  /// «الكل» — correct there, where three chips sit side by side and the
  /// shortest word that separates them wins. A card that leaves the app has no
  /// neighbouring chips to be short against, and «الفترة · الكل» reads as "the
  /// period · everything" rather than as the name of a period. The card says
  /// «كل الفترات».
  ///
  /// It lives beside [label] rather than inside the two cards because both
  /// cards need it, and two switches would be two places for the wording to
  /// drift apart.
  static String shareLabel(AppLocalizations l10n, StatisticsPeriod period) =>
      switch (period) {
        StatisticsPeriod.weekly => l10n.statPeriodWeekly,
        StatisticsPeriod.monthly => l10n.statPeriodMonthly,
        StatisticsPeriod.allTime => l10n.shareCardPeriodAllTime,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageMargin, Gap.md, kPageMargin, 0),
      child: Semantics(
        label: l10n.statPeriodLabel,
        container: true,
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<StatisticsPeriod>(
            segments: [
              for (final period in _order)
                ButtonSegment<StatisticsPeriod>(
                  value: period,
                  // `scaleDown` shrinks a label that will not fit and leaves
                  // one that does at its proper size, so the three segments
                  // stay the same width and nothing clips. `softWrap: false`
                  // keeps a label on one line for it to measure.
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label(l10n, period),
                      softWrap: false,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
            selected: {selected},
            // Single selection, so the set always holds exactly one.
            onSelectionChanged: (selection) => onChanged(selection.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              textStyle: theme.textTheme.labelLarge,
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ),
    );
  }
}
