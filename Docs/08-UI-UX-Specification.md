# UI/UX Specification

> Updated for the Community-first architecture (`v0.4.0-mvp`).

## Design principles

- Mobile first.
- Arabic by default, English available, RTL throughout.
- Match-centric: the match is what a player opens the app for.
- Show, then explain. Where a role lacks a permission, the control stays visible
  with a localized explanation rather than silently disappearing — a player who
  never sees a button cannot learn that admins have one.

## Screens

| Screen | Purpose |
|---|---|
| Login, Register | Email and password |
| Home | Greeting, upcoming matches across the user's communities, notifications |
| Communities | The user's communities; create, or join by code |
| Community details | Matches in that community, plus the management entry points the caller's role allows |
| Community settings | Owner only: edit, transfer ownership, delete |
| Members | Roster with roles; invite, change role, remove |
| Invitations | Pending invitations for the signed-in user; accept or decline |
| Invitation landing | What a shared invitation offers — community, and the match if one is attached. The only screen that works signed out |
| Invitation links | Owner and admin: the live links for a community, each with copy and revoke |
| Create / edit match | Owner and admin |
| Match details | Roster, reserve list, register and withdraw |
| Notifications | The user's own notifications |

There is no profile screen; it was removed from MVP scope.

## Invitations

Two things are shared, and they read differently. A directed invitation reaches
one named player and can offer the admin role. A **link** is a bearer token that
anyone may open, so it only ever grants player.

The landing screen shows the community, and for a match invitation its title,
date, time and places left, before asking for anything. Someone without an
account signs in from there and comes back to the same invitation rather than
losing it.

Two things it must say plainly, because the alternative is a misled player:

- when the starting places are gone, that joining now means the reserve list —
  said before the button, not after;
- when registration fails but joining succeeded, what actually happened and why
  (the match filled, it locked, it clashes with another) — the person is a
  member either way, so the screen goes to the community rather than pretending.

Links travel as `goplay://invite/<token>`. Organizers copy one from the
community screen or from match management; there is also a paste field, because
not every messaging app makes a custom-scheme link tappable.

Organizers can see what they have shared and take a link back, from the same
menu as sharing. Only live links are listed — revoking is how an organizer says
they are finished with one. A link that ended because its match started or was
deleted is shown greyed with the reason, and cannot be copied: spreading a link
that will not open helps nobody.

## Role-dependent UI

Every management control resolves against the caller's role in that community,
using the same cumulative rules the database enforces. The UI is a convenience,
never the boundary: a request that gets past a hidden button is still refused by
RLS and again inside the RPC.

## Known gap

There is no UI entry point for leaving a community. The rule (PD-12) is
implemented and tested server-side, and its strings were removed in the
`v0.4.0-mvp` cleanup as unused. Adding the entry point is a product decision,
recorded in `11-Future-Backlog.md`.
