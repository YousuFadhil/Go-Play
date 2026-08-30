// Cupertino, for its page transition alone: iOS users expect the back-swipe
// that comes with it, and Material does not export the builder.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'design.dart';
import 'tokens.dart';

/// The application's theme.
///
/// It is deliberately long. Everything stated here is something that would
/// otherwise be restated on every screen that needed it — a button's height, a
/// card's corner, how strong a heading is — and the point of putting it in one
/// place is that those answers stop being per-screen decisions.
///
/// The colours and the type are the frozen Club direction, applied here and
/// nowhere else. No screen was changed to land them: a screen asks the theme
/// what a card looks like, so moving a card from a tinted fill to white is a
/// change to one line in this file rather than to twenty files elsewhere. That
/// is the whole reason this phase can be tokens-only and still be visible.
ThemeData buildAppTheme() {
  const scheme = _clubScheme;
  final text = _textTheme(ThemeData(colorScheme: scheme).textTheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,

    // The page ground, and the one visible change this phase makes everywhere
    // at once. Not `scheme.surface`: the sheet a screen sits on is a shade
    // below the card ramp, which is what lets a white card read as lifted off
    // it rather than as a slightly different white.
    scaffoldBackgroundColor: GoColors.bgPage,

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
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: scheme.onSurface, size: IconSize.bar),
    ),

    // White, rounder, and no border. The tinted fill and hairline edge were
    // what made a list of cards read as one surface with divisions in it; the
    // direction separates them by lift instead, and the lift is two shadow
    // stops that Material's `elevation:` cannot draw. So the shadow is not
    // here — it belongs to the card component this phase does not build yet,
    // and until then a card is flat rather than wrongly shadowed.
    cardTheme: CardThemeData(
      elevation: 0,
      color: GoColors.surfaceCard,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
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
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: text.labelLarge,
      ),
    ),

    // Height matched to the filled button, width deliberately not: a secondary
    // action is usually beside something, and forcing it full width is how the
    // old layouts ended up with stretched "Retry" buttons.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, kButtonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: const BorderSide(color: GoColors.borderOutlined, width: 1.5),
        textStyle: text.labelLarge,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, Layout.tapMin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        textStyle: text.labelLarge,
      ),
    ),

    // Structurally what it was: a docked bar in the Scaffold's own slot, with a
    // filled pill behind the selected icon. The direction floats it instead and
    // that is a later phase's work — what lands here is only the label, which
    // would otherwise have inherited the row-title size the Club ramp gives
    // `labelMedium` and grown from 12px to 14px. A navigation label that no
    // longer fits at 320px would be a regression introduced by a token change,
    // which is exactly what this phase must not do.
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: IconSize.bar,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? GoType.navLabelSelected.copyWith(color: scheme.onSurface)
            : GoType.navLabelUnselected
                .copyWith(color: scheme.onSurfaceVariant),
      ),
    ),

    // A filled field with a hairline edge. Focus thickens the border to two
    // pixels in the primary colour; that is the whole focus treatment.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GoColors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.lg,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: const BorderSide(color: GoColors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: const BorderSide(color: GoColors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: const BorderSide(color: GoColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: const BorderSide(color: GoColors.error, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: const BorderSide(color: GoColors.error, width: 2),
      ),
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
      minVerticalPadding: Gap.sm,
    ),

    chipTheme: const ChipThemeData(
      side: BorderSide.none,
      shape: StadiumBorder(),
      labelStyle: GoType.chip,
      padding: EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
    ),

    // Content tabs, not a filter. An underline under the selected label and a
    // heavier word: the direction draws no indicator pill here.
    tabBarTheme: TabBarThemeData(
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: GoColors.primaryDeep, width: 2.5),
      ),
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: GoColors.onSurface,
      labelStyle: GoType.tabSelected,
      unselectedLabelColor: GoColors.outline,
      unselectedLabelStyle: GoType.tabUnselected,
      dividerColor: GoColors.hairline,
    ),

    // A filter or a view, which is the thing that separates it from a tab.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, 40),
        side: const BorderSide(color: GoColors.outlineVariant),
        shape: const StadiumBorder(),
        selectedBackgroundColor: GoColors.secondaryContainer,
        selectedForegroundColor: GoColors.onSecondaryContainer,
        foregroundColor: GoColors.onSurface,
        textStyle: text.labelLarge,
      ),
    ),

    dividerTheme: DividerThemeData(
      color: GoColors.hairline,
      space: Gap.xl,
      thickness: 1,
    ),

    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sheet),
      ),
      titleTextStyle: text.titleLarge,
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.all(Gap.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: GoColors.primary,
      strokeWidth: 3,
    ),
  );
}

