import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/football_components.dart'
    show GoChipTone, GoStatusChip;
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_deletion_preview_screen.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_user_detail_screen.dart';
import 'package:go_play/features/locations/wilayat_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';

import 'admin_fakes.dart';
import 'admin_merge_fixtures.dart';
import 'wilayat_fixtures.dart';

/// The read-only deletion preview (migration 0096), the way into both previews
/// from the account screen, and the repository calls they share.
///
/// The merge preview and the merge itself (migration 0101) are in
/// `admin_account_merge_test.dart`, against `admin_merge_fixtures.dart`.
///
/// The deletion documents below are not hand-written. They are what the preview
/// function returned in the offline run of the migration (PGlite, with a seeded
/// account), with only the timestamps replaced, so the mapper and the screens are
/// tested against the shape the database really produces. "Blocked" is an account
/// that many things name; "empty" is one with nothing in the database naming it;
/// "archive only" is an account that nothing but the immutable rating archives
/// names; "history only" is one that completed-match evidence (a registration, a
/// rating entry) names, with a derived statistics row beside it. "Membership only"
/// is a community member with nothing else; "statistics only" holds nothing but
/// derived statistics; "upcoming only" is registered for a match not yet played.
/// "Confirmed only" and "reserve only" hold one registration of a completed match,
/// of each status; "reserve lineup", "reserve goal" and "reserve rating" are a
/// reserve who also has that one kind of evidence. "Audit only" is an account that
/// nothing but the audit log names (as the account acted on); "audit actor" is a
/// former administrator who authored entries; "audit both" is actor, target and
/// both of one entry; "admin actor" is the signed-in System Admin, who authored an
/// entry; "event logs only" is named by an event log and nothing else.
const _deletionBlocked =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":1,"goals_total":0,"memberships":4,"push_tokens":1,"audit_entries":1,"notifications":2,"registrations":2,"matches_played":3,"product_events":2,"rating_entries":2,"created_matches":2,"generation_runs":0,"push_preferences":1,"recorded_results":1,"confirmed_lineups":0,"membership_events":1,"memberships_admin":1,"memberships_owner":2,"owned_communities":2,"lineup_assignments":2,"rating_archive_rows":3,"registration_events":1,"team_of_period_awards":2,"player_statistics_rows":1,"upcoming_registrations":1,"user_rating_archive_rows":1,"community_statistics_rows":2,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000002","email":"p2@x.com","full_name":"Source Player","is_active":true,"is_caller":false,"created_at":"2026-01-15T09:00:00+00:00","is_system_admin":false,"last_sign_in_at":"2026-01-15T09:00:00+00:00","sign_in_providers":["email","google"]}},"version":1,"findings":[{"code":"AUDIT_LOG_APPEND_ONLY","count":1,"category":"AUDIT","severity":"BLOCKER"},{"code":"CREATED_MATCHES","count":2,"category":"MATCH","severity":"BLOCKER"},{"code":"HISTORY_WOULD_CASCADE","count":5,"category":"HISTORY","severity":"BLOCKER"},{"code":"MVP_RESULTS_WOULD_CASCADE","count":1,"category":"MATCH","severity":"BLOCKER"},{"code":"OWNS_COMMUNITIES","count":2,"category":"OWNERSHIP","severity":"BLOCKER"},{"code":"RATING_ARCHIVE_IMMUTABLE","count":4,"category":"ARCHIVE","severity":"BLOCKER"},{"code":"UPCOMING_REGISTRATIONS","count":1,"category":"MATCH","severity":"CONFLICT"},{"code":"EVENT_LOGS_NAME_ACCOUNT","count":2,"category":"HISTORY","severity":"CONSTRAINT"},{"code":"RATING_HISTORY_IMMUTABLE","count":2,"category":"HISTORY","severity":"CONSTRAINT"}],"has_blockers":true,"personal_data":[{"code":"ACTIVITY_EVENTS","records":2},{"code":"AVATAR","records":1},{"code":"DATE_OF_BIRTH","records":1},{"code":"DEFAULT_LOCATION","records":1},{"code":"EMAIL_ADDRESS","records":1},{"code":"NOTIFICATIONS","records":2},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1},{"code":"PUSH_PREFERENCES","records":1},{"code":"PUSH_TOKENS","records":1},{"code":"SIGN_IN_IDENTITIES","records":2}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[{"title":"Match One","status":"completed","match_id":"00000000-0000-0000-0000-000000000513","start_at":"2026-01-15T09:00:00+00:00","has_result":false,"is_historical":false,"community_name":"Alpha"},{"title":"Match Three","status":"completed","match_id":"00000000-0000-0000-0000-000000000515","start_at":"2026-01-15T09:00:00+00:00","has_result":true,"is_historical":false,"community_name":"Alpha"}],"total":2,"by_status":{"completed":2}},"owned_communities":{"items":[{"name":"Alpha","is_active":true,"match_count":2,"community_id":"00000000-0000-0000-0000-000000000257","member_count":2,"other_admin_count":0},{"name":"Gamma","is_active":true,"match_count":0,"community_id":"00000000-0000-0000-0000-000000000259","member_count":1,"other_admin_count":0}],"total":2},"preserved_records":[{"code":"ADMIN_AUDIT_LOG","records":1},{"code":"RATING_HISTORY_ARCHIVE","records":3},{"code":"USER_RATING_ARCHIVE","records":1}],"historical_records":[{"code":"COMMUNITY_MEMBERSHIPS","records":4,"treatment":"CASCADE_DELETE"},{"code":"COMMUNITY_STATISTICS","records":2,"treatment":"CASCADE_DELETE"},{"code":"LINEUP_ASSIGNMENTS","records":2,"treatment":"CASCADE_DELETE"},{"code":"MATCH_REGISTRATIONS","records":2,"treatment":"CASCADE_DELETE"},{"code":"MVP_RESULTS","records":1,"treatment":"CASCADE_DELETE"},{"code":"PLAYER_STATISTICS","records":1,"treatment":"CASCADE_DELETE"},{"code":"RATING_HISTORY","records":2,"treatment":"CASCADE_DELETE"},{"code":"RECORDED_RESULTS","records":1,"treatment":"DETACH"},{"code":"ACTIVITY_EVENTS","records":2,"treatment":"RETAINED_ID"},{"code":"MEMBERSHIP_EVENTS","records":1,"treatment":"RETAINED_ID"},{"code":"REGISTRATION_EVENTS","records":1,"treatment":"RETAINED_ID"},{"code":"TEAM_OF_PERIOD_AWARDS","records":2,"treatment":"RETAINED_ID"}]}''';
const _deletionEmpty =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000003","email":"e1@x.com","full_name":"Empty One","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:57:31.779+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:57:31.779+04:00","sign_in_providers":[]}},"version":1,"findings":[],"has_blockers":false,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[]}''';
const _deletionArchiveOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":2,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":1,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000007","email":"ao@x.com","full_name":"Archive Only","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:57:31.781+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:57:31.781+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"RATING_ARCHIVE_IMMUTABLE","count":3,"category":"ARCHIVE","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[{"code":"RATING_HISTORY_ARCHIVE","records":2},{"code":"USER_RATING_ARCHIVE","records":1}],"historical_records":[]}''';
const _deletionSystemAdmin =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":1,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":1,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":1,"owned_communities":1,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000162","email":"admin2@x.com","full_name":"Admin Two","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:57:31.777+04:00","is_system_admin":true,"last_sign_in_at":"2026-10-09T20:57:31.777+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"CREATED_MATCHES","count":1,"category":"MATCH","severity":"BLOCKER"},{"code":"OWNS_COMMUNITIES","count":1,"category":"OWNERSHIP","severity":"BLOCKER"},{"code":"TARGET_IS_SYSTEM_ADMIN","count":1,"category":"IDENTITY","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[{"title":"Match Four","status":"open","match_id":"00000000-0000-0000-0000-000000000516","start_at":"2026-10-09T20:57:31.787+04:00","has_result":false,"is_historical":false,"community_name":"Delta"}],"total":1,"by_status":{"open":1}},"owned_communities":{"items":[{"name":"Delta","is_active":true,"match_count":1,"community_id":"00000000-0000-0000-0000-000000000260","member_count":3,"other_admin_count":0}],"total":1},"preserved_records":[],"historical_records":[{"code":"COMMUNITY_MEMBERSHIPS","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionHistoryOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":1,"matches_played":1,"product_events":1,"rating_entries":1,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":1,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000009","email":"ho@x.com","full_name":"History Only","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:57:31.782+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:57:31.782+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"HISTORY_WOULD_CASCADE","count":2,"category":"HISTORY","severity":"BLOCKER"},{"code":"RATING_HISTORY_IMMUTABLE","count":1,"category":"HISTORY","severity":"CONSTRAINT"}],"has_blockers":true,"personal_data":[{"code":"ACTIVITY_EVENTS","records":1},{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"MATCH_REGISTRATIONS","records":1,"treatment":"CASCADE_DELETE"},{"code":"PLAYER_STATISTICS","records":1,"treatment":"CASCADE_DELETE"},{"code":"RATING_HISTORY","records":1,"treatment":"CASCADE_DELETE"},{"code":"ACTIVITY_EVENTS","records":1,"treatment":"RETAINED_ID"}]}''';
const _deletionMembershipOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":1,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000010","email":"mem@x.com","full_name":"Membership Only","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:57:31.783+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:57:31.783+04:00","sign_in_providers":[]}},"version":1,"findings":[],"has_blockers":false,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"COMMUNITY_MEMBERSHIPS","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionStatisticsOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":4,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":1,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":1,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000011","email":"stat@x.com","full_name":"Statistics Only","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:57:31.783+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:57:31.783+04:00","sign_in_providers":[]}},"version":1,"findings":[],"has_blockers":false,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"COMMUNITY_STATISTICS","records":1,"treatment":"CASCADE_DELETE"},{"code":"PLAYER_STATISTICS","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionUpcomingOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":1,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":1,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":1,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000013","email":"upc@x.com","full_name":"Upcoming Only","is_active":true,"is_caller":false,"created_at":"2026-10-09T20:57:31.784+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T20:57:31.784+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"UPCOMING_REGISTRATIONS","count":1,"category":"MATCH","severity":"CONFLICT"}],"has_blockers":false,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"LINEUP_ASSIGNMENTS","records":1,"treatment":"CASCADE_DELETE"},{"code":"MATCH_REGISTRATIONS","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionConfirmedOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":1,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000015","email":"kreg@x.com","full_name":"Kind Registration","is_active":true,"is_caller":false,"created_at":"2026-10-09T21:37:00.079+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T21:37:00.079+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"HISTORY_WOULD_CASCADE","count":1,"category":"HISTORY","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"MATCH_REGISTRATIONS","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionReserveOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":1,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000019","email":"resv@x.com","full_name":"Reserve Only","is_active":true,"is_caller":false,"created_at":"2026-10-09T21:37:00.081+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T21:37:00.081+04:00","sign_in_providers":[]}},"version":1,"findings":[],"has_blockers":false,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"MATCH_REGISTRATIONS","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionReserveLineup =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":1,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":1,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000020","email":"rline@x.com","full_name":"Reserve Lineup","is_active":true,"is_caller":false,"created_at":"2026-10-09T21:37:00.082+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T21:37:00.082+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"HISTORY_WOULD_CASCADE","count":1,"category":"HISTORY","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"LINEUP_ASSIGNMENTS","records":1,"treatment":"CASCADE_DELETE"},{"code":"MATCH_REGISTRATIONS","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionReserveGoal =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":1,"mvp_awards":0,"goals_total":1,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":1,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000021","email":"rgoal@x.com","full_name":"Reserve Goal","is_active":true,"is_caller":false,"created_at":"2026-10-09T21:37:00.082+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T21:37:00.082+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"HISTORY_WOULD_CASCADE","count":1,"category":"HISTORY","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"GOAL_RECORDS","records":1,"treatment":"CASCADE_DELETE"},{"code":"MATCH_REGISTRATIONS","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionReserveRating =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":1,"matches_played":0,"product_events":0,"rating_entries":1,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000022","email":"rrate@x.com","full_name":"Reserve Rating","is_active":true,"is_caller":false,"created_at":"2026-10-09T21:37:00.083+04:00","is_system_admin":false,"last_sign_in_at":"2026-10-09T21:37:00.083+04:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"HISTORY_WOULD_CASCADE","count":1,"category":"HISTORY","severity":"BLOCKER"},{"code":"RATING_HISTORY_IMMUTABLE","count":1,"category":"HISTORY","severity":"CONSTRAINT"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"MATCH_REGISTRATIONS","records":1,"treatment":"CASCADE_DELETE"},{"code":"RATING_HISTORY","records":1,"treatment":"CASCADE_DELETE"}]}''';
const _deletionAuditOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":1,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000025","email":"aud@x.com","full_name":"Audit Only","is_active":true,"is_caller":false,"created_at":"2026-01-15T09:00:00+00:00","is_system_admin":false,"last_sign_in_at":"2026-01-15T09:00:00+00:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"AUDIT_LOG_APPEND_ONLY","count":1,"category":"AUDIT","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[{"code":"ADMIN_AUDIT_LOG","records":1}],"historical_records":[]}''';
const _deletionAuditActor =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":3,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000026","email":"former@x.com","full_name":"Former Admin","is_active":true,"is_caller":false,"created_at":"2026-01-15T09:00:00+00:00","is_system_admin":false,"last_sign_in_at":"2026-01-15T09:00:00+00:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"AUDIT_LOG_APPEND_ONLY","count":3,"category":"AUDIT","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[{"code":"ADMIN_AUDIT_LOG","records":3}],"historical_records":[]}''';
const _deletionAuditBoth =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":3,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000027","email":"both@x.com","full_name":"Actor And Target","is_active":true,"is_caller":false,"created_at":"2026-01-15T09:00:00+00:00","is_system_admin":false,"last_sign_in_at":"2026-01-15T09:00:00+00:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"AUDIT_LOG_APPEND_ONLY","count":3,"category":"AUDIT","severity":"BLOCKER"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[{"code":"ADMIN_AUDIT_LOG","records":3}],"historical_records":[]}''';
const _deletionAdminActor =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":1,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":1,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":0,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000161","email":"admin@x.com","full_name":"Admin One","is_active":true,"is_caller":true,"created_at":"2026-01-15T09:00:00+00:00","is_system_admin":true,"last_sign_in_at":"2026-01-15T09:00:00+00:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"AUDIT_LOG_APPEND_ONLY","count":1,"category":"AUDIT","severity":"BLOCKER"},{"code":"TARGET_IS_CALLER","count":1,"category":"IDENTITY","severity":"BLOCKER"},{"code":"TARGET_IS_SYSTEM_ADMIN","count":1,"category":"IDENTITY","severity":"BLOCKER"},{"code":"EVENT_LOGS_NAME_ACCOUNT","count":1,"category":"HISTORY","severity":"CONSTRAINT"}],"has_blockers":true,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[{"code":"ADMIN_AUDIT_LOG","records":1}],"historical_records":[{"code":"MEMBERSHIP_EVENTS","records":1,"treatment":"RETAINED_ID"}]}''';
const _deletionEventLogsOnly =
    r'''{"limit":25,"account":{"counts":{"rating":5,"goal_rows":0,"mvp_awards":0,"goals_total":0,"memberships":0,"push_tokens":0,"audit_entries":0,"notifications":0,"registrations":0,"matches_played":0,"product_events":0,"rating_entries":0,"created_matches":0,"generation_runs":0,"push_preferences":0,"recorded_results":0,"confirmed_lineups":0,"membership_events":0,"memberships_admin":0,"memberships_owner":0,"owned_communities":0,"lineup_assignments":0,"rating_archive_rows":0,"registration_events":1,"team_of_period_awards":0,"player_statistics_rows":0,"upcoming_registrations":0,"user_rating_archive_rows":0,"community_statistics_rows":0,"professional_guests_created":0},"account":{"id":"00000000-0000-0000-0000-000000000028","email":"evt@x.com","full_name":"Event Log Only","is_active":true,"is_caller":false,"created_at":"2026-01-15T09:00:00+00:00","is_system_admin":false,"last_sign_in_at":"2026-01-15T09:00:00+00:00","sign_in_providers":[]}},"version":1,"findings":[{"code":"EVENT_LOGS_NAME_ACCOUNT","count":1,"category":"HISTORY","severity":"CONSTRAINT"}],"has_blockers":false,"personal_data":[{"code":"EMAIL_ADDRESS","records":1},{"code":"PHONE_NUMBER","records":1},{"code":"PROFILE","records":1}],"coverage_notes":["EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED","STORAGE_OBJECTS_NOT_INSPECTED","AUTH_SESSIONS_NOT_INSPECTED"],"created_matches":{"items":[],"total":0,"by_status":{}},"owned_communities":{"items":[],"total":0},"preserved_records":[],"historical_records":[{"code":"REGISTRATION_EVENTS","records":1,"treatment":"RETAINED_ID"}]}''';

