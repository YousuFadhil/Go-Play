# 07 Database Design

**Database Design — Community-first (v3)**

Supersedes the Groups-first v2 document. Reflects the schema as it stands
after migration `0024`.

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
`match_team_assignments`, `system_admins`.

From the Results / Rating phase (`0022`): `match_results`, `match_goals`,
`rating_history`, `player_statistics`. All four are written only by
`record_match_result` and carry select policies and nothing else.

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
- `starting_players` between **4** and 30 — the approved `OP-2` minimum match
  size, 2 v 2, applied to the product as a whole and not to team generation
  alone (Engineering Specification §18.1.1, migration `0019`). The same guard
  sits inside `update_match`. `max_registration` stays between 2 and 60 and
  never below `starting_players`: it is a derived value, and narrowing it was
  not part of that decision.
- `matches.end_at > matches.start_at`.
  index), and an invitation can only offer `admin` or `player`.
- `notifications.match_id` uses **ON DELETE SET NULL**, so a "match deleted"
  notice survives the match it refers to (DD-08).
- `users.overall_rating` is `NUMERIC(4,2)`, NOT NULL, default `5.00`,
  constrained to `0.0 … 10.0` — the approved OP-1 scale, recorded in §18.1.1 of
  the BTGE Engineering Specification. It was widened from `NUMERIC(3,1)` by
  migration `0022`, because the approved engine moves a rating by `0.05` for a
  goal and one decimal place cannot represent that reversibly (`RR-1`). One
  decimal remains a *presentation* choice; round for the eye, never for the
  record. Under `SL-3` this column is the **Global Rating** — Level 1.
  `users.date_of_birth` and
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

Who may change `users.overall_rating` is **settled for the engine and open for
administrators**. Migration `0018` added the column and its range constraint
and said nothing about permissions, which left `users_update_own_profile`
governing it like any other profile field. Migration `0022` closed that
(`RR-2`): `UPDATE` on `public.users` was revoked from `authenticated` and
re-granted **per column** on the five profile fields a player owns — `phone`,
`full_name`, `primary_position`, `secondary_position`, `date_of_birth`. RLS
answers *which rows*, not *which columns*, so a column-level `GRANT` is what
enforces it.

The rating is therefore system-managed: the rating engine is its sole author.
Whether an **administrator** may adjust a rating by hand remains a
Product/Business Policy question and is still open.

Under `SL-3` the same rule governs the approved **Community Rating**: no client
may write either rating, and the community tables should carry select policies
only, as the four results tables already do.

## Statistics and leaderboards — approved architecture, not yet built

**No schema exists for this yet, and none is designed here.** The authoritative
source is `engineering/Statistics_Leaderboards_MVP_Specification.md` (v2.0);
this section records what the schema must express so that the future design
follows it rather than rediscovering it.

**Two levels (`SL-2`, `SL-3`).**

| Level | What it is | Where it lives today |
|---|---|---|
| **1 — Global** | The player's career: `player_statistics` counters plus `users.overall_rating` as the Global Rating | **Built** (`0022`) |
| **2 — Community** | The player's record inside one community, plus a Community Rating | **Not built** |

**Level 2 identity (`SL-1`).** One model, not three tables. A record is
identified by `(player, community_id, period_type, period_key)`, where
`period_type` is one of `overall`, `weekly`, `monthly`, and `period_key` is
`overall`, an ISO-8601 week such as `2026-W31`, or a month such as `2026-08`.
Adding a period later is a new `period_type` value, not a new table.

**Rules the schema must not contradict:**

- **Isolation.** A player's record in one community must never affect another
  community's figures. `community_id` is what makes that a property of the
  model rather than a discipline expected of each query.
- **Lifetime (`SL-4`).** A Level 2 record **outlives its membership row**. It
  is keyed by player and community and must not cascade from
  `community_members`: leaving preserves it, rejoining restores it, and a
  Community Rating is created once at the neutral baseline `5.00` and never
  reset. It still cascades with the community itself.
- **Audit.** A Community Rating History is required for the same reason
  `rating_history` is — a corrected result must reverse by the *applied* delta,
  which is the only exact reversal under clamping (`RR-1`, `RR-5`). It has no
  reader in the MVP; it is not optional.
