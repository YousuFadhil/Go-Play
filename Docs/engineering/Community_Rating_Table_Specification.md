# Community Rating (`community_ratings`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** Two build conditions; see §19 and §21 |
| Role | **Engineering Authority** for the physical table `public.community_ratings` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Level 2 |
| Scope | **`public.community_ratings` only.** Community Rating History and leaderboards appear **only as dependent or sibling entities** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-02 |

> **This table does not exist.** Level 2 is approved and unbuilt, so this is a
> **greenfield specification**: every column, key, index, constraint and access
> rule below is a design decision taken here.
>
> **It contains no SQL, no migration and no implementation**, and it designs no
> Community Rating History and no leaderboards.
>
> **It includes the dedicated review of the Community Rating as an independent
> engineering entity** (§4), covering all twelve points requested, and a
> conformance statement against `SL-1`…`SL-5`, `RR-1`, `RR-2`, `RR-5` and
> `RR-6` (§13).
>
> **Sibling authorities.** The thirteen table specifications, the BTGE database
> contract and the three engineering authorities, listed in *Related
> documents*.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Community Rating** — entity `E8` in the conceptual model |
| **Physical table** | **`community_ratings`** |

**One row is one player's rating in one community.** Not a period, not a
history, not a counter.

**Two naming points, settled here so they are not rediscovered:**

- **The physical name is plural**, following `communities`, `matches` and
  `match_results`. The logical entity is singular, as everywhere.
- **This document's filename is singular** (`Community_Rating_...`). As settled
  for the User Profile specification, **`UP-5` governs the entity name and the
  table name; a repository filename is neither.**

---

## 1. Purpose

### 1.1 Business purpose

A Community Rating record answers: **how good is this player *in this
community*?**

It exists because the Global Rating cannot answer that question and must not be
made to. A career rating is the sum of everything a player has done everywhere,
and `SL-4` §4.1 states the failure directly: *"a newcomer with a `9.20` career
rating would otherwise top the board before kicking a ball there."*

**So the product needs a second, independent rating** — one that starts everyone
level, moves only on what happens inside one community, and is therefore a
record of *what happened there*.

**Its consumers are two, and both are community-scoped:**

1. **The *Highest Rated* leaderboard**, in all three periods — which ranks by
   this value and **never** by the Global Rating (`SL-5`).
2. **The Community Dashboard**, if it ever displays a rating — a
   forward-looking permission, not a current reader (§10.2).

### 1.2 Business owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That the record exists** | **The system**, on the player's **first ever join** of that community | The join path (§2.2) |
| **The rating value** | **The system, exclusively** | The rating path, inside the recording operation |
| `community_id`, `user_id`, `created_at` | The database | Nothing writes them after insert |

**No person owns the value, and no person may set it.** `RR-2` settled that a
rating is system-managed and no client may write one; `SL-3` §3.5 extends that
rule to this rating explicitly — *"`SL-3` introduces a second rating, not a
second writer."*

### 1.3 Domain ownership

**Domain: Statistics. Position: a sibling of `community_statistics`, scoped by
the Community aggregate but not inside it.**

| Property | Value |
|---|---|
| Aggregate | **None.** Not in the Match aggregate; not beneath the Community root in the ownership sense |
| Depends on | `users` and `communities` structurally; the result, lineup and its own history semantically |
| Depended on by | The *Highest Rated* board, by behaviour; **nothing** by foreign key |
| Community-scoped | **Yes** — it is half the identity |
| Period-scoped | **No, and must never be** (§4.3) |
| Contains authorization | **No** |

**It belongs to the player and the community jointly** — ERD §3.4 — and to
neither alone. That joint ownership is what `SL-4` requires and what §4.7 and
§4.8 protect.

### 1.4 Lifecycle ownership

| Bounded by | Consequence |
|---|---|
| **The community** | **Absolutely.** *"A deleted community takes its statistics with it"* (`A7`) |
| **The player's account** | **Absolutely.** *"A deleted player does the same"* |
| **NOT the membership** | **`SL-4` and `A7`.** Preserved on departure, resumed on return. **It must never cascade from `community_members`** |
| **NOT any match** | Matches move it; they do not bound it |
| **NOT the clock** | Never reset, never rolled over, **never re-baselined** |

---

## 2. Lifecycle

### 2.1 The shape

```
  Player joins the community  (FIRST JOIN ONLY)
            │
            ▼
  RATING CREATED at 5.00 ──── the neutral baseline, NOT the Global Rating
            │
            │  a result is recorded for a match in THIS community
            ▼
  PROGRESSING ── +0.10 win / −0.10 loss / +0.05 per goal / +0.20 MVP
            │     clamped to 0.00 … 10.00, every movement audited in E9
            │
            ├── result corrected ──▶ reversed by the APPLIED delta, then re-applied
            ├── match deleted     ──▶ reversed
            │
            ▼
  Player LEAVES the community
            │
            ▼
  PRESERVED ── the value is untouched. No reset, no flag, no deletion.
  INELIGIBLE ── evaluated at read time, stored nowhere
            │
            ▼
  Player REJOINS
            │
            ▼
  RESUMED ── the same record, the same value, progression continues
```

### 2.2 Transition 1 — first join: created at 5.00

| Property | Value |
|---|---|
| When | **First join only** — `SL-4` |
| Value | **`5.00`**, the neutral baseline |
| Source of the value | **A constant.** Never the Global Rating, never a rating from another community (`A5`) |
| On rejoin | **Nothing.** The record exists and is reused (§2.6) |

**Three consequences the implementing phase must handle**, identical in shape to
those the Community Statistics specification records, and now doubled because
**the join path writes two Level 2 tables**:

| # | Consequence |
|---|---|
| 1 | **The join paths acquire a second statistics-domain write.** Joining by code, joining an open community, and creating a community all write here as well as to `community_statistics` |
| 2 | **Creation must be idempotent.** A rejoin must find, never insert — otherwise `SL-4`'s "never reset" is violated by the mechanism meant to honour it |
| 3 | **Existing memberships must be backfilled** — and **at what value is a real decision**, not a detail. §19.2, `CR-D2` |

### 2.3 Transition 2 — progression

The rating moves **only** when a result is recorded for a match **in this
community**, by the approved engine:

| Event | Delta |
|---|---|
| The player's side won | `+0.10` |
| The player's side lost | `−0.10` |
| Goals credited | `+0.05` each |
| Named MVP | `+0.20` |

**Clamped to `0.00 … 10.00`**, and **every movement is recorded in the Community
Rating History with the delta that was *applied*** — §4.4.

