# Technical Architecture

> Updated for the Community-first architecture (`v0.4.0-mvp`).

## Stack

Flutter → Supabase SDK → PostgreSQL. No custom backend.

## Layers

```
Screens (features/*)          no screen touches Supabase
      |
Repositories and services     the only place the SDK is used
      |
PostgREST + RPC  ->  PostgreSQL with RLS
```

A screen never constructs a Supabase client and never issues a query. Data
access lives in:

| Class | Responsibility |
|---|---|
| `CommunityRepository` | The community aggregate: overview, create, join by code, invitation preview, visibility, fetch, delete |
| `MemberRepository` | Members, roles, ownership transfer, removal |
| `MatchService` | Matches, registration, roster, the reserve setting |
| `AuthService` | Identity: sign-in, sign-up, session stream, profile name |
| `NotificationService` | The user's own notifications |

Each takes an optional `SupabaseClient` through its constructor, which is what
makes them testable. There is no DI container, no state-management package and
no routing package: screens use `setState` with `FutureBuilder`, and navigation
is `Navigator.push`. That is a deliberate MVP choice, not an oversight.

## Feature layout

```
lib/
  core/          config, theme, localization, locale
  features/
    auth/           identity
    communities/    the aggregate: list, create, details, settings
    members/        roster, roles, removal, transfer
    invitations/    the community invitation: link format, share screen, landing
    matches/        lifecycle, registration, roster management, app settings
    home/           shell and dashboard
    notifications/
```

## Security

- Email and password authentication (DD-02).
- Row Level Security on every table.
- `has_community_role(community_id, user_id, min_role)` is the single
  authorization predicate, with roles cumulative.
- Dual enforcement: an RLS policy and a check inside each RPC. Neither alone is
  sufficient — RLS is bypassed by `SECURITY DEFINER` functions, and RPC guards
  do not cover direct reads.
- The client holds only the publishable (anon) key, supplied at build time via
  `--dart-define`. No service-role key is ever shipped.

## Client compatibility

There is no compatibility layer. The database and the current app are the only
supported combination: a build made before the Community migration cannot talk
to the current schema.
