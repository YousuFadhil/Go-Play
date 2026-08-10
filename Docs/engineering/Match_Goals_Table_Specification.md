# Match Goal (`match_goals`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One Medium-severity consistency defect; see §18 and §20 |
| Role | **Engineering Authority** for the physical table `public.match_goals` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Results |
| Scope | **`public.match_goals` only.** `match_results`, `player_statistics`, Community Statistics, `rating_history` and leaderboards appear **only as dependent or parent entities** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **This document is the authoritative specification for the physical table
> `public.match_goals`.** Where an implementation and this document disagree,
> **the implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation**, and it designs no
> statistics, no ratings and no leaderboards.
>
> **It does not redesign approved product behaviour.** Approved context items
> 1–5 and 8–11 are taken as given and confirmed throughout. **Items 6 and 7, as
> written, contradict `SL-2` and `SL-3`** — §17.1 states the contradiction
> rather than resolving it silently, and this specification follows the
> approved specifications.
>
> **Sibling authorities.** The seven table specifications and
> `BTGE_Database_Contract.md` v1.0, listed in *Related documents*.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Match Goal Record** — collectively, **a result's scorers** |
| **Physical table** | **`match_goals`** |

**One row is not one goal.** It is *one scorer's tally for one match*: a
hat-trick is a single row saying three. §3.3 and §4.4 explain why, and it is
the decision the whole table turns on.

**The name is therefore slightly misleading**, and the specification records
that plainly: `match_goals` holds *goal counts per scorer*, not goals. A future
reader who expects one row per goal will misread the ordering question (§3.4),
the uniqueness rule (`MG-C3`) and the future-compatibility analysis (§14).

---

## 1. Purpose

### 1.1 Business purpose

A Match Goal Record states that **one player scored a stated number of goals in
one recorded match**.

It exists for exactly one reason, and being precise about it settles most of
this document: **the score alone does not say who scored.** A result of 3–2
moves ten players' ratings by the win/loss deltas; it says nothing about which
five of them the five goals belong to. This table is the only place that
attribution exists.

**Its consumers are two, and both are downstream:**

1. **The goal counter** on a player's career record.
2. **The goal award** in the rating engine — **+0.05 per goal**, which is why a
   scorer must be a participant (§7.2) and why a fabricated entry is a
   fabricated rating.

### 1.2 Business owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That a row exists** | **The organiser who records the result** | Recording, and re-recording |
| `goals` | The same organiser — it is part of their assertion about the match | Recording |
| `match_id`, `user_id`, `id`, `created_at` | The database | Nothing writes them after insert |

**Nobody else may write any of it**, including the scorer it credits. A player
who could add their own goal row would be awarding themselves rating.

### 1.3 Domain ownership

**Domain: Match. Position: inside the Match aggregate, beneath the result,
which is beneath the root.**

| Property | Value |
|---|---|
| Aggregate | **Member of the Match aggregate**, two levels below its root |
| Immediate parent | **`match_results`** — not `matches` (§5.2) |
| Aggregate root | `matches`, transitively |
| Depends on | `match_results` and `users` |
| Depended on by | **Nothing** |
| Contains authorization | **No** |

**It is the deepest table in the schema**, and the only one whose parent is
itself a child. That placement is deliberate and is the subject of §5.2.

### 1.4 Lifecycle ownership

| Bounded by | Consequence |
|---|---|
| **The result** | Absolutely. A goal record cannot exist without a recorded result, and cannot outlive one |
| **The match**, transitively | A deleted match takes the result, and the goals one cascade further along |
| **The scorer's account** | Cascades — **and this is where the consistency defect is** (§5.5, `MG-R1`) |
| **Not the clock** | Never expired, never archived |
| **Not its own** | **A goal record has no independent lifecycle at all.** Every write replaces the whole set for a match (§2.2) |

---

## 2. Lifecycle

### 2.1 The states

```
   NO GOAL RECORD
        │
        │  the result is recorded  ── the whole scorer set is written,
        ▼                             inside the result's transaction
   RECORDED
        │
        │  the result is corrected ── every row for the match is DELETED
        │                             and the new set INSERTED
        ▼
   REPLACED  ─────▶ (back to RECORDED with different rows)
        │
        ▼
   GONE   ── the result is deleted, the match is deleted,
             or the scorer's account is deleted
```

**There is no lifecycle of a goal record on its own.** A row is never edited,
never individually deleted, and never individually created. It exists exactly
as long as the version of the result that produced it.

### 2.2 Every valid transition

| # | From | To | Trigger | Notes |
|---|---|---|---|---|
| 1 | None | Recorded | The result is recorded | Written **inside the result's transaction**, after every validation has passed |
| 2 | Recorded | Replaced | The result is corrected | **Delete-all-then-insert-all**, for that match. Not an update, not a merge |
| 3 | Recorded | Gone | The result is deleted, or the match is | Cascade — and for the match path, the reversal has already run |
| 4 | Recorded | Gone | **The scorer's account is deleted** | Cascade. **The surviving rows no longer sum to the score** — `MG-R1` |
| 5 | Recorded | Historical | Time passes | Nothing changes |

### 2.3 Invalid transitions, and what refuses each

| Invalid | Why | Refused by |
|---|---|---|
| A goal record with no result | *"A goal is part of a recorded score, and one belonging to a match that has no result would be a number nothing adds up"* | The foreign key to the result (`MG-C1`) — **structural, not procedural** |
| Two rows for one scorer in one match | Not a bigger number — the same fact recorded twice, and which counted would be arbitrary | The business key (`MG-C3`), and `INVALID_GOALS` |
| A row saying zero or fewer | The row asserts that this player scored. Not scoring is **the absence of a row** | `MG-C4`, and `INVALID_GOALS` |
| A scorer who was not in the lineup | A goal is worth **+0.05**; without the rule an organiser could credit rating to any account in the system | `SCORER_NOT_PARTICIPANT` — **and, independently, the derivation ignores them** (§4.5) |
| Goals that do not sum to the score | Two statements about one match that disagree, with no rule for choosing | `GOALS_DO_NOT_MATCH_SCORE` |
| **Editing a row** | Would change a scorer's tally without reversing the statistics and rating it produced | **No write policy exists**, and no operation updates a row |
| **Deleting one row** | Would silently break the sum invariant | Same |
| **Adding a row to a recorded result** | Same | Same |
| A shootout goal | **Approved context item 11** — shootout goals are not football goals | §14.5 — nothing may write one here |

### 2.4 Why goals never mutate history directly

**Because goals are not history, and the history does not depend on them.**

This is the sharpest statement in the document and it deserves the space:

| | This table | The rating audit |
|---|---|---|
| What it holds | **The current attribution** for the current result | **Every rating change ever applied**, with its before, after and *applied* delta |
| On correction | **Replaced wholesale** | **Appended to** — a reversal is a new row naming the row it undoes |
| Can it be edited? | It is *rewritten*, never edited | **Never.** Three layers enforce it |
| Is it a historical record? | **No.** It is evidence attached to the current assertion | **Yes** |

**So a goals correction cannot corrupt history, because the correction never
touches history — it appends to it.** When a result is corrected:

1. The rating changes the previous goals produced are reversed **by new audit
   rows**, using the delta that was actually applied.
2. The counters are reversed by a separate statement over shared arithmetic.
3. **Only then** are the goal rows replaced.
4. The new rating changes are applied, **recorded as further new audit rows**.

