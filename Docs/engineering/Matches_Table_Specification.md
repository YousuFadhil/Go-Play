# Match (`matches`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One High-severity defect must be closed; see §19 and §21 |
| Role | **Engineering Authority** for the physical table `public.matches` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Phase 4 |
| Scope | **`public.matches` only.** `match_registrations`, `match_team_assignments`, BTGE, results, statistics and ratings appear **only as dependent entities** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **This document is the authoritative specification for the physical table
> `public.matches`.** Where an implementation and this document disagree,
> **the implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation.** It is a design
> record, complete enough that the table can be implemented without a further
> engineering decision — except for the items in §20.
>
> **It does not redesign approved product behaviour.** The three-status
> lifecycle (`DD-03`), derived locking (`DD-04`), lazy derived completion with
> no scheduler (`DD-05`), derived capacity (`DD-06`) and time-independent
> deletion (`DD-07`) are confirmed unchanged. §17 reviews the *architecture
> around* them, as the brief requires, and recommends no change to any of them.
>
> **Sibling authorities.** `Profiles_Table_Specification.md` v2.0,
> `Communities_Table_Specification.md` v1.0,
> `Community_Members_Table_Specification.md` v1.0,
> `Community_Invitations_Table_Specification.md` v1.0.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Match** |
| **Physical table** | **`matches`** |

The table was created in migration `0003` with a `group_id` column, renamed to
`community_id` in `0007`. **The name `group_id` is retired.**

**"Match" always means the fixture** — a scheduled game with a time, a place and
a roster. It never means a result, a lineup or a registration; each of those is
a separate entity beneath this one (§5.2).

---

## 1. Purpose

A Match is **one scheduled game of football belonging to one community**.

It exists for three reasons:

1. **It is the unit the product is organised around.** A community exists to
   play matches; every screen below the community list is about one.
2. **It is the aggregate root of everything that happens in a game** — who
   registered, who started, who was on which team, what the score was, who
   scored and who was named MVP. Six tables hang beneath it (§13.2), and §5
   states why they hang here rather than anywhere else.
3. **It is the concurrency boundary.** Every mutation anywhere in the Match
   aggregate takes a lock on the match row first, without exception (§5.4).
   That single discipline is what makes registration, promotion, roster
   rebalancing and result recording safe under concurrency, and it is the
   strongest evidence that this is the root.

**What a Match is deliberately not:**

- **It is not owned by its creator.** A match belongs to a **community**, never
  to the person who created it. `created_by` is audit attribution and is never
  read to grant anything (`PD-16`, `PD-07`).
- **It is not a venue booking.** `location` is free text. `fields` was in the
  v2 model and is out of scope (`06-ERD.md` §1).
- **It is not a result.** A match that has been played and a match whose result
  has been recorded are different things, and the second is a row in another
  table (§5.2).
- **It is not a roster.** It carries capacity, not people.

---

## 2. Business Owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That the match exists** | **The community's owner and admins** | Creation |
| `title`, `location`, `description`, `start_at`, `end_at`, `starting_players` | **The community's owner and admins** | The edit operation |
| `max_registration` | **The system — derived** (`DD-06`) | The capacity trigger, from `starting_players` + the global reserve |
| `status` | **The system — derived** (`DD-03`, `DD-05`) | Status recomputation, lazily |
| `community_id`, `created_by`, `id`, `created_at` | **The database** | Nothing writes them after insert |
| `updated_at` | **The database** | Trigger |

**Note the shape of this table's ownership: six editable columns and two
derived ones, with no user preference among them.** Every column is either an
organiser's decision about a fixture or a value the system computes. There is
no column a *player* may write — participation is expressed in
`match_registrations`, never here.

---

## 3. Domain Ownership

**Domain: Match. Position: root of the Match aggregate, which is nested inside
the Community aggregate.**

| Property | Value |
|---|---|
| Aggregate | **Root of the Match aggregate** |
| Nested inside | The **Community** aggregate, whose root is `communities` |
| Depends on | `communities` and `users` |
| Depended on by | Six tables (§13.2) |
| Contains authorization | **No.** It is *scoped* by authorization; it stores none |

**This nesting is the single most important structural fact about the table**,
and it is what keeps two things from being confused:

| Question | Answered by |
|---|---|
| **May this person do this to this match?** | **The Community aggregate** — `has_community_role(community_id, …)`. The match contributes only its `community_id` |
| **What happens to everything under this match?** | **The Match aggregate** — this table's own root responsibilities (§5) |

So a match is *governed from above* and *governs below*. `created_by` looks
like a third answer and is not (`PD-16`).

---

## 4. Lifecycle

### 4.1 The model: three stored states, three derived ones

The brief's example lifecycle has eight stages. **The product stores three.**
The other five are derived — from the clock, or from rows in other tables — and
that is a decision, not an omission (`DD-03`, `DD-04`, `DD-05`).

| # | Conceptual stage | How it is represented | Stored? |
|---|---|---|---|
| 1 | **Create** | Row inserted, `status = 'open'` | ✔ stored |
| 2 | **Open Registration** | `status = 'open'` and `start_at > now` | ✔ stored (partly) |
| 3 | **Registration Full** *(optional)* | `status = 'full'` — registrations reached `max_registration` | ✔ stored |
| 4 | **Registration Closed** | **Derived: `start_at <= now`.** The match is *locked* (`DD-04`) | ✘ derived from the clock |
| 5 | **Teams Generated** | **Not a match state.** Rows exist in the lineup table | ✘ another table |
| 6 | **Match Played** | **Derived: `end_at <= now`** | ✘ derived from the clock |
| 7 | **Result Recorded** | **Not a match state.** A row exists in the result table | ✘ another table |
| 8 | **Completed** | `status = 'completed'` | ✔ stored, **lazily** |

**Why five stages are not stored:**

- **Locking and playing are functions of the clock** (`DD-04`). A stored "locked"
  flag would need something to set it at the exact minute a match starts —
  which means a scheduler, which `DD-05` declined to introduce. A derived
  answer is correct at every instant without anything running.
- **"Teams generated" and "result recorded" are the existence of rows
  elsewhere.** Copying them onto the match would be a second answer to a
  question another table already answers, free to disagree with it — the same
  argument that keeps counters off `communities` and the rating off
  `player_statistics` (`RR-6`).

### 4.2 The stored status column, precisely

`status` holds exactly three values (`DD-03`) and is **derived from two
independent facts**:

| Value | Meaning | Derived from |
|---|---|---|
| `open` | Accepting registrations | Registration count **<** `max_registration` |
| `full` | Registration closed by capacity | Registration count **>=** `max_registration` |
| `completed` | The scheduled end has passed | The **clock**: `end_at <= now` |

**Two consequences that must be understood rather than fixed:**

1. **`completed` overwrites the fill state.** Once a match completes, the
   database no longer records whether it had been full. Nothing in the product
   asks, so nothing is lost — but a future report that asks will not find the
   answer here.
2. **The column is routinely stale, by design** (`DD-05`). Completion is
   written back *lazily* — by whichever operation next touches the row. A match
   that ended an hour ago and that nobody has touched still reads `open`.

**Therefore: every consumer must derive, never trust.** The codebase already
does — every guard reads `status = 'completed' **or** end_at <= now()`, and the
upcoming-matches query filters on `end_at`, not on `status`. **This is a rule,
not an observation** (`MT-C13`): any new consumer that trusts `status` alone
will be wrong about every match nobody has touched since it ended.

### 4.3 Valid transitions

| From | To | Trigger | Notes |
|---|---|---|---|
| *(none)* | `open` | Creation | The only entry point. A match is always born open |
| `open` | `full` | A registration brings the count to `max_registration` | Recomputed after every roster change |
| `full` | `open` | A withdrawal or removal frees a place; or `starting_players` is raised | **Reversible, and this is deliberate** — capacity is not a one-way door |
| `open` | `completed` | `end_at` passes, observed lazily | Never scheduled |
| `full` | `completed` | Same | Same |
| *(any)* | *(deleted)* | Deletion | Time-independent (`DD-07`) |

