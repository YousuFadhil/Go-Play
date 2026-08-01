# Community Statistics (`community_statistics`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved.** The two contradictions between approved documents are **resolved**; see §19 |
| Role | **Engineering Authority** for the physical table `public.community_statistics` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Statistics, Level 2 |
| Scope | **`public.community_statistics` only.** The Community Rating, Community Rating History and leaderboards appear **only as dependent or sibling entities** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **This table does not exist.** Level 2 is approved and unbuilt, so this is the
> **first greenfield specification in the phase**: every column, key, index,
> constraint and access rule below is a design decision taken here, not a
> description of something already running. §16 is therefore *design rationale*
> rather than audit, and there is no conformance section — there is a build
> instruction (§20).
>
> **It contains no SQL, no migration and no implementation**, and it designs no
> Community Rating, no rating history and no leaderboards.
>
> **All fourteen approved context items are taken as given.** Item 11 —
> the Community Rating is **not** stored here — resolves a contradiction between
> two approved documents (§19.1), and item 13 (DP-11) vindicates a gap this
> phase recorded against Level 1 (`PS-R2`).
>
> **Sibling authorities.** The nine table specifications and
> `BTGE_Database_Contract.md` v1.0, listed in *Related documents*.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Community Statistics** — entity `E7` in the conceptual model |
| **Physical table** | **`community_statistics`** |

**One row is one player's counters, in one community, over one period.** Not a
community's summary, not a player's career, and not a rating.

**The name is accurate but incomplete in one way worth stating at the top:**
these are *per-player* records. **The Community Dashboard's community-wide
figures — how many matches the community has played, and when it last played —
are not in this table and cannot be** (§19.2). That is the single most likely
misreading of the name, and §4.7 explains why the design is right anyway.

---

## 1. Purpose

### 1.1 Business purpose

A Community Statistics record answers: **what has this player done in this
community, over this period?**

It exists because Level 1 cannot answer that question and never could — a
career record carries no community dimension and no period, by decision
(`SL-2` §2.1, `RR-6`). **Adding either to Level 1 would destroy it**, because a
career is precisely the figure that spans communities and does not restart.

So the product needs a second, additive record — and this is it. It carries
the same six measures as a career, cut by two dimensions a career refuses:
**the community, and the period.**

**Its consumers are three:**

1. **The Community Dashboard** — **six** of its ten figures (§19.2).
2. **The nine Community Leaderboards** — *Top Scorers* and *Most MVP* read the
   counters; *Highest Rated* reads only the population.
3. **Eligibility** — which players appear on a board at all, in a window.

### 1.2 Business owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That the `overall` record exists** | **The system**, on the player's **first ever join** of that community | The join path (§2.2, `CS-D1`) |
| **That a periodic record exists** | **The system**, on the first result in that period | The apply path |
| **All six counters** | **The system, exclusively** | Apply and reverse |
| **The community and period identity** | **The system**, derived from the match | §4.6 |
| Timestamps | The database | — |

**No person owns any value here**, and — as at Level 1 — no person sets one.
Every number is a consequence of a recorded result.

### 1.3 Domain ownership

**Domain: Statistics. Position: a sibling of `player_statistics`, scoped by the
Community aggregate but not inside it.**

| Property | Value |
|---|---|
| Aggregate | **None.** It is not in the Match aggregate and not beneath the Community root in the ownership sense |
| Depends on | `users` and `communities` structurally; the result, goals and lineup semantically |
| Depended on by | The **Community Rating** as a sibling, never a parent; leaderboards by behaviour |
| Community-scoped | **Yes — and this is item 9.** The community dimension is owned here |
| Period-scoped | **Yes — and this is item 10** |
| Contains authorization | **No** |

**It is scoped by the community without belonging to it in the way
`community_members` does.** The distinction is `SL-4`'s and it is the whole of
§4.5: the record's *lifetime* is bounded by the community, and its *existence*
is bounded by neither the membership nor the match.

### 1.4 Lifecycle ownership

| Bounded by | Consequence |
|---|---|
| **The community** | **Absolutely.** A deleted community takes its statistics with it, *"the way everything under the aggregate root does"* (`A7`, ERD §3.4) |
| **The player's account** | **Absolutely**, *"the way `player_statistics` already goes with its user"* |
| **NOT the membership** | **`SL-4`, and this is the most important negative in the document.** A record outlives a departure and is found again on return. **It must never cascade from `community_members`** (`A7`) |
| **NOT any match** | Matches move the counters; they do not bound the record |
| **NOT the clock** | A period record is never expired or archived. `2026-W31` exists forever once written |

---

## 2. Lifecycle

The brief's sequence, transition by transition. **This is `SL-4` and ERD §3.7
expressed as data operations.**

### 2.1 The shape

```
  Player joins the community  (FIRST JOIN ONLY)
            │
            ▼
  OVERALL record created ─────────────── carrying zeros
            │
            │  first match played in a week / month
            ▼
  WEEKLY record created  }  created for periods the player
  MONTHLY record created }  ACTUALLY PLAYED IN — never in advance
            │
            ├── further results  ──▶ counters increase, in all three records
            ├── result corrected ──▶ reversed, then re-applied
            ├── match deleted    ──▶ counters decrease
            │
            ▼
  Player LEAVES the community
            │
            ▼
  EVERY RECORD PRESERVED ── nothing deleted, nothing altered, no flag written
  Player becomes INELIGIBLE ── evaluated at read time, stored nowhere
            │
            ▼
  Player REJOINS
            │
            ▼
  THE SAME RECORDS RESUME ── no new record, no new baseline, no reset
```

### 2.2 Transition 1 — the player joins: the `overall` record is created

**On the player's *first ever* join of that community, an `overall` record is
created carrying zeros.**

| Property | Value |
|---|---|
| When | First join only — `SL-4`, ERD §3.7 |
| What | One record: `(player, community, overall, overall)`, all counters zero |
| On rejoin | **Nothing.** The record already exists and is reused (§2.7) |
| Periodic records | **None.** They are created when the player plays (§2.3) |

**Why a record that asserts nothing is created at all.** ERD §3.7 is explicit —
*"a record can exist with nothing in it"* — and the reason is `SL-4`'s creation
rule: **"created once, ever"** is a statement about a *moment* if creation
happens at join, and a rule the write path must re-check on every result if it
does not.

**Three consequences the implementing phase must handle, and none is optional:**

| # | Consequence |
|---|---|
| 1 | **The join paths acquire a statistics write.** Joining by code, joining an open community, and creating a community all become writers of this table. §13.3 examines whether that breaches DP-3 |
| 2 | **Creation must be idempotent.** A player who left and rejoined must not receive a second record — the write is *create if absent*, never *insert* |
| 3 | **Existing memberships must be backfilled.** Every current member of every community predates this table and needs an `overall` record. The backfill is part of the build, not a follow-up |

**Recorded as `CS-D1`**, because the reason that made at-join creation
*necessary* — the Community Rating's baseline — **belongs to the rating table
under item 11**, and the remaining reasons are real but weaker (§18).

### 2.3 Transitions 2 and 3 — first match: the weekly and monthly records appear

**A periodic record is created the first time the player's result falls in that
period, and never in advance.**

ERD §3.7: *"Periodic records come into being for periods in which the player
actually played — a weekly record for a week with no appearances would carry
only zeros and assert nothing."*

**So one result creates or updates exactly three records** (§9.4 of the
statistics specification, the worked example):

| `period_type` | `period_key` |
|---|---|
| `overall` | `overall` |
| `weekly` | e.g. `2026-W31` |
| `monthly` | e.g. `2026-08` |

**And no record in any other community**, in any period. That is the isolation
rule expressed as data.

### 2.4 Transition 4 — results corrected: counters updated

**Identical in shape to Level 1, and the same defect must not recur.**

| Step | |
|---|---|
| 1 | Reverse the previous result's contribution from all three records |
| 2 | Replace the result |
| 3 | Apply the new contribution to all three records |

**`RR-4` applies here in advance**, and the statistics specification's own
readiness note says so: *"the reversal path for community counters will meet the
same `INSERT … ON CONFLICT` behaviour that produced the v1.0 reversal defect;
apply and reverse should stay separate statements over shared arithmetic."*