**A drawn match moves nothing** for the outcome, exactly as at Level 1: the
counters record a draw, the rating does not move for it.

### 2.4 Transition 3 — correction

Reverse by the **applied** delta from the history, newest first; then apply the
new result's deltas. **Identical in mechanism to the Global Rating**, and for
the identical reason (§4.4).

### 2.5 Transition 4 — departure: preserved

**Nothing is deleted, no value is altered, and no flag is written.**

What changes is **eligibility**, evaluated when a board is read (`SL-4` §4.2).
The record *"continues to exist; it simply stops being displayed and stops
accruing, since they can no longer play a match there."*

### 2.6 Transition 5 — rejoin: resumed

**The same record, the same value, progression continuing.** No new baseline
(`SL-4` §4.3).

**Why this is not merely convenient but required:** `SL-4` §4.4 states the
attack it prevents — *"if leaving and rejoining returned a player to `5.00`, any
player whose rating had fallen could clear it by leaving and coming back."*
**Preservation removes the incentive entirely**, and the mechanism that
guarantees it is the key: the record is identified by `(player, community)`,
which contains no membership reference to have changed.

### 2.7 Transition 6 — the account or the community is deleted

| Deleted | Effect |
|---|---|
| The player's account | Every rating of theirs, in every community, cascades |
| The community | Every rating in it cascades |
| **A membership** | **Nothing** — `A7` |

### 2.8 Invalid transitions

| Invalid | Why | Refused by |
|---|---|---|
| Two ratings for one player in one community | The community's answer to *how good is this player* would be ambiguous | **The primary key** (`CR-C1`) |
| A rating created on rejoin | `SL-4`: created once, ever | Idempotent creation (`CR-C8`) |
| A rating reset on rejoin | `SL-4` §4.4 — it would be gameable | Nothing resets it; no operation exists |
| A rating seeded from the Global Rating | `A5`, `SL-4` §4.1 | The default is a constant |
| A rating deleted on departure | `SL-4` §4.2 | No operation deletes one |
| A rating cascading from a membership | **`A7`** | **No foreign key to `community_members`** |
| A rating moved by a match in another community | The isolation rule (§4.6) | The community is taken from the match |
| A rating outside `0.00 … 10.00` | The approved `OP-1` scale | `CR-C5`, and the clamp |
| A **manual edit** | `RR-2` — no client may write a rating | **No write access** (§10.3) |
| A period on this record | `SL-5`, ERD §3.2 | **No such column** (§4.3) |

---

## 3. Responsibilities

### 3.1 What this table owns

| # | Responsibility | How expressed |
|---|---|---|
| 1 | **The player's current standing in one community** | `rating` |
| 2 | **That the standing exists at all** — the "created once, ever" fact | The row's existence |
| 3 | **When it began** | `created_at` — the player's first-ever join of this community |
| 4 | **Isolation between communities** | Structurally, by the leading key column |
| 5 | **The measure the *Highest Rated* board ranks by** | `rating`, read as the **current** value in every period (`SL-5`) |

### 3.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **Any counter** | `community_statistics` | A rating is not a counter (`SL-5`) — §4.3 |
| 2 | **The period dimension** | `community_statistics` | §4.3 |
| 3 | **The history of its own movements** | **Community Rating History (`E9`)** | §4.5 — and without it, correction cannot be exact |
| 4 | **The Global Rating** | `users.overall_rating` | §4.2 |
| 5 | **Eligibility** | `community_members`, at read time | §2.5 |
| 6 | **The board** | Derived | Rank, depth and tie-break are read-time |
| 7 | **The evidence** | Result, goals, lineup | It is two derivations away from them |

---

## 4. The Community Rating as an independent entity — dedicated review

**Twelve points, as requested.**

### 4.1 Relationship with the Global Rating — independent, and one observation worth raising

**`SL-3` is unambiguous:** *"**Independent** is the operative word. Neither
rating is derived from the other, neither is a view of the other, and the two
are expected to differ."*

| | Global Rating | Community Rating |
|---|---|---|
| Where | `users.overall_rating` | Here |
| Cardinality | One per player | One per player **per community** |
| Moved by | **Every** completed match, in any community | **Only** matches in this community |
| Starts at | `5.00` | `5.00` — the same constant, separately applied |
| Read by | **The Player Profile only** | **The Dashboard and the Leaderboards only** |
| History | `rating_history` (`E6`) — built | Community Rating History (`E9`) — **required, unbuilt** |

**Neither is reconcilable arithmetic.** A Global Rating is not the sum, mean or
any function of a player's Community Ratings, and `A5` forbids the reverse
seeding.

**The observation, raised rather than resolved.** The Balanced Team Generation
Engine reads **`users.overall_rating`** as a Core Player Input — the *Global*
Rating — including when generating teams for a community match. So inside one
community, at one moment, **two different numbers answer "how good is this
player"**: the Global Rating balances the sides, and the Community Rating ranks
the board.

**This is consistent with every approved document.** `KB-006` fixes the Core
Player Inputs at four with Overall Rating among them; no approved document says
BTGE should use a community rating; and `SL-3` expects the two to differ.

**It is nonetheless a real product-visible asymmetry** — a player new to a
strong community is balanced as an 8.0 and ranked as a 5.0 — and changing it
would be a Knowledge Base decision about the engine's inputs, not a schema
change. **Recorded as `CR-R1`, an observation, not a defect.**

### 4.2 Relationship with Community Statistics — siblings, never parent and child

**Both are Level 2. Neither derives from the other** (DP-10, approved context
items 5 and 6 of the statistics phase).

| | `community_statistics` | This table |
|---|---|---|
| Identified by | player + community + **period** | player + community |
| Cardinality | **Several** per pair | **Exactly one** per pair |
| Kind of number | Accumulating counters | A running value |
| Starts at | Zero | **`5.00`** |
| Created | `overall` at join; periodic on first play | **At join** |

**They are created at the same moment by the same operation and are still two
entities**, because their cardinality differs by a whole dimension. §4.3 is why.

**Neither reads the other.** A board that ranks by rating and filters by
"played in the window" reads both — but as two independent sources, not as one
computed from the other.

### 4.3 Why there is no period on this record

**`SL-5` settles it, and ERD §3.2 states it as an entity property:**

> *"A counter accumulates inside a window; a rating is a running value that has
> no natural zero and does not restart."*

**The consequence for the boards:** *Overall*, *Weekly* and *Monthly* Highest
Rated are **three boards, not three stored ratings**. The rating shown is always
the **current** one; **the period selects who is eligible to appear**, never
which value is displayed.

**So a period column here would be duplicated across every period of every
pair**, each copy free to disagree — which is exactly the error the statistics
specification's §14 readiness row contained until it was corrected on
2026-08-02.

