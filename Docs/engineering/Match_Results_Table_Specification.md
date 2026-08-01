# Match Result (`match_results`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One High-severity defect; see §17 and §19 |
| Role | **Engineering Authority** for the physical table `public.match_results` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Results |
| Scope | **`public.match_results` only.** `match_goals`, `player_statistics`, `rating_history`, Community Statistics and leaderboards appear **only as dependent entities** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **This document is the authoritative specification for the physical table
> `public.match_results`.** Where an implementation and this document disagree,
> **the implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation**, and it designs no
> goals, no statistics and no ratings.
>
> **It does not redesign approved product behaviour.** The ten decisions
> supplied with the brief are taken as given, as are `RR-1` … `RR-7`. §16
> reviews the architecture around them and recommends no change to any
> approved rule.
>
> **Sibling authorities.** `Profiles_Table_Specification.md` v2.0,
> `Communities_Table_Specification.md` v1.0,
> `Community_Members_Table_Specification.md` v1.0,
> `Community_Invitations_Table_Specification.md` v1.0,
> `Matches_Table_Specification.md` v1.0,
> `Match_Registrations_Table_Specification.md` v1.0,
> `Match_Team_Assignments_Table_Specification.md` v1.0,
> `BTGE_Database_Contract.md` v1.0.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Match Result** |
| **Physical table** | **`match_results`** |

One row is *the result of one match*. There is at most one, ever, per match —
§5.1 shows that this is not a rule bolted on but the shape of the table.

---

## 1. Purpose

### 1.1 Business purpose

A Match Result records **what happened in a match**: the two scores, and who
was named best player.

It exists because **it is the event that converts a game into figures.** Before
a result is recorded, a match has been played and the product knows nothing
about it — no rating moves, no counter increments, no leaderboard changes. The
recording is the moment the game enters the record, and this row is that
moment.

Three properties follow, and each is a section below:

1. **It is the sole origin of every figure in the product** (§4). Statistics,
   ratings, Community Statistics and leaderboards are all derived from it, none
   of them owns it, and none may be produced without it.
2. **Its effects are entailed, not optional.** A result recorded without its
   rating and counter changes would be a result that did not count, so recording
   and applying are one transaction (§7.2).
3. **It is correctable, and correction is by reversal** — of the effects, never
   by editing the audit (§2.4).

### 1.2 Business owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That a result exists** | **The community's owner and admins** | Recording |
| `team_a_score`, `team_b_score`, `mvp_user_id` | **The organiser who records it** — it is their assertion about a game they ran | Recording, and re-recording |
| `recorded_by` | The system, from the caller | Recording |
| `match_id`, `id`, `created_at` | The database | Nothing writes them after insert |

**Nobody else may write any of it.** Not the player whose rating it moves, not
the MVP it names, not the scorers. A result is an organiser's record of a game,
and the people it describes have no write access to it (§10.3).

### 1.3 Domain ownership

**Domain: Match. Position: inside the Match aggregate, beneath its root.**

| Property | Value |
|---|---|
| Aggregate | **Member of the Match aggregate**, not a root |
| Aggregate root | `matches` |
| Depends on | `matches`, `users`, and **`match_team_assignments` semantically** (§12.1) |
| Depended on by | `match_goals` by foreign key; four more tables by behaviour |
| Contains authorization | **No** |

**It is the aggregate's terminal record.** Registrations precede the match,
assignments record it, and the result concludes it. Nothing in the Match
aggregate comes after.

### 1.4 Lifecycle ownership

| Bounded by | Consequence |
|---|---|
| **The match** | Cascades with it — and the cascade fires a reversal first, so a deleted match un-counts itself (§6.4) |
| **The MVP's account** | **Cascades with it — and this one does *not* reverse.** `MRS-R1`, the High-severity finding (§6.4) |
| **Not the recorder's account** | `recorded_by` clears rather than cascading: recording a result can never be the reason an account cannot be deleted |
| **Not the clock** | A result is never expired, archived or closed. It stays until its match goes |

---

## 2. Lifecycle

### 2.1 The states

```
   NO RESULT
       │
       │  record  ── validated, then applied in ONE transaction:
       │              reverse nothing · store · apply ratings · apply counters
       ▼
   RECORDED  ── and simultaneously PUBLISHED: there is no draft (§2.5)
       │
       ├── correct ──┐   same operation, same rules:
       │             │   reverse ratings · reverse counters · replace the row
       │             │   · apply new ratings · apply new counters
       │      ◀──────┘   repeatable, unlimited
       │
       ▼
   HISTORICAL RECORD   ← nothing changes. The row stays as the last recorded
                         truth about the match.
```

**There are two states and one operation.** Recording a result for the first
time and correcting one already recorded are **the same call with the same
rules** — deliberately, because two operations would be two chances for the
rules to drift apart.

### 2.2 Every valid transition

| # | From | To | Trigger | Notes |
|---|---|---|---|---|
| 1 | No result | Recorded | An owner or admin records it | Validated in full **before anything is written** (§7.3) |
| 2 | Recorded | Recorded | **Correction** | The row is replaced; the *effects* are reversed and reapplied |
| 3 | Recorded | No result | The match is deleted | The reversal trigger fires first, so the match un-counts itself |
| 4 | Recorded | No result | **The MVP's account is deleted** | **The reversal does *not* fire** — `MRS-R1` |
| 5 | Recorded | Historical | Time passes | **Nothing changes.** The transition is entirely in what the row now means |

### 2.3 Invalid transitions, and what refuses each

| Invalid | Why | Refused by |
|---|---|---|
| Two results for one match | A match has one outcome. Two would make every derived figure ask which one counted | The business key (`MRS-C2`) |
| A result with no lineup | There would be no side for a player to have been on — no winner to reward, no loser to charge | `LINEUP_REQUIRED` |
| An MVP who did not play | A rating award to somebody who was not in the match | `MVP_NOT_PARTICIPANT` |
| A scorer who did not play | A goal is worth rating; without the rule, an organiser could credit any account in the system | `SCORER_NOT_PARTICIPANT` |
| A negative score | Not a football result | `INVALID_SCORE`, and a check constraint |
| Goals that do not sum to the score | The two would assert different facts about the same match, and every consumer would have to pick one | `GOALS_DO_NOT_MATCH_SCORE` |
| Two goal entries for one player | Not a bigger number — the same fact twice, and which counted would be arbitrary | `INVALID_GOALS` |
| A goal entry of zero or fewer | The entry asserts that this player scored | `INVALID_GOALS` |
| A result recorded by a non-admin | Recording moves other people's ratings | `NOT_AUTHORIZED` |
| **Editing the row directly** | Would store a result without reversing the previous one's effects, leaving every derived figure wrong and unrecoverable | **No write policy exists** (§10.3) |
| **Editing the rating audit** | `RR-5`: an audit that is edited when the facts change can answer neither *what happened* nor *what is true now* | Immutability on that table — not this one's business |

### 2.4 Why correction reverses rather than mutating history — and exactly what is mutated

**The brief asks why correction creates a new historical record instead of
modifying an existing one. The precise answer requires separating two things
that are easy to conflate, and this specification will not conflate them.**

