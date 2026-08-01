# Community (`communities`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** Two access-control defects must be closed; see §18 and §19 |
| Role | **Engineering Authority** for the physical table `public.communities` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Phase 3.2 |
| Scope | **`public.communities` only.** `community_members`, `matches`, statistics, ratings and leaderboards appear **only as dependencies** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-01 |

> **This document is the authoritative specification for the physical table
> `public.communities`.** Where an implementation and this document disagree,
> **the implementation is the defect**.
>
> **It contains no SQL, no migration and no implementation.** It is a design
> record, complete enough that the table can be implemented without taking a
> further design decision — except for the items explicitly listed as **Open
> Decisions** (§18).
>
> **Precedence above this document.** `Docs/01-PRD.md` and
> `Docs/10-Design-Decisions.md` govern what the product does.
> `engineering/Statistics_Leaderboards_MVP_Specification.md` v2.0 governs
> statistics and leaderboards. Where this document disagrees with any of them,
> **this document is the defect**.
>
> **Sibling authority.** `engineering/Profiles_Table_Specification.md` v2.0 is
> the authority for `public.users`. The two tables are the only ones whose
> specifications exist; where they touch — `owner_id`, visibility, the
> column-privilege pattern — this document follows it and says so.

---

## 0. Logical entity and physical table

Per `UP-5`, which binds all engineering documentation:

| | |
|---|---|
| **Logical entity** | **Community** |
| **Physical table** | **`communities`** (`public.communities`) |

Unlike the User Profile, the two names agree here and no split is needed. The
table was created as `groups` in migration `0002` and renamed to `communities`
in `0007`; **the name `groups` is retired and must not reappear**, in a
document, a column, a function or a variable. `community_members.community_id`
and `matches.community_id` were renamed in the same migration for the same
reason.

---

## 1. Purpose

The **Community** is the group of people who play football together, and the
container for everything they do: their members, their roles, their matches,
their invitations and — when Level 2 is built — their statistics and their
ratings.

It exists for three reasons:

1. **Amateur football is organised in standing groups, not in one-off
   gatherings.** The same people play weekly. A match belongs to a group of
   people who already know each other, and the group outlives any match.
2. **Every permission in the application is scoped to one.** There is no global
   role in the product. A person is an owner *here* and a player *there*, and
   the community is what "here" means (`DD-09`).
3. **It is the isolation boundary.** A player's record in one community must
   never affect another's figures (`SL-2` §2.2). Making that a property of the
   model rather than a discipline every query remembers requires a first-class
   entity to scope by.

**What the Community is deliberately not:**

- **It is not a venue.** `fields` was in the v2 model and is out of scope
  (`06-ERD.md` §1). A community plays wherever its matches say.
- **It is not a team.** `teams` is likewise out of scope; sides are generated
  per match by BTGE and recorded in `match_team_assignments`.
- **It is not a permission table.** It stores no role. `owner_id` looks like
  authority and is not (`PD-15`, §7 column 2).
- **It is not a tenancy or an organisation.** There is no hierarchy: a
  community has no parent, no children, and no relationship to another
  community. The model is deliberately flat.

---

## 2. Business Owner

**Product Owner**, as for every table in the project.

Ownership of the *contents* is split, and — as on `users` — the split must be
enforced by privilege rather than by convention:

| Field group | Owner | Enforced by |
|---|---|---|
| `name`, `description`, `join_policy` | **The community owner** — these are the settings the PRD role matrix places with the owner alone | Row-level rule + **column privilege (missing — `CM-R2`)** |
| `join_code` | **The system.** Generated on creation, reissued only by `regenerate_join_code` (owner or admin) | Must be withheld from every client write path |
| `owner_id` | **The system.** Written only by `create_community` and `transfer_ownership` | Must be withheld from every client write path |
| `is_active` | **Administration** — deactivation is not a member's act | Withheld |
| `id`, `created_at`, `updated_at` | **The database** | Nothing may write them |

**Who owns an individual community's data** is a separate question with a
separate answer: the person holding the `owner` role in `community_members`.
That is a *runtime* fact, not a schema one, and §5 states what it entitles them
to.

---

## 3. Domain Ownership

**Domain: Community.** The Community is the **aggregate root** of that domain —
§5 states why and what follows.

| Property | Value |
|---|---|
| Aggregate | **Root.** Everything in the Community domain hangs beneath it |
| Depends on | `users` only, and only for `owner_id` |
| Depended on by | `community_members`, `matches` today; the Level 2 statistics entities when built |
| User-scoped | **No.** A community is not owned by a person in the data sense — see below |
| Contains authorization | **No.** It stores no role and grants nothing |

**The relationship to the Player Identity domain is one-directional and thin.**
`communities` names a user in exactly one column, and that column is
attribution and reporting, never authority. The User Profile domain knows
nothing about communities; the Community domain knows one fact about a user.
That asymmetry is deliberate: it is what lets a person belong to many
communities without either domain being scoped by the other
(`Profiles_Table_Specification.md` §3, §13.1).

---

## 4. Lifecycle

### 4.1 Creation

A community is created by a signed-in user through **one path**:
`create_community` (`SECURITY DEFINER`). The operation is atomic and does two
things that must never happen separately:

1. Insert the community row, with the caller as `owner_id`.
2. Insert the caller's `community_members` row with role `owner`.

**A community has never existed without an owner membership, and must not be
able to.** A community whose owner row is missing has nobody who can manage it,
nobody who can delete it, and no route back to a valid state — every management
operation is gated on `has_community_role(..., 'owner')`, which would answer
false forever. This is the single strongest argument for the aggregate-root
design (§5) and it is why creation is an RPC rather than a client insert.

There is **no insert access for any client**, and there must never be one.

### 4.2 Update

Three settings are editable by the owner: `name`, `description`, `join_policy`.
They are written by a direct update, authorized by a row-level rule.

Two further columns change, and neither is a setting:

- `owner_id` moves — only inside `transfer_ownership`, only as the mirror of a
  role change that happens in the same transaction (`PD-15`).
- `join_code` is reissued — only inside `regenerate_join_code`, by an owner or
  an admin.

`updated_at` is refreshed by a trigger on every update from any path.

### 4.3 Deactivation — designed, dormant

`is_active` participates in every read of the table and in all three join
paths: an inactive community is invisible, cannot be joined by id, cannot be
joined by code, and previews as `not_found`.

**No code writes it.** No RPC, no policy and no trigger sets it to false. It
has been true for every row since migration `0002`.

This is the same dormancy the User Profile has (`PR-R4`) and is recorded the
same way: **a known dormancy, not a defect** (`CM-R4`). The column is correct
and the semantics are decided; the operation that would use it — suspending a
community rather than destroying it — has never been requested. §17.2 states
what completing it would require.

### 4.4 Deletion — hard, ordered, owner-only

Deletion is **hard**. There is no archive and no soft delete at this stage, and
there is no delete access for any client.

Two authorized callers, one body:

| Caller | Authorization |
|---|---|
| `delete_community` | The community **owner** — `has_community_role(..., 'owner')` |
| `admin_delete_community` | **System Admin** |
| *(also)* `admin_delete_user` | Purges every community the deleted account owns, because a community with no owner has nobody who can manage it |

All three delegate to **`purge_community`**, which holds the body. One cascade,
several callers, so the administrative path cannot drift from the member path
(`DD-13`).

**The order is not incidental** — §6.4 states it and why each step must precede
the next.

### 4.5 Immutability

`id` is immutable for the life of the row. `created_at` likewise. Neither has a
path that writes it after insert.

---

## 5. Aggregate Root responsibilities

### 5.1 Why the Community is the Aggregate Root

Four properties make it the root rather than merely the biggest table:

1. **Every consistency rule in the domain is scoped to one community and
   crosses more than one table.** *Exactly one owner.* *A member appears once.*
   *A match belongs to a community, never to its creator.* *Registration order
   decides who starts.* None of these can be stated on a single table, and all
   of them are bounded by one community. That is the definition of an aggregate
   boundary.
