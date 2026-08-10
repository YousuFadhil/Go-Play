# Community Dashboard — Read Model Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One open decision (`CD-D1`); see §17 and §18 |
| Role | **Engineering Authority** for the Community Dashboard read model |
| Owner | Product Owner |
| Phase | Database Design Engineering — Level 2 reads |
| Scope | **The Community Dashboard's ten figures only.** Leaderboards, the Player Profile and every table appear **only as sources or siblings** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024`; Level 2 approved and unbuilt |
| Date | 2026-08-02 |

> **This is a read specification, not a table specification.** It defines the
> complete read model of the Community Dashboard before any view, RPC or query
> is written, and it is the single authoritative reference for every dashboard
> read.
>
> **It is not a UI specification.** Layout, wording, formatting and localisation
> are outside it. What a figure *means* and *where it comes from* is inside it.
>
> **It contains no SQL, no view, no RPC and no implementation.** §10 states
> engineering recommendations for how each section should eventually be
> implemented; it designs none of them.
>
> **Governing documents were read, not recalled.** `SL-1`…`SL-5`, `A1`…`A7`,
> `OQ-1`…`OQ-9` and §7, §8, §9, §12 and §13 of the statistics specification were
> read in full for this document. §16 records one contradiction found — **and it
> is one this author introduced two turns ago.**

---

## 1. Purpose

### 1.1 Business purpose

The Community Dashboard answers one question: **what has this community done?**

Not what a player has done — that is the Player Profile, and it is a career
record with no community dimension. Not who is best — that is the leaderboards.
**The dashboard describes the community itself**: how much football it has
played, how many goals were scored in it, how many people have taken part, and
when it last played.

### 1.2 Why it exists

**Because a community is the product's unit of belonging, and belonging needs
evidence.** A member opening a community sees a roster and a fixture list, both
of which describe the present. The dashboard is the only surface that describes
**what the community has accumulated** — and it is what makes a two-year-old
community feel different from one created yesterday.

**It is also the only screen in the product that reads across two bounded
contexts** (§2.4), which is the whole reason this document exists: without a
single authority stating where each figure comes from, four of the ten would be
computed from the wrong place.

### 1.3 Business owner

**Product Owner**, as for every specification in this phase.

**The dashboard owns nothing** (§2), so there is no data ownership to assign.
What the Product Owner owns is **the definition of each figure** — what *Total
Matches* counts, and whether a departed member may be named as *Most Active
Player*. Both are live questions (§17).

### 1.4 Consumers

| Consumer | Reads |
|---|---|
| **A community member, in the app** | All ten figures, for one community |
| **Nobody else** | §9.3 — a non-member sees nothing |

**No system consumer.** Nothing in the database reads the dashboard: it is a
leaf of the read graph, and no figure it produces is stored, cached or fed back
into any table (§2.3).

---

## 2. Dashboard Architecture

### 2.1 The five statements

**Stated explicitly, as required, because every later section depends on them:**

| # | Statement | Consequence |
|---|---|---|
| 1 | **The dashboard owns no data** | It has no table, no column and no row. Every figure belongs to an entity that exists for its own reasons |
| 2 | **The dashboard writes nothing** | No read produces a side effect. There is no counter to bump, no timestamp to touch, no cache to populate |
| 3 | **The dashboard derives everything** | Every one of the ten figures is computed at read time from data written by another operation |
| 4 | **The dashboard is read-only** | Opening it changes nothing, and opening it twice yields the same answer unless the underlying data changed |
| 5 | **The dashboard is not a source of truth** | If a figure disagrees with its source, **the source is right**. The dashboard has no authority to be believed over the entity it read |

### 2.2 What follows from them

| Because | Therefore |
|---|---|
| It owns no data | **There is nothing to specify columns for**, which is why this document has a source matrix (§4) rather than a column specification |
| It writes nothing | **There is no write model, no access control for writes, and no audit** — the three sections every table specification carries are absent by construction |
| It derives everything | **Every figure has a freshness question**, answered in §11 |
| It is not a source of truth | **A stored dashboard figure would be a second answer** to a question an entity already answers — the duplication this schema has refused throughout |

### 2.3 The rule that keeps it true

> **No dashboard figure may ever be stored.** Not on `communities`, not on
> `community_statistics`, not anywhere. The moment a figure is stored it
> acquires a write path, a staleness window and a reconciliation problem — and
> the entity that owns the underlying fact acquires a rival.

**This rule has already been enforced twice in this phase**, in advance of this
document: the Communities specification refuses any count or last-match-date
column on `communities`, and the Community Statistics specification refuses a
community-wide row that describes no player.

### 2.4 The dashboard composes bounded contexts

**It is the only screen that does.** Ten figures, two contexts:

| Context | Figures | Owner |
|---|---|---|
| **Statistics** — Level 2 | 6 | `community_statistics` |
| **Match** | 4 | `matches`, and what a recorded result implies |

**Composition happens in the read, never in the data.** No entity is extended to
serve the dashboard, and no join is materialised. §10 recommends *where* the
composition should live; §6 explains *why* the split falls where it does.

---

## 3. Dashboard Sections

**Three sections, ten figures.** The section structure is the approved one and
is not redesigned here.

### 3.1 Section A — Overall

| # | Figure | Business meaning | Source entity | Read responsibility | Calculation responsibility | Refresh | Ownership |
|---|---|---|---|---|---|---|---|
| 1 | **Total Matches** | Matches this community has played | **Match domain** | The dashboard read | **A count of matches** — never a sum of appearances | On result recording, match deletion (§11) | `matches` |
| 2 | **Total Players** | Players who have taken part in this community | **Community Statistics** (`overall`) | The dashboard read | **A count of records with at least one appearance** (§5.2) | On result recording | `community_statistics` |
| 3 | **Total Goals** | Goals scored in this community's matches | **Community Statistics** (`overall`) | The dashboard read | **A sum** of the `goals` counter | On result recording | `community_statistics` |
| 4 | **Last Match Date** | When this community last played | **Match domain** | The dashboard read | **A maximum** over match start times | On match creation, edit, deletion, and possibly result recording (`CD-D1`) | `matches` |

