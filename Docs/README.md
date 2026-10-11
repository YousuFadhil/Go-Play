# Project Documentation

This is the index. It deliberately states no release number, schema number or
test count: they change with every release, so they live where they are generated
or checked. For the current state read `../CHANGELOG.md` (what shipped), the
newest file in `../supabase/migrations/` (the schema) and
`engineering/DB_Object_Catalog.md` (what exists, generated from the migrations).

Go Play is Community-first (one join code, a join policy, an internal admin
role) with a public Discover homepage, balanced team generation, recorded results
driving a system-managed rating, statistics and leaderboards, and platform
administration. See *Keeping the documentation current* at the end of this page
for how the documents are kept in step.

| Document | Status |
|---|---|
| `01-PRD.md` | Current — statistics and leaderboards are in MVP scope |
| `02-SRS.md` | Current |
| `03-Technical-Architecture.md` | Current — the map of the stack and where each fact lives; checked by `tool/check-docs.mjs` |
| `04-Wireframes.md` | Historical — the screen list predates the Community migration |
| `05-Workflow.md` | Historical — see `10-Design-Decisions.md` for behaviour as built |
| `06-ERD.md` | Design record (v3) — the Community-first model and the approved statistics model; where it differs from the migrations, the migrations are right |
| `07-Database-Design.md` | Design record (v3) — written against the schema through `0024`; later migrations are indexed in `engineering/DB_Object_Catalog.md` |
| `08-UI-UX-Specification.md` | Current |
| `09-Development-Blueprint.md` | Historical — the MVP sprint plan |
| `10-Design-Decisions.md` | Current — the decision log, `DD-01` onward, plus `SL-1` … `SL-5` |
| `11-Future-Backlog.md` | Current — deferred ideas, not commitments |
| `12-Testing.md` | Current — how to run the suites; records no results, because a result is stale on the next commit |
| `engineering/DB_Object_Catalog.md` | **Generated** — every table, view, function, Edge Function and workflow, with the migration that made it; never edit by hand |

Documents marked historical are kept because they record what was decided at
the time. Where one disagrees with the code, the code and `10-Design-Decisions`
are right.

## Architecture

| Document | Authority |
|---|---|
| `engineering/ARCHITECTURE_DECISIONS_V1.md` | **Architectural Authority** — the approved layer rules: `OP-2` Adapter, `OP-3` Domain Models, `OP-5` Errors, `OP-6` Testing (v1.0) |

Alone among the engineering documents it governs the code rather than
describing it: where an implementation conflicts with it, the implementation is
what changes.

Its `OP-n` identifiers are its own. The BTGE Engineering Specification numbers
an unrelated set of decisions with the same prefix — `OP-6` is Testing Strategy
here and the Diversity lookback window there — so cite the document alongside
the ID.

## Operations

| Document | Authority |
|---|---|
| `engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` | **Operational Authority** — how Supabase is used, changed, backed up and deployed (v1.0) |

It states no business rules. Its open adoption gaps (`GAP-1` … `GAP-4`) are
Product Owner decisions to schedule, not work already done.

## Statistics and leaderboards

| Document | Authority |
|---|---|
| `engineering/Statistics_Leaderboards_MVP_Specification.md` | **Product Authority for statistics and leaderboards** — the approved MVP feature (v2.0, decisions `SL-1` … `SL-5`) |

Approved on 2026-08-01 and **architecturally complete**: every question that
could change the shape of the data is closed. Two levels throughout — Global
(the career, on the Player Profile) and Community (per community, feeding the
dashboard and nine leaderboards over three periods). Its `SL-n` decisions are
recorded as project decisions in `10-Design-Decisions.md`.

**Built.** Level 1 is `player_statistics` (migration `0022`), Level 2 counters are
`community_statistics` (`0028`), and the Community/Period Rating is a derived read
model (`0081`, `DD-17`). The dashboard and leaderboards have their read-model
specifications under `engineering/` and their screens in
`app/lib/features/statistics`; `engineering/Community_Statistics_Build_Verification.md`
records the build check. Later additions (Team of Period, reverse leaderboards)
are in `../CHANGELOG.md`.