**This specification requires it** (`CS-C10`), and §16.1 explains why the
mistake is *more* likely here than it was at Level 1.

### 2.5 Transition 5 — the player leaves: everything is preserved

**Nothing is deleted. Nothing is altered. No flag is written.**

`SL-4` and ERD §3.7: *"Departure changes eligibility, not data. No entity is
deleted, no value is altered, and no flag is written onto the record."*

| What changes | Where |
|---|---|
| The player's **eligibility** for that community's boards | **`community_members`** — evaluated when a board is read |
| The player's **records** | **Nothing at all** |

**Why eligibility is never stored here.** Three reasons, and the third is
decisive:

1. A stored flag would need updating on every join and departure — a write to
   the statistics domain caused by a membership change.
2. It would be a second answer to a question `community_members` already
   answers, free to disagree with it.
3. **It would be wrong for periodic records.** Eligibility is a fact about *now*;
   a weekly record is a fact about a past week. A flag on `2026-W31` would have
   to mean *"is a member now"*, which is not a property of that week.

### 2.6 Transition 6 — ineligibility is a read-time filter

A departed player's records exist, hold correct figures, and **appear on no
board**. The filter is a join to `community_members` at read time (`SL-4`,
`SL-5`, `SL-2` §8).

**They also appear in no dashboard total** — except where the dashboard figure
is *community history*, which is unaffected by membership changes: §7.1 is
explicit that *"a departed member's matches and goals remain counted, because
they happened."*

**So the two consumers filter differently**, and the design must not conflate
them:

| Consumer | Filters by membership? |
|---|---|
| **Leaderboards** — ranking people | **Yes.** Only active members appear |
| **Dashboard community totals** — describing the community's history | **No.** What happened, happened |

### 2.7 Transitions 7 and 8 — the player rejoins: the same records resume

**No new record. No new baseline. No reset.**

`SL-4`: *"Previous Community Statistics reused — no new record, no new
baseline."* The records are found because they are keyed by
`(player, community, period)` — **not by membership** — so the key that located
them before locates them again.

**This is the requirement that dictates the whole ownership model** (§4.5):
if the records belonged to the membership, leaving would take them away and
rejoining would create empty ones, *"which is exactly what `SL-4` forbids."*

### 2.9 Transition 9 — the account or the community is deleted

| Deleted | Effect |
|---|---|
| **The player's account** | Every record of theirs, in every community, cascades away |
| **The community** | Every record in it, for every player, cascades away |
| **A membership** | **Nothing** — `A7`, and §4.5 |

### 2.10 Invalid transitions

| Invalid | Why | Refused by |
|---|---|---|
| A second `overall` record for one player in one community | The career-in-this-community would have two answers | **The primary key** (`CS-C1`) |
| Two records for the same player, community and period | Same | **The primary key** |
| A record created on rejoin | `SL-4`: created once, ever | Idempotent creation (`CS-C7`) |
| A record deleted on departure | `SL-4`: preserved | No operation deletes one |
| A record cascading from a membership | **`A7`, explicitly** | **No foreign key to `community_members`, and none may be added** |
| A negative counter | Meaningless, and the signature of a reversal bug | Non-negative checks (`CS-C6`) |
| A **manual edit** | A number with no contribution behind it can never be reversed | No write access (§11.3) |
| A `period_key` that does not match its `period_type` | *`overall` / `2026-W31`* is not a coherent record | The consistency check (`CS-C5`) — **new, and §7.2 explains why it is required** |
| A record for a community the match did not belong to | Isolation | The community is taken from the match, never supplied |
| A rating stored here | **Item 11**, and the cardinality is wrong (§4.4) | No such column |

---

## 3. Business Responsibilities

### 3.1 What this table owns

| # | Responsibility | How expressed |
|---|---|---|
| 1 | **Community-scoped counters** — the six measures, per player, per community | The six columns |
| 2 | **Overall counters** | `period_type = 'overall'` |
| 3 | **Weekly counters** | `period_type = 'weekly'` |
| 4 | **Monthly counters** | `period_type = 'monthly'` |
| 5 | **The period identity** — item 10 | `period_type` + `period_key` |
| 6 | **The community identity** — item 9 | `community_id` |
| 7 | **Isolation between communities** | Structurally, by the leading key column (§4.6) |
| 8 | **The population a board may rank** | The set of records for a community and period — filtered for eligibility at read time |

### 3.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **The Community Rating** | A separate Level 2 entity (`E8`) | **Item 11**, and §4.4 — the cardinality differs |
| 2 | **The Community Rating History** | A separate entity (`E9`) | Same |
| 3 | **Career figures** | `player_statistics` | Items 5 and 6, DP-10 |
| 4 | **The Global Rating** | `users.overall_rating` | Item 7 |
| 5 | **Eligibility** | `community_members`, at read time | §2.5 |
| 6 | **Any leaderboard** | Derived from this table | §4.3 |
| 7 | **Community-wide match counts and dates** | **`matches`** | **§19.2 — the contradiction** |
| 8 | **The evidence** | Result, goals, lineup | DP-12 |
| 9 | **Which matches contributed** | Nowhere derivable from here | §4.2 |

---

## 4. The Community Statistics Model

### 4.1 Why it is independent from Player Statistics

**Items 5, 6 and DP-10. Four reasons, and the second is structural rather than
architectural:**

1. **They answer different questions.** A career spans everything; this record
   is bounded twice.
2. **Level 1 has no community dimension to give.** Deriving Level 2 from Level 1
   is not discouraged — **it is impossible**, because there is nothing there to
   partition by. This is the same argument the Player Statistics specification
   makes from the other side (§4.5 there).
3. **`SL-4` would be unimplementable.** A record that must survive a departure
   and resume on return needs a community identity to survive *in*.
4. **Drift must not propagate.** Two independent derivations from one source can
   be compared and reconciled — **which is DP-11.** A chain cannot: an error at
   Level 1 would silently become an error in every period of every community.

**`SL-2` §2.5 states the relationship exactly:** the two levels *"count the same
matches"* and *"should agree **by construction**"* — because both derive from the
same evidence, **not because one derives from the other**.

### 4.2 Why they are accumulated counters, and not history

**Counters, for the same reason as Level 1** — a board and a dashboard must read
in one indexed scan, and recomputing would mean scanning every result in the
community on every screen open.

**Not history, and the distinction is sharper here than at Level 1:**

| | This table | A history |
|---|---|---|
| Granularity | **A period** — the finest is one week | One event |
| Says *which matches*? | **No** | Yes |
| Overwritten? | **Yes**, as the source changes | **Never** — appended to |

**A weekly record looks like history and is not.** `2026-W31` is a *bucket*, not
an event: it is overwritten when a result inside it is corrected, and it carries
no trace of what it previously said. **The history at this level is the Community
Rating History** (`E9`) — a separate entity, required, and out of scope here.

### 4.3 Why they are not leaderboards

A board is a **ranked, truncated, eligibility-filtered read** of this table. The
table holds the population and the measures; the board is a query.

**Three things the table therefore does not hold:** rank, eligibility, and
board depth. All three are read-time, and `SL-2` §8 confirms depth and tie-break
are presentation parameters.

### 4.4 Why they are not ratings — and why the rating is not stored here

**Item 11, and it is a cardinality argument before it is anything else.**

| | The six counters | The Community Rating |
|---|---|---|
| Identified by | player + community + **period** | player + community — **no period** |
| Cardinality | Several per pair | **Exactly one per pair** |
| Behaviour | Accumulates from zero within a window | A **running value** with no natural zero, which does not restart |

**Storing the rating on this row would duplicate it across every period of every
pair** — three copies today, more as periods are added, each free to disagree.

**ERD §3.2 already settled this** in its note *"Why `E8` is not scoped to a
period"*: *"a counter accumulates inside a window; a rating is a running value
that has no natural zero and does not restart… the rating is one value per player
per community, and the period dimension belongs to the counters and to
eligibility."*

**`SL-5` completes it:** the period selects **who is eligible to appear**, never
which rating is shown. *Highest Rated* in any window ranks by the **current**
rating.

