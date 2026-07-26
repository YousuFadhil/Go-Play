# Software Requirements Specification (SRS)

> Updated for the Community-first architecture (`v0.4.0-mvp`).

## Functional requirements

- Registration and login with email and password
- Community management: create, join by code, edit settings, delete
- Membership: invite, accept, revoke, change role, transfer ownership, remove a
  member, leave
- Match management: create, edit, delete, manage the roster
- Match registration with a reserve list and automatic promotion
- In-app notifications

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

## Authorization

Every permission derives from `community_members.role`. Nothing derives from
who created a row. The full matrix is in the Architecture Migration
Specification v1.2, section 4.2, and is enforced twice — in RLS and again
inside each RPC.

## Non-functional requirements

- Mobile-first, Arabic by default with English available, RTL throughout.
- Secure authentication; no service credentials in the client.
- PostgreSQL on Supabase, no custom backend.
- The approved behaviour is covered by an automated regression suite; see
  `12-Testing.md`.