### 4.4 Precision and the correction workflow

**`RR-1` applies unchanged.** `numeric(4,2)`, matching `users.overall_rating`
exactly.

**Why the precision is not negotiable here either:** the engine moves a rating
by `0.05` for a goal, which one decimal place cannot represent; and **rounding
is not invertible**, so a rounded reversal leaves a rating the player never
held.

**The correction workflow is `RR-5`'s, applied to Level 2:**

| Step | |
|---|---|
| 1 | Reverse each in-effect movement **by the delta that was applied**, newest first |
| 2 | Apply the new result's movements |

**Newest-first is load-bearing**, for the identical reason as at Level 1:
stepping back through states the player genuinely occupied means **no clamp can
fire on the way out**.

**And this is the dependency that makes §4.5 a build condition**: reversing by
the applied delta requires a record of what was applied, and that record is
`E9`.

### 4.5 Relationship with the Community Rating History — required, and a build condition

**`E9` is required and has no MVP reader.** `SL-4` §4.5: *"it exists for the
same reason the global audit does: a corrected result must reverse exactly, and
reversal is only exact when the applied delta is recorded… It has **no reader in
the MVP** — no screen displays it — but it is not optional."*

**The relationship is exactly `users.overall_rating` ↔ `rating_history`:** this
table holds the current value; `E9` holds every change. Neither can substitute
for the other — the current value cannot reconstruct the history, and the
history is what makes a correction exact.

> **Building this table without `E9` produces a rating that cannot be corrected
> exactly.** They must be built together. §19.1, `CR-D1`.

**The template `E9` should inherit** is recorded in
`Rating_History_Table_Specification.md` §4.10 and is not restated here.

### 4.6 Community isolation

**`SL-2` §2.2 makes isolation normative**, and `community_id` is what makes it
*a property of the model rather than a discipline expected of each query*.

**Expressed three ways in this design:**

| # | |
|---|---|
| 1 | `community_id` is **the leading column of the primary key** — a record cannot exist outside a community |
| 2 | **The community is taken from the match**, never supplied by a caller (`CR-C11`) — isolation cannot be a parameter |
| 3 | The worked example holds: a match in Community A moves the Global Rating and A's Community Rating. **Community B's rating for that player does not move**, in any period |

### 4.7 Leaving a community

**Nothing is deleted, nothing is altered, no flag is written** (§2.5).

**Eligibility is a read-time filter over `community_members`** — never stored
here. Three reasons, and the third is specific to a rating:

1. A stored flag would need writing on every join and departure.
2. It would be a second answer to a question `community_members` answers.
3. **A rating has no period to scope a flag to.** "Is a member now" is a fact
   about the present; the rating is a running value with no window. A flag would
   have to mean *"currently displayable"*, which is a property of the reader's
   question, not of the record.

### 4.8 Rejoining a community

**The same record resumes** (§2.6). The key contains no membership reference, so
nothing about a departure or a return can affect the record's identity.

**`SL-4` §4.4's anti-gaming argument is what makes this mandatory rather than
merely tidy**, and it is worth stating as a design property: **the only way to
guarantee a rating cannot be cleared by leaving is for departure to touch
nothing at all.**

### 4.9 The read model

**Community members only** — §10.2. Specified this way from the start,
explicitly applying the lesson of `PS-R1`, where Level 1's unscoped read permits
enumeration `UP-1` forbids.

**Two approved constraints shape it:**

- **`SL-3` §3.3:** *Highest Rated* must use this rating; the Player Profile
  always displays the **Global** Rating.
- **The PRD places *displaying a Community Rating on the Player Profile* out of
  scope.**

**So there is no screen on which a departed player would see their preserved
rating** — and therefore, unlike `rating_history` (`RH-R1`), **community-scoped
reads here contradict nothing.** §17 confirms it.

### 4.10 The write model

**`RR-2`, extended by `SL-3` §3.5 to this rating explicitly.**

| | |
|---|---|
| Client writes | **None.** No write policy of any kind |
| Writers | **Two system paths**: the join path creates at `5.00`; the rating path moves it |
| Where | Inside the recording operation's transaction, under the match row lock |
| Paired with | **An `E9` entry, in the same statement flow** — so a rating that moved without an audit entry is unreachable |

**The pairing is the strongest integrity property either table has**, and it is
the property `apply_rating_delta` already gives the Global Rating.

### 4.11 Initialization and progression — summary

| | |
|---|---|
| **Initialization** | `5.00`, at first join, from a constant. Never the Global Rating, never another community's (`A5`, `SL-4` §4.1) |
| **Progression** | Only by results in this community, by the approved engine, clamped, audited |

### 4.12 Review summary

| Point | Verdict |
|---|---|
| Global Rating | **Independent.** One observation raised — `CR-R1` |
| Community Statistics | **Sibling.** Cardinality differs by a dimension |
| Community Rating History | **Required — and a build condition**, `CR-D1` |
| Initialization (`5.00`) | **Sound** |
| Progression | **Sound** |
| Community isolation | **Sound**, expressed three ways |
| Leaving | **Sound** |
| Rejoining | **Sound**, and the key is what guarantees it |
| Correction workflow | **Sound**, and dependent on `E9` |
| Precision | **Sound** — `RR-1` unchanged |
| Read model | **Specified correctly from the start** |
| Write model | **Sound** — `RR-2` extended |

---

## 5. Relationships

### 5.1 Incoming

**None, and none may be added.**

**Community Rating History (`E9`) must reference `users` and `communities`
independently**, not this row — mirroring `rating_history`, which references the
player and the match rather than the rating it audits. The reasons are the same:
an audit entry is a fact about a moment, and binding it to the current-value row
would couple a permanent record to a mutable one.

### 5.2 Outgoing

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `communities` | `community_id` | many : 1 | **`CASCADE`** | **Identifying** — `A7` |
| `users` | `user_id` | many : 1 | **`CASCADE`** | **Identifying** |

**Exactly two — and the third that must never exist:**

> **No foreign key to `community_members`, ever** (`CR-C10`, `A7`).

### 5.3 Ownership

| Question | Answer |
|---|---|
| **Who owns the meaning?** | **The player and the community, jointly** — ERD §3.4 |
| **Can it be reparented?** | **No.** Both key columns are immutable |
| **Does the community know its ratings?** | **No stored aggregate.** A community-average rating would be a figure nothing asked for and nothing could reverse |
| **Does the player's profile know?** | **No, and it must not display one** — PRD, out of scope |

### 5.4 Deletion behaviour

