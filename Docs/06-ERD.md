# 06 ERD

**ERD — Community-first (v3)**

Supersedes the Groups-first v2 diagram, replaced during the Community
migration (`v0.4.0-mvp`). Community is the aggregate root: everything below
belongs to exactly one community, and nothing is owned by a user.

**§1 and §2 describe the model as built.** §3 is the **conceptual** model for
statistics and leaderboards, added 2026-08-01: approved, not built, and
deliberately free of physical design.

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
| `match_results` | One row per match: the score and the MVP |
| `match_goals` | One row per scorer per match, carrying how many they scored |
| `rating_history` | Every Global Rating change, immutable, forever |
| `player_statistics` | The player's **career** counters — one row per player |

`match_results`, `rating_history` and `player_statistics` were described in the
v2 document, deferred, and then built by the Results / Rating phase (migration
`0022`). `goals` was built as `match_goals`. Of the v2 list only `fields` and
`teams` remain out of scope — see `11-Future-Backlog.md`. The v2 `team_players`
idea is served by `match_team_assignments`, which was built for BTGE rather
than for statistics.

## 2. Relationships

```
users (1) --< community_members >-- (1) communities
                                          |
                                          +--< matches
                                                 +--< match_registrations >-- users
                                                 +--< match_team_assignments >-- users
                                                 +--o match_results >-- users (MVP)
                                                        +--< match_goals >-- users
                                                 +--< rating_history >-- users

users (1) --o player_statistics        (career counters, one row per player)

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
- A match has at most one result, and a result names exactly one MVP. Goals
  reference the *result*, not the match. Deleting a match reverses the ratings
  and counters it produced before its children cascade away.
- `player_statistics` is keyed by user alone: it is a **career** record, with
  no community and no period.

## 3. Statistics and leaderboards — the conceptual model

**Conceptual only.** No table, column, index, constraint, key, trigger or
migration is defined here, and none exists. This section states *what things
are, what they belong to, how many of each, and how long they live* — the
questions a physical design must answer, not the answers.

**Authority.** `engineering/Statistics_Leaderboards_MVP_Specification.md`
v2.0, decisions `SL-1` … `SL-5`, approved 2026-08-01. Where this section and
that document differ, that document governs.

**State.** Level 1 is built (migration `0022`). **Level 2 is not built.**

### 3.1 The two levels

| Level | What it represents | Scope | State |
|---|---|---|---|
| **1 — Global** | The player's complete football career across the app | The player | **Built** |
| **2 — Community** | The player's performance inside one community | The player, in one community | **Not built** |

The levels are additive, never substitutes. A screen reads from exactly one of
them (`SL-2`).

### 3.2 Conceptual entities

| # | Entity | Level | Identified by | Cardinality |
|---|---|---|---|---|
| E1 | **Player** | — | The person | — |
| E2 | **Community** | — | The community | — |
| E3 | **Community Membership** | — | Player + Community | Present for contrast — it owns **no** statistics |
| E4 | **Global Statistics** | 1 | Player | **One per player** |
| E5 | **Global Rating** | 1 | Player | **One per player** |
| E6 | **Global Rating History** | 1 | Player | **Many per player**, one per rating change |
| E7 | **Community Statistics** | 2 | Player + Community + Statistics Period | **One per player per community per period** |
| E8 | **Community Rating** | 2 | Player + Community | **One per player per community** |
| E9 | **Community Rating History** | 2 | Player + Community | **Many per pair**, one per rating change |
| E10 | **Statistics Period** | 2 | Period type + period key | A dimension of E7, not a record about a player |

`E4`, `E5` and `E6` exist today as `player_statistics`, `users.overall_rating`
and `rating_history`. `E7`, `E8` and `E9` do not exist.

**Why `E8` is not scoped to a period.** A counter accumulates inside a window;
a rating is a running value that has no natural zero and does not restart.
`SL-3` placed the Community Rating inside the community statistics model, and
`SL-5` then settled what that means: the rating is always the **current** one,
and the period selects **who is eligible to appear**, never which rating is
shown. So the rating is one value per player per community, and the period
dimension belongs to the counters and to eligibility. This is v2.0 §9.1 stated
as an entity.

### 3.3 The conceptual diagram

Notation follows §2: `(1)` one, `--<` one-to-many, `--o` one-to-at-most-one.

```
LEVEL 1 — the career, one of each per player

  Player (1) --o Global Statistics        the six career counters
  Player (1) --o Global Rating            the career rating
  Player (1) --< Global Rating History    one entry per change


LEVEL 2 — inside one community

  Player    (1) --+
                  +--o Community Rating (1) --< Community Rating History
  Community (1) --+

  Player    (1) --+
                  +--< Community Statistics >-- (1) Statistics Period
  Community (1) --+


OWNERSHIP — what Community Statistics does NOT depend on

  Community Membership   -- X --   Community Statistics
  Community Membership   -- X --   Community Rating

        no relationship, by decision (SL-4) — see §3.4
