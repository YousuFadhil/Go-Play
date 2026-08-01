# Results / Rating — Engineering Decisions

| Field | Value |
|---|---|
| Version | 1.1 |
| Status | **Approved record** — aligned to Statistics & Leaderboards v2.0 |
| Role | **Decision record** — why the Results / Rating Integration phase was built the way it was |
| Owner | Product Owner |
| Applies to | `app/lib/features/results/`, `supabase/migrations/0022`–`0024` |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Phase completed | 2026-08-01 |
| Aligned | 2026-08-01 — see *Alignment note* below |

> **Alignment note (v1.1).** Nothing this phase built has changed, and no
> decision below is withdrawn. What changed is the product scope around them:
> on 2026-08-01 the Product Owner approved
> `engineering/Statistics_Leaderboards_MVP_Specification.md` **v2.0**, which is
> now the authoritative source for statistics and leaderboards. Two
> consequences run through this document:
>
> - **What this phase built is Level 1.** `player_statistics` and
>   `users.overall_rating` are **Global Statistics** and the **Global Rating**
>   under `SL-2` and `SL-3`. They remain correct exactly as built.
> - **A second level is approved but not built.** Community Statistics and the
>   Community Rating are additive beside Level 1; no schema for them exists
>   yet. Where a section below reasons from "statistics and leaderboards are
>   out of MVP scope", that premise has expired — the *decision* it supported
>   still stands, and the updated reasoning is stated inline.
>
> Only the version, this note and the passages it names were edited. The
> engineering record — `RR-1` … `RR-7`, the defect analysis and the lessons —
> is unchanged.

> **Scope.** This document records *engineering* decisions taken while
> implementing an approved product scope. It defines no business rules and
> changes none: the approved rules for result entry, validation, the rating
> engine and result modification came from the Product Owner with the phase
> brief. Where this document and `Docs/01-PRD.md` or
> `Docs/10-Design-Decisions.md` disagree about *what the product does*, they
> win. What this document is authoritative about is *why the implementation
> looks the way it does* — the four decisions that were not dictated by the
> brief, the defect found in production validation, and the assumptions the
> implementation adopted.
>
> It is a record, not a plan. Everything below is built, applied and tested.

---

## Decision index

| ID | Decision | Migration |
|---|---|---|
| `RR-1` | Rating storage widened to `numeric(4,2)` | `0022` |
| `RR-2` | `overall_rating` is system-managed, enforced by column privilege | `0022` |
| `RR-3` | The reversal defect was fixed forward, not by editing `0022` | `0023` |
| `RR-4` | Apply and reverse are separate statements over shared arithmetic | `0023` |
| `RR-5` | Rating history is immutable; a reversal is a new row | `0022` |
| `RR-6` | Player statistics are global, matching the rating's scope — **now Level 1 under `SL-2`** | `0022` |
| `RR-7` | Four assumptions adopted where the brief was silent | `0022` |

## What the phase built

Four tables — `match_results`, `match_goals`, `rating_history`,
`player_statistics` — one write path, `record_match_result`, and a Flutter
feature (`app/lib/features/results/`) following the existing port / repository /
adapter separation. The approved rating engine is **winner +0.10, loser −0.10,
goal +0.05 each, MVP +0.20**, applied after a result is recorded and reversed
in full when one is corrected.

---

## 1. `RR-1` — Rating precision

### Decision

`users.overall_rating` was widened from `numeric(3,1)` to `numeric(4,2)`. The
approved `OP-1` range of `0.0 … 10.0` is unchanged, and so is the range CHECK.

### Why the previous precision could not hold the engine

The approved engine moves a rating by **0.05** for a goal. One decimal place
cannot represent that value at all. Storing it would have forced a rounding
step, and every available rounding gives a wrong answer:

- Round to nearest — one goal moves the rating by 0.1 or by nothing depending
  on where the player already sits. The bonus becomes a coin toss.
- Round down — a single goal is worth nothing, ever. The rule is deleted, not
  implemented.
- Accumulate and round once at the end — one goal and two goals both land on
  0.1, so a brace is indistinguishable from a single strike.

