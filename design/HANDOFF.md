# Go Play — Flutter implementation handoff

**Status: FROZEN.** The Club direction is approved and final. This document is the
specification for reproducing it in Flutter. Where this document and the running
kit disagree, `ui_kits/mobile-app/index.html` wins — open it and use the review
harness (role / state / registration / direction / width) to reach any state
described here.

Target: mobile-first Flutter Web / PWA, light theme only, Arabic default with
English available, RTL throughout.

---

## A. Design tokens

Source of truth: `tokens/*.css`. Values below are literal — do not round them to
a 4/8-px grid or to a Material default.

### Colour

| Token | Hex | Use |
|---|---|---|
| `--gp-primary-deep` | `#123D24` | Crest hero, filled buttons, rating panel, selected-tab underline, Team A |
| `--gp-primary` | `#306A42` | Community name on a card, text buttons, section actions, links |
| `--gp-primary-mid` | `#4E8A62` | Capacity-bar fill, stat glyphs, "next up" dot — the only green that holds at small sizes on light |
| `--gp-primary-container` | `#B3F1BF` | — (Material lineage; prefer `--status-open-bg`) |
| `--gp-on-primary-container` | `#15512C` | Crest initials |
| `--status-open-bg` / `-fg` | `#DCEEDF` / `#12492A` | Open chip, tonal button, crest background, nav pill, selected row |
| `--gp-warn` | `#C9A227` | Full-capacity bar fill |
| `--gp-warn-container` / `--gp-on-warn-container` | `#F6E7C4` / `#6E5410` | Full chip, full date tile |
| `--gp-tertiary` | `#38656A` | Reserve — bar segments, reserve subtitle, Team B |
| `--gp-tertiary-container` / `--gp-on-tertiary-container` | `#BCEBF0` / `#1F4D52` | Reserve chip |
| `--gp-error` | `#BA1A1A` | Destructive button, field error border/label |
| `--gp-error-container` / `--gp-on-error-container` | `#FFDAD6` / `#93000A` | Error banner, failed-read disc |
| `--bg-page` / `--surface-sheet` | `#EEF3EB` | The sheet a screen's content sits on |
| `--bg-hero` | `#123D24` | Crest hero block |
| `--surface-card` | `#FFFFFF` | Every card |
| `--gp-on-surface` | `#181D18` | Titles and body |
| `--gp-on-surface-variant` | `#414941` | Secondary lines |
| `--gp-outline` | `#717970` | Captions, micro-labels, disabled glyphs |
| `--border-hairline` | `outlineVariant` at 50% | Row dividers, task-bar underline |
| Alert orange | `#E4572E` | Notification badge — this and nothing else |
| Neutral row tints | `#EDF1EB`, `#E4E9E2` | Role chip, played chip, empty date tile |

Two extensions beyond `ColorScheme.fromSeed(0xFF1B7A43)`: `--gp-primary-deep` /
`--gp-primary-mid`, and the `--gp-warn` amber. Declare them as named constants
rather than deriving them.

**Gradient:** exactly one, `--gradient-mark`, inside a community crest
(`#B3F1BF` → `#9FDDAF`, vertical). Everything else is a flat fill. The hero is
**not** a gradient.

### Typography

Roboto, with a Naskh fallback for Arabic. Sizes are Material's; the two edits are
that headings are `w700` with negative tracking, and body runs at `1.45`.

