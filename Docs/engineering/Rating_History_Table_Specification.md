# Global Rating History (`rating_history`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One Medium contradiction with `SL-2` §6; see §17.1 and §20 |
| Role | **Engineering Authority** for the physical table `public.rating_history` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Statistics |
| Scope | **`public.rating_history` only.** The Community Rating, Community Rating History and leaderboards appear **only as sibling or future entities** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-02 |

> **This document is the authoritative specification for the physical table
> `public.rating_history`.** Where an implementation and this document disagree,
> **the implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation**, and it designs no
> Community Rating, no Community Rating History and no leaderboards.
>
> **It includes a dedicated review of the audit architecture** (§4), covering
> immutability, the reversal model, historical integrity, administrative
> adjustments, the correction workflow, ordering, precision, and the
> relationships with all three rating concepts.
>
> **Sibling authorities.** The twelve table specifications, the BTGE database
> contract and the three engineering authorities, listed in *Related
> documents*.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Global Rating History** — entity `E6` in the conceptual model |
| **Physical table** | **`rating_history`** |

**The name understates its scope in one direction and overstates it in
another**, and both matter enough to state at the top:

- **It is the audit of the *Global* Rating only.** The Community Rating (`E8`)
  will have its own history (`E9`), a separate entity that this table neither
  contains nor anticipates (§4.10).
- **It is not a history of ratings in general.** It records *changes*, each with
  the value before and after — so it is a ledger, not a series of snapshots.

**One row is one rating change to one player, caused by one match.**

---

## 1. Purpose

### 1.1 Business purpose

A Rating History entry records that **one player's Global Rating moved by a
stated amount, from a stated value to a stated value, for a stated reason, in a
stated match**.

It exists for one reason above all others, and the reason is arithmetic rather
than archival:

> **A correction must reverse by the delta that was *applied*, and only this
> table knows what that was.**

The engine's constants are `+0.10` for a win, `−0.10` for a loss, `+0.05` per
goal and `+0.20` for the MVP. **The applied delta equals the constant except at
the ends of the `0.00 … 10.00` range**, where clamping truncates it — a player
at `10.00` who wins gains nothing. Reversing by the constant would hand back a
tenth they never received, and every subsequent correction would compound the
error.

**So the audit is not a record kept for posterity. It is a working part of the
correction path**, and `RR-5`'s three enforcement layers exist because a
corrupted audit means a rating that can never be made right again.

**Its second purpose is a product one:** the Player Profile displays rating
history, newest first (`SL-2` §6).

### 1.2 Business owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That an entry exists** | **The system** | The rating path, inside the recording operation |
| Every column | **The system, exclusively** | The same, once, at insert |
| **Nothing, ever after** | — | **No column is writable after insert, by anyone** (§4.1) |

**There is no human owner of any value in this table**, and — uniquely in this
schema — **no human owner of a row's continued existence either**. An entry
appears as a consequence and disappears only when its match or its player does.

### 1.3 Domain ownership

**Domain: Statistics. Position: the audit of Level 1, sitting beside the rating
it describes.**

| Property | Value |
|---|---|
| Aggregate | **None.** Not in the Match aggregate; not in the Community aggregate |
| Describes | `users.overall_rating` — the Global Rating |
| Depends on | `users`, `matches`, and **itself** |
| Depended on by | **Nothing** — but the correction path cannot work without it |
| Community-scoped | **No.** A career audit spans every community |
| Contains authorization | **No** |

**It is the only self-referencing table in the schema** (`reverses_id`), and
that is what lets a reversal be recorded without touching what it reverses
(§4.2).

### 1.4 Lifecycle ownership

| Bounded by | Consequence |
|---|---|
| **The match** | Cascades with it. *"A deleted match takes its own audit with it, the way every other row under a match does"* |
| **The player's account** | Cascades with it |
| **A reversed entry** | A reversal cascades with the entry it reverses — necessarily, since both share a match |
| **Not the clock** | Never archived, never rolled over, never pruned |
| **Not its own** | **An entry has no lifecycle. It is written once and never changes** (§4.1) |

---

## 2. Lifecycle

### 2.1 The shape

```
  NO ENTRY
      │
      │  a result is recorded  ── one entry per rating movement
      ▼
  WRITTEN ─────────────────────── and never modified again
      │
      │  the result is corrected
      ▼
  REVERSED ── NOT by editing this entry. A NEW entry is written,
      │        carrying the opposite delta and naming this one
      │        via reverses_id. Both rows now exist, forever.
      │
      ▼
  GONE ── only when the match is deleted, or the player's account is
```

### 2.2 Every valid transition

| # | From | To | Trigger | Notes |
|---|---|---|---|---|
| 1 | None | Written | A result is recorded | One entry per movement: outcome, goals, MVP (§2.4) |
| 2 | Written | **Still written, and reversed** | A result is corrected, or its match is deleted | **A second row appears.** The first is untouched — §4.2 |
| 3 | Written | Gone | The match is deleted | Cascade, **after** the reversal has run |
| 4 | Written | Gone | The player's account is deleted | Cascade |
| 5 | Written | Gone | The entry it reverses is deleted | Cascade through `reverses_id` |

**There is no transition that modifies a row.** Transition 2 is the only
"change", and it is an insertion.

### 2.3 Invalid transitions, and what refuses each

| Invalid | Why | Refused by |
|---|---|---|
| **Editing any column** | An audit that changes when the facts change can answer neither *what happened* nor *what is true now* | **Three layers** — §4.1 |
| **Reversing an entry twice** | Would subtract a change that was only ever applied once | The uniqueness of `reverses_id` where present (`RH-C7`) |
| **Reversing a reversal** | A correction reverses originals and applies new ones; un-reversing is not an operation | The reversal query selects only entries with `reverses_id is null` |
| **An entry with no match** | Every movement is caused by a match | `match_id` is NOT NULL — **and this constrains an open decision** (§4.4) |
| **An entry with no before or after** | The pair is what makes the delta verifiable | Both NOT NULL |
| **A reason outside the five** | Each names a rule in the engine; a sixth names none | `RH-C5` |
| **A client writing anything** | | **No write policy of any kind** (§10.3) |
| **Deleting one entry** | | No operation deletes one; only the two cascades |

### 2.4 What one match produces

**A fixed, deterministic sequence** — *"any order reaches the same rating; a
fixed one makes the audit read the same way every time."*

| Order | Reason | Who | Delta |
|---|---|---|---|
| 1 | `WIN` / `LOSS` | Every participant — **only if the match was not drawn** | `+0.10` / `−0.10` |
| 2 | `GOAL` | Each scorer, **one entry per scorer** | `0.05 × goals` |
| 3 | `MVP` | Exactly one participant | `+0.20` |