**`completed` is terminal.** No transition leaves it. A completed match is
read-only for every organiser operation: editing, roster changes and
registration all refuse it.

### 4.4 Invalid transitions, and what refuses each

| Invalid | Why | Refused by |
|---|---|---|
| `completed` → `open` or `full` | Un-completing a match would reopen registration for a game already played, and would invalidate any result recorded against it | Status recomputation returns early once `end_at <= now`; every organiser guard raises `MATCH_COMPLETED` |
| Registration into a locked match (`start_at <= now`) | Registration closes when the match starts (`DD-04`). Someone arriving after kick-off is not a participant | `MATCH_LOCKED` in the registration path |
| Withdrawal after the match started | The roster that took the field is the record of who played | `MATCH_LOCKED` |
| Editing a locked or completed match | Its time, place and size were the terms people registered under | `MATCH_LOCKED` / `MATCH_COMPLETED` in the edit operation |
| Reducing `starting_players` below the number already registered | Would leave registrations with no place to occupy | `MAX_BELOW_REGISTERED` |
| Any status value outside the three | A fourth value has no defined behaviour in any guard | The status constraint (`MT-C10`) |
| A match belonging to no community, or moving between communities | §6.3 | `community_id` is NOT NULL; nothing may write it after insert (`MT-C14`, **unenforced** — `MT-R1`) |
| `end_at` at or before `start_at` | A match with no duration cannot be played, locked or completed coherently | `MT-C8` |

**Every one of these refusals lives in an operation, not in the schema.** That
is the finding of §17.2: the guards are real, and there is a write path that
does not pass through them.

---

## 5. Aggregate Root

### 5.1 Why the Match is the root of the Match Domain

Four properties, and the fourth is the decisive one:

1. **Every consistency rule below it is scoped to one match and spans several
   tables.** *The first `starting_players` registrations are confirmed and the
   rest are reserve.* *Registration order is unique per match.* *Every player is
   assigned to exactly one team.* *No team has two goalkeepers.* *A match has at
   most one result, naming exactly one MVP.* None is expressible on a single
   table; all are bounded by one match.
2. **Everything beneath it is meaningless without it.** A registration, a team
   assignment, a result, a goal and a rating entry all answer *"in which
   match?"* first. All six cascade with it.
3. **It carries the terms the rest are evaluated against.** `starting_players`
   decides who is confirmed; `max_registration` decides when registration
   closes; `start_at` and `end_at` decide what is locked and what is played.
   Those are the match's own state, and everything below reads them.
4. **It is the lock.** §5.4.

**And it is nested.** The Match aggregate does not own authorization or its own
lifetime — both belong to the Community above it (§3). A root that is itself a
member of a larger aggregate is exactly what a match is, and stating it
prevents the two mistakes: reading `created_by` as authority, and expecting a
match to survive its community.

### 5.2 Operations that must originate from the Match

Each takes a match id, resolves authority through the match's `community_id`,
and locks the match row first.

| # | Operation | Who | Why it must originate here |
|---|---|---|---|
| 1 | **Register** | Any community member | Capacity, lock state and the confirmed/reserve split are all read from the match row |
| 2 | **Withdraw** | The registered person | Freeing a place changes the match's fill state and may promote someone |
| 3 | **Reserve promotion** | The system, as a consequence of 2, 4 or 8 | Promotion order is a property of the match's roster, not of any one registration |
| 4 | **Remove a player** | Owner, admin | Same as 2, performed by someone else |
| 5 | **Roster rebalance** | The system, when `starting_players` changes | Which registrations are confirmed is a function of the match's own capacity |
| 6 | **Recompute status** | The system, after every roster change | §4.2 |
| 7 | **Derive capacity** | The system, on insert and whenever `starting_players` changes | `DD-06` |
| 8 | **Generate teams / adjust them manually** | Owner, admin | The generation set is the match's confirmed roster; the lineup is per match |
| 9 | **Record a result** | Owner, admin | A result is *of* a match, and reaches its participants only through the match's stored lineup |
| 10 | **Correct a result** | Owner, admin | Reverses against the same match's lineup before reapplying |
| 11 | **Edit the match** | Owner, admin | The match's own state |
| 12 | **Delete the match** | Owner, admin; System Admin | Only the root can order the disposal of its aggregate (§6.4) |

**No operation in this domain may bypass the match.** A registration created
without reading the match would not know whether it is confirmed; a result
recorded without one could not find its participants.

### 5.3 The invariants the root is responsible for

| # | Invariant | Enforced by | Structural? |
|---|---|---|---|
| `MT-AR1` | **A match belongs to exactly one community, for its whole life** | `community_id` NOT NULL; no operation writes it after insert | **No** — a direct update can move it (`MT-R1`) |
| `MT-AR2` | **`max_registration` = `starting_players` + the global reserve** | The capacity trigger | **Partly** — recomputed on every insert, but on update **only when `starting_players` changes** (`MT-R2`) |
| `MT-AR3` | **`status` reflects fill and time** | Status recomputation after every roster change | **No, and deliberately approximate** — lazily written, so routinely stale (`DD-05`, §4.2) |
| `MT-AR4` | **A locked or completed match is not modified** | Guards in every organiser operation | **No** — a direct update bypasses them (`MT-R1`) |
| `MT-AR5` | **Everything beneath the match dies with it** | Cascades on all six children, plus the ordered deletion path | **Yes** |
| `MT-AR6` | **Every mutation in the aggregate serialises on the match row** | Lock discipline, §5.4 | **By discipline** — see below |

### 5.4 The match row is the concurrency boundary

**Every operation that writes anything in the Match aggregate takes an
exclusive lock on the match row before doing anything else.** Registration,
withdrawal, removal, editing, deletion, roster rebalance and membership purge
all do it, and the roster-purge path does it once per match it touches, with the
comment *"same lock order as every other roster write: match row first."*

**This is what makes the aggregate safe**, and it is worth stating as a rule
because it is invisible in the schema:

> **A new operation touching anything under a match must lock the match row
> first. A single writer that does not will reintroduce every race the
> discipline currently prevents** — two registrations taking the last place,
> two promotions of the same reserve, a rebalance racing a withdrawal.

One deliberate exception in ordering: registration locks the **match** and then
the **caller's profile row**, the latter serialising one person's registrations
across *different* matches so the overlap check cannot race itself. The order
is always match-then-person, never the reverse.

---

## 6. Relationships

### 6.1 Outgoing — what a Match depends on

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `communities` | `community_id` | many : 1 | **`CASCADE`** | **Identifying.** The match is meaningless outside its community and must not survive it |
| `users` | `created_by` | many : 1 | **no action** | **Attribution only.** Never authorization (`PD-16`) |

**Why `created_by` deliberately does not cascade.** If it did, deleting an
account would silently destroy matches — with their results, lineups and the
statistics those produced — in *other people's communities*. The refusal is what
forces `admin_delete_user` to dispose of them explicitly and in order. This is
the same reasoning `communities.owner_id` uses, and the Profiles specification
records both as its "Group C" references.

### 6.2 Incoming — what depends on a Match

**Six foreign keys, six tables. Referenced here only as dependents.**

| Table | On delete | Relationship |
|---|---|---|
| `match_registrations` | `CASCADE` | Who signed up, and in what order |
| `match_team_assignments` | `CASCADE` | The lineup that actually played |
| `match_results` | `CASCADE` | At most one per match |
| `match_goals` | `CASCADE` *(via the result)* | Reached through the result, not the match |
| `rating_history` | `CASCADE` | Every rating change a match caused |
| `notifications` | **`SET NULL`** | The one exception — §6.4 |

### 6.3 Ownership

| Question | Answer |
|---|---|
| **Who owns the match's meaning?** | The **community**. A match says *of this community*; that is what scopes its statistics, its authorization and its audience |
| **Can a match be reparented?** | **No, and this is emphatic.** Moving a match to another community would carry its results, its goals and its rating history with it — corrupting both communities' future Level 2 figures, which are scoped by `community_id` through the match. No operation does it; nothing structural prevents it (`MT-R1`) |
| **Does the match know its children?** | **No.** No count, no roster snapshot, no "has result" flag, no "teams generated" flag. §4.1 and `MT-C15` |
| **Who owns the children's meaning?** | The match. Each answers *"in which match?"* first |

