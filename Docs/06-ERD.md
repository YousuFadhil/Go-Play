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
| `invitations` | An offer of membership at a given role |
| `matches` | A match inside one community |
| `match_registrations` | Starting and reserve places |
| `notifications` | In-app notices addressed to one user |
| `app_settings` | One global row; currently the reserve allowance |

Entities described in the v2 document but never built — `fields`, `teams`,
`team_players`, `match_results`, `goals`, `rating_history`,
`player_statistics` — remain out of scope. See `11-Future-Backlog.md`.

## 2. Relationships

```
users (1) --< community_members >-- (1) communities
                                          |
                                          +--< invitations
                                          +--< matches
                                                 +--< match_registrations >-- users

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

## 3. Fields that are not authorization

Two columns look like ownership and are not:

- `communities.owner_id` — a derived, synchronized mirror of the member holding
  `owner`. Kept for reporting, analytics and query convenience. Never read to
  grant or deny anything (PD-15).
- `matches.created_by` — audit only. It records who created the row and is
  shown as attribution. Management follows community role (PD-16, PD-07).

## 4. Business rules carried by the model

- Registration order decides who starts: the first `starting_players` are
  confirmed, the rest are reserve.
- No two registrations for one person in overlapping live matches.
- Withdrawing deletes the registration row, which is what allows re-registering
  (DD-01).
- Capacity is derived: `max_registration = starting_players + reserve_players`,
  the latter a single global setting (DD-06).
- Status holds only `open`, `full`, `completed` (DD-03).