- **Write path.** One system-managed writer, select-only policies, no client
  writes — the pattern `0022` established (`RR-2`).
- **Reversal.** Apply and reverse stay separate statements over shared
  arithmetic. `INSERT … ON CONFLICT DO UPDATE` validates the *proposed* row
  before it detects the conflict, which is what produced the `RR-4` defect; the
  community counters will meet the same behaviour.
- **Eligibility is a read-time filter**, never a stored flag: leaderboards show
  active members only.

**The reference time zone is `Asia/Muscat` (UTC+4)**, approved 2026-08-01. It
is the single application-wide constant from which `period_key` is derived, and
it **must not change once figures exist** — changing it re-buckets history into
different weeks and months. The conceptual model and the rest of the
engineering assumptions are in `06-ERD.md` §3.

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
lineup that actually played. `0019` applied the `OP-2` minimum match size,
`0020` made the lineup write atomic, and `0021` added the signup profile
inputs. `0022`–`0024` are the Results / Rating phase: the four results tables
and `record_match_result`, the statistics reversal fix, and the trigger
hardening that followed the linter — see
`engineering/Results_Rating_Engineering_Decisions.md` for why they are three
migrations and not one.
`supabase/setup_all.sql` is a generated concatenation of all of them, in order.

The migration sequence keeps the objects it later drops: it records the project's
history rather than its end state. Reading `0008` and `0012` together is how a
future reader learns why the invitation tables existed and why they do not now.

---

# Phase Status

**Database Design Engineering — 2026-08-02**

## 1. Status

**Completed.**

## 2. Implementation Readiness

**Ready.**

## 3. Approved Scope

- **All database tables specified.** Fifteen table specifications, each an
  Engineering Authority: the eleven built tables, and the four approved but
  unbuilt (`community_statistics`, `community_ratings`,
  `community_rating_history`, and the relocated invitation credential).
- **All Level 2 read models specified.** The Community Dashboard and the nine
  Community Leaderboards, each frozen before any view, RPC or query exists.
- **Cross-document consistency verified.** Every specification was validated
  against the PRD, the ERD, this document, the Design Decisions, and the
  `SL`, `RR`, `BTGE` and `UP` decision records. The architecture review of
  2026-08-02 resolved the Community Rating and dashboard-ownership
  contradictions at source; no contradiction between approved documents
  remains open.
- **The BTGE database contract** is frozen alongside the tables.

## 4. Outstanding Decisions

Unresolved only. Approved items are not repeated.

| # | Decision | Gates |
|---|---|---|
| 1 | **Confirm the `DP-n` principle readings.** Nine of eleven have no definition in the repository; each specification states the reading it applied | Nothing — but every specification leans on them |
| 2 | **Leaderboard scope: nine boards or fifteen** (`LB-X1`). *Most Matches Played* and *Most Wins* are not in the approved set | The leaderboard build |
| 3 | **Leaderboard read rules** — zero-valued entries (`LB-D1`), tie-break order (`LB-D2`), and the `SL-2` §2.3 wording fix (`LB-D3`) | The leaderboard build |
| 4 | **`Last Match Date` basis** (`CD-D1`) | One dashboard figure |
| 5 | **Level 2 build order and join-path write** (`CR-D1`, `CR-D3`, `CR-D4`) | The Level 2 build |
| 6 | **Administrative rating adjustment** (`RR-2`, open since the results phase; `RH-D1`) | Nothing today |
| 7 | **Invitation credential relocation** (`CI-D0`), which amends `DD-12` | That relocation only |
| 8 | **Per-table conformance items** recorded in each specification — the unused write rules (`MT-D1`, `NT-D1`, and their siblings), the deletion-cascade ordering (`MRS-D1`), and the integrity constraints `RH-D2` recommends | Their own tables |

## 5. Blocking Issues

**None.** No decision blocks implementation from beginning. Items 2, 3, 5 and 7
above gate specific deliverables within the next phase rather than the phase
itself.

## 6. Next Phase

**Database Implementation** — views, RPC functions, triggers and RLS.

Each specification carries its own conformance list and build instruction; those
are the implementation backlog. Four cross-cutting families recur across
tables and should be closed together rather than one table at a time: the
unused write rules, the account-deletion cascade ordering, the missing
`updated_at` columns, and the absent reconciliation checks.

## 7. Administrative roster ordering (migration `0053`)

