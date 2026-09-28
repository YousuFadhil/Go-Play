# Go Play Intelligence — Wave 4 Operational Hardening Design

**Status:** APPROVED — Product Owner approved decisions 1–4; implementation may proceed, no Wave 4 migration or runtime change applied yet  
**Branch:** `intelligence/wave4-operational-hardening`  
**Base:** `develop` at `9aa9f9a140e1f0951c95c892086a2df9541dd87a`  
**Production branch:** `main` at `7cefd7b4584cded2914c2bd2407b0d6db64488af`  
**Database:** shared live Supabase project  
**Current migration head:** `0089_wave3_evidence_capture`

---

## 1. Purpose

Wave 4 closes the remaining Operational Intelligence evidence gaps without
building an operations console inside Flutter and without adding an external
monitoring vendor.

The approved Wave 0 operational sources remain:

- Supabase project health / logs / advisors;
- GitHub Actions;
- Cloudflare;
- minimal persistent application evidence only where logs cannot answer the
  question reliably.

Wave 4 therefore covers only:

1. persistent Push Dispatch Outcome evidence;
2. minimum viable production Client Error evidence;
3. release-integrity smoke checks;
4. abuse/cost circuit breakers for intentionally public telemetry writers.

No player/community product feature is added.

---

## 2. Current-state findings

### 2.1 Backend health and latency already exist in Supabase logs

The current Supabase unified logs API is sufficient for OI-02 and OI-03.
No database mirror is justified.

A read-only 24-hour sample inspected during this design contained:

- 870 non-OPTIONS backend requests;
- 0 HTTP 4xx;
- 0 HTTP 5xx;
- P95 origin latency: 866 ms.

This is a point-in-time operational sample, not an SLO.

The Supabase changelog confirms the old Management API `logs.all` endpoint was
removed on 2026-09-23. Operational queries must use the current unified `logs`
stream and filter by source.

### 2.2 Push transport has no persistent outcome evidence

Live Edge Function:

- `push-dispatch`
- ACTIVE
- version 7
- `verify_jwt=false` intentionally because the function authenticates the
  database trigger with `PUSH_DISPATCH_SECRET`.

The live function matches the repository implementation.

Current terminal outcomes already exist in code:

- `not_found`
- `suppressed`
- `no_devices`
- `unrenderable`
- `dispatched` with:
  - sent
  - stale
  - failed
- HTTP 500 for an internal failure

But these outcomes are returned only to the asynchronous pg_net call and are
not persisted.

`notifications` is the Notification Center truth and must not be interpreted
as push-delivery truth.

There is no push outcome table today.

### 2.3 Client failures are not reported in Production

Current `Diagnostics` is development instrumentation only.

- release builds normally do not record provider exceptions;
- there is no `FlutterError.onError` production reporter;
- there is no `PlatformDispatcher.instance.onError` production reporter;
- there is no client crash/error evidence table.

This correctly preserves privacy today but leaves OI-06 unmeasurable.

### 2.4 Release workflow has build guards but no post-deploy smoke gate

Both workflows validate the bundle before publishing.

Production currently checks:

- required Supabase configuration exists;
- no `service_role` marker enters the bundle;
- a known application marker exists;
- Cloudflare publish succeeds.

Staging has equivalent pre-publish checks.

Neither workflow currently verifies after Cloudflare publication that:

- the public URL returns 200;
- bootstrap/main bundle is reachable;
- the deployed public URL is serving the exact expected commit.

This is the remaining OI-04 gap.

### 2.5 Anonymous acquisition writer is intentionally public

Wave 3 intentionally exposes one narrow `anon` RPC:

`record_anonymous_public_link_open`

It stores no target UUID, user id, IP, device id or fingerprint.

It currently has no application-level ingest limit.

Supabase's documented Edge Function rate-limit example uses an external Redis
service such as Upstash. Adding that dependency is not justified for the Go Play
MVP.

---

## 3. OI-02 and OI-03 — no application schema change

### OI-02 Server Error Rate

