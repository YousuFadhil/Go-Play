# Notification (`notifications`) — Table Engineering Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Engineering Approved — conditional.** Two Medium findings; see §15 and §18 |
| Role | **Engineering Authority** for the physical table `public.notifications` |
| Owner | Product Owner |
| Phase | Database Design Engineering — Infrastructure |
| Scope | **`public.notifications` only.** Matches, users and the operations that produce notifications appear **only as producers or dependencies** |
| Baseline | `v0.6.0-mvp`, schema through migration `0024` |
| Date | 2026-08-02 |

> **This document is the authoritative specification for the physical table
> `public.notifications`.** Where an implementation and this document disagree,
> **the implementation is the defect**.
>
> **It contains no SQL, no view, no RPC and no implementation.**
>
> **Every statement was validated against the repository**, not recalled: the
> table definition and policies in migration `0006`, all sixteen
> `create_notification` call sites, the client's rendering path, and `DD-08` in
> the original.
>
> **`DD-08` is validated explicitly in §16.1**, clause by clause, as required.

---

## 0. Logical entity and physical table

Per `UP-5`:

| | |
|---|---|
| **Logical entity** | **Notification** |
| **Physical table** | **`notifications`** |

**One row is one notice, addressed to one person, about one thing that
happened.**

---

## 1. Purpose

### 1.1 Business purpose

A Notification tells **one player that something affecting them has changed**,
without their having to notice it themselves.

`DD-08` states the reason directly: *to inform players of the changes that
affect them without having to refresh lists manually; and keeping the notice
after a match is deleted is necessary to understand the context — "why did this
match disappear?"*

**The second half is the design.** A notice about a deleted match must outlive
the match, or the only record of *why something vanished* vanishes with it.

### 1.2 Business owner

**Product Owner**, as for every table.

| What | Owner | Set by |
|---|---|---|
| **That a notice exists** | **The system**, as a consequence of a match-lifecycle event | `create_notification`, called from six operations |
| `type`, `message`, `match_id`, `user_id` | **The system, exclusively** | The same call, once |
| **`is_read`** | **The recipient** | The client, marking notices read |
| `id`, `created_at` | The database | Nothing writes them after insert |

**This is the only table in the schema with a column a player legitimately
writes about themselves** — and it is the one column that carries no business
meaning (§2.2).

### 1.3 Domain ownership

**Domain: Infrastructure. It is not a business domain at all.**

| Property | Value |
|---|---|
| Aggregate | **None.** It sits outside the Community and Match aggregates |
| Depends on | `users` and `matches` |
| Depended on by | **Nothing** |
| Contains authorization | **No** |
| Is a source of truth | **No, and never** — §2.3 |

**It is the only table in the phase that is infrastructure rather than
record.** Every other table answers a question about the product's subject
matter; this one carries a message about an answer given elsewhere.

### 1.4 Consumers

| Consumer | Reads |
|---|---|
| **The notifications screen**, for the signed-in player | Their own notices, newest first |
| **The unread badge** | A count of their own unread notices |
| **Nobody else** | §10.2 — not another player, not an admin, not a System Admin |

**No system consumer.** Nothing in the database reads a notification, and **no
business rule consults one** (§2.3).

### 1.5 Scope

**This document covers the table as it exists.** Push notifications, email,
scheduling, digests and preferences are evaluated for compatibility in §13 and
**designed nowhere** — `DD-08` places push out of scope and in the backlog.

---

## 2. Entity Responsibilities

### 2.1 What this table owns

| # | Responsibility | Column |
|---|---|---|
| 1 | **The addressee** — whose notice this is | `user_id` |
| 2 | **What kind of notice it is** | `type` |
| 3 | **The rendered text**, as a fallback | `message` — §6.2, and see §14.4 |
| 4 | **What it refers to**, when it still exists | `match_id` |
| 5 | **Whether the recipient has seen it** | `is_read` |
| 6 | **When it was raised** | `created_at` |

### 2.2 What this table does **not** own

| # | Not owned | Why not |
|---|---|---|
| 1 | **Any business fact** | A notice *reports* a fact recorded elsewhere. The promotion is in `match_registrations`; the deletion is the absence of a match |
| 2 | **Any business decision** | **No rule anywhere consults a notification** — §2.3 |
| 3 | **Delivery** | There is no delivery mechanism. A notice is *available*, never *sent* — §3.3 |
| 4 | **Read state as a business fact** | `is_read` is **presentation only**. Nothing branches on it but a badge |
| 5 | **The event that caused it** | The event is a row in another table, or the absence of one |
| 6 | **Localization** | §14.4 — the client renders from `type`; `message` is a frozen single-language fallback |
| 7 | **Any history** | A notice has no audit and needs none — §11 |

### 2.3 Notifications are infrastructure, never authority

**Six statements, all verified against the repository:**

| # | Statement | Verification |
|---|---|---|
| 1 | **Notifications never become the source of truth** | Nothing reads the table except the recipient's own screen |
| 2 | **Business events remain authoritative** | Every notice reports a change already committed in the same transaction |
| 3 | **Notifications may be regenerated** | Nothing is lost by recreating one; no uniqueness prevents it (§8) |
| 4 | **Deletion never alters business data** | No cascade leaves this table. Deleting a notice removes a notice |
| 5 | **Notification state never influences business rules** | `is_read` is read by the client only; no operation branches on it |
| 6 | **Read state is presentation only** | Confirmed — and it is why §11 requires no read audit |

**The consequence worth stating**: **losing this entire table would cost the
product nothing but the notices themselves.** No figure, no rating, no roster
and no permission depends on it. That is the definition of infrastructure, and
it is why §15 rates its findings lower than the same findings elsewhere.

---

