# Go Play AI Development Protocol v2

## Purpose

Deliver the highest implementation quality while minimizing unnecessary
AI context and token consumption.

## Core Principles

1.  Correctness before optimization.
2.  Read only what is required.
3.  ChatGPT thinks; Claude implements.
4.  Never perform repository-wide work unless explicitly requested.

# Standard Workflow

## Phase 1 -- ChatGPT

-   Clarify the request.
-   Decide whether Claude is required.
-   Estimate affected files.
-   Choose Context Budget.
-   Choose Execution Mode.
-   Produce one implementation prompt.

## Phase 2 -- Claude Code

-   Search before reading.
-   Read the minimum files.
-   Implement.
-   Run only relevant validation.
-   One approval per task: once the Product Owner approves the task summary,
    carry it through without per-step questions -- commit, pull request,
    merge to `develop` once the `Flutter checks` workflow passes, a safe
    migration, and a staging deploy. The Product Owner tests on staging and
    then decides the release to `main`. See `CLAUDE.md` §2.
-   Stop and ask mid-task only for a finding that changes the approved scope
    or needs a product decision, a failing check, an irreversible step, or a
    migration that changes what users of the deployed app see.

## Phase 3 -- ChatGPT

-   Review implementation.
-   Detect gaps.
-   Decide whether another Claude cycle is necessary.

# Context Budget

  Class             Max Files
  ------- -------------------
  S                         3
  M                        10
  L                        25
  XL        Approval required

Exceeding the estimate up to L is reported, not asked; XL needs approval
before work starts.

# Execution Modes

## QUICK

Single-file fixes.

## NORMAL

Default.

## SAFE

Extra validation and broader tests.

## DEEP

Architecture/repository analysis only on explicit request.

# Task Classification

  Type            Default Mode
  --------------- --------------
  Bug Fix         QUICK
  Small Feature   NORMAL
  Migration       SAFE
  Refactor        SAFE
  Architecture    DEEP
  Documentation   ChatGPT

# File Access Rules

-   Search using rg/git grep before opening files.
-   Never open documentation unless required.
-   Never reread unchanged files.
-   Never scan the repository by default.

# Validation Rules

Only run: - dart analyze (affected scope) - flutter test (affected
tests) - targeted commands

Avoid full test suites unless requested.

# Reporting

Default: - Files changed - Tests - Result - Remaining issues

Long reports only if requested.

# Escalation

If the task requires: - \>25 files - architecture changes - repository
audit - mass refactor

Stop and ask for approval.
