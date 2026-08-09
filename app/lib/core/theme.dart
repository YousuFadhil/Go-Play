// Cupertino, for its page transition alone: iOS users expect the back-swipe
// that comes with it, and Material does not export the builder.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'design.dart';

/// The application's theme.
///
/// It is deliberately long. Everything stated here is something that would
/// otherwise be restated on every screen that needed it — a button's height, a
/// card's corner, how strong a heading is — and the point of putting it in one
/// place is that those answers stop being per-screen decisions. Most of Sprint
/// 2's consistency comes from this file rather than from the screens, which is
/// why the screens changed less than the look did.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1B7A43));
  final text = _textTheme(ThemeData(colorScheme: scheme).textTheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,

    // A page transition that moves without sliding the whole world sideways.
    // Fast enough not to be waited on, which is the only thing an animation
    // here has to get right.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // The bar picks up a hairline only once content is behind it, so a
      // stationary screen has no line across it and a scrolled one does.
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
    ),

    // Cards carry no shadow. Material 3 separates surfaces by tint rather than
    // by lift, and a list of shadowed cards reads as a pile of receipts; the
    // tinted fill plus a hairline border is what makes these read as one
    // surface with divisions in it.
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),

    // Every button is the same height and the same corner. Only the fill
    // changes, which is what lets a filled button read as the primary action
    // without needing to be bigger than the one beside it.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Full width by default, as this app has always had it: `fromHeight`
        // sets an infinite minimum width. Buttons that sit in a row pass their
        // own minimumSize.
        minimumSize: const Size.fromHeight(kButtonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        textStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),

    // Height matched to the filled button, width deliberately not: a secondary
    // action is usually beside something, and forcing it full width is how the
    // old layouts ended up with stretched "Retry" buttons.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, kButtonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),

    // The selected tab is a filled pill behind the icon, and the selected label
    // is heavier than the unselected ones. Either alone is easy to miss at a
    // glance; together the current tab is unambiguous.
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          (states.contains(WidgetState.selected)
                  ? text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: scheme.onSurface)
                  : text.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)) ??
              const TextStyle()),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.lg,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
      minVerticalPadding: Gap.sm,
    ),

    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: Gap.xl,
      thickness: 1,
    ),

    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.all(Gap.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      strokeWidth: 3,
    ),
  );
}

/// Typography, tightened.
///
/// Two changes, applied consistently. Headings get heavier and their tracking
/// gets tighter, which is what makes a large word look set rather than merely
/// big. Body and label sizes are left where Material put them — the hierarchy
/// this sprint was missing was weight, not scale, and inflating sizes would
/// have cost the vertical space Priority 2 is trying to win back.
TextTheme _textTheme(TextTheme base) => base.copyWith(
      headlineLarge: base.headlineLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineMedium: base.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineSmall: base.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: base.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
    );
