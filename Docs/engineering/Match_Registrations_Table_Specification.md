# Match Registration (`match_registrations`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One Medium-severity audit gap and two inherited defects; see §19 and §20 |
| Role | **Engineering Authority** for the physical table `public.match_registrations` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Phase 4.2 |
| Scope | **`public.match_registrations` only.** `matches`, BTGE, team assignments, results, statistics and ratings appear **only as dependencies** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **This document is the authoritative specification for the physical table
> `public.match_registrations`.** Where an implementation and this document
> disagree, **the implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation.**
>
> **It does not redesign approved product behaviour.** The eight decisions
> supplied with the brief — Matches is the aggregate root, every operation
> starts from it, every write locks the match row first, promotion is
> automatic, overlapping registrations are prohibited, match status is partly
> derived, generation follows registration, results follow the match — are
> taken as given and are confirmed throughout. `DD-01` (withdrawal deletes the
> row) is likewise confirmed, and §16.2 shows it is load-bearing for more than
> it was approved for.
>
> **Sibling authorities.** `Profiles_Table_Specification.md` v2.0,
> `Communities_Table_Specification.md` v1.0,
> `Community_Members_Table_Specification.md` v1.0,
> `Community_Invitations_Table_Specification.md` v1.0,
> `Matches_Table_Specification.md` v1.0.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Match Registration** |
| **Physical table** | **`match_registrations`** |

The table was created in migration `0004` and **its structure has never
changed** — no column added, dropped or altered since. Only its read policy was
rewritten, in `0007`, when `group` became `community`. It is the most stable
table in the schema.

**"Registration" always means the claim on a place.** It never means
participation: who actually played, on which team, is the lineup, and §5.2
item 1 is emphatic about the difference.

---

## 1. Purpose

### 1.1 Business purpose

A Match Registration records that **one person has claimed a place in one
match**, and **where in the queue that claim sits**.

It exists because the product's central social problem is not scheduling — it
is **fairness about who gets to play** when more people want a game than the
pitch holds. That problem has exactly three parts, and this table is all three:

1. **Who wants to play** — the row exists.
2. **Who is in** — `status`.
3. **Who is next** — `registration_order`.

Without the third, "first come, first served" would be an intention rather than
a rule, and every promotion would be a judgement someone could dispute.

### 1.2 Business owner

**Product Owner**, as for every table. Contents are owned in three parts:

| What | Owner | Set by |
|---|---|---|
| **That the row exists** | **The player**, for their own registration | Registering; withdrawing |
| **That the row is gone** | The player (withdrawal) **or** an owner/admin (removal) | Withdrawal; removal |
| **`status`** | **The system, exclusively.** No person chooses who is confirmed | Assignment on register; automatic promotion; roster rebalance |
| **`registration_order`** | **The system, exclusively.** It is the arrival sequence | Assignment on register |
| `match_id`, `user_id`, `id`, `created_at` | The database | Nothing writes them after insert |

**Nobody may choose their own status or their own place in the queue.** That is
the whole point: an organiser who could promote a friend, or a player who could
edit their order, would destroy the only fairness guarantee the product makes.

### 1.3 Domain ownership

**Domain: Match. Position: inside the Match aggregate, beneath its root.**

| Property | Value |
|---|---|
| Aggregate | **Member of the Match aggregate**, not a root |
| Aggregate root | `matches` |
| Depends on | `matches` **and** `users` |
| Depended on by | **Nothing, by foreign key** |
| Contains authorization | **No** |

It is an associative entity between a match and a person, and — like
`community_members` between a community and a person — it belongs to the
aggregate, not to the person. **The parallel is exact and the difference
matters:** `community_members` says *this person belongs here now*;
`match_registrations` says *this person claimed a place in this fixture*. The
first is a current fact that a departure erases; the second is a claim on one
occasion that stops mattering once the occasion passes.

### 1.4 Lifecycle ownership

| Bounded by | Consequence |
|---|---|
| **The match** | A registration cannot outlive its match. Deleting the match removes every registration, by cascade |
| **The person** | A registration cannot outlive the account. Deleting the account removes it, by cascade |
| **Not** the community membership | **There is no foreign key to `community_members`, and there must never be one.** §6.4 states why, and §17.1 states what it costs |
| **Not** the clock | A registration is not deleted when the match ends. It persists as the record of who signed up (§4.7) |

---

## 2. Lifecycle

### 2.1 The states, and the shape of the diagram

```
   NOT REGISTERED
         │
         │  register  ── capacity, lock, membership, overlap all checked
         ▼
   ┌─────────────┬──────────────┐
   │  CONFIRMED  │   RESERVE    │   ← chosen by the system, never by the player
   └─────────────┴──────────────┘
         ▲              │
         │   PROMOTED   │  ← AUTOMATIC. A confirmed place is freed
         └──────────────┘
         │              ▲
         │   DEMOTED    │  ← AUTOMATIC. starting_players is lowered
         └──────────────┘
         │
         │  withdraw (self)  OR  remove (owner/admin)
         ▼
   NOT REGISTERED        ← the row is DELETED. Nothing is retained (DD-01)


   HISTORICAL END:  the match ends. The row does not change and is not
                    deleted. It stops being actionable because its match is
                    locked, then completed.
```

### 2.2 Every valid transition

| # | From | To | Trigger | Automatic? |
|---|---|---|---|---|
| 1 | Not registered | **Confirmed** | The player registers, and fewer than `starting_players` registrations are confirmed | Assignment is automatic; the act is not |
| 2 | Not registered | **Reserve** | The player registers, and the confirmed places are taken | Same |
| 3 | **Reserve** → **Confirmed** | A confirmed player withdraws or is removed | **Fully automatic**, same transaction, and the promoted player is notified |
| 4 | **Reserve** → **Confirmed** | An organiser raises `starting_players` | **Fully automatic** — the roster is rebalanced and every mover is notified |
| 5 | **Confirmed** → **Reserve** | An organiser lowers `starting_players` | **Fully automatic** — the only demotion in the product |
| 6 | Confirmed **or** Reserve → Not registered | The player withdraws | The row is **deleted** (`DD-01`) |
| 7 | Confirmed **or** Reserve → Not registered | An owner or admin removes them | The row is deleted; the person is notified, and if they were confirmed a reserve is promoted |
| 8 | Confirmed **or** Reserve → Not registered | The person leaves the community, by the removal path | Cascade of the same cleanup |
| 9 | Any → gone | The match is deleted, or the account is deleted | Cascade |
| 10 | Any → **historical** | The match starts, then ends | **Nothing changes on the row.** §4.7 |

### 2.3 Which transitions are automatic, and why it matters

**Three of the ten are fully automatic**, and all three are status changes
(3, 4, 5). **No person ever chooses a status.** An organiser chooses how many
play; a player chooses whether to be in the queue; the system decides who is
confirmed. That separation is what makes "first come, first served" a rule
rather than a claim.

**Promotion happens in the same transaction as the vacancy** — never on a
timer, never on a sweep, never on the next read. The product has no scheduler
(`DD-05`), and promotion does not need one: the only thing that can create a
vacancy is an operation, and that operation fills it before it returns.

### 2.4 Invalid transitions, and what refuses each

