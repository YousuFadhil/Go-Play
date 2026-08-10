# Community Rating History (`community_rating_history`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved** |
| Role | **Engineering Authority** for the physical table `public.community_rating_history` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Level 2 |
| Scope | **`public.community_rating_history` only.** The Community Rating and leaderboards appear **only as sibling or dependent entities** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-02 |

> **This table does not exist.** It is the **last of the three Level 2
> entities** and a **greenfield specification**: every column, key, index,
> constraint and access rule below is a design decision taken here.
>
> **It contains no SQL, no migration and no implementation**, and it designs no
> Community Rating and no leaderboards.
>
> **It inherits a template.** `Rating_History_Table_Specification.md` §4.10
> records what `E9` should take from `E6` and where it must differ. §4 states
> what was inherited, what was changed, and — in three places — **what Level 1
> lacks and this table specifies from the start.**
>
> **Sibling authorities.** The fourteen table specifications, the BTGE database
> contract and the three engineering authorities, listed in *Related
> documents*.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Community Rating History** — entity `E9` in the conceptual model |
| **Physical table** | **`community_rating_history`** |

**One row is one movement of one player's rating in one community.**

**The name follows `rating_history`**, singular, because both are ledgers rather
than collections — and the prefix is what distinguishes the Level 2 audit from
the Level 1 one at a glance.

---

## 1. Purpose

### 1.1 Business purpose

A Community Rating History entry records that **one player's rating in one
community moved by a stated amount, from a stated value to a stated value, for a
stated reason, in a stated match**.

**It exists for exactly one reason, and it is not display.** `SL-4` §4.5 states
it plainly:

> *"Community Rating History is preserved too, and exists for the same reason
> the global audit does: a corrected result must reverse exactly, and reversal
> is only exact when the applied delta is recorded (`RR-5`, `RR-1`). It has **no
> reader in the MVP** — no screen displays it — **but it is not optional**."*

**So this is the only table in the schema whose entire justification is a
mechanism.** It is a working part of the Level 2 correction path, and nothing
looks at it.

**Why it cannot be skipped.** The engine's deltas are clamped at the ends of the
`0.00 … 10.00` range. A player at `10.00` in a community who wins gains nothing.
**Reversing by the nominal constant would hand back a tenth they never
received**, and the error compounds with every subsequent correction. Only a
record of what was *applied* makes reversal exact — and this is that record.

### 1.2 Business owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That an entry exists** | **The system** | The Level 2 rating path, inside the recording operation |
| Every column | **The system, exclusively** | The same, once, at insert |
| **Nothing, ever after** | — | **No column is writable after insert, by anyone** (§4.1) |

**As at Level 1, there is no human owner of any value and no human owner of a
row's continued existence.**

### 1.3 Domain ownership

**Domain: Statistics. Position: the audit of the Community Rating, sitting
beside the value it describes.**

| Property | Value |
|---|---|
| Aggregate | **None.** Not in the Match aggregate; not beneath the Community root in the ownership sense |
| Describes | `community_ratings.rating` |
| Depends on | `communities`, `users`, `matches`, and **itself** |
| Depended on by | **Nothing** — but the Level 2 correction path cannot work without it |
| Community-scoped | **Yes** — §6.2 column 3 |
| Contains authorization | **No** |

**It is the second self-referencing table in the schema**, and the reason is the
same: a reversal must be recorded without touching what it reverses.

### 1.4 Lifecycle ownership

| Bounded by | Consequence |
|---|---|
| **The match** | Cascades with it, after the reversal has run |
| **The community** | Cascades with it — `A7` |
| **The player's account** | Cascades with it |
| **A reversed entry** | Its reversal cascades with it |
| **NOT the membership** | **`SL-4`, and this is the defining negative.** *"Community Rating History is preserved"* on departure — it must never cascade from `community_members` |
| **Not its own** | **An entry has no lifecycle. It is written once and never changes** |

---

## 2. Lifecycle

### 2.1 The shape

```
  NO ENTRY
      │
      │  a result is recorded for a match in THIS community
      ▼
  WRITTEN ─────────────────────── and never modified again
      │
      │  the result is corrected
      ▼
  REVERSED ── NOT by editing this entry. A NEW entry is written,
      │        carrying the opposite of the APPLIED delta and naming
      │        this one. Both rows exist, forever.
      │
      ├── the player leaves the community ──▶ NOTHING HAPPENS. Preserved.
      ├── the player rejoins               ──▶ NOTHING HAPPENS. Still preserved.
      │
      ▼
  GONE ── only when the match, the community, or the account is deleted
```

### 2.2 Every valid transition

| # | From | To | Trigger | Notes |
|---|---|---|---|---|
| 1 | None | Written | A result is recorded for a match in this community | One entry per movement (§2.4) |
| 2 | Written | **Still written, and reversed** | The result is corrected, or its match is deleted | **A second row appears; the first is untouched** |
| 3 | Written | **Unchanged** | **The player leaves the community** | **`SL-4` §4.2 — explicitly preserved** |
| 4 | Written | **Unchanged** | **The player rejoins** | Preserved, and now describing an active member again |
| 5 | Written | Gone | The match is deleted | Cascade, **after** the reversal has run |
| 6 | Written | Gone | The community is deleted | Cascade — `A7` |
| 7 | Written | Gone | The account is deleted | Cascade |
| 8 | Written | Gone | The entry it reverses is deleted | Cascade through `reverses_id` |