**Three consequences worth stating:**

- **A drawn match produces no outcome entry at all.** The counters record a
  draw; the rating does not move for it. So a player's `draws` can be non-zero
  with no corresponding audit entry — correct, and easily misread.
- **A hat-trick is one entry of `0.15`, not three of `0.05`** — matching the
  tally model of the evidence (`match_goals`).
- **The MVP entry is always written**, so every recorded result produces at
  least one entry.

---

## 3. Responsibilities

### 3.1 What this table owns

| # | Responsibility | Column |
|---|---|---|
| 1 | **Every Global Rating change ever applied** | The row's existence |
| 2 | **The applied delta** — what actually moved, not what was nominally due | `delta` |
| 3 | **The value before and after** | `rating_before`, `rating_after` |
| 4 | **Why it moved** | `change_reason` |
| 5 | **Which match caused it** | `match_id` |
| 6 | **Which change a reversal undoes** | `reverses_id` |
| 7 | **The order in which changes were applied** | `entry_no` — §4.6 |
| 8 | **Whether an entry is still in effect** | **As a query, never a flag** — §4.2 |

### 3.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **The current Global Rating** | `users.overall_rating` | A running value; this is its ledger. A copy here would be a second answer |
| 2 | **Any counter** | `player_statistics` | Counters and ratings are different kinds of number (`SL-5`) |
| 3 | **The Community Rating** | A separate entity (`E8`) | §4.9 |
| 4 | **The Community Rating History** | A separate entity (`E9`), required and unbuilt | §4.10 |
| 5 | **Who caused the change** | **Nowhere** | §4.4 — and this is the gap that constrains administrative adjustment |
| 6 | **Any statistic derived from ratings** | Nowhere; none exists | No board reads this table |
| 7 | **A permanent, indestructible record** | — | §4.3 — it is immutable, not immortal |

---

## 4. Audit Architecture Review

**The dedicated review requested.** Ten checks, each with a verdict.

### 4.1 Immutability — **sound, three layers, one honest qualification**

| Layer | Covers |
|---|---|
| **No update or delete policy** | Every client, for both operations |
| **A `BEFORE UPDATE` trigger raising `RATING_HISTORY_IMMUTABLE`** | The `SECURITY DEFINER` functions, which run past RLS |
| **`reverses_id` unique where present** | Logical immutability — one entry cannot be reversed twice |

**Each layer covers a path the others do not**, which is why three exist rather
than one.

**The qualification: immutability is against *modification*, not against
*deletion*.** The migration's own header says *"every rating change, immutable,
forever"*, and then, twenty lines later, *"deletion is deliberately not
blocked."* Both are true and the first overstates. **§4.3 states the accurate
position.**

**Verdict: sound.** No weakness found in the modification guarantee.

### 4.2 Reversal model — **sound, and the strongest design decision in the schema**

**A reversal is a new row that names what it undoes.** No historical row is
ever written twice.

| Property | How |
|---|---|
| The reversal carries the **opposite of the applied delta** | `−r.delta`, read from the entry itself |
| It names its target | `reverses_id` |
| Its reason is `REVERSAL` | So the audit reads as a narrative |
| It has its own before and after | So the reversal is itself auditable |
| **"Still in effect" is a query** | `reverses_id is null` **and** nothing reverses it |

**Why "still in effect" is not a flag.** A `reversed_at` column would be simpler
to read and would require **writing to a historical row** — the exact thing the
model forbids. Deriving it costs one `NOT EXISTS`, served by the unique index,
and keeps the table honest.

**Why the reversal walks newest-first.** Stepping back through states the player
genuinely occupied means every intermediate value is one the range already
accepted, **so no clamp can fire on the way out**. Reversing oldest-first could
push an intermediate value outside `0.00 … 10.00` and clamp it — losing exactly
the precision the audit exists to preserve.

**Verdict: sound.** This is the mechanism that made `RR-4`'s recovery exact
across a hundred results, including two accounts clamped at the ceiling.

### 4.3 Historical integrity — **sound within its bounds, and the bounds must be stated**

> **The audit is immutable, and it is not immortal.**

| Event | Effect on the audit |
|---|---|
| A result is corrected | **Nothing is lost.** Reversals are appended |
| A match is deleted | **The whole audit for that match is destroyed** — after the reversal has run |
| A player's account is deleted | **Their entire rating history is destroyed** |
| An entry's target is deleted | Its reversal goes too |

**The match-deletion case is coherent**: the reversal runs first, so the rating
returns to where it would have been, and the audit of a match that no longer
exists is removed with it. Nothing is left inconsistent.

**The account-deletion case is coherent for the deleted player** and inherits
the known problem for everyone else: where the deleted account was a match's MVP
or a scorer, **the result itself cascades away without reversing** (`MRS-R1`,
`MG-R1`) — so other players keep ratings whose audit entries survive but whose
cause is gone.

**Verdict: sound, with an inherited exposure.** No weakness in this table's own
integrity; the exposure is `RH-R2` and belongs to the tables that own the
cascades.

### 4.4 Administrative adjustments — **not supported, and three columns block it**

`RR-2` settled that the rating engine is the sole author of a rating and
**deliberately left open** whether an administrator may adjust one by hand. The
Profiles specification then decided in advance *where* such an adjustment would
be recorded: **on this table, not as a mutable column on `users`.**

**This table cannot record one today.** Three obstacles, and none is a matter of
convention:

| # | Obstacle | Why it blocks |
|---|---|---|
| 1 | **`match_id` is NOT NULL** | An administrative adjustment has no match. There is no value to supply and nothing to invent |
| 2 | **`change_reason` has no manual value** | The vocabulary is `WIN`, `LOSS`, `GOAL`, `MVP`, `REVERSAL` — five engine reasons and nothing else |
| 3 | **There is no actor column** | *Who* adjusted is exactly the fact an administrative adjustment must record, and there is nowhere to put it |

**So the open `RR-2` question has a concrete cost**: approving administrative
adjustment requires three schema changes here — a nullable `match_id`, a new
reason value, and an actor column.

**Verdict: a designed-in gap, correctly designed.** The table refuses to
represent a thing the product has not approved, rather than leaving a nullable
column waiting. **Recorded as `RH-D1`**, with the shape of the change stated so
it is not rediscovered.

**One consequence must be flagged now**, because it affects a decision already
taken: making `match_id` nullable would weaken `RH-C2` for *every* entry, so the
change should be paired with a constraint requiring a match for every
engine-caused reason. Stated in §14.1.

### 4.5 Correction workflow — **sound, and the ordering within it is load-bearing**

A correction, in order:

