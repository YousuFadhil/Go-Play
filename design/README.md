# Go Play — design handoff package

**Club is the FINAL production design direction.** It is approved by the Product
Owner and frozen. Do not restyle it, do not propose alternatives, and do not
change product scope or functionality from what is described here.

Directions A and B were explored and rejected. They are **archived and
non-production** and are deliberately not included in this package; they live
outside the repository in the design project's `archive/explorations/` folder.
Nothing in this package derives from them, other than the row density and
Arabic tolerance that were merged into Club before approval.

## What is authoritative

| File | Role |
|---|---|
| **`HANDOFF.md`** | **The engineering source of truth.** Tokens with literal values, component inventory, screen inventory, navigation map, implementation notes, Arabic/RTL audit, responsive behaviour. Read this first and build from it. |
| **`ui_kits/mobile-app/index.html`** | **The visual reference build.** Open it in a browser. Where this and any prose disagree, the running build wins. |

This package is intended for **Flutter Web / PWA implementation**, mobile-first,
light theme only, Arabic default with English available, RTL throughout.

## Layout

```
design/
├── HANDOFF.md            the specification
├── README.md             this file
├── styles.css            entry point — @import list only
├── _ds_bundle.js         generated: the compiled components, loaded by the build
├── tokens/               frozen design tokens
├── components/           the component library (source + props + usage + visual card)
├── screens/              the twelve approved screens
└── ui_kits/mobile-app/   the reference build
```

This folder is the **canonical** home of the tokens, components and screens —
not a copy of them. There is exactly one version of every source file, and the
package resolves entirely within itself: extract `design/` on its own and
`ui_kits/mobile-app/index.html` still loads.

`_ds_bundle.js` is the one **generated** file — the components compiled into a
single script for the reference build. If you edit anything under
`components/`, regenerate it; do not hand-edit it. Everything else in here is
source.

### `tokens/`

Literal frozen values. Every number in `HANDOFF.md` §A comes from here.

| File | Covers |
|---|---|
| `colors.css` | Full palette, semantic aliases, match/registration status colours, the one gradient |
| `typography.css` | Type scale, weights, tracking, the Arabic font stack |
| `spacing.css` | The six-step gap scale plus layout measurements |
| `shape.css` | Radii and the two elevation tokens |
| `motion.css` | Durations, easing, interaction-state opacities |
| `fonts.css` | `@font-face` / webfont loading, incl. Material Symbols |
| `base.css` | Element defaults and the icon-font helper class |

### `components/`

Grouped by concern. Each component ships four files:

- `<Name>.jsx` — the reference implementation
- `<Name>.d.ts` — the props contract, with per-prop notes on intended use
- `<Name>.prompt.md` — what it is, when to use it, a usage example, the rules
- one `*.card.html` per folder — the visual reference showing every variant and state

| Group | Components |
|---|---|
| `core/` | Button, IconButton, Chip, Avatar, Icon, CountPill, Divider |
| `forms/` | TextField, SelectField, SegmentedControl, SwitchRow |
| `layout/` | Hero, HeroBar, Sheet, Card, SectionHeading, ListRow, BottomNav, AppHeader, FootNote |
| `feedback/` | EmptyState, ErrorState, LoadingState, Skeleton, Snackbar, Dialog, BottomSheet |
| `football/` | MatchCard, CommunityCard, CommunityLogo, DateTile, CapacityBar, ParticipantRow, MemberRow, StatTile, RatingHero |

Coverage of the required reference set:

| Required | Where |
|---|---|
| Buttons | `core/Button` (7 variants, 3 heights) |
| Cards | `layout/Card` (padded / unpadded / outlined) |
| List rows | `layout/ListRow`, `football/MemberRow`, `football/ParticipantRow` |
| Status chips | `core/Chip` (pill = status, square = role) |
| Registration states | `football/CapacityBar` + the registration card on `screens/MatchDetails.jsx` |
| Match states | `football/MatchCard`, `football/DateTile`, `core/Chip` |
| Segmented controls | `forms/SegmentedControl` |
| Tabs | Underlined pair in `screens/CommunityDetails.jsx` — content switching, distinct from SegmentedControl |
| Bottom navigation | `layout/BottomNav` (floating, 58px, three destinations) |
| Community hero | `layout/Hero`, `layout/HeroBar`, `football/CommunityLogo` |
| Segmented capacity indicator | `football/CapacityBar` |
| Place-screen shell | `layout/Hero` + `layout/Sheet` + `layout/BottomNav` |
| Task-screen shell | `TaskBar` + `TaskBody` in `screens/Shell.jsx` |
| Pinned commit action | `ActionBar` in `screens/Shell.jsx` |

`screens/Shell.jsx` holds the four kit-level pieces above. They are part of the
frozen system and must be reproduced; they live with the screens rather than in
`components/` because they are compositions, not primitives.

### `screens/`

One file per approved screen. All twelve are present:

| Screen | File | Shape |
|---|---|---|
| Discover | `App.jsx` (`DiscoverScreen`) | Place |
| Home | `Home.jsx` | Place |
| Communities | `App.jsx` (`CommunitiesScreen`) | Place |
| Community Details | `CommunityDetails.jsx` | Place |
| Match Details | `MatchDetails.jsx` | Place |
| Create Match | `CreateMatch.jsx` | Task |
| Member Management | `Members.jsx` | Task |
| Invitation — share | `Invite.jsx` (`mode="share"`) | Place |
| Invitation — landing | `Invite.jsx` (`mode="landing"`) | Place |
| Teams / Arrange Participants | `Teams.jsx` | Task |
| Result Entry | `Result.jsx` | Task |
| Notifications | `App.jsx` (`NotificationsScreen`) | Task |
| Profile | `Profile.jsx` | Place |

Three small screens live in `App.jsx` alongside the router because they are a
single section each. `data.js` holds the fixtures, including the deliberately
long Arabic set used for the RTL audit.

**Place** = crest hero + floating nav. **Task** = plain `TaskBar`, no nav, one
commit action pinned in an `ActionBar`. Preserve this distinction.

## Arabic / RTL and responsive review

`ui_kits/mobile-app/index.html` carries a review harness above the phone. It is
**not part of the product** — it exists so an engineer can reach any state
without a backend:

| Control | Reaches |
|---|---|
| Role | Owner / Admin / Player — regates every organizer control |
| State | Populated / Loading / Empty / Error (on Create Match, Error shows the validation state) |
| You | Confirmed / Reserve / Not in — the three registration states |
| Dir | EN / العربية — mirrors the layout **and** swaps in long Arabic fixtures |
| Width | 320 / 412 / 480 — the three verified widths |

Verified 30 August 2026: across all twelve screens at 320 / 412 / 480 in both
directions, no text truncates while unused horizontal space remains in its row.
Truncation occurs only at 320 where row width is genuinely exhausted.

## Business rules that the design encodes

- **Result Entry:** recorded goals must sum to the final score. The Save action
  is blocked and an inline error is shown until they agree. Approved rule —
  keep it.
- **Reserve:** joining a full match adds the player to the reserve list; the
  first reserve takes a withdrawn player's place.
- **Role gating:** an action a role cannot take is **absent**, never disabled.

## Running the reference build

Open `ui_kits/mobile-app/index.html` directly in a browser. It needs a network
connection on first load (React, Babel and the Material Symbols webfont come
from CDNs). Everything else is local to this folder.

## Scope

Out of scope by direction: the System Admin surfaces, dark theme, and any
desktop layout. Do not begin Flutter implementation from this README — read
`HANDOFF.md`.
