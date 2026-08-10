import 'package:flutter/material.dart';

import '../../core/design.dart';

/// One figure: a number, and what it counts.
///
/// Shared by the Community Dashboard and the Player Statistics screen, which
/// show different figures in the same shape — a count with a label. It takes an
/// `int` because every figure either screen puts in one is a count; the Global
/// Rating is not, and has its own presentation on the player screen rather than
/// widening this.
///
/// The number leads and the icon is a mark beside it rather than a picture over
/// it. Three of these sit in a row on a phone, and an icon given its own line
/// costs the row a third of its height to say what the label already says.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.all(Gap.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Gap.lg,
            horizontal: Gap.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(height: Gap.sm),
              Text(
                '$value',
                maxLines: 1,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: Gap.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
