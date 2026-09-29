# Go Play Intelligence — Wave 3 Evidence Design

**Status:** APPROVED — Product Owner approved decisions 1–5; implementation may proceed, no Wave 3 migration applied yet  
**Branch:** `intelligence/wave3-evidence`  
**Base:** `develop` at `93d9cd56c656d4945ae700bf4658e56c9e7e58a1`  
**Database:** shared live Supabase project; Production data plane  
**Scope:** BTGE Generation Evidence + Anonymous Acquisition Context

---

## 1. Purpose

Wave 3 closes two evidence gaps approved in the Wave 0 contract:

1. preserve the BTGE-generated state **before human edits**, so internal analysis can compare
   `Generated → Final → Result`;
2. measure whether a signed-out reader who arrives through a public Go Play link
   creates an account, without fingerprinting the reader and without building a second
   analytics system.

Wave 3 does not change BTGE optimization rules, player ratings, team-generation
settings, the public information shown, or Production release policy.

---

## 2. Current-state findings

### 2.1 BTGE

Current flow:

1. `TeamRepository.fetchGenerationInputs` reads:
   - confirmed account players;
   - rating;
   - date of birth;
   - primary / secondary position;
   - match date;
   - approved teammate-history lookback.
2. `BtgeEngine.generate` runs entirely in Flutter/Dart.
3. `TeamRepository.generateTeams` currently returns only `List<TeamAssignment>`.
4. `TeamsScreen` then calls `saveLineup`.
5. `saveLineup` calls the existing database RPC `replace_match_lineup(..., p_from_generation=true)`.
6. `match_team_assignments` becomes the mutable current/final lineup.
7. Manual edits and later completed-match corrections can change that same lineup.

There is currently **no BTGE generation-history table**.

Important consequence:

> Once an organizer edits or regenerates a lineup, the engine's previous proposal is lost.

The engine already computes quality metrics, but the approved Wave 0 contract says not
to persist derived BTGE scores that can be recalculated from captured inputs.

### 2.2 Product analytics

`product_events` is the one product analytics table.

Current contract:

- `user_id uuid NOT NULL`;
- eleven event names;
- `record_product_event` derives the actor from `auth.uid()`;
- `anon` cannot execute the writer;
- signed-out public-link opens therefore cannot be recorded.

Current live event coverage confirms `public_link_opened` exists only for
authenticated readers.

### 2.3 Public-link routing

`PendingPublicLink` deliberately survives sign-in:

> a visitor who opens a player's profile and then registers should still be
> looking at that player afterwards.

However, the current signed-in transition only starts the account check/session.
It does not explicitly call the pending-public-link opener after authentication.

That means the intended post-auth destination continuity is not guaranteed by the
current implementation.

---

## 3. Recommended BTGE Generation Evidence

### 3.1 Preserve one immutable record per successful generation save

Add one append-only table:

`btge_generation_runs`

Recommended fields:

| Field | Purpose |
|---|---|
| id uuid PK | generation identity |
| match_id uuid | match the proposal belongs to |
| community_id uuid | immutable scope snapshot |
| generated_by uuid | organizer account |
| generated_at timestamptz | database time |
| generation_sequence bigint | order of generations within the match |
| variant_index integer | deterministic BTGE variant used |
| configuration jsonb | exact generation configuration used |
| player_inputs jsonb | minimal immutable player input snapshot |
| history_context jsonb | exact diversity context used |
| generated_lineup jsonb | engine proposal before guests/manual edits |

No quality score columns are stored.

### 3.2 Minimal input snapshot

For every account player supplied to BTGE, store only:

- `user_id`;
- `overall_rating`;
- `age_at_match`;
- `primary_position`;
- `secondary_position` nullable.

Do **not** store:

- player name;
- phone/email;
- avatar;
- date of birth;
- raw profile metadata.

Rationale:

BTGE uses date of birth only to derive age at the match date. Persisting
`age_at_match` reproduces the engine input relevant to balancing while avoiding an
extra immutable copy of DOB.

