# Match Team Assignment (`match_team_assignments`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One High-severity defect and one live known limitation; see §17 and §19 |
| Role | **Engineering Authority** for the physical table `public.match_team_assignments` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Phase 4.3 |
| Scope | **`public.match_team_assignments` only.** `matches`, `match_registrations`, the BTGE algorithm, `match_results`, statistics and ratings appear **only as dependencies** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **This document is the authoritative specification for the physical table
> `public.match_team_assignments`.** Where an implementation and this document
> disagree, **the implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation.**
>
> **It does not redesign approved product behaviour.** The seven decisions
> supplied with the brief are taken as given, and so are `KB-017`,
> `BTGE-MO-1` … `BTGE-MO-6` and `BTGE-HC-1` … `BTGE-HC-7`. §14 reviews the
> architecture around them and recommends no change to any of them.
>
> **Sibling authorities.** `Profiles_Table_Specification.md` v2.0,
> `Communities_Table_Specification.md` v1.0,
> `Community_Members_Table_Specification.md` v1.0,
> `Community_Invitations_Table_Specification.md` v1.0,
> `Matches_Table_Specification.md` v1.0,
> `Match_Registrations_Table_Specification.md` v1.0.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Match Team Assignment** — collectively, **the Lineup** |
| **Physical table** | **`match_team_assignments`** |

One row is *an assignment*; the set of rows for one match is *the lineup*. Both
terms are used below and they are not interchangeable: constraints apply to a
row, invariants apply to a lineup.

**"The lineup" always means the lineup that actually played** (`KB-017`),
including any manual change. It is never the engine's proposal.

---

## 1. Purpose

### 1.1 Business purpose

A Match Team Assignment records that **one player played for one side of one
match, in one position, for one stated reason**.

It exists because three downstream facts cannot be answered without it, and
none of them can be answered by the registration:

1. **Which side won.** The rating engine awards the winning side and charges
   the losing one. A confirmed registration says a person held a seat; it does
   not say which team they were on. Without this table there is no winning
   *side*, only a winning *score*.
2. **Who took part.** A goal is worth rating, so a scorer must be a
   participant. `RR-7 A2` enforces that against **this table**, not against
   registrations — because participation is what happened, not what was
   planned.
3. **Who has recently played with whom.** Diversity is permitted to consult
   Match History and nothing else (`BTGE-AX-1`, `BTGE-AX-4`), and this table is
   the whole of Match History.

### 1.2 Business owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That a lineup exists** | **The community's owner and admins** | Storing a generated lineup |
| **`team`** | **The organiser**, through generation *or* manual override — both are theirs (`BTGE-MO-5`) | The lineup write |
| **`assigned_position`, `assignment_basis`** | **The engine**, in practice | The lineup write |
| `match_id`, `user_id`, `id`, `created_at` | The database | Nothing writes them after insert |

**`BTGE-MO-3` settles the ownership question this table would otherwise
raise.** The engine does not re-optimise, revert or block a manual change; the
organiser's decision stands **even when it worsens every quality metric**. So
the organiser owns the lineup outright, and the engine's output is a proposal
they may keep or change.

### 1.3 Domain ownership

**Domain: Match. Position: inside the Match aggregate, beneath its root.**

| Property | Value |
|---|---|
| Aggregate | **Member of the Match aggregate**, not a root |
| Aggregate root | `matches` |
| Depends on | `matches` **and** `users` |
| Depended on by | **Nothing, by foreign key** — but §12.2 shows the behavioural dependency is the heaviest in the schema |
| Contains authorization | **No** |

It is a second associative entity between a match and a person, sitting beside
`match_registrations`. **The two are deliberately unrelated** — §4.1 is the
whole argument, and it is the most important section in this document.

### 1.4 Lifecycle ownership

| Bounded by | Consequence |
|---|---|
| **The match** | Cascades with it. A deleted match leaves no lineup behind |
| **The person** | Cascades with the account |
| **Not** the registration | **No foreign key, and none may be added** (§4.1) |
| **Not** the community membership | A departed member's assignment stays. A played match's lineup is history |
| **Not the clock** | **Nothing locks a lineup, ever** — §2.4. This is `TA-R2` |

---

## 2. Lifecycle

### 2.1 The states

```
  NO LINEUP                    ← no rows for the match
      │
      │  generate + store  (whole lineup written at once)
      ▼
  STORED
      │
      ├── manual adjustment  ── whole lineup REPLACED, same set of players
      │        (move a player │  ▲
      │         or swap two)  └──┘   repeatable, unlimited
      │
      ├── regenerate  ── whole lineup REPLACED, possibly different assignments
      │
      ├── clear  ──────▶ NO LINEUP    (a lineup of nobody is a valid write)
      │
      ▼
  HISTORICAL RECORD            ← the match ends. Nothing changes on the rows.
                                 They become Match History for Diversity and
                                 the participant set for the result.
```

**There is no `LOCKED` state.** The brief's example lifecycle includes one; the
product does not have one, and §2.4 states what that means.

### 2.2 Every valid transition

| # | From | To | Trigger | Notes |
|---|---|---|---|---|
| 1 | No lineup | Stored | Generation is run and the result stored | The only way a lineup first appears |
| 2 | Stored | Stored | **Manual adjustment** — move one player, or swap two | The **whole lineup is rewritten**, atomically. The set of players is unchanged |
| 3 | Stored | Stored | **Regeneration** | Same write path. The previous lineup is discarded entirely |
| 4 | Stored | No lineup | **Clear** | *"Clearing a lineup is a lineup of nobody, not a no-op"* — an explicit, supported outcome |
| 5 | Any | Historical | The match ends | **Nothing on the rows changes.** The transition is entirely in what the rows now mean |
| 6 | Any | Gone | The match or an account is deleted | Cascade |

**Every write is a full replacement.** There is no operation that inserts,
updates or deletes a single assignment. Migration `0020` made the replacement a
single transaction, because the previous two-statement client path could leave
a match with **no lineup at all**, having destroyed a good one — a window that
sat under every routine manual adjustment.

### 2.3 Generated versus manually modified — the distinction, and why it is not stored

**The table does not record whether a lineup was generated or adjusted, and it
must not.**

This is `KB-017`, stated exactly: manual overrides do not train the engine, and
if the manually adjusted lineup is the lineup that actually played, **that
lineup becomes Match History — because it reflects reality, not learning.**
`BTGE-AX-5` closes it: *"Nothing about the override itself is retained."*

| Question | Answer |
|---|---|
| Can you tell a generated lineup from an adjusted one? | **No, and deliberately.** Both are written by the same operation, in the same shape |
| Does `assignment_basis` record it? | **No.** It records *which positioning rule produced the position* — `PRIMARY`, `SECONDARY` or `TRANSITION`. It is about the position, never about the provenance of the row (§6.2 column 6) |
| Does `updated_at` record it? | **No** (§6.3). Every write is a delete-and-insert, so a manually adjusted lineup has fresh `created_at` values, exactly like a generated one |
| Why not store it? | Because a stored "this was overridden" flag is one query away from being an input. `KB-014` forbids behavioural inference, and `KB-007` forbids feedback loops; the safest way to guarantee the engine never learns from overrides is for the record not to exist |

**What the organiser may change is narrow.** `BTGE-MO-2` permits moving a
player between teams and swapping two players, **without rerunning the
engine**. It does not permit adding a player, dropping one, or changing a
position — and the application implements exactly that: both operations keep
each player's `assigned_position`, and therefore their `assignment_basis`,
untouched.

### 2.4 There is no lock, and the consequence is live