| Step | |
|---|---|
| 1 | **Reverse** every in-effect entry for the match, newest-first, appending reversals |
| 2 | Reverse the counters — a separate statement over shared arithmetic (`RR-4`) |
| 3 | Replace the result and its goals |
| 4 | **Apply** the new rating entries |
| 5 | Apply the new counters |

**Every step is inside one transaction, under the match row lock.**

**Two properties this gives, both verified in production recovery:**

- **The rating returns to exactly where it was** before the first result, at
  every intermediate point.
- **The audit reads as a narrative**: what the first result awarded, that each
  award was taken back, and what the second awarded instead.

**Verdict: sound.** No weakness found.

### 4.6 Ordering guarantees — **sound, and `created_at` could not have done it**

`entry_no` is a database-generated identity column, and it exists because
**`created_at` cannot order entries within a transaction**: a whole recording
happens at one instant and every row shares it.

| Property | |
|---|---|
| Scope | **Global**, not per player |
| Used for | Walking a match's entries newest-first during reversal |
| Guarantee | **Monotonic per transaction**, which is all the reversal needs |

**A global sequence still orders each player's entries correctly**, because a
descending global order preserves descending order within any subset.

**One honest limitation:** identity columns may leave gaps after a rolled-back
transaction, so `entry_no` is an *ordering*, never a *count*. Nothing treats it
as one.

**Verdict: sound.**

### 4.7 Precision guarantees — **sound, and `RR-1` is why**

`delta`, `rating_before` and `rating_after` are all `numeric(4,2)`, matching
`users.overall_rating` exactly.

**Every approved delta is a multiple of `0.05`**, so two decimal places are
exactly sufficient and nothing wider was taken. One decimal place could not
represent a goal's `0.05` at all, and **rounding is not invertible** — which
would make reversal permanently inexact.

**Storing the *applied* delta rather than the nominal constant is what makes
clamping survivable**, and it is the single most important column decision in
this table (§6.2).

**Verdict: sound.** The precision of the three numeric columns must never
diverge from `users.overall_rating`; §7.1 states it as a constraint.

### 4.8 Relationship with the Global Rating — **this table is its ledger**

| | `users.overall_rating` | This table |
|---|---|---|
| What | The **current** value | Every **change** |
| Kind | A running value | A ledger |
| Written by | `apply_rating_delta` | The same function, in the same statement |
| Can one be derived from the other? | **Yes in principle** — the sum of in-effect deltas from `5.00` | **No** — the current value cannot reconstruct the history |

**They are written together, in one function, so a rating that changed without
an audit entry is not a state this schema can reach.** That coupling is the
strongest integrity property either has.

**Verdict: sound.** And it is why §4.4's administrative adjustment must route
through the same function rather than writing the column directly.

### 4.9 Relationship with the Community Rating — **none, and there must be none**

The Community Rating (`E8`) is **independent** (`SL-3`): *"Neither rating is
derived from the other, neither is a view of the other, and the two are expected
to differ."*

| | |
|---|---|
| Does this table record Community Rating changes? | **No, and it must not** |
| Could it, with a `community_id` column? | **No.** A career audit has no community dimension, and adding one would make Level 1 community-scoped — destroying `RR-6` |
| Do the two move together? | **Only in that one match moves both.** A match in community A moves the Global Rating and A's Community Rating, and neither is computed from the other |

**Verdict: correctly absent.**

### 4.10 Relationship with the Community Rating History — **a required sibling, unbuilt, and this table is its template**

`E9` is **required and has no MVP reader** — *"it is not optional."* It exists
for exactly the reason this table does: a corrected result must reverse by the
applied delta, and clamping makes that differ from the constant.

**The template it should follow**, stated so the future phase inherits rather
than rediscovers:

| Property | Inherit? |
|---|---|
| Append-only, with reversal as a new row naming its target | **Yes** |
| Store the **applied** delta, before and after | **Yes** — for the identical clamping reason |
| Three immutability layers | **Yes** |
| `entry_no` for within-transaction ordering | **Yes** |
| Reversal walks newest-first | **Yes** |
| Keyed by player and match | **No** — it must also carry `community_id` |
| Cascades from the match | **Partly** — it must also cascade from the community, and **never from the membership** (`A7`) |

**Verdict: correctly separate.** One table cannot serve both: this one has no
community dimension and must not acquire one (§4.9).

### 4.11 Summary of the review

| Check | Verdict |
|---|---|
| Immutability | **Sound** — three layers; "forever" overstates, §4.3 corrects |
| Reversal model | **Sound** — the strongest design decision in the schema |
| Historical integrity | **Sound within bounds**; one inherited exposure |
| Administrative adjustments | **Not supported**; three columns block it — `RH-D1` |
| Correction workflow | **Sound** |
| Ordering | **Sound** |
| Precision | **Sound** |
| Global Rating | **Sound** — written together, indivisibly |
| Community Rating | **Correctly absent** |
| Community Rating History | **Correctly separate**; template recorded |

**One architectural weakness found, and it is in the read model rather than the
audit model** — §17.1.

---

## 5. Relationships

### 5.1 Incoming

| Source | Column | On delete |
|---|---|---|
| **`rating_history` itself** | `reverses_id` | **`CASCADE`** |

**The only self-reference in the schema.** It is what allows a reversal to be
recorded without touching what it reverses.

**Nothing else references this table**, and nothing should: an entry is a fact
about a moment, and anything pointing at it would be asserting a dependency on
a moment.

### 5.2 Outgoing

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `users` | `user_id` | many : 1 | **`CASCADE`** | **Identifying.** Whose rating moved |
| `matches` | `match_id` | many : 1 | **`CASCADE`** | **Identifying.** What caused it |
| `rating_history` | `reverses_id` | many : 0..1 | **`CASCADE`** | **Self-reference.** What this undoes |

**No foreign key to `match_results`**, deliberately: the audit outlives a
correction that replaces the result row, and binding it to a row that is
upserted would tie a permanent record to a mutable one.

### 5.3 Ownership

| Question | Answer |
|---|---|
| **Who owns the meaning?** | The **player** — it is their rating that moved. The match is the cause, not the owner |
| **Can an entry be reparented?** | **No.** Nothing writes any column after insert |
| **Does `users` know it has history?** | **No flag.** The rating is current; the history is queried |
| **Does the match know?** | **No.** §14.2 of the Matches specification confirms no result state is mirrored onto a match |

### 5.4 Deletion behaviour

| Path | Effect | Assessment |
|---|---|---|
| **Match deleted** | The reversal runs first, then the audit cascades | **Correct** — the rating is restored before its record goes |
| **Account deleted** | That player's entire history cascades | **Correct for them**, exposed for others (§4.3) |
| **Reversed entry deleted** | Its reversal cascades too | **Correct** — both share a match and would go together anyway |
| **Directly** | **No path exists** | **Correct** |

