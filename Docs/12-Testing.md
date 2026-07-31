# 12 Testing

Two layers: unit tests that need nothing, and an integration suite that runs
against a real Supabase project.

## Running the unit tests

```bash
flutter test
```

Runs everywhere with no configuration. The integration files skip themselves
when credentials are absent, so this stays usable by anyone.

**Last executed: 168 passed, 7 skipped** — one skip per integration file.
Observed on 2026-07-31, at the team-generation integration.

Covered: phone and email validation, the `CommunityRole` enum including its
cumulative precedence and the fallback for an unrecognised value, match
lifecycle derivation (lock, completion, capacity), repository construction with
an injected client, the RPC error-code mapping, join-code link parsing and the
pending-invitation holder, time formatting against both device preferences,
JSON parsing for every model, and the team-generation layer — what counts as a
complete profile, the §4 input contract the schema yields, the lookback window
the repository refuses to choose for itself, and the repository driving the
engine: a generation that succeeds, each way the engine refuses its input, and
the output mapped back into Domain Models.

## Running the engine's own tests

The Balanced Team Generation Engine is a separate package with a separate
suite. The application suite does not re-assert its rules.

```bash
cd packages/btge && dart test
```

**Last executed: 49 passed**, observed on 2026-07-31. `TS-03` alone searches
all 77,558,760 partitions of a 30-player pool, so a full run takes about two
and a half minutes.

## Running the integration suite

```bash
flutter test --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<publishable key>
```

**Last executed: 133 passed**, at `v0.8.0-mvp` (KB-D3). That was 54 unit tests
plus 79 integration tests, and it is the last figure anyone has watched go
green.

**Expected but not yet executed: 257** — the 168 unit tests above plus 89
integration tests, being the same 79 plus the 10 in
`team_generation_test.dart`. It is a count of the tests that exist, not the
result of a run. Three things have moved since the last observed figure and
none has been confirmed against a project: the Adapter Layer phase grew the
unit suite from 54 to 117 without updating this file, the team-generation
adapter added 30 unit and 10 integration tests, and the team-generation
integration added 21 unit tests.

> **The suite cannot currently run.** Every integration file fails in
> `setUpAll`: the four permanent `goplay.itest.*` accounts no longer exist in
> project `odhimoxvuhiyunwutzff` (confirmed 2026-07-31 — the project is healthy
> and holds 10 other users). Recreate them by hand with the suite password, as
> the harness message says; a test run must not mint them. Until then the
> figure above stays unexecuted, and this note stays here.

To run one file:

```bash
flutter test test/integration/authorization_test.dart --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### What it covers

| File | Scope |
|---|---|
| `authorization_test.dart` | The approved permission matrix, as all three roles, with the denials asserted as carefully as the grants |
| `business_rules_test.dart` | DD-01 to DD-08 |
| `community_management_test.dart` | Leaving, member removal, ownership transfer, the join policy and what it does and does not gate, join-code regeneration, community deletion |
| `concurrency_test.dart` | The last-seat race and racing withdrawals |
| `system_admin_test.dart` | That an ordinary account is refused by every admin function, and cannot read the roster. The grant path and the delete cascades are verified by hand — no test account holds the role, by design |
| `btge_schema_test.dart` | Migration `0018`: the three Core Player Inputs on the profile including the OP-1 rating range, and the stored lineup — its vocabularies, one assignment per player, one goalkeeper per team, who may read and write, and the cascade with its match |
| `team_generation_test.dart` | The adapter above that schema: the generation set is the confirmed seats, a missing date of birth is reported rather than invented, a lineup survives a round trip and is replaced rather than appended, a player can neither write one nor destroy one, and the played lineups Diversity may read |

`btge_schema_test.dart` writes the `player` account's profile columns and reads
the `outsider` account's; `team_generation_test.dart` writes the `owner` and
`admin` accounts'. The files run in parallel, so a new profile fixture needs an
account the others leave alone, the same way a match fixture needs its own day
offset.

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

### Fixture windows

The four accounts are shared and the files run concurrently, so two matches at
the same hour in different files make one registration fail the overlap rule
rather than the thing under test. Each file keeps to its own day offsets; if you
add a fixture, pick an offset nothing else uses.

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