| What | On correction | Why |
|---|---|---|
| **The rating audit** (`rating_history`) | **Never mutated.** Each previous change is undone by a **new row** naming the row it reverses. No historical row is ever updated | `RR-5`. An audit exists to answer *what happened*, not *what is true now*. A record edited when the facts change can answer neither — and it is a worse source for the present state than the rating column itself. After a correction the history reads as a narrative: what the first result awarded, that each award was taken back, and what the second awarded instead |
| **The counters** | **Reversed, then reapplied** — separate statements over shared arithmetic | `RR-4`. Applying and reversing are not one operation with a sign: applying may have to create a counters row, reversing never does. And a single statement carrying negative values proposes a row that violates the non-negative checks *before* the conflict is detected |
| **The rating values** | Reversed by the **applied** delta, newest first | `RR-1`, `RR-5`. Reversing by the nominal constant would hand back a tenth to a player who never received it, because a rating at the end of its range is clamped. Walking backwards through states the player genuinely occupied means no clamp can fire on the way out |
| **This row** | **Replaced in place.** The scores, the MVP and the recorder are overwritten | §2.5 |

> **The row is not a historical record. It is the current, last-recorded truth
> about the match.** What is immutable is the *audit of the effects*, not the
> *statement of the result*.

**Why that division is correct.** The audit exists so a correction can be
exact — reversal must use the delta that was actually applied, which only an
append-only record preserves. The result row exists so consumers can ask *what
was the score*, and there is exactly one true answer to that at any moment.
Keeping superseded scores would create a second answer with no rule for which
one counts.

**The consequence, stated rather than glossed:** **there is no history of
results.** A corrected result leaves no record of what it previously said. The
rating audit shows that deltas were reversed and new ones applied — so *that* a
correction happened is recoverable — but **the previous score and the previous
MVP are not.** No approved document asks for them. Recorded as `MRS-R4`.

### 2.5 Publication — there is no such event, and that is the design

**Recording a result *is* publishing it.** There is no draft, no pending state,
no `published_at`, no approval step and no reviewer.

| Why no draft state | |
|---|---|
| **A result has no meaning until it counts** | The recording applies the ratings and the counters in the same transaction. A stored-but-unpublished result would be a result whose effects had not happened, which is indistinguishable from no result at all |
| **It would need a second write path** | Publishing a draft would be a second operation applying the effects — and `RR-2`'s pattern, and the Single Business Path Principle, both refuse a second route to the same outcome |
| **Nobody has asked for one** | No approved document mentions publication, review or approval |

**Where a future review step would go** is §14.1 — and it is not a state on this
row.

---

## 3. Business Responsibilities

### 3.1 What this table owns

| # | Responsibility | How expressed |
|---|---|---|
| 1 | **The final score** | `team_a_score` and `team_b_score` — the definitive statement of the outcome |
| 2 | **The MVP** | `mvp_user_id`. **Exactly one per match**, and §5.1 shows the shape that guarantees it |
| 3 | **That the match produced figures at all** | The existence of the row. A match with no result produces nothing at either statistical level |
| 4 | **The trigger for every derived figure** | Recording is what applies ratings and counters; correcting is what reverses and reapplies them |
| 5 | **Attribution of the recording** | `recorded_by` — with the caveat in §11.2 |

**The winning side is owned but not stored** (§3.3).

### 3.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **Who took part** | `match_team_assignments` | Participation is the lineup's, absolutely. This row names one participant — the MVP — and validates against the lineup; it does not define the set |
| 2 | **Which side each player was on** | `match_team_assignments` | The result says *team A scored 3*; only the lineup says *who team A was* |
| 3 | **The goals** | `match_goals` | Referenced only as a dependent entity |
| 4 | **Any statistic or rating** | The statistics and rating tables | It *causes* them; it stores none. `RR-6`: the current rating is not copied beside the counters, and no figure is copied here |
| 5 | **Completion state** | `matches.status`, derived | §3.4 |
| 6 | **A publication event** | Nowhere — it does not exist | §2.5 |
| 7 | **The history of previous results** | Nowhere, deliberately | §2.4, `MRS-R4` |
| 8 | **Who *originally* recorded a corrected result** | Nowhere | §11.2, `MRS-R3` |

### 3.3 The winning side — owned, derived, never stored

**The winner is `team_a_score` compared with `team_b_score`. A draw is
equality.** There is no `winner` column, and none may be added.

**Why derived rather than stored:** a stored winner is a second statement of a
fact the scores already make, free to disagree with them. It is the same
argument that keeps out-of-position out of the lineup — where §5.1 of the
engine specification defines it as *exactly* a basis value, and migration
`0018` refused a column for it because *storing a derived value invites the two
to disagree.*

**Consequence:** "winning side consistency" is not a constraint this table
needs, because there is nothing for the winner to be inconsistent with. The
rule is enforced by the column's absence.

### 3.4 Completion state — not owned, and the asymmetry is recorded

A match's completion is `matches.status`, derived from the clock and written
back lazily.

**The database imposes no rule that a match must have finished before a result
is recorded.** The interface offers the entry point only for a completed match;
the database does not refuse a result for a future one.

**This is `RR-7 A4`, and it is a deliberate split**: the approved validation
rules list five checks and "the match must have finished" is not among them, so
making it a refusal would have been a Product Decision taken in the wrong
layer. Hiding a control is a presentation choice the codebase already makes;
refusing a write is not.

**Restated here, not resolved.** A client calling the recording operation for a
future match will succeed.

---

## 4. The Result Model

### 4.1 Why Match Results is the source of truth

**Because it is the only *assertion* in the chain. Everything after it is
arithmetic.**

| Layer | Nature |
|---|---|
| **The result** | An **assertion** by a human who was there: this was the score, this player was best |
| Goals | An assertion, constrained to agree with the score |
| Ratings | **Derived** — winner, loser, goal and MVP deltas applied over the lineup |
| Statistics (Level 1) | **Derived** — six counters computed from the same contribution |
| Community Statistics (Level 2) | **Derived** — the same facts, scoped by community and period |
| Leaderboards | **Derived** — ranked reads of Level 2 |

**Only the first can be wrong in a way that requires a human to fix.** Every
layer below is a function of it, so correcting the assertion and recomputing is
the whole of correction — which is exactly what the recording operation does.

### 4.2 Why Statistics never own results

**Because a counter is an accumulation and a result is an event, and an
accumulation cannot be corrected without the event that produced it.**

If statistics owned the result, correcting a score would mean adjusting
counters directly — and there would be no record of *what* was being corrected,
no way to compute the difference, and no way to verify the adjustment. The
counters would become a set of numbers somebody edited.

**`RR-4` is the concrete evidence.** Reversal is possible only because the
contribution each player made is recomputed *from the stored result and the
stored lineup*, by one shared helper that both directions read. Neither
direction restates a rule the other holds — and neither could exist if the
result were not a durable, separate record.

**`A4` states the same rule from the other side:** statistics arise **only**
from a recorded result. A match played but never recorded produces nothing at
either level.

### 4.3 Why Ratings never own results

**Because the rating is a running value and the result is what moves it — and
the audit of the movement is not the movement's cause.**

`rating_history` is append-only and records, for each change, the before, the
after, the applied delta, the reason and the match. **It is the record of an
effect, not of the event.** A correction reverses by the *applied* delta,
which the audit preserves and the result does not — so the two records answer
different questions and neither can replace the other:

| Question | Answered by |
|---|---|
| What was the score? | **The result** |
| By how much did this player's rating actually move, and from what? | **The rating audit** |
| Is this entry still in effect? | **A query over the audit** — not a stored flag, because a `reversed_at` column would mean writing to a historical row |

**And the rating must not be recomputable from the result alone**, because
clamping makes the applied delta differ from the nominal one at the ends of the
range. That is precisely why the audit exists — and precisely why it cannot own
the result.

### 4.4 Why Leaderboards never own results

