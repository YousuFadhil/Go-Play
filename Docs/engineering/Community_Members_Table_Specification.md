# Community Membership (`community_members`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** One High-severity defect must be closed; see §19 and §21 |
| Role | **Engineering Authority** for the physical table `public.community_members` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Phase 3.3 |
| Scope | **`public.community_members` only.** `communities`, `matches`, registrations, statistics, ratings and leaderboards appear **only as dependencies** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **This document is the authoritative specification for the physical table
> `public.community_members`.** Where an implementation and this document
> disagree, **the implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation.** It is a design
> record, complete enough that the table can be implemented without taking a
> further engineering decision — except for the items listed as **Open
> Decisions** (§20).
>
> **Precedence above this document.** `Docs/01-PRD.md` and
> `Docs/10-Design-Decisions.md` govern what the product does.
> `engineering/Statistics_Leaderboards_MVP_Specification.md` v2.0 governs
> statistics and leaderboards. Where this document disagrees with any of them,
> **this document is the defect**.
>
> **Sibling authorities.** `Profiles_Table_Specification.md` v2.0 (`users`) and
> `Communities_Table_Specification.md` v1.0 (`communities`). This table is the
> edge between them and inherits from both; every place it does is named.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Community Membership** |
| **Physical table** | **`community_members`** |

The table was created as `group_members` in migration `0002` and renamed in
`0007`, together with its `group_id` column. **The names `group_members` and
`group_id` are retired and must not reappear.**

Singular *Community Membership* is used for one row; *the membership edge* for
the relation. **"Member" alone is ambiguous** — it may mean the person or the
row — and is avoided in normative statements.

---

## 1. Purpose

A Community Membership records that **one person belongs to one community, in
one role**.

It exists for three reasons, and the third is the one that matters most:

1. **It is the many-to-many edge.** A person belongs to several communities; a
   community has many people. Neither side can hold the other, so the relation
   needs its own row.
2. **It carries the role.** The role is a property of neither the person nor
   the community — it is a property of the pairing. The same person is an owner
   here and a player there.
3. **It is the sole source of authority in the entire application.**
   `has_community_role(community_id, user_id, min_role)` reads this table and
   nothing else, and it is the *only* authorization predicate in the project
   (`DD-09`). Every permission question — may this person edit the community,
   create a match, remove a player, see a roster, reissue an invitation — is
   answered by one row of this table.

**What a Community Membership is deliberately not:**

- **It is not a statistics record, and nothing statistical may hang from it.**
  This is the single most important constraint on this table's future, and
  `06-ERD.md` §3.4 states it as *"the single most important statement"* of its
  section. See §5.2 and §16.5.
- **It is not an invitation.** No invitation entity exists — `DD-12` collapsed
  three of them into the community's join code. This table records arrival, not
  the offer that preceded it (§4.1).
- **It is not a history.** It records who belongs **now**. A departure deletes
  the row; nothing remains (§4.5, §5.2).
- **It is not a registration.** Belonging to a community and holding a place in
  one of its matches are different facts, recorded in different tables, with no
  foreign key between them (§6.4).

---

## 2. Business Owner

**Product Owner**, as for every table.

Contents are owned in two distinct halves, and confusing them is the origin of
several of the risks in §19:

| What | Owner | Set by |
|---|---|---|
| **That the row exists** — a person belongs | **The joining rules of the community**, which are `join_policy` and the join code | `create_community`, `join_community`, `join_community_by_code` |
| **That the row is gone** — a person no longer belongs | **The person** (may leave) **or an admin/owner** (may remove) | The self-delete rule; `remove_member` |
| **`role`** | **The community owner**, and only the owner | `set_member_role`, `transfer_ownership` |
| `community_id`, `user_id`, `id`, `created_at` | **The database** | Nothing writes them after insert |

**Note the asymmetry between creation and role.** Anyone may cause a row to
exist — that is what an open community means. **Nobody may choose the role it
is created with**: every join path writes `player`, and the only exception is
the person who creates a community, who becomes its `owner` in the same
transaction (§4.2). Elevation is always a second, separate, owner-authorized
act.

---

## 3. Domain Ownership

**Domain: Community. Position: inside the aggregate, beneath the root.**

| Property | Value |
|---|---|
| Aggregate | **Member of the Community aggregate**, not a root |
| Aggregate root | `communities` |
| Depends on | `communities` **and** `users` |
| Depended on by | **Nothing, by foreign key** — see §15.2 |
| Contains authorization | **Yes — it is the only table that does** |

**It is an associative entity spanning two domains, and it belongs to one of
them.** It references Player Identity (`users`) and Community
(`communities`), but its lifetime, its meaning and its disposal are the
Community's: it cascades with the community, it is scoped by the community, and
it is meaningless outside one. A person deleted from the application also takes
their memberships, but that is the destruction of one endpoint, not ownership
of the edge.

**Why this matters for the statistics architecture.** `SL-4` requires a
player's community record to *survive a departure and be found again on
return*. If Level 2 statistics belonged to this domain object, leaving would
take them away and rejoining would create empty ones — exactly what `SL-4`
forbids. So the boundary is drawn precisely: **this table owns belonging;
`communities` and `users` jointly own everything that outlives belonging**
(§16.5).

---

## 4. Lifecycle

The complete lifecycle, stage by stage, as requested. **Stage 1 produces no
row, and stage 5 destroys one; both facts are load-bearing.**

```
  (1) Invitation  ──optional, produces NOTHING──┐
                                                 ▼
  (2) Join  ──────────────────────────────────▶ ROW CREATED, role = player
                                                 │
  (3) Active Member  ◀───────────────────────────┘
        │
        ├──(4) Role change ──▶ same row, role rewritten
        │
        └──(5) Leave / removal ──▶ ROW DELETED, nothing retained
                     │
                     ▼
              (6) Rejoin ──▶ NEW ROW, new id, new created_at, role = player
```

### 4.1 Stage 1 — Invitation (optional, and stateless)

**No invitation is recorded anywhere.** There is no invitation table, no
pending state and no row in this table. Migration `0012` removed both previous
invitation systems in favour of the community's join code (`DD-12`).

What actually happens: an owner or admin shares the join code — as a link or as
characters to type. Sharing is an act outside the database entirely.

**Three consequences the design must be read with:**

- **An invitation cannot be revoked individually.** Reissuing the community's
  code retires every outstanding invitation at once, because there is only one
  thing to retire (`Communities_Table_Specification.md` §7 column 5).
- **There is no "invited" membership state**, and one must not be added here
  (§9.3). A person is a member or is not.
- **The stage is genuinely optional.** An `OPEN` community is joined with no
  invitation at all.

### 4.2 Stage 2 — Join

Three paths create a row, and no other path may:

| Path | Who | Role written | Guards |
|---|---|---|---|
| `create_community` | The creator | **`owner`** | The row and the community are inserted in one transaction — a community has never existed without its owner membership |
| `join_community` | Any signed-in user | `player` | Community exists and is active; `join_policy` is `OPEN`, else `JOIN_CODE_REQUIRED`; not already a member |
| `join_community_by_code` | Any signed-in user | `player` | Community exists and is active, found **by code alone**; not already a member. Works under **either** join policy — the code is the credential, not the policy (`DD-13`) |

**There is no insert access for any client**, and there must never be one. A
client insert could write any `role` value, which would make role assignment
self-service and defeat `DD-09` entirely.

**Joining is self-service in every path.** Nobody is added by someone else.
This is why `created_by` is not required (§14.3).

### 4.3 Stage 3 — Active Member

**The only state this table has.** A row's existence *is* active membership;
there is no status column and none is needed (§9).

What the row entitles the person to, at this stage:

- To be found by `has_community_role`, and therefore to pass every
  authorization check at or below their role.
- To read the community's roster, its matches and their registrations.
- To be visible to fellow members — this table is what answers tier 2 of `UP-1`
  in the User Profile specification.
- To register for the community's matches, to be assigned to a lineup, and to
  appear in results.
- To be **eligible** for the community's leaderboards, when built (§16.6).

### 4.4 Stage 4 — Role changes

Two operations, and they are not variants of each other:

