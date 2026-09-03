import 'package:flutter/material.dart';

import 'design.dart';
import 'responsive_grid.dart';
import 'tokens.dart';

/// What a screen shows while it is still reading.
///
/// A centred spinner tells the viewer that something is happening and nothing
/// else — the page stays blank, then everything appears at once and the layout
/// jumps. These are placeholders shaped like the content that is coming, so the
/// page arrives at its final size immediately and filling in is the only thing
/// left to happen.
///
/// The pulse is opacity on a single [AnimationController] shared down the tree
/// by an [AnimatedBuilder], not one controller per box and not a gradient sweep.
/// A loading state that costs measurable frames is worse than the spinner it
/// replaced.

/// One grey box, pulsing.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = Radii.sm,
  });

  /// A box as wide as its parent allows.
  const Skeleton.expand({
    super.key,
    required this.height,
    this.radius = Radii.sm,
  }) : width = double.infinity;

  /// A line of text. The height is a text line's, and [width] is the fraction
  /// of the available width it fills — real paragraphs do not end flush.
  const Skeleton.line({super.key, this.width = double.infinity})
      : height = 12,
        radius = Radii.sm;

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = width <= 1 ? width : null;

    final box = Container(
      width: fraction == null ? width : null,
      height: height,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    // A width of 0..1 is read as a fraction of the line, which is how the text
    // placeholders below ask for "about two thirds" without knowing the width.
    return fraction == null
        ? box
        : FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fraction,
            child: box,
          );
  }
}

/// Drives the pulse for everything beneath it.
class SkeletonFade extends StatefulWidget {
  const SkeletonFade({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonFade> createState() => _SkeletonFadeState();
}

class _SkeletonFadeState extends State<SkeletonFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // The subtree is built once and reused every frame; only the opacity
      // changes, so the pulse costs a composite rather than a rebuild.
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: 0.55 + 0.45 * _controller.value,
        child: child,
      ),
    );
  }
}

/// A placeholder shaped like a match card.
class MatchCardSkeleton extends StatelessWidget {
  const MatchCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Skeleton(width: 52, height: 60, radius: Radii.sm),
                SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(width: 0.7),
                      SizedBox(height: Gap.sm),
                      Skeleton.line(width: 0.45),
                      SizedBox(height: Gap.sm),
                      Skeleton.line(width: 0.55),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: Gap.lg),
            Skeleton.expand(height: 40),
          ],
        ),
      ),
    );
  }
}

/// A placeholder shaped like a community card.
class CommunityCardSkeleton extends StatelessWidget {
  const CommunityCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Skeleton(width: 52, height: 52, radius: Radii.pill),
                SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(width: 0.55),
                      SizedBox(height: Gap.sm),
                      Skeleton.line(width: 0.8),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: Gap.lg),
            Skeleton.expand(height: 40),
          ],
        ),
      ),
    );
  }
}

// --- the compact grids ------------------------------------------------------
//
// The two above are shaped like the *row* cards, and they are still right where
// a row card is what arrives — a community's own page, and the Latest Results
// feed. Where a screen now lays its matches out two across, a column of
// row-shaped placeholders promised a shape the page then did not take: the
// skeleton and the content disagreed, and the disagreement was visible as the
// layout changing shape the moment the read landed. These are the same
// placeholders under the arrangement that actually turns up.

/// A placeholder shaped like a compact match card.
///
/// The date pill, a two-line fixture name, the community under it, and the two
/// meta lines — in the proportions the card draws them, not to the pixel. A
/// skeleton is a promise about shape and size; matching a card's typography
/// exactly would make it a second copy of that card, which is a thing to keep
/// in step rather than a thing that helps.
class CompactMatchCardSkeleton extends StatelessWidget {
  const CompactMatchCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Skeleton(width: 84, height: 23, radius: Radii.dateTile),
            SizedBox(height: Gap.sm),
            Skeleton.line(width: 0.9),
            SizedBox(height: Gap.xs),
            Skeleton.line(width: 0.6),
            SizedBox(height: Gap.sm),
            Skeleton.line(width: 0.75),
            SizedBox(height: Gap.xs),
            Skeleton.line(width: 0.65),
          ],
        ),
      ),
    );
  }
}

/// A placeholder shaped like a compact community card.
///
/// The crest is a rounded square rather than the disc the row skeleton uses,
/// because that is the difference the loaded card makes between a community and
/// a person — a placeholder that got it the wrong way round would be the one
/// thing on the page saying something untrue.
class CompactCommunityCardSkeleton extends StatelessWidget {
  const CompactCommunityCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Skeleton(width: 42, height: 42, radius: 14),
            SizedBox(height: Gap.sm),
            Skeleton.line(width: 0.85),
            SizedBox(height: Gap.xs),
            Skeleton.line(width: 0.5),
            SizedBox(height: Gap.sm),
            Skeleton.line(width: 0.7),
            SizedBox(height: Gap.md),
            Skeleton.expand(height: Layout.buttonHeightSmall),
            SizedBox(height: Gap.sm),
            Skeleton.expand(height: Layout.buttonHeightSmall),
          ],
        ),
      ),
    );
  }
}

/// The loading state for a run of matches that will arrive in a compact grid.
///
/// Wrapped in the very same [ResponsiveCardGrid] the loaded cards use, with the
/// same [GridCard.matchMinWidth] and the same gutters — so how many columns
/// there are before the read lands and how many after it are one decision made
/// once, rather than two rules that agree until somebody changes one of them.
class CompactMatchGridSkeleton extends StatelessWidget {
  const CompactMatchGridSkeleton({super.key, this.count = 4});

  /// How many placeholders. Four fills two rows of two, which is about what a
  /// phone shows before the fold; a screen expecting fewer can say so.
  final int count;

  @override
  Widget build(BuildContext context) {
    return ResponsiveCardGrid(
      maxColumns: 2,
      minCardWidth: GridCard.matchMinWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.sheetGutter,
        vertical: Gap.xs,
      ),
      children: List.filled(count, const CompactMatchCardSkeleton()),
    );
  }
}

/// The same, for the communities a compact grid is about to hold.
class CompactCommunityGridSkeleton extends StatelessWidget {
  const CompactCommunityGridSkeleton({super.key, this.count = 2});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ResponsiveCardGrid(
      maxColumns: 2,
      minCardWidth: GridCard.communityMinWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.sheetGutter,
        vertical: Gap.xs,
      ),
      children: List.filled(count, const CompactCommunityCardSkeleton()),
    );
  }
}