### 6.4 Deletion behaviour

**Deletion is hard, time-independent and ordered.**

`DD-07` makes it time-independent: a match may be deleted whether or not it has
started or ended. That is approved product behaviour and is not revisited here.

**The order, and why each step is where it is:**

| Step | What | Why here |
|---|---|---|
| 1 | Lock the match row | §5.4 |
| 2 | **Notify every registered player** | Notifications must be written **before** the match goes, because they reference it. `notifications.match_id` is `SET NULL` (`DD-08`), so the notice survives the match it describes — which is the entire point of a "match deleted" message |
| 3 | Delete registrations | Explicit, though the cascade would also do it |
| 4 | **Delete the match row** | Fires the reversal trigger — below — then cascades the lineup, the result, the goals and the rating history |

**Deleting a match reverses everything it caused.** A `BEFORE DELETE` trigger
reverses the result's effects: every participant's Global Rating and career
counters move back by exactly what that match awarded (`RR-4`, `RR-5`). This is
correct — a match that no longer exists must not still be counted — and it is
the mechanism by which `DD-07`'s time-independence stays safe.

**A note on a comment that came due.** Migration `0006` said deletion *"becomes
protected only once the match is historical (recorded result, statistics,
ratings)… none of those exist at this MVP stage, so no such guard is added yet —
add it here when those features land."* **They landed** in migration `0022`.
The guard was **not** added, and that is correct rather than outstanding: the
results phase answered the same problem with *reversal* instead of *refusal*,
and `DD-07` keeps deletion time-independent. Recorded so the comment is not read
as an open task (§20 item 4).

### 6.5 Lifecycle ownership

| Relationship | Whose lifetime bounds whose |
|---|---|
| `communities` → `matches` | **The community bounds the match, absolutely.** A match cannot outlive it |
| `users` → `matches` | **Neither bounds the other.** A match outlives its creator's departure; an account cannot be deleted while it created matches, until those are disposed of explicitly |
| `matches` → its six children | **The match bounds all six**, absolutely — except `notifications`, which is deliberately released rather than destroyed (§6.4) |
| `matches` → Level 2 statistics *(unbuilt)* | **Indirect.** Deleting a match reverses the figures it produced; it does not delete a statistics record, which belongs to *(player, community)* and outlives every individual match |

---

## 7. Columns

Thirteen columns.

### 7.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `community_id` | `uuid` | No | none | **Never** |
| 3 | `created_by` | `uuid` | No | none | **Never** |
| 4 | `title` | `text` | No | none | Owner, admin |
| 5 | `location` | `text` | No | none | Owner, admin |
| 6 | `description` | `text` | **Yes** | `null` | Owner, admin |
| 7 | `start_at` | `timestamptz` | No | none | Owner, admin |
| 8 | `end_at` | `timestamptz` | No | none | Owner, admin |
| 9 | `starting_players` | `int` | No | none | Owner, admin |
| 10 | `max_registration` | `int` | No | **derived** | **System only** |
| 11 | `status` | `text` | No | `'open'` | **System only** |
| 12 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| 13 | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** |

> **The built schema does not enforce this column.** A row-level update rule
> with no column restriction lets an admin write **every one of these
> thirteen**, including the two marked *System only* and the three marked
> *Never*. This is `MT-R1`, the most serious finding in this document, and §17.2
> shows the fix is simpler here than on `communities`.

### 7.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated, never editable**

*Purpose.* The identity of the match, and the scope of its entire aggregate.

*Business justification.* Six tables key on it, every operation in the domain
takes it as its first argument, and it is the row the lock is taken on (§5.4).
Generated randomly rather than sequentially because match ids appear in shared
deep links.

---