**All four are community history** (§6) and are **unaffected by membership
changes** — §7.1 of the statistics specification: *"a departed member's matches
and goals remain counted, because they happened."*

### 3.2 Section B — This Week

| # | Figure | Business meaning | Source entity | Read responsibility | Calculation responsibility | Refresh | Ownership |
|---|---|---|---|---|---|---|---|
| 5 | **Matches Played** | Matches the community played within the current week | **Match domain** | The dashboard read | A count of matches, windowed | On result recording, match deletion | `matches` |
| 6 | **Goals Scored** | Goals scored in those matches | **Community Statistics** (`weekly`) | The dashboard read | A sum over the current week's records | On result recording | `community_statistics` |
| 7 | **Most Active Player** | The community's most active player over that week | **Community Statistics** (`weekly`) **+ `users`** | The dashboard read | **A maximum, then a name** (§5.7) | On result recording | `community_statistics`; the name from `users` |

### 3.3 Section C — This Month

| # | Figure | Business meaning | Source entity | Read responsibility | Calculation responsibility | Refresh | Ownership |
|---|---|---|---|---|---|---|---|
| 8 | **Matches Played** | Matches the community played within the current month | **Match domain** | The dashboard read | A count of matches, windowed | On result recording, match deletion | `matches` |
| 9 | **Goals Scored** | Goals scored in those matches | **Community Statistics** (`monthly`) | The dashboard read | A sum over the current month's records | On result recording | `community_statistics` |
| 10 | **Most Active Player** | The community's most active player over that month | **Community Statistics** (`monthly`) **+ `users`** | The dashboard read | A maximum, then a name | On result recording | `community_statistics`; the name from `users` |

### 3.4 What Sections B and C are, precisely

*"This Week and This Month read the same measures over a shorter window; they
introduce no measure the Overall block does not already have, **except Most
Active Player**."*

**So the dashboard has five distinct measures, not ten**: a match count, a
player count, a goal sum, a last-played date, and a most-active-player. Three of
the five appear in more than one window.

---

## 4. Data Source Matrix

**Complete, and no ambiguity remains.**

| # | Metric | Window | **Source entity** | Secondary source | Not from |
|---|---|---|---|---|---|
| 1 | Total Matches | Overall | **`matches`** | — | ✗ Community Statistics |
| 2 | Total Players | Overall | **`community_statistics`** (`overall`) | — | ✗ `community_members` |
| 3 | Total Goals | Overall | **`community_statistics`** (`overall`) | — | ✗ `match_goals` |
| 4 | Last Match Date | Overall | **`matches`** | — | ✗ Community Statistics |
| 5 | Matches Played | Weekly | **`matches`** | — | ✗ Community Statistics |
| 6 | Goals Scored | Weekly | **`community_statistics`** (`weekly`) | — | ✗ `match_goals` |
| 7 | Most Active Player | Weekly | **`community_statistics`** (`weekly`) | **`users`** — display name only | ✗ `community_members` for the measure |
| 8 | Matches Played | Monthly | **`matches`** | — | ✗ Community Statistics |
| 9 | Goals Scored | Monthly | **`community_statistics`** (`monthly`) | — | ✗ `match_goals` |
| 10 | Most Active Player | Monthly | **`community_statistics`** (`monthly`) | **`users`** — display name only | ✗ `community_members` for the measure |

### 4.1 Entities the dashboard reads, and what each contributes

| Entity | Contributes | Never contributes |
|---|---|---|
| **`matches`** | Metrics 1, 4, 5, 8 — every count of matches and the last-played date | Any per-player figure |
| **`community_statistics`** | Metrics 2, 3, 6, 7, 9, 10 — every per-player measure | Any count of matches (§6.2) |
| **`users`** | **Display names only**, for metrics 7 and 10 | Any measure |
| **`community_members`** | **No figure.** Visibility only, plus `OQ-3`'s open question (§9) | Any of the ten values |
| **`community_ratings`** | **Nothing today** (§8) | — |
| **`match_goals`, `match_results`, `match_team_assignments`** | **Nothing.** The dashboard never reads the evidence layer (§4.2) | — |

### 4.2 Why the evidence layer is never read

**Total Goals could be computed by summing `match_goals` for the community's
matches. It must not be.**

That query would **recompute the statistics engine in a read** — in a second
place, with no reversal path, and correct only by luck after a correction.
`SL-2` §2.3 forbids a leaderboard reading the wrong level for the same reason,
and the Match Goals specification §4.2 states it from the evidence side.

**The rule: the dashboard reads derived figures from the entity that owns them,
or facts about matches from the Match domain. It never derives a statistic
itself.**

---

## 5. Read Model

**Common to all ten:** every read is scoped to **one community**, supplied by the
caller and authorised by membership (§9.3). No dashboard read spans communities.

### 5.1 Metric 1 — Total Matches

| Aspect | |
|---|---|
| **Required inputs** | `community_id` |
| **Filtering** | Matches of this community **with a recorded result** — §6.3, resolved by `OQ-7` |
| **Eligibility** | **None.** Membership does not filter this figure |
| **Ordering** | None |
| **Grouping** | None |
| **Aggregation** | **Count of matches** |
| **Null behaviour** | Not nullable — a count is `0` or more |
| **Empty community** | **`0`** |
| **Tie behaviour** | Not applicable |
| **Read consistency** | See §5.11 |

### 5.2 Metric 2 — Total Players

| Aspect | |
|---|---|
| **Required inputs** | `community_id` |
| **Filtering** | `overall` records of this community **with at least one appearance** |
| **Eligibility** | **None** — departed members are counted (§6.1) |
| **Aggregation** | **Count of records** |
| **Empty community** | **`0`** |

**The appearance predicate is required, not optional.** An `overall` record is
created **at first join**, before any match is played, so a community of ten
members who have never played holds ten records of zeros. **Counting records
would report ten players who have "taken part" in nothing.**

**This is a direct consequence of the Community Statistics lifecycle** (§2.2 of
that specification) and is the single most easily-missed detail in this
document.

