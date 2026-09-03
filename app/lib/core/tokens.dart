/// The frozen Club design tokens.
///
/// Source of truth: `design/HANDOFF.md` §A and `design/tokens/*.css`, approved
/// and frozen by the Product Owner. Every value here is literal — transcribed,
/// not derived and not rounded to a Material default or a 4/8-px grid. The two
/// things that make this file worth having are that a value appears exactly
/// once, and that changing the product's look is a change here rather than a
/// change spread across twenty screens.
///
/// This file holds the tokens the Club direction *adds*: the palette as
/// explicit colours, the shadow stops, the icon scale, the layout measurements
/// and the motion constants. The measurements the app was already built from —
/// [Gap], [Radii], `kPageMargin` — stay in `design.dart`, which is what the
/// screens already import; where the two meet, `design.dart` refers here rather
/// than restating a number.
library;

import 'package:flutter/material.dart';

/// The palette.
///
/// The scheme was generated from `ColorScheme.fromSeed(Color(0xFF1B7A43))` and
/// then read back off the shipped build, so these are the colours that were on
/// the device when the direction was approved. They are declared literally
/// rather than re-derived: `fromSeed` is an algorithm, and an algorithm is free
/// to move between Flutter releases. A frozen design cannot be.
///
/// Three values are outside the scheme entirely and are the reason this class
/// exists at all: [primaryDeep] and [primaryMid], because one green cannot both
/// hold a hero and read at 7px on a light surface, and [warn], because a full
/// match is not an error and grey said "disabled".
abstract final class GoColors {
  // ---- the seed, kept for provenance only. Nothing derives from it. ----
  static const Color seed = Color(0xFF1B7A43);

  // ---- primary ----
  static const Color primary = Color(0xFF306A42);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFB3F1BF);
  static const Color onPrimaryContainer = Color(0xFF15512C);
  static const Color inversePrimary = Color(0xFF98D5A6);

  /// The crest hero and every filled control.
  static const Color primaryDeep = Color(0xFF123D24);

  /// The only green that reads correctly at small sizes on a light surface:
  /// capacity-bar fill, stat glyphs, the "next up" dot.
  static const Color primaryMid = Color(0xFF4E8A62);

  // ---- secondary ----
  static const Color secondary = Color(0xFF52634F);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFD2E8D3);
  static const Color onSecondaryContainer = Color(0xFF384B3C);

  // ---- tertiary: the reserve list, and nothing else ----
  static const Color tertiary = Color(0xFF38656A);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFBCEBF0);
  static const Color onTertiaryContainer = Color(0xFF1F4D52);

  // ---- warn: the one hue outside the Material scheme ----
  static const Color warn = Color(0xFFC9A227);
  static const Color warnContainer = Color(0xFFF6E7C4);
  static const Color onWarnContainer = Color(0xFF6E5410);

  // ---- error ----
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  // ---- surfaces: a green-tinted neutral ramp, never pure white behind text --
  static const Color surface = Color(0xFFF6FBF3);
  static const Color onSurface = Color(0xFF181D18);
  static const Color onSurfaceVariant = Color(0xFF414941);
  static const Color surfaceDim = Color(0xFFD7DBD3);
  static const Color surfaceBright = Color(0xFFF6FBF3);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF0F5ED);
  static const Color surfaceContainer = Color(0xFFEBF0E8);
  static const Color surfaceContainerHigh = Color(0xFFE5EAE2);
  static const Color surfaceContainerHighest = Color(0xFFDFE4DC);

  static const Color outline = Color(0xFF717970);
  static const Color outlineVariant = Color(0xFFC1C9BF);
  static const Color inverseSurface = Color(0xFF2D322C);
  static const Color onInverseSurface = Color(0xFFEEF2EA);
  static const Color scrim = Color(0xFF000000);

  // ---- semantic surfaces ----
  /// The sheet a screen's content sits on. Not [surface]: the page ground is a
  /// shade below the card ramp so a white card reads as lifted off it.
  static const Color bgPage = Color(0xFFEEF3EB);

  /// The crest hero block. Flat — the hero is never a gradient.
  ///
  /// [primary], not [primaryDeep]. This is the Light Club correction: the
  /// deeper green held the hero honestly enough but weighed the top of every
  /// place-screen down, and a product about turning up for a game should not
  /// open dark. The identity is unchanged — it is the same green the filled
  /// controls and the brand accents are drawn in, which is rather the point of
  /// it being this one.
  ///
  /// [primaryDeep] is not retired and has not been replaced anywhere else. It
  /// still carries the crest lettering, the hero's own filled button, the
  /// selected navigation destination and the open-match glyph, each of which
  /// wants the darker green *against* something — which is exactly what a
  /// background cannot be.
  static const Color bgHero = primary;

  /// Every card.
  static const Color surfaceCard = Color(0xFFFFFFFF);

  /// The light page that slides over the bottom of a hero.
  static const Color surfaceSheet = bgPage;

  // ---- match and registration status. The app uses exactly these. ----
  static const Color statusOpenBg = Color(0xFFDCEEDF);
  static const Color statusOpenFg = Color(0xFF12492A);
  static const Color statusFullBg = warnContainer;
  static const Color statusFullFg = onWarnContainer;
  static const Color statusCompletedBg = surfaceContainerHighest;
  static const Color statusCompletedFg = onSurfaceVariant;
  static const Color statusConfirmedFg = primary;
  static const Color statusReserveFg = tertiary;

  // ---- literals the components name directly ----
  /// The notification badge, and nothing else in the product.
  static const Color alert = Color(0xFFE4572E);

  /// Role chip and completed chip; the empty date tile.
  static const Color rowTintLight = Color(0xFFEDF1EB);
  static const Color rowTintDeep = Color(0xFFE4E9E2);

  /// The outlined button's edge.
  static const Color borderOutlined = Color(0xFFCBD8C9);

  /// The outlined card's edge — it marks the one next action on a screen.
  static const Color borderCardOutlined = Color(0xFFCBE3CF);

  /// Capacity bar: the places nobody has taken yet.
  static const Color capacityTrack = Color(0xFFDCE4DA);
  static const Color capacityTrackReserve = Color(0xFFE3EAE1);

  /// Capacity bar on a match that has been played.
  static const Color capacityCompleted = Color(0xFFA8B2A6);

  /// An unselected bottom-navigation destination.
  static const Color navUnselected = Color(0xFF8C978D);

  /// The disclosure glyph on a field row.
  static const Color chevron = Color(0xFFBFC9BE);

  /// Row dividers and the task bar's underline: [outlineVariant] at half
  /// strength. Not `const` — `withValues` is not — which is why it is `final`
  /// and read rather than inlined.
  static final Color hairline = outlineVariant.withValues(alpha: 0.5);

  /// The one gradient in the product, inside a community crest. The hero is
  /// flat and the rating panel is flat; there is no second gradient.
  static const LinearGradient gradientMark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryContainer, Color(0xFF9FDDAF)],
  );
}