**§19.1 records that one approved document says otherwise**, and that item 11
settles it.

### 4.5 Why the community dimension is fundamental

**It is not a filter. It is what makes isolation a property of the model rather
than a discipline every query must remember** (`SL-1` §9.1, `SL-2` §2.2).

**And it is what makes `SL-4` expressible.** The three requirements —
*preserved on departure, found again on return, created once ever* — are all
statements about a **(player, community)** pair. Without `community_id` on the
record there is no pair, and all three become unstatable.

**The rule this produces, and it is absolute:**

> **A Level 2 record belongs to the player and the community jointly. It must
> never reference, cascade from, or be keyed by the membership** (`A7`, ERD
> §3.4).

ERD §3.4 calls this *"the single most important statement"* of its section and
warns that *"the natural modelling instinct is wrong here"* — because a
membership is a *current fact* and a statistics record is a *historical* one, and
the second outlives the first.

### 4.6 Why the period dimension belongs here

**Item 10. Three reasons:**

1. **A period is a property of a counter, not of a player or a community.**
   Accumulation happens *within* a window; nothing else in the model
   accumulates.
2. **`SL-1` makes it a value, not an entity.** Three scopes are three values of
   two columns — *"a period is data about a record, not a different kind of
   record."* Three separate tables would triple the write path and the
   reconciliation.
3. **The Community Rating explicitly does not carry it** (§4.4). So the period
   lives on exactly one of the two Level 2 entities, and it is this one.

**How a match is placed in a period** is settled and inherited, not decided
here:

| | |
|---|---|
| **By which timestamp** | The match's **start** — `A3` |
| **In which zone** | **`Asia/Muscat` (UTC+4)** — `A1`, approved, *"must not change once figures exist"* |
| **Key formats** | ISO-8601 week (`2026-W31`); month `YYYY-MM` — `A2` |

**`A1` is the most fragile inherited constant in the design**: changing it
re-buckets history into different weeks and months, silently. §18 records it.

### 4.7 Why the table is per-player only

**Every record describes a player** — `SL-1` §9.1: *"identified by three
dimensions **beyond the player it describes**."*

**The alternative was considered and refused**: a nullable `user_id` meaning
*"the community as a whole"*, giving stored community-wide totals.

| Why refused | |
|---|---|
| **A null in a key is not a key** | The primary key would become partially nullable, and uniqueness of the community-level row would need a separate partial rule |
| **Two kinds of row in one table** | Every reader would have to know which it had |
| **It would duplicate `matches`** | *Total Matches* and *Last Match Date* are facts about matches. Storing them here would be a second answer to a question `matches` already answers — the duplication this schema has refused throughout |

**The consequence is §19.2**, and the design accepts it deliberately.

---

## 5. Relationships

### 5.1 Incoming

**None, and none may be added.**

The **Community Rating** (`E8`) is a **sibling**, not a child: it is keyed by
*(player, community)* and this table by *(player, community, period)*. Neither
references the other, and both are computed from the same evidence (DP-10).

**Leaderboards reference nothing** — they are queries.

### 5.2 Outgoing

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `users` | `user_id` | many : 1 | **`CASCADE`** | **Identifying.** *"A deleted player does the same, the way `player_statistics` already goes with its user"* |
| `communities` | `community_id` | many : 1 | **`CASCADE`** | **Identifying.** *"A deleted community takes its statistics with it"* — `A7` |

**Exactly two, and the third that must never exist:**

> **There is no foreign key to `community_members`, and there must never be
> one** (`A7`, §4.5).

**No foreign key to the evidence** either — a counter is an aggregate over many
results, with nothing single to point at (§12.2).

### 5.3 Ownership

| Question | Answer |
|---|---|
| **Who owns the meaning?** | **The player and the community, jointly** — ERD §3.4 |
| **Can a record be reparented?** | **No.** All four key columns are immutable |
| **Does the community know its statistics?** | **No stored total on `communities`** — refused there, and refused again here |
| **Does the record know which matches built it?** | **No** (§4.2), and it cannot regain the knowledge |

### 5.4 Deletion behaviour

| Path | Effect | Assessment |
|---|---|---|
| **The community is deleted** | Cascade | **Correct** — and note the ordering: the community's deletion also deletes its matches, which **reverses** the results first. So the records are decremented and *then* removed — wasteful but harmless, and it must not be "optimised" into a different order without re-examining the reversal |
| **The account is deleted** | Cascade | **Correct**, and it inherits the Level 1 problem: the *other* participants' community records are left holding a result that no longer exists where the MVP or a scorer was the deleted account (`MRS-R1`, `MG-R1`) |
| **A membership is deleted** | **Nothing** | **`A7`. The defining negative** |
| **A match is deleted** | Counters decrease; records remain | **Correct** |
| **Directly** | **No path exists** | **Correct** |

### 5.5 Lifecycle

| Relationship | Whose lifetime bounds whose |
|---|---|
| `users` → record | **Absolutely** |
| `communities` → record | **Absolutely** |
| **`community_members` → record** | **Neither bounds the other. This is `SL-4`** |
| Matches and results → record | **None.** They move it; a record outlives every match in it |
| Record → anything | **It bounds nothing** |

---

## 6. Columns

**Thirteen columns.** Every one is specified here for the first time.

### 6.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `community_id` | `uuid` | No | none | **Never** |
| 2 | `period_type` | `text` | No | none | **Never** |
| 3 | `period_key` | `text` | No | none | **Never** |
| 4 | `user_id` | `uuid` | No | none | **Never** |
| 5 | `matches_played` | `int` | No | `0` | **System only** |
| 6 | `wins` | `int` | No | `0` | **System only** |
| 7 | `losses` | `int` | No | `0` | **System only** |
| 8 | `draws` | `int` | No | `0` | **System only** |
| 9 | `goals` | `int` | No | `0` | **System only** |
| 10 | `mvp_count` | `int` | No | `0` | **System only** |
| 11 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| 12 | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** |

**Columns 1–4 are the primary key, in that order** (§8.1). **There is no
surrogate `id`**, and §8.1 states why.

**No `community_rating` column** (item 11). **No eligibility flag** (§2.5).
**No period start or end date** — the key names the period and `A1`/`A2` define
its boundaries; storing them would be a second, driftable answer.

### 6.2 Column detail

---

**1. `community_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Which community this record belongs to. **The leading key column.**

*Business justification.* It is what makes isolation structural (§4.5), and its
position as the **leading** column of the primary key is what makes every
board and dashboard read an index seek rather than a scan (§9.1).

*Never editable.* A record cannot move between communities; the figures were
earned in one.

---

**2. `period_type` — `text`, NOT NULL, no default, never editable**

*Purpose.* Which *kind* of period this record covers.

*Business justification.* Exactly three values in the MVP: `overall`, `weekly`,
`monthly` (`SL-1` §9.2). It is a closed vocabulary because every reader
branches on it and a fourth value would be read as *none of the above* by all
of them.

**A `text` vocabulary rather than an enumerated type**, because §14 shows the
extension path is *new values*, and adding a value to a check constraint is a
smaller change than altering a type in a live schema.

---

**3. `period_key` — `text`, NOT NULL, no default, never editable**

*Purpose.* Which *particular* period of that kind.

*Business justification.* Three formats, one per type (`SL-1` §9.3):

| `period_type` | `period_key` | Example |
|---|---|---|
| `overall` | The literal `overall` | `overall` |
| `weekly` | ISO-8601 week | `2026-W31` |
| `monthly` | Year and month | `2026-08` |

***`overall` is a period like any other***, with a single fixed key. ERD §3.5:
*"It is not a special case in the model, only in its key."* That is why it is
not a separate table, not a null, and not a boolean.

***A sortable text key rather than a date range.*** Both `2026-W31` and
`2026-08` sort lexicographically in chronological order within their type, so
*"the most recent four weeks"* is a range scan. A start/end date pair would be
two columns, two more things to compute, and two more that could disagree with
`A1`.

*Must agree with its type* — `CS-C5`, §7.2.

---

**4. `user_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Whose record this is. **The trailing key column.**

*Business justification.* It is the player's identity and the authentication
identity, so *"my record here"* needs no lookup.

