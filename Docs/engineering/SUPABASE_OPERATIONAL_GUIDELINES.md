# Supabase Operational Guidelines

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Approved reference** |
| Role | **Operational Authority** — how Supabase is used, changed, backed up and deployed in Go Play. |
| Owner | Product Owner |
| Applies to | Go Play — the Supabase project, `supabase/migrations/`, and every deployment |
| Baseline | `v0.6.0-mvp`, schema through migration `0017` |

> **Scope.** This document governs *operations*: where schema changes are
> authored, how they reach a database, how the database is backed up, what must
> be true before a table merges, and what must be verified before a release. It
> states no business rules and changes none. Product intent lives in
> `Docs/01-PRD.md` and `Docs/10-Design-Decisions.md`; the schema as built is
> described in `Docs/07-Database-Design.md`. Where this document and one of
> those disagree about *what the product does*, they win. Where they disagree
> with this document about *how a change is applied*, this document wins.
>
> **Current state vs. required state.** Some rules below describe a workflow the
> project has not adopted yet — the Supabase CLI in particular. Every such gap
> is marked **`GAP-n`** and collected in [§9](#9-adoption-gaps). A `GAP` is an
> honest statement that the rule is the target and the project is not there yet;
> it is not permission to ignore the rule where it already applies.

---

## 1. Development Strategy

### 1.1 Local-first development

Schema work is developed and tested against a **local** Supabase stack, started
by the Supabase CLI, before it is applied to any cloud project.

```bash
supabase start
```

The local stack runs Postgres, PostgREST, Auth and Storage in Docker on the
developer's machine. It costs nothing, has no usage quota, cannot be paused, and
can be destroyed and rebuilt from the migration files in seconds:

```bash
supabase db reset
```

`db reset` drops the local database and replays `supabase/migrations/` from
`0001` in order. That replay is the real value of local-first work: it proves
the migration files alone can build the schema, which is the only property that
makes them a source of truth rather than a historical note.

> **`GAP-1`** — the repository has no `supabase/config.toml` and the CLI has
> never been initialised here. Local-first is the target workflow, not today's.
> Until it is adopted, the migration-authoring rules in [§2](#2-database-change-policy)
> still bind, and the currently sanctioned way to apply a migration is
> [§2.4](#24-applying-a-migration-to-the-cloud-project).

### 1.2 The cloud project

The hosted project (`Go-Play`, Free plan) is used for **integration testing and
MVP deployment only**. It is not a scratchpad.

Two facts about it must be known before anyone touches it:

- **The integration suite writes to it.** There is no separate test project. The
  68 integration tests in `app/test/integration/` create communities, matches
  and registrations in whatever project `SUPABASE_URL` points at, and clean up
  through `delete_community` (`Docs/12-Testing.md`). Point them at production
  only when you mean to.
- **Four permanent test accounts live in it** (`goplay.itest.*@example.com`) and
  are never created or deleted by a run. They are a known, accepted piece of
  production data, recorded in `Docs/11-Future-Backlog.md`.

### 1.3 Never modify schema from the Dashboard

Schema is **authored in files, in the repository**. The Dashboard's Table
Editor, Policy Editor, Database → Functions/Triggers/Indexes screens, and
free-hand SQL typed into the SQL Editor are **not** change channels. A change
made there exists in exactly one database, is invisible to review, is absent
from `db reset`, and is silently lost the moment the schema is rebuilt.

The rule is about *where a change is written*, not about which window executes
it. Precisely:

| Action | Allowed |
|---|---|
| Author DDL in a new file under `supabase/migrations/` | **Yes** — this is the only way |
| Paste a committed migration file into the SQL Editor to apply it | **Yes** — see `GAP-1` and §2.4 |
| Create or alter a table, policy, function, trigger or index through the Dashboard UI | **No** |
| Type ad-hoc DDL into the SQL Editor | **No** |
| Run a `select` in the SQL Editor to inspect state | Yes — reads are not changes |
| Run a one-off `insert`/`update` of *data* (e.g. granting System Admin) | Yes, where the design says so — see below |

Two data operations are deliberately manual by design and are not schema
changes: granting the System Admin role
(`insert into system_admins (user_id) values ('<uuid>');`, migration `0017`)
and editing the global reserve setting in `app_settings` (DD-06). Both are
recorded in `SETUP.md` and `Docs/11-Future-Backlog.md`. Doing them by hand is
correct; anything that changes a table's *shape* is not.

---

## 2. Database Change Policy

### 2.1 Everything is a versioned migration

Every change to the database is a new, numbered, committed SQL file under
`supabase/migrations/`. This covers, without exception:

- tables, columns, constraints, enums and defaults
- **RLS: `enable row level security` and every policy**
- **functions**, including every `SECURITY DEFINER` RPC
- **triggers**
- **indexes**
- grants and revokes
- data seeds and back-fills the schema depends on

If it is part of the database and the application relies on it, it is in a
migration file. A policy that exists only in the cloud project is a defect.

### 2.2 Naming and ordering

`NNNN_short_description.sql` — four digits, zero-padded, strictly increasing.
The next file is `0018_`.

Migrations are **append-only**. An applied migration is never edited and never
renumbered, even when it is later undone: `0007` renames `groups` to
`communities` and `0012` removes the invitation-link tables that `0010` added.
Both are kept. The sequence is the project's history, and rewriting it would
break `db reset` for everyone who already ran it.

To change something a previous migration did, write the next migration.

### 2.3 What a migration file must contain

- A header comment saying **why** the change exists, and citing the decision
  that authorises it (`DD-nn`, `PD-nn`, or the document section). The existing
  files set the standard — see the header of `0017_system_admin.sql`.
- Idempotent DDL where it costs nothing (`create table if not exists`,
  `create or replace function`).
- `enable row level security` for every table it creates, in the same file.
- The policies for that table, in the same file — never "policies to follow".

### 2.4 Applying a migration to the cloud project

Target workflow, once `GAP-1` is closed:

```bash
supabase db push
```

Current workflow, until then: open the Supabase SQL Editor, paste the contents
of the **committed** migration file — unmodified — and run it. If the file needs
a change after you see the result, change the file, commit, and re-apply; do not
fix it in the editor.

`supabase/setup_all.sql` is a **generated convenience copy** of `0001`–`0017`
concatenated in order, used once to build a project from empty (`SETUP.md` §1).
It is not the source of truth and is not the way to apply an incremental change.
When a migration is added, regenerate it so a fresh project still builds.

### 2.5 Review

A migration is reviewed on a feature branch and merged only after the checklist
in [§4](#4-security-checklist) passes. New development never lands directly on
`main` (`CLAUDE.md` §1).

---

## 3. Backup Strategy

### 3.1 Why this section exists

**The Free plan includes no automatic backups.** Scheduled daily backups and
Point-in-Time Recovery are paid-plan features. On the Free plan the only backup
that exists is one somebody took on purpose. A dropped column, a mis-scoped
`delete`, or a project paused past its 90-day restore window is unrecoverable
otherwise.

### 3.2 The rule

> **Take a dump before every structural migration**, and before any manual data
> operation that deletes or rewrites rows.

"Structural" means anything in [§2.1](#21-everything-is-a-versioned-migration).
The dump is taken from the **cloud** project, immediately before the migration
is applied to it — a dump from last week does not cover today's registrations.

### 3.3 Manual backup procedure

Get the connection string from **Project Settings → Database → Connection
string** (URI form). It contains the database password; treat it as a secret and
never commit it.

**With the Supabase CLI** (preferred, once `GAP-1` is closed) — three files,
because roles, schema and data restore in that order:

```bash
supabase db dump --db-url "$DB_URL" -f backup_roles.sql --role-only
```

```bash
supabase db dump --db-url "$DB_URL" -f backup_schema.sql
```

```bash
supabase db dump --db-url "$DB_URL" -f backup_data.sql --data-only
```

**With `pg_dump` directly** (works today, needs the Postgres client tools
installed):

```bash
pg_dump "$DB_URL" --clean --if-exists --quote-all-identifiers --schema=public --schema=auth --schema=storage --file=goplay_backup.sql
```

In PowerShell, use the backtick for line continuation or keep the command on one
line — `\` and `^` do not continue a line there (`SETUP.md` §4 records the same
trap for `flutter run`).

### 3.4 Naming, storage and retention

- Name dumps `goplay_<UTC-date>_<reason>.sql`, e.g.
  `goplay_20260728_pre-0018.sql`. The reason is what makes an old dump usable.
- **Store dumps outside the repository.** A dump contains real user rows — names,
  phone numbers, auth identities. It is personal data and must never be
  committed, attached to an issue, or pasted into a chat. If a backups directory
  is ever created inside the working tree, it must be added to `.gitignore`
  first (`GAP-2`).
- Keep the last three structural-migration dumps plus the most recent one taken
  before a release. Delete older ones deliberately, not by accident.

### 3.5 Verifying a backup

An unverified dump is a hope, not a backup. At least once — and after any change
to the dump command — restore into a scratch database and confirm it builds:

```bash
psql "$LOCAL_DB_URL" --file=goplay_backup.sql
```

Restoring a Supabase dump into a plain Postgres instance will report errors for
Supabase-managed roles and extensions; that is expected. What must succeed is
the `public` schema — its tables, functions, policies and row counts.

### 3.6 Storage objects are not in a database dump

Files in Supabase Storage live outside Postgres and are **not** captured by
`pg_dump`. Only the `storage.objects` metadata rows are. Once the project starts
storing files ([§5](#5-storage-guidelines)), the backup procedure must also copy
the buckets (`supabase storage cp -r ss://<bucket> .`). Until then there is
nothing to copy — see `GAP-3`.

---

## 4. Security Checklist

Every migration that creates a table must satisfy all of the following before
it merges. A reviewer signs off on this list, not on a general impression.

- [ ] **RLS is enabled.** `alter table public.<t> enable row level security;` is
      in the same migration as the `create table`. A table with RLS off is
      readable and writable by any holder of the anon key — which is every
      installed copy of the app.
- [ ] **Access is explicit.** Either the table has policies naming exactly who
      may `select`, `insert`, `update` and `delete`, or it has **no policies at
      all** and is reachable only through `SECURITY DEFINER` functions. Both are
      valid; the second is the `system_admins` pattern from migration `0017`,
      where the header comment states the intent outright. What is never valid is
      RLS enabled with policies that were meant to exist and do not.
- [ ] **Authorization uses `has_community_role`.** Roles are cumulative
      (owner ≥ admin ≥ player). `owner_id` and `created_by` are never read to
      grant permission (`Docs/07-Database-Design.md`).
- [ ] **Enforcement is dual.** A write path exposed as an RPC carries the check
      *inside* the function **and** an RLS policy on the table. RLS alone is
      bypassed by `SECURITY DEFINER`; an RPC guard alone does not cover direct
      PostgREST reads (`Docs/03-Technical-Architecture.md`).
- [ ] **`SECURITY DEFINER` functions pin `search_path`** and are revoked from
      client roles when they are internal helpers (the `purge_*` pattern).
- [ ] **Denials are tested, not assumed.** The integration suite asserts refusals
      as carefully as grants (`authorization_test.dart`). A new table's denials
      belong there.
- [ ] **No public table without explicit Product Owner approval.** "Public" means
      readable or writable by the `anon` role, or by `authenticated` without a
      membership or role predicate. Today exactly one table is broadly readable
      by design — `communities`, whose `communities_select_visible` policy makes
      every active community visible so that a join link previews before signup
      (DD-13). That is an approved decision with a recorded reason. Any new one
      needs the same.
- [ ] **No secret reaches the client.** The app ships only the publishable
      (anon) key, via `--dart-define`. The `service_role` key is never in source,
      never in a build, never in a `--dart-define`, and never in a screenshot.
- [ ] **Advisors are clean.** Run the Supabase security advisor after applying
      the migration to the cloud project and resolve or explicitly accept every
      finding.

---

## 5. Storage Guidelines

### 5.1 What may be stored

In the MVP, Supabase Storage holds **two** kinds of object:

1. **Profile images** — one per user.
2. **Community logos** — one per community.

Nothing else. No match photos, no video, no attachments, no documents, no
exports. This is a scope rule, not a performance suggestion: 1 GB of Free-plan
storage and a 5 GB monthly egress quota are consumed by media faster than by
anything else the product does, and egress is charged against the whole
organization.

> **`GAP-3`** — the app uses no Storage today. No bucket exists and no Flutter
> code uploads a file. This section is the rule for when it does; adding profile
> images is a Product Owner decision, and `Docs/11-Future-Backlog.md` is where
> that request belongs.

### 5.2 Rules for when Storage is introduced

- **Buckets are private by default.** Serve through signed URLs unless the
  Product Owner approves a public bucket in writing. A public bucket is the
  Storage equivalent of a table without RLS.
- **Buckets and their policies are created by migration**, like everything else
  in [§2.1](#21-everything-is-a-versioned-migration) — not by clicking "New
  bucket" in the Dashboard. `storage.objects` is an ordinary RLS-protected table
  and its policies are reviewed under [§4](#4-security-checklist).
- **Constrain uploads at the bucket**: an explicit size limit (profile images
  and logos have no business exceeding ~2 MB) and an allowed MIME list
  (`image/jpeg`, `image/png`, `image/webp`). Client-side validation is a
  courtesy; the bucket limit is the control.
- **Resize before upload.** Store one display-sized image, not the camera
  original. Image transformation is unavailable on the Free plan, so whatever is
  uploaded is what every viewer downloads, every time.
- **Deterministic paths tied to the owning row** — `avatars/<user_id>` and
  `community-logos/<community_id>` — so a policy can authorize by path and a
  deleted row's object can be found and removed. Orphaned objects are storage
  quota nobody is watching.
- **Deletion is part of the cascade.** When a user or community is deleted, its
  object is deleted too. Postgres cascades do not reach Storage.

---

## 6. Free Tier Operational Notes

These are **platform constraints, not application bugs**. When the app returns
`cannot execute INSERT in a read-only transaction`, or the first request after a
quiet week hangs, or a sign-in fails with a connection error under load, the
correct first question is which limit was reached — not which commit broke it.
Misreading a quota as a defect wastes a debugging session and, worse, sometimes
produces a "fix" for something that was never wrong.

Verified against the Supabase documentation on **2026-07-28**. Limits change;
re-check the [pricing page](https://supabase.com/pricing) before relying on a
number here for a decision.

| Constraint | Free plan | What it means for Go Play |
|---|---|---|
| **Database size** | 500 MB per project (1 GB disk) | Exceeding it puts the database into **read-only mode** — writes fail until data is deleted and `vacuum` reclaims the space. A new project already uses ~40–60 MB for extensions and system objects. Note that deleting rows does not immediately reduce reported size; a vacuum must run. [Docs](https://supabase.com/docs/guides/platform/database-size) |
| **Storage size** | 1 GB | See [§5](#5-storage-guidelines). At ~200 KB per image, the MVP will not approach this — which is exactly why the "profile images and logos only" rule must hold. |
| **Egress** | 5 GB / month across database, storage and functions (storage bandwidth is counted as 5 GB cached + 5 GB uncached) | Every list refresh the app makes counts. Pull-to-refresh over a large roster is egress. [Docs](https://supabase.com/docs/guides/storage/serving/bandwidth) |
| **Monthly active users** | 50,000 MAU | Far beyond MVP need. Not a practical constraint. |
| **Project inactivity pause** | Paused after **7 days** with too little database activity | Two warning emails go to the project owner. A paused project can be restored from the Dashboard for **90 days**; after that the backup is gone. A few real requests a day prevent it. This is the single most likely way the MVP loses its database. [Docs](https://supabase.com/docs/guides/platform/free-project-pausing) |
| **Projects per Free organization** | 2 active (paused projects do not count) | This is why there is no separate test project today. Adding one is a real option — it would decouple the integration suite from production. |
| **Connection limits** | Bounded by the smallest compute size: direct Postgres connections number in the tens, and the pooler caps concurrent clients | The Flutter app uses PostgREST over HTTP and does not hold Postgres connections, so this bites tools, not users: a `psql` session, a dump, a migration and a test run at once can exhaust it. Read the actual numbers for this project in **Project Settings → Database**. [Docs](https://supabase.com/docs/guides/database/connecting-to-postgres) |
| **Automatic backups** | **None** | See [§3](#3-backup-strategy). This is the constraint that can end the project rather than inconvenience it. |

### 6.1 Keeping the project awake

Until the MVP has real daily traffic, the project pauses on its own. Either
visit the Dashboard, or let the integration suite run, at least twice a week.
Treat the first warning email as an incident, not a notification.

---

## 7. Deployment Checklist

Run this before every release build that is handed to anyone. A checked box
means somebody verified it, not that it is usually fine.

**Database**

- [ ] Every migration in `supabase/migrations/` is applied to the target
      project, in order, with none skipped.
- [ ] The migration list in `SETUP.md` §1 matches the files on disk.
- [ ] `supabase/setup_all.sql` regenerated if a migration was added, so a fresh
      project still builds from empty.

**Security**

- [ ] RLS is enabled on every table in `public` — confirm by query, not memory:
      `select relname, relrowsecurity from pg_class join pg_namespace n on n.oid = relnamespace where nspname = 'public' and relkind = 'r';`
- [ ] Every table either has the policies it is meant to have, or is
      deliberately policy-free and definer-only ([§4](#4-security-checklist)).
- [ ] The Supabase security advisor reports no unresolved findings.
- [ ] No `service_role` key appears in the build, the source tree, or the CI
      configuration.

**Storage**

- [ ] Required buckets exist with the expected public/private setting, size cap
      and MIME allow-list. *(Not applicable while `GAP-3` stands — no buckets.)*
- [ ] Storage policies applied and verified against a non-owner account.

**Configuration**

- [ ] `SUPABASE_URL` and `SUPABASE_ANON_KEY` passed via `--dart-define` at build
      time and pointing at the **intended** project.
- [ ] The build was produced in PowerShell with backtick continuation, or on one
      line — a `^` continuation silently drops the defines and the app starts
      with "Supabase configuration missing" (`SETUP.md` §4).
- [ ] Auth settings unchanged and correct: Email provider enabled, **Confirm
      email disabled** (`SETUP.md` §1.3) — until the deferred activation in
      [§10](#10-authentication-configuration-activation-deferred) is carried out,
      after which the settings listed there are the correct ones.

**Backup**

- [ ] A dump taken from the target project *after* the final migration and
      *before* the release is handed out ([§3.3](#33-manual-backup-procedure)),
      stored outside the repository, named by date and reason.

**Verification**

- [ ] `flutter test` passes — expected **54 passed, 4 skipped**.
- [ ] The integration suite passes against the target project — expected
      **122 passed** (`Docs/12-Testing.md`). Remember it writes to that project.
- [ ] Smoke test on the installed release build: sign in, open a community,
      open a match. A build that renders but cannot reach the database looks
      identical on the first screen.
- [ ] Manual paths that no test covers: System Admin grant and the delete
      cascades, if either was touched.

---

## 8. Quick Reference

| Question | Answer |
|---|---|
| Where do schema changes live? | `supabase/migrations/NNNN_*.sql`, append-only |
| Next migration number | `0018` |
| May I fix this in the Dashboard? | No — [§1.3](#13-never-modify-schema-from-the-dashboard) |
| Before a structural migration? | Take a dump — [§3.2](#32-the-rule) |
| New table needs? | RLS on, explicit access, dual enforcement, denial tests — [§4](#4-security-checklist) |
| Writes suddenly failing? | Check the 500 MB database-size limit before the code |
| Project unreachable after a quiet week? | It is paused — [§6](#6-free-tier-operational-notes) |
| Which key ships in the app? | The publishable (anon) key, only, via `--dart-define` |

---

## 9. Adoption Gaps

Open items where the rule above is the target and the project has not reached it.
Each is a Product Owner decision to schedule; none is implemented by this
document.

| Gap | Statement |
|---|---|
| **`GAP-1`** | No Supabase CLI setup: no `supabase/config.toml`, no local stack, no `db push`. Migrations are applied by pasting committed files into the SQL Editor, and `db reset` has never verified that `0001`–`0017` replay cleanly from empty. A related deferred item already exists in `Docs/11-Future-Backlog.md` — running the integration suite against a local stack via CLI + Docker. |
| **`GAP-2`** | `.gitignore` has no rule excluding database dumps. Nothing currently produces one inside the working tree, so nothing is at risk today; the rule should exist before the first dump is written there. |
| **`GAP-3`** | Supabase Storage is unused — no bucket, no upload path, no bucket policies. [§5](#5-storage-guidelines) is pre-emptive, and [§3.6](#36-storage-objects-are-not-in-a-database-dump) has nothing to cover yet. |
| **`GAP-4`** | The integration suite and production share one project (`Docs/12-Testing.md`), and four permanent test accounts live in production data. The Free plan allows a second project, which would separate them. |

---

## 10. Authentication Configuration (activation deferred)

The authentication modernization — Google sign-in, email confirmation for new
registrations, password recovery and the player-profile onboarding step —
ships as code and as migration `0092` that work under **both** Auth
configurations. **Nothing in this section is enabled by that change, and nothing
here has been changed on the live project.** Each step below is a Dashboard
setting the Product Owner applies deliberately, after the code and the migration
have been reviewed, in the order given.

> **Staging and production share one Supabase project**
> (`Docs/12-Testing.md`, `GAP-4`). Every setting below applies to
> both front ends at once; there is no "try it on staging first" for Dashboard
> configuration. Verify with a throwaway address, not a real player.

**1. Apply migration `0092` first.** Back up first ([§3](#3-backup-strategy)). The
new client asks `get_my_account_state()` and fails closed — an "account status
unavailable" screen — against a database that does not have it. The previous
client is unaffected by the migration.

**2. Redirect URLs.** *Authentication → URL Configuration → Redirect URLs* must
contain **every** form the app sends, or Auth ignores the parameter and falls
back to the Site URL, which is not an address that reopens the app. There are two
callbacks per platform: the **ordinary** one, for sign-up confirmation and the
return from Google, and the **recovery** one, which is the ordinary one with
`/recovery` after it. Password-recovery emails use the second, and that address is
how the app recognises a recovery — so it is not optional, and an allow-list
holding only the ordinary forms sends recovery emails to the Site URL:

| Form | Ordinary callback | Recovery callback |
|---|---|---|
| Native (Android) | `goplay://login-callback` | `goplay://login-callback/recovery` |
| Web, production | `https://go-play-44y.pages.dev/login-callback` | `https://go-play-44y.pages.dev/login-callback/recovery` |
| Web, staging | `https://go-play-staging.pages.dev/login-callback` | `https://go-play-staging.pages.dev/login-callback/recovery` |
| Web, local run | `http://localhost:<port>/login-callback` | `http://localhost:<port>/login-callback/recovery` |

(Local runs only while developing against this project. A wildcard entry such as
`goplay://login-callback/**` would cover both forms; the exact entries above are
the ones the app sends.)

The web value is derived from the running page's origin (`AuthService`), so a new
web host needs its own two rows before it can complete any of these flows. The app
is a single page: Cloudflare Pages serves `index.html` for any path that matches
no file, so `/login-callback` and `/login-callback/recovery` both reach it. The
Android manifest's `login-callback` filter names the host and restricts no path,
so `/recovery` is already accepted (asserted in
`app/test/auth_recovery_persistence_test.dart`); iOS is not configured for either
and is not a supported target of this change.

**3. Google provider.** *Authentication → Sign In / Providers → Google.* Create
an OAuth client of type *Web application* in Google Cloud, add
`https://<project-ref>.supabase.co/auth/v1/callback` as its authorised redirect
URI, and paste the client ID and secret into Supabase before switching the
provider on. The app uses Supabase's own redirect flow — there is no Google SDK
and no key in the app. **Enable the provider before serving a build that shows
"Continue with Google"**: the button is always drawn, and against a project with
the provider off Auth answers the browser with a raw error page.

**4. Email confirmation.** *Sign In / Providers → Email → Confirm email → on.*
A new email registration then produces an account and **no session**; the app
shows "check your email" and the person signs in after opening the link. The
app already handles both settings, so this can be flipped without a release.
Existing accounts are not asked to confirm anything. `SETUP.md` §1 and the
integration suite were written for confirmation **off** (they sign up and expect
an immediate session); once it is on, provision any new test accounts by hand.

**5. SMTP.** Supabase's built-in email service is for evaluation only: it is
heavily rate-limited and is not meant to deliver to real players. **Production
auth email requires a configured SMTP provider** (*Authentication → Emails →
SMTP Settings*) before Confirm email is switched on, or new players will not
receive their link. Password recovery depends on it equally. Keep the default
templates' `{{ .ConfirmationURL }}` so the redirect above is honoured. The app
respects the provider's limits: "Resend email" is held back for a minute and a
429 is reported as "too many attempts" rather than retried.

**6. What is deliberately not done.**

- **Existing accounts are not migrated, recreated or forced to verify.** Most
  legacy addresses are not real inboxes: password recovery cannot reach them,
  and Google cannot match them, until the player changes the address through
  *Edit Profile* and confirms it. That is by design.
- **A Google account whose verified email matches an existing account** is
  linked to it by Auth under its own automatic-linking rules; the application
  does nothing to cause or prevent it and does not hard-code any account.
- **A brand-new Google account has no player profile.** Migration `0092` stops
  `handle_new_user()` inventing one; the app shows *Complete your player
  profile* and the account is neither active nor suspended until it is done.
- **A recovery session never becomes an ordinary one.** The application keeps a
  small durable record on the device (local storage, `PasswordRecoveryState`):
  set by the launch or resume that came from the recovery callback and, as a
  backup, by Auth's recovery event; read by the auth gate before anything else
  about a signed-in account; cleared by finishing or cancelling (both sign the
  session out first) or when it is found with no session behind it. It is not
  derived from Auth's event, because that event can be emitted before the app is
  listening and a restored session carries no memory of how it began. The one
  case it cannot see is a recovery whose callback the platform hands over in a
  shape not recognised *and* whose event was also missed; such a session is then
  an ordinary one.
- **On the web, a recovery link redeems in any browser.** The app's Auth flow is
  PKCE, which stores a one-time verifier in the browser that made the request and
  can only be redeemed there. That suits a redirect that returns to the page it
  started from and fails for an email: a phone opens the link in whatever its mail
  app uses, which is often not the browser the person asked in. (The first Staging
  UAT hit exactly this: requested in iPhone Safari, opened in iPhone Chrome. The
  provider's logs showed `/verify` succeeding and then *no* `/token` request,
  because the SDK refuses the exchange client-side when the verifier is absent.)
  So on the web the recovery email is requested **without a PKCE challenge**
  (`SupabaseAuthAdapter.requestPasswordReset`): the link returns to
  `<origin>/login-callback/recovery#access_token=…&type=recovery`, which the app's
  own client already exchanges for a session, and the SDK removes from the address
  as soon as it has read it. Nothing about the project's configuration changes:
  the Redirect URLs and the email template are the same. Sign-up, Google and
  recovery on Android stay PKCE. The cost is tokens in a URL fragment for one
  redirect. A link that carries no session in the URL at all (`token_hash`, from a
  custom "Reset Password" email template that points at the app) would avoid it
  and would also be browser-independent; that is a template change and a client
  handler, and is a candidate follow-up rather than something assumed here.
- **Acquisition attribution is not carried across these redirects.** A sign-up
  completed through Google or an email-confirmation link leaves the app and
  returns to it, and may not count as the same-session anonymous signup
  conversion that a plain registration does. This is a known and accepted
  limitation: no persistent tracking or cookie is added to work around it.

---

## Related documents

| Document | What it holds |
|---|---|
| `SETUP.md` | First-time setup: creating the project, applying `setup_all.sql`, auth settings, build commands |
| `Docs/03-Technical-Architecture.md` | Layers, the repository boundary, the security model |
| `Docs/07-Database-Design.md` | The schema as built, constraints, the authorization predicate |
| `Docs/10-Design-Decisions.md` | DD-01 … DD-13 — why the product behaves as it does |
| `Docs/11-Future-Backlog.md` | Deferred ideas and known gaps |
| `Docs/12-Testing.md` | How to run both suites, what they cover, test accounts |