None of these implements the rule the Product Owner approved. The precision was
not a preference; the rule is unrepresentable without it.

### Why reversibility makes this non-negotiable

The approved modification rules require a corrected result to **reverse all
previous rating changes** before applying the new one. Rounding is not an
invertible operation. If 5.00 + 0.05 rounds to 5.1, then subtracting 0.05 and
rounding again yields 5.1 — the player keeps a tenth they never earned, and
every subsequent correction compounds the error. Reversal is only exact when
the stored value can hold every value the arithmetic produces.

Every approved delta — 0.05, 0.10, 0.20 — is a multiple of 0.05, so two decimal
places are exactly sufficient. Nothing wider was taken.

### Why presentation may still show one decimal

Storage precision and display precision are different questions with different
owners. `OP-1` describes a **0.0 – 10.0 scale to one decimal place**, which is
how a rating is read by a human; it does not require the database to be unable
to represent the arithmetic that produces it. A screen is free to render 5.35
as `5.4` or `5.3` — that is a presentation decision, and this phase did not
take one because no approved document asks for a rating to be displayed yet.

The rule for maintainers: **round for the eye, never for the record.** A
rounded value must never be written back.

### Compatibility

Widening a `numeric` scale is backward compatible. Every existing value was a
tenth and survived unchanged; the range CHECK still holds; no client code
required a change, because `ratingFromDb` already parsed `numeric` from either
a JSON number or its text form.

---

## 2. `RR-2` — Rating security

### Decision

`users.overall_rating` is system-managed. No client may write it. The
`UPDATE` privilege on `public.users` was revoked from `authenticated` and
re-granted **per column** on the five profile fields a player owns:
`phone`, `full_name`, `primary_position`, `secondary_position`,
`date_of_birth`.

### What this settled

`Docs/07-Database-Design.md` records that who may change `overall_rating` was
**not settled**: migration `0018` added the column and its range constraint and
said nothing about permissions, so `users_update_own_profile` governed it like
any other profile field, and the rating-adjustment workflow was expected to
decide.

This phase *is* that workflow, for the only writer it introduces. The decision
taken is the narrow one: the rating engine is the sole author of a rating.
Whether an administrator should be able to adjust a rating by hand remains
open, and is deliberately **not** decided here.

> **Aligned.** `SL-3` approves a **second** rating — the Community Rating — and
> `SL-3` §3.5 states that this rule governs it too: a rating is
> system-managed, and no client may write either one. `SL-3` introduces a
> second rating, not a second writer. The column-privilege pattern below is
> the one the community level should follow.

### Why RLS alone could not do it

Row Level Security answers *which rows* a statement may touch. It cannot answer
*which columns*. The existing policy —

```sql
create policy "users_update_own_profile" on public.users
  for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);
```

— is correct and unchanged. It says a player may update their own row. It has
no way to say *except that column*, and adding a `with check` on the rating
cannot help either: the check would have to compare against the old value,
which a policy expression cannot see in a way that distinguishes "unchanged"
from "changed to the same thing" reliably, and even then the rule would live in
a policy rather than where privileges belong.

Column-level `GRANT` is PostgreSQL's actual answer to the actual question. It
is enforced by the privilege system, before RLS is consulted, and it applies to
every path into the table.

### Why this is integrity, not hardening

Without it the rating engine is decoration. A signed-in player could have sent

```
PATCH /rest/v1/users?id=eq.<self>   {"overall_rating": 10.0}
```

and been believed. Every downstream consumer trusts that column: the Balanced
Team Generation Engine reads it as a Core Player Input (§4.1) and balances
sides from it, and `player_statistics.currentRating` reports it. A writable
rating means self-selected team balance and a meaningless leaderboard.

The narrowing changed nothing a client could legitimately do. The registration
and profile screens write exactly the fields still granted; the integration
suite asserts both halves — that a rating write is refused with `42501`, and
that a profile write still succeeds.

### The corresponding rule for the new tables

