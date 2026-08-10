# Community Invitation Credential (`community_invitations`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved as a design — contingent on `CI-D0`** (§19). The table does not exist; implementing it amends `DD-12` and the Communities specification |
| Role | **Engineering Authority** for the physical table `public.community_invitations` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Phase 3.4 |
| Scope | **`public.community_invitations` only.** `communities`, `community_members`, `users` appear **only as dependencies** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **The table specified here does not exist.** The invitation credential lives
> today as `communities.join_code`, a column on the aggregate root. This
> document specifies the table that credential should occupy, and §16 states
> why — the short version being that **the approved visibility rule cannot be
> enforced where the credential currently lives.**
>
> **This document contains no SQL, no migration and no implementation.**
>
> **It does not redesign approved product behaviour.** The Join Code
> architecture — one credential, unlimited use, rotation as revocation, no
> pending membership, join succeeds or fails — is confirmed unchanged in §16.
> What changes is *where the credential is stored*, not *what it is or how it
> behaves*.
>
> **Sibling authorities.** `Profiles_Table_Specification.md` v2.0 (`users`),
> `Communities_Table_Specification.md` v1.0 (`communities`),
> `Community_Members_Table_Specification.md` v1.0 (`community_members`).

---

## 0. Logical entity, physical table, and a naming warning

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Community Invitation Credential** |
| **Physical table** | **`community_invitations`** |

### 0.1 This is not the table that was removed

The project's migration history contains **two** removed tables whose names are
close enough to be confused with this one, and `SUPABASE_OPERATIONAL_GUIDELINES.md`
§2.2 keeps every migration, so a future reader **will** encounter both:

| Removed table | What it was | Why it is not this |
|---|---|---|
| `invitations` (migration `0008`, dropped in `0012`) | A **directed** invitation naming one recipient, with a pending/accepted/revoked/expired state machine and a 14-day expiry | It named a *person* and carried a *pending membership*. Both are forbidden by the approved architecture |
| `community_invite_links` (migration `0010`, dropped in `0012`) | A shareable link carrying **its own 32-character token**, separate from the community's join code | It was a **second identifier** for the same act of joining — exactly what `DD-12` collapsed |

**This table is neither.** It holds **one credential per community** — the same
single credential `DD-12` approved — relocated from a column to a row. It
names no recipient, carries no pending state, and introduces no second
identifier.

**Naming note for the implementing phase.** Because `invitations` already
appears in the history, the plural-and-prefixed name `community_invitations`
must be used in full, never abbreviated to `invitations` in code, comments or
documents.

---

## 1. Purpose

`community_invitations` holds **the credential that admits a person to a
community**.

It exists to give that credential three things it cannot have as a column on
the aggregate root:

1. **An access rule that can actually be enforced.** The approved rule — *the
   join code is visible only to the Community Owner and Community Admin* —
   **cannot be expressed where the credential lives today.** A row-level rule
   cannot restrict which columns are read; a column privilege is granted to a
   database role and cannot see whether the caller is an admin *of this
   particular community*. As a row in its own table, the rule becomes an
   ordinary row-level predicate. **This is the decisive reason the table
   exists** (§16.2).
2. **A lifecycle of its own.** A credential is issued, distributed, used and
   retired. Those events belong to the credential, not to the community that
   owns it, and a column cannot record when it was issued or by whom.
3. **An extension point that costs nothing now.** Campaign codes, expiry and
   QR distribution are all rows and columns here, and none of them is a change
   to the Community domain (§14).

**What this table is deliberately not:**

- **It is not a directed invitation.** It names no recipient. There is no
  `invitee_id`, and there must never be one — that was the dropped
  `invitations` table (§0.1).
- **It is not a pending membership.** No membership exists until a join
  succeeds. `community_members` never stores invitation state, and this table
  never stores membership state.
- **It is not an identifier.** The credential *admits*; it does not *identify*.
  Nothing may reference a community by its code, and no foreign key targets the
  code column (§9, `CI-C7`).
- **It is not a join log.** It records credentials, not the joins they
  produced. Who joined and when is `community_members.created_at` (§5.2).

---

## 2. Business Owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That a credential exists** | The system, on behalf of the community | Community creation issues the first one |
| **The credential value** | **The system, exclusively.** Never chosen, never client-supplied | The generator |
| **When a credential is retired** | **The community owner or an admin** — both share invitations, so both may retire one | Rotation |
| **Who may see a credential** | **Product Rule, approved:** Owner and Admin only | The read rule (§11.1) |
| `community_id`, `created_at`, `id` | The database | Nothing writes them after insert |

**Note what is *not* owned by the person who rotates a code:** the new value.
An owner may decide *that* the credential changes; they may never decide *what
it becomes*. A credential the holder chooses is not a credential (`CI-C6`).

---

## 3. Domain Ownership

**Domain: Community. Position: inside the aggregate, beneath the root.**

| Property | Value |
|---|---|
| Aggregate | **Member of the Community aggregate**, not a root |
| Aggregate root | `communities` |
| Depends on | `communities`, and `users` for attribution only |
| Depended on by | **Nothing** today. §14.5 states the one future reference and its condition |
| Contains authorization | **No.** Holding a credential admits you as a `player`; it grants no role and never has |

**It sits beside `community_members`, not above or below it.** The two are the
Community aggregate's other members, and they are strictly separated:

> **This table governs who *may join*. `community_members` records who *has
> joined*. Neither knows anything about the other, and no row of either
> references a row of the other.**

That separation is what `DD-12` means by *"the code governs joining, not having
joined"*, and it is why rotating a credential touches no membership, no match
and no registration.

---

## 4. Lifecycle

```
  (1) GENERATE ──▶ row created, active, value system-chosen
        │
        ▼
  (2) DISTRIBUTE ──▶ nothing happens in the database
        │
        ▼
  (3) USE ──▶ nothing is written here; a membership is created elsewhere
        │
        ▼
  (4) ROTATE ──▶ retire this row + issue a new one, ONE transaction
        │            (this is also how REVOKE is performed — §4.5)
        ▼
      RETIRED ──▶ permanent. The row is kept forever, never deleted
```

### 4.1 Stage 1 — Generate

A credential is created in exactly two situations:

| When | Trigger | Who |
|---|---|---|
| A community is created | The same transaction that creates the community and its owner membership | The creator |
| A credential is rotated | The retirement of the previous one, in the same transaction | Owner or admin |

**Generation rules:**

- **The value is system-chosen, always.** Twelve characters from a 31-symbol
  alphabet — Crockford-style base32 without `I`, `L`, `O`, `0` and `1`, which
  people mistype — giving about **59 bits**. `DD-12` raised it from six
  characters precisely because the code became the input to a function
  available to unauthenticated callers, and six characters were guessable.
- **The generator retries until the value is unused**, checked against **every
  row ever issued**, active and retired (`CI-C3`). §9.1 explains why the check
  must span retired rows.
- **No client insert exists**, by any route.

### 4.2 Stage 2 — Distribute

**Nothing happens in the database.** Distribution is the owner or admin sharing
the code — as a link, as characters typed into a chat, or as a QR image
someone generates from the link.

Three consequences the design must be read with:

- **The database has no idea how many places a code has been shared**, and
  cannot. Distribution is unbounded and untracked by design (`CI-C10`).
- **The link and the typed code carry the same value.** There is no second
  token (`DD-12`), so there is no second thing to retire.