Map<String, dynamic> _doc(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

AdminMergePreview _merge([String json = mergeChoicesDoc]) =>
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

    test('deletion: blockers, owned communities, created matches, history', () {
      final preview = _deletion();

      expect(preview.hasBlockers, isTrue);
      expect(
        preview.findingsOf(AdminFindingSeverity.blocker).map((f) => f.code),
        [
          'AUDIT_LOG_APPEND_ONLY',
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
      const text = '$mergeChoicesDoc$mergeBlockedDoc$_deletionBlocked';
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

    testWidgets('says deleting is permanent and gives the verdict',
        (tester) async {
      await open(tester);

      expect(find.text('Delete account'), findsOneWidget);
      expect(find.byKey(const Key('adminDeleteNotice')), findsOneWidget);
      expect(find.textContaining('Deleting is permanent'), findsOneWidget);
      expect(find.text('6 blockers found.'), findsOneWidget);
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
      expect(find.text('Blocker'), findsNWidgets(6));
      expect(find.text('Needs a rule'), findsOneWidget);
      expect(find.text('Cannot be changed'), findsNWidgets(2));
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
      expect(find.text('7 blockers found.'), findsOneWidget);
    });

    testWidgets('offers one destructive control, closed while anything blocks',
        (tester) async {
      final adapter = await open(tester);

      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('adminDeleteExecuteButton')))
            .onPressed,
        isNull,
      );
      expect(find.text('Resolve the blockers above first.'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      for (final word in ['Anonymise', 'Transfer', 'Merge']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      expect(adapter.calls, ['previewAccountDeletion:u2']);
      expect(adapter.deleteRequests, isEmpty, reason: 'reading deletes nothing');
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

      expect(find.text('6 blockers found.'), findsOneWidget);
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

      expect(find.text('حذف حساب'), findsOneWidget);
      expect(find.text('يملك مجتمعات: يجب نقل الملكية أولاً'), findsOneWidget);
      expect(find.text('عائق'), findsNWidgets(6));
      expect(find.text('يُمحى مع الحساب'), findsWidgets);
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

      expect(find.text('Merge accounts'), findsOneWidget);
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

      expect(find.text('Delete account'), findsOneWidget);
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

      test('as the account to delete', () {
        final preview = _deletion(_deletionSystemAdmin);

        expect(preview.account.isSystemAdmin, isTrue);
        expect(severityOf(preview.findings, 'TARGET_IS_SYSTEM_ADMIN'),
            AdminFindingSeverity.blocker);
        expect(preview.hasBlockers, isTrue);
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

      test(
          'an account named by completed-match evidence is blocked by that alone',
          () {
        final preview = _deletion(_deletionHistoryOnly);

        expect(preview.hasBlockers, isTrue);
        final blockers = preview.findingsOf(AdminFindingSeverity.blocker);
        expect(blockers.map((f) => f.code), ['HISTORY_WOULD_CASCADE']);
        expect(blockers.single.category, 'HISTORY');
        // One registration and one rating entry. Its statistics row is derived,
        // is listed below, and is not counted.
        expect(blockers.single.count, 2);
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

    // ---- erased, but not historical match evidence ------------------------------------
    group('what is erased but is not historical match evidence', () {
      Map<String, AdminPreviewRecord> erased(AdminDeletionPreview preview) =>
          {for (final r in preview.historicalRecords) r.code: r};

      test('a membership-only account is not blocked by HISTORY_WOULD_CASCADE',
          () {
        final preview = _deletion(_deletionMembershipOnly);

        expect(preview.findings.where((f) => f.code == 'HISTORY_WOULD_CASCADE'),
            isEmpty);
        expect(preview.hasBlockers, isFalse);
        expect(preview.findings, isEmpty);
        // The membership is still listed, as erased: visible, just not a blocker.
        expect(erased(preview).keys, ['COMMUNITY_MEMBERSHIPS']);
        expect(erased(preview)['COMMUNITY_MEMBERSHIPS']!.treatment,
            'CASCADE_DELETE');
        expect(erased(preview)['COMMUNITY_MEMBERSHIPS']!.records, 1);
      });

      test(
          'derived statistics alone do not create a historical evidence blocker',
          () {
        final preview = _deletion(_deletionStatisticsOnly);

        expect(preview.findings.where((f) => f.code == 'HISTORY_WOULD_CASCADE'),
            isEmpty);
        expect(preview.hasBlockers, isFalse);
        expect(preview.findings, isEmpty);
        expect(erased(preview).keys,
            unorderedEquals(['PLAYER_STATISTICS', 'COMMUNITY_STATISTICS']));
        for (final record in erased(preview).values) {
          expect(record.treatment, 'CASCADE_DELETE');
          expect(record.records, 1);
        }
      });

      test('upcoming registrations stay separately classified', () {
        final preview = _deletion(_deletionUpcomingOnly);

        expect(preview.findings, hasLength(1));
        final upcoming = preview.findings.single;
        expect(upcoming.code, 'UPCOMING_REGISTRATIONS');
        expect(upcoming.severity, AdminFindingSeverity.conflict);
        expect(upcoming.category, 'MATCH');
        expect(upcoming.count, 1);
        // Not evidence of a match that was played: no blocker of any kind.
        expect(preview.hasBlockers, isFalse);
        expect(preview.findings.where((f) => f.code == 'HISTORY_WOULD_CASCADE'),
            isEmpty);
        // Still visible as erased records.
        expect(erased(preview)['MATCH_REGISTRATIONS']!.records, 1);
        expect(erased(preview)['LINEUP_ASSIGNMENTS']!.records, 1);
      });

      test('historical match evidence remains a blocker, and is only evidence',
          () {
        final preview = _deletion();
        final cascade = preview.findings
            .firstWhere((f) => f.code == 'HISTORY_WOULD_CASCADE');

        expect(cascade.severity, AdminFindingSeverity.blocker);
        expect(cascade.category, 'HISTORY');
        // 1 registration + 2 lineup places + 2 rating entries of completed
        // matches. The four memberships, the statistics rows and the registration
        // for a match not yet played are erased too and listed, but not counted.
        expect(cascade.count, 5);
        expect(erased(preview)['COMMUNITY_MEMBERSHIPS']!.records, 4);
        expect(erased(preview)['MATCH_REGISTRATIONS']!.records, 2);
        expect(
            preview.findings
                .firstWhere((f) => f.code == 'UPCOMING_REGISTRATIONS')
                .severity,
            AdminFindingSeverity.conflict);
        expect(preview.hasBlockers, isTrue);
      });

      test('an account with evidence keeps its derived rows listed beside it',
          () {
        final preview = _deletion(_deletionHistoryOnly);

        expect(
            preview.findingsOf(AdminFindingSeverity.blocker).single.count, 2);
        expect(erased(preview)['PLAYER_STATISTICS']!.records, 1);
        expect(erased(preview)['MATCH_REGISTRATIONS']!.records, 1);
        expect(erased(preview)['RATING_HISTORY']!.records, 1);
      });

      testWidgets('deletion screen: a membership-only account has no blocker',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionMembershipOnly));

        expect(find.text('No blockers found in this preview.'), findsOneWidget);
        expect(find.text('Blocker'), findsNothing);
        expect(find.byKey(const Key('adminFinding_HISTORY_WOULD_CASCADE')),
            findsNothing);
        expect(find.text('Community memberships · 1'), findsOneWidget);
        expect(find.text('Erased with the account'), findsWidgets);
        expect(verdictTone(tester), isNot(GoChipTone.danger));
      });

      testWidgets(
          'deletion screen: derived statistics are listed, not blocking',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionStatisticsOnly));

        expect(find.text('No blockers found in this preview.'), findsOneWidget);
        expect(find.text('Blocker'), findsNothing);
        expect(find.text('Career statistics · 1'), findsOneWidget);
        expect(find.text('Community statistics rows · 1'), findsOneWidget);
      });

      testWidgets('deletion screen: an upcoming registration is a conflict',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionUpcomingOnly));

        expect(find.byKey(const Key('adminFinding_UPCOMING_REGISTRATIONS')),
            findsOneWidget);
        expect(find.text('Needs a rule'), findsOneWidget);
        expect(find.text('Blocker'), findsNothing);
        expect(find.byKey(const Key('adminFinding_HISTORY_WOULD_CASCADE')),
            findsNothing);
        expect(find.text('No blockers found in this preview.'), findsOneWidget);
      });
    });

    // ---- a reserve registration is on the waiting list, not in the match -------------
    group('a reserve registration is not historical evidence', () {
      Map<String, AdminPreviewRecord> erased(AdminDeletionPreview preview) =>
          {for (final r in preview.historicalRecords) r.code: r};

      List<AdminPreviewFinding> blockers(AdminDeletionPreview preview) =>
          preview.findingsOf(AdminFindingSeverity.blocker);

      test('a completed reserve-only registration does not create the blocker',
          () {
        final preview = _deletion(_deletionReserveOnly);

        expect(preview.findings.where((f) => f.code == 'HISTORY_WOULD_CASCADE'),
            isEmpty);
        expect(preview.hasBlockers, isFalse);
        expect(preview.findings, isEmpty);
        // Still visible, as erased, in its existing category.
        expect(erased(preview).keys, ['MATCH_REGISTRATIONS']);
        expect(erased(preview)['MATCH_REGISTRATIONS']!.records, 1);
        expect(erased(preview)['MATCH_REGISTRATIONS']!.treatment,
            'CASCADE_DELETE');
      });

      test('a completed confirmed registration does', () {
        final preview = _deletion(_deletionConfirmedOnly);

        expect(blockers(preview).map((f) => f.code), ['HISTORY_WOULD_CASCADE']);
        expect(blockers(preview).single.count, 1);
        expect(blockers(preview).single.category, 'HISTORY');
        expect(preview.hasBlockers, isTrue);
        // Listed exactly as the reserve one is: the category is the same.
        expect(erased(preview)['MATCH_REGISTRATIONS']!.records, 1);
      });

      for (final scenario in <(String, String, String)>[
        ('lineup place', _deletionReserveLineup, 'LINEUP_ASSIGNMENTS'),
        ('goal', _deletionReserveGoal, 'GOAL_RECORDS'),
        ('rating entry', _deletionReserveRating, 'RATING_HISTORY'),
      ]) {
        test('a reserve with a genuine ${scenario.$1} remains blocked', () {
          final preview = _deletion(scenario.$2);

          expect(
              blockers(preview).map((f) => f.code), ['HISTORY_WOULD_CASCADE']);
          // One piece of evidence: the reserve registration adds nothing.
          expect(blockers(preview).single.count, 1);
          expect(preview.hasBlockers, isTrue);
          // Both the registration and the evidence are listed.
          expect(erased(preview)['MATCH_REGISTRATIONS']!.records, 1);
          expect(erased(preview)[scenario.$3]!.records, 1);
          expect(erased(preview)[scenario.$3]!.treatment, 'CASCADE_DELETE');
        });
      }

      test('the reserve registration is a registration, not another category',
          () {
        for (final json in [
          _deletionReserveOnly,
          _deletionConfirmedOnly,
          _deletionReserveLineup,
        ]) {
          final preview = _deletion(json);
          expect(preview.historicalRecords.map((r) => r.code),
              contains('MATCH_REGISTRATIONS'));
          expect(preview.preservedRecords.map((r) => r.code),
              isNot(contains('MATCH_REGISTRATIONS')));
        }
      });

      testWidgets('deletion screen: a reserve-only account has no blocker',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionReserveOnly));

        expect(find.text('No blockers found in this preview.'), findsOneWidget);
        expect(find.text('Blocker'), findsNothing);
        expect(find.byKey(const Key('adminFinding_HISTORY_WOULD_CASCADE')),
            findsNothing);
        expect(find.text('Match registrations · 1'), findsOneWidget);
        expect(find.text('Erased with the account'), findsWidgets);
        expect(verdictTone(tester), isNot(GoChipTone.danger));
      });

      testWidgets('deletion screen: a confirmed registration blocks',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionConfirmedOnly));

        expect(find.text('1 blocker found.'), findsOneWidget);
        expect(find.byKey(const Key('adminFinding_HISTORY_WOULD_CASCADE')),
            findsOneWidget);
        expect(find.text('Match registrations · 1'), findsOneWidget);
        expect(verdictTone(tester), GoChipTone.danger);
      });

      testWidgets('deletion screen: a reserve with a lineup place still blocks',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionReserveLineup));

        expect(find.text('1 blocker found.'), findsOneWidget);
        expect(find.text('Match registrations · 1'), findsOneWidget);
        expect(find.text('Lineup places · 1'), findsOneWidget);
      });
    });

    // ---- identifiable audit entries outlive a deletion -----------------------------------------
    group('audit entries that would still identify a deleted account', () {
      const enWording =
          'Audit log entries naming this account are not erased by a deletion, '
          'so its name or email address would stay identifiable in them';
      const arWording = 'سجلات التدقيق التي تذكر هذا الحساب لا تُمحى بالحذف، '
          'فيبقى اسمه أو بريده الإلكتروني ظاهراً فيها';

      AdminPreviewFinding? auditOf(AdminDeletionPreview preview) {
        for (final finding in preview.findings) {
          if (finding.code == 'AUDIT_LOG_APPEND_ONLY') return finding;
        }
        return null;
      }

      String findingText(WidgetTester tester, String code) => tester
          .widgetList<Text>(find.descendant(
              of: find.byKey(Key('adminFinding_$code')),
              matching: find.byType(Text)))
          .map((t) => t.data ?? '')
          .reduce((a, b) => a.length >= b.length ? a : b);

      test('an account only the audit log names is blocked by that alone', () {
        final preview = _deletion(_deletionAuditOnly);

        expect(preview.findings, hasLength(1));
        final audit = auditOf(preview)!;
        expect(audit.severity, AdminFindingSeverity.blocker);
        expect(audit.category, 'AUDIT');
        expect(audit.count, 1);
        expect(preview.hasBlockers, isTrue);
        // The contract is unchanged: the log is still listed as a preserved record,
        // because it survives the deletion -- which is the problem.
        expect({for (final r in preview.preservedRecords) r.code: r.records},
            {'ADMIN_AUDIT_LOG': 1});
        expect(preview.historicalRecords, isEmpty);
        expect(preview.ownedCommunities.total, 0);
        expect(preview.createdMatches.total, 0);
      });

      test('an account no audit entry references has no audit finding', () {
        for (final json in [
          _deletionEmpty,
          _deletionArchiveOnly,
          _deletionHistoryOnly,
          _deletionMembershipOnly,
          _deletionStatisticsOnly,
          _deletionUpcomingOnly,
          _deletionConfirmedOnly,
          _deletionReserveOnly,
          _deletionReserveLineup,
          _deletionEventLogsOnly,
        ]) {
          final preview = _deletion(json);
          expect(auditOf(preview), isNull);
          expect(preview.preservedRecords.map((r) => r.code),
              isNot(contains('ADMIN_AUDIT_LOG')));
        }
        // ...so such an account is clear unless something else is in the way.
        expect(_deletion(_deletionEmpty).hasBlockers, isFalse);
        expect(_deletion(_deletionMembershipOnly).hasBlockers, isFalse);
      });

      test(
          'the administrator who acted is blocked as well as the account acted on',
          () {
        // A former administrator: the actor of three entries, a System Admin no more.
        final actor = _deletion(_deletionAuditActor);
        expect(actor.findings, hasLength(1));
        expect(auditOf(actor)!.severity, AdminFindingSeverity.blocker);
        expect(auditOf(actor)!.count, 3);
        expect(actor.hasBlockers, isTrue);

        // Actor of one entry, target of another and both of a third: three
        // entries, each counted once.
        final both = _deletion(_deletionAuditBoth);
        expect(auditOf(both)!.count, 3);
        expect(both.findingsOf(AdminFindingSeverity.blocker), hasLength(1));

        // The signed-in System Admin who authored an entry: blocked three ways.
        final admin = _deletion(_deletionAdminActor);
        expect(
            admin.findingsOf(AdminFindingSeverity.blocker).map((f) => f.code),
            unorderedEquals([
              'AUDIT_LOG_APPEND_ONLY',
              'TARGET_IS_CALLER',
              'TARGET_IS_SYSTEM_ADMIN',
            ]));
        expect(auditOf(admin)!.count, 1);
      });

      test('the football-history and structural blockers are untouched', () {
        final preview = _deletion();

        expect(
          {
            for (final f in preview.findingsOf(AdminFindingSeverity.blocker))
              f.code: f.count,
          },
          {
            'AUDIT_LOG_APPEND_ONLY': 1,
            'CREATED_MATCHES': 2,
            'HISTORY_WOULD_CASCADE': 5,
            'MVP_RESULTS_WOULD_CASCADE': 1,
            'OWNS_COMMUNITIES': 2,
            'RATING_ARCHIVE_IMMUTABLE': 4,
          },
        );
        expect(
            preview
                .findingsOf(AdminFindingSeverity.conflict)
                .map((f) => f.code),
            ['UPCOMING_REGISTRATIONS']);
        // Only the audit finding left the constraints.
        expect(
            preview
                .findingsOf(AdminFindingSeverity.constraint)
                .map((f) => f.code),
            ['EVENT_LOGS_NAME_ACCOUNT', 'RATING_HISTORY_IMMUTABLE']);
        // Blockers first, as the documents have always listed them.
        expect(preview.findings.first.severity, AdminFindingSeverity.blocker);
        expect(preview.hasBlockers, isTrue);
        // Football history on its own still blocks, with no audit finding beside it.
        expect(
            _deletion(_deletionHistoryOnly)
                .findingsOf(AdminFindingSeverity.blocker)
                .map((f) => f.code),
            ['HISTORY_WOULD_CASCADE']);
      });

      test(
          'has_blockers is exactly "some finding is a BLOCKER", audit included',
          () {
        for (final json in [
          _deletionBlocked,
          _deletionEmpty,
          _deletionAuditOnly,
          _deletionAuditActor,
          _deletionAuditBoth,
          _deletionAdminActor,
          _deletionEventLogsOnly,
          _deletionSystemAdmin,
          _deletionArchiveOnly,
          _deletionUpcomingOnly,
        ]) {
          final preview = _deletion(json);
          expect(
              preview.hasBlockers,
              preview.findings
                  .any((f) => f.severity == AdminFindingSeverity.blocker));
        }
        // An account only an event log names is a constraint, and not blocked.
        final events = _deletion(_deletionEventLogsOnly);
        expect(events.findings.map((f) => f.code), ['EVENT_LOGS_NAME_ACCOUNT']);
        expect(
            events.findings.single.severity, AdminFindingSeverity.constraint);
        expect(events.hasBlockers, isFalse);
      });

      test(
          'the documents carry how many entries there are, never what they hold',
          () {
        const text = '$_deletionBlocked$_deletionAuditOnly$_deletionAuditActor'
            '$_deletionAuditBoth$_deletionAdminActor$mergeBlockedDoc';
        for (final snapshot in [
          'audit-secret-target@x.com',
          'Audit Secret Label',
          'former-admin-secret@x.com',
          'both-secret@x.com',
          'Both Secret Label',
        ]) {
          expect(text, isNot(contains(snapshot)), reason: snapshot);
        }
      });

      testWidgets(
          'deletion screen: an audit-only account is blocked, in English',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionAuditOnly));

        expect(find.text('1 blocker found.'), findsOneWidget);
        expect(find.text('Blocker'), findsOneWidget);
        expect(find.text('Cannot be changed'), findsNothing);
        expect(find.text('No blockers found in this preview.'), findsNothing);
        expect(verdictTone(tester), GoChipTone.danger);
        expect(findingText(tester, 'AUDIT_LOG_APPEND_ONLY'), enWording);
        expect(find.text('Audit log entries'), findsWidgets);
      });

      testWidgets('the English wording says the identifying data would remain',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionAuditOnly));

        final text = findingText(tester, 'AUDIT_LOG_APPEND_ONLY');
        expect(text, contains('not erased by a deletion'));
        expect(text, contains('name or email address'));
        expect(text, contains('identifiable'));
        // The old wording read as a reassurance that nothing was wrong.
        expect(text, isNot(contains('are kept')));
        expect(text, isNot(contains('as they were written')));
      });

      testWidgets('deletion screen: the same, in Arabic', (tester) async {
        await pump(
          tester,
          AdminDeletionPreviewScreen(
            userId: 'u2',
            repository: AdminRepository(FakeAdminAdapter(
                deletionPreview: _deletion(_deletionAuditOnly))),
          ),
          locale: const Locale('ar'),
        );

        expect(find.text('عائق'), findsOneWidget);
        expect(findingText(tester, 'AUDIT_LOG_APPEND_ONLY'), arWording);
        expect(find.text('لا يمكن تغييره'), findsNothing);
        expect(verdictTone(tester), GoChipTone.danger);
      });

      testWidgets('the Arabic wording says the identifying data would remain',
          (tester) async {
        await pump(
          tester,
          AdminDeletionPreviewScreen(
            userId: 'u2',
            repository: AdminRepository(FakeAdminAdapter(
                deletionPreview: _deletion(_deletionAuditOnly))),
          ),
          locale: const Locale('ar'),
        );

        final text = findingText(tester, 'AUDIT_LOG_APPEND_ONLY');
        expect(text, contains('لا تُمحى بالحذف'));
        expect(text, contains('بريده الإلكتروني'));
        expect(text, contains('ظاهراً'));
        expect(text, isNot(contains('تُحفظ')));
      });

      testWidgets(
          'deletion screen: an account with no audit entries has none of this',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionMembershipOnly));

        expect(find.byKey(const Key('adminFinding_AUDIT_LOG_APPEND_ONLY')),
            findsNothing);
        expect(find.text('No blockers found in this preview.'), findsOneWidget);
        expect(find.text('Blocker'), findsNothing);
      });

      testWidgets(
          'deletion screen: an event-log-only account is still not blocked',
          (tester) async {
        await openDeletion(tester, _deletion(_deletionEventLogsOnly));

        expect(find.text('Cannot be changed'), findsOneWidget);
        expect(find.text('Blocker'), findsNothing);
        expect(find.text('No blockers found in this preview.'), findsOneWidget);
        expect(verdictTone(tester), isNot(GoChipTone.danger));
      });

    });

    // ---- has_blockers is not permission -------------------------------------------
    group('"no blockers" is not permission', () {
      test('the documents have no can_proceed; they have has_blockers', () {
        for (final json in [
          mergeChoicesDoc,
          mergeUnresolvableDoc,
          mergeBlockedDoc,
          mergeCleanDoc,
          mergeEmptyDoc,
          mergeSystemAdminDoc,
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
        final json = _doc(mergeBlockedDoc);
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
        expect(_merge(mergeCleanDoc).hasBlockers, isFalse);
      });

      testWidgets(
          'a clear deletion preview says so neutrally and opens only the one '
          'control', (tester) async {
        await openDeletion(tester, _deletion(_deletionEmpty));

        expect(find.text('No blockers found in this preview.'), findsOneWidget);
        expect(verdictTone(tester), GoChipTone.neutral,
            reason: 'not the colour of "open"');
        expectNoPermissionLanguage(tester);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const Key('adminDeleteExecuteButton')))
              .onPressed,
          isNotNull,
        );
        expect(find.byType(OutlinedButton), findsNothing);
      });

      testWidgets('a blocked preview is drawn as blocked', (tester) async {
        await openDeletion(tester, _deletion());

        expect(verdictTone(tester), GoChipTone.danger);
        expect(find.text('6 blockers found.'), findsOneWidget);
        expectNoPermissionLanguage(tester);
      });

      testWidgets('and in Arabic, the permanence notice is there',
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

        expect(find.textContaining('الحذف نهائي'), findsOneWidget);
        expect(find.text('لا توجد عوائق في هذه المعاينة.'), findsOneWidget);
      });
    });
  });
}