| Path | Effect | Assessment |
|---|---|---|
| **Community deleted** | Cascade | **Correct.** Note the ordering: deleting a community deletes its matches, which reverses their results first — so ratings are decremented and then removed. Harmless, and must not be "optimised" without re-examining the reversal |
| **Account deleted** | Cascade | **Correct**, with the inherited exposure: where the deleted account was a match's MVP or scorer, the result vanishes without reversing (`MRS-R1`, `MG-R1`), leaving other players' community ratings holding movements whose cause is gone |
| **Membership deleted** | **Nothing** | **`A7`. The defining negative** |
| **Match deleted** | Reversed, then the record remains | **Correct** |
| **Directly** | **No path exists** | **Correct** |

### 5.5 Lifecycle

| Relationship | Whose lifetime bounds whose |
|---|---|
| `communities` → record | **Absolutely** |
| `users` → record | **Absolutely** |
| **`community_members` → record** | **Neither. This is `SL-4`** |
| Matches → record | **None.** They move it; the record outlives them all |
| Record → `E9` | **Neither structurally.** They are written together and neither references the other |

---

## 6. Columns

**Five columns.** The smallest Level 2 table, and deliberately so.

### 6.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `community_id` | `uuid` | No | none | **Never** |
| 2 | `user_id` | `uuid` | No | none | **Never** |
| 3 | `rating` | `numeric(4,2)` | No | **`5.00`** | **System only** |
| 4 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| 5 | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** |

**Columns 1–2 are the primary key, in that order** (§8.1). **There is no
surrogate `id`.**

**No period column** (§4.3). **No counters** (§3.2). **No eligibility flag**
(§4.7). **No history column** — that is `E9`.

### 6.2 Column detail

---

**1. `community_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Which community this standing is in. **The leading key column.**

*Business justification.* It is half the identity and the whole of the isolation
guarantee (§4.6). Its position as the **leading** column is what makes the
*Highest Rated* board an index seek rather than a scan (§9.1).

*Never editable.* A rating earned in one community cannot be moved to another;
the value means nothing outside the play that produced it.

---

**2. `user_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Whose standing it is. The other half of the identity.

*Business justification.* It is the player's identity and the authentication
identity. Together with `community_id` it forms the key that **contains no
membership reference** — which is precisely what makes `SL-4`'s preservation and
resumption work (§4.8).

---

**3. `rating` — `numeric(4,2)`, NOT NULL, default `5.00`, system only**

*Purpose.* **The player's current standing in this community.**

*Business justification.* It is the measure *Highest Rated* ranks by, in every
period, and the only value this table exists to hold.

*`numeric(4,2)` — precision is a correctness requirement* (`RR-1`, §4.4). It
must match `users.overall_rating` exactly; a divergence would make one of the
two ratings unable to represent its own arithmetic.

*Default `5.00` — the approved neutral baseline* (`SL-4` §4.1, `A5`). **A
constant, never a copy.** The default is what implements *"created at the
baseline"*, and using a column default rather than an application value is what
guarantees no code path can seed it from somewhere else.

*Bounded `0.00 … 10.00`* — the approved `OP-1` scale, the same range the Global
Rating carries. The constraint is what makes the engine's clamp meaningful
rather than a convention.

*System only.* `RR-2`, extended by `SL-3` §3.5. **A client-writable community
rating would make the leaderboard self-selected**, which is the same argument
that made the Global Rating system-managed.

---

**4. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When this standing began — **the player's first-ever join of this
community.**

*Business justification.* It is the only place that fact is recorded.
`community_members.created_at` cannot answer it after a departure and a rejoin,
because that row is recreated; **this row is not**, by `SL-4`. So the column is
a genuine and free by-product of the preservation rule.

---

**5. `updated_at` — `timestamptz`, NOT NULL, default `now()`, trigger only**

*Purpose.* When the rating last moved.

*Business justification.* With `created_at` it distinguishes a player who has
never played in this community — the two are equal — from one who has. That is
otherwise unanswerable from this table, since the baseline and an unchanged
rating are the same number.

**Trigger-maintained**, because the writers are two system paths and a timestamp
each must remember is one that will be forgotten.

### 6.3 Why there is no surrogate key

Nothing references this table (§5.1), so a surrogate would have **zero
consumers** — the criticism this phase has recorded against four existing
surrogates, and the design `player_statistics` and `community_statistics` both
get right. **A greenfield table has no excuse for adding one.**

---

## 7. Constraints

### 7.1 Identity and integrity

| ID | Rule | Why it exists |
|---|---|---|
| `CR-C1` | **Primary key on `(community_id, user_id)`** | **One rating per player per community** — which makes `SL-4`'s *"created once per player per community and never reset"* a structural fact rather than a rule the write path must remember |
| `CR-C2` | **`community_id` references `communities(id)`, cascading** | `A7` |
| `CR-C3` | **`user_id` references `users(id)`, cascading** | A rating for nobody is not a fact |
| `CR-C4` | **`rating` is `numeric(4,2)` and NOT NULL** | `RR-1`. The precision must match `users.overall_rating` exactly (§4.4) |
| `CR-C5` | **`rating` is between `0.00` and `10.00`** | The approved `OP-1` scale. The type alone permits `99.99`; the range is a business rule and belongs in a constraint, and it is what makes the clamp meaningful |
| `CR-C6` | **`rating` defaults to `5.00`** | `SL-4` §4.1, `A5`. A **constant**, so no code path can seed it from the Global Rating or another community |
| `CR-C7` | **No client may insert, update or delete** | `RR-2`, `SL-3` §3.5. A client-writable rating makes the board self-selected |
| `CR-C8` | **Creation is idempotent** — a rejoin finds, never inserts | `SL-4`. Otherwise the mechanism meant to honour *"never reset"* would violate it |
| `CR-C9` | **No period column, ever** | `SL-5`, ERD §3.2 (§4.3) |
| `CR-C10` | **No foreign key to `community_members`, and no cascade from it** | **`A7`.** The defining negative |
| `CR-C11` | **The community is taken from the match, never supplied** | Isolation cannot be a parameter (§4.6) |
| `CR-C12` | **Every movement is recorded in `E9`, in the same statement flow** | §4.5. A rating that moved without an audit entry must be unreachable |
| `CR-C13` | **Movements are clamped to the range, and the *applied* delta is what `E9` records** | `RR-1`, `RR-5`. Reversal is exact only if the applied delta is stored |
| `CR-C14` | **A departure alters nothing; a rejoin reuses the record** | `SL-4` §4.2, §4.3 |
| `CR-C15` | **Eligibility is never stored** | §4.7 — a read-time filter, always |
| `CR-C16` | **Every change happens inside the recording operation's transaction, under the match row lock** | Level 1 and Level 2 must move together or not at all |