## 3. Notification Lifecycle

### 3.1 The shape

```
  NO NOTICE
      │
      │  a match-lifecycle event occurs, inside its own transaction
      ▼
  CREATED ── unread, addressed to one player, referring to one match
      │
      ├── the recipient opens the screen ──▶ READ  (is_read = true)
      │                                        │
      │                                        └── never returns to unread
      │                                            in practice (§3.4)
      │
      ├── the match is DELETED ──▶ match_id becomes NULL. The notice SURVIVES.
      │                            This is DD-08.
      │
      ▼
  GONE ── the recipient deletes it, the account is deleted,
          or the community is deleted (§3.6)
```

### 3.2 Creation

**One writer, six call sites.**

| Property | Value |
|---|---|
| Written by | **`create_notification`** — `SECURITY DEFINER`, and **revoked from `anon`, `authenticated` and `public`** |
| Called from | `rebalance_roster`, `withdraw_from_match`, `remove_player`, `update_match`, `delete_match`, `purge_membership` |
| Transaction | **Always inside the operation that caused the event**, under the match row lock |
| Client access | **None.** No insert policy exists, and the function is unreachable through the API |

**A notice is created in the same transaction as the change it reports**, so a
notice about a promotion that did not happen is not a reachable state.

### 3.3 Delivery — there is none

**There is no delivery step, no queue, no retry and no delivery status.**

A notification is **available** the moment it is committed. The recipient sees
it when they open the screen. **`DD-08` places push notifications out of
scope**, so nothing leaves the database.

**Stated because "delivery" appears in the lifecycle brief**: the correct answer
is that the concept does not exist in this design, and §13.1 states what
introducing it would require.

### 3.4 Reading

| Property | Value |
|---|---|
| Written by | **The recipient**, through the client |
| Mechanism | A direct update of `is_read`, authorised by the row-level rule |
| Granularity | The client marks **all unread notices read at once** |
| Reversible? | **Structurally yes; in practice never** — no client path sets `is_read` back to false |
| Business effect | **None.** §2.3 statement 6 |

**`is_read` is the only column any person writes**, and §10.4 records that the
rule permitting it permits far more.

### 3.5 Retention

**Indefinite. There is no expiry, no archive and no pruning.**

| Property | Value |
|---|---|
| Retention period | **Unbounded** |
| Pruned when read | **No** |
| Pruned by age | **No** |
| Bounded by | Only the recipient's account, and their own deletions |

**This is a growth risk rather than a defect** — §15.2, `NT-R3`.

### 3.6 Deletion

**Four paths, and the differences between them matter.**

| Path | Effect | Notes |
|---|---|---|
| **The recipient deletes it** | The row goes | The only client-initiated deletion in the schema |
| **The account is deleted** | Cascade from `users` — **and an explicit delete in `admin_delete_user`** | Belt and braces |
| **The match is deleted** | **The notice SURVIVES.** `match_id` becomes null | **`DD-08`** — §16.1 |
| **The community is deleted** | **The notices are DELETED** — explicitly, before the matches | §3.7 |

### 3.7 The survival guarantee is match-scoped, not absolute

**A notice survives its match. It does not survive its community.**

`purge_community` deletes the community's matches' notifications **first**, and
the migration states why: *"Notifications point at the match with ON DELETE SET
NULL, so they have to go first: once the matches are gone there is no way left
to tell which notifications belonged to this community."*

**This is deliberate and consistent, not a contradiction of `DD-08`.** `DD-08`'s
guarantee is about *match* deletion — *"so the 'match deleted' notice remains
readable after the match is actually deleted"*. **A deleted community is a
larger event**, and a notice about a match in a community that no longer exists
has no context left to preserve.

**The ordering is load-bearing**: if the matches went first, the `SET NULL`
would fire and the notices would become unattributable to the community —
orphaned rather than removed. **This is the reason `purge_community`'s step 2
exists**, and the Communities specification records it as step 2 of the ordered
disposal.

### 3.8 Every valid transition

| # | From | To | Trigger |
|---|---|---|---|
| 1 | None | Created, unread | A match-lifecycle event |
| 2 | Unread | Read | The recipient opens the screen |
| 3 | Read | **Read** | Idempotent — the client filters on `is_read = false` before updating |
| 4 | Any | `match_id` null | **The match is deleted** — the notice survives |
| 5 | Any | Gone | The recipient deletes it |
| 6 | Any | Gone | The account is deleted |
| 7 | Any | Gone | The community is deleted (§3.7) |

### 3.9 Invalid transitions

| Invalid | Why | Refused by |
|---|---|---|
| A client creating a notice | It could address anyone and assert anything | **No insert policy**, and the function is revoked from every client role |
| Reading someone else's notice | It is addressed to one person | The row-level rule on `user_id` |
| Marking someone else's notice read | Same | The same rule |
| **A notice cascading away with its match** | **`DD-08`** — the notice would vanish exactly when it is most needed | **`ON DELETE SET NULL`**, asserted twice in migration `0006` |
| A business rule branching on `is_read` | Read state is presentation only | Nothing does — verified |

---

## 4. Notification Model

### 4.1 The five types currently supported

**Verified against all sixteen call sites in the repository.**