The same reasoning produced the write model for everything this phase added.
`match_results`, `match_goals`, `rating_history` and `player_statistics` have
**select policies and nothing else**. There is no insert, update or delete
policy on any of them. `record_match_result` is the only writer, it runs
`SECURITY DEFINER`, and the absence of a write policy is what states that.

---

## 3. `RR-3` — Migration strategy

### Decision

Migration `0022` was left byte-for-byte as applied. The reversal defect was
fixed in `0023`, and two linter findings against `0022` were fixed in `0024`.
Three migrations, none of them edited after the fact.

### Why `0022` was not corrected in place

`Docs/engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` §2.2 states the rule:
migrations are **append-only**; an applied migration is never edited and never
re-run. To change something a previous migration did, write the next migration.

The temptation to amend was real — `0022` had been applied only to the
development project and was not yet merged. It was refused anyway, and the
reasoning is worth recording because the same argument will come up again:

- **A migration is a fact, not a draft.** `0022` ran. A database somewhere is
  in the state it produced. An edited `0022` would describe a state that
  database never passed through, and the file would no longer explain how the
  live schema came to be.
- **Reproducibility depends on the sequence, not the endpoint.** A fresh
  project replaying `0001`–`0024` must arrive where the live project is. That
  holds only if every file is what actually ran. Editing one breaks the
  equivalence silently — nothing fails, the two databases simply differ.
- **"Only development" is not a category the rule recognises.** Whether an
  applied migration may be edited cannot depend on a judgement about which
  databases matter, because that judgement is made by the person who least
  wants to write another file.
- **The defect is part of the record.** `0023` explains what `0022` got wrong
  and why. That is more useful to a future maintainer than a `0022` that looks
  as though it was right the first time.

### Why the fix was a function replacement

`0023` changes no table, column, constraint, policy or trigger. It is two
`create or replace function` statements. `create or replace` preserves a
function's existing privileges, so the revokes `0022` established were not
disturbed — restated in `0023` only so a reader need not check another file to
know they still hold.

### `0024`, and why it exists separately

The Supabase database linter, run after `0023`, reported two findings against
`0022`:

- `reject_rating_history_update` was the one function `0022` added without
  `set search_path`.
- Neither trigger function had been revoked from `anon` and `authenticated`.
  Migration `0005` set that rule for `handle_new_user` and `0021` restates it:
  no role may reach a trigger function through the API.

Both were the phase's own omissions measured against rules the project already
keeps, so both were closed — in a third migration, for the same reason `0023`
was not folded into `0022`. `0024` changes no behaviour.

---

## 4. `RR-4` — The statistics reversal defect

Found by the integration suite on first execution against a real database, and
fixed in `0023`. This section is the primary reason this document exists.

### Symptom

```
new row for relation "player_statistics" violates check constraint
"player_statistics_goals_check"
Failing row contains (b2760a97…, -1, -1, 0, 0, -3, -1, …)
```

Every correction of a recorded result was refused, and every attempt to delete
a match that had one failed with it.

### Root cause

`0022` treated applying and reversing a result's counters as one statement with
a sign flag:

```sql
insert into player_statistics as ps (user_id, matches_played, wins, …)
select a.user_id, p_sign, p_sign * (…), …
from match_team_assignments a …
on conflict (user_id) do update set
  matches_played = ps.matches_played + excluded.matches_played, …
```

With `p_sign = -1` the proposed row carries negative values — `matches_played
= -1`, `goals = -3`. That row is never meant to be stored: the player already
has a counters row, the conflict resolves, and `DO UPDATE` subtracts the
negatives from the existing totals, leaving a perfectly valid row behind.

**PostgreSQL never gets that far.** For `INSERT … ON CONFLICT DO UPDATE` it
builds the proposed tuple and validates its constraints — `NOT NULL`, `CHECK`,
domain constraints — *before* it performs the speculative insertion that
detects the conflict. The `check (goals >= 0)` therefore fires against a row
that was only ever an intermediate value, and the statement aborts.