**Because a leaderboard is a ranked read, two derivations removed.**

A board reads Level 2 records, which are derived from results, which are
scoped by community through the match. `SL-2` §2.3 makes it normative: **all
Community Leaderboards must use Community Statistics and must never read Level
1** — and by the same logic they must never read a result directly.

**A board that read results would recompute the statistics engine in a query**,
in a second place, with no reversal path. The correction that reverses a result
would leave that query's answer correct only by luck.

### 4.5 The rule the model turns on

> **One assertion, one write path, one direction of derivation. Nothing
> downstream may be authored, only computed — and everything downstream must be
> reversible from what the assertion and the lineup jointly say.**

---

## 5. Relationships

### 5.1 Incoming

| Table | Column | Targets | On delete | Note |
|---|---|---|---|---|
| `match_goals` | `match_id` | **`match_results(match_id)`** — the alternate key, **not** the primary key | `CASCADE` | §8.4 |

**One incoming foreign key, and it is unusual**: it targets the unique
`match_id` rather than the primary key. §8.4 explains why that is right.

### 5.2 Outgoing

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `matches` | `match_id` | **1 : 1** | **`CASCADE`** | **Identifying, and unique** — §5.3 |
| `users` | `mvp_user_id` | many : 1 | **`CASCADE`** | **The defect** — §6.4, `MRS-R1` |
| `users` | `recorded_by` | many : 1 | **`SET NULL`** | Attribution. Nullable so recording can never block an account deletion |

### 5.3 "One result per match" is the table's shape, not a rule added to it

`match_id` is **unique and NOT NULL**. Combined with `mvp_user_id` being NOT
NULL, this yields a guarantee stronger than any check could express:

> **A match has at most one result, and a result names exactly one MVP — so
> there is no shape in which a match has two MVPs or none.**

The alternative designs both fail: an MVP as a flag on the lineup would permit
zero or several, and an MVP table would need its own uniqueness rule. **Making
it a NOT NULL column of a row that is unique per match settles both questions
at once.**

### 5.4 Ownership

| Question | Answer |
|---|---|
| **Who owns the relationship's meaning?** | The **match**. A result says *of this fixture* |
| **Can it be reparented?** | **No.** Nothing writes `match_id` after insert; a correction upserts on it |
| **Does the match know it has a result?** | **No flag on the match**, deliberately. Its existence is the answer |
| **Does the result know the participants?** | **No.** It names one — the MVP — and validates against the lineup. The set is the lineup's |

### 5.5 Deletion behaviour

| Path | Behaviour |
|---|---|
| **The match is deleted** | A `BEFORE DELETE` trigger on the match **reverses the result's effects first** — every participant's rating and counters move back by exactly what this match awarded — and then the cascade removes the result and its goals. **The match un-counts itself** |
| **The MVP's account is deleted** | The result **cascades away with no reversal**. §6.4 |
| **The recorder's account is deleted** | `recorded_by` clears. The result is untouched |
| **Directly** | **No path exists.** There is no delete policy, and the recording operation never deletes a result — it replaces it |

### 5.6 Lifecycle

| Relationship | Whose lifetime bounds whose |
|---|---|
| `matches` → result | **Absolutely.** And the boundary is safe, because the trigger reverses before the cascade |
| `users` (MVP) → result | **Absolutely — and the boundary is not safe.** `MRS-R1` |
| `users` (recorder) → result | **Neither bounds the other.** Correct, and deliberate |
| result → `match_goals` | **Absolutely.** Goals cannot outlive the result they belong to |
| result → the derived figures | **Not structural.** Ratings and counters live on rows the result does not own, and are kept correct by the reversal discipline rather than by a cascade |

---

## 6. Columns

Eight columns.

### 6.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `match_id` | `uuid` | No | none | **Never** |
| 3 | `team_a_score` | `int` | No | none | **System only**, via correction |
| 4 | `team_b_score` | `int` | No | none | **System only**, via correction |
| 5 | `mvp_user_id` | `uuid` | **No** | none | **System only**, via correction |
| 6 | `recorded_by` | `uuid` | **Yes** | none | **System only**, via correction |
| 7 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| 8 | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** |

**"System only, via correction" is precise, not a euphemism.** No client may
write any column — there are **no write policies at all** — and the four
mutable columns change only inside the recording operation, which reverses the
previous result's effects before replacing them and applies the new ones after.
**A write that changed a score without doing that would leave every derived
figure permanently wrong**, which is why the write path is not merely
restricted but absent.

### 6.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated, never editable**

*Purpose.* Row identity.

*Business justification.* **It has no consumer.** Goals reference `match_id`,
not this column (§8.4); the recording operation upserts on `match_id`; nothing
reads a result by `id`. **Retained, not defended** — the same position taken on
every surrogate in this schema whose business key does the work.

---

**2. `match_id` — `uuid`, NOT NULL, unique, never editable**

*Purpose.* Which match this is the result of. **The business key.**

*Business justification.* It carries three jobs at once: it identifies the
result, it enforces one-result-per-match (§5.3), and it is the conflict target
the recording operation upserts on — which is what makes recording and
correcting the same call. It is also what `match_goals` references (§8.4).

*Unique and NOT NULL.* A result of no match is meaningless; a second result for
one match would make every derived figure ambiguous.

---

**3–4. `team_a_score`, `team_b_score` — `int`, NOT NULL, no default, non-negative**

*Purpose.* **The final score**, side by side.

*Business justification.* Two columns rather than one composite, because they
are two independent facts and every consumer needs them apart: the winner is
their comparison, the total is their sum (which the goals must equal), and a
draw is their equality.

*The letters are not arbitrary — they bind to the lineup.* `team_a_score`
belongs to the players the lineup marks `A`. **This is the only place the two
tables' vocabularies must agree**, and the agreement is by convention rather
than by constraint: nothing structural connects the letter here to the letter
there.

*Non-negative, and no upper bound.* A negative score is not a football result.
No maximum is imposed because none is approved and amateur football produces
absurd scorelines that are nonetheless real.

*No default.* A result with an assumed score would be a fabricated assertion —
and this row is *the* assertion (§4.1).

---

**5. `mvp_user_id` — `uuid`, NOT NULL, no default**

*Purpose.* **Who was named best player.**

*Business justification.* It is one of the four things a rating responds to
(**+0.20**, the largest single award), and the only one that is a judgement
rather than a fact — which is why it is validated against the lineup rather
than against anything the organiser could assert freely.

*NOT NULL — and this is a Product Decision expressed structurally.* **Every
recorded result names an MVP.** There is no "no MVP" outcome. Combined with the
unique `match_id`, it produces the guarantee in §5.3.

*Must be a participant* (`MVP_NOT_PARTICIPANT`). A rating award to somebody who
was not in the match would be rating conjured from nothing.

*Its deletion behaviour is wrong* — §6.4 and `MRS-R1`.

---

**6. `recorded_by` — `uuid`, NULLABLE, no default**

*Purpose.* Attribution: who recorded this result.

*Business justification.* Recording moves other people's ratings, so who did it
is worth knowing. **It is never read to grant or deny anything** — the same
reading `matches.created_by` and `communities.owner_id` get (`PD-16`, `PD-15`).

*Nullable with `SET NULL`, deliberately.* *"Recording a result can never be the
reason a user cannot be deleted."* The attribution is worth having and not worth
blocking an account deletion for.

***It is not what it appears to be.*** A correction overwrites it with the
current caller, so it names **the most recent recorder, not the original**.
§11.2 is the finding.

---

**7. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When the result was **first** recorded.

