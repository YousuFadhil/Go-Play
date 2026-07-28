# btge — Balanced Team Generation Engine

Pure Dart. No Flutter, no Supabase, no PostgreSQL, no schema. The database is an
adapter layer implemented elsewhere; this package operates only on the input
contract of the Engineering Specification §4.

## Authority

1. `Docs/engineering/BTGE_Design_Knowledge_Base.md` — **Design Authority**
2. `Docs/engineering/BTGE_Engineering_Specification.md` — **Implementation Authority**

Where this code and those documents disagree, **this code is the defect**. Rule
ids (`BTGE-*`, `KB-*`, `OP-*`) appear throughout the source and tests so any
line can be traced back to the rule that requires it.

## Running

```bash
dart test --exclude-tags capacity
```

The full suite including the 15 v 15 capacity check:

```bash
dart test
```

Measure the search boundary:

```bash
dart run tool/benchmark.dart 30
```

## Shape

| File | Responsibility |
|---|---|
| `src/models.dart` | Core Player Inputs (§4.1), match settings, Match History |
| `src/configuration.dart` | The Open Parameters. Product Decisions have **no default** |
| `src/distribution.dart` | Target shape derivation (§8) |
| `src/assignment.dart` | The chain (§9) and goalkeepers (§10), solved exactly |
| `src/scoring.dart` | One function per priority (§15) |
| `src/engine.dart` | Validation, staged lexicographic search, result assembly |

Inputs are player models, configuration and match settings. Outputs are team
assignments, quality metrics and diagnostics.

## Two things worth knowing before reading the code

**The search is exact.** Every partition is scored. There is no time budget, no
early exit and no heuristic, because `BTGE-PF-4` forbids returning a
good-enough result when a better one exists. There is also no random number
generator, no seed and no shuffle anywhere — `BTGE-PF-6` forbids randomness, and
a test enforces that by scanning the source.

**Product Decisions are unset on purpose.** `BtgeConfiguration` requires the
caller to supply the tolerance bands, the odd-count rule and the minimum player
count. They have no defaults, so an unmade decision is a compile error rather
than a silent assumption. That is §18.1's rule that no default may be treated as
a decision.

## Measured performance

Exhaustive search, one run per size, release-mode `dart run`:

| Players | Partitions | Elapsed |
|---:|---:|---:|
| 16 | 6,435 | 16 ms |
| 20 | 92,378 | 68 ms |
| 24 | 1,352,078 | 0.9 s |
| 26 | 5,200,300 | 3.6 s |
| 28 | 20,058,300 | 16.3 s |
| 30 | 77,558,760 | 51 s |

`TS-03` at 30 players with fully distinct ratings takes ~107 s, because distinct
ratings keep more candidates alive through the second priority. This is the
measured answer to `OP-8`.

## Known gaps

Both are recorded in tests rather than left to be discovered.

**Degenerate pools exceed the retention limit.** When a whole line shares one
rating, millions of partitions tie exactly on priorities 1 and 2 and the
candidate set outgrows `candidateRetentionLimit`. The engine throws rather than
sampling, because truncating would quietly turn the exact search into a
heuristic. This is a real gap against `BTGE-HC-7`; closing it means streaming
priorities 3 and 4 the way 1 and 2 already are.

**§11.1 does not follow from §8.** §11.1 says an all-forward pool is spread into
a workable shape via transitions. §8 derives the target by halving the pool's own
profile, so an all-forward pool yields an all-forward target and no spreading
occurs. The two cannot both hold. This package implements §8, which is the rule
with a worked example attached, and `TS-18` asserts that behaviour with the
divergence named in a comment. Resolving it is a specification question.