| Invalid | Why | Refused by |
|---|---|---|
| A second registration for the same person in the same match | Two claims on one match would give one person two places, two queue positions, and an ambiguous status | The business key (`MR-C3`), plus the explicit `ALREADY_REGISTERED` check |
| Registering in a match that has started | Registration closes at kick-off (`DD-04`). Someone arriving after the whistle is not in the queue for anything | `MATCH_LOCKED` |
| Registering in a completed match | The roster is the record of a game that happened | `MATCH_CLOSED` |
| Registering when the queue is full | Registration closes at `max_registration`, reserve included (`DD-06`) | `REGISTRATION_CLOSED` |
| Registering while holding a place in an overlapping match | §5.3 — a reserve can be promoted at any moment, so a clash is a clash even when unconfirmed | `OVERLAPPING_MATCH` |
| Registering in a community the person does not belong to | A match is visible to members; a place in it is a member's to take | `NOT_COMMUNITY_MEMBER` |
| Withdrawing after the match has started | The roster that took the field is the record | `MATCH_LOCKED` |
| **Choosing your own status** | Would destroy the fairness guarantee | No write path exists (§11.3) |
| **Editing your registration order** | Same | No write path exists |
| Promoting a specific person out of turn | The queue is the rule; an organiser who could skip it would be making the decision the queue exists to remove | Promotion selects the lowest `registration_order` reserve; there is no operation that names a person |
| A registration in no match, or for nobody | Meaningless | Both foreign keys are NOT NULL |
| Moving a registration to another match | The claim was on *this* occasion | Nothing writes `match_id` after insert (`MR-C13`) |

### 2.5 Re-registration — the cost of withdrawing

Withdrawal **deletes the row** (`DD-01`), and re-registering creates a new one
with `registration_order` = the match's current maximum **plus one**.

**So a player who withdraws goes to the back of the queue.** This is not a
side effect to be corrected — it is the correct outcome, and it should be
stated in the product's terms: a place given up is a place given up. Holding
one, releasing it and reclaiming it ahead of people who waited would be exactly
the unfairness the ordering exists to prevent.

**Orders are never reused and gaps are never closed.** After withdrawals a
match's orders may read 1, 2, 5, 9. Nothing depends on contiguity — the roster
rebalance ranks by order rather than reading it as a position — so gaps are
free, and closing them would mean rewriting other people's rows.

---

## 3. Registration States

Two states. **There is no third, and none may be added** — §3.3.

### 3.1 `confirmed`

| | |
|---|---|
| **Purpose** | The person holds a **place in the starting group**. They are expected to play |
| **Meaning** | Their `registration_order` ranks within the first `starting_players` of the match's registrations |
| **Entry rules** | (a) On registering, when fewer than `starting_players` registrations are currently confirmed; (b) **automatically**, on being the lowest-ordered reserve when a confirmed place is freed; (c) **automatically**, when the organiser raises `starting_players` and the rebalance ranks them inside it |
| **Exit rules** | (a) Withdrawal or removal — the row is deleted, **and a reserve is promoted in the same transaction**; (b) **automatically** to `reserve`, when the organiser lowers `starting_players` below their rank; (c) the match or the account is deleted |
| **What it entitles** | To be in the generation set when teams are drawn, and therefore to appear in the lineup, the result, the statistics and the rating that follow |

### 3.2 `reserve`

| | |
|---|---|
| **Purpose** | The person holds a **place in the queue**. They play if someone drops out |
| **Meaning** | Their `registration_order` ranks beyond the first `starting_players` |
| **Entry rules** | (a) On registering, when the confirmed places are taken; (b) **automatically**, on demotion when `starting_players` is lowered |
| **Exit rules** | (a) **Automatic promotion** to `confirmed`, when a confirmed place is freed and they hold the lowest order among reserves; (b) **automatic promotion**, when `starting_players` is raised; (c) withdrawal or removal — deleted, **with no promotion**, because no confirmed place was freed; (d) cascade |
| **What it entitles** | A place in the queue, and **nothing else**. A reserve is not in the generation set and does not appear in a lineup unless promoted first |
| **What it still costs** | **It blocks an overlapping registration** (§5.3). A reserve can be promoted at any moment, so the clash is real even while unconfirmed |

### 3.3 States that do not exist, and must not be added

| Not a state | Why not |
|---|---|
| `withdrawn` / `cancelled` | Withdrawal **deletes the row** (`DD-01`). A soft-deleted registration would need the business key narrowed to live rows or re-registration would be refused as a duplicate — and §16.2 shows it would break the roster invariant as well |
| `waitlisted` | That is `reserve`. Two names for one state |
| `pending` / `requested` | Registration is self-service and immediate: it succeeds or it fails. Nothing is approved by anyone |
| `attended` / `no_show` | **Attendance is not registration.** The record of who actually played is the lineup (`KB-017`), and §5.2 item 1 is emphatic |
| `declined` | Nobody is invited to a match; players register themselves |

---

## 4. Business Responsibilities

### 4.1 What this table owns

| # | Responsibility | How expressed |
|---|---|---|
| 1 | **Registration state** | `status` — the only two values a claim can have |
| 2 | **Registration order** | `registration_order` — the arrival sequence, unique per match, never reused |
| 3 | **The reserve queue** | `status = 'reserve'` ordered by `registration_order`. The queue is not a separate structure; it is a view of this table |
| 4 | **Promotion eligibility** | The lowest `registration_order` among a match's reserves. Answered by query, never by a flag |
| 5 | **Participation *eligibility*** | A confirmed row is what makes a person eligible to be drawn into a team. **Eligibility, not participation** — see §4.2 item 1 |
| 6 | **Uniqueness of the claim** | One registration per person per match (`MR-C3`) |
| 7 | **The capacity ledger** | The count of rows is what `max_registration` is compared against, and the count of confirmed rows is what `starting_players` is compared against |

### 4.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **Participation — who actually played, and for which team** | `match_team_assignments` | **The distinction is load-bearing.** A confirmed registration says a person *held a seat*; it does not say they turned up, and it does not say which side they were on. `KB-017` defines the lineup as the record of reality including manual changes, and the results phase requires a stored lineup before a result can be recorded precisely because a registration cannot answer "which team" |
| 2 | **Capacity** | `matches.starting_players` and `matches.max_registration` | The terms are the match's; this table is measured against them |
| 3 | **The registration cutoff** | `matches.start_at`, derived (`DD-04`) | A registration has no deadline of its own |
| 4 | **Eligibility to be in the community** | `community_members` | Checked when the row is created and **never re-checked** — §17.1 |
| 5 | **Match status** | `matches.status` | This table's row count feeds it; it does not store it |
| 6 | **Any statistic, counter or rating** | The Level 1 tables; the future Level 2 ones | A registration produces no figure. Only a *result* does |
| 7 | **Notifications** | `notifications` | Promotion and removal cause notices; the notice is not part of the claim |
| 8 | **Any history of withdrawal** | Nowhere, deliberately | `DD-01`. No MVP feature consumes it, and §16.2 shows the deletion is load-bearing |

---

## 5. Business Constraints

### 5.1 Enforced

| ID | Rule | Why it exists |
|---|---|---|
| `MR-C1` | **`match_id` references `matches(id)`, cascading** | A claim on a match that does not exist is not a fact. Cascading because nothing in the Match aggregate outlives its root |
| `MR-C2` | **`user_id` references `users(id)`, cascading** | A claim held by nobody is not a fact. Cascading because a deleted account must not keep occupying a place |
| `MR-C3` | **One registration per person per match** — `(match_id, user_id)` unique | **The business key.** Two rows would give one person two queue positions and two statuses, and every count this table feeds — capacity, confirmed places, the generation set — would double-count them |
| `MR-C4` | **Registration order is unique within a match** — `(match_id, registration_order)` unique | The order *is* the fairness rule. Two people sharing a position would make "who is next" ambiguous at exactly the moment it matters — when one place has been freed and two reserves want it |
| `MR-C5` | **`status` is one of `confirmed`, `reserve`** | Two states, no third (§3.3). A third value would be read as "not confirmed" by the promotion query and as "not reserve" by the generation set — invisible in both |
| `MR-C6` | **`registration_order` is NOT NULL** | A claim with no place in the sequence cannot be ranked, promoted or rebalanced |
| `MR-C7` | **No client may insert, update or delete** | There are **no write policies of any kind**. Every write is a `SECURITY DEFINER` operation. This is what makes it impossible to choose your own status or your own place in the queue |
| `MR-C8` | **`created_at` is NOT NULL** | §12.1 |

