# Player Statistics (`player_statistics`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One Medium-High access defect and one Medium recoverability gap; see §18 and §20 |
| Role | **Engineering Authority** for the physical table `public.player_statistics` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Statistics |
| Scope | **`public.player_statistics` only.** Community Statistics, `rating_history`, the Community Rating and leaderboards appear **only as dependent or sibling entities** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **This document is the authoritative specification for the physical table
> `public.player_statistics`.** Where an implementation and this document
> disagree, **the implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation**, and it designs no
> Community Statistics, no ratings and no leaderboards.
>
> **It does not redesign approved product behaviour.** All eleven approved
> context items are taken as given and confirmed throughout — and items 3–6
> **resolve the contradiction raised as `MG-D5`** in the previous phase
> (§17.1).
>
> **Sibling authorities.** The eight table specifications and
> `BTGE_Database_Contract.md` v1.0, listed in *Related documents*.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Global Statistics** — the player's career record |
| **Physical table** | **`player_statistics`** |

**Under `SL-2` this table is Level 1 — Global Statistics**, and the name
`player_statistics` predates that vocabulary. The two are the same thing, and
this document uses *career record* or *Level 1* where precision matters.

**The name understates one thing and overstates another:**

- It **understates** the scope: these are *career* counters spanning every
  community the player has ever played in, including ones they have left.
- It **overstates** the content: it holds six counters and **not the rating** —
  the other half of Level 1 lives on the profile (§4.3).

---

## 1. Purpose

### 1.1 Business purpose

A Player Statistics row is **one player's complete football career in this
application, expressed as six numbers**.

It exists because the question *"how have I played?"* must be answerable in one
row lookup, and the honest alternative is unaffordable: recomputing a career
would mean scanning every result the player ever appeared in, joined through
every lineup, on every profile open, forever.

**It is a cache with an exact reconstruction rule** — every increment is
matched by a reversal that subtracts precisely what was added — and §4.1
explains why that combination is what makes an accumulated counter safe here
where it would be dangerous elsewhere.

### 1.2 Business owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That the row exists** | **The system**, as a consequence of a first recorded result | The apply path's insert branch |
| **All six counters** | **The system, exclusively** | Apply and reverse, inside the recording operation |
| `user_id`, `created_at` | The database | Nothing writes them after insert |
| `updated_at` | The database | Trigger |

**No person owns any value in this table.** Not the player it describes, not
the organiser whose result moved it, not an administrator. Every number is a
consequence, and §5.4 states why that has to be absolute.

### 1.3 Domain ownership

**Domain: Player Identity — not the Match domain.**

| Property | Value |
|---|---|
| Aggregate | **None.** It sits beside `users`, outside the Community and Match aggregates |
| Depends on | `users` structurally; `match_results`, `match_goals` and `match_team_assignments` semantically (§12.1) |
| Depended on by | **Nothing** |
| Community-scoped | **No, and must never be** (§4.5) |
| Contains authorization | **No** |

**This is the first table in the phase whose domain is not the Match domain**,
and the placement is the point: a career belongs to the *person*, spans every
community, and outlives every match that contributed to it. `RR-6` states it —
*"it is a property of a player, not of a membership"* — and `SL-2` §2.1 makes it
normative: Global Statistics *"carry **no** community dimension."*

### 1.4 Lifecycle ownership

| Bounded by | Consequence |
|---|---|
| **The player's account** | Absolutely. Cascades with it, and the row is meaningless without the person |
| **Not any match** | A career outlives every match in it. Deleting a match *reduces* the counters; it does not delete the row |
| **Not any community** | A career spans communities including ones the player has left (`RR-6`, `SL-4`) |
| **Not the clock** | Never reset, never rolled over, never archived. **There is no season** |
| **Not its own** | It has no lifecycle of its own — every state change is a consequence of a result being recorded, corrected or removed |

---

## 2. Lifecycle

### 2.1 The states

```
   PLAYER CREATED
        │
        │   ← the profile row exists; there is NO statistics row
        ▼
   NO ROW            ← "absence is the starting point, not a missing record"
        │
        │  their first result is recorded
        ▼
   ROW CREATED       ← inserted with that match's contribution, not with zeros
        │
        ├── another result recorded  ──▶ counters increase
        ├── a result corrected       ──▶ reversed, then re-applied
        ├── a match deleted          ──▶ counters decrease
        │
        ▼
   ROW OF ZEROS      ← reachable, and NOT deleted (§2.4)
        │
        ▼
   GONE              ← only when the account is deleted
```

### 2.2 Every valid transition

| # | From | To | Trigger | Notes |
|---|---|---|---|---|
| 1 | No row | Row exists | **The player's first recorded result** | Created carrying that match's contribution. **Never created empty and never created in advance** |
| 2 | Row exists | Counters higher | A further result recorded | Upsert: insert if absent, add if present |
| 3 | Row exists | Counters adjusted | **A result corrected** | Reversed in full, then the new contribution applied — two statements, one transaction |
| 4 | Row exists | Counters lower | **A match deleted** | The reversal trigger runs before the cascade, so the match un-counts itself |
| 5 | Row exists | Row of zeros | Every contributing result reversed | **The row remains** — §2.4 |
| 6 | Any | Gone | **The account is deleted** | Cascade. The only deletion path |

**Note what is absent: there is no transition into this table that a person
performs.** Every one is a consequence of an event in the Match domain.

### 2.3 Invalid transitions, and what refuses each

| Invalid | Why | Refused by |
|---|---|---|
| A row created before a first result | The row would assert *this player has a career of zeros*, which is a different claim from *this player has not played* | Nothing creates one; the insert branch runs only over a match's contribution |
| Two rows for one player | The career would have two answers | **The primary key** — `user_id` (§8.1) |
| A negative counter | A career total below zero is meaningless, and it is the signature of a reversal bug | The non-negative checks (`PS-C3`) — §5.3 |
| **A manual edit** | Would set a number that no result produced, unreversibly | **No write policy exists** (§10.3) |
| **Reversal creating a row** | *"There is nothing to subtract from a player who was never added"* | The reverse path is an update, never an upsert (`PS-C6`) |
| A counter changed without a result changing | Every value is a consequence; there is no other cause | No operation exists |
| A community-scoped counter here | Level 1 has no community dimension | No such column, and §4.5 forbids one |

### 2.4 A row of zeros is not the same as no row — and neither is deleted

**Both states exist and they mean different things:**

| State | Meaning |
|---|---|
| **No row** | This player has never had a result recorded. *"Absence is the starting point, not a missing record."* The reading layer treats it as a career of zeros for display |
| **A row of all zeros** | This player *did* have results, and every one of them has since been reversed or deleted |

**The row is not deleted when it reaches zero**, and that is correct: deleting
it would discard the distinction, and re-creating it on the next result would be
indistinguishable from a first-ever career. **Nothing depends on the
distinction today** — the reading layer renders both as zeros — but destroying
information that costs nothing to keep would be the wrong trade.

**The display consequence is deliberate:** a player who has never played and a
player whose only match was deleted both show a career of zeros. That is
accurate in both cases.

### 2.5 Why statistics are rebuilt from result changes rather than edited

**The brief asks this directly, and the answer has three parts.**

**1. Because an edited counter is unreversible.** Every value here is the sum
of contributions, and every contribution can be taken back by exactly what it
added. A number somebody typed has no contribution behind it, so no correction
can remove it — it becomes permanent, undetectable and unattributable.