**It is last in the key by design** (§8.1): every high-volume read fixes the
community and period and wants *all* players; only the personal reads fix the
player, and `CS-X2` serves those.

---

**5–10. The six counters — `int`, NOT NULL, default `0`, non-negative**

`matches_played`, `wins`, `losses`, `draws`, `goals`, `mvp_count`.

*Purpose.* The same six measures as a career, accumulated **within this
community and this period**.

*Business justification.* `SL-1` §9.1 names exactly these six for Level 2, and
they are the same six as Level 1 — deliberately, so that `SL-2` §2.5's *"agree
by construction"* is checkable: **a player's career counters must equal the sum
of their `overall` records across communities.** §16.3 makes that the basis of
DP-11's reconciliation.

*Defaults of zero* — which is what lets the `overall` record be created empty at
join (§2.2), and what lets the apply path supply only the contributing values.

*Non-negative* — and, as at Level 1, **this is the constraint that catches a
reversal bug** rather than storing its result. `RR-4`'s lesson is why the write
path must not propose a negative row (§16.1).

*Which counter carries which meaning* is identical to Level 1 and inherited
without restatement, including that `matches_played` counts **lineup
appearances in matches whose result was recorded** — not registrations, not
reserves, not unrecorded matches (`A4`).

---

**11. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When this record came into being.

*Business justification.* For the `overall` record it is **when the player first
joined this community** — which `community_members.created_at` cannot answer
after a departure and rejoin, because that row is recreated (`CMB` §4.6). **So
this is the only place the first-ever join is recorded**, and that is a genuinely
useful property `SL-4` gives for free.

For a periodic record it is when the player first played in that period.

---

**12. `updated_at` — `timestamptz`, NOT NULL, default `now()`, trigger only**

*Purpose.* When the counters last moved.

*Business justification.* The only signal that a period's figures changed after
the period ended — which is precisely what a correction does, and precisely what
a reconciliation would want to look at first.

---

## 7. Business Constraints

### 7.1 Identity and integrity

| ID | Rule | Why it exists |
|---|---|---|
| `CS-C1` | **Primary key on `(community_id, period_type, period_key, user_id)`** | **One record per player per community per period** — which makes *"exactly one overall record"*, *"weekly uniqueness"* and *"monthly uniqueness"* one structural guarantee rather than three rules (§8.1) |
| `CS-C2` | **`community_id` references `communities(id)`, cascading** | A record for a community that does not exist is not a fact. Cascading per `A7` |
| `CS-C3` | **`user_id` references `users(id)`, cascading** | A record for nobody is not a fact |
| `CS-C4` | **`period_type` is one of `overall`, `weekly`, `monthly`** | A closed vocabulary every reader branches on |
| `CS-C5` | **`period_key` must agree with `period_type`** — `overall` exactly for `overall`; an ISO week for `weekly`; a year-month for `monthly` | **New in this specification, and required.** Without it *`overall` / `2026-W31`* is storable, and a record that names a kind of period it does not cover is incoherent to every reader — the dashboard, the boards and the reconciliation alike. §7.2 |
| `CS-C6` | **All six counters are NOT NULL, default zero, non-negative** | A community total below zero is meaningless and is the signature of a reversal bug (`RR-4`) |
| `CS-C7` | **The `overall` record is created once, ever, per (player, community)** | `SL-4`. **Creation must be idempotent** — a rejoin must find, never insert (§2.2) |
| `CS-C8` | **No foreign key to `community_members`, and no cascade from it** | **`A7`.** The defining negative of the whole design (§4.5) |
| `CS-C9` | **No client may insert, update or delete** | A written counter has no contribution behind it and can never be reversed |

### 7.2 Why `CS-C5` is required rather than merely tidy

**Nothing in the approved documents states it**, and greenfield design must
supply it, because three separate consumers assume it silently:

| Consumer | What it assumes |
|---|---|
| **The dashboard** | That asking for `weekly` / current-week returns records covering that week |
| **A board** | That the population it ranks all cover the same window |
| **The reconciliation** (DP-11) | That summing the `overall` records reproduces the career — which fails if an `overall` record carries a week's figures |

**An incoherent pairing would not be detected by any of them.** It would simply
produce a figure nobody could explain, in a table with no history to explain it
from.

### 7.3 Derivation and write path

| ID | Rule | Why it exists |
|---|---|---|
| `CS-C10` | **Apply and reverse are separate statements over shared arithmetic** | **`RR-4`, applied preventively.** §16.1 explains why the mistake is *more* likely here |
| `CS-C11` | **Counters change only as a consequence of a result being recorded, corrected or removed** | Item 4. There is no other cause |
| `CS-C12` | **A result updates exactly three records per participant** — `overall`, its week, its month | `SL-1` §9.4 |
| `CS-C13` | **Only participants receive counters** | DP-5. The contribution is driven by the lineup |
| `CS-C14` | **The community is taken from the match, never supplied by a caller** | Isolation cannot be a parameter. The same defence the lineup write uses for its match id |
| `CS-C15` | **The period is derived from the match's start, in `Asia/Muscat`** | `A1`, `A3`. **Fixed before the first figure is computed, and never changed afterwards** |
| `CS-C16` | **Every change happens inside the recording operation's transaction, under the match row lock** | DP-2. Level 1 and Level 2 must move together or not at all |
| `CS-C17` | **A reconciliation must exist** | **DP-11**, item 13. §16.3 |

### 7.4 Preservation and reuse

| ID | Rule | Why it exists |
|---|---|---|
| `CS-C18` | **A departure alters nothing** | `SL-4`. Not a deletion, not a value, not a flag (§2.5) |
| `CS-C19` | **A rejoin reuses the existing records** | `SL-4`. Guaranteed by the key: it contains no membership reference to have changed |
| `CS-C20` | **Eligibility is never stored** | §2.5 — a read-time filter over `community_members`, always |

### 7.5 Deliberately **not** constrained

| Not constrained | Why not |
|---|---|
| `wins + draws + losses = matches_played` | True by construction; the same reasoning as Level 1. A constraint would catch a reversal bug later and less precisely than `CS-C6` |
| That a periodic record's figures be ≤ its `overall` record's | **True by construction and expensive to check** — it is a cross-row rule the write path already guarantees. **It is, however, the best cheap reconciliation assertion**, and §16.3 proposes it there instead |
| A record existing for every period since the player joined | Periodic records exist only for periods played in (§2.3). Gaps are correct and meaningful |
| Any relationship to the Community Rating | Item 11; they are siblings (§5.1) |
| An upper bound on any counter | None approved |

---

## 8. Keys

### 8.1 Primary key — a natural composite, and no surrogate

**`(community_id, period_type, period_key, user_id)`.**

**Two decisions, both deliberate:**

**No surrogate `id`.** Nothing references this table (§5.1), so a surrogate
would have **zero consumers** — exactly the criticism this phase has recorded
against four existing surrogates, and exactly the design `player_statistics`
gets right. **A greenfield table has no excuse for adding one.**

**Community first, player last.** The column order is chosen for the dominant
read, and the difference is not marginal:

| Query | Served by this order? |
|---|---|
| *Top Scorers, community X, weekly, 2026-W31* | **Yes** — three equality columns, then the population |
| *Most MVP, community X, overall* | **Yes** |
| *Dashboard totals for community X, this month* | **Yes** |
| The apply/reverse conflict target | **Yes** — full key |
| *This player's record in community X* | **No** — `CS-X2` serves it |

**A key led by `user_id` would invert this**, forcing every board to scan. The
personal reads are far rarer and are served by one secondary index.

### 8.2 Business key

**`(community_id, period_type, period_key, user_id)`** — the same four columns,
in the domain's own words: *this player, in this community, over this period*.

**The business key is the primary key**, as at Level 1.

### 8.3 Candidate keys

**One.** No subset is unique — a player has several records in a community, a
period has several players — and no other column combination identifies a row.

### 8.4 Alternate keys

**None**, and none possible: there is exactly one candidate key.

### 8.5 Foreign keys

**Outgoing — two:**

| Column | References | On delete |
|---|---|---|
| `community_id` | `communities(id)` | **`CASCADE`** |
| `user_id` | `users(id)` | **`CASCADE`** |