### 5.5 Lifecycle

| Relationship | Whose lifetime bounds whose |
|---|---|
| `users` → entry | **Absolutely** |
| `matches` → entry | **Absolutely** |
| entry → its reversal | **Absolutely** |
| entry → `users.overall_rating` | **Neither.** The rating outlives every entry; the entries outlive nothing |

---

## 6. Columns

Ten columns.

### 6.1 Summary

| # | Name | Type | Nullable | Default | Editable |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `entry_no` | `bigint` | No | **identity** | **Never** |
| 3 | `user_id` | `uuid` | No | none | **Never** |
| 4 | `match_id` | `uuid` | No | none | **Never** |
| 5 | `change_reason` | `text` | No | none | **Never** |
| 6 | `delta` | `numeric(4,2)` | No | none | **Never** |
| 7 | `rating_before` | `numeric(4,2)` | No | none | **Never** |
| 8 | `rating_after` | `numeric(4,2)` | No | none | **Never** |
| 9 | `reverses_id` | `uuid` | **Yes** | `null` | **Never** |
| 10 | `created_at` | `timestamptz` | No | `now()` | **Never** |

**Every column is "Never".** This is the only table in the schema with no
writable column at all — not by a client, not by an administrator, not by the
system after insert. **That is what "append-only" means expressed as a column
table.**

### 6.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated**

*Purpose.* Row identity, **and the target of `reverses_id`**.

*Business justification.* **Unlike every other surrogate key in this schema,
this one has a real consumer**: a reversal names the entry it undoes by this
value, and the reversal function passes it directly. It is load-bearing, not
conventional.

---

**2. `entry_no` — `bigint`, NOT NULL, database-generated identity**

*Purpose.* **The order in which changes were applied.**

*Business justification.* §4.6. `created_at` cannot order entries written in one
transaction, and the reversal depends on walking newest-first so that no clamp
fires on the way out. **An ordering, never a count** — identity columns leave
gaps after a rollback.

*Not the primary key*, because `reverses_id` needs a stable opaque handle and
`id` already is one. Two identifiers, two jobs (§8.1).

---

**3. `user_id` — `uuid`, NOT NULL, no default**

*Purpose.* Whose Global Rating moved.

*Business justification.* It is the player's identity and the authentication
identity, so *"my rating history"* is a direct predicate. It also carries the
`ON DELETE CASCADE` that removes a departed account's audit with the rating it
describes.

---

**4. `match_id` — `uuid`, NOT NULL, no default**

*Purpose.* Which match caused the movement.

*Business justification.* It is how the reversal finds what to undo — the whole
correction path selects by it — and it is what makes the audit explicable: a
change with no cause could not be verified against anything.

***NOT NULL, and this is the constraint that blocks administrative
adjustment*** (§4.4). It is correct today: every approved cause of a rating
movement is a match. It becomes the obstacle the moment a cause that is not a
match is approved.

---

**5. `change_reason` — `text`, NOT NULL, five values**

*Purpose.* Which rule produced the movement.

| Value | Cause |
|---|---|
| `WIN` | The player's side won — `+0.10` |
| `LOSS` | The player's side lost — `−0.10` |
| `GOAL` | Goals credited — `0.05 × goals`, **one entry per scorer** |
| `MVP` | Named best player — `+0.20` |
| `REVERSAL` | This entry undoes another |

*Business justification.* It is what makes the audit readable as a narrative
rather than a list of numbers, and it is the only column that distinguishes an
original from a reversal without following `reverses_id`.

**A closed vocabulary with no manual value** — §4.4.

**One property worth naming:** a `REVERSAL` entry does not say *what kind* of
change it undoes. That is recoverable only by following `reverses_id`, which is
correct — the reason belongs to the original, and duplicating it would create
two places for one fact to drift.

---

**6. `delta` — `numeric(4,2)`, NOT NULL, no default**

*Purpose.* **How much the rating actually moved.**

*Business justification.* **The most important column in the table.** It is the
*applied* delta, not the nominal constant — they differ at the ends of the range
where clamping truncates the movement, and **reversing by the constant would
invent a rating the player never held**. Everything §4.2 guarantees rests on
this column holding what happened rather than what was due.

*Signed.* A loss and a reversal both carry negative values.

*`numeric(4,2)`* — §4.7.

---

**7–8. `rating_before`, `rating_after` — `numeric(4,2)`, NOT NULL**

*Purpose.* The value on each side of the movement.

*Business justification.* They make the entry **self-verifying**: `after − before`
must equal `delta`, so an entry can be checked without reference to any other
row. That is what allows a reconciliation to detect a corrupted audit at all
(§16.3).

**They also record the clamp.** Where a movement was truncated, `after − before`
is smaller than the constant — and the pair is the only place that fact is
visible.

*Both stored rather than one derived*, because deriving `before` from the
previous entry's `after` would require the previous entry to exist — which it
does not, for a player's first change — and would chain every value to every
earlier one.

---

**9. `reverses_id` — `uuid`, NULLABLE, default `null`**

*Purpose.* Which entry this one undoes.

*Business justification.* §4.2. It is how a reversal is recorded without
touching what it reverses, and it is what makes *"still in effect"* a query.

*Nullable, and null is meaningful*: an original entry has none. **This is the
column that distinguishes the two kinds of row**, and `change_reason =
'REVERSAL'` is its redundant companion — the two must always agree (`RH-C8`).

*Unique where present* (`RH-C7`) — one entry may be reversed once.

*Self-referencing with cascade* — §5.2.

---

**10. `created_at` — `timestamptz`, NOT NULL, default `now()`**

*Purpose.* When the change was applied.

*Business justification.* It is the timestamp the Player Profile displays, and
the only thing that dates a movement in human terms.

**It cannot order entries within a recording** — every row of one transaction
shares it, which is precisely why `entry_no` exists (§4.6). **Reading it as an
ordering is the single most likely misuse of this table**, and `RH-C9` states
the rule.

### 6.3 No `updated_at`, and no actor column

**No `updated_at`**, and correctly: nothing updates a row, so it could never
differ from `created_at`. This is the cleanest instance of the pattern in the
schema — the table is append-only by design rather than by habit.

**No actor column** — §4.4, and §11.

---

## 7. Constraints

### 7.1 Enforced