- **This stage is why the credential is a secret.** Once distributed, its
  security rests entirely on who was given it — which is why §11.1 restricts
  who can *read* it, and why §16.2 makes that the reason this table exists.

### 4.3 Stage 3 — Use

A person submits the code. The system finds the community **by the code alone**,
validates, and either **creates a membership or fails**. There is no
intermediate state, no request, no acceptance and no queue.

**Nothing is written to this table.** A credential is not consumed, not
decremented, and not marked used:

| Property | Value | Why |
|---|---|---|
| Uses per credential | **Unlimited** | The distribution channel is a group chat. A use limit would mean the first reader admits themselves and the rest of the team is locked out — the opposite of the intent (`CI-C10`) |
| Recorded here | **Nothing** | Who joined and when is `community_members.created_at`. Recording it twice would be two answers to one question |
| Effect of the join policy | The credential works under **both** `OPEN` and `CODE_REQUIRED` | `DD-13`: the code is the credential, not the policy. A link must work whatever the community's admission rule is |

**Two read paths take a code as input and neither reads this table as a
client:**

- **Preview before signup** — the application's only unauthenticated entry
  point. It accepts a code and returns a state, the community's id and name,
  and whether the caller is already a member. **It never returns a code**; it
  takes one.
- **Redemption** — accepts a code, creates a membership.

Both are `SECURITY DEFINER` and both address this table by the credential
value. Neither grants any client read access to it (§11.1).

### 4.4 Stage 4 — Rotate

**Rotation is the retirement of one credential and the issue of its
replacement, in one transaction.**

`DD-12` is explicit about the atomicity requirement: there must be no moment at
which a community has two codes or none. In this model that is stated
structurally rather than relied upon — the *at most one active* rule (`CI-C5`)
makes two codes unrepresentable, and the single transaction is what preserves
the other half.

| Property | Value |
|---|---|
| Who | **Owner and admin.** Both share invitations, so both may retire one (`PD` role matrix: *share the community invitation* — admin yes) |
| What changes on the retired row | `revoked_at` and `revoked_by`, written **once**, never again (`CI-C8`) |
| What happens to the value | **Nothing.** The retired row keeps its code forever. It is never reused, by this community or any other (`CI-C3`) |
| Effect on membership | **None.** Membership, matches and registrations are untouched — the code governs joining, not having joined (`DD-12`) |
| Effect on outstanding links | **Every one stops working, at once.** That is the point |

### 4.5 Stage 4 — Revoke

**For the MVP, revoke and rotate are the same operation**, and this is not a
simplification introduced here — it is `DD-12`'s own statement: *since the code
is the only identifier, there is nothing else to revoke; issuing a new code
invalidates the old one by replacing it.*

**Revocation without replacement** — retiring the active credential and issuing
nothing, leaving the community with no way in by code — is **not MVP
behaviour**. Today it is impossible (the column is NOT NULL) and this
specification preserves that: `CI-C11` requires exactly one active credential
at all times.

