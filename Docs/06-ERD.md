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
| `invitations` | A directed offer of membership at a given role |
| `community_invite_links` | A shareable invitation: a bearer token naming a community and, optionally, one match |
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
                                          +--< community_invite_links --? matches
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
- An invite link belongs to a community and may name one match. `kind` records
  which it was created as, so a link whose match was deleted (`match_id` set to
  null) is still distinguishable from a community-only one — that is what lets
  it report "the match was deleted" instead of silently becoming a community
  invitation.
- At most one active link per community and per match, so sharing twice hands
  back the same link rather than breeding new ones.

## 3. Fields that are not authorization

Two columns look like ownership and are not:

- `communities.owner_id` — a derived, synchronized mirror of the member holding
  `owner`. Kept for reporting, analytics and query convenience. Never read to
  grant or deny anything (PD-15).
- `matches.created_by` — audit only. It records who created the row and is
  shown as attribution. Management follows community role (PD-16, PD-07).

## 4. Two kinds of invitation

They are separate tables because they have opposite invariants:

| | `invitations` | `community_invite_links` |
|---|---|---|
| Recipient | A named existing user | Anyone holding the token |
| Uses | Once | Many |
| Role offered | `admin` or `player` | `player` only |
| Expiry | Always, 14 days | Never (community) or at kick-off (match) |
| Readable before sign-in | No | Yes, through `preview_invite_link` |

## 5. Business rules carried by the model

- Registration order decides who starts: the first `starting_players` are
  confirmed, the rest are reserve.
- No two registrations for one person in overlapping live matches.
- Withdrawing deletes the registration row, which is what allows re-registering
  (DD-01).
- Capacity is derived: `max_registration = starting_players + reserve_players`,
  the latter a single global setting (DD-06).
- Status holds only `open`, `full`, `completed` (DD-03).