Definition remains:

`HTTP 5xx requests / all backend requests * 100`

- source: Supabase unified logs;
- 4xx monitored separately;
- OPTIONS may be excluded from product request counts consistently.

### OI-03 P95 Origin Latency

Definition remains:

95th percentile of `response.origin_time` from Supabase edge logs for the
selected window.

No SLO is introduced in Wave 4.

No new Flutter UI or database table is created for either metric.

---

## 4. OI-05 — Push Dispatch Outcome Evidence

### 4.1 New append-only evidence table

Add:

`push_dispatch_outcomes`

Recommended fields:

- `attempt_no bigint identity primary key`
- `notification_id uuid not null`
- `occurred_at timestamptz not null default now()`
- `outcome text not null`
- `priority text null`
- `token_count integer not null default 0`
- `sent_count integer not null default 0`
- `stale_count integer not null default 0`
- `failed_count integer not null default 0`

Allowed outcomes:

- `not_found`
- `suppressed`
- `no_devices`
- `unrenderable`
- `dispatched`
- `internal_error`

No foreign key to `notifications`; transport evidence survives later business
row deletion.

Do not store:

- push token;
- service account data;
- dispatch secret;
- notification message/body;
- user id;
- email/phone;
- Firebase response body.

RLS enabled. Direct `anon` / `authenticated` access revoked.

### 4.2 Edge Function write contract

Add a service-role-only RPC:

`record_push_dispatch_outcome_v1(...)`

The Edge Function calls it best-effort at each terminal outcome.

Failure to write operational evidence must never change whether a notification
is delivered or whether the Notification Center row exists.

The Edge Function continues to delete stale FCM tokens exactly as today.

### 4.3 Push success metric

Recommended OI-05 definition:

> **FCM Acceptance Rate** =
> `sent_count / (sent_count + stale_count + failed_count) * 100`

Interpretation:

- `sent` means Firebase accepted the message;
- it does **not** prove the device displayed it;
- stale/invalid device tokens count as unsuccessful send attempts;
- FCM failures count as unsuccessful send attempts;
- `suppressed`, `no_devices`, `not_found` and `unrenderable` are
  operational outcomes but are excluded from the FCM-send denominator because
  no FCM device send was attempted.

Report outcome counts beside the rate when diagnosing push.

No player-facing metric is added.

---

## 5. OI-06 — Client Error Signal and Rate

### 5.1 Why a run denominator is required

An error count alone cannot produce an error rate.

Using authenticated `product_events.session_started` as the denominator would
exclude public/guest app runs and would mix Product Intelligence with
Operational Intelligence.

Wave 4 should therefore create one minimal operational evidence stream that
contains both run starts and errors.

### 5.2 New append-only table

Add:

`client_runtime_events`

Fields:

- `event_no bigint identity primary key`
- `run_id uuid not null`
- `event_type text not null` — `run_started` or `error`
- `occurred_at timestamptz not null default now()`
- `platform text not null` — web/android/ios
- `app_version text not null`
- `build_sha text not null`
- `category text null`
- `fingerprint text null`
- `context_code text null`

There is deliberately:

- no user id;
- no email/phone/name;
- no IP persisted by the application;
- no device id;
- no cookie;
- no auth/session token;
- no raw exception message;
- no raw stack trace.

RLS enabled. No direct table access for clients.

### 5.3 Run start

RPC:

`start_client_runtime_v1(p_platform, p_app_version, p_build_sha) returns uuid`

- callable by both `anon` and `authenticated`;
- server generates `run_id`;
- inserts exactly one `run_started` event;
- returns only the new run id.

The client holds `run_id` in memory only.

No persistence to SharedPreferences/localStorage/secure storage.

### 5.4 Error report

RPC:

`report_client_error_v1(p_run_id, p_category, p_fingerprint, p_context_code)`

- callable by `anon` and `authenticated`;
- verifies the referenced `run_started` exists;
- copies platform/version/build SHA from that run;
- accepts only bounded categories;
- accepts a fixed-format fingerprint;
- accepts a short sanitized context code;
- inserts no raw exception text or stack.