**The audit's independence is what makes step 3 safe** (DP-8, §13.8). Because
each audit row stores the delta that was applied, reversal never needs to
re-read the goals — so replacing them cannot make an earlier reversal wrong.
**Had the audit stored only "this player scored, award the constant", replacing
the goals would have made history unreadable.**

### 2.5 Why the whole set is replaced rather than diffed

Correction deletes every row for the match and inserts the new set, even when
one scorer's tally changed by one.

| Reason | |
|---|---|
| **The set is the unit of meaning** | The rows collectively must sum to the score. A per-row diff would have to reason about the sum mid-way, and the intermediate state would violate it |
| **It matches the result's own semantics** | The result is upserted and the goals are replaced in the same transaction — one act, one shape |
| **A diff would need an identity per goal that does not exist** | A row is a tally, not an event (§3.3). "Which goal changed" is not a question this model can ask |
| **`RR-4`'s lesson applies** | Applying and reversing are separate statements over shared arithmetic. A merge would fuse them again |

---

## 3. Business Responsibilities

### 3.1 What this table owns

| # | Responsibility | How expressed |
|---|---|---|
| 1 | **The goal scorer** | `user_id` — the attribution the score cannot make |
| 2 | **The goal count** | `goals` — how many, in this match, by this player |
| 3 | **The match relationship** | `match_id`, pointing at the **result**, not the match (§5.2) |
| 4 | **Uniqueness of attribution** | One row per scorer per match (`MG-C3`) |
| 5 | **The evidence for two derived figures** | The goal counter and the per-goal rating award — **owning the evidence, never the figures** (§4) |

### 3.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **Any statistic** | `player_statistics`, and future Level 2 records | §4.2. Approved context item 8 |
| 2 | **Any rating** | `users.overall_rating`, `rating_history`, and the future Community Rating | §4.3. Approved context item 9 |
| 3 | **Any leaderboard** | Derived from Level 2 records | §4.4. Approved context item 10 |
| 4 | **The score** | `match_results` | The score is the assertion; these rows must agree with it, and the agreement is checked against it |
| 5 | **Who took part** | `match_team_assignments` | Approved context item 3. A scorer is validated against the lineup and is not defined here |
| 6 | **Which side a goal counted for** | Nowhere, and **this is a real gap** | §3.5 |
| 7 | **Ordering** | Nowhere, and **unrepresentable by design** | §3.4 |
| 8 | **Shootout goals** | Nowhere — and they must never appear here | §14.5, approved context item 11 |

### 3.3 One row is a tally, not a goal

**A hat-trick is one row saying three, not three rows saying one.**

The reasoning recorded when the table was built: *no approved document asks for
the minute a goal was scored or the order of them, and rows that recorded
neither would be three copies of the same fact.*

**Three consequences, all of them intended:**

- Total goals in a match is a **sum**, never a count of rows.
- **The number of rows is the number of scorers**, not the number of goals.
- **A goal has no identity.** There is no "the second goal" to reference,
  annotate or dispute.

### 3.4 Ordering — not owned, and not representable

The brief lists *ordering* among the things this table might own. **It owns
none, and cannot.**

| Candidate ordering | Why it does not exist |
|---|---|
| The order goals were scored | A row is a tally, so there is nothing to order |
| The order scorers are listed | Presentation. Any consumer may sort by name or by tally; nothing is stored |
| `created_at` as an ordering | **Useless here.** Every row of a match is inserted in one statement inside one transaction and shares an instant — the same reason the rating audit needed a separate sequence column to order entries within a recording |

**If goal ordering is ever required, the row model changes** — one row per goal
— and §14.4 states what that costs.

### 3.5 Which side a goal counted for — a gap, stated rather than hidden

**The table records who scored. It does not record which team's score the goal
increased.**

For an ordinary goal this is derivable: the scorer's team, from the lineup.
**For an own goal it is not**, and the consequence is `MG-R2` (§14.1): an own
goal is currently unrecordable without one of three bad outcomes.

No approved document mentions own goals, so this is a **limitation, not a
breach**. It is recorded here because the future-compatibility section is where
someone will look for it, and because the cost of discovering it late is a
migration on a table that feeds ratings.

---

## 4. The Goal Model

### 4.1 Goals are evidence

**A goal record is evidence submitted with an assertion.** The result is the
assertion — *this was the score* — and the goals are the supporting detail that
makes it attributable.

**Three properties of evidence, all of which this table has:**

| Property | How it holds here |
|---|---|
| **It must be consistent with the claim it supports** | The goals must sum to the score (`MG-C7`) — and the check is against the *result*, not within this table |
| **It is replaced when the claim is corrected**, not amended | §2.5 |
| **It is not the finding** | It produces the counter and the rating award; it holds neither |

### 4.2 Statistics are derived — and this table never holds one

**Approved context item 8, and it is structural rather than a matter of
discipline.**

A player's career goal counter lives in the statistics table and is computed by
the same shared helper that computes wins, losses, draws and MVP counts. That
helper reads **the result, the lineup and these rows together** and returns one
row per player.

**Why the counter cannot live here.** A counter is a career accumulation across
every match; a goal record is one match's attribution. Summing these rows to
answer *how many career goals* would be recomputing the statistics engine in a
query, in a second place, with no reversal path — which §4.4 of the Match
Results specification refuses for leaderboards and which applies identically
here.

**`A4` states the boundary from the other side:** statistics arise **only** from
a recorded result. These rows are part of a recorded result; they are not a
statistic.

### 4.3 Ratings are derived — and this table never holds one

**Approved context item 9.**

The rating engine awards **+0.05 per goal** to the named scorer, and records
each award in the append-only audit with its before, after and *applied* delta.

**Why the rating cannot be derived from these rows later.** Clamping: a player
at the top of the range gains nothing from a goal, so the applied delta differs
from the nominal one. **Reversal must use the applied delta**, which only the
audit preserves. **These rows can produce a rating change; they can never
reconstruct one.**

That asymmetry is the whole of DP-8 (§13.8) and the reason §2.4's step 3 is
safe.

### 4.4 Leaderboards are derived — two layers away

**Approved context item 10.**

A board reads Level 2 records; those are derived from results; these rows are
part of a result. **A board that read this table would be three derivations out
of place** and would recompute the statistics engine in a ranking query.

`SL-2` §2.3 makes it normative for Level 1; the same reasoning forbids reading
the evidence layer directly.

### 4.5 Why Match Goals are not statistics — the structural answer

The distinction is not merely conceptual. **The derivation is driven by the
lineup and left-joins these rows** — so:

- **A player in the lineup with no goal row contributes zero.** Absence of a
  row means zero goals, which is why `goals > 0` is correct rather than
  restrictive.
- **A goal row for a player *not* in the lineup contributes nothing at all.**
  It is not joined, so it produces no counter and no rating. **The
  participant rule is enforced twice** — once by validation, and once by the
  shape of the derivation.

**That second enforcement is defence in depth and worth naming**: even if
`SCORER_NOT_PARTICIPANT` were bypassed, a fabricated row could not award
rating. It could, however, break the sum rule — which is `MG-R3`.

**And the same mechanism produces a limitation:** if the lineup is replaced
after a result is recorded, a scorer removed from it keeps their goal row, but
**their goals will not be subtracted on reversal** — they are no longer joined.
That is `RR-7`'s lineup-edit limitation seen from this table.

### 4.6 The chain, as approved

**§17.1 records that approved context items 6 and 7 state this chain
differently.** The chain below is the one `SL-2` and `SL-3` approve:

```
   Result  +  Lineup  +  Goals          ← the assertion and its evidence
                │
      ┌─────────┴──────────┐            ← both derived from the SAME source,
      ▼                    ▼               independently and in parallel
  LEVEL 1              LEVEL 2 (unbuilt)
  · counters           · community counters
  · Global Rating      · Community Rating
  · rating audit       · community rating audit
                             │
                             ▼
                       Leaderboards
```

**Neither level feeds the other, and within each level the rating is not
derived from the counters.** `SL-3`: *"Neither rating is derived from the
other, neither is a view of the other."* `SL-2` §2.5: the two levels *"count
the same matches"* and should agree **by construction**, not by one being
computed from the other.

---

## 5. Relationships

### 5.1 Incoming

**None. Nothing references a goal record**, and nothing may:

- A row is deleted and recreated on every correction, so any reference would
  break at the next one — the same rule the lineup specification states for its
  own rows.
- There is nothing a consumer would need to name: a goal has no identity
  (§3.3).

### 5.2 Outgoing — and the unusual parent

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| **`match_results`** | `match_id` → **`match_results(match_id)`** | many : 1 | **`CASCADE`** | **Identifying — and it targets the alternate key, not the primary key** |
| `users` | `user_id` | many : 1 | **`CASCADE`** | Identifying — **and the defect** (§5.5) |

**Why the parent is the result and not the match.** This is the single most
important structural decision in the table:

| | If it referenced `matches` | Referencing `match_results` |
|---|---|---|
| Can a goal exist without a result? | **Yes** — *"a number nothing adds up"* | **No.** Structurally impossible |
| Is "no orphan goals" a rule? | A procedural one somebody must remember | **A property of the model** |
| What happens when a match is deleted? | Direct cascade | Cascade **one step further along**, after the result |

**Why it targets `match_id` rather than the result's `id`.** The child needs
`match_id` anyway — its own uniqueness rule is one entry per player per match,
and every consumer addresses it by match. Referencing the surrogate would mean
carrying a redundant second column alongside it. `match_results.match_id` is
unique and NOT NULL, so it is a valid target, and it is the business key of the
parent.

**This is the only foreign key in the schema that targets a non-primary key**,
recorded so it is not mistaken for an oversight.

### 5.3 Ownership

| Question | Answer |
|---|---|
| **Who owns the relationship's meaning?** | The **result**. These rows are its evidence and have no meaning apart from it |
| **Can a row be reparented?** | **No.** Nothing writes either key column; every change is a full replacement |
| **Does the result know its scorers?** | Only by reading them. **No count, no total and no scorer list is stored on the result** — that would be a second statement of the sum the score already makes |
| **Does this table know the lineup?** | **No foreign key, and correctly none.** Validation and derivation both reach it through the result's match |

### 5.4 Deletion behaviour

| Path | Behaviour | Assessment |
|---|---|---|
| **Correction** | All rows for the match deleted, new set inserted, inside the result's transaction | **Correct** |
| **The result is deleted** | Cascade | **Correct** |
| **The match is deleted** | The reversal trigger runs first, then the result cascades, then these rows | **Correct** — the match un-counts itself before its evidence disappears |
| **The scorer's account is deleted** | Cascade, **with no reversal and no re-validation** | **`MG-R1`** — §5.5 |
| **Directly** | **No path exists.** No delete policy, and no operation deletes a single row | **Correct** |

### 5.5 The cascade on `user_id` — the consistency defect

**Deleting a scorer's account removes their goal rows, leaving the survivors no
longer summing to the score.**

`GOALS_DO_NOT_MATCH_SCORE` is a business rule the recording operation enforces
on every write. **After a scorer's account is deleted, the stored data violates
it** — a result reading 3–2 with only four goals attributed.

**What is and is not damaged:**

| | Effect |
|---|---|
| Other players' counters and ratings | **Intact.** Their own goal rows and lineup rows survive, and the derivation reads per player |
| The deleted player's figures | Gone entirely — their counters, audit rows and lineup rows all cascade too |
| **The stored sum invariant** | **Violated, silently and permanently** |
| **The ability to correct that result** | **Lost at its recorded score.** An organiser correcting it must resubmit goals summing to the score — but the deleted scorer can no longer be named, so the only way to satisfy the rule is to change the score or misattribute their goals to someone else |

**That last row is the sharpest consequence** and is what raises this above a
cosmetic inconsistency: **a deleted scorer makes a past result uncorrectable as
recorded.**

**It is the same family as the MVP cascade** (`MRS-R1`), and the same family as
the account-deletion gaps recorded on registrations and the lineup. Rated
**Medium** here rather than High because the surviving players' figures stay
correct — the damage is to the record's internal consistency and to future
correctability, not to other people's careers.

### 5.6 Lifecycle

| Relationship | Whose lifetime bounds whose |
|---|---|
| `match_results` → these rows | **Absolutely**, and structurally |
| `matches` → these rows | **Absolutely**, transitively, and safely — the reversal runs first |
| `users` → these rows | **Absolutely, and unsafely** — `MG-R1` |
| These rows → anything | **They bound nothing.** Nothing depends on them structurally |

---

## 6. Columns

Five columns — **the smallest table in the schema**, and deliberately so.

### 6.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `match_id` | `uuid` | No | none | **Never** |
| 3 | `user_id` | `uuid` | No | none | **Never** |
| 4 | `goals` | `int` | No | none | **Never edited — replaced** |
| 5 | `created_at` | `timestamptz` | No | `now()` | **Never** |

**No column is ever updated.** Every write is a delete of the whole set and an
insert of the new one, so the table has **no mutable column at all** — which is
why §11.2 concludes it needs no `updated_at`, and why that conclusion differs
from the two tables in this phase where the same absence is a defect.

### 6.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated, never editable**

*Purpose.* Row identity.

*Business justification.* **It has no consumer, and — as with the lineup —
nothing could reference it**, because the row is destroyed by the next
correction. Every operation addresses rows by `match_id`, and every read by
`match_id` or by the pair.

**Retained, not defended.** The business key does the work (§8.2).

---

**2. `match_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Which recorded result this attribution belongs to. Half of the
business key.

*Business justification.* It is the scoping column of everything: the sum rule
is per match, the uniqueness rule is per match, the delete half of every
correction is by match, and every read filters on it.

**It names a result, not a match** (§5.2) — the value is the same uuid, but the
referential target is what makes an orphan goal unrepresentable.

*Never editable.* An attribution belongs to the occasion it was made about.

---

**3. `user_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* **The scorer.** The attribution the score itself cannot make.

*Business justification.* This is the column the table exists for (§1.1), and
it is the one that carries rating consequences: **+0.05 per goal** to whoever is
named.

*Validated against the lineup, not against registrations.* Participation is the
lineup's, absolutely (approved context item 3). A confirmed registration says a
player held a seat; it does not say they played.

*Never editable.* Correcting an attribution replaces the set.

*Its cascade is the defect* — §5.5.

---

**4. `goals` — `int`, NOT NULL, no default, strictly positive**

*Purpose.* **How many.** The tally, not an event count.

*Business justification.* One row per scorer with a count, rather than one row
per goal, because *no approved document asks for the minute a goal was scored
or the order of them, and rows that recorded neither would be three copies of
the same fact* (§3.3).

***Strictly positive, and this is load-bearing.*** *"The row asserts that this
player scored. Nobody scoring nothing is the absence of a row, and a match with
no goals has none at all."*

**Why zero must be excluded rather than merely discouraged:** the derivation
left-joins these rows and treats a missing row as zero. A stored zero would be a
second way to say the same thing — and the two would be indistinguishable to
every consumer while being distinguishable to a `count(*)`. The constraint
keeps *no goals* expressible exactly one way.