| ID | Rule | Why it exists |
|---|---|---|
| `RH-C1` | **`user_id` references `users(id)`, cascading** | A rating change for nobody is not a fact. Cascading so a deleted account leaves no audit for a rating that no longer exists |
| `RH-C2` | **`match_id` references `matches(id)`, NOT NULL, cascading** | Every movement has a cause. The cascade is safe because the reversal runs first (§4.3) |
| `RH-C3` | **`reverses_id` references `rating_history(id)`, cascading** | A reversal cannot outlive what it reverses |
| `RH-C4` | **`delta`, `rating_before`, `rating_after` are `numeric(4,2)` and NOT NULL** | `RR-1`. The precision must match `users.overall_rating` exactly, or reversal stops being exact (§4.7) |
| `RH-C5` | **`change_reason` is one of the five** | Each names a rule; a sixth names none, and would be read as *not `REVERSAL`* by the reversal query — invisible where it matters most |
| `RH-C6` | **No column may be updated** | Enforced by a `BEFORE UPDATE` trigger **and** by the absence of an update policy. §4.1 |
| `RH-C7` | **`reverses_id` is unique where present** | One entry may be reversed once. Two reversals would subtract a change applied once |
| `RH-C8` | **No client may insert, update or delete** | There are **no write policies of any kind**. The audit is written by one function, in the same statement that moves the rating |

### 7.2 Specified here, not enforced

| ID | Rule | Why it exists | State |
|---|---|---|---|
| `RH-C9` | **`created_at` must never be used to order entries** | Every row of one recording shares it; `entry_no` is the ordering (§4.6) | **Convention.** Not expressible as a constraint |
| `RH-C10` | **`rating_after − rating_before` must equal `delta`** | It is what makes an entry self-verifying, and the only check that could detect a corrupted audit | **Expressible as a check and not present.** §16.3 |
| `RH-C11` | **`change_reason = 'REVERSAL'` if and only if `reverses_id` is present** | Two columns encode one fact; if they disagree, the reversal query and the narrative disagree | **Expressible as a check and not present** |
| `RH-C12` | **At most one in-effect entry per `(user_id, match_id, change_reason)`** | A double-apply would double a player's movement for one match. `RH-C7` prevents double-*reversal*; **nothing prevents double-*application*** | **Not enforced.** §16.2 |
| `RH-C13` | **Ratings must stay within `0.00 … 10.00`** | The approved `OP-1` scale | Enforced on `users.overall_rating`, not here. `rating_after` could record an out-of-range value if the clamp were ever bypassed |

### 7.3 Deliberately not constrained

| Not constrained | Why not |
|---|---|
| **A bound on `delta`** | The approved constants are `±0.10`, `0.05 × goals` and `+0.20`; `goals` is unbounded, so the delta is too |
| **That an entry's match involves the player** | True by construction — every entry is generated from the stored lineup — and checking it here would duplicate the lineup's own guarantee |
| **Deletion** | Deliberately permitted by cascade (§4.3) |
| **An entry per participant per match** | A drawn match produces no outcome entry (§2.4) |

---

## 8. Keys

### 8.1 Primary key

**`id`** — a generated `uuid`, and **the only surrogate key in this schema with
a genuine consumer**: `reverses_id` references it.

**Why not `entry_no`, which is also unique?** Two identifiers with two jobs:
`entry_no` is an *ordering* and may gap; `id` is an *opaque handle* and is what
a reference should point at. Making the ordering the primary key would tie every
reference to a sequence position.

### 8.2 Business key

**None — and this is correct.**

An entry is an *event*, and events have no natural key: the same player can
receive two `GOAL` entries for the same match if the result is corrected and
re-recorded (one original, one reversal, one new original). **Nothing about an
entry's content identifies it**, which is why the surrogate is load-bearing here
and decorative elsewhere.

### 8.3 Candidate keys

| Candidate | Unique? | Assessment |
|---|---|---|
| `id` | **Yes** — primary | Opaque, referenced |
| `entry_no` | **Yes** — identity | An ordering; see §8.1 |
| `reverses_id` | **Yes where present** | A partial key over reversals only |
| `(user_id, match_id, change_reason)` | **No** | Unique among *in-effect originals* only (`RH-C12`), not overall |

### 8.4 Alternate keys

**`entry_no`.** Unique, NOT NULL, database-generated — a genuine alternate key,
used for ordering rather than addressing.

**`reverses_id` is not a key**: it identifies a row only among reversals, and
half the table has none.

### 8.5 Foreign keys

**Outgoing — three**, two identifying and one self-referencing (§5.2).
**Incoming — one**, from itself.

---

## 9. Index Strategy

### 9.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `RH-X1` | **Primary key on `id`** | (a) the `reverses_id` foreign key check on every reversal; (b) the self-cascade |
| `RH-X2` | **`(match_id)`** | **The correction path.** Selecting a match's in-effect entries to reverse — the only high-frequency query against this table, and it runs inside the match lock |
| `RH-X3` | **`(user_id)`** | (a) the Player Profile's rating history; (b) the cascade from `users` |
| `RH-X4` | **Unique on `reverses_id`, where present** | (a) enforcement of `RH-C7`; (b) **the `NOT EXISTS` in the in-effect predicate**, which runs once per candidate entry during every correction |

**All four have a driving query.** `RH-X4` in particular is not merely a
uniqueness artefact — it is what makes *"still in effect"* cheap enough to be a
query rather than a flag.

### 9.2 Considered and deferred

| Candidate | Verdict |
|---|---|
| `(user_id, entry_no DESC)` | **Deferred.** The Player Profile reads one player's history newest-first; `RH-X3` locates the rows and a sort follows. At a few dozen entries per player that is free. **Revisit if a profile displays an unbounded history** — `OQ-5` leaves the depth open |
| `(match_id, entry_no DESC)` | **No.** `RH-X2` already narrows to one match's handful of rows |
| `(change_reason)` | **No.** Three of five values are common; nothing filters by reason alone |
| `(created_at)` | **No.** Nothing orders by it, and `RH-C9` forbids treating it as an ordering |

### 9.3 The rule for a future designer

> **This table is read by match during a correction, and by player for a
> profile.** An index serving anything else suggests a consumer is computing
> something from the audit that a statistics table should already hold.

---

## 10. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 10.1 The matrix

| Actor | Read | Insert | Update | Delete |
|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ |
| **The player, their own history** | ✓ **Should be unconditional** — §10.2 | ✗ | ✗ | ✗ |
| **Community Member** | ✓ Entries for matches in their communities | ✗ | ✗ | ✗ |
| **Community Admin / Owner** | ✓ Same — **role grants nothing here** | ✗ | ✗ | ✗ |
| **System Administrator** | ✗ No direct path | ✗ | ✗ | ✓ Transitively |
| **The system** | — | ✓ **Only actor** | ✗ **Nobody, ever** | ✓ Cascade only |

**Update has no actor at all** — not the system, not an administrator. That is
what distinguishes this table from every other in the schema.

### 10.2 Read — and the architectural weakness

**The rule as built:** an entry is readable by members of **the community of the
match that caused it**.

