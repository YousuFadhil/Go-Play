# BTGE Design Knowledge Base

| Field | Value |
|---|---|
| Version | 1.2 |
| Status | **Approved** |
| Role | **Design Authority** — approved product intent. Governs the Engineering Specification. |
| Owner | Product Owner |
| Companion document | `Docs/engineering/BTGE_Engineering_Specification.md` — the Implementation Authority |

## How to read this document

This is the **permanent institutional memory** of the Balanced Team Generation
Engine. It records *why* BTGE works the way it does.

It is **not a specification** and **not a discussion document**. It records
decisions that have already been approved. The Engineering Specification says
*what* to build; this document says *why*, and it is the reason a future
engineer can tell the difference between a rule that may be adjusted and a rule
that is load-bearing.

Everything here is final and approved unless it appears in
[Part H — Open Issues](#part-h-open-issues). Abandoned ideas, rejected
alternatives, and superseded discussion are deliberately absent: only final
outcomes are recorded.

Future engineers are assumed never to read the original conversations.
Everything needed to understand BTGE's design must be in this document.

### Document precedence

Established by `KB-015`:

1. **This Knowledge Base** — approved product philosophy. Governs everything.
2. **The Engineering Specification** — approved engineering rules. Must conform
   to this document.
3. **Implementation** — must conform to both.

When implementation proves difficult, **the implementation changes**. The
approved product philosophy does not. When the Engineering Specification
conflicts with this Knowledge Base, the Specification is the defect — see
[Part E](#part-e-required-corrections-to-the-engineering-specification).

---

## Part A: Product Philosophy (`KB-001` … `KB-015`)

Approved in v1.0. Unchanged in v1.1. Each entry records the decision, the stated
rationale, what the decision forbids, and where it lands in the Engineering
Specification.

### `KB-001` Product Philosophy

**Decision.** BTGE is not a football tactics engine. Its purpose is to create the
fairest possible teams for amateur football communities. It is designed for
community football, not professional football.

**Rationale.** Fairness is always preferred over tactical perfection.

**Forbids.** Any rule justified by tactical merit rather than fairness. Any
feature that would make sense for a professional squad but not for whoever
showed up on a Thursday evening.

**Traces to.** Specification §3 (Design Philosophy).

### `KB-002` Primary Objective

**Decision.** The objective is **overall match quality**, not merely minimizing
rating difference.

**Rationale.** A match with well-distributed positions and a slightly larger
rating gap is better than a match with nearly identical ratings but poor
positional balance.

**Forbids.** Treating `rating_delta` as the headline measure of success.
Optimizing rating first and treating position distribution as a constraint to
satisfy afterwards.

**Traces to.** Specification §7 (Optimization Priorities), §15 (Quality Metrics).

### `KB-003` Position Philosophy

**Decision.** Positions are more important than rating. The engine keeps players
in their natural positions before considering rating optimization. The order is:

1. Primary Position
2. Secondary Position
3. Logical fallback position
4. Emergency placement, only if unavoidable

**Rationale.** Playing out of position is the thing amateur players notice and
resent most; it degrades the match experience more than a rating gap does.

**Forbids.** Moving a player off their primary position to improve rating
balance when the primary was available. Skipping the secondary position and
jumping to a fallback.

**Traces to.** Specification §9 (Position Transition Rules). Steps 3 and 4 are
both expressed there as transitions along the pitch axis, distinguished by
distance: step 3 is the nearest available position, step 4 is a longer move made
only when nothing nearer is possible.

### `KB-004` No Fixed Formations

**Decision.** The engine does not enforce professional formations. It adapts to
the available players. Formations are **derived from the player pool, not
imposed on it**.

**Rationale.** Formations assume a squad selected to fill them. Amateur matches
are made of whoever attended.

**Forbids.** Any hard-coded target shape — 4-4-2, 4-3-3, or otherwise. Any rule
of the form "each team needs *n* defenders" independent of who is present.

**Traces to.** Specification §8 (`BTGE-PD-1`, `BTGE-PD-2`).

### `KB-005` Equal Treatment

**Decision.** The engine has no concept of star players, captains, popular
players, organizers, or senior members. Every player is evaluated **only** by
approved input data.

**Rationale.** Community standing is exactly the bias that manual team-picking
produces and that BTGE exists to remove.

**Forbids.** Any weighting, bonus, protection, or special handling derived from
a player's role in the community, their tenure, or their relationships. An
organizer's own generation must treat the organizer as an ordinary player.

**Traces to.** Specification §4 (Inputs) — the input contract contains no role,
tenure, or social standing field, and this is why.

### `KB-006` Approved Inputs

**Decision.** Only approved inputs are considered:

- Overall Rating
- Primary Position
- Secondary Position
- Date of Birth (for age balance)

Nothing else influences generation.

**Scope clarified in v1.1.** These four are the **Core Player Inputs** — the only
data used to *evaluate and balance* players. See `KB-016`, which defines the one
category of data that may be consulted outside evaluation, and the strict limits
on it.

**Forbids.** Introducing any fifth attribute into player evaluation. Deriving a
proxy for an excluded attribute from an approved one.

**Traces to.** Specification §4.1 (Per-player inputs).

### `KB-007` Manual Intervention

**Decision.** Manual editing exists because community football always requires
occasional human judgment. Manual changes are expected. However, they:

- never train the engine,
- never modify future generations,
- never become hidden business rules.

Every generation starts from scratch.

**Rationale.** An engine that learns from overrides accumulates undocumented
behaviour nobody approved and nobody can audit. Overrides must stay local to the
match they were made in.

**Forbids.** Feedback loops. Storing "the organizer usually moves X to defence"
and acting on it. Any adaptive weighting derived from override patterns.

**Boundary clarified in v1.1.** See `KB-017`. Recording the lineup that actually
played is not learning, and does not breach this entry.

**Traces to.** Specification §13 (`BTGE-MO-3`).

### `KB-008` Human Override Philosophy

**Decision.** Human intervention is **exceptional**. The engine should already
produce a high-quality result. Manual editing is intended only for special
community circumstances.

**Rationale.** Override is a safety valve for circumstances the approved inputs
cannot express, not a routine correction step.

**Forbids.** Treating routine override as acceptable engine behaviour. A result
that consistently requires editing is an engine defect, not a workflow.

**Traces to.** Specification §13 (Manual Override).

### `KB-009` Deterministic Behaviour

**Decision.** Identical inputs must always produce identical outputs.
**Randomness is not part of BTGE.** Where multiple equivalent solutions exist,
deterministic tie-breaking is required.

**Rationale.** A community must be able to trust that the engine is not rolling
dice on their behalf. Determinism also makes results reproducible and auditable.

**Forbids.** Random number generators. Random seeds. Shuffling. Any tie-break
that depends on hash ordering, collection iteration order, thread scheduling, or
wall-clock time.

**Traces to.** Specification §14.4 (Determinism) — which currently contradicts
this entry and must be corrected; see [Part E](#part-e-required-corrections-to-the-engineering-specification).

### `KB-010` Diversity

**Decision.** Diversity exists **only after quality**. The engine must never
reduce team quality merely to create new combinations. Social diversity is a
secondary optimisation goal.

**Rationale.** Variety in lineups is desirable but it is a comfort, not a
fairness requirement. Fairness is the product's reason to exist; variety is not.

**Forbids.** Accepting any measurable loss on priorities 1–4 to gain diversity.
Presenting a more varied but lower-quality split as the better result.

**Traces to.** Specification §12 (`BTGE-DV-1`, `BTGE-DV-3`).

### `KB-011` Goalkeeper Philosophy

**Decision.** Goalkeepers are treated as a special case. The engine allocates
**natural goalkeepers first**. Emergency goalkeeper assignment is the last
resort.

**Rationale.** Goalkeeper is the one position amateur players will not accept
being moved into casually. It is qualitatively unlike the outfield lines.

**Forbids.** Treating `GK` as an ordinary point on the position axis. Filling a
goalkeeper slot by proximity alone.

**Traces to.** Specification §10 (Goalkeeper Rules). Natural goalkeepers are
allocated first and distributed evenly. The trigger conditions for "emergency
assignment" were open in v1.1 and are fixed by `KB-018`.

### `KB-012` Odd Number Philosophy

**Decision.** When player count is odd, one team having one extra player is
acceptable. The engine should **compensate elsewhere** to preserve overall
fairness.

**Rationale.** Refusing to generate, or dropping a player to make the numbers
even, is worse for the community than an uneven split. The extra body is a real
advantage, so it is offset rather than ignored.

**Forbids.** Dropping a player to even the count. Splitting 7/4 when 6/5 is
possible. Ignoring the numerical advantage when scoring the result.

**Traces to.** Specification §11.4 (`BTGE-SC-4`), `BTGE-HC-4`. The compensation
*mechanism* is open — see [Part H](#part-h-open-issues), `OI-5`.

### `KB-013` Performance Philosophy

**Decision.** Optimality is more important than micro-optimisations. The expected
workload — community football matches — allows **searching for the best solution
instead of settling for heuristics**.

**Rationale.** The problem size is bounded and known. Buying speed at the cost of
result quality trades away the product's entire value.

**Forbids.** Returning a "good enough" result when a better one exists.
Abandoning a search on a time budget and returning the best found so far.
Justifying a weaker result by execution speed.

**Traces to.** Specification §14 (Performance Requirements) — which currently
contradicts this entry and must be corrected; see
[Part E](#part-e-required-corrections-to-the-engineering-specification).

### `KB-014` Simplicity

**Decision.** The MVP intentionally avoids:

- machine learning
- AI prediction
- chemistry models
- historical behaviour analysis
- tactical recommendations

**Rationale.** These are **conscious exclusions, not missing features.**

**Forbids.** Adding any of the above under the framing of "completing" BTGE.
Treating their absence as a gap or a defect.

**Scope clarified in v1.1.** "Historical behaviour analysis" means inferring,
predicting, or learning from how players have behaved. It does not cover the
factual record of who played together, whose narrow and non-inferential use is
defined in `KB-016`.

**Traces to.** Specification §17 (Out of Scope).

### `KB-015` Product Rule

**Decision.** If implementation becomes difficult, **the implementation must
change**. The approved product philosophy must not change.

**Rationale.** Difficulty is an engineering signal, not a product signal.

**Forbids.** Relaxing an approved rule because it is expensive, awkward, or slow
to implement. Silently reinterpreting a rule to make code simpler.

**Traces to.** Specification §18 (Change Control), `BTGE-CC-3`, `BTGE-CC-5`.

---

## Part B: Decisions Approved After v1.0

Product Owner decisions taken after the v1.0 philosophy was approved. They carry
the same authority as Part A.

`KB-016` and `KB-017` (v1.1) resolve how Diversity coexists with `KB-006` and
`KB-014`. **There is no contradiction**: the two concerns operate at different
layers, and those entries define the layering.

`KB-018` and `KB-019` (v1.2) close the two open issues raised by the v1.1
knowledge transfer.

### `KB-016` Core Player Inputs vs. Auxiliary Data

**Decision.** BTGE distinguishes two categories of data, and they are not
interchangeable.

**Core Player Inputs** — the only data used to *evaluate and balance* players:

- Overall Rating
- Primary Position
- Secondary Position
- Date of Birth

**Auxiliary Data** — Match History. It is **not a player evaluation input.** It
may be consulted **only** during Diversity optimization (Priority 5), **after all
higher-priority objectives have already been satisfied.**

Historical teammate information must **never** affect:

- player rating,
- position assignment,
- age balancing,
- team strength,
- any optimisation priority above Diversity.

It is **only a deterministic tie-breaker between otherwise equivalent
solutions.**

**Rationale.** The apparent conflict between `KB-006` ("nothing else influences
generation") and `KB-010` (diversity as a secondary goal) dissolves once
evaluation is separated from tie-breaking. Match History never touches how good a
player or a team is judged to be. By the time it is consulted, every judgment of
quality has already been made and the surviving solutions are, by definition,
equally good. It selects among equals; it does not rank.

This is also why Match History does not breach `KB-014`. Match History is a
factual record of who played together. It is not behavioural inference, not
prediction, and not learning — the distinction `KB-014` was drawn to exclude.

**Forbids.**

- Any use of Match History at priorities 1 through 4.
- Deriving a rating, strength estimate, or position preference from history.
- Chemistry modelling in any form — who "plays well with" whom is inference, and
  remains excluded by `KB-014`.
- Allowing history to break a tie that has not yet been established as a tie on
  priorities 1–4.
- Letting Match History resolve a tie non-deterministically (`KB-009` still
  governs).

**Traces to.** Specification §4.2 (Contextual inputs), §12 (Diversity Rules),
§15 (`repeat_pair_count`).

### `KB-017` Match History Reflects Reality, Not Learning

**Decision.** Manual overrides do not train the engine and do not modify future
business rules. However, **if the manually adjusted lineup is the lineup that
actually played the match, that lineup becomes part of Match History** — because
it reflects **reality, not learning.**

**Rationale.** Match History answers one question: who actually played together?
The honest answer is the lineup that took the field, not the proposal the engine
made before the organizer adjusted it. Recording the real lineup is
record-keeping. It is not a feedback loop, because nothing about the *override
itself* is retained, generalised, or reused — only the factual outcome.

**Forbids.**

- Recording the engine's original proposal as history when a different lineup
  played.
- Retaining the override as an override — the fact that a human intervened, what
  they changed, or why, must not influence any future generation.
- Deriving any rule, weight, or preference from override patterns (`KB-007`
  stands unchanged).

**Consequence.** `KB-007`'s "every generation starts from scratch" holds exactly:
each generation reads the Core Player Inputs fresh and carries no learned state.
Match History is data about the past, not state learned from it.

**Traces to.** Specification §13 (`BTGE-MO-5`), which is confirmed correct by
this entry.

### `KB-018` Emergency Goalkeeper Assignment

*Resolves `OI-10`.*

**Decision.** When **no natural goalkeeper exists**, or **only one exists where
two are required**, the engine assigns the **best available emergency
goalkeeper**, selected according to the approved position transition rules.

This is an emergency assignment, **not a new business rule**. `KB-011` already
established emergency assignment as the last resort; this entry fixes the
conditions under which that last resort is reached.

**Rationale.** `KB-011` ranked natural goalkeepers first but never stated when
emergency assignment applies, which left it unreachable. This entry makes the
last resort reachable without changing the ranking.

**Approved interpretation.** This is the governing statement of the guarantee.
It is quoted as approved, and it is the ceiling — see the warning below.

> The BTGE engine always attempts to assign a goalkeeper.
>
> Natural goalkeepers have the highest priority.
>
> If a natural goalkeeper is unavailable, the engine may assign an emergency
> goalkeeper according to the approved position transition rules.
>
> The engine must never fail to generate teams solely because a natural
> goalkeeper is unavailable.

**Do not derive any stronger guarantee than the above.** In particular, this
entry does **not** establish that every goal is always filled, and it does
**not** establish that a goalkeeper-free match can never occur. Those are
inferences, not adopted rules. If either is ever needed, it requires its own
Product Owner decision and its own Knowledge Base entry.

**Forbids.** Refusing to generate because no natural goalkeeper is present.
Preferring an emergency goalkeeper over an available natural one. Selecting the
emergency goalkeeper by any means other than the approved transition rules — in
particular, by rating, by availability, or by asking who volunteers.

**Traces to.** Specification §10 and `BTGE-PT-6`, which currently forbid
emergency assignment outright and must be corrected; see
[Part E](#part-e-required-corrections-to-the-engineering-specification).

### `KB-019` Canonical Ordering as the Final Tie-Break

*Resolves `OI-11`.*

**Decision.** When Match History contains no information — a first match, a new
community, players with no shared history — **Diversity contributes nothing.** If
multiple equally optimal solutions still exist, the engine applies its
**deterministic canonical ordering**. **Randomness is never introduced.**

**Rationale.** `KB-009` requires every tie to resolve deterministically. Match
History is the preferred tie-breaker under `KB-016`, but it is not always
available, and its absence must leave neither an undefined outcome nor an opening
for a random choice.

**Forbids.** Random or seeded selection when history is silent. Treating absent
history as an error. Any ordering that depends on input collection order, hash
ordering, thread scheduling, or wall-clock time — the ordering must be canonical
over the data itself (`KB-C12`).

**Traces to.** Specification §12 (`BTGE-DV-5`) and §14.4 (`BTGE-PF-6`), both of
which currently express this through a seed and must be corrected; see
[Part E](#part-e-required-corrections-to-the-engineering-specification).

---

## Part C: Implicit Knowledge Made Explicit

Reasoning that governed the design but was never written down. Recorded here so
it is not rediscovered by trial and error.

### `KB-C1` Why the priority order is lexicographic with tolerance bands

The five priorities are strictly ordered, not weighted. A weighted sum would let
a large gain on rating balance buy a loss on position distribution, which
`KB-002` forbids outright.

Strict ordering alone, however, makes priorities 3, 4, and 5 unreachable: exact
ties on continuous measures essentially never occur, so the first priority would
decide everything and "if multiple optimal solutions exist" would never be true.
Tolerance bands exist to make the lower priorities reachable: solutions close
enough to the best at a given priority count as equal *at that priority* and pass
to the next.

The bands are what make `KB-010` and `KB-016` operable at all. Without them,
Diversity would be permanently dead code. Band widths are open (`OI-3`).

### `KB-C2` Why "closest logical position" follows the pitch axis

Positions lie on one axis: `GK — DEF — MID — FWD`. Closeness is distance along
it. A midfielder covering defence is a smaller imposition than a forward doing
so, and this ordering is what `KB-003`'s steps 3 and 4 mean in practice — step 3
is the nearest available position, step 4 a longer move made only when nothing
nearer exists.

The axis is not a tactical model. It is the ordering amateur players themselves
recognise when asked to fill in somewhere.

### `KB-C3` Why out-of-position is minimized but never forbidden

Forbidding out-of-position assignment would make many real player pools
ungenerable — a pool of eleven forwards has no valid all-primary solution.
`KB-001` (fairness over tactical perfection) and `BTGE-HC-7` (always return a
valid result) together require that the engine bend rather than refuse.

Out-of-position is therefore a cost to minimize, never a constraint to satisfy.
A high out-of-position count on a difficult pool is a correct result, not a
failure.

### `KB-C4` Why out-of-position assignments are spread across both teams

Minimizing the *total* count is not sufficient. Four out-of-position players all
on one team is visibly unfair in a way that two per side is not, even though the
totals match. Fairness under `KB-001` is comparative, so the imbalance is
measured and minimized separately.

### `KB-C5` Why rating balance is measured on the mean

With odd player counts the teams differ in size, and summed ratings then compare
unlike quantities — the larger team's total is inflated by simply having another
player. Mean rating is well-defined across both cases and reduces to the same
ordering as the sum when sizes are equal. Summed rating is retained only as a
diagnostic.

### `KB-C6` Why the goalkeeper is special without being exempt from being filled

`KB-011` makes goalkeeper qualitatively unlike the outfield lines: it is the one
position players will not accept being moved into casually, so natural
goalkeepers are always allocated first. Being special governs *who* is preferred
for the role and in what order. Under `KB-018` the engine always attempts to
assign a goalkeeper, and where no natural goalkeeper is available it may assign
an emergency one — but no stronger guarantee than `KB-018`'s approved
interpretation may be read into this.

A "natural goalkeeper" is a player with `GK` as primary **or** secondary
position: both are steps 1 and 2 of `KB-003`. An emergency goalkeeper is a player
with no `GK` in either slot, reached at step 4. The distinction is load-bearing —
it is what "natural first, emergency last" means operationally.

### `KB-C7` Why age is computed from Date of Birth rather than stored

A stored age is wrong the day after it is written. Date of Birth is stable, and
age is derived at generation time against the match date. Match date is read in
the device's local time, consistent with `DD-11` in `Docs/10-Design-Decisions.md`.

### `KB-C8` Why age balance is measured two ways

Comparing mean ages alone is defeatable: a team of the very oldest and a team of
the very youngest can produce nearly identical means. `KB-001` fairness is about
what the players perceive, so the distribution is checked as well as the average.

### `KB-C9` Why the engine can never block, warn against, or undo a manual override

`KB-007` and `KB-008` establish that override exists for circumstances the
approved inputs cannot express — an injury, a guest, a falling-out, a player who
must leave early. The engine has no access to those facts by construction
(`KB-005`, `KB-006`), so it is never in a position to judge the organizer's
change. Quality metrics may be recomputed after an override, but only as
information, never as an objection.

Hard constraints remain enforced during override — no duplicated, dropped, or
unassigned players — because those protect data integrity, not result quality.

### `KB-C10` Why Diversity is a tie-breaker and never a goal in its own right

`KB-010` and `KB-016` together mean Diversity has no power to change a result's
quality — only to choose among results already established as equally good. This
is a deliberate ceiling on the feature. If exactly one solution is optimal, it is
returned however familiar its pairings are.

### `KB-C11` Why determinism excludes seeded randomness

`KB-009` rules out randomness, and a seeded generator is randomness with
reproducible output — the sequence is still arbitrary, and identical inputs would
produce different results under a different seed. A community must be able to
re-run a generation and see the same teams. Remaining ties are broken by a fixed
rule over the data, never by a generated sequence.

### `KB-C12` Why the input collection's order must not affect the result

Determinism under `KB-009` means determinism over the *inputs*, not over the
order they happened to arrive in. Two callers passing the same players in
different order must get the same teams, or `KB-005` equal treatment is breached
by accident of iteration order.

---

## Part D: Assumptions and Constraints

Facts a future engineer needs, recorded without recommendation.

### `KB-D1` Capacity

BTGE supports up to 30 players (15 vs 15). Above that, the request is rejected
rather than degraded.

### `KB-D2` Search space at capacity

Splitting 30 players into two teams of 15 admits 77,558,760 distinct partitions
before positions are assigned. `KB-013` records the approved position that this
workload permits searching for the best solution rather than settling for
heuristics. The figure is recorded here as a known engineering constraint that
implementation must accommodate — under `KB-015`, difficulty here is resolved by
changing the implementation, not the rule.

### `KB-D3` Required data does not yet exist

As of `v0.6.0-mvp`, `public.users` carries `primary_position` only, constrained to
`GK`/`DEF`/`MID`/`FWD` (`supabase/migrations/0001_users.sql`). BTGE additionally
requires:

- `overall_rating`,
- `date_of_birth`,
- `secondary_position` (nullable),
- persisted per-match team assignments, to serve as the Match History that
  `KB-016` permits.

These are prerequisites. Their design is a separate schema change and is not
authorized by BTGE's approved documents.

### `KB-D4` BTGE is outside the current MVP scope

The Team Generator is recorded as deferred from MVP in
`Docs/11-Future-Backlog.md`, per the PRD. The Knowledge Base and the Engineering
Specification exist so that the design survives the wait — not because
implementation has been scheduled.

### `KB-D5` A missing secondary position is normal

Secondary Position is optional. A player without one skips step 2 of `KB-003` and
moves from primary to fallback. This is ordinary input and never an error.

### `KB-D6` Team labels carry no meaning

"Team A" and "Team B" distinguish the two sides and nothing more. No rule treats
one as preferred, stronger, or primary.

---

## Part E: Required Corrections to the Engineering Specification

`KB-015` resolves these: the philosophy stands, the Specification changes. They
are recorded here because the Specification is currently marked Approved while
containing them.

| Spec location | Conflicts with | Required correction |
|---|---|---|
| §4.2 "Random seed" input; §14.4 `BTGE-PF-5`, `BTGE-PF-6`; `OP-9`; `seed` in §15 metrics; `TS-37` | `KB-009` — randomness is not part of BTGE | Remove the seed entirely. Determinism is over inputs alone. `OP-9` is void: there is no seed to reuse or vary. |
| §14.3 heuristic search guidance; `BTGE-PF-4` (return best-found-so-far at budget); `OP-8` time budget | `KB-013` — search for the best solution, not heuristics | Remove the time-bounded early return. `OP-8` is superseded as a policy question. |
| §12 `BTGE-DV-5` (no-history tie broken "by the seeded deterministic rule") | `KB-009`, `KB-019` | Retain the rule that absent history is never an error; replace the seeded mechanism with the deterministic canonical ordering. |
| §4.2 lists Teammate history as an undifferentiated input | `KB-016` | Restate as **Auxiliary Data**, explicitly excluded from priorities 1–4. |
| §10 `BTGE-GK-2` ("never conscript an outfield player into goal"); §9 `BTGE-PT-6` ("an outfield player is never moved into goal by transition"); the "plays without a goalkeeper" outcomes in `BTGE-GK-1`, `BTGE-GK-4`, `TS-06`, `TS-07` | `KB-018` — emergency goalkeeper assignment | **Largest correction of the four.** The Specification *prohibits* emergency assignment, which `KB-018` permits. Remove the prohibition and state the approved interpretation as written — the engine always attempts to assign a goalkeeper, natural first, and may assign an emergency goalkeeper under the transition rules. Do not replace the prohibition with a mandate: no stronger guarantee may be written into the Specification than `KB-018` states. Natural-first allocation and even distribution are unaffected. |

**Confirmed correct, no change needed:** §13 `BTGE-MO-5` (the played lineup feeds
Match History) is upheld by `KB-017`.

---

## Part F: Conscious Exclusions

Permanently out of scope. Their absence is a decision, not an omission
(`KB-014`, Specification §17). Recorded so no future engineer proposes them as
completions of the design.

| Excluded | Why |
|---|---|
| Machine learning, AI prediction | `KB-014` simplicity; `KB-007` no learning from use |
| Chemistry models | `KB-014`; inference about players, which `KB-016` explicitly does not license |
| Historical behaviour analysis | `KB-014`; distinct from the factual Match History permitted by `KB-016` |
| Tactical recommendations | `KB-001` — BTGE is not a tactics engine |
| Fatigue, injuries, weather | Not Core Player Inputs (`KB-006`) |
| Player preferences (who to play with, or a position other than declared) | `KB-005` equal treatment; `KB-006` |
| Star players, captains, seniority, organizer status | `KB-005` |
| Rating calculation | BTGE consumes Overall Rating; producing it belongs to the rating engine, itself deferred |
| More than two teams; substitutions and rotation | Not in the approved objective |

---

## Part H: Open Issues

Genuinely unresolved. Each requires a Product Owner decision before the code
depending on it is written. **None may be settled unilaterally by an
implementer** — `KB-015` and `BTGE-CC-6` both apply.

| ID | Open issue | Constrained by |
|---|---|---|
| `OI-1` | Overall Rating scale and precision. | `KB-006` |
| `OI-2` | Minimum supported player count (Specification proposes 2). | `KB-D1` |
| `OI-3` | Tolerance band width per priority. Without these, priorities 3–5 are unreachable. | `KB-C1` |
| `OI-4` | Cost weighting applied to transition distance. | `KB-003`, `KB-C2` |
| `OI-5` | The compensation mechanism for odd player counts. `KB-012` approves that compensation must happen; *how* is undecided. The Specification proposes giving the extra player to the team otherwise weaker on rating. | `KB-012` |
| `OI-6` | Diversity lookback window — how far back Match History is consulted. | `KB-016` |
| `OI-7` | The threshold at which an age spread is reported as wide. | `KB-C8` |
| `OI-8` | Whether any hard ceiling on generation time exists at 30 players. `KB-013` settles the policy — optimality is not traded for speed — but not whether an absolute limit exists. | `KB-013`, `KB-D2` |

### Closed

Recorded so they are not reopened. These are settled; do not treat them as
questions.

| ID | Outcome |
|---|---|
| `OI-9` | **Void.** Seed reuse on re-generation. No seed exists under `KB-009`, so the question has no subject. |
| `OI-10` | **Resolved by `KB-018`.** The engine always attempts to assign a goalkeeper, natural goalkeepers first; where none is available it may assign an emergency goalkeeper under the approved transition rules, and it must never fail to generate solely for want of a natural goalkeeper. No stronger guarantee than `KB-018`'s approved interpretation may be derived. |
| `OI-11` | **Resolved by `KB-019`.** With no Match History, Diversity contributes nothing; any remaining tie is broken by the engine's deterministic canonical ordering. Randomness is never introduced. |

---

## Version History

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-07-27 | Initial Knowledge Base. `KB-001` … `KB-015` approved. |
| 1.1 | 2026-07-27 | Product Owner decision resolving Diversity against `KB-006`/`KB-014`: added `KB-016` (Core Player Inputs vs. Auxiliary Data) and `KB-017` (Match History reflects reality, not learning); scope clarifications noted in `KB-006`, `KB-007`, `KB-014`. Knowledge transfer completed: Parts C–H added. `KB-001` … `KB-015` unchanged. |
| 1.2 | 2026-07-27 | Product Owner clarifications closing the two open issues raised by the v1.1 transfer: added `KB-018` (Emergency Goalkeeper Assignment, resolving `OI-10`) and `KB-019` (Canonical Ordering as the Final Tie-Break, resolving `OI-11`). `KB-011` trace and `KB-C6` rewritten to match `KB-018`; a fourth required Specification correction recorded in Part E. `KB-001` … `KB-017` otherwise unchanged. Before approval, the Product Owner corrected `KB-018`: the guarantee is capped at the approved interpretation quoted in that entry, and the inference "a goalkeeper-free match never occurs" was struck as not adopted. **Approved.** The Knowledge Base is the design authority for BTGE. |
