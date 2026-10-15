# Database and Platform Catalog

> **Generated file. Do not edit by hand.** Regenerate it with `node tool/check-docs.mjs --write`;
> `node tool/check-docs.mjs` fails when it is out of date.

Source of truth: the 107 files in `supabase/migrations/`, newest `0106`.

This is an **index** of what exists and which migration made it, not a specification. Behaviour is described
in each migration's header comment, in the table specifications under `Docs/engineering/`, and in
`Docs/10-Design-Decisions.md`.

*Introduced* is the first migration that created the object; *Last changed* is the latest one that replaced or altered it.
*Purpose* is the first sentence of the object's `COMMENT ON` when its migration wrote one, and empty otherwise.

## Tables (39)

| Table | Introduced | Last changed | Specification | Purpose |
|---|---|---|---|---|
| `account_merge_map` | `0101` | `0101` |  | Account merge (0101): the retired source UUID and the retained UUID it was |
| `admin_audit_log` | `0062` | `0103` |  | Platform Admin administrative audit trail (migration 0062). |
| `app_settings` | `0006` | `0097` |  |  |
| `btge_generation_runs` | `0089` | `0089` |  | Wave 3 (migration 0089): one immutable row per successful BTGE generated |
| `client_runtime_events` | `0090` | `0090` |  | Wave 4 (migration 0090): append-only production client runtime evidence -- |
| `communities` | `0002` | `0094` | [Communities](Communities_Table_Specification.md) |  |
| `community_members` | `0002` | `0007` | [Community_Members](Community_Members_Table_Specification.md) |  |
| `community_membership_events` | `0088` | `0088` |  | Wave 2 append-only membership lifecycle evidence. |
| `community_statistics` | `0028` | `0028` | [Community_Statistics](Community_Statistics_Table_Specification.md) | Level 2: one player's six counters, in one community, over one period. |
| `governorates` | `0094` | `0094` |  | The 11 governorates of Oman, keyed by the Ministry of Interior Region Code. |
| `match_goals` | `0022` | `0022` | [Match_Goals](Match_Goals_Table_Specification.md) |  |
| `match_participation_state` | `0088` | `0088` |  | Wave 2 mutable confirmation state for the authoritative lineup revision; participants remain in match_team_assignments. |
| `match_professional_guests` | `0044` | `0044` |  | A match-scoped temporary participant with no account, no membership, no |
| `match_registration_events` | `0088` | `0088` |  | Wave 2 append-only account registration lifecycle evidence. |
| `match_registrations` | `0004` | `0053` | [Match_Registrations](Match_Registrations_Table_Specification.md) |  |
| `match_result_reminder_activation` | `0100` | `0100` |  |  |
| `match_result_reminder_dispatches` | `0100` | `0100` |  |  |
| `match_results` | `0022` | `0044` | [Match_Results](Match_Results_Table_Specification.md) |  |
| `match_team_assignments` | `0018` | `0058` | [Match_Team_Assignments](Match_Team_Assignments_Table_Specification.md) |  |
| `matches` | `0003` | `0054` | [Matches](Matches_Table_Specification.md) |  |
| `notification_push_preferences` | `0036` | `0036` |  |  |
| `notification_push_tokens` | `0036` | `0038` |  |  |
| `notification_types` | `0036` | `0036` |  |  |
| `notifications` | `0006` | `0006` | [Notifications](Notifications_Table_Specification.md) |  |
| `player_statistics` | `0022` | `0022` | [Player_Statistics](Player_Statistics_Table_Specification.md) |  |
| `product_activity_last_seen` | `0091` | `0091` |  | Migration 0091: the newest product_events.created_at per account among |
| `product_events` | `0067` | `0091` |  | Product analytics (migration 0067). |
| `push_config` | `0036` | `0036` |  |  |
| `push_dispatch_outcomes` | `0090` | `0090` |  | Wave 4 (migration 0090): append-only push transport evidence, one row per |
| `rating_history` | `0022` | `0073` | [Rating_History](Rating_History_Table_Specification.md) |  |
| `rating_history_archive` | `0082` | `0082` |  | The operational rating_history as it stood before a rebase, row for row and |
| `rating_rebase_runs` | `0082` | `0082` |  | One row per historical rating rebase: the marker that makes it one-time, |
| `system_admins` | `0017` | `0017` |  |  |
| `team_of_period_awards` | `0079` | `0079` |  | The players a stored Team of Period snapshot selected, one row each. |
| `team_of_period_snapshots` | `0079` | `0079` |  | One stored Team of Period evaluation per community and closed period, |
| `telemetry_ingest_windows` | `0090` | `0090` |  | Wave 4 (migration 0090): per-channel accepted counts per minute for the |
| `user_rating_archive` | `0082` | `0082` |  | Every user's Global Rating as it stood before a rebase -- what a rollback |
| `users` | `0001` | `0102` | [Profiles](Profiles_Table_Specification.md) |  |
| `wilayats` | `0094` | `0094` |  | The 63 wilayats of Oman, keyed by the Ministry of Interior Wilayat Code (Sohar = 7). |