| # | `type` | Business meaning | Triggering event | Producer | Consumer | Lifetime |
|---|---|---|---|---|---|---|
| 1 | **`promoted`** | *You have moved from the reserve list into the starting group* | A confirmed player withdraws, is removed, or leaves the community; or the organiser raises `starting_players` | `withdraw_from_match`, `remove_player`, `purge_membership`, `rebalance_roster` | The promoted player | Indefinite |
| 2 | **`moved_to_reserve`** | *You have been moved to the reserve list because the player count changed* | The organiser **lowers** `starting_players` | `rebalance_roster` | The demoted player | Indefinite |
| 3 | **`removed`** | *The organiser has removed you from the match* | An owner or admin removes a registrant | `remove_player` | The removed player | Indefinite |
| 4 | **`match_updated`** | *The match details have been edited* | The organiser edits a match | `update_match` | **Every registrant** | Indefinite |
| 5 | **`match_deleted`** | *The match has been deleted* | An owner or admin deletes a match | `delete_match` | **Every registrant** | Indefinite — **and outlives the match** |

### 4.2 Producers, precisely

**Four of the five types have more than one producer**, and `promoted` has
four — because a confirmed place can be freed four different ways and each frees
it identically.

**That multiplicity is correct**: the notice describes what happened to the
*recipient*, not which operation caused it. A promoted player does not care
whether someone withdrew or was removed.

### 4.3 The type vocabulary is not governed by any approved document

**`DD-08` enumerates four *events***: promotion from the reserve, removal by the
organiser, a match edit, and a match deletion.

**The implementation carries five *types***. The fifth, `moved_to_reserve`,
arose from the roster rebalance — which is a *consequence* of the match-edit
event `DD-08` does list.

**So this is not a contradiction**: the type vocabulary is finer-grained than
`DD-08`'s event list, and `moved_to_reserve` sits inside *match edit*.

**But it means no approved document defines the vocabulary**, and the column has
no constraint (§8). **Nothing would catch a sixth type invented by a future
producer**, and §14.4 shows why that failure is silent rather than loud.
Recorded as `NT-R2`.

### 4.4 What produces no notification

**Recording, correcting or deleting a match *result* produces nothing.**

No player is told that a result was recorded, that their rating moved, or that
their statistics changed. **Five types, all match-lifecycle; none about
outcomes.**

**Not a defect against any approved rule** — `DD-08` lists four events and none
is a result — **but a genuine product gap**, and the most likely place a sixth
type would be added (§13.4).

---

## 5. Relationships

### 5.1 Outgoing

| Target | Column | Cardinality | On delete | Ownership | Lifecycle dependency |
|---|---|---|---|---|---|
| `users` | `user_id` | many : 1 | **`CASCADE`** | **Identifying** — the notice belongs to its addressee | **Absolute.** A notice cannot outlive its recipient |
| `matches` | `match_id` | many : 0..1 | **`SET NULL`** | **Reference only** — the notice is *about* the match, not owned by it | **None — deliberately.** `DD-08` |

**Two foreign keys, and the second is the most deliberate deletion behaviour in
the schema.** It is the only `SET NULL` reference among all fifteen tables, and
migration `0006` asserts it **twice** — once in the table definition and once
idempotently afterwards, *"to guarantee the match reference never
cascade-deletes notifications."*

### 5.2 Incoming

**None.** Nothing references a notification, and nothing should: a notice is a
leaf, and referencing one would give a business record a dependency on
infrastructure.

### 5.3 Ownership

| Question | Answer |
|---|---|
| **Who owns the notice?** | **The recipient.** It is addressed to them, readable only by them, and deletable only by them |
| **Who owns its content?** | **The system.** The recipient may mark it read; they may not author it |
| **Does the match own it?** | **No** — and that is the whole of `DD-08`. A notice *refers to* a match and outlives it |
| **Can it be reparented?** | **No.** Nothing writes `user_id` after insert |

### 5.4 Deletion behaviour — summary

| Deleted | Effect on notifications |
|---|---|
| The recipient's account | **Gone** — cascade, plus an explicit delete |
| The referenced match | **Survive**, with `match_id` nulled — `DD-08` |
| The community | **Deleted**, explicitly and first (§3.7) |
| A registration, a lineup, a result | **No effect** — no relationship exists |

---

## 6. Columns

**Seven columns.**

### 6.1 Summary

| # | Name | Type | Nullable | Default | Editable | Owner |
|---|---|---|---|---|---|---|
| 1 | `id` | `uuid` | No | generated | **Immutable** | Database |
| 2 | `user_id` | `uuid` | No | none | **Immutable** | System |
| 3 | `match_id` | `uuid` | **Yes** | none | **System only** — nulled by the FK | System |
| 4 | `type` | `text` | No | none | **Immutable in intent** — §10.4 | System |
| 5 | `message` | `text` | No | none | **Immutable in intent** — §10.4 | System |
| 6 | `is_read` | `boolean` | No | `false` | **The recipient** | **The recipient** |
| 7 | `created_at` | `timestamptz` | No | `now()` | **Immutable** | Database |

**"Immutable in intent" is precise, not evasive**: no operation writes these
columns after insert, **but the row-level update rule permits the recipient to**
— §10.4, `NT-R1`.

### 6.2 Column detail

---

**1. `id` — `uuid`, NOT NULL, generated, immutable**

*Purpose.* Row identity, and the handle the client uses to mark one notice read
or delete it.

*Justification.* A surrogate with a real client consumer, unlike several
elsewhere in the schema. Notifications have no natural key (§7.2), so a
surrogate is the only option.

---

**2. `user_id` — `uuid`, NOT NULL, immutable**

*Purpose.* **Who the notice is addressed to.**

*Business meaning.* It is the whole of the access model: a notice is readable,
updatable and deletable by exactly one person, and this column names them.

*Justification for the cascade.* A notice addressed to a deleted account is
addressed to nobody. **And unlike attribution columns elsewhere, there is no
reason to preserve it** — nothing depends on it and nobody can read it.

---

**3. `match_id` — `uuid`, NULLABLE, `ON DELETE SET NULL`**

*Purpose.* **What the notice is about**, while that thing still exists.