The behaviour is easy to reason past because the conflict *is* detected in the
end; the mental model that fails is "the `DO UPDATE` branch is chosen first."
It is not. The proposed row must be independently valid, whichever branch runs.

Two properties of the codebase made this worse rather than better, and both are
correct in themselves:

- The counters carry `check (… >= 0)` constraints, which is right — a negative
  career total is meaningless.
- `disposeCommunity` in the integration harness swallows teardown errors so
  that a cleanup failure cannot mask the assertion failure that matters. That
  is also right, and it is why the failing deletes were silent.

### Blast radius, and how it was found

The same function runs inside the `before delete on matches` trigger, so
`delete_match` and `delete_community` raised too. Teardown failed silently for
the whole run and nothing was cleaned up, so each test compounded the last:
**100 leftover `ITest%` communities**, and the four fixture accounts driven to
`10.00` (clamped), `10.00` (clamped), `2.20` and `0.00` across 100 recorded
matches.

That fallout is what made the diagnosis quick. Ratings pinned at the ceiling
returned a gain of `0.0` for every subsequent assertion, which produced eleven
failures from one defect — and the shape of the failures (every *apply* test
green, every *reverse* test red) pointed straight at the sign flag.

### Why the fix separates the two paths

Applying and reversing are not one operation with a sign. They differ in a way
that matters:

- **Applying** may have to create a counters row — a player finishing their
  first match has none.
- **Reversing** never creates one. There is nothing to subtract from a player
  who was never added.

So applying is an upsert and reversing is an `UPDATE … FROM`. The arithmetic
they share — what a result is worth to each participant — is stated once, in
`match_result_contribution(p_match_id)`, which returns one row per player in
the stored lineup carrying the numbers their counters move by. Neither path
restates a rule the other holds.

```sql
if p_sign < 0 then
  update player_statistics ps set
    matches_played = ps.matches_played - c.played, …
  from match_result_contribution(p_match_id) c
  where ps.user_id = c.user_id;
  return;
end if;
insert into player_statistics as ps (…)
select c.user_id, c.played, … from match_result_contribution(p_match_id) c
on conflict (user_id) do update set …
```

### Why the result is deterministic and reversible

- **One source of arithmetic.** Both directions read the same helper over the
  same stored lineup and the same result row, so the amount subtracted is by
  construction the amount that was added.
- **No intermediate row is ever proposed.** The reversal path issues an
  `UPDATE`, so the counters go from one valid state to another and the CHECK
  constraints are evaluated only against final values — where they belong.
- **A player outside the counters table is skipped, not created at zero and
  decremented.** There is nothing recorded of theirs to take away.
- **Verified by recovery, not only by assertion.** The 100 contaminated
  communities were cleaned up by deleting them through the *fixed* code, which
  fired the reversal trigger 100 times. All four fixture accounts returned to
  exactly `5.00` with every counter at zero — including the two that had been
  clamped at `10.00` and the one at `0.00`. That is the reversal proving
  itself exact through clamping, over a hundred results, on real data.

---

## 5. `RR-5` — Rating history design

### Decision

`rating_history` is append-only. A correction records the reversal of each
previous change as a **new row** that names the row it undoes, via
`reverses_id`. No historical row is ever updated.

### Why immutable

The approved modification rules say it directly — *preserve RatingHistory audit
records*, *never mutate historical audit records* — and the reason survives
restating. An audit exists to answer "what happened", not "what is true now".
A record that is edited when the facts change cannot answer either question: it
no longer describes what happened, and it is a worse source for the present
state than the rating column itself.

After a correction the history reads as a narrative: what the first result
awarded, that each of those awards was taken back, and what the second result
awarded instead.

### How immutability is enforced

Three layers, because each covers a path the others do not:

- **No update or delete policy.** With RLS enabled and no such policy, both are
  refused for every client.
- **A `before update` trigger** raising `RATING_HISTORY_IMMUTABLE`. This covers
  the `SECURITY DEFINER` functions, which run past RLS.
- **`reverses_id` is unique** where not null, so one entry cannot be reversed
  twice — which would subtract a change that was only ever applied once.