| Role | Size / line-height / weight | Tracking | Where |
|---|---|---|---|
| Hero title | 22–24 / 1.2 / 700 | −0.7 to −0.8 | Community name, "Hello, {name}", match title |
| Screen title (task) | 17 / 1.25 / 700 | −0.2 | TaskBar |
| Hero bar title | 16 / 1.2 / 500 | 0 | HeroBar (90% opacity white) |
| Section heading | 16.5 / 1.25 / 700 | −0.3 | SectionHeading |
| Card title | 15.5 / 1.3 / 700 | −0.2 | Match card, community card |
| Row title | 14–14.5 / 1.3 / 600 | 0 | Member, participant, list rows |
| Body | 15 / 1.35 / 400 | 0 | Field values, list-row primary |
| Secondary | 12.5 / 1.4 / 400 | 0 | Meta lines, descriptions |
| Caption | 12 / 1.3 / 400 | 0 | Row subtitles, counts |
| Micro-label | 11.5 / 1 / 600 UPPER | +0.06em | Field labels, "NEXT UP" |
| Button | 14.5 / 1 / 700 | 0 | All buttons |
| Chip | 11.5 / 1.35 / 700 | 0 | Status pills |
| Role chip | 10.5 / 1.6 / 700 UPPER | +0.06em | Square role markers |
| Nav label | 10.5 / 1 / 400–600 | 0 | Bottom navigation |
| Big numeral | 30–38 / 1 / 700 | −1.3 to −1.6 | Rating, score, starting-players stepper |

### Spacing

Six steps: **4 / 8 / 12 / 16 / 24 / 32**.

| Measurement | Value |
|---|---|
| Sheet gutter (card to phone edge) | 14 |
| Card inner padding | 16 |
| Hero inner padding | 18 |
| Gap between cards in a list | 9–10 |
| Section heading | 18 above, 9 below |
| Bottom padding under a scrolling list | **92** (the nav floats over it) |

### Radii

| Token | Value | Applies to |
|---|---|---|
| `--radius-control` | 16 | Buttons, fields, nav bar, banners |
| `--radius-card` | 20 | Every card |
| `--radius-sheet` | 26 | The sheet over a hero; bottom sheets |
| `--radius-crest` | 34% | Community crest (a **rounded square**) |
| Date tile | 14 | — |
| Pill | 999 | Status chips |
| Role chip | 6 | Square role markers |
| Avatar | 50% | People — never a square |

### Shadows

```
--elevation-card: 0 1px 2px rgba(20,40,25,.06), 0 6px 16px rgba(20,40,25,.04)
--elevation-nav:  0 6px 20px rgba(18,61,36,.16)
--elevation-sheet: 0 -2px 16px rgba(0,0,0,.08)
--elevation-snackbar: 0 4px 12px rgba(0,0,0,.18)
```

`--elevation-card` is two stops, both nearly invisible alone. In Flutter use two
`BoxShadow`s — a single `elevation:` will not reproduce it. If the shadow reads
*as* a shadow it is wrong.

### Motion

150ms state, 250ms sheets, ~300ms routes, `cubic-bezier(.2,0,0,1)`
(`Curves.fastOutSlowIn` is the closest stock match). Page transitions stay the
platform's own. Nothing bounces or scales on press.

### Icons

Material Symbols Outlined — the same family `Icons.*` already draws from.
24 in bars · 21 in nav · 18–19 on buttons and rows · 13–14 in meta lines and
chips · 32 in an empty-state disc. Filled **only** for a selected nav
destination, stat glyphs, and the confirmed-registration tick.

---

## B. Component inventory

`window.GoPlayDesignSystem_984b89.*`; source in `components/<group>/`. Each has a
sibling `.d.ts` (props) and `.prompt.md` (what and when).

### core

| Component | Variants | States | Usage |
|---|---|---|---|
| `Button` | filled · tonal · outlined · text · onHero · ghost · danger | default / hover (`brightness .94`) / disabled (.38) / loading (spinner replaces label) | **One filled per screen.** Heights 52 (screen primary) / 44 (in a card) / 38 (in a row). On the hero the pair is always `onHero` + `ghost`. |
| `IconButton` | plain · `onHero` | with/without badge | 44px target. Badge is alert orange, `dir="ltr"`. |
| `Chip` | open · full · completed · reserve · neutral · danger · onHero · role | static | Pill = a thing's **status**. `square` = a person's **role**. Never interactive. |
| `Avatar` | accent · neutral | image / initials / glyph | Circle. 30 bar · 34–38 rows · 62 profile. |
| `Icon` | fill on/off | — | Material Symbols wrapper. |
| `CountPill`, `Divider` | — | — | Supporting. |

