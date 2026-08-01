# User Profile (`users`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | **2.0 — final** |
| Status | **Engineering Approved** |
| Role | **Engineering Authority** for the physical table `public.users` |
| Owner | Product Owner |
| Approved | 2026-08-01 — Profiles final review |
| Phase | Database Design Engineering — Phase 3 (complete) |
| Scope | **`public.users` only.** No other table is designed, altered or implied |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |

> **This document is the authoritative specification for the physical table
> `public.users`.** Where an implementation and this document disagree, **the
> implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation.** It is a design
> record. Everything below is stated so that the implementing migration can be
> written from this document alone, without reopening a design question.
>
> **Precedence above this document.** `Docs/01-PRD.md` and
> `Docs/10-Design-Decisions.md` govern what the product does.
> `engineering/Statistics_Leaderboards_MVP_Specification.md` v2.0 governs
> statistics and leaderboards. `engineering/BTGE_Design_Knowledge_Base.md`
> governs team-generation intent. Where this document disagrees with any of
> them, **this document is the defect**.

---

## 0. Logical entity and physical table

**Approved — `UP-5`.**

| | |
|---|---|
| **Logical entity** | **User Profile** |
| **Physical table** | **`users`** (`public.users`) |

Both names are fixed. The convention is binding on all future engineering
documentation:

- **The logical entity is always called the *User Profile*.** It is the
  application's record of a person as a player.
- **The physical table is always called `users`.** It is never renamed.
- **The name `profiles` is not introduced as a physical table name**, in this
  document or in any other. It is not an alias, not a view name and not a
  planned rename.

**Why the physical name stays `users`.** A rename touches **twelve foreign
keys across eleven tables**, two access policies, one column-level privilege,
six functions that name the table (`handle_new_user`, `register_for_match`,
`apply_rating_delta`, `admin_list_users`, `admin_list_communities`,
`admin_delete_user`), one trigger, one index, the Supabase adapter layer and
the integration suite — for **zero product value**. `CLAUDE.md` §1 and §4
forbid exactly this kind of unrequested change.

**`public.users` is not the authentication record.** That is `auth.users`,
owned by Supabase Auth. The two are distinct tables sharing one primary key,
and the collision of names is historical. Migration `0001_users.sql` already
describes its own table as *"the `public.users` profile table"* — the entity
this document specifies.

Throughout: **User Profile** names the entity, **`users`** names the table.

---

## Approved decisions register

Five decisions were approved by the Product Owner in the Profiles final review
and are incorporated below. They are recorded as `UP-n` (**U**ser **P**rofile)
rather than `PD-n` because `PD-01` … `PD-18` is an **existing** product-decision
series in the Architecture Migration Specification v1.2, referenced throughout
`06-ERD.md`, `07-Database-Design.md`, `08-UI-UX-Specification.md` and
`10-Design-Decisions.md`. Reusing those numbers would make `PD-2` ambiguous
across the project. See *Remaining issues* (§19) — the Product Owner may
overrule the relabelling with one word.

| ID | Approved as | Decision | Sections |
|---|---|---|---|
| `UP-1` | `PD-1` | **Profile visibility.** Authenticated users have **no** unrestricted read access to all profiles. Self always readable; public visibility is a Product Rule; community visibility follows membership; least privilege; **enumeration is not permitted** | §10.1, §14, §16, §17 |
| `UP-2` | `PD-2` | **The database never invents a primary position.** The `'MID'` substitution is removed. A required value that is absent makes the operation fail | §4.1, §6.2, §8.3, §17 |
| `UP-3` | `PD-3` | **Three business rules belong in the database**, in addition to client-side validation: secondary ≠ primary position, no future birth date, no empty required text | §8.2, §17 |
| `UP-4` | `PD-4` | **No `updated_by` on `users`.** Administrative actions are recorded in immutable history, never in a mutable column | §11 |
| `UP-5` | `PD-5` | **Logical vs physical naming.** Logical entity *User Profile*; physical table `users`; the name `profiles` is not introduced | §0, throughout |

---

## 1. Purpose

The **User Profile** is the application's record of a **person as a player**:
who they are, how to reach them, how they play, and how strong they are.

It exists for four reasons, each of which independently requires it:

1. **`auth.users` is unreachable from the client.** Supabase Auth owns that
   table and exposes no row of it to PostgREST. A member list that shows a name
   needs a name in a table the access layer can serve.
2. **`auth.users` carries no football attributes.** Position, date of birth and
   rating are domain data, not authentication data, and adding them to a table
   owned by another system would put the domain inside a vendor's schema.
3. **Every table that names a person needs a foreign key target inside
   `public`.** Eleven tables have one, carrying twelve foreign keys between
   them (§12). A `public` schema whose people lived in `auth` would have every
   join crossing a boundary the access layer cannot reason about.
4. **The Balanced Team Generation Engine needs the Core Player Inputs on the
   person.** BTGE §4.1 lists rating, date of birth, primary and secondary
   position as attributes of a *player*, not of a membership. A player who
   belongs to three communities has one rating, not three (`RR-6`).

**What the User Profile is deliberately not:**

- **It is not an authorization record.** No role, no permission and no
  capability is stored here. Community authority lives on
  `community_members.role` and is read only through `has_community_role`
  (`DD-09`, `PD-15`, `PD-16`). The internal support role lives in
  `system_admins`. A profile grants nothing, anywhere.
- **It is not a statistics record.** Career counters live in
  `player_statistics`; a copy here would be a second answer to the same
  question, free to disagree with the first (`RR-6`).
- **It is not community-scoped.** It carries no `community_id`, ever. That is
  what allows one person to belong to many communities, and it is the
  structural reason Level 2 statistics must be a separate entity (§13.1).
- **It is not a directory.** Under `UP-1` the table is not a browsable list of
  the application's users, and no client may enumerate it (§10.1).

---

## 2. Business Owner

**Product Owner**, as for every table in the project.

Ownership of the *contents* is split by field group, and the split is enforced
by privilege rather than by convention:

| Field group | Owner | Enforced by |
|---|---|---|
| `full_name`, `phone` | The player | Row-level access rule + column privilege |
| `primary_position`, `secondary_position`, `date_of_birth` | The player | Row-level access rule + column privilege |
| `overall_rating` | **The system** — the rating engine is its sole author (`RR-2`, `OP-1`) | Column privilege withheld from every client role |
| `is_active` | **Administration** — account state is not a player's to set | Column privilege withheld |
| `id`, `created_at`, `updated_at` | **The database** | No client may write them (§6) |

**Visibility** is owned separately from writability, and by the Product Owner
alone: `UP-1` places *who may read whose profile* under Product Rules, not
under engineering discretion (§10.1).

The one open question about write ownership — *may an administrator adjust a
rating by hand?* — is recorded in `RR-2` as deliberately unsettled and is **not
settled here**. `UP-4` (§11.2) decides in advance where the audit for it would
live if it is ever approved.

---

## 3. Domain Ownership

**Domain: Player Identity.**

The User Profile is the **root reference entity** of the data model. Its
position is structural, not a matter of taste:

| Property | Value |
|---|---|
| Aggregate | **None.** The User Profile sits *outside* the Community aggregate |
| Depends on | `auth.users` only |
| Depended on by | Every domain in the application (§12) |
| Community-scoped | **No**, and must never become so |
| Contains authorization | **No** |

The project's aggregate root is the **Community** — everything below a
community belongs to exactly one community, and nothing is owned by a user
(`06-ERD.md` §1). The User Profile is the deliberate exception, and the
exception is what makes the model work: a person exists before any community,
belongs to several at once, and outlives their membership of any of them.

Stated as the rule a future designer must not break:

> **A User Profile belongs to no community. A community-scoped fact about a
> player belongs on a community-scoped table, never on the profile.**

This is the same rule `SL-4` states from the other direction, and it is why the
Community Rating cannot be a second column here (§13.1).

**`UP-1` does not change this.** Visibility is scoped by community; the
*record* is not. A profile that became community-scoped to satisfy a visibility
rule would break multi-community membership entirely — the rule is applied at
read time, over `community_members`, and never by partitioning this table.

---

## 4. Lifecycle

### 4.1 Creation — one path, no client insert

A profile row is created **only** as a consequence of an account being created
in `auth.users`, by an `AFTER INSERT` trigger on that table
(`handle_new_user`, `SECURITY DEFINER`).

- There is **no insert access for any client**, and there must never be one. A
  client that could insert a profile could insert one for somebody else's id,
  or for an id with no account behind it.
- The trigger function is revoked from `anon`, `authenticated` and `public`, so
  no role can reach it through the API (migration `0005`, restated in `0021`).
- The profile is created **in the same transaction as the account**. There is
  no window in which an account exists without a profile, and no repair path is
  needed for one.

**Field origin at creation** — as required by `UP-2`:

