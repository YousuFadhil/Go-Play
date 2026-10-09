import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/football_components.dart'
    show GoChipTone, GoStatusChip;
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_deletion_preview_screen.dart';
import 'package:go_play/features/admin/admin_merge_preview_screen.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_user_detail_screen.dart';
import 'package:go_play/features/locations/wilayat_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';

import 'admin_fakes.dart';
import 'wilayat_fixtures.dart';

/// The read-only merge and deletion previews (migration 0096).
///
/// The documents below are not hand-written. They are what the two
/// preview functions returned in the offline run of the migration (PGlite, with
/// a seeded conflicting pair of accounts), with only the timestamps replaced, so
/// the mapper and the screens are tested against the shape the database really
/// produces. "Conflicting" is a retained account and a source that share
/// communities, matches and statistics; "blocked" is the source seen for
/// deletion; "empty" is two accounts with nothing in the database naming them.
/// "System admins" has a System Admin on both sides of a merge; "archive only"
/// is an account that nothing but the immutable rating archives names; "clean
/// source" has conflicts to resolve but no blocker of any kind; "history only" is
/// an account that nothing but football history (a registration, a rating
/// entry, a statistics row) names.
const _mergeConflicting =
    r'''{"limit":25,"source":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":1,"goals_total":0,"memberships":4,"push_tokens":1,"audit_entries":1,"notifications":2,"registrations":2,"matches_played":3,"product_events":2,"rating_entries":2,"created_matches":2,"generation_runs":0,"push_preferences":1,"recorded_results":1,"confirmed_lineups":0,"membership_events":1,"memberships_admin":1,"memberships_owner":2,"owned_communities":2,"lineup_assignments":2,"rating_archive_rows":3,"registration_events":1,"team_of_period_awards":2,"player_statistics_rows":1,"upcoming_registrations":1,"user_rating_archive_rows":1,"community_statistics_rows":2,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000002","email":"p2@x.com","full_name":"Source Player","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.617+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.617+04:00","sign_in_providers":["email","google"]}},"version":1,"findings":[{"code":"OWNERSHIP_CONFLICT","count":1,"category":"OWNERSHIP","severity":"BLOCKER"},{"code":"RATING_ARCHIVE_IMMUTABLE","count":4,"category":"ARCHIVE","severity":"BLOCKER"},{"code":"SHARED_MATCH_COLLISION","count":1,"category":"MATCH","severity":"BLOCKER"},{"code":"COMMUNITY_STATISTICS_COLLISION","count":1,"category":"STATISTICS","severity":"CONFLICT"},{"code":"PLAYER_STATISTICS_RECOMPUTE","count":3,"category":"STATISTICS","severity":"CONFLICT"},{"code":"RATING_REPLAY_REQUIRED","count":2,"category":"RATING","severity":"CONFLICT"},{"code":"ROLE_CONFLICT","count":2,"category":"ROLE","severity":"CONFLICT"},{"code":"SHARED_MATCH_PARTICIPATION","count":2,"category":"MATCH","severity":"CONFLICT"},{"code":"SOURCE_CREATED_MATCHES","count":2,"category":"MATCH","severity":"CONFLICT"},{"code":"SOURCE_OWNS_COMMUNITIES","count":1,"category":"OWNERSHIP","severity":"CONFLICT"},{"code":"TEAM_AWARD_COLLISION","count":1,"category":"STATISTICS","severity":"CONFLICT"},{"code":"AUDIT_LOG_NAMES_SOURCE","count":1,"category":"AUDIT","severity":"CONSTRAINT"},{"code":"EVENT_LOGS_NAME_SOURCE","count":4,"category":"HISTORY","severity":"CONSTRAINT"}],"retained":{"counts":{"rating":5,"goal_rows":2,"mvp_awards":0,"goals_total":3,"memberships":3,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":3,"matches_played":5,"product_events":0,"rating_entries":1,"created_matches":2,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":1,"owned_communities":1,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":1,"player_statistics_rows":1,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":1,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000001","email":"p1@x.com","full_name":"Retained Player","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.616+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.616+04:00","sign_in_providers":["email"]}},"has_blockers":true,"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"shared_matches":{"items":[{"title":"Match One","status":"completed","match_id":"00000000-0000-0000-0000-000000000513","start_at":"2026-10-09T20:29:48.624+04:00","collision":true,"is_historical":false,"community_name":"Alpha","source_evidence":["LINEUP","RATING","REGISTRATION"],"retained_evidence":["GOALS","RATING","REGISTRATION"]},{"title":"Match Two","status":"completed","match_id":"00000000-0000-0000-0000-000000000514","start_at":"2026-10-09T20:29:48.624+04:00","collision":false,"is_historical":false,"community_name":"Beta","source_evidence":["LINEUP"],"retained_evidence":["REGISTRATION"]},{"title":"Match Three","status":"completed","match_id":"00000000-0000-0000-0000-000000000515","start_at":"2026-10-09T20:29:48.624+04:00","collision":false,"is_historical":false,"community_name":"Alpha","source_evidence":["MVP","RATING"],"retained_evidence":["GOALS"]}],"total":3,"by_kind":{"goals":0,"lineup":0,"rating":1,"registration":1},"colliding_total":1},"statistics_overlap":{"team_award_collisions":1,"community_statistics_collisions":1},"overlapping_communities":{"items":[{"name":"Alpha","source_owns":true,"source_role":"owner","community_id":"00000000-0000-0000-0000-000000000257","retained_owns":false,"retained_role":"player","role_conflict":true},{"name":"Beta","source_owns":false,"source_role":"admin","community_id":"00000000-0000-0000-0000-000000000258","retained_owns":true,"retained_role":"owner","role_conflict":true},{"name":"Delta","source_owns":false,"source_role":"player","community_id":"00000000-0000-0000-0000-000000000260","retained_owns":false,"retained_role":"player","role_conflict":false}],"total":3,"role_conflicts_total":2,"ownership_conflicts_total":1},"source_owned_communities":{"items":[{"name":"Alpha","community_id":"00000000-0000-0000-0000-000000000257","retained_role":"player","retained_is_member":true},{"name":"Gamma","community_id":"00000000-0000-0000-0000-000000000259","retained_role":null,"retained_is_member":false}],"total":2}}''';
const _mergeEmpty =
    r'''{"limit":25,"source":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000004","email":"e2@x.com","full_name":"Empty Two","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.619+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.619+04:00","sign_in_providers":[]}},"version":1,"findings":[],"retained":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000003","email":"e1@x.com","full_name":"Empty One","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.618+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.618+04:00","sign_in_providers":[]}},"has_blockers":false,"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"shared_matches":{"items":[],"total":0,"by_kind":{"goals":0,"lineup":0,"rating":0,"registration":0},"colliding_total":0},"statistics_overlap":{"team_award_collisions":0,"community_statistics_collisions":0},"overlapping_communities":{"items":[],"total":0,"role_conflicts_total":0,"ownership_conflicts_total":0},"source_owned_communities":{"items":[],"total":0}}''';