| Operation | Who may | What moves | Constraints |
|---|---|---|---|
| `set_member_role` | **Owner only** | One row, between `admin` and `player` | Cannot set `owner`. Cannot target the current owner's row. **Cannot change one's own role** |
| `transfer_ownership` | **Owner only** | **Two rows in one transaction**: the caller `owner → admin`, the target `→ owner`; and `communities.owner_id` is re-pointed in the same statement sequence | The target must already be a member. Cannot target oneself |

**Why ownership is not a value `set_member_role` may write.** Ownership is not
a role a person is given; it is a role that *moves*, and it must move as one
transaction so the community is never observable with zero owners or two. A
single-row update could produce either. This is the enforcement of `AR-1`
(§11.2) at the operation level — the schema-level half is missing (`CMB-R2`).

**Role changes are not timestamped.** The table has no `updated_at`, so a role
change leaves no trace of when it happened. This is `CMB-R3` and §14.2.

### 4.5 Stage 5 — Leave and removal

Four paths end a membership, and **they do not have the same consequences.
That is a defect, not a design.**

| Path | Who | Cleans up registrations? | Promotes reserves? |
|---|---|---|---|
| `remove_member` | Owner (admins + players); admin (players only) | **Yes** — delegates to `purge_membership` | **Yes**, with notification |
| `purge_membership` | Internal, via `remove_member` and `admin_delete_user` | **Yes** | **Yes** |
| **Self-departure** — the direct delete permitted to any non-owner | The person themselves | **No** | **No** |
| Cascade — the community or the account is deleted | — | Not applicable; everything goes | — |

**The asymmetry is `CMB-R1`, the most serious finding in this document.** A
person who leaves through the self-departure path keeps every match
registration they held in that community. The registration references the match
and the person — **never the membership** (§6.4) — so nothing removes it. The
result is a confirmed seat held by a non-member, invisible to the roster
because the reading policy hides it, and still counted against the match's
capacity. Meanwhile the identical outcome reached through `remove_member`
releases the seat and promotes a reserve.

**Owner departure is refused, in every path.** `remove_member` raises
`CANNOT_REMOVE_OWNER`; the self-departure rule excludes the owner role. The
owner must transfer ownership first (`PD-12`), because a community with no
owner cannot be managed or deleted by anyone
(`Communities_Table_Specification.md` §4.1).

**Nothing is retained.** No timestamp, no tombstone, no `left_at`. §5.2 and
§14.4 state why, and why adding one would be wrong rather than merely
unnecessary.

### 4.6 Stage 6 — Rejoin

A rejoin is an ordinary join (§4.2). It produces a **new row**, with a new
`id`, a new `created_at`, and role `player` — **regardless of the role held
before**. A former owner who left after transferring ownership and later
rejoins comes back as a player.

**Three properties follow, and all three are correct:**

- **Role is not restored.** Authority is granted by the current owner, never
  inherited from history. Restoring it would let a departed admin regain
  authority without anyone deciding to give it.
- **`created_at` is the *latest* join**, not the first. It is a join timestamp,
  not a tenure record (§14.1).
- **Level 2 statistics and the Community Rating *are* restored** — because they
  never belonged to this table. `SL-4` requires the previous record to be
  reused with no new baseline, and the only way that can hold is if the record
  is keyed by `(player, community)` and is untouched by any of this. This is
  §16.5, and it is the reason §3 draws the domain boundary where it does.

---

## 5. Business Responsibilities

### 5.1 What this table owns

| # | Responsibility | How it is expressed |
|---|---|---|
| 1 | **Membership** — that a person belongs to a community | The existence of the row |
| 2 | **Membership status** | The existence of the row. There is exactly one status and it is not stored (§9) |
| 3 | **Community role** | The `role` column — the only authority statement in the schema |
| 4 | **Join timestamp** | `created_at`, which is the moment of the *current* membership (§14.1) |
| 5 | **Eligibility for community resources** | Evaluated **at read time**, by asking this table. Never a stored flag (§5.3) |
| 6 | **Uniqueness of belonging** — one membership per person per community | The unique pairing (§11.1, `CMB-C3`) |
| 7 | **Authorization scope resolution** — turning *(community, person)* into an authority level | `has_community_role`, which reads this table and nothing else |

### 5.2 What this table does **not** own

Stated as strongly as §5.1, because over-reach here is what breaks `SL-4`:

| # | Not owned | Where it lives | Why not here |
|---|---|---|---|
| 1 | **Community Statistics and the Community Rating** | A Level 2 entity keyed by *(player, community, …)* | **`06-ERD.md` §3.4 and `SL-4`.** A membership is a *current* fact; a statistics record is a *historical* one, and the second outlives the first. If it belonged here, leaving would destroy it and rejoining would create an empty one |
| 2 | **Any history of belonging** | Nowhere. It does not exist | §14.4. A departure deletes the row. If tenure history is ever wanted, it is an append-only table, not a column here |
| 3 | **Leave timestamp** | Nowhere, deliberately | There is no row left to timestamp. §14.4 states what adding one would actually require and cost |
| 4 | **The person** | `users` | A person exists before any community and belongs to several. `UP-5`'s entity sits outside this aggregate |
| 5 | **The community** | `communities` | This row is beneath the root, never beside it |
| 6 | **Match registrations** | `match_registrations`, referencing the match and the person | §6.4 — deliberate, with a consequence (`CMB-R1`) |
| 7 | **Level 1 (career) statistics or the Global Rating** | `player_statistics`, `users.overall_rating` | A career spans every community including ones left (`RR-6`). It has no community dimension at all |
| 8 | **Invitations** | Nowhere — the join code is the whole mechanism | §4.1 |

### 5.3 Eligibility — owned, but never stored

This table owns eligibility for community resources, and owns it as a
**question, not a column**.

- A leaderboard shows active members only, and whether a player appears is
  answered by looking at this table *when the board is read* (`SL-5`,
  `06-ERD.md` §3.4).
- A departure therefore changes eligibility **without altering any statistics
  record** — the record still exists, the player simply stops appearing.
- **No eligibility flag may ever be written onto a Level 2 record**, and none
  onto this table either. `06-ERD.md` §3.4 is explicit: *"eligibility, not
  existence, is what membership governs."*

---

## 6. Relationships

### 6.1 Outgoing — what a Membership depends on

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `communities` | `community_id` | many : 1 | **`CASCADE`** | **Identifying.** The membership is meaningless outside its community and must not survive it |
| `users` | `user_id` | many : 1 | **`CASCADE`** | **Identifying.** A membership held by no one is not a fact about anything |

**Two identifying parents, both cascading.** This is what makes the table an
associative entity rather than an entity in its own right: it has no
independent existence, and destroying either endpoint destroys it. The pair of
columns is also the real key (§10.2).

### 6.2 Incoming — what depends on a Membership

**Nothing. There is no foreign key targeting this table, and there must never
be one.**

This is a design statement, not an observation. §16.5 explains it for Level 2,
but the rule is general:

> **Nothing may reference a membership row.** A membership is deleted on
> departure and recreated on return with a different `id`. Any reference to it
> is a reference that either breaks on departure or silently points at a
> different membership after a rejoin.

The application's other tables reference the **person** and the **community**
independently, which is exactly right: those two facts are stable, and the edge
between them is not.

### 6.3 Ownership, deletion and lifecycle

| Question | Answer |
|---|---|
| **Who owns the relationship's meaning?** | The **community**. A membership says *of this community*; that is its whole content besides the role |
| **Can a membership be reparented?** | **No.** Neither `community_id` nor `user_id` is written by any operation after insert. Moving a membership between communities, or between people, is meaningless — the target would be a different membership |
| **Deletion behaviour — inbound** | Deleting the **community** removes it (cascade). Deleting the **user** removes it (cascade). Neither is refused, because there is nothing to preserve |
| **Deletion behaviour — outbound** | Deleting a membership removes **nothing else**. No cascade fires. This is the direct cause of `CMB-R1`: the cleanup that *should* accompany a departure is procedural, in `purge_membership`, and one departure path skips it |
| **Lifecycle ownership** | The membership's lifetime is bounded by **both** parents and outlives neither. It is *not* bounded by anything below it, because nothing is below it |

### 6.4 The deliberate non-relationship: registrations