## Engineering decision records

| Document | Authority |
|---|---|
| `engineering/Results_Rating_Engineering_Decisions.md` | **Decision record** — why the Results / Rating Integration phase was built as it was (v1.1, decisions `RR-1` … `RR-7`) |

A decision record explains an implementation; it does not authorise one. Where
one disagrees with `01-PRD.md` or `10-Design-Decisions.md` about what the
product does, those win.

v1.1 aligns it to the Statistics & Leaderboards specification: what that phase
built is **Level 1**. No decision in it was withdrawn.

## BTGE

The Balanced Team Generation Engine has its own pair of documents under
`engineering/`.

**Status: integrated.** The engine lives in `packages/btge` — pure Dart, no
Flutter, no Supabase, no schema — and the app depends on it (`app/pubspec.yaml`).
Its inputs and the stored lineup are migration `0018`; generated lineups are saved
by `save_generated_lineup_v1`, with one `btge_generation_runs` row per generation
(`0089`).

| Document | Authority |
|---|---|
| `engineering/BTGE_Design_Knowledge_Base.md` | **Design Authority** — approved product intent (v1.6) |
| `engineering/BTGE_Engineering_Specification.md` | **Implementation Authority** — approved engineering rules (v1.5) |

The schema prerequisite in `KB-D3` — the rating, date of birth, secondary
position and per-match team assignment records — was delivered by migration
`0018`.

**The Product Decision gate is closed.** All five decisions that blocked final
validation — `OP-1`, `OP-2`, `OP-3`, `OP-5` and `OP-6` — were approved on
2026-07-31 and are recorded in §18.1.1 of the Engineering Specification.

That is the gate, not the outcome. This index does not record whether final
validation has since been executed; §18 of the Engineering Specification does.
What remains in §18.1 — `OP-4`, `OP-7`, `OP-8` — are
Engineering Decisions and an Implementation Detail, and none has ever blocked
validation. Who may change a player's rating stays a separate, open
Product/Business Policy question (see `07-Database-Design.md`).

Two follow-ups are recorded in `11-Future-Backlog.md` for review after
integration — a documented inconsistency between §8 and §11.1, and a known
limitation on pools where a whole line shares one rating. Neither changes the
Knowledge Base or the Engineering Specification.

If any conflict exists, the Knowledge Base governs product intent and the
Engineering Specification must be updated accordingly.

The original approved v1.0 specification is kept as the historical record at
`archive/BTGE_Engineering_Specification_v1.0.docx`. It is superseded — read the
two documents above instead.

The full migration record — the approved permission matrix, the phase plan and
every product decision behind the Community-first model — lives in the
Architecture Migration Specification v1.2, held outside this repository.

## Keeping the documentation current

Documentation drifts when it is written by hand about things that change, so each
kind of fact has one owner:

- **Generated.** `engineering/DB_Object_Catalog.md` is built from the migrations,
  the Edge Functions, the Pages Function and the workflows. Regenerate it with
  `node tool/check-docs.mjs --write`; never edit it.
- **Checked.** `node tool/check-docs.mjs` fails when a migration newer than `0094`
  is not named in `../CHANGELOG.md`, when the catalog is stale, when an Edge
  Function has no README or is missing from `03-Technical-Architecture.md`, when
  `CLAUDE.md`, `SETUP.md` or this page names a file that does not exist, or when
  prose carries a number that goes stale (a migration number, a test count, a
  "last executed" result, a version stamp). The same check runs on every pull
  request (`.github/workflows/docs-sync.yml`), and its own tests run with
  `node --test tests/docs/sql-catalog.test.mjs tests/docs/check-docs.test.mjs`.
- **By hand, in the same phase as the change.** One CHANGELOG line per migration;
  a decision record in `10-Design-Decisions.md` for anything that changes what
  the product does (with the Product Owner's approval); the table specification
  when a table's columns or rules change.
- **Never in prose.** Release numbers, schema numbers, test counts and "last run"
  results. Point to the file or command that produces them.

`CLAUDE.md` §13 makes this the closing step of every phase that touches the
database, an Edge Function or user-visible behaviour.