2. **Authorization is derived from it and from nothing else.**
   `has_community_role(community_id, user_id, min_role)` is the **only**
   authorization predicate in the project (`DD-09`). Every permission question
   is "what is this person inside this community", and the community id is
   always the first argument. A domain whose entire security model keys on one
   entity has already named its root.
3. **It bounds lifetime.** Nothing in the domain outlives its community. A
   deleted community takes its memberships, its matches and everything beneath
   them — and, when built, its Level 2 statistics and ratings (`SL-4`,
   `06-ERD.md` §3.4). Nothing beneath it can exist without it.
4. **It is the isolation boundary the statistics architecture requires.**
   `SL-2` §2.2 makes isolation *normative*: one community's activity must never
   move another's figures. `community_id` on a Level 2 record is what turns
   that from a rule every query must remember into a property of the model.

**The one deliberate non-member of the aggregate is the User Profile.** A
person exists before any community and belongs to several at once, so
`users` sits beside the aggregate, not within it — which is exactly why
`communities` references it and not the reverse.

### 5.2 Operations that must always originate from the Community

The following operations **must take a community id and must be authorized
against it**. None may be reached by any other route, and no future operation
in this domain may bypass the root.

| # | Operation | Who | Why it must originate here |
|---|---|---|---|
| 1 | **Create the community** | Any signed-in user | Creates the root and the owner membership in one transaction (§4.1). There is no valid intermediate state to expose |
| 2 | **Join** — by id, or by code | Any signed-in user | `join_policy` is a property of the root, and the decision to admit is the root's to make (§9, `CM-C7`) |
| 3 | **Regenerate the join code** | Owner, admin | The code is the community's single credential (`DD-12`). Retiring it is a community-level act, not a per-invitation one |
| 4 | **Change settings** — name, description, join policy | Owner | These *are* the root's state |
| 5 | **Manage members** — change a role, remove a member | Owner; admin for players only | A membership has no meaning outside its community; its authority is the root's to grant |
| 6 | **Transfer ownership** | Owner | The one operation that moves the root's identity. Demote and promote occur in one transaction so the community is never observable with zero or two owners |
| 7 | **Create, edit or delete a match** | Owner, admin | A match belongs to a community, never to its creator (`06-ERD.md` §2). Authority to manage it is the community's role, not `created_by` (`PD-07`, `PD-16`) |
| 8 | **Delete the community** | Owner; System Admin | Only the root can order the disposal of its own aggregate (§6.4) |
| 9 | **Read anything community-scoped** | Members, per the read rules | Membership of the root is what makes a roster, a lineup or a board readable |
| 10 | **Write a Level 2 statistic or rating** *(when built)* | The system | Keyed by `(player, community_id, …)`. The community is half the key and the whole of the isolation guarantee (`SL-1`, `SL-2`) |

### 5.3 The invariants the root is responsible for

Stated here because they are the aggregate's, even where they are enforced on a
table this document does not design. **Where an invariant is not structurally
enforced, that is said plainly rather than assumed.**

| # | Invariant | Enforced by | Structural? |
|---|---|---|---|
| `AR-1` | **A community always has exactly one owner** | `create_community` inserts one; `transfer_ownership` demotes and promotes in one transaction; `remove_member` refuses to remove an owner; `admin_delete_user` purges communities the account owns | **No — procedural only.** No constraint prevents zero or two owner rows. See `CM-R3` |
| `AR-2` | **`owner_id` mirrors the member holding `owner`** | `create_community` and `transfer_ownership` write both together | **No.** A direct update to `owner_id` desynchronizes it — see `CM-R2` |
| `AR-3` | **Nothing in the domain outlives its community** | `ON DELETE CASCADE` on both incoming foreign keys, plus the ordered `purge_community` | **Yes** |
| `AR-4` | **A community never spans another community** | There is no relationship between two communities and no column that could hold one | **Yes, by absence** |
| `AR-5` | **Authorization is derived only from `community_members.role`** | `has_community_role` is the only predicate; `owner_id` is never read to grant (`PD-15`) | **Yes, by discipline and review** — the checklist in `SUPABASE_OPERATIONAL_GUIDELINES.md` §4 tests it |

---

## 6. Relationships

### 6.1 Outgoing — what the Community depends on

| Target | Column | Cardinality | On delete | Nature |
|---|---|---|---|---|
| `users` | `owner_id` | many : 1 | **no action** | **Attribution and reporting.** A derived mirror of the owner membership (`PD-15`). Never read to grant or deny anything |

**One outgoing foreign key, and it must never acquire a second** that makes the
community a child of anything. A community has no parent, no venue, no
organisation and no league. `06-ERD.md` §1 states the model as flat and this
column is the only upward reference in it.

**`no action` is load-bearing.** The absence of a cascade is what makes it
impossible to delete a user and silently leave a community with no owner: the
foreign key **refuses**, which forces `admin_delete_user` to purge owned
communities first (`Profiles_Table_Specification.md` §4.4). A cascade here
would destroy communities as a side effect of an account deletion, and
`SET NULL` would produce exactly the ownerless community §4.1 exists to
prevent.

### 6.2 Incoming — what depends on the Community

**Built — two foreign keys, two tables:**

| Table | Column | On delete | Referenced only as |
|---|---|---|---|
| `community_members` | `community_id` | `CASCADE` | Dependency |
| `matches` | `community_id` | `CASCADE` | Dependency |

Two tables that previously referenced it — `invitations` and
`community_invite_links` — were removed by migration `0012` when the join code
became the single invitation identifier (`DD-12`). **Neither returns**, and
§14.2 states why no invitation table is needed again.

Everything else in the domain reaches the community **transitively**, through
`matches`: registrations, lineups, results, goals and rating history all hang
under a match, and a match hangs under a community. That two-level shape is
deliberate — it means the community's disposal logic has two children to order,
not eleven.

**Approved but not built — Level 2 (`SL-2`, `SL-3`, `SL-4`):**

| Future entity | Reference | On delete |
|---|---|---|
| Community Statistics (`E7`) | `community_id` | `CASCADE` |
| Community Rating (`E8`) | `community_id` | `CASCADE` |
| Community Rating History (`E9`) | `community_id` | `CASCADE` |

### 6.3 Dependency ownership

| Question | Answer |
|---|---|
| Which side holds the foreign key? | **The child, always.** `communities` holds one FK upward (`owner_id`) and none downward. It never points at its own children |
| Who owns the relationship's meaning? | **The community.** `community_members` has no meaning without one; a match has no meaning without one |
| Can a child be reparented? | **No.** Neither `community_members.community_id` nor `matches.community_id` is updated by any operation. A match cannot move between communities and a membership cannot be transferred |
| Does the community know its children? | **No, and it must not.** No count, no roster snapshot and no denormalized total lives on this table — §7 and `CM-C11` |

### 6.4 Deletion ownership

**The community owns the disposal of its entire aggregate.** Deletion is
ordered, and the order is a correctness requirement rather than a
tidiness one:

| Step | What | Why it must be here |
|---|---|---|
| 1 | Lock the community row | Serializes concurrent deletions and concurrent transfers of the same community |
| 2 | **Notifications** belonging to the community's matches | `notifications.match_id` is `ON DELETE SET NULL` (`DD-08`), so a notice *survives* its match by design. If the matches went first, there would be no way left to tell which notifications belonged to this community, and they would be orphaned rather than removed |
| 3 | Match registrations | — |
| 4 | **Matches** | This is the step with the largest blast radius; see below |
| 5 | Community members | — |
| 6 | The community row | Anything still pointing at it cascades here |

**Deleting a community rewrites global career figures, and this must not be a
surprise.** Step 4 fires the `BEFORE DELETE ON matches` trigger for every
match, which reverses the result each one produced — every participant's Global
Rating and career counters move back by exactly what that match awarded
(`RR-4`, `RR-5`). This is correct: a match that no longer exists must not still
be counted. But it means **deleting a community changes data belonging to Level
1, which is not community-scoped**, for players who may have left long ago and
for other communities' members who never played here. Recorded as `CM-R5`.

