import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'team_models.dart';

/// Who is being dragged across a match board right now, shared by both halves.
///
/// The two teams are drawn by two separate [PitchView]s, and a drag from one
/// half can end on the other, so the state that lets every valid card light up
/// has to sit above both. `MatchStageBoard` puts one here when it is given a
/// swap callback; a pitch without one still drags, and highlights only the card
/// under the finger.
class PitchDragScope extends StatefulWidget {
  const PitchDragScope({super.key, required this.child});

  final Widget child;

  /// The participant being dragged inside the nearest scope, or null when
  /// nobody is (or there is no scope). Rebuilds the caller when it changes.
  static TeamAssignment? draggingOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_PitchDragNotifier>()
      ?.notifier
      ?.value;

  static ValueNotifier<TeamAssignment?>? _notifierOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_PitchDragNotifier>()?.notifier;

  @override
  State<PitchDragScope> createState() => _PitchDragScopeState();
}

class _PitchDragScopeState extends State<PitchDragScope> {
  final _dragging = ValueNotifier<TeamAssignment?>(null);

  @override
  void dispose() {
    _dragging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _PitchDragNotifier(notifier: _dragging, child: widget.child);
}

class _PitchDragNotifier
    extends InheritedNotifier<ValueNotifier<TeamAssignment?>> {
  const _PitchDragNotifier({required super.notifier, required super.child});
}

/// One player card that can be dragged onto another and can take a drop.
///
/// Long-press then drag: the card follows the finger (or the mouse) and every
/// card [canSwap] accepts is outlined, the one under the pointer filled. Drop
/// on a valid card calls [onSwap]; anywhere else, nothing happens.
///
/// Long-press then release without moving is not a drag: it calls [onTap],
/// which on the Teams screen is the same menu a tap opens. A plain tap still
/// reaches the card's own [InkWell] untouched.
class SwappablePlayer extends StatefulWidget {
  const SwappablePlayer({
    super.key,
    required this.assignment,
    required this.canSwap,
    required this.onSwap,
    required this.feedback,
    required this.borderRadius,
    required this.child,
    this.onTap,
  });

  final TeamAssignment assignment;
  final bool Function(TeamAssignment dragged, TeamAssignment target) canSwap;
  final void Function(TeamAssignment dragged, TeamAssignment target) onSwap;
  final VoidCallback? onTap;

  /// What follows the pointer: the same card, without its tap target.
  final Widget feedback;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<SwappablePlayer> createState() => _SwappablePlayerState();
}

class _SwappablePlayerState extends State<SwappablePlayer> {
  double _travelled = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dragging = PitchDragScope.draggingOf(context);
    final notifier = PitchDragScope._notifierOf(context);

    return DragTarget<TeamAssignment>(
      onWillAcceptWithDetails: (details) =>
          widget.canSwap(details.data, widget.assignment),
      onAcceptWithDetails: (details) =>
          widget.onSwap(details.data, widget.assignment),
      builder: (context, candidates, _) {
        final hovered = candidates.isNotEmpty;
        final valid = hovered ||
            (dragging != null && widget.canSwap(dragging, widget.assignment));
        // Always the same box, so lighting a card up never remounts it.
        final card = DecoratedBox(
          decoration: valid
              ? BoxDecoration(
                  borderRadius: widget.borderRadius,
                  color: hovered ? scheme.primary.withValues(alpha: .18) : null,
                  border: Border.all(
                    color: scheme.primary,
                    width: hovered ? 3 : 1.5,
                  ),
                )
              : const BoxDecoration(),
          child: widget.child,
        );

        return LongPressDraggable<TeamAssignment>(
          data: widget.assignment,
          feedback: Material(
            type: MaterialType.transparency,
            child: widget.feedback,
          ),
          childWhenDragging: Opacity(opacity: .35, child: widget.child),
          onDragStarted: () {
            _travelled = 0;
            notifier?.value = widget.assignment;
          },
          onDragUpdate: (details) => _travelled += details.delta.distance,
          onDragEnd: (details) {
            if (notifier?.value == widget.assignment) notifier?.value = null;
            // Held and let go where it was picked up: the menu, not a drag.
            if (!details.wasAccepted && _travelled < kTouchSlop) {
              widget.onTap?.call();
            }
          },
          child: card,
        );
      },
    );
  }
}