### 3.3 Diversity context

Store the exact teammate-pair set supplied to priority 5, together with the effective
lookback configuration.

Do not store a derived `repeat_pair_count`; it can be recalculated.

This avoids depending on future historical-lineup corrections when reproducing what
the engine knew at generation time.

### 3.4 Generated lineup

Store account assignments only:

- `user_id`;
- team A/B;
- assigned position;
- assignment basis.

Professional Guests are excluded because BTGE never sees them.

The current/final participant state remains `match_team_assignments`.

### 3.5 Write contract

Do not replace `replace_match_lineup`.

Add a new generation-only RPC, e.g.:

`save_generated_lineup_v1(...)`

It performs one transaction:

1. authorization and match-state checks;
2. saves the generated account lineup using the existing authoritative lineup rules;
3. captures the immutable BTGE evidence row;
4. returns success only if both succeed.

Legacy clients and manual-edit paths keep using existing RPCs unchanged.

A failed lineup save leaves no generation evidence row.
A failed evidence insert leaves no lineup change.

---

## 4. Recommended Anonymous Acquisition Model

### 4.1 Scope

Wave 3 measures only:

> **signed-out public-link open → successful new account registration in the same running acquisition session**

Do not expand Wave 3 to general anonymous Discover browsing.

Do not count an existing account logging in as a new-user acquisition conversion.

### 4.2 Extend the existing analytics system

Keep `product_events` as the one analytics table.

Proposed additive changes:

- allow `user_id` to be null only for explicitly approved anonymous acquisition rows;
- add nullable `acquisition_id uuid`;
- add event `public_link_signup_completed`.

Existing authenticated events remain unchanged.

### 4.3 Anonymous open

Add a narrow RPC:

`record_anonymous_public_link_open(...)`

Characteristics:

- callable intentionally by `anon`;
- accepts only the one event shape it owns;
- creates a database-generated random `acquisition_id`;
- inserts `public_link_opened` with `user_id = null`;
- returns the `acquisition_id`;
- records platform/app version;
- records public-link kind through a bounded source value:
  - `public_link_player`
  - `public_link_community`
  - `public_link_match`
- does **not** persist the player/community/match target UUID for anonymous opens;
- records no IP address, device id, user agent, fingerprint, cookie id, email,
  phone, name, or auth metadata.

The client calls it only after the public destination has successfully loaded.

Analytics failure never blocks public reading.

### 4.4 Same-session conversion

The returned `acquisition_id` is held only in app memory for this MVP.

It is **not** persisted to local storage, cookies, secure storage, auth metadata, or
the user profile.

After a successful **new registration**, the now-authenticated client sends the same
`acquisition_id` to a second RPC:

`record_public_link_signup_completed(p_acquisition_id uuid)`

The RPC:

- requires `auth.uid()`;
- validates that the acquisition row exists and is an anonymous
  `public_link_opened`;
- verifies the authenticated account was created at or after that anonymous open,
  so an older account logging in cannot manufacture a signup conversion;
- inserts an authenticated `public_link_signup_completed` event carrying the same
  `acquisition_id`;
- does not modify/back-date the anonymous open row;
- is idempotent per acquisition id;
- exposes no anonymous row to the client.

This makes conversion derivable as:

anonymous `public_link_opened`
→ same `acquisition_id`
→ authenticated `public_link_signup_completed`.

### 4.5 Measurement boundary

Because the id is memory-only:

- conversion is measurable within the same running app/browser instance;
- a refresh, app kill, different device or different browser does not get stitched
  together.

That limitation is deliberate for MVP.

It avoids persistent pseudonymous tracking and device fingerprinting.

The Admin surface must label this metric accordingly, e.g. **Same-session public-link
signup conversion**, not universal attribution.

---

## 5. Public-link continuity correction

When authentication changes from signed-out to signed-in and an active
`PendingPublicLink` still exists:

