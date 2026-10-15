# Technical Architecture

> The structural rules are in `engineering/ARCHITECTURE_DECISIONS_V1.md`. This page
> is the map: what the pieces are and where each is described. Anything that
> changes with every release (table and function lists, versions, test counts) is
> generated or checked by `node tool/check-docs.mjs`, never written here. See
> *Where the facts live* below.

## Stack

| Piece | What it is |
|---|---|
| Client | A Flutter app for Android, iOS and web (`app/`), Arabic by default with English available |
| Backend | Supabase: PostgreSQL with Row Level Security, Auth, Storage, PostgREST and SQL RPCs. There is no custom application server |
| Server-side code outside SQL | Four Edge Functions (`supabase/functions/`) and one Cloudflare Pages Function (`functions/`), described below |
| Push notifications | Firebase Cloud Messaging. A database trigger on `public.notifications` calls the `push-dispatch` Edge Function |
| Scheduled work | `pg_cron` inside PostgreSQL (the missing-result reminder, migration `0100`); a manual GitHub Actions workflow stores the Team of Period snapshot |
| Web hosting | Cloudflare Pages: production is built on every push to `main`, staging on demand (`.github/workflows/`) |
| Team generation | `packages/btge`, a pure Dart package with no Flutter, Supabase or schema in it |

## Layers

```
Screens (app/lib/features/*)         no screen imports the Supabase SDK
      |
Feature services and adapter         e.g. features/matches/match_adapter.dart
interfaces (domain models, errors)
      |
app/lib/infrastructure/supabase      the only place the SDK is used,
      |                              e.g. supabase_match_adapter.dart
PostgREST + RPC  ->  PostgreSQL with RLS
```

Each feature declares what it needs from the backend as an adapter interface; the
Supabase implementation sits under `infrastructure/supabase/`. Where an
implementation conflicts with `ARCHITECTURE_DECISIONS_V1.md`, the implementation
is what changes. There is no state-management package and no routing package
(see `app/pubspec.yaml`); that is a deliberate MVP choice, not an oversight.

`app/lib/features/` holds one folder per feature, so `ls app/lib/features` is the
current feature list.

## Server-side code outside SQL

| Piece | Why it exists |
|---|---|
| `push-dispatch` (Edge Function) | Delivers a notification as a Firebase push; invoked by the database trigger, never by the client |
| `admin-merge-accounts` (Edge Function) | The System Admin console's request to merge two accounts; removes the profile picture from Storage, which SQL cannot |
| `admin-user-auth` (Edge Function) | Changes another account's email or password, or sends a recovery email; needs the service role, which never reaches the app |
| `delete-account` (Edge Function) | The one request both account-deletion entry points make; removes the profile picture, then calls the RPC |
| `functions/share/match/[id].js` (Pages Function) | Serves `/share/match/:id` with server-rendered Open Graph tags so a match invitation link previews well; see `engineering/MATCH_LINK_PREVIEW.md` |

Each Edge Function has a `README.md` next to its code, and the generated
`engineering/DB_Object_Catalog.md` lists all of them.

## Security

- Row Level Security on every table.
- `has_community_role(community_id, user_id, min_role)` is the single
  authorization predicate, with roles cumulative.
- Dual enforcement: an RLS policy and a check inside each RPC. Neither alone is
  sufficient — RLS is bypassed by `SECURITY DEFINER` functions, and RPC guards
  do not cover direct reads.
- The client holds only the publishable (anon) key, supplied at build time via
  `--dart-define`. The service-role key exists only inside Edge Functions and
  CI secrets; it is never shipped in a build.
- Which sign-in methods are on is Supabase Auth configuration, not code. See
  migration `0092` and `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` §10.

## Deployment and release integrity

Production and staging web builds are made by `deploy-web.yml` and
`deploy-staging.yml`. Each build writes a `build-info.json` and a smoke test
checks that the deployed site reports the commit that was built
(`app/tool/release_gate.dart`). Pushing to `main` deploys production; there is no
test gate in front of it, so what reaches `main` must already be tested.

## Client compatibility

There is no compatibility layer. The database and the current app are the only
supported combination: a build made before the Community migration cannot talk
to the current schema.

## Where the facts live

| Question | Source |
|---|---|
| Which tables, views and functions exist, and which migration made them | `engineering/DB_Object_Catalog.md` (generated) |
| What a table's columns and rules are | `engineering/*_Table_Specification.md`, then the header of the migration that built it |
| Why something is the way it is | `10-Design-Decisions.md` |
| What changed, and when | `../CHANGELOG.md` |
| How Supabase is operated, backed up and deployed | `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` |
| How to run the tests | `12-Testing.md` |
| How to set up a new environment | `../SETUP.md` |
