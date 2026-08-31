import 'package:flutter/material.dart';

import 'design.dart';
import 'tokens.dart';

/// The plain bar for a task: one way back and one bounded title, without the
/// signed-in account menu that belongs to the app's place screens.
class ClubTaskBar extends StatelessWidget implements PreferredSizeWidget {
  const ClubTaskBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions,
  });

  final String title;
  final VoidCallback? onBack;

  /// The task's own actions, at the trailing edge of the bar.
  ///
  /// A task screen usually has none — its action is the pinned button at the
  /// foot. This is for the exception: an action that belongs to the whole
  /// screen rather than to a step in it, such as sharing what is on it.
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(Layout.taskBarHeight + 1);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: Layout.taskBarHeight,
      backgroundColor: GoColors.surfaceCard,
      foregroundColor: GoColors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: GoColors.hairline),
      ),
      leading: IconButton(
        onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        icon: const BackButtonIcon(),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      actions: actions,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 17,
          height: 1.25,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: GoColors.onSurface,
        ),
      ),
    );
  }
}

/// The independently scrollable, light surface of a task screen.
class ClubTaskBody extends StatelessWidget {
  const ClubTaskBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsetsDirectional.fromSTEB(
      Layout.sheetGutter,
      Gap.md,
      Layout.sheetGutter,
      Gap.xl,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: GoColors.bgPage,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// The fixed commit surface at the bottom of a task screen.
class ClubActionBar extends StatelessWidget {
  const ClubActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GoColors.surfaceCard,
        border: Border(top: BorderSide(color: GoColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Layout.cardInner,
            Gap.md,
            Layout.cardInner,
            Gap.lg,
          ),
          child: child,
        ),
      ),
    );
  }
}