**When Level 2 is built**, its records cascade from `communities` directly and
need no step of their own — unless one of them carries a `SET NULL` reference,
in which case it needs a step *before* the row it points at, for exactly the
reason step 2 exists. That is the rule the implementing phase must apply
(§14.4).

### 6.5 Lifecycle ownership

| Relationship | Whose lifetime bounds whose |
|---|---|
| `users` → `communities` | **Neither bounds the other.** A user outlives the communities they leave; a community outlives an owner who transfers away. The one coupling is that a user cannot be deleted while owning a community — the community must go first, by an explicit act |
| `communities` → `community_members` | **The community bounds the membership**, absolutely. A membership cannot outlive it |
| `communities` → `matches` | **The community bounds the match**, absolutely, and transitively everything under it |
| `communities` → Level 2 records | **The community bounds them** (`A7`). Note the asymmetry `SL-4` requires: a Level 2 record **outlives the membership** that produced it but **not the community** it belongs to. Membership governs eligibility; the community governs existence |

---

## 7. Columns

Nine columns. **No column is added by this specification and none is removed.**

### 7.1 Summary

| # | Name | Type | Nullable | Default | Editable by |
|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Never** |
| 2 | `owner_id` | `uuid` | No | none | **System only** |
| 3 | `name` | `text` | No | none | Owner |
| 4 | `description` | `text` | **Yes** | `null` | Owner |
| 5 | `join_code` | `text` | No | generated | **System only** |
| 6 | `join_policy` | `text` | No | `'OPEN'` | Owner |
| 7 | `is_active` | `boolean` | No | `true` | **Administration only** |
| 8 | `created_at` | `timestamptz` | No | `now()` | **Never** |
| 9 | `updated_at` | `timestamptz` | No | `now()` | **Trigger only** |

*Editable by* carries the same three meanings as in the User Profile
specification: **Owner** = writable by the community owner through a granted
column; **System / Administration only** = reachable only through a
`SECURITY DEFINER` operation; **Never / Trigger only** = nothing writes it
after insert.

> **The table as built does not enforce this column.** A row-level rule cannot
> restrict which columns an update touches, and no column privilege exists on
> this table, so an owner can currently write `owner_id`, `join_code` and
> `is_active` directly. This is `CM-R2`, and it is the same defect `RR-2`
> closed on `users`.

### 7.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated, never editable**

*Purpose.* The identity of the community, and the first argument of every
authorization question in the application.

*Business justification.* A generated surrogate key rather than a natural one,
because there is no natural candidate: `name` is neither unique nor stable
(§8.2). It is a `uuid` rather than a sequence because it appears in shared
URLs and in client-held state, where a guessable identifier would let someone
enumerate communities by counting.

---

**2. `owner_id` — `uuid`, NOT NULL, no default, system only**

*Purpose.* Names the person who owns the community. **For reporting,
attribution and query convenience only.**

*Business justification, and the warning that goes with it.* `PD-15` is
explicit and `06-ERD.md` §4 restates it: **this column is never read to grant
or deny anything.** Authority comes from `community_members.role` through
`has_community_role`, always. The column exists because "who owns this" is a
question asked by the admin console and by `admin_delete_user` (which must find
the communities an account owns before it can remove the account), and
answering it by joining the membership table on a role string is worse than
keeping a mirror.

*It is a derived value.* It mirrors the member holding `owner`, and the mirror
is maintained in exactly one place: `transfer_ownership`, which moves the role
and re-points the column in one transaction. **A write to this column that does
not move the role is a corruption of `AR-2`**, and preventing it is why the
column must be system-only.

*NOT NULL with no default.* A community with no named owner is the state §4.1
exists to prevent. There is no value to default to — the owner is the caller,
and only the creating operation knows who that is.

---

**3. `name` — `text`, NOT NULL, no default, editable by the owner**

*Purpose.* What the community is called. The only thing a prospective member
sees before joining, and the label on every screen that lists it.

*Business justification.* Since `DD-13` every community is visible to every
signed-in user, and an invitation link previews the name to someone who has not
installed the app yet. The name is therefore the community's entire public
presentation, and the reason it has a **minimum** length of 2 as well as a
maximum of 50: a one-character name identifies nothing to a person deciding
whether to join.

*Not unique* — see §8.2, and `CM-C4` for why that is a decision rather than an
omission.

*Editable.* Communities rename themselves. Nothing references the name; every
reference is by `id`.

---

**4. `description` — `text`, NULLABLE, default `null`, editable by the owner**

*Purpose.* Optional free text saying what the community is — where it plays,
who it is for, when.

*Business justification.* It is the only place a community can explain itself
to someone deciding whether to join, and it is optional because most will not
bother and an empty one is not an error. The 200-character bound keeps it a
description rather than a noticeboard; nothing in the product renders long
text.

*Nullable, and null is the only way to say "none"* (`CM-C5`). An empty string
must not be stored as a second way to express absence — the same rule the User
Profile applies to `date_of_birth` and `secondary_position`, where absent and
empty both mean *not supplied* and both become null.

---

**5. `join_code` — `text`, NOT NULL, generated, system only**

*Purpose.* **The community's single invitation credential.** It is the one
identifier that admits a new member, and the invitation link is nothing more
than this code in a URL (`DD-12`).

*Business justification.* Migration `0012` removed two competing invitation
systems — a directed invitation naming a user, and a shareable link carrying
its own token — in favour of this one value. That collapse is what makes
invitation revocation expressible at all: **there is exactly one thing to
retire, so reissuing the code is a complete revocation** (`0015`). With three
identifiers there was no single act that invalidated an invitation.

*Twelve characters from a 31-symbol alphabet* — Crockford-style base32 without
`I`, `L`, `O`, `0` and `1`, which people mistype. About 59 bits. The original
six characters were brute-forceable, which mattered once the code became what
an **unauthenticated** preview accepts. The stored constraint permits 6 to 32
characters so that the historical estate and any future length remain
expressible; 12 is what the generator produces.

*Unique* — see §8.2. Uniqueness is not decoration: redemption looks a community
up **by code alone**, so two communities sharing one would make redemption
ambiguous and admit the caller to whichever the planner returned.

*System only, and this is the same integrity argument as `RR-2`.* A client that
could write this column could choose a guessable code, or one already shared
elsewhere. A credential the holder may choose is not a credential. Generation
belongs to `generate_join_code`, which loops until the value is unused, and
reissue belongs to `regenerate_join_code`.

*It is a secret, and the table currently does not treat it as one.* See §11.1
and `CM-R1` — this is the most serious finding in this document.

---

**6. `join_policy` — `text`, NOT NULL, default `'OPEN'`, editable by the
owner**

*Purpose.* How a person is allowed to join. Two values:

| Value | Meaning |
|---|---|
| `OPEN` | Anyone who can see the community may join it directly |
| `CODE_REQUIRED` | The community is visible and readable, but joining needs the code |

*Business justification.* `DD-13` separated two questions that `is_private` had
conflated: *is the community visible* and *how does someone join it*. Making
them one switch meant a community that wanted to control admission had to hide
itself from discovery, which is the opposite of what a community that wants
members needs. **Visibility is no longer a setting at all** — every active
community is visible — and this column carries what is left, which is the
admission rule.

*Default `OPEN`.* This reverses `DD-11` (private by default) deliberately: the
product's difficulty is getting communities discovered, not hiding them, and a
default that hides is a default that keeps communities empty.

*An unknown value reads as `CODE_REQUIRED`* (`CM-C8`). A policy the application
does not understand must not open the door — the safe reading of an
unrecognized admission rule is the restrictive one.

*Editable by the owner only.* The PRD role matrix places *edit settings* with
the owner alone; an admin may share the invitation and reissue the code, but
may not change who is allowed to use it.

---

**7. `is_active` — `boolean`, NOT NULL, default `true`, administration only**

*Purpose.* Whether the community participates in the application. It gates
every read of the table and all three join paths.