*Business justification.* Because the row is upserted rather than replaced,
this column **survives a correction** — so it genuinely answers *when did this
match first get a result*, which is the more useful of the two timestamps and
the one a dispute turns on.

---

**8. `updated_at` — `timestamptz`, NOT NULL, default `now()`, trigger only**

*Purpose.* When the result was **last** corrected.

*Business justification.* Together with `created_at` it is the only trace a
correction leaves on this row: **if the two differ, the result has been
corrected at least once.** That is a genuinely useful signal and it is free.

**It cannot say how many times, or what changed** — §2.4, `MRS-R4`.

### 6.3 This table satisfies the audit Standards in full

Both timestamps present, trigger-maintained, and — unlike `community_members`
and `match_registrations`, which this phase records as missing `updated_at` —
this one has a mutable column *and* the timestamp that goes with it.

### 6.4 The cascade on `mvp_user_id` — the High-severity finding

**Deleting the account of a player who was named MVP deletes the entire match
result**, and its goals with it, **without going through the match** — so the
`BEFORE DELETE ON matches` reversal trigger never fires.

**What is left behind:** every *other* participant keeps the rating changes and
the career counters that result produced, for a result that no longer exists.
The figures are unrecoverable — the audit entries naming the deleted player
cascade too, and the result that would let anyone recompute the rest is gone.

**Three options existed for this column, and the most destructive was taken:**

| Option | Effect |
|---|---|
| `NOT NULL`, **no action** | The account cannot be deleted until the result is handled — forcing the administrative path to reverse it explicitly |
| `NOT NULL`, **cascade** — *chosen* | The result is destroyed silently, and the reversal never runs |
| Nullable, **`SET NULL`** | The result survives, having lost its MVP — which would then violate the NOT NULL intent of §5.3 |

**The inconsistency is within the same table.** `recorded_by` was made nullable
and `SET NULL` on the explicit reasoning that *recording a result must never
block an account deletion*. The same reasoning was not applied to
`mvp_user_id`, which instead takes the option that destroys the most.

**This is `RR-7`'s recorded limitation** — *"deleting a user who was the MVP of
a match cascades that match's result away without going through matches, so the
reversal trigger does not fire"* — and this column is its direct and sole
cause. `RR-7` recorded it as known; **this specification names the mechanism and
rates it High** (§17, `MRS-R1`), because the blast radius is other people's
career figures and there is no recovery path.

---

## 7. Business Constraints

### 7.1 Enforced by the schema

| ID | Rule | Why it exists |
|---|---|---|
| `MRS-C1` | **`match_id` references `matches(id)`, cascading** | A result of a match that does not exist is not a fact. The cascade is safe because the reversal trigger fires first (§5.5) |
| `MRS-C2` | **One result per match** — `match_id` is unique | A match has one outcome. Two would make every derived figure ask which counted, with no rule to answer it |
| `MRS-C3` | **Scores are non-negative** | Not a football result otherwise |
| `MRS-C4` | **`mvp_user_id` is NOT NULL** | Every recorded result names an MVP. With `MRS-C2`, this is the whole of "exactly one MVP per match" (§5.3) |
| `MRS-C5` | **`recorded_by` is nullable and clears on account deletion** | Attribution must never block a deletion |
| `MRS-C6` | **`created_at` and `updated_at` are NOT NULL, and `updated_at` is trigger-maintained** | §6.2 |
| `MRS-C7` | **No client may insert, update or delete** | There are **no write policies of any kind**. A direct write would store a result without reversing the previous one's effects — leaving every derived figure permanently and undetectably wrong |

### 7.2 Enforced by the recording operation

Every one of these is checked **before anything is written** (§7.3).

| ID | Rule | Why it exists |
|---|---|---|
| `MRS-C8` | **Only an owner or admin of the match's community may record or correct** | Recording moves other people's ratings. Management is a community role (`PD-07`, `PD-16`); who created the match is attribution |
| `MRS-C9` | **A stored lineup is required** | Without one there is no side for a player to have been on, so no winner to reward and no loser to charge. `RR-7 A1` |
| `MRS-C10` | **The MVP must be in the lineup** | An award to somebody who was not in the match |
| `MRS-C11` | **Every scorer must be in the lineup** | A goal is worth **+0.05**. Without the rule an organiser could credit goals — and therefore rating — to any account in the system. `RR-7 A2` |
| `MRS-C12` | **Goals must sum to the total score** | The score and the goals are two statements about one match; if they disagree, every consumer must pick one and there is no rule for choosing |
| `MRS-C13` | **Each scorer appears once, with a positive count** | Two entries for one player is the same fact twice, not a bigger number; a zero entry asserts a scorer who did not score |
| `MRS-C14` | **Recording and correcting are one operation** | Two would be two chances for the rules to drift, and the correction path is the one that must never be weaker |
| `MRS-C15` | **The effects are applied in the same transaction as the row** | A result whose ratings had not been applied is a result that did not count. §7.4 |
| `MRS-C16` | **The match row is locked first** | The Match Row Lock Principle (§13.2) |

### 7.3 The validation boundary — nothing is written until everything passes

**Every check runs before the previous result is disturbed.** This is a
correctness property, not tidiness: correction reverses the old result's effects
*before* storing the new one, so a validation failure discovered halfway would
leave a match whose ratings had been unwound and whose result had not been
replaced.

**Stated as a term:** *a refused recording leaves the previous result, its
ratings and its counters exactly as they were.*

### 7.4 What is deliberately **not** constrained

| Not constrained | Why not |
|---|---|
| **That the match has finished** | `RR-7 A4`, §3.4. Not among the approved validation rules; making it a refusal would be a Product Decision in the wrong layer |
| **An upper bound on a score** | None approved, and amateur football produces real absurdities |
| **That the winning side has more goal entries** | Own goals exist and are credited to a scorer on the other side. A constraint here would refuse a legitimate result |
| **That the MVP was on the winning side** | An MVP is a judgement. Losing sides have best players |
| **A stored winner** | §3.3 — derived, never stored |
| **A publication or review step** | §2.5 |
| **A limit on how many times a result may be corrected** | Correction is exact and repeatable by design (`RR-4`, `RR-5`). A limit would strand a genuine error |

---

## 8. Keys

### 8.1 Primary key

**`id`** — a generated `uuid`, and a surrogate **with no consumer at all**
(§6.2 column 1). Nothing references it — not even the child table, which
references the business key instead.

### 8.2 Business key

**`match_id`.**

It identifies the result in the domain's terms — *the result of this match* —
it is how the recording operation addresses the row, it is the conflict target
that makes recording and correcting one call, and it is what `match_goals`
references.

### 8.3 Candidate keys

| Candidate | Enforced | Assessment |
|---|---|---|
| `id` | Primary key | Generated, unused |
| **`match_id`** | Unique, NOT NULL | **The business key**, and the only one the domain uses |

### 8.4 Alternate keys — and the one that is actually referenced

**`match_id` is the single alternate key, and it is unusual in this schema for
being the *target of a foreign key*.**

`match_goals.match_id` references **`match_results(match_id)`**, not
`match_results(id)`. This is deliberate and correct:

- **A goal belongs to a recorded score**, not to a match. One belonging to a
  match with no result would be a number nothing adds up.
- **Referencing the business key rather than the surrogate** means the child
  carries `match_id` — which it needs anyway, for its own uniqueness rule of one
  entry per player per match — instead of carrying a redundant surrogate
  alongside it.
- **A deleted match still takes the goals with it**, one cascade further along.