**No state, no column and no guard makes a lineup read-only.** The write
operation checks authentication and community-admin authority, and **nothing
else** — not that the match has started, not that it has ended, not that a
result has been recorded.

**The consequence is `RR-7`'s recorded limitation, and this table is where it
bites:** changing a lineup after its result is recorded, then correcting the
result, reverses statistics against the **new** lineup and so subtracts
something other than what was added. Ratings are unaffected — they reverse from
`rating_history`, which is immune to the lineup changing — but the counters are
not.

**Recorded, not resolved** (`TA-R2`). The limitation is already documented as
known and **not approved for work**; guarding it would mean refusing a lineup
edit once a result exists, which is a new refusal and outside the approved
scope. It is restated here because this specification is where a reader would
look for it.

### 2.5 Invalid transitions, and what refuses each

| Invalid | Why | Refused by |
|---|---|---|
| Two assignments for one player in one match | They would be on two teams at once, counted twice in every downstream figure, and the winning side would be ambiguous | The business key (`TA-C3`) — `BTGE-HC-1`, `BTGE-HC-2` |
| Two goalkeepers on one team | A football rule, and one the engine is required to honour | The partial uniqueness rule (`TA-C6`) — `BTGE-HC-6` |
| A team other than `A` or `B` | The product generates two sides. A third would have no meaning in the result, which has exactly two scores | `TA-C4` |
| A position outside the four | The engine's positioning logic is written against exactly four | `TA-C5` — `BTGE-HC-5` |
| A basis outside the three | It names which rule produced the position; a fourth value names no rule | `TA-C7` |
| **Assigning a player who is not a confirmed registrant** | `BTGE-MO-2` permits moving and swapping, not adding. `BTGE-HC-3` forbids dropping | **Nothing** — `TA-R1`, §7.2 |
| **Omitting a confirmed registrant** | `BTGE-HC-1` requires every player in the generation set to be assigned | **Nothing** — `TA-R1` |
| Partially writing a lineup | A half-replaced lineup is a lineup nobody chose | The write is one transaction |
| Moving an assignment to another match | The assignment records one occasion | Nothing writes `match_id` after insert |

---

## 3. Business Responsibilities

### 3.1 What this table owns

| # | Responsibility | How expressed |
|---|---|---|
| 1 | **Final team membership** | The set of rows for a match. `BTGE-MO-5`: a manually adjusted result **is** the authoritative lineup |
| 2 | **The assigned team** | `team` — `A` or `B` |
| 3 | **The assigned position** | `assigned_position` |
| 4 | **Assignment origin — in the positional sense** | `assignment_basis`: which rule produced the position. **Not** whether the row was generated or adjusted (§2.3) |
| 5 | **Participation identity** | **This table defines who took part.** A result's participants, a goal scorer's eligibility and the MVP's are all resolved here |
| 6 | **Match History** | The complete factual record of who played together, which is the only data Diversity may consult (`BTGE-AX-4`) |
| 7 | **Out-of-position, derived** | `assignment_basis = 'TRANSITION'` **is** out-of-position, by definition. No separate column exists, and none may be added (§6.2 column 6) |

**Assignment ordering: not owned, and not applicable.** There is no order
column. A lineup is a set of two sets; within a team there is no first or last,
and `team` is a label rather than a rank. Nothing reads the rows in a
significant order — the lineup screen sorts by team then user id, which is a
presentation choice with no meaning attached.

### 3.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **Eligibility to play** | `match_registrations` | Registration decides who *may* be assigned; this table records who *was*. §4.1 |
| 2 | **The engine's proposal, or its quality metrics** | Nowhere — computed and discarded | `BTGE-MO-6`: metrics may be recomputed, and are never used to warn against or undo a change. Storing them would create the feedback surface `KB-007` forbids |
| 3 | **Whether the lineup was overridden** | Nowhere, deliberately | §2.3, `BTGE-AX-5` |
| 4 | **The result** | `match_results` | Who played and what the score was are different facts. The result *depends* on this table; it is not part of it |
| 5 | **Goals, the MVP, ratings, statistics** | The results tables | This table names participants; it counts nothing |
| 6 | **Attendance in the sense of "turned up"** | Nowhere | The lineup is the organiser's record of who played. Nothing distinguishes a player who was assigned and absent |
| 7 | **Team size balance** | Nowhere, and correctly so | `BTGE-HC-4` balances team sizes **in generation**. `BTGE-MO-4` lists the constraints that survive override and **omits it** — moving a player necessarily unbalances the sides, and `BTGE-MO-3` says the organiser's decision stands. §7.4 |
| 8 | **Any lock or freeze** | Nowhere | §2.4 |

---

## 4. The Assignment Model

The three questions the brief asks, answered in order. **§4.1 is the reason
this table exists.**

### 4.1 Why assignments are stored separately from registrations

They look like the same relation — a person and a match — and they are not. The
separation rests on four facts, each independently sufficient:

| # | Fact | Consequence |
|---|---|---|
| 1 | **A registration cannot say which side.** It records a claim on a place, not a team | The rating engine awards a *side*. Without a separate record there is nothing to award |
| 2 | **The two sets are permitted to differ.** `KB-017` makes the stored lineup the record of **reality**, including any manual change | A single table would force the roster and the lineup to be the same set, which contradicts `BTGE-MO-5` |
| 3 | **They have different lifetimes and different mutability.** A registration is created and deleted by players, one row at a time, under a queue. A lineup is written whole by an organiser and replaced whole | Merging them would put two write models on one table, and the player's model would be able to touch the organiser's columns |
| 4 | **They answer questions at different times.** A registration is a *plan*, correct before the match. A lineup is a *record*, correct afterwards | Overwriting the plan with the record would destroy the queue that decided who was eligible in the first place |

**The concrete failure a merged design would produce:** a confirmed registrant
who did not play would either have to be deleted — destroying the roster and
the queue position that justified their place — or carry a null team, which
makes "was this person in the lineup" a test for null rather than a test for
existence. Both are worse than a second table.

**So: no foreign key from an assignment to a registration**, and none may be
added. An assignment references the match and the person independently, exactly
as a registration does.

### 4.2 Why assignments are the authoritative source for Results

**Because a result is about what happened, and only this table records it.**

`RR-7 A1` states it as an engineering assumption that became a rule: a stored
lineup is **required** before a result can be recorded, and the operation
refuses with `LINEUP_REQUIRED` when there is none. The reason is arithmetic —
the engine awards the winning side and charges the losing one, which requires
knowing which side each player was on, and *"a confirmed registration says a
player held a seat; it does not say which team they played for."*

Three consequences, all live:

- **Participants are defined here.** `RR-7 A2` enforces that a goal scorer is a
  participant, checked against this table. Without it, an organiser could credit
  goals — and therefore rating — to anyone in the system.
- **The MVP is checked here** for the same reason.
- **Every counter is computed here.** The contribution helper — the single
  source of the arithmetic for both applying and reversing a result — reads one
  row per player **from this table**.

**`BTGE-MO-5` is what makes it authoritative rather than merely available:** a
manually adjusted result *is* the authoritative lineup, so the record and the
adjustment are the same thing and there is no second candidate.

### 4.3 Why BTGE is a producer rather than an owner

**The engine writes nothing.** It is a pure function: given the confirmed
players and the match date, it returns a proposed split. Storing that proposal
is a separate act performed by the organiser's client, through the same
operation a manual adjustment uses.

Three approved rules make the producer/owner distinction binding:

| Rule | What it forbids |
|---|---|
| `BTGE-MO-3` | The engine may not re-optimise, revert or block a manual change. **The organiser's decision stands, including when it worsens every metric** |
| `BTGE-MO-6` | Quality metrics may be recomputed, and **never** used to warn against, discourage or undo a change |
| `KB-007`, `KB-014`, `BTGE-AX-5` | No feedback loop, no behavioural inference, nothing about the override retained |

