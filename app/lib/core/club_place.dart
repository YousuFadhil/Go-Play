/// The pieces a *place* is made of.
///
/// The frozen direction splits the product in two. A **place** is somewhere you
/// are — a community, a match, your own profile — and it opens with a flat
/// deep-green hero saying whose place it is, with the page sliding up over the
/// bottom of it. A **task** is something you are doing, and it gets a plain bar
/// and no hero at all. This file is the first half; the second is not this
/// phase's work.
///
/// Only what Community Details actually needs is here. There is no place-screen
/// shell, no navigation and no abstraction over the two kinds of screen —
/// those arrive when a second and third screen need them and can be written
/// against three real cases instead of one imagined one.
library;

import 'package:flutter/material.dart';

import 'app_header.dart';
import 'design.dart';
import 'tokens.dart';

/// The crest hero: a flat deep-green block that says whose place you are inside
/// before you read anything.
///
/// Flat, and that is the whole point — the direction has exactly one gradient
/// in the product and it is not this. Deliberately short, too: it carries a bar
/// row, an identity row, and at most a row of figures and a row of actions,
/// and then it stops.
class ClubHero extends StatelessWidget {
  const ClubHero({
    super.key,
    required this.bar,
    required this.identity,
    this.counts,
    this.action,
    this.ball = true,
    this.stadium = false,
  });

  /// The [ClubHeroBar] at the top: back, title, actions, all reversed out.
  final Widget bar;

  /// Who or what this place is. The crest and the name.
  final Widget identity;

  /// A row of figures under the identity.
  final Widget? counts;

  /// At most one row of actions.
  final Widget? action;

  /// The texture. A single very large, very faint ball, most of it outside the
  /// block — so it reads as a surface rather than as an icon somebody forgot to
  /// position. It is the Material glyph the app already draws from: no asset,
  /// no package, and nothing to load.
  final bool ball;

  /// Whether this hero is drawn as a ground rather than as a flat block.
  ///
  /// The approved Package 5 direction opens a player's record — and the public
  /// page of a match that has been played — on football rather than on a colour:
  /// a dark sky, floodlights, the far stand, and the pitch coming up to meet the
  /// page. It is [StadiumBackdrop], which is drawn from the product's own greens
  /// with a painter: no photograph, no licence, no asset to load, and the same
  /// picture on every device because nothing in it is random.
  ///
  /// Opt-in, and false everywhere it is not asked for: a community's hero is
  /// still the flat block the frozen direction specifies.
  final bool stadium;

  @override
  Widget build(BuildContext context) {
    // A flat block is still a flat `ColoredBox`: the frozen direction says the
    // hero is one colour and no gradient, and only the Package 5 grounds --
    // which are asked for by name -- are painted instead.
    final stack = Stack(
      children: [
        if (stadium) const Positioned.fill(child: StadiumBackdrop()),
        if (ball && !stadium)
          PositionedDirectional(
            // Mirrored under Arabic rather than pinned to a physical edge.
            // It is decoration, and decoration that ignores the reading
            // direction is the thing a reader notices about it.
            end: -44,
            top: -50,
            child: Icon(
              Icons.sports_soccer,
              size: 190,
              color: Colors.white.withValues(alpha: 0.055),
            ),
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Layout.heroInner,
              ),
              child: identity,
            ),
            if (counts != null)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Layout.heroInner,
                  Layout.sheetGutter,
                  Layout.heroInner,
                  0,
                ),
                child: counts,
              ),
            if (action != null)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Layout.heroInner,
                  Layout.sheetGutter,
                  Layout.heroInner,
                  0,
                ),
                child: action,
              ),
            // The hero's own bottom padding, less the distance the sheet
            // rides up over it. Flutter has no negative margin, and it does
            // not need one: the sheet's rounded top corners sit on a
            // deep-green scaffold, so the green shows through them exactly
            // as it does in the reference.
            const SizedBox(height: 30 + Layout.sheetOverlap),
          ],
        ),
      ],
    );

    return ClipRect(
      child: stadium
          ? DecoratedBox(
              decoration: const BoxDecoration(gradient: StadiumBackdrop.sky),
              child: stack,
            )
          : ColoredBox(color: GoColors.bgHero, child: stack),
    );
  }
}

/// A ground, drawn rather than photographed.
///
/// **Why a painter and not a picture.** The approved reference puts a stadium
/// behind the player. A photograph would be an asset to licence, a download on
/// every cold start and a different picture at every width; this is four shapes
/// in the product's own colours — so it costs nothing to load, scales to any
/// hero, mirrors nothing it should not, and renders identically on every device
/// and in every test.
///
/// What is drawn, from the top down: the night above the ground, two floodlight
/// glows, the far stand as a band of seats, and the pitch — a touchline, the
/// halfway line and the centre circle in perspective — rising to meet the page
/// that slides over it. Every value is a fraction of the block, so the same
/// composition holds at 320 points and at 480.
class StadiumBackdrop extends StatelessWidget {
  const StadiumBackdrop({super.key});