```

### 3.4 Ownership — Player **and** Community, never Membership

**Community Statistics and the Community Rating belong conceptually to the
Player and to the Community. They do not belong to the Community Membership.**

This is the single most important statement in this section, and it is stated
explicitly because the natural modelling instinct is wrong here:

- **Membership is a current fact; the record is a historical one.** A
  membership says *this player is in this community now*. A statistics record
  says *this is what this player did in this community*. The second outlives
  the first.
- **`SL-4` requires the record to survive a departure and be found again on a
  return.** If it belonged to the membership, leaving would take it away and
  rejoining would create a new, empty one — which is exactly what `SL-4`
  forbids.
- **Eligibility, not existence, is what membership governs.** Whether a player
  appears on a board is a question about their membership *at read time*. It
  is answered by looking at the membership, never by whether a statistics
  record exists.

The other two ownership rules:

- **A record belongs to exactly one community**, and never spans two. Isolation
  is therefore structural rather than a rule every query has to remember
  (`SL-2`).
- **A record's existence is bounded by both of its owners.** A deleted
  community takes its statistics with it, the way everything under the
  aggregate root does; a deleted player does the same, the way
  `player_statistics` already goes with its user. A deleted **membership**
  takes nothing — that is the whole point of §3.4.

### 3.5 The time dimension — Statistics Period

**Statistics Period** (`E10`) is a conceptual dimension of Community
Statistics, made of two parts:

| Part | Meaning | Values |
|---|---|---|
| Period type | Which **kind** of period | `overall`, `weekly`, `monthly` |
| Period key | Which **particular** period of that kind | `overall`; a week such as `2026-W31`; a month such as `2026-08` |

Conceptual properties:

- **One model, every scope.** A period is *data about a record*, not a
  different kind of record. Three scopes are three values, not three entities
  (`SL-1`).
- **A period is a property of the counters, not of the rating** — §3.2.
- **Overall is a period like any other**, with a single fixed key. It is not a
  special case in the model, only in its key.
- **A future scope is a new period type.** `yearly`, `season`, `tournament`,
  `league` and custom periods would extend the same dimension and add no
  entity (`SL-1`). **None is approved**; they are named to show the dimension
  is the extension point.

Which real-world instant falls in which period is an implementation question —
see §3.9.

### 3.6 The two ratings

| | **Global Rating** (`E5`) | **Community Rating** (`E8`) |
|---|---|---|
| **Purpose** | The player's complete football career across the app | The player's performance inside one specific community |
| **Ownership** | The Player. One per player, no community, no period | The Player **and** the Community. One per pair, no period |
| **Lifecycle** | Exists with the player; moved by **every** completed match in any community | Created once at first join, at the neutral baseline; moved **only** by matches in that community; preserved on departure; restored on return; **never reset** (`SL-4`) |
| **Consumers** | The **Player Profile only** | The **Community Dashboard** and the **Community Leaderboards** only |
| **History** | Global Rating History (`E6`) — built, immutable | Community Rating History (`E9`) — not built, preserved on departure |

Conceptual rules that hold across both:

- **They are independent.** Neither is derived from the other, neither is a
  view of the other, and they are expected to differ (`SL-3`).
- **Neither is reconcilable arithmetic.** A Global Rating is not the sum, mean
  or any function of a player's Community Ratings.
- **Both are system-managed.** No client authors either; a rating changes only
  as a consequence of a recorded result.
- **Both keep a history for the same reason.** A corrected result must reverse
  by the delta that was *applied*, which is the only exact reversal when a
  rating can sit at the end of its range (`RR-1`, `RR-5`). The Community Rating
  History has **no reader in the MVP** and is still required.

### 3.7 Lifecycle of a community record

The lifecycle the conceptual model must support, from `SL-4`:

```
  Player joins the community
            │
            ▼
  Community Statistics created          ← first join only
  Community Rating created at baseline
            │
            ▼
  Player plays matches in the community
            │
            ▼
  Community Statistics updated          ← counters, per period
  Community Rating updated              ← running value
            │
            ▼
  Player leaves the community
            │
            ▼
  Community Statistics preserved        ← nothing is deleted
  Community Rating preserved
  Community Rating History preserved
  Player becomes ineligible for the community's leaderboards
            │
            ▼
  Player rejoins the community
            │
            ▼
  Previous Community Statistics reused  ← no new record, no new baseline
  Previous Community Rating resumed
  Player becomes eligible again