| Field | Source | If absent |
|---|---|---|
| `id` | The `auth.users` id being inserted | Cannot be absent |
| `full_name` | Signup metadata — **required** | **The operation fails.** No empty string is substituted |
| `phone` | Signup metadata — **required** | **The operation fails.** No empty string is substituted |
| `primary_position` | Signup metadata — **required** | **The operation fails.** No value is invented — `UP-2` |
| `date_of_birth` | Signup metadata — optional | Stored as null. Absent and empty both mean *not supplied* |
| `secondary_position` | Signup metadata — optional | Stored as null |
| `overall_rating` | The column default | **Never** from metadata — a system-managed value must not be authored by whoever composes the signup request |
| `is_active`, `created_at`, `updated_at` | Column defaults | — |

### 4.2 Update

- **By the player**, on their own row, restricted to five columns (§10.3).
- **By the rating engine**, on `overall_rating` only, through a
  `SECURITY DEFINER` function that runs past both the row rule and the column
  privilege.

`updated_at` is refreshed by a `BEFORE UPDATE` trigger on every update from
either path.

### 4.3 Deactivation — designed, dormant

`is_active` is the soft-deletion flag. It participates in the read rule: an
inactive profile is not visible to any client, in any scope.

**No code writes it.** No RPC, no policy and no trigger sets it to false, and
no client holds the privilege to. It has been true for every row since
migration `0001`.

This is recorded as a **known dormancy, not a defect** (`PR-R4`). The column is
correct, the semantics are decided, and the operation that would use it has
never been requested. §17.2 states what completing it would require.

### 4.4 Deletion — hard, administrative, and only through one door

There is **no delete access for any client**. Deletion happens two ways:

1. **`admin_delete_user`** (System Admin only, `SECURITY DEFINER`). It removes
   everything that would outlive the account — communities the person owns,
   memberships elsewhere, matches they created in other people's communities,
   their notifications and registrations — then the profile, then the
   `auth.users` row. It refuses to delete the caller and refuses to delete
   another System Admin.
2. **Cascade from `auth.users`.** The primary key carries
   `ON DELETE CASCADE` against the auth row, so an account removed by any other
   means (the Supabase dashboard, the Auth admin API) takes the profile with
   it.

Path 2 is a **safety net, not an approved operation**. It bypasses the ordered
cleanup path 1 performs, and `RR-7` already records the consequence: deleting a
user who was the MVP of a match cascades that result away without going through
`matches`, so the reversal trigger never fires and other participants keep
counters for a result that no longer exists. Recorded as `PR-R2`.

### 4.5 Immutability

`id` is immutable for the life of the row. It is the auth user id, it is the
target of twelve foreign keys, and there is no operation that changes it. No
constraint states this because no path exists that could violate it: the column
is not in the client's column privilege, and no function updates it.

---

## 5. Relationships

### 5.1 Outgoing — what the User Profile depends on

| Target | Cardinality | Type | On delete | Why |
|---|---|---|---|---|
| `auth.users` | 1 : 1 | **Identifying** — the FK *is* the primary key | `CASCADE` | The profile is the domain half of one identity. It has no meaning without the account, and must not survive it |

**`users` has exactly one outgoing foreign key, and must never acquire a
second.** A profile that referenced a community, a team or a match would place
a person inside an aggregate they belong beside, not within.

### 5.2 Incoming — what depends on the User Profile

Twelve foreign keys across eleven tables, in three groups:

**Group A — membership and participation** (cascade: the person's own rows)

| Table | Column | On delete | Meaning |
|---|---|---|---|
| `community_members` | `user_id` | `CASCADE` | The membership edge |
| `match_registrations` | `user_id` | `CASCADE` | A place taken in a match |
| `match_team_assignments` | `user_id` | `CASCADE` | The lineup that actually played |
| `notifications` | `user_id` | `CASCADE` | Notices addressed to the person |
| `system_admins` | `user_id` (PK) | `CASCADE` | The internal support role |

**Group B — results and career record** (cascade: facts about the person)

| Table | Column | On delete | Meaning |
|---|---|---|---|
| `player_statistics` | `user_id` (PK) | `CASCADE` | The six career counters, 1 : 0..1 |
| `rating_history` | `user_id` | `CASCADE` | Every Global Rating change, immutable |
| `match_results` | `mvp_user_id` | `CASCADE` | The match's MVP |
| `match_goals` | `user_id` | `CASCADE` | A scorer and how many they scored |

**Group C — attribution and mirrors** (restrict / clear: not the person's rows)

| Table | Column | On delete | Meaning |
|---|---|---|---|
| `communities` | `owner_id` | **no action** | A derived mirror of the owning membership. Never read to grant anything (`PD-15`) |
| `matches` | `created_by` | **no action** | Audit attribution only (`PD-16`) |
| `match_results` | `recorded_by` | `SET NULL` | Attribution. Nullable so that recording a result can never be the reason a user cannot be deleted |

Group C is why `admin_delete_user` exists at all: two of these references
**block** a raw delete, so the ordered path has to dispose of the communities
and matches first. That is a deliberate design property — an account cannot be
deleted while it silently orphans a community that would then have nobody able
to manage it.

**`community_members` is also the visibility edge.** Under `UP-1` it carries a
second role: besides granting authority inside a community, it is what makes
one person's profile visible to another (§10.1). It remains the *only* place
either question is answered.

### 5.3 Relationship cardinality summary

```
auth.users (1) --o (1) users  [User Profile]
                        |
   +--------------------+---------------------+
   |            |            |                |
   +--< community_members    +--o player_statistics
   +--< match_registrations  +--< rating_history
   +--< match_team_assignments
   +--< notifications        +--o system_admins
   +--< match_goals
   +--o match_results (as MVP)
   +--? communities.owner_id, matches.created_by  (attribution, no cascade)
```

---

## 6. Columns

Ten columns. **No column is added by this specification and none is removed.**
The table as built already expresses the entity correctly; what this phase adds
is the *specification* — the reasons, the constraints and the access rules —
not new structure.

### 6.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | none | **Never** |
| 2 | `full_name` | `text` | No | none | Player |
| 3 | `phone` | `text` | No | none | Player |
| 4 | `primary_position` | `text` | No | **none — `UP-2`** | Player |
| 5 | `secondary_position` | `text` | **Yes** | `null` | Player |
| 6 | `date_of_birth` | `date` | **Yes** | `null` | Player |
| 7 | `overall_rating` | `numeric(4,2)` | No | `5.00` | **System only** |
| 8 | `is_active` | `boolean` | No | `true` | **Administration only** |
| 9 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| 10 | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** |

*Editable by* has exactly three values and each is a different enforcement
mechanism:

- **Player** — in the column privilege held by `authenticated`, on their own
  row.
- **System / Administration only** — not in the column privilege; reachable
  only by a `SECURITY DEFINER` function, which runs as the owner.
- **Never / Trigger only** — no path writes it after insert except the database
  itself.

### 6.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* The identity of the person, everywhere in the application.

*Business justification.* It is the `auth.users` id, not a value this table
generates. Reusing the auth id rather than minting a new key means the signed-in
caller's identity (`auth.uid()`) **is** the profile key, so every access rule in
the project can express "this person's own row" as a column comparison rather
than a subquery. A separate surrogate key would put a join between the
authenticated session and every authorization decision in the system. It is
also what makes the *self* tier of `UP-1` free of any lookup.

*No default.* A default would be a generated id with no account behind it. The
value must come from the auth row being inserted.

---

**2. `full_name` — `text`, NOT NULL, no default, editable by the player**

*Purpose.* The name shown wherever a person appears: member lists, match
rosters, lineups, goal scorers, the MVP, the admin console.

*Business justification.* An amateur football community is a group of people
who know each other; a roster of user ids is unusable. This is the **only**
human-readable identifier the application displays, because the email address
lives in `auth.users` and is never exposed to other members.

*NOT NULL, and non-empty by `UP-3`.* There is no state in which a person
appears on a roster without a name. A nullable — or empty — name would push a
fallback (`"Unknown player"`) into every screen that renders one.

*Editable.* People change their name, correct a typo, or prefer a different
form of it. There is no business reason to freeze it and no downstream record
that depends on its stability — every reference is by `id`.

---

**3. `phone` — `text`, NOT NULL, no default, editable by the player**

*Purpose.* Contact detail, so an organizer can reach a player about a match.

*Business justification.* `DD-02` moved **identity** to email + password and
demoted phone to a contact field. That demotion is the whole justification for
its shape: it is required because an organizer needs to reach a participant, it
is **not unique** because it is not an identity, and it is not validated for
format because the product serves one region informally and a format rule would
reject legitimate values (`PR-R3`).

*NOT NULL, and non-empty by `UP-3`.* Reaching a player is a core organizer
task. A null — or an empty string — converts "call the player" into "the app
cannot help you".

*Exposure.* Under `UP-1` this column is readable only by people who can already
see the row at all: the player themselves, and members of a community they
share. Beyond that scope no row is readable, so the question of the column does
not arise. Restricting it *further*, within a shared community, would defeat
the column's only purpose and is not proposed.

---

**4. `primary_position` — `text`, NOT NULL, no default, editable by the player**

*Purpose.* The player's declared main position, and a Core Player Input of the
team generation engine.

*Business justification.* BTGE §4.1 requires it for every player in a
generation set, and §4.3 forbids the engine inventing one. The vocabulary is
fixed at four values (§8.1) because the engine's position logic —
distribution, the goalkeeper rules, the `TRANSITION` basis — is written against
exactly those four (`BTGE-HC-5`).

***NOT NULL and no default — `UP-2`.*** The database must never invent a
player's primary position. A default is that invention moved one layer down and
stripped of its evidence: the engine cannot tell a declared `MID` from a
manufactured one, and it will balance a team around it. Where the value is
required and absent, **the operation fails** (§8.3).

*Editable.* A player's main position changes over seasons. Nothing historical
depends on the current value: `match_team_assignments` records the position each
player *actually played*, per match, at the time (`KB-017`), so editing the
profile never rewrites history.

---

**5. `secondary_position` — `text`, NULLABLE, default `null`, editable by the
player**

*Purpose.* A second position the player can cover, used by the engine to fill a
gap without charging the player an out-of-position penalty.

*Business justification.* BTGE §4.1 marks it **not required** and `BTGE-SC-6`
names the absence of one as *ordinary input, never an error*. Many amateur
players genuinely have one position.

*Nullable — and this nullability is load-bearing.* "No secondary position" and
"a secondary position we failed to record" must be the same state, because the
engine treats them the same way: it assigns from the primary, or marks the
assignment `TRANSITION`. Making it NOT NULL with a sentinel (`'NONE'`) would put
a fifth value into a four-value vocabulary that the engine's position logic
would then have to exclude everywhere.

*Same vocabulary as the primary*, so that the engine reads both through one
rule — and **must differ from it** when present (`UP-3`, §8.2).

---

**6. `date_of_birth` — `date`, NULLABLE, default `null`, editable by the
player**

*Purpose.* The input from which the engine derives age, as of the match date,
for age balance between the two teams.

*Business justification.* BTGE §4.1 requires it and §2 lists age balance in
scope. It is stored as a **date and never as an age**: age is a function of two
dates and is wrong the moment it is stored — a player balanced by a stale age is
balanced by a value that was true last year.

*A `date`, not a `timestamptz`.* A birthday has no time of day, and carrying one
would let the same birthday fall on two different days depending on the reader's
time zone.

*Nullable, deliberately, and permanently.* Accounts created before migration
`0021` were never asked for it. Inventing a date for them is exactly what BTGE
§4.3 forbids — the same principle `UP-2` states for the primary position — and
there is no honest value to backfill. The database records what it knows; the
*engine* rejects a player whose date is missing, and the *application* asks that
player to complete their profile. **This column must not be made NOT NULL, now
or later** — see `PR-R5`.

*The asymmetry is intentional and worth stating plainly:* required by the
engine, optional in the schema. The schema's job is to avoid recording a
falsehood; the engine's job is to refuse an incomplete request. They are
different jobs and they belong in different layers.

*When present, it must not be in the future* (`UP-3`, §8.2).

---

**7. `overall_rating` — `numeric(4,2)`, NOT NULL, default `5.00`, system only**

*Purpose.* The player's strength on the approved `0.0 … 10.0` scale. Under
`SL-3` this column **is the Global Rating** — Level 1, the career rating shown
on the Player Profile.

*Business justification.* Two consumers depend on it: BTGE reads it as a Core
Player Input and balances the two sides from it, and the Player Profile displays
it as the player's career figure.

*`numeric(4,2)` — precision is a correctness requirement, not a preference*
(`RR-1`). The approved engine moves a rating by **0.05** for a goal, which one
decimal place cannot represent at all. Every available rounding gives a wrong
answer, and worse, rounding is not invertible — the approved modification rules
require a corrected result to reverse every change it made, and a rounded
reversal leaves the player holding a tenth they never earned, compounding with
every correction. Every approved delta (0.05, 0.10, 0.20) is a multiple of 0.05,
so two decimals are exactly sufficient and nothing wider was taken.

*One decimal remains a presentation choice.* **Round for the eye, never for the
record.** A rounded value must never be written back.

*NOT NULL with default `5.00`.* This is the one default the design keeps, and it
does not contradict `UP-2`: a neutral starting rating is a **declared product
constant**, not a guess at an unknown fact. There is no true-but-unrecorded
rating for a new player the way there is a true-but-unrecorded position — the
career begins at the midpoint, by rule, and `SL-4` reuses the same value as the
Community Rating baseline. A new player is neither advantaged nor penalised.

*System only, and this is integrity rather than hardening* (`RR-2`). Without the
column privilege, a signed-in player could `PATCH` their own rating to `10.0`
and be believed — by the team generator, which would then balance sides from a
self-selected number, and by every figure derived from it. **An engine whose
input any client may write is decoration.**

---

**8. `is_active` — `boolean`, NOT NULL, default `true`, administration only**

*Purpose.* Whether the person participates in the application. It participates
in the read rule, so an inactive profile is not visible to any client in any
scope.

*Business justification.* Deletion is destructive and, for a person, mostly
wrong: their registrations, lineups, results, goals and rating history are facts
about matches that other people played in, and removing the person falsifies
those matches. A flag that hides them without unmaking them is the correct
primitive for suspension, and it is why `07-Database-Design.md` records deletion
as soft from migration `0001`.

*Withheld from the player's column privilege.* Deactivating an account is an
administrative act. A player who could set it would remove themselves from every
roster, silently, from a phone — and could set it back.

*Dormant.* See §4.3 and `PR-R4`.

---

**9. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When the account came into being. Required audit (§11).

*Business justification.* It is the only ordering the admin console has —
`admin_list_users` returns `order by created_at desc` — and the only answer to
"how long has this person been here", which is a routine support question.

---

**10. `updated_at` — `timestamptz`, NOT NULL, default `now()`, trigger only**

*Purpose.* When the row last changed. Required audit (§11).

*Business justification.* Maintained by a `BEFORE UPDATE` trigger rather than by
the writer, because a value the writer supplies is a value the writer can get
wrong or omit — and there are two writers here (the player and the rating
engine), only one of which is application code the project controls.

---

## 7. Keys

### 7.1 Primary key

**`id`.** A single-column `uuid` primary key that is simultaneously the foreign
key to `auth.users(id)`.

This is a **shared primary key**, and choosing it over a surrogate key with a
separate unique `auth_user_id` was the fundamental modelling decision of this
table:

- It makes "the caller's own row" a column comparison everywhere. With a
  surrogate key, every rule in the project that asks that question becomes a
  subquery against this table — evaluated per row, on tables whose own access is
  being decided. `UP-1`'s *self* tier depends on this directly.
- It makes the 1 : 1 cardinality **structural**. A surrogate key with a unique
  constraint states the same rule, but permits an intermediate state in which
  the row exists without its auth row; the shared key does not.
- It removes an entire class of bug: there is no second identifier for a person
  that could be passed where the first was expected.

### 7.2 Candidate keys

**`id` is the only candidate key.** Stated explicitly because the question will
be asked again:

| Attribute | Candidate key? | Why not |
|---|---|---|
| `phone` | **No** | Not unique by design. `DD-02` made it contact data, not identity. Family members share numbers, numbers are recycled by carriers, and a person may change theirs. A unique constraint would refuse a legitimate registration |
| `full_name` | **No** | Not unique in any population, and mutable |
| `(full_name, date_of_birth)` | **No** | Not unique, and `date_of_birth` is nullable — a null in a key is not a key |
| email | **Not here** | It *is* a candidate key of the identity, and it lives in `auth.users`, which owns it and enforces its uniqueness. Duplicating it into this table would create two copies of one fact, free to disagree, with no way to say which is authoritative. `admin_list_users` joins `auth.users` for it |

### 7.3 Alternate keys

**None.** There is exactly one candidate key and it is the primary key, so there
is no alternate key to declare. No unique constraint exists on this table other
than the primary key, and none should be added — every attribute other than `id`
is either non-unique by nature or nullable.

### 7.4 Foreign keys

**Outgoing — one:**

| Column | References | On delete | On update |
|---|---|---|---|
| `id` | `auth.users(id)` | `CASCADE` | *no action* — the auth id never changes |

**Incoming — twelve**, catalogued in §5.2.

---

## 8. Constraints

Every constraint, why it exists, and its enforcement state.

### 8.1 Enforced in the database today

| ID | Constraint | Why it exists |
|---|---|---|
| `PR-C1` | **Primary key on `id`** | One profile per person. Without it, two rows could claim the same identity and every dependent join would silently double |
| `PR-C2` | **`id` references `auth.users(id)`, `ON DELETE CASCADE`** | A profile without an account is a person who cannot sign in and whom nobody can remove — an orphan with no owner. The cascade is what guarantees the pair is created and destroyed together |
| `PR-C3` | **`primary_position IN ('GK','DEF','MID','FWD')`** | The engine's position logic — distribution, goalkeeper handling, the `TRANSITION` basis — is written against exactly these four values (`BTGE-HC-5`). A fifth value would not be balanced; it would be *unhandled*, and the failure would appear as a wrong lineup rather than an error |
| `PR-C4` | **`secondary_position IS NULL OR IN ('GK','DEF','MID','FWD')`** | Same vocabulary, same reason, plus: absence is ordinary input (`BTGE-SC-6`), so null must be permitted rather than encoded as a fifth value |
| `PR-C5` | **`overall_rating BETWEEN 0.00 AND 10.00`** | The approved `OP-1` scale. The type alone allows `99.99`; the range is a business rule and belongs in a constraint. It is also what makes the rating engine's clamping meaningful — a clamp with no constraint behind it is a convention |
| `PR-C6` | **`overall_rating` is `numeric(4,2)`** | A precision constraint carrying a correctness rule (`RR-1`): reversal is exact only when the stored value can hold every value the arithmetic produces |
| `PR-C7` | **NOT NULL on `id`, `full_name`, `phone`, `primary_position`, `overall_rating`, `is_active`, `created_at`, `updated_at`** | Each is a fact with no meaningful "unknown" state. See §6.2 for the per-column reason |
| `PR-C8` | **Nullable: `secondary_position`, `date_of_birth`** | The two facts the application may legitimately not know. Recording a guess is what BTGE §4.3 and `UP-2` forbid |

### 8.2 Approved database integrity rules — `UP-3`

**Approved.** These three business rules belong to the **database layer**, in
addition to the client-side validation that already exists in
`app/lib/features/profile/profile_models.dart`. They are not yet enforced in the
database; enforcing them is part of implementing this specification (§18).

The reason they are not left to the client: a rule enforced only above the
database is a rule a direct PostgREST call does not obey, and every one of these
is reachable that way.

| ID | Integrity rule | Why it exists | State |
|---|---|---|---|
| `PR-C9` | **`secondary_position` must differ from `primary_position`** (when both are present) | BTGE §4.1 reads the two as *distinct* positions. A repeated value asserts nothing the primary does not, and would let a player appear to cover two positions while covering one — which the engine would use when choosing an assignment | Client only |
| `PR-C10` | **`date_of_birth` must not be in the future** (when present) | Age is derived as of the match date. A future birth date yields a negative age, which the age-balance calculation has no defined behaviour for. The only thing any approved document says about the date is that it has already happened — no minimum and no maximum age is approved, and none is invented here | Client only |
| `PR-C11` | **Required text fields must reject empty values** — `full_name` between 2 and 60 characters after trimming, `phone` non-empty after trimming | `NOT NULL` does not exclude `''`, and an empty string is the exact state the two rules in §6.2 exist to prevent: a roster entry with no name, and a contact field that cannot be contacted. The 2–60 bound matches the approved bound on `matches.title`, so the product has one answer to "how long may a name be" | Nowhere |

**Client-side validation is retained, not replaced.** It gives the player an
immediate, localized message instead of a database error, and the two layers
answer different needs. The database layer is what makes the rule true.

### 8.3 The database never invents a value — `UP-2`

**Approved integrity principle.**

> **The database must never invent a player's primary position.** Where a
> required value is absent, the operation **fails**; it does not silently
> substitute one.

This closes a defect in the current signup path, which substitutes `'MID'` for a
missing primary position and `''` for a missing name or phone. The first
contradicts BTGE §4.3 outright — the engine must *never* invent a primary
position, and a default applied one layer below is the same invention with the
evidence removed. The second writes exactly the empty string `PR-C11` exists to
refuse.

**What the principle requires:**

- `primary_position` has **no column default** and the creation path supplies no
  fallback. A signup without one fails.
- `full_name` and `phone` are the same: required, no substituted empty string.
- `date_of_birth` and `secondary_position` are **unaffected**. They are
  genuinely optional, absent and empty both mean *not supplied*, and both become
  null — which is `PR-C8`, and is the same principle applied honestly: the
  database records that it does not know.
- `overall_rating`'s default of `5.00` is **not an exception**. A neutral
  starting rating is a declared product constant, not a guess at an unknown fact
  (§6.2, column 7).

**Consequences the implementing phase must handle:**

- A signup that omits a required field fails. Every current client path sends
  all three, and the integration suite covers registration, so this changes no
  working flow — but it converts a silent bad row into a visible failure, which
  is the intent.
- **Existing rows must be checked before `PR-C11` is enforced.** Any profile
  holding `''` for a name or phone is a row the rule would reject. The
  implementing phase establishes the current count first and the Product Owner
  decides the repair; this specification does not choose a value to backfill,
  because inventing one is the thing being fixed (`PR-R8`).

### 8.4 Constraints deliberately **not** specified

Stated so that a future reviewer knows they were considered and refused:

| Not constrained | Why not |
|---|---|
| `phone` format or uniqueness | Contact data, one informal region, no approved format. A format rule would refuse legitimate numbers; a unique index would refuse a legitimate registration (§7.2) |
| Minimum or maximum age | No approved document sets one. Inventing an age policy in a constraint would be taking a Product Decision in a schema |
| `full_name` character class | No approved rule. The application is bilingual (Arabic and English) and any character restriction would be a guess about names |
| A default for `primary_position` | `UP-2`. That default is the invention BTGE §4.3 forbids |
| `overall_rating` bounded more tightly than `OP-1` | The range is the approved scale. Narrowing it would make the engine's clamp fire where the product says it should not |

---

## 9. Index Strategy

The table is **small and read by key**. Every current access path is either a
primary-key lookup or a join on the primary key, and the design reflects that
rather than anticipating scale the product has not reached (10 users, 3
communities, 10 matches are the PRD's success criteria).

### 9.1 Required

| ID | Index | Query it supports |
|---|---|---|
| `PR-X1` | **Primary key on `id`** (implicit, unique) | Everything: (a) `fetchMyProfile` — the profile screen reading one row by the caller's own id, which is `UP-1`'s *self* tier; (b) the "own row" predicate on every profile update; (c) the twelve incoming foreign keys' referential-integrity checks; (d) every display join — member lists, rosters, lineups, scorers, the MVP; (e) `apply_rating_delta`'s `SELECT … WHERE id = ? FOR UPDATE`, which is on the rating engine's hot path and takes a row lock; (f) the per-user serialization lock in the registration RPCs, which takes `FOR UPDATE` on the caller's profile row to stop the overlapping-match check racing with itself |

**`PR-X1` is the only index this table requires.** That is the finding, not an
omission.

**`UP-1` adds no index requirement to this table.** The community-scoped
visibility tier is answered by looking up the *reader's and the subject's*
memberships, which is served by the existing `community_members` unique index on
`(community_id, user_id)` and its `user_id` index — both already present, and
neither belonging to this table. The implementing phase should confirm the
resulting plan, but no index on `users` participates in it.

### 9.2 Present, and not justified by any current query

| ID | Index | Assessment |
|---|---|---|
| `PR-X2` | **`(phone)`** — `users_phone_idx`, created by migration `0001` | **No reader.** No RPC, policy, screen or test filters or sorts by phone; `phone` appears only as a projected column, an insert target and a privilege. `admin_list_users` searches `full_name` and email. The index dates from the pre-`DD-02` design in which phone was the login identity — it outlived the reason for it |

**Recommendation: retain, do not drop, and record it.** It costs one B-tree
maintenance step per insert and per phone update on a table with hundreds of
rows, which is not worth a migration. Removing it is recorded in §17.4 as a
cleanup for whenever this table is next touched for another reason.

### 9.3 Considered and **not** required

| Candidate | Verdict | Reasoning |
|---|---|---|
| `(is_active)` | **No** | The read rule filters on it, but the predicate is evaluated against rows already located by another access path, and essentially every row is `true`. An index with no selectivity is pure write cost |
| `(overall_rating)` or `(overall_rating DESC)` | **No — and this is a design statement, not an oversight** | The instinct is that a "highest rated" board needs it. It does not: `SL-5` ranks *Highest Rated* by the **Community** Rating, and `SL-2` §2.3 forbids any leaderboard reading Level 1. The Player Profile reads one row by primary key. **No approved surface sorts this column**, so no index serves a query that exists |
| Trigram / `pg_trgm` GIN on `full_name` | **No, for the MVP** | `admin_list_users` uses a leading-wildcard search, which no B-tree can serve. It is a System Admin path, capped at 100 rows, over a table of hundreds — a sequential scan is the right plan. Revisit only on measurement, not prediction |
| `(created_at DESC)` | **No** | `admin_list_users` orders by it, but sorting hundreds of rows is not a cost worth an index. Same trigger to revisit |
| Any composite | **No** | There is no multi-column predicate anywhere against this table |

### 9.4 The rule for a future designer

> **An index on `users` must name the query it serves.** This table is a
> reference table joined by key; a filter or a sort over its non-key columns is
> a sign that a query is doing work that belongs on a statistics table.

---

## 10. Access Control

Access rules are stated as **rules, not as policy expressions**. How they are
expressed in the database is an implementation matter for the migration phase;
what they must achieve is fixed here.

### 10.1 Read — `UP-1`, approved

**Authenticated users MUST NOT have unrestricted read access to all user
profiles.** Read access is granted in tiers, and nothing outside a granted tier
is readable.

| Tier | Who may read | What | Governed by |
|---|---|---|---|
| **1 — Self** | The signed-in person | **Always** their own profile, every column | Engineering. Unconditional and not subject to any Product Rule — a person can always see their own record |
| **2 — Community** | A member of a community | The profiles of **people they share an active community with** | **Community membership**, plus future Product decisions about which fields and which member states |
| **3 — Public** | — | Whatever Product Rules declare public | **Product Rules.** No profile field is public today, and none becomes public by default |
| **Administrative** | System Admin, through `SECURITY DEFINER` functions only | The full roster, for support | `system_admins`. Not a client capability — see below |
| `anon` (not signed in) | **Nothing** | — | — |

**The binding rules:**

1. **Least privilege.** A profile is readable only where a stated rule grants
   it. There is no default-open tier and no "signed in is enough".
2. **Enumeration of all users is NOT permitted.** No client may list, page
   through, search or count the application's users. A reader may see the people
   they share a community with; they may not discover that anyone else exists.
3. **Public visibility is a Product Rule, not an engineering default.** Tier 3
   is empty until the Product Owner fills it. An engineer may not widen
   visibility to make a screen easier.
4. **Community visibility follows membership and remains a Product question in
   its detail.** *That* shared members can see each other is settled; *which
   fields*, and how a departed or inactive member is treated, is a future
   Product decision (§17.1). Until it is taken, tier 2 grants the whole row for
   an active shared community, which is what every current screen needs and no
   more.
5. **Inactive profiles are invisible in every tier** except *self* and
   administrative. `is_active` participates in the rule (§6.2, column 8).
6. **The administrative path is not an exception to rule 2.**
   `admin_list_users` enumerates, but it is a `SECURITY DEFINER` function gated
   on `system_admins` that raises `NOT_AUTHORIZED` first thing. The privilege
   belongs to the function, not to the caller's role, and no client role can
   reach the table that way. An authorized support tool is not client
   enumeration.

**Every current screen is satisfied by tiers 1 and 2.** This was checked rather
than assumed: member lists, match rosters, generated lineups, goal scorers, the
MVP and the community owner's name all render people who are members of the
community the reader is looking at. The Player Profile screen reads the reader's
own row. Nothing in the built application reads a profile outside a shared
community, so `UP-1` costs no feature.

**Conformance.** The schema as built does **not** yet satisfy `UP-1` — it grants
every authenticated user read access to every active profile. That is a
deviation from this specification, recorded in §18 as the first item the
implementing phase must close.

**No RLS SQL is designed here**, by instruction. The rules above are what the
implementation must achieve.

### 10.2 Insert

| Who | May insert |
|---|---|
| Every client role | **Nobody**, and this must never change |

The only creator is the `AFTER INSERT` trigger on `auth.users`, running
`SECURITY DEFINER` (§4.1). Under `UP-2` that trigger fails rather than
substituting a value for a missing required field.

### 10.3 Update

Enforcement is in **two layers, answering two different questions**, and neither
layer can answer the other's:

| Layer | Question it answers | Rule |
|---|---|---|
| **Row-level rule** | *Which rows?* | A signed-in user may update **their own row only** |
| **Column privilege** | *Which columns?* | `UPDATE` is revoked at table level and re-granted on exactly five columns: `phone`, `full_name`, `primary_position`, `secondary_position`, `date_of_birth` |

**Why both are required** (`RR-2`). Row Level Security answers *which rows* a
statement may touch; it has no way to say *except that column*. A row rule could
not protect `overall_rating` even in principle — a check on it would have to
compare against the old value, which a row-level expression cannot see in a way
that reliably distinguishes "unchanged" from "changed to the same thing".
Column-level privilege is PostgreSQL's actual answer to the actual question: it
is enforced by the privilege system, **before** row rules are consulted, and it
applies to every path into the table.

The five granted columns are exactly what the registration and profile screens
write. `overall_rating` is withheld because the rating engine owns it;
`is_active` because deactivation is administrative; `id`, `created_at` and
`updated_at` because nothing may write them.

**The system path.** `SECURITY DEFINER` functions run as the table owner and are
subject to neither layer. That is how `record_match_result` →
`apply_rating_delta` moves a rating that nothing else can, and it is why the
write path is *single*: one function, `SECURITY DEFINER`, revoked from client
roles where it is a helper.

### 10.4 Delete

| Who | May delete |
|---|---|
| Every client role | **Nobody** |
| `admin_delete_user` | Yes — System Admin only, `SECURITY DEFINER`, after ordered cleanup (§4.4) |
| Cascade from `auth.users` | Structurally, yes — see `PR-R2` |

### 10.5 Summary

| Operation | `anon` | `authenticated` | System Admin (via RPC) | System functions |
|---|---|---|---|---|
| Read | ✗ | **✓ own row; ✓ shared-community members; ✗ everyone else; ✗ enumeration** | ✓ full roster | ✓ |
| Insert | ✗ | ✗ | ✗ | ✓ signup trigger only |
| Update | ✗ | ✓ own row, 5 columns | ✗ *(open — §11.2)* | ✓ rating engine |
| Delete | ✗ | ✗ | ✓ `admin_delete_user` | ✓ cascade |

---

## 11. Audit

### 11.1 The four columns

| Column | Required? | State | Decision and reason |
|---|---|---|---|
| `created_at` | **Required** | Present | The only ordering the admin console has, and the answer to "how long has this person been here" — a routine support question with no other source. `auth.users` has its own timestamp, but it belongs to another system and is not readable by a client |
| `updated_at` | **Required** | Present | Two independent writers touch this row — the player and the rating engine. Without it, "when did this change" has no answer, and support has no way to correlate a profile change with a report. Trigger-maintained, never writer-supplied |
| `created_by` | **Not required — and must not be added** | Absent | A profile is created by the account holder, in the same transaction as their own account, by the only path that exists. `created_by` would equal `id` on **every row that will ever exist**. A column with one derivable value is not an audit; it is a second copy of the primary key that a future reader will mistake for meaningful |
| `updated_by` | **Excluded — `UP-4`, approved** | Absent | §11.2 |

### 11.2 `UP-4` — no `updated_by`, and why

**Approved: the `users` table does not include `updated_by`.**

> **Administrative actions are recorded using immutable history — Rating History
> today, a future audit table if one is approved — never a mutable column.**

The rationale, which is the reason the decision is safe to make permanent:

- **A mutable column records only the most recent write and is overwritten by
  the next one.** An administrator adjusts a rating; the player then edits their
  own name; the administrator's action is gone. **An audit that a later,
  unrelated, legitimate edit erases is not an audit.** This is the whole
  argument, and it does not depend on which administrative actions exist.
- **Today the column would carry no information anyway.** A profile row is
  written by its owner (the caller *is* the row) or by the rating engine, which
  writes one system-managed column and already records every change — before,
  after, delta, reason and match — in `rating_history`.
- **The event that needs an actor is the change, not the row.**
  `rating_history` is append-only and immutable by trigger, with one row per
  rating change; it is the correct shape for "who did what, when", and a mutable
  column is not.
- **If administrative rating adjustment is ever approved** (`RR-2`, still open),
  the actor and reason belong on **`rating_history`** — a new `change_reason`
  value and an actor column — and `users` does not change (§17.3).
- **The project already applies this principle.** `matches.created_by` and
  `communities.owner_id` are attribution, never authorization (`PD-15`,
  `PD-16`), and `RR-5` established that history is immutable and a reversal is a
  new row rather than an edit to an old one. `UP-4` is that same rule applied to
  this table.

### 11.3 What the audit does not cover, stated plainly

There is **no history of profile field changes**. A player who changes their
name, their primary position or their date of birth leaves no record of the
previous value.

This is correct for the MVP: no approved document asks for it, and the field
that genuinely matters historically — which position a player *played*, in which
match, on which team — is already recorded per match in
`match_team_assignments` (`KB-017`), so editing a profile never rewrites
history. Recorded as `PR-R6` so that it is a known boundary rather than an
assumption.

Should profile-change history ever be approved, `UP-4` decides its shape in
advance: **an append-only history table, never columns on `users`.**

---

## 12. Dependencies

### 12.1 Tables the User Profile depends on

| Table | Nature | Consequence |
|---|---|---|
| `auth.users` | Identifying parent; supplies the primary key; owns email, password and session | A profile cannot exist before its account, cannot outlive it, and never duplicates what that table owns |

**Nothing else.** `users` can be created immediately after `auth` exists, which
is why it is migration `0001`.

### 12.2 Tables that depend on the User Profile

**Built — eleven tables, twelve foreign keys:**

| Table | Column(s) | Cascade | Group |
|---|---|---|---|
| `community_members` | `user_id` | `CASCADE` | A |
| `match_registrations` | `user_id` | `CASCADE` | A |
| `match_team_assignments` | `user_id` | `CASCADE` | A |
| `notifications` | `user_id` | `CASCADE` | A |
| `system_admins` | `user_id` (PK) | `CASCADE` | A |
| `player_statistics` | `user_id` (PK) | `CASCADE` | B |
| `rating_history` | `user_id` | `CASCADE` | B |
| `match_results` | `mvp_user_id` | `CASCADE` | B |
| `match_goals` | `user_id` | `CASCADE` | B |
| `match_results` | `recorded_by` | `SET NULL` | C |
| `communities` | `owner_id` | *no action* | C |
| `matches` | `created_by` | *no action* | C |

**Approved but not built — Level 2 (`SL-2`, `SL-3`):**

| Future entity | Expected reference | Cascade |
|---|---|---|
| Community Statistics (`E7`) | player + `community_id` + period | `CASCADE` from **`users`** and from `communities` — **never** from `community_members` (`SL-4`) |
| Community Rating (`E8`) | player + `community_id` | Same |
| Community Rating History (`E9`) | player + `community_id` | Same |

**Functional dependencies** (code that reads the table without a foreign key):

`handle_new_user`, `set_updated_at`, `apply_rating_delta`, `record_match_result`,
`admin_list_users`, `admin_delete_user`, `admin_list_communities` (joins for the
owner's name), and `register_for_match`, which takes `FOR UPDATE` on the
caller's profile row as a per-user serialization lock. **That lock is a
non-obvious dependency**: the profile row is used as a mutex for a rule that has
nothing to do with profiles (`PR-R7`).

**`UP-1` adds one:** the read rule depends on `community_members` to answer
tier 2. Visibility therefore joins authorization in resting on the membership
edge, and both are answered there and nowhere else.

### 12.3 The shape of the dependency graph

The User Profile is a **sink with one parent and twelve incoming references
from eleven tables** — maximum in-degree, minimum out-degree. Two operational
consequences follow:

- **Changing this table is expensive**, and changing its primary key is not
  possible without touching every dependent table. This is the argument for
  `UP-5` (§0) and for refusing new columns without a named consumer.
- **Deleting a row is expensive**, which is why deletion has one door, and why
  soft deactivation was designed alongside it (§4.3).

---

## 13. Future Compatibility

The question this section answers: **can Community Statistics, Global
Statistics, Leaderboards and BTGE all be delivered without redesigning this
table?** For each: **yes**, and the reason is stated as a rule that must hold.

### 13.1 Community Statistics — Level 2 (`SL-2`, `SL-3`, `SL-4`, `SL-5`)

**Not built. Requires no change to `users`.**

A Level 2 record is identified by `(player, community_id, period_type,
period_key)`. `users` supplies exactly one thing to that key — the player — and
it already does, as a primary key a foreign key can reference with
`ON DELETE CASCADE`. `SL-4` requires the record to be bound to the *player and
the community* and explicitly **not** to the membership; `users` is
community-free, so it is the correct anchor by construction.

**The two rules that keep this true:**

1. **No `community_id` on `users`, ever.** The moment a profile is scoped to a
   community, a person cannot belong to two, and the entire Level 2
   architecture — isolation, departure, rejoining — becomes unstateable. This
   holds under `UP-1` too: visibility is scoped by community at *read* time, and
   never by partitioning the record (§3).
2. **The Community Rating is not a second column here.** It is one value per
   *(player, community)* pair. A column on `users` holds one value per player,
   which is the wrong cardinality, and `SL-3` requires the two ratings to be
   independent and expected to differ. This is the single most likely future
   mistake against this table, and it is refused in advance.

`SL-4`'s lifecycle — created once at the `5.00` baseline, preserved on
departure, resumed on return, never reset — is entirely a property of the Level
2 table. Nothing about it touches this one. And `A5`'s baseline is the same
neutral `5.00` this table already uses for a new career, so the two levels start
from one constant rather than two.

### 13.2 Global Statistics — Level 1 (`RR-6`, `SL-2` §2.1)

**Built, and already correct.**

Level 1 is composed of two things that are deliberately in two places:

| Item | Where it lives | Why there |
|---|---|---|
| The **Global Rating** | `users.overall_rating` | It is a live value the engine reads as a Core Player Input, moved by every completed match in any community. It is not a counter |
| The six **counters** | `player_statistics`, keyed 1 : 0..1 by `user_id` | They are an accumulation with a different write pattern and a different lifecycle — a player with no completed match has no row at all |

**The rule that keeps this true: no counter is copied onto `users`.** A
`matches_played` column here would be a second answer to a question
`player_statistics` already answers, free to disagree with it — the same
argument `RR-6` used to keep the rating *out* of `player_statistics`. The Player
Profile screen assembles both by joining on the primary key, which `PR-X1`
serves, and it reads the caller's own row, which is `UP-1` tier 1.

### 13.3 Leaderboards (`SL-2` §2.3, `SL-5`)

**Not built. Requires no change to `users`, and — importantly — no index on
it.**

All nine boards read **Level 2** and are forbidden from reading Level 1, for any
board in any period. *Highest Rated* ranks by the **Community** Rating and never
by `overall_rating` (`SL-5`).

`users` contributes exactly one thing to a leaderboard: **the display name**,
fetched by joining on the primary key after the board has been computed and
truncated. That is `PR-X1` again.

**`UP-1` and leaderboards agree by construction.** A community board lists
people in that community, and tier 2 makes exactly those profiles readable to a
member of it. Eligibility — who may appear — is a read-time filter over
`community_members` and never a stored flag, so no eligibility column belongs
here either, and the same edge answers both eligibility and visibility.

**The rule that keeps this true:** a leaderboard query that sorts or filters on
a `users` column is reading the wrong level, and the fix is the query, not an
index (§9.4).

### 13.4 BTGE (`KB-006`, `KB-016`, §4.1)

**Built and integrated. Requires no change to `users`.**

All four Core Player Inputs are present with the nullability the specification
requires:

| BTGE §4.1 input | Column | Required by engine | Nullable in schema | Correct? |
|---|---|---|---|---|
| Player ID | `id` | Yes | No | ✓ |
| Overall Rating | `overall_rating` | Yes | No, default `5.00` | ✓ |
| Date of Birth | `date_of_birth` | Yes | **Yes** | ✓ — §6.2, `PR-C8` |
| Primary Position | `primary_position` | Yes | No, **no default** | ✓ — `UP-2` |
| Secondary Position | `secondary_position` | **No** | Yes | ✓ |

Four properties make this durable:

- **`UP-2` protects the engine's contract at the schema level.** BTGE §4.3
  forbids inventing a rating, a date of birth or a primary position; with no
  default on `primary_position`, the schema cannot manufacture one for the
  engine to read as declared.
- **Nothing derived is stored.** Age is computed from `date_of_birth` as of the
  match date, never stored as a number, so a rebalance next season uses a
  correct age without a migration.
- **Auxiliary data is not here.** Match History — the only input Diversity may
  consult — lives in `match_team_assignments` (`BTGE-AX-4`), so no teammate,
  chemistry or behavioural value can accumulate on the profile. `KB-014` forbids
  behavioural inference, and keeping the profile declarative is what makes that
  enforceable rather than merely intended.
- **A fifth input would be an additive nullable column**, on the same pattern
  `0018` used for the current three. It would need a Knowledge Base decision
  first, and nothing in this design blocks one.

**Generation is unaffected by `UP-1`.** A generation set is the confirmed
players of one match, all members of that match's community, so the organizer
reading their inputs is inside tier 2.

### 13.5 The general rule

> **A new column on `users` must be a declared attribute of a person, must not
> be community-scoped, must not be derivable from another table, and must name
> the consumer that reads it.** Anything failing one of those four tests belongs
> on another table.

---

## 14. Consistency Review

The whole specification was re-checked against each named source after the five
approved decisions were incorporated.

| # | Source | Verdict | Notes |
|---|---|---|---|
| 1 | `Docs/01-PRD.md` | **No contradiction** | Email + password identity matches `DD-02` and the absence of an email column. The three roles are per community and appear nowhere on this table. Statistics at two levels are satisfied by §13.1–13.3. **`UP-1` costs no PRD feature** — every listed capability (join a community, register for matches, generate teams, record results, view statistics) operates inside a community the actor belongs to |
| 2 | `Docs/06-ERD.md` | **No contradiction** | §1 names `users` as *"player profile, keyed to the Supabase auth user"* — this entity, under `UP-5`'s logical name. §2's `users (1) --< community_members >-- (1) communities` matches §5.2. §3.4's "ownership is Player **and** Community, never Membership" is what §13.1 preserves; **`UP-1` does not disturb it** — visibility uses the membership edge at read time, which §3.4 explicitly permits ("eligibility is a question about membership *at read time*"). §3.9 `A5` (baseline `5.00`) matches `overall_rating`'s default |
| 3 | `Docs/07-Database-Design.md` | **One statement now superseded** | *Standards* (UUID PKs, `created_at`/`updated_at`, `SECURITY DEFINER` for multi-step writes) all hold, as do the `RR-1` precision narrative, the nullability of `date_of_birth` and `secondary_position`, and the `RR-2` column-privilege rule. **Superseded:** that document describes the read rule as "any signed-in user can see active profiles". `UP-1` replaces it. §18 records the documentation update |
| 4 | **Database Principles** | **No artifact in the repository** | Validated instead against the principles as recorded in `07-Database-Design.md` §*Standards*, `SUPABASE_OPERATIONAL_GUIDELINES.md` §2 and §4, and `ARCHITECTURE_DECISIONS_V1.md`. Under those, `UP-1` moves this table **into** compliance with §4's rule that no table is broadly readable without approval, and `UP-2`/`UP-3` move integrity into the layer that owns it. **If a separate Database Principles document exists outside the repository, this specification has not been checked against it** |
| 5 | **Data Domains** | **No artifact in the repository** | Same caveat. §3 states this table's domain ownership from first principles and from the aggregate rule in `06-ERD.md` §1 |
| 6 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction** | `SL-1`…`SL-5` are satisfied by §13.1–13.3. §6 (Player Profile: Global Rating + six counters + rating history) is served by `overall_rating` joined to `player_statistics` and `rating_history`, all read from the caller's own row. §14's prerequisites that touch a player anchor are met by *not* changing this table. **`UP-1` and the boards agree** — a community board's population is exactly tier 2 |
| 7 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction** | `RR-1` (precision), `RR-2` (column privilege), `RR-5` (immutable history), `RR-6` (global scope) are restated exactly. **`UP-4` extends `RR-5`'s principle** — immutable history, never a mutable column — from `rating_history` to this table's audit design. `RR-7`'s user-deletion limitation is carried forward as `PR-R2` rather than silently inherited |
| 8 | `Docs/10-Design-Decisions.md` | **One naming collision, resolved** | `DD-02` (email identity), `DD-09` (role-based authorization), `PD-15`/`PD-16` (attribution is not authorization) all hold and are cited. **Collision:** `PD-01` … `PD-18` is an existing product-decision series. The five decisions approved in this review are therefore recorded as `UP-1` … `UP-5`, with the mapping stated in the register above (§19, remaining issue 1) |
| 9 | `BTGE_Engineering_Specification.md` v1.5 | **Contradiction resolved** | §4.1 and §4.3 are satisfied by the columns (§13.4). The `'MID'` substitution that contradicted §4.3 is **removed by `UP-2`** |
| 10 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **Discrepancy resolved** | §4's checklist states that exactly one table (`communities`) is broadly readable by `authenticated` without a membership predicate. `users` was an undocumented second one; **`UP-1` removes it from that category**, restoring the checklist's accuracy. The rest of §4 — access explicit, `SECURITY DEFINER` with pinned `search_path`, no secret to the client — holds |
| 11 | Application layer (`profile_models.dart`) | **Alignment approved** | The three rules enforced in Dart or nowhere are **approved into the database layer by `UP-3`** (`PR-C9`, `PR-C10`, `PR-C11`). Client-side validation is retained alongside, not replaced (§8.2) |

**Result: no contradiction remains within this specification or between it and
any source in the repository.** Three deviations of the *built schema* from this
specification remain and are listed in §18 — those are conformance items for the
implementing phase, not design contradictions.

---

## 15. Design Rationale

The six decisions that shaped this table, in the order they constrain everything
else.

### 15.1 The primary key is the auth id

Everything follows from this. It makes "the caller's own row" a column
comparison rather than a subquery, which means every authorization *and*
visibility decision starts from a fact the session already holds. It makes the
1 : 1 relationship structural rather than merely constrained. And it removes the
possibility of a second identifier for a person — the class of bug where an auth
id is passed where a profile id was expected simply does not exist.

### 15.2 The profile sits outside the aggregate

The project's rule is that the Community is the aggregate root and nothing is
owned by a user. The User Profile is the deliberate exception, and it has to be:
a person exists before any community, belongs to several at once, and outlives
their membership of any of them. Every future community-scoped fact —
statistics, rating, eligibility — must therefore be a separate entity keyed by
*(player, community)*, which is precisely what `SL-4` requires and §13.1
protects.

### 15.3 Visibility is scoped, not assumed — `UP-1`

A signed-in session is authentication, not authorization, and it is not
visibility either. The earlier design let any authenticated user read every
active profile because it was the cheapest way to render a name; `UP-1` replaces
convenience with least privilege. The membership edge already answers "may this
person act here"; it now also answers "may this person see this record", and
both live in one place. The cost was checked and is zero: every screen the
product has renders people inside a community the reader belongs to.

### 15.4 Ownership is split by column, not by row

The row belongs to the player. Two of its columns do not. Row-level rules cannot
express that, and the project learned this the expensive way (`RR-2`): a rating
the client could write made the entire team-generation engine decoration. The
resolution — table-level `UPDATE` revoked, re-granted per column — is the pattern
this table now demonstrates for the rest of the schema, and `SL-3` already names
it as the pattern the Community Rating must follow.

### 15.5 The schema records what it knows, and refuses what it cannot — `UP-2`, `UP-3`

`date_of_birth` is required by BTGE and nullable in the database, and that is
not a compromise. The two layers have different jobs: the database's job is to
avoid recording a falsehood, and the engine's job is to refuse an incomplete
request. A NOT NULL here would have forced a backfilled birth date for every
account created before migration `0021` — a fabricated fact, permanently
indistinguishable from a real one, feeding age balance forever.

`UP-2` applies the same principle in the other direction: where a value is
required and cannot honestly be defaulted, the operation **fails** rather than
inventing one. `UP-3` completes the pair — a rule the product holds is enforced
where it cannot be bypassed, not only where it is convenient to report.

### 15.6 Deletion has one door

Twelve incoming foreign keys, two of which do not cascade, mean a raw delete
either fails or destroys more than the caller intended. `admin_delete_user`
exists so that the order is stated once — communities owned, memberships,
matches created elsewhere, then the person — and so that the cascades are reused
rather than restated (`purge_community`, `purge_match`, `purge_membership`).
Soft deactivation exists beside it because for a *person*, deletion is usually
the wrong operation: their registrations, lineups, goals and results are facts
about matches other people played in, and removing them falsifies those matches.

---

## 16. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `PR-R1` | **Broad profile read access** — any signed-in user could read every active profile, including `phone`, and enumerate the application's users | Was **Medium** (privacy) | **Resolved by `UP-1`** at the specification level. **The built schema still has it**, so it remains an open *conformance* item until the implementing phase closes it (§18, item 1) |
| `PR-R2` | **Deleting a user by cascade from `auth.users` bypasses the ordered cleanup.** A user who was the MVP of a match takes that result away without going through `matches`, so the reversal trigger never fires and other participants keep counters for a result that no longer exists | Medium | **Known and inherited** (`RR-7`). Mitigated in practice because the approved path is `admin_delete_user`. Not resolved: resolving it means either a trigger on profile deletion or refusing the cascade, both outside this phase |
| `PR-R3` | **`phone` has no format validation and no uniqueness**, so a typo is undetectable and two people can hold the same number | Low | **Accepted by design** (§8.4). Contact data, not identity (`DD-02`). A format rule is a Product Decision and would refuse legitimate values. `UP-3` adds only the empty-value rule, which is not a format rule |
| `PR-R4` | **`is_active` is dormant.** The read rule depends on it, but nothing writes it, so the designed suspension capability does not exist | Low | **Accepted.** §17.2 states what completing it requires. The column is correct; only the operation is missing |
| `PR-R5` | **Pressure to make `date_of_birth` NOT NULL** will recur, because the engine requires it and a nullable column looks like an omission | Medium — a silent data-quality failure, not a visible one | **Refused in advance** (§6.2, §15.5). Any backfill fabricates a fact that feeds age balance permanently and is indistinguishable from a real one — the same failure `UP-2` forbids for the primary position. The correct path is the application asking the player |
| `PR-R6` | **No history of profile field changes.** A name, position or birth date change leaves no record of the previous value | Low | **Accepted for the MVP** (§11.3). If ever approved, `UP-4` fixes its shape: an append-only table, never columns here |
| `PR-R7` | **The profile row is used as a per-user mutex.** `register_for_match` takes `FOR UPDATE` on the caller's profile to serialize the overlapping-match check. A future long-running transaction that writes a profile would contend with match registration for reasons no reader would predict | Low, but sharp | **Recorded, not changed.** It works and is tested (`concurrency_test.dart`). Documented so the next person to add a write path to this table knows the lock exists |
| `PR-R8` | **Existing rows may hold `''` for `full_name` or `phone`**, which `PR-C11` would reject | Low | **Must be measured before implementation** (§8.3). The implementing phase establishes the count first; the Product Owner decides the repair. This specification does not choose a backfill value |
| `PR-R9` | **The logical / physical name split** (*User Profile* vs `users`) must be applied consistently, and `public.users` is one character from `auth.users` in a project where both appear | Low | **Managed by `UP-5`** (§0). The convention is binding on all future engineering documentation. See §19, remaining issue 2, for the one file that does not yet follow it |
| `PR-R10` | **`UP-1` tier 2 is stated at row granularity.** Which *fields* a fellow community member may see, and how a departed or inactive member is treated, is a future Product decision | Low | **Open by design** (§10.1 rule 4, §17.1). Until taken, tier 2 grants the whole row for an active shared community — what every current screen needs and no more |

---

## 17. Future Considerations

None of the following is approved, in scope, or authorized by this document.
They are recorded so that they are found deliberately rather than rediscovered.

### 17.1 Visibility refinements under `UP-1`

Tier 2 is settled in principle and open in detail. Future Product decisions may
narrow it — which fields a fellow member may see, whether a departed member
remains visible on the historical rosters they appear in, whether an inactive
member is visible to community admins. Tier 3 (public visibility) is empty and
is filled only by a Product Rule.

**All of these are read-time refinements over `community_members`.** None adds a
column to `users`, and none partitions it (§3, §13.1).

### 17.2 Completing the deactivation capability (`PR-R4`)

Would require a `SECURITY DEFINER` operation gated on System Admin, a Product
Decision on what deactivation *means* for existing memberships, registrations in
live matches and leaderboard eligibility, and a decision on whether the person
can reactivate themselves. **The column is not the missing part; the policy
is.**

### 17.3 Administrative rating adjustment (`RR-2`, open)

If approved: the actor and reason belong on `rating_history` — a new
`change_reason` value and an actor column — **not** on `users`. This is `UP-4`
(§11.2), decided in advance. `users` would not change.

### 17.4 Cleanups, for whenever this table is next touched for another reason

- Drop `users_phone_idx` (`PR-X2`, §9.2) — no reader since `DD-02`.
- Revoke the residual table-level insert and delete privileges from
  `authenticated`. Both are already denied by the absence of a rule granting
  them, so this is defence in depth, not a fix.

**Neither justifies a migration on its own** (`CLAUDE.md` §4). Both are natural
companions to the `UP-1` work, which does touch this table's access rules.

### 17.5 Deliberately excluded

Avatar or photo (Storage is not adopted — `SUPABASE_OPERATIONAL_GUIDELINES.md`
§5); preferred foot, height, weight or any further attribute (`KB-006` fixes the
Core Player Inputs at four, and `KB-014` forbids behavioural inference);
per-community display name; notification preferences; any counter, any rating
other than the Global Rating, any role, any capability; and any column that
exists to make a profile findable — `UP-1` rule 2 forbids enumeration, and a
search key would be the first step towards it.

---

## 18. Conformance — where the built schema differs from this specification

This document is now the authority for `public.users`. Three deviations exist
between it and the schema as built through migration `0024`. Each is a
**conformance item for a future implementation phase**, not an open design
question — the design is settled here.

| # | Deviation | Required by | Notes for the implementing phase |
|---|---|---|---|
| 1 | **Read access is unrestricted.** Every authenticated user can read every active profile and enumerate the table | `UP-1` (§10.1) | The largest of the three. Tiers 1 and 2 must be expressed without a per-row subquery cost the read paths cannot bear; the membership indexes needed already exist (§9.1). Denials must be asserted in the integration suite, not assumed (`SUPABASE_OPERATIONAL_GUIDELINES.md` §4) |
| 2 | **The signup path substitutes values** — `'MID'` for a missing primary position, `''` for a missing name or phone | `UP-2` (§8.3) | Must fail instead. No current client path is affected; the change converts a silent bad row into a visible failure |
| 3 | **Three integrity rules are not in the database** — secondary ≠ primary, no future birth date, no empty required text | `UP-3` (§8.2) | Item 2 must land first or together: `PR-C11` cannot hold while the trigger writes `''`. Existing rows must be counted before enforcement (`PR-R8`) |

**Documentation follow-up.** `Docs/07-Database-Design.md` describes the old read
rule ("any signed-in user can see active profiles") and
`SUPABASE_OPERATIONAL_GUIDELINES.md` §4 names `communities` as the only broadly
readable table. Both should be aligned to `UP-1` when it is implemented — **not
before**, so that the documents keep describing the schema as it actually is.

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched.

---

## 19. Engineering Approval

**Status: Engineering Approved.**

**This document is the authoritative engineering specification for the physical
table `public.users`.** Where an implementation and this document disagree, the
implementation is the defect.

| Criterion | Status |
|---|---|
| Logical entity and physical table named and fixed (`UP-5`) | ✓ |
| Purpose, ownership, domain and lifecycle stated | ✓ |
| Every column specified — name, purpose, type, nullability, default, editability, business justification | ✓ 10 of 10 |
| Keys: primary, candidate, alternate, foreign — each stated, including those deliberately absent | ✓ |
| Every business constraint stated with its reason | ✓ 11, of which 3 approved into the database layer by `UP-3` |
| Integrity principle: the database invents nothing (`UP-2`) | ✓ |
| Index strategy: every index justified by a named query; every rejected candidate justified | ✓ |
| Access control: read, insert, update, delete — who, at what scope, by which mechanism (`UP-1`) | ✓ |
| Audit: all four columns ruled on; `updated_by` excluded with rationale (`UP-4`) | ✓ |
| Dependencies in both directions, built and approved-but-unbuilt | ✓ |
| Future compatibility: Community Statistics, Global Statistics, Leaderboards, BTGE — each shown to need no redesign | ✓ |
| Consistency review against all named sources | ✓ 11 sources, 0 remaining contradictions |
| Conformance gaps between specification and built schema recorded | ✓ 3, §18 |
| No SQL, no migration, no implementation, no other table | ✓ |

### Remaining issues

Two, neither of which blocks approval. Both are the Product Owner's to settle.

1. **Decision ID namespace.** The five decisions were approved as `PD-1` … `PD-5`
   and are recorded here as `UP-1` … `UP-5`, because `PD-01` … `PD-18` is an
   existing product-decision series cited across `06-ERD.md`,
   `07-Database-Design.md`, `08-UI-UX-Specification.md` and
   `10-Design-Decisions.md`. Reusing those numbers would make `PD-2` ambiguous
   project-wide. **The mapping is stated in the register above**, so nothing is
   lost either way. Overrule with one word if the `PD-n` labels are preferred.
2. **This file's name.** The path is
   `Docs/engineering/Profiles_Table_Specification.md`, which carries the word
   `UP-5` retires. The file was named before the decision and the path was
   specified in the task, so it was **not** renamed. Renaming it to
   `User_Profile_Table_Specification.md` is a one-line change whenever you want
   it.

### Validation caveat, stated rather than glossed

The review brief names *Database Principles* and *Data Domains* as consistency
sources. **Neither exists as a document in this repository** (§14, rows 4 and
5). Consistency was reviewed against the principles recorded in
`07-Database-Design.md`, `SUPABASE_OPERATIONAL_GUIDELINES.md` and
`ARCHITECTURE_DECISIONS_V1.md`. If those two documents exist outside the
repository, this specification has not been checked against them and that check
remains outstanding.

---

## Related documents

| Document | Relationship |
|---|---|
| `Docs/01-PRD.md` | Product scope; identity is email + password (`DD-02`) |
| `Docs/06-ERD.md` | §1 names this entity; §3 is the conceptual model this design must not contradict |
| `Docs/07-Database-Design.md` | The schema as built. Its read-access statement is superseded by `UP-1` — align when `UP-1` is implemented (§18) |
| `Docs/10-Design-Decisions.md` | `DD-02`, `DD-09`, `PD-15`, `PD-16`, `SL-1`…`SL-5`; the `PD-01`…`PD-18` series this document does not reuse |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **Authoritative** for statistics and leaderboards (v2.0) |
| `engineering/Results_Rating_Engineering_Decisions.md` | `RR-1`, `RR-2`, `RR-5`, `RR-6`, `RR-7`; `UP-4` extends `RR-5`'s principle |
| `engineering/BTGE_Engineering_Specification.md` | §4.1 Core Player Inputs, §4.3 input validity, `OP-1`; `UP-2` closes the §4.3 contradiction |
| `engineering/BTGE_Design_Knowledge_Base.md` | `KB-006`, `KB-014`, `KB-016`, `KB-017` — design authority |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §2 migration policy, §4 security checklist — `UP-1` restores this table to §4 compliance |
| `engineering/ARCHITECTURE_DECISIONS_V1.md` | Layer responsibilities |