### 5.3 Metric 3 — Total Goals

| Aspect | |
|---|---|
| **Required inputs** | `community_id` |
| **Filtering** | `overall` records of this community |
| **Eligibility** | **None** — departed members' goals remain counted |
| **Aggregation** | **Sum** of the `goals` counter |
| **Null behaviour** | **Sum of an empty set is `0`, never null** — the read must coalesce |
| **Empty community** | **`0`** |

### 5.4 Metric 4 — Last Match Date

| Aspect | |
|---|---|
| **Required inputs** | `community_id` |
| **Filtering** | **`CD-D1` — open.** Either all matches whose start has passed, or only those with a recorded result (§17) |
| **Eligibility** | None |
| **Aggregation** | **Maximum** of `start_at` |
| **Null behaviour** | **Nullable** — the only nullable figure on the dashboard |
| **Empty community** | **Null**, rendered as an absence, never as a date |

### 5.5 Metrics 5 and 8 — Matches Played (weekly, monthly)

As metric 1, with one addition:

| Aspect | |
|---|---|
| **Filtering** | Matches of this community with a recorded result **whose start falls in the current period** |
| **Period boundary** | Derived from `start_at` in **`Asia/Muscat` (UTC+4)** — `A1`, `A3`, `OQ-6`. ISO-8601 weeks; calendar months |
| **Empty period** | **`0`** — a community that did not play this week reports zero, not an absence |

### 5.6 Metrics 6 and 9 — Goals Scored (weekly, monthly)

As metric 3, over the period's records:

| Aspect | |
|---|---|
| **Filtering** | `weekly` / `monthly` records of this community whose `period_key` is the current one |
| **Period key** | Computed by the reader from the clock in `Asia/Muscat`, then matched exactly — **never a range scan over keys** |
| **Empty period** | **`0`** — no records for that key means no goals |

### 5.7 Metrics 7 and 10 — Most Active Player

**The only figure that names a person, and the only one with an open
definition.**

| Aspect | |
|---|---|
| **Required inputs** | `community_id`, the current period key, and — for the name — `users` |
| **Filtering** | `weekly` / `monthly` records of this community for the current period, **with at least one appearance** |
| **Eligibility** | **`OQ-3` — open.** Whether a departed member may be named (§9.2) |
| **Ordering** | By `matches_played` descending |
| **Grouping** | None — one row per player already |
| **Aggregation** | **Maximum**, then the identity of the holder |
| **Null behaviour** | **Nullable.** No one played this period → no player to name |
| **Empty period** | **Null**, rendered as an absence |
| **Tie behaviour** | **`OQ-3` — open.** A deterministic tie-break is required; §17 recommends one |

**Two players with equal appearances is the common case, not the edge case**, in
a community where everyone plays every week. **A non-deterministic answer would
change between two loads of the same screen with no data change**, which is why
§17 treats the tie-break as required rather than cosmetic.

### 5.8 Ordering, grouping and aggregation — summary

| Metric | Ordering | Grouping | Aggregation |
|---|---|---|---|
| 1, 5, 8 | None | None | Count of matches |
| 2 | None | None | Count of records |
| 3, 6, 9 | None | None | Sum |
| 4 | None | None | Maximum |
| 7, 10 | **Descending by appearances** | None | **Maximum, then identity** |

### 5.9 Null behaviour — the complete rule

| Kind | Figures | Rule |
|---|---|---|
| **Counts and sums** | 1, 2, 3, 5, 6, 8, 9 | **Never null. Zero.** The read coalesces an empty aggregate to `0` |
| **A date** | 4 | **Nullable.** Absence means *never played* |
| **A person** | 7, 10 | **Nullable.** Absence means *nobody played this period* |

**Zero and null mean different things and must not be conflated**: `0` goals is
a fact about a period that happened; a null Most Active Player is the absence of
anyone to name.

### 5.10 Empty community behaviour

**A community with no matches and no play produces a complete, valid
dashboard**: seven zeros and three absences. **It is never an error, never an
empty state to be special-cased in the read**, and §12.1 states what that means
for presentation.

### 5.11 Read consistency

**The dashboard reads two bounded contexts, and a result recorded between the
two reads produces a screen that is internally inconsistent** — Total Goals
including a match Total Matches does not.

| Option | Assessment |
|---|---|
| **Ten independent queries** | **Skew is possible** on every recording. Cheapest, least correct |
| **One statement set inside one transaction** | **A consistent snapshot.** `READ COMMITTED` within a single statement is sufficient for each figure; **one transaction is what makes the ten agree** |
| Repeatable-read isolation | Unnecessary — a single transaction over ten fast aggregates already sees one snapshot per statement, and the window is milliseconds |

**Recommendation: one transaction, which §10 turns into one RPC.** The
inconsistency window is small and the consequence is cosmetic — but a screen
whose figures contradict each other is exactly the kind of defect that erodes
trust in every other figure.

---

## 6. Community History

### 6.1 The approved decision this section resolves

> **Community Statistics must never own match history.**

**Four of the ten figures are match history**, and this section states which and
why — resolving the ownership question in the direction the approved
architecture already requires.

| # | Figure | Why it is match history |
|---|---|---|
| 1 | **Total Matches** | It counts *matches*, which are Match-domain entities |
| 4 | **Last Match Date** | It is a *date on a match*. No date exists anywhere in the statistics model |
| 5 | **Matches Played** (weekly) | As #1, windowed |
| 8 | **Matches Played** (monthly) | As #1, windowed |

### 6.2 Why Community Statistics cannot supply them — the arithmetic

**Summing each player's Matches Played counts appearances, not matches.**

> Ten players in one match sum to **ten**.

**There is no per-player figure from which a match count can be recovered**,
because the divisor — how many players were in each match — varies per match and
is not stored in the statistics model.

**And no date exists to take a maximum of.** A statistics record carries a
period *key*, not a timestamp: `2026-W31` names a window, and its boundaries are
computed from `A1`'s reference zone rather than stored. Deriving *when the
community last played* from a period key would give the **week**, never the
**day**.

