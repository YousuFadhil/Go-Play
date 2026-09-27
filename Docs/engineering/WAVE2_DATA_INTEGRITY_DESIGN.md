# Go Play Intelligence — Wave 2 Data Integrity Design

**Status:** PROPOSED — design only, no Wave 2 migration applied  
**Branch:** `intelligence/wave2-data-integrity`  
**Base:** `develop` at `bc4ec45dcdff6ae02aa23adb427b91142a37540c`  
**Database:** shared live Supabase project; Production data plane  
**Rule:** no historical backfill by inference or guess

---

## 1. Purpose

Wave 2 adds the minimum missing raw evidence needed to stop treating mutable
current-state rows as historical truth.

Approved scope:

1. Participation Truth
2. Registration Lifecycle
3. Membership Lifecycle

Wave 2 does **not** change the rating formula, team generator, notification
product behavior, or Production release branch.

---

## 2. Current write-path findings

### 2.1 Match registration

Current account registration state lives in `match_registrations`.

All ordinary app writes go through database RPCs:

- self registration → `register_for_match` → `register_player_in_match`
- organizer add → `admin_add_player_to_match` → `register_player_in_match`
- self withdrawal → `withdraw_from_match`
- organizer removal → `remove_player`
- reserve promotion/demotion → `rebalance_roster`
- organizer roster ordering → `set_match_roster_order` / `swap_match_participants`
- membership removal → `purge_membership`
- completed factual correction → `set_completed_match_player` /
  `correct_completed_match_players`
- match/community/account deletion can also remove registration rows through
  purge/admin functions.

Important consequence:

> `match_registrations` is current state, not lifecycle history.

A withdrawn or removed registration can disappear completely.

### 2.2 Community membership

Current membership state lives in `community_members`.

Writes currently occur through:

- community creation → owner membership insert
- open join / code join → player membership insert
- role change → `set_member_role`
- ownership transfer → `transfer_ownership`
- organizer removal → `remove_member` → `purge_membership`
- community/account deletion purge paths.

No ordinary user “leave community” RPC exists in the current product.

Important consequence:

> Absence from `community_members` cannot tell us when or why someone left.

### 2.3 Participation

The current product already treats `match_team_assignments` as the factual
played lineup once a match is completed:

- result validation requires a stored lineup;
- MVP and scorers must belong to that lineup;
- ratings/statistics are applied from that lineup;
- completed-match correction explicitly edits “who actually played”.

Therefore Wave 2 must **not** create a second participant list.

The missing fact is only:

> Has an organizer explicitly confirmed that the current completed lineup is the
> factual participation record?

---

## 3. Recommended architecture

### 3.1 Registration lifecycle — append-only raw evidence

Add one table:

`match_registration_events`

Proposed fields:

| Field | Purpose |
|---|---|
| event_no bigint identity PK | deterministic event order |
| registration_id uuid | identity of the mutable registration row |
| match_id uuid | match snapshot identifier |
| community_id uuid | community snapshot identifier |
| user_id uuid | account participant only |
| actor_user_id uuid nullable | authenticated actor when available |
| operation text | `created`, `status_changed`, `deleted` |
| from_status text nullable | previous confirmed/reserve |
| to_status text nullable | new confirmed/reserve |
| match_was_completed boolean | separates live demand from historical correction |
| occurred_at timestamptz | event time |

No Professional Guest events are stored here. Guests are organizer-created
match participants, not community registration demand.

Capture mechanism:

- one database trigger on `match_registrations`;
- account rows only (`user_id is not null`);
- INSERT → `created`;
- UPDATE only when `status` changes → `status_changed`;
- DELETE → `deleted`.

No Flutter write is added.

No existing registration RPC needs to be replaced solely to collect the raw
evidence.

Semantic information is derived later:

- created before completion → registration;
- reserve → confirmed before completion → promotion;
- confirmed → reserve before completion → moved to reserve;
- deleted before completion with actor = target → self removal/withdrawal;
- deleted before completion with another actor → organizer/system removal;
- any change after completion → historical participation correction, not demand.

Events whose match/community was later deleted must be excluded from current
community demand metrics rather than interpreted as ordinary churn.

### 3.2 Membership lifecycle — append-only raw evidence

Add one table:

`community_membership_events`

Proposed fields:

| Field | Purpose |
|---|---|
| event_no bigint identity PK | deterministic event order |
| membership_id uuid | identity of the mutable membership row |
| community_id uuid | community snapshot identifier |
| user_id uuid | member |
| actor_user_id uuid nullable | authenticated actor |
| operation text | `joined`, `role_changed`, `deleted` |
| from_role text nullable | owner/admin/player |
| to_role text nullable | owner/admin/player |
| occurred_at timestamptz | event time |

Capture mechanism:

- trigger on `community_members`;
- INSERT → `joined`;
- UPDATE only when role changes → `role_changed`;
- DELETE → `deleted`.

“Rejoined” is derived when a later `joined` follows a prior `deleted` for
the same community/user after Wave 2 capture began.

Because there is no current self-leave feature, Wave 2 does not invent a
historical `left` event. A future self-leave path can be distinguished by
actor/user identity without changing this table.