*Business meaning.* It is what lets the client navigate from a notice to its
match — and **null means the match is gone**, which is itself information the
client can act on.

***This is `DD-08`, and it is the most consequential single choice in the
table.*** With `CASCADE`, the *"match deleted"* notice would be destroyed by the
very deletion it exists to report — **the notice would vanish exactly when it is
the only remaining explanation.**

*Nullable, and null carries meaning*: either the match was deleted, or — in a
future type — the notice was never about a match at all (§13.6).

*The only column the database itself writes after insert*, via the foreign key.

---

**4. `type` — `text`, NOT NULL, no constraint**

*Purpose.* **The machine-readable kind of notice.**

*Business meaning.* It is what the client switches on to render localized text
(§14.4), and therefore **the authoritative content of the notice** — not
`message`.

*Justification, and the finding.* **Free text with no CHECK and no approved
vocabulary** (§4.3). Five values are in use. A sixth, introduced by a future
producer, would be accepted silently and would render as the Arabic fallback
for every user regardless of language.

**Recommended: a CHECK constraint over the five known values** — `NT-C4`, §8.

---

**5. `message` — `text`, NOT NULL**

*Purpose.* **A pre-rendered notice text.**

*Business meaning — and it is not what the name suggests.* **The client does not
display this column for any known type.** It renders localized text from `type`
and falls back to `message` only for a type it does not recognise.

*So `message` is:*

| | |
|---|---|
| For the five known types | **Dead** — written on every insert, read by nothing |
| For an unknown type | **A fallback that is always Arabic**, regardless of the reader's language |
| As a design | **A duplicate of `type`**, frozen at write time in one language |

***It cannot be localized.*** The string is chosen by the producing operation
inside the database, which has no knowledge of the reader. **Every stored
message in the repository is Arabic.**

**Recommended: do not extend it, and do not rely on it.** §14.4 and `NT-R2`.

---

**6. `is_read` — `boolean`, NOT NULL, default `false`, written by the
recipient**

*Purpose.* Whether the recipient has seen the notice.

*Business meaning.* **Presentation only.** It drives an unread badge and
nothing else. **No business rule consults it** — verified.

*Justification for the default.* A notice is unread when raised; anything else
would be a claim about the recipient the system cannot make.

*It is the only column any person writes in this table*, and one of very few in
the schema — justified because it is a fact about the reader's own attention,
which only the reader can report.

---

**7. `created_at` — `timestamptz`, NOT NULL, default `now()`, immutable**

*Purpose.* When the notice was raised.

*Business meaning.* It is the **ordering** of the notifications screen, newest
first — and the second column of the index that serves it.

*Justification.* Unlike several tables in this phase where `created_at` is not
an ordering, **here it is exactly that**, and the index is built for it.

### 6.3 No `updated_at`, and here that is correct

`is_read` is mutable, so the pattern that made its absence a defect on
`community_members` and `match_registrations` appears to apply.

**It does not.** *When* a notice was read has **no consumer and no business
meaning** — read state is presentation only (§2.3), and a timestamp on it would
record the moment of an act nothing depends on.

**This is the third distinct answer this phase has given to the same question**,
and the difference is the consumer, not the mutability:

| Table | Mutable column | `updated_at` | Why |
|---|---|---|---|
| `community_members` | `role` | **Required, missing** | A role change is consequential and untimestamped |
| `match_goals` | none | **Correctly absent** | Nothing updates a row |
| **`notifications`** | **`is_read`** | **Correctly absent** | The mutation has no business meaning |

---

## 7. Keys

### 7.1 Primary key

**`id`** — a generated `uuid`, with a real client consumer (§6.2).

### 7.2 Business key — **none, and none is possible**

A notification is an **event**, and events have no natural key. The same player
can receive two `match_updated` notices for the same match if the organiser
edits it twice — **and both are correct.**

**There is deliberately no uniqueness rule**, which is what makes §2.3
statement 3 true: **notifications may be regenerated**, and a duplicate is a
second notice rather than an error.

### 7.3 Candidate keys

**One: `id`.** No column or combination else is unique.

### 7.4 Alternate keys

**None**, and none possible.

### 7.5 Foreign keys

| Column | References | On delete | Why |
|---|---|---|---|
| `user_id` | `users(id)` | **`CASCADE`** | A notice addressed to nobody is not a fact |
| `match_id` | `matches(id)` | **`SET NULL`** | **`DD-08`** — the notice must outlive the match |

---

## 8. Constraints

| ID | Constraint | Status | Why |
|---|---|---|---|
| `NT-C1` | **Primary key on `id`** | **Enforced** | Row identity, and the client's handle |
| `NT-C2` | **`user_id` references `users(id)`, cascading** | **Enforced** | §6.2 |
| `NT-C3` | **`match_id` references `matches(id)` with `SET NULL`** | **Enforced, and asserted twice** | **`DD-08`** |
| `NT-C4` | **`type` is one of the five known values** | **MISSING** | Free text today. A sixth type is accepted silently and renders as the Arabic fallback (§14.4). **Recommended** |
| `NT-C5` | **`type` and `message` are NOT NULL** | **Enforced** | A notice with neither says nothing |
| `NT-C6` | **`is_read` is NOT NULL, default `false`** | **Enforced** | A notice is unread when raised |
| `NT-C7` | **No client may insert** | **Enforced** | No insert policy; the function is revoked from every client role |
| `NT-C8` | **A client may only touch their own notices** | **Enforced** | The row-level rules on all three of select, update and delete |
| `NT-C9` | **A client may update `is_read` and nothing else** | **MISSING** | The update rule is row-level with no column restriction — `NT-R1`. **Recommended** |
| `NT-C10` | **No uniqueness of any kind** | **Deliberately absent** | §7.2 — regeneration must remain valid |
| `NT-C11` | **A notice is created in the same transaction as its cause** | **Inherited** | From the producing operations, under the match row lock |
| `NT-C12` | **No business rule may read `is_read`** | **Convention** | Verified true; not expressible as a constraint |