It is, however, a coherent future capability ("close this community to new
members for now"), and the row model already expresses it — a community with
all rows retired. Recorded as `CI-D2`, with a recommendation and the reason it
is not MVP.

### 4.6 Stage 4 — Expire

**No credential expires in the MVP.** `expires_at` is specified, is always
null, and null means *never expires* (§7.2, column 5).

**Expiry is a read-time question, not a stored state**, and this follows the
project's established treatment of every time-derived fact: a match's lock is
derived from the clock rather than stored (`DD-04`), completion likewise
(`DD-05`), and leaderboard eligibility is evaluated when a board is read
(`SL-5`). A credential is *usable* when it is not retired and not past its
expiry, evaluated at the moment someone tries to use it.

**This has a structural consequence the implementing phase must respect:** the
*at most one active* rule (`CI-C5`) is expressed over **retirement only**, not
over expiry, because a uniqueness rule cannot depend on the current time. An
expired-but-not-retired credential still occupies the community's single active
slot until it is rotated. For the MVP this is vacuous — nothing expires — and
§14.4 states what changes when campaigns arrive.

### 4.7 The terminal state

**A retired credential is retained forever.** It is never deleted, and there is
no operation that deletes one. It leaves only when its community does, by
cascade.

Three reasons, and the first is a security property:

1. **A retired code must never become live again for a different community.**
   The generator checks every row ever issued, so a code shared in a chat two
   years ago can never later admit someone to somebody else's community
   (`CI-C3`).
2. **Rotation is a security response**, and a security response with no record
   of when it happened or who performed it is weak. The retired row *is* that
   record.
3. **It costs nothing.** A community rotates its code rarely — the expected
   count is single digits over a community's life.

---

## 5. Business Responsibilities

### 5.1 What this table owns

| # | Responsibility | How expressed |
|---|---|---|
| 1 | **The invitation credential** — the value that admits a person | `code` |
| 2 | **Validity** — whether a credential may currently admit anyone | `revoked_at` is null, and `expires_at` has not passed. Evaluated at use time |
| 3 | **Expiration** — the time bound, when one exists | `expires_at`. Always null in the MVP |
| 4 | **Rotation history** — which credentials this community has had, when each was issued and retired, and by whom | The full set of rows for a community |
| 5 | **Uniqueness of the credential across the application** | The global uniqueness of `code` (`CI-C3`) |
| 6 | **The one-active rule** — a community offers exactly one way in at a time | `CI-C5` and `CI-C11` |
| 7 | **Usage rules** — that a credential is unlimited-use and is not consumed | By the *absence* of any counter (§5.3) |

### 5.2 What this table does **not** own

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **Membership** | `community_members` | This table governs who *may* join; that one records who *has*. §3 |
| 2 | **Any pending or intermediate membership state** | Nowhere — it does not exist | Approved architecture: a join succeeds or fails. A pending row is a state that can be abandoned, duplicated or accepted after the community changed |
| 3 | **The recipient of an invitation** | Nowhere | It names nobody. That was the dropped `invitations` table (§0.1) |
| 4 | **The join *policy*** | `communities.join_policy` | `DD-13`: the code is the credential, the policy is the rule. A credential that also carried the policy would recreate the `is_private` conflation `DD-13` removed |
| 5 | **Who joined, and when** | `community_members.created_at` | Recording it here too would be a second answer to one question |
| 6 | **Which credential admitted a given member** | Nowhere, deliberately | §14.5 states the one future case that would need it, and its cost |
| 7 | **How widely a code was distributed** | Nowhere, and unknowable | §4.2 |
| 8 | **Any role or authority** | `community_members.role` | Redeeming a credential admits a `player`. It has never granted more, and must not |

### 5.3 Usage limits — owned as an absence

The rule is *a credential is unlimited-use*, and it is expressed by there being
**no counter to increment**.

This is a design choice with a concrete benefit: a use counter on a credential
is a write on the join path, and every join of a popular community would
contend for the same row. Unlimited use means **redemption reads this table and
never writes it** — the join path takes no lock here at all.

If a use limit is ever approved, §14.4 states the shape and names the
contention as the cost.

---

## 6. Relationships

### 6.1 Outgoing — what a credential depends on

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `communities` | `community_id` | many : 1 | **`CASCADE`** | **Identifying.** A credential to nowhere is not a fact |
| `users` | `created_by` | many : 1 | **`SET NULL`** | **Attribution only.** Never authorization |
| `users` | `revoked_by` | many : 1 | **`SET NULL`** | **Attribution only.** Never authorization |

**Why the two `users` references are `SET NULL` and nullable.** They follow the
precedent `match_results.recorded_by` already sets: attribution must never be
the reason an account cannot be deleted. An owner who leaves the application
should not make their community's credential history undeletable, and the
history is still meaningful with the actor unknown — *this code was retired on
this date* remains true.

**They are never read to grant or deny anything**, exactly as
`communities.owner_id` and `matches.created_by` are not (`PD-15`, `PD-16`).

### 6.2 Incoming — what depends on a credential

**Nothing today, and nothing may be added without the condition in §14.5.**

In particular, and stated as a rule:

> **Nothing may reference a credential by its `code` value.** The code is
> mutable in the sense that matters — it is retired and replaced — so a stored
> reference to it is a reference that stops resolving. Anything needing to name
> a credential names its `id`.

### 6.3 Ownership, deletion and lifecycle

| Question | Answer |
|---|---|
| **Who owns the relationship's meaning?** | The **community**. A credential says *admits to this community*; that is its entire content |
| **Can a credential be reparented?** | **No.** `community_id` is never written after insert. A credential for a different community is a different credential |
| **Deletion — inbound** | Deleting the **community** removes every credential it has ever had, by cascade. Deleting a **user** clears the two attribution columns and removes nothing |
| **Deletion — outbound** | Deleting a credential removes nothing. No cascade fires, and **no operation deletes one** (§4.7) |
| **Lifecycle ownership** | The community bounds the credential absolutely. The credential bounds nothing |

**A lesson `DD-12` records applies directly here.** When `0012` dropped the old
`invitations` table, `delete_community` kept deleting from it and community
deletion broke in production — found only because the test teardown used that
function. The corresponding rule for *adding* a table is the mirror image:
**`purge_community` must be verified against this table before it is
introduced.** The cascade handles it — `purge_community` ends by deleting the
community row — but that must be confirmed rather than assumed, and the
credential must not be given a `SET NULL` reference to anything that
`purge_community` deletes earlier, or it acquires an ordering requirement of
the kind that made notifications step 2.

---

## 7. Columns

Nine columns.

### 7.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `community_id` | `uuid` | No | none | **Never** |
| 3 | `code` | `text` | No | generated | **Never** — rotation issues a new row |
| 4 | `created_by` | `uuid` | **Yes** | none | **Never** |
| 5 | `expires_at` | `timestamptz` | **Yes** | `null` | **System only.** Always null in the MVP |
| 6 | `revoked_at` | `timestamptz` | **Yes** | `null` | **System only, write-once** |
| 7 | `revoked_by` | `uuid` | **Yes** | `null` | **System only, write-once** |
| 8 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| — | `updated_at` | — | — | — | **Not required** — §12.2 |

**The row is write-once-then-sealed.** Every column is immutable from insert
except `revoked_at` and `revoked_by`, which are written together, exactly once,
in the one-way transition *active → retired*. There is no path back and no
second retirement (`CI-C8`).

### 7.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated, never editable**

*Purpose.* Row identity, and the only safe way for anything to name a
credential.

*Business justification.* Unlike `community_members.id` — which this project's
own specification records as having no consumer — this column has a real role:
it is what a future reference must use, because the credential's *value* is
retired and replaced and is therefore unusable as a reference (§6.2). It is
also what distinguishes two credentials of the same community in a rotation
history.

---

**2. `community_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Which community this credential admits to.

*Business justification.* It is the entire meaning of the row, and it is the
scoping column of the whole Community aggregate — the same value `matches` and
`community_members` carry, for the same reason. It is also what the read rule
(§11.1) tests, which is only possible because the credential is a row.

*NOT NULL, no default.* A credential to no community admits nobody to nothing.

*Never editable.* Reparenting would silently redirect every outstanding link.

---

**3. `code` — `text`, NOT NULL, system-generated, globally unique, never
editable**

*Purpose.* **The credential.** The value a person submits to be admitted.

*Business justification.* `DD-12` collapsed three invitation identifiers into
one, and this is it. The collapse is what makes revocation expressible at all:
with one credential there is exactly one thing to retire, so issuing a
replacement is a complete revocation. With three identifiers there was no
single act that invalidated an outstanding invitation.

*Twelve characters, 31-symbol alphabet, ≈59 bits.* The alphabet excludes `I`,
`L`, `O`, `0` and `1` because the code is typed by hand as well as followed as
a link. The length was raised from six by `DD-12` because the code became the
input to an **unauthenticated** preview, and six characters were brute-forceable.
The stored bound is 6 to 32 characters so that the historical estate and any
future length remain expressible.

*Globally unique, across active and retired rows, forever* — `CI-C3`. Not
merely per community, and not merely among active rows. §9.1 explains why, and
it is a security property rather than a tidiness one.

*Never editable, and never client-chosen.* Rotation **issues a new row**; it
does not rewrite this one. A credential whose holder may choose its value is not
a credential, and a credential whose value can be edited in place destroys the
rotation history that is this table's second reason to exist.

*It is a secret.* §11.1 is the whole of its protection, and §16.2 is why that
protection is possible here and not where the credential lives today.

---

**4. `created_by` — `uuid`, NULLABLE, no default, never editable**

*Purpose.* Who issued this credential.

*Business justification.* Rotation is a security response — someone decided a
shared code should stop working. *Who decided* is part of that record, and
today it is not recorded anywhere at all. For the first credential of a
community it is the creator; for every later one it is the owner or admin who
rotated.

*Nullable, and `SET NULL` on account deletion* — attribution must never block a
deletion (§6.1). It is nullable rather than NOT NULL for that reason alone;
every row is written with a value.

*Never editable.* An attribution that can be rewritten is not an attribution.

---

**5. `expires_at` — `timestamptz`, NULLABLE, default `null`, system only**

*Purpose.* When this credential stops being usable, if it ever does.

*Business justification.* **Null means "never expires", and in the MVP every
row is null.** The column is specified now rather than added later because
adding it later is free while *designing around its absence* is not: without it,
the first campaign requirement forces a schema change on the join path.

*Expiry is evaluated at use time, never swept.* The project has no scheduler by
decision (`DD-05`), and a background job that retires expired credentials would
be the first. Deriving usability from the clock is what `DD-04` and `DD-05`
already do for match lock and completion.

*System only.* If a bounded credential is ever issued, its bound is set at
issue. Extending an expiry in place would let a retired-by-time credential come
back to life — the one thing §4.7 exists to prevent.

---

**6. `revoked_at` — `timestamptz`, NULLABLE, default `null`, system only,
write-once**

*Purpose.* When this credential was retired. **Null is what "active" means.**

*Business justification.* Retirement needs to be a stored fact rather than a
derived one, because it is a decision rather than a consequence — unlike expiry,
nothing about the clock implies it. Storing the *moment* rather than a boolean
flag costs nothing and answers "when did we last rotate", which is the question
an owner responding to a leak actually asks.

*Null-means-active is deliberate over a boolean.* A boolean would need a second
column for the timestamp anyway, and two columns encoding one fact can
disagree.

*Write-once, one-way* — `CI-C8`. A retired credential can never be reactivated.
Reactivation would make a code that people were told had stopped working start
working again.

---

**7. `revoked_by` — `uuid`, NULLABLE, default `null`, system only, write-once**

*Purpose.* Who retired this credential.

*Business justification.* The other half of the rotation record. Same
nullability, same `SET NULL`, same never-authorization reading as `created_by`.

*It is null exactly when `revoked_at` is null*, and the two are written
together (`CI-C9`).

---

**8. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When this credential was issued.

*Business justification.* It orders the rotation history, and with
`revoked_at` it bounds the window during which a given code was live — which is
the question asked when investigating how someone got in.

---

### 7.3 `updated_at` — not required, unlike on `community_members`

The Community Members specification records the absence of `updated_at` as a
**defect**, because that table has a mutable column whose change is
untimestamped.

**Here the answer is the opposite, and for a reason rather than by
inconsistency.** The only mutation this row ever undergoes is retirement, and
**`revoked_at` is that timestamp**. An `updated_at` would hold the same instant
as `revoked_at` on every row that has one, and equal `created_at` on every row
that does not. A column that is always a copy of another column is not an audit
(the argument `Profiles_Table_Specification.md` §11.1 used to refuse
`created_by` there).

The project's Standards in `Docs/07-Database-Design.md` call for
`created_at`/`updated_at` as a pair. **This is a deliberate, reasoned
departure**, recorded as `CI-D3` so it is ratified rather than assumed.

---

## 8. The Invitation Model

Why a join code, and not the three alternatives.

### 8.1 Why not email invitations

| Reason | Detail |
|---|---|
| **The distribution channel is a group chat, not an address book** | Amateur football communities organise in WhatsApp. The organiser has a group, not a list of email addresses, and asking for addresses is friction at the exact moment enthusiasm is highest |
| **It would require knowing an identity before granting one** | An email invitation must name a recipient. The organiser frequently does not know which email a player will sign up with, or whether they have an account at all |
| **It introduces a delivery dependency** | Deliverability, bounces, spam folders and a mail provider become part of whether someone can join a football match. A code in a chat message has none of those failure modes |
| **It does not preview before signup** | A code in a URL can be shown to someone who has not installed the application — the project's only unauthenticated entry point. An invitation addressed to an account requires the account to exist first |

### 8.2 Why not pending requests

| Reason | Detail |
|---|---|
| **A pending state must be reconciled** | It can be abandoned, duplicated, expired, or accepted after the community's policy changed. Every one of those is a code path and a support question |
| **It would put a filter inside the hottest predicate in the application** | `has_community_role` is evaluated on essentially every request. If a membership could be pending, that predicate must exclude pending rows — and a mistake there is a permission bug, not a display bug |
| **It contradicts the approved architecture directly** | `community_members` never stores invitation state, and joining either succeeds immediately or fails |
| **It requires a decision-maker to be present** | A request needs someone to approve it. Communities that play on Friday do not want joining to block on an admin opening the app |

### 8.3 Why not an invitation acceptance workflow

| Reason | Detail |
|---|---|
| **Two-sided handshakes need two rows and a state machine** | The removed `invitations` table had four states and a 14-day expiry. Each was a correctness surface, and none of it delivered anything a code does not |
| **Revocation becomes unbounded** | With per-recipient invitations there is no single act that invalidates outstanding offers — you must find and revoke each. With one credential, one rotation retires everything at once |
| **Acceptance can happen after the world changed** | An invitation accepted three weeks later may name a role that no longer makes sense, or a community whose policy has changed. A code is evaluated only at the moment it is used |

### 8.4 Engineering benefits, stated as properties

1. **No state machine.** A credential is active or retired; a person is a member
   or is not. There is no third thing to reconcile.
2. **No scheduler.** Nothing needs sweeping. `DD-05` established that the
   project has no scheduler, and this model does not ask for the first one.
3. **The join path never writes this table.** Redemption is a read (§5.3), so
   the credential is never a contention point however popular a community
   becomes.
4. **Revocation is complete and atomic.** One statement retires every
   outstanding invitation, with no moment at which the community has two
   credentials or none (`DD-12`, `CI-C5`).
5. **It works before an account exists.** Preview-before-signup is possible only
   because the invitation is a bearer credential rather than a directed offer.
6. **It is policy-independent.** The same credential works under `OPEN` and
   `CODE_REQUIRED` (`DD-13`), so a shared link never has to care how the
   community is configured.
7. **Row growth is bounded by rotations, not by invitees.** A community with
   200 members and two rotations has two rows here. A directed-invitation model
   would have at least 200.

---

## 9. Business Constraints

### 9.1 Required constraints

| ID | Rule | Why it exists |
|---|---|---|
| `CI-C1` | **Primary key on `id`** | One row per credential; the only safe way to name one (§6.2) |
| `CI-C2` | **`community_id` references `communities(id)`, cascading** | A credential to a community that does not exist admits nobody to nothing. Cascading because the credential is meaningless without its community and there is nothing to preserve |
| `CI-C3` | **`code` is unique across every row ever issued — active and retired, all communities, forever** | **A security rule, not a tidiness one.** Redemption finds a community **by the code alone**. If a retired code could be reissued, a link shared in a chat two years ago would silently begin admitting people to a *different* community. Scoping uniqueness per community, or to active rows only, both permit exactly that |
| `CI-C4` | **`code` is 6 to 32 characters** | 12 is what the generator produces; the bound accommodates the historical estate and any future length without a schema change |
| `CI-C5` | **At most one active credential per community** — at most one row per `community_id` with `revoked_at` null | A community offers **one** way in. Two active credentials would mean rotating one leaves the other working, which is not revocation. This is `DD-12`'s *"never a moment with two codes"* made structural |
| `CI-C6` | **`code` is never client-chosen** | A credential whose holder chooses its value is not a credential: they could pick a guessable one, or one already circulating elsewhere. The generator's entropy and its collision check are the whole of the code's strength, and a direct write bypasses both |
| `CI-C7` | **`code` is immutable; rotation issues a new row** | Rewriting the value in place destroys the rotation record, and makes `CI-C3`'s forever-uniqueness unenforceable because the old value is gone |
| `CI-C8` | **Retirement is write-once and one-way** — `revoked_at` may go from null to a value exactly once, and never back | A reactivated credential is a code that people were told had stopped working, working again. Once is what makes the retired row a reliable record |
| `CI-C9` | **`revoked_at` and `revoked_by` are null together and written together** | They encode one event. Either alone is a half-recorded retirement, and a reader would have to guess which half is authoritative |
| `CI-C10` | **A credential is unlimited-use and is never consumed** | The distribution channel is a group message. A use limit means the first person to read it admits themselves and the rest of the team is locked out. It also keeps redemption a pure read (§5.3) |
| `CI-C11` | **Exactly one active credential per community, at all times** | Preserves today's guarantee — `join_code` is NOT NULL, so every community has always had exactly one way in. `CI-C5` gives the *at most* half structurally; the *at least* half is procedural (below) |
| `CI-C12` | **No client insert, update or delete, by any route** | Every column is either system-generated or a system-recorded event. There is no user preference on this row |
| `CI-C13` | **No credential is ever deleted** | §4.7. The retired row is what makes `CI-C3` enforceable and what records the rotation |

**On `CI-C11`, the same honest split as `CMB-C4b`.** *At most one active* is
structurally expressible — a uniqueness rule over each community's non-retired
rows states it and nothing can work around it. ***At least one* is not**: no
uniqueness or check constraint can require a row to exist. It is held by two
operations behaving correctly — community creation issues the first credential,
and rotation retires and issues in one transaction — exactly as the single-owner
invariant is held on `community_members`.

**Recommendation:** enforce the *at most one* half structurally and leave *at
least one* procedural. This is the same posture recommended as `CMB-D2`, and
consistency between the two is worth more than either choice on its own.

### 9.2 Deliberately **not** constrained

| Not constrained | Why not |
|---|---|
| A use limit, or a use counter | `CI-C10`. Would break the primary distribution channel and put a write on the join path |
| An expiry on MVP credentials | No approved requirement. Inventing a lifetime would be taking a Product Decision in a schema, and an expiry nobody asked for silently breaks a link someone shared |
| A rotation frequency or cooldown | An owner responding to a leak must be able to rotate immediately and again if needed |
| A limit on retired rows per community | Growth is bounded by rotations, which are rare. A cap would mean deleting history, which `CI-C13` forbids |
| Any relationship between a credential and a member | §5.2 item 6, §14.5 |
| The credential's *format* beyond length | The alphabet is the generator's business. Constraining the character set in the schema would refuse the historical estate and any future generator |

---

## 10. Index Strategy

Not requested in the brief, and included because omitting it would leave a
design decision open — which this specification is required not to do.

| ID | Index | Queries it supports |
|---|---|---|
| `CI-X1` | **Unique on `code`** | **The access path for the entire invitation flow.** (a) redemption, which finds a community by the code alone; (b) preview-before-signup, the only unauthenticated entry point; (c) the generator's collision check on issue. It is also `CI-C3`'s enforcement |
| `CI-X2` | **Partial unique on `community_id` where `revoked_at` is null** | Enforces `CI-C5`, and serves the one query the application issues constantly: *fetch this community's current credential*, for the owner/admin screen that displays and shares it |
| `CI-X3` | **Primary key on `id`** (implicit) | Row identity. No query today; it is the target of any future reference (§6.2) |

**Considered and not required:** an index on `(community_id, created_at)` for
the rotation history — that history is a handful of rows per community and
`CI-X2`'s leading column already narrows to them; and anything on
`expires_at`, which is evaluated on a row already located by code (§4.6).

---

## 11. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 11.1 The matrix

| Actor | Read | Create (issue) | Rotate | Revoke | Delete |
|---|---|---|---|---|---|
| **Public (`anon`)** | ✗ **Nothing** | ✗ | ✗ | ✗ | ✗ |
| **Non-member** (signed in) | ✗ **Nothing** | ✗ | ✗ | ✗ | ✗ |
| **Member — `player`** | ✗ **Nothing** | ✗ | ✗ | ✗ | ✗ |
| **Community Admin** | ✓ **This community's credentials** | ✗ *(only as the second half of a rotation)* | ✓ | ✓ = rotate | ✗ |
| **Community Owner** | ✓ **This community's credentials** | ✗ *(same)* | ✓ | ✓ = rotate | ✗ |
| **System Administrator** | ✗ **No path exists, and none is proposed** | ✗ | ✗ | ✗ | ✗ *(transitively, by community deletion)* |

### 11.2 Read — the reason this table exists

**Only the owner and admins of a community may read its credentials.** A
player may not; a non-member may not; an unauthenticated caller may not.

This is a **plain row-level rule** — *the caller holds `admin` or above in this
row's community* — and it is enforceable precisely because the credential is a
row. Where the credential lives today it is not enforceable at all (§16.2).

**Three notes:**

- **Players are excluded deliberately.** The PRD role matrix places *share the
  community invitation* with the owner and admin, and explicitly not with
  players. A player who could read the code could pass it on, which under
  `CODE_REQUIRED` is an invitation nobody authorised.
- **Retired credentials are readable by the same people.** They are the
  rotation history, and hiding them from the owner would defeat the second
  reason the table exists. There is no risk in it — a retired code admits
  nobody.
- **Unauthenticated preview is not a read of this table.** It *accepts* a code
  and answers a question about a community; it never returns a code. The
  distinction matters: `anon` submits a credential it already holds, and
  receives no credential back.

### 11.3 Create

**No client insert, by any route.** Credentials are issued by two
`SECURITY DEFINER` operations only: community creation, and rotation. A client
insert could choose the value, which is `CI-C6`.

### 11.4 Rotate and Revoke

**Owner and admin, through one `SECURITY DEFINER` operation.** For the MVP the
two words name the same act (§4.5): retire the current credential and issue its
replacement, in one transaction.

**Both roles, and not the owner alone.** Both share invitations, so both must
be able to retire one — this matches `regenerate_join_code`'s existing
authorization and the PRD role matrix. It is also the safer split: a leak is
discovered by whoever is looking, and requiring the owner would leave a known-
leaked code live until they are available.

**Note the asymmetry with `join_policy`, which is owner-only.** An admin
controls *the credential*; the owner controls *the rule*.

### 11.5 Delete

**Nobody, by any route** (`CI-C13`). Rows leave only when their community does,
by cascade.

**System Administrator has no direct path to this table**, and none is
proposed. A System Admin who needs a community's credential history has the
same recourse they have for everything else — the community's owner. The
existing administrative functions read communities, matches and users; adding
credential access would widen support's reach to a live secret for every
community in the application, which is a bigger grant than any support task
established so far requires. Recorded as `CI-D4`.

---

## 12. Audit

| Column | Required? | Verdict |
|---|---|---|
| `created_at` | **Required** | When the credential was issued. Orders the rotation history and bounds the window a code was live |
| `updated_at` | **Not required** | §12.2 — a reasoned departure from the Standards |
| `created_by` | **Required** | §12.1 — and this is the first table in the project where it is |
| `updated_by` | **Required in substance, named `revoked_by`** | §12.3 |

### 12.1 `created_by` — required, and genuinely informative

Refused on `users` (it would equal the primary key on every row) and not
required on `community_members` (joining is self-service, so it would equal
`user_id`). **Here it is neither.** A credential is issued by a person acting
on the community's behalf, and *which* owner or admin rotated the code is not
derivable from anything else. Rotation is a security response; its author is
part of the record.

### 12.2 `updated_at` — not required

§7.3. The only mutation is retirement, and `revoked_at` is that timestamp. An
`updated_at` would be a copy of it on every retired row and a copy of
`created_at` on every active one.

**This is a departure from `Docs/07-Database-Design.md` §Standards** and is
recorded as `CI-D3` so that it is ratified rather than assumed — particularly
because the Community Members specification treats the *absence* of
`updated_at` as a defect, and the two conclusions must be seen to rest on
different facts rather than on inconsistency.

### 12.3 `updated_by` — satisfied by `revoked_by`, not refused

`UP-4` excludes `updated_by` because a mutable column recording only the most
recent write is erased by the next one. **That failure mode cannot occur here**:
there is exactly one mutation in the row's life, so a column recording "who
changed this" records one event and is never overwritten.

So `UP-4`'s *rule* is honoured and its *mechanism* is unnecessary: the actor is
recorded, and it is recorded on a row that is thereafter sealed. Naming the
column `revoked_by` rather than `updated_by` states what it means and prevents a
future reader from treating it as a general-purpose last-writer field.

**This is the pattern `UP-4` points at** — an append-only record of discrete,
consequential, authorized events — arrived at by making the row itself the
history entry, rather than by adding a separate history table.

---

## 13. Dependencies

### 13.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `communities` | Identifying parent, cascading | Owns the credential's scope, meaning and lifetime |
| `community_members` | **Not a foreign key — an authorization dependency** | The read rule and the rotation authorization both resolve through `has_community_role`, which reads that table. A defect in it is a defect in who can see this table's secret |
| `users` | Attribution only, `SET NULL` ×2 | Owns the person. Takes no responsibility for the credential |

### 13.2 Tables depending on this table

**None, by foreign key.** By behaviour, the coupling is one-directional and
narrow: redemption and preview read this table and write `community_members`;
nothing reads a membership to decide anything about a credential.

**`communities` depends on it in one respect once implemented:** a community
without an active credential cannot be joined by code, and under
`CODE_REQUIRED` cannot be joined at all. `CI-C11` is what prevents that state.

---

## 14. Future Compatibility

### 14.1 QR invitations — **already supported, zero schema change**

A QR code encodes the same URL that carries the same credential. Generating and
scanning it are client concerns. **Nothing here changes**, and nothing needs to
be added.

### 14.2 Share links — **already the mechanism, zero schema change**

The link *is* the credential in a URL (`DD-12`). Deep-linking work — a domain
serving `/join/<code>`, asset links, install referrer — is entirely outside the
database.

### 14.3 Email invitations — two paths, and the cheap one is right

| Path | What it needs | Assessment |
|---|---|---|
| **Deliver the existing credential to an address** | **No schema change at all.** An email carrying the community's link | **Recommended.** It is a delivery channel for something that already exists, and keeps one credential |
| **A directed invitation naming a recipient** | A **new table** — recipient, status, expiry — and a pending state | **A different entity, not a column here.** It is what `0012` removed, and adopting it would reintroduce the acceptance workflow §8.3 argues against. If ever approved it sits *beside* this table; this one does not change |

**The distinction to preserve:** this table holds *bearer* credentials — anyone
holding the value may use it. A directed invitation is a *named* offer. Mixing
the two on one row would give a column that is sometimes null and sometimes
load-bearing, which is how a table stops being explicable.

### 14.4 Temporary invitation campaigns — the case this model was shaped for

*"A code for the Ramadan tournament, valid three weeks, shared on Instagram."*

| What it needs | Already present? |
|---|---|
| Several credentials per community, simultaneously | **Row model: yes.** Requires relaxing `CI-C5` |
| A time bound | **Yes** — `expires_at`, specified and unused |
| A record of which campaign a credential belongs to | **No** — one `label` column |
| A use limit | **No** — and see the cost below |

**The only structural change is to `CI-C5`.** *At most one active credential*
would narrow to *at most one active **primary** credential*, with campaign
credentials outside the uniqueness rule. Nothing else moves: the code stays
globally unique forever, retirement stays one-way, and redemption is unchanged
because it already finds a community by the code alone and does not care which
credential matched.

**Two warnings for whoever implements it:**

- **A use limit puts a write on the join path.** Every redemption of a popular
  campaign code would contend for one row. If it is required, the counter
  belongs somewhere designed for contention, not on the credential.
- **Expiry stays read-time** (§4.6). Introducing a sweeper would give the
  project its first scheduler, against `DD-05`.

### 14.5 Attributing a member to the credential that admitted them

*"How many people joined from the Instagram campaign?"*

This is the **one** future case that would put a foreign key into this table,
and it carries a condition:

- The reference belongs on the **membership**, pointing at the credential's
  `id` — never at its `code` (§6.2).
- It would give `community_members` a **third outgoing foreign key**, and that
  table's specification lists exactly two. **It cannot be added without
  amending `Community_Members_Table_Specification.md` §6.1.**
- The reference must be nullable and `SET NULL`-safe, because `CI-C13` keeps
  credentials forever but a membership must not depend on one.

**Not approved, and not recommended for the MVP.** Recorded so it is
recognised as a cross-specification change rather than attempted as a column.

---

## 15. Validation

**Contradictions are named, not resolved silently.** This table contradicts an
approved decision, and that is stated first.

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | `Docs/10-Design-Decisions.md` — **`DD-12`** | **CONTRADICTION — §15.1** | `DD-12` names `communities.join_code` as the invitation identifier and records that both invitation tables were removed |
| 2 | `Docs/06-ERD.md` — **§5** | **CONTRADICTION — §15.1** | *"`communities.join_code` is the only invitation identifier… there is no second token and no invitation table"* |
| 3 | `Communities_Table_Specification.md` v1.0 | **SUPERSESSION — §15.2** | That approved authority specifies `join_code` as a column of `communities` (§7 column 5, `CM-C6`, `CM-C14`, `CM-C15`, `CM-X2`). Implementing this table supersedes all of them |
| 4 | `Communities_Table_Specification.md` — **`CM-R1`** | **RESOLVED — §15.3** | The High-severity credential exposure is resolved *structurally* by this design. This is the strongest argument for the table |
| 5 | `Community_Members_Table_Specification.md` v1.0 | **No contradiction** | That table never stores invitation state, and this one never stores membership state (§3). Neither references the other. The `CMB-C4b` posture on *at most / at least* is deliberately mirrored by `CI-C11` |
| 6 | `Profiles_Table_Specification.md` v2.0 | **No contradiction** | `created_by` / `revoked_by` follow the attribution pattern (`SET NULL`, never authorization). `UP-4` is honoured in substance — §12.3 explains why the mechanism differs |
| 7 | `Docs/01-PRD.md` | **No contradiction** | *Invite players to the community with a link or join code* is unchanged. The role matrix places *share the community invitation* with owner and admin, which is exactly §11.2 and §11.4 |
| 8 | `Docs/10-Design-Decisions.md` — `DD-13` | **No contradiction** | The credential remains policy-independent: it works under both `OPEN` and `CODE_REQUIRED` (§4.3) |
| 9 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction** | Nothing statistical touches this table. `SL-4`'s lifecycle concerns membership and community, neither of which this table participates in |
| 10 | **Database Principles** | **No artifact in the repository** | Fifth phase in which this is recorded. Validated against `07-Database-Design.md` §Standards, `SUPABASE_OPERATIONAL_GUIDELINES.md` §2 and §4, `ARCHITECTURE_DECISIONS_V1.md`. **One deliberate departure from the Standards is declared** (§12.2). If a Database Principles document exists outside the repository, this specification has not been checked against it |
| 11 | **Data Domains** | **No artifact in the repository** | Same. §3 states the domain position from first principles |
| 12 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **No contradiction** | §4's checklist is satisfiable: access explicit, authorization via `has_community_role`, no broad read. **This table is the opposite of a public table** — it is the least-readable table in the schema |

### 15.1 Contradiction — `DD-12` and `06-ERD.md` §5 name a column, and this is a table

**Both state that the invitation identifier is `communities.join_code` and that
there is no invitation table.** This specification proposes a table. The letter
of both documents is contradicted.

**What is *not* contradicted — and this distinction is the whole of the
argument:**

| `DD-12`'s substance | Preserved here? |
|---|---|
| **One credential; no second identifier** | **Yes.** One active credential per community (`CI-C5`, `CI-C11`). The link and the typed code carry the same value |
| **Rotation is revocation** | **Yes**, and unchanged (§4.4, §4.5) |
| **Never two codes or none** | **Yes**, and made *structural* rather than relied upon |
| **Membership, matches and registrations are untouched by rotation** | **Yes** (§3) |
| **59 bits of entropy, mistype-safe alphabet** | **Yes**, unchanged |
| **No directed invitation, no pending state** | **Yes** (§0.1, §8) |

**So this is a relocation, not a reintroduction.** The credential does not gain
a sibling; it moves from a column to a row.

**Not resolved silently.** Implementing this table requires the Product Owner
to **amend `DD-12`** — recording that the credential's substance is unchanged
and its location has moved — and to update `06-ERD.md` §5. This is `CI-D0`, the
condition on which this specification's approval rests (§19, §21).

### 15.2 Supersession — the Communities specification

`Communities_Table_Specification.md` v1.0 is an approved Engineering Authority
that specifies `join_code` as one of the nine columns of `communities`.
Implementing this table removes that column, and with it:

| Superseded | Becomes |
|---|---|
| `CM-C6` — join code NOT NULL, unique, 6–32 chars | `CI-C3`, `CI-C4` |
| `CM-C14` — never client-chosen | `CI-C6` |
| `CM-C15` — readable only by owner and admin | §11.2, and **now enforceable** |
| `CM-X2` — unique index on `join_code` | `CI-X1` |
| `CM-D3` — should a member see the code? | **Answered: no.** §11.2 |
| §7's nine columns; §8.2–8.3's alternate key | Eight columns; **no alternate key** — `code` leaves, and `id` becomes the sole candidate key of `communities` |

**That amendment is out of scope for this document** — the brief forbids
designing `communities` — and must be made in that specification, not inferred
from this one. Listed in §20.

### 15.3 Resolution — `CM-R1` closes structurally

The Communities specification records a **High**-severity finding: every
authenticated user can read every community's join code, because the community
row is broadly readable by approved decision (`DD-13`) and a row-level rule
cannot exclude a column. Its own §11.1 concedes that a column privilege
*cannot* express the rule, because privileges are granted to a database role and
cannot see per-community authority — so the fix would need a function or a view.

**Moving the credential to its own table makes the rule an ordinary row-level
predicate**, with no function, no view and no special case. The community row
stays broadly readable, as `DD-13` requires; the credential simply is not on it.

This is the strongest argument in this document and the reason §16 recommends
proceeding.

---

## 16. Engineering Review

**Required by the brief: is the Join Code architecture still the simplest and
strongest solution for the MVP, after all approved Community Domain
decisions?**

### 16.1 The architecture: confirmed, unchanged, and still correct

**Yes.** Nothing decided in the Community Domain since `DD-12` weakens it, and
two decisions strengthen it:

- **`DD-13` separated visibility from joining.** The credential became purely
  an admission mechanism, independent of policy. That made it *more* coherent,
  not less: one value, one job.
- **The Community Members specification forbids invitation state on
  memberships**, and forbids anything referencing a membership row. A pending-
  membership model would violate both. The join code model is the only one of
  the four in §8 that does not.

Re-examined against §8's alternatives, the code still wins on every axis that
matters to this product: the distribution channel, the absence of a state
machine, complete revocation, preview-before-signup, and no scheduler.

**Recommendation: keep the Join Code architecture exactly as approved.**

### 16.2 The location: wrong, and this is the finding

The architecture is right. **Where the credential is stored is not**, for one
reason that is not a matter of taste:

> **The approved rule — the join code is visible only to the Community Owner
> and Community Admin — cannot be enforced while the credential is a column on
> `communities`.**

The two mechanisms PostgreSQL offers each fail on a different half:

| Mechanism | Why it fails |
|---|---|
| **Row-level rule** | Answers *which rows*, never *which columns*. It cannot exclude one column from a row the reader is entitled to see — and by `DD-13` every reader is entitled to see every active community row |
| **Column privilege** | Answers *which columns*, but is granted to a **database role** (`authenticated`). It cannot ask whether the caller is an admin *of this particular community*, which is exactly what the rule requires |

A credential in its own table needs neither: *the caller holds `admin` or above
in this row's community* is an ordinary row-level predicate, and it is the same
shape as every other rule in the schema.

### 16.3 The alternatives, considered fairly

Three ways to satisfy the approved visibility rule without a new table were
examined. **All three work; none is better.**

| Alternative | Verdict |
|---|---|
| **A view over `communities` omitting the code** | **Insufficient on its own.** The base table remains readable, so the code is still reachable unless `SELECT` is also revoked on `communities` and re-granted on the view — which changes every existing read path in the application. And it delivers no rotation record and no extension point |
| **Column-level `SELECT` on `communities`, plus an operation returning the code to an authorised caller** | **This genuinely works, and is the smallest change.** Grant `SELECT` on the eight other columns, withhold it on `join_code`, expose the code through an owner/admin-gated function. **If closing `CM-R1` were the only goal, this would be the recommendation.** It delivers no rotation history, no `created_by`, no expiry and no campaign path — every one of which then becomes a schema change later |
| **Leave it, and accept the exposure** | **Rejected.** It defeats `CODE_REQUIRED` for anyone holding an account, and contradicts an approved Product Rule |

### 16.4 Recommendation

**Keep the architecture. Move the credential.**

The table is recommended over the column-privilege route on the balance of two
facts, and the second is what decides it:

1. Both close `CM-R1`. The table does so with a plain row rule; the alternative
   with a privilege plus a function.
2. **The brief's own future-compatibility list — email, QR, share links,
   campaigns — includes one case (campaigns) that requires several credentials
   per community with independent lifetimes.** That is a row model. Choosing
   the column-privilege route now means choosing it again later, and doing the
   migration then instead — with live credentials in circulation.

**If the Product Owner judges campaigns unlikely**, the column-privilege route
is the smaller change and remains defensible. That judgement is a product one,
and it is `CI-D0`.

---

## 17. Engineering Rationale

### 17.1 A credential is a row because a rule about it must be enforceable

§16.2. Everything else in this design follows from having made the credential a
first-class row; the lifecycle columns, the rotation record and the campaign
path are consequences, not motivations.

### 17.2 Rotation issues a row; it does not rewrite one

The project has decided this shape twice already — `RR-5` (a reversal is a new
row, never an edit) and `UP-4` (administrative actions go to immutable history,
never a mutable column). A credential retired in place leaves no record that it
ever existed, which means no answer to *when did we rotate, and who did it* —
the two questions asked when investigating a leak.

### 17.3 Uniqueness is global and permanent because redemption has no other input

Redemption receives a code and nothing else. Every narrowing of uniqueness —
per community, or among active rows — creates a world in which one code resolves
to two communities at two points in time. `CI-C3` is the only rule that makes
"this link admits you to this community" true forever.

### 17.4 Expiry is derived, not swept

`DD-04` and `DD-05` established that time-dependent state is derived from the
clock rather than stored and maintained, and that the project has no scheduler.
A credential's usability follows the same rule, which is why `expires_at` is a
bound rather than a status.

### 17.5 The join path never writes here

Unlimited use is a product decision (§5.3) with an engineering dividend:
redemption is a pure read, so the credential of a popular community is never a
contention point. A use counter would reverse that on the single hottest path
this table has.

---

## 18. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `CI-R1` | **The table contradicts `DD-12` and `06-ERD.md` §5 as written.** Implementing it without amending them leaves the project with an approved decision its schema does not follow | **High — process, not data** | **Open**, `CI-D0`. §15.1 sets out precisely what is preserved and what must be amended |
| `CI-R2` | **Implementing it changes an approved Engineering Authority.** `Communities_Table_Specification.md` loses a column, an alternate key, four constraints and an index | Medium | **Open.** §15.2 lists every superseded item; the amendment belongs to that document (§20) |
| `CI-R3` | **A live migration moves a credential in circulation.** Every community has a code people are holding; moving it must preserve the exact value, or every outstanding link breaks silently | Medium | **Recorded.** Values must be carried across unchanged; this is a relocation, not a reissue. `DD-12` already caused one deliberate mass invalidation and it should not be repeated by accident |
| `CI-R4` | **`CI-C11`'s *at least one* half is procedural.** Nothing structural prevents a community from having no active credential, which under `CODE_REQUIRED` means nobody can join at all | Medium | **Open**, `CI-D1`. Same posture as `CMB-C4b` |
| `CI-R5` | **The join path gains a join.** Redemption and preview reach the community through this table instead of reading one row | Low | **Accepted.** Both are indexed unique lookups on the code, which is what they already are today |
| `CI-R6` | **Rotation is available to admins, so an admin can invalidate every outstanding invitation** the owner has shared | Low | **Accepted by design**, and unchanged from today. It matches the PRD role matrix; the alternative leaves a known-leaked code live until the owner is available |
| `CI-R7` | **A retired credential is readable by owner and admin forever**, so a code that once circulated remains visible to future admins | Low | **Accepted.** A retired code admits nobody (`CI-C8`), and the history is the point |
| `CI-R8` | **`purge_community` must be verified against the new table.** `DD-12` records the inverse failure — a dropped table whose references broke community deletion in production | Low | **Recorded**, §6.3. The cascade covers it; it must be confirmed, not assumed |

---

## 19. Open Decisions

| ID | Question | Recommendation |
|---|---|---|
| `CI-D0` | **Proceed with the table at all**, amending `DD-12` and `06-ERD.md` §5 — or close `CM-R1` with column privileges and keep the credential on `communities`? | **Proceed with the table**, on §16.4's reasoning: both close `CM-R1`, but only the table supports campaigns without a second migration over live credentials. **If campaigns are judged unlikely, the column-privilege route is smaller and defensible** — this is a product judgement. **Everything else in this specification is contingent on this decision** |
| `CI-D1` | **Enforce *at most one active credential* structurally, accepting that *at least one* stays procedural?** | **Yes**, mirroring the `CMB-D2` recommendation. Consistency between the two invariants is worth more than either choice alone |
| `CI-D2` | **Should revoke-without-replacement exist** — retiring the active credential and issuing nothing, closing the community to new members? | **Not for the MVP.** It is a coherent capability the row model already expresses, but it creates a state that has never existed and whose product meaning (a `CODE_REQUIRED` community nobody can join) needs a Product decision first |
| `CI-D3` | **Ratify the departure from the `created_at`/`updated_at` Standard** (§12.2) | **Ratify.** `revoked_at` is the modification timestamp; `updated_at` would be a copy of it. Worth an explicit decision because the Community Members specification calls the same absence a defect there, on different facts |
| `CI-D4` | **Should a System Administrator be able to read credentials?** | **No**, as specified. It would give support a live secret for every community in the application, which exceeds any established support task. Revisit only against a named support scenario |

---

## 20. Implementation consequences

The table does not exist, so there is no conformance gap to list — there is a
build. What follows is what building it entails **outside this table**, recorded
so none of it is discovered late.

| # | Consequence | Owner |
|---|---|---|
| 1 | **`DD-12` amended** — the credential's substance unchanged, its location moved. `06-ERD.md` §5 updated to match | Product Owner |
| 2 | **`Communities_Table_Specification.md` amended** — `join_code` removed, with `CM-C6`, `CM-C14`, `CM-C15`, `CM-X2`, `CM-D3` superseded and its alternate key retired (§15.2). **Not designed here** | The Communities authority |
| 3 | **Existing credential values carried across unchanged** (`CI-R3`). A relocation must not invalidate a single outstanding link |  Implementing phase |
| 4 | **`purge_community` verified against the new table** (`CI-R8`) | Implementing phase |
| 5 | **`CM-R1` marked resolved** in the Communities specification once implemented | The Communities authority |
| 6 | **Denials asserted in the integration suite** — that a player, a non-member and `anon` cannot read a credential. `SUPABASE_OPERATIONAL_GUIDELINES.md` §4 requires refusals to be tested, not assumed | Implementing phase |

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched, and no other specification was
edited.

---

## 21. Engineering Approval

**Status: Engineering Approved as a design — contingent on `CI-D0`.**

The specification is complete and internally consistent, and it is sufficient
to implement the table without a further engineering decision. **It is
contingent rather than unconditional because it contradicts an approved
decision** (`DD-12`, §15.1). That contradiction is a product-authority matter,
not an engineering one: `DD-12` is the Product Owner's to amend, and until it is
amended this table must not be built.

**What is approved unconditionally**, whatever `CI-D0` decides:

- The **Join Code architecture** is confirmed as still the simplest and
  strongest solution for the MVP (§16.1), and is not redesigned here.
- **`CM-R1` must be closed.** Every authenticated user reading every
  community's credential defeats an approved Product Rule. `CI-D0` chooses the
  mechanism, not whether to act.

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5`; distinguished from both removed tables | ✓ §0 |
| Purpose, business owner, domain ownership | ✓ |
| **Lifecycle of the credential** — generate, distribute, use, rotate / revoke / expire | ✓ §4, every stage |
| **Business responsibilities** — owned and not owned | ✓ §5, 7 + 8 |
| Relationships: incoming, outgoing, ownership, deletion behaviour, lifecycle ownership | ✓ §6 |
| Every column — name, purpose, type, nullability, default, editability, justification | ✓ 8 present + `updated_at` ruled out |
| **Invitation model** — why not email, pending requests, or an acceptance workflow; engineering benefits | ✓ §8 |
| Every business constraint with its reason | ✓ 13 |
| Index strategy *(not requested; included to leave no decision open)* | ✓ §10 |
| Access control: owner, admin, member, non-member, System Administrator × read/create/rotate/revoke/delete | ✓ §11 |
| Audit: all four columns ruled on | ✓ §12 |
| Dependencies both directions | ✓ §13 |
| Future compatibility: email, QR, share links, campaigns | ✓ §14, four of four |
| Validation; contradictions named, not resolved | ✓ 12 sources, **2 contradictions + 1 supersession + 1 resolution** |
| **Engineering review of the architecture**, with alternatives considered | ✓ §16 |
| Open decisions with recommendations | ✓ 5 |
| No SQL, no migration, no implementation, no other table designed | ✓ |

### Validation caveat, stated rather than glossed

The brief names *Database Principles* and *Data Domains* as validation sources.
**Neither exists as a document in this repository** — the fifth phase in which
this has been recorded, and the first in which a specification declares a
deliberate departure from the Standards it was checked against instead (§12.2,
`CI-D3`). If those documents exist outside the repository, this specification
has not been checked against them.

---

## Related documents

| Document | Relationship |
|---|---|
| `Docs/10-Design-Decisions.md` | **`DD-12` — contradicted in letter, preserved in substance** (§15.1). `DD-13` (policy independence), `PD-15`/`PD-16` (attribution is not authorization) |
| `Docs/06-ERD.md` | **§5 — contradicted in letter** (§15.1) |
| `engineering/Communities_Table_Specification.md` | **Parent authority, and superseded in part** (§15.2). Its `CM-R1` is resolved by this design (§15.3) |
| `engineering/Community_Members_Table_Specification.md` | **Sibling.** Strictly separated (§3); `CMB-C4b`'s posture is mirrored by `CI-C11`; §14.5 names the one change that would touch it |
| `engineering/Profiles_Table_Specification.md` | `UP-4` (honoured in substance — §12.3), `UP-5` (naming) |
| `Docs/01-PRD.md` | *Invite with a link or join code*; the role matrix that places sharing with owner and admin |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | No interaction; recorded for completeness |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §2.2 (migration history keeps removed tables — hence §0.1), §4 (denials must be tested) |
| `Docs/07-Database-Design.md` | §Standards — **one declared departure**, §12.2 |
