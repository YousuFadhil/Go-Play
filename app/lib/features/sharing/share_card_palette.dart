import 'dart:ui' show Color;

/// The colours every share card is drawn in.
///
/// **Stated here rather than taken from the app theme, and that is the whole
/// reason this exists.** A share card is a picture that leaves the phone: it
/// must not change because the reader has dark mode on, so it cannot read
/// `Theme.of(context)` for a colour. Each card having its own copy of the four
/// values would make "the same visual language" something four files remember
/// rather than something one file states — and the second card is exactly when
/// that stops being hypothetical.
///
/// The green is the app's own, deep enough to sit behind white text (white on
/// [pitch] is 5.3:1).
abstract final class ShareCardPalette {
  /// The top of the card's gradient.
  static const pitch = Color(0xFF1E7B45);

  /// The very top of a poster-style card, a shade deeper than [pitch].
  static const pitchTop = Color(0xFF176B3A);

  /// The bottom of it.
  static const pitchDeep = Color(0xFF145A32);

  /// The one accent: rules, badges, the disc behind a player's face.
  static const accent = Color(0xFF3DDC84);

  /// Text.
  static const ink = Color(0xFFFFFFFF);

  /// Text that supports rather than states — a label under a figure, the
  /// wordmark at the foot.
  static const inkMuted = Color(0xB3FFFFFF);

  /// The award mark behind a trophy, and nothing else on a card.
  ///
  /// The product's own warn hue and its ink (`GoColors.warn`,
  /// `GoColors.onWarnContainer`), restated here for the reason every other
  /// value on this class is: a card must not read a colour off the reader's
  /// theme. It is the one amber the product has, and a Recent Highlight is
  /// drawn on it on screen as well as on a card.
  static const award = Color(0xFFC9A227);
  static const onAward = Color(0xFF3A2C05);

  /// The white sheet a poster-style card puts its content on, and the inks and
  /// tints that go on it. Stated here for the same reason as the rest: a card
  /// must not read a colour off the reader's theme.
  static const paper = Color(0xFFFFFFFF);
  static const paperInk = Color(0xFF181D18);
  static const paperMuted = Color(0xFF717970);
  static const paperTint = Color(0xFFF3F8F1);
  static const paperLine = Color(0x80C1C9BF);

  /// The disc behind a face with no picture, and the three results.
  static const avatarFill = Color(0xFF2E6B45);
  static const resultWin = Color(0xFF1E7B45);
  static const resultLoss = Color(0xFFBA1A1A);
  static const resultDraw = Color(0xFFC3C9C1);
  static const onResultDraw = Color(0xFF414941);

  /// The seed a card pins its `ColorScheme` to before drawing anything that
  /// takes colours from one — an avatar's fallback disc, for instance.
  ///
  /// Without pinning, the same player composed in light mode and in dark mode
  /// produces two different pictures of one record.
  static const avatarSeed = Color(0xFF1B7A43);
}