**So the engine has no standing to object to the contents of this table**, and
the table stores nothing the engine would need in order to. That is why it holds
no proposal, no score, no metric and no override marker — not because those
were forgotten, but because storing them would give a producer the surface of an
owner.

**One asymmetry worth naming:** `assignment_basis` *is* the engine's output,
and it survives a manual override unchanged — because override never changes a
position (§2.3). If manual position changes are ever approved, the basis of a
manually positioned player becomes an open question (§13.2).

---

## 5. Relationships

### 5.1 Outgoing

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `matches` | `match_id` | many : 1 | **`CASCADE`** | **Identifying.** *"A deleted match leaves no lineup behind"* |
| `users` | `user_id` | many : 1 | **`CASCADE`** | **Identifying.** An assignment of nobody is not a fact |

**No third foreign key**, and in particular none to `match_registrations`
(§4.1) and none to `match_results` (the dependency runs the other way).

### 5.2 Incoming

**None, by foreign key.** Nothing references an assignment row — not the
result, not a goal, not a rating entry. All of them reference the match and the
person independently.

**This is correct and load-bearing:** because every lineup write is a full
replacement, every assignment row is deleted and recreated on each edit, with a
new `id`. **Any foreign key to a row here would break on the next manual
adjustment.**

> **Nothing may reference an assignment row.** Reference the match and the
> person, as everything already does.

### 5.3 Ownership and deletion

| Question | Answer |
|---|---|
| **Who owns the relationship's meaning?** | The **match**. An assignment says *played for this side of this fixture* |
| **Can it be reparented?** | **No.** Neither key column is written after insert; every change is a replacement |
| **Deletion — inbound** | Deleting the match removes the lineup (cascade). Deleting an account removes that person's assignments (cascade) |
| **Deletion — outbound** | Removes nothing, and **triggers nothing** |
| **Partial deletion** | Not an operation. The only delete is the first half of a replacement |

**One deletion consequence must be stated, because it is not obvious.**
Deleting an *account* cascades that person's assignment rows away **without
going through the match**. A recorded result then references a lineup that has
silently lost a player, and its counters were computed from the set that
included them. This is the neighbouring case to `RR-7`'s recorded limitation —
deleting a *match* is fully handled by the reversal trigger; deleting a *user*
is an administrative, already-destructive operation whose semantics remove
everything they hold. Recorded as `TA-R4`.

### 5.4 Lifecycle

| Relationship | Whose lifetime bounds whose |
|---|---|
| `matches` → assignments | **Absolutely.** Cascade |
| `users` → assignments | **Absolutely.** Cascade |
| assignments → `match_results` | **Neither bounds the other structurally**, and that is a gap rather than a design: a result may outlive the lineup it was computed from, because the lineup can be replaced at any time (§2.4) |
| assignments → Match History | The rows *are* Match History. It has no separate lifetime |

---

## 6. Columns

Eight columns.

### 6.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `match_id` | `uuid` | No | none | **Never** |
| 3 | `user_id` | `uuid` | No | none | **Never** |
| 4 | `team` | `text` | No | none | **Replaced, never edited** |
| 5 | `assigned_position` | `text` | No | none | **Replaced, never edited** |
| 6 | `assignment_basis` | `text` | No | none | **Replaced, never edited** |
| 7 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| 8 | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** — and vestigial, §6.3 |

**"Replaced, never edited" is a fourth editability class, and it is specific to
this table.** No operation updates a row: an organiser's change deletes every
row for the match and inserts a new set. The three content columns are
therefore write-once per row, and mutable only in the sense that the row they
sit on is discarded.

### 6.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated, never editable**

*Purpose.* Row identity.

*Business justification.* Nothing references it, and — unlike every other
surrogate in the schema — **nothing can**, because the row it names is
destroyed by the next lineup write (§5.2). It exists as PostgREST's row
identity and for no domain reason.

**Retained, not defended.** The business key is what does the work (§8.2).

---

**2. `match_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Which match was played. Half of the business key.

*Business justification.* It scopes everything: the lineup is per match, the
goalkeeper rule is per match, the result reads by it, and the replacement
operation deletes by it. **It is taken from the operation's argument and never
from the payload**, so a submitted row cannot name a match other than the one
being authorised — a deliberate defence, because the payload is client-supplied
JSON.

---

**3. `user_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Who played. The other half of the business key.

*Business justification.* It is the identity every downstream consumer joins
on — the result's participant checks, the contribution arithmetic, the teammate
history, and the player's own match history.

**This is the column that should be constrained against the match's confirmed
registrations and is not** — `TA-R1`, §7.2.

---

**4. `team` — `text`, NOT NULL, two values, replaced never edited**

*Purpose.* **Which side the player was on.**

*Business justification.* It is the single most consequential column in the
schema for a player's rating: the winner gains, the loser loses, and this
column is what decides which. `match_results` carries exactly two scores —
`team_a_score` and `team_b_score` — so the vocabulary here is what those two
columns are about.

*Two values, `A` and `B`.* The product splits a set into two sides. A third
would have no score to belong to.

*Not a name.* Teams are not entities in the MVP — `teams` was in the v2 model
and is out of scope — so this is a label on an assignment rather than a
reference to something. §13.4 shows what would change if that were ever
revisited.

*Changed by manual override*, and it is the **only** column an override
changes: a move flips it for one player, a swap exchanges it for two, and
neither touches anything else.

---

**5. `assigned_position` — `text`, NOT NULL, four values, replaced never
edited**

*Purpose.* Which position the player played in this match.

*Business justification.* The engine derives position distribution from the
players actually available, so a player's position **in a match** is not
necessarily their declared position. Recording it per match is what makes the
profile's `primary_position` editable without rewriting history: the profile
says what a player *is*, this column says what they *played*.

*The same four values as the profile* (`BTGE-HC-5`), so one vocabulary serves
both.

*Not changed by manual override* — `BTGE-MO-2` permits moving and swapping
only, and both keep the position. §13.2 records what a future position override
would need to settle.

---

**6. `assignment_basis` — `text`, NOT NULL, three values, replaced never
edited**

*Purpose.* **Which rule produced the position** — `PRIMARY` (their declared
main position), `SECONDARY` (their declared second), or `TRANSITION` (neither;
the closest logical position).

*Business justification.* It is how the product knows a player was played out
of position, and §5.1 of the engine specification defines out-of-position as
**exactly** `assignment_basis = 'TRANSITION'`.

***Out-of-position is therefore not stored as its own column, and must never
be.*** A derived value stored beside the value it derives from invites the two
to disagree, and migration `0018` refused it on exactly that ground.

*It is about the position, never about provenance.* A reader looking for
"was this row generated or adjusted" will find nothing here, and §2.3 explains
why that is deliberate.

---

**7. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When **this version of the lineup** was stored.

*Business justification — and a semantic that must not be misread.* Because
every write replaces the whole lineup, **`created_at` is the timestamp of the
most recent lineup write, not of when that player was first assigned.** A
player who has been on team A since generation carries the timestamp of the
last unrelated adjustment somebody else's move caused.

So it answers *when was this lineup stored*, and it answers it identically for
every row of the lineup. It does **not** answer *when was this player
assigned*, and no column does.

---

**8. `updated_at` — `timestamptz`, NOT NULL, default `now()`, trigger only**

*Purpose.* When the row last changed. Maintained by a `BEFORE UPDATE` trigger.

*Business justification, stated honestly.* **Under the current write model this
column can never differ from `created_at`**, because no operation updates a
row — every change is a delete and an insert. It is vestigial.

