# 06 ERD

**ERD — Community-first (v3)**

Supersedes the Groups-first v2 diagram, replaced during the Community
migration (`v0.4.0-mvp`). Community is the aggregate root: everything below
belongs to exactly one community, and nothing is owned by a user.

## 1. Entities as built

| Entity | Purpose |
|---|---|
| `users` | Player profile, keyed to the Supabase auth user |
| `communities` | The aggregate root |
| `community_members` | The membership edge, carrying the role |
| `matches` | A match inside one community |
| `match_registrations` | Starting and reserve places |
| `notifications` | In-app notices addressed to one user |
| `app_settings` | One global row; currently the reserve allowance |
| `system_admins` | The internal administration role; not a community role |
| `match_team_assignments` | The lineup that actually played a match (KB-D3) |

Entities described in the v2 document but never built — `fields`, `teams`,
`match_results`, `goals`, `rating_history`, `player_statistics` — remain out of
scope. See `11-Future-Backlog.md`. The v2 `team_players` idea is now served by
`match_team_assignments`, which was built for BTGE rather than for statistics.

## 2. Relationships

```
users (1) --< community_members >-- (1) communities
                                          |
                                          +--< matches
                                                 +--< match_registrations >-- users
                                                 +--< match_team_assignments >-- users

users --< notifications --? matches   (match_id nullable, ON DELETE SET NULL)
```

- A user belongs to many communities; a community has many members. The
  membership row carries `role` in (`owner`, `admin`, `player`).
- Exactly one member per community holds `owner`, always.
- A match belongs to a community, never to its creator.
- A registration is unique per `(match_id, user_id)`, and `registration_order`
  is unique per match.
- A notification keeps its text after its match is deleted, because `match_id`
  is set to null rather than cascading.
- A team assignment is unique per `(match_id, user_id)`, and at most one row per
  `(match_id, team)` may carry `GK`. It cascades with its match: a deleted match
  leaves no lineup behind.

## 3. Fields that are not authorization

Two columns look like ownership and are not:

- `communities.owner_id` — a derived, synchronized mirror of the member holding
  `owner`. Kept for reporting, analytics and query convenience. Never read to
  grant or deny anything (PD-15).
- `matches.created_by` — audit only. It records who created the row and is
  shown as attribution. Management follows community role (PD-16, PD-07).

## 4. One invitation

`communities.join_code` is the only invitation identifier. The link is that
code in a URL and the join dialog accepts the same code typed by hand; there is
no second token and no invitation table. Twelve characters from a 31-symbol
alphabet, reissued only if the owner needs to invalidate what was shared.

## 5. Business rules carried by the model

- Registration order decides who starts: the first `starting_players` are
  confirmed, the rest are reserve.
- No two registrations for one person in overlapping live matches.
- Withdrawing deletes the registration row, which is what allows re-registering
  (DD-01).
- Capacity is derived: `max_registration = starting_players + reserve_players`,
  the latter a single global setting (DD-06).
- Status holds only `open`, `full`, `completed` (DD-03).
- Every match has a title: `matches.title` is NOT NULL, between 2 and 60
  characters.
- `communities.join_policy` in (`OPEN`, `CODE_REQUIRED`), default `OPEN`. It
  replaced `is_private`, which conflated visibility with joining; a community is
  always visible now.