  /// The sky and the grass behind everything else. Dark at the top, because the
  /// identity is reversed out of it, and the product's own green where the page
  /// meets it — so the sheet slides off a colour it belongs to rather than off a
  /// photograph's edge.
  static const LinearGradient sky = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF07200F),
      Color(0xFF0E3720),
      GoColors.primaryDeep,
      GoColors.primary,
    ],
    stops: [0, 0.38, 0.72, 1],
  );

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _StadiumPainter());
}

class _StadiumPainter extends CustomPainter {
  const _StadiumPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Where the grass starts: the far touchline, low enough that the identity
    // sits against the stand and the pitch reads as distance.
    final horizon = h * 0.52;

    // --- the floodlights -----------------------------------------------------
    for (final x in [w * 0.16, w * 0.84]) {
      final centre = Offset(x, -h * 0.18);
      final radius = w * 0.58;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFFFFF).withValues(alpha: 0.16),
              const Color(0x00FFFFFF),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    // --- the far stand -------------------------------------------------------
    final standTop = horizon - h * 0.22;
    canvas.drawRect(
      Rect.fromLTRB(0, standTop, w, horizon),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x33000000)],
        ).createShader(Rect.fromLTRB(0, standTop, w, horizon)),
    );
    // Seats: three rows of short strokes, fading upwards. Regular on purpose —
    // a crowd read from this distance is a texture, not people.
    final seat = Paint()..strokeWidth = 2;
    for (var row = 0; row < 3; row++) {
      final y = standTop + h * 0.05 + row * h * 0.05;
      seat.color =
          const Color(0xFFFFFFFF).withValues(alpha: 0.05 - row * 0.012);
      for (var x = w * 0.02; x < w; x += w * 0.045) {
        canvas.drawLine(Offset(x, y), Offset(x + w * 0.022, y), seat);
      }
    }

    // --- the pitch -----------------------------------------------------------
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.18);

    // The touchline, and the halfway line running back from it.
    canvas.drawLine(Offset(0, horizon), Offset(w, horizon), line);
    canvas.drawLine(Offset(w / 2, horizon), Offset(w / 2, h), line);

    // The centre circle, flattened by the angle it is seen at.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, horizon + h * 0.30),
        width: w * 0.62,
        height: h * 0.42,
      ),
      line,
    );

    // A goal area at the far end, narrowing with distance.
    final boxPath = Path()
      ..moveTo(w * 0.30, horizon)
      ..lineTo(w * 0.24, horizon - h * 0.07)
      ..lineTo(w * 0.76, horizon - h * 0.07)
      ..lineTo(w * 0.70, horizon);
    canvas.drawPath(boxPath, line);

    // --- and the grass, lit unevenly ----------------------------------------
    canvas.drawRect(
      Rect.fromLTRB(0, horizon, w, h),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.6),
          radius: 0.9,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.07),
            const Color(0x00FFFFFF),
          ],
        ).createShader(Rect.fromLTRB(0, horizon, w, h)),
    );
  }

  @override
  bool shouldRepaint(covariant _StadiumPainter oldDelegate) => false;
}

/// The bar inside a [ClubHero]: back, title, actions — all reversed out.
class ClubHeroBar extends StatelessWidget {
  const ClubHeroBar({
    super.key,
    this.title,
    this.onBack,
    this.actions = const [],
    this.showCurrentUserMenu = false,
  });

  /// Often absent. On a community the name is the identity row below, and
  /// repeating it here would say the same thing twice in two sizes.
  final String? title;

  final VoidCallback? onBack;
  final List<Widget> actions;

  /// Whether the signed-in player's picture and menu close this bar.
  ///
  /// Opt-in, and false by default, because this bar serves both kinds of
  /// screen. A **place** you navigate to from the shell — Discover, Home,
  /// Communities — is where identity belongs: there is no back button to leave
  /// by, so without it a player has no way to reach their profile, their
  /// settings or sign-out from the screen the app opens on. A **task** screen
  /// arrived at from one of those already has a back button and its own
  /// actions, and putting a second way out beside them is noise.
  ///
  /// [AppHeader] makes the same guarantee unconditionally, which is why the
  /// task screens that still use it are not affected either way. What this adds
  /// is the same guarantee for the screens the Club redesign moved off it —
  /// where it was restored by hand on one and forgotten on the other two.
  ///
  /// Appended after [actions], the same order [AppHeader] uses, so a screen's
  /// own actions keep their position as they differ from screen to screen.
  final bool showCurrentUserMenu;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Layout.heroBarHeight,
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              iconSize: IconSize.navBack,
              color: Colors.white,
              icon: const BackButtonIcon(),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            )
          else
            const SizedBox(width: Layout.sheetGutter),
          Expanded(
            child: title == null
                ? const SizedBox.shrink()
                : Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoType.heroBarTitle.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
          ),
          ...actions,
          // White, like the back arrow and the title beside it. This bar
          // reverses everything out onto the hero, and the identity is the one
          // thing on it that was still taking its colour from a theme built for
          // light surfaces — so the player's own name was the least readable
          // word on the screen.
          if (showCurrentUserMenu)
            const CurrentUserMenu(foregroundColor: Colors.white),
        ],
      ),
    );
  }
}