*No upper bound.* No approved rule sets one, and the sum rule already binds the
total to the score.

*No default.* A default tally would be an invented assertion.

---

**5. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When this attribution was written.

*Business justification.* It is the timestamp of **the most recent recording of
the result**, because every correction replaces the rows — so it does not say
when the goal was scored, and does not say when it was *first* attributed.

**It orders nothing** (§3.4): every row of a match shares one instant.

**Its honest use is narrow**, and stating it prevents misreading: it tells a
reader when the current version of this attribution was written, which — since
the result's own `created_at` survives corrections and its `updated_at` records
the latest — is nearly always the same information the result already carries.

### 6.3 No `updated_at`, and here that is correct

Two tables in this phase — `community_members` and `match_registrations` —
carry a mutable column with no modification timestamp, and both are recorded as
defects.

**This table is not one of them.** Nothing updates a row: correction deletes and
inserts. An `updated_at` would equal `created_at` on every row that will ever
exist.

**The comparison to `match_team_assignments` is instructive**: that table *has*
`updated_at` under the same delete-and-insert model, where it is vestigial and
retained on the ground that the Standards require the pair and a future
in-place edit would need it. **Here the same column is simply absent.**

**The two tables are inconsistent with each other**, and one of them is
carrying a column it never uses while the other is missing one it never would.
Recorded as `MG-R4` — cosmetic, and worth settling once rather than twice
(`MG-D2`).

---

## 7. Business Constraints

### 7.1 Enforced by the schema

| ID | Rule | Why it exists |
|---|---|---|
| `MG-C1` | **`match_id` references `match_results(match_id)`, cascading** | **"No orphan goals" as a property, not a rule.** A goal belonging to a match with no result would be a number nothing adds up |
| `MG-C2` | **`user_id` references `users(id)`, cascading** | A goal credited to nobody is not a fact. The cascade is where `MG-R1` lives |
| `MG-C3` | **One row per scorer per match** — `(match_id, user_id)` unique | Two entries for one player is not a bigger number: it is the same fact twice, and which of them counted would be arbitrary |
| `MG-C4` | **`goals` is strictly positive** | The row asserts scoring. Not scoring is the absence of a row, and a stored zero would be a second way to say it (§6.2 column 4) |
| `MG-C5` | **`goals`, `match_id`, `user_id` and `created_at` are NOT NULL** | Each is a fact the row cannot omit and still assert anything |
| `MG-C6` | **No client may insert, update or delete** | There are **no write policies of any kind**. A direct write would change a scorer's tally without reversing the statistics and rating it produced — leaving both permanently wrong and undetectably so |

### 7.2 Enforced by the recording operation

All checked **before anything is written**, and all inside the result's
transaction.

| ID | Rule | Why it exists |
|---|---|---|
| `MG-C7` | **The goals must sum to the total score** | The score and the goals are two statements about one match. If they disagree, every consumer must pick one and there is no rule for choosing. **This cannot be a schema constraint** — it is a cross-row aggregate compared against another table |
| `MG-C8` | **Every scorer must be in the lineup** | A goal is worth **+0.05**; without the rule an organiser could credit rating to any account in the system. Approved context item 4 |
| `MG-C9` | **Each scorer appears at most once in a submission** | The duplicate rule, checked before the unique constraint would raise, so the caller gets a meaningful refusal |
| `MG-C10` | **Each submitted tally is positive** | Refused rather than silently dropped, so a caller learns their submission was malformed |
| `MG-C11` | **Only an owner or admin of the match's community may write** | Recording moves other people's ratings |
| `MG-C12` | **The whole set is replaced, never merged** | §2.5 |
| `MG-C13` | **The match row is locked first** | DP-2, §13.2 |

### 7.3 Enforced by the shape of the derivation

| ID | Rule | How |
|---|---|---|
| `MG-C14` | **A row for a non-participant produces no statistic and no rating** | The derivation is driven by the lineup and left-joins these rows, so an unjoined row contributes nothing (§4.5). **Defence in depth behind `MG-C8`** |

### 7.4 Deliberately **not** constrained

| Not constrained | Why not |
|---|---|
| **An upper bound on a tally** | The sum rule already binds the total to the score, and no approved rule caps a score |
| **That the scorer was on the side the goal counted for** | **Own goals** — §3.5, §14.1. A constraint here would refuse a legitimate result once own goals are supported, and cannot be written today because the side is not recorded |
| **That the number of scorers is plausible for the score** | The sum rule is the only relationship that matters |
| **Ordering of any kind** | §3.4 — unrepresentable in this model |
| **A goal time, type, or assist** | §14 — none approved |
| **That shootout goals be excluded** | **Nothing can express a shootout goal here**, which is the strongest form of the exclusion (§14.5) |

---

## 8. Keys

### 8.1 Primary key

**`id`** — a generated `uuid`, and a surrogate with **no consumer and no
possible consumer** (§6.2 column 1).

### 8.2 Business key

**`(match_id, user_id)`.**

It states the central rule — one attribution per scorer per match — and it is
how every operation and every consumer addresses a row: the derivation's left
join is on exactly this pair, the correction deletes by its leading column, and
the read filters by it.

### 8.3 Candidate keys

| Candidate | Enforced | Assessment |
|---|---|---|
| `id` | Primary key | Generated, unused, unusable |
| **`(match_id, user_id)`** | Unique | **The business key**, and the only one the domain uses |

**Not a candidate key:** `(match_id, goals)` — several players may score the
same number in one match, which is ordinary.

### 8.4 Alternate keys

**One: `(match_id, user_id)`** — the business key is also the sole alternate
key.

**Nothing references it**, unlike the parent's alternate key, which is a foreign
key target (§5.2). Here the alternate key addresses rows; it does not anchor
them.

### 8.5 Foreign keys

**Outgoing — two:**

| Column | References | On delete | Assessment |
|---|---|---|---|
| `match_id` | **`match_results(match_id)`** — the alternate key | `CASCADE` | **Correct, and the reason orphans are impossible** |
| `user_id` | `users(id)` | `CASCADE` | **Wrong** — `MG-R1`, §5.5 |

**Incoming — none, and none may be added** (§5.1).

---

## 9. Index Strategy

### 9.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `MG-X1` | **Unique on `(match_id, user_id)`** | (a) **the derivation's left join**, on exactly this pair, once per participant per result recording, correction and reversal — the hot path; (b) **read the scorers of this match**, by the leading column, which is the only read the product performs; (c) the delete half of every correction; (d) the per-goal rating award, which reads a match's rows; (e) enforcement of `MG-C3` |
| `MG-X2` | **Primary key on `id`** (implicit) | **No query.** Listed as the counterpart to §8.1 |

**`MG-X1` is the only index this table requires.**

### 9.2 Present, without a driving query

| ID | Index | Assessment |
|---|---|---|
| `MG-X3` | **`(user_id)`** — `match_goals_user_id_idx` | **No query is driven by it.** Every reader addresses this table by match: the derivation joins on the pair, the rating award reads by match, the client reads goals nested under a result, and a player's career goal total comes from the **statistics table**, never from scanning these rows — §4.2 forbids the alternative. **The index is nonetheless justified by the cascade**: `user_id` carries `ON DELETE CASCADE` from `users`, and without an index every account deletion scans this table |

**Recommendation: retain, and record the justification correctly.** This is the
same situation as `match_team_assignments(user_id)`, and the same conclusion:
the stated reason is not the operative one, and the operative one is sufficient.

### 9.3 Considered and not required