Recommended categories:

- `flutter_framework`
- `platform_unhandled`

The reporter observes only uncaught framework/runtime failures.

Expected business refusals, validation errors, authentication failures and
ordinary network failures are not client errors and are not reported here.

### 5.5 Flutter capture

Production only:

- `FlutterError.onError` reports framework-unhandled failures while preserving
  Flutter's existing presentation/termination behavior;
- `PlatformDispatcher.instance.onError` reports other uncaught root-isolate
  errors without swallowing them.

The reporter is best-effort and never blocks UI flow.

It begins only after Supabase initialization succeeds.

Staging/default local builds do **not** send client operational telemetry into
the shared live database.

### 5.6 Build identity

Avoid adding a package dependency.

Deployment workflows derive:

- app version from `app/pubspec.yaml`;
- actual checked-out commit from `git rev-parse HEAD`.

They inject:

- `GOPLAY_DEPLOYMENT_ENV`
- `GOPLAY_APP_VERSION`
- `GOPLAY_BUILD_SHA`

Client runtime reporting is enabled only when:

`GOPLAY_DEPLOYMENT_ENV=production`

### 5.7 Client Error Rate

Recommended OI-06 definition:

> **Client Error Rate** =
> `distinct production run_id with >=1 error / distinct production run_id started * 100`

This measures affected application runs rather than raw error volume.

Also retain:

- total error count;
- top fingerprints by app version/platform.

No operations dashboard is added to Flutter.

---

## 6. Public telemetry circuit breaker

### 6.1 Goal

Protect intentionally public telemetry writers from runaway insertion without:

- IP storage;
- device fingerprinting;
- CAPTCHA in a read-only public-link flow;
- Redis/Upstash;
- another external service.

This is an **ingest circuit breaker**, not user identification.

### 6.2 Internal minute-bucket counter

Add an internal/RLS-closed table such as:

`telemetry_ingest_windows`

Key:

- channel
- minute bucket

Value:

- accepted count

A non-client-executable helper atomically consumes one unit before a public
telemetry insert.

Recommended MVP limits:

- anonymous public-link opens: **120/minute**
- client run starts: **120/minute**
- client error reports: **240/minute**

These are deliberately far above expected MVP traffic but bound a runaway
client or simple write flood.

If the budget is exhausted:

- the telemetry RPC refuses/drops the event;
- the Flutter caller swallows the telemetry failure;
- reading, login, registration and navigation continue normally.

The circuit breaker stores no caller identity.

### 6.3 Existing Wave 3 writer

To protect the actual public endpoint, `record_anonymous_public_link_open`
must keep the same signature but gain the circuit-breaker check.

This is a compatible behavior change to the existing RPC, not a second
unlimited `v2` endpoint.

---

## 7. OI-04 — Release Integrity Smoke Gate

### 7.1 Build identity artifact

After Flutter build, both web workflows write a small public file:

`build-info.json`

Containing only:

- app version;
- checked-out Git SHA;
- deployment environment.

No secrets.

This file is included in the Cloudflare deployment.

### 7.2 Post-deploy checks

After Cloudflare publish, the workflow performs bounded retry checks against the
primary site.

Production:

- production public URL;
- `/`;
- `/flutter_bootstrap.js`;
- `/main.dart.js`;
- `/build-info.json`.

Staging:

- `https://go-play-staging.pages.dev`;
- same paths.

Checks:

1. HTTP 200;
2. `build-info.json` SHA equals the actual checked-out SHA;
3. deployed `main.dart.js` still contains Supabase URL marker;
4. deployed `main.dart.js` contains no `service_role` marker.

A failed smoke check marks the deployment workflow failed and requires review.

It does not attempt an automatic rollback.

### 7.3 Production public base

The existing production default is:

`https://go-play-44y.pages.dev`