### Specified, but no such table exists after all migrations

A table specification exists for each of these, and no migration leaves a table of that name behind.
Treat the specification as the design as approved, not as the schema; the migration headers say what was built instead.

- `community_invitations` — [Community_Invitations_Table_Specification.md](Community_Invitations_Table_Specification.md)
- `community_rating_history` — [Community_Rating_History_Table_Specification.md](Community_Rating_History_Table_Specification.md)
- `community_ratings` — [Community_Rating_Table_Specification.md](Community_Rating_Table_Specification.md)

## Views (16)

| View | Introduced | Last changed | Purpose |
|---|---|---|---|
| `v_community_members` | `0025` | `0073` | Read model: community roster -- membership joined to the member profile. |
| `v_community_summary` | `0025` | `0025` | Read model: one row per community with member and match counts. |
| `v_completed_matches` | `0037` | `0037` | Read model: matches that are completed under 0029's rule — status is |
| `v_football_community_player_stats` | `0057` | `0105` | Cycle 2 read model: one row per current member with an all-time record in a |
| `v_football_community_stats` | `0057` | `0057` | Cycle 2 read model: a community's football record -- completed matches, |
| `v_football_completed_matches` | `0057` | `0057` | Cycle 2 read model: one row per completed match in an active community, with |
| `v_football_match_lineup` | `0057` | `0073` | Cycle 2 read model: the stored lineup of a completed match -- side, assigned |
| `v_football_match_participants` | `0057` | `0073` | Cycle 2 read model: the roster of a completed match, confirmed and reserve, |
| `v_match_details` | `0025` | `0025` | Read model: a match with its community, organizer, registration counts and |
| `v_match_registrations` | `0025` | `0073` | Read model: match registrations (confirmed and reserve) for both kinds of |
| `v_match_teams` | `0025` | `0073` | Read model: the played lineup for both kinds of participant -- team, |
| `v_player_statistics` | `0025` | `0073` | Read model: one row per active user -- profile, Global Rating and career |
| `v_public_communities` | `0033` | `0094` | Public community discovery. |
| `v_public_upcoming_matches` | `0033` | `0094` | Public read model: matches that have not ended, with remaining places and the |
| `v_upcoming_matches` | `0025` | `0025` | Read model: matches starting after now() that are not completed, with |
| `v_user_profile` | `0025` | `0073` | Read model: a player identity joined to the global career counters in |

## Functions (195)

RPCs, helpers and trigger functions in the `public` schema, by name. Overloads are counted once.