/// A community's mark: its picture, or its initials, in a rounded square.
///
/// **Still not a circle, and that has not changed now that there is a picture.**
/// A circle is a person in this product and the two appear beside each other
/// constantly — a community crest above a roster of faces, a community card
/// beside a player's. The shape is what carries the difference, so a logo is
/// clipped into the rounded square rather than being allowed to bring its own
/// outline.
///
/// **Initials are not a placeholder.** A community with no picture is the
/// ordinary case, not an unfinished one: it shows its letters, exactly as every
/// community did before migration `0061`. The same is true of a picture that
/// will not load — a URL that 404s, a device with no connection — which falls
/// back to the letters rather than to a broken-image glyph.
class CommunityCrest extends StatelessWidget {
  const CommunityCrest({
    super.key,
    required this.name,
    this.logoUrl,
    this.size = 56,
    this.onHero = false,
  });

  final String name;

  /// The community's picture, when it has one. Null is the initials crest.
  final String? logoUrl;

  final double size;

  /// The translucent treatment for a crest sitting on the green hero.
  final bool onHero;

  /// The first letter of each of the first two words.
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => w.characters.first).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.34);
    final url = logoUrl;
    final hasLogo = url != null && url.isNotEmpty;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onHero
            ? Colors.white.withValues(alpha: 0.15)
            : GoColors.statusOpenBg,
        borderRadius: radius,
        border: onHero
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              )
            : null,
      ),
      // Clipped to the crest's own corners rather than given its own shape: the
      // picture takes the mark's outline, so a community with a logo and one
      // without are the same object on the page.
      child: hasLogo
          ? ClipRRect(
              borderRadius: radius,
              child: Image.network(
                url,
                width: size,
                height: size,
                // Cover, so a picture of any proportion fills the square
                // without being stretched into a different one.
                fit: BoxFit.cover,
                // A picture that will not load is a community with no picture,
                // which the product already knows how to draw. Never a broken
                // image, and never an empty box.
                errorBuilder: (context, error, stack) => _Initials(
                  name: name,
                  size: size,
                  onHero: onHero,
                ),
              ),
            )
          : _Initials(name: name, size: size, onHero: onHero),
    );
  }
}

/// The letters a community is known by, or a group glyph when it has no name to
/// take letters from.
///
/// Its own widget because it is drawn from two places now — as the crest itself,
/// and as what a picture falls back to when it fails — and those two must not be
/// allowed to differ.
class _Initials extends StatelessWidget {
  const _Initials({
    required this.name,
    required this.size,
    required this.onHero,
  });

  final String name;
  final double size;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final initials = CommunityCrest.initialsOf(name);
    final color = onHero ? Colors.white : GoColors.primaryDeep;

    if (initials.isEmpty) {
      return Icon(Icons.groups, size: size * 0.46, color: color);
    }
    return Text(
      initials,
      maxLines: 1,
      style: TextStyle(
        fontSize: size * 0.34,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: color,
      ),
    );
  }
}

/// One figure on a hero, and what it counts.
class ClubHeroCount extends StatelessWidget {
  const ClubHeroCount({super.key, required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // A bare figure among Arabic words is a neutral-first run, and one that
        // reaches two digits is long enough for the reordering to show.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            '$value',
            style: const TextStyle(
              fontSize: 17,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 5),
        // The figure always fits; the word beside it is what gives way. A
        // label that is squeezed shortens, so three counts stay on the one row
        // the direction puts them on rather than one of them overflowing the
        // hero.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

/// The light page that slides up over the bottom of a [ClubHero].
///
/// Static, and a plain container rather than a `DraggableScrollableSheet`: it
/// is where the page lives, not a panel a reader is meant to drag. Whatever
/// scrolls does so inside it.
class ClubSheet extends StatelessWidget {
  const ClubSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: GoColors.surfaceSheet,
        borderRadius: BorderRadiusDirectional.only(
          topStart: Radius.circular(Radii.sheet),
          topEnd: Radius.circular(Radii.sheet),
        ),
      ),
      child: child,
    );
  }
}

/// The two button treatments that only exist on a hero.
///
/// They live here rather than in the theme because a filled button on a green
/// block is not the same object as a filled button on a card — it is white, and
/// the theme has no way to know which surface it is being asked about.
abstract final class ClubHeroButtons {
  /// The primary action on a hero: white, with the deep green on it.
  static ButtonStyle get filled => FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: GoColors.primaryDeep,
        minimumSize: const Size(0, Layout.buttonHeightCompact),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      );

  /// The one beside it: the hero showing through, with an edge to hold it.
  static ButtonStyle get ghost => OutlinedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.16),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, Layout.buttonHeightCompact),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side:
            BorderSide(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      );
}