**Incoming — none, and none may be added** (§5.1).

**Forbidden — `community_members`** (`CS-C8`).

---

## 9. Index Strategy

### 9.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `CS-X1` | **Primary key on `(community_id, period_type, period_key, user_id)`** | (a) **all nine leaderboards** — three equality columns select the population; (b) **six dashboard figures** (§19.2) — the same seek, aggregated; (c) the apply and reverse paths' conflict target and join; (d) enforcement of `CS-C1`, and of *exactly one overall record* |
| `CS-X2` | **`(user_id, community_id)`** | (a) **a player's records in one community** — the personal dashboard view, and `SL-4`'s rejoin lookup; (b) **a player's records across communities** — which is what **DP-11's reconciliation needs**: summing every `overall` record for a player and comparing with their career (§16.3); (c) the cascade from `users` |

**Two indexes, and the second earns its place mainly through
reconciliation** — which is a use `PS-R2` shows Level 1 currently has no way to
perform at all.

### 9.2 Considered and deliberately deferred

| Candidate | Verdict |
|---|---|
| `(community_id, period_type, period_key, goals DESC)` and the same for `mvp_count` | **Not for the MVP.** They would let a board skip its sort — but `CS-X1` already reduces the population to one community and period, which for the PRD's target (three communities) is tens of rows. **Two more indexes to maintain on every result, to avoid sorting tens of rows, is the wrong trade today.** Revisit on measurement, and note that *Highest Rated* would need a third against a table this specification does not design |
| `(community_id, period_type, period_key, matches_played DESC)` | **No** — *Most Active Player* is one row from an already-narrowed set |
| `(period_type, period_key)` | **No.** Nothing asks a question across communities; that would be a global leaderboard, which is out of scope |
| A partial index on `period_type = 'overall'` | **No.** `overall` is a period like any other (`SL-1`), and a special-case index would be the first crack in that |

### 9.3 The rule for a future designer

> **This table is read by community-and-period, or by player.** An index that
> serves a question spanning communities is a global ranking, which is out of
> scope — and an index that special-cases `overall` breaks `SL-1`'s one-model
> design.

---

## 10. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

**This is a greenfield table, so the rule below is specified correctly from the
start** — explicitly applying the lesson of `PS-R1`, where Level 1's unscoped
read permits enumeration that `UP-1` forbids.

### 10.1 The matrix

| Actor | Read | Write | Recalculate | Delete |
|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ |
| **Non-member of that community** | ✗ **Nothing** | ✗ | ✗ | ✗ |
| **Player — their own record** | ✓ **Only within communities they belong to** | ✗ | ✗ | ✗ |
| **Community Member** | ✓ **Every record of that community** | ✗ | ✗ | ✗ |
| **Community Admin** | ✓ as a member — **admin grants nothing extra** | ✗ | ✗ | ✗ |
| **Organizer** *(as such)* | ✓ as a member — **not a role** | ✗ | ✗ | ✗ |
| **System Administrator** | ✗ No direct path | ✗ | ✗ | ✓ Transitively |
| **The system** | — | ✓ **Only actor** | ✓ **Required** (`CS-C17`) | ✓ |

### 10.2 Read — scoped to the community, deliberately

**Membership of the community is what grants sight of its statistics**, and
nothing else does.

**Three reasons:**

1. **A board and a dashboard are the community's own.** `SL-2` §2.2's isolation
   rule is about figures not *affecting* each other; this is about who may
   *see* them, and the same boundary is the natural one.
2. **`UP-1` and `PS-R1`.** An unscoped read would let any account enumerate
   every player who has ever played anywhere, with figures attached —
   reintroducing at Level 2 exactly the hole `UP-1` is closing at Level 1.
3. **`SUPABASE_OPERATIONAL_GUIDELINES.md` §4** permits exactly one broadly
   readable table, with recorded approval. **This must not become a second.**

**Departed members' records are readable by current members** — they are part of
the community's history (§2.6), and hiding them would make the dashboard's
community totals unexplainable.

**A player's own record in a community they have left is *not* readable by
them**, because the read is scoped by current membership. **This is a
consequence worth confirming** rather than assuming: `SL-4` preserves the record
for the player's *return*, not for their inspection while away. Recorded as
`CS-D3`.

### 10.3 Write, Recalculate, Delete

**No write access of any kind**, and no operation a person invokes. Every change
is a consequence of the recording operation, inside its transaction and its
lock.

**Recalculate is required and must exist** — `CS-C17`, DP-11, §16.3. **It is
not a write capability granted to a person**: it is a system operation, and if
it is ever exposed it belongs to the System Administrator and to nobody in a
community.

**Delete has no path** except the two cascades.

---

## 11. Audit

| Column | Required? | Verdict |
|---|---|---|
| `created_at` | **Required** | §6.2 column 11 — and for the `overall` record it is the **only** record of the player's first-ever join |
| `updated_at` | **Required** | The signal that a closed period's figures changed — the first thing a reconciliation looks at |
| `created_by` | **Not required** | §11.1 |
| `updated_by` | **Not required** | §11.1 |

### 11.1 Neither actor column is required — the same reason as Level 1

**Every write is a consequence, never an act.** A counter moves because a result
was recorded, corrected or removed; the person who caused it did not touch this
table, did not choose the value, and — for the `overall` record created at join
— the "actor" is the player themselves, which `user_id` already says.

**The actor for the cause is recorded where the cause is**
(`match_results.recorded_by`). `UP-4` independently refuses `updated_by`; here
the prior objection is that there is no writer to name.

### 11.2 What the audit does not cover

**No history of the counters, and no per-period trace of which matches
contributed.** The record shows current figures for its window and nothing about
how they were reached (§4.2).

**This is why DP-11's reconciliation is not optional** (§16.3): it is the only
mechanism that could ever detect that a figure is wrong.

---

## 12. Dependencies

### 12.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `communities` | Identifying parent, cascading | Owns the community, and bounds the record's lifetime |
| `users` | Identifying parent, cascading | Owns the player |
| `match_results` | **Derivation source** — no foreign key | The scores from which win/loss/draw and MVP are determined |
| `match_goals` | **Derivation source** — no foreign key | The goal tallies |
| `match_team_assignments` | **Derivation driver** — no foreign key | One row per participant, and the side each was on |
| `matches` | **Two roles, no foreign key** | Supplies `community_id` (`CS-C14`) **and** `start_at`, from which the period is derived (`CS-C15`). Also the row locked while counters move |
| `community_members` | **Read-time only, and never referenced** | Eligibility, evaluated when a board is read (`CS-C20`). **`A7` forbids any structural link** |

### 12.2 The unrepresented dependencies

**Four tables determine every value here and none is referenced** — the same
situation as Level 1, with the same three costs: no cascade can keep the
counters honest, no constraint can express consistency with the source, and no
database mechanism can detect drift.

**Which is exactly why DP-11 is approved**, and why this specification requires
a reconciliation rather than recommending one.

### 12.3 Tables depending on this table

**None by foreign key.** By behaviour:

| Consumer | Dependency |
|---|---|
| **The nine leaderboards** | *Top Scorers* and *Most MVP* read the counters; all nine read the population |
| **The Community Dashboard** | Six of ten figures (§19.2) |
| **The Community Rating** | **None — it is a sibling** (§5.1, DP-10) |

**And one explicit non-dependent:** `player_statistics` neither reads nor is
read by this table (items 5 and 6).

---

## 13. Engineering Principles

The brief names eleven. **Nine have no textual definition in this repository** —
the twelfth phase in which the absent *Database Principles* document has been
recorded. The reading applied is stated for each. **If a reading differs from
the approved definition, this section is the defect** (`CS-D4`).

**Two are newly named here**, and both are approved as context items:
DP-11 (item 13) and DP-12 (item 14). **`DP-9` remains absent from the list.**

### DP-1 Match Aggregate Root Principle — **conforms, from outside**

This table is not in the Match aggregate. Every change originates from a match,
takes a match id, and happens under the match's authority and lock. **It never
reaches into a match**, and the two values it takes from one — the community and
the start time — are read, never written.

### DP-2 Match Row Lock Principle — **conforms, inherited, and this matters more here**