*Business justification.* The same argument as on `users`: destruction is the
wrong primitive for a suspension. A community's matches, results and ratings
are facts about games real people played, and hiding a community without
unmaking them is a capability the product should have. It is also the only
mechanism by which a community could be taken out of circulation without
firing the mass statistics reversal that deletion causes (§6.4, `CM-R5`).

*Withheld from any client's write path.* Deactivating a community is
administrative. An owner who could set it would remove their community from
everyone's view without deleting it, leaving members with memberships they
cannot see.

*Dormant.* See §4.3 and `CM-R4`.

---

**8. `created_at` — `timestamptz`, NOT NULL, default `now()`, never editable**

*Purpose.* When the community came into being. Required audit (§12).

*Business justification.* It is the ordering of every community list the
application shows — both the browse-all screen and the admin console sort by it
— and the only answer to "how long has this community existed", which is a
routine support question.

---

**9. `updated_at` — `timestamptz`, NOT NULL, default `now()`, trigger only**

*Purpose.* When the row last changed. Required audit (§12).

*Business justification.* Maintained by a `BEFORE UPDATE` trigger rather than
by the writer, because there are several writers — the owner's settings update,
`transfer_ownership`, `regenerate_join_code` — and a timestamp each of them
must remember to set is a timestamp one of them will forget.

---

## 8. Keys

### 8.1 Primary key

**`id`** — a single-column generated `uuid`.

A surrogate key, because there is no natural candidate (§8.2). It is the first
argument of `has_community_role`, the scope of every Level 2 record, and the
value carried in shared URLs — so it is generated randomly rather than
sequentially, since a sequential community id would let anyone enumerate the
application's communities by counting upward.

### 8.2 Candidate keys

**Two: `id` and `join_code`.** This table has a genuine alternate key, unlike
`users`.

| Attribute | Candidate key? | Reasoning |
|---|---|---|
| `id` | **Yes — primary** | Generated, immutable, meaningless, stable |
| `join_code` | **Yes — alternate** (§8.3) | Unique by constraint, NOT NULL, and used as a sole lookup key by two operations |
| `name` | **No** | Not unique, and mutable. See `CM-C4` |
| `(owner_id)` | **No** | One person may own several communities |
| `(owner_id, name)` | **No** | Would make "one person cannot have two communities with the same name" a rule. Plausible, but no approved document states it, and inventing it would be taking a Product Decision in a schema |

### 8.3 Alternate keys

**`join_code` — one alternate key.**

It qualifies on the definition: NOT NULL, unique, and sufficient on its own to
identify a row. It is not decorative — `join_community_by_code` and
`preview_community_invite` both look a community up **by code alone**, with no
other predicate, which is precisely the use of an alternate key.

**But it differs from the primary key in two ways that matter, and treating
them as interchangeable is an error:**

- **It is mutable by design.** `regenerate_join_code` replaces it, and that is
  the entire revocation mechanism (`DD-12`). Nothing may store it as a
  reference to a community — a stored code is a reference that silently stops
  resolving, or worse, later resolves to a different community.
- **It is a credential.** The primary key identifies; this one *admits*.
  Knowledge of it is a capability, which is why §11.1 restricts who may read
  it, and why no foreign key anywhere targets it.

### 8.4 Foreign keys

**Outgoing — one:**

| Column | References | On delete | On update |
|---|---|---|---|
| `owner_id` | `users(id)` | **no action** | *no action* |

**Incoming — two**, catalogued in §6.2. Both target `id`; **nothing targets
`join_code` and nothing may.**

---

## 9. Business Constraints

Every business rule the table carries, why it exists, and whether the database
enforces it today.

### 9.1 Enforced

| ID | Rule | Why it exists | Category |
|---|---|---|---|
| `CM-C1` | **Primary key on `id`** | One row per community. Every authorization decision and every Level 2 record keys on it | Identity |
| `CM-C2` | **`owner_id` references `users(id)` with no cascade** | A community must name a real person, and the *absence* of a cascade is what makes an ownerless community unreachable: deleting the user is refused until the community is disposed of (§6.1) | Ownership |
| `CM-C3` | **`name` is NOT NULL, 2–50 characters after trimming** | Every community is identifiable to a person deciding whether to join. The minimum exists because a one-character name identifies nothing; the maximum because every list renders it on one line | Presentation |
| `CM-C4` | **`name` is NOT unique** — deliberately | Two communities may legitimately be called *Friday Football*. A global uniqueness rule would let whoever registered first own a common name for everybody, and a community name is a display label, not an identifier. Ambiguity is resolved by the description and by who invited you, not by the schema | Uniqueness |
| `CM-C5` | **`description` is optional, at most 200 characters** | Optional because most communities will not write one and an empty one is not an error. Bounded because nothing in the product renders long text | Presentation |
| `CM-C6` | **`join_code` is NOT NULL and unique, 6–32 characters** | Redemption looks a community up **by code alone**. Two communities sharing one would make redemption ambiguous and admit the caller to whichever the planner happened to return. NOT NULL because a community with no code cannot be joined by link or by dialog — which, under `CODE_REQUIRED`, means it cannot be joined at all | Invitation |
| `CM-C7` | **`join_policy` is NOT NULL, one of `OPEN` or `CODE_REQUIRED`, default `OPEN`** | The admission rule, separated from visibility by `DD-13`. Constrained to a closed vocabulary because the joining functions branch on it, and a value they do not recognise has no defined behaviour | Visibility / joining |
| `CM-C8` | **An unrecognised `join_policy` is treated as `CODE_REQUIRED`** | Defensive, and stated as a rule rather than left to a branch: a policy the application does not understand must not open the door. This is the safe reading, and `DD-13` records it | Visibility / joining |
| `CM-C9` | **`is_active` is NOT NULL, default true, and gates every read and every join path** | One switch, consulted everywhere, so that "this community is out of circulation" cannot be true on one screen and false on another | Lifecycle |
| `CM-C10` | **`created_at` and `updated_at` are NOT NULL** | §12 | Audit |

### 9.2 Specified here, **not** enforced today

These are business rules the product holds that the schema does not yet state.
Each follows the precedent `UP-2` and `UP-3` set for the User Profile: a rule
enforced only above the database is a rule a direct PostgREST call does not
obey.

| ID | Rule | Why it exists | State |
|---|---|---|---|
| `CM-C11` | **The stored `name` is the trimmed name** | `CM-C3` validates `char_length(trim(name))`, so `"  AB  "` passes while storing four characters of whitespace around two of content. Migration `0002` trimmed on insert; the `0016` rewrite of `create_community` dropped the `trim` and nothing replaced it. Validating one form and storing another means the constraint does not describe the data | **Regression.** Trimmed on insert until `0016`, not since |
| `CM-C12` | **`description` is null when absent, never an empty string** | Two ways to express "no description" is one too many: every reader must then test both, and one of them will be forgotten. The User Profile specification already fixed this reading for its optional fields | Not enforced |
| `CM-C13` | **`owner_id` changes only together with the `owner` role** (`AR-2`) | The column is a mirror. A write that moves the mirror without moving the thing it reflects produces a community whose reported owner cannot manage it and whose real owner is invisible to the admin console. Today an owner can do exactly this with one request | Not enforced — `CM-R2` |
| `CM-C14` | **`join_code` is never client-chosen** | A credential the holder may choose is not a credential. The generator's uniqueness loop and its entropy are the whole of the code's strength, and both are bypassed by a direct write | Not enforced — `CM-R2` |
| `CM-C15` | **`join_code` is readable only by the community's owner and admins** | It is the credential. A community with `CODE_REQUIRED` is asserting that admission needs something not everyone has; if every signed-in user can read every code, the policy admits everyone with an account | Not enforced — `CM-R1` |
| `CM-C16` | **Exactly one member holds `owner`, at all times** (`AR-1`) | A community with no owner cannot be managed or deleted by anyone; one with two has no answer to "who may transfer ownership". Enforced procedurally today by four separate operations each doing the right thing | Not structurally enforced — `CM-R3`. *Note: any structural enforcement would live on `community_members`, which this document does not design* |

### 9.3 Constraints deliberately **not** specified

