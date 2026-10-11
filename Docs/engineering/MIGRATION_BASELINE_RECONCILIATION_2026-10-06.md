# Go Play — Migration Baseline Reconciliation and Staging Check

**To:** Chief Architect
**From:** Product Owner (prepared with Claude, 2026-10-06)
**Scope:** the two checks you required before Phase 1. Everything here was read-only. Nothing was changed in the repository, the database, or any configuration.

## Result

1. **Baseline.** The migration *history* differs between the repository and the live database, but I found no difference in the *resulting schema*. Every live function body equals the latest definition in the repository, and every live table, view, policy, and trigger is accounted for by name. The history differences are record-keeping and documentation text. One class of object was not compared (section 5).
2. **Staging.** There is no separate staging Supabase project. Staging and production share one database. This is already documented in the repository.

Both need your ruling (section 7).

---

## 1. Method

- **Local:** 95 migration files, read from a checkout whose content is identical to `origin/main` and `origin/develop`.
- **Live:** `supabase_migrations.schema_migrations` on project `Go-Play` holds 90 records. Every record stores the full SQL that was applied, as one statement string.
- **History comparison:** hash of each local file against hash of each live record's stored SQL, at increasing levels of normalization (whitespace; then SQL comments; then `COMMENT ON` statements). Remaining differences were diffed statement by statement.
- **End-state comparison:** live catalog (`pg_proc`, `pg_class`, `pg_policies`, `pg_trigger`) against what the 95 local files produce when read in order.

## 2. Migration history: local against live

| # | Finding | Local files | Live records |
|---|---|---:|---:|
| 1 | Identical, including comments | 27 | 27 |
| 2 | Identical code, different `--` comments | 42 | 42 |
| 3 | Identical code, differing only in `COMMENT ON ...` statements | 13 | 13 |
| 4 | Small text differences, each explained below | 4 | 4 |
| 5 | One local file corresponding to three live records | 1 | 3 |
| 6 | Local file with no live record | 8 | — |
| 7 | Live record with no local file | — | 1 |
| | **Total** | **95** | **90** |

**Row 3.** `0037`, `0048`, `0051`, `0060`, `0062`, `0063`, `0064`, `0065`, `0068`, `0070`, `0073`, `0086`, `0093`. The live SQL omits or rewords the documentation strings. Example: live `0093` has no `COMMENT ON FUNCTION` statements; live `0037` has a hyphen where the file has an em dash. Executable SQL is identical.

**Row 4.**

| Migration | Difference | End state on live |
|---|---|---|
| `0010` (live name `invite_links`) | One `REVOKE` on `invite_link_state`: live `from anon, public`, file `from anon, authenticated, public` | Function no longer exists (dropped with invite links in `0012`) |
| `0045` | One `REVOKE` on `rebalance_roster`: live omits `public` | ACL is owner and `service_role` only |
| `0046` | Four `REVOKE`s (`match_result_contribution`, `player_statistics_evidence`, `apply_match_rating_effects`, `apply_rating_delta`): live omits `public` | ACL is owner and `service_role` only on all four |
| `0049` | Seven statements: live `jsonb_array_elements(p_goals) e`, file `... as e` | Same meaning; the function body on live equals the latest repository definition |

The character counts of these differences account for the whole length difference of each file.

**Row 5.** Local `0028_community_statistics` against live `0028`, `0028a_community_statistics_reverse_prunes_empty_periods`, and `0028b_statistics_period_zone_search_path`. The live database received the original plus two follow-up patches; the repository file appears to be the consolidated version. I did not diff this one statement by statement. The functions it defines match on live, and `statistics_period_zone()` on live has `search_path=public` and an owner/`service_role`-only ACL, as the file specifies.

**Row 6.** `0001`–`0004`, `0007`–`0009`, `0034`.

- `0001`–`0004`: the project was created 2026-07-21 04:55 UTC and the first tracked record is from 06:43 the same day. These appear to have been applied before tracking began.
- `0007`–`0009`: no record between `match_management_v2` (07-24) and `invite_links` (07-26). They appear to have been applied outside tracking. Their effects are present: the `communities` and `community_members` tables and the renamed `communities_set_updated_at` trigger exist.
- `0034`: no record. Its effect is present: `anon` and `authenticated` hold only `SELECT` on `v_public_communities` and `v_public_upcoming_matches`.

