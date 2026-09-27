# Go Play Intelligence — Wave 0 Metric & Safety Contract

**Status:** ACTIVE — Wave 0 approved by Product Owner  
**Scope:** Football Intelligence, Community Intelligence, Product Intelligence, Operational Intelligence  
**Working branch:** `intelligence/wave0-contracts` (based on `develop`)  
**Production branch:** `main` — MUST NOT be modified by this work until explicit Product Owner approval  
**Database:** Current live Supabase project; treat as Production data even when the UI build is Staging  
**Baseline captured:** 2026-09-27 (Asia/Muscat)

---

## 1. Purpose

This document is the single Wave 0 contract for turning existing Go Play data into useful information without duplicating data, duplicating UI, or weakening the current production system.

It defines:

1. the current baseline;
2. source-of-truth rules;
3. metric definitions;
4. where each information item belongs in the UI;
5. what is already present and must not be recreated;
6. safety invariants for shared-DB Staging work;
7. which later metrics are blocked by missing evidence.

This document does **not** authorize destructive database changes, Production deployment, or a new analytics platform.

---

## 2. Environment Safety Contract

### 2.1 Staging

The existing Staging workflow publishes to the separate Cloudflare Pages project `go-play-staging` and can build an arbitrary source ref, defaulting to `develop`.

Staging UI isolation does **not** imply database isolation.

The actual values of the GitHub `staging` environment secrets are not readable through the current connector, therefore this work must **not assume** that Staging uses a separate Supabase database.

Until separately proven otherwise:

> **Any Staging build connected to the current Supabase project is operating on Production user data.**

### 2.2 Shared-database rules

Allowed without another Product Owner decision:

- read-only SQL inspection;
- read-only views/RPCs that are additive and do not change existing contracts;
- derived calculations;
- UI development that performs only existing safe reads;
- tests using mocks/local test doubles;
- documentation.

Not allowed as ad-hoc testing:

- `INSERT`, `UPDATE`, or `DELETE` against real user/business rows;
- join/withdraw/create/edit actions merely to create test data;
- destructive or speculative backfills;
- notification-producing test actions against real users;
- schema drops, renames, destructive ALTERs;
- replacing current RPC/view contracts while Production clients still depend on them.

If an end-to-end test later requires a real write, execution stops before that write and the exact test impact is presented to the Product Owner.

### 2.3 Additive migration rule

While Staging and Production may share one database:

> **Add, do not replace.**

For intelligence work:

- prefer new read contracts such as `*_v2`;
- do not alter an existing Production read contract merely to serve Staging;
- no DROP;
- no rename;
- no trigger change during Wave 1;
- no write-path change during Wave 1;
- no RLS weakening;
- no historical reconstruction from guesses.

---

## 3. Baseline Snapshot

### 3.1 Repository / release baseline

| Item | Baseline |
|---|---|
| `develop` | `513956cb980c5935163d2e11218adca63728e1fe` |
| `main` | `7cefd7b4584cded2914c2bd2407b0d6db64488af` |
| Latest Production deploy observed | successful, same `main` SHA |
| Flutter deployment version | 3.44.7 |
| Latest live migration | `20260919161928 / 0084_team_of_week_closed_sunday_saturday` |

### 3.2 Live data counts

These counts are a point-in-time baseline only. The database is live, so later differences are not automatically defects.

| Entity | Rows |
|---|---:|
| users | 37 |
| communities | 1 |
| community_members | 34 |
| matches | 28 |
| match_registrations | 410 |
| match_team_assignments | 395 |
| match_results | 28 |
| match_goals | 152 |
| player_statistics | 32 |
| community_statistics | 270 |
| rating_history | 1292 |
| notifications | 1075 |
| product_events | 595 |
| match_professional_guests | 24 |
| notification_push_tokens | 13 |
| admin_audit_log | 2 |

Match classification at baseline:

- ended/completed by effective definition: **28**
- historical matches: **7**
- normal matches: **21**

### 3.3 Data integrity baseline

At capture time:

- duplicate current memberships: **0**
- duplicate account registrations per match: **0**
- `reconcile_community_statistics()` mismatches: **0**

These are Safety Gates, not immutable row-count expectations.

---

## 4. Existing Data That MUST NOT Be Duplicated