```

Four conceptual consequences:

- **Creation happens once, ever.** "First join only" is the whole rule: a
  record is created for a `(player, community)` pair that has none, and never
  again for that pair.
- **Departure changes eligibility, not data.** No entity is deleted, no value
  is altered, and no flag is written onto the record. Eligibility is evaluated
  when a board is read.
- **A record can exist with nothing in it.** Joining creates the rating at the
  baseline and the player's `overall` record before any match is played.
  Periodic records come into being for periods in which the player actually
  played — a weekly record for a week with no appearances would carry only
  zeros and assert nothing. Appearing on a board additionally requires at least
  one completed match in the window (`SL-5`), so a player who has joined and
  never played holds a record and appears nowhere.
- **Nothing about this touches Level 1.** A player's career record spans every
  community they have played in, including ones they have left (`RR-6`).

### 3.8 Consumers — which level each surface reads

| Surface | Reads | Never reads |
|---|---|---|
| **Player Profile** | **Global Statistics and the Global Rating** (`E4`, `E5`, `E6`) | Community Statistics; the Community Rating |
| **Community Dashboard** | **Community Statistics** (`E7`), and the Community Rating if it ever shows one | Global Statistics; the Global Rating |
| **Community Leaderboards** | **Community Statistics** (`E7`) and the Community Rating (`E8`) | Global Statistics; the Global Rating |

- **Community Leaderboards depend on Community Statistics and never on Global
  Statistics** — for all nine boards, in every period (`SL-2` §2.3, `SL-3`
  §3.3). *Highest Rated* ranks by the current Community Rating and never by the
  Global Rating.
- **The Player Profile depends on Global Statistics and never on Community
  Statistics.** A career figure is never assembled from, or replaced by, a
  community one.
- No surface in the MVP reads both levels, and no measure is assembled from
  both.

### 3.9 Engineering assumptions recorded for the design phase

Not conceptual model, but decisions and constraints the physical design will
need. Recorded here so they are inherited rather than rediscovered.

| # | Assumption |
|---|---|
| A1 | **Reference time zone: `Asia/Muscat` (UTC+4).** Approved 2026-08-01. One application-wide constant, used to derive which week and month a match falls in. It must not change once figures exist — changing it re-buckets history into different periods. |
| A2 | Week keys follow **ISO-8601** week notation (`2026-W31`); month keys are `YYYY-MM`. |
| A3 | A match is placed in a period by **when it was played** — its start — evaluated in `A1`. |
| A4 | Statistics arise **only from a recorded result**. A match played but never recorded produces nothing at either level, and a corrected result reverses in full before the new one applies. |
| A5 | The Community Rating baseline is the same neutral value a career starts at (`5.00`), and a joining player never imports their Global Rating (`SL-4`). |
| A6 | Both levels are **system-managed**: one write path, no client writes. |
| A7 | Level 2 records cascade with their **community**, never with a **membership** (§3.4). |

## 4. Fields that are not authorization

Two columns look like ownership and are not:

- `communities.owner_id` — a derived, synchronized mirror of the member holding
  `owner`. Kept for reporting, analytics and query convenience. Never read to
  grant or deny anything (PD-15).
- `matches.created_by` — audit only. It records who created the row and is
  shown as attribution. Management follows community role (PD-16, PD-07).

## 5. One invitation

`communities.join_code` is the only invitation identifier. The link is that
code in a URL and the join dialog accepts the same code typed by hand; there is
no second token and no invitation table. Twelve characters from a 31-symbol
alphabet, reissued only if the owner needs to invalidate what was shared.

## 6. Business rules carried by the model

- Registration order decides who starts **until an owner or admin arranges the
  roster**: the first `starting_players` of the authoritative order are
  confirmed, the rest are reserve. The authoritative order is
  `match_registrations.admin_order` when `matches.roster_order_mode = 'manual'`
  and arrival order otherwise — see §7 and `07-Database-Design.md`.
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

## 7. The administrative roster arrangement (migration `0053`)

Two columns, and no new entity.

| Column | Meaning |
|---|---|
| `matches.roster_order_mode` | `registration` (default) or `manual`. Records that an owner or admin has arranged this match's roster. **One-way**: a trigger refuses `manual` → `registration`, so administrative ordering is never reverted, not even by an admin writing the row directly. |
| `match_registrations.admin_order` | The participant's place in that arrangement, 1 first. Null for every participant of a match still in registration order; non-null for every participant of an arranged one. Unique per match, **deferrable**, because every arrangement rewrites the order as one statement and a permutation passes through a moment where two rows share a value. |

The authoritative participant order is one expression, used by
`rebalance_roster`, by `next_reserve_registration` and by the
`v_match_registrations.roster_position` column the app reads:

```
ORDER BY admin_order NULLS LAST, (user_id IS NULL), registration_order
```

Everything that follows is a consequence of that one clause plus the existing
cut at `starting_players`:

- **The default is untouched.** A match nobody has arranged has `admin_order`
  null on every row, so the first term ties and the two derived terms decide —
  which is exactly migration `0045`'s behaviour, including the Professional
  Guest FIFO/LIFO fallback.
- **`registration_order` keeps its meaning.** It is the record of arrival, it is
  what the default ordering reads, and it is what an arrangement is seeded from
  the first time one is created. It is never rewritten.
- **A guest is ordered against a community player by the same column.** There is
  one participant order, not a user queue and a guest queue.
- **Capacity cannot be exceeded.** No operation grants a seat. Starting and
  reserve are derived by cutting the order, and there are only ever
  `starting_players` positions above the cut.