**Transitions 3 and 4 are the ones that distinguish this table from its Level 1
counterpart**, and they are transitions in which **nothing happens** — which is
precisely the point of `SL-4`.

### 2.3 Invalid transitions

| Invalid | Why | Refused by |
|---|---|---|
| **Editing any column** | An audit that changes when the facts change can answer neither *what happened* nor *what is true now* | **Three layers** — §4.1 |
| **Reversing an entry twice** | Would subtract a movement applied once | `CRH-C8` |
| **Reversing a reversal** | A correction reverses originals and applies new ones | The reversal query selects only entries with no `reverses_id` |
| **Deleting an entry on departure** | **`SL-4` §4.2 — preserved in full** | No operation deletes one |
| **Cascading from a membership** | **`A7`** | **No foreign key to `community_members`** |
| An entry with no community | It would describe a rating that has no identity | `community_id` is NOT NULL |
| An entry whose community differs from its match's | The community is derived from the match; two answers would disagree | `CRH-C6` |
| A reason outside the five | Each names a rule in the engine | `CRH-C5` |
| **A client writing anything** | | **No write access, and no read access either** (§10) |

### 2.4 What one match produces

**Per participant, in a fixed deterministic order** — inherited from Level 1 so
that the two audits read the same way:

| Order | Reason | Who | Delta |
|---|---|---|---|
| 1 | `WIN` / `LOSS` | Every participant — **only if the match was not drawn** | `+0.10` / `−0.10` |
| 2 | `GOAL` | Each scorer, **one entry per scorer** | `0.05 × goals` |
| 3 | `MVP` | Exactly one participant | `+0.20` |

**And exactly one community's worth of entries.** A match belongs to one
community, so a single match produces entries in this table for that community
and no other — which is the isolation rule expressed in the audit.

**A drawn match produces no outcome entry**, exactly as at Level 1. The Level 2
counters record a draw; the Level 2 rating does not move for it.

---

## 3. Responsibilities

### 3.1 What this table owns

| # | Responsibility | Column |
|---|---|---|
| 1 | **Every Community Rating movement ever applied** | The row's existence |
| 2 | **The applied delta** — what actually moved, not what was nominally due | `delta` |
| 3 | **The value before and after** | `rating_before`, `rating_after` |
| 4 | **Why it moved** | `change_reason` |
| 5 | **Which match caused it** | `match_id` |
| 6 | **Which community's rating it describes** | `community_id` |
| 7 | **Which movement a reversal undoes** | `reverses_id` |
| 8 | **The order movements were applied in** | `entry_no` |
| 9 | **Whether an entry is still in effect** | **A query, never a flag** |

### 3.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **The current Community Rating** | `community_ratings` | A running value; this is its ledger |
| 2 | **Any counter** | `community_statistics` | Counters and ratings are different kinds of number (`SL-5`) |
| 3 | **The period dimension** | `community_statistics` | An audit records movements, not windows. §4.6 |
| 4 | **Global Rating movements** | `rating_history` | Two levels, two audits, no overlap (§4.9) |
| 5 | **Eligibility** | `community_members`, at read time | An audit of what happened is unaffected by who is a member now |
| 6 | **Who caused the change** | **Nowhere** | §4.8 — the same designed-in gap Level 1 has |
| 7 | **A permanent record** | — | §4.3 — immutable, not immortal |

---

## 4. Audit architecture — inherited, changed, and improved

**The template is `Rating_History_Table_Specification.md` §4.10.** This section
states what each row of that template became.

### 4.1 Immutability — **inherited unchanged, three layers**

| Layer | Covers |
|---|---|
| No update policy — **and no policy at all** (§10) | Every client, for every operation |
| A `BEFORE UPDATE` trigger raising an immutability error | The `SECURITY DEFINER` functions, which run past row rules |
| `reverses_id` unique where present | One entry cannot be reversed twice |

**Each covers a path the others do not.**

### 4.2 The reversal model — **inherited unchanged**

A reversal is **a new row naming what it undoes**, carrying the opposite of the
**applied** delta, with its own before and after. *"Still in effect"* is a
query — `reverses_id is null` **and** nothing reverses it — never a flag,
because a flag would require writing to a historical row.

**Reversal walks newest-first**, so every intermediate value is one the range
already accepted and **no clamp can fire on the way out**.

### 4.3 Historical integrity — **inherited, with one addition**

> **Immutable, and not immortal.**

The audit cannot be rewritten. It **is** destroyed with its match, its
community, or its player.

**The addition is what it survives**: `SL-4` requires it to survive a
**departure** and a **rejoin**, and it does — because nothing in its key or its
foreign keys references a membership.

### 4.4 Precision — **inherited unchanged**

`numeric(4,2)` for `delta`, `rating_before` and `rating_after`, matching
`community_ratings.rating` exactly (`RR-1`).

**Every approved delta is a multiple of `0.05`**, so two decimals are exactly
sufficient. **Storing the applied delta rather than the constant is what makes
clamping survivable**, and it is the reason this table exists at all (§1.1).

### 4.5 Ordering — **inherited unchanged**

`entry_no`, a database-generated identity, because `created_at` cannot order
entries written in one transaction — every row of one recording shares it.

**An ordering, never a count**: identity columns gap after a rollback.

### 4.6 The community dimension — **the one addition to the shape**

`E6` is keyed by player and match. **`E9` adds `community_id`**, and it is the
only structural difference between the two audits.