1. finish the existing active-account gate;
2. open the pending public destination through the current signed-in route;
3. clear the pending target only when it is being acted on.

Registration conversion telemetry and navigation remain independent:

- telemetry failure does not prevent navigation;
- navigation failure does not fabricate a conversion;
- login by an existing account resumes the destination but records no signup conversion.

This implements the behavior the current `PendingPublicLink` documentation already
states.

---

## 6. Security and privacy boundaries

### BTGE evidence

- RLS enabled;
- no direct `anon` or `authenticated` access;
- append-only evidence;
- no names/emails/phones/DOB;
- no direct client table write;
- admin/internal reads only through future scoped RPCs.

### Anonymous acquisition

An anon-executable writer is an intentional public API endpoint and must therefore:

- own exactly one narrow insert shape;
- validate bounded event/source values;
- generate acquisition id on the server;
- never accept a user id;
- never return other analytics rows;
- never read private account/community data;
- have all default `PUBLIC` privileges explicitly revoked and only the required
  role granted;
- pass Supabase Security Advisor review.

`product_events` itself remains inaccessible for direct client writes/reads.

---

## 7. What Wave 3 does NOT do

- no cross-device attribution;
- no persistent anonymous cookie/device id;
- no IP/user-agent storage;
- no ad attribution;
- no general anonymous Discover analytics;
- no new analytics vendor;
- no second analytics event table;
- no BTGE algorithm change;
- no BTGE tuning;
- no player-facing BTGE quality score;
- no historical reconstruction of past generation attempts;
- no Production deployment.

Existing historical matches/generations remain without BTGE generation evidence.

---

## 8. Required validation

### BTGE

- first generation produces one immutable run;
- regeneration produces a second run, never overwriting the first;
- generated evidence is written atomically with the generated lineup save;
- failed save produces no evidence;
- manual move/swap/position change produces no new generation run;
- completed correction produces no generation run;
- Professional Guests are absent from the generated BTGE snapshot;
- no BTGE quality scores are persisted;
- captured player inputs reproduce the inputs used by the engine.

### Anonymous acquisition

- signed-out successful public-link load records one anonymous open;
- failed/not-found public destination records none;
- no direct anon access to `product_events`;
- anonymous writer accepts only the approved public-link event shape;
- successful registration with pending acquisition records one conversion;
- registration failure records no conversion;
- existing-user login records no signup conversion;
- duplicate completion call is idempotent;
- analytics failure never blocks registration or routing;
- pending public target resumes correctly after registration/login;
- no local persistent tracking identifier is created.

---

## 9. Product Owner decisions — APPROVED

1. **Anonymous scope — APPROVED**  
   Wave 3 anonymous measurement is limited to public shared links only,
   excluding general Discover browsing.

2. **Privacy boundary — APPROVED**  
   Same-running-session attribution only, with a server-generated random UUID
   kept in memory and no cookie/local-storage/device fingerprint.

3. **Conversion definition — APPROVED**  
   Only successful **new registrations** count as acquisition conversion;
   login by an existing account resumes the link but is not a conversion.

4. **Analytics storage — APPROVED**  
   Extend the existing `product_events` table with nullable
   `acquisition_id` / controlled anonymous rows instead of creating a second analytics
   table.

5. **Public-link continuity — APPROVED**  
   Correct the current auth transition so a visitor who registers or logs in
   from a public link returns to that same public target after authentication.

BTGE evidence storage is an engineering implementation of the already-approved Wave 0
BTGE Generation Evidence contract and introduces no new user-facing behavior.

### Engineering decisions frozen for implementation

- anonymous acquisition rows store link **kind**, not the target UUID;
- the anonymous writer is intentionally narrow and may be callable by `anon`, while
  direct table privileges remain revoked;
- signup completion must be server-validated against the account creation time;
- no historical backfill is allowed for BTGE runs or anonymous acquisition;
- legacy `record_product_event` and legacy generated-lineup write contracts remain
  available for older clients; Wave 3 adds new bounded contracts instead of replacing them.
