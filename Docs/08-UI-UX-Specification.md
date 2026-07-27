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
| Members | Roster with roles; invite, change role, remove |
| Invitation landing | Which community a shared invitation offers. The only screen that works signed out |
| Community invitation | Owner and admin: share the link, copy the link, copy the join code, regenerate the code |
| Create / edit match | Owner and admin |
| Match details | Roster, reserve list, register and withdraw |
| Notifications | The user's own notifications |
| Administration | System Admin only: three tabs — users, communities, matches — each a search box, a list and a delete action |

There is no profile screen; it was removed from MVP scope.

## Invitations

There is one invitation and one identifier behind it: the community's join
code. The invitation screen offers three ways to pass it on — share the link,
copy the link, copy the code — because the link is the code in a URL and some
people will be told the code over the phone instead.

The landing screen names the community before asking for anything. Someone
without an account signs in from there and comes back to the same invitation
rather than losing it. Redeeming joins the community and nothing else: matches
are browsed afterwards, and players register themselves.

An organizer who has leaked a code regenerates it from the same screen. The
confirmation says the two things that matter: the current link and code stop
working immediately, and people already in the community stay members. The new
code and link replace the old ones in place, so they can be copied or shared
without reopening the screen.

Links are shared as `https://goplay.app/join/<code>` and opened today by
`goplay://join/<code>`. See the deferred deep linking note below for why both
exist. There is also a paste field, because not every messaging app makes a
link tappable.

## Deferred deep linking

The path is: tap a link, land on the invitation, join. When the app is not
installed the same code has to survive an install, which needs three things the
project does not have yet — a domain serving `/join/<code>` and
`assetlinks.json`, a Play Store listing, and an install referrer.

What exists today is the part that does not depend on them. `PendingInvite`
holds a code from any source until a screen consumes it, and it outlives sign-in
and registration. A code recovered after an install is `offer`ed to the same
holder and travels the same path as a tapped link, so nothing downstream needs
to know where it came from. The https intent filter is written in the manifest
and commented out with the reason: enabling it before the domain verifies would
show a chooser instead of opening the app.

## Join policy

Every community is visible to every signed-in user. Visibility and joining are
two questions, and only the second is configurable:

- **Open join** — anyone can join from the list.
- **Join by code** — the list still shows the community, and Join asks for the
  code instead of joining outright.

Default is open. The owner changes it from the community menu, next to sharing.
A code-required community carries a small key icon in the list, so the extra
step is not a surprise when the button asks.

The invitation link is unchanged under either policy: it carries the join code,
and a code is accepted whichever policy is set. That is what a code is — the
credential, not the policy.

## Time

Clock times follow the device, not the app: `formatTime` and `formatTimeRange`
in `core/time_format.dart` read the phone's own 12/24-hour preference through
`TimeOfDay.format`, so neither format is hardcoded. A range is wrapped in a
left-to-right isolate, because its order is start-then-end in every language
and an unisolated range reverses under Arabic — making a match look as though
it ended before it began.

## The match card

Shared by Home and the community's match list. The match's own name is the
title — bold, one line, ellipsised when it runs long — with location, date and
time, and total capacity below it. A match with no name keeps falling back to
its location as the title, and then the location is not repeated underneath.

The last line is playing capacity and nothing else — `starting_players`, the
number who actually take the field. Deliberately not `max_registration`: that
is starting players plus the global reserve allowance (DD-06), so it would
announce twelve players for a six-a-side match. How many have registered, and
who is on the reserve list, belong to the match screen: a list is for choosing
which match to open.

## Administration

Reached from a shield icon on Home that only a System Admin sees. Three lists,
each with a search field and a delete button, and nothing else — no dashboard,
no counts worth reading, no moderation. Find a record, remove it.

A System Admin row cannot be deleted: the button is disabled and the RPC refuses
too. Granting the role happens in SQL, outside the app.

Hiding the icon is a convenience. Every admin function checks `is_system_admin()`
server-side, so a client that got to the screen anyway would be refused.

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