| Not constrained | Why not |
|---|---|
| `name` uniqueness, globally or per owner | `CM-C4`. Would let the first registrant own a common name for everyone |
| A maximum number of communities per owner | No approved rule. A quota is a Product Decision, and inventing one in a schema takes it silently |
| A maximum number of members, or of matches | Same. Capacity is a per-match concept (`DD-06`), never a community-level one |
| A minimum membership before a community is "real" | A community with one member is a community that has just been created. Every community passes through that state |
| `description` character class or minimum length | Bilingual product; any restriction would be a guess |
| Any relationship between two communities | The model is flat by decision (§1). A parent, a league or a federation is a new entity, not a column |

---

## 10. Index Strategy

Like `users`, this table is small and accessed by key. The PRD's success
criteria are three active communities; the design targets correctness of access
paths, not scale.

### 10.1 Required

| ID | Index | Queries it supports |
|---|---|---|
| `CM-X1` | **Primary key on `id`** (implicit, unique) | (a) every `has_community_role` evaluation reaches the community by id; (b) `fetchCommunity` — the details screen; (c) the two incoming foreign keys' referential-integrity checks; (d) the row lock taken by `transfer_ownership`, `regenerate_join_code` and `purge_community`; (e) `join_community` by id; (f) every future Level 2 record's foreign key |
| `CM-X2` | **Unique on `join_code`** (implicit in the uniqueness constraint) | (a) `join_community_by_code` — redemption, which looks up by code alone; (b) `preview_community_invite` — the unauthenticated invitation preview, the application's only anon entry point; (c) `generate_join_code`'s collision check, which loops until the candidate is unused. **This index is not merely a uniqueness artefact — it is the access path for the entire invitation flow** |

### 10.2 Required, with a narrower justification than it appears to have

| ID | Index | Assessment |
|---|---|---|
| `CM-X3` | **`(owner_id)`** — `communities_owner_id_idx` | **One reader:** `admin_delete_user`, which must find every community an account owns before it can remove the account. That path is rare but its correctness is not optional, and without the index it is a sequential scan inside an already-heavy administrative transaction. `admin_list_communities` also names `owner_id`, but it joins to `users` on *that* table's primary key and does not use this index. **Retain** — one real reader is a justification, and this one cannot be removed |

### 10.3 Considered and **not** required

| Candidate | Verdict | Reasoning |
|---|---|---|
| `(is_active)` | **No** | Read by every policy evaluation, but with no selectivity — essentially every row is true. An index that matches everything is pure write cost |
| `(created_at DESC)` | **No** | Both community lists order by it, and the admin console does too. Sorting a few hundred rows is cheaper than maintaining an index. Revisit on measurement |
| `(join_policy)` | **No** | No query filters by it. It is read *after* a row has been located, to decide whether to admit |
| Trigram / `pg_trgm` on `name` | **No, for the MVP** | `admin_list_communities` searches with a leading wildcard, which no B-tree serves. System Admin path, capped at 100 rows. Sequential scan is the right plan |
| `(name)` | **No** | Nothing looks a community up by name — deliberately, since `CM-C4` makes the name non-unique and therefore not a lookup key |
| Anything supporting membership counts | **No, and never** | A count is a query over `community_members`, not a property of this table. `CM-C11`'s neighbour rule: no denormalized total lives here (§6.3) |

### 10.4 The rule for a future designer

> **An index on `communities` must name the query it serves.** The table is
> reached by primary key, by join code, and — for one administrative
> operation — by owner. A filter or sort over any other column is a sign the
> query belongs on a child table.

---

## 11. Access Control

Stated as **rules, not policy expressions**. No RLS SQL is designed here.

### 11.1 Read

**A community's row is visible to every signed-in user; its join code is
not.** These are two different rules and the table currently implements only
the first.

| Tier | Who | May read |
|---|---|---|
| **Public (`anon`)** | Not signed in | **No direct read of the table at all.** The only public surface is `preview_community_invite`, which takes a code and returns four values — a state, the community's id and name, and whether the caller is already a member. Never the roster, the matches, the owner, or **the code itself** |
| **Authenticated** | Any signed-in user | **Every active community's row, excluding `join_code`.** This is the approved broad-read exception — see below |
| **Member** | A member of the community | The same as any authenticated user. Membership grants no extra column here; what it grants is access to the community's *children* |
| **Owner / Admin** | `has_community_role(..., 'admin')` | The same, **plus `join_code`** — `CM-C15` |
| **System Admin** | Through `SECURITY DEFINER` functions only | The full estate, via `admin_list_communities` |

**Why the broad row read is correct, and approved.** `DD-13` makes every
community visible: hiding communities from discovery is the opposite of what a
product struggling to get communities found needs, and an invitation link must
preview before the recipient has an account.
`SUPABASE_OPERATIONAL_GUIDELINES.md` §4 names `communities` as *the one* table
broadly readable by `authenticated` without a membership predicate, with a
recorded reason. **That statement is now accurate again**: `UP-1` removed
`users` from the same category, leaving exactly one approved exception, which
is this table.

**Why `join_code` must be carved out of it.** The code is the credential
(`DD-12`, §7 column 5). Under the rule as built, any signed-in user can read
the join code of every community in the application, which means
`CODE_REQUIRED` restricts nobody who has an account. `preview_community_invite`
was written deliberately never to return the code — and the table hands it out
directly. This is `CM-R1`, the most serious finding in this document.

**A note for the implementing phase, without designing the mechanism.** A
column privilege cannot express this rule: privileges are granted to a *role*
(`authenticated`), and this rule is about the caller's role *within a specific
community*, which a grant cannot see. The implementation will therefore need
either a function that returns the code to an authorized caller, or a view that
omits it — not a `GRANT`. That is a genuine difference from how `users`
protects `overall_rating`, and stating it here prevents the obvious wrong
approach.

### 11.2 Insert

| Who | May insert |
|---|---|
| Every client role | **Nobody**, and this must never change |

The only creator is `create_community` (`SECURITY DEFINER`), because the row and
its owner membership must be created together or not at all (§4.1). A client
insert would produce a community nobody can manage.

### 11.3 Update

Two layers, as on `users`, answering two different questions:

| Layer | Question | Rule |
|---|---|---|
| **Row-level rule** | *Which rows?* | Only the **owner** of that community — `has_community_role(id, auth.uid(), 'owner')`. Not an admin, not a member |
| **Column privilege** | *Which columns?* | **Exactly three: `name`, `description`, `join_policy`.** Everything else is system-managed or immutable |

**The second layer does not exist today**, which is `CM-R2`. Its absence means
the owner of a community can currently write `owner_id` (desynchronizing the
`PD-15` mirror from the real owner), `join_code` (choosing a weak or
already-known credential) and `is_active` (hiding their own community). The
argument is the one `RR-2` already made and won on `users`: **a row rule
answers which rows, never which columns**, and the fix is privilege, not a
cleverer predicate.

**System write paths**, each `SECURITY DEFINER` and subject to neither layer:

| Operation | Writes | Authorized to |
|---|---|---|
| `create_community` | The whole row | Any signed-in user |
| `transfer_ownership` | `owner_id`, with the two role rows | Owner |
| `regenerate_join_code` | `join_code` | Owner **and admin** — both share invitations, so both may retire one |

### 11.4 Delete

| Who | May delete |
|---|---|
| Every client role | **Nobody** |
| `delete_community` | The **owner** |
| `admin_delete_community` | **System Admin** |
| `admin_delete_user` | Transitively, for communities the deleted account owns |

All delegate to `purge_community` (§6.4). No cascade from `users` can reach
this table — that is `CM-C2`.

### 11.5 Summary by actor

| | Read row | Read `join_code` | Insert | Update settings | Transfer / reissue | Delete |
|---|---|---|---|---|---|---|
| **Public (`anon`)** | ✗ *(preview by code only)* | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Authenticated non-member** | ✓ active only | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Member (player)** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Admin** | ✓ | **✓** | ✗ | ✗ | Reissue code only | ✗ |
| **Owner** | ✓ | **✓** | ✗ | **✓** (3 columns) | **✓** both | **✓** |
| **System Admin** | ✓ via RPC | ✓ via RPC | ✗ | ✗ | ✗ | **✓** |