const _deletionBlocked =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":1,"goals_total":0,"memberships":4,"push_tokens":1,"audit_entries":1,"notifications":2,"registrations":2,"matches_played":3,"product_events":2,"rating_entries":2,"created_matches":2,"generation_runs":0,"push_preferences":1,"recorded_results":1,"confirmed_lineups":0,"membership_events":1,"memberships_admin":1,"memberships_owner":2,"owned_communities":2,"lineup_assignments":2,"rating_archive_rows":3,"registration_events":1,"team_of_period_awards":2,"player_statistics_rows":1,"upcoming_registrations":1,"user_rating_archive_rows":1,"community_statistics_rows":2,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000002","email":"p2@x.com","full_name":"Source Player","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.617+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.617+04:00","sign_in_providers":["email","google"]}},"version":1,"findings":[{"code":"CREATED_MATCHES","count":2,"category":"MATCH","severity":"BLOCKER"},{"code":"HISTORY_WOULD_CASCADE","count":13,"category":"HISTORY","severity":"BLOCKER"},{"code":"MVP_RESULTS_WOULD_CASCADE","count":1,"category":"MATCH","severity":"BLOCKER"},{"code":"OWNS_COMMUNITIES","count":2,"category":"OWNERSHIP","severity":"BLOCKER"},{"code":"RATING_ARCHIVE_IMMUTABLE","count":4,"category":"ARCHIVE","severity":"BLOCKER"},{"code":"UPCOMING_REGISTRATIONS","count":1,"category":"MATCH","severity":"CONFLICT"},{"code":"AUDIT_LOG_APPEND_ONLY","count":1,"category":"AUDIT","severity":"CONSTRAINT"},{"code":"EVENT_LOGS_NAME_ACCOUNT","count":2,"category":"HISTORY","severity":"CONSTRAINT"},{"code":"RATING_HISTORY_IMMUTABLE","count":2,"category":"HISTORY","severity":"CONSTRAINT"}],"has_blockers":true,"personal_data":[{"code":"ACTIVITY_EVENTS","records":2},{"code":"AVATAR","records":1},{"code":"DATE_OF_BIRTH","records":1},{"code":"DEFAULT_LOCATION","records":1},{"code":"EMAIL_ADDRESS","records":1},{"code":"NOTIFICATIONS","records":2},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1},{"code":"PUSH_PREFERENCES","records":1},{"code":"PUSH_TOKENS","records":1},{"code":"SIGN_IN_IDENTITIES","records":2}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[{"title":"Match One","status":"completed","match_id":"00000000-0000-0000-0000-000000000513","start_at":"2026-10-09T20:29:48.624+04:00","has_result":false,"is_historical":false,"community_name":"Alpha"},{"title":"Match Three","status":"completed","match_id":"00000000-0000-0000-0000-000000000515","start_at":"2026-10-09T20:29:48.624+04:00","has_result":true,"is_historical":false,"community_name":"Alpha"}],"total":2,"by_status":{"completed":2}},"owned_communities":{"items":[{"name":"Alpha","is_active":true,"match_count":2,"community_id":"00000000-0000-0000-0000-000000000257","member_count":2,"other_admin_count":0},{"name":"Gamma","is_active":true,"match_count":0,"community_id":"00000000-0000-0000-0000-000000000259","member_count":1,"other_admin_count":0}],"total":2},"preserved_records":[{"code":"ADMIN_AUDIT_LOG","records":1},{"code":"RATING_HISTORY_ARCHIVE","records":3},{"code":"USER_RATING_ARCHIVE","records":1}],"historical_records":[{"code":"COMMUNITY_MEMBERSHIPS","records":4,"treatment":"CASCADE_DELETE"},{"code":"COMMUNITY_STATISTICS","records":2,"treatment":"CASCADE_DELETE"},{"code":"LINEUP_ASSIGNMENTS","records":2,"treatment":"CASCADE_DELETE"},{"code":"MATCH_REGISTRATIONS","records":2,"treatment":"CASCADE_DELETE"},{"code":"MVP_RESULTS","records":1,"treatment":"CASCADE_DELETE"},{"code":"PLAYER_STATISTICS","records":1,"treatment":"CASCADE_DELETE"},{"code":"RATING_HISTORY","records":2,"treatment":"CASCADE_DELETE"},{"code":"RECORDED_RESULTS","records":1,"treatment":"DETACH"},{"code":"ACTIVITY_EVENTS","records":2,"treatment":"RETAINED_ID"},{"code":"MEMBERSHIP_EVENTS","records":1,"treatment":"RETAINED_ID"},{"code":"REGISTRATION_EVENTS","records":1,"treatment":"RETAINED_ID"},{"code":"TEAM_OF_PERIOD_AWARDS","records":2,"treatment":"RETAINED_ID"}]}''';
const _deletionEmpty =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000003","email":"e1@x.com","full_name":"Empty One","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.618+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.618+04:00","sign_in_providers":[]}},"version":1,"findings":[],"has_blockers":false,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[]}''';
const _mergeSystemAdmins =
    r'''{"limit":25,"source":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":1,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":1,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000161","email":"admin@x.com","full_name":"Admin One","is_active":true,"is_caller":true,"created_at":"2026-10-09T20:29:48.609+04:00","is_system_admin":true,"last_sign_in_at":"2026-10-09T20:29:48.609+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"RETAINED_IS_SYSTEM_ADMIN","count":1,"category":"IDENTITY","severity":"BLOCKER"},{"code":"SOURCE_IS_CALLER","count":1,"category":"IDENTITY","severity":"BLOCKER"},{"code":"SOURCE_IS_SYSTEM_ADMIN","count":1,"category":"IDENTITY","severity":"BLOCKER"},{"code":"AUDIT_LOG_NAMES_SOURCE","count":1,"category":"AUDIT","severity":"CONSTRAINT"},{"code":"EVENT_LOGS_NAME_SOURCE","count":1,"category":"HISTORY","severity":"CONSTRAINT"}],"retained":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":1,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":1,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":1,"owned_communities":1,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000162","email":"admin2@x.com","full_name":"Admin Two","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.615+04:00","is_system_admin":true,"last_sign_in_at":"2026-10-09T20:29:48.615+04:00","sign_in_providers":[]}},"has_blockers":true,"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"shared_matches":{"items":[],"total":0,"by_kind":{"goals":0,"lineup":0,"rating":0,"registration":0},"colliding_total":0},"statistics_overlap":{"team_award_collisions":0,"community_statistics_collisions":0},"overlapping_communities":{"items":[],"total":0,"role_conflicts_total":0,"ownership_conflicts_total":0},"source_owned_communities":{"items":[],"total":0}}''';
const _mergeArchiveOnly =
    r'''{"limit":25,"source":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":2,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":1,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000007","email":"ao@x.com","full_name":"Archive Only","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.622+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.622+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"RATING_ARCHIVE_IMMUTABLE","count":3,"category":"ARCHIVE","severity":"BLOCKER"}],"retained":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000003","email":"e1@x.com","full_name":"Empty One","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.618+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.618+04:00","sign_in_providers":[]}},"has_blockers":true,"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"shared_matches":{"items":[],"total":0,"by_kind":{"goals":0,"lineup":0,"rating":0,"registration":0},"colliding_total":0},"statistics_overlap":{"team_award_collisions":0,"community_statistics_collisions":0},"overlapping_communities":{"items":[],"total":0,"role_conflicts_total":0,"ownership_conflicts_total":0},"source_owned_communities":{"items":[],"total":0}}''';
const _mergeCleanSource =
    r'''{"limit":25,"source":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":1,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":1,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000006","email":"cs@x.com","full_name":"Clean Source","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.621+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.621+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"RATING_REPLAY_REQUIRED","count":1,"category":"RATING","severity":"CONFLICT"},{"code":"SOURCE_OWNS_COMMUNITIES","count":1,"category":"OWNERSHIP","severity":"CONFLICT"}],"retained":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000003","email":"e1@x.com","full_name":"Empty One","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.618+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.618+04:00","sign_in_providers":[]}},"has_blockers":false,"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"shared_matches":{"items":[],"total":0,"by_kind":{"goals":0,"lineup":0,"rating":0,"registration":0},"colliding_total":0},"statistics_overlap":{"team_award_collisions":0,"community_statistics_collisions":0},"overlapping_communities":{"items":[],"total":0,"role_conflicts_total":0,"ownership_conflicts_total":0},"source_owned_communities":{"items":[{"name":"Epsilon","community_id":"00000000-0000-0000-0000-000000000261","retained_role":null,"retained_is_member":false}],"total":1}}''';
