# Balanced Team Generation Engine (BTGE) — Engineering Specification

| Field | Value |
|---|---|
| Version | 1.5 |
| Status | **Approved** |
| Role | **Implementation Authority** — what to build. |
| Owner | Product Owner |
| Governed by | `Docs/engineering/BTGE_Design_Knowledge_Base.md` v1.6 — the **Design Authority**. If any conflict exists, the Knowledge Base governs product intent and this document must be updated accordingly. |
| Supersedes | `Docs/archive/BTGE_Engineering_Specification_v1.0.docx` — the original approved v1.0, retained as the historical record. The canonical form is this file. |
| Applies to | Go Play — Balanced Team Generation Engine |

> **Document precedence.** The **Knowledge Base** is the design authority and
> governs this document (`KB-015`). This specification is the engineering
> statement of what to build; the Knowledge Base records why, and where the two
> conflict, **the Knowledge Base wins and this document is the defect**. Where
> this document and an *implementation* disagree, this document wins and the
> implementation is the defect.
>
> Business rules here must not be changed by implementation work. Rules carry a
> `KB-nnn` reference where the Knowledge Base is their source; that reference is
> the reason the rule exists and must not be dropped when the rule is edited.
>
> Items marked **`OP-n` (Open Parameter)** are values and thresholds
> deliberately *not* fixed at design time. They are tuning inputs, not business
> rules, and each must be confirmed by the Product Owner before the code that
> depends on it is written. No implementer may silently choose one. Each `OP-n`
> corresponds to the Knowledge Base open issue of the same number (`OI-n`).

---

## 1. Purpose

BTGE is the official engineering specification and single source of truth for
team generation in Go Play.

The engine takes the set of players confirmed for a match and splits them into
two balanced teams, assigning each player a position. "Balanced" means balanced
in the way an amateur football community experiences fairness: both teams have a
sensible spread of positions, comparable overall strength, few players played out
of position, comparable age profiles, and — all else being equal — a lineup that
is not a repeat of last week's.

The engine exists to remove the recurring social friction of picking teams by
hand, while leaving the organizer in full control of the final result.

## 2. Scope

In scope:

- Splitting confirmed players into two teams.
- Deriving position distribution from the players actually available.
- Rating balance between the two teams.
- Age balance between the two teams, calculated from Date of Birth.
- Social diversity as a tie-breaker between equally good solutions.
- Goalkeeper handling, including the absence of a goalkeeper.
- Producing internal quality metrics for the generated result.
- Preserving the organizer's ability to manually override the result.