| Information / evidence | Existing authoritative source | Rule |
|---|---|---|
| current global rating | `users.overall_rating` / current profile views | no new rating field |
| rating changes | `rating_history` | derive trend; do not copy |
| career W/D/L/goals/MVP/matches | `player_statistics` | no duplicate stats table |
| period player/community counters | `community_statistics` | reuse |
| recent form | `player_recent_form` and public equivalent | already implemented; do not recreate |
| recent achievements/highlights | current player record functions | reuse |
| current community membership | `community_members` | remains current-state truth |
| current match registration state | `match_registrations` | remains current-state truth |
| current/final team assignment state | `match_team_assignments` | do not create a second final-lineup table |
| result | `match_results` | reuse |
| goals | `match_goals` | reuse |
| Team of Period | current snapshots/awards | reuse |
| in-app notification | `notifications` | notification creation truth |
| push token | `notification_push_tokens` | reuse |
| product behavioral telemetry | `product_events` | extend carefully later; do not create a parallel analytics system |
| privileged admin actions | `admin_audit_log` | reuse |
| backend request/log health | Supabase logs | do not copy into a general app log table |
| release history | GitHub Actions | do not duplicate in DB |

---

## 5. Information Surface Ownership

Principle:

> **One information item has one primary surface per audience. Repetition is permitted only when context is required to understand another metric.**

### 5.1 Player Profile

Current ownership:

- identity;
- career figures;
- Recent Form;
- recent achievements;
- share profile.

Do **not** add a second Recent Form or a full analytics block.

### 5.2 Player Statistics

Primary home for numeric self-analysis:

- current rating;
- Matches / W / D / L / Goals / MVP;
- Weekly / Monthly / All Time;
- **Win Rate** — Wave 1;
- **Goals per Match** — Wave 1;
- **Rating Trend** — Wave 1.

Recent Form stays on Profile.

### 5.3 Community Statistics

Current ownership remains football/community record:

- completed matches;
- total players for selected statistics period;
- goals;
- Team of Period;
- leaderboards.

Do **not** place organizer operations metrics here.

### 5.4 Community Insights — Organizer only

Planned primary surface for Community Intelligence:

- Active Members 30d;
- Participation Rate 30d;
- Match Frequency;
- Capacity Utilization;
- Guest Dependency;
- later: Reserve Demand / Promotion Rate / Membership Growth / Churn.

Preferred navigation location: existing Community organizer actions, not a fourth general member tab.

### 5.5 Match Details

No analytics dashboard.

Later Participation Truth belongs to the result/finalization workflow so the stored final lineup can become reliable evidence of who played.

### 5.6 Platform Admin

Existing Admin Overview is the primary Product Intelligence surface.

Extend the existing structure instead of creating a second product dashboard.

Internal football/BTGE diagnostics, when implemented, also belong under Platform Admin / drilldown rather than player-facing screens.

### 5.7 Operational Intelligence

Primary sources remain operational tools:

- GitHub Actions;
- Supabase project/logs/advisors;
- Cloudflare.

Do not bring infrastructure credentials or a full operations console into Flutter for MVP.

---

## 6. Metric Contract — Football Intelligence

### FI-01 Win Rate

**Definition**

`wins / matches_played * 100`

- source: the same statistics record currently displayed for the selected period;
- if `matches_played = 0`: display as unavailable, not 0%;
- draws remain in the denominator because they are played matches.

**Primary surface:** Player Statistics  
**Raw data required:** none

### FI-02 Goals per Match

**Definition**

`goals / matches_played`

- same period as the currently selected statistics period;
- if `matches_played = 0`: unavailable;
- presentation precision is UI-only and must not be persisted.

**Primary surface:** Player Statistics  
**Raw data required:** none

### FI-03 Rating Trend

**Definition**

Net rating movement across the player's most recent **up to five completed played matches**.

Implementation rule:

1. use the same recent completed-match population represented by current Recent Form;
2. aggregate **all** `rating_history.delta` rows by `match_id`, including reversals/corrections so the net match effect is authoritative;
3. sum the net effect for the most recent up to five matches;
4. do not store a second rating snapshot.

This is a recent directional indicator, not a historical rating replacement.

**Primary surface:** Player Statistics  
**Raw data required:** none

### FI-04 Recent Form

Already implemented through `player_recent_form`.

**Primary surface:** Profile  
**Action:** no change; explicitly protected from duplicate display.

### FI-05 Position Fit

Internal calculation:

`PRIMARY or SECONDARY assignment count / eligible account assignment count`

- guest assignments excluded from player position fit;
- intended for BTGE evaluation, not a player score.

**Primary surface:** internal/admin football diagnostics  
**Raw data required:** none for current/final fit

### FI-06 Actual Participation

Current proxy: presence in `match_team_assignments`.

Status: **PROVISIONAL / evidence gap**.

Future authoritative meaning: final confirmed participant evidence after match finalization.

Do not label current proxy as attendance/no-show truth.

---