**Row 7.** `switch_auth_identity_to_email` (2026-07-21): drops `users_phone_key` and redefines `handle_new_user()`. On live there is no `users_phone_key`, and `handle_new_user()` equals the latest repository definition.

**Names.** Twelve live records carry no number prefix: `0005`, `0006`, `0011`–`0017`, `0021`, `0033`, `0080`. Their SQL matches the numbered files.

**Head.** Both end at `0094_nearby_discovery_wilayat`.

**Likely cause.** The SQL applied to live was an edited copy of each file (comments and documentation stripped), not the file itself. The repository still holds `.min` copies of some SQL files in `supabase/`.

## 3. End-state verification

| Object class | Live | Result |
|---|---:|---|
| Functions in `public` | 163 | All 163 bodies identical to the latest repository definition (whitespace and comments ignored). None missing, none extra. |
| Tables | 36 | All match by name |
| Views | 16 | All match by name |
| RLS policies (`public`, `storage`) | 39 | All match by table and name |
| Triggers calling `public` functions | 24 | All match by table and name |

The name comparison first showed five local-only items and one live-only item. All six are explained by statements my parser did not model: two `DROP TABLE ... CASCADE` in `0012` (removing two policies and two triggers) and one `ALTER TRIGGER ... RENAME` in `0007`.

## 4. Live definitions of the objects Phase 1 touches

**`public.users`** — 17 columns: `id`, `phone` (not null), `full_name` (not null), `primary_position` (not null), `is_active`, `created_at`, `updated_at`, `overall_rating`, `date_of_birth` (nullable), `secondary_position`, `avatar_path`, `profile_visibility`, `age_visible`, `suspended_at`, `suspended_by`, `suspension_reason`, `default_wilayat_code`.

- CHECKs: `primary_position` in GK/DEF/MID/FWD; `secondary_position` null or in the same set; `profile_visibility` in EVERYONE/COMMUNITY_MEMBERS; `overall_rating` 0–10.
- FKs: `id` → `auth.users` (cascade); `default_wilayat_code` → `wilayats(code)`.
- No unique constraint on `phone`.
- Policies: `authenticated_select_active_users` (SELECT, `is_active`); `users_update_own_profile` (UPDATE, `auth.uid() = id AND is_current_user_active()`).
- Trigger: `users_set_updated_at`.
- Column-level UPDATE granted to `authenticated`: `full_name`, `phone`, `date_of_birth`, `primary_position`, `secondary_position`, `avatar_path`, `profile_visibility`, `age_visible`, `default_wilayat_code`.

**`public.notification_push_preferences`** — `user_id`, `match_push`, `community_push`, `mute_all`, `updated_at`. Own-row SELECT, INSERT, UPDATE policies.

**`public.admin_audit_log`** — 10 columns. RLS enabled with no policies. `action` CHECK allows `USER_SUSPENDED`, `USER_REACTIVATED`, `COMMUNITY_SUSPENDED`, `COMMUNITY_REACTIVATED`. `target_type` CHECK allows `USER`, `COMMUNITY`.

**Functions** (all `security definer`, `search_path=public`):

| Function | Executable by |
|---|---|
| `is_system_admin()` | `authenticated`, `service_role` |
| `record_admin_audit(text, text, uuid, text, text, jsonb)` | `service_role` only; actor is `auth.uid()` and it raises when that is null |
| `admin_list_users(text)` | `authenticated`, `service_role` |
| `admin_suspend_user(uuid, text)` | `authenticated`, `service_role` |
| `complete_my_player_profile(text, text, date, text, text)` | `authenticated`, `service_role` |

Live counts: 1 system admin; 39 accounts (36 email only, 2 Google only, 1 both).

## 5. Not verified

