# 07 Database Design

**Database Design — Community-first (v3)**

Supersedes the Groups-first v2 document. Reflects the schema as it stands
after migration `0017`.

## Standards

- PostgreSQL on Supabase, no custom backend.
- UUID primary keys, `created_at` / `updated_at` audit columns.
- Identity is **email + password**. The v2 document specified phone + password;
  that was superseded by DD-02, and `users.phone` is a required contact field
  rather than a login identity.
- Multi-step writes go through `SECURITY DEFINER` RPCs so they stay atomic;
  reads go through RLS.

## Tables

`users`, `communities`, `community_members`, `matches`,
`match_registrations`, `notifications`, `app_settings`,
`match_team_assignments`.

## Key constraints

- One membership per person per community: `unique (community_id, user_id)`.
- `community_members.role` in (`owner`, `admin`, `player`), default `player`.
- One registration per person per match, and `registration_order` unique per
  match.
- `matches.status` in (`open`, `full`, `completed`) — DD-03.
- `matches.title` is NOT NULL, 2 to 60 characters: every match has a name.
- `communities.join_policy` in (`OPEN`, `CODE_REQUIRED`), default `OPEN`.
  `join_community` joins an OPEN community and raises `JOIN_CODE_REQUIRED`
  otherwise; `join_community_by_code` accepts the code under either policy,
  which is why an invitation link never has to care. The
  `communities_select_visible` policy no longer asks about membership: every
  active community is visible.
- `communities.join_code` is the single invitation identifier, 12 characters
  from a 31-symbol alphabet, unique, and 6 to 32 characters by constraint.
  `regenerate_join_code` (owner and admin) issues a new one in a single
  statement: that is how a leaked invitation is invalidated, since replacing
  the code is the only thing there is to revoke. Membership, matches and
  registrations are untouched — the code governs joining, not having joined.
- `starting_players` between 2 and 30; `max_registration` between 2 and 60 and
  never below `starting_players`.
- `matches.end_at > matches.start_at`.
  index), and an invitation can only offer `admin` or `player`.
- `notifications.match_id` uses **ON DELETE SET NULL**, so a "match deleted"
  notice survives the match it refers to (DD-08).
- `users.overall_rating` is `NUMERIC(3,1)`, NOT NULL, default `5.0`, constrained
  to `0.0 … 10.0` — the approved OP-1 scale. `users.date_of_birth` and
  `users.secondary_position` are nullable: existing players have neither, and
  the database must not invent what the engine is required to reject as missing.
  `secondary_position` uses the same vocabulary as `primary_position`.
- `match_team_assignments`: one row per player per match, unique on
  `(match_id, user_id)` — every player assigned exactly once, never twice
  (`BTGE-HC-1`, `BTGE-HC-2`). A partial unique index on `(match_id, team)` where
  `assigned_position = 'GK'` gives no team more than one goalkeeper
  (`BTGE-HC-6`). `team` in (`A`, `B`), `assigned_position` in the position
  vocabulary, `assignment_basis` in (`PRIMARY`, `SECONDARY`, `TRANSITION`).
  Out-of-position is not stored: it is exactly `assignment_basis = 'TRANSITION'`.
  Rows hold the lineup that **actually played**, including any manual change —
  a record of reality, not of the engine's proposal (KB-017).

## Authorization

`has_community_role(community_id, user_id, min_role)` is the only authorization
predicate. Roles are cumulative: owner >= admin >= player.

- Enforcement is dual: an RLS policy **and** a check inside the RPC. RLS alone
  is bypassed by `SECURITY DEFINER` functions; RPC checks alone do not cover
  direct PostgREST reads.
- `owner_id` and `created_by` are never read to grant or deny. The one
  `created_by = auth.uid()` in the match insert policy sits beside the role
  check and only stops a caller stamping someone else as creator.

The approved permission matrix is in the Architecture Migration Specification
v1.2, section 4.2.

`is_match_community_admin(match_id, user_id)` is the write predicate for
match-scoped tables, mirroring the existing `is_match_community_member` read
predicate. Both are `SECURITY DEFINER` because a policy that reached into
`matches` directly would have that subquery evaluated under the matches table's
own RLS. Reading a lineup is a member's business; writing one is match
management, which PD-06 and PD-07 already placed with the owner and admins.