**That is reasonable for other people's entries and wrong for your own**, and it
produces a direct contradiction with `SL-2` §6 — §17.1.

**The rule this specification requires:**

> **A player may always read their own complete rating history, unconditionally
> — including entries from communities they have left.** Other people's entries
> remain scoped to shared community membership.

**Why the self tier must be unconditional.** The Player Profile displays rating
history as a **career** record, and `SL-2` §6 states that *"leaving a community
does not change this screen."* Under the rule as built it does: the entries
vanish from the player's own history the moment they leave.

### 10.3 Write

**There are no write policies of any kind**, and — beyond that — **no update
path exists for anyone**, because the trigger refuses even `SECURITY DEFINER`
callers.

**Insert has exactly one author**: `apply_rating_delta`, which writes the entry
**in the same statement flow that moves the rating**. A rating that changed
without an audit entry is not a state this schema can reach.

### 10.4 Delete

**No client path.** Only the three cascades (§5.4). **No administrative
deletion**, and none should be added: an audit an administrator can prune is not
an audit.

---

## 11. Audit model

**This table *is* the audit**, so the four columns are asked of it differently
from every other table.

| Column | Required? | Verdict |
|---|---|---|
| `created_at` | **Required** | Present. When the change was applied — **not an ordering** (`RH-C9`) |
| `updated_at` | **Must not exist** | Nothing updates a row. A column recording modification on an immutable table would be a contradiction in the schema |
| `created_by` | **Not required today; required if `RR-2` is approved** | §11.1 |
| `updated_by` | **Must not exist** | There is no update to attribute |

### 11.1 `created_by` — the one column this table will need

**Today it would carry no information.** Every entry is written by the rating
path as a consequence of a result, and *who recorded that result* is already
recorded on the result itself.

**If administrative adjustment is approved, it becomes required** — and this
table is where the Profiles specification already decided it belongs, precisely
because a mutable column on `users` would be erased by the next edit while an
append-only entry cannot be.

**So the column is absent, correctly, and its future is already decided.**
`RH-D1`.

### 11.2 What the audit does not cover

**It does not record what it did not cause.** A rating that was somehow changed
outside `apply_rating_delta` would leave no entry — and nothing would detect it,
because no reconciliation compares the current rating against the sum of
in-effect deltas.

**That check is available and cheap** (§16.3), and its absence is `RH-R3`.

---

## 12. Dependencies

### 12.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `users` | Identifying parent, cascading | Owns the person **and the rating this table audits** |
| `matches` | Identifying parent, cascading | Owns the cause, and supplies the row locked while entries are written |
| **Itself** | Self-reference | Owns the reversal relationship |
| `match_results`, `match_goals`, `match_team_assignments` | **Not referenced — the evidence behind the entries** | Determine who receives which entry and how much |

### 12.2 Tables depending on this table

**None by foreign key** (§5.1).

**By behaviour, one — and it is not a reader but a dependant:**

| Consumer | Dependency |
|---|---|
| **The correction path** | **Cannot reverse a rating without this table.** Not a read for display: the audit is a working part of the operation |
| The Player Profile | Displays it, newest first |

**And one explicit non-dependant:** `player_statistics` neither reads nor is
read by this table. Counters and ratings are computed from the same evidence
independently (DP-10).

---

## 13. Engineering Principles

Eleven principles have been named across this phase. **Nine have no textual
definition in this repository** — the thirteenth phase in which that has been
recorded. The reading applied is the one established in the previous
specifications; where a reading differs from the approved definition, this
section is the defect (`RH-D3`).

| Principle | Verdict |
|---|---|
| **DP-1 Match Aggregate Root** | **Conforms from outside.** Entries are caused by a match, take its id, and are written under its lock. This table reaches into no match |
| **DP-2 Match Row Lock** | **Conforms, inherited.** Every entry is written inside the recording operation's lock. Without it, two corrections could interleave reversals |
| **DP-3 Business Transition** | **Conforms absolutely.** One route, one function, no policy admitting another, and **no update route for anyone** |
| **DP-4 Historical Identity** | **Conforms, and this table defines the principle.** It states what happened, identified by the player and the match, and stores nothing about the process that produced it |
| **DP-5 Final Participation** | **Conforms.** Entries are generated from the stored lineup; a non-participant receives none |
| **DP-6 Single Business Path** | **Conforms.** `apply_rating_delta` is the sole author, and both the apply and reverse directions call it — the reversal simply passes a negated delta and a target |
| **DP-7 Producer / Commit Separation** | **Conforms by not applying.** Nothing here is a candidate a human may reject; an entry is entailed by the movement it records |
| **DP-8 Historical Record Protection** | **This table is the principle's subject.** §4.1–§4.3 are its full statement, including the honest bound: immutable, not immortal |
| **DP-10 Independent Derivation** | **Conforms.** The audit is not derived from the counters and the counters are not derived from it; both follow from the same evidence |
| **DP-11 Derived Data Reconciliation** | **Partially met — and this is a finding.** The audit is *reconcilable* (§16.3) but **no reconciliation exists**. `RH-R3` |
| **DP-12 Evidence Before Derivation** | **Conforms, with the inherited exposure.** An entry exists only while its match does — and the cases where a match's evidence is destroyed without reversal are `MRS-R1` and `MG-R1` |

---

## 14. Future Compatibility

### 14.1 Administrative rating adjustment — the change is known and specified

If `RR-2`'s open question is approved, this table changes in three ways
(§4.4), and they should be made together:

| # | Change | Note |
|---|---|---|
| 1 | `match_id` becomes **nullable** | **Pair it with a constraint requiring a match for every engine reason**, or `RH-C2` weakens for all entries |
| 2 | A new `change_reason` value — e.g. `ADJUSTMENT` | Additive to a closed vocabulary |
| 3 | An **actor column**, nullable, clearing on account deletion | §11.1, and the pattern `match_results.recorded_by` sets |

**Everything else holds unchanged**: immutability, the reversal model, the
precision, and the ordering. **An adjustment must route through
`apply_rating_delta`**, so that the rating and its audit stay indivisible
(§4.8).

### 14.2 The Community Rating History — a sibling, not an extension

§4.10. It is a **separate entity** that inherits this table's design and adds a
community dimension. **This table must not grow one.**

### 14.3 Displaying rating history — no change

`SL-2` §6 already places it on the Player Profile, newest first, with depth left
open (`OQ-5`). **Depth is a query parameter**, and §9.2 records the index to add
if an unbounded history is ever displayed.

### 14.4 A rating engine change — no change to this table

New constants, a new reason, or a different formula are all values and
vocabulary. **The one property that must never change is that `delta` records
what was applied**, because every guarantee in §4 rests on it.