### 5.2 Enforced procedurally, inside the match lock

These are the rules the operations carry. They are not schema constraints
because none of them can be — each depends on the match row, on a count across
sibling rows, or on other matches.

| ID | Rule | Why it exists |
|---|---|---|
| `MR-C9` | **Registration closes at `max_registration`** — total rows, reserve included | Registration is capped at the whole queue, not just the starting group, so that a queue does not grow without limit behind a match nobody is leaving |
| `MR-C10` | **A new registration is confirmed only while fewer than `starting_players` are confirmed** | The first `starting_players` arrivals play. This is the fairness rule stated as an assignment |
| `MR-C11` | **`registration_order` is the match's current maximum plus one** | Arrival sequence. Computed inside the match lock, which is what makes it a sequence rather than a race (§8.1) |
| `MR-C12` | **No registration in a match that overlaps one the person already holds** | §5.3 |
| `MR-C13` | **The person must be a member of the match's community, at registration time** | A match is a community's fixture; a place in it is a member's to take. **"At registration time" is exact** — nothing re-checks it (§17.1) |
| `MR-C14` | **Registration and withdrawal are refused once the match is locked or completed** | The roster at kick-off is the roster that played. `DD-04` makes the boundary the clock |
| `MR-C15` | **A freed confirmed place promotes the lowest-ordered reserve, in the same transaction** | Automatic promotion is approved product behaviour. Same transaction because a vacancy that persists past the operation that created it is a vacancy someone can see and nobody can claim |
| `MR-C16` | **Changing `starting_players` rebalances the whole roster by order** | Raising it promotes; lowering it demotes. Ranking by order rather than by current status is what keeps the invariant true (§5.4) |
| `MR-C17` | **`match_id` and `user_id` are immutable after insert** | A claim was made on one occasion by one person. Nothing writes either, so this is a rule to preserve rather than a gap to close |

### 5.3 The overlap rule, stated precisely

**A person may not hold a place in two matches whose times overlap** — where
*hold a place* includes **reserve**.

Three parts, each with a reason:

- **Reserves count.** A reserve can be promoted at any moment, without warning
  and without their involvement. Allowing an overlapping reserve claim would
  mean the product could automatically commit someone to two matches at once.
- **Only live matches count.** The check considers matches that are still open
  or full **and** whose end has not passed. A finished match cannot clash with
  anything.
- **It is protected by locking the person's profile row.** Two simultaneous
  registrations by the same person in two overlapping matches would otherwise
  both pass the check and both insert. Locking the caller's row serialises
  them. This is the *only* reason that lock exists, and the Profiles
  specification records it as a non-obvious dependency (`PR-R7`).

**The lock order is always match first, then person** — never the reverse
(§8.1).

### 5.4 The roster invariant

> **The confirmed registrations of a match are exactly the first
> `starting_players` of its registrations, ordered by `registration_order`.**

This is the product's fairness guarantee expressed as a data property, and it
is maintained by **three independent mechanisms** that never consult each
other:

| Mechanism | How it maintains the invariant |
|---|---|
| **Assignment on register** | New rows take the highest order, and are confirmed only while the confirmed count is below `starting_players` |
| **Promotion on exit** | Promotes the **lowest-ordered** reserve into the place a departure freed |
| **Rebalance on resize** | Recomputes every row's status by rank |

**They agree only because withdrawal deletes the row** — §16.2. And **nothing
verifies the invariant**: it is not a constraint, and no operation checks it
(`MR-R4`).

### 5.5 Deliberately not constrained

| Not constrained | Why not |
|---|---|
| A minimum notice before withdrawing | No approved rule. A player who cannot come is more useful withdrawing late than not withdrawing |
| A limit on how often one person may register and withdraw | The cost is already paid: they go to the back of the queue (§2.5) |
| Contiguity of `registration_order` | Nothing reads it as a position; everything ranks by it (§2.5) |
| A registration deadline separate from `start_at` | The cutoff is the match's, derived from the clock (`DD-04`). A second deadline would be a second answer |
| Attendance, or a no-show marker | Not registration (§4.2 item 1) |

---

## 6. Relationships

### 6.1 Outgoing

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `matches` | `match_id` | many : 1 | **`CASCADE`** | **Identifying.** A claim outside a match is meaningless |
| `users` | `user_id` | many : 1 | **`CASCADE`** | **Identifying.** A claim held by nobody is meaningless |

**Two identifying parents, both cascading** — the same shape as
`community_members`, and for the same reason: this is an associative entity
with no independent existence, and the pair of columns is its real key.

### 6.2 Incoming

**None, by foreign key, and none may be added.**

Nothing references a registration. In particular the **lineup does not**: a
team assignment references the match and the person independently, exactly as
this table does. That is deliberate — §7.2 explains what it buys.

### 6.3 Ownership and deletion

| Question | Answer |
|---|---|
| **Who owns the relationship's meaning?** | The **match**. A registration says *a place in this fixture* |
| **Can it be reparented?** | **No.** Neither column is written after insert (`MR-C17`) |
| **Deletion — inbound** | Deleting the **match** removes it (cascade). Deleting the **account** removes it (cascade). Neither is refused |
| **Deletion — outbound** | Removes nothing. **But it must trigger a promotion**, and that is procedural, not a cascade (`MR-C15`) |
| **Does the match know its registrations?** | **No count is stored on the match.** The count is queried inside the lock, every time |

### 6.4 The deliberate non-relationship: community membership

**There is no foreign key to `community_members`, and there must never be
one.** Membership is checked when the row is created and the row does not
depend on it thereafter.

**This is correct for two reasons:**

1. **A completed match's roster must not change when someone leaves.** A
   cascade from membership would erase a played match's registrations the
   moment a participant left the community — falsifying the record of a game
   other people played in.
2. **Role changes must not touch registrations.** A player promoted to admin
   mid-week keeps their place. A foreign key to a membership row would make a
   registration depend on a row whose role changed underneath it.

**The cost is `MR-R1`**, and it is stated rather than argued away: because
nothing links them, nothing automatically removes a registration when a
membership ends. That cleanup is procedural, and one departure path skips it
(§17.1).

---

## 7. Columns

Six columns. **One further column is specified as required and is absent** —
`updated_at`, §7.3.

### 7.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `match_id` | `uuid` | No | none | **Never** |
| 3 | `user_id` | `uuid` | No | none | **Never** |
| 4 | `status` | `text` | No | **none** | **System only** |
| 5 | `registration_order` | `int` | No | **none** | **Never** |
| 6 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| — | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** | **← required, absent (§7.3)** |

**This table's write model is already correct**, and is the model the rest of
the schema should follow: there are **no write policies at all**, so no client
can write any column by any route. Where `matches` needs a rule withdrawn and
`communities` needs column privileges added, this table needs neither.

### 7.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated, never editable**

*Purpose.* Row identity.