**It is a deliberate denormalization**, because the community is derivable by
joining to the match. **It is justified on three grounds, and the third is what
makes it safe:**

| # | Ground |
|---|---|
| 1 | **The subject of the entry is a *(player, community)* rating.** An audit that can only name its subject by joining elsewhere describes it indirectly |
| 2 | **Reconciliation needs it directly** — §16.3's check is per `(community, player)`, and joining every entry through `matches` to perform it would make the check expensive enough to skip |
| 3 | **It can never drift.** The row is immutable and a match cannot be reparented (`MT-C14`), so **both the source and the copy are frozen at insert.** A denormalization between two immutable values is not a denormalization risk |

**And there is no period column** (§3.2 item 3). A period is a property of a
*counter's* window; an audit records movements, each of which happened at an
instant. `SL-5` keeps the period on the counters and on eligibility, and this
table inherits neither.

### 4.7 What Level 1 lacks and this table specifies from the start

**Three integrity constraints.** `Rating_History_Table_Specification.md` records
them as `RH-C10`, `RH-C11` and `RH-C12` — **specified, expressible, and absent**
from the built Level 1 table, recommended as `RH-D2`.

**A greenfield table has no reason to repeat the omission**, so all three are
required here:

| Constraint | What it catches |
|---|---|
| `CRH-C9` — **`rating_after − rating_before = delta`** | A corrupted or hand-written entry, per row |
| `CRH-C10` — **`change_reason = 'REVERSAL'` if and only if `reverses_id` is present** | Two columns encoding one fact drifting apart |
| `CRH-C11` — **at most one in-effect entry per `(user_id, match_id, change_reason)`** | **A result's effects applied twice** — the symmetric guard to `CRH-C8`, which Level 1 has only in one direction |

**This is the clearest benefit of specifying Level 2 after Level 1 was built:**
the gaps found by auditing the first are closed by design in the second.

### 4.8 Administrative adjustments — **the same designed-in gap, deliberately**

Level 1's audit cannot record an administrative adjustment: `match_id` is NOT
NULL, the reason vocabulary has no manual value, and there is no actor column
(`RH-D1`).

**This table has the same three properties, and that is correct.** No approved
document contemplates a manually adjusted Community Rating, and adding a
nullable `match_id` and an unused actor column **against a decision nobody has
taken** would leave two columns waiting for a purpose.

**If administrative adjustment is ever approved at either level, it should be
approved at both and changed the same way** — the three changes are identical
and are specified in `Rating_History_Table_Specification.md` §14.1. Recorded as
`CRH-D1`.

### 4.9 Relationship with the Global Rating History — **two audits, no overlap**

| | `rating_history` (`E6`) | This table (`E9`) |
|---|---|---|
| Audits | `users.overall_rating` | `community_ratings.rating` |
| Community dimension | **None** | **`community_id`** |
| Written when | **Every** recorded result, any community | **The same results**, but recording one community's movement |
| Reader | The Player Profile | **None** (§10) |

**One recorded result writes to both**, in the same transaction, describing two
different numbers that moved by the same nominal deltas and may differ in the
applied ones — because the two ratings clamp independently.

**That last point is worth stating**, because it is the strongest argument
against a shared audit: a player at `10.00` globally and `7.00` in this
community gains nothing globally and `+0.10` here from the same win. **One entry
could not describe both.**

### 4.10 Relationship with the Community Rating — **its ledger, written together**

The Community Rating holds the current value; this table holds every change.
**Neither substitutes for the other**: the current value cannot reconstruct the
history, and the history is what makes a correction exact.

**They must be written in the same statement flow**, so that a rating which
moved without an audit entry is not a state the schema can reach — the property
`apply_rating_delta` already gives Level 1, and the reason `CR-D1` makes this
table a build condition of that one.

### 4.11 Review summary

| Property | Verdict |
|---|---|
| Immutability | **Inherited unchanged** — three layers |
| Reversal model | **Inherited unchanged** |
| Historical integrity | **Inherited**, plus survival of departure and rejoin |
| Precision | **Inherited unchanged** |
| Ordering | **Inherited unchanged** |
| Community dimension | **Added**, and safe because both sides are immutable |
| Period dimension | **Correctly absent** |
| Three integrity constraints | **Specified from the start** — Level 1's gaps closed |
| Administrative adjustment | **Same gap, deliberately** — `CRH-D1` |
| Global audit | **No overlap.** One result, two audits |
| Community Rating | **Its ledger**, written indivisibly |

---

## 5. Relationships

### 5.1 Incoming

| Source | Column | On delete |
|---|---|---|
| **Itself** | `reverses_id` | **`CASCADE`** |

**Nothing else references this table, and nothing should.**

### 5.2 Outgoing

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `communities` | `community_id` | many : 1 | **`CASCADE`** | **Identifying** — `A7` |
| `users` | `user_id` | many : 1 | **`CASCADE`** | **Identifying** |
| `matches` | `match_id` | many : 1 | **`CASCADE`** | **Identifying** — the cause |
| Itself | `reverses_id` | many : 0..1 | **`CASCADE`** | Self-reference |

**Four foreign keys — the most of any table in the schema**, and the fourth that
must never exist:

> **No foreign key to `community_members`, and none to `community_ratings`.**

**Not to the membership**, by `A7` and `SL-4`. **Not to the rating**, because an
audit entry is a fact about a moment and the rating row is a mutable current
value — the same reasoning that keeps `rating_history` referencing the player and
the match rather than `users.overall_rating`.

