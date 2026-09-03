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

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ColoredBox(
        color: GoColors.bgHero,
        child: Stack(
          children: [
            if (ball)
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
        ),
      ),
    );
  }
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

/// A community's mark: its initials in a rounded square.
///
/// Not a circle. A circle is a person in this product and the two appear beside
/// each other often enough that the shape has to carry the difference — the
/// schema has no logo column, so this *is* a community's crest rather than a
/// placeholder for one that has not been uploaded.
class CommunityCrest extends StatelessWidget {
  const CommunityCrest({
    super.key,
    required this.name,
    this.size = 56,
    this.onHero = false,
  });

  final String name;
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
    final initials = initialsOf(name);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onHero
            ? Colors.white.withValues(alpha: 0.15)
            : GoColors.statusOpenBg,
        borderRadius: BorderRadius.circular(size * 0.34),
        border: onHero
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              )
            : null,
      ),
      child: initials.isEmpty
          ? Icon(
              Icons.groups,
              size: size * 0.46,
              color: onHero ? Colors.white : GoColors.primaryDeep,
            )
          : Text(
              initials,
              maxLines: 1,
              style: TextStyle(
                fontSize: size * 0.34,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: onHero ? Colors.white : GoColors.primaryDeep,
              ),
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