*Business justification — and an honest one.* Nothing references it: no foreign
key, no client read, and every operation addresses rows by `(match_id,
user_id)` or by the promotion query. It is used **once**, internally: the
withdrawal and removal paths select the registration row and then delete it by
`id`, having already found it by the business key.

**Retained, not defended** — the same position the Community Members
specification takes on its surrogate. The business key is what does the work
(§9.2).

---

**2. `match_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Which match the place is claimed in. Half of the business key.

*Business justification.* It is the scoping column of everything this table
does: capacity is per match, order is per match, the queue is per match, and
the lock that makes all of it safe is on the match row this column names.

*Never editable.* A claim was made on one occasion; moving it would move a
person's queue position into a match they never joined.

---

**3. `user_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Who claimed the place. The other half of the business key.

*Business justification.* It is the User Profile's primary key, which is also
the authentication identity — so the withdrawal path can find "my registration"
with a column comparison rather than a lookup, and the overlap check can scope
to the caller directly.

*Never editable.* A place is not transferable. A person who cannot come
withdraws, and the queue decides who takes it — which is exactly the decision
the queue exists to make. **A transferable registration would let a departing
player hand their place to a friend ahead of the reserves**, which is the
unfairness this table was built to prevent.

---

**4. `status` — `text`, NOT NULL, no default, two values, system only**

*Purpose.* Whether this claim is a **place in the game** or a **place in the
queue**.

*Business justification.* It is what every consumer reads: the roster screen
renders it, the generation set filters on it, and the promotion query selects
by it.

*No default — deliberately.* Unlike `matches.status`, which is born `open`,
there is no correct default here: the value depends on how many places are
already taken, which only the registering operation knows. A default would be
a value that is right by luck.

*System only.* Nobody chooses their status (§1.2). There is no write policy, so
this is enforced by absence rather than by restriction.

*It is fully derivable, and it is stored anyway.* §17.2 examines this as a
duplicated responsibility and concludes it should stay — the decisive reason
being that **notifications are driven by status *transitions***, and a
transition cannot be detected in a value that was never stored.

---

**5. `registration_order` — `int`, NOT NULL, no default, never editable**

*Purpose.* **The arrival sequence.** The fairness rule, made a number.

*Business justification.* Everything about who plays follows from it: who is
confirmed on arrival, who is promoted when a place frees, and how the roster
re-sorts when the organiser changes the size. Without it, promotion would be a
choice, and every choice would be arguable.

*Assigned as the match's current maximum plus one, inside the match lock.* The
lock is what makes it a sequence — two concurrent registrations would otherwise
compute the same maximum and one would violate `MR-C4`.

*Not `created_at`, and not a global sequence.* A timestamp shared by two rows
in one transaction cannot order them, and a global sequence would leak how many
registrations the whole application has. A per-match integer is the smallest
thing that answers the only question asked of it.

*Never reused, never renumbered* (§2.5).

*Never editable — by anyone.* An organiser who could edit it could promote a
friend without appearing to.

---

**6. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When the place was claimed.

*Business justification.* It is **not** the ordering — `registration_order` is,
and §7.2 column 5 explains why a timestamp cannot be. It answers *when did I
sign up*, which is what a player asks when they are surprised to be on the
reserve list.

---

### 7.3 `updated_at` — specified as **required**, and absent

**`status` is mutable — it is the single most consequential mutation in the
product's social contract — and nothing records when it changes.**

A player promoted from reserve to confirmed has no timestamp for it. Neither
does a player demoted when an organiser shrank the match. The notification
records that it happened; the row does not record when.

**This is the same gap the Community Members specification records as
`CMB-R3`**, and it deviates from `Docs/07-Database-Design.md` §*Standards*,
which lists `created_at`/`updated_at` as the rule for the schema.

**It is not the same as the Community Invitations case**, where `updated_at`
was correctly refused because `revoked_at` already recorded the one mutation.
**Here there is no such column** — the mutation writes only `status`, and
`status` carries no time.

*Specification:* `timestamptz`, NOT NULL, default `now()`, maintained by a
trigger, never writer-supplied.

Recorded as `MR-R2` and §20 item 1.

---

## 8. Concurrency

Not a required section; included because this table's correctness rests
entirely on it, and leaving it implicit would leave a design decision open.

### 8.1 The lock discipline

**Every write to this table happens inside an exclusive lock on the match
row**, taken first, by the operation. That is approved architecture and it is
confirmed here. What this table adds:

| Operation | Locks | Why in this order |
|---|---|---|
| Register | **Match**, then the **caller's profile row** | The match lock serialises seat allocation and order assignment for the fixture; the profile lock serialises *this person's* registrations **across** matches, which is what makes the overlap check safe (§5.3) |
| Withdraw, Remove | **Match** | Deletion and the promotion it triggers must be one atomic step |
| Rebalance | Inherits the caller's **match** lock | Called only from the match edit path |

**The order is always match → person, never person → match.** A future
operation that reverses it will deadlock against registration.

### 8.2 What the lock buys

Four races that would otherwise exist, closed by one lock:

1. **Two people taking the last place.** Both would count the same total.
2. **Two registrations computing the same `registration_order`.** One would
   violate `MR-C4` — visible as an error rather than corruption, but an error
   the user did not cause.
3. **Two promotions of the same reserve**, from a simultaneous withdrawal and
   removal.
4. **A rebalance racing a withdrawal**, leaving statuses that match neither the
   old nor the new `starting_players`.

### 8.3 The cost, stated plainly

**Registration for one match is serialised: one transaction at a time.** For a
30-player match this is irrelevant. It is recorded because it is the deliberate
trade — correctness over throughput — and because a future optimisation that
weakens it reopens all four races (`MR-R6`).

---

## 9. Keys

This table has the richest key structure in the schema: **a primary key, a
business key, and a second alternate key.**

### 9.1 Primary key

**`id`** — a generated `uuid`, and a surrogate with almost no consumer (§7.2
column 1).

### 9.2 Business key

**`(match_id, user_id)`.**

This is the key the domain actually uses. It states the central rule — **one
registration per person per match** — and it is how every operation addresses a
row: the duplicate check, the withdrawal lookup, the removal lookup, the
membership purge.

It is immutable in both columns, NOT NULL in both, and unique by constraint.
**It is what the primary key would be in a design that started from the
domain.**

### 9.3 Candidate keys

| Candidate | Enforced | Assessment |
|---|---|---|
| `id` | Primary key | Generated, immutable, meaningless, near-unused |
| **`(match_id, user_id)`** | Unique | **The business key** (§9.2) |
| **`(match_id, registration_order)`** | Unique | **A second alternate key** (§9.4) |

### 9.4 Alternate keys

**Two**, and they are alternate keys of different kinds:

| Alternate key | What it guarantees | Why it is a key rather than a constraint |
|---|---|---|
| `(match_id, user_id)` | One claim per person per match | It identifies a row uniquely and is how the domain names one |
| `(match_id, registration_order)` | **One person per queue position** | It also identifies a row uniquely — *the third person who registered for this match* is a complete address |

**The second is unusual and worth naming as a key rather than as a uniqueness
rule**, because it is the fairness guarantee in structural form: if two rows
could share a position, "who is next" would have two answers at exactly the
moment one place is free.

### 9.5 Foreign keys

**Outgoing — two, both identifying, both cascading:**

| Column | References | On delete |
|---|---|---|
| `match_id` | `matches(id)` | **`CASCADE`** |
| `user_id` | `users(id)` | **`CASCADE`** |

**Incoming — none, and none may be added** (§6.2).

---

## 10. Index Strategy