### 5.3 Ownership and deletion

| Question | Answer |
|---|---|
| **Who owns the meaning?** | The **player and the community jointly** — it is their rating that moved |
| **Can an entry be reparented?** | **No.** Nothing writes any column after insert |
| **Deletion — match** | The reversal runs first, then the cascade | 
| **Deletion — community** | Cascade. Its matches go too, so most entries leave by both routes |
| **Deletion — account** | Cascade |
| **Deletion — membership** | **Nothing.** `SL-4`, `A7` |
| **Directly** | **No path exists** |

### 5.4 Lifecycle

| Relationship | Whose lifetime bounds whose |
|---|---|
| `communities`, `users`, `matches` → entry | **Absolutely**, each independently |
| entry → its reversal | **Absolutely** |
| **`community_members` → entry** | **Neither. This is `SL-4`** |
| entry → `community_ratings.rating` | **Neither.** The rating outlives every entry; entries outlive nothing |

---

## 6. Columns

**Eleven columns** — the widest table in the schema, and every column load-bearing.

### 6.1 Summary

| # | Name | Type | Nullable | Default | Editable |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `entry_no` | `bigint` | No | **identity** | **Never** |
| 3 | `community_id` | `uuid` | No | none | **Never** |
| 4 | `user_id` | `uuid` | No | none | **Never** |
| 5 | `match_id` | `uuid` | No | none | **Never** |
| 6 | `change_reason` | `text` | No | none | **Never** |
| 7 | `delta` | `numeric(4,2)` | No | none | **Never** |
| 8 | `rating_before` | `numeric(4,2)` | No | none | **Never** |
| 9 | `rating_after` | `numeric(4,2)` | No | none | **Never** |
| 10 | `reverses_id` | `uuid` | **Yes** | `null` | **Never** |
| 11 | `created_at` | `timestamptz` | No | `now()` | **Never** |

**Every column is "Never"** — the second table in the schema with no writable
column at all, and for the same reason: append-only is what the entity *is*.

### 6.2 Column detail

Columns inherited from `rating_history` carry their Level 1 justification
unchanged and are stated briefly; **column 3 is the addition and is stated in
full.**

---

**1. `id` — `uuid`, NOT NULL, generated.** Row identity, **and the target of
`reverses_id`** — a surrogate with a real consumer, as at Level 1.

**2. `entry_no` — `bigint`, NOT NULL, identity.** The order movements were
applied in. **An ordering, never a count** (§4.5).

---