*Keep it.* Two reasons: the table structurally permits updates and the Standards
in `Docs/07-Database-Design.md` require the pair; and if a future operation ever
edits a single assignment in place (§13.2), the column is already there and
already maintained. **The cost of an unused timestamp is nothing; the cost of
adding one later to a table with history is a column that is null or wrong for
every existing row.**

Recorded as an observation, `TA-R6`, not a defect.

### 6.3 Note: this table has both audit timestamps

Unlike `community_members` and `match_registrations` — both of which this phase
records as missing `updated_at` while carrying a mutable column — **this table
has both, with a trigger.** It satisfies the Standards in full.

---

## 7. Business Constraints

### 7.1 Enforced

| ID | Rule | Why it exists |
|---|---|---|
| `TA-C1` | **`match_id` references `matches(id)`, cascading** | A lineup for a match that does not exist is not a fact. Cascading: a deleted match leaves no lineup behind |
| `TA-C2` | **`user_id` references `users(id)`, cascading** | An assignment of nobody is not a fact |
| `TA-C3` | **One assignment per player per match** — `(match_id, user_id)` unique | **`BTGE-HC-1` and `BTGE-HC-2`.** Two rows would put one player on two teams, count them twice in every downstream figure, and make "which side won" ambiguous for them. It is also what enforces *one team per player* — the two rules are one constraint |
| `TA-C4` | **`team` is `A` or `B`** | The result carries exactly two scores. A third team would have no score to belong to |
| `TA-C5` | **`assigned_position` is one of the four** | `BTGE-HC-5`. The positioning logic is written against exactly these, and a fifth value would be unhandled rather than balanced |
| `TA-C6` | **No team holds more than one goalkeeper** — uniqueness on `(match_id, team)` restricted to goalkeeper rows | **`BTGE-HC-6`**, and it survives manual override by `BTGE-MO-4`. Stated as a conditional uniqueness rule so it *cannot be worked around* — including by an organiser's move |
| `TA-C7` | **`assignment_basis` is one of the three** | Each names a rule in the position-transition chain. A fourth value names no rule, and would silently read as "not `TRANSITION`" — that is, as *in position* — to every consumer of §5.1's definition |
| `TA-C8` | **Every write replaces the whole lineup, in one transaction** | A failure between the delete and the insert would leave a match with **no lineup**, having destroyed a good one. Migration `0020` exists for this, and the window it closed sat under every routine manual adjustment |
| `TA-C9` | **`created_at` and `updated_at` are NOT NULL** | §6 |

### 7.2 Specified here, **not** enforced — the lineup must match the generation set

**This is the significant gap.** Two approved hard constraints govern *which
players* a lineup may contain, and neither is enforced anywhere:

| ID | Rule | Approved by | State |
|---|---|---|---|
| `TA-C10` | **Every player in the lineup is a confirmed registrant of that match** | `BTGE-MO-2` permits *moving* and *swapping*, not adding. `BTGE-HC-3` forbids the set being reduced; nothing permits it being enlarged | **Not enforced** |
| `TA-C11` | **Every confirmed registrant of the match is in the lineup** | `BTGE-HC-1`: every player in the generation set is assigned to exactly one team. `BTGE-MO-4`: no player may be **dropped** or **left unassigned**, under override | **Not enforced** |

**What is unenforced, precisely.** The lineup write accepts a client-supplied
array of user ids and inserts them. There is no foreign key to
`match_registrations` — correctly, §4.1 — and **no procedural check in its
place**. So a community admin may store a lineup containing a player who never
registered, who is not a member of the community, or who does not exist in the
match at all; and may store one that omits a confirmed registrant.

**Why it matters beyond tidiness.** Participation is defined by this table
(§4.2). `RR-7 A2` protects rating from being credited to non-participants by
checking scorers **against this table** — so the protection is exactly as strong
as this table's own integrity, and this table has none on who may be in it. A
fabricated assignment is a fabricated participant, and a fabricated participant
earns a real rating.

**Recorded as `TA-R1`**, High. §19 item 1.

**Note what is *not* claimed:** `TA-C11` cannot be a schema constraint — "every
member of a set elsewhere appears here" is not expressible as a check or a
uniqueness rule. Both belong in the write operation, and §18 `TA-D1` records
the one design question that goes with them.

### 7.3 Enforced by the operation

| ID | Rule | Why |
|---|---|---|
| `TA-C12` | **Only an owner or admin of the match's community may write a lineup** | Assembling teams is match management, which `PD-06`/`PD-07` placed with owner and admin |
| `TA-C13` | **The match is taken from the operation's argument, never from the payload** | The payload is client-supplied JSON. Reading the match from it would let one authorised call write rows into a different match |
| `TA-C14` | **An empty lineup is a valid write** | *"Clearing a lineup is a lineup of nobody, not a no-op."* An organiser who generated in error must be able to undo it |

### 7.4 Deliberately **not** constrained

| Not constrained | Why not |
|---|---|
| **Team size balance** | `BTGE-HC-4` balances sizes **in generation**. `BTGE-MO-4` lists the constraints that survive override and **omits it** — moving one player necessarily unbalances the sides, and `BTGE-MO-3` makes the organiser's decision stand. **Enforcing it would break approved manual override** |
| **A lock once the match starts, or once a result exists** | §2.4. Guarding it is a new refusal, outside approved scope, and recorded as a known limitation rather than designed around |
| **A minimum or maximum lineup size** | The match's `starting_players` already bounds the generation set (`OP-2`, 4 to 30), and a lineup cleared to nobody must remain valid (`TA-C14`) |
| **That positions be distributed sensibly** | Distribution is an optimisation priority, not a hard constraint. `BTGE-MO-3` forbids the schema second-guessing the organiser |
| **Whether a lineup was generated or adjusted** | §2.3. Storing it creates the surface `KB-007` and `KB-014` forbid |
| **Any quality metric** | `BTGE-MO-6`. Metrics may be recomputed and never used to discourage a change; a stored metric is one query from becoming a rule |

### 7.5 The hard constraints, and where each is enforced

The seven approved hard constraints, audited against this table. **Two of the
four that survive manual override are unenforced.**

| ID | Constraint | Survives override? | Enforced by |
|---|---|---|---|
| `BTGE-HC-1` | Every player in the set assigned to exactly one team | **Yes** (`BTGE-MO-4`) | *At most one*: `TA-C3`. ***At least one*: nothing* — `TA-C11` |
| `BTGE-HC-2` | No player appears more than once | **Yes** | `TA-C3` ✔ |
| `BTGE-HC-3` | No player is dropped | **Yes** | **Nothing** — `TA-C11` |
| `BTGE-HC-4` | Team sizes balanced | **No** — omitted from `BTGE-MO-4` | Engine only, correctly (§7.4) |
| `BTGE-HC-5` | Positions from the four | Yes | `TA-C5` ✔ |
| `BTGE-HC-6` | No team with two goalkeepers | **Yes** | `TA-C6` ✔ |
| `BTGE-HC-7` | A valid solution for any valid input | n/a — an engine property | Engine only |

---

## 8. Keys

### 8.1 Primary key

**`id`** — a generated `uuid`, and the least consequential surrogate in the
schema: nothing references it and nothing can (§6.2 column 1).

### 8.2 Business key

**`(match_id, user_id)`.**

It states the central rule — **one assignment per player per match**, which is
simultaneously *one team per player* — and it is how every consumer addresses a
row: the result's participant check, the scorer check, the MVP check and the
contribution arithmetic all join on this pair.

Immutable in both columns, NOT NULL in both, unique by constraint. **It is what
the primary key would be in a design that started from the domain**, and here
the argument is stronger than elsewhere, because the surrogate is not merely
unused but unusable.