**Four indexes, each with a distinct driving query and none redundant.** This
is the best-formed index set in the schema, and it is worth saying so — the
`community_members` set contains a redundant index and `matches` and `users`
each carry an unused one.

### 10.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `MR-X1` | **Unique on `(match_id, user_id)`** | (a) the `ALREADY_REGISTERED` check on every registration; (b) the withdrawal lookup — *my registration in this match*; (c) the removal lookup; (d) the membership-purge lookup. **And by its leading column alone**, every "this match's roster" query |
| `MR-X2` | **Unique on `(match_id, registration_order)`** | (a) `max(registration_order)` for the next order — a backward scan on the prefix, inside the lock, on **every** registration; (b) the roster read, which orders by `registration_order` within one match; (c) the rebalance, which ranks by it |
| `MR-X3` | **`(match_id, status, registration_order)`** | **The promotion query**, exactly: *the lowest-ordered reserve of this match*. Equality on the first two columns, ordered on the third — the index answers it without a sort, and promotion runs inside a lock on the product's most contended path |
| `MR-X4` | **`(user_id)`** | (a) **the overlap check**, which scans one person's registrations and joins to matches — the leading driver, since neither `MR-X1` nor `MR-X2` has `user_id` first; (b) the membership purge, which finds one person's registrations across a community's matches; (c) administrative account deletion |

### 10.2 Why `MR-X3` is not redundant against `MR-X2`

Both begin with `match_id`, so the question is fair. **They serve different
shapes:**

- `MR-X2` is `(match_id, registration_order)`. The promotion query would use it
  to scan a match's rows in order and **filter each on `status`** — reading
  every confirmed row before reaching the first reserve.
- `MR-X3` is `(match_id, status, registration_order)`. It seeks straight to the
  first reserve.

On a full 30-player match the difference is scanning up to `starting_players`
rows versus one, on the hot path, inside a lock. **Both are justified.**

### 10.3 Considered and not required

| Candidate | Verdict | Reasoning |
|---|---|---|
| `(user_id, match_id)` | **No** | `MR-X4` plus the join to `matches` by primary key already serves the overlap check; a composite adds nothing |
| `(status)` | **No** | No selectivity — two values — and nothing filters by status across matches |
| `(created_at)` | **No** | Nothing orders by it; `registration_order` is the ordering |
| Anything for capacity counting | **No** | `count(*) where match_id = ?` is served by `MR-X1`'s leading column |

### 10.4 The rule for a future designer

> **This table is addressed by match, by match-and-person, or by person.** An
> index serving anything else means a query is asking this table something that
> belongs to `matches` or to the lineup.

---

## 11. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 11.1 The matrix

| Actor | Read | Register | Withdraw | Remove | Promote | Update | Delete |
|---|---|---|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Non-member** | ✗ **Nothing** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Member — player** | ✓ **Full roster of any match in their communities** | ✓ **Themselves only** | ✓ **Themselves only** | ✗ | ✗ | ✗ | ✗ |
| **Community Admin** | ✓ Same | ✓ Themselves | ✓ Themselves | ✓ **Any registrant** | ✗ | ✗ | ✗ |
| **Community Owner** | ✓ Same | ✓ Themselves | ✓ Themselves | ✓ Any registrant | ✗ | ✗ | ✗ |
| **System Administrator** | ✗ **No direct path** | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ Transitively |
| **The system** | — | — | — | — | ✓ **Only actor** | ✓ Only actor | ✓ |

**Promote and Update have no human actor at all.** Promotion is a consequence,
never a command: there is no operation by which a person promotes a named
reserve, and adding one would replace the queue with a choice. `Update` is
likewise the system's — status is the only mutable column, and only the three
automatic mechanisms write it.

### 11.2 Read

**Membership of the match's community grants sight of the full roster**, with
every registrant's status and order.

**Why the whole roster and not just one's own row:** the queue is the fairness
guarantee, and a guarantee nobody can see is not one. A reserve must be able to
see how many people are ahead of them — otherwise "you are next" is something
they have to take on trust.

**Non-members see nothing**, consistent with `matches`: a community's fixtures
and their rosters are members' business.

**System Administrator has no read path**, and none is proposed. The
administrative match listing shows a registration **count**, never the names.

### 11.3 Write — all of it

**There are no write policies of any kind on this table**, for insert, update
or delete. Every write is a `SECURITY DEFINER` operation, and the absence of a
policy is the statement of the rule.

**This is the strongest write model in the schema, and it is the right one
here more than anywhere else**, because two of this table's columns are values
people would want to change about themselves: their status, and their place in
the queue. **A row-level "your own registration" write rule would be a
disaster** — it would let any player set their own status to `confirmed` and
their own order to `0`. The table is protected not by restricting a write path
but by having none.

`matches`, by contrast, has a row-level update rule that no writer needs
(`MT-R1`). **This table is what that one should look like.**

### 11.4 The asymmetry between withdraw and remove

| | Withdraw | Remove |
|---|---|---|
| Who | The registrant | Owner or admin |
| Target | Only themselves | Any registrant |
| Notifies the person? | No — they did it | **Yes** |
| Promotes a reserve? | Yes, if they were confirmed | Yes, if they were confirmed |
| Refused once locked? | Yes | Yes |

An organiser **cannot remove themselves** through the removal path — they
withdraw like anyone else. And **there is no self-removal exemption from the
lock**: once the match starts, nobody leaves the roster, organiser included.

---

## 12. Audit

| Column | Required? | State | Verdict |
|---|---|---|---|
| `created_at` | **Required** | Present | §12.1 |
| `updated_at` | **Required** | **ABSENT** | §7.3, `MR-R2` — the gap |
| `created_by` | **Not required** | Absent | §12.2 |
| `updated_by` | **Not required** | Absent | §12.3 — and the reasoning is unlike every other table |

### 12.1 `created_at` — required, present

When the place was claimed. **Not the ordering** — `registration_order` is
(§7.2 column 5). It answers *when did I sign up*, and it is the only thing that
can, because the order number is relative to one match.

### 12.2 `created_by` — not required

Registration is self-service: a player registers themselves and nobody else
can. **There is no operation by which an organiser adds a person to a match.**
So `created_by` would equal `user_id` on every row that will ever exist — the
same argument that refused it on `community_members`.

**The condition under which this changes:** if an organiser is ever able to add
a player directly, `created_by` stops being derivable and becomes required.
Recorded as `MR-D2`.

### 12.3 `updated_by` — not required, and for a reason unique to this table

Elsewhere `updated_by` is **refused** under `UP-4`, because a mutable
last-writer column is erased by the next write.

**Here it is not required at all, for a prior reason: there is no human writer
to record.** The only mutation is a status change, and all three paths that
cause one are **automatic consequences**, not acts:

- A promotion is caused by someone *withdrawing* — that person did not promote
  anyone; the system did.
- A demotion is caused by an organiser *resizing the match* — they did not
  demote a named person; the rebalance did.

**Recording the acting user would be actively misleading**: it would name
someone who did not make the decision, on a row that is not theirs. The truthful
answer to "who promoted this player" is *the queue*, and the queue is
`registration_order`.

**What is genuinely missing is *when*, not *who*** — which is `updated_at`
(§7.3), not `updated_by`.

---

## 13. Dependencies

### 13.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `matches` | Identifying parent, cascading | **Owns the scope, the lifetime, the capacity terms and the lock.** Supplies `starting_players`, `max_registration`, `start_at`, `end_at` and `community_id` — every value the operations test against |
| `users` | Identifying parent, cascading | Owns the person. Also supplies the **row locked to serialise the overlap check** (§5.3) |
| `community_members` | **Not a foreign key — an authorization and eligibility dependency** | Answers who may read the roster, who may register, and who may remove. Checked at registration time and never again (§17.1) |