**This is the only place in the schema where a foreign key targets a
non-primary key**, and the specification records it explicitly so it is not
mistaken for an oversight.

### 8.5 Foreign keys

**Outgoing — three:**

| Column | References | On delete | Assessment |
|---|---|---|---|
| `match_id` | `matches(id)` | `CASCADE` | **Correct** — the reversal trigger fires first |
| `mvp_user_id` | `users(id)` | `CASCADE` | **Wrong** — `MRS-R1`, §6.4 |
| `recorded_by` | `users(id)` | `SET NULL` | **Correct**, and its reasoning is what §6.4 says should have been applied to the MVP |

**Incoming — one**, targeting the alternate key (§8.4).

---

## 9. Index Strategy

### 9.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `MRS-X1` | **Unique on `match_id`** | (a) **fetch the result of this match** — the match details screen and the result entry form, the only reads the product performs against this table; (b) the conflict target of every recording and correction; (c) enforcement of `MRS-C2`; (d) the referential-integrity check for every goal row; (e) the contribution helper, which joins the result to the lineup per match |
| `MRS-X2` | **Primary key on `id`** (implicit) | **No query.** Listed for completeness, as the counterpart to §8.1 |

**`MRS-X1` is the only index this table requires.**

### 9.2 Considered and not required

| Candidate | Verdict | Reasoning |
|---|---|---|
| `(mvp_user_id)` | **Not yet — and it is the first one to add** | Nothing queries it today: the MVP count on the Player Profile comes from the counters table, not from scanning results. **But it carries `ON DELETE CASCADE` from `users`**, so every account deletion scans this table to find rows to remove. At present the table is tiny; if `MRS-R1` is closed by changing the cascade, the reference remains and the argument strengthens |
| `(recorded_by)` | **No** | Nothing queries by recorder, and the `SET NULL` path is equally rare |
| `(created_at)` | **No** | Nothing lists results across matches. Every read is by match |
| Anything for statistics | **No, and never** | A statistic is read from a statistics table. **A query that scans results to compute a figure is reading the wrong layer** — §4.2 |

### 9.3 The rule for a future designer

> **This table is read by match, and only by match.** An index on anything else
> means a consumer is computing a figure that a statistics table already
> holds — or should.

---

## 10. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 10.1 The matrix