### 14.5 What must never be added

| Never | Why |
|---|---|
| `community_id` | §4.9 — it would make Level 1 community-scoped |
| A `reversed_at` or `is_reversed` flag | §4.2 — it would require writing to a historical row |
| The current rating | §3.2 — a second answer to what `users.overall_rating` holds |
| An `updated_at` | §11 — a modification timestamp on an immutable table |
| Any counter | Counters are not ratings (`SL-5`) |

---

## 15. Engineering Rationale

### 15.1 The applied delta is the whole design

Store the constant and reversal becomes approximate at the ends of the range;
store what actually moved and it is exact everywhere. Every other property —
the append-only model, the before/after pair, the newest-first walk — follows
from taking that requirement seriously.

### 15.2 A reversal is a row, not an edit

`RR-5`. An audit that is edited when the facts change can answer neither *what
happened* nor *what is true now*. Appending costs one row and yields a narrative
that reads correctly however many times a result is corrected.

### 15.3 Two identifiers, two jobs

`id` is an opaque handle that a reference can point at; `entry_no` is an
ordering that may gap. Collapsing them would tie every reference to a sequence
position.

### 15.4 The rating and its audit are written together

One function, one flow. A rating that changed without an entry is unreachable —
which is a stronger guarantee than any reconciliation could provide after the
fact.

### 15.5 Immutable, not immortal

§4.3. The audit cannot be rewritten and can be destroyed with its cause. Saying
so plainly is better than a claim of permanence the cascades contradict.

---

## 16. Engineering Review

**Six findings.**

### 16.1 Ownership — one violation, in the read model

**No write violation exists**, and the write model is the strictest in the
schema.

**The read rule contradicts `SL-2` §6** — §17.1, `RH-R1`.

### 16.2 A guard exists against double-reversal and not against double-application

`RH-C7` makes it impossible to reverse an entry twice. **Nothing prevents the
same result's effects being applied twice** — which would double every
participant's movement for that match.

**It is not reachable through the approved path**: the recording operation
reverses before applying, inside one transaction under the match lock. **But the
symmetry is missing**, and the guard that would close it is cheap: uniqueness on
`(user_id, match_id, change_reason)` restricted to in-effect entries
(`RH-C12`).

**Assessment: a latent gap, not a live defect.** Recorded as `RH-R4`.

### 16.3 No reconciliation — and three checks are available

**DP-11 requires derived data to be reconcilable and the mechanism to exist.**
The audit is reconcilable and **no reconciliation exists**:

| # | Check | Cost | Detects |
|---|---|---|---|
| 1 | **`rating_after − rating_before = delta`**, per row | A single scan, or a check constraint (`RH-C10`) | A corrupted or hand-written entry |
| 2 | **`5.00 + sum(in-effect deltas) = users.overall_rating`**, per player | One aggregate | **A rating changed outside `apply_rating_delta`** — §11.2 |
| 3 | **Every reversal's delta equals the negation of its target's** | One self-join | A reversal that undid the wrong amount |

**Check 1 is expressible as a constraint** and should simply be added.
**Check 2 is the valuable one**: it is the only mechanism that would detect a
rating moved outside the audited path.

Recorded as `RH-R3`.

### 16.4 Two columns encode one fact and are not tied together

`change_reason = 'REVERSAL'` and `reverses_id is not null` must always agree.
**Nothing enforces it** (`RH-C11`), and if they disagreed the reversal query
(which filters on `reverses_id`) and the displayed narrative (which reads
`change_reason`) would tell different stories.

**Expressible as a check.** Recorded as `RH-R5`.

### 16.5 Duplicate responsibilities — none

No figure, no counter, no current value is stored here. The before/after pair
is not a duplication of `users.overall_rating` but a record of two moments it
passed through.

### 16.6 Performance — sound

Four indexes, each with a driving query. The correction path reads one match's
entries — a handful — inside a lock. The profile reads one player's, bounded by
their career. **No unbounded scan exists.**

### 16.7 Summary

| Finding | Verdict |
|---|---|
| Read model contradicts `SL-2` §6 | **`RH-R1`, Medium** — §17.1 |
| No double-application guard | **`RH-R4`, Low** — latent |
| No reconciliation | **`RH-R3`, Medium** — DP-11 |
| Reason and `reverses_id` untied | **`RH-R5`, Low** |
| Duplicate responsibilities | **None** |
| Performance | **Sound** |

---

## 17. Validation and contradictions

| # | Source | Verdict |
|---|---|---|
| 1 | `Statistics_Leaderboards_MVP_Specification.md` §6 | **CONTRADICTION** — §17.1 |
| 2 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction.** `RR-1` is §4.7; `RR-2`'s open question is §4.4; `RR-5` is §4.1–§4.2 in full; `RR-7`'s user-deletion limitation is `RH-R2` |
| 3 | `Docs/06-ERD.md` §3 | **No contradiction.** `E6` is *"many per player, one per rating change"*; §3.6 states both ratings keep a history *"for the same reason"* |
| 4 | `Player_Statistics_Table_Specification.md` | **No contradiction.** Its §4.3 (why counters are not ratings) is §3.2 here; its DP-8 treatment names this table as the historical record it is protected from |
| 5 | `Profiles_Table_Specification.md` §11.2 | **No contradiction — and it is the authority for §4.4.** It designates this table as the home of an administrative actor, which §11.1 accepts and §14.1 specifies |
| 6 | `Match_Results_Table_Specification.md`, `Match_Goals_Table_Specification.md` | **No contradiction.** Both name the applied-delta property as what makes their own replacement safe |
| 7 | `Community_Statistics_Table_Specification.md` | **No contradiction.** Its §4.2 confirms the Level 2 history is `E9`, separate; §4.10 here records the template |
| 8 | `Matches_Table_Specification.md` | **No contradiction.** Its §6.4 reversal-before-cascade is what makes `RH-C2`'s cascade safe |
| 9 | `Docs/01-PRD.md` | **No contradiction.** *A system-managed player rating, applied and reversed with each result* |
| 10 | `Docs/10-Design-Decisions.md`, `Docs/07-Database-Design.md` | **No contradiction** |
| 11 | **Database Principles** | **No artifact in the repository** — thirteenth phase |
| 12 | `SUPABASE_OPERATIONAL_GUIDELINES.md` §4 | **No contradiction.** RLS enabled, access explicit, select-only, `SECURITY DEFINER` with pinned `search_path`, revoked from client roles |

### 17.1 The contradiction — a player cannot read their own full rating history

**`SL-2` §6 states**, of the Player Profile:

> *"Rating History is a read of the existing audit… **Leaving a community does
> not change this screen.** Global Statistics span every community the player
> has played in, including ones they have left."*