Two rows of this table describe rules the schema does not yet enforce — the
`join_code` column for everyone below Admin (`CM-R1`), and the three-column
limit on the owner's update (`CM-R2`).

---

## 12. Audit

| Column | Required? | State | Reasoning |
|---|---|---|---|
| `created_at` | **Required** | Present | The ordering of every community list in the product, and the answer to "how long has this existed" — a routine support question with no other source |
| `updated_at` | **Required** | Present | Several writers touch this row — the owner's settings update, `transfer_ownership`, `regenerate_join_code`. Trigger-maintained, because a timestamp each writer must remember is one a writer will forget |
| `created_by` | **Not required for the MVP — but see below** | Absent | §12.1 |
| `updated_by` | **Excluded** | Absent | §12.2 |

### 12.1 `created_by` — the one audit column that would carry real information

On `users`, `created_by` was refused outright because it would equal the primary
key on every row that will ever exist. **The argument does not transfer here.**

`owner_id` names the *current* owner, and ownership moves. After a transfer,
nothing records who founded the community. That is genuinely
non-derivable information, so refusing the column on the `users` reasoning
would be wrong.

**It is nonetheless not required, on a different and weaker argument: no
consumer asks for it.** No screen, no RPC, no report and no approved document
references the founder of a community. Adding a column against a hypothetical
reader is how tables accumulate fields nobody can later explain.

Recorded as an **open decision** (`CM-D1`, §18) rather than a refusal, because
unlike `updated_by` it is defensible and cheap, and because the moment to add
it is before communities accumulate history — a column added later is null for
every community that already exists, permanently.

### 12.2 `updated_by` — excluded, per `UP-4`

**Approved for `users` as `UP-4`; the reasoning is table-independent and is
applied here.**

> Administrative and ownership actions are recorded using immutable history,
> never a mutable column.

A mutable `updated_by` records only the most recent write and is erased by the
next one. An owner transfers the community, then edits the description; the
transfer's actor is gone. **An audit that a later, unrelated, legitimate edit
erases is not an audit.**

The events on this table that would ever need an actor are ownership transfer
and join-code reissue — both discrete, both consequential, both exactly the
shape an append-only record fits. If either is ever required to be auditable,
the answer is a history table on the pattern `rating_history` already
establishes (`RR-5`), and `communities` does not change. Recorded as `CM-D2`.

---

## 13. Dependencies

### 13.1 Tables the Community depends on

| Table | Nature | Ownership responsibility |
|---|---|---|
| `users` | Referenced by `owner_id`, no cascade | **The Community owns the reference; `users` owns the person.** The community must name a live account, and the account cannot be removed while it does. `users` knows nothing of communities and takes no responsibility for one — the coupling is entirely on this side |

**Nothing else.** `communities` requires only `users` to exist, which is why
`groups` was migration `0002`, immediately after `0001`.

### 13.2 Tables that depend on the Community

**Built:**

| Table | Ownership responsibility |
|---|---|
| `community_members` | **The Community owns its existence and its meaning.** A membership cannot be created, moved or survive without one. The community does **not** own who is a member — that is the joining rules' business — but it owns that they are a member *of it* |
| `matches` | **The Community owns its existence, its lifetime and its authority.** A match belongs to a community and never to its creator; who may manage it is a community role (`PD-07`, `PD-16`) |

**Transitive dependants** — `match_registrations`, `match_team_assignments`,
`match_results`, `match_goals`, `rating_history`, `notifications` — reach the
community through `matches`. **The community owns their lifetime** (they are
disposed of when it is) **and none of their meaning** (each belongs to its
match).

**Approved, not built:** Community Statistics, Community Rating and Community
Rating History (`SL-2`, `SL-3`). The Community will own their existence and
their isolation; it will **not** own their creation, which `SL-4` binds to the
player's first join.

### 13.3 What the Community does *not* own

Stated explicitly because the aggregate-root role invites over-reach:

- **It does not own the person.** `users` sits outside the aggregate (§3).
- **It does not own Level 1 statistics.** A career spans every community,
  including ones the player has left (`RR-6`). Deleting a community *moves*
  Level 1 figures — by reversing the results it destroys — but it does not own
  them, and that distinction is exactly why `CM-R5` is worth recording.
- **It does not own authorization.** It is the *scope* of every authorization
  question; the answer lives in `community_members.role` (`AR-5`).

---

## 14. Future Compatibility

Each of the six named futures, with the reason no redesign of this table is
required.

### 14.1 Community Members

**Built. No change required.**

The membership edge already carries the role, is unique per
`(community_id, user_id)`, and cascades with the community. Every future
membership question — a fourth role, a join request queue, a per-member setting
— is a column or a table on *that* side. The community supplies the scope and
nothing else, which is why `AR-5` holds: authority is read from the membership,
never from a column here.

### 14.2 Invitations

**Built as the join code. No change required, and no invitation table
returns.**

`DD-12` collapsed three invitation systems into one credential on this row. The
extension points are already present:

- **Revocation** is reissue, and exists (`regenerate_join_code`).
- **A link** is the code in a URL; it needs no storage.
- **Preview before signup** exists and is the application's only anon entry
  point.

Two futures that would *not* fit this row, stated so they are recognised as new
entities rather than attempted as columns: **multiple simultaneous codes**
(per-campaign invitations) and **a per-invitation expiry or use limit**. Both
are per-invitation state, and a row that holds one code cannot hold state about
several. Each would be a new table referencing `communities` — additive, and
neither is approved.

### 14.3 Matches

**Built. No change required.**

A match already belongs to a community and cascades with it. Nothing about a
match is stored here — not a count, not the last match date, not a schedule.
That is `CM-C11`'s neighbour rule (§6.3, §10.3) and it is what keeps the
Community Dashboard's *Total Matches* and *Last Match Date* a query rather than
two columns that can silently disagree with the matches themselves.

### 14.4 Community Statistics — Level 2 (`SL-1`, `SL-2`)

**Not built. No change required.**

A Level 2 record is keyed by `(player, community_id, period_type, period_key)`.
This table supplies `community_id`, and it already does — as a primary key a
foreign key can reference with `ON DELETE CASCADE`.

**Three rules keep it true:**

1. **No counter is copied onto `communities`.** Not total matches, not member
   count, not goals. Every one would be a second answer to a question the
   statistics model already answers.
2. **No period dimension appears here.** A period is a property of a Level 2
   record (`06-ERD.md` §3.5), not of the community. Adding a "current season"
   column would make the community stateful about time and break `SL-1`'s
   one-model design.
3. **Any new child must be placed correctly in the disposal order.** It
   cascades from `communities` and needs no explicit step — **unless** it holds
   a `SET NULL` reference to something else being deleted, in which case it
   needs a step before that thing, for the reason notifications do (§6.4).

### 14.5 Community Rating (`SL-3`, `SL-4`)

**Not built. No change required — and one column must never be added.**

**The Community Rating must not live on this table**, in any form. It is one
value per *(player, community)* pair; a column here holds one value per
community, which is the wrong cardinality by an entire dimension. This is the
mirror of the rule the User Profile specification states (§13.1 there): the
rating belongs to neither of its two owners alone.

The baseline `SL-4` requires — `5.00`, never reset, preserved on departure and
resumed on return — is entirely a property of the Level 2 entity. The community
contributes its identity and its isolation, nothing more.

### 14.6 Leaderboards (`SL-2` §2.3, `SL-5`)

**Not built. No change required, and no index on this table.**

A board is computed over Level 2 records filtered by `community_id`, then
truncated, then joined for display names. This table appears in that flow only
as the scope — one row, fetched by primary key, to render the community's name
in a header.

Eligibility (who may appear) is a read-time filter over `community_members`,
never a stored flag — so no eligibility column belongs here either.

### 14.7 The general rule

> **A new column on `communities` must be a property of the community itself,
> must not be derivable from its children, must not be per-member or
> per-period, and must name the consumer that reads it.** Anything failing one
> of those four tests belongs on another table.

