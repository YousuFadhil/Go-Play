# Community Statistics — Build & Verification Report

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | **Built and verified.** All scenarios pass |
| Feature | Feature-01 — Community Statistics Foundation |
| Authority | `engineering/Community_Statistics_Table_Specification.md` v1.0 |
| Migration | `supabase/migrations/0028_community_statistics.sql` |
| Baseline | `v0.6.0-mvp`, schema through `0027` |
| Verified against | Supabase project `Go-Play` (`odhimoxvuhiyunwutzff`), PostgreSQL 17.6 |
| Date | 2026-08-07 |

---

## 1. What was built

One table, one constant, six functions, two triggers, one policy — and nothing
else. No rating, no rating history, no leaderboard, no view, no client code.

### 1.1 The table

`public.community_statistics` — twelve columns, exactly as §6.1 specifies.

| | |
|---|---|
| Primary key | `(community_id, period_type, period_key, user_id)` — natural composite, community first, no surrogate |
| Counters | `matches_played`, `wins`, `losses`, `draws`, `goals`, `mvp_count` — `int not null default 0`, non-negative |
| Foreign keys | `communities` and `users`, both `cascade`. **No reference to `community_members`** (`CS-C8`) |
| Index | `CS-X2` on `(user_id, community_id)` |
| Not present | rating column, eligibility flag, period start/end dates, surrogate id |

**No speculative fields.** The six counters are the six `SL-1` §9.1 names for
Level 2, and they are deliberately identical to Level 1 — which is what makes
the cross-level reconciliation in §4 possible at all.

### 1.2 Functions and triggers

| Object | Kind | Purpose |
|---|---|---|
| `statistics_period_zone()` | new | **`A1` in one place, FROZEN.** Build req. 2 |
| `statistics_period_key(timestamptz, text)` | new | Period derivation from the match's start (`CS-C15`) |
| `match_community_contribution(uuid)` | new | **Extends** `match_result_contribution`; adds community and period |
| `apply_community_statistics(uuid, int)` | new | Apply / reverse, as two statements (`CS-C10`) |
| `apply_match_statistics(uuid, int)` | **replaced** | Now moves both levels in one call (`DP-2`) |
| `rebuild_community_statistics(uuid)` | new | Recompute from evidence. Build req. 4 |
| `reconcile_community_statistics()` | new | Three checks. `CS-C17`, build req. 3 |
| `create_community_statistics_on_join()` | new | `overall` record at first join (`CS-C7`) |
| `community_members_create_statistics` | new trigger | `after insert on community_members` |
| `community_statistics_set_updated_at` | new trigger | `before update` |
| `community_statistics_select_members` | new policy | Community-scoped read (§10.2) |

**No existing table, column, constraint, policy or trigger was changed.**
`record_match_result` and `reverse_match_effects_before_delete` keep the bodies
`0022` gave them, untouched.

---

## 2. The two design decisions taken during the build

Both are recorded here because neither is stated verbatim in the specification.

### 2.1 Both levels move in one call, rather than three paired call sites

`DP-2` requires Level 1 and Level 2 to *"move together or not at all"*. There are
three places that move Level 1: the reversal and the application inside
`record_match_result`, and the `before delete on matches` trigger.

Adding a second call beside each would have left three places where a later edit
could move one level and not the other — and §11.2 is explicit that nothing short
of the reconciliation could detect it afterwards. Instead `apply_match_statistics`
now applies both levels. **"They move together" became a property of the code
rather than a discipline every caller has to remember**, and the three call sites
did not have to be touched at all.

Both levels therefore land inside the recording operation's transaction, under
the match row lock `record_match_result` already takes — `CS-C16`, inherited
rather than re-implemented.

### 2.2 A reversal removes a periodic record that has gone to zero

§2.3 is explicit that periodic records exist only for periods the player actually
played in, *"because one carrying only zeros asserts nothing"*. The reverse path
therefore deletes a **periodic** record whose six counters have just reached zero.
`overall` records are never deleted — there the zero is the fact (§2.2), and
`SL-4` preserves them.

**Without this the incremental path and `rebuild_community_statistics` disagree,
and disagree silently:** the rebuild's step (d) removes exactly these rows, while
the evidence check compares a stored zero against an absent contribution of zero
and finds them equal. It would have surfaced only as a period's leaderboard or
player count including people who did not play in that period. §5.2 shows the
two paths now agree exactly.

---

## 3. Required verification

All three required scenarios were run **against the live database** through
`record_match_result` — the real entry point, under a real `auth.uid()`, with the
real authorization path — and not by inspection. `CS-R1` is explicit that `RR-4`
*"passed review by inspection"* and *"the migration ran clean"*.

