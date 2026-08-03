# Community Leaderboards — Read Model Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One scope contradiction to settle (`LB-X1`) and two open decisions; see §16, §17, §18 |
| Role | **Engineering Authority** for every Community Leaderboard read |
| Owner | Product Owner |
| Phase | Database Design Engineering — Level 2 reads |
| Scope | **The nine approved leaderboards.** The dashboard, the Player Profile and every table appear **only as sources or siblings** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024`; Level 2 approved and unbuilt |
| Date | 2026-08-02 |

> **This is a read specification.** It freezes the read architecture of every
> MVP leaderboard before any view, RPC or query is written.
>
> **It is not a UI specification, not SQL, not an implementation, and not a view
> or RPC design.** §10 states engineering recommendations; it designs nothing.
>
> **Governing documents were read, not recalled.** `SL-2` §2.3, `SL-4`, `SL-5`
> in full, §8, §9, §12 and §13 of the statistics specification, and the entity
> specifications for all four sources.
>
> **§16 records one contradiction between this brief and the approved
> architecture**, and one imprecision in the governing document. Neither is
> resolved silently.

---

## 1. Purpose

### 1.1 Business purpose

A leaderboard answers: **who is best, among the people you actually play
with?**

**The second half of that sentence is the whole design.** `SL-2` §2.4 states
it: *"a leaderboard is only meaningful if it ranks people against the players
they actually play with. A board fed from career totals would rank a community
by achievements earned elsewhere."*

**So every board is bounded twice** — by one community, and by one period — and
every rule in this document follows from those two bounds.

### 1.2 Scope

**The nine approved leaderboards**: three board types × three periods.

| Board type | Ranks by |
|---|---|
| **Highest Rated** | Current Community Rating |
| **Top Scorers** | Goals in the period |
| **Most MVP** | MVP count in the period |

| Period | Window |
|---|---|
| **Overall** | All time |
| **Weekly** | The current week |
| **Monthly** | The current month |

**Two board types named in this phase's brief are *not* in the approved set** —
*Most Matches Played* and *Most Wins*. §16.1 records the discrepancy; §13.7
states what adding them would take. **They are not specified here as MVP
boards.**

### 1.3 Consumers

| Consumer | Reads |
|---|---|
| **A community member, in the app** | Any of the nine, for one community |
| **Nobody else** | §5.3 — a non-member sees nothing |

**No system consumer.** No board result is stored, cached or read by anything
in the database (§2).

### 1.4 Business owner

**Product Owner.** The boards own no data (§2), so what the owner owns is **the
definitions**: which boards exist (§16.1), how deep they go and how ties break
(`OQ-4`), and whether a zero-valued entry appears at all (`LB-D1`).

---

## 2. Read Architecture

### 2.1 The five statements

| # | Statement | Consequence |
|---|---|---|
| 1 | **Leaderboards own no data** | No table, no column, no row. Every value belongs to an entity that exists for its own reasons |
| 2 | **Leaderboards write nothing** | Reading a board has no side effect. No rank is stored, no "last computed" timestamp exists |
| 3 | **Leaderboards derive everything** | Rank, population and eligibility are all computed at read time |
| 4 | **Leaderboards are read models** | They compose sources; they do not extend them |
| 5 | **Leaderboards never become sources of truth** | If a board disagrees with its sources, **the sources are right** |

### 2.2 The rule that keeps it true

> **No rank, no board position and no board membership may ever be stored.**

**A stored rank would need invalidating on every recorded result, in every
community, for every period** — and would be wrong between the result and the
refresh. **Eligibility in particular is never stored**: `SL-4` §4.5 is explicit
that *"it is not a flag written onto the record, and it never changes a stored
number."*

### 2.3 Boards and the dashboard are independent read models

**They share sources and must never share a read.**

| | Dashboard | Leaderboards |
|---|---|---|
| Describes | **The community** | **The players in it** |
| Reads the Match domain | **Yes** — four figures | **Never** (§2.4) |
| Reads `community_ratings` | **No** | **Yes** — Highest Rated only |
| Filters by membership | Visibility only | **Eligibility — every board** |
| Names a person | One figure, `OQ-3` | **Every row of every board** |

**Neither reads the other**, and no figure is computed once and used by both.
Total Goals on the dashboard is a **sum**; Top Scorers is a **ranking of the
same column** — the same source, two independent reads, and neither is derived
from the other.

### 2.4 The Match domain is never a ranking source

**No board reads `matches`, `match_results`, `match_goals` or
`match_team_assignments`.** Not for ranking, not for eligibility, not for the
population.

**This is the sharpest structural difference from the dashboard**, which reads
the Match domain for four of its ten figures. A board's every input is Level 2
plus membership plus a display name.

**The constraint, stated as a rule:** *the Match domain never becomes a ranking
source unless explicitly approved.* §13.2 shows which future board would be the
first to need it, and why that makes it a scope decision rather than a query.

---

## 3. Leaderboard Inventory

**Nine boards, documented independently. One set of definitions across three
periods** — §8 of the governing document.

### 3.1 Board 1 — Overall Highest Rated

| Aspect | |
|---|---|
| **Question** | Who is the highest-rated player in this community, of those who have played here? |
| **Ranks by** | **Current Community Rating** — `community_ratings.rating` |
| **Population** | Players with an `overall` Community Statistics record showing **at least one appearance** |
| **Eligibility** | **Active members only** |
| **The rating shown** | **The current one.** Never a historical or period value |

### 3.2 Board 2 — Weekly Highest Rated

As Board 1, with the population narrowed: *"active members who participated in
at least one completed match during the **current week**."*

**The rating is identical to the one on Board 1.** `SL-5`: *"A player who
appears on both the weekly and the monthly board shows the same rating on each —
their current one."*

### 3.3 Board 3 — Monthly Highest Rated

As Board 2, with the month's window.

### 3.4 Boards 4–6 — Top Scorers (Overall, Weekly, Monthly)

| Aspect | |
|---|---|
| **Question** | Who scored the most goals in this community, in this window? |
| **Ranks by** | **`community_statistics.goals`** for the period |
| **Population** | Players with a record for that `period_type` and `period_key` |
| **Eligibility** | Active members only |
| **The period selects both** | **The population *and* the measure** — because goals accumulate within the period (§8, §7.2) |

### 3.5 Boards 7–9 — Most MVP (Overall, Weekly, Monthly)

| Aspect | |
|---|---|
| **Question** | Who was named best player most often in this community, in this window? |
| **Ranks by** | **`community_statistics.mvp_count`** for the period |
| **Population** | Players with a record for that period |
| **Eligibility** | Active members only |
| **The period selects both** | Population and measure |

### 3.6 The one structural difference across the three types

| | Highest Rated | Top Scorers, Most MVP |
|---|---|---|
| Score source | **`community_ratings`** | **`community_statistics`** |
| What the period selects | **The population only** | **The population *and* the measure** |
| Sources per read | **Four** | **Three** |
| A zero-valued entry | **Cannot occur** — a rating has no natural zero | **Can occur** — `LB-D1` |

**This is `SL-5` expressed as a read model**, and it is why §6 documents Highest
Rated separately.

---

## 4. Source Matrix

**Complete. No ambiguity remains.**

| # | Board | Period | **Ranking source** | **Population source** | **Eligibility source** | Display source | Tie-break source |
|---|---|---|---|---|---|---|---|
| 1 | Highest Rated | Overall | **`community_ratings.rating`** | `community_statistics` — `overall`, appearances > 0 | `community_members` | `users` | `LB-D2` |
| 2 | Highest Rated | Weekly | **`community_ratings.rating`** | `community_statistics` — current `weekly` key | `community_members` | `users` | `LB-D2` |
| 3 | Highest Rated | Monthly | **`community_ratings.rating`** | `community_statistics` — current `monthly` key | `community_members` | `users` | `LB-D2` |
| 4 | Top Scorers | Overall | **`community_statistics.goals`** — `overall` | *Same record* | `community_members` | `users` | `LB-D2` |
| 5 | Top Scorers | Weekly | **`community_statistics.goals`** — `weekly` | *Same record* | `community_members` | `users` | `LB-D2` |
| 6 | Top Scorers | Monthly | **`community_statistics.goals`** — `monthly` | *Same record* | `community_members` | `users` | `LB-D2` |
| 7 | Most MVP | Overall | **`community_statistics.mvp_count`** — `overall` | *Same record* | `community_members` | `users` | `LB-D2` |
| 8 | Most MVP | Weekly | **`community_statistics.mvp_count`** — `weekly` | *Same record* | `community_members` | `users` | `LB-D2` |
| 9 | Most MVP | Monthly | **`community_statistics.mvp_count`** — `monthly` | *Same record* | `community_members` | `users` | `LB-D2` |

### 4.1 Required joins

| Board type | Joins |
|---|---|
| **Highest Rated** | `community_ratings` **⋈** `community_statistics` (population) **⋈** `community_members` (eligibility) **⋈** `users` (name) — **four sources** |
| **Top Scorers / Most MVP** | `community_statistics` **⋈** `community_members` **⋈** `users` — **three sources** |

**All joins are on `(community_id, user_id)` or on `user_id`**, and every one is
served by an index the source specifications already require (§10.4).

### 4.2 What is never a source

| Never | Why |
|---|---|
| **`matches` and everything under it** | §2.4 |
| **`player_statistics`** | `SL-2` §2.3 — *"They must never read Global Statistics — for any board, in any period"* |
| **`users.overall_rating`** | `SL-3` §3.3 — *Highest Rated* must use the Community Rating and never the Global one |
| **`community_rating_history`** | §13.1 — ranking by movement is Most Improved, forbidden by `SL-5` §5.2 |
| **The dashboard** | §2.3 |

---

## 5. Ranking Rules

### 5.1 Ranking metric

| Board type | Metric | Direction |
|---|---|---|
| Highest Rated | `rating` | Descending |
| Top Scorers | `goals` in the period | Descending |
| Most MVP | `mvp_count` in the period | Descending |

**No board ranks by improvement, movement or delta**, in any period —
`SL-5` §5.2: *"An implementation that sorts by a delta has built the wrong
board."*

### 5.2 Eligibility

**Two conditions, both required, on every one of the nine.**

| # | Condition | Source | Rule |
|---|---|---|---|
| 1 | **Active membership** | `community_members` | *"Only active members appear. A player who has left the community is ineligible; their record is preserved but not displayed, and rejoining makes them eligible again"* (`SL-4`) |
| 2 | **Participation in the window** | `community_statistics` | The player has a record for the period **and it shows at least one appearance** |

**Condition 2 is what the period does on a Highest Rated board** — it selects
the population and nothing else.

### 5.3 Visibility — who may read a board

**Members of that community, and nobody else.** Every source is
community-scoped by its own specification, so a board is readable exactly when
all four of its sources are.

### 5.4 Ordering

Descending by the metric, then by the tie-break, then — as a final
deterministic key — **by a stable identifier** so that the order cannot change
between two reads of unchanged data (§5.5).

### 5.5 Tie-breaking

**`OQ-4` leaves tie-break order open as a presentation parameter. This document
states why it cannot be left unspecified in the *read*, and recommends one.**

**Ties are the common case, not the edge case:**

| Board | Why ties are frequent |
|---|---|
| Most MVP, weekly | One MVP per match; a week with two matches gives at most two players a count of 1 |
| Top Scorers, weekly | Most scorers in one week score once |
| Highest Rated | Two players who have won the same matches hold the same rating exactly — the deltas are constants |

> **A board whose order changes between two loads of unchanged data looks
> broken, and undermines confidence in every figure beside it.**

**Recommendation (`LB-D2`):**

| Board | Tie-break |
|---|---|
| **Highest Rated** | Rating desc → **appearances in the window** desc → `community_statistics.created_at` asc → `user_id` asc |
| **Top Scorers** | Goals desc → appearances asc *(fewer matches for the same goals ranks higher)* → `created_at` asc → `user_id` asc |
| **Most MVP** | MVP count desc → appearances asc → `created_at` asc → `user_id` asc |

**`user_id` as the final key is not a preference — it is the guarantee.** It is
unique, stable and always present, so the order is total.

### 5.6 Null behaviour

| Value | Nullable? | Rule |
|---|---|---|
| `rating` | **No** — NOT NULL with a `5.00` default | A player in the population always has one |
| `goals`, `mvp_count` | **No** — NOT NULL, default `0` | A record in the period always has both |
| The display name | **No** — `full_name` is NOT NULL | |
| **The board itself** | **Can be empty** | §5.7 |

**No null ever reaches a board.** Every column read is NOT NULL in its own
specification, and the population filter guarantees the row exists.

### 5.7 Empty community behaviour

**An empty board is a valid result, never an error.**

| Situation | Result |
|---|---|
| No members | **Empty board** |
| Members who have never played | **Empty board** — participation is required (§5.2) |
| No matches this week | **Empty weekly board**; the overall board is unaffected |
| Everyone has left | **Empty board** — records preserved, nobody eligible |

**The read returns zero rows.** It does not fail, and it does not return a row
of zeros.

### 5.8 Minimum participation

**At least one appearance in the window — on every board, including Overall.**

`SL-5` is explicit for Highest Rated: *"a player who has never played a match in
the community does not appear, even though joining gave them a `5.00` rating. **A
leaderboard ranks players who have played.**"*

**This is the same predicate the dashboard's Total Players needs**, and for the
same reason: a Community Statistics `overall` record is created **at join**, so
its existence proves membership, not participation.

**A minimum *metric* value is a different question** — `LB-D1`, §5.9.

### 5.9 Zero-valued entries — the open question

**A player who played this week but scored nothing has a `weekly` record with
`goals = 0`. Do they appear on Top Scorers?**

| Reading | Consequence |
|---|---|
| **Include zeros** | *Top Scorers* lists players who scored nothing. In a week where nobody scored, it lists everyone at `0` — **a board that ranks nobody** |
| **Exclude zeros** | The board lists only players who scored. In a week where nobody scored, it is **empty**, which is honest |

**It is not covered by `OQ-4`.** Depth truncates a ranked list; it does not
decide whether an entry belongs on it. In a small community, depth would not
even hide the zeros.

**Recommendation: exclude zero-valued entries from Top Scorers and Most MVP.**
The board's name asserts an achievement, and `0` is the absence of one — the
same reading `match_goals` takes, where *"not scoring is the absence of a row"*.

**Highest Rated is unaffected**: a rating has no natural zero, and `5.00` is a
starting point rather than an absence.

**Recorded as `LB-D1`** (§17).

### 5.10 Departed members

**Ineligible, immediately, on every board.** Their records are preserved in full
and simply stop being displayed (`SL-4` §4.2).

**Nothing is deleted and no stored value changes** — which is why rejoining
restores them without any recomputation.

### 5.11 Rejoined members

**Eligible again, immediately, with their previous record intact.** `SL-4`
§4.3: the previous Community Statistics and Community Rating are restored,
progression continues, no new baseline.

**The board requires no knowledge of the departure.** Eligibility is evaluated
against current membership at read time, so a rejoin needs no event, no
backfill and no refresh.

### 5.12 Deleted users

**Their Level 2 records cascade away**, so they leave every board completely and
permanently.

**One inherited exposure**: where the deleted account was a match's MVP or
scorer, that result is destroyed without reversing (`MRS-R1`, `MG-R1`) — so
other players' counters and ratings keep movements whose cause is gone, and the
boards rank on them. **Not this document's defect**; recorded as `LB-R5`.

---

## 6. Community Rating Leaderboards

**Highest Rated, in three periods — documented separately because it is the
only board whose score and population come from different entities.**

### 6.1 The three-way separation

| Responsibility | Entity | Contributes |
|---|---|---|
| **The score** | **`community_ratings`** | `rating` — the number the board ranks by |
| **The population** | **`community_statistics`** | *Who played in this window* |
| **Eligibility** | **`community_members`** | *Who is currently a member* |

**Three entities, three questions, and none can answer another's.**

### 6.2 Why Community Rating provides the score

**Because `SL-3` §3.3 makes it normative**: *"Highest Rated MUST use Community
Rating. It must never use the Global Rating. This applies to all three scopes."*

**And because a rating is the only measure that means "how good", rather than
"how much".** Goals and MVP counts measure volume; the rating measures standing.

### 6.3 Why Community Statistics provides the population

**Because a rating carries no period and cannot select one.** `SL-5`: the
Community Rating is *"one value per player per community — a running value, not
a per-period one."*

**So the only record that can answer *did this player play this week* is the
periodic statistics record**, and that is precisely the job it does here — it
contributes **no number to the board**, only a membership of the population.

**This is the cleanest illustration of `SL-5` in the whole architecture:** the
period changes *who appears*, never *what is shown*.

### 6.4 Why Community Membership provides eligibility

**Because membership is a fact about now and the other two are facts about the
past.** A departed player's rating and participation are both unchanged by
leaving; only their membership changed, and only membership can express it.

**And because storing it would break `SL-4`** — §2.2.

### 6.5 Why the three must remain independent

| If they were merged | What breaks |
|---|---|
| Rating stored on the periodic record | **Duplicated across every period**, each copy free to disagree — the error corrected in the governing document on 2026-08-02 |
| Participation inferred from the rating | **Impossible.** A rating of `5.00` cannot distinguish *never played* from *played and broke even* |
| Eligibility stored on either | **`SL-4` violated** — a departure would alter a stored number |

**The three responsibilities are independent because the three questions have
different answers over time**, and any merge would force one answer to serve two
questions.

### 6.6 The three boards, precisely

| Board | Score | Population |
|---|---|---|
| **Overall Highest Rated** | Current rating | `overall` record, appearances > 0 |
| **Weekly Highest Rated** | **The same current rating** | Record for the current ISO week |
| **Monthly Highest Rated** | **The same current rating** | Record for the current month |

*"A quiet week means a short weekly board, not a different measure."*

---

## 7. Statistics Leaderboards

**Six boards — Top Scorers and Most MVP, in three periods each.**

### 7.1 Counters used

| Board | Counter | Counters never read |
|---|---|---|
| Top Scorers | **`goals`** | `wins`, `losses`, `draws`, `mvp_count` |
| Most MVP | **`mvp_count`** | `wins`, `losses`, `draws`, `goals` |
| **Both** | `matches_played` — **as the participation predicate and a tie-break only**, never as a rank | |

**Three of the six counters are read by no board at all**: `wins`, `losses` and
`draws`. §16.1 is why — the two board types that would rank on them are not in
the approved set.

### 7.2 Period filtering

**By exact `period_key` match, never by a range.**

| Period | `period_type` | `period_key` |
|---|---|---|
| Overall | `overall` | The literal `overall` |
| Weekly | `weekly` | The current ISO week, e.g. `2026-W31` |
| Monthly | `monthly` | The current month, e.g. `2026-08` |

**The reader computes the current key from the clock in `Asia/Muscat`, then
matches it exactly.** It never scans a range and never filters an `overall`
record by date — **no record carries a date** (§8.2).

### 7.3 Aggregation

**None. There is nothing to aggregate.**

A Community Statistics record is already one row per player per period, so a
board is a **filter, a sort and a truncation** — never a `GROUP BY`.

**This is `SL-1`'s payoff.** Had the three periods been three tables, or had
statistics been stored per match, every board would be an aggregation. As
designed, the hardest operation on a leaderboard is a sort.

### 7.4 Read behaviour

| Step | |
|---|---|
| 1 | Compute the period key (`Asia/Muscat`) |
| 2 | Select this community's records for that `period_type` and `period_key` |
| 3 | Filter to active members (join `community_members`) |
| 4 | Filter to at least one appearance (§5.8), and — pending `LB-D1` — a non-zero metric |
| 5 | Order by the metric, then the tie-break, then `user_id` |
| 6 | Truncate to the board depth (`OQ-4`) |
| 7 | Join `users` for the display name **after truncation** |

**Step 7's position matters**: joining names before truncation reads a name for
every member rather than for the few displayed.

---

## 8. Period Behaviour

### 8.1 The three periods

| Period | Window | Key | Rolls over |
|---|---|---|---|
| **Overall** | All time | `overall` | **Never** |
| **Weekly** | One ISO week | `2026-W31` | Monday 00:00 `Asia/Muscat` |
| **Monthly** | One calendar month | `2026-08` | The 1st, 00:00 `Asia/Muscat` |

### 8.2 ISO week behaviour and the reference time zone

**Settled by `OQ-6` and recorded as `A1`, `A2`, `A3`:**

| Element | Value |
|---|---|
| Week numbering | **ISO-8601** — `2026-W31` |
| Month | `YYYY-MM` |
| Which timestamp places a match | **The match's start** (`A3`) |
| Reference zone | **`Asia/Muscat` (UTC+4)** (`A1`) |

**`A1` must not change once figures exist** — changing it re-buckets history
into different weeks and months, silently.

**The consequence for a board reader**: the current period key must be computed
**server-side, once per read**, in that zone. A client computing it from device
time would put a board in the wrong week near midnight — and two members in
different zones would see different boards for the same community.

### 8.3 Period transitions

**A period transition is not an event. Nothing runs, nothing is archived and
nothing is recomputed.**

| At the transition | What happens |
|---|---|
| In the data | **Nothing.** The previous period's records remain, untouched, forever |
| In the read | **The computed key changes**, so the board selects a different set of records |
| On screen | **The weekly board empties** until the community plays again |

**An empty board immediately after a rollover is correct**, not a failure —
§12.8.

**And the previous period is never deleted**, so a future *last week* view is a
key change and nothing more (§13.5).

### 8.4 Incomplete periods

**Every weekly and monthly board is read mid-period, always.** There is no
"complete" period in the MVP and nothing waits for one to close.

**So a board is a live standing, not a final result** — which is worth stating
because a "final" reading would imply an archival step the model deliberately
does not have.

---

## 9. Read Consistency

### 9.1 The risk

**Each board reads three or four sources.** A recorded result or a membership
change between two of those reads produces a board that contradicts itself:

| Skew | Symptom |
|---|---|
| Statistics read, then membership | A departed player appears; or a rejoined one is missing |
| Ratings read, then statistics | A player is ranked by a rating whose match is not yet in the population |
| Names read separately | A row with a rank and no name |

### 9.2 The requirement

> **One board is one snapshot.** Every source for a single board must be read in
> **one transaction**.

**One statement is sufficient and simplest**, but the requirement is the
transaction, not the statement count.

### 9.3 Across boards, and across screens

| Scope | Requirement |
|---|---|
| **Within one board** | **A single snapshot — required** (§9.2) |
| **Between two boards on one screen** | **Not required.** They are independent read models; a millisecond's skew between Top Scorers and Most MVP has no visible consequence |
| **Between a board and the dashboard** | **Not required, and not desirable to couple.** §2.3 keeps them independent |

### 9.4 Why isolation beyond a single transaction is unnecessary

Every source is read once per board. **A single transaction sees one snapshot
per statement**, and the whole read is milliseconds over tens of rows. Repeatable
read or serializable isolation would buy nothing measurable and would introduce
retry handling for a read that cannot conflict.

---

## 10. Performance Model

**Engineering recommendation only.**

### 10.1 Per board type

| Board type | Recommendation | Why |
|---|---|---|
| **Highest Rated** (3 boards) | **One RPC**, parameterised by community and period | Four sources, one snapshot required (§9.2), and the period key must be computed server-side (§8.2) |
| **Top Scorers** (3 boards) | **One RPC**, parameterised by community and period | Three sources, same snapshot and period requirements |
| **Most MVP** (3 boards) | **One RPC**, parameterised by community and period | Same |

### 10.2 The recommendation, stated once

> **Three read operations, parameterised by community and period, serving nine
> boards.**

**Not nine operations.** The three periods differ only in the key they compute,
and `SL-1`'s one-model design is what makes a single parameterised read possible
— *"nothing about the board changes but the period it is asked for."*

| Approach | Verdict |
|---|---|
| **Three parameterised RPCs** | **Recommended** |
| A view per board | **Rejected.** Nine views, and none can take *now* as a parameter cleanly |
| Direct client queries | **Acceptable as an MVP fallback**, at the cost of the snapshot and of the period arithmetic living in the client — **which §8.2 warns against** |
| **Materialized read** | **Rejected for the MVP.** Trivial volumes, and a refresh policy the product does not need. §13.8 states the trigger to revisit |

### 10.3 Privilege

**`SECURITY INVOKER`, not `SECURITY DEFINER`.**

Every source is already readable by a community member under its own rule, so a
board needs no elevated privilege — **and must not have one.** An invoker-rights
operation inherits each source's access rule, which is what makes §5.3 true
without restating it.

**This matches the dashboard's recommendation and the project's convention**:
*reads go through RLS; `SECURITY DEFINER` is for multi-step writes.*

### 10.4 Index support — and where the deferred indexes become due

**Every join and filter is served today**:

| Read | Served by |
|---|---|
| A community's records for one period | `community_statistics(community_id, period_type, period_key, user_id)` — `CS-X1` |
| A player's rating | `community_ratings(community_id, user_id)` — `CR-X1` |
| Eligibility | `community_members(community_id, user_id)` |
| A display name | The `users` primary key |

**The sorts are not.** Both source specifications deferred a sort-avoiding index
with the note *"revisit on measurement"*:

| Deferred index | Would serve | Recorded in |
|---|---|---|
| `community_statistics(community_id, period_type, period_key, goals DESC)` | Top Scorers | `CS-X2` candidate, §9.2 there |
| The same on `mvp_count` | Most MVP | Same |
| `community_ratings(community_id, rating DESC)` | Highest Rated, **all three periods** | `CR-X2` candidate, §9.2 there |

**This document makes the trigger concrete**: they become due when a community's
member count makes the sort measurable — not before. **At the PRD's targets the
population per board is tens of rows and the sort is free.**

---

## 11. Refresh Behaviour

### 11.1 Everything is immediate

| Class | Boards | Status |
|---|---|---|
| **Immediately updated** | **All nine** | Computed at read time from current data |
| Eventually consistent | None | — |
| Cached | None | — |
| Materialised | None | — |

**There is nothing to refresh**, because nothing is stored. A board is current
by construction.

### 11.2 What changes a board

| Event | Effect |
|---|---|
| **A result is recorded** | Counters and ratings move → **every affected board changes on its next read** |
| **A result is corrected** | Reversed and re-applied inside one transaction → boards reflect the new state |
| **A match is deleted** | Reversed first → boards reflect the removal |
| **A player leaves** | **Immediately ineligible** — no data change, only the eligibility join |
| **A player rejoins** | **Immediately eligible again** — same |
| **A period rolls over** | The computed key changes; the weekly board empties (§8.3) |
| **An account is deleted** | Their records cascade → they leave every board |

### 11.3 Values refreshed after result recording

**All nine**, potentially. A single recorded result can change:

| Board | How |
|---|---|
| Top Scorers × 3 | The scorers' `goals` rise in three period records |
| Most MVP × 3 | One player's `mvp_count` rises in three |
| Highest Rated × 3 | Ratings move for every participant, **and the population gains anyone playing their first match in the period** |

**Note the second half of that last row**: a result changes not only Highest
Rated's order but **who is on it** — which is `SL-5`'s design working as
intended.

---

## 12. Failure Behaviour

**None of these is an error.**

| # | Condition | Behaviour |
|---|---|---|
| 1 | **Empty community** | **Zero rows.** No members, nothing to rank |
| 2 | **Members who have never played** | **Zero rows** — participation is required (§5.8) |
| 3 | **No statistics for the period** | **Zero rows** for that period; other periods unaffected |
| 4 | **No ratings** | **Cannot occur** for an eligible player: a rating is created at first join and is NOT NULL |
| 5 | **Ties** | **Resolved deterministically** — `LB-D2`. Never a non-deterministic order |
| 6 | **Deleted players** | Gone from every board; their records cascaded |
| 7 | **Departed members** | Ineligible; records preserved (§5.10) |
| 8 | **Rejoined members** | Eligible again, previous record intact (§5.11) |
| 9 | **Incomplete periods** | **The normal case** (§8.4). A live standing, never a final result |
| 10 | **A period with no play** | **Empty board.** Correct, and expected after a rollover |

### 12.1 The empty board is a presentation question

**The read returns zero rows and does not fail.** Whether an empty board is
rendered as a message or a blank list is a UI decision this document does not
take.

**What it does state**: emptiness is never signalled by an error, and never by a
row of zeros.

---

## 13. Future Compatibility

### 13.1 Most Improved — **forbidden, and the data would support it**

**Explicitly out of scope** — §12, and `SL-5` §5.2: *"No board, in any period,
ranks by rating movement. An implementation that sorts by a delta has built the
wrong board."*

**The uncomfortable fact worth recording**: once Community Rating History
exists, *"rating gained this week"* is **computable** — a sum of in-effect
deltas over the period. **The data will support a board the architecture
forbids.**

**So the prohibition must be enforced by review, not by absence of data**, and
this is the clearest case in the phase where that is true.

### 13.2 Longest Win Streak — **the first board that would need the Match domain**

**Not computable from Community Statistics.** A streak needs the *sequence* of a
player's results; the counters hold totals with no order and no per-match
granularity.

**It would need a read over `match_results` joined through
`match_team_assignments`, ordered by match start** — making the Match domain a
ranking source, which §2.4 forbids without explicit approval.

**Assessment: a scope decision, not a query.** And the honest engineering note:
it is the one candidate board that **cannot** be served by the Level 2 model at
all.

### 13.3 Top Assists — **additive, blocked upstream**

Needs an assists counter on Community Statistics and an assists evidence table.
Both are recorded as additive in their own specifications; **neither exists**,
and the rating treatment of an assist is an unanswered Product question.

**The board itself would be a fourth board type with three periods** — identical
in shape to Top Scorers.

### 13.4 Top Goalkeepers — **additive, and partly free**

*Appearances in goal* and *clean sheets* need **no new evidence**: the lineup
carries `assigned_position = 'GK'` and the result carries both scores. **Saves
and goals conceded do need new evidence.**

**So a "most clean sheets" board is the cheapest new board available**, and it
would still need a counter on Community Statistics plus the backfill decision
(`PS-D2`).

### 13.5 Custom periods and season leaderboards

**Supported by the period model with no structural change** — a new
`period_type` value and a key format. `SL-1` §11: *"a future scope is a new
period type… would extend the same dimension and add no entity."*

**And a "last week" board needs nothing at all**: the previous period's records
are never deleted (§8.3), so it is a key change.

**Tournament and league periods are the exception** — their key is not derivable
from a date, so they need the Match domain to carry the reference first
(Community Statistics §14.2).

### 13.6 Global leaderboards — **permanently out of scope**

§12: *"Global rankings across communities. Unchanged by `SL-2` and `SL-3`:
Global Statistics and the Global Rating are a career record on a profile, never
a cross-community leaderboard."*

**And the model actively prevents one**: every index and every read is led by
`community_id`, and both source specifications refuse an index that would serve
a cross-community sort.

### 13.7 The two board types in this brief that are not approved

**Most Matches Played** and **Most Wins** — §16.1.

**Both would be trivial to build and neither is approved:**

| Board | Counter | Exists? | Needs |
|---|---|---|---|
| Most Matches Played | `matches_played` | **Yes** | **Approval only** — plus a definition of what it means when everyone plays every match |
| Most Wins | `wins` | **Yes** | **Approval only** — plus a decision on whether draws count |

**No schema change, no new counter, no new index beyond the deferred sort ones.
They are a scope decision and nothing else.**

### 13.8 Historical snapshots — **out of scope, and the model cannot fake one**

§12: *"Historical snapshots and 'as of' views of a past leaderboard."*

**Worth stating why it is more than a scope choice**: a past board cannot be
reconstructed, because **eligibility is not stored**. The counters for
`2026-W31` are preserved forever, but *who was a member that week* is not — the
membership row is recreated on rejoin and destroyed on departure.

**So "the board as it stood in July" is unrecoverable by design**, and building
it would require storing eligibility — which `SL-4` §4.5 forbids.

---

## 14. Engineering Review

### 14.1 Ownership — clean

**No board owns anything, stores anything or writes anything** (§2). There is no
write path to audit.

### 14.2 Responsibility — clean, and §6 is the demonstration

**Three entities, three questions, no overlap** (§6.1). The score, the
population and the eligibility each come from the only entity that can answer
them, and §6.5 shows what breaks if any two are merged.

### 14.3 Aggregate boundaries — respected

**Every board reads across the Community aggregate boundary and writes nothing.**
Same rule as the dashboard: *a read model may compose across aggregates; a write
may not.*

**And no board crosses into the Match aggregate at all** (§2.4) — a stricter
boundary than the dashboard observes.

### 14.4 Performance — sound, with a named threshold

**No aggregation** (§7.3) — the hardest operation is a sort over one community's
records for one period. **The threshold for the deferred indexes is measurable
and stated** (§10.4).

**One genuine efficiency note**: joining display names **after** truncation
(§7.4 step 7) is the difference between reading a name per member and a name per
displayed row.

### 14.5 Consistency — one requirement, stated

**A board is one snapshot** (§9.2). Between boards, and between a board and the
dashboard, no coupling is required or desirable.

### 14.6 Duplication — none, and one near-miss named

**No value is computed twice and no rank is stored.**

**The near-miss is Total Goals.** The dashboard sums `goals` over a community's
records; Top Scorers ranks the same column. **These are the same source read
twice, independently — not a duplication, and they must not be unified**, because
the moment one is computed from the other the two read models are coupled (§2.3).

### 14.7 Read correctness — three traps recorded

| Trap | Consequence |
|---|---|
| **Omitting the participation predicate** | Members who joined and never played appear on every board at `5.00` / `0` — **and the Overall board looks the most wrong** |
| **Ranking Highest Rated by a counter** | §16.2's imprecision in the governing document makes this a real misreading risk |
| **Computing the period key client-side** | Boards in the wrong week near midnight; different members see different boards (§8.2) |

---

## 15. Risks

### 15.1 High

| ID | Risk | Cause | Impact | Recommendation |
|---|---|---|---|---|
| `LB-R1` | **Highest Rated implemented as a statistics board** | `SL-2` §2.3 says boards *"MUST use Community Statistics"*, which read literally excludes the rating entity — §16.2 | **The wrong board entirely**: ranking by goals or appearances instead of standing | **§4's matrix is normative.** Correct the governing wording (§16.2) and assert the source in a test |
| `LB-R2` | **Participation predicate omitted** | An `overall` record exists from first join, before any play | **Every member appears on every board**, most at `5.00` and `0` — the board asserts nothing | **§5.8 is required, not an optimisation.** Same predicate the dashboard needs |

### 15.2 Medium

| ID | Risk | Cause | Impact | Recommendation |
|---|---|---|---|---|
| `LB-R3` | **Board order changes between two loads of unchanged data** | No deterministic tie-break; ties are the common case (§5.5) | The screen looks broken, and undermines confidence in every figure | **Settle `LB-D2`.** `user_id` as the final key makes the order total |
| `LB-R4` | **Mixed snapshot within one board** | Three or four sources read separately | A departed player ranked; a rank with no name | **One transaction per board** (§9.2) |
| `LB-R5` | **Inherited: an account deletion destroys a result without reversing** | `MRS-R1`, `MG-R1` | Boards rank on counters and ratings whose cause is gone | Not this document's to fix. Close at source |
| `LB-R6` | **Period key computed client-side** | The key depends on `A1`'s fixed zone | Wrong week near midnight; different members see different boards | **Compute server-side, once per read** (§8.2, §10.2) |

### 15.3 Low

| ID | Risk | Cause | Impact | Recommendation |
|---|---|---|---|---|
| `LB-R7` | **Zero-valued entries on Top Scorers / Most MVP** | No minimum-metric rule (`LB-D1`) | *Top Scorers* lists players who scored nothing | **Settle `LB-D1`** — recommend excluding zeros |
| `LB-R8` | **Names joined before truncation** | A natural query shape | A name read per member rather than per displayed row | **§7.4 step 7** |
| `LB-R9` | **Most Improved built because the data supports it** | `E9` makes rating movement computable | A board `SL-5` §5.2 explicitly forbids | **§13.1** — enforced by review, not by absent data |

---

## 16. Contradictions

**Two found. Neither is resolved silently.**

### 16.1 `LB-X1` — this brief lists two board types that are not approved

**The brief's inventory names five board types**: Most Matches Played, Most
Wins, Most Goals, Most MVP Awards, Highest Rated.

**The approved set is three** — §8: *"Three scopes, three boards each — **nine
boards**, one set of definitions"*, being **Highest Rated, Top Scorers and Most
MVP**.

| Brief's name | Status |
|---|---|
| Most Goals | **Approved** — named *Top Scorers* in the governing document |
| Most MVP Awards | **Approved** — named *Most MVP* |
| Highest Rated | **Approved** |
| **Most Matches Played** | **NOT in the approved set** |
| **Most Wins** | **NOT in the approved set** |

**Adding them would take the MVP from nine boards to fifteen** — two board types
× three periods.

**Not resolved silently, and not silently expanded.** This document specifies
**the nine approved boards**. §13.7 records exactly what the two additional
types would need: **approval, and nothing else** — both counters exist,
`matches_played` and `wins`, and no schema change is required.

**If the Product Owner intends fifteen boards, this document should be extended
rather than reinterpreted** — and two definitions would need answering first:
what *Most Matches Played* means in a community where everyone plays every
match, and whether draws count toward *Most Wins*.

**Two naming variants should also be settled**: the governing document says
*Top Scorers* and *Most MVP*; the brief says *Most Goals* and *Most MVP
Awards*. **This document uses the governing names.**

### 16.2 `LB-X2` — `SL-2` §2.3's wording excludes the rating entity

**`SL-2` §2.3 states**: *"All Community Leaderboards MUST use Community
Statistics. They must never read Global Statistics — for any board, in any
period."*

**§8 repeats it**: *"A leaderboard reads Community Statistics only."*

**But Highest Rated ranks by `community_ratings`, not by Community
Statistics** — `SL-3` §3.3 makes that normative.

**Read as *"Level 2, never Level 1"*, both sentences are correct.** Read as
*"the Community Statistics entity only"*, they contradict `SL-3` and `SL-5`.

**This is the third instance of one root cause**, already identified in the
architecture review of 2026-08-02: **"Community Statistics" names three
different things** — the level, the logical model, and the `E7` entity. The
first two instances were §3.2's rating dimensions and §14's ERD readiness row,
both corrected.

**Recommended wording, not applied here**: *"All Community Leaderboards MUST
read Level 2 — Community Statistics and the Community Rating. They must never
read Global Statistics or the Global Rating, for any board, in any period."*

**Recorded rather than corrected**, because it is a change to a governing
document's normative rule and belongs with the Product Owner. `LB-D3`.

### 16.3 Checked and found consistent

| Potential conflict | Verdict |
|---|---|
| `SL-5` requires participation; `SL-4` preserves records on departure | **Consistent.** Preservation is about data; participation and eligibility are read filters |
| Overall Highest Rated excludes a joined-but-never-played member who has a `5.00` rating | **Consistent and explicit** — `SL-5` §5.1 |
| Boards and the dashboard both read `community_statistics.goals` | **Consistent.** Two independent reads of one source (§14.6) |

---

## 17. Open Decisions

**Three, and each is genuinely required before implementation.**

| ID | Question | Recommendation |
|---|---|---|
| `LB-D1` | **Do zero-valued entries appear on Top Scorers and Most MVP?** | **Exclude them.** The board's name asserts an achievement and `0` is its absence. Not covered by `OQ-4`, which truncates a ranked list rather than deciding membership of it (§5.9) |
| `LB-D2` | **The tie-break order** — `OQ-4` leaves it open as presentation | **Required in the read, not optional.** Ties are the common case (§5.5). Recommend metric → appearances → record `created_at` → **`user_id` as the final total key**. Without the last, the order is non-deterministic |
| `LB-D3` | **Correct `SL-2` §2.3's wording** so it does not exclude the rating entity | **Yes**, with the wording in §16.2. It is a normative rule and a literal reading builds the wrong board (`LB-R1`) |

**`OQ-4`'s other half — board depth — needs no decision here.** Any depth works;
the read truncates after ordering (§7.4).

---

## 18. Engineering Approval

**Status: Engineering Approved — conditional.**

**Conditional on `LB-X1`** — the scope question of whether the MVP has nine
boards or fifteen. **This document is complete and authoritative for the nine
approved boards**; if two more types are approved it must be extended, not
reinterpreted.

**And on `LB-D1` and `LB-D2`**, both of which change what a board displays.

| Criterion | Status |
|---|---|
| Purpose, scope, consumers, business owner | ✓ §1 |
| **Read architecture — the five statements** | ✓ §2 |
| Leaderboard inventory — every board documented independently | ✓ §3, nine boards |
| **Source matrix — ranking, population, eligibility, joins, tie-break; no ambiguity** | ✓ §4 |
| Ranking rules — metric, eligibility, ordering, ties, nulls, empty, minimum participation, departed, rejoined, deleted | ✓ §5 |
| **Community Rating leaderboards — the three-way separation and why it must hold** | ✓ §6 |
| Statistics leaderboards — counters, period filtering, aggregation, read behaviour | ✓ §7 |
| Period behaviour — overall, weekly, monthly, ISO weeks, zone, transitions, incomplete periods | ✓ §8 |
| Read consistency | ✓ §9 |
| Performance model — per board type, recommendation only | ✓ §10 |
| Refresh behaviour | ✓ §11 |
| Failure behaviour — ten conditions | ✓ §12 |
| Future compatibility — eight candidates | ✓ §13 |
| Engineering review — seven audits | ✓ §14 |
| Risks — High, Medium, Low, with cause, impact, recommendation | ✓ §15, nine risks |
| **Contradictions — two found, neither resolved silently** | ✓ §16 |
| Open decisions | ✓ §17, three |
| No SQL, no views, no RPC, no implementation | ✓ |

---

## 19. Validation

| # | Source | Verdict |
|---|---|---|
| 1 | `Statistics_Leaderboards_MVP_Specification.md` §8 | **Contradiction with this brief — `LB-X1`** (§16.1). Nine boards, three types |
| 2 | Same, `SL-2` §2.3 | **Imprecision — `LB-X2`** (§16.2). Wording excludes the rating entity |
| 3 | Same, `SL-5` in full | **No contradiction.** §5.1's three boards are §3.1–§3.3; §5.2's prohibition is §5.1 and §13.1; the participation rule is §5.8 |
| 4 | Same, `SL-4` | **No contradiction.** Departure, rejoin and preservation are §5.10, §5.11 |
| 5 | Same, `SL-1` §9, `OQ-6` | **No contradiction.** `A1`, `A2`, `A3` are §8.2 |
| 6 | Same, §12 out of scope | **No contradiction.** §13 evaluates each without proposing scope change |
| 7 | Same, `OQ-4` | **Noted, and narrowed.** Depth needs no decision; the tie-break does (`LB-D2`) |
| 8 | `Community_Statistics_Table_Specification.md` | **No contradiction.** Creation at join is why §5.8's predicate exists; `CS-X1` serves every population read |
| 9 | `Community_Rating_Table_Specification.md` | **No contradiction.** Its §12.3 states the board needs three tables — §6 here |
| 10 | `Community_Rating_History_Table_Specification.md` | **No contradiction.** Never a board source (§4.2); §13.1 records why |
| 11 | `Community_Members_Table_Specification.md` | **No contradiction.** Eligibility only, evaluated at read time |
| 12 | `Community_Dashboard_Read_Specification.md` | **No contradiction.** §2.3 keeps the two read models independent |
| 13 | `Profiles_Table_Specification.md` | **No contradiction.** `UP-1` tier 2 covers the display names |
| 14 | `Player_Statistics_Table_Specification.md` | **No contradiction.** Never a board source — `SL-2` §2.3, and its own §9.2 refuses a ranking index |
| 15 | `Docs/01-PRD.md` | **No contradiction.** *Nine leaderboards over three periods* — which is the approved set, not fifteen |
| 16 | `Docs/06-ERD.md` §3 | **No contradiction.** `E7`, `E8` separate; `A1`, `A3` govern the period arithmetic |
| 17 | **Database Principles** | **No artifact in the repository** — seventeenth phase |
| 18 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **No contradiction.** §10.3 keeps boards under RLS |

**Note on source 15**: `Docs/01-PRD.md` names *"nine leaderboards over three
periods"* — **independently confirming the approved count** and strengthening
§16.1.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **The governing authority** — §8 defines the nine boards; `SL-2` §2.3, `SL-4`, `SL-5` are normative. **§16 records one contradiction with this brief and one imprecision in its wording** |
| `engineering/Community_Rating_Table_Specification.md` | **The score for three boards.** Its §12.3 anticipates §6 |
| `engineering/Community_Statistics_Table_Specification.md` | **The measure for six boards, the population for all nine** |
| `engineering/Community_Members_Table_Specification.md` | **Eligibility for all nine** |
| `engineering/Community_Dashboard_Read_Specification.md` | **The sibling read model.** Shares sources, shares no read (§2.3) |
| `engineering/Community_Rating_History_Table_Specification.md` | Never a source; §13.1 records why |
| `engineering/Player_Statistics_Table_Specification.md` | **Never a source** — `SL-2` §2.3 |
| `engineering/Profiles_Table_Specification.md` | `UP-1` tier 2 — display names |
| `Docs/06-ERD.md` §3 | `A1`, `A3` — period arithmetic |
| `Docs/01-PRD.md` | *Nine leaderboards over three periods* |
