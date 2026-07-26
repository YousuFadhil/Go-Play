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
| Create / edit match | Owner and admin |
| Match details | Roster, reserve list, register and withdraw |
| Notifications | The user's own notifications |

There is no profile screen; it was removed from MVP scope.

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
