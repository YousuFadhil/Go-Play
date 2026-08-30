# Components

The frozen Go Play component set. See `../HANDOFF.md` §B for variants, states
and usage rules in table form.

Each component ships four files:

- `<Name>.jsx` — reference implementation. Styling is inline and references the
  CSS custom properties in `../tokens/`; there are no CSS classes to port.
- `<Name>.d.ts` — the props contract. The per-prop comments carry the design
  intent (when to use a variant, what a prop must never be used for).
- `<Name>.prompt.md` — what it is, when to reach for it, a usage example, and
  the rules that keep it consistent.
- `*.card.html` — one per folder. Open it in a browser to see every variant and
  state rendered together.

The `.jsx` files are a specification of appearance and behaviour, not code to
port. Read the values out of them; build the widget in Flutter.

## Rules that cross the whole set

1. **One filled button per screen.** If two actions look equally important, one
   is outlined.
2. **Pill chip = a thing's status. Square chip = a person's role.** They appear
   together; the shape is what distinguishes them.
3. **Square crest = a community. Circle avatar = a person.** Same reasoning.
4. **Cards carry `--elevation-card`, which is two nearly invisible shadow
   stops.** Not a Material `elevation:`. If the shadow reads as a shadow, it is
   wrong.
5. **Capacity is a segmented bar, never a ring or a `LinearProgressIndicator`.**
   The reserve allowance is a separate teal run after a 6px gap.
6. **Role gating removes controls; it never disables them.**
7. **Every user-content text node truncates on one line.** A long Arabic name
   shortens — it never grows the row.

Removed from the system and not to be reintroduced: `StatCard`, `HeroBanner`.