Counters move inside the recording operation, under the match row lock.

**Level 1 and Level 2 must move together or not at all.** Without the shared
lock and transaction, a correction could update the career and fail on the
community records — leaving the two levels disagreeing, with **no mechanism to
detect it** short of the reconciliation DP-11 requires.

### DP-3 Business Transition Principle — **conforms, with one question raised**

*Reading: a state change happens only through the business operation that owns
it.*

**Counter changes conform absolutely**: one route, the recording operation, no
policy admitting another.

**The `overall` record's creation at join raises a fair question** (§2.2): is
creating a statistics record part of the *join* transition, or is the join path
reaching into another domain?

**Assessment: it conforms**, because *"the player's record in this community
begins"* is genuinely part of what joining means — `SL-4` treats it as one
event. **But it is the one place this table's write path is not the recording
operation**, and `CS-D1` records the alternative.

### DP-4 Historical Identity Principle — **conforms**

*Reading: a historical record states what happened, identified by the entities
that took part, never by the process that produced it.*

**These records are not historical** — they are current totals for a window,
overwritten as the source changes, and §4.2 says so rather than letting a
weekly record be mistaken for history. They are identified entirely by
entities and a period; **nothing about the process is stored**.

### DP-5 Final Participation Principle — **conforms, and depends on it entirely**

`matches_played` is a count of lineup rows, scoped to a community and a period.
A player absent from the lineup receives nothing at either level.

### DP-6 Single Business Path Principle — **conforms**

Applying and reversing are two statements but one path and one arithmetic —
**and the arithmetic must be the same helper Level 1 uses**, extended with the
community and period, rather than a second implementation. **Two contributions
computed separately would be two chances to disagree**, and `SL-2` §2.5's *"agree
by construction"* would become a hope.

### DP-7 Producer / Commit Separation Principle — **conforms, by not applying**

Nothing here is a candidate a human may reject. The counters are entailed by the
result, and separating computation from commitment would produce a recorded
result whose community figures had not been applied.

### DP-8 Historical Record Protection Principle — **conforms**

*Reading: the historical record is protected from, and independent of, the
derived data around it.*

**This table writes no history and depends on none.** The Level 2 history is the
Community Rating History (`E9`) — a separate entity, required, and out of scope
here. **A defect in these counters cannot corrupt it**, because that record
stores applied deltas and needs nothing from here.

### DP-10 Independent Derivation Principle — **conforms, and §4.1 is the argument**

Both levels derive from the same evidence, independently. **Neither reads the
other, and neither could usefully**: Level 1 has no community dimension to give,
and Level 2 has no career to give back.

### DP-11 Derived Data Reconciliation Principle — **conforms by design, and requires an operation** (`CS-C17`)

*Reading (approved, item 13): derived data must be reconcilable against its
evidence, and the mechanism to do so must exist.*

**This is the principle that turns `PS-R2` from a finding into a requirement**,
and it is satisfiable here in a way it is not at Level 1 alone — §16.3 sets out
three checks, two of which are free.

### DP-12 Evidence Before Derivation Principle — **conforms, with one inherited exposure**

*Reading (approved, item 14): a derived figure may exist only while the evidence
that produced it exists; evidence must not be destroyed while a derivation from
it survives.*

**The derivation path conforms**: a figure is written only from a recorded
result, and removed by reversing it.

**The exposure is inherited, and DP-12 is precisely the principle it breaches:**
deleting the account of an MVP or a scorer destroys evidence *without* reversing
what it produced (`MRS-R1`, `MG-R1`), and a replaced lineup strands a
contribution (`RR-7`). **All three leave a Level 2 figure whose evidence is
gone.**

**DP-12 being approved means these are now principle violations rather than
merely known limitations** — which is a change in status this specification
records without resolving (§16.4, `CS-R3`).

---

## 14. Future Compatibility

### 14.1 The extension model — one value, not one table

**`SL-1` is the whole answer**, and §11 of the statistics specification names
the extension point: *"a future scope is a new period type… would extend the
same dimension and add no entity."*

| Future | What it needs | Structural change |
|---|---|---|
| **Season statistics** | `period_type = 'season'`, key e.g. `2026-S1` | **A new vocabulary value.** None |
| **Tournament statistics** | `period_type = 'tournament'`, key = the tournament's identifier | **A new vocabulary value** — plus §14.2 |
| **League statistics** | `period_type = 'league'`, key = the league's identifier | Same |
| **Custom periods** | `period_type = 'custom'`, key = the period's identifier | Same |
| **Additional counters** | A column, an evidence source, a contribution term | **A column** — plus §14.3 |

**Nothing above changes a key, an index, an access rule or the write path's
shape.** That is the payoff of `SL-1`, and it is why three scopes were built as
two columns rather than three tables.

### 14.2 The one thing the period model does not currently support

**A period key that is not derivable from the match's start time.**

`CS-C15` derives the period from `start_at` in a fixed zone. That works for
weeks, months, seasons and any calendar period.

**A tournament or a league is not a calendar period.** Which tournament a match
belongs to is a *property of the match*, not of its date — so supporting it
needs the match to carry that property, and the period derivation to read it.

**The consequence, stated so it is not discovered late:** *season*, *custom* and
any calendar scope are **pure vocabulary additions**; *tournament* and *league*
require the Match domain to gain a reference first. **The table is ready for
both; the evidence layer is ready only for the first.**

### 14.3 Additional counters — and the backfill problem, again

The Player Statistics specification records that **a new counter column defaults
to zero, and zero is an assertion** — `assists = 0` says *never assisted*, which
is false for careers predating the measure.

**The problem is the same here and the answer may differ**, because a Level 2
record is bounded by a period: a *weekly* record for a week before assists were
recorded is unambiguously *"we did not record assists then"*, and a weekly
record created afterwards is unambiguously zero.

**So the period dimension makes the honest answer cheaper at Level 2 than at
Level 1** — records are naturally partitioned by when they were created. **The
rule should still be decided once for both levels** (`PS-D2`), and this
specification defers to it.

### 14.4 What must not be added

| Never | Why |
|---|---|
| A rating column | Item 11, §4.4 |
| An eligibility flag | §2.5 |
| A membership reference | `A7`, `CS-C8` |
| A community-wide row with a null player | §4.7 |
| A period start/end date pair | `A1` and `A2` define them; storing them invites drift |
| A stored rank | §4.3 |

---

## 15. Engineering Rationale

### 15.1 The key is the design

Four columns, in one order, deliver: one record per player per community per
period; *exactly one overall record* as a structural fact; isolation on the
leading column; every board and dashboard read as an index seek; and the
apply/reverse conflict target. **No surrogate, no alternate key, no second way
to name a row.**

### 15.2 Three scopes are two columns, because a period is data

`SL-1`. Three tables would triple the write path, the reversal, the
reconciliation and the access rules — to express something two columns already
express. And **the extension path is then a value, not a migration** (§14.1).

### 15.3 The record belongs to the pair, never to the membership

`SL-4` and `A7`. It is the requirement that dictates the key, the cascades, and
the absence of a foreign key that the modelling instinct would add. ERD §3.4
calls it *"the single most important statement"* of its section, and this
specification treats it as one.

### 15.4 `RR-4` is designed against, not merely remembered

`CS-C10`. The defect that broke every correction at Level 1 will present itself
identically here, and §16.1 argues it is *more* likely — so apply and reverse
are separate statements over shared arithmetic, specified before the first line
is written.

### 15.5 The read rule is scoped from the start

`PS-R1` records Level 1's unscoped read as a Medium-High finding. **A greenfield
table has no reason to repeat it**, and §10.2 specifies community-scoped reads
as the rule rather than as a correction.

---

## 16. Engineering Review

**Six findings.** This is a design review rather than an audit — the table does
not exist — so each is a risk the build must avoid rather than a defect it has.

### 16.1 `RR-4` is more likely to recur here than it was at Level 1

**The defect:** reversing by proposing negative values through
`INSERT … ON CONFLICT DO UPDATE`. PostgreSQL validates the proposed tuple
*before* detecting the conflict, so a non-negative check fires against a row
that was only ever intermediate.

**Why it is more likely here, not less:**