### 7.2 Deliberately not constrained

| Not constrained | Why not |
|---|---|
| A relationship between this rating and the Global Rating | `SL-3` — they are independent and expected to differ. A constraint tying them would deny the decision |
| A minimum number of matches before a rating is "real" | No approved rule. `SL-5` already requires at least one completed match in the window for a player to *appear* on a board; that is a read-time filter, not a stored condition |
| A community-average or normalisation | No approved rule, and it would be a figure nothing could reverse |
| That the player be a current member | **`SL-4` forbids it.** The record must survive a departure |

---

## 8. Keys

### 8.1 Primary key

**`(community_id, user_id)`** — a natural composite, **community first**.

**Two decisions:**

**No surrogate** (§6.3).

**Community first, player second**, chosen for the dominant read:

| Query | Served? |
|---|---|
| *Highest Rated*, community X — the population | **Yes**, on the leading column |
| The apply/reverse target | **Yes**, full key |
| Creation's idempotency check | **Yes**, full key |
| *This player's rating here* | **Yes**, full key |
| *This player's ratings everywhere* | **No** — `CR-X2` serves it |

**Consistent with `community_statistics`**, whose key leads with the same
column for the same reason — so both Level 2 tables are seeked identically by
every board and dashboard read.

### 8.2 Business key

**`(community_id, user_id)`** — the same two columns, and the domain's own name
for the row: *this player, in this community*.

**The business key is the primary key.**

### 8.3 Candidate keys

**One.** No subset is unique: a community has many rated players, and a player
has many community ratings.

### 8.4 Alternate keys

**None**, and none possible.

### 8.5 Foreign keys

**Outgoing — two**, both identifying, both cascading (§5.2).
**Incoming — none, and none may be added** (§5.1).
**Forbidden — `community_members`** (`CR-C10`).

---

## 9. Index Strategy

### 9.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `CR-X1` | **Primary key on `(community_id, user_id)`** | (a) **the *Highest Rated* board's population**, by the leading column, in all three periods; (b) the apply and reverse target on every result in that community; (c) the idempotency check on join; (d) *this player's rating here*; (e) enforcement of `CR-C1`, and therefore of *created once, ever* |
| `CR-X2` | **`(user_id)`** | (a) the cascade from `users`; (b) *this player's ratings across communities* — which has **no MVP reader** (the profile shows the Global Rating and the PRD places a Community Rating there out of scope) but is what a reconciliation would use |

### 9.2 Considered and deferred

| Candidate | Verdict |
|---|---|
| `(community_id, rating DESC)` | **Deferred, and it is the first to add.** It would let *Highest Rated* skip its sort. `CR-X1` already narrows to one community — tens of rows at the PRD's targets — so the sort is free today. **Revisit on a measured board latency**, not on prediction. Note it would serve all three periods, because the rating shown is always the current one (`SL-5`) |
| `(rating DESC)` alone | **No, and never.** It would serve a cross-community ranking — a global leaderboard, explicitly out of scope |
| Anything on `created_at` or `updated_at` | **No.** Nothing orders by either |

### 9.3 The rule for a future designer

> **This table is read by community, or by player.** An index serving a
> question that spans communities is a global ranking, which the PRD places out
> of scope.

---

## 10. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 10.1 The matrix

| Actor | Read | Write | Recalculate | Delete |
|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ |
| **Non-member of that community** | ✗ **Nothing** | ✗ | ✗ | ✗ |
| **Player — their own rating** | ✓ **Within communities they belong to** | ✗ | ✗ | ✗ |
| **Community Member** | ✓ **Every rating in that community** | ✗ | ✗ | ✗ |
| **Community Admin / Owner** | ✓ as a member — **role grants nothing here** | ✗ | ✗ | ✗ |
| **System Administrator** | ✗ No direct path | ✗ | ✗ | ✓ Transitively |
| **The system** | — | ✓ **Only actor** | ✓ **Required** | ✓ |

### 10.2 Read — community-scoped, and it contradicts nothing

**Membership of the community grants sight of its ratings**, and nothing else
does. A board that ranks a community's players is the community's own.

**Specified this way from the start**, applying `PS-R1`'s lesson preventively
rather than as a correction.

**The departed-player question, answered explicitly**, because the equivalent
question is a live finding on `rating_history`:

> A departed player cannot read their preserved Community Rating. **This
> contradicts nothing**, because no approved screen would show it to them: the
> Player Profile displays the **Global** Rating (`SL-3` §3.3), and *displaying a
> Community Rating on the Player Profile* is **out of MVP scope** by the PRD.

**The contrast with `RH-R1` is the point.** There, a career audit was scoped by
community and a career screen displays it — so scoping broke an approved rule.
Here, a community value is scoped by community and only community screens
display it — so scoping is exactly right. **Same rule shape, opposite verdict,
because the subject differs.**

### 10.3 Write

**No client writes of any kind** — `RR-2`, `SL-3` §3.5.

**Two system paths**: creation at join, and movement inside the recording
operation. Both `SECURITY DEFINER`; the second paired indivisibly with an `E9`
entry (`CR-C12`).

### 10.4 Recalculate and delete

**Recalculate is required**, for the same reason `PS-R2` and DP-11 require it at
Level 1 — and here it is additionally **the only honest backfill path** for
existing memberships (§19.2).

**Delete has no path** except the two cascades. **No administrative deletion**,
and none should be added: a rating an administrator can remove is a rating a
player can be argued out of.

---

## 11. Audit model

| Column | Required? | Verdict |
|---|---|---|
| `created_at` | **Required** | The player's first-ever join of this community — recorded nowhere else (§6.2) |
| `updated_at` | **Required** | Distinguishes a never-played rating from an unchanged one |
| `created_by` | **Not required** | §11.1 |
| `updated_by` | **Not required — and refused** | §11.1 |

### 11.1 Neither actor column, and the movement's audit is a separate entity

**Creation has no meaningful actor**: the player joined, and `user_id` says so.

**Movement has no human actor at all**: a rating moves as a consequence of a
recorded result. The person who recorded it did not choose the value; the engine
did. Naming them would name someone who made a different decision.

**And the audit that does matter is `E9`**, not a column here — exactly as
`rating_history` is the audit of `users.overall_rating` rather than a column on
`users`. `UP-4`'s principle applies with full force: **a mutable last-writer
column is erased by the next movement**, and a rating moves on every match.

**If administrative adjustment of a Community Rating is ever approved**, the
actor belongs on `E9` — and `E9` must be designed with the three columns
`Rating_History_Table_Specification.md` §14.1 specifies for the same question at
Level 1.