`users.overall_rating` is not client-writable. `users_update_own_profile` lets a
player edit their own row, so the table-level UPDATE grant is replaced by an
explicit column list that omits the rating — otherwise a player could set their
own strength and the balance the engine computes would mean nothing. Rating
adjustment is a separate business rule; until it exists, nothing writes that
column from a client.

## Derived values

- `max_registration = starting_players + app_settings.reserve_players`, set by
  the `matches_set_capacity` trigger (DD-06).
- Lock is derived from the clock, not stored: a match is locked from its start
  until it ends (DD-04).
- Completion is derived the same way and written back lazily by whichever RPC
  next touches the row — there is no scheduler (DD-05).
- `communities.owner_id` mirrors the owner membership row and is updated inside
  `transfer_ownership` (PD-15).

## Indexes

Primary keys, the membership unique index (which also serves role resolution),
`communities(owner_id)`, `community_members(user_id)`,
`community_members(community_id)`, `matches(community_id, start_at)`,
`matches(status)`, `match_registrations(match_id, status, registration_order)`,
`match_registrations(user_id)`, `notifications(user_id, created_at desc)`,
`invitations(invitee_id, status)`, `match_team_assignments(user_id)` and the
partial unique `match_team_assignments(match_id, team) where assigned_position
= 'GK'`.

## System Admin

`system_admins(user_id)` is a role that is not a community role. It appears in
no `community_members` row, `has_community_role` knows nothing about it, and it
grants nothing inside any community. It exists so support can remove a user, a
community or a match.

Membership is granted by hand in SQL. There is no RPC and no screen for it: the
app must not be able to create its own administrators. The table has RLS on and
**no policies at all**, so not even an administrator can read the roster from a
client — `is_system_admin()` answers only about the caller.

Six functions are gated on it: `admin_list_users`, `admin_list_communities`,
`admin_list_matches`, `admin_delete_user`, `admin_delete_community`,
`admin_delete_match`. Each raises `NOT_AUTHORIZED` first thing.

Deletion reuses the cascades rather than restating them. `purge_community`,
`purge_match` and `purge_membership` hold the bodies `delete_community`,
`delete_match` and `remove_member` already had; those keep their authorization
checks and delegate. One cascade, two callers, so the admin path cannot drift
from the member path. The purge helpers are revoked from every client role.

`admin_delete_user` removes the account and everything that would outlive it:
communities it owns go whole (a community with no owner has nobody who can
manage it), memberships elsewhere go through `purge_membership` so reserves are
promoted the way they are for any other departure, matches it created in other
people's communities are deleted because `created_by` does not cascade, then its
notifications, registrations, profile and finally the `auth.users` row. It
refuses to delete the caller, and refuses to delete a System Admin — that
account is managed outside the app.

## The one unauthenticated entry point

`preview_community_invite` is the only function granted to `anon`. It exists
because an invitation has to be readable by someone who has not installed the
app yet. It is `SECURITY DEFINER` and returns four columns — a state, the
community's id and name, and whether the caller is already a member — and never
the join code itself, the roster, the matches or the owner. An unknown code
returns `not_found` and nothing else.

## Migrations

`0001`–`0006` built the Groups-first MVP. `0007` renamed the aggregate to
Community, `0008` moved authorization onto `community_members.role` and added
invitations, `0009` added ownership transfer, member removal and community
deletion, `0010` added shareable invite links. `0011`–`0014` are the
Community-first simplification: a required match title, the removal of both
invitation systems in favour of the join code, the title guard in
`update_match`, and the `delete_community` fix that followed from it. `0015`
added join-code regeneration, `0016` replaced `is_private` with
`join_policy`, and `0017` added the System Admin role. `0018` is KB-D3: the
three Core Player Inputs on the profile and `match_team_assignments`, the
lineup that actually played.
`supabase/setup_all.sql` is a generated concatenation of all eighteen, in order.

The migration sequence keeps the objects it later drops: it records the project's
history rather than its end state. Reading `0008` and `0012` together is how a
future reader learns why the invitation tables existed and why they do not now.