| Candidate | Verdict | Reasoning |
|---|---|---|
| `(user_id, match_id)` | **No** | Would serve *a player's scoring history across matches*. **That query must not exist** — it is the statistics engine recomputed in a read (§4.2) |
| `(goals)` | **No** | Nothing filters or orders by tally. A "top scorer" board reads Level 2 records, not this table |
| `(created_at)` | **No** | Orders nothing (§3.4) |

### 9.4 The rule for a future designer

> **This table is read by match, and only by match.** An index that serves a
> per-player scan is a sign that a consumer is computing a statistic here
> instead of reading one from where it belongs.

---

## 10. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 10.1 The matrix

| Actor | Read | Insert | Correct | Delete |
|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ |
| **Non-member** | ✗ **Nothing** | ✗ | ✗ | ✗ |
| **Player / Community Member** | ✓ **The scorers of any match in their communities** | ✗ | ✗ | ✗ |
| **Organizer** *(the match's creator, as such)* | ✓ as a member | **✗** — not a role (§10.4) | ✗ | ✗ |
| **Community Admin** | ✓ | ✓ *(only as part of recording)* | ✓ *(only as part of correcting)* | ✗ |
| **Community Owner** | ✓ | ✓ *(same)* | ✓ *(same)* | ✗ |
| **System Administrator** | ✗ No direct path | ✗ | ✗ | ✓ Transitively |

**Insert, Correct and Delete are not separate capabilities here.** None of them
is reachable on its own: writing goals is a *step inside* recording a result,
and there is no operation that touches this table alone. The matrix marks them
for completeness, and §10.3 states what that means.

### 10.2 Read

**Any member of the match's community may read the scorers**, exactly as they
may read the result. A scoreline without attribution is half the news.

**Non-members see nothing.** **System Administrator has no read path**,
consistent with the whole Match aggregate.

### 10.3 Write — there is no write capability for this table

**There are no write policies of any kind**, and — more strongly than on any
other table in the schema — **there is no operation that writes this table by
itself.**

| | |
|---|---|
| Can an admin add a goal to a recorded result? | **No.** They re-record the result, with the full scorer set |
| Can an admin fix one scorer's tally? | **No.** They re-record the result |
| Can anyone delete one row? | **No.** Nothing deletes a single row, ever |

**Why this is right rather than merely strict:** every one of those operations,
if it existed, would change a scorer's rating and career counter **without
reversing what the previous attribution produced**. The table is protected not
by restricting a write path but by having none of its own — and the enclosing
operation is what guarantees the reversal happens.

### 10.4 The organizer is not a role

As on `match_results`: `matches.created_by` is attribution and is **never read
to grant or deny anything** (`PD-16`); `PD-07` moved match management to the
community role.

**An admin may record the scorers of a match they did not create; a player may
not record the scorers of one they did.**

---

## 11. Audit

| Column | Required? | State | Verdict |
|---|---|---|---|
| `created_at` | **Required** | Present | §6.2 column 5 — with its narrow honest meaning stated |
| `updated_at` | **Not required** | Absent | §11.2 |
| `created_by` | **Not required** | Absent | §11.1 |
| `updated_by` | **Not required** | Absent | §11.2 |

### 11.1 `created_by` — not required, and not derivable either

**This is a case the phase has not met before.** On `users` and
`community_members`, `created_by` was refused because it would equal a column
already present. Here it would carry genuine information — *which admin
attributed these goals* — and it is **still not required**, on a different
ground:

**The parent already records it.** `match_results.recorded_by` names whoever
performed the recording, and these rows are written in the same statement of the
same transaction. **A `created_by` here would be a copy of the parent's
column** — and `RR-6`'s discipline refuses a second answer to one question.

**The caveat inherited from the parent:** `recorded_by` is overwritten on every
correction, so it names the *most recent* recorder. **After a correction, who
originally attributed a goal is unrecoverable** — which is the parent's finding
(`MRS-R3`), and this table inherits it rather than being able to fix it.

### 11.2 `updated_at` and `updated_by` — not required, because nothing updates

**No column of this table is ever updated.** Correction deletes and inserts, so:

- `updated_at` would equal `created_at` on every row (§6.3).
- `updated_by` would have no update to attribute, and `UP-4` refuses a mutable
  last-writer column in any case.

**This is the cleanest instance of the pattern in the phase**: where
`match_registrations` lacks `updated_at` *and has a mutable column* — a defect —
this table lacks it *and has none*, which is correct.

### 11.3 What the audit does not cover

**No history of attributions.** A corrected result leaves no record of who was
previously credited with what. That a correction happened is inferable from the
rating audit; the previous attribution is not.

**Accepted**, and it is the same boundary the parent records (`MRS-R4`): the
rows are evidence for the current assertion, not a historical record.

---

## 12. Dependencies

### 12.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| **`match_results`** | Identifying parent, cascading, **via its alternate key** | **Owns the assertion these rows support**, their scope, their lifetime, and the sum they must satisfy |
| `users` | Identifying parent, cascading | Owns the person. **The cascade is the defect** (§5.5) |
| `match_team_assignments` | **Not a foreign key — the validation and derivation source** | Defines who may be named, and drives the join that turns these rows into figures (§4.5). Approved context items 3 and 4 |
| `matches` | Transitive, through the result | Supplies the community for authorization and the row for the lock |
| `community_members` | Not a foreign key — authorization | Answers who may read and who may write |

### 12.2 Tables depending on this table

**None by foreign key** (§5.1). **Three by behaviour**, and in each case this
table is an *input to a computation*, never a source of truth:

| Consumer | Dependency |
|---|---|
| `player_statistics` | The goal counter is computed from these rows, per player, by the shared helper |
| `rating_history` and `users.overall_rating` | The **+0.05** per-goal award is applied and reversed from them |
| Community Statistics and the Community Rating *(unbuilt)* | Will consume the same rows the same way |

**And one non-dependency worth naming:** leaderboards do **not** depend on this
table (§4.4). They are two derivations away, and a board reading these rows
would be reading the wrong layer.

---

## 13. Engineering Principles

The brief names eight, with `DP-n` identifiers. **Six have no textual
definition in this repository** — the tenth phase in which the absent *Database
Principles* document has been recorded. The reading applied is stated for each
and its basis marked, as the BTGE contract and the Match Results specification
did. **If a reading differs from the approved definition, this section is the
defect** (`MG-D1`).

### DP-1 Match Aggregate Root Principle — **conforms**

Everything hangs beneath the match: these rows sit two levels down, cascade
transitively with it, and resolve authority through the match's community.
There is no cross-match goal record and nothing above the match.

### DP-2 Match Row Lock Principle — **conforms, inherited**

The enclosing recording operation locks the match row before anything else —
before authorization, before validation, before any write. **These rows are
written inside that lock**, so the principle is satisfied without this table
needing an operation of its own.

**This matters concretely:** without it, two simultaneous corrections could each
delete the other's inserted rows.

### DP-3 Business Transition Principle — **conforms**

*Reading applied: a state change happens only through the business operation
that owns it, never through a direct write reaching the same state by another
route.*

**There is exactly one route, and it is not even this table's own** (§10.3). No
policy admits a second, and no operation writes these rows in isolation. **This
is the strictest conformance in the schema** — most tables have one write path;
this one has none of its own.

### DP-4 Historical Identity Principle — **conforms**

*Reading applied: a historical record states what happened, identified by the
entities that took part, never by the process that produced it.*

- These rows are **not** a historical record — they are evidence for the current
  assertion, replaced when it changes (§2.4). The specification says so rather
  than letting the two be conflated.
- They are identified by *(match, player)* — entities — never by a process, a
  version or a sequence number.
- **Nothing about the recording is stored here**: no actor, no version, no
  correction count.

### DP-5 Final Participation Principle — **conforms, and is enforced twice**

*Reading applied: participation is defined by exactly one record — the final
assignments — and every consumer resolves it there.*

- A scorer is **validated** against the lineup (`MG-C8`).
- A goal row **contributes** only when it joins the lineup (`MG-C14`).

**The second is the stronger conformance**: participation is not merely checked
at write time but is structurally required at derivation time. A row that
escaped the check would still produce nothing.

### DP-6 Single Business Path Principle — **conforms**

*Reading applied: one business outcome has one code path.*

Recording and correcting are one call, and writing these rows is one step
inside it. **There is no "add a goal" path to drift from an "edit a goal"
path**, because neither exists.

### DP-7 Producer / Commit Separation Principle — **conforms, by not applying**

*Reading applied: where a component computes a candidate a human may accept or
reject, computation and commitment must be separate steps.*

**Nothing computes a goal record.** It is asserted by a human, and its effects —
the counter and the rating award — are *entailed* by it, not a second decision.
As with the result itself, **separation would be a defect here**: goals stored
without their effects would be an attribution that had not counted, which is the
draft state the results model refuses.

**The principle governs BTGE, where the output is a proposal. It correctly does
not govern evidence submitted with an assertion.**

### DP-8 Historical Record Protection Principle — **conforms, and this table is the case that proves the principle's worth**

*Named "Historical Independence Principle" in this table's brief and
"Historical Record Protection Principle" from the Player Statistics brief
onward. The reading applied is unchanged; the later name is used across the
corpus.*

*Reading applied: a historical record's validity does not depend on the current
state of the data that produced it — it stands on its own.*

**This is the principle that makes goal correction safe**, and the mechanism is
worth stating exactly:

| If the audit stored… | Then replacing goals would… |
|---|---|
| *"this player scored, award the constant"* | require re-reading the goals to reverse — **and the goals have been replaced.** History would be unreadable |
| **The applied delta, per change** — as it does | need nothing from this table. **Reversal is exact regardless of what these rows now say** |

**So the audit's independence from this table is what permits §2.5's
delete-and-replace.** And it is why clamping — which makes the applied delta
differ from the nominal one — forced the design that also delivered this
property.

**Conformance statement:** these rows may be replaced freely without any risk to
the historical record, because the historical record never depends on them.

---

## 14. Future Compatibility

### 14.1 Own goals — the one future that needs a column, and a Product Decision first

**An own goal is currently unrecordable without one of three bad outcomes**,
and the specification states them because a future phase will meet them:

| Option today | Outcome |
|---|---|
| Name the player who scored it | **They receive +0.05 rating for it.** Wrong |
| Name nobody | **The sum rule refuses the result.** Wrong |
| Attribute it to a player on the benefiting side | **Falsifies the record**, and rewards the wrong player |

**What the table would need:** a marker distinguishing an own goal from an
ordinary one — a nullable flag, or a small `kind` vocabulary (§14.5).

**What must be decided first, and it is not an engineering question:** *how does
the rating engine treat an own goal?* Football convention credits the goal to
the opposing side and does not credit the scorer. The approved engine awards
**+0.05 to whoever is named**, and no approved document contemplates a negative
or absent award.

**Assessment: additive to the table, blocked on a Product Decision.** Recorded
as `MG-R2` and `MG-D3`.

### 14.2 Assists — additive, and a separate concept

An assist is *a different relationship to the same goal*. Two shapes are
possible and the choice is not this specification's:

| Shape | Assessment |
|---|---|
| A nullable `assist_user_id` on this row | **Only works while a row is one goal.** With a tally of three, one assist column cannot say who assisted which |
| A separate assists table, same shape as this one | **Consistent with the tally model** and additive. One row per assister per match, with a count |

**The second follows this table's own logic**, and neither requires a change
here. **Any rating consequence is a Product Decision** — no approved document
mentions assists.

### 14.3 VAR — no change here

As on the result: a review is *an assertion about an assertion*, and it records
who reviewed, when, and with what outcome. **Correcting the attribution is
already supported** — it is an ordinary correction.

**No status column belongs here**, and none belongs on the result either: a
`disputed` flag would be mutable state about a process, which DP-4 refuses.

### 14.4 Goal timestamps — the one future that breaks the row model

**A goal time cannot be added to this table.** A row is a tally, and three goals
cannot carry three times in one row.

**Supporting it means one row per goal**, which changes:

| What changes | To |
|---|---|
| The business key | **No longer `(match_id, user_id)`** — a player may score twice, so the pair stops being unique |
| The uniqueness rule | Gone, or replaced by something including the minute — which is not reliably unique either |
| `goals` | Removed, or fixed at one |
| The derivation | A `sum` where it currently reads a column |
| Ordering | **Becomes possible for the first time** (§3.4) |

**Assessment: this is a table redesign, not an extension.** It is the one
future in the brief's list that is not additive, and it is recorded so that the
cost is known before it is chosen rather than discovered during it. `MG-D4`.

**The cost is not an argument against it** — one row per goal is a perfectly
ordinary model, and the current one was chosen only because no approved document
asked for times or order. It is an argument for deciding deliberately.

### 14.5 Goal types — additive, and the vehicle for the shootout exclusion

A `kind` vocabulary — ordinary, penalty, own goal, free kick — is a nullable or
defaulted column, and additive. It would also carry §14.1's own-goal marker.

**And it is where approved context item 11 must be enforced.** **Penalty
shootout goals are not football goals and must never affect statistics or
ratings.**

> **The strongest form of that exclusion is the one in force today: a shootout
> goal cannot be represented in this table at all.**

There is no column for it, and the sum rule binds these rows to the match score
— which a shootout does not change. **If a `kind` vocabulary is ever added, a
shootout value must not be among its members**, because a shootout goal in this
table would be summed into the score check, counted in a career total and
awarded **+0.05** — breaching item 11 in three places at once.

**Where shootout scores belong** is the result — as separate nullable columns,
excluded from the goals-sum rule — which the Match Results specification §14.4
already states. **Nothing about a shootout comes here.**

### 14.6 The general rule

> **A new column on `match_goals` must be a property of *this scorer's tally in
> this match*, must not be a derived figure, and must not require a goal to
> have an identity.** Anything needing per-goal identity is the redesign in
> §14.4; anything about a shootout belongs to the result, or nowhere.

---

## 15. Engineering Rationale

### 15.1 A tally, because no approved document asked for an event

Three rows saying one, with no time and no order, would be three copies of the
same fact. The tally model is the smallest thing that answers every question the
product actually asks — and §14.4 records honestly that it is the one decision
a future requirement could overturn.

### 15.2 The parent is the result, so orphans are unrepresentable

Referencing the result rather than the match converts *"a goal must belong to a
recorded score"* from a rule somebody enforces into a shape the database cannot
express otherwise. It is the cheapest guarantee in the schema.

### 15.3 Zero is the absence of a row

The derivation left-joins and treats a missing row as zero. Permitting a stored
zero would create a second way to say the same thing, distinguishable only to a
row count. One representation, enforced.

### 15.4 The table has no write path of its own

Every conceivable single-row operation would change a rating without reversing
what the previous attribution produced. Having no such operation is a stronger
guarantee than having a careful one.

### 15.5 The audit's independence is what makes replacement safe

DP-8, §13.8. Because each audit row stores the delta that was actually applied,
reversal never re-reads these rows — so they can be discarded and rewritten
without any risk to history. **The property was forced by clamping and delivered
this for free.**

---

## 16. Engineering Review

**Six findings.**

### 16.1 Ownership violations — none

No client can write this table by any route, and no column belongs to anyone but
the enclosing operation. **There is not even a write path to withdraw**, unlike
`matches`, `communities` and `match_team_assignments`.

### 16.2 Duplicate responsibilities — none

No figure is stored here; no fact held here is duplicated elsewhere. **And one
duplication was actively avoided**: `created_by` is absent because the parent
already records it (§11.1).

### 16.3 History violations — none

`rating_history` is never touched by anything this table does, and DP-8 explains
why it need not be (§13.8). **These rows are not history and do not claim to
be** — §2.4 states the distinction explicitly.

### 16.4 Database consistency risks — two

| Risk | Assessment |
|---|---|
| **A deleted scorer breaks the sum invariant**, and makes the result uncorrectable at its recorded score | **`MG-R1`, Medium.** §5.5 |
| **A replaced lineup strands a goal row** — the scorer's goals were added but will not be subtracted on reversal, because the derivation no longer joins them | **`MG-R3`, inherited** from `RR-7`'s lineup-edit limitation, known and not approved for work |

**A third was checked and is not a risk:** a fabricated row for a non-participant
cannot award rating, because the derivation would not join it (§4.5). It would
break the sum rule, and the validation refuses it first.

### 16.5 Performance risks — none

Every access is by match, served by the composite index; the table is the
smallest in the schema; and every write is bounded by the number of scorers in
one match. **The one index without a driving query** (§9.2) is justified by the
cascade and costs a single maintenance step per write.

### 16.6 A cosmetic inconsistency with a sibling

This table has no `updated_at` and needs none; `match_team_assignments` has one
and never uses it. **Both are under a delete-and-insert write model**, so one of
them is wrong about the Standards — and the phase has now recorded both
positions with different justifications. Worth settling once (`MG-D2`).

### 16.7 Summary

| Finding | Verdict |
|---|---|
| Ownership violations | **None** — no write path exists to violate |
| Duplicate responsibilities | **None**, and one was avoided |
| History violations | **None** — DP-8 explains why none is possible |
| Consistency — deleted scorer | **`MG-R1`, Medium** |
| Consistency — stranded goal row | **`MG-R3`**, inherited, known |
| Performance | **None** |
| Cosmetic — `updated_at` inconsistency with a sibling | **`MG-R4`**, settle once |

**No approved product behaviour is redesigned by any of the above.**

---

## 17. Validation

**Contradictions are named, not resolved silently.**

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | **Approved context, items 6 and 7** | **CONTRADICTION with `SL-2` and `SL-3`** | §17.1 |
| 2 | `Match_Results_Table_Specification.md` v1.0 | **No contradiction** | Its §8.4 records this table's foreign key as targeting the parent's alternate key — §5.2 here states it from the child's side. Its `MRS-R3` (`recorded_by` is a last-writer column) is inherited in §11.1 |
| 3 | `BTGE_Database_Contract.md` v1.0 | **No contradiction** | Its §6.2 forbids BTGE writing this table; §10.3 confirms nothing but the recording operation writes it |
| 4 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction, and it is the authority §17.1 rests on** | `A4` (statistics only from a recorded result) is §4.2. `SL-2` §2.5 (the two levels count the same matches and agree **by construction**) and `SL-3` (the ratings are **independent**, neither derived from the other) are what items 6 and 7 contradict |
| 5 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction** | `RR-1` (why the applied delta must be stored) is what makes DP-8 hold. `RR-4` (apply and reverse are separate statements) is §2.5. `RR-5` (append-only audit) is §2.4. **`RR-7`'s lineup-edit limitation is `MG-R3`**, inherited and not resolved |
| 6 | `Matches_Table_Specification.md` v1.0 | **No contradiction** | Its §6.4 — deleting a match reverses before cascading — is why the match path is safe here |
| 7 | `Match_Team_Assignments_Table_Specification.md` v1.0 | **No contradiction; one inconsistency noted** | Its §4.2 (the lineup is authoritative for results) is `MG-C8` and `MG-C14`. **Its `updated_at` position differs from this table's** — `MG-R4`, cosmetic |
| 8 | `Docs/06-ERD.md` | **No contradiction** | §2: *"Goals reference the *result*, not the match"* — §5.2, stated identically |
| 9 | `Docs/01-PRD.md` | **No contradiction** | *Record match results: score, **goal scorers** and the MVP*. Goal scorers, not goals — which is exactly the tally model |
| 10 | `Docs/10-Design-Decisions.md` | **No contradiction** | `PD-07`, `PD-16` hold; `SL-1`…`SL-5` are the authority for §17.1 |
| 11 | **Database Principles** | **No artifact in the repository** | **Tenth phase.** Six of the eight `DP-n` principles have no definition here; §13 states the reading applied for each. **If a reading differs, §13 is the defect** — `MG-D1` |
| 12 | `Docs/07-Database-Design.md` | **No contradiction** | *"written only by `record_match_result` and carry select policies and nothing else"* — §10.3 |
| 13 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **No contradiction** | §4's checklist satisfied in full |

### 17.1 The contradiction — the derivation chain in the approved context

**Approved context items 6 and 7 state:**

> *6. Player Statistics feed Community Statistics.*
> *7. Community Statistics feed Ratings and Leaderboards.*

**As written, both contradict approved specifications:**

| Item | Contradicts | The approved position |
|---|---|---|
| **6** | `SL-2` | Level 2 is **additive beside** Level 1, not derived from it. `SL-2` §2.5: the two levels *"count the same matches"* and *"should agree **by construction**"* — because both are computed from the same results, **not because one is computed from the other**. `SL-2` opens by stating they are *"not two views of one record"* |
| **7** | `SL-3`, `SL-5` | *"**Independent** is the operative word. Neither rating is derived from the other, neither is a view of the other."* The Global Rating is *"updated by **every completed match**, in every community"* — i.e. by results, not by counters. And a rating is **not a counter**: `SL-5` makes it a running value with no natural zero, which no accumulation can produce. **Leaderboards** reading Community Statistics is correct (`SL-2` §2.3); **ratings** being derived from them is not |

**The approved chain** — which §4.6 documents and this specification follows:

```
Result + Lineup + Goals
   ├──▶ Level 1: counters, Global Rating, rating audit
   └──▶ Level 2: community counters, Community Rating, community audit
                        └──▶ Leaderboards
```

**Both levels derive from the same results, independently and in parallel.
Neither feeds the other, and within each level the rating is a sibling of the
counters, not a function of them.**

**Not resolved silently.** This may well be shorthand in the brief rather than a
decision — the two chains agree about what feeds what at the ends, and differ
only in the middle. **But the difference is not cosmetic:** if Level 2 were
computed from Level 1, `SL-4`'s requirement that a community record survive a
departure and resume on return would be unimplementable, because Level 1 has no
community dimension to survive in.

**Recorded as `MG-D5`, and resolved on 2026-08-02** in favour of the reading applied here — see `Player_Statistics_Table_Specification.md` §17.1.
This specification follows `SL-2` and `SL-3`.

---

## 18. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `MG-R1` | **Deleting a scorer's account breaks the sum invariant** — the surviving rows no longer total the recorded score — **and makes that result uncorrectable at its recorded score**, because the deleted scorer can no longer be named. Other players' figures stay correct | **Medium** | **Open**, §20 item 1. Same family as `MRS-R1`, `MR-R3` and `TA-R4` |
| `MG-R2` | **Own goals are unrecordable** without either rewarding the scorer, breaking the sum rule, or falsifying the attribution | Low — no approved requirement | **Open**, §14.1, `MG-D3`. Blocked on a Product Decision about the rating treatment |
| `MG-R3` | **A replaced lineup strands a goal row**: the scorer's goals were added but will not be subtracted on reversal, because the derivation no longer joins them | Medium | **Inherited from `RR-7`**, known, **not approved for work** |
| `MG-R4` | **`updated_at` treatment differs from `match_team_assignments`** under the same write model | Cosmetic | **Open**, `MG-D2`. Settle once for both |
| `MG-R5` | **`MG-X3` has no driving query**; its operative justification is the cascade, not the one recorded when it was created | Low | **Retain the index**, correct the justification (§9.2) |
| `MG-R6` | **No history of attributions.** A corrected result leaves no record of who was previously credited | Low | **Accepted** — the same boundary the parent records (`MRS-R4`) |
| `MG-R7` | **The name misleads.** `match_goals` holds tallies, not goals | Low | **Accepted**, and stated at §0 so the misreading is pre-empted |

---

## 19. Open Decisions

| ID | Question | Recommendation |
|---|---|---|
| `MG-D5` | **RESOLVED 2026-08-02.** Which derivation chain governs — approved context items 6 and 7, or `SL-2`/`SL-3`? | **Resolved in favour of `SL-2` and `SL-3`**, confirmed by the Player Statistics brief's items 3-6 and recorded in `Player_Statistics_Table_Specification.md` §17.1. Original reasoning: **`SL-2` and `SL-3`.** Both levels derive from results independently; neither feeds the other; ratings are not derived from counters. **If items 6 and 7 are intended as decisions rather than shorthand, they overturn `SL-2`, `SL-3` and `SL-5`, and `SL-4` becomes unimplementable** (§17.1) |
| `MG-D1` | **Do the eight `DP-n` readings in §13 match their approved definitions?** | **Confirm.** Six are stated readings. The same request as `BDC-D4` and `MRS-D4`; all three should be answered together |
| `MG-D2` | **`updated_at` on delete-and-insert tables — present or absent?** | **Absent**, as here. A column that can never differ from `created_at` is not an audit. If the Standards are read as requiring the pair regardless, then `match_team_assignments` is right and this table should match it — **either way, the two should agree** |
| `MG-D3` | **How should the rating engine treat an own goal?** | **Not an engineering decision.** Football convention credits the goal to the opposing side and does not credit the scorer; the approved engine awards **+0.05 to whoever is named**. Until this is settled, own goals cannot be recorded correctly (§14.1) |
| `MG-D4` | **Is per-goal identity — times, order, individual annotation — foreseeable?** | **Decide before it is needed.** It is the one future that redesigns the table rather than extending it (§14.4): the business key stops being unique and the tally column disappears. Cheap now, disruptive later |

---

## 20. Conformance

| # | Deviation | Required by | Severity | Notes for the implementing phase |
|---|---|---|---|---|
| 1 | **`user_id` cascades, breaking the sum invariant and stranding an uncorrectable result** | §5.5, `MG-C7` | **Medium** | Same family as `MRS-D1`. If account deletion is made to reverse affected results before removing the account, this closes with it — **the two should be settled together**, since a scorer and an MVP are the same deletion path |
| 2 | **`MG-X3`'s recorded justification is not its operative one** | §9.2 | Low | Documentary. Keep the index |

**Everything else conforms.** The structure, the business key, the foreign key
to the parent's alternate key, all four checks, the sole required index, the
select-only access model, the absence of any write path of its own, and the
delete-and-replace correction semantics are exactly as specified.

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched.

---

## 21. Engineering Approval

**Status: Engineering Approved — conditional.**

This document is the authoritative engineering specification for
`public.match_goals`. It is **conditional** on §20 item 1 — a Medium, and the
first table in the phase whose only conditional item is shared with a sibling
rather than its own.

**A note on the shape of the findings.** This is the **cleanest table in the
phase**: no ownership violation, no duplicate responsibility, no history
violation, no performance risk, no write path of its own to withdraw, and a
correct `updated_at` decision. Its two real issues are both about **what happens
when something else is deleted** — the same family that has now appeared on four
consecutive tables.

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5`, **with the misleading name pre-empted** | ✓ §0 |
| Business purpose, business owner, domain ownership, lifecycle ownership | ✓ §1, all four |
| **Complete lifecycle** — five valid transitions, ten invalid, **and why goals never mutate history directly** | ✓ §2 |
| **Business responsibilities** — owned and not owned, **including ordering shown to be unrepresentable** | ✓ §3 |
| **Goal model** — goals are evidence; statistics, ratings and leaderboards derived; **why goals are not statistics, answered structurally** | ✓ §4 |
| Relationships: incoming, outgoing, ownership, deletion, lifecycle | ✓ §5 |
| Every column — name, purpose, type, nullability, default, editability, justification | ✓ 5 of 5 |
| Every business constraint with its reason | ✓ 14, across three enforcement layers |
| Keys: primary, **business key**, candidate, alternate, foreign | ✓ §8 |
| Index strategy: one required, one unused-but-justified, three rejected | ✓ §9 |
| Access control: organizer, admin, member, player, non-member, System Administrator × read/insert/correct/delete | ✓ §10 |
| Audit: all four columns ruled on | ✓ §11 |
| Dependencies both directions | ✓ §12 |
| **Eight `DP-n` principles**, each validated, with the reading and basis marked | ✓ §13 |
| **Future compatibility**: own goals, assists, VAR, goal timestamps, goal types | ✓ §14, five of five — **one shown to be a redesign, not an extension** |
| **Engineering review** — ownership, duplication, history, consistency, performance | ✓ §16, six findings |
| Validation; contradictions named, not resolved | ✓ 13 sources, **1 contradiction named** |
| No SQL, no migration, no statistics, no ratings, no leaderboards, no other table designed | ✓ |

### Validation caveat, stated rather than glossed

The brief names *Database Principles* as a validation source. **It does not
exist as a document in this repository** — the tenth phase in which this has
been recorded. Six of the eight `DP-n` principles §13 validates against have no
definition here; §13 states the reading applied for each. `MG-D1` asks for
confirmation, together with `BDC-D4` and `MRS-D4`.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Match_Results_Table_Specification.md` | **Parent authority.** Its §8.4 records this foreign key from the other side; its `MRS-R3` and `MRS-R4` are inherited here |
| `engineering/Match_Team_Assignments_Table_Specification.md` | **The participant source** — validation and derivation both reach it. Its `updated_at` position differs (`MG-R4`) |
| `engineering/Matches_Table_Specification.md` | The aggregate root; the lock these writes occur under |
| `engineering/BTGE_Database_Contract.md` | §6.2 forbids BTGE writing this table; `BDC-D4` is `MG-D1` |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **`SL-2`, `SL-3`, `SL-5`, `A4`** — the authority for §17.1 |
| `engineering/Results_Rating_Engineering_Decisions.md` | `RR-1` (why DP-8 holds), `RR-4`, `RR-5`, `RR-7` (`MG-R3`) |
| `engineering/Profiles_Table_Specification.md` | `UP-4` (§11.2); the rating column the per-goal award moves |
| `Docs/06-ERD.md` | §2 — *"goals reference the result, not the match"* |
| `Docs/01-PRD.md` | *score, **goal scorers** and the MVP* — the tally model in the product's own words |
| `Docs/07-Database-Design.md` | *"written only by `record_match_result` and carry select policies and nothing else"* |