### 11.2 What the audit does not cover

**This table records no history at all.** The current value and nothing about
how it was reached — which is precisely why `E9` is not optional (§4.5).

---

## 12. Dependencies

### 12.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `communities` | Identifying parent, cascading | Owns the community and bounds the record's lifetime |
| `users` | Identifying parent, cascading | Owns the player |
| **Community Rating History (`E9`)** | **Not a foreign key — a functional dependency** | **Holds the applied deltas without which a correction cannot be exact** (§4.5) |
| `match_results`, `match_team_assignments`, `match_goals` | **Derivation sources** — no foreign key | Determine who moves and by how much |
| `matches` | **Two roles, no foreign key** | Supplies `community_id` (`CR-C11`) and the row locked while the rating moves |
| `community_members` | **Read-time only, never referenced** | Eligibility. **`A7` forbids any structural link** |

### 12.2 Tables depending on this table

**None by foreign key.** By behaviour:

| Consumer | Dependency |
|---|---|
| **The *Highest Rated* board**, all three periods | Ranks by this value |
| The Community Dashboard | **Forward-looking only** — no block displays a rating today |

**And two explicit non-dependants:** `player_statistics` and
`users.overall_rating` neither read nor are read by this table (`SL-3`, DP-10).

### 12.3 The board needs three tables, and that is worth stating

*Highest Rated*, in any period, is:

| Source | Contributes |
|---|---|
| **This table** | The rating, ranked — always the **current** value |
| **`community_members`** | Eligibility — active members only |
| **`community_statistics`** | The population filter — *played at least one completed match in the window* (`SL-5`) |

**No single table can serve the board**, and the three are read independently.
That is the direct consequence of `SL-5` separating the *measure* from the
*population*.

---

## 13. Conformance to the named decisions

**Requested explicitly. Each verified, with the reason.**

| Decision | Verdict | Reason |
|---|---|---|
| **`SL-1`** — one model, not three tables | **Conforms** — §13.1 |
| **`SL-2`** — two levels, isolation, boards never read Level 1 | **Conforms.** This is a Level 2 entity; `community_id` makes isolation structural; the board reads it and never `users.overall_rating` |
| **`SL-3`** — two independent rating systems | **Conforms.** Independent cardinality, independent movement, independent history. §4.1 raises one observation and no contradiction |
| **`SL-4`** — the lifecycle | **Conforms in full.** `5.00` at first join (`CR-C6`); preserved on departure (`CR-C14`); resumed on rejoin, guaranteed by a key containing no membership reference (§4.8); never reset (`CR-C1` + `CR-C8`) |
| **`SL-5`** — Highest Rated is a current-rating board | **Conforms.** No period column (`CR-C9`); the period selects the population, which lives in `community_statistics` (§12.3) |
| **`RR-1`** — precision | **Conforms.** `numeric(4,2)`, matching `users.overall_rating` (`CR-C4`) |
| **`RR-2`** — system-managed, no client writes | **Conforms**, and `SL-3` §3.5 extends it here explicitly (`CR-C7`) |
| **`RR-5`** — immutable history, reversal by applied delta | **Conforms by delegation.** This table holds no history; `E9` must implement `RR-5` in full, and §4.5 makes it a build condition |
| **`RR-6`** — Level 1 stays global | **Conforms.** This table adds a community dimension **beside** Level 1, never inside it. `users.overall_rating` and `player_statistics` are untouched |

### 13.1 `SL-1` conformance, stated because the naive reading is wrong

**`SL-1` says *one model, not three tables*.** A reader could ask whether a
separate Community Rating table violates it.

**It does not.** `SL-1` forbids splitting the **periodic statistics** into
`overall`, `weekly` and `monthly` tables — *"a scope is not a different kind of
record, it is the same record carrying a different community and period."*

**The Community Rating is a different kind of record**: different cardinality
(one per pair, not one per pair per period), a different kind of number (a
running value, not an accumulation), and a different lifecycle (created once at
join, never reset). **`SL-1` unifies scopes of one thing; it does not unify two
things.**

**ERD §3.2 confirms it** by listing `E7` and `E8` as separate entities with
different cardinalities, and §4.3 is the reason.

---

## 14. Future Compatibility

### 14.1 Community Rating History — the immediate sibling

Not future compatibility so much as a build condition (§4.5, `CR-D1`).

### 14.2 Displaying the rating on the Community Dashboard

**Already permitted and not yet exercised.** `SL-3` names the Dashboard as a
reader and forbids it the Global Rating; §7 of the statistics specification
records that no block displays a rating today, so *"the rule is immediately
operative as a prohibition and forward-looking as a permission."*

**No change to this table** — one more read.

### 14.3 Displaying it on the Player Profile

**Out of MVP scope by the PRD**, and if ever approved it would be a **scope
change requiring approval**, not a schema change. **The table is ready; the
read rule would need widening** (§10.2), and that widening is what makes it a
product decision rather than an engineering one.

### 14.4 A different rating engine, or different constants

**No change.** The constants live in the engine; this table holds a value in a
range. **The one property that must never change is that `E9` records the
applied delta** (§4.4).

### 14.5 Per-period ratings

**Must never be added** (§4.3, `CR-C9`). `SL-5` settled that the three named
forms are boards, not stored ratings, and adding a period here would duplicate
the value across every period of every pair.

### 14.6 A rating decay, or inactivity adjustment

**Not approved, and it would need `E9` first.** Any automatic movement is still
a movement and must be audited with an applied delta — and it would need a new
`change_reason` value in `E9`, exactly as an administrative adjustment would at
Level 1.

### 14.7 What must never be added

| Never | Why |
|---|---|
| A period column | §4.3 |
| A counter | §3.2 — counters are `community_statistics` |
| An eligibility flag | §4.7 |
| A membership reference | `A7`, `CR-C10` |
| A copy of the Global Rating | `SL-3` — they are independent, and a copy would be a second answer |
| A stored rank | §3.2 — rank is read-time |

---

## 15. Engineering Rationale

### 15.1 The key is what makes `SL-4` true

`(community_id, user_id)` contains **no membership reference**, so nothing a
departure or a rejoin does can affect the record's identity. **Preservation and
resumption are not behaviours the write path implements — they are properties
the key guarantees.** That is the whole of §4.8, and it is why `A7` forbids the
foreign key the modelling instinct would add.

### 15.2 A separate entity, because the cardinality differs by a dimension

§4.3. Counters carry a period; a running value cannot. Storing the rating on the
periodic record would duplicate it three times per pair today and more as
periods are added — the error the statistics specification's §14 row contained
until 2026-08-02.

