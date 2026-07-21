# 07 Database Design


Database Design Engineering Version (v2)

Architecture Standards

Database: PostgreSQL / Supabase Primary Keys: UUID Soft Delete: is_active fields where applicable Audit Fields: created_at, updated_at Authentication: Phone Number + Password

Data Dictionary

users, groups, group_members, fields, matches, match_registrations, teams, team_players, match_results, goals, rating_history, player_statistics Each table includes UUID PK, FK constraints, indexes and validation rules.

Key Constraints

- Unique phone number. - Unique group membership (group_id,user_id). - Unique match registration (match_id,user_id). - One result per match. - Ratings between 1 and 10. - Match end time must be greater than start time.

Index Strategy

users(phone, overall_rating) groups(owner_id, join_code) matches(group_id, start_datetime, status) match_registrations(match_id, user_id, registration_order) goals(player_id) rating_history(user_id, created_at) player_statistics(goals, wins, current_rating)

Business Logic

- Auto reserve when match is full. - Auto promote first reserve after cancellation. - Auto team regeneration after roster changes. - Rating updates: WIN +0.10, LOSS -0.10, GOAL +0.05, MVP +0.20. - Match creator controls results and MVP selection.

Security & Integrity

- Foreign key enforcement. - Ownership validation. - No hard delete for critical records. - Audit trail via rating_history.

Implementation Readiness

Database design approved for MVP implementation. Recommended next phase: Workflow Design Specification.