---

## 15. Validation

Reviewed against each named source. **Contradictions are named, not resolved
silently.**

| # | Source | Verdict | Detail |
|---|---|---|---|
| 1 | `Docs/01-PRD.md` | **No contradiction** | *Create and join communities* and *invite with a link or join code* are served by `join_policy` and `join_code`. The role matrix matches §11: *edit settings, transfer ownership, delete the community* are owner-only; *share the invitation* extends to admin, which is why `regenerate_join_code` accepts admin and settings updates do not |
| 2 | `Docs/06-ERD.md` | **No contradiction** | §1 names `communities` as *"the aggregate root"* — §5 here states why. §2's cascade description, the single-owner invariant and the "one invitation" section (§5 there) all match. §4's warning that `owner_id` is not authorization is restated as `CM-C13` and `AR-5` |
| 3 | **Database Principles** | **No artifact in the repository** | Third phase in which this has been recorded. Validated instead against `07-Database-Design.md` §*Standards*, `SUPABASE_OPERATIONAL_GUIDELINES.md` §2 and §4, and `ARCHITECTURE_DECISIONS_V1.md`. **If this document exists outside the repository, this specification has not been checked against it** |
| 4 | **Data Domains** | **No artifact in the repository** | Same. §3 and §5 state the domain and the aggregate boundary from first principles and from `06-ERD.md` §1 |
| 5 | `Statistics_Leaderboards_MVP_Specification.md` v2.0 | **No contradiction** | `SL-1`…`SL-5` are served by §14.4–14.6. `SL-2` §2.2's isolation requirement is what §5.1 point 4 identifies as a reason this is the root. `SL-4`'s asymmetry — a Level 2 record outlives its *membership* but not its *community* — is stated in §6.5 |
| 6 | `Results_Rating_Engineering_Decisions.md` v1.1 | **No contradiction, one consequence surfaced** | `RR-6` keeps Level 1 global, which this table does not touch. **Surfaced:** because deletion removes matches, and the `BEFORE DELETE ON matches` trigger reverses their results (`RR-4`), deleting a community rewrites Level 1 figures for every participant. Correct by design, non-obvious in effect — `CM-R5` |
| 7 | `Profiles_Table_Specification.md` v2.0 | **No contradiction; two patterns inherited** | `owner_id` → `users(id)` is consistent with that document's §5.2 Group C ("attribution and mirrors", no cascade). **`UP-1` and this table agree**: profile visibility is scoped by shared community, and community rows are broadly visible — the community list shows `owner_id` as a *uuid* and never joins for the owner's name, so no screen reads a profile outside `UP-1` tier 2. The `RR-2`/`UP` column-privilege pattern is inherited by §11.3, and `UP-4` by §12.2 |
| 8 | `Docs/10-Design-Decisions.md` | **One contradiction found** — see below | `DD-09`, `DD-12`, `DD-13`, `PD-15`, `PD-16` all hold and are cited |
| 9 | `SUPABASE_OPERATIONAL_GUIDELINES.md` | **No contradiction** | §4 names `communities` as the one approved broadly-readable table, and that statement is **accurate again** now that `UP-1` has removed `users` from the same category. §4's other items hold |
| 10 | `Docs/07-Database-Design.md` | **No contradiction** | Its *Key constraints* section describes `join_policy`, `join_code` and the regeneration behaviour exactly as specified here |

### 15.1 Contradiction 1 — `DD-13` and `DD-12` versus the read rule as built

**`DD-13` states that the join code is *"a credential, not a policy"*, and
`DD-12` makes it the single invitation identifier. The read rule as built lets
every authenticated user read every community's join code.**

Under `CODE_REQUIRED`, admission is supposed to require something the joiner
does not otherwise have. Every signed-in user has it. The two decisions and the
implementation cannot all be right.

**Not resolved silently.** The specification states the rule the decisions
imply (`CM-C15`, §11.1) and records the deviation as `CM-R1` and §19 item 1.
Whether to close it, and how, is confirmed in §18 as `CM-D3` — because closing
it changes an observable behaviour (a member can currently see the code and
pass it on) and that is the Product Owner's call, not engineering's.

### 15.2 Contradiction 2 — `PD-15` versus the update rule as built

**`PD-15` states that `owner_id` is a derived mirror, synchronized inside
`transfer_ownership`. The update rule as built lets the owner write it
directly**, with no accompanying role change.

A row-level rule cannot restrict columns; no column privilege exists on this
table. So `AR-2` is stated as an invariant and is unenforced.

**Not resolved silently.** Recorded as `CM-C13`, `CM-R2` and §19 item 2. The
fix is the pattern `RR-2` already established and the Product Owner already
approved for `users`, so no new decision is needed — only implementation.

### 15.3 Regression 3 — `CM-C3` versus what `create_community` stores

The name constraint validates the **trimmed** length while `create_community`
stores the **untrimmed** value. Migration `0002` trimmed; the `0016` rewrite
dropped it. Stated as `CM-C11`; low severity, but the constraint does not
describe the data, which is how a "guaranteed" property later turns out not to
hold.

---

## 16. Engineering Rationale

The five decisions that shaped this table.

### 16.1 The aggregate root is an entity, not a convention

The alternative — communities as a label on matches and memberships, with
permissions computed ad hoc — was never viable, because every consistency rule
in this domain spans tables and every one is bounded by one community. Making
the boundary an entity is what allows `has_community_role` to be *the* single
authorization predicate rather than one of several. A domain with one security
question has one root, and this is it.

### 16.2 Creation is atomic because the invalid state is unrecoverable

Most atomicity requirements protect against a state that is merely wrong. This
one protects against a state that cannot be repaired from inside the
application: a community with no owner membership has nobody who satisfies any
management check, so no operation can fix it and no user can delete it. That is
why creation is an RPC and why there is no insert access for a client.

### 16.3 Visibility and joining were separated because they are two questions

`is_private` answered both, so a community that wanted to control who joined had
to hide itself from the people it wanted to attract. `DD-13` split them: a
community is always visible, and `join_policy` carries what is left. The column
that conflated them was dropped rather than left behind, because a column no
policy reads and no screen writes is a trap for the next reader.

### 16.4 One credential, because revocation needs a single thing to retire

Three invitation identifiers meant there was no single act that invalidated an
invitation. Collapsing them onto the row makes reissue a complete revocation —
one statement, no window in which a community has two codes or none. The
consequence is that this column is a secret living on a broadly-readable row,
which is the tension `CM-R1` records: the design is right and its protection is
missing.

### 16.5 The row holds no summary of its children

No member count, no match count, no last-match date, no statistics. Every one
would be a second answer to a question a child table already answers, free to
disagree with it — the same argument `RR-6` used to keep the rating out of
`player_statistics`, applied downward instead of upward. It is also what keeps
the Community Dashboard honest: its ten figures are computed, so they cannot
drift.

---

## 17. Risks

