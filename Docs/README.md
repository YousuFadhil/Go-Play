# Project Documentation

Current as of `v0.6.0-mvp` — Community-first: one join code, a join policy, and an internal admin role.

| Document | Status |
|---|---|
| `01-PRD.md` | Current |
| `02-SRS.md` | Current |
| `03-Technical-Architecture.md` | Current |
| `04-Wireframes.md` | Historical — the screen list predates the Community migration |
| `05-Workflow.md` | Historical — see `10-Design-Decisions.md` for behaviour as built |
| `06-ERD.md` | Current (v3) |
| `07-Database-Design.md` | Current (v3) |
| `08-UI-UX-Specification.md` | Current |
| `09-Development-Blueprint.md` | Historical — the MVP sprint plan |
| `10-Design-Decisions.md` | Current — the decision log, DD-01 onward |
| `11-Future-Backlog.md` | Current — deferred ideas, not commitments |
| `12-Testing.md` | Current — how to run the suites |

Documents marked historical are kept because they record what was decided at
the time. Where one disagrees with the code, the code and `10-Design-Decisions`
are right.

## BTGE

The Balanced Team Generation Engine has its own pair of documents under
`engineering/`.

**Status: design complete, implementation not started.** No code exists yet.
Implementation may begin once the prerequisites below are met — no open
parameter blocks starting.

| Document | Authority |
|---|---|
| `engineering/BTGE_Design_Knowledge_Base.md` | **Design Authority** — approved product intent (v1.3) |
| `engineering/BTGE_Engineering_Specification.md` | **Implementation Authority** — approved engineering rules (v1.2) |

Before implementation can begin: the schema prerequisite in `KB-D3` — the
rating, date of birth, secondary position and per-match team assignment records
do not exist yet, and designing that change sits outside both BTGE documents.

Before the engine can be validated and released: five Product Owner decisions,
`OP-1`, `OP-2`, `OP-3`, `OP-5` and `OP-6`, listed in §18.1 of the Engineering
Specification.

If any conflict exists, the Knowledge Base governs product intent and the
Engineering Specification must be updated accordingly.

The original approved v1.0 specification is kept as the historical record at
`archive/BTGE_Engineering_Specification_v1.0.docx`. It is superseded — read the
two documents above instead.

The full migration record — the approved permission matrix, the phase plan and
every product decision behind the Community-first model — lives in the
Architecture Migration Specification v1.2, held outside this repository.