| Actor | Read | Record | Correct | Delete | Publish |
|---|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ | — |
| **Non-member** | ✗ **Nothing** | ✗ | ✗ | ✗ | — |
| **Player / Community Member** | ✓ **The result of any match in their communities** | ✗ | ✗ | ✗ | — |
| **Organizer** *(the match's creator, as such)* | ✓ as a member | **✗ — see §10.4** | ✗ | ✗ | — |
| **Community Admin** | ✓ | ✓ | ✓ | ✗ | — |
| **Community Owner** | ✓ | ✓ | ✓ | ✗ | — |
| **System Administrator** | ✗ No direct path | ✗ | ✗ | ✓ Transitively | — |

**"Publish" has no actor because there is no publication step** (§2.5).
Recording is publishing.

### 10.2 Read

**Any member of the match's community may read the result.** A result is the
community's news; restricting it to participants would hide the score from the
people who could not get a place.

**Non-members see nothing**, consistent with `matches`, `match_registrations`
and `match_team_assignments`.

**System Administrator has no read path**, consistent with the rest of the
Match aggregate.

### 10.3 Record, Correct and Delete

**There are no write policies of any kind.** Every write is the one
`SECURITY DEFINER` operation, and the absence of a policy is the statement of
the rule.

**This is `RR-2`'s pattern**, and this table is one of the four that established
it: *select policies and nothing else*. **It is also the strongest reason this
table has no analogue of the defects found on `matches` and
`match_team_assignments`** — there is no second write path to withdraw, because
none was ever created.

**Delete has no path at all.** Not for an admin, not for an owner. A result is
removed only by deleting its match — which reverses first — or, wrongly, by
deleting its MVP (§6.4). **An organiser who recorded a result in error corrects
it; they do not delete it.**

### 10.4 The organizer is not a role

The brief lists *Organizer* as an actor. **In this product it is not an
authorization concept.**

`matches.created_by` records who created a match and is **never read to grant
or deny anything** (`PD-16`). `PD-07` moved match management from the creator to
the community role. So:

- **An admin may record the result of a match they did not create.**
- **A player may not record the result of a match they did create.**

The word *organizer* in this document therefore means *whoever is running the
match*, which in authorization terms is **owner or admin**, and never
`created_by`.

---

## 11. Audit

| Column | Required? | State | Verdict |
|---|---|---|---|
| `created_at` | **Required** | Present | When the result was **first** recorded — survives corrections (§6.2 column 7) |
| `updated_at` | **Required** | Present | When it was **last** corrected. Their inequality is the only on-row trace of a correction |
| `created_by` | **Required in substance, named `recorded_by`** | Present | §11.1 |
| `updated_by` | **Not required as a column — but its absence has a consequence** | Absent | §11.2 |

### 11.1 `recorded_by` satisfies `created_by`

The information `created_by` would carry — *which of several entitled people
did this* — is genuinely non-derivable and is captured. Naming it
`recorded_by` states what the act was.

### 11.2 `updated_by` — and the finding that comes with refusing it

`UP-4` excludes `updated_by`: a mutable last-writer column is erased by the
next write.

**The finding is that `recorded_by` is already that column.** It is overwritten
on every correction, so after one correction **the original recorder is
unrecoverable** — from this table, from the rating audit (which carries no
actor), and from anywhere else.

So the position is:

- **Adding `updated_by` is refused**, per `UP-4`. It would be a second mutable
  last-writer column beside one that already exists.
- **`recorded_by`'s semantics must be stated honestly**: it is *last recorded
  by*, not *first recorded by*. Reading it as the latter is the mistake this
  section exists to prevent.
- **If who-corrected-what is ever required**, the answer is an actor on the
  append-only rating audit — which is where `Profiles_Table_Specification.md`
  §11.2 already directs the equivalent question for administrative rating
  adjustment — and `match_results` does not change.

Recorded as `MRS-R3`.

### 11.3 What the audit does not cover

**No history of results** (§2.4, `MRS-R4`). A corrected result leaves no record
of its previous score or MVP. That a correction occurred is inferable from the
rating audit and from `created_at ≠ updated_at`; *what it was* is not.

---

## 12. Dependencies

### 12.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `matches` | Identifying parent, cascading, **1 : 1** | Owns the scope, the lifetime, the authorization route and the lock |
| `users` | Two references — one cascading (MVP), one clearing (recorder) | Owns the people |
| **`match_team_assignments`** | **Not a foreign key — the strongest semantic dependency in the schema** | **A result cannot be recorded without it, cannot name an MVP outside it, cannot credit a goal outside it, and every figure it produces is computed over it.** §12.3 |
| `community_members` | Not a foreign key — authorization | Answers who may read and who may record |

### 12.2 Tables depending on this table

| Table | Dependency |
|---|---|
| `match_goals` | **By foreign key**, to the business key. Referenced only as a dependent entity |
| `rating_history` | By behaviour — every entry is produced by recording, and reversed by correcting |
| `player_statistics` | By behaviour — the six counters are applied and reversed by the same operation |
| Community Statistics and the Community Rating *(unbuilt)* | By behaviour — the same facts, scoped by community and period |
| Leaderboards *(unbuilt)* | Two derivations removed (§4.4) |

### 12.3 The unrepresented dependency

**The lineup is not referenced by any column here, and the dependency is
absolute.**

This is correct — a result is *of a match*, and the lineup is a separate record
of the same match — but it means the relationship is maintained by the
operation rather than by the schema. **Three consequences the specification
records:**

- **A result is valid only against the lineup as it stood when the result was
  recorded.** Nothing binds them afterwards.
- **`RR-7`'s lineup-edit limitation follows directly**: replacing a lineup after
  a result is recorded, then correcting the result, reverses counters against a
  set that never produced them. **Ratings are unaffected**, because they reverse
  from the append-only audit.
- **The dependency cannot be made a foreign key.** A lineup is many rows and is
  replaced wholesale; there is nothing single to point at. §12.3 of the lineup
  specification states the same from the other side.

---

## 13. Engineering Principles

The brief names seven. **Five have no textual definition in this repository**
— the ninth phase in which the absent *Database Principles* document has been
recorded. §13.3 onward states the reading applied, as the BTGE contract did, and
marks its basis. **If a reading differs from the approved definition, this
section is the defect.**

### 13.1 Match Aggregate Root Principle — **conforms**

Everything about the result hangs beneath the match: it is keyed 1 : 1 to it,
cascades with it, and resolves authority through the match's community. There
is no cross-match result and no aggregate above.

### 13.2 Match Row Lock Principle — **conforms, and it is the model**

**The recording operation locks the match row before anything else** — before
authorization, before validation, before any write.

This is worth emphasising because it is **the one place in the Match aggregate
where the discipline is fully observed on a table other than the roster**: the
lineup store does **not** take the lock (`BDC-R2`), and this operation does.

**Why it matters here specifically:** recording touches the result, the goals,
every participant's rating, every participant's audit entries and every
participant's counters. Without the lock, two simultaneous corrections could
each reverse the other's effects.

### 13.3 Business Transition Principle — **conforms**

*Reading applied: a state change happens only through the business operation
that owns it, never through a direct write reaching the same state by another
route.*

**There is exactly one route and no policy admits another** (§10.3). A result
cannot come into existence, change or disappear except through the operation —
which is why this table has no analogue of `MT-R1` or `TA-R3`.

### 13.4 Historical Identity Principle — **conforms, with the distinction in §2.4**

*Reading applied: a historical record states what happened, identified by the
entities that took part, never by the process that produced it.*

- **The rating audit is the historical record**, it is append-only, and a
  reversal is a new row naming what it undoes.
- **This row is not a historical record** — it is the current assertion, and
  §2.4 states the division explicitly rather than letting the two be conflated.
- Nothing about the recording process is stored: no engine, no version, no
  review, no draft.

### 13.5 Final Participation Principle — **conforms**

*Reading applied: participation is defined by exactly one record — the final
assignments — and every consumer resolves it there.*

The result **consumes** participation and does not define it: the MVP is
validated against the lineup, every scorer is validated against the lineup, and
the contribution arithmetic reads the lineup. **This row names one participant
and defines none.**

### 13.6 Single Business Path Principle — **conforms, and it is the clearest case in the schema**

*Reading applied: one business outcome has one code path.*

**Recording a result for the first time and correcting one are the same call**,
by explicit design — *"two functions would be two chances for them to drift"*,
and the correction path is the one that must never be weaker. The reversal steps
are skipped when there is nothing to reverse, which is the only difference
between the two cases.

### 13.7 Producer / Commit Separation Principle — **conforms, by not applying**

*Reading applied: where a component computes a candidate that a human may
accept or reject, computation and commitment must be separate steps.*

**This principle governs BTGE and deliberately does not govern results**, and
the contrast is instructive:

| | BTGE | Match Result |
|---|---|---|
| Who produces? | The engine — a **proposal** | A human — an **assertion** |
| May it be rejected? | **Yes.** The organiser may discard or adjust it | No. There is nothing to reject; the organiser is the author |
| Separation required? | **Yes** — generation writes nothing | **No — and separation would be a defect** |

**Why fusion is correct here.** A result's effects are *entailed* by the
result: ratings and counters are not a second decision but a consequence. A
result stored without them would be a result that did not count, and a separate
"apply" step would create exactly the draft state §2.5 refuses.

**So the principle is satisfied by correctly identifying that this is a commit,
not a producer.** Where a future *reviewer* is introduced (§14.1), a producer
appears — and separation would then apply to the review, not to the result.

---

## 14. Future Compatibility

### 14.1 VAR / referee review — supported, as a new entity, not a state here

A review is *an assertion about an assertion*: someone examines a recorded
result and confirms or changes it.

**What already works:** changing it is a correction, and correction is exact,
repeatable and fully reversing.

**What a review would add:** a record of *who reviewed, when, and with what
outcome* — which is **an append-only review record referencing the match**, not
a status column here.

**Why not a status column.** A `reviewed` or `under_review` flag on this row
would be mutable state about a process, which §13.4 refuses; and a
`pending_review` state would be the draft §2.5 refuses. **The result stays the
current truth; the review is a separate history.**

**No change to this table.**

### 14.2 Multiple result reviewers — supported by the same entity

Several reviewers are several rows in that same append-only record. **This
table would still hold one current result** — which is the point: a result is
what it is now, and who agreed with it is a different fact.

**`recorded_by` must not be pressed into service** as a reviewer list; it is a
single last-writer column (§11.2) and would be wrong for this in two ways at
once.

### 14.3 Tournament results — supported; the addition is elsewhere

A tournament needs a match to belong to a stage or a group, and standings to
aggregate over results. **Both are properties of the match or of a new
tournament entity, not of the result.**

**What stays true:** two scores and an MVP describe a tournament match exactly
as they describe a friendly. **What would need care** is that a tournament's
standings are a *derived* figure and must be computed from results in a
statistics-shaped record, never by scanning this table (§4.4, §9.2).

### 14.4 Penalty shootouts — the one future needing columns here, and they are additive

A shootout is a **second, subordinate score** that decides a tie without
changing the match score. It cannot be folded into the existing columns: a 3–3
draw decided 5–4 on penalties is not an 8–7 result, and recording it as one
would corrupt the goals-sum rule and every scorer's tally.

**Shape:** two nullable columns for the shootout scores, null meaning *no
shootout*. **Additive**, and the constraints that follow are stated so the
future phase does not rediscover them:

- Non-null only when the match scores are **equal** — a shootout resolves a
  draw and nothing else.
- **Excluded from `MRS-C12`.** Shootout goals are not match goals and must not
  enter the sum, or every scorer's rating would move for them.
- **The winner derivation changes** (§3.3): with a shootout present, the winner
  is its comparison rather than the scores'. **How the rating engine should
  treat a shootout win is a Product Decision** — a shootout is conventionally
  not a win in football's own statistics — and this table would only record it.

### 14.5 Extra time — probably no change at all

Extra time changes *when* goals were scored, not *what* the result was. The
score is the score after extra time, and the goals are all the goals.

**A column would be needed only if the product wanted to report the score at 90
minutes separately** — which no approved document asks for, and which would be
a second score with the same ambiguity a shootout has.

### 14.6 The general rule

> **A new column on `match_results` must be part of the assertion about what
> happened, must not be a derived figure, must not be a state about a process,
> and must not be a second score that competes with the first.**

---

## 15. Engineering Rationale

### 15.1 The assertion is one row; everything else is arithmetic

§4. The result is the only thing in the chain a human authors, and the only
thing that can be wrong in a way that requires a human to fix. Every layer below
is a function of it — which is what makes correction tractable at all.

### 15.2 One operation, because the correction path must never be weaker

Recording and correcting share every rule because they are the same act with a
different starting state. Two operations would drift, and the one that would
drift into weakness is the one that runs less often — correction — which is
also the one whose failure is hardest to detect.

### 15.3 Validate everything, then disturb nothing until it passes

§7.3. Correction unwinds the previous result before storing the new one, so a
check that ran after the unwinding would be able to leave a match with reversed
ratings and no result. Every check runs first.

### 15.4 Exactly one MVP is a shape, not a rule

§5.3. A NOT NULL column on a row that is unique per match makes *two MVPs* and
*no MVP* unrepresentable. No check constraint could achieve either, and a
separate MVP table would need two rules to achieve both.

### 15.5 The winner is not stored, for the same reason out-of-position is not

§3.3. A derived value stored beside what it derives from invites the two to
disagree. This schema has refused that twice now, and both refusals came from
the same argument.

---

## 16. Engineering Review

**Six findings.**

### 16.1 Ownership violations — none

**No client can write this table by any route**, and no column belongs to
anyone but the recording operation. Recording moves other people's ratings, and
the write model reflects that. **This table has no analogue of `CM-R2`,
`MT-R1` or `TA-R3`** — the first table in the phase where there is simply
nothing to withdraw.

### 16.2 Duplicate responsibilities — none

No figure is stored here, and no fact held here is duplicated elsewhere. The
winner is derived; the participants are the lineup's; the goals are their own
table; the counters and ratings are computed and stored where they belong.
`RR-6`'s discipline — no second answer to the same question — holds throughout.

### 16.3 History violations — one, and it is a boundary rather than a breach

**The rating audit is never mutated** — `RR-5` holds in full, enforced three
ways.

**But the result row itself is upserted**, so there is no history of results
(§2.4). A corrected result leaves no record of its previous score or MVP.

**Assessment: correct as designed, and recorded as a boundary.** The row is the
current assertion, not a historical record, and keeping superseded scores would
create a second answer with no rule for choosing. No approved document asks for
result history. `MRS-R4`.

### 16.4 Immutability risks — one, and it is the High

**The reversal discipline is exact and well-proven** — verified over 100
contaminated results recovered through the fixed path, returning four accounts
to exactly their baseline including two that had been clamped at the ceiling.

**The risk is not to the discipline but around it:** two paths remove a result
without running the reversal.

| Path | Reverses? | Status |
|---|---|---|
| Deleting the **match** | **Yes** — trigger fires first | Correct |
| Deleting the **MVP's account** | **No** | **`MRS-R1`, High** — §6.4 |
| Replacing the **lineup** after recording | n/a — the result survives, but a later correction reverses against the wrong set | `RR-7`, known, not approved for work |

### 16.5 Database consistency risks — the unrepresented lineup dependency

§12.3. The strongest dependency in the schema is carried by an operation rather
than by a constraint, and it cannot be otherwise — a lineup is many rows,
replaced wholesale, with nothing single to reference.

**Assessment: unavoidable, and the mitigation is elsewhere** — validating the
lineup's contents against the confirmed roster (`TA-R1` / `BDC-R4`) is what
makes the participants this table validates against trustworthy in the first
place.

### 16.6 A consistency risk this table shares with nothing else — the team letter

`team_a_score` binds to the lineup rows marked `A` **by convention only**.
Nothing structural connects the letter in one table to the letter in the other,
and nothing would detect a consumer that inverted them.

**Assessment: acceptable, and recorded.** Both vocabularies are two-valued,
fixed, and read by one arithmetic helper. The risk is a coding error in one
place, not a data model weakness. `MRS-R5`.

### 16.7 Summary

| Finding | Verdict |
|---|---|
| Ownership violations | **None** — the model table |
| Duplicate responsibilities | **None** |
| History violations | **None**; one recorded boundary, `MRS-R4` |
| Immutability risks | **One High** — `MRS-R1`, the MVP cascade |
| Database consistency | The unrepresented lineup dependency — **unavoidable**, mitigated elsewhere |
| Team-letter convention | **Acceptable**, recorded as `MRS-R5` |

**No approved product behaviour is redesigned by any of the above.**

---

## 17. Validation

**Contradictions are named, not resolved silently.**

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction; one limitation's mechanism named** | `RR-1` (precision), `RR-2` (the select-only write model), `RR-4` (apply and reverse are separate statements), `RR-5` (the audit is append-only), `RR-6` (Level 1 is global) all hold. **`RR-7`'s MVP-deletion limitation is recorded there as known; §6.4 names the column that causes it and rates it High** — a change of severity assessment, not of fact |
| 2 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction** | `A4` — statistics arise only from a recorded result — is §4.2. `SL-2` §2.3's prohibition on boards reading Level 1 extends to reading results directly (§4.4) |
| 3 | `BTGE_Database_Contract.md` v1.0 | **No contradiction** | Its §6.2 forbids BTGE writing this table; §10.3 here confirms nothing but the recording operation writes it. Its §9.4 relationship with results is §12.3 here, from the other side |
| 4 | `BTGE_Engineering_Specification.md` v1.5 | **No contradiction** | No engine output reaches this table, and no result reaches the engine |
| 5 | `Matches_Table_Specification.md` v1.0 | **No contradiction** | Its §6.4 — deleting a match reverses what it caused — is §5.5 here. Its §14.2 confirms no result state is mirrored onto the match |
| 6 | `Match_Registrations_Table_Specification.md` v1.0 | **No contradiction** | Its §14.3 states this table is not in the results path — participation comes from the lineup, never from registrations. Confirmed by `MRS-C9`–`MRS-C11` |
| 7 | `Match_Team_Assignments_Table_Specification.md` v1.0 | **No contradiction; one dependency confirmed** | Its §4.2 — why assignments are authoritative for results — is §4.1 and §12.1 here. Its `TA-R1` is what makes §12.3's mitigation necessary |
| 8 | `Docs/06-ERD.md` | **No contradiction** | §2: *"a match has at most one result, and a result names exactly one MVP. Goals reference the result, not the match. Deleting a match reverses the ratings and counters it produced before its children cascade away"* — §5.3, §8.4 and §5.5 respectively |
| 9 | `Docs/01-PRD.md` | **No contradiction** | *Record match results: score, goal scorers and the MVP* is exactly this table plus its child. The role matrix places match management with admin and owner |
| 10 | `Docs/10-Design-Decisions.md` | **No contradiction** | `DD-07` (time-independent deletion), `PD-07`, `PD-16` hold. `SL-1`…`SL-5` are downstream |
| 11 | **Database Principles** | **No artifact in the repository** | **Ninth phase.** Five of the seven principles §13 validates against have no definition here; §13 states the reading applied for each and marks its basis. **If a reading differs from the approved definition, §13 is the defect** |
| 12 | `Docs/07-Database-Design.md` | **No contradiction** | *"All four are written only by `record_match_result` and carry select policies and nothing else"* — §10.3. **Standards satisfied in full** |
| 13 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **No contradiction** | §4's checklist is satisfied in full: RLS enabled, access explicit (select policy, deliberately no write policies), authorization via the community-role predicate inside a `SECURITY DEFINER` function with a pinned `search_path`, not broadly readable |

### 17.1 The one assessment that differs from an approved document

`RR-7` records the MVP-deletion cascade as a **known limitation**, alongside
the observation that deleting a user is *"an administrative, already-destructive
operation whose existing semantics remove everything they hold."*

**This specification rates the same mechanism High** (§6.4, `MRS-R1`), on a
ground `RR-7` does not address: **what is destroyed is not only what the deleted
user holds.** Every *other* participant's career counters and rating changes
survive a result that no longer exists, and there is no path to recover them.

**Not a contradiction of fact — a difference of severity assessment**, stated
openly so the Product Owner can settle it (`MRS-D1`).

---

## 18. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `MRS-R1` | **Deleting the MVP's account destroys the entire result without reversing it.** Every other participant keeps ratings and counters for a result that no longer exists, unrecoverably. The cascade choice on `mvp_user_id` is the sole cause, and the opposite choice was made deliberately one column away on `recorded_by` | **High** | **Open**, §19 item 1. `RR-7` records the mechanism as known; §17.1 states why this rates it higher |
| `MRS-R3` | **`recorded_by` is a last-writer column presented as attribution.** After one correction the original recorder is unrecoverable — here, in the rating audit, and everywhere else | Low | **Open.** Fix is documentary unless who-corrected-what becomes a requirement (§11.2) |
| `MRS-R4` | **No history of results.** A corrected result leaves no record of its previous score or MVP | Low | **Accepted as a boundary** (§2.4, §16.3). No approved document asks for it |
| `MRS-R5` | **The team letter binds to the lineup by convention only.** Nothing structural connects `team_a_score` to the lineup rows marked `A` | Low | **Accepted** (§16.6). Two fixed vocabularies read by one helper |
| `MRS-R6` | **A result may be recorded for a match that has not been played** | Low | **Accepted** — `RR-7 A4`, §3.4. A recorded asymmetry, not an oversight |
| `MRS-R7` | **A lineup replaced after recording makes a later correction reverse against the wrong set.** Ratings are immune; counters are not | Medium | **Inherited from `RR-7`, known, not approved for work.** Belongs to the lineup, surfaces here |
| `MRS-R8` | **No index on `mvp_user_id`**, which carries a cascade | Low | **Accepted for now** (§9.2). Becomes the first index to add if the table grows or the cascade is retained |

---

## 19. Open Decisions

| ID | Question | Recommendation |
|---|---|---|
| `MRS-D1` | **What should happen when the MVP's account is deleted?** | **Refuse the cascade and handle it in the administrative deletion path** — reverse the result explicitly, as deleting a match already does, before removing the account. This preserves other participants' figures, which is the whole of the problem. **`SET NULL` is not available** without giving up the NOT NULL guarantee in §5.3, and silently destroying the result is what the current choice does |
| `MRS-D2` | **Is who-corrected-what ever required?** | **Not for the MVP.** If it becomes required, the answer is an actor on the append-only rating audit — not `updated_by` here, and not overloading `recorded_by` (§11.2) |
| `MRS-D3` | **Should a result be refused for a match that has not finished?** | **A Product Decision, and `RR-7 A4` already recorded it as deliberately out of the database's scope.** Engineering has no position beyond noting the asymmetry is known |
| `MRS-D4` | **Do the seven principles in §13 match their approved definitions?** | **Confirm.** Five are stated readings. The same request as `BDC-D4`, and the two should be answered together |

---

## 20. Conformance

| # | Deviation | Required by | Severity | Notes for the implementing phase |
|---|---|---|---|---|
| 1 | **`mvp_user_id` cascades, destroying a result with no reversal** | §6.4 | **High** | Settle `MRS-D1`. If the cascade becomes a refusal, the administrative account-deletion path must reverse and remove affected results before deleting the account — the ordering discipline it already applies to communities, memberships and matches |
| 2 | **`recorded_by`'s semantics are undocumented in the schema** | §11.2 | Low | Documentary. The column is correct; the reading of it is what misleads |

**Everything else conforms.** The structure, the business key, the unique
1 : 1 to the match, all four checks, the three foreign keys' *intent*, the sole
index, the select-only access model, both audit timestamps, the single write
path, the validate-then-write ordering and the match row lock are exactly as
specified.

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched.

---

## 21. Engineering Approval

**Status: Engineering Approved — conditional.**

This document is the authoritative engineering specification for
`public.match_results`. It is **conditional** on §20 item 1.

**A note on the shape of the findings.** This is the first table in the phase
with **no ownership violation, no duplicate responsibility and no second write
path** — its access model is the one the rest of the schema is being corrected
towards. Its single serious defect is not in what may be written but in **what
happens when something else is deleted**.

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5` | ✓ |
| Business purpose, business owner, domain ownership, lifecycle ownership | ✓ §1, all four |
| **Complete lifecycle** — five valid transitions, eleven invalid, **and why correction reverses rather than mutating**, with the row/audit distinction stated explicitly | ✓ §2 |
| **Business responsibilities** — owned and not owned, including the derived winner and the absent publication event | ✓ §3 |
| **Result model** — why it is the source of truth; why statistics, ratings and leaderboards never own results | ✓ §4, all four |
| Relationships: incoming, outgoing, ownership, deletion, lifecycle | ✓ §5 |
| Every column — name, purpose, type, nullability, default, editability, justification | ✓ 8 of 8 |
| Every business constraint with its reason | ✓ 16 |
| Keys: primary, **business key**, candidate, alternate — **including the one that is a foreign-key target** | ✓ §8 |
| Index strategy: one required index, one candidate named | ✓ §9 |
| Access control: organizer, admin, member, player, non-member, System Administrator × read/record/correct/delete/publish | ✓ §10, with *organizer* shown not to be a role |
| Audit: all four columns ruled on | ✓ §11 |
| Dependencies both directions, including the unrepresented one | ✓ §12 |
| **Seven engineering principles**, each validated with the reading applied and its basis marked | ✓ §13 |
| **Future compatibility**: VAR/review, multiple reviewers, tournaments, shootouts, extra time | ✓ §14, five of five |
| **Engineering review** — ownership, duplication, history, immutability, consistency | ✓ §16, six findings |
| Validation; contradictions named, not resolved | ✓ 13 sources, **1 severity difference named** |
| No SQL, no migration, no goals, no statistics, no ratings, no other table designed | ✓ |

### Validation caveat, stated rather than glossed

The brief names *Database Principles* as a validation source. **It does not
exist as a document in this repository** — the ninth phase in which this has
been recorded. Five of the seven principles §13 validates against have no
definition here; §13 states the reading applied for each. `MRS-D4` asks for
confirmation, together with `BDC-D4`.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Results_Rating_Engineering_Decisions.md` | **`RR-1` … `RR-7`.** `RR-2` established this table's write model; `RR-7`'s MVP limitation is `MRS-R1`, rated higher here (§17.1) |
| `engineering/Match_Team_Assignments_Table_Specification.md` | **The participant source.** Its §4.2 is this document's §4.1 from the other side; its `TA-R1` is why §12.3's mitigation matters |
| `engineering/Matches_Table_Specification.md` | The aggregate root; its §6.4 reversal-on-delete is this table's safe cascade |
| `engineering/Match_Registrations_Table_Specification.md` | Confirms registrations are **not** in the results path |
| `engineering/BTGE_Database_Contract.md` | §6.2 forbids BTGE writing this table; `BDC-D4` is `MRS-D4` |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | `A4`; `SL-2` §2.3 — boards never read this layer |
| `engineering/Profiles_Table_Specification.md` | `UP-4` (applied in §11.2); the rating column this table's effects move |
| `Docs/06-ERD.md` | §2 — one result, one MVP, goals reference the result, deletion reverses first |
| `Docs/01-PRD.md` | *Record match results: score, goal scorers and the MVP* |
| `Docs/07-Database-Design.md` | *"written only by `record_match_result` and carry select policies and nothing else"*; **Standards satisfied in full** |