### 13.2 Tables depending on this table

**None, by foreign key** (§6.2).

**By behaviour, three**, and the distinction between them is important:

| Consumer | How it depends |
|---|---|
| `matches` | Its `status` is recomputed from this table's row count after every change here. **The dependency runs upward**, which is unusual and is examined in §17.3 |
| Team generation | Reads the **confirmed** registrations as its generation set. This is a read at one instant; nothing is retained |
| `notifications` | Promotion, demotion, removal and match edits each produce a notice naming the affected registrant |

**What does *not* depend on this table:** the lineup, the result, the goals, the
rating history and every statistic. All of them reference the match and the
person directly. **A registration is upstream of the game, not part of its
record.**

---

## 14. Future Compatibility

### 14.1 BTGE — built, no change required

The engine's **generation set is this table's confirmed registrations** for one
match, resolved at the moment generation runs.

**Three properties keep this stable:**

- **The engine reads, never writes.** No engine output is stored here — not the
  team, not the assigned position, not the balance score. All of it is the
  lineup's.
- **`status` is the only column the engine consults**, and only as a filter.
  `registration_order` is not an input: arrival order says nothing about how
  good a player is, and using it would be behavioural inference of exactly the
  kind `KB-014` forbids.
- **`OP-2`'s minimum of four is enforced on the match**, not here. This table
  cannot know whether a set is large enough; the match's `starting_players`
  already refuses it at creation.

### 14.2 Team assignments — built, no change required

**The lineup is a separate record and must stay one.** It references the match
and the person, not the registration (§6.2).

**Why that separation is required rather than merely tidy:** `KB-017` defines
the lineup as *the lineup that actually played, including any manual change*.
An organiser may move a player between teams after generation, and may field
someone the roster did not confirm. A lineup bound to a registration could not
express either.

**Consequence to keep in view:** *confirmed* and *played* are different sets,
and nothing reconciles them. That is correct — but it means this table can
never be used to answer "did this person play" (§4.2 item 1).

### 14.3 Results — built, no change required

A result references the match; its participants are read from the **lineup**,
never from this table. `RR-7 A1` makes a stored lineup a precondition for
recording a result precisely because a registration cannot say which team
someone was on.

**So this table is not in the results path at all**, and a change to it cannot
affect a recorded result.

### 14.4 Statistics — Level 1 built, Level 2 approved, no change required

**No statistic is derived from a registration.** `A4` is explicit: statistics
arise **only from a recorded result**. A match that was registered for, played
and never recorded produces nothing at either level.

**So registering is not participating for any counter**, and the six Level 1
counters plus every future Level 2 counter are fed from the result and the
lineup. This table contributes nothing and needs no column for them.

### 14.5 Ratings — built, no change required

A rating moves only as a consequence of a recorded result, by the winner /
loser / goal / MVP deltas, applied over the **lineup**. **No rating of either
level is stored here, and registration order has no effect on any rating.**

### 14.6 Leaderboards — not built, no change required, no index

Boards read Level 2 records and filter by community membership at read time.
**This table is not read by a board**, in any period. It is two steps upstream
of the records a board consumes.

### 14.7 The general rule

> **A new column on `match_registrations` must be a property of the claim
> itself, must not describe what happened in the match, and must not be a
> measure.** Anything about the game as played belongs to the lineup or the
> result; anything that accumulates belongs to a statistics record.

---

## 15. Engineering Rationale

### 15.1 The order number is the product

Most of this table is one integer. `registration_order` is what turns "first
come, first served" from a promise into a mechanism: it decides who is
confirmed on arrival, who is promoted when a place frees, and how the roster
re-sorts when the organiser changes the size. Everything else here exists to
support it or to be derived from it.

### 15.2 `DD-01` is load-bearing beyond its stated reason

`DD-01` approved hard deletion on withdrawal so that a player can re-register.
**It also silently guarantees the roster invariant.**

Three mechanisms maintain "the first `starting_players` by order are confirmed"
without consulting each other (§5.4), and they agree **only because a withdrawn
row is gone**. If withdrawal became a soft delete, promotion — which promotes
the lowest-ordered reserve — would no longer produce the same set as the
rebalance, which ranks over all rows. The two would diverge silently, and the
first symptom would be a roster nobody could explain.

**Anyone revisiting `DD-01` must read §5.4 first.**

### 15.3 The table has no write policies, and that is the design

Two of its columns are values people would want to change about themselves.
Protecting them with a restricted write rule would be an invitation to get the
restriction wrong; having no write path at all cannot be got wrong. §11.3.

### 15.4 Status is stored, because notifications need a transition

`status` is fully derivable (§17.2). It is stored because the product notifies
people when it changes — *you have been promoted*, *you have been moved to the
reserve list* — and a change can only be detected against a previous value that
was written down.

### 15.5 One lock, four races

§8.2. The match row is the single serialisation point, and it closes the last
place, the duplicate order, the double promotion and the racing rebalance
together. The cost is that registration for one match is serialised, which for
a 30-player fixture is not a cost.

---

## 16. Engineering Review

The brief asks for ownership violations, duplicated responsibilities, race
conditions, lifecycle inconsistencies and performance risks. **Six findings.**

### 16.1 Ownership violation — none on this table

**This is the first table in the phase with no ownership violation.** There is
no write policy, so no client can write any column; every mutation is a
`SECURITY DEFINER` operation; and no column that should be system-managed is
reachable. The defects found on `communities` (`CM-R2`) and `matches`
(`MT-R1`) have no analogue here.

**The violation that touches this table originates elsewhere** — §17.1.

### 16.2 Duplicated responsibility — `status` is fully derivable

`status` is exactly `row_number() over (order by registration_order) <=
matches.starting_players`. It is a **pure cache** of a rank, and the rebalance
computes precisely that expression.

**Assessment: keep it.** Two reasons, and the second is decisive:

- Deriving it on read would need the match's `starting_players` and a window
  function on every roster render.
- **Notifications are driven by transitions** (§15.4). A derived status has no
  previous value to compare against, so *you have been promoted* could not be
  sent.

**The cost is real and is `MR-R4`:** three mechanisms maintain the invariant,
none consults the others, and **nothing verifies it**. There is no constraint
that can express a cross-row rank rule, and no operation checks it.

**Recommendation: state the invariant (§5.4) and add a verification to the
integration suite**, not to the schema.

### 16.3 Race conditions — one open, outside this table's operations

**Within this table's own operations: none.** The match lock closes all four
races (§8.2), and the profile lock closes the overlap race.

**One risk remains, and it belongs to a writer of this table rather than to
this table:** the membership-purge path iterates a person's registrations
across a community's matches and takes a lock on **each match row in an
unordered sequence**. Two such purges running concurrently over overlapping
match sets can acquire the same two locks in opposite orders and **deadlock**.

- **Reachable when:** two members are removed from the same community
  simultaneously, and both hold registrations in at least two matches in
  common.
- **Probability:** low. **Consequence:** one transaction is aborted by the
  database; the removal fails with a deadlock error rather than corrupting
  anything.
- **Fix:** order the loop deterministically — by match id — so all callers
  acquire in the same sequence.

Recorded as `MR-R5`. **The fix belongs to that operation, not to this table.**

### 16.4 Lifecycle inconsistency — the account-deletion path does not promote