### 3.3 Security for lifecycle evidence

Both event tables:

- append-only by trigger;
- RLS enabled;
- direct `anon` and `authenticated` table access revoked;
- no client INSERT/UPDATE/DELETE policy;
- no foreign keys to mutable/deletable business rows, so deleting a match,
  membership or user cannot erase the evidence;
- no personal snapshot fields such as names/emails.

Later read RPCs expose only aggregates or authorized scoped history.

---

## 4. Participation Truth

### 4.1 Do not duplicate participants

`match_team_assignments` remains the one participant source.

Add only one small state table:

`match_participation_state`

Proposed fields:

| Field | Purpose |
|---|---|
| match_id uuid PK | one state row per existing match |
| lineup_revision bigint | increments whenever the lineup changes |
| confirmed_revision bigint nullable | revision explicitly confirmed |
| confirmed_at timestamptz nullable | latest confirmation time |
| confirmed_by uuid nullable | organizer who confirmed |

A participation record is authoritative when:

`confirmed_revision = lineup_revision`

No player IDs are copied into this table.

### 4.2 Lineup revision trigger

Add a trigger on `match_team_assignments`:

- any INSERT / UPDATE / DELETE increments the match's `lineup_revision`;
- for a completed match, an explicit completed-participant correction may also
  confirm the resulting latest revision because that action itself says
  “these are the people who actually played”;
- deleting the match cascades/removes its participation-state row.

This ensures an old confirmation cannot remain valid after the lineup changes.

### 4.3 Initial confirmation

Add an authenticated organizer-only RPC:

`confirm_match_participation(p_match_id uuid)`

Server rules:

- authenticated active account;
- active community;
- owner/admin role;
- match completed by the existing authoritative completion rule;
- non-empty stored lineup;
- sets `confirmed_revision = lineup_revision`,
  `confirmed_at = now()`, `confirmed_by = auth.uid()`.

It does not alter ratings, statistics, result, goals, registrations or lineup.

### 4.4 Product integration

Recommended UX:

In Result Entry for a completed match, add one required confirmation:

> “I confirm that the lineup represents the players who actually participated
> in this match.”

Save Result remains unavailable until it is confirmed.

The save sequence is:

1. confirm participation;
2. save the result through the existing result transaction.

These facts are intentionally independent. If result validation fails after the
confirmation succeeds, participation evidence remains valid because the
organizer still confirmed the lineup.

For a previously confirmed lineup, the UI may show it already confirmed only
while `confirmed_revision = lineup_revision`.

If a completed lineup is corrected later, the revision changes and the previous
confirmation is no longer current.

---

## 5. What Wave 2 does NOT change

- No historical rows are fabricated.
- Existing completed matches start as **unknown/unconfirmed** unless a future
  organizer action confirms them.
- `match_registrations` remains the current roster state.
- `community_members` remains the current membership state.
- `match_team_assignments` remains the participant source.
- Rating/statistics calculations remain unchanged in Wave 2.
- Wave 1 Community Insights remains explicitly provisional until sufficient
  confirmed participation evidence exists.
- No new fourth community tab.
- No Production deployment to `main`.

---

## 6. Shared-database safety

Because Staging and Production use the same Supabase project:

1. create only additive tables/functions/triggers;
2. do not rename/drop existing columns or RPCs;
3. event capture must not change return values or business decisions;
4. migrations must contain no historical DML backfill;
5. legacy Production clients must continue using current RPCs unchanged;
6. new UI uses only additive reads/actions;
7. schema/data integrity baseline is recorded before migration and checked after;
8. tests must prove failed business transactions leave no lifecycle event behind
   because trigger rows roll back in the same transaction.

---

## 7. Required tests before Staging

### Registration lifecycle

- self confirmed registration
- self reserve registration
- organizer add
- reserve promotion
- move to reserve after capacity/order change
- withdrawal
- organizer removal
- membership purge of future registrations
- completed participant correction is not counted as new demand
- failed registration produces no event

### Membership lifecycle

- community creation owner join
- open/code join
- player → admin / admin → player
- ownership transfer produces both role changes
- organizer member removal
- failed join/role/remove produces no event
- no guessed historical events

### Participation

- unconfirmed completed match is not authoritative
- confirmation requires organizer and completion
- confirmation requires non-empty lineup
- confirmation writes no rating/stat/result changes
- lineup edit invalidates prior revision
- completed participant correction establishes/renews current evidence if that
  behavior is approved
- match deletion removes only current participation state, not lifecycle history

---

## 8. Decisions requiring Product Owner approval before migration

1. **Participation confirmation UX**  
   Require the organizer to explicitly confirm the played lineup in Result Entry
   before saving a result.

2. **Completed correction behavior**  
   Treat an organizer's completed-match “Played Participants” correction as an
   implicit confirmation of the resulting lineup revision.

3. **Lifecycle storage model**  
   Approve the two append-only raw event tables plus one small participation
   state table rather than modifying current business tables to store history.

No Wave 2 schema/code implementation starts until these three decisions are
approved.