Out of scope: see [§17 Out of Scope](#17-out-of-scope).

## 3. Design Philosophy

BTGE models **amateur football communities, not professional tactical
formations.** Every rule below follows from that single premise:

1. **No fixed formations.** The engine never targets a 4-4-2, a 4-3-3, or any
   other predefined shape. Formations assume a squad selected to fill them;
   amateur matches are made of whoever showed up.
2. **Position distribution is derived from available players.** The shape of each
   team is an output of who is present, not an input imposed on them.
3. **Respect what players consider themselves.** A player's primary position is
   honoured first, then their secondary, and only then the closest logical
   alternative. Being played out of position is a cost the engine actively
   minimizes, not a free move.
4. **Fairness before optimality.** A perfectly optimized split that is socially
   unacceptable — one team stacked, the same two friends split every week, one
   team visibly older — is a failure regardless of its numeric score.
5. **The organizer has the last word.** The engine proposes; a human disposes.
   Manual override is a first-class feature, not an escape hatch.
6. **Diversity is free or it does not happen.** Variety in lineups is pursued
   only among solutions that are already optimal. Solution quality is never
   traded away for diversity.

## 4. Inputs

### 4.1 Per-player inputs (core)

Provided for every player in the generation set:

| Input | Type | Required | Notes |
|---|---|---|---|
| Player ID | identifier | Yes | Unique within the generation set. |
| Overall Rating | numeric | Yes | Single scalar strength value. Scale per `OP-1`, resolved — 0.0 to 10.0 to one decimal place ([§18.1.1](#1811-resolved-product-decisions)). |
| Date of Birth | date | Yes | Age is derived, never stored as a number. |
| Primary Position | `GK` \| `DEF` \| `MID` \| `FWD` | Yes | The player's declared main position. |
| Secondary Position | `GK` \| `DEF` \| `MID` \| `FWD` \| *none* | No | May be absent — see [§11.6](#116-btge-sc-6-no-secondary-position). |

The four attributes above are the **Core Player Inputs** (`KB-006`, `KB-016`).
They are the only data used to **evaluate and balance** players.

### 4.2 Contextual inputs

Not player attributes, listed so the input contract is complete:

| Input | Required by | Notes |
|---|---|---|
| Match date/time | Age Balance | Age is computed as of the match date. |

### 4.2.1 Auxiliary Data — Match History

Match History is **not a player evaluation input** (`KB-016`). It is Auxiliary
Data, and its use is narrowly bounded:

| ID | Rule |
|---|---|
| `BTGE-AX-1` | Match History may be consulted **only** during Diversity optimization (priority 5), and only **after** priorities 1–4 have already been satisfied. |
| `BTGE-AX-2` | It must **never** affect player rating, position assignment, age balancing, team strength, or any priority above Diversity. |
| `BTGE-AX-3` | It is **only a deterministic tie-breaker** between otherwise equivalent solutions. It selects among equals; it never ranks. |
| `BTGE-AX-4` | Match History is the factual record of who played together, over the lookback window `OP-6`. Deriving a rating, strength estimate, position preference, or any chemistry model from it is forbidden — that is behavioural inference, excluded by `KB-014`. |
| `BTGE-AX-5` | Where a match was manually adjusted, the lineup that **actually played** is the lineup recorded in Match History (`KB-017`) — because it reflects reality, not learning. Nothing about the override itself is retained. |

### 4.3 Input validity

- The generation set contains between **4** and 30 players inclusive (lower
  bound per `OP-2`, resolved — [§18.1.1](#1811-resolved-product-decisions)). A
  set of fewer than 4 is an invalid generation request.
- Player IDs are unique within the set.
- A player missing a required input is a caller error; the engine rejects the
  request rather than substituting a default. In particular the engine must
  **never** invent a rating, a date of birth, or a primary position.

### 4.4 Prerequisite: current schema gap

**As of `v0.6.0-mvp` the data required by this specification does not fully
exist.** `public.users` (migration `0001_users.sql`) carries `primary_position`
only, constrained to `GK`/`DEF`/`MID`/`FWD`.

Before BTGE can be implemented, the following must be added:

- `overall_rating` on the player profile,
- `date_of_birth` on the player profile,
- `secondary_position` on the player profile (nullable),
- a persisted record of team assignments per match, to serve as the teammate
  history the Diversity Rules depend on.

These are prerequisites, not part of BTGE itself. Their design belongs to a
separate schema change and is not authorized by this document.

## 5. Outputs

### 5.1 Team assignments

For each player in the generation set, exactly one assignment record:

| Field | Description |
|---|---|
| Player ID | The player being assigned. |
| Team | `A` or `B`. |
| Assigned Position | `GK` \| `DEF` \| `MID` \| `FWD`. |
| Assignment Basis | `PRIMARY` \| `SECONDARY` \| `TRANSITION` — which rule in [§9](#9-position-transition-rules) produced the assigned position. |
| Out of Position | Boolean; true when Assignment Basis is `TRANSITION`. |

Team labels `A` and `B` carry no meaning beyond distinguishing the two sides.
Nothing in this specification treats one label as preferred over the other.

### 5.2 Quality metrics

The engine returns the metrics defined in [§15 Quality Metrics](#15-quality-metrics)
alongside the assignments. These are **internal**: they exist for testing,
diagnostics, and tuning. Surfacing any of them in the user interface is a
separate product decision and is not authorized by this document.

## 6. Hard Constraints

Hard constraints are inviolable. A result that breaches any of them is invalid
and must never be returned, regardless of how well it scores on the optimization
priorities.

| ID | Constraint |
|---|---|
| `BTGE-HC-1` | Every player in the generation set is assigned to exactly one team. |
| `BTGE-HC-2` | No player appears more than once in the output. |
| `BTGE-HC-3` | No player is dropped. The engine never reduces the generation set to make a nicer split. |
| `BTGE-HC-4` | Team sizes are balanced: equal when the player count is even; differing by exactly one when it is odd. |
| `BTGE-HC-5` | Every assigned position is one of `GK`, `DEF`, `MID`, `FWD`. |
| `BTGE-HC-6` | No team has more than one player assigned `GK`. |
| `BTGE-HC-7` | For any valid input in the supported range, the engine returns a valid solution. Returning "no solution" is not permitted. |

## 7. Optimization Priorities

The engine optimizes in this strict order:

1. **Position Distribution**
2. **Rating Balance**
3. **Minimize Out-of-Position**
4. **Age Balance** (calculated from Date of Birth)
5. **Social Diversity**

### 7.1 How the ordering is applied

The ordering is **lexicographic with tolerance bands**, not a weighted sum.

- Priority *k* is evaluated first. Every solution whose score at priority *k* is
  within the tolerance band for that priority of the best achievable score is
  treated as **equally good at that level**, and survives to be judged at
  priority *k+1*. Solutions outside the band are eliminated.
- A solution that is better at priority *k* can never be beaten by one that is
  better only at priority *k+1* or below.
- Tolerance bands exist because raw continuous metrics almost never tie exactly.
  Without them, priorities 3, 4, and 5 would be unreachable dead rules and the
  requirement "if multiple optimal solutions exist" would never be satisfiable.

The tolerance band for each priority is `OP-3`, **resolved**. The approved
widths are recorded in
[§18.1.1](#1811-resolved-product-decisions).

### 7.2 Consequences

- Rating Balance never overrides Position Distribution. Two evenly-rated teams
  where one has every defender is a worse result than a slightly uneven pair of
  well-shaped teams.
- Social Diversity never overrides anything. It only chooses *between* solutions
  already judged equivalent on priorities 1 through 4. See
  [§12](#12-diversity-rules).

## 8. Position Distribution Rules

| ID | Rule |
|---|---|
| `BTGE-PD-1` | **No fixed formations.** The engine has no target shape and must not encode one. |
| `BTGE-PD-2` | **Distribution is derived from available players.** The target shape of each team is computed from the position profile of the generation set. |
| `BTGE-PD-3` | Each position line present in the generation set is split as evenly as possible between the two teams. Where a line holds an odd number of players, the surplus player goes to one team and the imbalance is carried into the Position Distribution metric. |
| `BTGE-PD-4` | Assignment follows the chain **Primary Position → Secondary Position → Closest Logical Position** ([§9](#9-position-transition-rules)). |
| `BTGE-PD-5` | The engine never manufactures a position line that the generation set cannot support. If nobody is a defender by primary, secondary, or transition, the teams play without defenders. |
| `BTGE-PD-6` | Neither team may be left without any outfield line that the other team has in quantity, where the player pool makes an even split possible. Concentrating all of one line on one side is a Position Distribution failure. |

**Worked illustration** (non-binding, for comprehension only): a set of 14
players holding 2 GK, 4 DEF, 5 MID, 3 FWD produces two teams of 7. The even
split is 1 GK / 2 DEF / 2–3 MID / 1–2 FWD per side. The odd MID and odd FWD are
each carried by one team; no formation was consulted to reach this.

## 9. Position Transition Rules

### 9.1 The assignment chain

For each player, the engine assigns a position by walking this chain and
stopping at the first step that satisfies the team's derived distribution:

1. **Primary Position** — the player's declared main position. Preferred always.
2. **Secondary Position** — used only when the primary cannot be honoured within
   the derived distribution.
3. **Closest Logical Position** — used only when neither primary nor secondary
   can be honoured.

| ID | Rule |
|---|---|
| `BTGE-PT-1` | The chain is strictly ordered. A secondary assignment is never made when the primary is available; a transition is never made when the secondary is available. |
| `BTGE-PT-2` | Only step 3 counts as out-of-position. Primary and secondary assignments are not penalized. |
| `BTGE-PT-3` | Out-of-position assignments are minimized as priority 3, and are distributed as evenly as possible between the two teams. One team absorbing every out-of-position player is itself a failure. |

### 9.2 Closest Logical Position

Positions lie on the pitch axis:

```
GK  —  DEF  —  MID  —  FWD
```

The closest logical position is the nearest position on this axis to the
player's primary position. Transition distance is the number of steps along the
axis:

| From \ To | GK | DEF | MID | FWD |
|---|---|---|---|---|
| **GK** | 0 | 1 | 2 | 3 |
| **DEF** | 1 | 0 | 1 | 2 |
| **MID** | 2 | 1 | 0 | 1 |
| **FWD** | 3 | 2 | 1 | 0 |

| ID | Rule |
|---|---|
| `BTGE-PT-4` | A shorter transition is always preferred to a longer one. `MID → DEF` (distance 1) is chosen over `FWD → DEF` (distance 2) whenever both are possible. |
| `BTGE-PT-5` | Transition distance is measured from the **primary** position, not from the secondary. |
| `BTGE-PT-6` | Transitions into `GK` are governed by [§10 Goalkeeper Rules](#10-goalkeeper-rules), not by distance alone. An outfield player may be moved into goal only as an emergency goalkeeper under `BTGE-GK-2`. |
| `BTGE-PT-7` | A goalkeeper who cannot be used in goal (see [§10.5](#105-surplus-goalkeepers)) transitions outward along the axis, `GK → DEF` first. |

The cost weighting applied to transition distance within the priority-3 metric
is `OP-4`.

## 10. Goalkeeper Rules

Goalkeeper is not an ordinary position and is handled before the outfield split.

### 10.1 Natural and emergency goalkeepers

A **natural goalkeeper** is a player with `GK` as their primary **or** secondary
position. An **emergency goalkeeper** is any other player, placed in goal by
transition under [§9](#9-position-transition-rules).

This section states the goalkeeper guarantee in full, per `KB-018`:

| ID | Rule |
|---|---|
| `BTGE-GK-1` | The engine **always attempts to assign a goalkeeper.** Natural goalkeepers have the highest priority. |
| `BTGE-GK-2` | Where a natural goalkeeper is unavailable, the engine **may** assign an **emergency goalkeeper**, selected according to the position transition rules in [§9](#9-position-transition-rules). |
| `BTGE-GK-3` | The engine **must never fail to generate teams solely because a natural goalkeeper is unavailable.** |
| `BTGE-GK-4` | **No stronger guarantee than `BTGE-GK-1` … `BTGE-GK-3` may be derived from this section.** It does not establish that every goal is always filled, and it does not establish that a goalkeeper-free match can never occur. Either would require a new Product Owner decision and a new Knowledge Base entry (`KB-018`). |
| `BTGE-GK-5` | An available natural goalkeeper is never passed over in favour of an emergency goalkeeper. |
| `BTGE-GK-6` | An emergency goalkeeper is selected **only** by the transition rules — never by rating, by availability, or by asking who volunteers. |
| `BTGE-GK-7` | An emergency goalkeeper is assigned with basis `TRANSITION` and counts as out-of-position under priority 3. |

### 10.2 No natural goalkeeper in the set

| ID | Rule |
|---|---|
| `BTGE-GK-8` | When no player has `GK` as primary or secondary position, neither team has a natural goalkeeper available. `BTGE-GK-1` … `BTGE-GK-7` govern each team independently. |

### 10.3 Exactly one natural goalkeeper

| ID | Rule |
|---|---|
| `BTGE-GK-9` | The single natural goalkeeper is assigned `GK` on one team and stays there. |
| `BTGE-GK-10` | The other team has no natural goalkeeper available; `BTGE-GK-2` applies to it. |
| `BTGE-GK-11` | The natural goalkeeper's team is chosen by the remaining optimization priorities, not by team label. Having the goalkeeper is not itself treated as a strength advantage. |

### 10.4 Multiple natural goalkeepers

| ID | Rule |
|---|---|
| `BTGE-GK-12` | Natural goalkeepers are distributed evenly: with two, one per team. |
| `BTGE-GK-13` | Both natural goalkeepers on the same team is invalid — it breaches `BTGE-HC-6`. |

### 10.5 Surplus goalkeepers

| ID | Rule |
|---|---|
| `BTGE-GK-14` | When the set holds more natural goalkeepers than the two teams can use — three or more — two are assigned `GK`, one per team, and the remainder are treated as outfield players and assigned by the normal chain ([§9](#9-position-transition-rules)), beginning at their secondary position and falling back to `GK → DEF`. |
| `BTGE-GK-15` | A goalkeeper played outfield counts as out-of-position under priority 3 unless placed at their declared secondary position. |
| `BTGE-GK-16` | Which goalkeepers keep the gloves is decided by the remaining optimization priorities. |

## 11. Special Cases

Every special case below must produce a valid result. None of them is an error
condition, and none may cause the engine to refuse to generate.

### 11.1 `BTGE-SC-1`: All attackers

Every player is `FWD` by primary position.

- Both teams are built from forwards.
- The engine spreads them into a workable shape using secondary positions first,
  then transitions (`FWD → MID`, then `FWD → DEF`), applied symmetrically so
  neither team is left as a pure attack while the other is reshaped.
- The out-of-position count will be high. This is correct and expected; the
  engine minimizes it but does not treat it as a failure.

### 11.2 `BTGE-SC-2`: Missing defenders

No player has `DEF` as primary position.

- Players whose **secondary** is `DEF` fill the line first.
- If still short, `MID` players transition to `DEF` (distance 1) before any
  `FWD` player does (distance 2).
- If no player can reasonably cover the line, both teams play without defenders
  (`BTGE-PD-5`). The engine never leaves one team with defenders and the other
  without, where the pool allows otherwise.

### 11.3 `BTGE-SC-3`: Missing midfielders

No player has `MID` as primary position.

- Players whose **secondary** is `MID` fill the line first.
- If still short, `DEF` and `FWD` players are both at distance 1 and are equally
  eligible; the choice between them is made by the remaining optimization
  priorities, and transitions are drawn from both lines rather than gutting one.
- If the line cannot be filled, both teams play without midfielders.

### 11.4 `BTGE-SC-4`: Uneven player counts

The generation set holds an odd number of players.

- One team has exactly one more player than the other (`BTGE-HC-4`).
- The extra player creates a genuine advantage, so the engine compensates: the
  larger team is the one that is otherwise weaker on Rating Balance. The rule
  for selecting the larger team is `OP-5`, **resolved** to exactly that —
  the weaker team receives the extra player
  ([§18.1.1](#1811-resolved-product-decisions)).
- Rating Balance is measured on **mean** rating (see [§15](#15-quality-metrics)),
  which remains meaningful across unequal team sizes.

### 11.5 `BTGE-SC-5`: Large age differences

The generation set spans a wide age range.

- Age Balance (priority 4) compares the **mean age** of the two teams.
- A wide spread must not be concentrated on one side: the engine also balances
  how many players fall above and below the set's median age, so that one team
  is not built from the oldest players and the other from the youngest even when
  the two means happen to match. The tolerance for both measures is `OP-3`
  ([§18.1.1](#1811-resolved-product-decisions)); the definition of "wide
  spread" for reporting purposes is `OP-7`, which remains open.
- Age Balance never overrides Position Distribution, Rating Balance, or
  Out-of-Position minimization.

### 11.6 `BTGE-SC-6`: No secondary position

A player has no secondary position recorded.

- The chain skips step 2 for that player and moves from primary straight to
  closest logical position.
- A missing secondary is normal input, never an error, and never a reason to
  reject the player or the request.

## 12. Diversity Rules

| ID | Rule |
|---|---|
| `BTGE-DV-1` | Diversity applies **only** when multiple optimal solutions exist — that is, solutions judged equivalent on priorities 1 through 4 within their tolerance bands. |
| `BTGE-DV-2` | Among those solutions, the engine chooses the one that most reduces repeated teammate combinations relative to recent matches, using Match History as Auxiliary Data under [§4.2.1](#421-auxiliary-data--match-history). |
| `BTGE-DV-3` | **Solution quality is never reduced for diversity** (`KB-010`). If exactly one solution is optimal, that solution is returned regardless of how familiar the pairings are. Diversity is a tie-breaker and nothing else. |
| `BTGE-DV-4` | Repetition is measured over a bounded lookback window of recent matches within the same community (`OP-6`, resolved as the **last 5 matches** — [§18.1.1](#1811-resolved-product-decisions)), not over all history. |
| `BTGE-DV-5` | When Match History contains no information — a new community, a first match, or players with no shared history — **diversity contributes nothing**. If multiple equally optimal solutions still exist, the tie is broken by the deterministic canonical ordering in [§14.4](#144-determinism) (`KB-019`). Absence of history is never an error. |

## 13. Manual Override

| ID | Rule |
|---|---|
| `BTGE-MO-1` | Manual override **must remain supported**. Any implementation that removes or bypasses it violates this specification. |
| `BTGE-MO-2` | After generation, the organizer may move a player between teams or swap two players **without rerunning the engine**. |
| `BTGE-MO-3` | The engine does not re-optimize, revert, or block a manual change. The organizer's decision stands, including when it worsens every quality metric. |
| `BTGE-MO-4` | Hard constraints [§6](#6-hard-constraints) remain in force under manual override: no player may be duplicated, dropped, or left unassigned, and no team may hold two goalkeepers. |
| `BTGE-MO-5` | A manually adjusted result is the authoritative lineup for that match. It is what is recorded, and it is what feeds the teammate history used by [§12](#12-diversity-rules). |
| `BTGE-MO-6` | Quality metrics may be recomputed for a manually adjusted lineup, but are never used to warn against, discourage, or undo the organizer's change. |

## 14. Performance Requirements

### 14.1 Capacity

| ID | Requirement |
|---|---|
| `BTGE-PF-1` | The engine supports up to **30 players (15 vs 15)**. |
| `BTGE-PF-2` | The supported range is **4** to 30 players inclusive (lower bound per `OP-2`, resolved — [§18.1.1](#1811-resolved-product-decisions)). Outside that range — below 4 or above 30 — the engine rejects the request rather than degrading silently. |

### 14.2 Optimality over speed

| ID | Requirement |
|---|---|
| `BTGE-PF-3` | **Optimality is more important than micro-optimisations** (`KB-013`). The expected workload — community football matches — permits searching for the best solution rather than settling for heuristics. |
| `BTGE-PF-4` | The engine **must not return a "good enough" result when a better one exists.** Abandoning the search on a time budget and returning the best found so far is forbidden. |
| `BTGE-PF-5` | Execution speed is never a justification for a weaker result. Where optimality proves expensive, `KB-015` applies: the implementation changes, not the rule. |

Whether any absolute ceiling on generation time exists at 30 players is `OP-8`.

### 14.3 Search feasibility

Splitting 30 players into two teams of 15 admits **77,558,760** distinct
partitions before positions are assigned. This figure is recorded as a known
engineering constraint that implementation must accommodate under `BTGE-PF-3`.
It is not a licence to substitute a heuristic.

### 14.4 Determinism

| ID | Requirement |
|---|---|
| `BTGE-PF-6` | **Identical inputs always produce identical outputs** (`KB-009`). **Randomness is not part of BTGE** — no random number generator, no seed, no shuffling. |
| `BTGE-PF-7` | Any tie remaining after all five priorities — including the no-history case in `BTGE-DV-5` — is broken by the engine's **deterministic canonical ordering** (`KB-019`), never from unordered iteration, hash ordering, thread scheduling, or wall-clock time. |
| `BTGE-PF-8` | The canonical ordering is defined over the input data itself. Supplying the same players in a different collection order must produce the same result. |

## 15. Quality Metrics

Internal metrics, returned with every result ([§5.2](#52-quality-metrics)). Each
maps to exactly one optimization priority, plus solver diagnostics.

| Metric | Priority | Definition | Better |
|---|---|---|---|
| `position_distribution_score` | 1 | Aggregate deviation between each team's realized position counts and the derived target distribution. | Lower |
| `rating_delta` | 2 | Absolute difference between the two teams' **mean** overall rating. Mean is used so the measure holds under unequal team sizes ([§11.4](#114-btge-sc-4-uneven-player-counts)). | Lower |
| `rating_delta_total` | 2 | Absolute difference in summed rating. Reported for diagnostics; not the ordering metric. | Lower |
| `out_of_position_count` | 3 | Number of players assigned by `TRANSITION`. | Lower |
| `out_of_position_cost` | 3 | Sum of transition distances ([§9.2](#92-closest-logical-position)) weighted per `OP-4`. | Lower |
| `out_of_position_imbalance` | 3 | Difference in out-of-position counts between the two teams (`BTGE-PT-3`). | Lower |
| `age_delta` | 4 | Absolute difference between the two teams' mean age in years, computed from Date of Birth as of the match date. | Lower |
| `age_split_imbalance` | 4 | Difference in the count of above-median-age players between the two teams ([§11.5](#115-btge-sc-5-large-age-differences)). | Lower |
| `repeat_pair_count` | 5 | Number of teammate pairs in this result that also appeared together within the lookback window `OP-6`. | Lower |
| `emergency_goalkeeper_count` | — | How many goalkeepers were assigned as emergency rather than natural (`BTGE-GK-2`). | — |
| `goalkeeper_mode` | — | `NONE` \| `SINGLE` \| `EVEN` \| `SURPLUS`. Which branch of [§10](#10-goalkeeper-rules) applied, counting natural goalkeepers. | — |
| `solution_count_at_optimum` | — | How many solutions were tied at the optimum before diversity broke the tie. Diagnostic for whether `OP-3` bands are usefully sized. | — |
| `elapsed_ms` | — | Solver diagnostic. A result is reproduced from its inputs alone — there is no seed (`BTGE-PF-6`). | — |

Age is computed as completed years between Date of Birth and the match date.
Match date is read in the device's local time, consistent with `DD-11`.

## 16. Test Scenarios

Every scenario below must be covered by an automated test citing the rule IDs it
exercises. Expected results are stated as assertions on outputs and metrics, not
as a fixed expected lineup — several lineups may be equally correct.

### 16.1 Hard constraints

| ID | Scenario | Assertion |
|---|---|---|
| `TS-01` | 10 players, ordinary mix | Every player assigned exactly once; team sizes 5/5. `BTGE-HC-1`, `-HC-2`, `-HC-4` |
| `TS-02` | 11 players | Team sizes 6/5, never 7/4. `BTGE-HC-4` |
| `TS-03` | 30 players (15v15) | Valid result at full capacity; the search is not cut short and no better solution exists. `BTGE-HC-7`, `BTGE-PF-1`, `-PF-3`, `-PF-4` |
| `TS-04` | 31 players | Request rejected; no partial or degraded result. `BTGE-PF-2` |
| `TS-05` | Player missing rating / DOB / primary position | Request rejected; no substituted default. [§4.3](#43-input-validity) |

### 16.2 Goalkeepers

| ID | Scenario | Assertion |
|---|---|---|
| `TS-06` | 12 players, no natural GK (none by primary or secondary) | Generation succeeds — it must not fail for want of a natural goalkeeper (`BTGE-GK-3`). Any player assigned `GK` is an emergency goalkeeper with basis `TRANSITION`, counted out-of-position (`BTGE-GK-2`, `-GK-7`). **The test must not assert that a goalkeeper is present, nor that one is absent** — neither is guaranteed (`BTGE-GK-4`). |
| `TS-07` | 12 players, exactly 1 natural GK | The natural goalkeeper is assigned `GK` and is never passed over (`BTGE-GK-5`, `-GK-9`). If the other team receives a goalkeeper, it is an emergency one selected by the transition rules (`BTGE-GK-2`, `-GK-10`). No assertion either way on whether it does (`BTGE-GK-4`). |
| `TS-08` | 12 players, exactly 2 natural GK | One `GK` per team. `BTGE-GK-12`, `-GK-13` |
| `TS-09` | 12 players, 3 natural GK | Two assigned `GK` (one per team); the third assigned outfield via secondary, else `DEF`. `BTGE-GK-14`, `-PT-7` |
| `TS-10` | 12 players, 5 natural GK | Exactly two `GK` assignments; three outfield; `BTGE-HC-6` holds. |
| `TS-39` | No natural GK; pool contains both `DEF` and `FWD` players | If an emergency goalkeeper is assigned, it is a `DEF` (distance 1), never a `FWD` (distance 3), and never chosen by rating or availability. `BTGE-GK-6`, `-PT-4` |

### 16.3 Position distribution and transitions

| ID | Scenario | Assertion |
|---|---|---|
| `TS-11` | Balanced pool (2 GK / 4 DEF / 6 MID / 4 FWD) | Each line split as evenly as its parity allows; `out_of_position_count` is 0. `BTGE-PD-3`, `-PT-2` |
| `TS-12` | 5 DEF (odd line) | Split 3/2; the imbalance appears in `position_distribution_score` and does not silently vanish. `BTGE-PD-3` |
| `TS-13` | Player with primary `MID`, secondary `DEF`, no `MID` slot free | Assigned `DEF` with basis `SECONDARY`; not counted out-of-position. `BTGE-PT-1`, `-PT-2` |
| `TS-14` | `DEF` line short; both a `MID` and a `FWD` available to transition | The `MID` transitions (distance 1), not the `FWD` (distance 2). `BTGE-PT-4` |
| `TS-15` | Player with primary `FWD`, secondary `DEF`, transition needed | Distance measured from `FWD`, not `DEF`. `BTGE-PT-5` |
| `TS-16` | Pool with no goalkeepers and a short outfield line | No outfield player is transitioned into `GK`. `BTGE-PT-6` |
| `TS-17` | Pool forcing 4 out-of-position players | Split 2/2 across teams, not 4/0. `BTGE-PT-3`, `out_of_position_imbalance` = 0 |

### 16.4 Special cases

| ID | Scenario | Assertion |
|---|---|---|
| `TS-18` | 14 players, all primary `FWD` | Valid result; both teams reshaped symmetrically; no team left as a pure attack while the other is not. `BTGE-SC-1` |
| `TS-19` | 12 players, no `DEF` primary, some `DEF` secondary | Secondary defenders used before any transition. `BTGE-SC-2` |
| `TS-20` | 12 players, no `DEF` primary or secondary | Both teams play without defenders; neither team has defenders while the other does not. `BTGE-SC-2`, `BTGE-PD-5` |
| `TS-21` | 12 players, no `MID` primary or secondary | Transitions drawn from both `DEF` and `FWD`, not exclusively one line. `BTGE-SC-3` |
| `TS-22` | 13 players, ratings skewed | The larger team is the one otherwise weaker on rating. `BTGE-SC-4`, `OP-5` |
| `TS-23` | 16 players, ages 16 to 55 | `age_delta` within band; `age_split_imbalance` shows the old and young are not stacked on opposite sides. `BTGE-SC-5` |
| `TS-24` | Several players with no secondary position | Chain skips step 2 for them; no error; no rejection. `BTGE-SC-6` |

### 16.5 Priority ordering

| ID | Scenario | Assertion |
|---|---|---|
| `TS-25` | Pool where one split gives perfect rating balance but stacks a position line, and another gives good distribution with slightly worse rating | The well-distributed split wins. Priority 1 > 2 |
| `TS-26` | Pool where a lower out-of-position count is achievable only by worsening rating balance beyond its band | Rating balance wins. Priority 2 > 3 |
| `TS-27` | Pool where better age balance requires worsening out-of-position count beyond its band | Out-of-position minimization wins. Priority 3 > 4 |
| `TS-28` | Pool where the most diverse split is worse on any of priorities 1–4 | The higher-quality split wins; diversity is not applied. `BTGE-DV-3`, priority 4 > 5 |

### 16.6 Diversity

| ID | Scenario | Assertion |
|---|---|---|
| `TS-29` | Multiple splits tied on priorities 1–4, with teammate history available | The split with the lowest `repeat_pair_count` is returned. `BTGE-DV-1`, `-DV-2` |
| `TS-30` | Exactly one optimal split, with heavy repeat pairings | That split is returned unchanged. `BTGE-DV-3` |
| `TS-31` | No Match History (first match in a new community) | Valid result; no error; diversity contributes nothing; any remaining tie broken by the canonical ordering. `BTGE-DV-5`, `BTGE-PF-7` |
| `TS-32` | History older than the lookback window | Ignored in `repeat_pair_count`. `BTGE-DV-4` |

### 16.7 Manual override

| ID | Scenario | Assertion |
|---|---|---|
| `TS-33` | Organizer swaps two players after generation | Swap applied; engine not rerun; result not re-optimized. `BTGE-MO-2`, `-MO-3` |
| `TS-34` | Organizer moves a player, creating uneven teams beyond the allowed difference | Rejected under `BTGE-HC-4` / `BTGE-MO-4` — hard constraints survive override. |
| `TS-35` | Organizer makes a change that worsens every metric | Change accepted; no warning that blocks or reverses it. `BTGE-MO-3`, `-MO-6` |
| `TS-36` | Manually adjusted lineup recorded, then a later match generated | The adjusted lineup — not the engine's original proposal — feeds `repeat_pair_count`. `BTGE-MO-5` |

### 16.8 Determinism

| ID | Scenario | Assertion |
|---|---|---|
| `TS-37` | Same inputs, run twice | Byte-identical assignments. No seed is involved. `BTGE-PF-6` |
| `TS-38` | Same inputs, players supplied in a different order | Identical result; ordering of the input collection has no effect. `BTGE-PF-8` |
| `TS-40` | Codebase check | No random number generator, seed, or shuffle is reachable from the generation path. `BTGE-PF-6` |

## 17. Out of Scope

The following are explicitly **not** part of BTGE. They must not be implemented,
approximated, or partially introduced under this specification:

- **Player chemistry** — modelling which players perform better together.
- **AI tactics** — tactical instruction, formation recommendation, or style of play.
- **Fatigue** — load tracking, minutes played, recovery.
- **Injuries** — injury status, risk, or return-to-play handling.
- **Weather** — conditions affecting selection or shape.
- **Player preferences** — requests to play with or against particular people, or
  to play a position other than the declared primary and secondary.
- **Rating calculation** — BTGE consumes Overall Rating as an input. Producing,
  updating, or recalculating ratings belongs to the rating engine, which remains
  a deferred backlog item (`Docs/11-Future-Backlog.md`).
- **More than two teams** — three-way or rotating splits.
- **Substitutes and rotation** — in-match substitution planning.
- **Persisting results** — schema and storage for generated lineups are a
  separate change ([§4.4](#44-prerequisite-current-schema-gap)).
- **Machine learning, AI prediction, historical behaviour analysis** — inferring,
  predicting, or learning from how players have behaved (`KB-014`).

**Not excluded:** Match History. The factual record of who played together is
Auxiliary Data and is permitted within the strict bounds of
[§4.2.1](#421-auxiliary-data--match-history) (`KB-016`). It is a record, not
behavioural inference — the distinction `KB-014` was drawn to make.

## 18. Change Control

| ID | Rule |
|---|---|
| `BTGE-CC-0` | The **Knowledge Base** (`Docs/engineering/BTGE_Design_Knowledge_Base.md`) is the design authority and governs this document. Where the two conflict, the Knowledge Base wins and this document is the defect (`KB-015`). |
| `BTGE-CC-1` | Subject to `BTGE-CC-0`, this document is the single source of truth for what to build. |
| `BTGE-CC-2` | Any future implementation of the Team Generation Engine must follow this specification. |
| `BTGE-CC-3` | **Changes require a new specification version.** No business rule in this document may be changed by implementation work, refactoring, bug fixing, or tuning. |
| `BTGE-CC-4` | A new version requires Product Owner approval, a version increment, and an entry in [§18.2](#182-version-history). |
| `BTGE-CC-5` | Where code and specification conflict, the specification is authoritative and the code is the defect. |
| `BTGE-CC-6` | Where a rule here is unclear or a case is unaddressed, implementation **stops and the Product Owner is asked**. Ambiguity is never resolved by guessing in code. |
| `BTGE-CC-7` | Resolving an Open Parameter ([§18.1](#181-open-parameters)) is a Product Owner decision, recorded here. It does not require a major version increment, but it does require this document to be updated before the dependent code is written. |

### 18.1 Open Parameters

These were deliberately left unfixed at design time. **None of them is a business
rule**, and none classified as a Product Decision may be chosen unilaterally by
an implementer. Each `OP-n` is the same question as Knowledge Base open issue
`OI-n`.

#### What "blocks" means

Two distinct gates, and they must not be conflated:

- **Blocks Implementation** — work cannot begin. The architecture itself cannot
  be built until the value is known.
- **Blocks Final Validation** — work can begin and proceed, but the engine
  cannot be validated or released until the value is known.

**No open parameter blocks implementation.** Every one of them is a configurable
value that the architecture accommodates rather than depends on. Implementation
may begin with all eight outstanding, provided each is expressed as
configuration and no default is silently treated as a decision.

| ID | Parameter | Classification | Blocks Implementation | Blocks Final Validation | Depends on |
|---|---|---|---|---|---|
| `OP-1` | Overall Rating scale and precision (range, integer or decimal). | Product Decision | No | No — **resolved**, [§18.1.1](#1811-resolved-product-decisions) | Rating Balance; the prerequisite schema change ([§4.4](#44-prerequisite-current-schema-gap)) |
| `OP-2` | Minimum supported player count. | Product Decision | No | No — **resolved**, [§18.1.1](#1811-resolved-product-decisions) | [§4.3](#43-input-validity), `BTGE-PF-2` |
| `OP-3` | Tolerance band per priority — how close two solutions must be to count as equally good at each of priorities 1–4. | Product Decision | No | No — **resolved**, [§18.1.1](#1811-resolved-product-decisions) | [§7.1](#71-how-the-ordering-is-applied) |
| `OP-4` | Cost weighting applied to transition distance in `out_of_position_cost`. | Engineering Decision | No | No | `BTGE-PT-4`, [§15](#15-quality-metrics) |
| `OP-5` | Which team receives the extra player on an odd count. | Product Decision | No | No — **resolved**, [§18.1.1](#1811-resolved-product-decisions) | `BTGE-SC-4`, `KB-012` |
| `OP-6` | Diversity lookback window — how many recent matches, or what time span, counts as "recent". | Product Decision | No | No — **resolved**, [§18.1.1](#1811-resolved-product-decisions) | `BTGE-DV-4` |
| `OP-7` | Threshold at which an age spread is reported as wide. | Implementation Detail | No | No | `BTGE-SC-5` |
| `OP-8` | Whether any absolute ceiling on generation time exists at 30 players. `KB-013` settles the policy — optimality is never traded for speed — but not whether a hard limit exists. | Engineering Decision | No | No | [§14.2](#142-optimality-over-speed) |

**`OP-3` in particular — resolved.** The record of why it was held open is kept
because it explains the shape of the code: the tolerance-band *mechanism* is
architecture and was built against configurable parameters, while the *values*
were a Product Decision required before the engine could be validated or
released. That gate was a Blocks Final Validation gate, never a Blocks
Implementation gate. The values were approved on 2026-07-31 and are recorded in
[§18.1.1](#1811-resolved-product-decisions); the priority-ordering scenarios
`TS-25` … `TS-28`, which could not be written without them, are now writable.

**Classification meanings.** *Product Decision* — belongs to the Product Owner;
`BTGE-CC-6` applies. *Engineering Decision* — the product intent is already
approved and closed; the implementer chooses within it and records the choice
here (`BTGE-CC-3`). *Implementation Detail* — needs no decision from anyone; it
is handled during implementation and documented.

**Closed.** `OP-9` (seed reuse on re-generation) is **void**: no seed exists
under `KB-009`, so the question has no subject. Recorded so it is not reopened.

**Open Parameter review — closed.** All eight parameters were reviewed and
classified; the results are the table above. Five required Product Owner
decisions (`OP-1`, `-2`, `-3`, `-5`, `-6`), two are Engineering Decisions the
implementer may settle and record (`OP-4`, `-8`), and one is an Implementation
Detail (`OP-7`). The review is not reopened by implementation work.

**The Product Decision gate is closed.** All five parameters that blocked final
validation — `OP-1`, `OP-2`, `OP-3`, `OP-5` and `OP-6` — were resolved by the
Product Owner on 2026-07-31 and are recorded in
[§18.1.1](#1811-resolved-product-decisions). **No Product Decision now blocks
BTGE final validation.**

This is a statement about the *gate*, not about the outcome. **Final validation
has not been executed and has not passed.** The two must not be conflated: the
gate closing means validation may now be planned and run, nothing more. What
remains outstanding is engineering, not product — `OP-4` and `OP-8` are
Engineering Decisions and `OP-7` an Implementation Detail, and none of the three
has ever blocked validation.

Two questions deliberately outside this gate remain open and are **not** settled
by anything here:

- **Who may change a player's `overall_rating`.** A Product/Business Policy
  decision, explicitly separate from `OP-1`, which fixes the scale and nothing
  else. See `Docs/07-Database-Design.md`.
- The rating engine that would *produce* a rating, which [§17](#17-out-of-scope)
  places outside BTGE entirely.

#### 18.1.1 Resolved Product Decisions

Recorded under `BTGE-CC-7`. Each entry is the Product Owner's decision as
approved; no implementer may reinterpret, round, or tune a value here.

**`OP-1` — Overall Rating scale and precision.** Approved 2026-07-31.

| Property | Approved value |
|---|---|
| Minimum | **0.0** |
| Maximum | **10.0** |
| Precision | **0.1** — one decimal place |
| Default | **5.0** |
| Null permitted | **No** |

The scale therefore admits **101 distinct values**: 0.0, 0.1, 0.2 … 9.9, 10.0.

This approval formalized the contract implemented by migration
`0018_btge_schema.sql` — at the time `numeric(3,1)`, `NOT NULL DEFAULT 5.0`,
constrained by `users_overall_rating_range` to `0.0 … 10.0`. It required no
migration and no change to the engine, which treats rating as an opaque number
and never assumes a range ([§4.1](#41-per-player-inputs-core)).

> **Alignment note — 2026-08-01.** The **approved values above are
> unchanged.** Two facts around them have moved, and neither touches `OP-1`:
>
> - **Storage was widened to `numeric(4,2)`** by migration `0022`, because the
>   approved rating engine moves a rating by `0.05` for a goal and one decimal
>   place cannot represent that reversibly (`RR-1` in
>   `Results_Rating_Engineering_Decisions.md`). `OP-1`'s `0.1` precision is the
>   **presentation** contract — how a rating is read by a human — and it still
>   holds. The engine is unaffected either way.
> - **There are now two ratings** (`SL-3` in
>   `Statistics_Leaderboards_MVP_Specification.md`): a Global Rating and a
>   per-community Community Rating. **BTGE balances on the Global Rating**,
>   `users.overall_rating`, exactly as §4.1 has always specified. The Community
>   Rating is a leaderboard measure and is never a Core Player Input.

**Who may change a player's rating is not decided here.** That is a separate
Product/Business Policy question; `OP-1` fixes the scale, its precision and its
default, and nothing else. Migration `0022` settled it for the *engine* — the
rating is system-managed and no client may write it (`RR-2`) — while whether an
**administrator** may adjust one by hand remains open.

**`OP-2` — Minimum supported player count.** Approved 2026-07-31.

| Property | Approved value |
|---|---|
| `minPlayers` | **4** |
| Smallest supported match | **2 v 2** |

Product rationale, as approved: 4 is the minimum size of a supported Go Play
match. **The rule applies to the product as a whole, not to team generation
alone** — a match the product does not support should not be creatable, so the
same bound governs `matches.starting_players` (4 … 30) as governs the
generation set. Fewer than 4 confirmed players is an invalid generation
request; 4 or more is eligible, subject to every other approved rule.

**Decision history.** Three values have stood here, and the sequence matters:

1. The Specification originally *proposed* 2, never approved.
2. The Product Owner approved **6** (3 v 3) on 2026-07-31.
3. On review of how match capacity relates to team generation — `starting_players`
   caps the confirmed roster, so a bound of 6 would have made every match below
   it permanently un-generatable while remaining creatable — that decision was
   **superseded the same day** by the final approved minimum of **4**.

The values 2 and 6 survive only as history, here and in
[§18.2](#182-version-history). **No normative rule in this document states
either as the current minimum.**

**`OP-3` — Tolerance bands.** Approved 2026-07-31.

| Priority | Parameter | Approved value |
|---|---|---|
| 1 — Position Distribution | `distributionBand` | **2** |
| 2 — Rating Balance | `ratingBand` | **0.10** |
| 3 — Minimize Out-of-Position | `outOfPositionBand` | **2** |
| 4 — Age Balance | `ageBand` | **1.00** |

Product rationale, as approved:

- Match fairness and generation quality take priority over generation speed.
- The generator should seek the highest-quality balanced result even when
  generation takes longer.
- Strength balance is a major fairness objective.
- Limited positional flexibility is acceptable when it produces a meaningfully
  fairer match.
- Closely related positional transitions are acceptable within the approved
  transition model of [§9](#9-position-transition-rules).
- Large or unnecessary positional compromises should remain disfavoured.
- Age balance matters, but greater tolerance is acceptable relative to the
  higher-priority criteria.
- Performance optimization must not silently reduce generation quality or alter
  these Product Decisions.

Each value is expressed in the units of its own metric as defined in
[§15](#15-quality-metrics): `distributionBand` and `outOfPositionBand` in the
integer units of `position_distribution_score` and `out_of_position_cost`,
`ratingBand` in Overall Rating points, `ageBand` in years of mean age.

**`OP-5` — Odd player count rule.** Approved 2026-07-31.

| Property | Approved decision |
|---|---|
| Rule | **`OddCountRule.weakerTeamGetsExtra`** |
| Behaviour | When the confirmed player count is odd, the team that would otherwise be **weaker by rating** receives the extra player |

Product rationale, as approved: the extra player compensates for the weaker
team's rating strength, serving the primary objective of the fairest practical
match.

This confirms the behaviour [§11.4](#114-btge-sc-4-uneven-player-counts) already
described provisionally, and `KB-012`'s requirement that the numerical advantage
be offset rather than ignored. **No additional odd-count rule or tie-breaking
policy is introduced** beyond what this specification already defines.

**`OP-6` — Diversity lookback window.** Approved 2026-07-31.

| Item | Approved decision |
|---|---|
| Diversity basis | **Last N matches** |
| N | **5** |
| Time-based window | **None approved** |

Product rationale, as approved:

- The system should consider each player's last 5 relevant matches when
  evaluating historical team diversity.
- A match-count window provides predictable behaviour regardless of how
  frequently a community plays.
- Diversity remains subordinate to the higher-priority balancing criteria of
  [§7](#7-optimization-priorities), unchanged by this decision.

No time-duration form of `OP-6` is approved. Where an implementation exposes a
time-span option alongside the match count, that option is outside the approved
decision and must be left unset.

### 18.2 Version history

| Version | Date | Status | Change |
|---|---|---|---|
| 1.0 | 2026-07-27 | Approved | Initial specification. Adopted as the single source of truth for team generation. |
| 1.1 | 2026-07-27 | Approved | **Synchronized with Knowledge Base v1.2**, which becomes the governing design authority (`BTGE-CC-0`). Four corrections: **(1)** randomness removed entirely — the seed is gone from §4.2, §14.4, §15 and `TS-37`; ties now resolve by deterministic canonical ordering (`KB-009`, `KB-019`). **(2)** §14.2 reversed from a heuristic time budget to optimality over speed; §14.3 no longer licenses heuristics (`KB-013`). **(3)** Match History restated as Auxiliary Data in a new §4.2.1 (`BTGE-AX-1` … `-AX-5`), bounded to priority 5 and barred from evaluation (`KB-016`, `KB-017`); §17 clarifies it is not the excluded "historical behaviour analysis". **(4)** §10 rewritten for emergency goalkeeper assignment (`KB-018`): the prohibition in the old `BTGE-GK-2` and `BTGE-PT-6` is removed and replaced with the approved guarantee, capped by `BTGE-GK-4` — no stronger guarantee may be derived. **ID changes:** goalkeeper rules renumbered `BTGE-GK-1` … `-GK-16`; `BTGE-PF-3` … `-PF-6` renumbered `-PF-3` … `-PF-8`. **Added:** `BTGE-CC-0`, `BTGE-AX-1` … `-AX-5`, `TS-39`, `TS-40`, metric `emergency_goalkeeper_count`. **Closed:** `OP-9` void; `OP-8` narrowed. |
| 1.5 | 2026-07-31 | Approved | **`OP-2` superseded within the same day: the approved minimum is 4, not 6.** On reviewing how match capacity relates to team generation — `matches.starting_players` caps the confirmed roster, so a minimum of 6 would have left every smaller match creatable but permanently un-generatable — the Product Owner lowered the bound to **4** (2 v 2) and extended it to the product as a whole rather than to generation alone. §4.3 and `BTGE-PF-2` now read 4; §18.1.1's `OP-2` entry carries the value and the full 2 → 6 → 4 sequence. Implemented in the database by migration `0019_minimum_match_size.sql`, which moves `matches_starting_players_check` and the `update_match` guard from 2 to 4. **Only `OP-2` changed** — `OP-1`, `OP-3`, `OP-5` and `OP-6` are untouched, and the Product Decision gate remains closed. |
| 1.4 | 2026-07-31 | Approved | **`OP-1`, `OP-2` and `OP-5` resolved**, closing the Product Decision gate: with `OP-3` and `OP-6` already settled in v1.3, **no Product Decision blocks final validation any longer**. `OP-1`: 0.0–10.0, precision 0.1, default 5.0, not null — formalizing the contract migration `0018` already implements, with no migration and no engine change. `OP-2`: `minPlayers` **6** (3 v 3), **superseding the provisional lower bound of 2**; §4.3 and `BTGE-PF-2` now read 6, and rejection applies below 6 as well as above 30. `OP-5`: `weakerTeamGetsExtra`, confirming §11.4. All three recorded in [§18.1.1](#1811-resolved-product-decisions). §4.1 and §11.4 now point at the approved values. **The gate closing is not a claim that final validation has been executed or passed.** Still open and unaffected: `OP-4`, `OP-7`, `OP-8` (never blocking), and the separate Product/Business Policy question of who may change a player's rating. |
| 1.3 | 2026-07-31 | Approved | **`OP-3` and `OP-6` resolved** by Product Owner decision and recorded in a new [§18.1.1](#1811-resolved-product-decisions), per `BTGE-CC-7`. `OP-3`: `distributionBand` 2, `ratingBand` 0.10, `outOfPositionBand` 2, `ageBand` 1.00. `OP-6`: last 5 matches, no time-based window. §18.1's table, its "`OP-3` in particular" note and the `BTGE-DV-4` rule updated to match; §7.1 and §11.5 now point at the approved values. **No business rule changed** — only parameters that were deliberately left unfixed are now fixed. `OP-1`, `OP-2` and `OP-5` remain open and still block final validation; `OP-4`, `-7`, `-8` are unaffected. Governing Knowledge Base reference corrected to v1.4 (it had been left at v1.2 while the Knowledge Base stood at v1.3). |
| 1.2 | 2026-07-27 | Approved | Open Parameter review closed (`BTGE-CC-7`). §18.1 gained a classification per parameter — Product Decision, Engineering Decision, or Implementation Detail — and split blocking into two gates: **Blocks Implementation** and **Blocks Final Validation**. **No open parameter blocks implementation**; five block final validation (`OP-1`, `-2`, `-3`, `-5`, `-6`). `OP-3` is explicitly recorded as Blocks Final Validation, not Blocks Implementation: the tolerance-band mechanism is architecture and is buildable now against configuration, while the values are a Product Decision required before validation and release. No business rule changed. |