**2. `community_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Which community this match belongs to.

*Business justification.* It answers three separate questions with one value:
**who may see it** (community members), **who may manage it** (owner and admins,
via `has_community_role`), and **whose statistics it feeds** (`SL-2`'s isolation
requirement is expressed by scoping Level 2 records to `community_id`, reached
through the match). A match belongs to a community and never to its creator —
`06-ERD.md` §2 states it, and this column is the whole of the mechanism.

*NOT NULL, no default.* A match belonging to nobody has no audience, no
managers and no statistics home.

*Never editable — and this is emphatic.* §6.3.

---

**3. `created_by` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Who created the match. **Attribution and display only.**

*Business justification, and the warning that goes with it.* `PD-16` and
`06-ERD.md` §4 are explicit: **this column is never read to grant or deny
anything.** It was authority once — until `0008`, editing and deleting a match
were the creator's privilege — and `PD-07` moved that to the community role.
The column stayed because "who organised this" is worth showing.

**The one place it appears in a rule is not an exception.** The creation rule
requires `created_by` to equal the caller — that keeps the audit field honest by
stopping someone stamping another person as organiser; it is not what grants the
insert, which is the role check beside it.

*NOT NULL with no cascade.* §6.1.

---

**4. `title` — `text`, NOT NULL, 2–60 characters trimmed, editable by owner and
admin**

*Purpose.* What the match is called. The label in every list and notification.

*Business justification.* `DD-12` made it required. Before that it was optional
and screens fell back to the location, which meant a list of matches at the same
pitch was a list of identical rows. Existing rows were backfilled from their
location once — the value the interface was already showing — and **no title is
ever generated for a new match**: the organiser types one.

*The bound matches `communities.name`'s upper half* (60 vs 50) — both are
single-line labels, and the product has one answer to how long a label may be.

---

**5. `location` — `text`, NOT NULL, 2–100 characters trimmed, editable by owner
and admin**

*Purpose.* Where the match is played, as free text.

*Business justification.* Amateur communities play at pitches that have names
people know, not addresses in a database. A `fields` entity was considered in
the v2 model and left out of scope; free text is what the product actually
needs, and it costs nothing to replace later because nothing references it.

*NOT NULL.* A match nobody can find is not organised.

---

**6. `description` — `text`, NULLABLE, default `null`, editable by owner and
admin**

*Purpose.* Optional free text — what to bring, which gate, the shirt colour.

*Business justification.* Optional because most matches need nothing beyond a
time and a place. Bounded at 300 characters because it is a note, not a
document.

*Null is the only way to say "none"* (`MT-C7`). The edit operation already
normalises an empty string to null; creation must do the same. This is the same
rule the Communities specification states for its `description`.

---

**7. `start_at` — `timestamptz`, NOT NULL, no default, editable by owner and
admin**

*Purpose.* When the match begins. **And the lock boundary.**

*Business justification.* It carries two jobs and both are load-bearing: it is
what players plan around, and it is the instant at which the match closes to
registration and to organiser edits (`DD-04`). A stored "locked" flag would need
something to set it at that instant; deriving it means the answer is correct at
every instant with nothing running.

*`timestamptz`, always.* A match has a real instant, and communities may
travel. Storing a wall-clock time would make "has it started" depend on who is
asking.

---

**8. `end_at` — `timestamptz`, NOT NULL, no default, editable by owner and
admin**

*Purpose.* When the match finishes. **And the completion boundary.**

*Business justification.* Completion is derived from it (`DD-05`), so it is not
merely informational: it is what makes a match read-only, what makes its result
recordable in the product's own terms, and what the overlap check uses to decide
whether two matches clash.

*Strictly after `start_at`* (`MT-C8`). A zero-length match would be
simultaneously not-yet-started and already-completed.

---

**9. `starting_players` — `int`, NOT NULL, 4–30, editable by owner and admin**

*Purpose.* How many players take the field. **The organiser's only capacity
input.**

*Business justification.* It decides two things: how many registrations are
confirmed rather than reserve, and — with the global reserve setting — where
registration closes (`DD-06`).

*Minimum 4, not 2.* The approved `OP-2` decision, 2 v 2, applied to the product
as a whole rather than to team generation alone: **a match Go Play does not
support should not be creatable in the first place.** It supersedes both the
earlier approval of 6 and the original schema range of 2.

*Maximum 30.* Thirty a side is already beyond any format the product serves;
the bound exists to catch a typo, not to express a rule.

*Changing it rebalances the roster.* Raising it promotes reserves; lowering it
demotes the tail. Both notify. That is why the edit path is an operation and not
a column write — and why `MT-R1` matters (§17.2).

---

**10. `max_registration` — `int`, NOT NULL, derived, system only**

*Purpose.* Where registration closes: the last place anyone may take.

*Business justification.* **It is derived, never supplied** (`DD-06`):
`starting_players` + the single global reserve allowance in `app_settings`. The
organiser chooses the size of the game; the *reserve depth* is one
application-wide decision, so that every community's matches behave the same
way and an organiser cannot accidentally create a match with no reserve.

*Stored rather than computed on read* — a denormalisation, and a justified one:
it is read on **every** registration attempt, inside a lock, and recomputing it
would mean reading `app_settings` on the hottest path in the product. Storing it
also freezes the reserve depth a match was created under, so changing the global
setting does not silently re-size matches people have already registered for.

*System only, maintained by a trigger* on insert and whenever
`starting_players` changes. **The trigger does not fire on an update that
touches only this column**, which is how a derived value becomes directly
writable (`MT-R2`).

*Its own bound is 2–60 and is not the product minimum.* That constraint governs
a derived value; `OP-2`'s minimum of 4 lives on `starting_players`, and
narrowing this one was deliberately not part of that decision.

---

**11. `status` — `text`, NOT NULL, default `'open'`, three values, system only**

*Purpose.* The stored half of the lifecycle (§4.2).

*Business justification.* `DD-03` reduced the lifecycle to three states by
removing `draft`, `cancelled` and `postponed`. Each of the three removed states
was either a product feature nobody asked for (draft), or deletion by another
name (cancelled), or an edit (postponed). Three states, all derivable, none
requiring an organiser to remember to set anything.

*Derived from two independent sources* — registrations and the clock — and
**written back lazily**, so it is routinely stale (§4.2). Every consumer must
derive rather than trust (`MT-C13`).

*System only.* Nothing about a match's status is an organiser's choice: it is a
consequence of how many people registered and what time it is.

---

**12. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When the match was created. Required audit (§12).

*Business justification.* It is **not** the match's ordering — `start_at` is,
in every list the product renders. It answers when the fixture was announced,
which is the question asked when a player says they never saw it.

---

**13. `updated_at` — `timestamptz`, NOT NULL, default `now()`, trigger only**

*Purpose.* When the row last changed. Required audit (§12).

*Business justification.* Several writers touch this row — the edit operation,
the capacity trigger, status recomputation. Trigger-maintained because a
timestamp each writer must remember is one a writer will forget, and here two of
the writers are triggers themselves.

---

## 8. Keys

### 8.1 Primary key

**`id`** — a generated `uuid`.

A surrogate, and unlike `community_members.id` it has substantial consumers:
six foreign keys, every operation in the domain, the lock, and shared deep
links. Random rather than sequential so that a match id in a URL does not let
someone enumerate a community's fixtures by counting.

### 8.2 Candidate keys

**`id` only.** Stated explicitly because the question will be asked:

| Attribute | Candidate key? | Why not |
|---|---|---|
| `id` | **Yes — primary** | Generated, immutable, meaningless |
| `(community_id, start_at)` | **No** | A community may legitimately run two matches at once — two pitches, two age groups. Making this unique would refuse a real fixture |
| `(community_id, title)` | **No** | Titles repeat by design: *Friday Football* every Friday |
| `(community_id, title, start_at)` | **No** | Still not guaranteed, and it would make a title change a key change |

### 8.3 Alternate keys

**None**, and none should be added. Every natural combination either refuses a
legitimate fixture or depends on a mutable column. A match is identified by its
surrogate key alone.

### 8.4 Foreign keys

**Outgoing — two:**

| Column | References | On delete |
|---|---|---|
| `community_id` | `communities(id)` | **`CASCADE`** |
| `created_by` | `users(id)` | **no action** |

**Incoming — six**, catalogued in §6.2. All target `id`.

---

## 9. Business Constraints

### 9.1 Enforced

| ID | Rule | Why it exists |
|---|---|---|
| `MT-C1` | **Primary key on `id`** | One row per match; the scope of the whole aggregate |
| `MT-C2` | **`community_id` references `communities(id)`, cascading** | **Community ownership.** A match belongs to exactly one community. Cascading because nothing in the aggregate may outlive the community |
| `MT-C3` | **`created_by` references `users(id)`, no cascade** | **Organizer attribution.** The creator must be a real account, and the absence of a cascade prevents an account deletion silently destroying matches in other communities (§6.1) |
| `MT-C4` | **Creation requires `admin` or above in the match's community, and `created_by` must be the caller** | `PD-06` narrowed match creation from any member to owner and admin. The `created_by` half keeps the audit field honest; it is not what grants the insert |
| `MT-C5` | **`title` NOT NULL, 2–60 characters trimmed** | Every match has a name (`DD-12`). Two characters minimum because a one-character title identifies nothing in a list |
| `MT-C6` | **`location` NOT NULL, 2–100 characters trimmed** | A match nobody can find is not organised |
| `MT-C7` | **`description` optional, at most 300 characters** | A note, not a document |
| `MT-C8` | **`end_at` strictly after `start_at`** | A zero-length match would be simultaneously not-started and completed, and every derived state would contradict itself |
| `MT-C9` | **`starting_players` between 4 and 30** | **`OP-2`**, approved: the minimum supported match is 2 v 2, applied to the product as a whole. A match the product cannot serve should not be creatable |
| `MT-C10` | **`status` NOT NULL, one of `open`, `full`, `completed`** | `DD-03`. A fourth value has no defined behaviour in any guard, and would be read as "not completed" by every check that tests for completion |
| `MT-C11` | **`max_registration` between 2 and 60, and never below `starting_players`** | Registration must not close before the starting eleven is filled. The 2–60 bound governs a derived value and is deliberately **not** the product minimum (§7.2, column 10) |
| `MT-C12` | **`max_registration` is derived, never supplied** | `DD-06`. Reserve depth is one application-wide decision, so matches behave the same everywhere and no organiser can create one with no reserve |

### 9.2 Specified here, not enforced

| ID | Rule | Why it exists | State |
|---|---|---|---|
| `MT-C13` | **No consumer may trust `status` alone; completion must be derived** | The column is lazily written and therefore routinely stale (`DD-05`, §4.2). Every existing guard already reads `status = 'completed' or end_at <= now()` | Held by convention across the codebase; nothing enforces it for a new consumer |
| `MT-C14` | **`community_id` and `created_by` are immutable after insert** | Reparenting a match carries its results, goals and rating history into another community's figures (§6.3). Rewriting `created_by` falsifies attribution | **Not enforced** — a direct update writes both (`MT-R1`) |
| `MT-C15` | **`status` and `max_registration` are unreachable by any client write** | Both are derived. A client-written `status` bypasses recomputation; a client-written `max_registration` breaks `DD-06`'s derivation outright | **Not enforced** — `MT-R1`, `MT-R2` |
| `MT-C16` | **A locked or completed match is not modified, by any path** | Its time, place and size were the terms people registered under; a completed match is the record of a game that happened | **Not enforced structurally** — the guards live in the edit operation, which a direct update bypasses (`MT-R1`) |
| `MT-C17` | **Stored `title` and `location` are the trimmed values** | The constraints validate the trimmed form. The edit operation trims; **creation does not**, so a title may be stored with surrounding whitespace that the constraint was checked against but the table does not hold | **Regression on the create path** — `MT-R4` |
| `MT-C18` | **`description` is null when absent, never an empty string** | Two ways to express "no description" is one too many. The edit operation already normalises; creation does not | Not enforced on create |

### 9.3 Deliberately not constrained

| Not constrained | Why not |
|---|---|
| **A match may not be created in the past** | Deliberately absent. `DD-07` already makes deletion time-independent, and an organiser recording a fixture that has just finished is a real case. It would also be a Product Decision, taken in a schema |
| **Deletion restricted once a result exists** | `DD-07` makes deletion time-independent, and the results phase answered the same concern with *reversal* rather than *refusal* (§6.4) |
| Two matches at the same time in one community | Two pitches, two age groups. Refusing it would refuse a real fixture (§8.2) |
| A maximum number of matches per community | No approved rule |
| `location` as a reference to a venue entity | `fields` is out of MVP scope |
| A minimum notice period before `start_at` | No approved rule; would refuse a match arranged an hour beforehand, which is exactly how amateur football works |

---

## 10. Index Strategy

### 10.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `MT-X1` | **Primary key on `id`** | Everything: (a) the row lock every operation in the aggregate takes first (§5.4); (b) the six incoming foreign keys' integrity checks; (c) the match details screen; (d) every guard, which loads the match row before deciding anything |
| `MT-X2` | **`(community_id, start_at)`** | (a) the community's match list, which is filtered by community and ordered by start time — the product's second-most-used screen; (b) any community-scoped date-range scan, including the future Level 2 period bucketing (§14.3), which selects a community's matches within a window |

### 10.2 Present, without a driving query

| ID | Index | Assessment |
|---|---|---|
| `MT-X3` | **`(status)`** | **No query is driven by it.** Nothing in the codebase filters matches by status alone: the upcoming-matches screen filters on `end_at`, the community list on `community_id`, the admin console orders by `start_at`, and every guard reaches its match by primary key. The one predicate mentioning status — the overlapping-match check — is driven from the registration side by `user_id` and reaches matches by primary key. The column is also **low-cardinality (three values) and skewed**, so it would be a poor driver even if a query wanted one |

**Recommendation: retain for now, record it.** Unlike the redundant index on
`community_members`, this one is not duplicated work — it is simply unused, and
`matches` is not a high-write table. Dropping it is a candidate for whenever
this table is next touched (§20 item 5).

### 10.3 Considered and not required

| Candidate | Verdict | Reasoning |
|---|---|---|
| `(end_at)` | **Not yet** | The upcoming-matches screen filters on it **across all communities**, which `MT-X2` cannot serve. It is the strongest candidate for the first real index need — but at three communities and ten matches it is a sequential scan over a trivial table. **Revisit on measurement**, and it is the one to add first |
| `(created_by)` | **No** | The only reader is the administrative account deletion, which is rare, and the table is small |
| `(community_id, status)` | **No** | Nothing filters by both, and status is a poor index column (§10.2) |
| Anything for the overlap check | **No** | Driven from `match_registrations(user_id)`, which already exists on that table |

### 10.4 The rule for a future designer

> **`matches` is reached by primary key, or by community and date.** An index
> serving anything else should be justified by a measured plan, not by the shape
> of a screen.

---

## 11. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 11.1 The matrix

| Actor | Read | Create | Update | Delete | Record result | Generate teams |
|---|---|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Non-member** | ✗ **Nothing** | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Member — `player`** | ✓ **All matches of communities they belong to** | ✗ | ✗ | ✗ | ✗ | ✗ *(may read the lineup)* |
| **Community Admin** | ✓ Same | ✓ | ✓ **Through the edit operation only** | ✓ | ✓ | ✓ |
| **Community Owner** | ✓ Same | ✓ | ✓ Same | ✓ | ✓ | ✓ |
| **System Administrator** | ✓ Via the admin listing only | ✗ | ✗ | ✓ | ✗ | ✗ |

**Owner and admin are identical on this table.** Every match operation requires
`admin` or above, and the cumulative ranking means the owner satisfies it. There
is no match capability the owner has and an admin does not — a deliberate
split: the owner's exclusive powers are all about the *community* (settings,
roles, ownership, deletion), never about a fixture.

### 11.2 Read

**Membership of the match's community grants sight of the match**, and nothing
else does. A non-member sees nothing — not the fixture, not its time, not that
it exists.

**This is stricter than `communities` and matches `community_members`.** A
community's *existence* is public to signed-in users (`DD-13`, the one approved
broad-read exception); its roster and its fixtures are not. Discovery tells you
a community exists; it does not tell you when they play.

### 11.3 Create

**Owner and admin of the target community**, and the creator must stamp
themselves as `created_by` (`MT-C4`).

**Creation is a direct insert, not an operation** — and this is the asymmetry
§17.3 examines: the create path is validated by constraints alone, while the
edit path passes eight guards.

### 11.4 Update

**Owner and admin, through the edit operation only.**

The operation enforces, in order: authorization; not completed; not locked; a
valid title; a valid time range; `starting_players` within range; and that the
new capacity still fits everyone registered. It then rebalances the roster,
recomputes the status and notifies every registered player.

**A direct row update must not be possible.** §17.2 is the finding, and the
recommendation there is to withdraw the update rule entirely rather than
narrow it to columns — because **no legitimate writer needs it**.

### 11.5 Delete

**Owner and admin** of the community, and **System Administrator** through the
administrative path. Time-independent (`DD-07`), ordered, and reversing
(§6.4).

**Note who is absent: the creator, as such.** Before `0008`, deletion was the
creator's privilege. `PD-07` moved it to the community role, so an admin may
delete a match they did not create and a player may not delete one they did.

### 11.6 Record result, generate teams

Both require **`admin` or above in the match's community**, resolved through
the match's `community_id`.

Both are named here because the brief asks, and both belong to *other* tables:
recording a result writes the result tables, and generating teams writes the
lineup table. **What this table contributes to each is its `community_id` for
the authorization check and its row for the lock** (§5.4). Neither writes a
column of `matches` — in particular, **neither sets a "result recorded" or
"teams generated" flag, because none exists** (`MT-C15`, §4.1).

---

## 12. Audit

| Column | Required? | State | Reasoning |
|---|---|---|---|
| `created_at` | **Required** | Present | When the fixture was announced — not its ordering, which is `start_at`. It is the answer when a player says they never saw the match |
| `updated_at` | **Required** | Present | Several writers, two of them triggers. Trigger-maintained |
| `created_by` | **Required, and present** | Present | §12.1 |
| `updated_by` | **Excluded** | Absent | §12.2 |

### 12.1 `created_by` — required, and the reasoning differs from every other table

Refused on `users` (it would equal the primary key), not required on
`community_members` (joining is self-service). **Here it is genuinely
informative and always has been:** a match is created by one of several people
entitled to create one, and which of them did it is not derivable from anything
else.

It is also the one audit column in the schema with a **history of being
misread**. Until `0008` it was authorization; `PD-07` and `PD-16` moved that to
the community role and left the column as attribution. Its specification
therefore carries a warning rather than only a justification (§7.2, column 3).

### 12.2 `updated_by` — excluded, per `UP-4`

A mutable column recording only the most recent write is erased by the next
one. An admin moves the kick-off time; another admin later fixes a typo in the
description; the first change's author is gone. **An audit that a later
legitimate write erases is not an audit.**

The events here that could warrant an actor — moving a match, resizing it,
deleting it — are discrete and consequential, which is the shape an append-only
record fits (`RR-5`). **Two of them already have one:** every registered player
receives a notification when a match is edited or deleted, and those
notifications survive the match (`DD-08`). That is not a full audit, but it
means the change is not silent.

If match-change history is ever required, it is an append-only table and
`matches` does not change. `MT-D3`.

---

## 13. Dependencies

### 13.1 Tables the Match depends on

| Table | Nature | Ownership responsibility |
|---|---|---|
| `communities` | Identifying parent, cascading | **Owns the match's scope, its authorization and its lifetime.** The match holds the reference; the community takes no responsibility for any individual fixture |
| `users` | Attribution, no cascade | **Owns the person.** Takes no responsibility for the match, and the absence of a cascade is what makes that separation safe (§6.1) |
| `community_members` | **Not a foreign key — an authorization dependency** | Every create, update, delete, result and lineup operation resolves through `has_community_role`, which reads that table. A defect there is a defect in who may manage every match |
| `app_settings` | **Not a foreign key — a derivation dependency** | Supplies the global reserve allowance the capacity trigger reads (`DD-06`). The match stores the *result* of that derivation, freezing the depth it was created under |

### 13.2 Tables depending on the Match

Referenced **only as dependents**, per the scope.

| Table | Ownership responsibility |
|---|---|
| `match_registrations` | The match owns their existence, their lifetime and the capacity rules that decide their status |
| `match_team_assignments` | The match owns existence and lifetime; the lineup's *content* is the organiser's and the engine's |
| `match_results` | The match owns existence and lifetime. At most one per match |
| `match_goals` | Reached through the result, not the match directly |
| `rating_history` | The match owns the entries' lifetime — deleting it reverses and then removes them |
| `notifications` | **The match owns none of it.** The reference is released rather than destroyed (`DD-08`), because a notice about a deleted match must outlive it |

### 13.3 What the Match does not own

- **The people.** Registrations and lineups name users; the match owns neither.
- **The community's statistics.** Deleting a match *moves* Level 1 figures by
  reversing what it caused, and will do the same for Level 2 — but a statistics
  record belongs to *(player, community)* and outlives every individual match.
- **Authorization.** It is *scoped* by it and stores none (§3).

---

## 14. Future Compatibility

### 14.1 BTGE — built, no change required

The engine's generation set is **the match's confirmed registrations**; its
contextual input is **the match date**, used to compute each player's age as of
the match; its auxiliary data is the lineup table. It reads `start_at` and
nothing else from this row.

**Two rules keep this true:**

- **No engine output is stored here.** Not the balance score, not the quality
  metrics, not whether generation has run. The lineup table holds *the lineup
  that actually played*, including any manual change (`KB-017`), and this table
  holds no flag about it (§4.1).
- **`starting_players` remains the only capacity input.** The engine derives
  team sizes from the players actually available; it does not need a second
  column here.

### 14.2 Results — built, no change required

A result references the match. **No result state is mirrored onto this row** —
no `has_result`, no `score`, no `mvp`. Recording a result does not update
`matches` at all; deleting a match reverses the result's effects through a
trigger (§6.4).

The one asymmetry worth restating from the results phase: **the database imposes
no rule that a match must have finished before a result is recorded.** The
interface hides the entry point until the match is completed, and the database
does not refuse it — a deliberate split, because the approved validation rules
did not list it and making it a refusal would have been taking a Product
Decision in the wrong layer.

### 14.3 Community Statistics — Level 2, not built, no change required

A Level 2 record is keyed by `(player, community_id, period_type, period_key)`,
and **the match supplies the period**: `A3` places a match in a period by *when
it was played* — its `start_at` — evaluated in the reference time zone
`Asia/Muscat` (`A1`).

**Three consequences:**

1. **`start_at` becomes the period-bucketing input.** It already exists, is
   already NOT NULL, and is already `timestamptz` — which is what makes zone
   conversion correct. Nothing changes.
2. **No period column belongs on this table.** A match does not have a period;
   a *statistics record* has one, derived from the match's start. Storing a
   bucket here would freeze it against a time-zone constant `A1` warns must
   never change once figures exist.
3. **`MT-X2` already serves it.** Bucketing selects a community's matches within
   a window — exactly `(community_id, start_at)`.

### 14.4 Community Rating — not built, no change required

A rating moves as a consequence of a recorded result, and is keyed by
*(player, community)*. The match contributes the community and the occasion.
**No rating, of either level, is ever stored on this table.**

### 14.5 Leaderboards — not built, no change required, no index

Boards are computed over Level 2 records for one community, filtered by period
and eligibility. **This table is not read by a board at all** — it is upstream
of the records the board reads. It appears only when a board wants to name the
match behind a figure, which is a primary-key lookup.

### 14.6 The general rule

> **A new column on `matches` must be a property of the fixture itself, must
> not be derivable from its children, must not be a measure, and must name the
> consumer that reads it.** A count, a score, a flag about whether something
> beneath the match has happened, or anything per-player belongs elsewhere.

---

## 15. Validation

**Contradictions are named, not resolved silently.**

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | `Docs/01-PRD.md` | **No contradiction** | *Create matches* and *match registration with a reserve list and automatic promotion* are served. The role matrix places *create, edit and delete matches; manage a roster* with admin **and** owner and not with players — exactly §11.1 |
| 2 | `Docs/06-ERD.md` | **No contradiction** | §2's *"a match belongs to a community, never to its creator"* is `MT-C2` and §7.2 column 3. §4's warning that `created_by` is audit-only is restated as a warning. §6's capacity, status and title rules all hold |
| 3 | **Database Principles** | **No artifact in the repository** | Sixth phase in which this is recorded. Validated against `07-Database-Design.md` §Standards — which this table satisfies in full, including both audit columns — plus `SUPABASE_OPERATIONAL_GUIDELINES.md` §2 and §4 and `ARCHITECTURE_DECISIONS_V1.md`. **If a Database Principles document exists outside the repository, this specification has not been checked against it** |
| 4 | **Data Domains** | **No artifact in the repository** | Same. §3 states the nested-aggregate position from first principles |
| 5 | `Profiles_Table_Specification.md` v2.0 | **No contradiction** | `created_by` → `users(id)` with no cascade is that document's "Group C" pattern, and it names this column explicitly as one of the two that block a raw account deletion |
| 6 | `Communities_Table_Specification.md` v1.0 | **No contradiction** | Its §6.2 lists `matches` as one of the community's two direct children with `CASCADE`; its §5.2 operation 7 places match management with the community role. **`MT-R1` is the same defect class as its `CM-R2`**, and §17.2 explains why the fix here is simpler |
| 7 | `Community_Members_Table_Specification.md` v1.0 | **One consequence surfaced, not a contradiction** | Its §15.2 lists `matches` as depending on it for authorization. **Surfaced:** that document's `CMB-R1` — a self-departure that leaves registrations behind — manifests *here* as a confirmed seat held by a non-member, counted against this table's `max_registration`. The defect is that table's; the visible symptom is this one's capacity |
| 8 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction** | `A3`'s period rule uses `start_at`; `A1`'s zone constant is applied at read time, not stored (§14.3). `SL-2`'s isolation is expressed by `community_id`, reached through this table |
| 9 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction** | `RR-4`/`RR-5`'s reversal on delete is §6.4. `RR-7`'s recorded asymmetry — the database does not require a match to have finished before a result is recorded — is restated in §14.2 rather than silently inherited |
| 10 | `Docs/10-Design-Decisions.md` | **No contradiction** | `DD-03` (three states), `DD-04` (derived lock), `DD-05` (lazy completion, no scheduler), `DD-06` (derived capacity), `DD-07` (time-independent deletion), `DD-08` (notifications survive), `DD-12` (title required), `PD-06`, `PD-07`, `PD-16` all hold and are cited |
| 11 | `Docs/07-Database-Design.md` | **No contradiction** | Its capacity, status, title and `OP-2` statements match. Its index inventory lists both `matches(community_id, start_at)` and `matches(status)`; §10.2 records that the second has no driving query |
| 12 | `engineering/BTGE_Engineering_Specification.md` | **No contradiction** | §4.2's contextual input is the match date, which is `start_at` (§14.1). `OP-2`'s minimum is `MT-C9` |
| 13 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **One checklist item not met** | §15.1 |

### 15.1 The checklist item this table does not meet

`SUPABASE_OPERATIONAL_GUIDELINES.md` §4 requires that **enforcement be dual** —
a write path exposed as an RPC carries the check inside the function *and* an
RLS policy on the table, because RLS alone is bypassed by `SECURITY DEFINER`
and an RPC guard alone does not cover direct reads.

**On this table the two halves have drifted apart rather than reinforcing each
other.** The edit operation carries seven guards beyond authorization —
completion, lock, title, time range, size, capacity-versus-registered — and the
row-level update rule carries **only** the authorization check. The two are not
a belt and braces; they are two different rules, and the weaker one is
independently usable.

**Not resolved silently.** Recorded as `MT-R1`, analysed in §17.2, listed in
§19 and §20 item 1.

---

## 16. Engineering Rationale

### 16.1 The match is the lock, and therefore the root

Aggregate boundaries are usually argued from modelling. Here there is direct
physical evidence: every operation that writes anything in the domain takes an
exclusive lock on the match row before it does anything else, and the codebase
says so at the point it does it. Registration, withdrawal, removal, editing,
deletion, rebalancing and membership purge all obey it. **The boundary is not a
diagram; it is a lock order**, and §5.4 states it as a rule for whoever adds the
next operation.

### 16.2 Three states, because the other five are free

`DD-03` removed `draft`, `cancelled` and `postponed` — each was a feature
nobody asked for, deletion by another name, or an edit. What remains is three
values, and even those are derived: two from a count, one from the clock.
Deriving lock and completion (`DD-04`, `DD-05`) means the product needs no
scheduler, which is why it still has none.

### 16.3 Capacity is one organiser input and one global constant

The organiser chooses how many play; the reserve depth is decided once for the
application (`DD-06`). This removes a decision from every match creation and
guarantees that no organiser accidentally creates a match with no reserve. The
derived value is *stored* rather than computed on read because it is consulted
inside a lock on the hottest path in the product — and storing it freezes the
depth a match was created under, so changing the global setting cannot re-size
matches people have already joined.

### 16.4 The row holds no summary of its children

No registration count, no "teams generated", no "result recorded", no score.
Every one would be a second answer to a question a child table already answers
— the argument `RR-6` used to keep the rating out of `player_statistics`,
applied downward. `status` is the single exception, and §4.2 is honest about
what that costs: a cache with no freshness guarantee, which every consumer must
know not to trust.

### 16.5 Deletion reverses rather than refuses

`DD-07` keeps deletion time-independent, and the results phase made that safe by
reversing a deleted match's effects rather than refusing to delete a match that
has any. The alternative — a guard once results exist, which migration `0006`
anticipated — would have left organisers unable to remove a mistaken match.

---

## 17. Engineering Review

The brief asks for duplicated responsibilities, ownership violations, lifecycle
inconsistencies and unnecessary complexity. **Four findings, one of them
serious.**

### 17.1 Duplicated responsibility — `status` duplicates two derivable facts

`status` restates a count from `match_registrations` and a comparison against
the clock. It is a **cache**, written lazily, with no freshness guarantee
(`DD-05`).

**Assessment: keep it, and the duplication is justified** — it is read inside a
lock on the registration path, and recomputing the count there would be worse.
**But the duplication has a cost the schema does not express**, which is
`MT-C13`: nothing stops a future consumer trusting the column. The mitigation is
documentation, not a schema change; the alternative — computing status on read —
would trade a stale value for a slower hot path, which is the wrong trade.

**No change recommended.**

### 17.2 Ownership violation — the update rule permits what no writer needs

**This is the serious finding.**

The row-level update rule authorises an admin to write **any column of any match
in their community**. It does not restrict columns, and there is no column
privilege on this table.

**What that permits, all of it bypassing the edit operation's seven guards:**

| Written directly | Consequence |
|---|---|
| `status` | Set a match to `completed` while it is still being played, or back to `open` after it ended — bypassing recomputation entirely |
| `max_registration` | **Breaks `DD-06` outright.** The capacity trigger recomputes it on insert and on updates that change `starting_players` — but **not** on an update touching only this column, so a supplied value persists |
| `community_id` | **Move a match to another community**, carrying its registrations, lineup, result, goals and rating history — corrupting both communities' Level 2 figures, which are scoped through this column |
| `created_by` | Rewrite the organiser attribution |
| `start_at` / `end_at` | Re-time a **locked or completed** match, bypassing `MATCH_LOCKED` and `MATCH_COMPLETED` |
| `starting_players` | Resize without the roster rebalance, leaving confirmed and reserve statuses stale and nobody notified; and bypass `MAX_BELOW_REGISTERED` |

**The finding is not that the rule is too broad. It is that the rule has no
consumer at all.**

- The application updates matches through the edit operation, never by direct
  write.
- Every internal writer — the edit operation, status recomputation, the roster
  rebalance, the capacity trigger — is `SECURITY DEFINER` and runs **past** row
  rules anyway.

**So the update rule is pure attack surface. Recommendation: withdraw it
entirely.**

**This is materially simpler than the equivalent finding on `communities`
(`CM-R2`)**, and the difference is worth stating: there, an owner genuinely
edits three settings by direct write, so the fix is column privileges. Here,
nothing legitimate writes this table directly, so the fix is removal. **Removing
a rule with no consumer costs nothing and closes six bypasses.**

### 17.3 Lifecycle inconsistency — creation and editing are validated differently

**Creating a match is a direct insert; editing one is an operation with eight
guards.** The asymmetry is real:

| Checked when editing | Checked when creating |
|---|---|
| Authorization | ✔ (the insert rule) |
| Title present and ≥ 2 characters | ✔ by constraint only |
| Time range valid | ✔ by constraint only |
| `starting_players` in range | ✔ by constraint only |
| Capacity fits those registered | n/a |
| Not locked, not completed | n/a |
| **`title` and `location` trimmed before storing** | **✘ — not trimmed** (`MT-C17`) |
| **empty `description` normalised to null** | **✘** (`MT-C18`) |

**Assessment: the asymmetry is mostly harmless and partly a defect.** The
constraint-only checks are adequate — a constraint is a stronger guarantee than
a guard, not a weaker one. The two genuine gaps are trimming and description
normalisation, both of which mean the *constraint validates a value the table
does not store*.

**Recommendation: close `MT-C17` and `MT-C18` on the create path.** Do **not**
convert creation into an RPC — the insert rule works, and the guards that
creation lacks are ones that only make sense for an existing match.

### 17.4 Unnecessary complexity — none found, and one thing that looks like it

**The capacity trigger looks like unnecessary complexity and is not.** A
`BEFORE INSERT OR UPDATE` trigger that conditionally recomputes one column is
more machinery than a generated column or a computed read. It exists because the
value must be *frozen* at the reserve depth in force when the match was created
(§16.3), which neither alternative achieves.

**Its condition, however, is where `MT-R2` lives:** recomputing only when
`starting_players` changes is correct for every path that goes through the edit
operation, and is exactly what makes the column directly writable otherwise.
**Closing `MT-R1` closes `MT-R2` as a side effect** — with no direct update
path, the trigger's condition can never be reached with a client-supplied value.

**No other complexity found.** Thirteen columns, two foreign keys, no nullable
column that carries meaning by being null, no state machine beyond three values,
and no operation that does two jobs.

### 17.5 Summary

| Finding | Verdict |
|---|---|
| Duplicated responsibility — `status` as a cache | **Justified.** No change |
| **Ownership violation — the update rule** | **Withdraw the rule.** §19 `MT-R1` |
| Lifecycle inconsistency — create vs edit validation | **Partly a defect.** Close trimming and null-normalisation |
| Unnecessary complexity | **None found** |

**No approved product behaviour is redesigned by any of the above.** `DD-03`
through `DD-08`, `PD-06`, `PD-07`, `PD-16` and `OP-2` are all confirmed
unchanged.

---

## 18. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `MT-R1` | **The update rule permits writing every column, bypassing every guard.** `status`, `max_registration`, `community_id`, `created_by`, times on a locked match, and resizing without a rebalance — all reachable by any community admin with the publishable key. **The rule has no legitimate consumer** | **High** | **Open**, §20 item 1. Recommendation: **withdraw the rule entirely** (§17.2) |
| `MT-R2` | **`max_registration` is directly writable**, because the capacity trigger recomputes it only when `starting_players` changes. A derived value under `DD-06` becomes a supplied one | High — but **a strict consequence of `MT-R1`** | **Open.** Closing `MT-R1` closes this |
| `MT-R3` | **A match can be moved between communities**, carrying its results, goals and rating history into another community's figures | High — same origin | **Open.** Closing `MT-R1` closes this |
| `MT-R4` | **`title` and `location` are not trimmed on creation**, so the table stores values the constraint validated in a different form | Low | **Open**, §20 item 2 |
| `MT-R5` | **`status` is routinely stale.** A match that ended is `open` until something touches it (`DD-05`) | Low, **and by design** | **Accepted.** Every current consumer derives; `MT-C13` states the rule for new ones |
| `MT-R6` | **A confirmed seat may be held by a non-member.** A person who leaves a community via the self-departure path keeps their registrations, which still count against this table's `max_registration` | Medium | **Not this table's defect** — it is `CMB-R1`. Recorded because the symptom is a match that cannot fill a place it appears to have |
| `MT-R7` | **Deleting a match rewrites Level 1 career figures** for every participant, by reversing the result it produced | Medium — correct, irreversible, surprising | **Accepted by design** (`RR-4`, `RR-5`). The alternative — counting results of matches that no longer exist — is worse |
| `MT-R8` | **Nothing prevents creating a match in the past**, which is immediately completed and can never be registered for | Low | **Accepted** (§9.3). A Product Decision, not a schema one, and the case is legitimate |
| `MT-R9` | **`completed` erases the fill state.** After completion nobody can tell whether the match had been full | Low | **Accepted.** No consumer asks. Recorded so a future report does not assume the answer is available |

---

## 19. Open Decisions

| ID | Question | Recommendation |
|---|---|---|
| `MT-D1` | **Withdraw the update rule entirely, or narrow it to columns?** | **Withdraw entirely.** No legitimate writer uses it: the application edits through the operation, and every internal writer runs past row rules anyway. Narrowing would keep a path nothing needs. This is the one decision that closes three of the four High-severity risks |
| `MT-D2` | **Should creation become an operation, matching editing?** | **No.** The insert rule works, and the guards creation lacks are ones that only make sense for an existing match. Close the two genuine gaps (`MT-C17`, `MT-C18`) instead |
| `MT-D3` | **Is match-change history required** — who moved the kick-off, and when? | **Not for the MVP.** Every registered player is already notified of an edit, and those notices survive the match. If ever required it is an append-only table, **not** `updated_by` (§12.2, `UP-4`) |
| `MT-D4` | **Drop the unused `status` index?** | **Retain for now**, drop when the table is next touched. It is unused rather than duplicated, and this is not a high-write table (§10.2) |
| `MT-D5` | **Should a match be refused a start time in the past?** | **No, as specified.** It is a Product Decision, the case is legitimate, and `DD-07` already treats match time as independent of what may be done to a match |

---

## 20. Conformance — where the built schema differs from this specification

| # | Deviation | Required by | Severity | Notes for the implementing phase |
|---|---|---|---|---|
| 1 | **A direct update path exists that bypasses every guard** | `MT-C14`, `MT-C15`, `MT-C16`; §11.4 | **High** | Settle `MT-D1`. The recommendation is to withdraw the update rule; verify first that no client code and no non-`SECURITY DEFINER` path performs a direct update — the adapter uses the RPC, and every internal writer is `SECURITY DEFINER`. Assert the denial in the integration suite, as `SUPABASE_OPERATIONAL_GUIDELINES.md` §4 requires. **Closes `MT-R1`, `MT-R2` and `MT-R3` together** |
| 2 | **`title` and `location` are not trimmed on creation** | `MT-C17` | Low | Check existing rows for surrounding whitespace before enforcing. Same class as the Communities specification's `CM-C11`, and the two should be closed the same way |
| 3 | **An empty `description` may be stored on creation** | `MT-C18` | Low | The edit path already normalises; creation must match |
| 4 | **A comment in migration `0006` asks for a deletion guard once results exist** | — | **None — superseded** | Results landed in `0022` and answered the same concern by *reversal* rather than *refusal*; `DD-07` keeps deletion time-independent. **No action.** Recorded so the comment is not read as an open task |
| 5 | **The `status` index has no driving query** | `MT-X3` | Low | `MT-D4`. Drop when the table is next touched |

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched.

---

## 21. Engineering Approval

**Status: Engineering Approved — conditional.**

This document is complete and is the authoritative engineering specification for
`public.matches`. It is **conditional** because one High-severity defect (§20
item 1) exists between it and the schema as built. **Approving this document
approves the design, not the current state of the table.**

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5` | ✓ |
| Purpose, business owner, domain ownership | ✓ |
| **Complete lifecycle** — all eight conceptual stages mapped to three stored states and five derived ones; valid and invalid transitions | ✓ §4 |
| **Aggregate Root** — why, every operation that must originate here, six invariants, and the lock discipline | ✓ §5, 12 operations |
| **Business responsibilities** — owned and not owned | ✓ §5, §13.3 |
| Relationships: incoming, outgoing, ownership, deletion behaviour, lifecycle ownership | ✓ §6 |
| Every column — name, purpose, type, nullability, default, editability, justification | ✓ 13 of 13 |
| Every business constraint with its reason: organizer, community ownership, capacity, reserve, scheduled time, completion, deletion | ✓ 18 |
| Keys: primary, candidate, **alternate (none, with reasons)**, foreign | ✓ §8 |
| Index strategy: every index justified by a named query; the unused one identified | ✓ §10 |
| Access control: owner, admin, member, non-member, System Administrator × read/create/update/delete/record result/generate teams | ✓ §11 |
| Audit: all four columns ruled on | ✓ §12 |
| Dependencies both directions, with ownership responsibilities | ✓ §13 |
| Future compatibility: BTGE, results, community statistics, community rating, leaderboards | ✓ §14, five of five |
| Validation; contradictions named, not resolved | ✓ 13 sources, **1 checklist failure + 1 consequence surfaced** |
| **Engineering review** — duplicated responsibilities, ownership violations, lifecycle inconsistencies, unnecessary complexity | ✓ §17, four findings |
| No SQL, no migration, no implementation, no other table designed | ✓ |