### 8.3 Candidate keys

| Candidate | Enforced | Assessment |
|---|---|---|
| `id` | Primary key | Generated, and destroyed by the next lineup write |
| **`(match_id, user_id)`** | Unique | **The business key** |
| `(match_id, team, assigned_position)` | **No** | Not unique — a team has several defenders. It *is* unique when restricted to goalkeepers, which is `TA-C6` — but see §8.4 |

### 8.4 Alternate keys

**One: `(match_id, user_id)`** — the business key is also the only alternate
key.

**`TA-C6` is not a key, and calling it one would be a mistake.** Uniqueness of
`(match_id, team)` restricted to goalkeeper rows identifies a row only among
goalkeepers; it says nothing about the other twenty. It is a **conditional
uniqueness rule expressing a football rule**, not an addressing scheme, and
nothing may use it to name a row.

### 8.5 Foreign keys

**Outgoing — two, both identifying, both cascading:**

| Column | References | On delete |
|---|---|---|
| `match_id` | `matches(id)` | **`CASCADE`** |
| `user_id` | `users(id)` | **`CASCADE`** |

**Incoming — none, and none may be added** (§5.2).

---

## 9. Index Strategy

### 9.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `TA-X1` | **Unique on `(match_id, user_id)`** | (a) **the lineup read** — every row for one match, on the teams screen and before every result operation, served by the leading column; (b) the `LINEUP_REQUIRED` existence check; (c) the scorer and MVP participant checks, which probe by exactly this pair; (d) the contribution arithmetic, which reads one row per player of a match; (e) the teammate-history join, which reaches this table by `match_id`; (f) the delete half of every lineup replacement. **And it enforces `TA-C3`** |
| `TA-X2` | **Unique on `(match_id, team)`, restricted to goalkeeper rows** | Enforcement of `TA-C6`, which is its only purpose. It incidentally answers *who is in goal for this team*, which no screen currently asks |
| `TA-X3` | **`(user_id)`** | §9.2 |

### 9.2 `TA-X3` — the stated justification is unimplemented; a quieter one holds

Migration `0018` justified this index as *"Match History reads by person across
recent matches."* **No such query exists.** The implemented teammate history is
driven from `matches` — filtered by community, bounded by the lookback window,
ordered by start time — and joins this table by `match_id`; the per-person
pairing is computed above the database.

**The index is nonetheless justified, by the cascade.** `user_id` carries
`ON DELETE CASCADE` from `users`, and without an index on the referencing column
every account deletion scans this table sequentially to find the rows to
remove.

**Recommendation: retain**, and correct the justification rather than the index.
Recorded as `TA-R5`.

### 9.3 Considered and not required

| Candidate | Verdict | Reasoning |
|---|---|---|
| `(match_id, team)` unrestricted | **No** | The lineup is read whole and split above the database; no query filters by team |
| `(assignment_basis)` | **No** | Three values, no selectivity, and nothing filters across matches by it |
| `(user_id, match_id)` | **No** | Would serve a per-person history query. **That query does not exist** (§9.2); adding the index for it would be anticipating a screen nobody has specified |
| `(assigned_position)` | **No** | No query filters by position across matches |

### 9.4 The rule for a future designer

> **This table is read by match, and written by match.** An index on anything
> else should follow a query, not precede one — and `TA-X3`'s history is the
> cautionary case.

---

## 10. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 10.1 The matrix

| Actor | Read | Generate (store) | Adjust | Delete | Lock |
|---|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ | — |
| **Non-member** | ✗ **Nothing** | ✗ | ✗ | ✗ | — |
| **Player / Member** | ✓ **The full lineup of any match in their communities** | ✗ | ✗ | ✗ | — |
| **Community Admin** | ✓ Same | ✓ | ✓ | ✓ *(clear)* | — |
| **Community Owner** | ✓ Same | ✓ | ✓ | ✓ *(clear)* | — |
| **System Administrator** | ✗ **No direct path** | ✗ | ✗ | ✓ Transitively | — |

**"Lock" has no actor at all, because there is no lock** (§2.4). The column is
kept in the matrix because the brief asks for it, and the honest entry is that
the capability does not exist.

**Owner and admin are identical**, as they are on `matches`: assembling teams is
match management, and every match capability is `admin` or above.

### 10.2 Read

**Reading a lineup is a member's business** — every member of the match's
community sees the whole lineup, both teams, positions and bases.

**Why members and not only participants:** a lineup is the answer to *who is
playing on Friday*, which is the question the whole community asks. Restricting
it to the assigned players would hide it from the reserves, who most need to see
it.

**Non-members see nothing**, consistent with `matches` and
`match_registrations`.

**System Administrator has no read path**, and none is proposed — consistent
with `match_registrations`, where the administrative listing shows a count and
never names.

### 10.3 Generate, Adjust and Delete are one operation

**There is no separate "generate", "adjust" or "delete" write.** All three are
the same full replacement (§2.2), authorised the same way, and the table cannot
tell them apart (§2.3).

- **Generate** = replace with the engine's proposal.
- **Adjust** = replace with the same players, one or two team values changed.
- **Delete** = replace with nobody (`TA-C14`).

**This is a strength, not a limitation.** One write path means one place to
authorise, one place to validate, and one transaction boundary — and it is
precisely what makes `TA-C10`/`TA-C11` implementable in a single place when they
are closed.

### 10.4 The direct write path that should not exist

**Three write rules — insert, update and delete — permit a community admin to
write this table directly, row by row, bypassing the replacement operation
entirely.**

They date from migration `0018`, when the client did write directly. Migration
`0020` replaced that with the atomic operation **and explicitly changed no
policy**, so the unsafe path it was written to eliminate is still open.

**The application no longer uses it**, and every internal writer is
`SECURITY DEFINER` and runs past row rules anyway. **So the three write rules
have no consumer**, and what they permit is exactly the failure `0020` names:
a delete and an insert as two transactions, leaving a match with no lineup at
all after being told nothing was wrong.

**Recommendation: withdraw all three.** This is the same finding and the same
fix as `MT-R1` on `matches`, and the argument is stronger here because the
migration that introduced the safe path documented the danger of the unsafe one
in its own header. Recorded as `TA-R3`, §19 item 2.

---

## 11. Audit

| Column | Required? | State | Verdict |
|---|---|---|---|
| `created_at` | **Required** | Present | §11.1 |
| `updated_at` | **Required** | Present | §6.2 column 8 — vestigial, keep |
| `created_by` | **Required — and absent** | Absent | §11.2 |
| `updated_by` | **Not required** | Absent | §11.3 |

### 11.1 `created_at` — required, present, and easily misread

It is the timestamp of **the lineup write**, not of the player's assignment
(§6.2 column 7). Every row of one lineup carries the same value, and an
unrelated adjustment refreshes all of them.

### 11.2 `created_by` — required, and this is the first table in the phase where it is genuinely missing

Refused on `users` (it would equal the primary key), not required on
`community_members` or `match_registrations` (both self-service, so it would
equal `user_id`).

**Here it is neither, and the information is not derivable from anything.** A
lineup is written by *one of several people entitled to write it* — any owner or
admin of the community — and **who stored this lineup** is not recorded
anywhere. Not on the row, not on the match, not in a notification: unlike a
match edit, storing a lineup notifies nobody.

**Why it matters more here than the pattern suggests.** This table defines
participation, and participation earns rating. `TA-R1` shows an admin can
currently write a lineup containing anyone; **and if they do, nothing records
which admin did it.** The two gaps compound: an unconstrained write with no
attribution.