**`match_registrations` has no foreign key to this table**, and references the
match and the person separately.

**This is correct and must not change**, for three reasons:

1. **A registration is a fact about a match**, and matches outlive role
   changes. A player promoted to admin mid-week keeps their seat; a foreign key
   to a membership row would make the registration's validity depend on a row
   whose role has changed underneath it.
2. **Registrations must survive what memberships do not.** A completed match's
   registrations are part of the record of that match. A cascade from
   membership would erase a played match's roster the moment someone left.
3. **`SL-4` reasoning applies here too.** Anything bound to a membership row is
   destroyed by a departure. Registrations belong to the historical record.

**The cost, stated plainly:** because there is no foreign key, nothing
*automatically* removes registrations when a membership ends. That cleanup is
procedural, and it is skipped by one of the four departure paths — `CMB-R1`.
The fix is to make every departure path perform the cleanup, **not** to add a
foreign key.

---

## 7. Columns

Five columns exist. **One further column is specified as required and is
absent** — `updated_at`, §7.3.

### 7.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `community_id` | `uuid` | No | none | **Never** |
| 3 | `user_id` | `uuid` | No | none | **Never** |
| 4 | `role` | `text` | No | `'player'` | **System only** |
| 5 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| — | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** | **← required, absent (§7.3)** |

**This table gets one thing right that `communities` gets wrong.** `role` is
already unreachable by any client write: there is **no update policy at all**,
so the only writers are `SECURITY DEFINER` functions. The column-privilege
defect that `CM-R2` records for `communities` does not exist here, because the
row-level rule for updates is *absent* rather than *permissive*.

### 7.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated, never editable**

*Purpose.* Row identity.

*Business justification — and an honest one.* **This column has no reader.**
No foreign key targets it (§6.2); no function looks a membership up by it —
`has_community_role`, `set_member_role`, `remove_member` and `purge_membership`
all address rows by `(community_id, user_id)`; and the application never
selects it. It exists because the table was created with a surrogate key by
convention, and the real key is the pair (§10.2).

*Retained, not defended.* Removing it would be churn with no benefit, and
PostgREST is more predictable with a single-column row identity. But a future
reader should not infer significance from its presence: **the composite is the
key that does the work.**

---