### What must happen before the table is implementation-conformant

1. **Settle `MT-D1` and close §20 item 1.** The only High, and it closes three
   risks at once.
2. Close §20 items 2 and 3 — trimming and null-normalisation on creation.
3. `MT-D4`, then §20 item 5.

### Validation caveat, stated rather than glossed

The brief names *Database Principles* and *Data Domains* as validation sources.
**Neither exists as a document in this repository** — the sixth phase in which
this has been recorded. Validation used the principles in
`07-Database-Design.md`, `SUPABASE_OPERATIONAL_GUIDELINES.md` and
`ARCHITECTURE_DECISIONS_V1.md`. **This table satisfies the `07-Database-Design.md`
Standards in full** — the first in this phase to do so. If those two documents
exist outside the repository, this specification has not been checked against
them.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Communities_Table_Specification.md` | **Parent authority.** This table is one of the community's two direct children; `MT-R1` is the same defect class as its `CM-R2`, with a simpler fix |
| `engineering/Community_Members_Table_Specification.md` | Supplies every authorization answer for this table. Its `CMB-R1` surfaces here as `MT-R6` |
| `engineering/Profiles_Table_Specification.md` | `created_by` follows its "Group C" attribution pattern; `UP-4` is applied in §12.2 |
| `Docs/01-PRD.md` | The role matrix placing match management with owner and admin |
| `Docs/06-ERD.md` | §2 (a match belongs to a community), §4 (`created_by` is not authorization), §6 (capacity, status, title) |
| `Docs/07-Database-Design.md` | The schema as built; **Standards satisfied in full**; the index inventory listing the unused status index |
| `Docs/10-Design-Decisions.md` | `DD-03` … `DD-08`, `DD-12`, `PD-06`, `PD-07`, `PD-16` |
| `engineering/Results_Rating_Engineering_Decisions.md` | `RR-4`, `RR-5` (deletion reverses), `RR-7` (the recorded asymmetry restated in §14.2) |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | `A1`, `A3` — `start_at` is the period-bucketing input |
| `engineering/BTGE_Engineering_Specification.md` | §4.2 (match date as contextual input), `OP-2` (the minimum match size) |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §4 — **the dual-enforcement item this table does not meet** (§15.1) |
