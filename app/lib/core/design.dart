/// The measurements the interface is built from.
///
/// Before this file the app used whatever number the screen in front of you
/// happened to reach for: 4, 6, 8, 12, 14, 16, 20, 24 and 32 all appeared, often
/// two of them inside one card. That is what makes a layout read as assembled
/// rather than designed — not any single value being wrong, but no two screens
/// agreeing on what "a gap" is.
///
/// These are the only spacings and radii the app uses now. They are a scale, not
/// a palette: each step is meaningfully larger than the one below it, so picking
/// the wrong one is visible rather than merely different.
library;

/// Space between things.
///
///   xs  4  — inside a line: an icon and its label
///   sm  8  — between related lines
///   md 12  — inside a card, between its parts
///   lg 16  — a card's own padding, and the page's side margin
///   xl 24  — between a heading and what it introduces
///  xxl 32  — between one section and the next
abstract final class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// How round things are.
///
/// Three sizes only, and they carry meaning: [sm] is for something inside a
/// card, [md] for the card itself, [lg] for a panel that holds cards. [pill] is
/// for badges and chips, where the radius is the shape rather than a corner.
abstract final class Radii {
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 26;
  static const double pill = 999;
}

/// The height every button is, so that a row of them lines up without anyone
/// having to check.
const double kButtonHeight = 52;

/// The page's side margin. Cards, headers and body copy all start here, which is
/// what gives a scrolling page a single left edge instead of a ragged one.
const double kPageMargin = 16;