/// The palette, stated rather than derived.
///
/// It was generated from `ColorScheme.fromSeed(Color(0xFF1B7A43))` and then
/// read back off the shipped build, so these are the colours that were on the
/// device when the direction was approved. Writing them out is the point:
/// `fromSeed` is an algorithm and an algorithm is free to move between Flutter
/// releases, which is a thing a frozen design cannot afford. Every value comes
/// from [GoColors], so the scheme and the components that reach past it are
/// reading the same constant.
const ColorScheme _clubScheme = ColorScheme(
  brightness: Brightness.light,
  primary: GoColors.primary,
  onPrimary: GoColors.onPrimary,
  primaryContainer: GoColors.primaryContainer,
  onPrimaryContainer: GoColors.onPrimaryContainer,
  secondary: GoColors.secondary,
  onSecondary: GoColors.onSecondary,
  secondaryContainer: GoColors.secondaryContainer,
  onSecondaryContainer: GoColors.onSecondaryContainer,
  tertiary: GoColors.tertiary,
  onTertiary: GoColors.onTertiary,
  tertiaryContainer: GoColors.tertiaryContainer,
  onTertiaryContainer: GoColors.onTertiaryContainer,
  error: GoColors.error,
  onError: GoColors.onError,
  errorContainer: GoColors.errorContainer,
  onErrorContainer: GoColors.onErrorContainer,
  surface: GoColors.surface,
  onSurface: GoColors.onSurface,
  onSurfaceVariant: GoColors.onSurfaceVariant,
  surfaceDim: GoColors.surfaceDim,
  surfaceBright: GoColors.surfaceBright,
  surfaceContainerLowest: GoColors.surfaceContainerLowest,
  surfaceContainerLow: GoColors.surfaceContainerLow,
  surfaceContainer: GoColors.surfaceContainer,
  surfaceContainerHigh: GoColors.surfaceContainerHigh,
  surfaceContainerHighest: GoColors.surfaceContainerHighest,
  outline: GoColors.outline,
  outlineVariant: GoColors.outlineVariant,
  inverseSurface: GoColors.inverseSurface,
  onInverseSurface: GoColors.onInverseSurface,
  inversePrimary: GoColors.inversePrimary,
  scrim: GoColors.scrim,
);

/// Typography, as the direction sets it.
///
/// The Club ramp is a half-step scale — 10.5, 11.5, 12.5, 14.5, 15.5 — rather
/// than Material's. Most of it maps onto a [TextTheme] slot and is applied
/// here; the sizes that have no slot are in [GoType].
///
/// Tracking is stated on every slot, including the ones the direction sets to
/// zero. Left unstated, Material's own tracking survives a `copyWith` — half a
/// pixel on body text and a tenth on a button label — and the type would be
/// almost, but not quite, the approved one.
///
/// [TextTheme.headlineLarge] and [TextTheme.headlineMedium] keep the treatment
/// they already had. The direction names neither, and inventing a value for a
/// slot nobody specified is how a frozen design quietly stops being frozen.
TextTheme _textTheme(TextTheme base) => base.copyWith(
      // The big numeral: a rating, a score, a join code.
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 34,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.4,
      ),
      headlineLarge: base.headlineLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineMedium: base.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      // A hero title: a match name, "Hello, {name}".
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 23,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      // A community's name on its hero.
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
      ),
      // A task screen's title.
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      // A section heading.
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 16.5,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      // Body, and a list row's primary line.
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      // A meta line, a description.
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 12.5,
        height: 1.4,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      // A row subtitle, a count.
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      // Every button.
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14.5,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      // A member, a participant, a list row's title.
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      // A field label. The capitals and the +0.06em the direction asks of a
      // micro-label are in [GoType.microLabel]: this slot is shared with places
      // that are not micro-labels, and tracking them all would be wrong.
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11.5,
        height: 1,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