Administrative account deletion first purges the person's memberships, which
correctly releases their registrations **and promotes reserves**. It then
performs a blanket delete of any remaining registrations for that person —
**with no promotion.**

Those leftovers exist only in one circumstance: **a registration held by
someone who is no longer a member**, which is `CMB-R1`. So a confirmed place
freed by deleting such an account leaves the reserve queue untouched, and a
match keeps an empty confirmed slot with people waiting behind it.

Recorded as `MR-R3`. **Low severity, because it is reachable only through
another table's defect** — but it is a second place where the same root cause
surfaces, and closing `CMB-R1` does not close this one.

### 16.5 Lifecycle inconsistency — eligibility is checked once and never again

§17.1. Membership is a precondition of registering and is not a condition of
*holding* a registration.

### 16.6 Performance risks — two, both acceptable

| Risk | Assessment |
|---|---|
| **Registration for one match is serialised** (§8.3) | **Acceptable and deliberate.** A 30-player match cannot generate contention that matters. It is recorded because a future optimisation that weakens the lock reopens four races |
| **`max(registration_order)` is computed per insert** | **Acceptable.** `MR-X2` makes it a backward index scan on the prefix — one row read. The alternative, a per-match sequence, would need its own table and would not survive a match being deleted |

**No index is missing, and none is redundant** (§10).

### 16.7 Summary

| Finding | Verdict |
|---|---|
| Ownership violations | **None** — §16.1 |
| Duplicated responsibility — derivable `status` | **Keep; verify the invariant in tests** — `MR-R4` |
| Race conditions — within this table | **None** |
| Race conditions — the purge loop's lock order | **Open**, `MR-R5`, fix belongs to that operation |
| Lifecycle — deletion path does not promote | **Open**, `MR-R3` |
| Lifecycle — eligibility checked once | **Open**, `MR-R1`, inherited |
| Performance | **Two, both acceptable** |

**No approved product behaviour is redesigned by any of the above.**

---

## 17. Findings inherited from other tables

### 17.1 `MR-R1` — a registration may be held by a non-member

Membership is checked when a registration is created (`MR-C13`) and **never
re-checked**. Because there is no foreign key to `community_members` — which is
correct (§6.4) — nothing removes a registration when a membership ends.

**The removal path handles it correctly.** The **self-departure path does
not**: a person who leaves a community by deleting their own membership row
keeps every registration they held in it.

**What that produces, traced to the end:**

| Step | Consequence |
|---|---|
| 1 | A confirmed place is held by a non-member |
| 2 | It counts against the match's `max_registration`, so someone else is refused |
| 3 | The row still appears on the roster — the read rule governs who may *read*, not whose rows are shown — but **nothing indicates that the holder has left**, so an organiser sees an ordinary registrant |
| 4 | **They are in the generation set**, so the engine may draw them into a team |
| 5 | They may then appear in the lineup, the result, and the ratings and statistics that follow |

**The defect is `CMB-R1` and belongs to `community_members`.** It is recorded
here because this table is where the bad data sits, and because step 4 shows
the blast radius reaching further than that document states.

### 17.2 `MR-R7` — the roster shows registrations, not membership

Following from §17.1: the roster read returns every registration of a match to
any member of its community. It does **not** verify that each registrant is
still a member, and there is no column that could say so.

**This is correct behaviour, not a defect** — a completed match's roster must
show who signed up, including people who have since left. It is recorded so it
is not mistaken for a leak of a departed person's presence.

---

## 18. Validation

**Contradictions are named, not resolved silently.**

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | `Docs/01-PRD.md` | **No contradiction** | *Match registration with a reserve list and automatic promotion* is §2 and §3. The role matrix places *view the community, join and withdraw from matches* with all three roles, and *manage a roster* with admin and owner — exactly §11.1 |
| 2 | `Docs/06-ERD.md` | **No contradiction** | §2's *"a registration is unique per `(match_id, user_id)`, and `registration_order` is unique per match"* is `MR-C3` and `MR-C4`. §6's *"registration order decides who starts"* is §5.4; *"no two registrations for one person in overlapping live matches"* is §5.3; *"withdrawing deletes the registration row, which is what allows re-registering"* is `DD-01` |
| 3 | **Database Principles** | **No artifact in the repository** | Seventh phase in which this is recorded. Validated against `07-Database-Design.md` §Standards, `SUPABASE_OPERATIONAL_GUIDELINES.md` §2 and §4, and `ARCHITECTURE_DECISIONS_V1.md`. **One deviation from the Standards** — §18.1 |
| 4 | `Profiles_Table_Specification.md` v2.0 | **No contradiction; one dependency confirmed** | `user_id` → `users(id)` cascading matches its §5.2 Group A. **Its `PR-R7`** — the profile row used as a per-user mutex — is this table's overlap protection (§5.3), and this document states the same fact from the other side |
| 5 | `Communities_Table_Specification.md` v1.0 | **No contradiction** | This table reaches the community only through the match. Deleting a community removes these rows transitively, which its §6.4 step 3 performs explicitly |
| 6 | `Community_Members_Table_Specification.md` v1.0 | **One inherited defect, with wider reach than recorded there** | Its `CMB-R1` lands here as `MR-R1`. **§17.1 traces it two steps further than that document does** — into the generation set, the lineup and the resulting statistics. Its §6.4 is what §6.4 here confirms from the other side |
| 7 | `Matches_Table_Specification.md` v1.0 | **No contradiction** | Its `MT-R6` names the same symptom this document details as `MR-R1`. Its §5.4 lock discipline is §8.1 here. Its `MT-C13` — never trust `status` — is why the overlap check tests `end_at` as well as status (§5.3) |
| 8 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction** | `A4`: statistics arise only from a recorded result, so a registration produces no figure (§14.4). No board reads this table |
| 9 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction** | `RR-7 A1` — a stored lineup is required before a result, because a confirmed registration does not say which team — is §4.2 item 1 and §14.3 |
| 10 | `engineering/BTGE_Engineering_Specification.md` | **No contradiction** | The generation set is the confirmed registrations; `registration_order` is not an input, and using it would be the behavioural inference `KB-014` forbids (§14.1) |
| 11 | `Docs/10-Design-Decisions.md` | **No contradiction** | `DD-01` (withdrawal deletes the row) is confirmed and §15.2 shows it carries more weight than its stated reason. `DD-04`, `DD-06`, `PD-06`, `PD-07` all hold |
| 12 | `Docs/07-Database-Design.md` | **One deviation** | §18.1 |
| 13 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **No contradiction** | §4's checklist is satisfied in full: RLS enabled, access explicit (a read policy and deliberately no write policies), authorization via `has_community_role`, `SECURITY DEFINER` helpers with pinned `search_path` and revoked from client roles, not broadly readable |

### 18.1 Deviation — the Standards require `updated_at`; this table has none

`Docs/07-Database-Design.md` §*Standards* states the rule as *"UUID primary
keys, `created_at` / `updated_at` audit columns."* This table has `created_at`
and no `updated_at`, while `status` is written by three separate mechanisms.

**Not resolved silently.** Specified as required in §7.3, recorded as `MR-R2`,
listed in §20 item 1.

**This is the second table in the phase with the same gap** — the first being
`community_members`, also an associative entity with a mutable status-like
column. **The two should be closed together**, and the shared cause is worth
noting: both were created early, and both acquired their mutability afterwards.

---

