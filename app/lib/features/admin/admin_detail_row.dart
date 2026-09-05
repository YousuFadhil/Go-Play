import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/tokens.dart';

/// Stands in for a figure the database genuinely does not have.
///
/// The same dash the Overview and User Detail use, and for the same reason: an
/// unknown Last Seen is not a Last Seen of the join date, and an unobserved
/// platform is not "none".
const String adminUnknownValue = '—';

/// A label and the value beside it, as every Platform Admin record screen
/// writes one.
///
/// Extracted rather than copied into each of the four screens that now want it.
/// The alternative was four private widgets with the same padding and the same
/// two text styles, which is exactly the kind of duplication that ends with a
/// record screen that looks subtly unlike its neighbours.
class AdminDetailRow extends StatelessWidget {
  const AdminDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.unknown = false,
    this.onTap,
  });

  final String label;
  final String value;

  /// Whether [value] is the dash standing in for something the database does
  /// not have, rather than a figure. Only affects how it is spoken -- a screen
  /// reader announcing "dash" tells an administrator nothing.
  final bool unknown;

  /// Where this row leads, when it leads anywhere. Null for the ordinary case:
  /// a record screen is mostly facts, and a fact is not a button.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tap = onTap;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardInner,
        vertical: Gap.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              semanticsLabel:
                  unknown ? context.l10n.adminMetricUnavailable : null,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: tap == null ? null : theme.colorScheme.primary,
              ),
            ),
          ),
          if (tap != null) ...[
            const SizedBox(width: Gap.xs),
            Icon(
              Icons.chevron_right,
              size: IconSize.meta,
              color: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
    );

    return tap == null ? row : InkWell(onTap: tap, child: row);
  }
}
