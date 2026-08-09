# Project Documentation

Current as of `v0.4.0-public-beta`, the first public beta — built and tested on
`feature/btge-adapter`, schema through migration `0035`. Community-first (one
join code, a join policy, an internal admin role), a public Discover homepage,
balanced team generation, and recorded results driving a system-managed rating.

**Statistics and leaderboards entered MVP scope on 2026-08-01** and are
**approved but not built**. The whole documentation set was aligned to that
approval on the same day; see *Statistics and leaderboards* below.

| Document | Status |
|---|---|
| `01-PRD.md` | Current — statistics and leaderboards are in MVP scope |
| `02-SRS.md` | Current |
| `03-Technical-Architecture.md` | Current |
| `04-Wireframes.md` | Historical — the screen list predates the Community migration |
| `05-Workflow.md` | Historical — see `10-Design-Decisions.md` for behaviour as built |
| `06-ERD.md` | Current (v3) — records the approved statistics model as not built |
| `07-Database-Design.md` | Current (v3) — schema through `0024`, plus the approved statistics architecture |
| `08-UI-UX-Specification.md` | Current |
| `09-Development-Blueprint.md` | Historical — the MVP sprint plan |
| `10-Design-Decisions.md` | Current — the decision log, `DD-01` onward, plus `SL-1` … `SL-5` |
| `11-Future-Backlog.md` | Current — deferred ideas, not commitments |
| `12-Testing.md` | Current — how to run the suites |

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

**Not built.** The engineering design phase — ERD and Database Design — has not
started. §14 of the specification lists what may proceed and the prerequisites
that must be settled during the phase.

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

**Status: design complete; engine implemented, awaiting review.** The engine
lives in `packages/btge` — pure Dart, no Flutter, no Supabase, no schema.
Integration begins only after that branch is reviewed.

| Document | Authority |
|---|---|
| `engineering/BTGE_Design_Knowledge_Base.md` | **Design Authority** — approved product intent (v1.6) |
| `engineering/BTGE_Engineering_Specification.md` | **Implementation Authority** — approved engineering rules (v1.5) |

Before integration can begin: the schema prerequisite in `KB-D3` — the rating,
date of birth, secondary position and per-match team assignment records do not
exist yet, and designing that change sits outside both BTGE documents.

**The Product Decision gate is closed.** All five decisions that blocked final
validation — `OP-1`, `OP-2`, `OP-3`, `OP-5` and `OP-6` — were approved on
2026-07-31 and are recorded in §18.1.1 of the Engineering Specification.

That is the gate, not the outcome: **final validation has not been executed and
has not passed.** What remains in §18.1 — `OP-4`, `OP-7`, `OP-8` — are
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