| | Level 1 | Level 2 |
|---|---|---|
| Records touched per participant | **One** | **Three** |
| Records that may not exist yet | The player's, on a first match | **The weekly and monthly, on every new period** |
| Temptation to use one upsert for both directions | Present | **Stronger** — the "create if absent" need is more frequent, which is exactly what makes an upsert look right |

**`CS-C10` is therefore specified as a rule rather than left as a lesson**, and
`CS-C6` is retained precisely because it is what catches the mistake.

### 16.2 Ownership — no violation possible if §10 is built as specified

No write access, no human actor, community-scoped reads. **The one thing to
verify at build time is that the read rule is implemented as specified** and
does not default to the unscoped form `PS-R1` records at Level 1.

### 16.3 Reconciliation — required by DP-11, and three checks are available

**Two are nearly free and one is exact:**

| # | Check | Cost | What it detects |
|---|---|---|---|
| 1 | **A player's career counters equal the sum of their `overall` records across communities** | One aggregate, served by `CS-X2` | **Drift between the two levels** — the strongest available check, and it exists only because both levels carry the same six measures |
| 2 | **A periodic record's figures never exceed its `overall` record's** | One aggregate per community | A misplaced period, a missed reversal |
| 3 | **Recompute from the evidence and compare** | A full derivation | Everything — and it is the only check that survives a Level 1 defect |

**Check 1 is the reason §6.2 keeps the six measures identical to Level 1**, and
it is what makes `SL-2` §2.5's *"agree by construction"* verifiable rather than
aspirational.

**A rebuild operation is also required** — `PS-D5` asks for one at Level 1, and
here it is additionally the only honest backfill path for §2.2's existing
memberships and for any future counter.

### 16.4 DP-12 changes the status of three inherited findings

**DP-12's approval means the three evidence-destruction cases are now principle
violations**, not merely recorded limitations:

| Case | Source |
|---|---|
| Deleting an MVP's account destroys a result with no reversal | `MRS-R1` |
| Deleting a scorer's account destroys goal evidence with no reversal | `MG-R1` |
| Replacing a lineup after recording strands a contribution | `RR-7` |

**Each will produce a Level 2 figure whose evidence is gone**, in up to three
period records per participant per community. **Not resolved here** — none is
this table's to fix — but recorded as `CS-R3`, and **the reconciliation in
§16.3 is what would make them visible.**

### 16.5 Consistency — the period constant is the fragile inheritance

**`A1` — `Asia/Muscat` — must be fixed before the first figure is computed and
must never change.** Changing it re-buckets history into different weeks and
months, silently, with no error and no way to detect it afterwards.

**Three mitigations, all cheap, none currently specified anywhere:**

1. State the constant in one place that the derivation reads.
2. Record in the implementing migration that it is frozen.
3. **Include it in the reconciliation's assumptions** — check 2 in §16.3 would
   detect a re-bucketing, because periodic figures would stop summing to
   `overall`.

### 16.6 Performance — sound, with one deferred decision

Every read is an index seek on the leading three key columns. Every write
touches three records per participant of one match. **The table's size is
bounded by (players × communities × periods played)**, which for the PRD's
targets is small and for any realistic growth is modest.

**The deferred decision is §9.2's sort-avoiding indexes** — correctly deferred,
and the trigger to revisit is a measured board latency, not a prediction.

### 16.7 Summary

| Finding | Verdict |
|---|---|
| `RR-4` recurrence risk | **Designed against** — `CS-C10`, `CS-C6` |
| Ownership | **None possible** if §10 is built as specified |
| Reconciliation | **Required** — `CS-C17`, three checks specified |
| DP-12 — three inherited violations | **Recorded**, `CS-R3`; not this table's to fix |
| The `A1` constant | **Fragile**, three mitigations named |
| Performance | **Sound**; one decision correctly deferred |

---

## 17. Validation

**Contradictions are named, not resolved silently. Two are found, and both are
between approved documents.**

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 — **§14** | **CONTRADICTION with item 11 and with the ERD** | §19.1 |
| 2 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 — **§7** | **CONTRADICTION with `SL-1` §9.1** | §19.2 |
| 3 | `Statistics_Leaderboards_MVP_Specification.md` — `SL-1`, `SL-2`, `SL-4`, `SL-5`, §9, §11 | **No contradiction** | The key, the three period types, the isolation rule, the lifecycle and the extension model are followed exactly |
| 4 | `Player_Statistics_Table_Specification.md` v1.0 | **No contradiction** | Its §4.5 (why Level 1 never feeds Level 2) is this document's §4.1 from the other side. Its `PS-R1` is the lesson §10.2 applies preventively; its `PS-R2` is what DP-11 now requires |
| 5 | `Match_Results_Table_Specification.md` v1.0 | **No contradiction** | The result is the evidence; `MRS-R1` lands here as `CS-R3` |
| 6 | `Match_Goals_Table_Specification.md` v1.0 | **No contradiction** | Its §4.5 (the goals→statistics boundary) holds identically at Level 2; `MG-R1` lands here |
| 7 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction** | `RR-4` is `CS-C10` and §16.1; `RR-6` is why Level 1 stays global; `RR-7` lands here |
| 8 | `Docs/06-ERD.md` §3 | **No contradiction — and it is the authority for §19.1** | §3.2 (`E7` per period, `E8` per pair), §3.4 (ownership is Player **and** Community, never Membership), §3.5 (the period dimension), §3.7 (the lifecycle), §3.9 (`A1`–`A7`) are all followed |
| 9 | `Docs/01-PRD.md` | **No contradiction** | *Community — per-community statistics, the Community Dashboard, and nine leaderboards over three periods* |
| 10 | `Docs/10-Design-Decisions.md` | **No contradiction** | `SL-1`…`SL-5` hold |
| 11 | **Database Principles** | **No artifact in the repository** | **Twelfth phase.** Nine of the eleven `DP-n` principles have no definition here; §13 states the reading applied. `DP-9` remains absent from the list |
| 12 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **No contradiction, if built as specified** | §4's checklist is satisfiable in full — and §10.2 exists specifically so this does not become a second broadly-readable table |

### 17.1 *(numbering continues at §19 — see below)*

---

## 18. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `CS-R1` | **`RR-4` recurs**, because three records per participant and frequent first-time periods make a single sign-flagged upsert look correct | **Medium** — and entirely preventable | **Designed against** — `CS-C10`. Verify at build with a reversal test, not by inspection: `RR-4` *"passed review by inspection"* and *"the migration ran clean"* |
| `CS-R2` | **The `A1` time-zone constant changes after figures exist**, silently re-bucketing history | **Medium** | **Open.** Three mitigations in §16.5, none currently recorded anywhere |
| `CS-R3` | **Three inherited evidence-destruction cases** each leave Level 2 figures whose evidence is gone — and **DP-12's approval makes them principle violations** | Medium | **Inherited** — `MRS-R1`, `MG-R1`, `RR-7`. Reconciliation makes them visible; only their sources fix them |
| `CS-R4` | **The read rule is built unscoped**, repeating `PS-R1` at Level 2 and creating a second unapproved broadly-readable table | **Medium-High if it happens** | **Preventable.** §10.2 specifies the rule; §16.2 says to verify it |
| `CS-R5` | **The at-join creation couples the join path to the statistics domain**, and requires a backfill of every existing membership | Low | **Open**, `CS-D1`. Approved by ERD §3.7; the alternative is recorded |
| `CS-R6` | **Two levels can drift with nothing to detect it**, until the reconciliation exists | Medium | **Closed by `CS-C17`** if built with the table rather than after it |
| `CS-R7` | **Tournament and league periods need the Match domain to change first** | Low | **Recorded**, §14.2. The table is ready; the evidence layer is not |
| `CS-R8` | **A departed player cannot read their own preserved record** | Low | **Open**, `CS-D3`. A consequence of community-scoped reads, and arguably correct |

---

## 19. The two contradictions — both resolved

**Resolved by the architecture review of 2026-08-02.** Both were contradictions
*between approved documents*, not defects in this design; this specification
followed the correct reading throughout and the conflicting passages have been
corrected at source. `CS-D2` is closed.

### 19.1 The Community Rating: stored here, or not? — **RESOLVED**