**2. Because the reversal must be exact, and only the source can make it so.**
Correction reverses using `match_result_contribution` — a single helper that
recomputes what a result was worth to each player, read by *both* the apply and
the reverse paths. **Neither direction restates a rule the other holds**, so the
amount subtracted is by construction the amount that was added. An edit sits
outside that guarantee.

**3. Because `RR-4` proved the cost of getting this wrong.** The original
implementation treated applying and reversing as one statement with a sign
flag. Every correction and every deletion of a match with a result was refused,
silently, and the wreckage was 100 leftover communities and four accounts driven
to the ends of the rating range. **The fix was recovery *through the corrected
code path*** — deleting the contaminated communities so the reversal fired 100
times — which returned every account to exactly its baseline, **including two
that had been clamped at the ceiling**.

> **That recovery is only possible because the counters are derived. A hand-
> edited counter could not have been recovered at all.**

**And it exposes the gap:** recovery worked because the *results still
existed*. Where a result is gone, reversal is impossible and only a rebuild
would help — **and no rebuild operation exists** (§16.5, `PS-R2`).

---

## 3. Business Responsibilities

### 3.1 What this table owns

| # | Responsibility | Column |
|---|---|---|
| 1 | **Matches Played** — appearances in matches whose result was recorded | `matches_played` |
| 2 | **Wins** — results that favoured the player's side | `wins` |
| 3 | **Draws** — results that ended level | `draws` |
| 4 | **Losses** — results that went against the player's side | `losses` |
| 5 | **Goals** — goals credited to the player | `goals` |
| 6 | **MVP Count** — times named best player | `mvp_count` |
| 7 | **One career record per player, and only one** | The primary key |

**All six are career-wide**: across every community, including ones the player
has left (`RR-6`, `SL-4`, `SL-2` §6).

### 3.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **The Global Rating** | `users.overall_rating` | §4.3. *"A copy beside the counters would be a second number for the same thing, free to disagree with it"* |
| 2 | **Any history** | `rating_history` | §4.2. A counter says *how many*, never *which* or *when* |
| 3 | **Community Statistics** | A separate Level 2 entity | §4.5. **Approved context items 5 and 6, and DP-10** |
| 4 | **The Community Rating** | A separate Level 2 entity | Same |
| 5 | **Any leaderboard** | Derived from Level 2 | §4.4. `SL-2` §2.3 forbids a board reading this table, in any period |
| 6 | **The evidence** | `match_results`, `match_goals`, `match_team_assignments` | These are the figures; those are the facts |
| 7 | **Which matches contributed** | Nowhere derivable from here | §4.2 — the counters have no per-match granularity and cannot regain it |
| 8 | **Any period or season** | Nowhere. Level 2 carries the time dimension | §4.5. `SL-1`: a period is a property of a Level 2 record |

---

## 4. The Statistics Model

### 4.1 Why statistics are accumulated counters

**Because the alternative is unaffordable and the accumulation is safe.**

| | Recompute on read | Accumulate (chosen) |
|---|---|---|
| Cost of reading a career | Scan every result the player appeared in, joined through every lineup | **One row lookup by primary key** |
| Cost of recording a result | Nothing | One upsert over the match's participants |
| Risk | None | **A cache that can drift from its source** |

**What makes the accumulation safe is the exactness of the reversal** (§2.5):
one shared helper computes each player's contribution, both directions read it,
and the non-negative checks catch an over-subtraction rather than storing it.

**Where the safety ends is where the source disappears** — §16.5.

### 4.2 Why statistics are not history

**A counter says *how many*. History says *which*, *when* and *by how much*.**

| Question | This table | `rating_history` |
|---|---|---|
| How many goals has this player scored? | **Yes**, in one lookup | Not directly |
| Which matches did they score in? | **No, and unrecoverably** | — |
| What was the effect of this particular match? | **No** | **Yes** — before, after, applied delta, reason, match |
| Can an entry be undone exactly? | Only by re-deriving from the source | **Yes**, from the row itself |

**The row is overwritten, never appended to.** After a correction the counters
show the new total and no trace of the old — which is correct for a total and
would be wrong for an audit. **That is why the audit is a different table**, and
why `RR-5` made it append-only with a reversal as a new row.

### 4.3 Why statistics are not ratings

**They are different kinds of number, and `SL-5` says so:** a rating is a
**running value** with no natural zero that does not restart; a counter is an
**accumulation** that begins at zero and only moves by what happened.

| | The six counters | The Global Rating |
|---|---|---|
| Starts at | **Zero** | **`5.00`** — the neutral midpoint |
| Moves by | What the result contained | An engine's deltas, **clamped** at the ends of the range |
| Reversible from itself? | No — from the source | **No — from the audit**, because clamping makes the applied delta differ from the nominal one |
| Stored where | Here | **`users.overall_rating`** |

**Why the rating is deliberately not stored here** (`RR-6`): *"a copy beside the
counters would be a second number for the same thing, free to disagree with
it."* The reading layer joins them — the profile query reads the user row and
embeds the counters — which is the same pattern that keeps out-of-position
derived rather than stored.

**Both are Level 1**, and being in two tables is not a split of the concept: it
is two kinds of number kept where each belongs.

### 4.4 Why statistics are not leaderboards

**`SL-2` §2.3 is normative and unqualified:** *"All Community Leaderboards MUST
use Community Statistics. They must never read Global Statistics — for any
board, in any period."*

`RR-6` states the same from this side: *"These counters are read by the **Player
Profile** and by nothing else. No leaderboard reads them, in any period."*

**The reason is not privacy but meaning.** A board ranks people against the
players they actually play with. A board fed from career totals would rank a
community by achievements earned elsewhere — and a player who dominated a
casual community would outrank someone holding their own in a strong one.

### 4.5 Why statistics never become the source for Community Statistics

**Approved context items 5 and 6, and DP-10 — and this is the section that
resolves `MG-D5`.**

**Both levels derive from the same evidence, independently and in parallel.
Neither feeds the other.**

```
   Match Result  +  Match Goals  +  Match Team Assignments
            │
   ┌────────┴─────────┐
   ▼                  ▼
 LEVEL 1           LEVEL 2                ← same source, separate derivations
 (this table)      (community counters)
                      └──▶ Leaderboards
```

**Four reasons this must hold, and the second is decisive:**

1. **This table has no community dimension to give.** A Level 2 record needs
   `(player, community, period)`; these counters carry only *player*. There is
   nothing here to partition by, so deriving Level 2 from Level 1 is not merely
   discouraged — **it is impossible**.
2. **`SL-4` would become unimplementable.** A community record must survive a
   departure and be found again on return. If it were computed from Level 1, it
   would have no community identity to survive *in*.
3. **`SL-2` says they are not two views of one record**, and that they agree
   *by construction* — because both count the same recorded results, **not
   because one is computed from the other**.
4. **A drift in one must not propagate.** Two independent derivations from one
   source can be compared and reconciled. A chain cannot: an error at Level 1
   would silently become an error at Level 2, at every period, in every
   community.

> **DP-10 conformance, stated once: this table is a *sibling* of Community
> Statistics, never its parent.**

---

## 5. Business Constraints

### 5.1 Enforced by the schema

