# Statistics & Leaderboards — MVP Specification

| Field | Value |
|---|---|
| Version | **2.0** |
| Supersedes | v1.3, v1.2, v1.1, v1.0 |
| Status | **Approved — architecturally complete** |
| Role | **Product specification** — what the Statistics & Leaderboards feature is |
| Owner | Product Owner |
| Baseline | `v0.8.0-mvp` plus the Results / Rating phase, schema through `0024` |
| Approved | 2026-08-01 |

> **This version is an implementation reference.** Every architectural question
> is closed. What remains open ([§13](#13-open-questions)) is presentation
> parameters — none of them can change the shape of the data, and none blocks
> implementation. [§14](#14-implementation-readiness) states what may now
> proceed and what must be chosen before it does.

> **Document provenance.** The approved v1.0 of this specification is held
> outside this repository, as the Architecture Migration Specification v1.2 is
> (`Docs/README.md`). No v1.0 file exists in `Docs/`, `Docs/engineering/`,
> `Docs/archive/` or the repository history, so v1.1 **restated the
> specification in full** rather than patching sections in place, and every
> later version continues from that restatement. If the Product Owner supplies
> the v1.0 source, section numbering can be reconciled against it without
> changing any decision recorded here.

> **Scope of this document.** It states *what the product shows*. It authorises
> no implementation: no schema, no migration and no client code is defined
> here, and none was written for it. Where it and `Docs/01-PRD.md` or
> `Docs/10-Design-Decisions.md` disagree about what the product does, the
> Product Owner's latest approval governs — see
> [Related documents](#related-documents) for the references that still need
> aligning.

---

## Decision index

| ID | Decision | Approved | Resolves |
|---|---|---|---|
| [`SL-1`](#10-sl-1--one-model-not-three-tables) | One statistics model, not three tables | v1.1 | — |
| [`SL-2`](#2-sl-2--two-levels-of-statistics) | Two levels of statistics — Global and Community | v1.2 | `OQ-1` |
| [`SL-3`](#3-sl-3--two-rating-systems) | Two rating systems — Global Rating and Community Rating | v1.3 | `OQ-2` |
| [`SL-4`](#4-sl-4--the-community-rating-lifecycle) | The Community Rating lifecycle — join, leave, rejoin | v2.0 | `OQ-8` |
| [`SL-5`](#5-sl-5--highest-rated-is-a-current-rating-board) | Highest Rated is a current-rating board | v2.0 | `OQ-9` |

---

## Contents

| § | Section |
|---|---|
| 1 | [Purpose](#1-purpose) |
| 2 | [`SL-2` — Two levels of statistics](#2-sl-2--two-levels-of-statistics) |
| 3 | [`SL-3` — Two rating systems](#3-sl-3--two-rating-systems) |
| 4 | [`SL-4` — The Community Rating lifecycle](#4-sl-4--the-community-rating-lifecycle) |
| 5 | [`SL-5` — Highest Rated is a current-rating board](#5-sl-5--highest-rated-is-a-current-rating-board) |
| 6 | [Player Statistics — the Player Profile](#6-player-statistics--the-player-profile) |
| 7 | [Community Dashboard](#7-community-dashboard) |
| 8 | [Community Leaderboards](#8-community-leaderboards) |
| 9 | [Community Statistics — the time dimension](#9-community-statistics--the-time-dimension) |
| 10 | [`SL-1` — One model, not three tables](#10-sl-1--one-model-not-three-tables) |
| 11 | [Future extensibility](#11-future-extensibility) |
| 12 | [Out of scope](#12-out-of-scope) |
| 13 | [Open questions](#13-open-questions) |
| 14 | [Implementation readiness](#14-implementation-readiness) |
| 15 | [Change log](#15-change-log) |

---

## 1. Purpose

Give a player a record of how they have played, and give a community a picture
of its own activity and its best performers — over three time scopes: all
time, the current week and the current month.

The feature reads what the Results / Rating phase already produces. It defines
no new way to record a match, changes no rating rule, and adds no refusal.

---

## 2. `SL-2` — Two levels of statistics

**Approved in v1.2.** Resolves [`OQ-1`](#13-open-questions) and governs every
other section of this document.

### Decision

The project supports **two levels of statistics**, with different purposes,
different scopes and different readers:

| Level | Scope | Purpose | Read by |
|---|---|---|---|
| **1 — Global Statistics** | The whole application | The player's complete football career | Player Profile |
| **2 — Community Statistics** | One community | The player's performance inside that community | Community Dashboard, Community Leaderboards |

The two levels are **not two views of one record**. They answer different
questions and are never substituted for one another.

### 2.1 Level 1 — Global Statistics

**Purpose.** Represent the player's complete football career across the entire
application.

Global Statistics comprise:

| Item |
|---|
| Global Rating ([`SL-3`](#3-sl-3--two-rating-systems)) |
| Matches Played |
| Wins |
| Losses |
| Draws |
| Goals |
| MVP Count |
| Rating History |

- They are shown on the **Player Profile**.
- They are **not** used for Community Leaderboards.
- They carry **no community dimension**: a career is one record per player,
  spanning every community they have played in.

### 2.2 Level 2 — Community Statistics

**Purpose.** Represent the player's performance inside a **specific
community**.

Community Statistics are used by:

- The Community Dashboard ([§7](#7-community-dashboard))
- The Community Leaderboards ([§8](#8-community-leaderboards))
- Weekly Statistics ([§9](#9-community-statistics--the-time-dimension))
- Monthly Statistics ([§9](#9-community-statistics--the-time-dimension))

**Community Statistics are isolated per community.** A player's performance in
Community A **must never** affect Community B's leaderboards, dashboard or any
figure Community B displays. Isolation is a rule of the specification, not a
default that a query may relax for convenience.

### 2.3 Binding rules

Two rules follow directly from the decision, and both are normative:

1. **All Community Leaderboards MUST use Community Statistics.** They must
   never read Global Statistics — for any board, in any period.
2. **The Player Profile MUST display only Global Statistics.** Community
   Statistics must not be mixed into the player's career profile.

A screen therefore reads from exactly one level. There is no screen in the MVP
that shows both, and no measure that is assembled from both.

### 2.4 Design rationale

- **It preserves the player's global football identity.** A career is the sum
  of everything a player has played, not a figure that changes with the
  community they happen to be looking at. The profile stays the one place that
  answers "how have I played?"
- **It allows community-specific competition.** A leaderboard is only
  meaningful if it ranks people against the players they actually play with. A
  board fed from career totals would rank a community by achievements earned
  elsewhere.
- **It supports weekly and monthly rankings.** The community level carries the
  time dimension ([§9](#9-community-statistics--the-time-dimension)), so a
  weekly or monthly board is a period of the same record rather than a
  different kind of statistic.
- **It avoids conflicts between communities.** Isolation
  ([§2.2](#22-level-2--community-statistics)) means one community's activity
  can never move another's numbers. Without the split there is no way to state
  that rule at all.
- **It remains extensible for future periods.** New scopes are new
  `period_type` values on the community level, with no second engine and no
  change to the career level ([§11](#11-future-extensibility)).
- **It keeps responsibilities clearly separated.** Each level has one purpose
  and one set of readers, so "which number is right" is never a question — it
  depends only on which question was asked.

### 2.5 What `SL-2` does not change

- **No business rule changes.** Result entry, result modification, the rating
  engine, its constants and its audit are untouched.
- **`RR-6` remains correct for Level 1.** The existing global counters
  (`engineering/Results_Rating_Engineering_Decisions.md`, `RR-6`) are one row
  per player across every community — which is exactly what Global Statistics
  is. `SL-2` does not overturn that decision; the community level is
  **additive** beside it.
- **The two levels count the same matches.** Nothing here permits them to
  diverge: a player's career counters and the sum of their per-community
  `overall` counters describe the same recorded results and should agree by
  construction. **Ratings are not counters and are not summed** — see
  [`SL-3`](#3-sl-3--two-rating-systems).
- **No global ranking is introduced.** Global *statistics* on a profile are not
  a global *leaderboard*; cross-community ranking stays out of scope
  ([§12](#12-out-of-scope)).

---

## 3. `SL-3` — Two rating systems

**Approved in v1.3.** Resolves [`OQ-2`](#13-open-questions). It is the rating
counterpart of [`SL-2`](#2-sl-2--two-levels-of-statistics) and follows the same
two-level shape.

### Decision

The project officially supports **two independent rating systems**:

| Level | Scope | Purpose | Read by |
|---|---|---|---|
| **1 — Global Rating** | The whole application | The player's complete football career | Player Profile only |
| **2 — Community Rating** | One community | The player's performance inside that community | Community Dashboard, Community Leaderboards |

**Independent** is the operative word. Neither rating is derived from the
other, neither is a view of the other, and the two are expected to differ.

### 3.1 Level 1 — Global Rating

**Purpose.** Represent the player's complete football career across the entire
application.

| Characteristic | |
|---|---|
| Cardinality | **One rating per player** |
| Updated by | **Every completed match**, in every community |
| Used by | **Player Profile only** |
| Never used by | **Community Leaderboards** |
| Never used by | **Community Dashboard** |

This is the rating that exists today: `users.overall_rating`, system-managed,
maintained by the approved rating engine.

### 3.2 Level 2 — Community Rating

**Purpose.** Represent the player's performance inside a **specific
community**.

| Characteristic | |
|---|---|
| Cardinality | **One rating per player per community** |
| Isolation | **Completely isolated from every other community** |
| Updated by | **Only matches played inside that community** |
| Initialized at | **`5.00`** — the neutral baseline ([`SL-4`](#4-sl-4--the-community-rating-lifecycle)) |
| Used by | **Community Dashboard** |
| Used by | **Community Leaderboards** |

A player active in three communities therefore holds one Global Rating and
three Community Ratings, and a match in one community moves exactly two of
those numbers: the Global Rating, and that community's Community Rating.

**Community Rating belongs to the community *level*** — Level 2 — and **not to
the Community Statistics record**. It is a **separate entity** with its own
cardinality, its own lifecycle and its own history:

| Dimension | |
|---|---|
| `community_id` | Which community the rating belongs to |
| The player | Whose rating it is |
| **A period** | **No.** A rating is a running value and carries no period |

**One rating per player per community — not one per period.** The entity form
is `E8` in `Docs/06-ERD.md` §3.2, beside `E7` Community Statistics (one per
player per community per period) and `E9` Community Rating History.

The product speaks of an *Overall*, a *Weekly* and a *Monthly* Community
Rating, and those three names are **boards, not stored ratings**:

| Name in the product | What it is |
|---|---|
| Overall Community Rating | The *Highest Rated* board, all-time population |
| Weekly Community Rating | The same board, population from the current week |
| Monthly Community Rating | The same board, population from the current month |

**What those three forms are, precisely.** `SL-5` settles it: they are the
three **boards**, not three stored ratings. The rating is always the player's
**current** Community Rating, and the period selects **who is eligible to
appear**, not which rating is shown. So the rating itself is one value per
player per community — a running value, not a per-period one — while the
period dimension applies to the counters beside it and to eligibility. Stated
again as a model property in
[§9.1](#91-one-logical-model-one-community-many-time-scopes), and as an entity
in `Docs/06-ERD.md` §3.2.

### 3.3 Binding rules

Both rules are normative:

1. **Highest Rated MUST use Community Rating.** It must never use the Global
   Rating. This applies to **all three scopes** — Overall, Weekly and Monthly.
2. **The Player Profile always displays the Global Rating.** Community Rating
   must never be displayed as the player's career rating.

Future versions **may** optionally display a Community Rating inside a
community context. That is **out of scope for the MVP**
([§12](#12-out-of-scope)).

### 3.4 Design rationale

- **It preserves the player's global football identity.** A career rating that
  changed with the community being viewed would not be a career rating. The
  profile keeps one number that means the same thing everywhere.
- **It prevents experienced players from dominating new community rankings.** A
  player arriving with a high career rating would otherwise sit at the top of a
  community board before playing a single match in it. Under `SL-3` they rank
  on what they have done *there*.
- **It makes community competition fair.** Everyone in a community is measured
  by the same yardstick — matches played in that community — so a board
  reflects the contest its members are actually in.
- **It keeps communities independent.** A player's form in Community A cannot
  move their standing in Community B, because the two ratings never touch.
- **It allows community progression without affecting the overall career.** A
  player can rise inside a community without that being a claim about their
  career, and can have a quiet season in one community without their profile
  rewriting itself.
- **It aligns with the two-level statistics architecture.** `SL-3` adds no new
  concept: the rating now sits at whichever level the measure around it already
  sits, so a screen still reads from exactly one level
  ([§2.3](#23-binding-rules)).

### 3.5 What `SL-3` inherits and does not change

- **No business rule is redesigned.** The approved rating engine — winner
  `+0.10`, loser `−0.10`, goal `+0.05` each, MVP `+0.20`, on the
  `0.0 … 10.0` scale — is untouched, and so are result entry, result
  modification, the reversal rules and the audit. `SL-3` changes **which
  matches feed which rating**, not what a match is worth.
- **The Community Rating uses that same engine**, applied to the subset of
  matches played inside the community. A narrower match set is the only
  difference.
- **The two ratings are not reconcilable arithmetic.** A Global Rating is not
  the sum, mean or any function of a player's Community Ratings, and no screen
  or query should try to derive one from the other. They are produced by the
  same engine over different match sets, and the engine clamps at both ends of
  the range, so they diverge legitimately.
- **`RR-2` still holds.** A rating is system-managed and no client may write
  one. `SL-3` introduces a second rating, not a second writer.
- **No global rating ranking is introduced.** The Global Rating is a profile
  figure, never a cross-community board ([§12](#12-out-of-scope)).

---

## 4. `SL-4` — The Community Rating lifecycle

**Approved in v2.0.** Resolves [`OQ-8`](#13-open-questions) and records the
approved **Community Rating initialization** decision. It answers what happens
to a player's community record across the whole of their membership: joining,
leaving, and coming back.

### Decision

| Event | What happens |
|---|---|
| **Joins for the first time** | Community Rating starts at the neutral baseline, **`5.00`**. It is **not** initialized from the Global Rating. |
| **Leaves the community** | Nothing is deleted. Community Statistics, Community Rating and Community Rating History are **all preserved**. The player becomes **ineligible** for that community's leaderboards. |
| **Rejoins the same community** | The previous Community Statistics and Community Rating are **restored**, and progression continues from that state. **No new baseline is created.** |

The single sentence behind all three: **a Community Rating is created once per
player per community and never reset.**

### 4.1 Initialization — joining for the first time

A player joining a community for the first time starts that community's rating
at **`5.00`**, the same neutral baseline every player starts a career at.

It is **not** seeded from their Global Rating, and not from their rating in any
other community.

**Why.** Each community has its own competitive progression. A player's
experience elsewhere must not immediately dominate a community they have just
joined — a newcomer with a `9.20` career rating would otherwise top the board
before kicking a ball there. Starting everyone at the same place is what makes
the board a record of what happened *in that community*.

### 4.2 Departure — leaving a community

When a player leaves a community, **nothing is deleted**:

- Community Statistics are **not** deleted.
- Community Rating is **not** deleted.
- Community Rating History is **not** deleted.
- Historical data is preserved in full.

What changes is **eligibility, not data**. The player no longer appears on that
community's leaderboards, because a leaderboard ranks the community's **active
members**. Their record continues to exist; it simply stops being displayed and
stops accruing, since they can no longer play a match there.

**Community history is unaffected.** The matches happened, so a departed
member's goals and appearances remain part of the community's own aggregates on
the dashboard ([§7.1](#71-overall)) — Total Matches, Total Players and Total
Goals describe what the community did, not who is currently in it.

### 4.3 Return — rejoining the same community

A player rejoining a community they previously left **resumes their previous
record**:

- The previous Community Statistics are restored.
- The previous Community Rating is restored.
- Progression continues from the previous state.
- **The Community Rating is not reset**, and no second baseline is created.

Rejoining is therefore a change of eligibility in the other direction. The
record was never gone; it becomes visible and active again.

### 4.4 Design rationale

- **Deleting history would destroy the community's own record.** A departed
  player's matches, goals and results happened, and the community's totals
  depend on them. Removing the player's record would silently change figures
  that describe the community rather than the player.
- **A rating that resets on rejoin is a rating that can be gamed.** If leaving
  and rejoining returned a player to `5.00`, any player whose rating had fallen
  could clear it by leaving and coming back. Preservation removes the incentive
  entirely.
- **Eligibility is the right lever, not deletion.** The question "should this
  player appear on this board?" is about current membership. Answering it by
  destroying data answers a different, larger question nobody asked.
- **It matches how the career level already behaves.** `RR-6` records that a
  player leaving a community keeps the counters it produced. `SL-4` gives the
  community level the same property, so neither level loses history on a
  membership change.
- **It is the least surprising behaviour.** A returning player expects to find
  what they left. Continuity is what a record is for.

### 4.5 What `SL-4` implies for the record

Consequences worth stating, because an implementation must not violate them:

- **A Community Statistics record outlives its membership row.** It is keyed by
  player and community, and its lifetime is **not** tied to the membership.
  Leaving a community must not cascade it away. See
  [§14](#14-implementation-readiness).
- **Community Rating History is preserved too**, and exists for the same reason
  the global audit does: a corrected result must reverse exactly, and reversal
  is only exact when the *applied* delta is recorded (`RR-5`, `RR-1`). It has
  **no reader in the MVP** — no screen displays it — but it is not optional.
- **Eligibility is a display filter.** It is evaluated when a board is read; it
  is not a flag written onto the record, and it never changes a stored number.
- **The record is still bounded by its community.** If the community itself is
  deleted, its statistics go with it, exactly as its matches do.

---

## 5. `SL-5` — Highest Rated is a current-rating board

**Approved in v2.0.** Resolves [`OQ-9`](#13-open-questions).

### Decision

**Highest Rated always represents the player's *current* Community Rating.**
It **never** represents rating improvement.

The period does not change *which rating is shown*. It changes **who is
eligible to appear**.

### 5.1 The three boards

| Board | Ranks by | Eligible players |
|---|---|---|
| **Overall Highest Rated** | Current Community Rating | Active members who have played at least one completed match in this community |
| **Weekly Highest Rated** | Current Community Rating | Active members who participated in at least one completed match during the **current week** |
| **Monthly Highest Rated** | Current Community Rating | Active members who participated in at least one completed match during the **current month** |

Read plainly: *Weekly Highest Rated* is **the highest current Community Rating
among players who participated in at least one completed match during the
current week**, and *Monthly Highest Rated* is the same sentence with "month"
in place of "week".

Three consequences follow, and all three are intended:

- **The rating shown is the same number on all three boards.** A player who
  appears on both the weekly and the monthly board shows the same rating on
  each — their current one.
- **The periods differ only in the participation window.** A quiet week means a
  short weekly board, not a different measure.
- **The Overall board's window is all time.** It is the same rule with the
  widest window: a player who has never played a match in the community does
  not appear, even though joining gave them a `5.00` rating
  ([§4.1](#41-initialization--joining-for-the-first-time)). A leaderboard ranks
  players who have played.

### 5.2 Highest Rated is not Most Improved

**`Highest Rated ≠ Most Improved`.**

The two answer different questions, and the difference is worth stating because
a periodic board invites the confusion:

| | Answers |
|---|---|
| **Highest Rated** | Who *is* the best rated, among those who played in this window |
| **Most Improved** | Who *gained the most rating* during this window |

**Most Improved is not part of the MVP** ([§12](#12-out-of-scope)). No board,
in any period, ranks by rating movement. An implementation that sorts by a
delta has built the wrong board.

### 5.3 Design rationale

- **A rating is a state, not an event.** "Highest rated this week" naturally
  means "the best players who turned out this week" — asking a running value
  to behave like a counter is what made this ambiguous in the first place.
- **One definition serves all three periods.** The boards stay comparable, and
  the weekly board is not a different product from the overall one.
- **Participation is what a period should select.** A weekly board should
  reflect the week's activity; gating on who played is exactly that, without
  inventing a second rating measure.
- **It keeps the model simple.** No periodic rating value has to be stored,
  reconciled or reversed — the rating is read from the community record and
  the period filters the population.

---

## 6. Player Statistics — the Player Profile

**Status: in MVP.** The measures are unchanged from v1.0. Confirmed in v1.2 as
**Level 1 — Global Statistics**; the rating was named the **Global Rating** in
v1.3.

| Item | Meaning |
|---|---|
| Global Rating | The player's career rating on the approved `0.0 … 10.0` scale |
| Matches Played | Matches the player appeared in |
| Wins | Matches whose result favoured the player's side |
| Losses | Matches whose result went against the player's side |
| Draws | Matches that ended level |
| Goals | Goals credited to the player |
| MVP Count | Times the player was named MVP |
| Rating History | The player's rating changes, newest first |

Notes:

- Every figure above is **global** — across every community the player has
  played in.
- The Global Rating is **not a counter**. It is the player's live career
  rating, which the rating engine owns and no client may write. It is read,
  never recomputed here.
- Rating History is a **read of the existing audit**. It presents rating
  changes recorded when results were; it introduces no new record and no new
  writer. How many entries are shown is [`OQ-5`](#13-open-questions).
- **No Community Statistics and no Community Rating appear on this screen**
  ([§2.3](#23-binding-rules), [§3.3](#33-binding-rules)).
- **Leaving a community does not change this screen.** Global Statistics span
  every community the player has played in, including ones they have left
  ([`RR-6`](#related-documents), [§4.2](#42-departure--leaving-a-community)).

---

## 7. Community Dashboard

**Status: in MVP.** The *Overall* block is unchanged from v1.0; the *This Week*
and *This Month* blocks were added in v1.1. Every figure on this screen is
**Level 2 — Community Statistics**.

The dashboard describes **one community**, never the whole app and never a
player's career.

### 7.1 Overall

| Item | Meaning |
|---|---|
| Total Matches | Matches this community has played |
| Total Players | Players who have taken part in this community |
| Total Goals | Goals scored in this community's matches |
| Last Match Date | When this community last played |

These are **community history** and are unaffected by membership changes: a
departed member's matches and goals remain counted, because they happened
([§4.2](#42-departure--leaving-a-community)).

### 7.2 This Week

| Item | Meaning |
|---|---|
| Matches Played | Matches this community played within the current week |
| Goals Scored | Goals scored in those matches |
| Most Active Player | The community's most active player over that week |

### 7.3 This Month

| Item | Meaning |
|---|---|
| Matches Played | Matches this community played within the current month |
| Goals Scored | Goals scored in those matches |
| Most Active Player | The community's most active player over that month |

*This Week* and *This Month* read the same measures over a shorter window; they
introduce no measure the Overall block does not already have, except **Most
Active Player** — participation count within the window, with the tie-break
and the treatment of departed members left as a presentation detail
([`OQ-3`](#13-open-questions)).

**On ratings.** `SL-3` names the dashboard as a reader of the Community Rating
and forbids it the Global Rating ([§3.1](#31-level-1--global-rating)). No block
above displays a rating today, so the rule is immediately operative as a
prohibition and forward-looking as a permission: **if** a rating is ever shown
on this screen it is the Community Rating, and adding one is a scope change
requiring approval.

---

## 8. Community Leaderboards

**Status: in MVP.** Overall is unchanged from v1.0; Weekly and Monthly were
added in v1.1. All nine boards read **Level 2 — Community Statistics**, never
Global Statistics.

Three scopes, three boards each — **nine boards**, one set of definitions:

| Board | Ranks by |
|---|---|
| Highest Rated | **Current Community Rating** ([`SL-5`](#5-sl-5--highest-rated-is-a-current-rating-board)) |
| Top Scorers | Goals in the period |
| Most MVP | MVP count in the period |

| Scope | Window |
|---|---|
| **A. Overall** | All time |
| **B. Weekly** | The current week |
| **C. Monthly** | The current month |

Rules that hold for all nine:

- **A leaderboard reads Community Statistics only**
  ([§2.3](#23-binding-rules)). Global Statistics are never a leaderboard
  source, in any period.
- **A leaderboard is scoped to one community**, and ranks only that community's
  play. There is no global ranking in the MVP ([§12](#12-out-of-scope)).
- **Only active members appear.** A player who has left the community is
  ineligible; their record is preserved but not displayed, and rejoining makes
  them eligible again ([`SL-4`](#4-sl-4--the-community-rating-lifecycle)).
- **The period selects the population.** For *Top Scorers* and *Most MVP* it
  also selects the measure, because those are counters accumulated within the
  period. For *Highest Rated* it selects the population only — the rating
  shown is always the current one
  ([`SL-5`](#5-sl-5--highest-rated-is-a-current-rating-board)).
- **No board ranks by improvement**
  ([§5.2](#52-highest-rated-is-not-most-improved)).
- Board depth (top *N*) and tie-break order are presentation parameters —
  [`OQ-4`](#13-open-questions).

---

## 9. Community Statistics — the time dimension

Introduced in v1.1, extended in v1.2 with the community dimension (`SL-2`) and
in v1.3 with the Community Rating (`SL-3`). This section replaces the storage
concept described in v1.0.

It describes **Level 2 only**. Global Statistics
([§2.1](#21-level-1--global-statistics)) carry no period and no community: one
career record per player.

### 9.1 One logical model, one community, many time scopes

The Statistics Engine keeps **a single logical statistics model** for the
community level. One model holds every scope the product asks for; a scope is
not a different kind of record, it is the same record carrying a different
community and period.

A Community Statistics record is identified by three dimensions beyond the
player it describes:

| Dimension | Purpose |
|---|---|
| `community_id` | Which community the record belongs to |
| `period_type` | Which *kind* of period the record covers |
| `period_key` | Which *particular* period of that kind |

`(player, community_id, period_type, period_key)` identifies one record.
`community_id` is what makes the isolation rule in
[§2.2](#22-level-2--community-statistics) a property of the model rather than a
discipline expected of each query.

The measures a record carries — Matches Played, Wins, Losses, Draws, Goals and
MVP Count — accumulate within their period. The **Community Rating**
([`SL-3`](#3-sl-3--two-rating-systems)) is a running value that belongs to the
player-and-community, not to a period: `SL-5` reads the current rating and uses
the periodic records only to establish **who played in the window**.

### 9.2 `period_type`

Allowed values in the MVP — exactly three:

| Value | Covers |
|---|---|
| `overall` | Everything in that community, with no time boundary |
| `weekly` | One week |
| `monthly` | One calendar month |

### 9.3 `period_key`

`period_key` names the single period a record covers, within its `period_type`.

| `period_type` | `period_key` | Example |
|---|---|---|
| `overall` | The literal key `overall` | `overall` |
| `weekly` | A week identifier | `2026-W31` |
| `monthly` | A month identifier | `2026-08` |

Stated plainly:

- **Overall statistics use the `overall` key.** There is only ever one overall
  period, so it needs no date in its name and never rolls over. It is still
  scoped to one community.
- **Weekly statistics use a week identifier** — the year and the week within
  it, as in `2026-W31`, which is ISO-8601 week notation.
- **Monthly statistics use a month identifier** — the year and the month, as
  in `2026-08`.

A record is therefore read as a sentence: *this player, in this community, over
this period, played these matches and scored these goals.*

### 9.4 Worked example

One player finishing one match in Community A in the first week of August 2026
is reflected in three Community Statistics records — the same measures, one
community, three periods:

| `community_id` | `period_type` | `period_key` |
|---|---|---|
| Community A | `overall` | `overall` |
| Community A | `weekly` | `2026-W31` |
| Community A | `monthly` | `2026-08` |

Community B holds no record for that match, in any period, and **Community B's
Community Rating for that player does not move**. That is the isolation rule,
expressed as data.

The same match also advances the player's **Global Statistics** and their
**Global Rating** ([§2.1](#21-level-1--global-statistics),
[§3.1](#31-level-1--global-rating)) — the career record, which has no
community and no period.

Every leaderboard and every dashboard block in this document is then one read
of the community model at a stated community, `period_type` and `period_key`.
*Weekly Top Scorers* is *Top Scorers* at this community / `weekly` / the
current week; nothing about the board changes but the period it is asked for.

### 9.5 What this section does not decide

- **Which timestamp places a match in a period**, and in **which time zone** a
  week and a month begin and end — [`OQ-6`](#13-open-questions). A
  configuration choice, not an architectural one: the model is identical
  whichever is chosen, but it must be fixed before the first periodic figure is
  computed ([§14](#14-implementation-readiness)).
- **Any physical schema.** Table names, keys, indexes, policies and the write
  path are engineering decisions taken when the phase is authorised. This
  document defines the model, not its storage.

---

## 10. `SL-1` — One model, not three tables

**Approved in v1.1.** Scoped by v1.2 to the community level; the rationale is
unchanged.

### Decision

The Statistics Engine uses **one unified Community Statistics model carrying
`community_id`, `period_type` and `period_key`**, instead of separate tables
per scope:

| Rejected | |
|---|---|
| `player_statistics` | all-time counters |
| `weekly_statistics` | the same counters, per week |
| `monthly_statistics` | the same counters, per month |

### Why

- **It avoids a duplicated schema.** The three rejected tables hold the *same
  measures* with the same meanings and the same constraints. Three copies of
  one shape is one definition maintained three times — and three chances for
  them to drift.
- **It is easier to maintain.** Every rule that governs a counter — how it is
  incremented, how it is reversed when a result is corrected, what makes it
  valid — is stated once and holds for every scope. Under separate tables,
  each rule has to be restated per table and each restatement can be got wrong
  independently.
- **It extends without redesign.** A new scope is a new `period_type` value,
  not a new table with a new write path, new policies and new client code
  ([§11](#11-future-extensibility)).
- **Leaderboard queries are simpler.** Nine boards become one shape of query
  parameterised by three values. Under separate tables, "Top Scorers" is three
  different queries against three different tables that must be kept agreeing
  with one another; a change to the board applies to one query here and to
  three there.

### Trade-offs, stated plainly

- Every record must carry its community and its period, including the `overall`
  records, where the period key is a constant.
- A single model mixes scopes, so **every read must state its community and its
  period** — a query that forgets to is not wrong-looking, it is just wrong.
  That is a real cost, and it is the reason the three dimensions are specified
  as part of the model's identity rather than left to the reader. It is also
  what [§2.2](#22-level-2--community-statistics) depends on.
- Recording one match touches more than one record — one per period in scope,
  in one community, plus the career record at Level 1. This is a property of
  the feature, not of the model: any design that reports three scopes maintains
  three scopes.

---

## 11. Future extensibility

**Recorded as a property of `SL-1`, not as approved scope.** Nothing in this
section is in the MVP.

The same community model supports further scopes by adding `period_type`
values, with no redesign of the Statistics Engine:

| Possible later `period_type` | Example `period_key` |
|---|---|
| `yearly` | `2026` |
| `season` | a season identifier |
| `tournament` | a tournament identifier |
| `league` | a league identifier |
| custom periods | a caller-defined identifier |

Two things make this hold: the measures are the same whatever the period, and
the period is *data* rather than structure. Adding `yearly` adds no table, no
second write path and no second definition of what a win is — and it does not
touch Level 1, which has no period dimension to extend.

**None of these is approved, planned or scheduled.** They are recorded so a
future request is understood as a new value in an existing model rather than a
redesign.

---

## 12. Out of scope

Four items were **removed** from this list in v1.1 because they became part of
the MVP:

| Removed from Out of Scope | Now specified in |
|---|---|
| ~~Weekly Statistics~~ | [§9](#9-community-statistics--the-time-dimension) |
| ~~Monthly Statistics~~ | [§9](#9-community-statistics--the-time-dimension) |
| ~~Weekly Leaderboards~~ | [§8](#8-community-leaderboards) |
| ~~Monthly Leaderboards~~ | [§8](#8-community-leaderboards) |

Added since:

- **Displaying a Community Rating inside a community context** *(v1.3)*. Future
  versions may choose to; the MVP does not. The Player Profile shows the Global
  Rating and nothing else ([§3.3](#33-binding-rules)).
- **Most Improved** *(v2.0)*. No board ranks by rating movement, in any period
  ([§5.2](#52-highest-rated-is-not-most-improved)).

Everything else stays out of scope, unchanged:

- Charts and any graphical presentation of statistics
- Analytics — trends, form curves, projections, any derived interpretation
- AI recommendations and insights
- Player comparison — head-to-head or side-by-side views
- **Global rankings across communities.** Unchanged by `SL-2` and `SL-3`:
  Global Statistics and the Global Rating are a career record on a profile,
  never a cross-community leaderboard.
- Yearly, season, tournament, league and custom periods
  ([§11](#11-future-extensibility))
- Per-position, per-formation and per-opponent breakdowns
- Exporting or sharing statistics outside the app
- Historical snapshots and "as of" views of a past leaderboard
- Displaying Community Rating History on any screen. It is preserved
  ([§4.5](#45-what-sl-4-implies-for-the-record)) but has no MVP reader.

The MVP shows recorded numbers for three periods. It does not interpret them.

---

## 13. Open questions

**No open question blocks implementation.** Every architectural question is
closed. What remains is presentation parameters: each has an obvious default,
and changing any of them later costs a query or a constant, never a migration.

### Resolved

| ID | Question | Resolution |
|---|---|---|
| `OQ-1` | Are statistics scoped per community, globally, or both? | **RESOLVED** — both. [`SL-2`](#2-sl-2--two-levels-of-statistics) |
| `OQ-2` | What does Highest Rated rank by at the community level? | **RESOLVED** — the Community Rating. [`SL-3`](#3-sl-3--two-rating-systems) |
| `OQ-6` | Which timestamp assigns a match to a period, in which time zone, under which week numbering? | **RESOLVED — 2026-08-01.** Match start, `Asia/Muscat` (UTC+4), ISO-8601 weeks. See below. |
| `OQ-7` | Do the periodic scopes apply to completed matches with a recorded result only? | **RESOLVED by inheritance** — yes. See below. |
| `OQ-8` | What happens to Community Statistics when a player leaves, or rejoins? | **RESOLVED** — preserved, then restored. [`SL-4`](#4-sl-4--the-community-rating-lifecycle) |
| `OQ-9` | What does a Weekly or Monthly Community Rating measure? | **RESOLVED** — the current rating; the period selects the population. [`SL-5`](#5-sl-5--highest-rated-is-a-current-rating-board) |

**`OQ-7` — resolved by inheritance, not by a new decision.** Statistics arise
only from a recorded result: `record_match_result` is the only writer of
counters and ratings, and it requires a stored lineup. A match that was played
but never recorded produces nothing at either level, and a corrected result
reverses in full before the new one applies. This was already true of the built
system; `SL-5`'s wording — "at least one **completed** match" — reads
against the same fact. Nothing was decided here.

### Remaining — non-blocking implementation details

| ID | Question | Default | Why it cannot block |
|---|---|---|---|
| `OQ-3` | **Most Active Player** — measure, tie-break, and whether a departed member may be named | Participation count within the window; deterministic tie-break | Affects one dashboard field. No stored value changes whichever way it goes. |
| `OQ-4` | Leaderboard depth (top *N*) and tie-break order | A fixed depth per board, applied to all nine; deterministic tie-break | Presentation parameters. The model supports any depth. |
| `OQ-5` | How many entries **Rating History** shows | A fixed recent count | A query limit on an existing audit. |
**`OQ-6` is closed.** Its three parts are settled: `2026-W31` is ISO-8601 week
notation; a match is placed by **when it was played**, its start (start and end
differ only for a match crossing midnight); and the **reference time zone is
`Asia/Muscat` (UTC+4)**, approved 2026-08-01. It is one application-wide
constant and **must not change once figures exist**, because changing it
re-buckets history into different weeks and months. Recorded as assumption `A1`
in `Docs/06-ERD.md` §3.9.

### Deferred — future features

None outstanding. Items previously raised as possible scope are recorded in
[§11](#11-future-extensibility) (further periods) and
[§12](#12-out-of-scope) (Most Improved, per-community rating display,
cross-community ranking, and the rest).

---

## 14. Implementation readiness

**Assessment: the specification is sufficient to begin implementation.** The
data model, both levels, the rating lifecycle and all nine board definitions
are fixed. Nothing outstanding can change the shape of the data.

### What may proceed

| Target | Ready | What this specification provides |
|---|---|---|
| **ERD** | **Yes** | **Three separate community-scoped entities**: Community Statistics keyed by `(player, community_id, period_type, period_key)` carrying **the six counters only**; the **Community Rating**, one per `(player, community_id)` and **carrying no period**; and a **Community Rating History**. The existing global entities are unchanged. See [§3.2](#32-level-2--community-rating) and `Docs/06-ERD.md` §3.2. |
| **Database Design** | **Yes** | The dimensions, the two levels, the lifecycle rules and the write/read separation. Physical schema — names, keys, indexes, policies — remains an engineering decision. |
| **Statistics Engine** | **Yes** | What each match must update: the career record and the community record across three periods, applied and reversed by the same arithmetic. |
| **Leaderboards** | **Yes** | Nine boards, each fully defined: measure, window, population and eligibility. Only depth and tie-break remain (`OQ-4`). |
| **Community Dashboard** | **Yes** | All ten figures defined. Only *Most Active Player*'s tie-break and departed-member treatment remain (`OQ-3`). |
| **Workflow** | **Not required** | No approved flow changes. `04-Wireframes.md` and `05-Workflow.md` are already marked *Historical* in `Docs/README.md`; new screens are additive. Update only if the Product Owner wants the screen inventory refreshed. |

### Prerequisites — must be settled during implementation, not before design

Stated explicitly, as requested. None of these blocks starting; each must be
closed before the corresponding work is finished.

1. **The reference time zone is `Asia/Muscat` (UTC+4)** — approved
   2026-08-01, closing `OQ-6`. It must never change once figures exist;
   changing it re-buckets history. Recorded as `A1` in `Docs/06-ERD.md` §3.9.
2. **A Community Statistics record must not cascade from a membership row.**
   `SL-4` requires it to survive a departure and be found again on rejoin, so
   its lifetime is bound to the player and the community, not to
   `community_members` ([§4.5](#45-what-sl-4-implies-for-the-record)).
3. **Community Rating History has no MVP reader but is not optional.** It
   exists so that a corrected result reverses exactly, for the same reason
   `rating_history` does at the career level (`RR-1`, `RR-5`). It must not be
   dropped as unused.
4. **The write path must remain single and system-managed.** `RR-2`'s rule now
   governs two ratings: no client may write either, and the community tables
   should carry select policies only, as `match_results` and `player_statistics`
   already do.
5. **`RR-4`'s constraint-evaluation lesson applies directly.** The reversal path
   for community counters will meet the same `INSERT … ON CONFLICT` behaviour
   that produced the v1.0 reversal defect; apply and reverse should stay
   separate statements over shared arithmetic.
6. **`RR-7`'s known limitation widens.** Editing a lineup after its result is
   recorded already mis-reverses global counters; with community and periodic
   records it mis-reverses more of them. Unchanged in kind, larger in extent —
   still recorded, still not approved for work.

### Documentation alignment — complete

The project documentation was aligned to this specification on **2026-08-01**.
`Docs/01-PRD.md` now places statistics and leaderboards **in** MVP scope,
`Docs/11-Future-Backlog.md` keeps only the genuinely deferred items, `SL-1` …
`SL-5` are recorded in `Docs/10-Design-Decisions.md`, and `06-ERD.md`,
`07-Database-Design.md` and `Results_Rating_Engineering_Decisions.md` (v1.1)
carry the approved architecture. No contradiction remains; see
[Related documents](#related-documents).

---

## 15. Change log

### v2.0 — 2026-08-01 — architecturally complete

**Why this version is complete.** Every question that could change the shape of
the data is answered. The levels are fixed (`SL-2`), the ratings are fixed
(`SL-3`), the lifecycle of a community record is fixed (`SL-4`), and the
meaning of every board is fixed (`SL-5`, `SL-1`). What remains open is four
presentation parameters, each with an obvious default and none capable of
forcing a redesign. That is what promotes this document from a specification
under negotiation to an implementation reference.

**Architecture**

- **`SL-4` approved** — the Community Rating lifecycle: initialization at
  `5.00`, full preservation on departure, restoration on rejoin, and no reset
  ever ([§4](#4-sl-4--the-community-rating-lifecycle)).
- **`SL-5` approved** — Highest Rated is a current-rating board; the period
  selects the population, not the measure
  ([§5](#5-sl-5--highest-rated-is-a-current-rating-board)).
- Community Rating initialization recorded as an approved decision rather than
  the entailment v1.3 inferred
  ([§4.1](#41-initialization--joining-for-the-first-time)).
- Eligibility introduced as a **display filter** — active members appear on
  boards; departed members keep their record and stop being shown
  ([§8](#8-community-leaderboards)).
- Community history stated as unaffected by membership changes
  ([§7.1](#71-overall)).

**Open questions**

- `OQ-8` **RESOLVED** by `SL-4`; `OQ-9` **RESOLVED** by `SL-5`.
- `OQ-7` **RESOLVED by inheritance** — statistics follow recorded results, as
  the built system already does. No new decision was taken.
- `OQ-3`, `OQ-4`, `OQ-5`, `OQ-6` reclassified as **non-blocking implementation
  details**, each with a stated default. `OQ-6` carries a caveat: the reference
  time zone must be fixed before the first periodic figure is computed.
- **No open question blocks implementation.**

**Added**

- [§14 Implementation readiness](#14-implementation-readiness) — what may
  proceed, and six prerequisites stated explicitly.
- A [decision index](#decision-index) covering `SL-1` … `SL-5`.

**Added to Out of Scope**

- **Most Improved** ([§12](#12-out-of-scope)).
- Displaying Community Rating History on any screen.

**Editorial**

- Sections renumbered to place `SL-4` at §4 and `SL-5` at §5; §6–§15 shift
  accordingly.

**Unchanged**

- Every business rule. No rule was redesigned, added or relaxed. The rating
  engine, its constants, result entry, result modification and the audit are
  untouched.
- The MVP measure set, the nine boards and the dashboard blocks.

### v1.3 — 2026-08-01

- **`SL-3` approved** — two independent rating systems, Global and Community
  ([§3](#3-sl-3--two-rating-systems)). `OQ-2` **RESOLVED**.
- Community Rating placed inside the Community Statistics model.
- `OQ-9` added (resolved in v2.0); `OQ-8` widened to cover the Community Rating
  and the rejoining case.
- Out of Scope: displaying a Community Rating inside a community context.

### v1.2 — 2026-08-01

- **`SL-2` approved** — two levels of statistics, Global and Community
  ([§2](#2-sl-2--two-levels-of-statistics)). `OQ-1` **RESOLVED**.
- Community Statistics gained the **`community_id`** dimension.
- `OQ-2` reshaped and made blocking (resolved in v1.3); `OQ-5` narrowed; `OQ-8`
  added.

### v1.1 — 2026-08-01

**Added to MVP scope**

- Community Dashboard *This Week* and *This Month* blocks
  ([§7.2](#72-this-week), [§7.3](#73-this-month)).
- Weekly and Monthly leaderboard scopes, three boards each
  ([§8](#8-community-leaderboards)).
- *Recent Rating History* stated in the Player Statistics set
  ([§6](#6-player-statistics--the-player-profile)), renamed *Rating History* in
  v1.2.

**Architecture**

- The v1.0 statistics storage concept **replaced** by the unified model with
  `period_type` and `period_key`
  ([§9](#9-community-statistics--the-time-dimension)).
- `SL-1` records the decision and its rationale
  ([§10](#10-sl-1--one-model-not-three-tables)).

**Removed from Out of Scope**

- Weekly Statistics, Monthly Statistics, Weekly Leaderboards, Monthly
  Leaderboards ([§12](#12-out-of-scope)).

### v1.0

The approved baseline. Held outside this repository; see *Document provenance*.

---

## Related documents

**All documents below were aligned to this specification on 2026-08-01.** Each
row states the relationship as it now stands.

| Document | Relationship |
|---|---|
| `Docs/01-PRD.md` | Product scope. **Aligned** — statistics and leaderboards are in MVP scope, at both levels, and the exclusions match [§12](#12-out-of-scope). |
| `Docs/11-Future-Backlog.md` | **Aligned** — the MVP items are struck through as delivered or approved; only genuinely deferred enhancements remain, pointing here rather than restating. |
| `engineering/Results_Rating_Engineering_Decisions.md` | **Aligned (v1.1).** What that phase built is **Level 1**. `RR-6`'s trade-off "a per-community leaderboard cannot be built from this table" is answered by Level 2; `RR-2` now governs two ratings; `RR-1` and `RR-5` apply to the Community Rating on the same reasoning; `RR-4`'s constraint-evaluation lesson applies to the new reversal path; `RR-7`'s lineup limitation widens. No decision was withdrawn. |
| `Docs/06-ERD.md` | **Aligned** — the four results entities are recorded as built, and §2a records the approved Level 2 model as *not built*, including that it must not hang off `community_members`. |
| `Docs/07-Database-Design.md` | **Aligned** — schema through `0024`, the rating widened to `NUMERIC(4,2)`, the `RR-2` permission question closed, and a section recording the approved statistics architecture with no schema designed. |
| `Docs/10-Design-Decisions.md` | **Aligned** — `SL-1` … `SL-5` recorded as official project decisions, pointing here for detail rather than duplicating it. `DD-07`'s stale "outside approved scope" clause corrected. |
| `Docs/README.md` | **Aligned** — this specification is indexed as the Product Authority for the feature. |
| `engineering/BTGE_Engineering_Specification.md` | **Aligned** — `OP-1`'s approved values are unchanged; an alignment note records the `numeric(4,2)` widening and states that BTGE balances on the **Global Rating**. |
| `Docs/04-Wireframes.md`, `Docs/05-Workflow.md` | Already marked *Historical*; no change required ([§14](#14-implementation-readiness)). |
| `engineering/ARCHITECTURE_DECISIONS_V1.md` | **Architectural Authority** — the layer rules an implementation must follow. No conflict. |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | **Operational Authority** — §2.2 append-only migrations. No conflict. |

`SL-n` identifiers are this document's own. Cite the document alongside the ID,
per the convention in `Docs/README.md`.