### 8.1 Deliberately not constrained

| Not constrained | Why not |
|---|---|
| A retention period | §3.5. No approved rule sets one |
| Uniqueness per `(user, match, type)` | §7.2 — two edits produce two notices, correctly |
| `message` length or language | It is a fallback that should not be extended (§14.4) |
| That `match_id` be non-null | A future type may refer to no match (§13.6) |

---

## 9. Index Strategy

### 9.1 Existing

| ID | Index | Serves |
|---|---|---|
| `NT-X1` | **`(user_id, created_at DESC)`** | **The notifications screen** — one player's notices, newest first. **The single access pattern this table has**, and the index matches it exactly |
| `NT-X2` | **Primary key on `id`** (implicit) | Marking one notice read; deleting one |

### 9.2 Expected access patterns

| Pattern | Frequency | Served by |
|---|---|---|
| One player's notices, newest first | **Every screen open** | `NT-X1` |
| One player's **unread count** | **Every app open** | `NT-X1`'s leading column, then a filter on `is_read` |
| Mark all unread read | Occasional | Same |
| Delete one notice | Rare | `NT-X2` |
| **The cascade from `users`** | Rare | `NT-X1`'s leading column |
| **`purge_community`'s delete by match** | Rare | **No index** — §9.4 |

### 9.3 Required, and not present

**None required.** The unread-count filter is evaluated over one player's rows —
tens at most — after an index seek. A partial index on unread notices would
save a negligible scan and would be maintained on every read-marking.

### 9.4 One unindexed access path, and why it is acceptable

**`purge_community` deletes notifications by `match_id in (…)`**, and there is
**no index on `match_id`**.

| | |
|---|---|
| Frequency | **Community deletion only** — the rarest operation in the product |
| Cost | A sequential scan of the table |
| Growth | Unbounded retention (§3.5) means the scan grows forever |

**Assessment: acceptable today, and it is the second-order consequence of
`NT-R3`.** An index on `match_id` would also serve the `SET NULL` on match
deletion, which is far more frequent. **Recommended if retention is ever
bounded, or if match deletion becomes common** — recorded as `NT-R4`, Low.

### 9.5 Redundant indexes

**None.** Two indexes, two distinct access patterns.

---

## 10. Access Control

Stated as **rules, not policy expressions**.

### 10.1 The matrix

| Actor | Create | Read | Update | Delete |
|---|---|---|---|---|
| **Public (`anon`)** | ✗ | ✗ | ✗ | ✗ |
| **The recipient** | ✗ | ✓ **Their own** | ✓ **Their own** — §10.4 | ✓ **Their own** |
| **Any other player** | ✗ | ✗ | ✗ | ✗ |
| **Community Admin / Owner** | ✗ | ✗ **Nothing** | ✗ | ✗ |
| **System Administrator** | ✗ | ✗ **No direct path** | ✗ | ✓ Transitively, via account deletion |
| **The system** | ✓ **Only actor** | — | — | ✓ Via the community purge |

**A community role grants nothing here** — which is right: a notice is addressed
to a person, not to a member.

### 10.2 Read

**A player reads their own notices and nobody else's.** The rule is a direct
comparison against the signed-in identity, made possible because `user_id` *is*
the authentication identity.

**This is the narrowest read rule in the schema** — narrower than the User
Profile's, narrower than any community-scoped table's. **Correctly**: a notice
is private correspondence.

### 10.3 Create

**No client may insert, by any route.** Two independent barriers:

| Barrier | |
|---|---|
| **No insert policy** | RLS with no policy denies the operation for every client role |
| **The function is revoked** | `create_notification` is revoked from `anon`, `authenticated` and `public` — it is unreachable through the API |

**The second is what matters**, and it follows the project's rule that *no role
may reach a trigger or helper function through the API*.

### 10.4 Update — the finding

**The rule permits the recipient to update *any column* of their own notice.**

It is row-level with no column restriction, so a recipient could change their
own notice's `type`, `message`, `match_id` or `created_at` — not merely
`is_read`.

**What that permits:**

| Written | Consequence |
|---|---|
| `type` | Changes how the client renders it, and could point it at a different meaning |
| `match_id` | Changes where the notice navigates to — **including to a match they can see but was not the subject** |
| `created_at` | Reorders their own list |
| `message` | Rewrites the fallback text |

**Severity is genuinely lower than the same defect elsewhere**, and the reason
is §2.3: **notifications are not authority.** A player rewriting their own notice
deceives only themselves; no figure, permission or business record moves.

**But it is still a permission with no consumer.** The client writes `is_read`
and nothing else. **Recommended: restrict to `is_read`** — `NT-C9`, `NT-R1`.

**This is the fourth instance of the same pattern in the phase** — a row-level
write rule granting more than any writer uses — after `communities`, `matches`
and `match_team_assignments`.

### 10.5 Delete

**The recipient may delete their own notices.** This is the **only
client-initiated deletion in the entire schema**, and it is correct:

- A notice is the recipient's own correspondence.
- **Deleting one alters no business data** (§2.3 statement 4).
- Nothing references it, so nothing breaks.

---

## 11. Audit

| Column | Required? | Verdict |
|---|---|---|
| `created_at` | **Required, present** | The screen's ordering, and the index's second column |
| `updated_at` | **Not required** | §6.3 — the only mutation has no business meaning |
| `created_by` | **Not required** | §11.1 |
| `updated_by` | **Not required** | §11.1 |