### 6.3 Which matches count — resolved by `OQ-7`

`OQ-7` is **resolved**: *"Statistics arise only from a recorded result… A match
that was played but never recorded produces nothing at either level."*

**Applied to the dashboard's match counts** — metrics 1, 5 and 8 — this fixes
the basis: **matches with a recorded result**. It is not a new decision; it is
the existing one applied consistently, and it is what makes Total Matches and
Total Goals describe **one population**.

**Last Match Date is the one figure `OQ-7` does not settle**, because it answers
a *recency* question rather than a *counting* one — §17, `CD-D1`.

### 6.4 The rule this establishes

> **A dashboard figure about *matches* is read from the Match domain. A
> dashboard figure about *players* is read from Community Statistics. No figure
> crosses.**

**This is the only clean boundary available**, and it is the one the approved
architecture already implies. §14.2 records that the alternative — a
community-wide statistics row describing no player — was considered and refused
in the Community Statistics specification before this document existed.

---

## 7. Community Statistics Consumption

**Six of the ten figures. Three period types, consumed differently.**

### 7.1 What is consumed, by period

| Period | Figures | Counters read | Records read |
|---|---|---|---|
| **`overall`** | 2 (Total Players), 3 (Total Goals) | `matches_played` *(as a predicate only)*, `goals` | Every `overall` record of the community |
| **`weekly`** | 6 (Goals Scored), 7 (Most Active Player) | `goals`, `matches_played` | Records whose `period_key` is the current ISO week |
| **`monthly`** | 9 (Goals Scored), 10 (Most Active Player) | `goals`, `matches_played` | Records whose `period_key` is the current month |

### 7.2 Why each period is consumed the way it is

**`overall` — because "total" means all time.** Total Goals and Total Players
describe the community's whole history, which is exactly what the `overall`
period is: *"everything in that community, with no time boundary."*

**`weekly` and `monthly` — because the window is the question.** *This Week* is
not a filter applied to the overall record; it is **a different record**, and
`SL-1` §9.4's worked example makes that explicit: one match updates three
records, one per period.

**So the dashboard never computes a period by filtering.** It selects the
record whose `period_key` matches the current period, computed from the clock in
`Asia/Muscat`. **Summing an overall record and subtracting would be wrong** —
and impossible, since no record carries dates.

### 7.3 Which counters are never consumed

**Four of the six counters are never read by the dashboard:** `wins`, `losses`,
`draws`, and `mvp_count`.

| Counter | Read by |
|---|---|
| `matches_played` | **Metric 7 and 10** as a measure; **metric 2** as a predicate |
| `goals` | Metrics 3, 6, 9 |
| `wins`, `losses`, `draws` | **Nothing on this screen.** The Player Profile reads their Level 1 equivalents |
| `mvp_count` | **The *Most MVP* leaderboard**, not the dashboard |

**Stated because it constrains a future change**: adding a *Win Rate* block to
the dashboard would consume counters nothing currently reads, which is additive
and needs no schema change (§13.4).

### 7.4 The one predicate that is not a measure

**Metric 2 reads `matches_played` to decide whether a record counts, not to
report it** — §5.2. It is the only place on the dashboard where a counter is a
filter rather than a value, and forgetting it inflates Total Players by every
member who has never played.

---

## 8. Community Rating Consumption

### 8.1 Today: **none**

**No dashboard figure consumes the Community Rating.** Not one of the ten.

This is not an oversight and not a gap. The governing documents say so from two
directions:

| Source | Statement |
|---|---|
| **§7, "On ratings"** | *"No block above displays a rating today, so the rule is immediately operative as a prohibition and forward-looking as a permission."* |
| **§12, out of scope** | *"Displaying a Community Rating inside a community context (v1.3). Future versions may choose to; the MVP does not."* |

### 8.2 The forward-looking permission, stated precisely

`SL-3` §3.2 lists the **Community Dashboard** as a user of the Community Rating.
**That is a permission, not a current reader.** The reconciliation is §7's:

> **If a rating is ever shown on this screen it is the Community Rating, never
> the Global Rating — and adding one is a scope change requiring approval.**

**So the binding rule today is a prohibition**: the dashboard must not display
the Global Rating, in any block, in any period. `SL-3` §3.1 forbids it
explicitly.

### 8.3 Why the Community Rating is independent from Community Statistics

**Required by the brief, and the answer is a cardinality argument before it is
anything else:**

| | Community Statistics | Community Rating |
|---|---|---|
| Identified by | player + community + **period** | player + community |
| Cardinality | **Several** per pair | **Exactly one** per pair |
| Kind of number | **Accumulating counters** — start at zero, only move by what happened | **A running value** — starts at `5.00`, has no natural zero, does not restart |
| Reset by a period | Conceptually yes — a new week is a new record | **Never.** It does not restart |

**`SL-3` states the independence directly:** *"Neither rating is derived from
the other, neither is a view of the other, and the two are expected to differ."*
And `SL-5` settles the period question: the three named forms are **boards, not
stored ratings** — the period selects who is eligible to appear, never which
value is shown.

**For the dashboard specifically, the consequence is simple**: if a rating is
ever added, it is **one number per player**, not a per-period one, and it cannot
be aggregated into a community-level figure without inventing a measure nobody
has approved (§13.5).

---

## 9. Community Membership Consumption

**Membership affects the dashboard in exactly two ways — and produces no figure
at all.**

### 9.1 Where membership is consumed

| Use | Affects | Status |
|---|---|---|
| **Visibility** | *Whether the dashboard may be read* | §9.3 — settled |
| **Most Active Player eligibility** | *Whether a departed member may be named* | **`OQ-3` — open** (§17) |
| **Every other figure** | **Nothing** | §9.4 — settled |

### 9.2 Eligibility — the one open use

`OQ-3` leaves open *"whether a departed member may be named"* as Most Active
Player.

**It matters because the dashboard names a person**, and the other nine figures
do not. A departed member's *goals* remaining in Total Goals is uncontroversial —
they happened. **A departed member appearing on the screen by name is a
different question**, and it is the same question the leaderboards answer with
*"only active members appear."*