| Source | Says |
|---|---|
| **Approved context, item 11** | *"Community Rating is **NOT** stored inside Community Statistics."* |
| **`06-ERD.md` §3.2** | `E7` is **one per player per community per period**; `E8` is **one per player per community** — separate entities, different cardinality. §3.2's note *"Why `E8` is not scoped to a period"* explains why they must be separate |
| **`Statistics_Leaderboards_MVP_Specification.md` §14** | The ERD entity is *"keyed by `(player, community_id, period_type, period_key)`, **carrying the six counters and the Community Rating**"* |

**The third contradicts the first two**, and it is not a cosmetic difference: a
rating carried on a per-period row is **duplicated across every period of every
pair**, with three copies today and more as periods are added, each free to
disagree with the others.

**Item 11 settles it, in favour of the ERD**, and this specification follows
item 11: **there is no rating column here.**

**Not resolved silently.** `Statistics_Leaderboards_MVP_Specification.md` §14's
readiness row should be corrected to match `06-ERD.md` §3.2 and item 11.
Recorded as `CS-D2`.

### 19.2 The Community Dashboard: can this table supply every figure? — **RESOLVED**

**`Statistics_Leaderboards_MVP_Specification.md` §7 opens:** *"Every figure on
this screen is **Level 2 — Community Statistics**."*

**Four of its ten figures cannot come from this table**, and the reason is
arithmetic rather than architectural:

| Figure | Derivable here? | Why not |
|---|---|---|
| Total Goals | **Yes** — sum of `goals` over the community's `overall` records | — |
| Total Players | **Yes** — count of records | — |
| Most Active Player (weekly, monthly) | **Yes** — highest `matches_played` in the period | — |
| Goals Scored (weekly, monthly) | **Yes** | — |
| **Total Matches** | **No** | Summing `matches_played` counts **player-appearances**, not matches. Ten players in one match sums to ten |
| **Matches Played (weekly, monthly)** | **No** | Same |
| **Last Match Date** | **No** | **No date is stored on any record**, by design (§14.4) |

**All four are facts about matches, and their source is `matches`** — a count
of the community's matches in a window, and the latest start time. Both are
cheap, both are already indexed by `matches(community_id, start_at)`, and
storing them here would be a second answer to a question `matches` already
answers.

**So §7's opening sentence is true of the *level* and false of *this table*.**

**Not resolved silently.** The design is unchanged — §4.7 explains why
per-player-only is right — but §7 should be corrected to say that the
dashboard's community-history figures are read from the Match domain. Recorded
as `CS-D2`, with §19.1.

---

## 20. Build instruction

**There is no conformance section: the table does not exist.** What follows is
what building it entails.

| # | Requirement | Source |
|---|---|---|
| 1 | **Settle `CS-D2`** — the two documentation contradictions — before the entity is built to one reading and documented as the other | §19 |
| 2 | **Fix `A1` in one place** and record that it is frozen | `CS-C15`, §16.5 |
| 3 | **Build the reconciliation with the table, not after it** | `CS-C17`, DP-11, §16.3 |
| 4 | **Build the rebuild operation** — it is also the only honest backfill for item 5 | §16.3, `PS-D5` |
| 5 | **Backfill an `overall` record for every existing membership** | §2.2 |
| 6 | **Extend the shared contribution helper** rather than writing a second one | DP-6, §13 |
| 7 | **Apply and reverse as separate statements**, and **test the reversal against a real database** — `RR-4` passed inspection and a clean migration | `CS-C10`, `CS-R1` |
| 8 | **Build the read rule scoped to community membership**, and assert the denials | §10.2, `CS-R4` |

**Nothing was changed in this phase.** No code, no SQL, no migration and no
Supabase object was touched.

---

## 21. Engineering Approval

**Status: Engineering Approved.**

This document is the authoritative engineering specification for
`public.community_statistics`. The two contradictions **between approved
documents** that it was conditional on (§19) were **resolved on 2026-08-02**:
the Community Rating is a separate entity, and four of the ten dashboard
figures belong to the Match domain. This specification had followed both
correct readings already; the conflicting passages were corrected at source in
`Statistics_Leaderboards_MVP_Specification.md`. **`CS-D2` is closed.**

**A note on what is different about this one.** Every previous specification in
the phase documented and audited a table that exists. **This one designs one.**
Its findings are therefore risks to avoid rather than defects to fix — and three
of them (`CS-R1`, `CS-R4`, `CS-R6`) exist only as warnings **because earlier
phases found them the expensive way at Level 1**.

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5`, **with the likely misreading pre-empted** | ✓ §0 |
| Business purpose, business owner, domain ownership, lifecycle ownership | ✓ §1, all four |
| **Complete lifecycle** — nine transitions from join to rejoin, each explained; ten invalid | ✓ §2 |
| **Business responsibilities** — eight owned, nine not | ✓ §3 |
| **The model** — independence, counters, not ratings, not leaderboards, not history; **why the community dimension is fundamental; why the period dimension belongs here** | ✓ §4, seven of seven |
| Relationships: incoming, outgoing, ownership, deletion, lifecycle | ✓ §5 |
| Every column — name, purpose, type, nullability, default, editability, justification | ✓ 12 of 12, **all newly specified** |
| Every business constraint with its reason | ✓ 20, **including one (`CS-C5`) no approved document states and greenfield design must supply** |
| Keys: primary, **business key**, candidate, alternate, foreign — **a natural composite, no surrogate, ordered for the dominant read** | ✓ §8 |
| Index strategy: two required, four deferred with the trigger to revisit | ✓ §9 |
| Access control: player, member, admin, organizer, System Administrator × read/write/recalculate/delete | ✓ §10, **scoped correctly from the start** |
| Audit: all four columns ruled on | ✓ §11 |
| Dependencies both directions, including the unrepresented ones | ✓ §12 |
| **Eleven `DP-n` principles**, each validated, with the reading and basis marked | ✓ §13 |
| **Future compatibility**: season, tournament, league, custom periods, additional counters | ✓ §14 — **with the one case the period model does not yet support named** |
| **Engineering review** — ownership, duplication, derived-data, consistency, performance | ✓ §16, six findings |
| Validation; contradictions named, not resolved | ✓ 12 sources, **2 contradictions between approved documents** |
| No SQL, no migration, no Community Rating, no rating history, no leaderboards, no other table designed | ✓ |

### Validation caveat, stated rather than glossed

The brief names *Database Principles* as a validation source. **It does not
exist as a document in this repository** — the twelfth phase in which this has
been recorded. Nine of the eleven `DP-n` principles have no definition here;
§13 states the reading applied for each. `CS-D4` asks for confirmation, together
with `BDC-D4`, `MRS-D4`, `MG-D1` and `PS-D1`.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **The governing authority** — `SL-1`, `SL-2`, `SL-4`, `SL-5`, §9, §11. **Two of its passages are contradicted by other approved sources** (§19) |
| `Docs/06-ERD.md` §3 | **The conceptual model** — `E7`–`E10`, §3.4 ownership, §3.7 lifecycle, `A1`–`A7`. **The authority §19.1 follows** |
| `engineering/Player_Statistics_Table_Specification.md` | **The Level 1 sibling.** Its §4.5 is this document's §4.1; its `PS-R1` and `PS-R2` are applied preventively here |
| `engineering/Match_Results_Table_Specification.md` | The primary evidence; `MRS-R1` lands here |
| `engineering/Match_Goals_Table_Specification.md` | Evidence for one counter; `MG-R1` lands here |
| `engineering/Match_Team_Assignments_Table_Specification.md` | The derivation driver — `matches_played` counts its rows |
| `engineering/Matches_Table_Specification.md` | Supplies the community, the period's source timestamp, and the lock |
| `engineering/Communities_Table_Specification.md` | The parent that bounds this record's lifetime (`A7`) |
| `engineering/Community_Members_Table_Specification.md` | **Referenced at read time only, and never structurally** — `A7`, §4.5 |
| `engineering/Results_Rating_Engineering_Decisions.md` | **`RR-4`** (§16.1), `RR-6`, `RR-7` |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §4 — the one-public-table rule §10.2 exists to protect |