**The read rule as built scopes entries to the community of the causing
match.** A player who leaves a community immediately loses sight of every rating
change earned there — on their own profile, describing their own career.

**Both cannot be true.** The rule the specification requires is §10.2's: **self
is unconditional; other people's entries stay scoped by shared membership.**

**Root cause.** The four results tables received one read rule between them —
*members of the match's community* — which is right for `match_results`,
`match_goals` and the lineup, all of which describe a **match**. **This table
describes a player**, and inherited a rule written for a different subject.

**Not resolved silently.** Recorded as `RH-R1`, §20 item 1. **It does not affect
an approved decision** — `SL-2` §6 already states the required behaviour, and
this is the implementation departing from it.

---

## 18. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `RH-R1` | **A player cannot read their own rating history for a community they have left**, contradicting `SL-2` §6 | **Medium** | **Open**, §20 item 1 |
| `RH-R2` | **Deleting an MVP's or scorer's account destroys a result without reversing**, leaving other players' audit entries describing a cause that no longer exists | Medium | **Inherited** — `MRS-R1`, `MG-R1` |
| `RH-R3` | **No reconciliation.** A rating moved outside `apply_rating_delta` would leave no trace and nothing would detect it | Medium | **Open**, §16.3. DP-11 requires the mechanism |
| `RH-R4` | **No guard against applying one result's effects twice**, though double-reversal is guarded | Low, latent | **Open**, `RH-C12` |
| `RH-R5` | **`change_reason` and `reverses_id` are not tied together** | Low | **Open**, `RH-C11` |
| `RH-R6` | **`created_at` will be mistaken for an ordering.** Every row of one recording shares it | Low | **Documented** (`RH-C9`, §6.2). Not expressible as a constraint |
| `RH-R7` | **Approving administrative adjustment requires three schema changes here**, one of which weakens `RH-C2` for all entries | Low today | **Specified in advance**, §14.1 |
| `RH-R8` | **"Immutable, forever" overstates the guarantee** — the audit is destroyed with its match or its player | Low | **Corrected in this specification** (§4.3); the migration comment remains as written, per the append-only rule |

---

## 19. Open decisions

| ID | Question | Recommendation |
|---|---|---|
| `RH-D1` | **May an administrator adjust a rating by hand?** (`RR-2`, open since the results phase) | **Not an engineering decision.** If approved, §14.1 specifies the three changes; **do not approve it without them**, because the table cannot represent the adjustment today |
| `RH-D2` | **Add the three cheap integrity constraints** — `RH-C10` (delta arithmetic), `RH-C11` (reason ⇔ `reverses_id`), `RH-C12` (no double-application)? | **Yes to all three.** Each is a check or a partial unique rule, each closes a gap that is currently unguarded, and none changes behaviour |
| `RH-D3` | **Do the `DP-n` readings match their approved definitions?** | **Confirm**, together with `BDC-D4`, `MRS-D4`, `MG-D1`, `PS-D1` and `CS-D4` |
| `RH-D4` | **How deep is the displayed rating history?** (`OQ-5`) | **A presentation parameter.** §9.2 records the index to add if it becomes unbounded |

---

## 20. Conformance

| # | Deviation | Required by | Severity | Notes |
|---|---|---|---|---|
| 1 | **A player cannot read their own history for a community they have left** | §10.2, `SL-2` §6 | **Medium** | Add an unconditional self tier to the read rule; keep the shared-community tier for other people's entries. **Verify the profile query and assert the denial and the permission in the integration suite** |
| 2 | **Three integrity constraints absent** | `RH-C10`, `RH-C11`, `RH-C12` | Low | `RH-D2`. Check existing rows before adding `RH-C12` |
| 3 | **No reconciliation** | DP-11, §16.3 | Medium | Check 2 is the valuable one and is a single aggregate per player |

**Everything else conforms.** The structure, all three foreign keys, the
immutability trigger, the `reverses_id` uniqueness, the four indexes, the
select-only access model, the append-only write path and the absence of
`updated_at` are exactly as specified.

**Nothing was changed in this phase.** No code, no SQL, no migration and no
Supabase object was touched.

---

## 21. Engineering Approval

**Status: Engineering Approved — conditional** on §20 item 1.

**The audit architecture itself is sound.** The dedicated review found **no
weakness in immutability, the reversal model, the correction workflow, ordering
or precision** — the five properties everything else depends on. The one
architectural weakness is in the **read model**, and it is a rule written for a
different subject applied to this one.

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5` | ✓ §0 |
| Purpose, business ownership, domain ownership, lifecycle ownership | ✓ §1 |
| Lifecycle — five transitions, eight invalid | ✓ §2 |
| Responsibilities — eight owned, seven not | ✓ §3 |
| **Dedicated audit architecture review — all ten checks** | ✓ §4 |
| Relationships, including the schema's only self-reference | ✓ §5 |
| Every column — ten, all immutable | ✓ §6 |
| Keys: primary, **business key (none, with reasons)**, candidate, alternate, foreign | ✓ §8 |
| Constraints | ✓ 8 enforced, 5 specified |
| Index strategy — four, each with a driving query | ✓ §9 |
| Access control | ✓ §10 |
| Audit model — **the table is the audit** | ✓ §11 |
| Dependencies both directions | ✓ §12 |
| Engineering principles — eleven | ✓ §13 |
| Future compatibility | ✓ §14 |
| Engineering review — six findings | ✓ §16 |
| Validation; contradictions named, not resolved | ✓ 12 sources, **1 contradiction** |
| Risks, open decisions, rationale | ✓ §15, §18, §19 |
| No SQL, no migration, no implementation | ✓ |

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Results_Rating_Engineering_Decisions.md` | **`RR-1`, `RR-2`, `RR-5`, `RR-7`** — the decisions this table implements |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **§6 — the contradiction** (§17.1); `SL-3`, `SL-5` |
| `engineering/Profiles_Table_Specification.md` | Holds `users.overall_rating`, the rating this audits; **§11.2 designates this table as the home of an administrative actor** |
| `engineering/Player_Statistics_Table_Specification.md` | The counters beside the rating; DP-10 |
| `engineering/Community_Statistics_Table_Specification.md` | Level 2's counters; `E9` is this table's sibling (§4.10) |
| `engineering/Match_Results_Table_Specification.md` | The cause of every entry |
| `engineering/Match_Goals_Table_Specification.md` | Evidence for `GOAL` entries |
| `engineering/Matches_Table_Specification.md` | Supplies the lock and the cascade that runs after reversal |
| `Docs/06-ERD.md` | §3.2 `E6`; §3.6 the two ratings and their histories |
| `Docs/01-PRD.md` | *A system-managed player rating, applied and reversed with each result* |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §4 security checklist |