Wave 4 should state this explicitly once in the production workflow and pass it
as `PUBLIC_WEB_BASE`, rather than relying on a hidden Dart default and then
hardcoding another copy only for smoke checks.

This preserves current product behavior.

---

## 8. No new operations UI

Wave 4 does not add an Operations tab or dashboard to Flutter.

Operational analysis remains in:

- Supabase Logs / SQL;
- Security and Performance Advisors;
- GitHub Actions;
- Cloudflare deployment state.

A later admin/reporting request may add scoped read contracts, but it is not
part of this wave.

---

## 9. Security rules

- no service-role key in Flutter or web bundle;
- no raw FCM token in dispatch outcomes;
- no raw client exception message or stack in database;
- no user id in client runtime evidence;
- no persistent client run id;
- public telemetry functions accept closed shapes only;
- every public writer is circuit-breaker protected;
- operational evidence tables are RLS enabled and direct client access revoked;
- service-role-only push outcome writer explicitly revokes PUBLIC/anon/authenticated;
- no historical backfill;
- existing business data remains unchanged.

Run Supabase Security and Performance Advisors after migration.

---

## 10. Validation requirements

### Push

- each terminal push-dispatch path attempts one outcome record;
- a successful FCM send records sent count;
- stale token records stale count and existing token cleanup still runs;
- failed FCM request records failed count;
- evidence-write failure does not convert an otherwise successful dispatch into
  a failed push;
- no token/message/user id is persisted in outcome evidence.

### Client runtime

- Production build starts exactly one run per app process/page load;
- staging/local build records none;
- framework-unhandled error records an error tied to the in-memory run;
- platform-unhandled error records an error tied to the run;
- ordinary validation/network/business failures record none;
- no raw exception text/stack is sent;
- error reporting failure never blocks or changes app behavior;
- run id is never persisted locally.

### Circuit breaker

- requests below limit pass;
- requests beyond limit do not insert telemetry;
- product behavior still succeeds when telemetry is rate-limited;
- no IP/device identity is stored.

### Release integrity

- build-info has exact source SHA;
- post-deploy primary URL checks pass;
- deliberately mismatched SHA test fails the smoke script;
- production and staging remain separate Cloudflare projects;
- no production deploy occurs from a feature branch.

---

## 11. Product Owner decisions — APPROVED

Before implementation, approve these four decisions:

1. **Push metric semantics — APPROVED**  
   OI-05 is **FCM Acceptance Rate**, not guaranteed device delivery:
   `sent / (sent + stale + failed)`.

2. **Client error measurement — APPROVED**  
   Measure affected **production app runs** across signed-in and guest use with
   an in-memory server-generated run id and **no user identity**. Store only
   category + deterministic fingerprint + short sanitized context; no raw
   message/stack.

3. **Public telemetry circuit breaker — APPROVED**  
   Add a global, non-identifying minute-bucket limiter with initial limits:
   - public-link opens 120/min;
   - client run starts 120/min;
   - client errors 240/min.
   When exceeded, telemetry is dropped only; product flows continue.

4. **Release smoke gate — APPROVED**  
   Add post-deploy smoke checks to both Staging and Production workflows.
   A smoke failure marks the workflow failed after publication; there is no
   automatic rollback.

All four decisions are approved. They close the Wave 0 operational evidence gaps
with no new vendor, no personal tracking, no operations UI and minimal runtime
surface.

### Engineering decisions frozen for implementation

- no Sentry, Upstash, Redis, or new monitoring vendor;
- no Operations UI in Flutter;
- no user identity, IP, device id, raw exception text, raw stack trace, or push token in operational evidence;
- client telemetry is Production-only; Staging/local builds must not write runtime events to the shared live database;
- public telemetry failures and circuit-breaker refusals are always best-effort and must never block product flows;
- the existing `push-dispatch` authentication model using `PUSH_DISPATCH_SECRET` remains unchanged;
- the existing notification center remains the source of truth; push outcome evidence is transport-only;
- no automatic rollback is added to deployment workflows;
- no historical backfill is allowed.