Deletion by cascade is deliberately *not* blocked: a deleted match takes its
own audit with it, the way every other row under a match does.

### Why "still in effect" is a query, not a flag

An entry is still in effect when it is not itself a reversal and nothing
reverses it:

```sql
where h.reverses_id is null
  and not exists (select 1 from rating_history x where x.reverses_id = h.id)
```

A `reversed_at` column would have been simpler to read and would have required
writing to a historical row — the exact thing the rules forbid. Deriving it
costs one `NOT EXISTS` and keeps the table honest.

### Why the recorded delta is the *applied* delta

Each row stores `rating_before`, `rating_after`, and a `delta` equal to their
difference — which is the approved constant **except** at the ends of the
`0.0 … 10.0` range, where a player at 10.00 who wins gains nothing.

This is what makes reversal exact under clamping. Reversing by the nominal
constant would hand back 0.10 to a player who never received it. Reversing by
the applied delta returns them to the rating they actually held.

The reversal walks a player's entries **newest first**, ordered by `entry_no`.
That is a guarantee, not a preference: stepping back through states the player
genuinely occupied means every intermediate value is one the range already
accepted, so no clamp can fire on the way out. `entry_no` is an identity column
rather than `created_at` because a whole recording happens in one transaction
and shares a single timestamp.

---

## 6. `RR-6` — Global statistics

> **Aligned to `SL-2` / `SL-3`.** What this section describes is now named
> **Level 1 — Global Statistics** and the **Global Rating**. The decision is
> unchanged and remains correct; the scope around it has widened, and each
> place where that matters is marked below.

### Decision

`player_statistics` holds **one row per player**, across every community they
play in. It is the player's **career** record — Level 1 in the two-level
architecture approved by `SL-2`.

Statistics were not partitioned by community when this phase was built, and
this table still is not. Per-community statistics are now approved as a
**second, additive level** (`SL-2`) with its own rating (`SL-3`); nothing about
them is built, and nothing here changes when they are.

### Rationale

The scope follows the rating's. `users.overall_rating` is a single global
number — it is a property of a player, not of a membership, and the Balanced
Team Generation Engine reads it that way. A per-community statistics table
sitting beside a global rating would offer two answers to "how good is this
player", and the two would disagree the moment somebody played in two
communities.

No approved document asked for per-community figures **when this phase was
built**, and `Docs/01-PRD.md` placed statistics and leaderboards out of MVP
scope entirely, so this phase maintains counters without displaying them;
choosing a partition for a report nobody had specified would have been deciding
a product question in a schema.

> **Aligned.** That premise expired on 2026-08-01: statistics and leaderboards
> are in MVP scope, and per-community figures **are** now specified — by
> `SL-2`, not by this table. The reasoning above is why the *global* table was
> right to stay global, and it still is. A per-community record is a separate
> Level 2 entity; it does not partition this one.

### Current rating is not stored here

`player_statistics` carries the six counters and **not** the rating. The rating
is `users.overall_rating`, which this phase's own functions maintain; a copy
beside the counters would be a second number for the same thing, free to
disagree with it. `PlayerStatistics.currentRating` is populated by joining, the
same way §5.1's out-of-position marker is derived rather than stored.

### Advantages

- One player, one rating, one set of totals — no reconciliation between scopes.
- The write path stays a single upsert keyed on `user_id`.
- A player's history follows them between communities rather than resetting.
- The BTGE inputs and the counters describe the same population.

### Trade-offs, stated plainly

- **A per-community leaderboard cannot be built from this table.** It would
  need either a partitioned table or aggregation over `match_results` joined
  through `matches` to a community. **Answered by `SL-2`:** the approved design
  is a separate Level 2 record keyed by
  `(player, community_id, period_type, period_key)`. This table is not the
  source for any leaderboard, and `SL-2` §2.3 forbids it being one.
- **Communities of different standards are pooled.** A player dominating a
  casual community and one holding their own in a strong one contribute to the
  same totals. **Answered by `SL-3`:** the Community Rating measures a player
  inside one community, and a newcomer starts there at the neutral baseline
  (`SL-4`), so a community board is never distorted by outside form.
