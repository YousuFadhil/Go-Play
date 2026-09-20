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
/// The green is the app's own seed colour, dark enough to sit behind white
/// text.
abstract final class ShareCardPalette {
  /// The top of the card's gradient.
  static const pitch = Color(0xFF07341C);

  /// The bottom of it.
  static const pitchDeep = Color(0xFF04180E);

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

  /// The seed a card pins its `ColorScheme` to before drawing anything that
  /// takes colours from one — an avatar's fallback disc, for instance.
  ///
  /// Without pinning, the same player composed in light mode and in dark mode
  /// produces two different pictures of one record.
  static const avatarSeed = Color(0xFF1B7A43);
}