*Specification:* `uuid`, nullable, referencing the person who performed the
write, cleared rather than blocking on account deletion — the attribution
pattern `match_results.recorded_by` already establishes.

Recorded as `TA-R7` and §19 item 3.

### 11.3 `updated_by` — not required

**No operation updates a row** (§6.2 column 8), so there is no update to
attribute. If a future operation edits a single assignment in place (§13.2),
the question reopens — and `UP-4` answers it in advance: a mutable last-writer
column is erased by the next write, so the record belongs on an append-only
table or, as here, on the row that is written once.

---

## 12. Dependencies

### 12.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `matches` | Identifying parent, cascading | **Owns the scope, the lifetime, the authorization route and the lock discipline.** Supplies `community_id` for every authorization check |
| `users` | Identifying parent, cascading | Owns the person |
| `match_registrations` | **Not a foreign key — a semantic dependency that is not expressed** | Supplies the generation set. **The dependency is real and unrepresented** — `TA-C10`, `TA-C11`, `TA-R1` |
| `community_members` | **Not a foreign key — an authorization dependency** | Answers who may read a lineup and who may write one |

### 12.2 Tables depending on this table

**None, by foreign key** (§5.2). **By behaviour, the dependency is the heaviest
in the schema**, and it is worth stating precisely because "no foreign key"
badly understates it:

| Consumer | How it depends |
|---|---|
| `match_results` | **Cannot be created without a lineup** (`LINEUP_REQUIRED`). Its MVP must be a participant here |
| `match_goals` | Every scorer must be a participant here (`SCORER_NOT_PARTICIPANT`) |
| `rating_history` | Every entry is produced by the win/loss/goal/MVP arithmetic, computed over this table |
| `player_statistics` | Every counter — matches played, wins, losses, draws, goals, MVP — is applied and reversed over this table |
| Level 2 statistics *(unbuilt)* | Will apply and reverse the same way, over the same rows |
| BTGE Diversity | This table **is** Match History, the only auxiliary data the engine may consult |

**One sentence states the risk this creates:** every figure in the product,
at both statistical levels, is computed from a table that anyone with community
admin rights can rewrite at any time, with no constraint on who may be in it
(`TA-R1`) and no record of who wrote it (`TA-R7`).

---

## 13. Future Compatibility

### 13.1 BTGE evolution — no change required

The engine is a producer (§4.3). Its inputs are profile columns and the
confirmed roster; its output is the three content columns of this table.

**What can change without touching this table:** every weight, every priority,
the whole optimisation strategy, the diversity lookback window, and the
position-transition chain's internals.

**What would touch it:** a **fifth position** or a **fourth assignment basis**,
both of which are vocabulary changes — an additive value in a check, plus the
same value on the profile for position. Both would need a Knowledge Base
decision first, and neither is blocked.

**What must not be added:** any engine metric, score or proposal (§3.2 item 2).

### 13.2 Manual Draft Mode — supported by the row model; two rules to settle

A draft — an organiser assembling teams by hand from scratch, with no
generation — **is already expressible**: it is a lineup written by the same
operation with the organiser's choices instead of the engine's.

**Two questions the row model does not answer, and which are engineering
decisions rather than schema ones:**

1. **What `assignment_basis` does a hand-picked position carry?** The three
   values name rules in the engine's transition chain, and a human choice
   followed no rule. Either a fourth value (`MANUAL`) is added — which is a
   vocabulary change and would make out-of-position, defined as exactly
   `TRANSITION`, silently under-count — or the basis is computed from the
   player's declared positions by the same chain, which keeps §5.1's definition
   intact. **The second is recommended**, and it is `TA-D2`.
2. **Does a draft imply position editing?** `BTGE-MO-2` currently permits
   moving and swapping only. Position editing is a new capability, not a new
   table.

**No structural change is required for either.**

### 13.3 Captain Picks — one nullable column, and one rule not to break

Captains picking alternately is a *process* for arriving at a lineup, and the
lineup it produces is the same eight columns.

**If a captain must be recorded**, it is a nullable `is_captain` or a
`captain_user_id` on the *match*; the former is a property of an assignment and
belongs here. Either way it is **additive**.

**The rule not to break:** a captain is not a role and grants nothing.
Authority in this product comes from `community_members.role` and from nowhere
else (`DD-09`), and a captain column that started gating operations would be a
second authorization source — the thing `PD-15` and `PD-16` exist to prevent.

### 13.4 Tournament Mode — the one future that needs more than a column

A tournament introduces **standing teams that persist across matches**, which
this table cannot express: `team` here is a label on one assignment, scoped to
one match, with no identity of its own.

**What it would need:** a `teams` entity — which was in the v2 model and is out
of MVP scope — and then a nullable reference from an assignment to the standing
team it represents.

**What would *not* change:** everything downstream. The result would still
carry two scores, participation would still be defined by this table, and the
rating arithmetic would still read one row per player. **The `A`/`B` label would
remain**, as the per-match side, with the standing team as an additional fact
about it.

**So Tournament Mode is additive too** — but it is the one case that adds an
entity rather than a column, and §7.4's refusal to constrain team size becomes
relevant, since tournament formats fix squad sizes.

### 13.5 The general rule

> **A new column on `match_team_assignments` must be a property of *this
> player, in this match*, must not be an engine output other than the position
> and its basis, and must not record anything about how the lineup came to be.**
> Anything about the engine's reasoning belongs nowhere; anything about a
> standing team belongs to a `teams` entity.

---

## 14. Engineering Review

**Six findings.**

### 14.1 Ownership violation — the direct write rules

§10.4. Three write rules with no consumer permit exactly the non-atomic path
migration `0020` was written to eliminate. **Withdraw all three.** `TA-R3`.

### 14.2 Ownership violation — the lineup's contents are unconstrained

§7.2. This table defines participation, participation earns rating, and nothing
constrains who may be in a lineup. **The strongest finding in this document.**
`TA-R1`.

**It is an ownership violation in the precise sense:** `match_registrations`
owns eligibility, and this table currently claims the right to contradict it.

### 14.3 Duplicate responsibility — none

**No column here duplicates a fact held elsewhere.** Out-of-position is
deliberately derived rather than stored; the engine's metrics are absent; no
counter and no result field is mirrored. Migration `0018` refused the one
tempting duplication — an `out_of_position` column — on the correct ground.

**This is the cleanest table in the phase on this axis.**

### 14.4 Lifecycle inconsistency — nothing locks a lineup

§2.4. A lineup can be rewritten before registration closes, after the match has
been played, and after its result has been recorded. The third makes `RR-7`'s
recorded limitation live.

**Not a new finding and not approved for work** — restated because this is where
a reader would look for it. `TA-R2`.

### 14.5 Lifecycle inconsistency — deleting a user silently alters a played lineup

§5.3. Cascade removes a person's assignments without going through the match, so
a recorded result's participant set can shrink beneath it. Neighbouring case to
`RR-7`'s recorded user-deletion limitation. `TA-R4`.

### 14.6 Future extensibility — sound, with one trap

The row model absorbs draft mode, captains and engine evolution as columns or
values. **The one trap is `assignment_basis`:** §5.1 defines out-of-position as
*exactly* `TRANSITION`, so any new basis value silently reduces the
out-of-position count. §13.2 records the recommendation — derive the basis from
the declared positions even for hand-picked assignments — as `TA-D2`.

### 14.7 Summary

| Finding | Verdict |
|---|---|
| Ownership — direct write rules | **Withdraw**, `TA-R3` |
| Ownership — unconstrained lineup contents | **Close**, `TA-R1` — **High** |
| Duplicate responsibilities | **None** |
| Lifecycle — no lock | **Known limitation**, `TA-R2`, not approved for work |
| Lifecycle — user deletion alters a played lineup | **Recorded**, `TA-R4` |
| Future extensibility | **Sound**; one trap recorded as `TA-D2` |