/// The shadows.
///
/// `--elevation-card` is **two stops**, both nearly invisible alone: a contact
/// edge and a wide diffuse lift. Material's `elevation:` draws one, so a single
/// number cannot reproduce it — these are applied by a component's own
/// [BoxDecoration]. If the shadow reads *as* a shadow, it is wrong.
abstract final class Elevations {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color.fromRGBO(20, 40, 25, 0.06),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color.fromRGBO(20, 40, 25, 0.04),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> nav = [
    BoxShadow(
      color: Color.fromRGBO(18, 61, 36, 0.16),
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> sheet = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.08),
      blurRadius: 16,
      offset: Offset(0, -2),
    ),
  ];

  static const List<BoxShadow> snackbar = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.18),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> menu = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.14),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];
}

/// How big a glyph is, by where it sits.
///
/// Icons are drawn from the Material icon font the app already uses; the
/// direction changes their sizes, not their family. Filled variants are for a
/// selected navigation destination, a stat glyph and the confirmed tick — and
/// nothing else.
abstract final class IconSize {
  /// App bars and hero bars.
  static const double bar = 24;

  /// A bottom-navigation destination.
  static const double nav = 21;

  /// On a button, and a field row's leading glyph.
  static const double action = 19;

  /// A list row's leading glyph.
  static const double row = 18;

  /// A meta line — the clock and pin under a match title.
  static const double meta = 14;

  /// Inside a chip.
  static const double chip = 13;

  /// The glyph in an empty state's tinted disc.
  static const double emptyDisc = 32;

  /// A hero bar's back arrow, and a row's chevron.
  static const double navBack = 22;

  /// The reorder handle on the arrange list.
  static const double dragHandle = 20;
}

/// The Club layout measurements.
///
/// These sit beside [Gap] rather than inside it: [Gap] is the *scale* a layout
/// is built from, and these are the specific distances the direction fixes —
/// how far a card sits from the phone's edge, how tall a bar is, how much room
/// a floating navigation bar needs under a list.
abstract final class Layout {
  /// Card to phone edge. Narrower than the page margin: a card carries its own
  /// 16 inside, and 16 + 16 pushed the content too far in.
  static const double sheetGutter = 14;

  /// A card's own padding.
  static const double cardInner = 16;

  /// A hero's side padding.
  static const double heroInner = 18;