- View definitions and policy expressions. PostgreSQL stores them deparsed, so they cannot be hash-compared with source text. Only names were compared, except for the `users` policies shown above.
- Column types and defaults, indexes, and table grants for tables other than those in section 4.
- Function attributes (volatility, argument defaults, grants) other than the samples shown.
- Storage buckets, extensions, scheduled jobs, and Auth dashboard settings.
- I did not replay the 95 migrations into an empty database and diff the catalogs. That would be the complete proof and needs a local Supabase stack.

## 6. Staging

- The Supabase account has one organization, one project (`Go-Play`), and one branch (`main`, no preview branches).
- `Docs/engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` states: "Staging and production share one Supabase project ... there is no 'try it on staging first' for Dashboard configuration."
- "Staging" is a second front end: the `go-play-staging` Cloudflare Pages site, built from a chosen ref and pointed at the same database.

Consequences:

- A Phase 1 migration can only be applied to the production database. Staging can test the Flutter side against it, not the migration itself.
- Phase 2 cannot be tested without touching production Auth, unless a separate Supabase project is created.

## 7. Rulings requested

1. **Baseline.** Do you accept "live schema at `0094` equals the repository end state, within the limits of section 5" as the trusted baseline for writing the next append-only migration? Or do you require the full replay-and-diff first?
2. **History.** I propose leaving both histories untouched and recording this reconciliation in the repository documentation. Agreed?
3. **Apply discipline.** For the next migration: apply the committed file verbatim, then verify by hash against the stored record. Agreed?
4. **Phase 1 without a staging database.** The Phase 1 migration is additive: new functions and one widened CHECK constraint. Is applying it to the shared database, then testing through the staging front end, acceptable? Acceptance criterion 13 ("works on a real Staging before merge") cannot be met literally.
5. **Phase 2.** You ruled out testing on production. That makes a separate staging Supabase project a precondition for Phase 2, and a Product Owner decision. Please confirm, and say whether Supabase branching is an acceptable alternative.

## 8. Phase 1 scope as I now understand it (confirm or correct)

- One read RPC and five write RPCs mirroring the owner's operations. No patch RPC.
- One audit action, `USER_PROFILE_UPDATED`, with `before`, `after`, `changed_fields` in `metadata`. No Phase 2 actions in this migration.
- No change means no UPDATE and no audit row.
- Guards on every write: caller is a system admin, target is not the caller, target is not a system admin.
- Validation as in `complete_my_player_profile`.
- Avatar is displayed only. No avatar removal.
- No service role anywhere. Existing Flutter feature/repository/adapter pattern. Targeted tests only.

Two details to confirm:

- `before`/`after` will contain phone number and date of birth. Criterion 8 says "without sensitive data". Should values be stored, or only the names of changed fields?
- Reason is optional in Phase 1 and mandatory in Phase 2. Correct?

## 9. Observations outside this task (not acted on)

- The guidelines cite `Docs/12-Testing.md`, `GAP-4` for the shared database; a search of that file did not find `GAP-4`.
- Five trigger functions remain executable by `PUBLIC` on live (`set_updated_at`, `assign_admin_order_on_insert`, `enforce_roster_order_mode_lock`, `reject_rating_archive_delete`, `reject_rating_archive_update`). Trigger functions cannot be called directly, so this looks harmless.

## Architect ruling (2026-10-06)

1. **Baseline accepted for Phase 1.** "Live schema at `0094` equals the repository end state", within the limits of section 5, is the trusted baseline for the next append-only migration. A full replay-and-diff is not required now. This is not a statement that the two histories are identical.
2. **History is left untouched.** No historical migration is renamed, edited, or added. New work starts after `0094`.
3. **Apply discipline.** A new migration is applied verbatim from the committed file. Success is judged by the resulting database state (functions, signatures, grants, constraints, permissions, tested behaviour), not by the migration record alone.
4. **Phase 1 on the shared database.** There is no separate staging database. A Phase 1 migration is applied to the shared database only after Architect review and Product Owner approval, then verified in a controlled way against a designated test account, then checked through the staging front end.
5. **Phase 2** (Auth administration) is outside this record. Its testing strategy is unresolved, and this record does not authorize testing or deploying Phase 2 against the shared production database.
6. **Audit metadata for Phase 1** holds `changed_fields` only. No before or after values are stored.
7. **Reason** is optional in Phase 1.
