# Architecture Decisions v1.0

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Approved — final** |
| Role | **Official architectural reference** for Go Play |
| Owner | Product Owner |
| Source | Approved decision record, 2026-07-28 |

## Purpose

- This document is the official architectural reference for Go Play's approved
  architecture decisions.
- It is the **single source of truth** for how the application layers relate
  to Supabase and to each other.
- **If any implementation conflicts with this document, this document
  prevails.** The implementation must be brought into line with the decision
  recorded here — not the other way around.

---

## OP-2 — Adapter Layer Responsibilities

### Decision

The Adapter is the infrastructure layer responsible for:

- Connecting to Supabase.
- Converting data to and from Domain Models.
- Converting technical errors into unified Failures.
- Composing data from multiple queries when needed, without applying
  business logic.

### Allowed Responsibilities

The Adapter is allowed to:

- Perform all communication with Supabase (Queries / RPC / Auth / Storage as
  needed).
- Convert Supabase data into the approved Domain Models or DTOs.
- Convert Domain Models into the format Supabase expects.
- Convert technical errors into unified errors the application understands.
- Combine the results of multiple queries into a single object when needed,
  provided the combination is pure data composition and not an application
  of business rules.

### Forbidden Responsibilities

The Adapter is forbidden to:

- Apply any business logic.
- Make any product-specific decision.
- Validate registration rules.
- Decide whether to promote a player from the reserve list.
- Determine user permissions.
- Compute statistics.
- Change application behavior based on data.
- Contain any logic that must remain correct even if Supabase is replaced by
  another provider.

### Rationale

The purpose of this decision is to fully isolate the application from
Supabase, so that the data provider can be changed in the future without
affecting the application's logic or its interfaces.

### Golden Rule

If Supabase could be replaced tomorrow without needing to change a given
piece of logic, that logic does not belong inside the Adapter.

---

## OP-3 — Domain Models & DTOs

### Decision

Outside the Adapter, there is exactly one representation per entity in the
system: the **Domain Model**. All application layers (Repository, Use Cases,
UI) work with the same model.

### Scope

- Examples of Domain Models: `Match`, `Player`, `Registration`, `Group`,
  `Profile`.
- No layer outside the Adapter deals with any Supabase-related type.
- The Adapter is solely responsible for the conversion between
  representations:
  - On read: `Supabase Row` → (conversion) → `Domain Model`.
  - On write: `Domain Model` → (conversion) → `Supabase Row`.
- Any detail specific to Supabase — column names, relationships, or
  Supabase-specific data types — stays confined inside the Adapter.

### Rules

DTO policy:

- A DTO is allowed **only if** it is:
  - Specific to Supabase.
  - Used internally within the Adapter.
  - Never exposed to any other layer.
- A DTO is forbidden from being:
  - Received by a Repository.
  - Returned by a Repository.
  - Used by a Use Case.
  - Used by the UI.
- A DTO is not part of the application's architectural contract — it is an
  implementation detail.

### Golden Rule

If a data type leaves the Adapter, it must be a Domain Model. Any other type
is a violation of the approved architecture.

---

## OP-5 — Error Strategy

### Decision

No error originating from Supabase, the network, or any data provider is
allowed to reach the rest of the application in its original form. All
errors pass through the Adapter, where they are converted into unified
errors the application understands.

### Failure Types

The application adopts a small, fixed set of error types:

- `AuthenticationFailure` — login errors or an expired session.
- `AuthorizationFailure` — the user lacks the required permission.
- `ValidationFailure` — invalid or incomplete data.
- `NotFoundFailure` — the requested resource does not exist.
- `ConflictFailure` — a state conflict (e.g. a registration conflict or data
  that changed concurrently).
- `NetworkFailure` — a connectivity interruption or network problem.
- `InfrastructureFailure` — a failure in the database or a supporting
  service.
- `UnknownFailure` — any unclassified error.

This list is not tied to Supabase — it is the application's own "error
language."

### UI Contract

The UI knows only the error's **type**, not its technical detail. For
example:

- `NetworkFailure` → offer a retry option.
- `ValidationFailure` → ask the user to correct their input.
- `AuthorizationFailure` → block the operation and explain that the user
  lacks permission.

This keeps UI behavior consistent regardless of the data provider.

### Infrastructure Contract

Technical details — PostgreSQL codes, Supabase error codes, original
exception messages, stack traces — stay inside the infrastructure layers.
They may be used for logging or diagnostics, but they are never used as a
basis for application logic and are never shown to the user.

### Golden Rule

The application depends on the **meaning** of an error, not on its source or
its technical wording. If Supabase is replaced in the future, no other layer
will need any change in how it handles errors.

---

## OP-6 — Testing Strategy

### Decision

Mandatory tests focus on Business Rules, Use Cases, and Repository/Adapter.
UI tests are not mandatory in the MVP and are added only where they provide
clear value.

### Mandatory Tests

- Business Rules
- Use Cases
- Repository / Adapter

### Pull Request Acceptance Criteria

A PR may not be merged unless:

- All mandatory tests pass.
- `flutter analyze` passes.
- The build succeeds.
- It does not cause a regression in behavior.
- Every new business rule ships with a test that covers it.

### Regression Policy

Every bug fix must be accompanied by a test that prevents its recurrence.

---

# Architectural Constraints

Checklist to reference during development:

- [ ] No business logic, product decision, permission check, or statistic
      computation lives inside the Adapter.
- [ ] No logic that must stay correct across a provider change lives inside
      the Adapter — only Supabase communication, model conversion, error
      conversion, and pure data composition.
- [ ] Every layer outside the Adapter (Repository, Use Cases, UI) uses
      Domain Models only — never a Supabase-related type.
- [ ] DTOs, when they exist, are Supabase-specific, stay internal to the
      Adapter, and never cross into a Repository, Use Case, or the UI.
- [ ] Any type that leaves the Adapter is a Domain Model — nothing else.
- [ ] No raw Supabase, network, or provider error reaches the application
      outside the Adapter — every error is converted to one of the eight
      approved Failure types.
- [ ] The UI branches only on Failure type, never on technical error detail
      (PostgreSQL codes, Supabase codes, exception messages, stack traces).
- [ ] Technical error detail is confined to the infrastructure layer, for
      logging/diagnostics only.
- [ ] Every PR passing review has: all mandatory tests (Business Rules, Use
      Cases, Repository/Adapter) green, a clean `flutter analyze`, a
      successful build, no behavior regression, and a test for every new
      business rule.
- [ ] Every bug fix ships with a regression test.

---

# Amendment Policy

- This document is the official reference for Go Play's architecture
  decisions.
- No decision recorded here may be modified or bypassed during development.
- Any future change must first be an approved Product Decision, adopted
  before implementation begins.
- No architectural change is permitted while implementing a feature unless
  it has been formally approved beforehand.