### 11.1 No actor columns, for two different reasons

**`created_by`**: there is no human author. A notice is raised by an operation as
a consequence of an event, and **the actor of the *event* is recorded where the
event is** — the organiser who edited the match is `matches`' concern, not this
table's.

**`updated_by`**: the only update is the recipient marking their own notice read,
and **`user_id` already names them.** The column would be a copy of one already
present.

### 11.2 History, immutability and tracking

| Aspect | Position |
|---|---|
| **History** | **None, and none needed.** A notice is not a record of anything — the record is elsewhere (§2.2) |
| **Immutability** | **Intended for six of seven columns, enforced for none** — §10.4 |
| **Read tracking** | **`is_read` only.** No timestamp, no per-device state, no partial read |
| **Deletion tracking** | **None.** A deleted notice leaves nothing, and should not — §2.3 statement 4 |

**The absence of all four is correct for infrastructure**, and stating it
explicitly is what prevents a future phase adding an audit to a table that has
nothing to audit.

---

## 12. Dependency Review

### 12.1 Upstream producers

| Producer | Types raised |
|---|---|
| `rebalance_roster` | `promoted`, `moved_to_reserve` |
| `withdraw_from_match` | `promoted` |
| `remove_player` | `promoted`, `removed` |
| `purge_membership` | `promoted` |
| `update_match` | `match_updated` |
| `delete_match` | `match_deleted` |

**All six are Match-domain operations**, and all six write through the single
`create_notification` function.

### 12.2 Downstream consumers

| Consumer | Reads |
|---|---|
| The notifications screen | The recipient's own notices |
| The unread badge | A count |

**Nothing else — in the database or the application.**

### 12.3 External dependencies

**None.** No mail provider, no push service, no queue, no scheduler. **`DD-08`
places push out of scope**, and nothing in the current design reaches outside
the database.

### 12.4 The dependency shape

**This table is a sink**: six producers, two readers, no incoming foreign keys,
and nothing depending on it. **It can be emptied, dropped or rebuilt without
affecting a single business record** — which is §2.3's claim, expressed
structurally.

---

## 13. Future Compatibility

### 13.1 Push notifications

**Out of scope by `DD-08`, and in the backlog.**

**Compatibility: the table is a reasonable starting point and is not
sufficient.** Push needs, at minimum:

| Needs | Present? |
|---|---|
| A device or token registry | **No** — a new entity |
| A delivery status per notice | **No** — §3.3, delivery does not exist |
| A retry policy | **No** |
| **The event and the addressee** | **Yes** — `type`, `user_id`, `match_id` |

**The critical design point**: push must be driven **from the same row**, not
from a parallel path — otherwise a player could receive a push for a notice that
does not appear in the app, or the reverse.

### 13.2 Email notifications

**Same shape as push**, plus a rendered body — which is where §14.4's finding
becomes expensive: **`message` is Arabic and frozen**, so email would need
rendering from `type` exactly as the client does.

**That is an argument for treating `type` as the sole content authority now**,
before a second renderer exists.

### 13.3 Scheduled and reminder notifications

*"Your match starts in an hour."*

**The blocker is not this table — it is that the product has no scheduler.**
`DD-05` established that completion is derived lazily precisely to avoid one.

**A reminder needs something to run at a time nobody triggers**, which is a new
infrastructure capability, not a column. **The table itself would need only a
new `type`.**

### 13.4 Digest notifications

*"Three things happened this week."*

**A digest is a read-side grouping of existing rows**, needing no schema change
at all — the index already supports *one player's notices in a window*.

**If a digest is instead a *stored* summary notice**, it is one new `type` and
nothing more.

### 13.5 Notification preferences

*"Do not notify me about match edits."*

**A new entity** — preferences per user, probably per type. **And a decision
this table cannot make**: whether a suppressed notice is *not created* or
*created and hidden*.

**Recommendation for whoever designs it**: **create it and hide it.** A notice
never created cannot be recovered if the preference changes, and §2.3 statement
3 (notifications may be regenerated) is easier to honour when nothing was
skipped.

### 13.6 Silent notifications

*A notice that updates state without alerting.*

**Structurally supported already** — `is_read` defaulting `true`, or a `type` the
badge ignores. **No schema change.**

**But it collides with §2.3 statement 5**: a silent notification whose purpose is
to *carry state* would make notification state influence behaviour, which is
forbidden. **A silent notice must remain a notice.**

### 13.7 What every future type needs

| # | Requirement |
|---|---|
| 1 | **A client mapping**, added at the same time — otherwise the Arabic fallback renders for every user (§14.4) |
| 2 | **Addition to `NT-C4`'s vocabulary**, once that constraint exists |
| 3 | **A producer inside the transaction of the event it reports** |

---

## 14. Engineering Review

### 14.1 Ownership — clean

**No business ownership to violate.** The table owns notices; every fact it
reports is owned elsewhere (§2.2). **§2.3's six statements were verified against
the repository, not assumed.**

### 14.2 Aggregate boundaries — respected, with one deliberate exception

**A notification sits outside every aggregate**, which is why it can outlive a
match (§5.1). **That is the exception, and it is `DD-08`'s entire point**: a
notice about a deleted match must not be bounded by the aggregate it describes.

**And the exception is bounded in turn**: a notice does not outlive its
*community* (§3.7), because at that scale the context is gone too.

### 14.3 Responsibility — clean

Six columns of system-owned content, one column of recipient-owned state.
**The split is clean and the boundary is meaningful**: the system says what
happened; the recipient says whether they have seen it.

### 14.4 Duplicate responsibility — one, and it is `message`

**`type` and `message` both carry what the notice says. Only `type` is used.**

The client renders localized text by switching on `type`, *"falling back to the
stored message"* only for an unrecognised type.

