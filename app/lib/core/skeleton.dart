import 'package:flutter/material.dart';

import 'design.dart';

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