- **A player leaving a community keeps the counters it produced.** Correct for
  a career record, arguable for a community-scoped view. **Answered by
  `SL-4`:** the community record is preserved too, and the player becomes
  *ineligible* for that community's boards rather than erased. Rejoining
  restores it.

These counters are read by the **Player Profile** and by nothing else
(`SL-2` §2.3). No leaderboard reads them, in any period.

### Future enhancement — now approved

Per-community statistics were recorded here as a **candidate**. They were
approved on 2026-08-01 as **Level 2** (`SL-2`, `SL-3`, `SL-4`, `SL-5`), and the
open question this section named — *what the global rating means once a
per-community record exists next to it* — is the question `SL-3` answers: the
two ratings are independent, the Global Rating stays the career figure on the
profile, and the Community Rating is the only rating a leaderboard may read.

What was written here still holds for the implementation: nothing in this phase
blocks Level 2. The underlying facts remain in `match_results`, `match_goals`
and `match_team_assignments`, all reachable from a community through `matches`,
so the community level can be built without migrating what is stored.

---

## 7. `RR-7` — Assumptions adopted

The approved brief did not answer these four questions. Each was resolved in
the direction that made the approved rules enforceable, and each is recorded
here because a future maintainer would otherwise read them as arbitrary.

### A1 — A stored lineup is required before a result can be recorded

`record_match_result` raises `LINEUP_REQUIRED` when a match has no rows in
`match_team_assignments`.

The rating engine awards **+0.10 to the winning side** and charges **−0.10 to
the losing side**. That requires knowing which side each player was on, and the
only record of that is the stored lineup — which `KB-017` already defines as
the lineup that *actually played*, including any manual override. A confirmed
registration says a player held a seat; it does not say which team they played
for.

So the lineup is also what "match participants" means for the two participant
rules in the brief. The Teams screen must have been used before the Result
screen; the UI reflects this by showing an explanation instead of a form.

### A2 — Goal scorers must be match participants

`SCORER_NOT_PARTICIPANT`. The brief states this for the MVP and is silent for
scorers.

Enforced anyway, because a goal is worth **+0.05** to whoever is named. Without
the rule, an organizer could credit goals — and therefore rating — to any user
in the system, including one who was never in the match. The same participant
set already had to exist for the MVP rule, so this adds no new concept.

### A3 — Statistics are global

Recorded in full as `RR-6` above. **Aligned:** what this assumption produced is
Level 1. It was an assumption when taken and is now an approved decision —
`SL-2` — with a second level beside it.

### A4 — Result entry appears only for a completed match — presentation only

The match details screen offers the result entry point when
`canManage && match.isCompleted`. The database imposes **no** such rule.

The split is deliberate. The approved brief lists five validation rules and
"the match must have finished" is not among them, so making it a refusal would
have been taking a Product Decision this layer does not hold. Offering an
organizer a form for a match that has not been played is nonsense, so the entry
point is hidden. Hiding a control is a presentation choice the codebase already
makes elsewhere; **refusing** a write is not, and none was added.

Maintainers should read this as a known asymmetry, not an oversight: a client
calling `record_match_result` for a future match will succeed. If that should
be refused, it is a Product Decision and belongs in the RPC.

### Known limitations recorded, not resolved

Neither of the following was in scope, and neither has been approved for work.
They are recorded so that they are found deliberately rather than discovered.

- **Changing a lineup after its result is recorded, then correcting the
  result,** will reverse statistics against the *new* lineup and so subtract
  something other than what was added. Ratings are unaffected — they reverse
  from `rating_history`, which is immune to the lineup changing. Guarding this
  would mean refusing a lineup edit once a result exists, which is a new
  refusal and outside the approved scope.
- **Deleting a user** who was the MVP of a match cascades that match's result
  away without going through `matches`, so the reversal trigger does not fire
  and the other participants keep counters for a result that no longer exists.
  Deleting a *match* is fully handled; deleting a *user* is an administrative,
  already-destructive operation whose existing semantics remove everything they
  hold.