**2. `community_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Which community this membership is in. Half of the real key, and the
first argument of every authorization question in the application.

*Business justification.* Authority is per community and cumulative within one
(`DD-09`); this column is what "within one" means. It is also the scoping
column of the entire Community aggregate — `matches`, and every Level 2 record,
carry the same value for the same reason.

*NOT NULL, no default.* A membership of no community is not a fact. There is no
value to default to; the joining operation knows which community, and nothing
else does.

*Never editable.* Reparenting is meaningless (§6.3).

---

**3. `user_id` — `uuid`, NOT NULL, no default, never editable**

*Purpose.* Who belongs. The other half of the real key.

*Business justification.* It is the User Profile's primary key, which is also
the authentication id — so `has_community_role` compares it directly against
the caller's identity with no lookup, and every "is this me" rule in the
project is a column comparison. That is the property
`Profiles_Table_Specification.md` §7.1 identifies as the reason for the shared
primary key, and this table is one of its principal beneficiaries.

*NOT NULL, no default.* A membership held by nobody is not a fact.

*Never editable.* A membership cannot be transferred to another person. What
looks like a transfer — `transfer_ownership` — moves the *role* between two
rows that already exist; it never moves a row between people.

---

**4. `role` — `text`, NOT NULL, default `'player'`, system only**

*Purpose.* **The authority this person holds in this community.** The only
authorization statement in the schema.

*Business justification.* `DD-09` moved every permission in the application
onto this column, and `06-ERD.md` §4 and `PD-15`/`PD-16` state the corollary:
`communities.owner_id` and `matches.created_by` are never read to grant
anything. One column, one predicate, one place to get it wrong.

*Three values, closed and cumulative* — §8.

*Default `'player'`* — the least-privileged value. Every self-service join path
writes it explicitly, so the default is defence in depth rather than the
mechanism, but it is the right default: a role that arrives by omission must be
the one that grants least.

*System only.* There is **no update policy on this table**, so no client can
write this column by any route. The two writers are `set_member_role` and
`transfer_ownership`, both `SECURITY DEFINER`, both owner-gated. This is
correct and must not be relaxed: a client-writable role column would make the
entire authorization model self-service.

*Not `owner`, from any client-reachable path except community creation.* No
join writes it, `set_member_role` refuses it, and no invitation can confer it
(the dropped invitation table carried the same rule). It arrives exactly twice:
at community creation, and at ownership transfer.

---

**5. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* **The join timestamp** — when this membership began.

*Business justification.* It has a real reader: the roster is ordered by it
ascending, so a community's member list reads oldest-first, which is the order
people expect. It also answers "how long has this person been here", a routine
question for an owner deciding on a promotion.

*It is the timestamp of the current membership, not of first ever contact.*
A rejoin is a new row (§4.6), so a person who left and returned shows the later
date. This is correct for a table that records *belonging now*, and it is a
second reason tenure history — if ever wanted — is a different table (§14.4).

---

### 7.3 `updated_at` — specified as **required**, and absent

**A mutable column with no modification timestamp.**

`role` changes, by two operations, and nothing records when. An owner promoted
a player last month or last year; the table cannot say which, and no other
table records it either.

This is also a **deviation from the project's own stated standard**:
`Docs/07-Database-Design.md` §*Standards* lists *"UUID primary keys,
`created_at` / `updated_at` audit columns"* as the rule for the schema. Every
other table with a mutable column carries both and a `BEFORE UPDATE` trigger to
maintain it. This one does not, and it is the only such table.

*Specification:* `timestamptz`, NOT NULL, default `now()`, maintained by a
trigger, never writer-supplied — identical to every other table in the schema.

Recorded as `CMB-R3` and §21 item 2.

---

## 8. Roles

### 8.1 The approved MVP roles — confirmed

**Exactly three, held per community, and cumulative: `owner` ≥ `admin` ≥
`player`.** This matches the PRD role matrix and `DD-09`, and is confirmed
unchanged by this specification.

Cumulative means a check for `admin` is satisfied by an owner, and a check for
`player` by anyone with a row. `has_community_role` implements this by ranking
the three values and comparing — so there is one ordering, in one place, and a
new role would be a new rank rather than a new set of checks.

### 8.2 `owner`

| | |
|---|---|
| **Purpose** | The person accountable for the community. Its final authority and the only one who can dispose of it |
| **Cardinality** | **Exactly one per community, always** (`AR-1`, `CMB-C4`) |
| **How it is acquired** | Creating the community, or receiving it by `transfer_ownership`. **No other path** |
| **Permissions** | Everything an admin may do, plus: edit community settings (name, description, join policy); change any member's role; remove admins as well as players; transfer ownership; delete the community |
| **Limitations** | **Cannot leave** without transferring ownership first (`PD-12`) — refused by both departure paths. **Cannot be removed** by anyone, including a System Admin acting through `remove_member`. **Cannot change their own role.** Cannot be assigned by `set_member_role` |

**Why the owner cannot simply leave.** Every management operation is gated on
`has_community_role(..., 'owner')`. A community whose owner row is gone has
nobody who satisfies that check, so it cannot be edited, cannot be handed over
and cannot be deleted — by anyone, forever. The refusal is not a courtesy; it
is what keeps the aggregate reachable.

### 8.3 `admin`

| | |
|---|---|
| **Purpose** | Day-to-day organisation. The person who runs matches without being accountable for the community itself |
| **Cardinality** | Zero or more |
| **How it is acquired** | `set_member_role`, by the owner. Also acquired by the *outgoing* owner during `transfer_ownership`, who is demoted to `admin` rather than to `player` — they remain trusted |
| **Permissions** | Everything a player may do, plus: create, edit and delete matches; remove a player from a match; **share and reissue the community's invitation code**; remove **players** from the community |
| **Limitations** | Cannot edit community settings. Cannot change anyone's role. **Cannot remove another admin or the owner.** Cannot transfer ownership or delete the community. **May leave freely** |

**The one asymmetry worth naming:** an admin may reissue the join code but may
not change `join_policy`. They control *the credential*; the owner controls
*the rule*. `Communities_Table_Specification.md` §7 column 6 states the same
split from the other side.

### 8.4 `player`

| | |
|---|---|
| **Purpose** | The ordinary participant. The role the product exists for |
| **Cardinality** | Zero or more |
| **How it is acquired** | **Every self-service join path**, and demotion by the owner |
| **Permissions** | View the community, its roster and its matches; register for and withdraw from matches; be assigned to a lineup; appear in results and on leaderboards; read fellow members' profiles (`UP-1` tier 2) |
| **Limitations** | No management of any kind. Cannot see the join code (`CM-C15`). Cannot remove anyone, including themselves from someone else's match. **May leave freely** |

### 8.5 Roles that are deliberately absent

| Not a role | Why not |
|---|---|
| **System Admin** | It is not a community role and must never appear in this table. It lives in `system_admins`, `has_community_role` knows nothing about it, and it grants **nothing** inside any community (`DD-13`). A System Admin acting on a community does so through gated `SECURITY DEFINER` functions, not by holding a row here |
| `guest`, `pending`, `invited` | There is no partial membership. §9.3 |
| `banned` | Removal is deletion. A ban is a *different* concept — a memory of someone who must not return — and this table holds no memory (§5.2). It would be a new entity, and none is approved |
| Multiple simultaneous roles | The role is a single ranked value. Two roles for one pairing would make `has_community_role` ambiguous, and cumulative ranking already gives every combination the product needs |

---

## 9. Membership States

### 9.1 There are two states, and neither is stored

| State | Represented by | Sub-typed by |
|---|---|---|
| **Non-member** | **The absence of a row** | — |
| **Member** | **The presence of a row** | `role` — `owner`, `admin`, `player` |

**There is no status column, and none may be added.** Membership is existence.
This is a decision, and it is the right one:

- **A status column would need a second uniqueness rule.** The current
  guarantee — one membership per person per community — is a plain unique
  pairing. With a status, "one *active* membership" would need a partial unique
  rule over active rows only, and every authorization read would have to filter
  by status. `has_community_role` is the hottest predicate in the application;
  adding a status test to it adds a way for every permission in the product to
  be wrong.
- **Every intermediate state the product might want is stateless.** *Invited*
  is a shared code (§4.1). *Departed* is the absence of a row. *Eligible* is a
  read-time question (§5.3).
- **`SL-4` needs departure to be total.** A soft-deleted membership would be a
  membership that still exists, and the temptation to hang a statistics record
  from it — the thing `06-ERD.md` §3.4 forbids — returns immediately.

### 9.2 Valid transitions

| From | To | By | Notes |
|---|---|---|---|
| Non-member | Member (`player`) | `join_community`, `join_community_by_code` | The ordinary path |
| Non-member | Member (`owner`) | `create_community` **only** | Atomic with the community's own creation |
| Member (`player`) | Member (`admin`) | `set_member_role`, owner only | Promotion |
| Member (`admin`) | Member (`player`) | `set_member_role`, owner only | Demotion |
| Member (`owner`) | Member (`admin`) | `transfer_ownership` **only** | Never alone — always paired with the line below, in one transaction |
| Member (`admin` or `player`) | Member (`owner`) | `transfer_ownership` **only** | Never alone |
| Member (`admin` or `player`) | Non-member | Self-departure, or `remove_member` | Two paths, **different consequences** — `CMB-R1` |
| Member (any role) | Non-member | Cascade: community deleted, or account deleted | Total |
| Non-member | Member (`player`) | Rejoin | A **new row**. Role is not restored (§4.6) |

### 9.3 Invalid transitions, and what refuses each one

| Invalid | Why it must be refused | Refused by |
|---|---|---|
| Non-member → `owner`, other than by creating the community | Ownership would become claimable rather than granted | No join path writes `owner`; `set_member_role` rejects the value |
| Non-member → `admin` directly | Authority must be a deliberate second act by the owner, never a property of arrival | Same |
| Member → Member (a second row for the same pairing) | Two rows would give one person two roles in one community, and `has_community_role` would return whichever the planner found | The unique pairing (`CMB-C3`), plus the `ALREADY_MEMBER` guard in both join paths |
| `player` → `owner` in one step | Would leave two owners, or none, depending on ordering | `set_member_role` rejects `owner`; only `transfer_ownership` moves it, atomically |
| `owner` → Non-member | The community would become unmanageable and undeletable, permanently | `remove_member` raises `CANNOT_REMOVE_OWNER`; the self-departure rule excludes the owner role |
| Owner changing their **own** role | An owner could demote themselves to `admin`, leaving the community with no owner and no path to one | `set_member_role` raises `CANNOT_CHANGE_OWN_ROLE` |
| Admin removing another admin, or the owner | Peer removal would let one admin unilaterally strip another; owner removal is covered above | `remove_member` requires `owner` to target an `admin` |
| Anyone removing themselves via `remove_member` | Departure is the self-departure path, and conflating them would let the guard for one apply to the other | `remove_member` raises `CANNOT_REMOVE_SELF` |
| Member → "suspended" / "banned" / "pending" | No such state exists (§9.1) | The role vocabulary; the absence of a status column |
| Reparenting a membership to another community or person | Meaningless; the target would be a different membership | Nothing writes `community_id` or `user_id` after insert |

---

## 10. Keys

### 10.1 Primary key

**`id`** — a generated `uuid`.

**It is a surrogate with no consumer** (§7.2). Every constraint, every function
and every query in the application addresses rows by `(community_id, user_id)`;
nothing references this column, inside the database or outside it.

**Specified as retained**, on the narrow grounds that changing a primary key on
a live table is expensive and this one causes no harm. **It is not defended as
the better choice** — see §10.3.

### 10.2 Candidate keys

**Two, and the second is the one that matters.**

| Candidate | Enforced | Assessment |
|---|---|---|
| `id` | Primary key | Generated, immutable, meaningless, and unused |
| **`(community_id, user_id)`** | **Unique** | **The natural key.** Immutable in both columns, NOT NULL in both, and the addressing mode of every operation and every constraint |

### 10.3 Alternate keys

**`(community_id, user_id)` — one alternate key, and the table's real
identity.**

It expresses the central business rule directly: **a person has at most one
membership in a community** (`CMB-C3`). That is not a uniqueness rule bolted
onto a table; it is what the table *is*.

**Whether it should have been the primary key.** It should — a pure associative
entity with an immutable natural key has no use for a surrogate, and the
composite would have made the rule structural rather than an additional
constraint. **This is recorded as an observation, not a change request**
(`CMB-D1`): the composite is already unique, so the guarantee is identical; the
only difference is which index the primary key uses, and swapping it is churn.

### 10.4 Foreign keys

**Outgoing — two, both identifying, both cascading:**

| Column | References | On delete | On update |
|---|---|---|---|
| `community_id` | `communities(id)` | **`CASCADE`** | *no action* |
| `user_id` | `users(id)` | **`CASCADE`** | *no action* |

**Incoming — none, and none may be added** (§6.2).

---

## 11. Business Constraints

### 11.1 Enforced today

| ID | Rule | Why it exists |
|---|---|---|
| `CMB-C1` | **The community must exist** — `community_id` references `communities(id)`, cascading | A membership of a community that does not exist is not a fact. Cascading because the membership is meaningless without its community, and `SL-4` needs departure from the *community* to be total |
| `CMB-C2` | **The player must exist** — `user_id` references `users(id)`, cascading | A membership held by nobody is not a fact. Cascading because a deleted account must not leave authority behind: a stale row would still satisfy `has_community_role` for an id that no longer exists |
| `CMB-C3` | **One membership per person per community** — the pairing is unique | Two rows would give one person two roles in one community, and `has_community_role` would return whichever the planner reached first — a non-deterministic permission. It is also what makes "already a member" a checkable condition rather than a count |
| `CMB-C4a` | **`role` is one of `owner`, `admin`, `player`** | The three approved MVP roles (§8). A fourth value has no rank in `has_community_role`, so it would compare as the lowest and grant player-level authority silently — a failure that looks like a working system |
| `CMB-C5` | **`role` defaults to `player`** | Least privilege. A role that arrives by omission must grant least |
| `CMB-C6` | **`role` is unreachable by any client write** | No update policy exists, so the two owner-gated `SECURITY DEFINER` operations are the only writers. A client-writable role column makes the whole authorization model self-service |
| `CMB-C7` | **No client may insert** | No insert policy exists. A client insert could choose its own `role` |
| `CMB-C8` | **The owner may not leave** — the self-departure rule excludes `role = 'owner'` | A community with no owner cannot be managed, handed over or deleted by anyone (§8.2) |
| `CMB-C9` | **`created_at` is NOT NULL** | It is the join timestamp and the roster's ordering (§7.2) |

### 11.2 Specified here, **not** enforced

| ID | Rule | Why it exists | State |
|---|---|---|---|
| `CMB-C4b` | **Exactly one member holds `owner`, per community, at all times** (`AR-1`) | A community with **no** owner is permanently unmanageable; one with **two** has no answer to who may transfer ownership or delete it. `Communities_Table_Specification.md` §5.3 records this invariant as the aggregate's and states that its structural enforcement *"would live on `community_members`"* — **this document is where that lands** | **Procedural only.** Four operations each behave correctly; nothing prevents a fifth from not doing so |
| `CMB-C10` | **`updated_at` exists and is trigger-maintained** | `role` is mutable and its change is untimestamped; the project's own Standards require the column (§7.3) | **Absent** |
| `CMB-C11` | **Every departure path releases the person's registrations in that community and promotes reserves** | The same real-world event — a person stops belonging — must have one outcome. Today it has two (§4.5) | **Not enforced; one path skips it** — `CMB-R1` |
| `CMB-C12` | **`community_id` and `user_id` are immutable after insert** | Reparenting is meaningless (§6.3). Nothing writes them today, so this is a rule to preserve rather than a gap to close | Held by absence of a writer, not by a constraint |

**On `CMB-C4b`, an honest engineering note.** *At most one owner* is
structurally expressible — a uniqueness rule over the community's owner rows
states it, and nothing can work around it. ***At least one* owner is not.** No
uniqueness or check constraint can require a row to exist; expressing it needs
a trigger or a deferred constraint, and a trigger on this table would fire
during `transfer_ownership`'s intermediate state, where the community
momentarily has zero or two owners inside one transaction.

**Recommendation:** enforce the *at most one* half structurally, which closes
the case a future code path is most likely to cause, and leave *at least one*
procedural — with the guards in `remove_member`, the self-departure rule and
`admin_delete_user` as they already are. Recorded as `CMB-D2` because "half a
structural guarantee" is a decision worth taking deliberately rather than
inheriting.

### 11.3 Deliberately **not** constrained

| Not constrained | Why not |
|---|---|
| A maximum number of members | Capacity is a per-match concept (`DD-06`), never a community-level one. No approved rule sets a community size |
| A maximum number of admins | No approved rule. An owner who wants ten admins is making an ordinary choice |
| A minimum tenure before a role change | Would encode a policy nobody has stated |
| A cooldown before rejoining | Would require remembering that someone left, which this table deliberately does not (§5.2) |
| Anything about the *order* of members | `created_at` gives the roster its order; nothing depends on rank |

---

## 12. Index Strategy

Every query against this table is one of three shapes: *resolve one pairing*,
*list one community's members*, or *list one person's communities*. The index
set is judged against exactly those.

### 12.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `CMB-X1` | **Unique on `(community_id, user_id)`** | **The most important index in the application.** (a) `has_community_role` — every authorization decision in the product, on every request; (b) `is_community_member`, which delegates to it; (c) `set_member_role`, `remove_member`, `purge_membership`, all of which address rows by the pair; (d) `fetchMyRole` — the client resolving its own role on entering a community; (e) the `ALREADY_MEMBER` guard in both join paths; (f) **and, by its leading column alone, every "list this community's members" query** |
| `CMB-X2` | **`(user_id)`** — `community_members_user_id_idx` | (a) `fetchMyCommunities` — the home screen, listing the communities a person belongs to, which is the application's most frequent read after authorization; (b) `admin_delete_user`, which must find every membership an account holds; (c) `UP-1` tier 2 — resolving which profiles a reader may see requires finding the reader's communities. The composite cannot serve these: `user_id` is its *trailing* column |
| `CMB-X3` | **Primary key on `id`** (implicit) | **No query.** It exists because the primary key exists. Listed for completeness, and as the counterpart to §10.1's finding |

### 12.2 Present, and redundant

| ID | Index | Assessment |
|---|---|---|
| `CMB-X4` | **`(community_id)`** — `community_members_community_id_idx` | **Redundant.** `CMB-X1` is a composite whose **leading** column is `community_id`, so it serves every query this single-column index does — roster listings, member counts, the community-scoped reads in `purge_community` — at the same cost for those predicates. A B-tree prefix is usable exactly as if it were an index on the prefix alone |

**Recommendation: drop it.** Unlike `users_phone_idx` — retained in the User
Profile specification because it is merely unused — this one is *duplicated
work on the write path of the application's hottest table*: every join,
departure and role change maintains two structures where one suffices.

`Docs/07-Database-Design.md` lists both `community_members(user_id)` and
`community_members(community_id)` in its index inventory, without noting the
overlap. Recorded as `CMB-R4` and §21 item 3.

### 12.3 Considered and **not** required

| Candidate | Verdict | Reasoning |
|---|---|---|
| `(community_id, role)` | **No** | The plausible query is "list this community's admins", which the product never issues — the roster is fetched whole and the role is rendered per row. `has_community_role` filters by role *after* locating the pairing |
| `(role)` | **No** | No selectivity — nearly every row is `player` — and no query filters by role alone |
| A partial index on owner rows | **Not as an index** | If `CMB-C4b` is enforced, the mechanism is a *uniqueness rule over owner rows*, whose index is a side effect. It would incidentally make "who owns this community" a fast lookup, but that question is already answered by `communities.owner_id` (`PD-15`) |
| `(created_at)` | **No** | The roster orders by it, but only within one community, where `CMB-X1` has already narrowed the set to a handful of rows |

### 12.4 The rule for a future designer

> **This table is addressed by pairing, by community, or by person.** An index
> serving anything else means a query is asking this table a question that
> belongs to `communities`, to `users`, or to a statistics table.

---

## 13. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 13.1 The matrix

| Actor | Read | Insert | Update (`role`) | Delete |
|---|---|---|---|---|
| **Non-member** (signed in) | ✗ **Nothing.** Not even that a community has members | ✗ | ✗ | ✗ |
| **Public** (`anon`) | ✗ Nothing. The invitation preview reports *whether the caller is a member* and never the roster | ✗ | ✗ | ✗ |
| **Member — `player`** | ✓ **Every row of every community they belong to**, including roles | ✗ | ✗ | ✓ **Their own row only** (self-departure) |
| **Member — `admin`** | ✓ Same | ✗ | ✗ | ✓ Own row; and **players** of that community, via `remove_member` |
| **Member — `owner`** | ✓ Same | ✗ | ✓ Via `set_member_role` (`admin` ⇄ `player`, never own, never the owner row) and `transfer_ownership` | ✓ **Admins and players**, via `remove_member`. **Never their own row** |
| **System Administrator** | ✓ Aggregate counts only, via `admin_list_communities`. **No roster read** | ✗ | ✗ | ✓ Transitively — `admin_delete_user`, `admin_delete_community` |

### 13.2 Read

**Membership of a community is what grants sight of its roster**, and nothing
else does. A non-member cannot read a single row, cannot count members, and
cannot discover whether a given person belongs to a given community.

**This table is stricter than `communities`, and that is deliberate.** Every
active community's *row* is visible to every signed-in user (`DD-13`, the one
approved broad-read exception) so that a community can be discovered and an
invitation previewed. **Its roster is not.** Discovery tells you a community
exists; it does not tell you who is in it.

**Two structural notes for the implementing phase:**

- **The read rule must be evaluated through a `SECURITY DEFINER` predicate.**
  A rule on this table that queried this table would recurse — the policy would
  be evaluated to decide whether the policy's own subquery may read a row.
  `is_community_member` exists for exactly this reason, and migration `0002`'s
  comment says so.
- **This table answers `UP-1` tier 2.** The User Profile specification scopes
  profile visibility to *people you share a community with*, which is a
  question about this table's contents. So the two read rules are mutually
  supporting and must be implemented consistently: a change to what counts as
  "sharing a community" here silently changes who can see whose profile.

### 13.3 Insert

**Nobody, by any client route.** Three `SECURITY DEFINER` paths only (§4.2).
The absence of an insert policy is the statement of the rule.

### 13.4 Update

**Nobody, by any client route** — there is **no update policy at all**, which
is stronger than the `users` and `communities` arrangements and is correct
here: not a single column of this table is a user preference. Two owner-gated
`SECURITY DEFINER` operations are the only writers (§4.4).

### 13.5 Delete

**The one place a client writes this table directly.** A signed-in person may
delete **their own** row, provided their role is not `owner` — this is `PD-12`,
the *leave community* rule.

**Two things must be said about it:**

1. **It has no user interface.** `CLAUDE.md` records that the rule is
   implemented and tested in the database and that shipping it without a screen
   is a deliberate decision so far. The absence of a screen is **not** a
   control: the rule is reachable by anyone holding the app's publishable key.
2. **It does not do what `remove_member` does.** This is `CMB-R1`, §4.5 and
   §21 item 1. The rule permits the *deletion*; it cannot perform the
   *cleanup*, because a row-level access rule is a permission, not a procedure.

**The fix is architectural, and stated here so the implementing phase does not
reach for the wrong one:** a departure that must do more than delete a row is
an **operation**, not a permission. The self-departure path should become a
`SECURITY DEFINER` operation that authorizes the caller and then delegates to
`purge_membership` — the same body `remove_member` already delegates to — and
the direct delete rule should be withdrawn. That gives one departure with one
outcome, which is `CMB-C11`.

---

## 14. Audit

| Column | Required? | State | Verdict |
|---|---|---|---|
| `created_at` | **Required** | **Present** | §14.1 |
| `updated_at` | **Required** | **ABSENT** | §14.2 — the gap |
| `created_by` | **Not required** | Absent | §14.3 |
| `updated_by` | **Excluded** | Absent | §14.4 |

### 14.1 `created_at` — required, present

It is the **join timestamp** (§7.2), it orders the roster, and it answers how
long someone has been in a community.

It is *not* a tenure record: a rejoin resets it, because a rejoin is a new
membership (§4.6).

### 14.2 `updated_at` — required, and the one real audit gap

`role` is mutable and its change is untimestamped. Nothing in the schema
records when a promotion or demotion happened — not this table, and not any
other.

**This is the only table in the schema with a mutable column and no
`updated_at`**, and it deviates from the Standards in
`Docs/07-Database-Design.md`. Specified in §7.3; recorded as `CMB-R3` and §21
item 2.

### 14.3 `created_by` — not required

It would record **who admitted this person**. Today that is always the person
themselves: every join path is self-service (§4.2), and `create_community`
makes the creator their own first member. So the column would equal `user_id`
on every row that exists — the same argument that refused `created_by` on
`users` (`Profiles_Table_Specification.md` §11.1).

**The condition under which this changes, stated so it is noticed:** if an
operation is ever added by which *an owner or admin adds someone directly* —
rather than sharing a code and letting them join — then `created_by` stops
being derivable and becomes genuinely informative. No such operation is
approved. Recorded as `CMB-D3`.

### 14.4 `updated_by` — excluded, per `UP-4`; and no `left_at`

**`updated_by` is excluded**, applying `UP-4`. A role change is done *by
somebody else* — `set_member_role` refuses self-changes — so unlike on `users`,
the column would carry real information. **It is refused anyway, on `UP-4`'s
own reasoning:** a mutable column records only the most recent write and is
erased by the next one. An owner promotes a player, later demotes them; the
promotion's author is gone. **An audit that a later legitimate write erases is
not an audit.**

Role changes are discrete, consequential, owner-authorized events — exactly the
shape an append-only record fits, on the pattern `rating_history` already
establishes (`RR-5`). If role-change auditing is ever required, that is the
answer; `community_members` does not change. Recorded as `CMB-D4`.

**`left_at` is likewise excluded, and for a stronger reason: there would be no
row to write it on.** Departure deletes the row. Keeping a departure timestamp
means keeping the row, which means:

- membership becomes a *status* rather than an *existence* — §9.1 explains what
  that costs, and it is charged against `has_community_role`, the hottest
  predicate in the product;
- the unique pairing must be narrowed to active rows only, or a rejoin is
  refused as a duplicate;
- and a departed membership row becomes visible as somewhere to hang a
  statistics record, which `06-ERD.md` §3.4 forbids.

**If tenure history is ever wanted, it is an append-only membership-history
table**, and this table stays as it is. `CMB-D5`.

---

## 15. Dependencies

### 15.1 Tables this table depends on

| Table | Nature | Responsibility |
|---|---|---|
| `communities` | Identifying parent, cascading | Owns the membership's scope, meaning and lifetime. `Communities_Table_Specification.md` §6.2 lists this table as one of its two direct children |
| `users` | Identifying parent, cascading | Owns the person. Supplies the id that is both the membership's other half and the caller's authenticated identity |

**Both must exist before this table can.** It was migration `0002`, immediately
after `users` (`0001`) and in the same file as `communities`.

### 15.2 Tables that depend on this table

**By foreign key: none, and none may be added** (§6.2).

**By behaviour: effectively all of them.** This is worth stating precisely,
because "no foreign key" understates the coupling:

| Dependant | How it depends |
|---|---|
| `communities` | Its update, and every management operation, is gated on `has_community_role`, which reads this table |
| `matches` | Read, create, edit and delete are all gated on it |
| `match_registrations` | Registering requires membership **at the time of registration**; the row is not re-checked afterwards (§16.2) |
| `match_team_assignments` | Reading a lineup requires community membership; writing one requires `admin` |
| `users` | **`UP-1` tier 2** — which profiles a person may read is decided by shared membership |
| Level 2 statistics *(unbuilt)* | **Eligibility only**, at read time. Never existence, never a foreign key (§16.5) |

**Every one of these couplings runs through `has_community_role`**, not through
a foreign key. That is the design: one predicate, one table, one place to be
wrong. It also means a defect in this table's contents is a defect in every
permission in the application simultaneously — which is why `CMB-C4b` matters
more than its severity rating suggests.

---

## 16. Future Compatibility

Each named future, with the reason no redesign of this table is required.

### 16.1 Matches

**Built. No change required.**

A match belongs to a **community**, never to a membership and never to its
creator (`06-ERD.md` §2, `PD-16`). This table supplies the authority to create,
edit and delete one — through `has_community_role` — and nothing else. A match
holds no reference to a membership row, so role changes and departures do not
touch it.

### 16.2 Registrations

**Built. No change required — and one property must be understood rather than
fixed.**

A registration references the **match** and the **person**, never the
membership (§6.4). Membership is checked when the registration is *created* and
is **not re-evaluated afterwards**.

**That is correct for role changes** — a player promoted to admin mid-week
keeps their seat — **and it is the mechanism behind `CMB-R1`**: a departure
that does not explicitly release registrations leaves them in place. The
resolution is `CMB-C11` (every departure path performs the cleanup), **not** a
foreign key, which would destroy a played match's roster whenever someone left.

### 16.3 Team Generation (BTGE)

**Built. No change required, and this table is not in the engine's input
contract at all.**

BTGE's Core Player Inputs are four attributes of a *person* (`KB-006`), read
from `users`; its generation set is the confirmed registrations of one match;
its only auxiliary data is `match_team_assignments` (`BTGE-AX-4`). **Role and
membership are not inputs** — a community admin is not a better footballer, and
`KB-014` forbids inferring anything of the kind.

The single coupling is authorization: generating and saving a lineup is match
management, so it requires `admin` (`is_match_community_admin`). That reads
this table and changes nothing about it.

### 16.4 Results

**Built. No change required.**

`match_results`, `match_goals` and `rating_history` reference matches and
people. Recording a result requires community authority; the recorded facts
carry none. A player who leaves keeps the goals they scored, because the goal
belongs to the match.

### 16.5 Community Statistics, Community Rating and their History (`SL-2`, `SL-3`, `SL-4`)

**Not built. No change required — and this is the section that must not be
misread.**

> **No Level 2 entity may reference this table, and none may cascade from
> it.**

The reasoning, from `06-ERD.md` §3.4 and `SL-4`:

- A Level 2 record is keyed by **`(player, community_id, …)`** — by the two
  endpoints, never by the edge between them.
- **`SL-4` requires the record to survive a departure and be found again on
  return.** A membership row does not survive a departure, and a rejoin creates
  a *different* row with a *different* `id`. A foreign key to it would either
  destroy the record on departure or fail to find it on return — the two exact
  outcomes `SL-4` forbids.
- **A Community Rating is created once, at the neutral baseline, and never
  reset.** "Once, ever" is per *(player, community)*, not per membership. If it
  were per membership, every rejoin would mint a new baseline.
- `06-ERD.md` §3.4 states the ownership rule and warns that *"the natural
  modelling instinct is wrong here"*. This section is that warning applied to
  the table the instinct would attach to.

**What this table does contribute:** eligibility, evaluated when a board is
read (§5.3). Nothing more, and nothing stored.

### 16.6 Leaderboards (`SL-5`)

**Not built. No change required, and no index on this table.**

A board is computed over Level 2 records for one community, then filtered to
**active members** — a read-time question answered by this table, on the
pairing `CMB-X1` already serves — then truncated, then joined to `users` for
display names (`UP-1` tier 2, also this table).

So this table appears twice in a leaderboard query and contributes no measure
to it. **Eligibility is never a stored flag**, here or on the Level 2 record.

### 16.7 The general rule

> **A new column on `community_members` must be a property of the *pairing*,
> must not be a measure, must not need to survive a departure, and must name
> the consumer that reads it.** Anything that must outlive belonging belongs to
> the player and the community jointly — not to the edge.

---

## 17. Validation

Reviewed against each named source. **Contradictions are named, not resolved
silently.**

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | `Docs/01-PRD.md` | **No contradiction** | The three-role matrix matches §8 exactly, including the two asymmetries: *remove a member* is "players only" for an admin and "admins and players" for an owner; *leave the community* is "only after transferring ownership" for the owner |
| 2 | `Docs/06-ERD.md` | **No contradiction** | §1 names this *"the membership edge, carrying the role"*. §2's *"exactly one member per community holds `owner`, always"* is `CMB-C4b` — and this document records that it is **not structurally enforced**, which §2 does not say. **§3.4 is honoured in full** by §5.2 and §16.5 |
| 3 | **Database Principles** | **No artifact in the repository** | Fourth phase in which this is recorded. Validated against `07-Database-Design.md` §*Standards*, `SUPABASE_OPERATIONAL_GUIDELINES.md` §2 and §4, and `ARCHITECTURE_DECISIONS_V1.md`. **If this document exists outside the repository, this specification has not been checked against it** |
| 4 | **Data Domains** | **No artifact in the repository** | Same. §3 states the domain and aggregate position from first principles |
| 5 | `Profiles_Table_Specification.md` v2.0 | **No contradiction; three inheritances** | `user_id` → `users(id)` cascading matches its §5.2 Group A. **`UP-1` tier 2 is answered by this table** (§13.2, §15.2) — the two read rules are mutually supporting. `UP-4` is applied in §14.4 |
| 6 | `Communities_Table_Specification.md` v1.0 | **No contradiction; one invariant transferred** | Its §5.3 records `AR-1` as *"procedural only"* and states that structural enforcement *"would live on `community_members`, which this document does not design"*. **This document is where it lands** — `CMB-C4b`, with an honest account of which half is expressible (§11.2) |
| 7 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction** | `SL-4`'s lifecycle is what §16.5 protects. `SL-5`'s eligibility filter is §5.3 and §16.6 |
| 8 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction** | `RR-6` keeps Level 1 free of any community dimension, so this table is not in its path at all. `RR-5`'s immutable-history pattern is what §14.4 points to for role auditing |
| 9 | `Docs/10-Design-Decisions.md` | **No contradiction** | `DD-09` (role-based authorization), `DD-12`, `DD-13`, `PD-12` (leave), `PD-15`, `PD-16` all hold and are cited |
| 10 | `Docs/07-Database-Design.md` | **One contradiction found** | §17.1 below |
| 11 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **No contradiction** | §4's checklist is satisfied: access is explicit, authorization uses `has_community_role`, enforcement is dual, `SECURITY DEFINER` helpers pin `search_path` and are revoked. This table is **not** broadly readable, so the "one public table" rule is untouched |

### 17.1 Contradiction — the Standards require `updated_at`; this table has none

`Docs/07-Database-Design.md` §*Standards* states the schema's rule as *"UUID
primary keys, `created_at` / `updated_at` audit columns."* This table has
`created_at` and no `updated_at`, while carrying a mutable column that two
operations write.

**Not resolved silently.** Specified as required in §7.3 and `CMB-C10`,
recorded as `CMB-R3`, and listed as §21 item 2.

### 17.2 Contradiction — `PD-12` is implemented as a permission, but departure is an operation

`PD-12` grants a non-owner the right to leave. The database implements it as a
direct row deletion. `remove_member` implements the *same real-world event* as
an operation that also releases registrations and promotes reserves.

**One event, two implementations, two outcomes.** The rule and the procedure
cannot both be complete.

**Not resolved silently.** Specified as `CMB-C11`, recorded as `CMB-R1`, and
listed as §21 item 1 with the architectural fix stated in §13.5.

### 17.3 Observation — the ERD asserts an invariant the schema does not enforce

`06-ERD.md` §2 states *"exactly one member per community holds `owner`,
always"* without qualification. It is true of the system as built, and it is
true only because four separate operations each behave correctly. Recorded as
`CMB-C4b` / `CMB-R2` rather than left as an assertion.

---

## 18. Engineering Rationale

### 18.1 Authority lives on the edge, because that is where it is true

The alternative designs both fail on the same fact: a person's authority is not
a property of the person (they are an owner in one community and a player in
another) and not a property of the community (it differs per person). It is a
property of the pairing, so it lives on the pairing — and because there is
exactly one place it lives, there is exactly one predicate that reads it. A
project with one authorization predicate can be audited; one with several
cannot.

### 18.2 Membership is existence, not status

A status column looks harmless and is not. It would put a filter inside
`has_community_role` — the predicate evaluated on essentially every request in
the product — and it would turn one uniqueness rule into a conditional one. §9.1
sets out the full cost. Every state the product has wanted so far is either the
absence of a row or a read-time question.

### 18.3 Ownership moves as a transaction, never as an assignment

`set_member_role` cannot write `owner`, and this is not an oversight to be
tidied up later. A single-row update can only produce zero owners or two — never
a clean handover. Making transfer its own operation, writing two role rows and
the community's mirror together, is what makes `AR-1` true in practice even
though it is not true structurally.

### 18.4 Nothing may point at a membership row

The row is deleted on departure and recreated on return with a new identity.
Any reference to it is a reference that breaks or, worse, silently resolves to a
different membership later. This single rule is what keeps `SL-4` implementable:
because nothing points here, a Level 2 record can be keyed by the two endpoints
and survive everything this table does.

### 18.5 The table records belonging, and nothing that must outlive it

Statistics, ratings, tenure, bans and departure timestamps are all things that
must survive a departure. None of them is here, and §16.7 states the test that
keeps it that way.

---

## 19. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `CMB-R1` | **Two departure paths, two outcomes.** Self-departure deletes the membership row and nothing else, leaving the person's match registrations in place — a confirmed seat held by a non-member, hidden from the roster by the read rule and still counted against the match's capacity. `remove_member` releases the seat and promotes a reserve. The same real-world event produces different data | **High** — silent data inconsistency, and a match that cannot fill a seat it appears to have | **Open.** Specified as `CMB-C11`; fix stated in §13.5; §21 item 1. **Not currently reachable through the app** (no UI for leaving) but reachable by anyone with the publishable key |
| `CMB-R2` | **`AR-1` / `CMB-C4b` is procedural only.** Nothing structural prevents a community from having zero or two owners; four operations each behave correctly and a fifth need not | Medium | **Open**, `CMB-D2`. Half is structurally expressible (*at most one*) and half is not (*at least one*) — §11.2 |
| `CMB-R3` | **No `updated_at`.** Role changes are untimestamped, in a table where the role is the entire authorization model. Deviates from the project's own Standards | Medium | **Open**, §21 item 2. Specified as `CMB-C10` |
| `CMB-R4` | **A redundant index** on `(community_id)` duplicates the leading column of the unique composite, adding maintenance cost to every write on the application's hottest table | Low | **Open**, §21 item 3. Recommendation: drop |
| `CMB-R5` | **`PD-12` is live without a user interface.** The absence of a screen reads as "not shipped" and is not a control — the rule is reachable directly | Low on its own; it is what makes `CMB-R1` reachable | **Recorded.** Closing `CMB-R1` closes this: the direct delete rule is withdrawn in favour of an operation |
| `CMB-R6` | **A departed person's Level 1 statistics keep counting matches played in a community they left**, correctly (`RR-6`), while their Level 2 record becomes invisible (`SL-4`). Two true figures that will look inconsistent to a user comparing screens | Low | **Accepted by design.** `SL-2` §2.3 forbids any screen from showing both levels, which is precisely what prevents the comparison |
| `CMB-R7` | **The surrogate primary key has no consumer** (§10.1). A future reader may assume it is referenced somewhere and design around it | Low | **Accepted.** Documented in §7.2 and §10.3 rather than changed; `CMB-D1` |
| `CMB-R8` | **A defect in this table's contents is a defect in every permission simultaneously**, because one predicate over one table answers every authorization question in the product | Structural, not a defect | **Accepted — and it is the design.** Named so that changes here are reviewed as security changes, which is what they are |

---

## 20. Open Decisions

Five. Each carries an engineering recommendation; none blocks implementing the
rest of the specification.

| ID | Question | Recommendation |
|---|---|---|
| `CMB-D1` | **Should the primary key be the composite `(community_id, user_id)` instead of the surrogate `id`?** | **No — leave it.** The composite is already unique, so the guarantee is identical; the only gain is conceptual tidiness, and changing a primary key on the application's hottest table is not worth it. Recorded because the observation will recur |
| `CMB-D2` | **Enforce *at most one owner* structurally, accepting that *at least one* stays procedural?** | **Yes.** Half a structural guarantee is worth having: it closes the case a future code path is most likely to cause (a second owner), and the other half is genuinely inexpressible without a trigger that would fire inside `transfer_ownership`'s intermediate state (§11.2) |
| `CMB-D3` | **Will an owner or admin ever add a member directly**, rather than sharing a code? | **Not approved, and not recommended for the MVP** — self-service joining is what makes `created_by` derivable and the join paths simple. If it is ever added, `created_by` becomes required (§14.3) |
| `CMB-D4` | **Is role-change history required?** | **Not for the MVP.** If it ever is, the answer is an append-only table on the `rating_history` pattern — **not** `updated_by` (§14.4, `UP-4`) |
| `CMB-D5` | **Is membership tenure history required** — who was in this community, and when? | **Not for the MVP**, and if it ever is, it is an append-only history table. **Not** a `left_at` column: keeping the row converts membership from existence to status and charges the cost against every authorization check (§14.4, §9.1) |

---

## 21. Conformance — where the built schema differs from this specification

| # | Deviation | Required by | Severity | Notes for the implementing phase |
|---|---|---|---|---|
| 1 | **Self-departure deletes the row without releasing registrations or promoting reserves** | `CMB-C11` | **High** | The fix is architectural, not a bigger policy: make departure a `SECURITY DEFINER` operation that authorizes the caller and delegates to `purge_membership` — the body `remove_member` already uses — and withdraw the direct delete rule. One departure, one outcome. Existing data should be checked for registrations held by non-members before the change |
| 2 | **No `updated_at`** | `CMB-C10`, §7.3 | Medium | Add the column with a `BEFORE UPDATE` trigger, matching every other table. Existing rows take the migration's timestamp, which is honest — the schema does not know when their roles last changed and must not invent it (`UP-2`'s principle) |
| 3 | **Redundant index on `(community_id)`** | `CMB-X4`, §12.2 | Low | Drop. Confirm first that no query plan depends on it, then update the index inventory in `Docs/07-Database-Design.md` |
| 4 | **`AR-1` unenforced** | `CMB-C4b` | Medium | Settle `CMB-D2` first. If approved, enforce *at most one owner per community* structurally; leave *at least one* to the existing operational guards |

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched.

---

## 22. Engineering Approval

**Status: Engineering Approved — conditional.**

This document is complete and is the authoritative engineering specification
for `public.community_members`. It is **conditional** because one
High-severity defect (§21 item 1) exists between this specification and the
schema as built. **Approving this document approves the design, not the current
state of the table.**

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5` | ✓ |
| Purpose, business owner, domain ownership | ✓ |
| **Complete lifecycle** — invitation, join, active member, role changes, leave, rejoin, with what happens at each | ✓ §4, six stages |
| **Business responsibilities** — what it owns and what it does not | ✓ §5, 7 owned + 8 not owned |
| Relationships: incoming, outgoing, ownership, deletion behaviour, lifecycle ownership | ✓ §6 |
| Every column — name, purpose, type, nullability, default, editability, justification | ✓ 5 present + 1 specified-and-absent |
| **Roles** — purpose, permissions, limitations for each; MVP roles confirmed | ✓ §8, three confirmed + four refused |
| **Membership states** — states, valid transitions, invalid transitions | ✓ §9 |
| Keys: primary, candidate, **alternate** (`(community_id, user_id)`), foreign | ✓ §10 |
| Every business constraint with its reason | ✓ 13 |
| Index strategy: every index justified by a named query; the redundant one identified | ✓ §12 |
| Access control: owner, admin, member, non-member, System Administrator × read/insert/update/delete | ✓ §13 |
| Audit: all four columns ruled on | ✓ §14 |
| Dependencies both directions, including the "no foreign key but total coupling" finding | ✓ §15 |
| Future compatibility: matches, registrations, team generation, results, community statistics, leaderboards, community rating | ✓ §16, seven of seven |
| Validation against all named sources; contradictions named, not resolved | ✓ 11 sources, **2 contradictions + 1 observation** |
| Open decisions stated with recommendations | ✓ 5 |
| No SQL, no migration, no implementation, no other table designed | ✓ |