### 15.3 The baseline is a column default, not an application value

`CR-C6`. Making `5.00` the default means **no code path can seed the rating from
the Global Rating or from another community**, which is what `A5` requires. An
application-supplied baseline would be one refactor away from being an
application-supplied *anything*.

### 15.4 The rating and its audit must be written together

§4.10. The Global Rating already has this property — one function moves the
value and writes the entry — and it is the strongest integrity guarantee either
level has. Level 2 must inherit it, which is why `E9` is a build condition
rather than a follow-up.

### 15.5 The read rule is scoped from the start

§10.2. `PS-R1` records Level 1's unscoped read as a Medium-High finding; a
greenfield table has no reason to repeat it, and here the scoping is not merely
safe but exactly correct, because the value is a community's own.

---

## 16. Engineering Review

**Six findings.** A design review, not an audit — the table does not exist.

### 16.1 Ownership — none possible if §10 is built as specified

No write access, no human actor, community-scoped reads. **The one thing to
verify at build time is that the read rule is implemented as specified** and
does not default to the unscoped form Level 1 carries.

### 16.2 The build-order dependency is the significant finding

**This table without `E9` is a rating that cannot be corrected exactly.** Every
correction would either reverse by the nominal constant — inventing a value at
the range ends — or not reverse at all.

**It is a build-order finding rather than a design defect**, and it is stated as
a condition (§19.1) rather than a risk to manage.

### 16.3 Duplicate responsibilities — none

No counter, no period, no rank, no copy of the Global Rating, no history. **Five
columns, two of which are the key.**

### 16.4 The backfill value is a real decision, not a detail

§19.2. Existing members predate this table and have no "first join" event under
Level 2. **Backfilling every one at `5.00`** means a community that has played
twenty matches opens its first leaderboard with every member on exactly the same
number — **a board that ranks nobody and asserts nothing.**

**The alternative — replaying the community's own recorded results — is
available**, because the evidence exists in full, and would also generate the
`E9` entries that make the result correctable afterwards.

**Recorded as `CR-D2`**, with a recommendation.

### 16.5 Two Level 2 writes now hang off the join path

The Community Statistics specification recorded `CS-D1`: the `overall` record is
created at join, which couples the join path to the statistics domain. **This
table adds a second write to the same path.**

**Assessment: acceptable, and the coupling is the same one.** Both are created
by the same event for the same reason — *"the player's record in this community
begins"* — and doing them in one operation is better than two. **But it should
be one operation, not two independent writes**, so that a partial failure cannot
leave a player with statistics and no rating.

Recorded as `CR-R4`.

### 16.6 Performance — sound

Every read is an index seek on the leading key column. Every write touches one
row per participant of one match. **The table's size is bounded by (players ×
communities they belong to)** — the smallest of the three Level 2 entities.

### 16.7 Summary

| Finding | Verdict |
|---|---|
| Ownership | **None possible** if built as specified |
| **Build order — `E9` first or together** | **`CR-D1`, a condition** |
| Duplicate responsibilities | **None** |
| **Backfill value** | **`CR-D2`, a real decision** |
| Join-path coupling doubles | **`CR-R4`**, acceptable, one operation required |
| Performance | **Sound** |

---

## 17. Validation and contradictions

| # | Source | Verdict |
|---|---|---|
| 1 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction.** `SL-1`…`SL-5` conformance is §13. §3.2 as corrected on 2026-08-02 states this entity's form exactly |
| 2 | `Docs/06-ERD.md` §3 | **No contradiction.** `E8` is *"one per player per community"*; §3.2's note *"Why `E8` is not scoped to a period"* is §4.3; §3.4's ownership rule is §1.3; §3.6's two-ratings table is §4.1; `A5` and `A7` are `CR-C6` and `CR-C10` |
| 3 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction.** `RR-1`, `RR-2`, `RR-5`, `RR-6` are §13. `RR-7`'s deletion limitations are inherited (§5.4) |
| 4 | `Community_Statistics_Table_Specification.md` v1.0 | **No contradiction.** Its §3.2 item 1 states the rating is not stored there, and item 11 of its approved context is the same decision from the other side. Its `CS-D1` is compounded here as `CR-R4` |
| 5 | `Rating_History_Table_Specification.md` v1.0 | **No contradiction.** Its §4.9 confirms this table's rating is absent from the Global audit and must stay so; its §4.10 records the template `E9` inherits |
| 6 | `Player_Statistics_Table_Specification.md` v1.0 | **No contradiction.** Level 1 is untouched — `RR-6` |
| 7 | `Profiles_Table_Specification.md` v2.0 | **No contradiction.** Its §13.1 states that the Community Rating **must not** be a second column on `users`, for exactly the cardinality reason §4.3 gives |
| 8 | `Docs/01-PRD.md` | **No contradiction.** *Displaying a Community Rating on the Player Profile* is out of scope, which §4.9 and §10.2 respect |
| 9 | `Docs/10-Design-Decisions.md`, `Docs/07-Database-Design.md` | **No contradiction.** `07-Database-Design.md` line 115 states that `RR-2`'s rule governs this rating and that the community tables *"should carry select policies only"* — §10.3 |
| 10 | `engineering/BTGE_Engineering_Specification.md`, `BTGE_Database_Contract.md` | **No contradiction — one observation.** BTGE reads the **Global** Rating as a Core Player Input, including for community matches. Consistent with `KB-006` and `SL-3`; recorded as `CR-R1` (§4.1) |
| 11 | **Database Principles** | **No artifact in the repository** — fourteenth phase |
| 12 | `SUPABASE_OPERATIONAL_GUIDELINES.md` §4 | **No contradiction**, if built as specified. §10.2 exists so this does not become a second broadly-readable table |

**No contradiction found.** The one item raised (§4.1) is an observation about
two approved decisions coexisting, not a conflict between them.

---