| ID | Risk | Severity | Status |
|---|---|---|---|
| `CM-R1` | **The join code is readable by every authenticated user.** Any signed-in account can read the credential of every active community, which makes `CODE_REQUIRED` restrict nobody who has an account. `preview_community_invite` deliberately withholds the code; the table hands it out | **High** — a credential exposed to every account, and a stated product policy defeated | **Open.** Rule specified as `CM-C15`; deviation recorded in §19 item 1; the product question of what a member should see is `CM-D3` |
| `CM-R2` | **The owner can write every column of their own community**, including `owner_id` (desynchronizing the `PD-15` mirror), `join_code` (choosing a weak or already-known credential) and `is_active` (hiding the community). A row-level rule cannot restrict columns and no column privilege exists here | **High** — the same defect class `RR-2` closed on `users` | **Open.** Rules specified as `CM-C13`, `CM-C14`; deviation recorded in §19 item 2. **No new decision needed** — the pattern is approved |
| `CM-R3` | **The single-owner invariant (`AR-1`) is procedural, not structural.** Four operations each do the right thing; nothing prevents zero or two owner rows if a fifth path is ever added | Medium | **Recorded.** Any structural enforcement belongs on `community_members`, which this document does not design. Named here because the invariant is the aggregate's |
| `CM-R4` | **`is_active` is dormant.** Every read and all three join paths depend on it, but nothing writes it, so the designed suspension capability does not exist | Low | **Accepted**, as on `users`. §17.2 states what completing it requires |
| `CM-R5` | **Deleting a community rewrites Level 1 career figures.** Its matches are deleted, the reversal trigger fires for each, and every participant's Global Rating and career counters move — including players who have left and members of other communities | Medium — correct by design, surprising in effect, and irreversible | **Recorded, not changed.** The alternative (leaving results counted for matches that no longer exist) is worse. It is also the strongest argument for completing `CM-R4`: deactivation would take a community out of circulation without this |
| `CM-R6` | **The stored name is not trimmed** (`CM-C11`). The constraint validates a trimmed form the table does not store | Low | **Open**, §19 item 3. A regression from `0016`, not an original design choice |
| `CM-R7` | **Nothing prevents a community from having no members after creation**, because `remove_member` refuses to remove the owner but the owner's own departure is unimplemented (`PD-12` has no UI). The community would be owned by someone who has left | Low | **Latent.** Not reachable today: there is no path by which an owner leaves. Recorded so that implementing `PD-12` does not create it |
| `CM-R8` | **`name` is not unique**, so two communities may present identically to someone choosing which to join | Low | **Accepted by design** (`CM-C4`). Global uniqueness would be worse. Mitigated by the description and by the fact that most joining happens through a link, which is unambiguous |

---

## 18. Open Decisions

Four. Each is stated with an engineering recommendation; none blocks
implementation of the rest of the specification.

| ID | Question | Engineering recommendation |
|---|---|---|
| `CM-D1` | **Add `created_by`?** It would record who founded a community, which becomes non-derivable after an ownership transfer | **Weak yes, if taken now.** No consumer asks for it, so it fails the §14.7 test — but a column added later is permanently null for every existing community, so the moment to decide is before there is history. Defensible either way |
| `CM-D2` | **Is ownership transfer required to be auditable?** | **Not for the MVP.** If it ever is, the answer is an append-only history table on the `rating_history` pattern — **not** `updated_by` (§12.2, `UP-4`) |
| `CM-D3` | **Should a *member* be able to see their community's join code?** `CM-C15` restricts it to owner and admin. A member who can read it can pass it on, which under `CODE_REQUIRED` is an invitation the owner did not authorise | **Owner and admin only.** The PRD role matrix already places *share the community invitation* with those two and explicitly not with players. But this changes what a member sees today, so it is a Product call |
| `CM-D4` | **Does deactivation (`CM-R4`) belong in the MVP?** It is the only way to take a community out of circulation without the mass statistics reversal `CM-R5` describes | **Not in the MVP** unless the reversal is judged unacceptable. The capability is designed and dormant; completing it needs the Product decisions in §17.2, not schema work |

---

## 19. Conformance — where the built schema differs from this specification

Three deviations between this document and the schema as built through
migration `0024`.

| # | Deviation | Required by | Severity | Notes for the implementing phase |
|---|---|---|---|---|
| 1 | **`join_code` is readable by every authenticated user** | `CM-C15`, §11.1 | **High** | A column privilege cannot express "owner or admin *of this community*" (§11.1). The implementation needs a function or a view, not a `GRANT`. The client currently selects `join_code` in its standard column list for *all* communities, including the browse-all screen — the read path changes with the rule. Settle `CM-D3` first |
| 2 | **An owner can update every column**, not the three specified | `CM-C13`, `CM-C14`, §11.3 | **High** | Exactly the `RR-2` pattern: revoke table-level `UPDATE`, re-grant on `name`, `description`, `join_policy`. `transfer_ownership` and `regenerate_join_code` are unaffected — they are `SECURITY DEFINER` and run as the owner of the table. Assert the denials in the integration suite, as `RR-2` did |
| 3 | **The stored name is not trimmed** | `CM-C11` | Low | The `trim` existed until `0016` and was lost in a rewrite. Restoring it should be accompanied by a check of existing rows, as `PR-R8` requires for the User Profile's empty strings |

Two further items are **specified but not yet enforced anywhere**, and are
listed here rather than above because they were never enforced and so are not
regressions: `CM-C12` (`description` is null, never empty) and `CM-C16` (the
single-owner invariant, whose enforcement would live on `community_members`).

**Nothing in this section was changed in this phase.** No code, no SQL, no
migration and no Supabase object was touched.

---

## 20. Engineering Approval

**Status: Engineering Approved — conditional.**

This document is complete and is the authoritative engineering specification
for `public.communities`. It is marked **conditional** for one reason, stated
plainly rather than buried: **two High-severity access-control deviations
(§19 items 1 and 2) exist between this specification and the schema as built.**
The design is settled; the schema does not yet meet it. Approving this document
approves the design, not the current state of the table.

| Criterion | Status |
|---|---|
| Logical entity and physical table named, per `UP-5` | ✓ |
| Purpose, business owner, domain ownership, lifecycle | ✓ |
| **Aggregate Root responsibilities** — why it is the root, what must originate from it, and the five invariants it owns | ✓ §5 |
| Relationships: incoming, outgoing, dependency / deletion / lifecycle ownership | ✓ §6 |
| Every column — name, purpose, type, nullability, default, editability, business justification | ✓ 9 of 9 |
| Keys: primary, candidate, **alternate** (`join_code`), foreign | ✓ §8 |
| Every business constraint with its reason: ownership, uniqueness, visibility, lifecycle, deletion | ✓ 16 |
| Index strategy: every index justified by a named query; every rejected candidate justified | ✓ §10 |
| Access control: read, insert, update, delete × owner, admin, member, public | ✓ §11 |
| Audit: all four columns ruled on | ✓ §12 |
| Dependencies both directions, with ownership responsibilities | ✓ §13 |
| Future compatibility: members, invitations, matches, community statistics, community rating, leaderboards | ✓ §14, six of six |
| Validation against all named sources, contradictions named not resolved | ✓ 10 sources, **2 contradictions + 1 regression, all named** |
| Open decisions stated with recommendations | ✓ 4 |
| No SQL, no migration, no implementation, no other table designed | ✓ |

### What must happen before the table is *implementation*-conformant

1. Close §19 item 1 (`join_code` exposure) — after settling `CM-D3`.
2. Close §19 item 2 (column privileges) — no new decision required.
3. Close §19 item 3 (name trimming) — with a check of existing rows.

### Validation caveat, stated rather than glossed

The brief names *Database Principles* and *Data Domains* as validation sources.
**Neither exists as a document in this repository** — the third phase in which
this has been recorded. Validation used the principles in
`07-Database-Design.md`, `SUPABASE_OPERATIONAL_GUIDELINES.md` and
`ARCHITECTURE_DECISIONS_V1.md`. If those documents exist outside the
repository, this specification has not been checked against them.

---

## Related documents

| Document | Relationship |
|---|---|
| `engineering/Profiles_Table_Specification.md` | **Sibling authority** for `users`. `UP-1`, `UP-4`, `UP-5` and the `RR-2` column-privilege pattern are inherited here |
| `Docs/01-PRD.md` | Product scope and the three-role permission matrix |
| `Docs/06-ERD.md` | §1 names this the aggregate root; §4 the non-authorization fields; §5 the one invitation |
| `Docs/07-Database-Design.md` | The schema as built; join policy, join code and regeneration |
| `Docs/10-Design-Decisions.md` | `DD-09`, `DD-12`, `DD-13`, `PD-15`, `PD-16` |
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **Authoritative** for statistics and leaderboards; `SL-1`…`SL-5` |
| `engineering/Results_Rating_Engineering_Decisions.md` | `RR-2` (the column-privilege pattern), `RR-4`/`RR-5` (why deletion reverses), `RR-6` |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §4 names this the one approved broadly-readable table |
| `engineering/ARCHITECTURE_DECISIONS_V1.md` | Layer responsibilities |