---

## 8. Lessons learned

### The defect and how it surfaced

One production defect (`RR-4`) reached the database and was caught the first
time the code met a real PostgreSQL instance. Nothing before that point could
have caught it — and that is the finding worth keeping.

The failing construct was valid SQL, applied without error, and passed review by
inspection. The migration ran clean. Every unit test stayed green, because unit
tests exercise the Dart layers against fake ports and the defect lived entirely
in a SQL statement's interaction with constraint-evaluation order. No amount of
additional Dart-side testing would have found it.

### Why integration testing exposed it

Because the integration suite executes the real statement against real
constraints on real rows, and because it covered the *reverse* direction as a
first-class scenario rather than only the happy path. The apply path was
correct throughout; every test that recorded a result passed. Only the tests
that corrected one, and the one that deleted a match with a result, failed.

Two properties of the suite made the diagnosis fast:

- **Symmetry in the test set.** "Apply" and "reverse" were tested separately
  and equally, so the failure pattern isolated the fault immediately.
- **Real teardown.** The `before delete on matches` trigger runs during
  teardown, so the defect was hit by every test in the file, not only by the
  ones that targeted it.

The suite also cost something worth naming: because teardown deliberately
swallows its own errors, the contamination went unnoticed until the assertions
failed. That trade-off is still the right one — a teardown error must not mask
a real assertion failure — but it means **a failing integration run should be
followed by a check of fixture state**, not just a fix.

### What improved as a result

- **`match_result_contribution` exists.** Splitting apply and reverse could
  have duplicated the win/loss/draw/goal/MVP expressions. Extracting them
  instead means the two directions cannot drift apart — a stronger property
  than the one-statement version had, since that version was symmetric only by
  appearance.
- **Constraint-evaluation order is now documented** at the point that depends
  on it, in `0023`, so the next `ON CONFLICT` written against a constrained
  table starts from the correct model.
- **The reversal is verified over real data, not only over fixtures.**
  Recovering the 100 contaminated matches through the fixed path demonstrated
  exactness through clamping at both ends of the range — evidence no unit test
  could have produced.
- **Two security gaps closed on the way.** `RR-2`, found while writing the test
  that proves a client cannot award itself a rating; and the `0024` linter
  findings. Both came from validating against a real project rather than from
  reading the migration again.

### The transferable rule

**A migration is not verified until it has run.** Review catches what a reader
can predict; a database catches what it actually does. For any migration
carrying procedural logic — a function, a trigger, a constraint interaction —
applying it to a real project and running the integration suite is part of
writing it, not a step afterwards.

---

## Validation record

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| Unit + widget tests | 369 passed, 0 failed |
| Full suite incl. integration | **522 passed, 0 failed, 0 skipped** |
| New tests added | 76 unit/widget, 37 integration |
| Supabase security advisors | No finding attributable to `0022`–`0024` |
| Development project state | No `ITest` residue; all fixture accounts at baseline |

Migrations `0022`, `0023` and `0024` are applied to the `Go-Play` development
project. `supabase/setup_all.sql` was regenerated through `0024`.

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **Authoritative for statistics and leaderboards** (v2.0). `SL-1` … `SL-5`; what this phase built is Level 1 |
| `Docs/01-PRD.md` | Product scope; statistics and leaderboards are **in** MVP since 2026-08-01 |
| `Docs/07-Database-Design.md` | The schema as built; records the rating-permission question `RR-2` settles |
| `Docs/10-Design-Decisions.md` | The product decision log (`DD`, `PD`) |
| `Docs/11-Future-Backlog.md` | Where the `RR-7` limitations belong if approved for work |
| `Docs/12-Testing.md` | How to run the suites |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §2.2 append-only rule behind `RR-3` |
| `engineering/BTGE_Engineering_Specification.md` | `OP-1` (the rating scale), §4.1, `KB-017` |
| `engineering/ARCHITECTURE_DECISIONS_V1.md` | `OP-2`, `OP-3`, `OP-5` — the layer rules this phase follows |