## 18. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `CR-R1` | **Two ratings answer "how good is this player" inside one community**: BTGE balances by the Global Rating, the board ranks by this one. Product-visible, and consistent with every approved document | Low — **an observation** | **Raised, not resolved.** Changing it is a Knowledge Base decision about engine inputs (§4.1) |
| `CR-R2` | **Built without `E9`, corrections cannot reverse exactly** | **High if it happens** | **Prevented by `CR-D1`**, a build condition |
| `CR-R3` | **Backfilling existing members at `5.00`** opens every established community's first board with every member on the same number | Medium | **Open**, `CR-D2` |
| `CR-R4` | **Two Level 2 writes hang off the join path.** A partial failure leaves a player with statistics and no rating, or the reverse | Medium | **Open**, §16.5. Must be one operation |
| `CR-R5` | **Inherited: deleting an MVP or scorer's account destroys a result without reversing**, leaving community ratings holding movements whose cause is gone | Medium | **Inherited** — `MRS-R1`, `MG-R1` |
| `CR-R6` | **No reconciliation.** A rating moved outside the audited path would leave no trace | Medium | **Open.** DP-11; the check is `5.00 + sum(in-effect E9 deltas) = rating`, per pair |
| `CR-R7` | **The read rule is built unscoped**, repeating `PS-R1` at Level 2 | **Medium-High if it happens** | **Preventable.** §10.2 specifies it; §16.1 says to verify |
| `CR-R8` | **Pressure to seed a joining player from their Global Rating** will recur — it looks fairer to an experienced player | Low, and it would break `SL-4` | **Refused in advance** by `CR-C6` making the baseline a column default (§15.3) |

---

## 19. Open decisions and build conditions

### 19.1 `CR-D1` — the build condition

**Community Rating History (`E9`) must be built with this table, not after it.**

Without it, a correction reverses by the nominal constant and invents a value
whenever the rating sat at either end of the range. **There is no interim
design that is correct** — the alternatives are an inexact rating or no
correction at all.

**Recommendation: build `E9` first, or in the same phase.** Its template is
already recorded (`Rating_History_Table_Specification.md` §4.10).

### 19.2 `CR-D2` — the backfill value for existing memberships

| Option | Assessment |
|---|---|
| **`5.00` for everyone** | Matches the letter of `SL-4`, and **is what the approved rule literally says**. But every established community opens its first leaderboard with all members identical — a board that ranks nobody |
| **Replay the community's recorded results** | The evidence exists in full — results, lineups, goals — and replaying generates the `E9` entries that make the result correctable. **Truthful, and more work** |

**Recommendation: replay.** Three reasons: the evidence exists; `A5`'s
prohibition is on importing *another* rating, and a community's own past matches
are not another rating; and a first board that ranks nobody is worse than no
board.

**This is a Product decision**, because it determines what the first Level 2
leaderboards say.

### 19.3 Other open decisions

| ID | Question | Recommendation |
|---|---|---|
| `CR-D3` | **Should the join path's two Level 2 writes be one operation?** | **Yes** (§16.5). A partial failure otherwise leaves a player half-initialised at Level 2 |
| `CR-D4` | **Is a reconciliation built with the table?** | **Yes** — DP-11, and it is one aggregate per pair (`CR-R6`) |
| `CR-D5` | **Do the `DP-n` readings match their approved definitions?** | **Confirm**, with `BDC-D4`, `MRS-D4`, `MG-D1`, `PS-D1`, `CS-D4` and `RH-D3` |

---

## 20. Build instruction

**No conformance section — the table does not exist.**

| # | Requirement | Source |
|---|---|---|
| 1 | **Build `E9` first, or in the same phase** | `CR-D1` |
| 2 | Settle `CR-D2` before backfilling | §19.2 |
| 3 | **Make the baseline a column default**, not an application value | `CR-C6`, §15.3 |
| 4 | **Create at join, idempotently**, in **one** operation with the Community Statistics record | `CR-C8`, `CR-D3` |
| 5 | **Pair every movement with an `E9` entry in the same statement flow** | `CR-C12` |
| 6 | **Apply and reverse over shared arithmetic**, reversing by the applied delta, newest first | `CR-C13`, `RR-4`'s lesson |
| 7 | **Build the read rule scoped to community membership**, and assert the denials | §10.2, `CR-R7` |
| 8 | **Build the reconciliation with the table** | `CR-D4` |

**Nothing was changed in this phase.** No code, no SQL, no migration and no
Supabase object was touched.

---

## 21. Engineering Approval

**Status: Engineering Approved — conditional** on `CR-D1` (build `E9` with it)
and `CR-D2` (the backfill value).

**Neither condition is a defect in this design.** The first is a build-order
requirement that follows from `RR-5`; the second is a Product decision the
approved rule does not answer, because `SL-4` describes a first join and
existing members never had one under Level 2.

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5` | ✓ §0 |
| Purpose, business ownership, domain ownership, lifecycle ownership | ✓ §1 |
| Lifecycle — six transitions, ten invalid | ✓ §2 |
| Responsibilities — five owned, seven not | ✓ §3 |
| **Dedicated independent-entity review — all twelve points** | ✓ §4 |
| Relationships: incoming, outgoing, ownership, deletion, lifecycle | ✓ §5 |
| Every column — five, all newly specified | ✓ §6 |
| Keys: primary, **business key**, candidate, alternate, foreign | ✓ §8 |
| Constraints | ✓ 16 |
| Index strategy — two required, three considered | ✓ §9 |
| Access control | ✓ §10 |
| Audit model | ✓ §11 |
| Dependencies both directions, **including why the board needs three tables** | ✓ §12 |
| **Conformance to `SL-1`…`SL-5`, `RR-1`, `RR-2`, `RR-5`, `RR-6`** | ✓ §13, nine of nine |
| Future compatibility | ✓ §14 |
| Engineering review | ✓ §16, six findings |
| Validation — **no contradiction found**, one observation raised | ✓ 12 sources |
| Risks, open decisions, rationale | ✓ §15, §18, §19 |
| No SQL, no migration, no implementation | ✓ |

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **The governing authority** — `SL-1`…`SL-5`, and §3.2 as corrected |
| `Docs/06-ERD.md` §3 | **`E8`**, §3.2's period note, §3.4's ownership rule, `A5` and `A7` |
| `engineering/Community_Statistics_Table_Specification.md` | **The sibling.** Same key order, same join-path creation, different cardinality |
| `engineering/Rating_History_Table_Specification.md` | **The template `E9` inherits** (§4.10 there); §4.9 confirms this rating stays out of the Global audit |
| `engineering/Results_Rating_Engineering_Decisions.md` | `RR-1`, `RR-2`, `RR-5`, `RR-6` |
| `engineering/Profiles_Table_Specification.md` | Holds the Global Rating; its §13.1 refuses this rating a column there |
| `engineering/Player_Statistics_Table_Specification.md` | Level 1's counters — untouched by this table |
| `engineering/Matches_Table_Specification.md` | Supplies the community, and the lock under which the rating moves |
| `engineering/Communities_Table_Specification.md` | The parent that bounds this record's lifetime |
| `engineering/BTGE_Database_Contract.md` | §4.1 — BTGE reads the **Global** Rating, which is `CR-R1` |
| `Docs/01-PRD.md` | Places a Community Rating on the Player Profile out of scope |