## 19. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `MR-R1` | **A registration may be held by a non-member**, occupying a confirmed place, counting against capacity, and **entering the generation set** — so a departed person can be drawn into a lineup, a result and the ratings that follow | **Medium** | **Inherited** — the defect is `CMB-R1`. §17.1 traces the full reach. Closing it there closes this |
| `MR-R2` | **No `updated_at`.** Promotion and demotion — the most consequential events in the product's fairness contract — are untimestamped. Deviates from the project's own Standards | **Medium** | **Open**, §20 item 1 |
| `MR-R3` | **Administrative account deletion removes leftover registrations without promoting reserves**, leaving an empty confirmed place with people waiting | Low | **Open**, §20 item 2. Reachable only through `CMB-R1`, and **not** closed by fixing it |
| `MR-R4` | **The roster invariant is maintained by three mechanisms and verified by none.** No constraint can express a cross-row rank rule | Low | **Open**, §20 item 3. Recommendation: assert it in the integration suite |
| `MR-R5` | **The membership-purge loop takes match locks in an unordered sequence**, so two concurrent purges over overlapping match sets can deadlock | Low | **Open**, §20 item 4. The fix belongs to that operation — order the loop by match id |
| `MR-R6` | **Registration for one match is fully serialised.** A future optimisation that weakens the match lock reopens four races at once | Low, **and by design** | **Accepted** (§8.3). Recorded so the trade is deliberate |
| `MR-R7` | **The roster shows people who have since left the community**, with no indication that they have | Low | **Accepted, and correct** (§17.2). A completed match's roster is a historical record |
| `MR-R8` | **A withdrawn registration leaves no trace**, so a match that filled and emptied repeatedly looks the same as one nobody wanted | Low | **Accepted by design** (`DD-01`). No MVP feature consumes withdrawal history, and §15.2 shows the deletion is load-bearing |

---

## 20. Open Decisions

| ID | Question | Recommendation |
|---|---|---|
| `MR-D1` | **Add `updated_at`?** | **Yes**, and close it together with the identical gap on `community_members`. Existing rows take the migration's timestamp, which is honest — the schema does not know when their statuses last changed and must not invent it (`UP-2`'s principle) |
| `MR-D2` | **Will an organiser ever be able to add a player to a match directly?** | **Not approved, and not recommended.** Self-service registration is what makes `created_by` derivable and the queue defensible — a place granted by an organiser is a place taken out of turn. If it is ever added, `created_by` becomes required (§12.2) |
| `MR-D3` | **Should the roster invariant be verified?** | **Yes, in the integration suite**, not in the schema — a cross-row rank rule cannot be a constraint, and a trigger checking it would fire inside the rebalance's own intermediate states |
| `MR-D4` | **Is withdrawal history required?** | **No.** `DD-01` is confirmed, and §15.2 shows the hard delete is load-bearing for the roster invariant. If it is ever wanted, it is an append-only table — **not** a status value here, which would break §5.4 |

---

## 21. Conformance — where the built schema differs from this specification

| # | Deviation | Required by | Severity | Notes for the implementing phase |
|---|---|---|---|---|
| 1 | **No `updated_at`** | §7.3, `MR-C8` neighbour | **Medium** | Add with a `BEFORE UPDATE` trigger, matching every other table. Close together with `community_members` (§18.1) |
| 2 | **Account deletion does not promote when removing leftover registrations** | `MR-C15` | Low | The blanket delete should route through the same promotion path the purge uses. Note that fixing `CMB-R1` removes the *source* of leftovers but not this path's behaviour |
| 3 | **The roster invariant is unverified** | §5.4 | Low | `MR-D3`. Integration assertion, not a constraint |
| 4 | **The purge loop's lock order is non-deterministic** | §16.3 | Low | Order by match id. **Belongs to `purge_membership`, not to this table** |

**Everything else conforms.** The structure, the keys, all four indexes, the
read rule and the complete absence of write policies are exactly as specified —
the closest match between specification and implementation in the phase so far.

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched.

---

## 22. Engineering Approval

**Status: Engineering Approved — conditional.**

This document is the authoritative engineering specification for
`public.match_registrations`. It is **conditional** on §21 item 1, the
`updated_at` gap. **There is no High-severity finding on this table** — the
first in the phase.

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5` | ✓ |
| Business purpose, business owner, domain ownership, **lifecycle ownership** | ✓ §1, all four |
| **Complete lifecycle** — ten valid transitions, twelve invalid ones, and which are automatic | ✓ §2 |
| **Business responsibilities** — owned and not owned | ✓ §4, 7 + 8 |
| **Registration states** — purpose, meaning, entry rules, exit rules for each; five refused | ✓ §3 |
| Relationships: incoming, outgoing, ownership, deletion, lifecycle | ✓ §6 |
| Every column — name, purpose, type, nullability, default, editability, justification | ✓ 6 present + 1 specified-and-absent |
| Every business constraint with its reason | ✓ 17 |
| Keys: primary, **business key**, candidate, **two alternate keys**, foreign | ✓ §9 |
| Index strategy: four indexes, each with a distinct driving query, none redundant | ✓ §10 |
| Access control: player, owner, admin, member, non-member, System Administrator × read/register/withdraw/remove/promote/update/delete | ✓ §11 |
| Audit: all four columns ruled on | ✓ §12 |
| Dependencies both directions | ✓ §13 |
| Future compatibility: BTGE, team assignments, results, statistics, ratings, leaderboards | ✓ §14, six of six |
| **Engineering review** — ownership violations, duplicated responsibilities, race conditions, lifecycle inconsistencies, performance risks | ✓ §16, six findings |
| Validation; contradictions named, not resolved | ✓ 13 sources, **1 deviation + 1 inherited defect traced further** |
| No SQL, no migration, no implementation, no other table designed | ✓ |

### What must happen before the table is implementation-conformant

1. **§21 item 1** — `updated_at`. The only conditional item.
2. §21 items 2–4 — all Low, and two of them belong to operations on other
   tables.

### Validation caveat, stated rather than glossed

The brief names *Database Principles* as a validation source. **It does not
exist as a document in this repository** — the seventh phase in which this has
been recorded. Validation used the principles in `07-Database-Design.md`,
`SUPABASE_OPERATIONAL_GUIDELINES.md` and `ARCHITECTURE_DECISIONS_V1.md`. If it
exists outside the repository, this specification has not been checked against
it.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Matches_Table_Specification.md` | **Parent authority.** Its §5.4 lock discipline is this table's correctness; its `MT-R6` is this table's `MR-R1` |
| `engineering/Community_Members_Table_Specification.md` | Supplies eligibility and authorization. **Its `CMB-R1` is this table's `MR-R1`**, and §17.1 traces it further than that document does. Both tables share the `updated_at` gap |
| `engineering/Profiles_Table_Specification.md` | `user_id` → `users(id)`; **its `PR-R7`** — the profile row as a per-user mutex — is this table's overlap protection |
| `engineering/Communities_Table_Specification.md` | Reached only through the match |
| `Docs/01-PRD.md` | *Reserve list and automatic promotion*; the role matrix |
| `Docs/06-ERD.md` | §2 (the two uniqueness rules), §6 (order decides who starts; the overlap rule; `DD-01`) |
| `Docs/10-Design-Decisions.md` | **`DD-01`** — load-bearing beyond its stated reason (§15.2); `DD-04`, `DD-06` |
| `engineering/BTGE_Engineering_Specification.md` | The generation set is the confirmed registrations; `KB-014` is why order is not an input |
| `engineering/Results_Rating_Engineering_Decisions.md` | `RR-7 A1` — a registration cannot say which team, which is why the lineup exists |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | `A4` — statistics arise only from a recorded result |
| `Docs/07-Database-Design.md` | §Standards — **one deviation**, §18.1 |