### Schema

- `matches.roster_order_mode` — `text NOT NULL DEFAULT 'registration'`,
  constrained to (`registration`, `manual`). It records that an owner or admin
  has arranged this match's roster. The transition is **one-way**: the
  `matches_roster_order_mode_locked` trigger raises
  `ROSTER_ORDER_MODE_LOCKED` on any update that moves it back, so the approved
  rule "administrative ordering is never silently reverted" is a database
  invariant rather than a convention the RPCs happen to keep. It has to be,
  because `matches_update_community_admins` lets an admin write the row
  directly.
- `match_registrations.admin_order` — `integer`, null for every participant of a
  match still in registration order and non-null for every participant of an
  arranged one. `unique (match_id, admin_order) DEFERRABLE INITIALLY DEFERRED`,
  and the deferral is load-bearing: every arrangement rewrites the order in one
  statement, and a permutation of `1,2,3` into `1,3,2` passes through a moment
  where two rows share a value. Nulls do not collide, so an unarranged match
  holds as many nulls as it has participants.
- `match_registrations_admin_order` — a `BEFORE INSERT` trigger that appends a
  new participant to the end of the arrangement when the match has one. A
  trigger rather than a line in each of the five functions that insert a
  registration, for the reason migration `0050` hangs lineup reconciliation off
  `recompute_match_status`: the invariant belongs at the one place that sees
  every insert.

### The ordering

One expression, used by `rebalance_roster` (which cuts it at
`starting_players`), by `next_reserve_registration` (which promotes from it) and
by `v_match_registrations.roster_position` (which the app reads it through):

```sql
ORDER BY admin_order NULLS LAST, (user_id IS NULL), registration_order
```

An unarranged match ties on the first term, so the two derived terms decide and
migration `0045`'s behaviour is unchanged — including the Professional Guest
FIFO promotion and LIFO displacement, which remain the approved fallback.

### RPCs

| Function | Who | What it does |
|---|---|---|
| `set_match_roster_order(uuid, uuid[])` | owner, admin | Writes the whole participant order, starting participants first. The array must be an **exact permutation** of the match's registration ids — same length, no repeats, all belonging to this match — or the call raises `ROSTER_MISMATCH` |
| `swap_match_participants(uuid, uuid, uuid)` | owner, admin | Exchanges two seats' positions. `INVALID_SWAP` when the two ids are equal, null, or not both participants of this match |

Both take the match row `FOR UPDATE` before reading anything that depends on
capacity or ordering — the same lock, in the same place, as registration,
withdrawal and the guest operations — then activate administrative ordering if
this is the first arrangement, write, re-cut the roster and call
`recompute_match_status`. Both are `SECURITY DEFINER` with `search_path` pinned,
revoked from `anon` and `public`, granted to `authenticated`, and authorized
internally by `has_community_role(community_id, auth.uid(), 'admin')`. No table
privilege was widened and no RLS policy changed.

**Why the whole order rather than a move.** "Move X to position 4" has to be
interpreted against the order the caller was looking at, which may have changed
since they looked. Sending the resulting order makes the caller's view part of
the request: a roster that moved underneath is refused with `ROSTER_MISMATCH`
instead of being applied to a roster nobody saw. That is the whole of the
concurrency story, and it costs one comparison.

**Why no seat travels.** The array says positions and nothing else; starting and
reserve are derived by the cut. So capacity and starting/reserve exclusivity are
not validated in these functions because they cannot be violated in them.

### A played match

`set_match_roster_order` and `swap_match_participants` work on a completed match
— an owner or admin administers a match in every state — but neither re-cuts its
roster, for the reason migration `0047` states: everyone in the record played,
and re-cutting would demote players out of a recorded lineup and notify them
about a match that is over. The arrangement is stored; the seats are left as the
record they are.

### Functions changed, and how

`rebalance_roster`, `register_player_in_match`, `withdraw_from_match`,
`remove_player` and `purge_membership` each gained the new ordering term and
nothing else, except `register_player_in_match`, which also gained one branch:
under an arrangement the new row is appended, so its seat is decided by whether
the arrangement has a starting position left, rather than by the community count
migration `0045` uses. That branch is what stops the next community player to
register from displacing a Professional Guest the administrator deliberately put
in the starting lineup.
