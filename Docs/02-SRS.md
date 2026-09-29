# Software Requirements Specification (SRS)

> Updated for the Community-first architecture (`v0.4.0-mvp`).

## Functional requirements

- Registration and login with email and password
- Community management: create, join, change the join policy, delete
- Membership: change role, transfer ownership, remove a member, leave
- One invitation system: the community's join code. It is shared as a link or
  read out as a code, and both carry the same identifier. Opening a link shows
  which community is offered without an account; redeeming it joins that
  community
- Nearby discovery: a Wilayat (one of the 63) is the only location unit. A
  community has one, required when it is created in the app and changeable only
  by its owner; a player may set a private Default Location; Discover has a
  session-only Near override, and a guest's choice stays on the device
- Match management: create (with a required title), edit, delete, manage the
  roster
- Match registration with a reserve list and automatic promotion
- In-app notifications
- A System Admin role, independent of community roles, with three management
  sections: users, communities and matches. View, search and delete only.

## Business rules

- The first registrations take the starting places; the rest join the reserve
  list in registration order.
- When a confirmed place frees up, the first reserve is promoted and told.
- Nobody may hold registrations in two live matches whose times overlap.
- Withdrawing removes the registration, which is what allows registering again.
- A match is locked from its scheduled start until it ends: no registration,
  no withdrawal, no edits, no roster changes.
- A match is completed once its end time passes; there is no scheduler.
- Maximum registration is the starting players plus one global reserve
  allowance.
- A match may be deleted at any point before it is completed.
- Removing a member also withdraws them from every match in that community,
  promoting reserves as usual.
- Deleting a community removes everything belonging to it.
- Exactly one owner per community, always.
- Every community is visible to every signed-in user. What differs is the join
  policy: OPEN lets anyone join from the list, CODE_REQUIRED asks for the join
  code first. Default is OPEN.
- Discover orders by Near: the reader's Wilayat first, then everything else. Upcoming
  matches go by `start_at` ascending, and one in play (`start_at <= now < end_at`)
  is badged LIVE, not sorted apart. Communities go by their latest completed
  match's `start_at` (`status = 'completed' OR end_at <= now()`), else
  `created_at`, then `id`. A community with no Wilayat is not local. With nothing
  local, everything else is shown without a message.
- Latest Results is unaffected by Near, and shows no Wilayat.
- A match has no location of its own: it takes its community's current Wilayat.
  `matches.location` is display text only.
- The invitation link works under either policy, because it carries the code.
- Redeeming an invitation grants the player role and nothing more.
- System Admin is granted only in SQL. The app can neither grant it nor delete
  an account that holds it.
- Deleting a user removes everything that would outlive the account, including
  communities they own; reserves are promoted the way they are for any other
  departure.
- An owner or admin can regenerate the join code. The previous code and link
  stop working immediately and are not retained; existing members, matches and
  registrations are unaffected.
- Every match has a title. It is required at creation and cannot be removed by
  editing.
- Players register themselves for matches. Nobody is registered by anyone else,
  so no invitation refers to a match.

## Authorization

Every permission derives from `community_members.role`. Nothing derives from
who created a row. The full matrix is in the Architecture Migration
Specification v1.2, section 4.2, and is enforced twice — in RLS and again
inside each RPC.

## Non-functional requirements

- Mobile-first, Arabic by default with English available, RTL throughout.
- Clock times follow the device's own 12/24-hour preference rather than a
  format chosen by the app.
- Secure authentication; no service credentials in the client.
- PostgreSQL on Supabase, no custom backend.
- The approved behaviour is covered by an automated regression suite; see
  `12-Testing.md`.