**So `message` is written on every insert and read for no known type** — and
when it *is* read, it is Arabic regardless of the reader's language.

**The sharper consequence**: `message` **masks** a missing client mapping rather
than surfacing it. A new type without a mapping renders as Arabic text instead
of failing visibly — **so the defect ships quietly.**

**Assessment: `type` is the content authority. `message` is a legacy fallback
that should not be extended or relied upon.** Recorded as `NT-R2`.

### 14.5 Lifecycle consistency — sound, with one asymmetry explained

**Creation, reading and deletion are all consistent.** The one asymmetry — a
notice survives a match but not a community — is deliberate, documented in the
migration, and load-bearing for the deletion ordering (§3.7).

### 14.6 Performance — sound, with a growth risk

**One index, one access pattern, exact match.** The risk is unbounded retention
(§3.5) compounding an unindexed deletion path (§9.4) — both Low, both
recorded.

### 14.7 Security — sound, with one over-broad rule

**Reads and inserts are correct and narrow.** The update rule grants more than
any writer uses (§10.4) — and the severity is genuinely reduced by §2.3, because
the data is not authority.

### 14.8 Read/write separation — the cleanest in the schema

| Direction | Actor |
|---|---|
| **Content written** | **The system only**, through one revoked function |
| **State written** | **The recipient only**, on their own row |
| **Read** | **The recipient only** |

**No overlap, and no third party at any point.**

---

## 15. Risks

### 15.1 High

**None.** Every finding is bounded by §2.3: **nothing in this table is
authority**, so no defect here can move a figure, a permission or a business
record.

**Stating that explicitly is part of the assessment** — the same over-broad
update rule that is High on `matches` is Medium here, and the reason is the
data, not the rule.

### 15.2 Medium

| ID | Risk | Cause | Impact | Recommendation |
|---|---|---|---|---|
| `NT-R1` | **The recipient may update every column of their own notice** | Row-level update rule with no column restriction | They may rewrite `type`, `message`, `match_id` or `created_at` — changing rendering, navigation and ordering of their own list. **No business data moves** | **Restrict to `is_read`** (`NT-C9`). Fourth instance of this pattern in the phase |
| `NT-R2` | **A new `type` renders as Arabic for every user** | `type` has no constraint and no approved vocabulary; `message` is a frozen Arabic fallback that **masks** the missing client mapping | A shipped notification type appears in the wrong language and **fails silently** | **Add `NT-C4`**, and require a client mapping with every new type (§13.7). Treat `type` as the sole content authority |

### 15.3 Low

| ID | Risk | Cause | Impact | Recommendation |
|---|---|---|---|---|
| `NT-R3` | **Unbounded retention** | No expiry, no pruning, no archive (§3.5) | The table grows forever; an active player accumulates thousands of rows | **Accept for the MVP.** Revisit with a retention rule if volume becomes measurable |
| `NT-R4` | **`purge_community` scans to delete by `match_id`** | No index on `match_id` | A sequential scan on the rarest operation, growing with `NT-R3` | **Add an index on `match_id` if retention is bounded or match deletion becomes common.** It would also serve the `SET NULL` |
| `NT-R5` | **No notification for recorded results** | Five types, all match-lifecycle | Players are not told their rating or statistics moved | **A product gap, not a defect.** The most likely sixth type (§4.4, §13.7) |
| `NT-R6` | **`message` is written on every insert and read by nothing** | §14.4 | Storage and producer complexity for a dead column | **Do not extend it.** Removing it is not recommended — it remains the only fallback for an unmapped type |

---

## 16. Contradictions

### 16.1 `DD-08` — validated explicitly, clause by clause

**Required by the brief. Every clause checked against the repository.**

| # | `DD-08` clause | Verified | Evidence |
|---|---|---|---|
| 1 | A `notifications` table with **type, message, read/unread, optional `match_id`** | ✅ **Exact** | All four columns present with those semantics |
| 2 | **Promotion from the reserve** raises a notice | ✅ | `promoted`, four producers |
| 3 | **Removal by the organiser** raises a notice | ✅ | `removed`, from `remove_player` |
| 4 | **A match edit** raises a notice | ✅ | `match_updated`, to every registrant |
| 5 | **A match deletion** raises a notice | ✅ | `match_deleted`, to every registrant, **raised before the deletion** |
| 6 | **`match_id` uses `ON DELETE SET NULL`, not `CASCADE`** | ✅ **And asserted twice** | Once in the table definition, once idempotently — *"to guarantee the match reference never cascade-deletes notifications"* |
| 7 | **The "match deleted" notice survives the match** | ✅ | The notice is created first, and the `SET NULL` preserves it |
| 8 | **Push notifications out of scope, in the backlog** | ✅ | No push mechanism exists anywhere (§12.3) |
| 9 | **Purpose: understand why a match disappeared** | ✅ | Achieved by clauses 5, 6 and 7 together |

**`DD-08` is fully honoured. No clause is contradicted, weakened or partially
implemented.**

**One clarification, not a contradiction** (§3.7): the survival guarantee is
**match-scoped**. A notice does not survive its *community* — `purge_community`
deletes it deliberately and first. `DD-08` speaks only of match deletion, so
this is consistent; it is recorded because a reader could expect otherwise.

### 16.2 One observation — the type vocabulary exceeds `DD-08`'s event list

`DD-08` enumerates **four events**; the implementation carries **five types**.

**Not a contradiction** (§4.3): `moved_to_reserve` is a consequence of the
*match edit* event `DD-08` lists, and the type vocabulary is simply
finer-grained than the event list.

**But it means the vocabulary is governed by no approved document**, which is
`NT-R2`'s root.