§17 records the recommendation.

### 9.3 Visibility — who may read the dashboard

**Members of that community, and nobody else.**

Every source the dashboard reads is community-scoped by its own specification:
`community_statistics` reads are scoped to members; `matches` are visible to
members of the match's community; `users` display names are visible under `UP-1`
tier 2, which is satisfied because the named player shares this community.

**So the dashboard needs no access rule of its own** — it inherits one from
every source, and the composition is readable exactly when all its parts are.

**One consequence worth stating**: a departed member cannot read the dashboard
of the community they left, including the figures their own play contributed to.
That is consistent with every other community-scoped read and contradicts
nothing.

### 9.4 Current member count is **not** a dashboard figure

**The brief lists it as an example of membership consumption. It is not one of
the ten.**

**And it must not be confused with Total Players**, which is the figure it most
resembles:

| | Total Players (metric 2) | Current member count |
|---|---|---|
| Question | *How many people have taken part?* | *How many people are here now?* |
| Source | **`community_statistics`** | **`community_members`** |
| Counts departed members | **Yes** — they took part | **No** |
| Counts members who never played | **No** (§5.2) | **Yes** |
| On the dashboard | **Yes** | **No** |

**If a current member count is ever added**, it is a `community_members` read
and needs no statistics involvement — additive, and §13.4 records it.

### 9.5 Permission and ownership

**Neither affects any figure.** No dashboard value differs for an owner, an
admin or a player. **Role grants nothing on this screen** — which is right,
because the dashboard describes the community rather than the reader's standing
in it.

---

## 10. Performance Model

**Engineering recommendation only. No SQL, no view, no RPC is designed here.**

### 10.1 Per section

| Section | Recommendation | Why |
|---|---|---|
| **Overall** | **One RPC, returning all four** | It composes two bounded contexts; a single call gives a consistent snapshot (§5.11) and one round trip |
| **This Week** | **The same RPC** | Same sources, same shape, same snapshot |
| **This Month** | **The same RPC** | Same |

### 10.2 The recommendation, stated once

> **One read operation returning all ten figures for one community.**

| Approach | Verdict |
|---|---|
| **One RPC** | **Recommended.** Consistency (§5.11), one round trip, one place for the period arithmetic (`A1`) |
| **A view** | **Rejected for the composite.** A view cannot take *now* as a parameter cleanly, and the weekly and monthly figures depend on the current period computed in a fixed zone |
| **Direct queries from the client** | **Acceptable as an MVP fallback**, at the cost of skew and of the period arithmetic living in the client |
| **Materialized read** | **Rejected for the MVP.** The volumes are trivial; a materialized view introduces a refresh policy the product does not need and a staleness window §11 does not want |

### 10.3 Why an RPC rather than a view, in more detail

**Three reasons, and the second is decisive:**

1. **The period must be computed in `Asia/Muscat`, once.** A view would either
   hard-code the zone or recompute it per reference; an RPC computes the two
   period keys once and uses them for four figures.
2. **A view cannot give a transactional snapshot across ten aggregates** unless
   the caller wraps it — which is the RPC by another name.
3. **The `SECURITY DEFINER` question does not arise.** Every source is already
   readable by a community member, so the operation needs no elevated
   privilege — **and it should not have one.** A `SECURITY INVOKER` operation
   inherits each source's access rule, which is exactly §9.3's argument.

**This is a departure from the project's usual pattern worth naming**: the
convention is *"multi-step writes go through `SECURITY DEFINER` RPCs; reads go
through RLS."* **This is a read, and it should stay under RLS** — the RPC is for
composition and consistency, not for privilege.

### 10.4 Index support

**No new index is required.** Every read is served by an index the source
specifications already require:

| Read | Served by |
|---|---|
| A community's matches, windowed | `matches(community_id, start_at)` — `MT-X2` |
| A community's statistics records, by period | `community_statistics(community_id, period_type, period_key, user_id)` — `CS-X1` |
| A display name | The `users` primary key |

**Metric 2's appearance predicate and metric 7's maximum are both evaluated
over an already-narrowed set** — one community, one period — so neither needs
its own index. §13.6 records when that changes.

---

## 11. Refresh Model

### 11.1 Every figure is real-time

**Nothing is cached, nothing is materialised, nothing is precomputed.** All ten
are computed at read time from current data.

| Class | Figures | Status |
|---|---|---|
| **Real-time** | **All ten** | Computed on read |
| **Cached** | None | — |
| **Eventually consistent** | None | — |
| **Materialised** | None | — |

### 11.2 What changes each figure

| Event | Changes |
|---|---|
| **A result is recorded** | **All ten**, potentially — the match now counts, its goals enter the statistics, appearances rise |
| **A result is corrected** | The same ten. Reversal and re-application both run before the next read |
| **A match is deleted** | All ten — the reversal runs first, then the match disappears from the counts |
| **A match is created or its time edited** | **Metric 4 only**, and only under one reading of `CD-D1`; the counts are unaffected until a result exists |
| **A player joins or leaves** | **Nothing** — except `OQ-3`'s open question for metrics 7 and 10 |
| **An account is deleted** | Their statistics records cascade, so metrics 2, 3, 6, 7, 9, 10 change |

### 11.3 Values refreshed after match result recording

**All six statistics-derived figures, and the three match counts.** That is nine
of the ten; only Last Match Date may be unaffected, depending on `CD-D1`.

**The refresh is not an operation.** Recording a result updates the underlying
entities inside its own transaction; the dashboard simply reads newer data on
its next load. **There is nothing to invalidate and nothing to trigger.**

### 11.4 Why nothing is cached

| Reason | |
|---|---|
| **The volumes are trivial** | The PRD's success criteria are three communities and ten matches. Ten aggregates over tens of rows |
| **A cache needs invalidation** | Which means a write path on a read model — breaking §2.1 statement 2 |
| **Staleness is worse than cost here** | A member who records a result and opens the dashboard expects to see it. A stale figure would look like a lost result |

**Revisit only on measurement**, and §13.6 states what would change first.

---