**No approved product behaviour is redesigned by any of the above.**

---

## 15. Validation

**Contradictions are named, not resolved silently.**

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | `Docs/01-PRD.md` | **No contradiction** | *Balanced team generation (BTGE)* is in scope and built. The role matrix places match management with admin and owner — §10.1 |
| 2 | `Docs/06-ERD.md` | **No contradiction** | §1 names this *"the lineup that actually played a match (KB-D3)"*. §2's *"a team assignment is unique per `(match_id, user_id)`, and at most one row per `(match_id, team)` may carry `GK`… it cascades with its match"* is `TA-C3`, `TA-C6`, `TA-C1` |
| 3 | **Database Principles** | **No artifact in the repository** | Eighth phase in which this is recorded. Validated against `07-Database-Design.md` §Standards — **which this table satisfies in full** — plus `SUPABASE_OPERATIONAL_GUIDELINES.md` §2 and §4 and `ARCHITECTURE_DECISIONS_V1.md` |
| 4 | `Profiles_Table_Specification.md` v2.0 | **No contradiction** | `user_id` → `users(id)` cascading is its §5.2 Group A. Its §13.4 states that BTGE's Core Player Inputs live on the profile and that *nothing derived is stored* — which is why `assigned_position` here is a per-match fact and not a profile one |
| 5 | `Communities_Table_Specification.md` v1.0 | **No contradiction** | Reached only through the match |
| 6 | `Community_Members_Table_Specification.md` v1.0 | **One consequence surfaced** | Its §16.3 states that role and membership are **not** engine inputs, which this table honours — no role appears here. **Surfaced:** its `CMB-R1` reaches further than recorded there or in the registrations specification. A departed member can be in a lineup, and a lineup is what defines participation, so they can earn rating from a community they left |
| 7 | `Matches_Table_Specification.md` v1.0 | **No contradiction** | Its §14.1 states that *no engine output is stored on the match* and *no flag about whether generation has run* — this table is where the lineup lives, and it stores no such flag either (§2.3). Its `MT-R1` is the same defect class as `TA-R3` |
| 8 | `Match_Registrations_Table_Specification.md` v1.0 | **No contradiction; one rule confirmed from both sides** | Its §4.2 item 1 states that registration does **not** own participation and that this table does. Its §14.2 states that the lineup must stay a separate record and must not reference a registration — §4.1 here confirms it and gives the four reasons |
| 9 | `engineering/BTGE_Engineering_Specification.md` v1.5 | **Two hard constraints unenforced** | §15.1 |
| 10 | `engineering/BTGE_Design_Knowledge_Base.md` v1.6 | **No contradiction** | `KB-017` and `BTGE-AX-5` are why provenance is not stored (§2.3). `KB-007` and `KB-014` are why no metric is stored (§3.2 item 2) |
| 11 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction; one known limitation restated** | `RR-7 A1` and `A2` are §4.2. **`RR-7`'s lineup-edit limitation is live and belongs to this table** — §2.4, `TA-R2`. Its user-deletion limitation has a neighbour here — `TA-R4` |
| 12 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction** | `A4`: statistics arise only from a recorded result, and a result is computed over this table. No statistic is stored here |
| 13 | `Docs/10-Design-Decisions.md` | **No contradiction** | `DD-09`, `PD-06`, `PD-07`, `PD-16` hold |
| 14 | `Docs/07-Database-Design.md` | **No contradiction** | Its description of this table matches in full, including that *"out-of-position is not stored: it is exactly `assignment_basis = 'TRANSITION'`"*. **Standards satisfied in full** |
| 15 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **One checklist item not met** | §15.2 |

### 15.1 Contradiction — two approved hard constraints are unenforced

`BTGE-HC-1` requires every player in the generation set to be assigned to
exactly one team, and `BTGE-HC-3` forbids any player being dropped.
`BTGE-MO-4` keeps both in force **under manual override**.

**Neither is enforced anywhere** — not by the schema, and not by the write
operation (§7.2, §7.5).

The specification's own precedence note states that where it and an
implementation disagree, *the specification wins and the implementation is the
defect*. **Not resolved silently.** Specified as `TA-C10` and `TA-C11`,
recorded as `TA-R1`, listed at §19 item 1.

### 15.2 The checklist item this table does not meet

`SUPABASE_OPERATIONAL_GUIDELINES.md` §4 requires **dual enforcement**: a write
path exposed as an RPC carries the check inside the function **and** an RLS
policy on the table.

**Here the two halves are not a belt and braces but two different paths.** The
operation performs an authorised, atomic, whole-lineup replacement; the three
write rules permit unauthorised-in-shape, non-atomic, row-by-row writes by the
same actors. The weaker path is independently usable, and it is the one
migration `0020` exists to prevent.

**Not resolved silently.** Recorded as `TA-R3`, §19 item 2.

---

## 16. Engineering Rationale

### 16.1 Two tables because a plan and a record are different facts

§4.1. The registration is what was intended; the lineup is what happened. A
single table would have to choose which of the two it was, and every downstream
consumer would then be reading the wrong one half the time.

### 16.2 The record stores reality and nothing about how reality was reached

No proposal, no metric, no override marker. `KB-017` permits the adjusted
lineup into Match History precisely because it reflects reality rather than
learning — and the way to keep that true is for the table to hold nothing the
engine could learn from. §2.3.

### 16.3 Out-of-position is derived, because a stored derivation drifts

§5.1 of the engine specification defines it as exactly one basis value.
Migration `0018` refused a column for it on the ground that storing a derived
value invites the two to disagree, and that refusal is now the reason a fourth
basis value would be a trap (§14.6).

### 16.4 One write path, whole-lineup replacement

Generation, adjustment and clearing are the same operation (§10.3). One path
means one authorisation point, one transaction boundary, and — when `TA-C10`
and `TA-C11` are closed — **one place to validate them**.

### 16.5 Nothing may reference an assignment row

Every write destroys and recreates every row. A foreign key to one would break
on the next adjustment. §5.2.

---

## 17. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `TA-R1` | **A lineup's contents are unconstrained.** An admin may store a lineup containing a player who never registered, is not a community member, or was never in the match — and may omit a confirmed registrant. **Participation is defined here, and participation earns rating**, so a fabricated assignment is a fabricated participant with a real rating. Two approved hard constraints (`BTGE-HC-1`, `BTGE-HC-3`) are unenforced | **High** | **Open**, §19 item 1. Specified as `TA-C10`/`TA-C11`; the check belongs in the write operation, and `TA-D1` records the one design question |
| `TA-R2` | **Nothing locks a lineup.** It can be rewritten before registration closes, after the match, and **after its result is recorded** — which makes `RR-7`'s recorded limitation live: correcting a result then reverses counters against the new lineup | Medium | **Known, and not approved for work.** Restated here because this is the table it belongs to |
| `TA-R3` | **Three direct write rules with no consumer** permit exactly the non-atomic, row-by-row path migration `0020` was written to eliminate | Medium | **Open**, §19 item 2. Same finding and fix as `MT-R1` |
| `TA-R4` | **Deleting an account silently alters a played lineup**, because the cascade removes assignments without going through the match. A recorded result's participant set shrinks beneath it | Low | **Recorded.** Neighbour of `RR-7`'s user-deletion limitation; account deletion is already administrative and destructive |
| `TA-R5` | **`TA-X3`'s stated justification is unimplemented.** The per-person history query it was created for does not exist | Low | **Retain the index** — the cascade justifies it — and correct the justification (§9.2) |
| `TA-R6` | **`updated_at` can never differ from `created_at`** under whole-lineup replacement | Low, and not a defect | **Accepted.** Keep it: Standards require the pair, and a future in-place edit would need it (§6.2 column 8) |
| `TA-R7` | **No `created_by`.** Who stored a lineup is recorded nowhere, and storing one notifies nobody. It compounds `TA-R1` — an unconstrained write with no attribution | Medium | **Open**, §19 item 3 |
| `TA-R8` | **A departed community member can appear in a lineup** and therefore earn rating in a community they left | Low | **Inherited** — root cause is `CMB-R1`. Closing `TA-R1` also closes this, because a non-member is not a confirmed registrant |

