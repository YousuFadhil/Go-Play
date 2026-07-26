# 12 Testing

Two layers: unit tests that need nothing, and an integration suite that runs
against a real Supabase project.

## Running the unit tests

```bash
flutter test
```

Runs everywhere with no configuration. The integration files skip themselves
when credentials are absent, so this stays usable by anyone.

Expected: **74 passed, 5 skipped**.

Covered: phone and email validation, the `CommunityRole` enum including its
cumulative precedence and the fallback for an unrecognised value, match
lifecycle derivation (lock, completion, capacity), repository construction with
an injected client, the RPC error-code mapping, invitation-link parsing and the
pending-invitation holder, time formatting against both device preferences, and
JSON parsing for every model.

## Running the integration suite

```bash
flutter test --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<publishable key>
```

Expected: **169 passed**, which is the unit tests plus 95 integration tests.

To run one file:

```bash
flutter test test/integration/authorization_test.dart --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### What it covers

| File | Scope |
|---|---|
| `authorization_test.dart` | The approved permission matrix, as all three roles, with the denials asserted as carefully as the grants |
| `business_rules_test.dart` | DD-01 to DD-08 |
| `community_management_test.dart` | Invitation limits and lifecycle, leaving, member removal, ownership transfer, visibility, community deletion |
| `concurrency_test.dart` | The last-seat race and racing withdrawals |
| `invite_link_test.dart` | Both invitation types: who may share, the unauthenticated preview, redemption, the split outcome when registration fails, and every way a link stops working, and the organizer's management list |

### Test accounts

The suite signs in to four permanent accounts and never creates or deletes
them:

```
goplay.itest.owner@example.com
goplay.itest.admin@example.com
goplay.itest.player@example.com
goplay.itest.outsider@example.com
```

They share one password, held in `test/integration/support.dart`. If one is
missing the suite fails with a message naming it — create it once by hand
rather than letting a test run add users to the project.

Everything below the account level — communities, matches, registrations,
invitations — is created per test and removed in teardown through
`delete_community`, which cascades. A run leaves the project as it found it.

### Two things to know before running it

- **It writes to whichever project you point it at.** There is no separate test
  project; point it at production only when you mean to.
- Tests inside a file share fixtures through `setUp`, and the four files can run
  in parallel because each creates its own community.

## Release build

```bash
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Verify by installing it and signing in — a build that renders but cannot reach
the database looks identical on the first screen.
