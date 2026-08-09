import 'package:flutter/material.dart';

import 'design.dart';
import 'l10n.dart';

/// The three things a screen shows when it is not showing its content.
///
/// Before this file each screen wrote its own. A failed read was a bare
/// sentence over a stretched Retry button on one screen and a centred column
/// with an icon on the next; an empty list was sometimes a paragraph and
/// sometimes nothing at all. None of those differences meant anything — they
/// were simply what whoever wrote the screen reached for — and the cost was
/// that the same situation looked like a different situation depending on where
/// the reader met it.
///
/// One shape each, used everywhere, so "nothing here yet" and "that did not
/// load" are recognisable before they are read.

/// Nothing to show, and that is normal.
///
/// [action] is offered only where the reader can actually do something about
/// it. An empty state with a button that leads nowhere is worse than one
/// without: it implies the emptiness is the reader's to fix.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.note,
    this.action,
  });

  final IconData icon;

  /// The headline. Optional, because some empty states are one sentence and a
  /// title above it would only repeat that sentence in fewer words.
  final String? title;
  final String message;

  /// A quieter second line — usually why something is unavailable rather than
  /// what to do about it.
  final String? note;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.xl,
          vertical: Gap.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The icon sits in a tinted disc rather than floating on the
            // background: at this size a bare outline glyph reads as a missing
            // image instead of as an illustration.
            Container(
              padding: const EdgeInsets.all(Gap.lg),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Gap.lg),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Gap.sm),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (note != null) ...[
              const SizedBox(height: Gap.md),
              Text(
                note!,
                textAlign: TextAlign.center,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Gap.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A read that failed, and the one thing worth offering about it.
///
/// The retry is an outlined button rather than a filled one on purpose: it is
/// the only control on the screen, and filling it would make a recovery look
/// like the screen's purpose.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;

  /// Defaults to the generic load failure, which is what nearly every caller
  /// wants; a screen that knows something more specific passes it.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.xl,
          vertical: Gap.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Gap.lg),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 32,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: Gap.lg),
            Text(
              message ?? l10n.loadFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Gap.xl),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// A read still in flight, where there is no shape to placeholder.
///
/// Screens that know what is coming use the skeletons instead; this is for the
/// ones whose content has no fixed shape, and it exists mainly so that a
/// spinner is the same size in the same place on every one of them.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(Gap.xxl),
        child: SizedBox(
          height: 32,
          width: 32,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

/// A heading over a group of things, with the size of the group beside it.
///
/// The count is a separate, quieter figure rather than part of the title.
/// "Members (12)" makes the number look like part of the word; a pill beside it
/// reads as a measurement of what follows, which is what it is.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      kPageMargin,
      Gap.xl,
      kPageMargin,
      Gap.sm,
    ),
  });

  final String title;
  final int? count;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: Gap.sm),
            _CountPill(count: count!),
          ],
          if (trailing != null) ...[
            const SizedBox(width: Gap.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A card that holds a group of rows, with the page margin already on it.
///
/// The details screens were lists of bare [ListTile]s running edge to edge,
/// which is what made them read as forms. Grouping the rows the same way the
/// rest of the product groups things is most of what separates a record from a
/// settings page.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(vertical: Gap.xs),
    this.margin = const EdgeInsets.fromLTRB(
      kPageMargin,
      Gap.sm,
      kPageMargin,
      Gap.sm,
    ),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A quiet closing sentence: what the figures above mean, or why something is
/// not offered. Never an error, and styled so it cannot be mistaken for one.
class FootNote extends StatelessWidget {
  const FootNote(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(
      kPageMargin,
      Gap.xl,
      kPageMargin,
      Gap.lg,
    ),
    this.textAlign = TextAlign.start,
  });

  final String text;
  final EdgeInsetsGeometry padding;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Text(
        text,
        textAlign: textAlign,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }
}