---

## 18. Open Decisions

| ID | Question | Recommendation |
|---|---|---|
| `TA-D1` | **Should the lineup be validated against the confirmed roster *as it stands at write time*, or against the roster *as it stood when registration closed*?** | **As it stands at write time.** It is the only set the operation can read without a second stored snapshot, and after the match is locked no registration can change — so before the lock the two are the same set anyway. The alternative requires freezing the roster, which is a new entity |
| `TA-D2` | **If hand-picked positions are ever supported, what `assignment_basis` do they carry?** | **Derive it from the player's declared positions using the same transition chain**, rather than adding a `MANUAL` value. A fourth value would silently reduce the out-of-position count, which §5.1 defines as exactly `TRANSITION` |
| `TA-D3` | **Should a lineup become read-only once a result is recorded?** | **A Product Decision, and it would close `TA-R2`.** Engineering's position: the refusal is narrow and well-defined, but it is a new refusal and `RR-7` recorded it as deliberately out of scope. Recorded rather than recommended |
| `TA-D4` | **Should storing a lineup notify the assigned players?** | **Not for the MVP**, and it is not this table's decision — but it is worth noting that a match edit notifies everyone and a lineup write notifies nobody, which is the larger asymmetry behind `TA-R7` |

---

## 19. Conformance — where the built schema differs from this specification

| # | Deviation | Required by | Severity | Notes for the implementing phase |
|---|---|---|---|---|
| 1 | **The lineup's contents are unvalidated against the confirmed roster** | `TA-C10`, `TA-C11` | **High** | Settle `TA-D1`. Both checks belong in the write operation — `TA-C11` cannot be a schema constraint, and `TA-C10` should not be a foreign key (§4.1). One place, one transaction, both checks. Assert the refusals in the integration suite |
| 2 | **Three direct write rules bypass the atomic replacement** | §10.4, §15.2 | Medium | Withdraw all three. Verify first that no client code writes this table directly — the adapter uses the operation, and every internal writer is `SECURITY DEFINER`. Same fix as `MT-R1` on `matches`, and the two should be closed together |
| 3 | **No `created_by`** | §11.2 | Medium | Add as nullable with `SET NULL` on account deletion, following `match_results.recorded_by` |
| 4 | **`TA-X3`'s stated justification is wrong** | §9.2 | Low | Correct the comment; keep the index |

**Everything else conforms.** The structure, both uniqueness rules, the
goalkeeper rule, all three checks, the cascades, the read rule, both audit
timestamps and the atomic write are exactly as specified.

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched.

---

## 20. Engineering Approval

**Status: Engineering Approved — conditional.**

This document is the authoritative engineering specification for
`public.match_team_assignments`. It is **conditional** on §19 item 1.
**Approving this document approves the design, not the current state of the
table.**

The conditional item deserves one sentence of emphasis: **this table defines
who took part in a match, every rating and every statistic in the product is
computed from it, and nothing currently constrains who may be in it.**

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5` | ✓ |
| Business purpose, business owner, domain ownership, lifecycle ownership | ✓ §1, all four |
| **Complete lifecycle** — six valid transitions, nine invalid ones, **and generated vs manually modified distinguished** (§2.3 — the distinction is deliberately not stored, with the approved reason) | ✓ §2 |
| **Business responsibilities** — owned and not owned | ✓ §3, 7 + 8 |
| **Assignment model** — why separate from registrations, why authoritative for results, why BTGE is a producer | ✓ §4, all three |
| Relationships: incoming, outgoing, ownership, deletion, lifecycle | ✓ §5 |
| Every column — name, purpose, type, nullability, default, editability, justification | ✓ 8 of 8 |
| Every business constraint with its reason, **plus an audit of all seven hard constraints against their enforcement** | ✓ 14 + §7.5 |
| Keys: primary, **business key**, candidate, alternate, foreign — including why the goalkeeper rule is **not** a key | ✓ §8 |
| Index strategy: three indexes, each justified; one justification corrected | ✓ §9 |
| Access control: player, owner, admin, member, non-member, System Administrator × read/generate/adjust/delete/lock | ✓ §10 |
| Audit: all four columns ruled on; `created_by` specified as required and missing | ✓ §11 |
| Dependencies both directions | ✓ §12 |
| Future compatibility: BTGE evolution, Manual Draft Mode, Captain Picks, Tournament Mode | ✓ §13, four of four |
| **Engineering review** — ownership violations, duplicate responsibilities, lifecycle inconsistencies, future extensibility | ✓ §14, six findings |
| Validation; contradictions named, not resolved | ✓ 15 sources, **2 contradictions named** |
| No SQL, no migration, no implementation, no other table designed | ✓ |

### What must happen before the table is implementation-conformant

1. **§19 item 1** — validate the lineup against the confirmed roster. The only
   High, and it also closes `TA-R8`.
2. §19 item 2 — withdraw the three direct write rules, together with the same
   fix on `matches`.
3. §19 item 3 — `created_by`.
4. §19 item 4 — correct the index justification.

### Validation caveat, stated rather than glossed

The brief names *Database Principles* as a validation source. **It does not
exist as a document in this repository** — the eighth phase in which this has
been recorded. Validation used the principles in `07-Database-Design.md`
(**satisfied in full by this table**), `SUPABASE_OPERATIONAL_GUIDELINES.md` and
`ARCHITECTURE_DECISIONS_V1.md`. If it exists outside the repository, this
specification has not been checked against it.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Matches_Table_Specification.md` | **Parent authority.** Its `MT-R1` is this table's `TA-R3`; its §14.1 confirms no lineup flag lives on the match |
| `engineering/Match_Registrations_Table_Specification.md` | **The other half of §4.1.** Its §4.2 item 1 and §14.2 state the same separation from the other side. Its `MR-R1` reaches here as `TA-R8` |
| `engineering/Community_Members_Table_Specification.md` | Supplies authorization; its §16.3 confirms role is not an engine input. Its `CMB-R1` reaches here |
| `engineering/Profiles_Table_Specification.md` | `user_id` → `users(id)`; its §13.4 is why position is stored per match rather than derived from the profile |
| `engineering/BTGE_Engineering_Specification.md` | **§6 hard constraints (two unenforced — §15.1), §13 manual override, §5.1 out-of-position** |
| `engineering/BTGE_Design_Knowledge_Base.md` | **`KB-017`** (reality, not learning), `KB-007`, `KB-014`, `BTGE-AX-5` |
| `engineering/Results_Rating_Engineering_Decisions.md` | **`RR-7 A1` and `A2`** — why a lineup is required before a result; the lineup-edit limitation this table makes live |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | `A4` — statistics arise only from a recorded result, computed over this table |
| `Docs/06-ERD.md` | §1 and §2 — the lineup that actually played, and its two uniqueness rules |
| `Docs/07-Database-Design.md` | The schema as built; **Standards satisfied in full** |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §4 — **the dual-enforcement item this table does not meet** (§15.2) |
