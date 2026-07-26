# 07 Database Design

**Database Design — Community-first (v3)**

Supersedes the Groups-first v2 document. Reflects the schema as it stands
after migration `0010`.

## Standards

- PostgreSQL on Supabase, no custom backend.
- UUID primary keys, `created_at` / `updated_at` audit columns.
- Identity is **email + password**. The v2 document specified phone + password;
  that was superseded by DD-02, and `users.phone` is a required contact field
  rather than a login identity.
- Multi-step writes go through `SECURITY DEFINER` RPCs so they stay atomic;
  reads go through RLS.

## Tables

`users`, `communities`, `community_members`, `invitations`,
`community_invite_links`, `matches`, `match_registrations`, `notifications`,
`app_settings`.

## Key constraints

- One membership per person per community: `unique (community_id, user_id)`.
- `community_members.role` in (`owner`, `admin`, `player`), default `player`.
- One registration per person per match, and `registration_order` unique per
  match.
- `matches.status` in (`open`, `full`, `completed`) — DD-03.
- `starting_players` between 2 and 30; `max_registration` between 2 and 60 and
  never below `starting_players`.
- `matches.end_at > matches.start_at`.
- At most one pending invitation per person per community (partial unique
  index), and an invitation can only offer `admin` or `player`.
- `notifications.match_id` uses **ON DELETE SET NULL**, so a "match deleted"
  notice survives the match it refers to (DD-08).
- `community_invite_links.role` is checked to be `player`: a link has no named
  recipient, so it can never confer more (DD-10).
- `community_invite_links.kind` in (`community`, `match`), with a check that a
  `community` link carries no `match_id`. Two partial unique indexes keep at
  most one active link per community and per match.

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

## Derived values

- `max_registration = starting_players + app_settings.reserve_players`, set by
  the `matches_set_capacity` trigger (DD-06).
- Lock is derived from the clock, not stored: a match is locked from its start
  until it ends (DD-04).
- Completion is derived the same way and written back lazily by whichever RPC
  next touches the row — there is no scheduler (DD-05).
- `communities.owner_id` mirrors the owner membership row and is updated inside
  `transfer_ownership` (PD-15).
- An invite link's usability is derived rather than stored: `invite_link_state`
  reads `is_active`, `kind` and the match's `start_at` and returns one of
  `valid` / `revoked` / `expired` / `match_deleted` / `not_found`. Preview and
  redemption share it, so the landing screen cannot promise what redemption
  would refuse (DD-10).

## Indexes

Primary keys, the membership unique index (which also serves role resolution),
`communities(owner_id)`, `community_members(user_id)`,
`community_members(community_id)`, `matches(community_id, start_at)`,
`matches(status)`, `match_registrations(match_id, status, registration_order)`,
`match_registrations(user_id)`, `notifications(user_id, created_at desc)`,
`invitations(invitee_id, status)`.

## The one unauthenticated entry point

`preview_invite_link` is the only function granted to `anon`. It exists because
an invitation has to be readable by someone who has not installed the app yet.
It is `SECURITY DEFINER` and returns a fixed set of columns — the community
name, the match's public face, seat counts — and never the row, the join code,
the roster or who created the link. A revoked or unknown token returns its state
and nothing else. Everything else about links (`create_invite_link`,
`revoke_invite_link`, `redeem_invite_link`, and the `invite_link_state` helper)
is denied to `anon`, and the table itself is readable only by community admins.

## Migrations

`0001`–`0006` built the Groups-first MVP. `0007` renamed the aggregate to
Community, `0008` moved authorization onto `community_members.role` and added
invitations, `0009` added ownership transfer, member removal and community
deletion, `0010` added shareable invite links. `supabase/setup_all.sql` is a
generated concatenation of all ten, in order.