## 7. Metric Contract — Community Intelligence

Unless otherwise stated, Community Intelligence excludes `is_historical = true` matches.

### CI-01 Active Members 30d

Wave 1 provisional definition:

A **current active account member** of the community with at least one account assignment in an ended/completed normal match whose `start_at` is within the rolling last 30 days.

Later, replace the assignment proxy with Actual Participation evidence without changing the public meaning of the metric.

**Primary surface:** Community Insights  
**Raw data required:** none in Wave 1

### CI-02 Participation Rate 30d

`Active Members 30d / eligible current active members * 100`

Eligible denominator:

- current `community_members`;
- joined account is active;
- role does not exclude participation.

If denominator is zero: unavailable.

**Primary surface:** Community Insights  
**Raw data required:** none in Wave 1

### CI-03 Match Frequency

Rolling 30-day normal completed/ended match count normalized to weeks:

`matches_in_last_30d / (30 / 7)`

Display may also show the raw 30-day match count if required for comprehension, but it is not stored.

**Primary surface:** Community Insights  
**Raw data required:** none

### CI-04 Capacity Utilization

Per eligible match:

`final_lineup_seats / starting_players * 100`

Wave 1 proxy:

- `match_team_assignments` account + professional guest seats;
- normal ended/completed matches only.

Community metric:

average per-match utilization for the selected rolling window.

Do not cap above 100%; a value above 100 is itself useful evidence.

Status: **PROVISIONAL until Actual Participation exists**.

**Primary surface:** Community Insights  
**Raw data required:** none in Wave 1

### CI-05 Guest Dependency

`professional_guest_assignment_count / total_final_assignment_count * 100`

- normal ended/completed matches;
- this is descriptive, not a quality score.

**Primary surface:** Community Insights  
**Raw data required:** none

### CI-06 Reserve Demand

Status: **BLOCKED by Registration Lifecycle evidence**.

Do not infer historical reserve demand from surviving current rows.

### CI-07 Membership Growth / Churn

Status: **BLOCKED by Membership Lifecycle evidence**.

Do not reconstruct historical leavers from absence in the current membership table.

---

## 8. Metric Contract — Product Intelligence

### PI-01 Total / New Users

Source: `users.created_at`.

Historically complete for rows that still exist in the current user table.

**Primary surface:** existing Admin Overview

### PI-02 DAU / WAU / MAU

Source: distinct authenticated `product_events.user_id` with `event_name='session_started'`.

Windows:

- DAU: current Muscat calendar day;
- WAU: current day + previous 6 Muscat calendar days;
- MAU: current day + previous 29 Muscat calendar days.

Scope limitation: authenticated tracked users only.

**Primary surface:** existing Admin Overview

### PI-03 Weekly Product Return

`users active in previous rolling 7-day window who are also active in current rolling 7-day window / users active in previous window`

If the previous cohort is empty: **null / not measurable**, not 0%.

**Primary surface:** existing Admin Overview

### PI-04 Matches Created

Source: `matches.created_at`.

Product-activity reporting excludes `is_historical=true` rows.

### PI-05 Results Recorded

Source: `match_results.created_at` joined to `matches`.

Product-activity reporting excludes historical matches.

### PI-06 Registrations

Current `product_events.match_registered` coverage is incomplete and `match_registrations` loses rows on withdrawal.

Therefore:

- current event-based number may be labeled only **Tracked Registrations**;
- it must not be presented as authoritative total registrations;
- authoritative registration lifecycle metrics are blocked until lifecycle evidence exists.

### PI-07 Feature Adoption

Source: behavioral `product_events` such as community view, match view, teams view, result view, share.

Use unique users + event counts; do not interpret event count alone as value delivered.

### PI-08 Share Adoption

Source: `share_used`.

Anonymous downstream conversion remains unmeasurable with the current authenticated-only event recorder.

### PI-09 Player / Organizer Activation

Status: **DEFERRED — not required for Wave 1**.

Do not freeze a North Star or activation window until new-user and lifecycle evidence are sufficient.

---

## 9. Metric Contract — Operational Intelligence

### OI-01 Backend Health

Source: Supabase project health.

No duplicate DB storage.

### OI-02 Server Error Rate

`HTTP 5xx requests / all backend requests * 100`

4xx is monitored separately as client/request rejection and is not treated as backend failure.

### OI-03 P95 Origin Latency

95th percentile of Supabase edge `response.origin_time` over the chosen operational window.

Current baseline observed: approximately **1.38 s** over the inspected sample.

This is a baseline, not yet an SLO.

### OI-04 Release Integrity

Healthy Production release requires:

1. latest Production workflow conclusion = success;
2. deployed workflow head SHA = expected `main` SHA;
3. application smoke checks pass when introduced.

Source: GitHub Actions + deployment checks.

### OI-05 Push Dispatch Success

Status: **BLOCKED by persistent dispatch outcome evidence**.

Do not equate `notifications` rows with successful Push delivery.

### OI-06 Client Error Rate

Status: **BLOCKED by client error reporting signal**.

Do not infer client health solely from Supabase/Cloudflare health.

---

## 10. Future Raw Evidence Contract

Only the following new evidence classes are currently justified.

### 10.1 Actual Participation Evidence

Purpose: distinguish generated/final lineup membership from confirmed participation.

Rule:

- do not create a second competing final-lineup source;
- confirmation evidence must make the authoritative final participant state unambiguous.

### 10.2 Registration Lifecycle

Append-only evidence for:

- registered;
- entered reserve;
- promoted;
- moved to reserve;
- withdrew;
- removed by organizer/admin.

No speculative backfill.

### 10.3 Membership Lifecycle

Append-only evidence for:

- joined;
- role changed;
- left;
- removed;
- rejoined.

No speculative backfill.

### 10.4 BTGE Generation Evidence

Capture the generated state **before human edits**, with enough immutable context to compare:

`Generated → Final → Result`.

Do not copy derived BTGE scores that can be recalculated from captured inputs.

### 10.5 Anonymous Acquisition Context

Must extend the analytics model without creating an unrelated parallel analytics system.

Privacy/security design required before implementation.

### 10.6 Push Dispatch Outcome

Persist minimal transport evidence only; do not persist secrets or full device tokens in the event record.

### 10.7 Client Error Signal

Minimum viable production error evidence only:

- timestamp;
- app version;
- platform;
- error fingerprint/category;
- sanitized diagnostic context.

No credentials, tokens, or unnecessary personal content.

---

## 11. Wave 1 Implementation Boundary

Wave 1 is limited to intelligence derivable from existing data.

### Allowed scope

- FI-01 Win Rate;
- FI-02 Goals per Match;
- FI-03 Rating Trend;
- CI-01 Active Members 30d;
- CI-02 Participation Rate 30d;
- CI-03 Match Frequency;
- CI-04 Capacity Utilization;
- CI-05 Guest Dependency;
- Product Admin read-model corrections that can be derived from existing authoritative sources;
- Staging-only UI placement consistent with Section 5.

### Database rule for Wave 1

If new database contracts are necessary, they must be:

- additive;
- read-only;
- separately named, preferably `*_v2`;
- non-destructive to existing Production contracts;
- permission-scoped at least as strongly as the data they expose.

Wave 1 does **not** authorize:

- Participation write flows;
- lifecycle event writes;
- BTGE generation history writes;
- anonymous tracking;
- Push dispatch logging;
- client crash/error telemetry;
- Production deployment.

---

## 12. Safety Gates for Every Later Database Change

Before:

1. confirm exact target project;
2. inspect current schema;
3. inspect current migration head;
4. record relevant row-count baseline;
5. run applicable reconciliation checks;
6. confirm no existing field/table already serves the purpose.

During:

1. one bounded migration;
2. no unrelated refactor;
3. no destructive DML unless separately approved;
4. no guessed historical backfill.

After:

1. verify new schema objects;
2. rerun relevant integrity/reconciliation checks;
3. verify legacy Production read paths still work;
4. compare critical counts for unexpected loss;
5. test Staging reads;
6. do not move `main` until Product Owner approval.

Because Production is live, legitimate concurrent user activity may change row counts. A count difference is investigated, not automatically treated as migration-caused.

---

## 13. Wave 0 Exit Criteria

Wave 0 is complete when:

- Source-of-Truth rules are documented;
- existing duplicated-risk data and surfaces are identified;
- metric formulas are fixed for Wave 1;
- blocked metrics are explicitly marked rather than guessed;
- Staging/shared-DB safety rules are fixed;
- baseline integrity checks pass;
- no Production code or user data was modified.

At document creation time, all of the above conditions are satisfied.

---

## 14. Next Engineering Step

Proceed to Wave 1 on the working branch, starting with **read models and tests before UI**.

Implementation order:

1. derive/read FI metrics;
2. derive/read Community Insights metrics;
3. correct Product Admin read models where current business-truth sourcing is incomplete;
4. add UI only after the read contracts are tested;
5. deploy the working branch to Staging only after confirming the Staging build is pointed at the expected Supabase project;
6. perform read-only smoke verification against live data.

No Production merge is part of Wave 1 without a separate Product Owner decision.