### What must happen before the table is *implementation*-conformant

1. Close §21 item 1 — one departure path with one outcome. **The only High.**
2. Close §21 item 2 — `updated_at`.
3. Settle `CMB-D2`, then close §21 item 4 if approved.
4. Close §21 item 3 — drop the redundant index.

### Validation caveat, stated rather than glossed

The brief names *Database Principles* and *Data Domains* as validation sources.
**Neither exists as a document in this repository** — the fourth phase in which
this has been recorded. Validation used the principles in
`07-Database-Design.md`, `SUPABASE_OPERATIONAL_GUIDELINES.md` and
`ARCHITECTURE_DECISIONS_V1.md`. If those documents exist outside the
repository, this specification has not been checked against them.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Profiles_Table_Specification.md` | **Sibling authority** for `users`. `UP-1` tier 2 is answered by this table; `UP-4` and `UP-5` are applied here |
| `engineering/Communities_Table_Specification.md` | **Parent authority.** Its `AR-1` invariant is enforced — or not — here; its §6.2 lists this table as a direct child |
| `Docs/01-PRD.md` | The three-role permission matrix |
| `Docs/06-ERD.md` | §1 names this the membership edge; **§3.4 is the constraint on its future** |
| `Docs/07-Database-Design.md` | The schema as built; its *Standards* require the `updated_at` this table lacks; its index inventory lists the redundant index |
| `Docs/10-Design-Decisions.md` | `DD-09`, `DD-12`, `DD-13`, `PD-12`, `PD-15`, `PD-16` |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | `SL-4` is why nothing may reference this table |
| `engineering/Results_Rating_Engineering_Decisions.md` | `RR-5` (the append-only pattern), `RR-6` (Level 1 has no community dimension) |
| `engineering/BTGE_Engineering_Specification.md` | §4.1 — membership and role are **not** engine inputs |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §4 security checklist |