**Fixture.** A 3-v-3 lineup on a previously unrecorded match starting
2026-08-02 (→ `2026-W31`, `2026-08`). The focus player is a member of **two**
communities and already carried counters in the other one, so every step also
tests isolation. **The whole scenario ran in a transaction and was rolled back**
— the database is unchanged (§5.1).

### 3.1 A new result updates statistics

Recorded A 3–1; focus player MVP with 2 goals.

| Scope | Period | played | won | lost | goals | mvp |
|---|---|---|---|---|---|---|
| Focus / test community | `overall` | 1 | 1 | 0 | 2 | 1 |
| Focus / test community | `weekly` `2026-W31` | 1 | 1 | 0 | 2 | 1 |
| Focus / test community | `monthly` `2026-08` | 1 | 1 | 0 | 2 | 1 |
| **Focus / other community** | all three | **1** | **0** | **1** | **1** | **0** |

**PASS.** Exactly three records per participant (`CS-C12`), created for the
period played in and not in advance. The other community's records **did not
move** — isolation is structural, not a filter. Level 1 career rose 1→2 played,
1→3 goals, 0→1 MVP, so both levels moved together.

Record counts: `weekly` 6, `monthly` 6 (the six participants), `overall` 8 (every
member, including the two who did not play).

### 3.2 A correction reverses, then reapplies

Corrected to A 1–2; MVP moved to an opponent; focus player down to 1 goal.

| Scope | Period | played | won | lost | goals | mvp |
|---|---|---|---|---|---|---|
| Focus / test community | all three | 1 | **0** | **1** | **1** | **0** |
| Focus / L1 career | — | 2 | 0 | 2 | 2 | 0 |

**PASS.** The win became a loss, the second goal was taken back and the MVP was
removed — in all three period records simultaneously. `matches_played` correctly
stayed at 1: the correction changed the result, not who played.

**No negative-counter error was raised at any point.** This is the specific
failure `RR-4` produced at Level 1 and `CS-R1` predicts is *more* likely here,
and it is the reason apply and reverse are separate statements.

### 3.3 Deleting a match restores the previous values

| Scope | Period | Result |
|---|---|---|
| Focus / test community | `overall` | back to **0/0/0/0/0/0** — the baseline |
| Focus / test community | `weekly`, `monthly` | **rows removed** — the periods are as if never played |
| Focus / other community | all three | **unchanged** |
| Focus / L1 career | — | back to 1 played, 1 goal — the baseline |
| Record count / test community | — | `overall` 8; no weekly, no monthly |

**PASS, and byte-identical to the step-0 baseline.** The `overall` record
survived at zero, as `SL-4` requires — the player is still a member and the
record is still theirs.

---

## 4. Reconciliation — `CS-C17`, `DP-11`

`reconcile_community_statistics()` runs three checks and returns one row per
discrepancy; an empty result is the pass condition.

| # | Check | Detects |
|---|---|---|
| 1 | Stored counters vs recomputed from the evidence | Everything; survives a Level 1 defect |
| 2 | A periodic figure exceeding its own `overall` | A misplaced period, a missed reversal, an `A1` re-bucketing |
| 3 | Level 1 career vs the sum of Level 2 `overall` records | Drift between the two levels |

**Result: 0 discrepancies at every stage** — after the backfill, after the new
result, after the correction, after the deletion, and after the membership
lifecycle tests. Check 3 passing is `SL-2` §2.5's *"agree by construction"*
verified rather than assumed.

---

## 5. Additional verification

### 5.1 Backfill — build req. 5

Done **through the rebuild, not through an insert of zeros**, so the table was
correct from its first moment rather than from the next result onwards.

| | |
|---|---|
| `overall` records created | **17** — one per existing membership, exactly |
| `weekly` / `monthly` records | **8 + 8** — the participants of the one already-recorded match |
| Counters | Filled from the evidence; reconciliation clean immediately |

### 5.2 The rebuild is a verified no-op

Running `rebuild_community_statistics()` over a table the incremental path
already maintains changed **0 rows of 33**. The two paths agree exactly, which is
what makes the rebuild safe to run as a repair.

### 5.3 Access control — build req. 8, `CS-R4`

The denials were asserted, not assumed.

| Actor | Action | Result |
|---|---|---|
| Non-member of the community | read its records | **0 rows** |
| Non-member | read everything visible | **25 rows** — only their own community |
| Member | read the community's records | **8 rows** — every member's, including departed players' |
| `anon` | any read | **permission denied** |
| `authenticated` | `insert` / `update` / `delete` | **permission denied** on all three (`CS-C9`) |

**`PS-R1` was not repeated at Level 2.** The read is scoped to membership from
the first migration, and this did not become a second broadly-readable table.