## 12. Failure Behaviour

**None of these is an error.** Every one produces a valid dashboard.

| Condition | Behaviour |
|---|---|
| **Zero players** | Seven zeros, three absences. A community created a minute ago |
| **Zero matches** | Same — the two are indistinguishable on this screen, correctly, because neither has produced anything |
| **No ratings** | **No effect.** The dashboard consumes no rating (§8) |
| **No statistics records** | Metrics 2, 3, 6, 7, 9, 10 → `0`, `0`, `0`, null, `0`, null |
| **Statistics records that are all zeros** | **Metric 2 reports `0`**, because of the appearance predicate (§5.2) — a community whose members have all joined but never played |
| **Deleted users** | Their records cascade away, so their goals and appearances leave every figure. **Total Matches and Last Match Date are unaffected** — the matches happened |
| **Departed members** | **No effect on nine figures** — their contributions remain (§6.1). **Metrics 7 and 10 depend on `OQ-3`** |
| **Rejoined members** | **No effect.** Their records were never removed, so nothing re-enters |

### 12.1 The empty dashboard is a presentation question, not a read one

**The read model always returns ten values.** Whether a community with nothing
to show is rendered as zeros or as an onboarding prompt is a UI decision, and
this document does not take it.

**What it does state**: the read must not signal emptiness by failing, by
returning no row, or by returning null where §5.9 requires zero.

### 12.2 One inherited exposure

**Deleting the account of a match's MVP or scorer destroys that result without
reversing it** (`MRS-R1`, `MG-R1`). The dashboard would then show goals in Total
Goals that no surviving result explains, and a Total Matches that no longer
counts the match.

**Not this document's defect** — it is recorded against the tables that own the
cascades — but **the dashboard is where a user would first see the
inconsistency**, which is worth knowing when one is reported.

---

## 13. Future Compatibility

### 13.1 Charts, trend graphs and activity heatmaps

**All three are out of scope** — §12 lists *"charts and any graphical
presentation of statistics."*

**Compatibility, when approved:** a chart of *goals per week over the last
twelve weeks* is **twelve reads of an existing record shape**, one per
`period_key`. **No schema change, no new entity, no new measure.** The period
model was designed for exactly this: *"a scope is not a different kind of
record."*

**The one thing that would need care**: a chart needs *every* period in a range,
including periods with no play — which have **no record** (§2.3 of the Community
Statistics specification). **The reader must supply the missing periods as
zeros**, because absence and zero mean different things in the store and the
same thing on a chart.

### 13.2 Analytics, trends and projections

**Out of scope**, and the boundary is stated in the governing document: *"The
MVP shows recorded numbers for three periods. It does not interpret them."*

**Compatibility: unaffected.** Interpretation is a read-layer concern and needs
no stored value. **The rule to preserve is that no interpreted figure is ever
stored** — a stored trend is a second answer to a question the records already
answer, with a staleness window.

### 13.3 Historical comparison

*"This month vs last month"* is **two reads of the same record shape**, with
different `period_key` values. **Already supported.**

**And "as of" views of a past leaderboard are explicitly out of scope** — §12 —
which this document does not revisit.

### 13.4 Growth metrics

*Members joined this month*, *first-time players this week*, *current member
count*.

| Metric | Source | Change needed |
|---|---|---|
| Current member count | `community_members` | **None** — a count of an existing table (§9.4) |
| Members joined in a period | `community_members.created_at` | **None** — but note that a rejoin recreates the row, so it counts as a new join |
| First-time players in a period | `community_statistics.created_at` | **None** — and this one is *not* affected by a rejoin, because `SL-4` preserves the record |

**That last row is a genuine capability the current design already has**, and it
falls out of `SL-4`'s preservation rule rather than being designed for.

### 13.5 What would need a decision rather than a query

| Candidate | Why |
|---|---|
| **A community-average rating** | It would be a **new measure**, not a new read. Nobody has approved one, and aggregating a per-player running value into a community figure is a statistical choice, not an engineering one |
| **A win-rate block** | Reads counters nothing currently consumes (§7.3) — additive, but the definition (draws counted how?) is a Product decision |
| **Any figure spanning communities** | **Out of scope permanently** — §12, *"global rankings across communities."* The dashboard describes one community |

### 13.6 When the performance model changes

**Two triggers, both measurable:**

1. **A chart over many periods** — twelve reads instead of one. `CS-X1` serves
   each, but the composite RPC would grow; a range scan over `period_key` is
   what the sortable key format was chosen to allow.
2. **A community with thousands of players** — metric 2's count and metric 7's
   maximum both scan one community's records. At that size a covering index
   becomes worth measuring, and §9.2 of the Community Statistics specification
   already names the candidate.

---

## 14. Engineering Review

**Seven audits, as required.**

### 14.1 Ownership — clean, and the boundary is the finding

**No ownership violation.** The dashboard owns nothing (§2.1), stores nothing
(§2.3) and has no write path to violate.

**The finding is that ownership was easy to get wrong and is now fixed**: four
figures look like statistics and are not (§6). Without §4's matrix, an
implementer summing `matches_played` for Total Matches would produce a number
ten times too large **and it would look plausible**.

### 14.2 Duplicated responsibility — none, and one was refused in advance

**No figure is computed in two places, and none may be stored** (§2.3).

**The duplication that was available was refused before this document existed**:
the Community Statistics specification §4.7 considered a community-wide row with
a null player — which would have made Total Matches a stored counter — and
refused it on three grounds, one of which was that it would duplicate a fact the
Match domain owns.

**So the boundary §6.4 states is not new. This document names it; the entity
specifications already enforced it.**

### 14.3 Violation of approved architecture — none

| Constraint | Status |
|---|---|
| Dashboard is a read model only | ✓ §2 |
| Dashboard owns nothing | ✓ §2.1 |
| Dashboard never updates data | ✓ §2.1, §11.3 |
| Community Statistics independent from Community Rating | ✓ §8.3 |
| Community Rating is a separate entity | ✓ §8.3 |
| Community Statistics never owns match history | ✓ **§6 — resolved explicitly** |
| Match history belongs to the Match domain | ✓ §6.4 |
| Dashboard composes bounded contexts | ✓ §2.4 |

