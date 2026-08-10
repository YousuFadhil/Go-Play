# 12 Testing

Two layers: unit tests that need nothing, and an integration suite that runs
against a real Supabase project.

## Running the unit tests

```bash
flutter test
```

Runs everywhere with no configuration. The integration files skip themselves
when credentials are absent, so this stays usable by anyone.

**Last executed: 172 passed, 7 skipped** — one skip per integration file.
Observed on 2026-07-31, at the `OP-2` minimum match size change.

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

**Last executed: 267 passed, 0 failed, 267 total** — observed 2026-07-31
against project `odhimoxvuhiyunwutzff`, on the six-account fixture model. That
is 172 unit tests plus 95 integration tests; the seven per-file skip guards do
not run when credentials are supplied.

This is the full suite green. It is **not** BTGE Final Validation, which is a
separate approved procedure and **has not been executed**.

> **Resolved — `saveLineup` now surfaces an unauthorized clear.** On its first
> ever execution, "a player cannot write a lineup, and cannot destroy one
> either" failed: `SupabaseTeamAdapter.saveLineup` deletes before it inserts,
> and PostgREST expresses a delete refused by RLS as zero rows matched rather
> than an error. With an empty lineup no insert followed, so the call returned
> success having changed nothing.
>
> Data was never at risk — `match_team_assignments_delete_admins` held
> throughout. The adapter now asks `is_match_community_admin`, the same
> predicate all three write policies use, before touching the table, and raises
> `AuthorizationFailure` when it says no. RLS is still the only enforcement;
> this only reports what it decided. A new test covers the case the fix must
> not break: an admin clearing an already-empty lineup still succeeds.

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

The suite signs in to **six** permanent accounts and never creates or deletes
them. They are **provisioned by hand**, once, in the Supabase Dashboard — a test
run must never mint a user in the project.

| Account | Role |
|---|---|
| `goplay.itest.owner@example.com` | Creates every fixture community and owns it |
| `goplay.itest.admin@example.com` | Promoted to `admin` in the community under test |
| `goplay.itest.player@example.com` | Ordinary member |
| `goplay.itest.player2@example.com` | Ordinary member — the fourth body |
| `goplay.itest.player3@example.com` | Ordinary member — the fifth body |
| `goplay.itest.outsider@example.com` | The dedicated **non-member**, for RLS and authorization coverage |

**Why five members and not four.** The approved minimum match is 4 players
(`OP-2`), and a reserve only exists at the `starting_players + 1`-th
registration — so any scenario that needs a reserve needs **five genuine
community members**: `owner`, `admin`, `player`, `player2`, `player3`. That
covers reserve and promotion in `business_rules_test.dart`, the last-seat race
and the racing withdrawals in `concurrency_test.dart`, and reserve exclusion in
`team_generation_test.dart`.

**`outsider` is not that fifth body.** It is reserved for proving that a
non-member is refused, and is added to a community only by a test specifically
exercising a role or authorization rule — currently just "an admin may not
remove another admin" in `community_management_test.dart`. Do not broaden that
exception.

They share one password, held in `test/integration/support.dart`. If one is
missing the suite fails with a message naming it — create it once by hand.

Everything below the account level — communities, matches, memberships,
registrations, lineups — is created per test and removed in teardown through
`delete_community`, which cascades. Nothing depends on application rows
surviving between runs, and a run leaves the project as it found it.

### Fixture windows

The six accounts are shared and the files run concurrently, so two matches at
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