### 5.4 Constraints

| Rule | Attempt | Result |
|---|---|---|
| `CS-C5` | `('overall', '2026-W31')` | **rejected** — `community_statistics_period_coherent` |
| `CS-C4` | `period_type = 'yearly'` | **rejected** |
| `CS-C6` | `goals = -1` | **rejected** — `community_statistics_goals_check` |

`CS-C5` is the constraint no approved document states; §7.2 required it and it
holds.

### 5.5 Membership lifecycle — `SL-4`

| Step | Expected | Actual |
|---|---|---|
| Records before departure | 3 | 3 |
| **After departure** | preserved, unaltered | **3, counters unchanged** |
| **After rejoin** | the same records resume | **3 — no second record** |
| `overall.created_at` after rejoin | unchanged | **unchanged** |
| A brand-new member | gets one `overall` record | **1** |

**Deleting a membership did nothing to the records** — `A7` and `CS-C8`, the
defining negative of the design, confirmed behaviourally.

### 5.6 Database linter

The one finding attributable to this migration — `statistics_period_zone` without
`set search_path`, against the rule `0024` set for this schema — was **fixed**.
No new RLS finding: the table has RLS enabled *and* a policy. All remaining
advisories predate this work.

---

## 6. Dashboard metrics now available

**Six of the Community Dashboard's ten figures, plus the population for all nine
leaderboards.** Every query below is an index seek on the leading key columns.

### 6.1 From `community_statistics`

| # | Metric | Periods | Derivation |
|---|---|---|---|
| 1 | **Total Goals** | overall | `sum(goals)` where `period_type='overall'` |
| 2 | **Total Players** | overall | `count(*)` where `period_type='overall'` |
| 3 | **Goals Scored** | weekly, monthly | `sum(goals)` for the period |
| 4 | **Most Active Player** | weekly, monthly | max `matches_played` in the period |
| 5 | **Top Scorers** | all three | order by `goals` |
| 6 | **Most MVP** | all three | order by `mvp_count` |
| 7 | **Wins / Losses / Draws per player** | all three | the three counters |
| 8 | **Leaderboard population and eligibility** | all three | the record set, joined to `community_members` at read time |

### 6.2 NOT from this table — §19.2

**Four dashboard figures are facts about matches and must be read from
`matches`.** Summing `matches_played` counts *player-appearances*, not matches:
ten players in one match sums to ten.

| Metric | Source |
|---|---|
| **Total Matches** | `count(*)` over `matches` |
| **Matches Played** (weekly, monthly) | `matches` filtered by `start_at` |
| **Last Match Date** | `max(start_at)` over `matches` |

Both are already served by `matches(community_id, start_at)`.

### 6.3 Not available, and deliberately

**The Community Rating and *Highest Rated*.** The rating is a separate entity
(`E8`), one value per (player, community) with no period — item 11 and §4.4.
It is not built by this migration and is not stored here.

---

## 7. Open items carried forward

| ID | Item | Status |
|---|---|---|
| `CS-R2` | The `A1` constant is fragile | **Closed to the extent possible** — stated once, marked FROZEN, and a rebuild exists as the safe response to any change |
| `CS-R3` | Three inherited evidence-destruction cases (`MRS-R1`, `MG-R1`, `RR-7`) now leave Level 2 figures too | **Inherited, unresolved.** Not this table's to fix; the reconciliation makes them visible |
| `CS-R8` / `CS-D3` | A departed player cannot read their own preserved record | **Accepted**, a consequence of community-scoped reads |
| `CS-D4` | Nine `DP-n` principles still have no definition in the repository | **Open**, unchanged by this build |
| — | `supabase/setup_all.sql` covers `0001–0024` only | **Pre-existing.** It is a generated convenience copy and was already stale by three migrations; not updated here |

---

## 8. Result

**Every requirement of §20 is met, and the three required scenarios pass against
a real database.**

| Build requirement | Status |
|---|---|
| 1. `CS-D2` settled before building | ✓ Resolved 2026-08-02; no rating column |
| 2. `A1` fixed in one place, recorded as frozen | ✓ `statistics_period_zone()` |
| 3. Reconciliation built **with** the table | ✓ Three checks, 0 discrepancies |
| 4. Rebuild operation | ✓ Verified no-op over a maintained table |
| 5. Backfill every existing membership | ✓ 17 of 17, through the rebuild |
| 6. Extend the shared contribution helper | ✓ One arithmetic, both levels |
| 7. Apply and reverse separate, **tested against a real database** | ✓ §3.2, §3.3 |
| 8. Read rule scoped, denials asserted | ✓ §5.3 |
