# Tokens

The frozen values. `../HANDOFF.md` §A transcribes these into tables with usage
notes; this folder is the machine-readable form.

`../styles.css` is the entry point and is nothing but `@import` lines. Link that
one file and the whole closure is available as CSS custom properties on
`:root`. This folder is the only home of these values — nothing outside the
package redefines them.

| File | Covers |
|---|---|
| `colors.css` | Palette, semantic aliases, status colours, the single gradient |
| `typography.css` | Scale, weights, tracking, Arabic stack |
| `spacing.css` | Six-step gap scale, page margin, control heights, bar heights |
| `shape.css` | Radii, border widths, elevation |
| `motion.css` | Durations, easing, state-layer opacities |
| `fonts.css` | Webfont loading, incl. Material Symbols Outlined |
| `base.css` | Element defaults and the `.gp-icon` helper |

## Two extensions beyond the Material seed

The scheme is `ColorScheme.fromSeed(seedColor: Color(0xFF1B7A43))`, with three
values added deliberately. Declare them as named constants in Flutter rather
than trying to derive them:

- `--gp-primary-deep` `#123D24` — the crest hero and every filled control
- `--gp-primary-mid` `#4E8A62` — the only green that reads correctly at small
  sizes on a light surface
- `--gp-warn` `#C9A227` (+ container pair) — a **full** match. Grey said
  "disabled", and a full match is a healthy match.

## Icon sizing

Material Symbols Outlined. 24 in bars · 21 in bottom nav · 18–19 on buttons and
rows · 13–14 in meta lines and chips · 32 in an empty-state disc. Filled only
for a selected nav destination, stat glyphs, and the confirmed-registration
tick.