| Function | Introduced | Last changed | Purpose |
|---|---|---|---|
| `account_deletion_blockers` | `0102` | `0102` | Account deletion (0102), INTERNAL: TARGET_IS_SYSTEM_ADMIN and OWNS_COMMUNITIES, the two things that |
| `account_football_evidence` | `0102` | `0102` | Account deletion (0102), INTERNAL: the football record of one account as counts and hashes, |
| `activate_manual_roster_order` | `0053` | `0053` |  |
| `add_played_professional_guest` | `0075` | `0075` | Records that a Professional Guest played a COMPLETED match: the guest, a |
| `add_professional_guest` | `0047` | `0065` |  |
| `admin_add_player_to_match` | `0041` | `0065` |  |
| `admin_analytics_communities` | `0069` | `0069` | Platform Admin: the communities behind Weekly Active Communities (migration |
| `admin_analytics_communities_v2` | `0087` | `0087` |  |
| `admin_analytics_matches` | `0069` | `0069` | Platform Admin: the matches behind Matches 7d/30d and Results 7d/30d |
| `admin_analytics_matches_v2` | `0087` | `0087` |  |
| `admin_analytics_overview` | `0067` | `0067` | Platform Admin: the Overview dashboard, one row, one call (migration 0067). |
| `admin_analytics_overview_v2` | `0085` | `0085` | Wave 1 additive Platform Admin read model. |
| `admin_analytics_registrations` | `0069` | `0069` | Platform Admin: the individual match_registered events behind Registrations |
| `admin_analytics_registrations_v2` | `0087` | `0087` |  |
| `admin_analytics_users` | `0069` | `0069` | Platform Admin: the people behind eight Overview figures (migration 0069). |
| `admin_analytics_users_v2` | `0087` | `0091` |  |
| `admin_check_user_auth_action` | `0103` | `0103` | Admin authentication management (0103): whether the signed-in System Admin may CHANGE_EMAIL, |
| `admin_delete_account` | `0102` | `0102` | Platform Admin: permanently deletes one account (Auth user, profile data, personal records) and |
| `admin_delete_community` | `0017` | `0017` |  |
| `admin_delete_match` | `0017` | `0017` |  |
| `admin_delete_user` | `0017` | `0017` |  |
| `admin_get_community_inspection` | `0069` | `0069` | Platform Admin: one community, read only (migration 0069). |
| `admin_get_match_inspection` | `0069` | `0069` | Platform Admin: one match, read only (migration 0069). |
| `admin_get_user_account` | `0095` | `0095` | Platform Admin: one account's data and settings -- profile, privacy, |
| `admin_list_audit_log` | `0068` | `0068` | Platform Admin: the administrative audit trail, newest first (migration |
| `admin_list_communities` | `0017` | `0066` | Platform Admin: communities, searchable by name, newest first, capped at |
| `admin_list_matches` | `0017` | `0017` |  |
| `admin_list_users` | `0017` | `0066` | Platform Admin: accounts, searchable by name or email, newest first, capped |
| `admin_merge_accounts` | `0101` | `0102` | Platform Admin: folds a source account into a retained one and removes the |
| `admin_preview_account_deletion` | `0096` | `0102` | Platform Admin: what deleting one account would do. |
| `admin_preview_account_merge` | `0096` | `0101` | Platform Admin, READ ONLY: what merging a source account into a retained one |
| `admin_preview_account_snapshot` | `0096` | `0096` | Platform Admin, INTERNAL: one account's identity (name, e-mail, state, |
| `admin_reactivate_community` | `0065` | `0065` | Platform Admin: restores a community by setting communities.is_active true |
| `admin_reactivate_user` | `0064` | `0064` | Platform Admin: restores an account by setting users.is_active true and |
| `admin_record_user_email_changed` | `0103` | `0103` | Admin authentication management (0103): records USER_EMAIL_CHANGED for p_user_id, attributed to |
| `admin_record_user_password_set` | `0103` | `0103` | Admin authentication management (0103): records USER_PASSWORD_SET for p_user_id, attributed to |
| `admin_record_user_recovery_sent` | `0103` | `0103` | Admin authentication management (0103): records USER_RECOVERY_SENT for p_user_id, attributed to |
| `admin_set_support_whatsapp_phone` | `0097` | `0097` |  |
| `admin_suspend_community` | `0065` | `0065` | Platform Admin: suspends a community by setting communities.is_active false |
| `admin_suspend_user` | `0064` | `0064` | Platform Admin: suspends an account by setting users.is_active false and |
| `admin_update_user_account` | `0095` | `0095` | Platform Admin: sets an account's full name and phone as one group. |
| `admin_update_user_default_wilayat` | `0095` | `0095` | Platform Admin: sets or clears (null) an account's Default Location. |
| `admin_update_user_player_profile` | `0095` | `0095` | Platform Admin: sets an account's date of birth and primary and secondary |
| `admin_update_user_privacy` | `0095` | `0095` | Platform Admin: sets an account's profile visibility (EVERYONE or |
| `admin_update_user_push_preferences` | `0095` | `0095` | Platform Admin: sets an account's three push switches as one group; a null |
| `admin_user_activity_summary` | `0068` | `0091` | Platform Admin: one account in figures (migrations 0068, 0091). |
| `admin_user_activity_timeline` | `0068` | `0091` | Platform Admin: one account's recent activity, newest first (migrations |
| `admin_user_auth_guard` | `0103` | `0103` | Admin authentication management (0103), INTERNAL: the gate shared by the check and the audit |
| `advance_match_participation_revision` | `0088` | `0101` |  |
| `anonymize_user_profile` | `0102` | `0102` | Account deletion (0102), INTERNAL: turns a live profile into the anonymised stand-in. |
| `apply_community_statistics` | `0028` | `0028` |  |
| `apply_match_rating_effects` | `0022` | `0078` |  |
| `apply_match_statistics` | `0022` | `0028` |  |
| `apply_rating_delta` | `0022` | `0101` |  |
| `assert_result_survives_lineup` | `0029` | `0044` |  |
| `assign_admin_order_on_insert` | `0053` | `0053` |  |
| `assign_professional_guest_teams` | `0050` | `0058` |  |
| `attach_match_effects` | `0029` | `0029` |  |
| `capture_community_membership_event` | `0088` | `0101` |  |
| `capture_match_registration_event` | `0088` | `0101` |  |
| `community_insights_v1` | `0085` | `0085` | Wave 1 organizer-only rolling-30-day Community Intelligence. |
| `community_join_code` | `0055` | `0055` | The community join code, to an owner or admin and to nobody else. |
| `community_logo_folder` | `0061` | `0061` | The community uuid a community-logos object path is scoped by, or null when |
| `community_period_xi_closed_evidence` | `0079` | `0084` | The candidate rows for the period that has CLOSED -- the last closed |
| `community_period_xi_closed_window` | `0079` | `0084` | Team of Period evidence for the period that has CLOSED -- the last closed |
| `community_period_xi_evidence` | `0070` | `0079` | Team of the Week / Team of the Month candidates: one row per real player |
| `community_period_xi_evidence_in` | `0079` | `0079` |  |
| `community_period_xi_matches` | `0070` | `0079` | The matches a Team of Period award is decided from: this community, inside |
| `community_period_xi_matches_between` | `0084` | `0084` | The matches a Team of Period award is decided from, by canonical bounds: |
| `community_period_xi_matches_in` | `0079` | `0084` |  |
| `community_period_xi_window` | `0070` | `0079` | Team of Period, the period itself: exactly one row naming the CURRENT ISO |
| `community_period_xi_window_in` | `0079` | `0079` |  |
| `community_scoped_rating` | `0081` | `0081` | The Community/Period Rating: one rating per player, from 5.000, over the |
| `community_statistics_recency` | `0060` | `0060` | Per-player timestamps of the most recent goal, MVP, played match and win in |
| `complete_my_player_profile` | `0092` | `0092` | Creates the signed-in caller's player profile when none exists. |
| `confirm_match_participation` | `0088` | `0088` | Wave 2 organizer confirmation that the current completed lineup is the factual participation record. |
| `consume_telemetry_budget_v1` | `0090` | `0090` | Wave 4 (migration 0090): consumes one unit of a public telemetry channel's |
| `correct_completed_match_players` | `0074` | `0074` | Corrects several community players of a COMPLETED match in one atomic |
| `create_community` | `0007` | `0094` | Creates a community with the caller as owner. |
| `create_community_statistics_on_join` | `0028` | `0028` |  |
| `create_match` | `0026` | `0091` | Creates a match in a community the caller owns or administers and returns |
| `create_notification` | `0006` | `0006` |  |
| `current_statistics_week_at` | `0077` | `0077` | The ISO week (Monday to Sunday, Asia/Muscat) containing p_at, as |
| `delete_account_core` | `0102` | `0102` | Account deletion (0102), INTERNAL: removes personal data and the Auth user, keeps the football |
| `delete_community` | `0009` | `0065` |  |
| `delete_match` | `0006` | `0065` |  |
| `delete_my_account` | `0102` | `0102` | Account deletion (0102): the signed-in user permanently deletes their own account. |
| `deleted_player_name` | `0102` | `0102` | Account deletion (0102): the name shown for a deleted player, in both languages. |
| `detach_match_effects` | `0029` | `0029` |  |
| `dispatch_push_notification` | `0036` | `0036` |  |
| `emit_missing_match_result_reminders_v1` | `0100` | `0100` |  |
| `enforce_roster_order_mode_lock` | `0053` | `0053` |  |
| `generate_join_code` | `0012` | `0030` |  |
| `get_my_account_state` | `0092` | `0092` | The signed-in caller's account state: ACTIVE, SUSPENDED or |
| `handle_auth_user_deleted` | `0102` | `0102` | Account deletion (0102), INTERNAL: anonymises the profile of an Auth user deleted by any other route. |
| `handle_new_user` | `0001` | `0092` |  |
| `has_active_community_role` | `0062` | `0062` | Whether an active user holds at least p_min_role in an active community. |
| `has_community_role` | `0008` | `0008` |  |
| `is_community_member` | `0007` | `0008` |  |
| `is_current_user_active` | `0062` | `0062` | Whether the signed-in caller has an active public.users row. |
| `is_match_community_admin` | `0018` | `0018` |  |
| `is_match_community_member` | `0007` | `0007` |  |
| `is_system_admin` | `0017` | `0098` |  |
| `join_community` | `0016` | `0065` |  |
| `join_community_by_code` | `0007` | `0065` |  |
| `last_completed_statistics_period` | `0070` | `0070` | The last COMPLETED ISO week or calendar month, in Asia/Muscat, as |
| `last_completed_team_of_period_week` | `0084` | `0084` | The last FULLY CLOSED Team of Period week: Sunday to Saturday, Asia/Muscat, |
| `leave_community` | `0104` | `0104` |  |
| `match_community_contribution` | `0028` | `0028` |  |
| `match_membership_context` | `0042` | `0042` | Why a match did not load: whether the id names one, which community it |
| `match_result_contribution` | `0023` | `0046` |  |
| `merge_invariants` | `0101` | `0101` | Account merge (0101), INTERNAL: fingerprints of what a merge must not change |
| `merge_participation_blockers` | `0101` | `0101` | Account merge (0101), INTERNAL: why one account's participation in one match |
| `merge_rating_scope_excludes` | `0101` | `0101` | Account merge (0101), INTERNAL: true only inside the merge transaction while one |
| `merge_shared_matches` | `0101` | `0101` | Account merge (0101), INTERNAL: the matches both accounts have participation |
| `merge_skips_lifecycle` | `0101` | `0101` | Account merge (0101), INTERNAL: true only inside the merge transaction, and only |
| `merge_source_stored_files` | `0101` | `0101` | Account merge (0101), INTERNAL: the names of the objects in the avatars bucket |
| `my_profile` | `0055` | `0094` | The signed-in player's own account row, phone and Default Location included. |
| `next_reserve_registration` | `0053` | `0053` |  |
| `period_form_score_v1` | `0070` | `0070` | Period Form Score v1: one player's form contribution from one match. |
| `period_goal_form_v1` | `0070` | `0070` | Period Form v1: what one player's goals in one match are worth -- 0.02 |
| `period_xi_required_matches` | `0070` | `0072` | How many qualifying matches a Team of Period candidate must have played: 0 |
| `player_profile` | `0043` | `0063` | One player's football profile: identity, playing positions, picture, |
| `player_rating_trend_v1` (2 overloads) | `0085` | `0086` | Wave 1 target-aware rating trend. |
| `player_recent_achievements` | `0081` | `0084` | A player's recent achievements: their latest MVP, and every stored Team of |
| `player_recent_form` | `0079` | `0080` | One player's last N completed matches, newest first, as outcome, goals, |
| `player_recent_highlights` | `0079` | `0080` | A player's highlight candidates for a signed-in reader: at most one MVP |
| `player_statistics_evidence` | `0032` | `0046` |  |
| `preview_community_invite` | `0012` | `0061` | What a shared invitation offers, readable without a session. |
| `preview_my_account_deletion` | `0102` | `0102` | Account deletion (0102): whether anything blocks the signed-in user deleting their own account, |
| `public_community_football_record` | `0093` | `0093` | The public football record of one active community: completed matches, |
| `public_community_recent_results` | `0081` | `0081` | One active community's most recent completed results, in the same public |
| `public_community_top_players` | `0093` | `0105` | The Top 11 players of one active community, for the public community page: |
| `public_match_detail` | `0079` | `0079` | One match for the /match/{id} link, upcoming or completed, in an active |
| `public_match_lineup` | `0079` | `0079` | The lineup of a completed match in an active community, for the /match/{id} |
| `public_player_profile` | `0079` | `0079` | The public Player Profile a /player/{id} link opens: name, positions, |
| `public_player_recent_achievements` | `0081` | `0081` | The public Recent Achievements: kind, date, community name and period, for |
| `public_player_recent_form` | `0079` | `0080` | The public Recent Form: the last N results newest first, as sequence_no, |
| `public_player_recent_highlight` | `0079` | `0080` | The public Recent Highlight candidates: at most one MVP and one stored Team |
| `public_recent_results` | `0081` | `0081` | The most recent completed matches with a recorded result, across every |
| `purge_community` | `0017` | `0017` |  |
| `purge_match` | `0017` | `0045` |  |
| `purge_membership` | `0017` | `0104` |  |
| `push_dispatch_payload` | `0036` | `0036` |  |
| `rebalance_roster` | `0006` | `0053` |  |
| `rebase_ratings_to_0078` | `0082` | `0082` | The approved one-time rebase: archives the operational rating history and |
| `rebuild_community_statistics` | `0028` | `0028` |  |
| `rebuild_player_statistics` | `0032` | `0032` |  |
| `recompute_match_status` | `0006` | `0050` |  |
| `reconcile_community_statistics` | `0028` | `0028` | CS-C17 / DP-11: three checks over community_statistics — stored vs evidence, |
| `reconcile_match_lineup` | `0050` | `0058` |  |
| `record_admin_audit` | `0062` | `0062` | Writes one row to admin_audit_log. |
| `record_anonymous_public_link_open` | `0089` | `0090` | Wave 3 (migration 0089), budgeted by Wave 4 (0090): records one anonymous |
| `record_match_result` | `0022` | `0074` | Records or corrects the final result of a COMPLETED match: refused with |
| `record_product_event` | `0067` | `0091` | The authenticated writer for product_events (migrations 0067, 0079, 0091). |
| `record_public_link_signup_completed` | `0089` | `0089` | Wave 3 (migration 0089): records public_link_signup_completed for the |
| `record_push_dispatch_outcome_v1` | `0090` | `0090` | Wave 4 (migration 0090): appends one push_dispatch_outcomes row for a |
| `record_team_of_period_snapshot` | `0079` | `0084` | The only writer of Team of Period snapshots. |
| `regenerate_join_code` | `0015` | `0065` |  |
| `register_for_match` | `0004` | `0065` |  |
| `register_player_in_match` | `0041` | `0091` |  |
| `register_push_token` | `0036` | `0064` |  |
| `reject_rating_archive_delete` | `0082` | `0083` |  |
| `reject_rating_archive_update` | `0082` | `0083` |  |
| `reject_rating_history_update` | `0022` | `0024` |  |
| `remove_member` | `0009` | `0065` |  |
| `remove_played_professional_guest` | `0059` | `0065` |  |
| `remove_player` | `0006` | `0065` |  |
| `remove_professional_guest` | `0047` | `0065` |  |
| `rename_professional_guest` | `0047` | `0065` |  |
| `replace_match_lineup` | `0020` | `0071` | Replaces a match lineup atomically. |
| `report_client_error_v1` | `0090` | `0090` | Wave 4 (migration 0090): records one uncaught client error against an |
| `reverse_match_effects_before_delete` | `0022` | `0022` |  |
| `reverse_match_rating_effects` | `0022` | `0022` |  |
| `run_retention_cleanup_v1` | `0091` | `0091` | Migration 0091: internal retention cleanup. |
| `save_generated_lineup_v1` | `0089` | `0089` | Wave 3 (migration 0089): saves a BTGE-generated account lineup through |
| `set_community_logo` | `0061` | `0065` | Sets or clears a community's logo_url, for an owner or an admin and nobody |
| `set_community_wilayat` | `0094` | `0094` | Owner only: moves a community to another active wilayat. |
| `set_completed_match_player` | `0029` | `0065` |  |
| `set_match_capacity` | `0006` | `0006` |  |
| `set_match_roster_order` | `0053` | `0065` |  |
| `set_member_role` | `0008` | `0065` |  |
| `set_updated_at` | `0001` | `0005` |  |
| `shares_active_community` | `0043` | `0043` | Whether two players are both in the same active community -- the predicate |
| `start_client_runtime_v1` | `0090` | `0090` | Wave 4 (migration 0090): records one run_started for a production client |
| `statistics_period_key` | `0028` | `0028` |  |
| `statistics_period_zone` | `0028` | `0028` | A1: the time zone every statistics period is derived in. |
| `swap_match_participants` | `0053` | `0065` |  |
| `team_of_period_period_bounds` | `0084` | `0084` | The canonical half-open bounds of a Team of Period period named by its key. |
| `team_of_period_statistics_period` | `0077` | `0084` | The period a Team of Period award describes: for weekly, the last CLOSED |
| `team_of_period_week_at` | `0084` | `0084` | The Team of Period football week containing p_at: Sunday 00:00 Asia/Muscat |
| `team_of_period_week_of_key` | `0084` | `0084` | The canonical Sunday-to-Saturday Team of Period week a YYYY-W## key names -- |
| `transfer_ownership` | `0009` | `0065` |  |
| `update_match` | `0006` | `0091` | Owner/admin match administration in every lifecycle state (migrations |
| `withdraw_from_match` | `0004` | `0065` |  |

## Edge Functions (4)

| Function | Purpose | README |
|---|---|---|
| `admin-merge-accounts` | The one request the System Admin console makes to merge two accounts for good. | [README](../../supabase/functions/admin-merge-accounts/README.md) |
| `admin-user-auth` | The one request the System Admin console makes to change another account's sign-in. | [README](../../supabase/functions/admin-user-auth/README.md) |
| `delete-account` | The one request both deletion entry points make: a System Admin deleting a user ({ "p_user_id": "&lt;uuid&gt;" }) and a signed-in user deleting their own account ({}). | [README](../../supabase/functions/delete-account/README.md) |
| `push-dispatch` | Delivers a notification as a Firebase push. | [README](../../supabase/functions/push-dispatch/README.md) |

## Cloudflare Pages Functions (1)

| Route | File |
|---|---|
| `/share/match/:id` | `functions/share/match/[id].js` |

## GitHub Actions workflows (4)

| Workflow | Name | Triggers |
|---|---|---|
| `.github/workflows/deploy-staging.yml` | Deploy staging web app to Cloudflare Pages | workflow_dispatch |
| `.github/workflows/deploy-web.yml` | Deploy web app to Cloudflare Pages | push, workflow_dispatch |
| `.github/workflows/docs-sync.yml` | Docs sync check | pull_request |
| `.github/workflows/team-of-period-snapshot.yml` | Team of Period snapshot | workflow_dispatch |