  /// Between two cards in a list.
  static const double cardGap = 10;

  /// A section heading: this much above the title, and [sectionBelow] under it.
  static const double sectionAbove = 18;
  static const double sectionBelow = 9;

  /// What every scrolling list needs at the end of it. The navigation bar
  /// floats over the content rather than closing the page off, so without this
  /// the last row is under it.
  static const double listBottom = 92;

  /// How far the sheet rides up over the hero. Negative: it is a margin, not a
  /// gap.
  static const double sheetOverlap = -22;

  /// The smallest thing worth aiming a thumb at.
  static const double tapMin = 44;

  /// A screen's primary action.
  static const double buttonHeight = 52;

  /// An action inside a card.
  static const double buttonHeightCompact = 44;

  /// An action inside a row.
  static const double buttonHeightSmall = 38;

  /// The floating navigation bar, and how far it sits off the bottom and sides.
  static const double navHeight = 58;
  static const double navInset = 14;

  /// A task screen's plain bar.
  static const double taskBarHeight = 54;

  /// The bar inside a hero.
  static const double heroBarHeight = 50;

  /// A hero is deliberately short: a bar row, an identity row, and at most one
  /// action row.
  static const double heroMinHeight = 150;
  static const double heroMaxHeight = 185;
}

/// How long things take, and how they get there.
///
/// Fast enough not to be waited on, which is the only thing an animation here
/// has to get right. Page transitions stay the platform's own.
abstract final class Motion {
  static const Duration instant = Duration(milliseconds: 80);

  /// Press and hover state changes.
  static const Duration fast = Duration(milliseconds: 150);

  /// Expansion, and sheets.
  static const Duration medium = Duration(milliseconds: 250);

  /// Route transitions.
  static const Duration page = Duration(milliseconds: 300);

  /// `cubic-bezier(.2, 0, 0, 1)`. [Curves.fastOutSlowIn] is the closest stock
  /// match and is what the direction names.
  static const Curve standard = Curves.fastOutSlowIn;
  static const Curve decelerate = Curves.decelerate;
  static const Curve accelerate = Curves.easeInCubic;

  /// Material state layers, not custom colours.
  static const double stateHover = 0.08;
  static const double stateFocus = 0.10;
  static const double statePressed = 0.12;
}

/// The type the Material scale has no slot for.
///
/// The Club ramp is a half-step scale — 10.5, 11.5, 12.5, 14.5, 15.5 — and
/// most of it maps onto [TextTheme]. What does not map lives here rather than
/// being written out again at each call site: a chip's label is one size in one
/// weight everywhere it appears, and the way to keep that true is for there to
/// be one of it.
///
/// These carry no colour. Colour is the caller's, because the same label is
/// white on a hero and [GoColors.onSurface] on a card.
abstract final class GoType {
  /// A status pill.
  static const TextStyle chip = TextStyle(
    fontSize: 11.5,
    height: 1.35,
    fontWeight: FontWeight.w700,
  );

  /// The square role marker. Set in capitals by the caller — a text style
  /// cannot transform its content.
  static const TextStyle roleChip = TextStyle(
    fontSize: 10.5,
    height: 1.6,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.63, // 0.06em at 10.5px
  );

  /// A field's label, and "NEXT UP". Capitals, set by the caller.
  ///
  /// The Material slot this would otherwise occupy — `labelSmall` — is shared
  /// with several places that are not micro-labels, so the tracking the
  /// direction asks for lives here instead of on the slot.
  static const TextStyle microLabel = TextStyle(
    fontSize: 11.5,
    height: 1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.69, // 0.06em at 11.5px
  );

  /// A match or community card's title.
  static const TextStyle cardTitle = TextStyle(
    fontSize: 15.5,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  /// The value on a task screen's field row.
  static const TextStyle fieldValue = TextStyle(
    fontSize: 15.5,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  /// The title on a hero's bar. Reversed out at 90% white by the caller.
  static const TextStyle heroBarTitle = TextStyle(
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w500,
  );

  /// A bottom-navigation label. The selected one is heavier; either the pill or
  /// the weight alone is easy to miss at a glance.
  static const TextStyle navLabelSelected = TextStyle(
    fontSize: 10.5,
    height: 1,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle navLabelUnselected = TextStyle(
    fontSize: 10.5,
    height: 1,
    fontWeight: FontWeight.w400,
  );

  /// A content tab. Underlined, not a Material indicator pill.
  static const TextStyle tabSelected = TextStyle(
    fontSize: 14,
    height: 1,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle tabUnselected = TextStyle(
    fontSize: 14,
    height: 1,
    fontWeight: FontWeight.w500,
  );
}
