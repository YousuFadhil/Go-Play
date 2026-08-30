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
///
/// This file is what the screens import, and it stays that way. The frozen Club
/// tokens the direction *adds* — the palette, the shadow stops, the icon scale,
/// the layout measurements, the motion constants — live in `tokens.dart`.
/// Where the two meet, this file refers there rather than restating a number:
/// a value that appears twice is a value that will eventually disagree with
/// itself.
library;

import 'tokens.dart';

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
/// The Club direction adds three that carry the product's shape language:
/// [control] for a button, a field or a bar, [card] for a card, and [sheet] for
/// the panel that slides over a hero. A card is rounder than a control and a
/// sheet is rounder than a card, so the three never read as the same object.
///
/// [sm], [md] and [lg] are the previous generation. They stay because the
/// screens still name them and migrating a screen is not this phase's work;
/// [sm] in particular is still exactly right for a form field. New code should
/// reach for [control], [card] and [sheet].
abstract final class Radii {
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 26;
  static const double pill = 999;

  /// Buttons, fields, the navigation bar, banners.
  static const double control = 16;

  /// Every card.
  static const double card = 20;

  /// The sheet over a hero, and bottom sheets.
  static const double sheet = 26;

  /// The date tile on a match card.
  static const double dateTile = 14;

  /// The square role marker. A role is a property of a person rather than a
  /// status of a thing, and the shape is what says so.
  static const double roleChip = 6;
}

/// The height every button is, so that a row of them lines up without anyone
/// having to check.
///
/// An alias for [Layout.buttonHeight], which is where the direction states it.
/// The name is kept because the screens already use it.
const double kButtonHeight = Layout.buttonHeight;

/// The page's side margin. Cards, headers and body copy all start here, which is
/// what gives a scrolling page a single left edge instead of a ragged one.
///
/// The Club direction moves a *card* closer to the phone's edge than this —
/// see [Layout.sheetGutter] — because a card carries its own padding inside.
/// Body copy that is not in a card still starts here.
const double kPageMargin = 16;
