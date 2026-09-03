/// How many cards fit across, and what to do when they do not.
///
/// Three screens now lay cards out in rows rather than one per line, and each
/// wants a different maximum: two for a match, two for a community, three for a
/// member. What they must not each decide for themselves is *when* to give one
/// up — a grid that keeps two columns past the point the card can hold its
/// content is the thing this file exists to prevent.
///
/// Deliberately not a responsive framework. There are no breakpoints, no device
/// classes and no notion of "tablet": a breakpoint is a claim about a screen,
/// and what actually matters here is a claim about a *card* — the narrowest it
/// can be and still be read. That number belongs to the card, so each caller
/// states its own and this decides the rest.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A row-wrapping grid of equal-width cards.
///
/// Rows of [Expanded] children rather than a [GridView], for two reasons. Every
/// caller sits inside a list that already scrolls, and a nested scrollable would
/// have to be shrink-wrapped and un-scrolled to behave — but more importantly a
/// [GridView] wants a `childAspectRatio`, which fixes a card's height in advance
/// and is exactly wrong here: an Arabic name that takes two lines where an
/// English one takes one must make the row taller, not clip.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.children,
    required this.maxColumns,
    required this.minCardWidth,
    this.spacing = Layout.cardGap,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;

  /// The most columns this content is ever laid out in. Never exceeded — a
  /// wide window gets wider cards, not more of them, because these grids are
  /// read at a glance and a fourth column across a desktop turns them into a
  /// table.
  final int maxColumns;

  /// The narrowest a card may be drawn and still be worth reading.
  ///
  /// This is the whole decision. Below it the grid drops a column, which is the
  /// approved fallback — never a horizontal scroll, and never a smaller
  /// typeface.
  final double minCardWidth;

  final double spacing;
  final EdgeInsetsGeometry padding;

  /// How many columns [availableWidth] supports.
  ///
  /// Pure, and public, so the contract can be tested as arithmetic instead of
  /// only through a rendered tree. [availableWidth] is the width *after* the
  /// surrounding padding — what the cards actually get.
  ///
  /// Tries the maximum first and steps down while a card would come out
  /// narrower than [minCardWidth]. One column is always the answer of last
  /// resort: a single card too narrow to read is still better than two.
  static int columnsFor({
    required double availableWidth,
    required int maxColumns,
    required double minCardWidth,
    double spacing = Layout.cardGap,
  }) {
    for (var columns = maxColumns; columns > 1; columns--) {
      final cardWidth = (availableWidth - spacing * (columns - 1)) / columns;
      if (cardWidth >= minCardWidth) return columns;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      // Inside the padding, so the constraint read here is the width the cards
      // are actually offered rather than the width of the window.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = columnsFor(
            availableWidth: constraints.maxWidth,
            maxColumns: maxColumns,
            minCardWidth: minCardWidth,
            spacing: spacing,
          );

          final rows = <Widget>[];
          for (var start = 0; start < children.length; start += columns) {
            final end = (start + columns).clamp(0, children.length);
            final row = children.sublist(start, end);

            rows.add(
              // The two or three cards on a row are the same height, whichever
              // of them has the longest name. Without this a short name beside
              // a wrapped one leaves the shorter card floating at the top of a
              // taller slot, which reads as a mistake.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) SizedBox(width: spacing),
                      // A short last row keeps its cards at column width rather
                      // than stretching them across the gap.
                      Expanded(
                        child: column < row.length
                            ? row[column]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                rows[i],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The narrowest each kind of card may be drawn.
///
/// Here rather than at the call sites because the same card appears on more
/// than one screen — a match on Discover, on Home and in a community — and the
/// point at which it gives up a column must not depend on which screen the
/// reader is standing on.
abstract final class GridCard {
  /// A compact match card. Set so that a 360-wide phone keeps two columns and
  /// a 320-wide one falls back to one, which is where the card stops holding a
  /// two-line fixture name beside a status chip.
  static const double matchMinWidth = 150;

  /// A compact community card. The same measurement: the two sit in the same
  /// scroll on Discover and a different fallback point between them would show.
  static const double communityMinWidth = 150;

  /// A member card. Smaller because it carries less — a face, a name and a
  /// position — which is what lets three of them sit across a phone.
  static const double memberMinWidth = 96;
}