### 16.3 Checked and found consistent

| Source | Verdict |
|---|---|
| `Matches_Table_Specification.md` §6.4 | **Consistent.** Its deletion ordering step 2 is §3.7 here, from the other side |
| `Communities_Table_Specification.md` §6.4 | **Consistent.** Its step 2 exists precisely because of the `SET NULL` |
| `Community_Members_Table_Specification.md` | **Consistent.** `purge_membership` raises `promoted`; no membership state is stored here |
| `Match_Registrations_Table_Specification.md` | **Consistent.** Every promotion notice accompanies a registration change, in the same transaction |
| `Profiles_Table_Specification.md` §5.2 | **Consistent.** `notifications` is listed as a Group A cascade — confirmed |
| `SUPABASE_OPERATIONAL_GUIDELINES.md` §4 | **Consistent.** RLS enabled, access explicit, the helper revoked from client roles, not broadly readable |
| `Docs/01-PRD.md` | **Consistent.** *In-app notifications are in scope and built; push notifications are out of scope* |

**No contradiction found in any approved document.**

---

## 17. Open Decisions

**One.**

| ID | Question | Recommendation |
|---|---|---|
| `NT-D1` | **Should `type` gain a CHECK constraint over the five known values?** | **Yes** (`NT-C4`). It is the only mechanism that would make a mistyped or unmapped new type fail loudly rather than render as Arabic. **The cost is that every new type becomes a migration** — which is the correct trade, because every new type already requires a client change (§13.7) and shipping one without the other is exactly the failure the constraint prevents |

**`NT-C9` — restricting the update to `is_read` — is not an open decision.** It
is a defect with an obvious fix and no trade-off, recorded as `NT-R1`.

---

## 18. Engineering Approval

**Status: Engineering Approved — conditional** on `NT-R1` and `NT-R2`.

**Neither is High**, and §15.1 explains why: nothing in this table is authority,
so no defect here can reach a business record. **The conditional status reflects
that both are cheap to close and both are silent failures if left.**

| Criterion | Status |
|---|---|
| Purpose, business owner, domain ownership, consumers, scope | ✓ §1 |
| **Entity responsibilities — owned and not owned, with the six infrastructure statements verified** | ✓ §2 |
| Lifecycle — creation, delivery, reading, retention, deletion; seven valid transitions, five invalid | ✓ §3 |
| **Notification model — five types, each with meaning, trigger, producer, consumer, lifetime** | ✓ §4 |
| Relationships — ownership, cardinality, deletion, lifecycle dependency | ✓ §5 |
| Every column — purpose, meaning, ownership, mutability, default, justification | ✓ 7 of 7 |
| Keys — primary, candidate, alternate, business, foreign, each explained | ✓ §7 |
| Constraints — enforced, missing, inherited, recommended | ✓ 12 |
| Index strategy — existing, required, redundant, access patterns | ✓ §9 |
| Access control — create, read, update, delete; RLS conceptually | ✓ §10 |
| Audit — ownership, history, immutability, read tracking, deletion tracking | ✓ §11 |
| Dependency review — upstream, downstream, external | ✓ §12 |
| Future compatibility — seven candidates | ✓ §13 |
| Engineering review — eight audits | ✓ §14 |
| Risks — High, Medium, Low with cause, impact, recommendation | ✓ §15, six risks |
| **Contradictions — `DD-08` validated clause by clause; none found** | ✓ §16 |
| Open decisions | ✓ §17, one |
| No SQL, no views, no RPC, no implementation | ✓ |

---

## 19. Validation

| # | Source | Verdict |
|---|---|---|
| 1 | **`Docs/10-Design-Decisions.md` — `DD-08`** | **Validated clause by clause; fully honoured** (§16.1) |
| 2 | **The repository — migration `0006`** | Table, index, three policies and the revoked function all verified directly |
| 3 | **The repository — all sixteen `create_notification` call sites** | Five types and six producers confirmed (§4) |
| 4 | **The repository — the client's rendering path** | Localizes from `type`, falls back to `message` (§14.4) |
| 5 | `Matches_Table_Specification.md` | **Consistent** — the deletion ordering |
| 6 | `Communities_Table_Specification.md` | **Consistent** — step 2 of the ordered purge |
| 7 | `Community_Members_Table_Specification.md` | **Consistent** — `purge_membership` raises `promoted` |
| 8 | `Match_Registrations_Table_Specification.md` | **Consistent** — promotion notices accompany registration changes |
| 9 | `Profiles_Table_Specification.md` | **Consistent** — Group A cascade |
| 10 | `Docs/01-PRD.md` | **Consistent** — in-app in scope, push out |
| 11 | `Docs/06-ERD.md` | **Consistent** — the notification entity and its `SET NULL` |
| 12 | `SUPABASE_OPERATIONAL_GUIDELINES.md` §4 | **Consistent** |
| 13 | **Database Principles** | **No artifact in the repository** — eighteenth phase |

---

## Related documents

| Document | Relationship |
|---|---|
| `Docs/10-Design-Decisions.md` | **`DD-08`** — the governing decision, validated in §16.1 |
| `engineering/Matches_Table_Specification.md` | The referenced match; its §6.4 deletion ordering depends on the `SET NULL` |
| `engineering/Communities_Table_Specification.md` | §6.4 step 2 deletes these rows first, and §3.7 explains why |
| `engineering/Match_Registrations_Table_Specification.md` | Every promotion notice accompanies a registration change |
| `engineering/Community_Members_Table_Specification.md` | `purge_membership` is one of the six producers |
| `engineering/Profiles_Table_Specification.md` | The recipient; Group A cascade |
| `Docs/01-PRD.md` | In-app notifications in scope; push out |
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | §4 security checklist |