**3. `community_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* **Which community's rating this movement belongs to.**

*Business justification.* It is half the subject: this table audits a
*(player, community)* rating, and an entry that could not name its community
without a join would describe its own subject indirectly.

**It is a deliberate denormalization** — the community is derivable from the
match — **and it is safe because both sides are immutable**: the row is never
updated, and a match can never be reparented (`MT-C14`). **A copy that cannot
drift from a source that cannot move is not a denormalization risk** (§4.6).

*It also carries the `A7` cascade directly*, rather than relying on the
match's — so the community's ownership of its Level 2 audit is structural rather
than transitive.

*Must equal the match's community* (`CRH-C6`).

---

**4. `user_id` — `uuid`, NOT NULL.** Whose rating moved. The other half of the
subject.

**5. `match_id` — `uuid`, NOT NULL.** What caused the movement, and how the
reversal finds what to undo. **NOT NULL, which is what blocks administrative
adjustment** (§4.8).

**6. `change_reason` — `text`, NOT NULL, five values.** `WIN`, `LOSS`, `GOAL`,
`MVP`, `REVERSAL` — the same closed vocabulary as Level 1, deliberately, so both
audits read alike.

---

**7. `delta` — `numeric(4,2)`, NOT NULL**

*Purpose.* **How much the rating actually moved.**

*Business justification.* **The column this table exists for.** It records the
*applied* delta, which differs from the constant wherever clamping truncated the
movement — and reversing by the constant would invent a rating the player never
held (§1.1).

**And it may differ from the Level 1 entry for the same event**, because the two
ratings clamp independently (§4.9).

---

**8–9. `rating_before`, `rating_after` — `numeric(4,2)`, NOT NULL.** The values
either side, making each entry **self-verifying** — and `CRH-C9` enforces the
arithmetic, which Level 1 leaves unchecked.

**10. `reverses_id` — `uuid`, NULLABLE.** Which entry this undoes. **Null is
meaningful**: an original has none. Unique where present (`CRH-C8`), and tied to
`change_reason` by `CRH-C10`.

**11. `created_at` — `timestamptz`, NOT NULL.** When the movement was applied.
**Not an ordering** — every row of one recording shares it (`CRH-C12`).

### 6.3 No `updated_at`, and no actor column

**No `updated_at`**: nothing updates a row, so it could never differ from
`created_at`. A modification timestamp on an immutable table would be a
contradiction in the schema.

**No actor column**: §4.8.

---

## 7. Constraints

### 7.1 Identity, integrity and immutability

| ID | Rule | Why it exists |
|---|---|---|
| `CRH-C1` | **`community_id` references `communities(id)`, cascading** | `A7`. The community owns its Level 2 audit directly, not transitively |
| `CRH-C2` | **`user_id` references `users(id)`, cascading** | A movement for nobody is not a fact |
| `CRH-C3` | **`match_id` references `matches(id)`, NOT NULL, cascading** | Every movement has a cause. The cascade is safe because the reversal runs first |
| `CRH-C4` | **`reverses_id` references this table, cascading** | A reversal cannot outlive what it reverses |
| `CRH-C5` | **`change_reason` is one of the five** | A sixth value names no rule and would read as *not `REVERSAL`* to the reversal query — invisible where it matters most |
| `CRH-C6` | **`community_id` equals the match's community** | Two columns describe one fact; if they disagreed, an entry would be filed under a community whose match it did not belong to. §4.6 |
| `CRH-C7` | **`delta`, `rating_before`, `rating_after` are `numeric(4,2)`, NOT NULL** | `RR-1`. Must match `community_ratings.rating` exactly |
| `CRH-C8` | **`reverses_id` is unique where present** | One movement may be reversed once |
| `CRH-C9` | **`rating_after − rating_before = delta`** | Makes every entry self-verifying, and is the only per-row check that could detect a corrupted audit. **Level 1 lacks this** (§4.7) |
| `CRH-C10` | **`change_reason = 'REVERSAL'` if and only if `reverses_id` is present** | Two columns encode one fact and must not drift. **Level 1 lacks this** |
| `CRH-C11` | **At most one in-effect entry per `(user_id, match_id, change_reason)`** | Guards against a result's effects being applied twice — the symmetric partner of `CRH-C8`. **Level 1 lacks this** |
| `CRH-C12` | **`created_at` is never used to order entries** | Every row of one recording shares it; `entry_no` is the ordering. **A convention, not expressible as a constraint** |
| `CRH-C13` | **No column may be updated** | A `BEFORE UPDATE` trigger **and** the absence of any policy |
| `CRH-C14` | **No client may read, insert, update or delete** | §10 |
| `CRH-C15` | **Every entry is written in the same statement flow as the rating movement it records** | A rating that moved without an entry must be unreachable (§4.10) |
| `CRH-C16` | **No foreign key to `community_members`** | **`SL-4`, `A7`.** The audit survives a departure |

### 7.2 Deliberately not constrained

| Not constrained | Why not |
|---|---|
| A bound on `delta` | Goals are unbounded, so the goal delta is |
| That `rating_after` lie within `0.00 … 10.00` | Enforced on `community_ratings`; recording an out-of-range value here would be evidence of a clamp failure, and refusing to record it would hide the evidence |
| That the player be a member | **`SL-4` forbids it** — the audit outlives membership |
| Deletion | Deliberately permitted by cascade (§4.3) |
| A period | §4.6 |

---

## 8. Keys

### 8.1 Primary key

**`id`** — a generated `uuid`, **with a real consumer**: `reverses_id`
references it. As at Level 1, `entry_no` is deliberately *not* the primary key,
because an ordering that may gap is the wrong thing for a reference to point at.

### 8.2 Business key

**None — and correctly.** An entry is an *event*, and events have no natural
key: the same player can receive two `GOAL` entries for one match across a
correction cycle (an original, a reversal, and a new original).

### 8.3 Candidate keys

| Candidate | Unique? |
|---|---|
| `id` | **Yes** — primary |
| `entry_no` | **Yes** — an alternate key (§8.4) |
| `reverses_id` | **Yes where present** — a partial key over reversals |
| `(user_id, match_id, change_reason)` | **No** — unique only among in-effect originals (`CRH-C11`) |

### 8.4 Alternate keys

**`entry_no`.** Unique, NOT NULL, generated — used for ordering rather than
addressing.

### 8.5 Foreign keys

**Outgoing — four** (§5.2), three identifying and one self-referencing.
**Incoming — one**, from itself.
**Forbidden — `community_members` and `community_ratings`.**

---

## 9. Index Strategy

**Fewer indexes than Level 1's audit, because this table has no display
reader.**

### 9.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `CRH-X1` | **Primary key on `id`** | (a) the `reverses_id` foreign key check on every reversal; (b) the self-cascade |
| `CRH-X2` | **`(match_id)`** | **The correction path** — selecting a match's in-effect entries to reverse. The only high-frequency query, and it runs inside the match lock. Also serves the cascade from `matches`, which is how most entries leave |
| `CRH-X3` | **Unique on `reverses_id`, where present** | (a) enforcement of `CRH-C8`; (b) **the `NOT EXISTS` in the in-effect predicate**, evaluated once per candidate during every correction |
| `CRH-X4` | **`(user_id, community_id)`** | (a) **the reconciliation** — `5.00 + sum(in-effect deltas) = community_ratings.rating`, per pair (§16.3); (b) the cascade from `users`. **It has no display reader**, and §9.2 says so plainly |

### 9.2 Considered and not required

| Candidate | Verdict |
|---|---|
| `(community_id)` alone | **No.** The cascade from `communities` is served transitively: deleting a community deletes its matches, and `CRH-X2` removes the entries by that route |
| `(user_id, community_id, entry_no DESC)` | **No, for now.** It would serve *display this player's rating history in this community* — **a screen that does not exist and is out of MVP scope.** Add it with the screen, not before |
| `(change_reason)` | **No.** Low cardinality, no query |
| `(created_at)` | **No.** Nothing orders by it, and `CRH-C12` forbids treating it as an ordering |

### 9.3 The rule for a future designer

> **This table is read by match during a correction, and by pair during a
> reconciliation. Nothing displays it.** An index serving a display query should
> arrive with the display, and its absence today is a statement about scope, not
> an oversight.

---

## 10. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 10.1 The rule: no client access of any kind

| Actor | Read | Insert | Update | Delete |
|---|---|---|---|---|
| **Everyone** — `anon`, non-member, player, member, admin, owner, System Administrator | **✗** | ✗ | ✗ | ✗ |
| **The system** | — | ✓ **Only actor** | ✗ **Nobody, ever** | ✓ Cascade only |

**RLS enabled, and no policies at all.** The table is reachable only through
`SECURITY DEFINER` functions.

### 10.2 Why no read policy — and why that is the correct choice rather than a lazy one

**`SL-4` §4.5 states that this table has no reader in the MVP**: *"no screen
displays it — but it is not optional."* The statistics specification's §12 lists
*"Displaying Community Rating History on any screen"* as **out of scope**.

**So there is no consumer to grant.** And
`SUPABASE_OPERATIONAL_GUIDELINES.md` §4 recognises this exact shape as one of
two valid arrangements:

> *"Either the table has policies naming exactly who may `select`, `insert`,
> `update` and `delete`, **or it has no policies at all and is reachable only
> through `SECURITY DEFINER` functions.** Both are valid."*

**This is the `system_admins` pattern**, and it is the strongest protection
available: **a table with no policies cannot leak through a policy that was
written for a different subject.**

**That last point is not abstract.** `rating_history` — Level 1's audit — carries
a read policy inherited from the results tables, written for records that
describe a *match*, applied to a table that describes a *player*. The result is
`RH-R1`: **a player cannot read their own rating history for a community they
have left**, contradicting `SL-2` §6.

**Granting no read at all cannot produce that class of defect**, and when a
reader is approved the policy will be written for this table's actual subject
rather than inherited from a neighbour.

### 10.3 When a reader is approved

**Add a policy scoped to the community**, matching `community_ratings` §10.2 —
because the subject is a community-scoped value and the screens that would show
it are community screens. **Do not inherit the results tables' rule.**

---

## 11. Audit model

**This table is the audit**, so the four columns are asked of it differently.

| Column | Required? | Verdict |
|---|---|---|
| `created_at` | **Required** | When the movement was applied — **not an ordering** (`CRH-C12`) |
| `updated_at` | **Must not exist** | Nothing updates a row |
| `created_by` | **Not required today** | §4.8 — required only if administrative adjustment is ever approved, at both levels together |
| `updated_by` | **Must not exist** | There is no update to attribute |

### 11.1 What the audit does not cover

**It does not record what it did not cause.** A Community Rating changed outside
the audited path would leave no entry, and **nothing would detect it** — until a
reconciliation exists (§16.3).

---

## 12. Dependencies

### 12.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `communities` | Identifying parent, cascading | Owns the community and bounds the audit (`A7`) |
| `users` | Identifying parent, cascading | Owns the player |
| `matches` | Identifying parent, cascading | Owns the cause; supplies the community (`CRH-C6`) and the row locked while entries are written |
| **Itself** | Self-reference | Owns the reversal relationship |
| `community_ratings` | **Not referenced — the value it audits** | Written together, indivisibly (§4.10) |
| `match_results`, `match_goals`, `match_team_assignments` | **Not referenced — the evidence** | Determine who moves and by how much |

### 12.2 Tables depending on this table

**None by foreign key.** By behaviour, **one — and it is not a reader:**

| Consumer | Dependency |
|---|---|
| **The Level 2 correction path** | **Cannot reverse a Community Rating without this table.** Not a display read: the audit is a working part of the operation |

**This is the only table in the schema whose sole consumer is a mechanism.**

---

## 13. Engineering Principles

The readings established across this phase are applied unchanged. **Nine of the
eleven have no textual definition in this repository** — the fifteenth phase in
which that is recorded (`CRH-D3`).

| Principle | Verdict |
|---|---|
| **DP-1 Match Aggregate Root** | **Conforms from outside.** Entries are caused by a match, take its id, and are written under its lock |
| **DP-2 Match Row Lock** | **Conforms, inherited.** Without it, two corrections could interleave reversals |
| **DP-3 Business Transition** | **Conforms absolutely.** One route, no policy admitting another, **and no update route for anyone** |
| **DP-4 Historical Identity** | **Conforms, and this table is a definition of it.** It states what happened, identified by player, community and match, and stores nothing about the process |
| **DP-5 Final Participation** | **Conforms.** Entries are generated from the stored lineup |
| **DP-6 Single Business Path** | **Conforms.** One writer; apply and reverse differ only in a negated delta and a target |
| **DP-7 Producer / Commit Separation** | **Conforms by not applying.** An entry is entailed by the movement it records |
| **DP-8 Historical Record Protection** | **This table is the principle's subject at Level 2.** §4.1–§4.3 |
| **DP-10 Independent Derivation** | **Conforms.** Level 1's audit and this one are written from the same evidence independently; neither derives from the other (§4.9) |
| **DP-11 Derived Data Reconciliation** | **Specified, not yet built.** §16.3 — and unlike Level 1, it is required here from the start |
| **DP-12 Evidence Before Derivation** | **Conforms, with the inherited exposure.** An entry exists only while its match does; the cases where evidence is destroyed without reversal are `MRS-R1` and `MG-R1` |

---

## 14. Future Compatibility

### 14.1 Displaying the history — additive, and the index arrives with it

Out of MVP scope. When approved: a read policy scoped to the community (§10.3)
and the deferred index (§9.2). **No structural change.**

### 14.2 Administrative adjustment — the same three changes as Level 1

§4.8, `CRH-D1`. A nullable `match_id` paired with a constraint requiring a match
for every engine reason, a new `change_reason` value, and an actor column.
**Approve at both levels together or neither.**

### 14.3 A rating decay or inactivity adjustment

Any automatic movement is still a movement and must be audited with an applied
delta and a new reason value. **The table is ready; the reason vocabulary is the
extension point.**

### 14.4 New periods, seasons or tournaments

**No change.** Periods live on the counters (§4.6). A season-scoped *rating*
would be a new entity, not a column here — and `SL-5` already settled that the
named period forms are boards rather than stored ratings.

### 14.5 What must never be added

| Never | Why |
|---|---|
| A period column | §4.6 |
| A `reversed_at` or `is_reversed` flag | §4.2 — it would require writing to a historical row |
| The current rating | §3.2 — a second answer to what `community_ratings` holds |
| An `updated_at` | §6.3 |
| A membership reference | `SL-4`, `A7`, `CRH-C16` |
| A foreign key to `community_ratings` | §5.2 — an immutable record must not depend on a mutable row |

---

## 15. Engineering Rationale

### 15.1 The applied delta is the reason the table exists

Everything else — append-only, the before/after pair, newest-first reversal — is
machinery in service of storing what actually moved. Without clamping there
would be no need for this table at all; with it, there is no alternative.

### 15.2 The community column is denormalized, and immutability makes it safe

§4.6. A copy that cannot drift from a source that cannot move is a copy with no
risk — and it buys a self-describing entry and a cheap reconciliation.

### 15.3 No policies at all, because there is no reader

§10.2. And the choice is not merely conservative: it is the one arrangement that
**cannot** reproduce `RH-R1`, where a policy written for a match-shaped record
was applied to a player-shaped one.

### 15.4 Level 1's gaps are closed here by design

§4.7. Three constraints Level 1 lacks are required from the start. **This is the
value of specifying the second implementation after auditing the first**, and it
is the clearest example of it in the phase.

### 15.5 The rating and its audit are written together

§4.10. One flow, so a movement without an entry is unreachable — the property
that makes `CR-D1` a build condition rather than a preference.

---

## 16. Engineering Review

**Five findings.** A design review — the table does not exist.

### 16.1 Ownership — none possible

No read access, no write access, no human actor. **Nothing to violate.**

### 16.2 Duplicate responsibilities — one, deliberate and safe

`community_id` duplicates a fact derivable from the match. §4.6 states the three
grounds and why immutability removes the risk. **Assessment: justified.**

### 16.3 Reconciliation — required from the start

**DP-11.** Two checks, and both are cheap:

| # | Check | Detects |
|---|---|---|
| 1 | **`rating_after − rating_before = delta`** | A corrupted entry — **and here it is a constraint** (`CRH-C9`), so it cannot be violated rather than merely detected |
| 2 | **`5.00 + sum(in-effect deltas) = community_ratings.rating`**, per pair | **A rating moved outside the audited path** — the only mechanism that would catch it (§11.1) |

**Check 2 is the valuable one**, served by `CRH-X4`, and it is the Level 2
equivalent of the check `RH-R3` records as missing at Level 1.

### 16.4 The build-order dependency runs the other way

`CR-D1` makes **this table** a condition of the Community Rating. **This table
has no such dependency in return** — it can be built first, and probably should
be.

**Assessment: build this one first.** It is the only ordering in which neither
table is ever live without the other's guarantee.

### 16.5 Performance — sound

Four indexes, each with a driving query. The correction path reads one match's
entries inside a lock. **No unbounded scan exists**, and no display query exists
at all.

### 16.6 Summary

| Finding | Verdict |
|---|---|
| Ownership | **None possible** |
| Duplicate responsibility — `community_id` | **Justified**, and safe by immutability |
| Reconciliation | **Required from the start** — one check is a constraint |
| Build order | **This table first** |
| Performance | **Sound** |

---

## 17. Validation and contradictions

| # | Source | Verdict |
|---|---|---|
| 1 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction.** `SL-4` §4.5 requires this table, states it has no MVP reader, and forbids it being dropped as unused — §1.1 and §10.2. §12 places display out of scope |
| 2 | `Docs/06-ERD.md` §3 | **No contradiction.** `E9` is *"many per pair, one per rating change"* and *"preserved on departure"*; §3.6 states both ratings keep a history *"for the same reason"* |
| 3 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction.** `RR-1` is §4.4; `RR-5` is §4.1–§4.2 in full; `RR-2`'s write model is §10 |
| 4 | `Rating_History_Table_Specification.md` v1.0 | **No contradiction; the template is followed.** §4.10 there is §4 here. **Its `RH-D2` recommendations are implemented as `CRH-C9`–`CRH-C11`**, and its `RH-R1` is what §10.2 avoids by construction |
| 5 | `Community_Rating_Table_Specification.md` v1.0 | **No contradiction.** Its `CR-D1` is answered by §16.4; its §4.5 states this dependency from the other side |
| 6 | `Community_Statistics_Table_Specification.md` v1.0 | **No contradiction.** Counters carry the period; this audit does not (§4.6) |
| 7 | `Docs/01-PRD.md` | **No contradiction.** Nothing displays this table |
| 8 | `Docs/10-Design-Decisions.md`, `Docs/07-Database-Design.md` | **No contradiction.** `07-Database-Design.md` states *"A Community Rating History is required… It has no reader in the MVP; it is not optional"* |
| 9 | `SUPABASE_OPERATIONAL_GUIDELINES.md` §4 | **No contradiction — and §10.2 uses its own stated pattern.** RLS enabled with no policies is explicitly recognised as valid |
| 10 | **Database Principles** | **No artifact in the repository** — fifteenth phase |

**No contradiction found.**

---

## 18. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `CRH-R1` | **Built after `community_ratings`**, leaving a live rating that cannot be corrected exactly | **High if it happens** | **Prevented by §16.4** — build this table first |
| `CRH-R2` | **Inherited: deleting an MVP or scorer's account destroys a result without reversing**, leaving entries describing a cause that no longer exists | Medium | **Inherited** — `MRS-R1`, `MG-R1` |
| `CRH-R3` | **No reconciliation.** A Community Rating moved outside the audited path would leave no trace | Medium | **Specified** (§16.3); build it with the table |
| `CRH-R4` | **A table nobody reads is a table nobody notices is wrong.** With no display, a defect could persist indefinitely | Medium | **This is why §16.3 is required rather than recommended.** The reconciliation is the only observer |
| `CRH-R5` | **Pressure to drop it as unused** will recur, because it has no reader | Low, and the consequence is severe | **Refused in advance.** `SL-4` §4.5: *"it is not optional."* §1.1 states the mechanism it serves |
| `CRH-R6` | **`created_at` will be mistaken for an ordering** | Low | **Documented** (`CRH-C12`). Not expressible as a constraint |

---

## 19. Open decisions

| ID | Question | Recommendation |
|---|---|---|
| `CRH-D1` | **Administrative adjustment of a Community Rating** | **Not approved, and not recommended separately.** If taken, approve at both levels together and make the same three changes (§4.8, §14.2) |
| `CRH-D2` | **Build this table before `community_ratings`?** | **Yes** (§16.4). It is the only ordering in which neither table is live without the other's guarantee |
| `CRH-D3` | **Do the `DP-n` readings match their approved definitions?** | **Confirm**, with the six earlier requests |

---

## 20. Build instruction

| # | Requirement | Source |
|---|---|---|
| 1 | **Build this table before or with `community_ratings`** | `CRH-D2`, `CR-D1` |
| 2 | **Three immutability layers**, including the `BEFORE UPDATE` trigger | `CRH-C13` |
| 3 | **RLS enabled with no policies at all** | §10.2 |
| 4 | **All three integrity constraints Level 1 lacks** | `CRH-C9`–`CRH-C11` |
| 5 | **Write each entry in the same statement flow as the movement** | `CRH-C15` |
| 6 | **Reverse newest-first, by the applied delta** | §4.2 |
| 7 | **Build the reconciliation with the table** | §16.3 |
| 8 | **Test the reversal against a real database.** `RR-4` passed review by inspection and a clean migration | `RR-4` |

**Nothing was changed in this phase.** No code, no SQL, no migration and no
Supabase object was touched.

---

## 21. Engineering Approval

**Status: Engineering Approved.**

**Unconditionally** — the first Level 2 specification with no open condition.
The build-order requirement (`CRH-D2`) is a recommendation about sequence, not a
dependency this table has: **it depends on nothing that does not yet exist.**

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5` | ✓ §0 |
| Purpose, business ownership, domain ownership, lifecycle ownership | ✓ §1 |
| Lifecycle — eight transitions, nine invalid, **including two in which nothing happens** | ✓ §2 |
| Responsibilities — nine owned, seven not | ✓ §3 |
| **Audit architecture — inherited, changed, and three gaps closed** | ✓ §4 |
| Relationships — **four foreign keys**, two forbidden | ✓ §5 |
| Every column — eleven, all immutable | ✓ §6 |
| Keys: primary, **business key (none, with reasons)**, candidate, alternate, foreign | ✓ §8 |
| Constraints | ✓ 16 |
| Index strategy — four, **fewer than Level 1 because nothing displays it** | ✓ §9 |
| Access control — **no policies at all**, with the reasoning | ✓ §10 |
| Audit model | ✓ §11 |
| Dependencies both directions | ✓ §12 |
| Engineering principles — eleven | ✓ §13 |
| Future compatibility | ✓ §14 |
| Engineering review — five findings | ✓ §16 |
| Validation — **no contradiction found** | ✓ 10 sources |
| Risks, open decisions, rationale | ✓ §15, §18, §19 |
| No SQL, no migration, no implementation | ✓ |

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Rating_History_Table_Specification.md` | **The template** (§4.10 there). Its `RH-D2` gaps are closed here as `CRH-C9`–`CRH-C11`; its `RH-R1` is what §10.2 avoids |
| `engineering/Community_Rating_Table_Specification.md` | **The value this audits.** Its `CR-D1` is answered by §16.4 |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **`SL-4` §4.5** — required, no MVP reader, not optional |
| `Docs/06-ERD.md` §3 | `E9`, §3.6, `A7` |
| `engineering/Community_Statistics_Table_Specification.md` | The Level 2 counters — the period lives there, not here |
| `engineering/Results_Rating_Engineering_Decisions.md` | `RR-1`, `RR-2`, `RR-5` |
| `engineering/Matches_Table_Specification.md` | Supplies the lock, the community and the cascade that runs after reversal |
| `engineering/Communities_Table_Specification.md` | The parent that bounds this audit (`A7`) |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §4 — **the no-policies pattern §10.2 uses** |