| ID | Rule | Why it exists |
|---|---|---|
| `PS-C1` | **`user_id` is the primary key and references `users(id)`, cascading** | One career per player, structurally (§8.1). Cascading because a career without a person is not a fact, and a stale row would report a career for an id that no longer exists |
| `PS-C2` | **All six counters are NOT NULL with a default of zero** | A career total is never *unknown*. The default is what lets the insert branch supply only the contributing values |
| `PS-C3` | **All six counters are non-negative** | A career total below zero is meaningless — **and it is the signature of a reversal bug.** §5.3 |
| `PS-C4` | **`created_at` and `updated_at` are NOT NULL, and `updated_at` is trigger-maintained** | §11 |
| `PS-C5` | **No client may insert, update or delete** | There are **no write policies of any kind**. A written counter has no contribution behind it and can never be reversed (§2.5) |

### 5.2 Enforced by the write path

| ID | Rule | Why it exists |
|---|---|---|
| `PS-C6` | **Applying is an upsert; reversing is an update.** Reversal never creates a row | *"Applying may have to create a counters row — a player finishing their first match has none. Reversing never does: there is nothing to subtract from a player who was never added"* (`RR-4`) |
| `PS-C7` | **Both directions read one shared contribution helper** | Neither restates a rule the other holds, so the amount subtracted is by construction the amount added |
| `PS-C8` | **Apply and reverse are separate statements, never one statement with a sign** | `RR-4`. §5.3 explains why the alternative is not merely inelegant but refused by the database |
| `PS-C9` | **Every change happens inside the recording operation's transaction**, under the match row lock | A counter moved outside the transaction that moved the result would be a figure with no cause |
| `PS-C10` | **A counter changes only as a consequence of a result being recorded, corrected or removed** | There is no other cause, and no operation offers one |
| `PS-C11` | **Only participants receive counters** | The contribution is driven by the lineup (approved context item 4). A non-participant is not joined and receives nothing |

### 5.3 `PS-C3` is not decoration — it is the constraint that found `RR-4`

**The non-negative checks caused the phase's one production defect, and keeping
them is the right conclusion.**

The original implementation reversed by proposing a row of negative values and
relying on `ON CONFLICT DO UPDATE` to subtract them. **PostgreSQL validates the
proposed tuple before performing the speculative insertion that detects the
conflict**, so `matches_played = -1` was checked against `>= 0` and the statement
aborted — every correction and every deletion of a match with a result, refused.

**Three lessons this table's specification carries forward:**

1. **The mental model that fails is "the `DO UPDATE` branch is chosen first."**
   It is not. The proposed row must be independently valid, whichever branch
   runs.
2. **The constraint was right and the statement was wrong.** A negative career
   total is meaningless; the fix was to stop proposing one.
3. **The checks are now the last line of defence against a reversal bug.** An
   over-subtraction raises rather than storing a nonsense career — which is
   exactly what a constraint on a cache should do.

### 5.4 No manual editing — why the prohibition is absolute

The brief lists *no manual editing* as a rule. **It is stronger than a rule
here: there is no mechanism.**

| | |
|---|---|
| No write policy | A client cannot write, by any route |
| No administrative operation | Not even a System Admin has one |
| No repair operation | And this is a gap, not a virtue — §16.5 |

**Why not even an administrator.** A hand-set counter is a number with no
contribution behind it. The next correction of any match the player appeared in
would reverse *its* contribution correctly and leave the hand-set portion
untouched — permanently, undetectably, and with no record of who set it or why.
**The counters would stop being derived, and the exactness that makes correction
possible would be gone.**

### 5.5 Deliberately **not** constrained

| Not constrained | Why not |
|---|---|
| **`wins + draws + losses = matches_played`** | **True by construction and deliberately unenforced.** Every contribution supplies exactly one of the three plus one appearance. A constraint would add nothing the derivation does not already guarantee — and would convert a reversal bug into a refusal at a point too late to diagnose, where `PS-C3` already catches it earlier and more precisely |
| `goals` bounded by anything | A prolific career has no ceiling |
| `mvp_count <= matches_played` | True by construction, same reasoning |
| A minimum before the row exists | The row appears with the first result, carrying it |
| Any per-community or per-period breakdown | §4.5 — Level 1 has no such dimension |

---

## 6. Relationships

### 6.1 Incoming

**None. Nothing references a statistics row**, and nothing should: the row is
identified by the player, so any consumer that needs it already holds the
player's id.