### forms

| Component | Variants | States | Usage |
|---|---|---|---|
| `TextField` | single · multiline | rest / focus (2px primary border) / error / disabled / with counter | Label stays above the value. Focus is a border and nothing else. |
| `SelectField` | native select · picker (`onClick`) | rest / error / disabled | Date and time never take typed input. |
| `SegmentedControl` | full width · inline | one selected | Switches a **filter or view** (statistics period, Teams/Arrange). |
| `SwitchRow` | — | on / off / disabled | Always carries a subtitle saying what it does. |

Underlined tabs (Community's Matches / Played) switch **content**, not a filter,
and are built in the screen — 2.5px `--gp-primary-deep` underline, 700 when
selected.

### layout

| Component | Variants | Usage |
|---|---|---|
| `Hero` / `HeroBar` / `Sheet` | ball texture on/off | The place-screen shell. Hero is 150–185px: bar row + identity row + at most one action row. |
| `Card` | padded · unpadded · `outlined` | White, 20, `--elevation-card`. `outlined` (1.5px `#CBE3CF`) marks the **one** next action per screen. |
| `SectionHeading` | with count · with action | 18/9 padding; count inline after a middot. |
| `ListRow` | icon · custom leading · chevron · danger | Rows live inside an unpadded Card and divide with a hairline. |
| `BottomNav` | floating (default) · docked | 58px, 14 off the bottom, three destinations, always labelled. |
| `AppHeader`, `FootNote` | — | `AppHeader` is the docked alternative to `HeroBar`. |

### feedback

`EmptyState` (neutral / accent tone) · `ErrorState` (retry is **outlined**, never
filled) · `LoadingState` · `Skeleton` · `Snackbar` · `Dialog` (destructive
variant; cancel word is "Back") · `BottomSheet`.

### football

| Component | Notes |
|---|---|
| `MatchCard` | Date tile + title + status chip + community crest line + meta + `CapacityBar`. **No action button** — the card opens the match. |
| `CommunityCard` | Crest, name, role chip, description, two counts. The row is the action. |
| `CommunityLogo` | Rounded square, initials. 17–22 inline · 38–46 list · 56–68 hero. |
| `DateTile` | 50×56. Green when open, amber when full, tick when played. |
| `CapacityBar` | Segmented, one segment per place; reserve is a separate teal run after a 6px gap. Replaces every progress ring. |
| `ParticipantRow` | Position tag on the end; a guest is always "Professional (name)". |
| `MemberRow` | Role + position on one line; trailing column only for a caller who can act. |
| `StatTile` | Three per row, six maximum. |
| `RatingHero` | Flat deep green, optional 6-bar form sparkline. |

Removed and not to be reintroduced: `StatCard`, `HeroBanner`.

---

## C. Screen inventory

| Screen | Shape | Major sections | Components | Primary CTA | Role-specific | States |
|---|---|---|---|---|---|---|
| **Discover** | Place | Brand hero · Open matches · Communities | Hero, MatchCard, ListRow, CommunityLogo, Button | Open (per community) | — | loading, empty, error |
| **Home** | Place | Greeting hero · Next-up card · This week | Hero, Card(outlined), CapacityBar, MatchCard, SectionHeading | Open match | — | loading, empty, error; next-up absent when no upcoming match |
| **Communities** | Place | Hero + Create/Join · Community list | Hero, Button, CommunityLogo, Chip | Create | — | empty |
| **Community Details** | Place | Crest hero · counts · action row · Matches/Played tabs · Members preview | Hero, Button, MatchCard, MemberRow, SectionHeading, BottomSheet | Create match (organizer) / Join community (visitor) | Create + Invite: Admin, Owner. Manage: Admin, Owner. Joining policy + Delete: Owner | loading, empty, error; tab empty |
| **Match Details** | Place | Crest hero + facts · registration card · organizer actions · Starting · Reserve | Hero, Card(outlined), CapacityBar, Button, ParticipantRow, Chip, Dialog | Join match / Join the reserve list / Withdraw | Teams + Result + Arrange: Admin, Owner | open, full, played; not-registered, confirmed, reserve; loading, error; empty reserve |
| **Create Match** | Task | Community line · title+location · date/times · starting-players stepper · note | TaskBar, RowGroup, FieldRow, CapacityBar, ActionBar, Button | Create match | Screen only reachable by Admin/Owner | validation error (blocks Save), saving |
| **Member Management** | Task | Search · member list · role note | TaskBar, MemberRow, Chip, IconButton, BottomSheet | — (per-row sheet) | Trailing actions: organizers only. Transfer ownership / change an admin: Owner | empty, no-search-results, permission-restricted (read-only for Player) |
| **Invitation — share** | Place | Crest hero · join code · link + policy rows · regenerate | Hero, Card, RowGroup, Button | Share link | Organizers only | copied (snackbar), regenerated |
| **Invitation — landing** | Place | Centred crest hero · Join · What is coming up | Hero, Button, MatchCard | Join community | — | — |
| **Teams / Arrange** | Task | Segmented switch · Team A / Team B panels **or** Starting + Reserve reorder | TaskBar, SegmentedControl, ParticipantRow, Button | Regenerate / Share (Teams); implicit save (Arrange) | Organizers only | selection state, empty roster |
| **Result Entry** | Task | Scoreboard steppers · goalscorers · player of the match | TaskBar, RowGroup, Avatar, Chip, ActionBar | Save result | Organizers only | validation mismatch (blocks Save) |
| **Notifications** | Task | Grouped list | TaskBar, RowGroup | Mark all read | — | read / unread, empty |
| **Profile** | Place | Identity hero + rating · period control · Record · Form · Communities · Account | Hero, SegmentedControl, StatTile, RatingHero, ListRow | — | — | period switch, empty record |

**Place** = crest hero + floating nav; you can leave it by tapping elsewhere.
**Task** = plain `TaskBar`, no nav, one commit action pinned in an `ActionBar`;
you finish it or back out.

---

## D. Navigation map

```
Bottom navigation (3 roots, always present on a place)
├── Discover ──► Community Details
│                Match Details
├── Home ──────► Match Details ──► Teams / Arrange      (organizer)
│                              └─► Result Entry          (organizer)
│                Notifications                            [task]
│                Profile ──► Community Details
└── Communities ► Community Details
                  ├─► Create Match                        [task, organizer]
                  ├─► Member Management                   [task, organizer]
                  ├─► Invitation (share)                  [organizer]
                  └─► Match Details

Invitation (landing)  ──► Community Details        (entered from a link, outside the nav)
```

Rules:
- A task pushes over the current place and returns to it. Create Match returns to
  the community it was started from, not to a nav root.
- The nav tab stays lit by lineage: everything under a community keeps
  **Communities** selected; Match Details keeps **Home**.
- Match Details is reachable from three places and always looks the same.
- Back from a task never commits. Only the `ActionBar` button commits.

---

## E. Implementation notes

1. **Two shadow stops, not one.** `--elevation-card` cannot be expressed as a
   Material `elevation:` value. Use an explicit two-`BoxShadow` decoration.
2. **The hero is flat.** No `LinearGradient` on `--bg-hero`. The single gradient
   in the product is inside the community crest.
3. **The nav floats.** It is not a `BottomNavigationBar` in a `Scaffold` slot —
   it is a positioned bar over the content, and every scrolling list needs 92px
   of trailing padding so its last row clears it.
4. **The sheet overlaps the hero by 22px** with a 26px top radius. Build it as a
   negative-margin container, not as a `DraggableScrollableSheet`.
5. **Square crest, circle avatar.** They appear side by side; the shape is the
   only thing distinguishing a community from a person.
6. **Role gating removes controls.** Never render a disabled organizer action for
   a player — a disabled control still advertises the feature and implies the
   reader is the problem.
7. **Capacity is segmented, not continuous.** `LinearProgressIndicator` is wrong:
   build a `Row` of flex-1 bars with a 6px gap before the reserve run.
8. **Logical directions throughout.** `EdgeInsetsDirectional`,
   `AlignmentDirectional`, `PositionedDirectional`. No `left` / `right`.
9. **Isolate neutral-first runs.** Time ranges, scores, join codes, `6/12`
   ratios and URLs must not be reordered by an RTL paragraph — wrap them in
   `Directionality(textDirection: TextDirection.ltr, …)` or the
   `\\u2066…\\u2069` isolate pair. This is already handled in the kit; the same
   spots need it in Flutter.
10. **Truncate, never reflow.** Every name, title and meta line is
    `maxLines: 1, overflow: TextOverflow.ellipsis`. A long Arabic name must
    shorten, not push the row taller.
11. **Buttons never wrap.** `softWrap: false` on button labels; an Arabic label
    that does not fit shrinks the neighbouring control, not the button.
12. **No dark theme.** Light only, by decision.

---

## F. Arabic / RTL readiness

Audited against deliberately long Arabic fixtures (`window.GP_DATA_AR` in
`ui_kits/mobile-app/data.js`) at 320, 412 and 480px. Switch the harness to
**العربية** to reproduce.

| Checked | Result |
|---|---|
| Long person names (e.g. `يوسف بن عبدالله الفاضل الحارثي`) | Truncate with ellipsis in every row; no row grows |
| Long community names | Hero title truncates; crest and role chip hold position |
| Long match titles | Card title truncates on one line above the meta run |
| RTL mirroring | Full mirror — heroes, rows, nav, sheets, tabs, steppers |
| Time ranges / scores / codes / ratios | Isolated LTR; `17:25 – 18:35` and `6/12` never reverse |
| Truncation | Applied at every text node that can receive user content |
| Button width | Labels are `nowrap`; the row shares width by flex, not by wrapping |
| Chips | `nowrap`; status and role chips keep their shapes |
| List rows | Trailing column is `flex: 0 0 auto` so it survives a long name |
| Navigation | Labels fit at 320px in both languages |
| Form labels | Micro-labels sit above their values, so length never squeezes the field |
| Mixed English inside Arabic | `unicode-bidi: plaintext` on message text; punctuation stays at the right end |

**Chrome strings in the harness stay English.** The app already ships
`app_ar.arb`; what this pass proves is that the *layout* survives Arabic content.

## G. Responsive behaviour

Mobile-first. One column at every width — there is no desktop product.

| Width | Behaviour |
|---|---|
| **320 (narrow)** | Everything holds; the meta run truncates the location first, then the title. Hero stats stay on one row. Nav labels fit. Nothing is hidden. |
| **360–412 (normal)** | The reference. All measurements in this document are authored at 412. |
| **480 (small tablet)** | Layout does **not** re-flow into columns. Cap the content column at ~480 and centre it; the extra width goes to margins, not to more content per row. |

Stat tiles stay three per row at every width. Do not introduce a two-column
match list.

---

## H. Sign-off

- Visual system frozen: colours, type, spacing, radii, shadows, icons, buttons,
  fields, cards, rows, chips, tabs, segmented controls, nav, hero, capacity.
- All twelve user-facing screens built and reachable in the kit.
- Required states covered: loading, empty, populated, open / full / played,
  confirmed / reserve / not registered, validation error, permission-restricted,
  network error.
- Roles: Owner, Admin, Player — one visual theme, gated by presence.
- Arabic and RTL audited at three widths.
- No System Admin surfaces (out of scope, by direction).

**Ready for engineering implementation.**