### 14.4 Performance risks — low, with one named threshold

Every read is an index seek on a narrow set. **The composite is ten aggregates
over one community**, which at the PRD's targets is trivial.

**The threshold is §13.6's**: charts over many periods, or a community with
thousands of players. **Neither is near.**

### 14.5 Read consistency — one real risk, one recommendation

§5.11. **Ten independent reads can produce a self-contradicting screen.** The
window is milliseconds and the consequence is cosmetic, but it is visible and
it undermines confidence in figures that are otherwise correct.

**Recommendation: one operation, one transaction** (§10.2).

### 14.6 Separation of concerns — sound

| Concern | Where it lives |
|---|---|
| What a figure means | **This document** |
| Where it comes from | **This document**, §4 |
| How it is computed | **This document**, §5 |
| How it is fetched | §10, as a recommendation only |
| How it is displayed | **Nowhere here** — a UI concern |
| What the underlying data means | The entity specifications |

### 14.7 Aggregate boundaries — respected, and the composition is explicit

**The dashboard crosses an aggregate boundary, and that is allowed because it
only reads.**

| Boundary | Crossed how |
|---|---|
| Match aggregate | **Read only** — four figures. No match is modified, no lock taken |
| Community aggregate | **Read only** — visibility is resolved through membership |
| Statistics | **Read only** — six figures |

**The rule this establishes**: *a read model may compose across aggregates; a
write may not.* Every write in this schema originates from one aggregate root
and stays inside it. **The dashboard is the first thing in the project that
legitimately spans two, and it can only because it changes nothing.**

---

## 15. Risks

### 15.1 High

| ID | Risk | Cause | Impact | Recommendation |
|---|---|---|---|---|
| `CD-R1` | **Total Matches computed by summing appearances** | The figure looks like a statistic, and `community_statistics` holds a counter called `matches_played` | **A number roughly ten times too large, that looks plausible** and would not be caught by any constraint | **§4's matrix is normative.** Metrics 1, 5 and 8 come from `matches`. Assert the distinction in a test with a multi-player match |

### 15.2 Medium

| ID | Risk | Cause | Impact | Recommendation |
|---|---|---|---|---|
| `CD-R2` | **Total Players counts members who have never played** | An `overall` record is created **at join**, before any match | A community of ten who have never played reports ten players who "have taken part" | **The appearance predicate is required** (§5.2), not an optimisation |
| `CD-R3` | **Self-contradicting screen** from independent reads | Ten reads across two contexts, no shared snapshot | Total Goals includes a match Total Matches does not | **One operation, one transaction** (§10.2) |
| `CD-R4` | **Most Active Player changes between loads with no data change** | No deterministic tie-break (`OQ-3`) | The screen looks unreliable | **Settle `OQ-3`** with a deterministic tie-break (§17) |
| `CD-R5` | **Inherited: an account deletion destroys a result without reversing** | `MRS-R1`, `MG-R1` | Dashboard figures disagree with the matches that produced them, and **this is where a user notices** | Not this document's to fix. Close at source |

### 15.3 Low

| ID | Risk | Cause | Impact | Recommendation |
|---|---|---|---|---|
| `CD-R6` | **Period computed in the wrong zone** | The weekly and monthly figures depend on `A1` | Figures land in the wrong week near midnight | **Compute the period keys once, server-side** (§10.3) — never in the client |
| `CD-R7` | **Null rendered as zero, or zero as absence** | §5.9's two kinds of emptiness | *Never played* shown as a date, or `0` goals shown as "—" | The read returns them distinctly; presentation must preserve the distinction |
| `CD-R8` | **A chart later reads only existing period records** | Periods with no play have no record | Gaps silently omitted rather than shown as zero | **§13.1** — the reader supplies missing periods as zeros |

---

## 16. Contradictions

**One found — and it is one this author introduced.**

### 16.1 `CD-X1` — §7 re-opens a question `OQ-7` had already resolved

**The passage**, added to §7 of the statistics specification on 2026-08-02 as
part of the dashboard-ownership correction:

> *"**One definition remains open.** Whether Total Matches counts every
> completed match or only those with a recorded result."*

**`OQ-7`, twelve sections later in the same document, is marked RESOLVED**:

> *"Do the periodic scopes apply to completed matches with a recorded result
> only? **RESOLVED by inheritance** — yes… Statistics arise only from a recorded
> result… **Nothing was decided here.**"*

**So the question was already answered when it was re-raised.** The passage is
wrong, and it is wrong in the governing document rather than in a table
specification — which makes it the most consequential kind of error to leave
standing.

**Cause.** The dashboard-ownership correction was written from the metric
tables in §7 without re-reading §13's resolved list. **The instruction to read
the governing documents rather than rely on memory exists precisely for this**,
and it was not followed closely enough two turns ago.

**Resolution — and it is not silent.** §6.3 of this document records the
correct position: **`OQ-7` fixes the basis at *matches with a recorded result*,
and the dashboard's match counts inherit it.** The §7 passage should be
corrected to say so, and this document reports the change rather than making it
quietly.

**One part genuinely remains open, and it is narrower than the passage claimed**:
`OQ-7` governs figures that *count*; **Last Match Date answers a recency
question**, and applying the recorded-result basis to it would show a stale date
whenever a result is pending. That is `CD-D1` (§17) — a real open decision, and
the only one.

### 16.2 Checked and found consistent

| Potential conflict | Verdict |
|---|---|
| `SL-3` §3.2 lists the Dashboard as a Community Rating reader; §12 places rating display out of scope | **Reconciled by §7's "On ratings"** — a prohibition now, a permission later. Not a contradiction (§8.2) |
| §7.1 says Overall figures are unaffected by membership; `SL-5` says boards show active members only | **Not a conflict** — different screens, different rules. The dashboard's totals are history; a board ranks people (§9.2) |
| Total Players resembles a member count | **Not a conflict** — two different questions, two sources (§9.4) |

---

## 17. Open Decisions