const _deletionArchiveOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":2,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":1,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000007","email":"ao@x.com","full_name":"Archive Only","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.622+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.622+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"RATING_ARCHIVE_IMMUTABLE","count":3,"category":"ARCHIVE","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[{"code":"RATING_HISTORY_ARCHIVE","records":2},{"code":"USER_RATING_ARCHIVE","records":1}],"historical_records":[]}''';
const _deletionSystemAdmin =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":1,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":1,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":1,"owned_communities":1,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000162","email":"admin2@x.com","full_name":"Admin Two","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.615+04:00","is_system_admin":true,"last_sign_in_at":"2026-10-09T20:29:48.615+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"CREATED_MATCHES","count":1,"category":"MATCH","severity":"BLOCKER"},{"code":"HISTORY_WOULD_CASCADE","count":1,"category":"HISTORY","severity":"BLOCKER"},{"code":"OWNS_COMMUNITIES","count":1,"category":"OWNERSHIP","severity":"BLOCKER"},{"code":"TARGET_IS_SYSTEM_ADMIN","count":1,"category":"IDENTITY","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[{"title":"Match Four","status":"open","match_id":"00000000-0000-0000-0000-000000000516","start_at":"2026-10-09T20:29:48.624+04:00","has_result":false,"is_historical":false,"community_name":"Delta"}],"total":1,"by_status":{"open":1}},"owned_communities":{"items":[{"name":"Delta","is_active":true,"match_count":1,"community_id":"00000000-0000-0000-0000-000000000260","member_count":3,"other_admin_count":0}],"total":1},"preserved_records":[],"historical_records":[{"code":"COMMUNITY_MEMBERSHIPS","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionHistoryOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":1,"matches_played":1,"product_events":1,"rating_entries":1,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":1,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000009","email":"ho@x.com","full_name":"History Only","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:29:48.623+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:29:48.623+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"HISTORY_WOULD_CASCADE","count":3,"category":"HISTORY","severity":"BLOCKER"},{"code":"RATING_HISTORY_IMMUTABLE","count":1,"category":"HISTORY","severity":"CONSTRAINT"}],"has_blockers":true,"personal_data":[{"code":"ACTIVITY_EVENTS","records":1},{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"MATCH_REGISTRATIONS","records":1,"treatment":"CASCADE_DELETE"},{"code":"PLAYER_STATISTICS","records":1,"treatment":"CASCADE_DELETE"},{"code":"RATING_HISTORY","records":1,"treatment":"CASCADE_DELETE"},{"code":"ACTIVITY_EVENTS","records":1,"treatment":"RETAINED_ID"}]}''';

Map<String, dynamic> _doc(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

AdminMergePreview _merge([String json = _mergeConflicting]) =>
    adminMergePreviewFromJson(_doc(json));

AdminDeletionPreview _deletion([String json = _deletionBlocked]) =>
    adminDeletionPreviewFromJson(_doc(json));

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 5200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    ));
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  group('the mapper reads what the database really returns', () {
    test('merge: both accounts, with their counts and provider names', () {
      final preview = _merge();

      expect(preview.retained.fullName, 'Retained Player');
      expect(preview.source.fullName, 'Source Player');
      expect(preview.source.signInProviders, ['email', 'google']);
      expect(preview.retained.signInProviders, ['email']);
      expect(preview.source.count('owned_communities'), 2);
      expect(preview.source.count('created_matches'), 2);
      expect(preview.source.count('mvp_awards'), 1);
      expect(preview.source.count('rating_archive_rows'), 3);
      expect(preview.source.count('user_rating_archive_rows'), 1);
      expect(preview.source.count('matches_played'), 3);
      expect(preview.retained.count('goals_total'), 3);
      expect(preview.source.count('does_not_exist'), 0);
      expect(preview.source.rating, 5.0);
      // The rating is a rating, not a count.
      expect(preview.source.counts.containsKey('rating'), isFalse);
      expect(preview.hasBlockers, isTrue);
    });

    test('merge: the overlap, with the role and ownership conflicts among it',
        () {
      final overlap = _merge().overlappingCommunities;

      expect(overlap.total, 3);
      expect(overlap.items, hasLength(3));
      expect(overlap.isTruncated, isFalse);
      final alpha = overlap.items.firstWhere((i) => i.name == 'Alpha');
      expect(alpha.retainedRole, 'player');
      expect(alpha.sourceRole, 'owner');
      expect(alpha.roleConflict, isTrue);
      expect(alpha.sourceOwns, isTrue);
      final beta = overlap.items.firstWhere((i) => i.name == 'Beta');
      expect(beta.retainedOwns, isTrue);
      expect(beta.sourceRole, 'admin');
      final delta = overlap.items.firstWhere((i) => i.name == 'Delta');
      expect(delta.roleConflict, isFalse);
      final preview = _merge();
      expect(preview.roleConflictsTotal, 2);
      expect(preview.ownershipConflictsTotal, 1);
      expect(preview.sourceOwnedCommunities.total, 2);
      final gamma = preview.sourceOwnedCommunities.items
          .firstWhere((i) => i.name == 'Gamma');
      expect(gamma.retainedIsMember, isFalse);
      expect(gamma.retainedRole, isNull);
    });

    test('merge: shared matches say what each account holds, and which collide',
        () {
      final preview = _merge();
      final shared = preview.sharedMatches;

      expect(shared.total, 3);
      expect(preview.collidingMatchesTotal, 1);
      expect(preview.collisionsByKind['registration'], 1);
      expect(preview.collisionsByKind['rating'], 1);
      expect(preview.collisionsByKind['lineup'], 0);
      final one = shared.items.first;
      expect(one.title, 'Match One');
      expect(one.collision, isTrue);
      expect(one.retainedEvidence, contains('REGISTRATION'));
      expect(one.sourceEvidence, contains('REGISTRATION'));
      final three = shared.items.firstWhere((i) => i.title == 'Match Three');
      expect(three.collision, isFalse);
      expect(three.retainedEvidence, ['GOALS']);
      expect(three.sourceEvidence, ['MVP', 'RATING']);
      expect(three.startAt, isNotNull);
      expect(preview.communityStatisticsCollisions, 1);
      expect(preview.teamAwardCollisions, 1);
    });

    test('merge: findings keep their severity, count and order', () {
      final preview = _merge();
      final blockers = preview.findingsOf(AdminFindingSeverity.blocker);

      expect(blockers.map((f) => f.code), [
        'OWNERSHIP_CONFLICT',
        'RATING_ARCHIVE_IMMUTABLE',
        'SHARED_MATCH_COLLISION'
      ]);
      expect(preview.findings.first.severity, AdminFindingSeverity.blocker);
      expect(
        preview.findings.map((f) => f.severity.index).toList(),
        orderedEquals(
            [...preview.findings.map((f) => f.severity.index)]..sort()),
        reason: 'blockers first, then conflicts, then constraints',
      );
      final archive = preview.findings
          .firstWhere((f) => f.code == 'RATING_ARCHIVE_IMMUTABLE');
      expect(archive.severity, AdminFindingSeverity.blocker);
      expect(archive.count, 4);
      expect(archive.category, 'ARCHIVE');
      expect(preview.coverageNotes, hasLength(3));
    });

    test('merge: two empty accounts have nothing in the way', () {
      final preview = _merge(_mergeEmpty);

      expect(preview.hasBlockers, isFalse);
      expect(preview.findings, isEmpty);
      expect(preview.overlappingCommunities.total, 0);
      expect(preview.overlappingCommunities.items, isEmpty);
      expect(preview.sharedMatches.total, 0);
      expect(preview.collidingMatchesTotal, 0);
      expect(preview.retained.count('registrations'), 0);
    });

    test('deletion: blockers, owned communities, created matches, history', () {
      final preview = _deletion();

      expect(preview.hasBlockers, isTrue);
      expect(
        preview.findingsOf(AdminFindingSeverity.blocker).map((f) => f.code),
        [
          'CREATED_MATCHES',
          'HISTORY_WOULD_CASCADE',
          'MVP_RESULTS_WOULD_CASCADE',
          'OWNS_COMMUNITIES',
          'RATING_ARCHIVE_IMMUTABLE',
        ],
      );
      expect(preview.ownedCommunities.total, 2);
      final alpha =
          preview.ownedCommunities.items.firstWhere((c) => c.name == 'Alpha');
      expect(alpha.memberCount, 2);
      expect(alpha.otherAdminCount, 0);
      expect(alpha.matchCount, 2);
      expect(preview.createdMatches.total, 2);
      expect(preview.createdMatchesByStatus['completed'], 2);
      final three = preview.createdMatches.items
          .firstWhere((m) => m.title == 'Match Three');
      expect(three.hasResult, isTrue);
      final one = preview.createdMatches.items
          .firstWhere((m) => m.title == 'Match One');
      expect(one.hasResult, isFalse);
    });

    test('deletion: what the cascade would erase is told apart from what stays',
        () {
      final preview = _deletion();
      final byCode = {for (final r in preview.historicalRecords) r.code: r};

      expect(byCode['MVP_RESULTS']!.treatment, 'CASCADE_DELETE');
      expect(byCode['MVP_RESULTS']!.records, 1);
      expect(byCode['RECORDED_RESULTS']!.treatment, 'DETACH');
      expect(byCode['REGISTRATION_EVENTS']!.treatment, 'RETAINED_ID');
      expect(preview.historicalRecords.first.treatment, 'CASCADE_DELETE');
      final preserved = {
        for (final r in preview.preservedRecords) r.code: r.records,
      };
      expect(preserved['RATING_HISTORY_ARCHIVE'], 3);
      expect(preserved['USER_RATING_ARCHIVE'], 1);
      expect(preserved['ADMIN_AUDIT_LOG'], 1);
      // Rating history rejects UPDATE only and is deleted with the account, so it
      // is history that is erased -- not a record that is preserved.
      expect(preserved.containsKey('RATING_HISTORY'), isFalse);
      expect(preserved, hasLength(3));
      expect(byCode['RATING_HISTORY']!.treatment, 'CASCADE_DELETE');
      expect(byCode['RATING_HISTORY']!.records, 2);
      final personal = {
        for (final r in preview.personalData) r.code: r.records,
      };
      expect(personal['AVATAR'], 1);
      expect(personal['PUSH_TOKENS'], 1);
      expect(personal['SIGN_IN_IDENTITIES'], 2);
    });

    test('deletion: an empty account holds only its profile', () {
      final preview = _deletion(_deletionEmpty);

      expect(preview.hasBlockers, isFalse);
      expect(preview.findings, isEmpty);
      expect(preview.ownedCommunities.total, 0);
      expect(preview.createdMatches.total, 0);
      expect(preview.createdMatchesByStatus, isEmpty);
      expect(preview.historicalRecords, isEmpty);
      expect(preview.preservedRecords, isEmpty);
      expect(preview.personalData.map((r) => r.code),
          containsAll(['PROFILE', 'EMAIL_ADDRESS']));
    });

    test('the documents never carry a credential', () {
      const text = '$_mergeConflicting$_deletionBlocked';
      for (final secret in [
        'secret-token-value',
        'identity-secret',
        'hash-secret-do-not-leak',
        'encrypted_password',
        'identity_data',
        'access_token',
        'refresh_token',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('what the mapper does not know is kept or softened, never dropped',
        () {
      final json = _doc(_deletionBlocked);
      (json['findings'] as List).add({
        'code': 'SOMETHING_NEW',
        'severity': 'ABOUT_TO_EXIST',
        'category': 'FUTURE',
        'count': 7,
      });
      final preview = adminDeletionPreviewFromJson(json);
      final novel =
          preview.findings.firstWhere((f) => f.code == 'SOMETHING_NEW');

      expect(novel.severity, AdminFindingSeverity.conflict,
          reason: 'asks for attention rather than hiding');
      expect(novel.count, 7);

      final bare = adminDeletionPreviewFromJson({});
      expect(bare.hasBlockers, isTrue,
          reason: 'unknown reads as blocked, never as clear');
      expect(bare.findings, isEmpty);
      expect(bare.ownedCommunities.items, isEmpty);
      expect(adminMergePreviewFromJson({}).hasBlockers, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('the repository', () {
    test('the same account twice is refused without asking the database',
        () async {
      final adapter = FakeAdminAdapter(mergePreview: _merge());
      final repository = AdminRepository(adapter);

      await expectLater(
        repository.previewAccountMerge(
            retainedUserId: 'u1', sourceUserId: 'u1'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.calls, isEmpty);
    });

    test('two different accounts are passed through, in order', () async {
      final adapter = FakeAdminAdapter(
        mergePreview: _merge(),
        deletionPreview: _deletion(),
      );
      final repository = AdminRepository(adapter);

      expect(
        await repository.previewAccountMerge(
            retainedUserId: 'u1', sourceUserId: 'u2'),
        isA<AdminMergePreview>(),
      );
      expect(await repository.previewAccountDeletion('u2'),
          isA<AdminDeletionPreview>());
      expect(adapter.calls,
          ['previewAccountMerge:u1:u2', 'previewAccountDeletion:u2']);
    });

    test('a refusal reaches the caller as itself, never as an empty preview',
        () async {
      final adapter =
          FakeAdminAdapter(previewFailure: const AuthorizationFailure());
      final repository = AdminRepository(adapter);

      await expectLater(repository.previewAccountDeletion('u2'),
          throwsA(isA<AuthorizationFailure>()));
      await expectLater(
        repository.previewAccountMerge(
            retainedUserId: 'u1', sourceUserId: 'u2'),
        throwsA(isA<AuthorizationFailure>()),
      );
    });

    test('a preview performs no write: every call it makes is a preview',
        () async {
      final adapter = FakeAdminAdapter(
        mergePreview: _merge(),
        deletionPreview: _deletion(),
      );
      final repository = AdminRepository(adapter);

      await repository.previewAccountMerge(
          retainedUserId: 'u1', sourceUserId: 'u2');
      await repository.previewAccountDeletion('u1');

      expect(adapter.calls.every((c) => c.startsWith('preview')), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('the deletion preview screen', () {
    Future<FakeAdminAdapter> open(
      WidgetTester tester, {
      AdminDeletionPreview? preview,
      Failure? failure,
      Locale locale = const Locale('en'),
      Map<String, dynamic>? json,
    }) async {
      final adapter = FakeAdminAdapter(
        deletionPreview: preview ??
            (json == null ? _deletion() : adminDeletionPreviewFromJson(json)),
        previewFailure: failure,
      );
      await pump(
        tester,
        AdminDeletionPreviewScreen(
          userId: 'u2',
          repository: AdminRepository(adapter),
        ),
        locale: locale,
      );
      return adapter;
    }

    testWidgets('says it is read only and gives the verdict', (tester) async {
      await open(tester);

      expect(find.text('Deletion preview'), findsOneWidget);
      expect(
        find.text(
            'Read only. Nothing is merged, deleted or changed from this screen, and this '
            'preview does not make a merge or deletion available or authorised.'),
        findsOneWidget,
      );
      expect(find.text('5 blockers found.'), findsOneWidget);
    });

    testWidgets('lists every blocker, conflict and constraint, graded',
        (tester) async {
      await open(tester);

      for (final code in [
        'OWNS_COMMUNITIES',
        'CREATED_MATCHES',
        'MVP_RESULTS_WOULD_CASCADE',
        'HISTORY_WOULD_CASCADE',
        'UPCOMING_REGISTRATIONS',
        'RATING_ARCHIVE_IMMUTABLE',
        'RATING_HISTORY_IMMUTABLE',
        'AUDIT_LOG_APPEND_ONLY',
      ]) {
        expect(find.byKey(Key('adminFinding_$code')), findsOneWidget,
            reason: code);
      }
      expect(find.text('Blocker'), findsNWidgets(5));
      expect(find.text('Needs a rule'), findsOneWidget);
      expect(find.text('Cannot be changed'), findsNWidgets(3));
      expect(find.text('Owns communities: ownership must be transferred first'),
          findsOneWidget);
      expect(
        find.text(
            'Deleting would erase the results of matches where this player is the MVP'),
        findsOneWidget,
      );
    });

    testWidgets('owned communities and created matches are listed',
        (tester) async {
      await open(tester);

      expect(
          find.text('2 members · 0 other admins · 2 matches'), findsOneWidget);
      expect(
          find.text('1 members · 0 other admins · 0 matches'), findsOneWidget);
      expect(find.text('Match One'), findsOneWidget);
      expect(find.text('Match Three'), findsOneWidget);
      expect(find.text('Has a recorded result'), findsOneWidget);
      expect(find.text('completed · 2'), findsOneWidget);
    });

    testWidgets('history says what the delete would do to each part',
        (tester) async {
      await open(tester);

      expect(find.text('Erased with the account'), findsWidgets);
      expect(find.text('Link removed, record kept'), findsWidgets);
      expect(find.text('Kept, pointing at no account'), findsWidgets);
      expect(find.text('MVP awards · 1'), findsOneWidget);
      expect(find.text('Career statistics · 1'), findsOneWidget,
          reason: 'a statistics record is one record, not the matches in it');
      expect(find.text('Rating history archive'), findsOneWidget);
    });

    testWidgets('says what the preview could not see', (tester) async {
      await open(tester);

      expect(find.text('Not covered by this preview'), findsOneWidget);
      expect(
        find.textContaining('lineup-generation data are not scanned'),
        findsOneWidget,
      );
      expect(find.textContaining('profile picture file in storage'),
          findsOneWidget);
      expect(
          find.textContaining('Sign-in sessions and tokens'), findsOneWidget);
    });

    testWidgets('a list the database bounded says so', (tester) async {
      final json = _doc(_deletionBlocked);
      (json['owned_communities'] as Map)['total'] = 32;
      await open(tester, json: json);

      expect(find.text('Showing 2 of 32'), findsOneWidget);
    });

    testWidgets('an account with nothing in the way says exactly that',
        (tester) async {
      await open(tester, preview: _deletion(_deletionEmpty));

      expect(find.text('No blockers found in this preview.'), findsOneWidget);
      expect(find.text('Nothing in the way.'), findsOneWidget);
      expect(find.byKey(const Key('adminPreviewBounded')), findsNothing);
    });

    testWidgets('a word the screen does not know is shown as sent',
        (tester) async {
      final json = _doc(_deletionBlocked);
      (json['findings'] as List).insert(0, {
        'code': 'SOMETHING_NEW',
        'severity': 'BLOCKER',
        'category': 'FUTURE',
        'count': 7,
      });
      await open(tester, json: json);

      expect(find.text('SOMETHING_NEW'), findsOneWidget);
      expect(find.text('6 blockers found.'), findsOneWidget);
    });

    testWidgets(
        'has nothing to press: no delete, anonymise, transfer or confirm',
        (tester) async {
      final adapter = await open(tester);

      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      // The app header owns a menu; the preview itself has no tappable row.
      expect(
        find.descendant(
            of: find.byType(ListView), matching: find.byType(InkWell)),
        findsNothing,
      );
      for (final word in [
        'Delete',
        'Anonymise',
        'Transfer',
        'Confirm',
        'Merge'
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      expect(adapter.calls, ['previewAccountDeletion:u2']);
    });

    for (final failure in <Failure>[
      const AuthorizationFailure(),
      const InfrastructureFailure(),
      const NetworkFailure(),
      const NotFoundFailure(),
    ]) {
      testWidgets(
          '${failure.runtimeType}: a failed read offers a retry, not an '
          'empty preview', (tester) async {
        await open(tester, failure: failure);

        expect(find.text('Failed to load data.'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('No blockers found in this preview.'), findsNothing);
        expect(find.text('Nothing in the way.'), findsNothing);
      });
    }

    testWidgets('the retry reads again', (tester) async {
      final adapter = await open(tester, failure: const NetworkFailure());

      adapter.previewFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('5 blockers found.'), findsOneWidget);
      expect(adapter.calls,
          ['previewAccountDeletion:u2', 'previewAccountDeletion:u2']);
    });

    testWidgets('a retry that fails again is still just a retry',
        (tester) async {
      // The retry builds its future before the next frame, so a failure can land
      // before the screen is listening. It must show as failed, not escape as an
      // unhandled error.
      final adapter = await open(tester, failure: const NetworkFailure());

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Failed to load data.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(adapter.calls.length, 2);
    });

    testWidgets('it reads in Arabic', (tester) async {
      await open(tester, locale: const Locale('ar'));

      expect(find.text('معاينة حذف الحساب'), findsOneWidget);
      expect(find.text('يملك مجتمعات: يجب نقل الملكية أولاً'), findsOneWidget);
      expect(find.text('عائق'), findsNWidgets(5));
      expect(find.text('يُمحى مع الحساب'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  group('the merge preview screen', () {
    final retained = adminUser(id: 'u1', name: 'Retained Player');
    final source = adminUser(id: 'u2', name: 'Source Player');

    late FakeAdminAdapter adapter;

    Future<void> open(
      WidgetTester tester, {
      AdminMergePreview? preview,
      Failure? failure,
      Locale locale = const Locale('en'),
    }) async {
      adapter = FakeAdminAdapter(
        users: [retained, source, adminUser(id: 'u3', name: 'Third Player')],
        mergePreview: preview ?? _merge(),
        previewFailure: failure,
      );
      await pump(
        tester,
        AdminMergePreviewScreen(
          retained: retained,
          repository: AdminRepository(adapter),
        ),
        locale: locale,
      );
    }

    Future<void> chooseSource(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(const Key('adminMergeSourceSlot')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('adminMergePick_$id')));
      await tester.pumpAndSettle();
    }

    bool canPreview(WidgetTester tester) =>
        tester
            .widget<FilledButton>(
                find.byKey(const Key('adminMergePreviewButton')))
            .onPressed !=
        null;

    testWidgets('starts with the account the administrator came from',
        (tester) async {
      await open(tester);

      expect(find.text('Merge preview'), findsOneWidget);
      expect(find.text('Account to keep'), findsOneWidget);
      expect(find.text('Retained Player'), findsOneWidget);
      expect(find.text('Account to merge in'), findsOneWidget);
      expect(find.text('Choose an account'), findsOneWidget);
      expect(canPreview(tester), isFalse);
      expect(find.text('Choose two different accounts to preview.'),
          findsOneWidget);
      expect(adapter.calls, isEmpty, reason: 'nothing is read until asked');
    });

    testWidgets('the picker never offers the account already chosen',
        (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('adminMergeSourceSlot')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminMergePick_u1')), findsNothing);
      expect(find.byKey(const Key('adminMergePick_u2')), findsOneWidget);
      expect(find.byKey(const Key('adminMergePick_u3')), findsOneWidget);
    });

    testWidgets('two different accounts can be previewed', (tester) async {
      await open(tester);

      await chooseSource(tester, 'u2');
      expect(find.text('Source Player'), findsOneWidget);
      expect(canPreview(tester), isTrue);
      expect(
          find.text('Choose two different accounts to preview.'), findsNothing);

      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      // `listUsers` is the picker reading the Users list; nothing else is asked.
      expect(
        adapter.calls.where((c) => c != 'listUsers'),
        ['previewAccountMerge:u1:u2'],
      );
      expect(find.text('3 blockers found.'), findsOneWidget);
    });

    testWidgets('shows the communities both belong to, with the conflicts',
        (tester) async {
      await open(tester);
      await chooseSource(tester, 'u2');
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      expect(find.text('Communities both belong to'), findsOneWidget);
      expect(find.text('Merged-in account owns it'), findsOneWidget);
      expect(find.text('Kept account owns it'), findsOneWidget);
      expect(find.text('Different roles'), findsNWidgets(2));
      expect(find.text('Keep: Player · Merge in: Owner'), findsOneWidget);
      expect(find.text('Keep: Owner · Merge in: Admin'), findsOneWidget);
      expect(
          find.text('Communities the merged-in account owns'), findsOneWidget);
      expect(find.text('Kept account is not a member'), findsOneWidget);
    });

    testWidgets('shows the matches both appear in, and the one that collides',
        (tester) async {
      await open(tester);
      await chooseSource(tester, 'u2');
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      expect(find.text('Matches both appear in'), findsOneWidget);
      expect(find.text('Match One'), findsOneWidget);
      expect(find.text('Collision'), findsOneWidget);
      expect(find.text('Keep: Goals, Rating, Registration'), findsOneWidget);
      expect(
          find.text('Merge in: Lineup, Rating, Registration'), findsOneWidget);
      expect(find.text('Keep: Goals'), findsOneWidget);
      expect(find.text('Merge in: MVP, Rating'), findsOneWidget);
      expect(find.text('Registration · 1'), findsOneWidget);
      expect(find.text('Rating · 1'), findsOneWidget);
    });

    testWidgets('grades the findings and counts both accounts side by side',
        (tester) async {
      await open(tester);
      await chooseSource(tester, 'u2');
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminFinding_OWNERSHIP_CONFLICT')),
          findsOneWidget);
      expect(find.byKey(const Key('adminFinding_SHARED_MATCH_COLLISION')),
          findsOneWidget);
      expect(
          find.byKey(const Key('adminFinding_ROLE_CONFLICT')), findsOneWidget);
      expect(find.byKey(const Key('adminFinding_RATING_ARCHIVE_IMMUTABLE')),
          findsOneWidget);
      expect(find.text('Blocker'), findsNWidgets(3));
      expect(
          find.text(
              'Rating archive rows name this account and cannot be moved or deleted, so '
              'retiring it safely is not demonstrated'),
          findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Merge in'), findsOneWidget);
      expect(find.text('Statistics that would collide'), findsOneWidget);
    });

    testWidgets('two accounts with nothing in common have nothing in the way',
        (tester) async {
      await open(tester, preview: _merge(_mergeEmpty));
      await chooseSource(tester, 'u2');
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      expect(find.text('No blockers found in this preview.'), findsOneWidget);
      expect(find.text('Nothing in the way.'), findsOneWidget);
      expect(find.byKey(const Key('adminFinding_OWNERSHIP_CONFLICT')),
          findsNothing);
    });

    testWidgets('swapping the accounts drops the answer to the old question',
        (tester) async {
      await open(tester);
      await chooseSource(tester, 'u2');
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adminPreviewVerdict')), findsOneWidget);

      await tester.tap(find.byKey(const Key('adminMergeSwap')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminPreviewVerdict')), findsNothing);
      final keep = find.descendant(
          of: find.byKey(const Key('adminMergeRetainedSlot')),
          matching: find.text('Source Player'));
      final merge = find.descendant(
          of: find.byKey(const Key('adminMergeSourceSlot')),
          matching: find.text('Retained Player'));
      expect(keep, findsOneWidget);
      expect(merge, findsOneWidget);

      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();
      expect(adapter.calls.last, 'previewAccountMerge:u2:u1',
          reason: 'the swapped pair is what is asked about');
    });

    testWidgets('choosing a different account drops the old answer',
        (tester) async {
      await open(tester);
      await chooseSource(tester, 'u2');
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      await chooseSource(tester, 'u3');

      expect(find.byKey(const Key('adminPreviewVerdict')), findsNothing);
      expect(canPreview(tester), isTrue);
    });

    testWidgets('a failed read offers a retry beside the choice',
        (tester) async {
      await open(tester, failure: const AuthorizationFailure());
      await chooseSource(tester, 'u2');
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load data.'), findsOneWidget);
      expect(find.byKey(const Key('adminMergeRetry')), findsOneWidget);
      expect(find.text('No blockers found in this preview.'), findsNothing);
      // The choice is still there to change.
      expect(find.text('Source Player'), findsOneWidget);

      adapter.previewFailure = null;
      await tester.tap(find.byKey(const Key('adminMergeRetry')));
      await tester.pumpAndSettle();
      expect(find.text('3 blockers found.'), findsOneWidget);
    });

    testWidgets('has nothing to press that merges, deletes or confirms',
        (tester) async {
      await open(tester);
      await chooseSource(tester, 'u2');
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      // Only the preview button and the swap: no second FilledButton, nothing else.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      for (final word in [
        'Merge accounts',
        'Delete',
        'Confirm',
        'Anonymise',
        'Execute'
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      expect(
        adapter.calls
            .where((c) => c != 'listUsers')
            .every((c) => c.startsWith('preview')),
        isTrue,
        reason: 'only the picker\'s read of the Users list, and previews',
      );
    });

    testWidgets('it reads in Arabic', (tester) async {
      await open(tester, locale: const Locale('ar'));
      await chooseSource(tester, 'u2');
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      expect(find.text('معاينة دمج الحسابات'), findsOneWidget);
      expect(find.text('الحساب المُبقى'), findsWidgets);
      expect(find.text('عائق'), findsNWidgets(3));
      expect(find.text('تعارض'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('the way in from the account screen', () {
    Future<FakeAdminAdapter> openDetail(
      WidgetTester tester, {
      AdminUserAccount? account,
      String? signedIn,
    }) async {
      final adapter = FakeAdminAdapter(
        activitySummary: seenActivitySummary,
        accountResult: account,
        signedInUserId: signedIn,
        mergePreview: _merge(),
        deletionPreview: _deletion(),
      );
      await pump(
        tester,
        AdminUserDetailScreen(
          userId: 'u1',
          repository: AdminRepository(adapter),
          wilayatRepository: WilayatRepository(FakeWilayatAdapter()),
        ),
      );
      return adapter;
    }

    testWidgets('both previews are offered for an ordinary account',
        (tester) async {
      await openDetail(tester, signedIn: 'admin-1');

      expect(find.byKey(const Key('adminAccountPreviewMerge')), findsOneWidget);
      expect(
          find.byKey(const Key('adminAccountPreviewDeletion')), findsOneWidget);
      expect(find.text('Preview merge'), findsOneWidget);
      expect(find.text('Preview deletion'), findsOneWidget);
    });

    testWidgets(
        'and for the administrator\'s own account and a System Admin\'s, '
        'which is how their blockers are seen', (tester) async {
      await openDetail(tester, account: adminAccount(id: 'u1'), signedIn: 'u1');
      expect(
          find.byKey(const Key('adminAccountPreviewDeletion')), findsOneWidget);
      expect(find.byKey(const Key('adminAccountEdit')), findsNothing,
          reason: 'editing is still left out');
    });

    testWidgets('the same for a System Admin', (tester) async {
      await openDetail(tester,
          account: adminAccount(isSystemAdmin: true), signedIn: 'admin-1');
      expect(find.byKey(const Key('adminAccountPreviewMerge')), findsOneWidget);
      expect(
          find.byKey(const Key('adminAccountPreviewDeletion')), findsOneWidget);
    });

    testWidgets('are not offered when the account data did not load',
        (tester) async {
      final adapter = FakeAdminAdapter(
        activitySummary: seenActivitySummary,
        accountFailure: const NetworkFailure(),
      );
      await pump(
        tester,
        AdminUserDetailScreen(
          userId: 'u1',
          repository: AdminRepository(adapter),
          wilayatRepository: WilayatRepository(FakeWilayatAdapter()),
        ),
      );

      expect(find.byKey(const Key('adminAccountPreviewMerge')), findsNothing);
      expect(
          find.byKey(const Key('adminAccountPreviewDeletion')), findsNothing);
    });

    testWidgets('the merge preview opens with this account as the one to keep',
        (tester) async {
      await openDetail(tester,
          account: adminAccount(fullName: 'Account Holder'));

      await tester
          .ensureVisible(find.byKey(const Key('adminAccountPreviewMerge')));
      await tester.tap(find.byKey(const Key('adminAccountPreviewMerge')));
      await tester.pumpAndSettle();

      expect(find.text('Merge preview'), findsOneWidget);
      final slot = find.byKey(const Key('adminMergeRetainedSlot'));
      expect(find.descendant(of: slot, matching: find.text('Account Holder')),
          findsOneWidget);
    });

    testWidgets('the deletion preview opens and reads this account',
        (tester) async {
      final adapter = await openDetail(tester);

      await tester
          .ensureVisible(find.byKey(const Key('adminAccountPreviewDeletion')));
      await tester.tap(find.byKey(const Key('adminAccountPreviewDeletion')));
      await tester.pumpAndSettle();

      expect(find.text('Deletion preview'), findsOneWidget);
      expect(adapter.calls, contains('previewAccountDeletion:u1'));
    });
  });

  // ---------------------------------------------------------------------------
  group('the safety rules of the read-only phase', () {
    AdminFindingSeverity? severityOf(
        List<AdminPreviewFinding> findings, String code) {
      for (final finding in findings) {
        if (finding.code == code) return finding.severity;
      }
      return null;
    }

    Future<FakeAdminAdapter> openMerge(
        WidgetTester tester, AdminMergePreview preview) async {
      final adapter = FakeAdminAdapter(
        users: [
          adminUser(id: 'u1', name: 'Retained Player'),
          adminUser(id: 'u2', name: 'Source Player'),
        ],
        mergePreview: preview,
      );
      await pump(
        tester,
        AdminMergePreviewScreen(
          retained: adminUser(id: 'u1', name: 'Retained Player'),
          repository: AdminRepository(adapter),
        ),
      );
      await tester.tap(find.byKey(const Key('adminMergeSourceSlot')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adminMergePick_u2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();
      return adapter;
    }

    Future<void> openDeletion(
        WidgetTester tester, AdminDeletionPreview preview) async {
      await pump(
        tester,
        AdminDeletionPreviewScreen(
          userId: 'u2',
          repository:
              AdminRepository(FakeAdminAdapter(deletionPreview: preview)),
        ),
      );
    }

    GoChipTone verdictTone(WidgetTester tester) => tester
        .widget<GoStatusChip>(find.byKey(const Key('adminPreviewVerdict')))
        .tone;

    /// Words that would read as permission. The previews use none of them.
    void expectNoPermissionLanguage(WidgetTester tester) {
      const words = [
        'proceed',
        'ready to',
        'safe to',
        'approved',
        'allowed',
        'can be merged',
        'can be deleted',
        'go ahead',
      ];
      final offenders = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((text) => words.any(text.toLowerCase().contains))
          .toList();
      expect(offenders, isEmpty);
    }

    // ---- System Admins -------------------------------------------------------
    group('a System Admin is blocked wherever one appears', () {
      test('on either side of a merge', () {
        final preview = _merge(_mergeSystemAdmins);

        expect(preview.retained.isSystemAdmin, isTrue);
        expect(preview.source.isSystemAdmin, isTrue);
        for (final code in [
          'RETAINED_IS_SYSTEM_ADMIN',
          'SOURCE_IS_SYSTEM_ADMIN',
          'SOURCE_IS_CALLER',
        ]) {
          expect(
              severityOf(preview.findings, code), AdminFindingSeverity.blocker,
              reason: code);
        }
        expect(preview.hasBlockers, isTrue);
      });

      test('as the account to delete', () {
        final preview = _deletion(_deletionSystemAdmin);

        expect(preview.account.isSystemAdmin, isTrue);
        expect(severityOf(preview.findings, 'TARGET_IS_SYSTEM_ADMIN'),
            AdminFindingSeverity.blocker);
        expect(preview.hasBlockers, isTrue);
      });

      testWidgets('the merge screen shows each as a blocker', (tester) async {
        await openMerge(tester, _merge(_mergeSystemAdmins));

        expect(find.byKey(const Key('adminFinding_RETAINED_IS_SYSTEM_ADMIN')),
            findsOneWidget);
        expect(find.byKey(const Key('adminFinding_SOURCE_IS_SYSTEM_ADMIN')),
            findsOneWidget);
        expect(
            find.text('The account to keep is a System Admin'), findsOneWidget);
        expect(find.text('The account to merge in is a System Admin'),
            findsOneWidget);
        expect(find.text('Blocker'), findsNWidgets(3));
        expect(find.text('3 blockers found.'), findsOneWidget);
        expect(verdictTone(tester), GoChipTone.danger);
      });

      testWidgets('the deletion screen shows it as a blocker', (tester) async {
        await openDeletion(tester, _deletion(_deletionSystemAdmin));

        expect(find.text('This account is a System Admin'), findsOneWidget);
        expect(find.byKey(const Key('adminFinding_TARGET_IS_SYSTEM_ADMIN')),
            findsOneWidget);
        expect(verdictTone(tester), GoChipTone.danger);
      });
    });

    // ---- immutable archives --------------------------------------------------
    group('immutable rating archives block the account that would be retired',
        () {
      test('merge: an account only the archives name is blocked by that alone',
          () {
        final preview = _merge(_mergeArchiveOnly);

        expect(preview.findings, hasLength(1));
        expect(preview.findings.single.code, 'RATING_ARCHIVE_IMMUTABLE');
        expect(preview.findings.single.severity, AdminFindingSeverity.blocker);
        expect(preview.findings.single.category, 'ARCHIVE');
        expect(preview.findings.single.count, 3);
        expect(preview.hasBlockers, isTrue);
        // Nothing else is wrong with it: the archive is the whole of the block.
        expect(preview.source.count('registrations'), 0);
        expect(preview.source.count('owned_communities'), 0);
      });

      test('deletion: the same, and the archives are still listed', () {
        final preview = _deletion(_deletionArchiveOnly);

        expect(
            preview.findingsOf(AdminFindingSeverity.blocker).map((f) => f.code),
            ['RATING_ARCHIVE_IMMUTABLE']);
        expect(preview.hasBlockers, isTrue);
        expect({
          for (final r in preview.preservedRecords) r.code: r.records
        }, {
          'RATING_HISTORY_ARCHIVE': 2,
          'USER_RATING_ARCHIVE': 1,
        });
      });

      test(
          'the conflicting pair is blocked by the archives as well as the rest',
          () {
        final preview = _merge();

        expect(severityOf(preview.findings, 'RATING_ARCHIVE_IMMUTABLE'),
            AdminFindingSeverity.blocker);
        expect(severityOf(preview.findings, 'RATING_REPLAY_REQUIRED'),
            AdminFindingSeverity.conflict,
            reason: 'the replay is a rule to be made; the archive is a block');
      });

      testWidgets('merge screen: one blocker, worded as "not demonstrated"',
          (tester) async {
        await openMerge(tester, _merge(_mergeArchiveOnly));

        expect(find.text('Blocker'), findsOneWidget);
        expect(find.text('1 blocker found.'), findsOneWidget);
        expect(
          find.text('Rating archive rows name this account and cannot be moved '
              'or deleted, so retiring it safely is not demonstrated'),
          findsOneWidget,
        );
        expect(verdictTone(tester), GoChipTone.danger);
      });

      testWidgets('deletion screen: the same', (tester) async {
        await openDeletion(tester, _deletion(_deletionArchiveOnly));

        expect(find.text('Blocker'), findsOneWidget);
        expect(find.byKey(const Key('adminFinding_RATING_ARCHIVE_IMMUTABLE')),
            findsOneWidget);
        expect(find.text('Rating history archive'), findsOneWidget);
      });
    });

    // ---- rating_history: UPDATE is rejected, but the cascade deletes it -------
    group('football history the cascade would erase', () {
      /// The wording of one finding row: its longest text, not the severity chip.
      String findingText(WidgetTester tester, String code) => tester
          .widgetList<Text>(find.descendant(
              of: find.byKey(Key('adminFinding_$code')),
              matching: find.byType(Text)))
          .map((t) => t.data ?? '')
          .reduce((a, b) => a.length >= b.length ? a : b);

      test('an account only football history names is blocked by that alone',
          () {
        final preview = _deletion(_deletionHistoryOnly);

        expect(preview.hasBlockers, isTrue);
        final blockers = preview.findingsOf(AdminFindingSeverity.blocker);
        expect(blockers.map((f) => f.code), ['HISTORY_WOULD_CASCADE']);
        expect(blockers.single.category, 'HISTORY');
        // One registration, one statistics row and one rating entry.
        expect(blockers.single.count, 3);
        expect(preview.findings.where((f) => f.code == 'OWNS_COMMUNITIES'),
            isEmpty);
        expect(preview.findings.where((f) => f.code == 'CREATED_MATCHES'),
            isEmpty);
      });

      test('the rating-history finding is a constraint about history', () {
        final preview = _deletion(_deletionHistoryOnly);
        final rating = preview.findings
            .firstWhere((f) => f.code == 'RATING_HISTORY_IMMUTABLE');

        expect(rating.severity, AdminFindingSeverity.constraint);
        expect(rating.category, 'HISTORY', reason: 'it is not an archive');
        expect(rating.count, 1);
        expect(severityOf(preview.findings, 'HISTORY_WOULD_CASCADE'),
            AdminFindingSeverity.blocker,
            reason: 'never softened to a conflict');
      });

      test('rating entries are erased with the account, and nothing is kept',
          () {
        final preview = _deletion(_deletionHistoryOnly);
        final erased = {for (final r in preview.historicalRecords) r.code: r};

        expect(erased['RATING_HISTORY']!.treatment, 'CASCADE_DELETE');
        expect(erased['RATING_HISTORY']!.records, 1);
        expect(preview.preservedRecords, isEmpty);
      });

      test('no deletion document lists rating history as a preserved record',
          () {
        for (final json in [
          _deletionBlocked,
          _deletionEmpty,
          _deletionArchiveOnly,
          _deletionSystemAdmin,
          _deletionHistoryOnly,
        ]) {
          final preserved = _deletion(json).preservedRecords.map((r) => r.code);
          expect(preserved, isNot(contains('RATING_HISTORY')));
          expect(
              preserved,
              everyElement(isIn(const [
                'RATING_HISTORY_ARCHIVE',
                'USER_RATING_ARCHIVE',
                'ADMIN_AUDIT_LOG',
              ])));
        }
      });

      testWidgets(
          'deletion screen: one blocker, rating entries shown as erased',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionHistoryOnly));

        expect(find.text('Blocker'), findsOneWidget);
        expect(find.text('1 blocker found.'), findsOneWidget);
        expect(find.byKey(const Key('adminFinding_HISTORY_WOULD_CASCADE')),
            findsOneWidget);
        expect(find.text('Rating entries · 1'), findsOneWidget);
        expect(find.text('Erased with the account'), findsWidgets);
        // Nothing is preserved for this account, and the screen does not say so.
        expect(find.text('Rating history archive'), findsNothing);
        expect(verdictTone(tester), GoChipTone.danger);
      });

      testWidgets('the rating-history wording is about UPDATE, not deletion',
          (tester) async {
        await openDeletion(tester, _deletion());

        final text = findingText(tester, 'RATING_HISTORY_IMMUTABLE');
        expect(
          text,
          'Rating entries cannot be edited (updates are rejected), so they '
          'cannot be anonymised in place; deleting the account deletes them',
        );
        for (final promise in [
          'cannot be deleted',
          'cannot be removed',
          'is preserved',
          'are preserved',
          'protected',
        ]) {
          expect(text, isNot(contains(promise)), reason: promise);
        }
      });

      testWidgets('the same wording in Arabic', (tester) async {
        await pump(
          tester,
          AdminDeletionPreviewScreen(
            userId: 'u2',
            repository:
                AdminRepository(FakeAdminAdapter(deletionPreview: _deletion())),
          ),
          locale: const Locale('ar'),
        );

        final text = findingText(tester, 'RATING_HISTORY_IMMUTABLE');
        expect(text, contains('تُرفض التحديثات'));
        expect(text, endsWith('وحذف الحساب يحذفها'));
        expect(text, isNot(contains('لا يمكن حذف')));
      });
    });

    // ---- has_blockers is not permission -------------------------------------------
    group('"no blockers" is not permission', () {
      test('the documents have no can_proceed; they have has_blockers', () {
        for (final json in [
          _mergeConflicting,
          _mergeEmpty,
          _mergeSystemAdmins,
          _mergeArchiveOnly,
          _mergeCleanSource,
          _deletionBlocked,
          _deletionEmpty,
          _deletionArchiveOnly,
          _deletionSystemAdmin,
        ]) {
          final doc = _doc(json);
          expect(doc.containsKey('can_proceed'), isFalse);
          expect(doc['has_blockers'], isA<bool>());
          expect(json, isNot(contains('can_proceed')));
          // The flag is exactly "some finding is a blocker".
          final anyBlocker = (doc['findings'] as List)
              .any((f) => (f as Map)['severity'] == 'BLOCKER');
          expect(doc['has_blockers'], anyBlocker);
        }
      });

      test('a flag that says "none" never hides a blocker in the findings', () {
        final json = _doc(_mergeConflicting);
        json['has_blockers'] = false;

        expect(adminMergePreviewFromJson(json).hasBlockers, isTrue);
      });

      test('a missing or malformed flag reads as blocked, never as clear', () {
        final missing = _doc(_deletionEmpty)..remove('has_blockers');
        final garbled = _doc(_deletionEmpty)..['has_blockers'] = 'false';

        expect(adminDeletionPreviewFromJson(missing).hasBlockers, isTrue);
        expect(adminDeletionPreviewFromJson(garbled).hasBlockers, isTrue);
      });

      test('only an explicit false with no blocker finding reads as clear', () {
        expect(_deletion(_deletionEmpty).hasBlockers, isFalse);
        expect(_merge(_mergeCleanSource).hasBlockers, isFalse);
      });

      test(
          'a source with conflicts to resolve but nothing blocking is not '
          'blocked, and its conflicts are still reported', () {
        final preview = _merge(_mergeCleanSource);

        expect(preview.findingsOf(AdminFindingSeverity.blocker), isEmpty);
        expect(preview.findingsOf(AdminFindingSeverity.conflict), isNotEmpty);
        expect(severityOf(preview.findings, 'SOURCE_OWNS_COMMUNITIES'),
            AdminFindingSeverity.conflict);
        expect(preview.hasBlockers, isFalse);
      });

      testWidgets(
          'a clear merge preview says so neutrally and authorises nothing',
          (tester) async {
        final adapter = await openMerge(tester, _merge(_mergeCleanSource));

        expect(find.text('No blockers found in this preview.'), findsOneWidget);
        expect(verdictTone(tester), GoChipTone.neutral,
            reason: 'not the colour of "open"');
        expect(
          find.textContaining(
              'does not make a merge or deletion available or authorised'),
          findsOneWidget,
        );
        expect(find.text('Needs a rule'), findsWidgets,
            reason: 'its conflicts are still in front of the reader');
        expectNoPermissionLanguage(tester);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(
          adapter.calls
              .where((c) => c != 'listUsers')
              .every((c) => c.startsWith('preview')),
          isTrue,
        );
      });

      testWidgets(
          'a clear deletion preview says so neutrally and authorises '
          'nothing', (tester) async {
        await openDeletion(tester, _deletion(_deletionEmpty));

        expect(find.text('No blockers found in this preview.'), findsOneWidget);
        expect(verdictTone(tester), GoChipTone.neutral);
        expect(
          find.textContaining(
              'does not make a merge or deletion available or authorised'),
          findsOneWidget,
        );
        expectNoPermissionLanguage(tester);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
      });

      testWidgets('a blocked preview is drawn as blocked', (tester) async {
        await openDeletion(tester, _deletion());

        expect(verdictTone(tester), GoChipTone.danger);
        expect(find.text('5 blockers found.'), findsOneWidget);
        expectNoPermissionLanguage(tester);
      });

      testWidgets('and in Arabic, the same disclaimer is there',
          (tester) async {
        await pump(
          tester,
          AdminDeletionPreviewScreen(
            userId: 'u2',
            repository: AdminRepository(
                FakeAdminAdapter(deletionPreview: _deletion(_deletionEmpty))),
          ),
          locale: const Locale('ar'),
        );

        expect(
            find.textContaining('لا تجعل الدمج أو الحذف متاحاً أو مصرّحاً به'),
            findsOneWidget);
        expect(find.text('لا توجد عوائق في هذه المعاينة.'), findsOneWidget);
      });
    });
  });
}