### 6.2 Outgoing

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `users` | `user_id` — **which is also the primary key** | **1 : 1** *(0..1 from the user's side)* | **`CASCADE`** | **Identifying** |

**One foreign key, and it is the primary key.** §8.1.

**No foreign key to the evidence**, and none is possible: the counters are an
aggregate over many results across many matches, and there is nothing single to
point at. §12.2 states what that costs.

### 6.3 Ownership

| Question | Answer |
|---|---|
| **Who owns the relationship's meaning?** | The **player**. The row is their career and has no meaning apart from them |
| **Can it be reparented?** | **No.** `user_id` is the primary key; nothing writes it |
| **Does the user row know it has statistics?** | **No flag**, deliberately. Its existence is the answer, and the profile query embeds it |
| **Does this row know which results built it?** | **No** (§4.2), and it cannot regain the knowledge |

### 6.4 Deletion behaviour

| Path | Behaviour | Assessment |
|---|---|---|
| **The account is deleted** | Cascade. The career goes with the person | **Correct** |
| **A match is deleted** | The reversal runs first; the counters **decrease**. The row survives | **Correct** — §2.4 |
| **A result is corrected** | Reversed and re-applied | **Correct** |
| **Directly** | **No path exists** | **Correct** |

**Three inherited cases where the counters are left wrong**, each belonging to
another table and each recorded here because this is where the damage lands:

| Case | Effect on this table | Source |
|---|---|---|
| The **MVP's account** is deleted | The result vanishes with no reversal; **every other participant keeps counters for a result that no longer exists** | `MRS-R1` |
| A **scorer's account** is deleted | Their goal rows vanish; a later correction of that result reverses fewer goals than were added | `MG-R1` |
| A **lineup is replaced** after recording | A removed player's contribution is no longer joined, so their counters are never reversed | `RR-7` |

**All three produce the same outcome here — a career total that no operation
can correct** — and none of them is this table's to fix. §16.5 is the finding
that follows.

### 6.5 Lifecycle

| Relationship | Whose lifetime bounds whose |
|---|---|
| `users` → this row | **Absolutely** |
| Matches, results, goals → this row | **None.** They move it and do not bound it. A career outlives every match in it |
| Communities → this row | **None**, and this is the whole of `RR-6` |
| This row → anything | **It bounds nothing** |

---

## 7. Columns

Nine columns.

### 7.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `user_id` | `uuid` | No | none | **Never** |
| 2 | `matches_played` | `int` | No | `0` | **System only** |
| 3 | `wins` | `int` | No | `0` | **System only** |
| 4 | `losses` | `int` | No | `0` | **System only** |
| 5 | `draws` | `int` | No | `0` | **System only** |
| 6 | `goals` | `int` | No | `0` | **System only** |
| 7 | `mvp_count` | `int` | No | `0` | **System only** |
| 8 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| 9 | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** |

**"System only" here means something stronger than on any other table**: not
merely *no client may write it*, but **no actor of any kind sets a value** —
every number is arrived at by adding or subtracting a contribution the source
data determines (§5.4).

### 7.2 Column detail

---

**1. `user_id` — `uuid`, NOT NULL, no default, never editable, primary key**

*Purpose.* Whose career this is.

*Business justification.* It is the player's identity, which is also their
authentication identity — so *"my career"* is a primary-key lookup with no join
and no subquery.

***It is simultaneously the primary key and the only foreign key***, which
makes the 1 : 1 relationship structural: there is no shape in which a player has
two career records, and none in which a career record exists without a player.
**§8.1 records this as the strongest key design in the schema.**

---

**2. `matches_played` — `int`, NOT NULL, default `0`, non-negative**

*Purpose.* How many matches the player has appeared in.

*Business justification.* It is the denominator of everything a player might
compute — a win rate, goals per game — and the only counter that increments for
**every** participant of **every** recorded result.

**"Appeared in" means "was in the stored lineup of a match whose result was
recorded."** Three exclusions follow, and all are correct:

| Not counted | Why |
|---|---|
| A match played but never recorded | `A4`: statistics arise **only** from a recorded result |
| A match the player registered for but was not in the lineup | Participation is the lineup's (approved context item 3) |
| A reserve who was never promoted | Same — they held a queue place, not a seat |

---

**3–5. `wins`, `losses`, `draws` — `int`, NOT NULL, default `0`, non-negative**

*Purpose.* How the matches the player appeared in turned out for their side.

*Business justification.* Each is derived from the result's two scores compared
against **the player's team in the stored lineup** — which is why a result
cannot be recorded without a lineup, and why these three counters are the
clearest expression of why participation must be a separate record.

*Three columns rather than one signed outcome*, because a career shows all
three and each is asked for independently. **Their sum equals
`matches_played`** by construction (§5.5).

*A draw counts for both sides.* The contribution marks a draw when the scores
are equal, for every participant.

---

**6. `goals` — `int`, NOT NULL, default `0`, non-negative**

*Purpose.* Goals credited to the player across their career.

*Business justification.* It is the counter with the most visible product
meaning and the one most likely to be disputed, which is why its evidence is a
separate table with its own sum rule tying it to the score.

**Absence of a goal record contributes zero**, by a left join — so a
participant who did not score is counted as playing and scoring nothing, in one
pass.

---

**7. `mvp_count` — `int`, NOT NULL, default `0`, non-negative**

*Purpose.* Times the player was named best player.

*Business justification.* Exactly one participant per recorded result
increments it, guaranteed by the result's shape — a NOT NULL column on a row
unique per match. **So the sum of every player's `mvp_count` equals the number
of recorded results**, which is a property no other counter has and a useful
reconciliation check if one is ever wanted (§16.5).

---

**8. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When this career record began — **the moment the player's first
result was recorded.**

*Business justification.* It survives every correction, because corrections
update the row rather than replacing it. So it genuinely answers *when did this
player's recorded career start*, which is more meaningful here than on most
tables and is not derivable from anything else — the matches that produced it
may since have been deleted.

---

**9. `updated_at` — `timestamptz`, NOT NULL, default `now()`, trigger only**

*Purpose.* When the counters last moved.

*Business justification.* It is the only signal that a career changed without a
new match — a correction, or a deletion elsewhere. Trigger-maintained because
the writers are two statements inside a function, and a timestamp each must
remember is one that will be forgotten.

**This table has both audit timestamps and uses both**, unlike the two tables in
this phase where the pair is incomplete or vestigial.

---

## 8. Keys

### 8.1 Primary key — and the best key design in the schema

**`user_id`** — the player's identity, serving simultaneously as:

| Role | Consequence |
|---|---|
| **Primary key** | One career per player, structurally |
| **The only foreign key** | No career without a player, structurally |
| **The business key** | The domain's own name for the row (§8.2) |
| **The authentication identity** | *"My career"* is a column comparison |

**There is no surrogate `id`, and this is the point.** Every other table in this
phase carries one, and in four of them this specification records that it has no
consumer. **Here the natural key was used, and the result is a table with no
unused column and no second way to name a row.**

**It is the design the Community Members specification recommended for itself
and declined to change** (`CMB-D1`), on the ground that changing a primary key
on a live table is not worth it. **This table is what that recommendation looks
like when taken at the start.**

### 8.2 Business key

**`user_id`** — the same column. The business key *is* the primary key.

### 8.3 Candidate keys

**One: `user_id`.** No other column or combination is unique — six counters can
repeat across players freely, and two players with identical careers are
ordinary.

### 8.4 Alternate keys

**None**, and none is possible. There is exactly one candidate key and it is the
primary key.

### 8.5 Foreign keys

**Outgoing — one, which is also the primary key:**

| Column | References | On delete | On update |
|---|---|---|---|
| `user_id` | `users(id)` | **`CASCADE`** | *no action* |

**Incoming — none, and none needed** (§6.1).

**No foreign key to the evidence**, and none possible (§6.2).

---

## 9. Index Strategy

### 9.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `PS-X1` | **Primary key on `user_id`** (implicit, unique) | **Everything.** (a) the profile read, which fetches one career by player; (b) the apply path's conflict target on every recorded result; (c) the reverse path's join to the contribution, per participant; (d) enforcement of one-career-per-player; (e) the referential-integrity check and the cascade from `users` |

**`PS-X1` is the only index this table requires, and it is free** — it is the
primary key. **This is the only table in the phase whose entire index strategy
is its primary key**, and that is a direct consequence of §8.1: a table keyed by
the thing every query already holds needs nothing else.

### 9.2 Considered and **not** required

| Candidate | Verdict | Reasoning |
|---|---|---|
| `(goals DESC)`, `(mvp_count DESC)`, `(wins DESC)` | **No — and this is a design statement** | The instinct is that a "top scorer" board needs one. **It does not.** `SL-2` §2.3 forbids any leaderboard reading this table, in any period, and `RR-6` confirms the counters are read by the Player Profile and nothing else. **An index here would serve a query that must not exist** |
| `(matches_played)` | **No** | Nothing filters or sorts by it. A "most active player" figure is a Community Dashboard measure, computed at Level 2 |
| `(updated_at)` | **No** | Nothing lists recently-changed careers |
| Any composite | **No** | There is no multi-column predicate anywhere against this table |

### 9.3 The rule for a future designer

> **An index on `player_statistics` other than its primary key is evidence that
> something is ranking careers — which `SL-2` §2.3 forbids.** The fix is the
> query, and its answer is at Level 2.

---

## 10. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 10.1 The matrix — as specified

| Actor | Read | Write | Recalculate | Delete |
|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ |
| **Player — their own career** | ✓ **Always** | ✗ | ✗ | ✗ |
| **Community Member** | ✓ **Careers of people they share a community with** | ✗ | ✗ | ✗ |
| **Non-member** | ✗ **Nothing** | ✗ | ✗ | ✗ |
| **Organizer** *(as such)* | ✓ as a member — **not a role** | ✗ | ✗ | ✗ |
| **Community Admin** | ✓ as a member. **Admin grants nothing here** | ✗ | ✗ | ✗ |
| **System Administrator** | ✗ No direct path | ✗ | ✗ | ✓ Transitively, by deleting the account |
| **The system** | — | ✓ **Only actor** | ✗ **No such operation exists** | ✓ |

**Two rows deserve emphasis:**

- **A community role grants nothing on this table.** An admin sees a member's
  career because they share a community, not because they are an admin. **This
  is the only table in the Match/Community estate where authority is irrelevant**
  — which is right, because a career is not a community's business.
- **"Recalculate" has no actor because no such operation exists** — §16.5,
  `PS-R2`.

### 10.2 Read — the specification, and the deviation

**The rule specified above scopes reads to self and to shared communities**,
matching `UP-1` tier 2 for profiles.

**The schema as built does not do this.** The read policy grants **every
authenticated user unconditional read of every row** — no membership predicate,
no self predicate, no scoping of any kind.

**Why that matters, precisely:**

| Consequence | |
|---|---|
| **Enumeration** | A direct query returns **every `user_id` that has ever had a result recorded**, with their complete career. `UP-1` states that *"enumeration of all users is NOT permitted"* — this table permits it for every player who has played |
| **It partially defeats `UP-1`** | `UP-1` is closing the equivalent hole on `users`. Leaving this one open preserves the ability to enumerate a large subset of the same population, with career detail attached |
| **It is a second broadly-readable table** | `SUPABASE_OPERATIONAL_GUIDELINES.md` §4: *"Today exactly one table is broadly readable by design — `communities`… Any new one needs the same [explicit Product Owner approval]."* **No such approval is recorded for this table** |

**Note the application does not rely on it.** The profile read is driven from
`users` and embeds the counters, so it is already scoped by whatever governs
profile reads. **Narrowing this policy costs the application nothing** — which
is the same finding shape as `MT-R1` and `TA-R3`: a permission with no consumer.

**Recorded as `PS-R1`, Medium-High**, §20 item 1. **It should be closed together
with `UP-1`**, since one without the other leaves the population enumerable.

### 10.3 Write, Recalculate, Delete

**There are no write policies of any kind**, and there is no write operation
that a person invokes. Every change is a consequence of the recording operation
(§5.4).

**Delete has no path except the account cascade.** Not for an administrator,
not for the player. A career is not deletable while its owner exists.

**Recalculate does not exist** — §16.5.

---

## 11. Audit

| Column | Required? | State | Verdict |
|---|---|---|---|
| `created_at` | **Required** | Present | When the recorded career began — not derivable elsewhere (§7.2 column 8) |
| `updated_at` | **Required** | Present | The only signal a career moved without a new match |
| `created_by` | **Not required** | Absent | §11.1 |
| `updated_by` | **Not required** | Absent | §11.1 |

### 11.1 Neither actor column is required, and the reason is unique to this table

On every other table the question is *which of several entitled people did
this*. **Here there is no actor at all.**

**Every write is a consequence, never an act.** A counter moves because a result
was recorded, corrected or removed — and:

- **The person who caused it did not touch this table.** They recorded a result;
  the counters followed.
- **They did not decide the value.** The contribution helper did, from the
  evidence.
- **Naming them would be misleading**, in the same way the registrations
  specification records for automatic promotion: it would name someone who made
  a different decision, on a row that is not theirs.

**The actor for the *cause* is recorded where the cause is** —
`match_results.recorded_by` — and the *effect* is recorded in `rating_history`
for ratings. **This table records neither, because it is the residue of both.**

`UP-4` independently refuses `updated_by` as a mutable last-writer column; here
the prior objection is that there is no writer to record.

### 11.2 What the audit does not cover

**No history of the counters, and no per-match granularity** (§4.2). The row
shows the current totals and nothing about how they were reached. Reconstructing
*which* matches contributed is impossible from this table and would require
re-deriving from the evidence — **which is exactly the operation that does not
exist** (§16.5).

---

## 12. Dependencies

### 12.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `users` | **Identifying parent, and the primary key**, cascading | Owns the person, and — separately — owns the **other half of Level 1**, the Global Rating |
| `match_results` | **Not a foreign key — a derivation source** | Supplies the scores from which win/loss/draw and the MVP are determined |
| `match_goals` | **Not a foreign key — a derivation source** | Supplies the goal tallies |
| `match_team_assignments` | **Not a foreign key — the derivation driver** | **Drives the contribution**: one row per participant, and the side each was on. Approved context items 3 and 4 |
| `matches` | Transitive | Supplies the row locked while the counters move |

### 12.2 The unrepresented dependencies, and what they cost

**Three tables determine every value here and none is referenced.**

**This is unavoidable** — a counter is an aggregate over many rows across many
matches, and an aggregate has nothing single to point at — but the cost is
concrete and belongs in this specification rather than being discovered later:

| Cost | |
|---|---|
| **No cascade can keep the counters honest** | The three inherited cases in §6.4 all arise here |
| **No constraint can express consistency with the source** | *"Consistency with Match Goals"* and *"consistency with Match Results"* — both listed in the brief — **can only be maintained procedurally**, and only while the source survives |
| **No database mechanism can detect drift** | Which is why §16.5 asks for a reconciliation and a rebuild rather than a constraint |

### 12.3 Tables depending on this table

**None by foreign key.** By behaviour, **one reader**: the Player Profile.

**And two explicit non-dependents**, both worth stating because the instinct is
otherwise:

- **Community Statistics do not depend on this table** (§4.5, DP-10).
- **No leaderboard depends on it** (§4.4, `SL-2` §2.3).

---

## 13. Engineering Principles

The brief names nine, and two points of drafting are recorded rather than
assumed:

- **`DP-8` is named *Historical Record Protection Principle* here**, and was
  named *Historical Independence Principle* in the previous phase's brief. The
  reading applied below covers both formulations; **if they are distinct
  principles, this section addresses the one stated here** (`PS-D3`).
- **`DP-9` is not in the list.** Not treated as an omission — simply not
  addressed.

**Seven of the nine have no textual definition in this repository** — the
eleventh phase in which the absent *Database Principles* document has been
recorded. The reading applied is stated for each. **If a reading differs from
the approved definition, this section is the defect** (`PS-D1`).

### DP-1 Match Aggregate Root Principle — **conforms, from outside**

This table is **not in the Match aggregate** (§1.3), and conformance is
therefore about respecting a boundary rather than sitting inside one: every
change to it originates from a match, takes a match id, and happens under the
match's authority and its lock. **It never reaches into a match**, and no query
here traverses to one.

### DP-2 Match Row Lock Principle — **conforms, inherited**

Counters move inside the recording operation, which locks the match row before
anything else. **Without it, two simultaneous corrections of the same match
could each reverse the other's contribution** — and the non-negative checks
would catch some of that and not all.

### DP-3 Business Transition Principle — **conforms absolutely**

*Reading: a state change happens only through the business operation that owns
it.*

**There is no route to this table other than the recording operation, and this
table has no operation of its own.** No policy admits a write, no administrative
function exists, and no repair path exists — the last of which is a gap (§16.5)
but not a conformance failure.

### DP-4 Historical Identity Principle — **conforms**

*Reading: a historical record states what happened, identified by the entities
that took part, never by the process that produced it.*

**These counters are not a historical record and the specification says so**
(§4.2). They are a current total, overwritten as the source changes. The
historical record is `rating_history`, which this table neither writes nor
reads. **Nothing about the process is stored here**: no actor, no correction
count, no source list.

### DP-5 Final Participation Principle — **conforms, and depends on it entirely**

*Reading: participation is defined by exactly one record — the final
assignments — and every consumer resolves it there.*

**`matches_played` is literally a count of lineup rows.** Every counter here is
driven by the lineup, per participant, and a player absent from it receives
nothing — even if they registered, even if they scored a goal that was somehow
recorded (§4.5 of the goals specification).

**This is the table where the principle is most load-bearing**: get
participation wrong and every career figure in the product is wrong.

### DP-6 Single Business Path Principle — **conforms**

*Reading: one business outcome has one code path.*

**Applying and reversing are two statements, but one path and one arithmetic.**
The shared contribution helper is what makes them one outcome expressed twice
rather than two implementations — *"neither path restates a rule the other
holds"* (`RR-4`).

**The two-statement split is not a violation of this principle but a
requirement of `PS-C6`**: applying may create a row, reversing must not.

### DP-7 Producer / Commit Separation Principle — **conforms, by not applying**

*Reading: where a component computes a candidate a human may accept or reject,
computation and commitment must be separate.*

**Nothing here is a candidate.** The counters are entailed by the result, not
proposed for approval — and separation would produce exactly the state §2.5
forbids: a recorded result whose statistics had not been applied.

**The principle governs BTGE, whose output is a proposal. It correctly does not
govern a consequence.**

### DP-8 Historical Record Protection Principle — **conforms**

*Reading applied: the historical record is protected from, and independent of,
the derived data around it — its validity never depends on the current state of
what produced it.*

**This table cannot damage the historical record, and does not depend on it.**

| | |
|---|---|
| Does this table write history? | **No.** `rating_history` is written by the rating path, not the statistics path |
| Could a defect here corrupt history? | **No.** The two are computed from the same source independently, and the audit stores the *applied* delta, needing nothing from here |
| Could history be used to repair this table? | **Partially — and this is the useful observation.** `rating_history` names the match behind every change, so it retains a per-match trace that these counters do not. §16.5 records it as a possible basis for reconciliation |

### DP-10 Independent Derivation Principle — **conforms, and §4.5 is the whole argument**

*Reading (approved, context item 11): each derived record is computed from the
shared source independently; derived records never feed one another.*

- **This table derives from results, goals and the lineup** — the source.
- **It never reads Community Statistics**, and never could: it has no community
  dimension.
- **Community Statistics never read it**, and could not usefully: there is
  nothing here to partition by (§4.5 reason 1).
- **Neither is a view of the other**, and both counting the same recorded
  results is what makes them agree — `SL-2` §2.5's *"by construction"*.

**Conformance statement: `player_statistics` is a sibling of Community
Statistics, never its parent, and the impossibility of the alternative is
structural rather than a matter of discipline.**

---

## 14. Future Compatibility

**Every candidate in the brief is an additive counter column**, and the analysis
below is the same shape for each — which is itself the finding: **this table
extends by columns, and the hard part is never the column.**

### 14.1 The three things every new counter needs

| # | Requirement | Why |
|---|---|---|
| 1 | **An evidence source** | A counter with no evidence cannot be reversed, which breaks §2.5 |
| 2 | **A term in the contribution helper** | Both directions read it; adding a counter anywhere else would let apply and reverse drift |
| 3 | **A Product Decision on rating treatment** | Whether the new fact moves the rating is not an engineering question |

### 14.2 The backfill problem — the finding that applies to all five

**A new counter column defaults to zero for every existing row, and zero is an
assertion.**

> A career row showing `assists = 0` says *this player has never assisted a
> goal*. For a player whose matches predate assist recording, that is **false** —
> the truth is *we did not record assists then*.

**This is `UP-2`'s principle** — the database must never invent what it does not
know — applied to a column rather than a row, and it is the one genuinely
awkward thing about extending this table.

**Three options, and the recommendation:**

| Option | Assessment |
|---|---|
| Default zero, and accept the falsehood | **Silently wrong**, and permanently indistinguishable from a real zero |
| **Nullable, meaning "not recorded in this player's era"** | **Recommended.** Null is *unknown*; zero is *none*. The reading layer renders null as "—", and every counter added after launch carries the distinction honestly |
| Backfill by re-deriving from the evidence | **Only correct where the evidence exists**, which for a new fact it does not |

**Recorded as `PS-D2`**, because it is a decision that should be taken once and
applied to every future counter rather than per column.

### 14.3 Assists — additive, needs a new evidence table

Needs an evidence source of the same shape as goals — one row per assister per
match, with a count. Then a contribution term and a rating decision.

**No change to this table's structure**; one column, and §14.2.

### 14.4 Own goals — additive, and blocked upstream

Would be a counter — *own goals conceded* — but **the evidence cannot currently
be recorded** (`MG-R2`): a goal row cannot say which side a goal counted for,
and naming the scorer awards them **+0.05**.

**This table is ready; the evidence layer is not.** The Product Decision named
in `MG-D3` must come first.

### 14.5 Cards — additive, needs a new evidence table

Needs a per-match disciplinary record. Two counters — yellows and reds — or one
per type.

**One consideration that is not obvious:** cards are the first candidate that is
**not derived from a result**. A card is a fact about a match that is true
whether or not the result was ever recorded — which would break the invariant
that *statistics arise only from a recorded result* (`A4`).

**Either cards are recorded as part of the result** (preserving `A4`), **or
`A4` acquires an exception.** The first is strongly preferred, and it is a
Product Decision. `PS-D4`.

### 14.6 Clean sheets — additive, **and derivable from data that already exists**

A clean sheet is *the player was in the lineup, played in goal, and the
opposing side scored zero*.

**Every input already exists**: the lineup carries `assigned_position = 'GK'`,
and the result carries both scores. **No new evidence table is needed** — only a
contribution term and a column.

**It is the cheapest of the five**, and the only one needing no upstream work.

### 14.7 Goalkeeper statistics — additive, mostly available

Saves and goals conceded need new evidence; **appearances in goal** needs none,
for the same reason as clean sheets.

**A design note worth recording:** goalkeeper counters would be zero for most
players forever, and null for outfield players is not more truthful than zero —
a player who never kept goal genuinely conceded no goals *as a keeper*.
**§14.2's recommendation does not apply here**, which is why the decision should
be per-counter under one stated rule rather than blanket.

### 14.8 The general rule

> **A new column on `player_statistics` must be a career total of a fact
> recorded per match, must have an evidence source that can be reversed, and
> must declare whether zero or null is the truthful value for careers that
> predate it.** Anything per-community, per-period or per-match belongs
> elsewhere.

---

## 15. Engineering Rationale

### 15.1 A cache is acceptable because the reversal is exact

Accumulated counters are a denormalisation, and this schema has refused
denormalisation repeatedly — no counter on the community, no result flag on the
match. **This one is different because it can be taken back exactly**: one
shared helper, both directions, contribution by contribution. §4.1.

### 15.2 The natural key, because the row is about the person

No surrogate, no second name for a row, no unused column. **The table every
other one in this phase is measured against on key design** (§8.1).

### 15.3 The rating is not here, because two numbers for one thing disagree

`RR-6`. Level 1 lives in two tables because a running value and an accumulation
are different kinds of number, and joining them at read time costs one
primary-key lookup.

### 15.4 The constraints found the defect, so the constraints stay

`PS-C3` caused `RR-4`'s symptom and was right throughout. A cache with
constraints raises when it would otherwise store nonsense — which is the whole
argument for constraining derived data. §5.3.

### 15.5 No human writes it, so no human is recorded

§11.1. Every value is a consequence; naming an actor would name someone who made
a different decision on a row that is not theirs.

---

## 16. Engineering Review

**Six findings.**

### 16.1 Ownership violations — one, and it is about reading

**No write violation exists**: no policy, no operation, no actor.

**The read policy is unscoped** (§10.2) — every authenticated user may read
every career, which permits enumeration `UP-1` forbids and makes this an
unapproved second broadly-readable table. **`PS-R1`, Medium-High.**

### 16.2 Duplicate responsibilities — none, and one was actively avoided

The rating is deliberately not stored here (`RR-6`). No per-community figure, no
period, no per-match trace. **The table holds six numbers and nothing that
belongs to another layer.**

### 16.3 History violations — none

This table writes no history and depends on none (§13, DP-8). It is not a
historical record and does not present as one (§4.2).

### 16.4 Derived-data violations — none in principle, three inherited in practice

**The derivation rules are correct and correctly implemented.** The violations
are all of the form *the source changed underneath a figure that was already
derived from it*, and all three belong to other tables (§6.4): the MVP cascade,
the deleted scorer, the replaced lineup.

**Their common shape is worth stating once:** every one of them removes evidence
without reversing what it produced, and **every one of them lands here as a
career total that no operation can correct** — which is §16.5.

### 16.5 Database consistency — the missing rebuild path

**There is no operation that recomputes these counters from the evidence.**

The counters are maintained incrementally. When a result exists, correction is
exact. **When the evidence is gone, correction is impossible** — and the three
cases in §6.4 all destroy evidence without reversing.

**`RR-4`'s recovery is the precedent, and it shows the limit:** 100 contaminated
matches were repaired by deleting them *through the corrected code*, which fired
the reversal 100 times and returned every account to exactly its baseline.
**That worked because the results still existed.** Where a result has been
cascaded away, nothing can be fired.

**Two things this specification asks for, and neither is a schema change:**

| # | Ask | Why |
|---|---|---|
| 1 | **A reconciliation check** — recompute the counters from the evidence and compare, without writing | Drift is currently undetectable. `mvp_count` gives a free global check: **its sum across all players must equal the number of recorded results** (§7.2 column 7) |
| 2 | **A rebuild operation** — recompute and replace, for one player or all | The only repair available once evidence is gone. It is also the *only* operation that would let a new counter column be backfilled honestly (§14.2) |

**Recorded as `PS-R2`, Medium.** Neither is urgent while the three upstream
cases remain rare; both become necessary the moment one of them occurs in
production, because **today there would be no way to know it had.**

### 16.6 Performance risks — none, with one note

Every access is by primary key. The apply path writes one row per participant of
one match; the reverse path updates the same set. **The table is one row per
player who has played** — the smallest possible representation of what it holds.

**The note:** §9.2's refusal of ranking indexes is a performance decision as
much as an architectural one. Should a board ever be pointed at this table, it
would scan every career in the application — and the correct response is to fix
the query, not to add the index.

### 16.7 Summary

| Finding | Verdict |
|---|---|
| Ownership — unscoped read | **`PS-R1`, Medium-High** — §20 item 1 |
| Ownership — writes | **None** |
| Duplicate responsibilities | **None**, and one avoided |
| History violations | **None** |
| Derived-data violations | **None in principle**; three inherited, all landing here |
| Consistency — no reconciliation, no rebuild | **`PS-R2`, Medium** — §20 item 2 |
| Performance | **None** |

**No approved product behaviour is redesigned by any of the above.**

---

## 17. Validation

**Contradictions are named, not resolved silently.**

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | **Approved context, items 3–6** | **Resolves a prior contradiction** | §17.1 |
| 2 | `Match_Results_Table_Specification.md` v1.0 | **No contradiction** | Its §4.2 (why statistics never own results) is §4.1–§4.2 here from the other side. Its `MRS-R1` lands here as an uncorrectable career total (§6.4) |
| 3 | `Match_Goals_Table_Specification.md` v1.0 | **No contradiction** | Its §4.2 (why goals are not statistics) and this document's §4.1 are the same boundary. Its `MG-R1` lands here (§6.4) |
| 4 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction** | `SL-2` §2.1 (Level 1 carries no community dimension), §2.3 (no board reads it), §2.5 (the levels agree by construction), §6 (the Player Profile's measures), `SL-5` (a rating is not a counter), `A4` (only from a recorded result) — all confirmed |
| 5 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction** | `RR-4` is §5.3 and `PS-C6`–`PS-C8`. `RR-6` is §1.3, §4.3 and §4.4. **`RR-7`'s lineup limitation lands here** (§6.4) |
| 6 | `BTGE_Database_Contract.md` v1.0 | **No contradiction** | Its §6.2 forbids BTGE writing this table — confirmed, nothing but the statistics path writes it |
| 7 | `Docs/06-ERD.md` | **No contradiction** | §1: *"the player's **career** counters — one row per player"*. §2: *"keyed by user alone: it is a **career** record, with no community and no period"*. §3.2: `E4` Global Statistics, one per player |
| 8 | `Docs/01-PRD.md` | **No contradiction** | *Statistics and leaderboards, at two levels: **Global** — the player's career, shown on the Player Profile* |
| 9 | `Docs/10-Design-Decisions.md` | **No contradiction** | `SL-1`…`SL-5` hold |
| 10 | **Database Principles** | **No artifact in the repository** | **Eleventh phase.** Seven of the nine `DP-n` principles have no definition here; §13 states the reading applied. **Two drafting points are recorded rather than assumed**: `DP-8`'s name differs from the previous brief, and `DP-9` is absent (§13) |
| 11 | `Docs/07-Database-Design.md` | **No contradiction** | *"written only by `record_match_result` and carry select policies and nothing else"* — confirmed for writes. §17.2 |
| 12 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **One checklist item not met** | §17.2 |

### 17.1 The prior contradiction, now resolved

The previous phase recorded `MG-D5`: **approved context items stating that
Player Statistics feed Community Statistics, and that Community Statistics feed
Ratings**, both of which contradicted `SL-2` and `SL-3`.

**This brief's items 3–6 state the opposite, and correctly:**

> *3. Player Statistics are derived directly from Match Results and Match
> Goals.*
> *4. Community Statistics are derived **independently** from Match Results and
> Match Goals.*
> *5. Player Statistics **never** feed Community Statistics.*
> *6. Community Statistics **never** feed Player Statistics.*

Together with items 7–10 and DP-10, this is exactly `SL-2` and `SL-3`.

**`MG-D5` is therefore answered**, in favour of the reading that specification
applied. Recorded here so the resolution is traceable rather than implicit.

### 17.2 The checklist item this table does not meet

`SUPABASE_OPERATIONAL_GUIDELINES.md` §4: *"No public table without explicit
Product Owner approval. 'Public' means readable… by `authenticated` without a
membership or role predicate. **Today exactly one table is broadly readable by
design — `communities`**… Any new one needs the same."*

**This table is broadly readable and no approval is recorded.** With `UP-1`
closing the equivalent hole on `users`, this would be the only unapproved one
remaining.

**Not resolved silently.** Specified in §10.1, recorded as `PS-R1`, §20 item 1.

---

## 18. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `PS-R1` | **Every authenticated user can read every player's career**, unscoped — permitting enumeration of every user who has ever played, with full career detail. Partially defeats `UP-1`, and makes this an unapproved second broadly-readable table | **Medium-High** | **Open**, §20 item 1. **The application does not rely on it** — the profile read is driven from `users` — so narrowing costs nothing. **Close together with `UP-1`** |
| `PS-R2` | **No reconciliation and no rebuild.** Drift is undetectable, and once evidence is destroyed it is uncorrectable. The three upstream cases in §6.4 all produce exactly that | **Medium** | **Open**, §20 item 2. Neither is a schema change |
| `PS-R3` | **Three inherited cases leave permanently wrong career totals**: the MVP cascade, the deleted scorer, the replaced lineup | Medium | **Inherited** — `MRS-R1`, `MG-R1`, `RR-7`. None is this table's to fix; all land here |
| `PS-R4` | **A new counter column defaults to zero, asserting a falsehood** for careers predating the measure | Low, until a counter is added | **Open**, `PS-D2`. Decide once, apply to every future counter |
| `PS-R5` | **A row of zeros is indistinguishable from a never-played career**, in the reading layer | Low | **Accepted** (§2.4). Both display identically and both statements are accurate |
| `PS-R6` | **Pressure to point a leaderboard at this table** will recur, because it holds exactly the numbers a board wants | Low, but the consequence is architectural | **Refused in advance** — `SL-2` §2.3, §9.2. Recorded because the refusal must survive the next person who notices |

---

## 19. Open Decisions

| ID | Question | Recommendation |
|---|---|---|
| `PS-D1` | **Do the nine `DP-n` readings in §13 match their approved definitions?** | **Confirm.** Seven are stated readings. The same request as `BDC-D4`, `MRS-D4` and `MG-D1`; all four should be answered together |
| `PS-D3` | **RESOLVED 2026-08-02.** Is `DP-8` one principle or two? | **One principle, one name.** *Historical Record Protection Principle* is used across the corpus; `Match_Goals_Table_Specification.md` §13 records the earlier name as a synonym and its reading is unchanged. Original note: **Confirm.** §13 addresses the formulation stated here and the reading covers both; if they are distinct, one has not been validated against |
| `PS-D2` | **When a new counter is added, is zero or null the truthful value for careers predating it?** | **Null, as a default rule** — zero asserts *none*, null asserts *unknown*, and `UP-2` forbids inventing what the database does not know. **But decide it as a rule with a per-counter exception** (§14.7): a goalkeeper counter is truthfully zero for an outfield player |
| `PS-D4` | **If cards are ever added, are they recorded as part of the result?** | **Yes.** A card recorded independently would break `A4` — statistics arising only from a recorded result — which every reversal guarantee depends on (§14.5) |
| `PS-D5` | **Should a reconciliation check and a rebuild operation be built?** | **Reconciliation: yes, and cheaply** — `mvp_count`'s global sum gives a free check. **Rebuild: yes, before the first production occurrence** of any §6.4 case, since it is also the only honest backfill path for `PS-D2` |

---

## 20. Conformance

| # | Deviation | Required by | Severity | Notes for the implementing phase |
|---|---|---|---|---|
| 1 | **The read policy is unscoped** — every authenticated user reads every career | §10.2 | **Medium-High** | Scope to self and shared communities, matching `UP-1` tier 2. **Verify no client path breaks** — the profile read goes through `users` and embeds the counters, so it should not. Assert the denial in the integration suite. **Close with `UP-1`** |
| 2 | **No reconciliation and no rebuild operation** | §16.5 | Medium | Neither is a schema change. Reconciliation first — it is nearly free and makes the other three risks *visible* rather than silent |

**Everything else conforms.** The structure, the natural primary key, all six
counters with their defaults and checks, both audit timestamps with the trigger,
the complete absence of write policies, the two-statement apply/reverse split
and the shared contribution arithmetic are exactly as specified.

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched.

---

## 21. Engineering Approval

**Status: Engineering Approved — conditional.**

This document is the authoritative engineering specification for
`public.player_statistics`. It is **conditional** on §20 item 1.

**A note on the shape of the findings.** This table has **the best key design
and the best write model in the phase** — a natural primary key with no unused
surrogate, no write policy, no human actor, and an index strategy consisting
entirely of its primary key. **Both of its findings are about the edges**: who
may read it, and what happens when the evidence behind it disappears.

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5`, **with the name's two inaccuracies stated** | ✓ §0 |
| Business purpose, business owner, domain ownership, lifecycle ownership | ✓ §1, all four |
| **Complete lifecycle** — six valid transitions, seven invalid, **and why statistics are rebuilt from result changes rather than edited** | ✓ §2 |
| **Business responsibilities** — six owned, eight not | ✓ §3 |
| **Statistics model** — why counters, why not history, why not ratings, why not leaderboards, **why never the source for Community Statistics** | ✓ §4, five of five |
| Relationships: incoming, outgoing, ownership, deletion, lifecycle | ✓ §6 |
| Every column — name, purpose, type, nullability, default, editability, justification | ✓ 9 of 9 |
| Every business constraint with its reason | ✓ 11, plus five deliberately refused |
| Keys: primary, **business key**, candidate, alternate, foreign — **the business key *is* the primary key** | ✓ §8 |
| Index strategy: **the primary key and nothing else**, with ranking indexes refused as a design statement | ✓ §9 |
| Access control: player, member, admin, organizer, System Administrator × read/write/recalculate/delete | ✓ §10 |
| Audit: all four columns ruled on, **with a reason unique to this table** | ✓ §11 |
| Dependencies both directions, **including the three unrepresented ones and what they cost** | ✓ §12 |
| **Nine `DP-n` principles**, each validated, with the reading and basis marked | ✓ §13 |
| **Future compatibility**: assists, own goals, cards, clean sheets, goalkeeper statistics | ✓ §14, five of five — **with the backfill problem that applies to all of them** |
| **Engineering review** — ownership, duplication, history, derived-data, consistency, performance | ✓ §16, six findings |
| Validation; contradictions named, not resolved | ✓ 12 sources, **1 checklist failure named, 1 prior contradiction resolved** |
| No SQL, no migration, no Community Statistics, no ratings, no leaderboards, no other table designed | ✓ |

### Validation caveat, stated rather than glossed

The brief names *Database Principles* as a validation source. **It does not
exist as a document in this repository** — the eleventh phase in which this has
been recorded. Seven of the nine `DP-n` principles have no definition here, and
two drafting inconsistencies between briefs are recorded in §13 rather than
assumed away. `PS-D1` and `PS-D3` ask for confirmation.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Match_Results_Table_Specification.md` | **The primary evidence.** Its §4.2 is this document's §4.1 from the other side; its `MRS-R1` lands here |
| `engineering/Match_Goals_Table_Specification.md` | **Evidence for one counter.** Its §4.2 states the same boundary; its `MG-R1` lands here; its `MG-D5` is resolved by §17.1 |
| `engineering/Match_Team_Assignments_Table_Specification.md` | **The derivation driver** — `matches_played` is a count of its rows |
| `engineering/Matches_Table_Specification.md` | Supplies the lock under which counters move |
| `engineering/Profiles_Table_Specification.md` | **Holds the other half of Level 1** — the Global Rating (`RR-6`). **`UP-1` is the rule §10.2 says this table should match** |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **`SL-2`, `SL-5`, `A4`** — the authority for §4 throughout |
| `engineering/Results_Rating_Engineering_Decisions.md` | **`RR-4`** (§5.3), **`RR-6`** (§1.3, §4.3), `RR-7` (§6.4) |
| `engineering/BTGE_Database_Contract.md` | §6.2 forbids BTGE writing this table; `BDC-D4` is `PS-D1` |
| `Docs/06-ERD.md` | §1, §2, §3.2 `E4` — the career record, keyed by user alone |
| `Docs/01-PRD.md` | *Global — the player's career, shown on the Player Profile* |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §4 — **the one-public-table rule this table breaks** (§17.2) |