**One, and it is genuinely required.**

| ID | Question | Recommendation |
|---|---|---|
| `CD-D1` | **Does *Last Match Date* count matches with a recorded result, or every match whose start has passed?** | **Every match whose start has passed.** It answers *when did we last play*, which is a fact about the fixture rather than about the result — and the recorded-result basis would show a stale date for as long as an organiser has not recorded a result. **This is the one place the two bases legitimately differ**, and §6.3 explains why `OQ-7` does not settle it |

**`OQ-3` is noted, not re-opened.** It belongs to the statistics specification
and is recorded there as non-blocking. **This document's recommendation, for
whoever closes it:**

| Part | Recommendation |
|---|---|
| Measure | Participation count within the window — already the default |
| **Tie-break** | **Required, and deterministic.** Recommend most appearances, then most goals in the same period, then the earliest `created_at` of the statistics record. **A non-deterministic answer is `CD-R4`** |
| Departed members | **Do not name them.** The figure names a person on the community's screen, and the leaderboards already answer this with *"only active members appear"* |

---

## 18. Engineering Approval

**Status: Engineering Approved — conditional** on `CD-D1`.

**The conditional item is narrow**: one figure's filter, with a recommendation.
Nine of the ten figures are fully specified and unambiguous.

| Criterion | Status |
|---|---|
| Purpose, why it exists, business owner, consumers | ✓ §1 |
| **Dashboard architecture — the five statements** | ✓ §2 |
| Dashboard sections — every metric with meaning, source, read and calculation responsibility, refresh, ownership | ✓ §3, ten of ten |
| **Data source matrix — no ambiguity** | ✓ §4 |
| Read model — inputs, filtering, eligibility, ordering, grouping, aggregation, null, empty, tie, consistency | ✓ §5 |
| **Community history — the approved decision resolved explicitly** | ✓ §6 |
| Community Statistics consumption, by period, with reasons | ✓ §7 |
| Community Rating consumption — **none today**, with the permission recorded | ✓ §8 |
| Community membership consumption — visibility, eligibility, and what it does **not** affect | ✓ §9 |
| Performance model — per section, recommendation only | ✓ §10 |
| Refresh model | ✓ §11 |
| Failure behaviour — eight conditions | ✓ §12 |
| Future compatibility — six candidates | ✓ §13 |
| Engineering review — seven audits | ✓ §14 |
| Risks — High, Medium, Low, each with cause, impact, recommendation | ✓ §15, eight risks |
| **Contradictions — one found and reported, not silently resolved** | ✓ §16 |
| Open decisions | ✓ §17, one |
| No SQL, no view, no RPC, no implementation | ✓ |

---

## 19. Validation

**Governing documents were read for this specification**, not recalled: §7, §8,
§9, §12 and §13 of the statistics specification in full, and the entity
specifications for every source.

| # | Source | Verdict |
|---|---|---|
| 1 | `Statistics_Leaderboards_MVP_Specification.md` §7 | **One contradiction — `CD-X1`** (§16.1), introduced by this author |
| 2 | Same, `SL-1`…`SL-5` | **No contradiction.** `SL-1`'s period model is §7.2; `SL-2`'s isolation is inherent; `SL-3`/`SL-5` are §8 |
| 3 | Same, `OQ-3`, `OQ-6`, `OQ-7` | **`OQ-7` applied** (§6.3); `OQ-6`'s zone is §5.5; `OQ-3` noted, not re-opened (§17) |
| 4 | Same, §12 out of scope | **No contradiction.** §13 evaluates each listed item without proposing scope change |
| 5 | `Community_Statistics_Table_Specification.md` | **No contradiction.** Its §4.7 (per-player only) is §6.2 here; its §2.2 (creation at join) is why §5.2's predicate exists |
| 6 | `Community_Rating_Table_Specification.md` | **No contradiction.** Its §1.1 names the dashboard as a forward-looking consumer; §8.1 confirms none today |
| 7 | `Matches_Table_Specification.md` | **No contradiction.** Its §14.3 states no count or last-match-date is stored on a match — which is why §6 reads them |
| 8 | `Communities_Table_Specification.md` | **No contradiction.** Its §6.3 and §10.3 refuse any stored total on `communities` |
| 9 | `Community_Members_Table_Specification.md` | **No contradiction.** Membership supplies visibility and `OQ-3`; no figure (§9) |
| 10 | `Profiles_Table_Specification.md` | **No contradiction.** `UP-1` tier 2 covers the display names in metrics 7 and 10 |
| 11 | `Match_Goals_Table_Specification.md` | **No contradiction.** Its §4.2 forbids computing statistics from evidence — §4.2 here |
| 12 | `Docs/01-PRD.md` | **No contradiction.** *The Community Dashboard* is in MVP scope; charts and analytics are not |
| 13 | `Docs/06-ERD.md` §3 | **No contradiction.** `E7` and `E8` are separate; `A1`, `A3` govern the period arithmetic |
| 14 | **Database Principles** | **No artifact in the repository** — sixteenth phase |
| 15 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **No contradiction.** §10.3 keeps the read under RLS rather than elevating it |

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **The governing authority** — §7 defines the ten figures; `OQ-3` and `OQ-7` bear directly on §6.3 and §17. **§16.1 reports a needed correction to its §7** |
| `engineering/Community_Statistics_Table_Specification.md` | **Six figures.** Its creation-at-join lifecycle is why §5.2 needs an appearance predicate |
| `engineering/Matches_Table_Specification.md` | **Four figures.** Its refusal to store counts is why they are read |
| `engineering/Community_Rating_Table_Specification.md` | **Zero figures today** — §8 |
| `engineering/Community_Members_Table_Specification.md` | Visibility and `OQ-3`; no figure |
| `engineering/Communities_Table_Specification.md` | Refuses any stored dashboard total |
| `engineering/Profiles_Table_Specification.md` | `UP-1` tier 2 — the display names |
| `Docs/06-ERD.md` §3 | `A1`, `A3` — the period arithmetic |
| `Docs/01-PRD.md` | Places the dashboard in MVP scope and charts out of it |
