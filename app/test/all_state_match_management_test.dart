import 'dart:io';

import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/community_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/team_mapper.dart';

/// All-State Match Management, Cycle A — migration `0074` and the Dart seam.
///
/// The migration has not been applied anywhere and cannot be executed from a
/// widget test, so the database half of this suite reads the file, exactly as
/// the suites for `0069`, `0070`, `0071` and `0073` do. That limit is worth
/// stating: this proves the file says the right things, and the integration
/// suite run against a real database is what proves it does them.
///
/// Three rules are under test, and each of them is a rule a reader gets wrong:
/// a batch correction is ONE transaction and not a loop over the single-player
/// function; a match's lifecycle moves forward and never backwards; and a final
/// result belongs to a match that has actually been played.
void main() {
  const path = '../supabase/migrations/0074_all_state_match_management.sql';

  /// Line endings normalized, for the reason `0071`'s suite gives: `core
  /// .autocrlf` is true here and no `.gitattributes` rule covers `*.sql`, so a
  /// committed migration is checked out with CRLF while a new one is still LF.
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with SQL string literals blanked, so a `comment on` body cannot
  /// satisfy an assertion about executable text.
  final executable = statements
      .split('\n')
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  /// One function's own text, header through body.
  String bodyOf(String name) {
    final start = statements.indexOf('create or replace function public.$name');
    if (start < 0) throw StateError('0074 does not define $name');
    final end = statements.indexOf('\n\$\$;', start);
    return statements.substring(start, end == -1 ? statements.length : end);
  }

  group('the migration is 0074, and it is append-only', () {
    test('the file exists under the number the brief fixed', () {
      expect(File(path).existsSync(), isTrue);
    });

    test('exactly one migration file carries this number', () {
      final numbered = Directory('../supabase/migrations')
          .listSync()
          .map((entry) => entry.uri.pathSegments.last)
          .where((name) => name.startsWith('0074'))
          .toList();
      expect(numbered, hasLength(1));
    });

    test('it adds no schema and takes nothing away', () {
      // Append-only in the sense that matters: this migration replaces function
      // bodies and creates one, and touches no table, view, trigger or index.
      for (final forbidden in const [
        'alter table',
        'drop table',
        'drop view',
        'create table',
        'create trigger',
        'drop function',
        'drop index',
      ]) {
        expect(executable.toLowerCase(), isNot(contains(forbidden)),
            reason: forbidden);
      }
    });

    test('0073 is not disturbed', () {
      // Rating precision and the participation value belong to 0073. This
      // migration runs after it and says nothing about either.
      for (final token in const [
        'numeric(5,3)',
        'rating_history',
        'overall_rating',
        'apply_rating_delta',
        'PARTICIPATION',
      ]) {
        expect(statements, isNot(contains(token)), reason: token);
      }
    });

    test('0071 keeps its generation guard', () {
      // The completed-match generation guard lives in replace_match_lineup and
      // is relied on rather than redefined: regeneration stays forbidden after
      // completion, and explicit correction stays allowed.
      expect(
          statements, isNot(contains('function public.replace_match_lineup')));
    });

    test('the single-player RPC is kept for older clients', () {
      // Backward compatibility: set_completed_match_player is neither redefined
      // nor dropped here, so a deployed build that calls it still works.
      expect(statements,
          isNot(contains('function public.set_completed_match_player')));
    });

    test('Team of Period PFS v1 is not touched', () {
      for (final token in const [
        'period_form_score_v1',
        'period_goal_form_v1',
        'period_xi_required_matches',
      ]) {
        expect(statements, isNot(contains(token)), reason: token);
      }
    });
  });

  group('A1: the batch correction is one transaction', () {
    final body = bodyOf('correct_completed_match_players');
    final detach = body.indexOf('detach_match_effects');
    final attach = body.indexOf('attach_match_effects');

    test('it takes the whole batch as one payload', () {
      expect(body, contains('p_match_id uuid'));
      expect(body, contains('p_changes jsonb'));
    });

    test('it is security definer with a pinned search path', () {
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
    });

    test('it is not the single-player function in a loop', () {
      // The whole point of A1. Calling set_completed_match_player N times would
      // detach and reattach N times and leave K-1 corrections standing when
      // player K is refused.
      expect(body, isNot(contains('set_completed_match_player')));
    });

    test('the effects come apart once and go back together once', () {
      expect(RegExp('detach_match_effects').allMatches(body), hasLength(1));
      expect(RegExp('attach_match_effects').allMatches(body), hasLength(1));
      expect(detach, lessThan(body.indexOf('for v_change in')),
          reason: 'detached before the changes are applied');
      expect(body.indexOf('end loop;'), lessThan(attach),
          reason: 'reattached only after every change is applied');
    });

    test('every refusal is raised before anything is written', () {
      // A refused batch leaves no partial registration, assignment, rating or
      // statistic, and this is the property that makes that true.
      for (final token in const [
        'NOT_AUTHENTICATED',
        'ACCOUNT_SUSPENDED',
        'MATCH_NOT_FOUND',
        'COMMUNITY_INACTIVE',
        'NOT_AUTHORIZED',
        'MATCH_NOT_COMPLETED',
        'INVALID_CHANGES',
        'INVALID_TEAM',
        'INVALID_POSITION',
        'MEMBER_NOT_FOUND',
        'NOT_COMMUNITY_MEMBER',
      ]) {
        expect(body.indexOf("raise exception '$token'"), lessThan(detach),
            reason: '$token is refused before the first write');
        expect(body.indexOf("raise exception '$token'"), greaterThan(-1),
            reason: '$token is raised at all');
      }
    });

    test('the authorization order is the project convention', () {
      expect(body.indexOf('auth.uid() is null'),
          lessThan(body.indexOf('is_current_user_active')));
      expect(body.indexOf('is_current_user_active'),
          lessThan(body.indexOf('for update')));
      expect(body.indexOf('COMMUNITY_INACTIVE'),
          lessThan(body.indexOf('has_active_community_role')));
      expect(body.indexOf('has_active_community_role'),
          lessThan(body.indexOf("raise exception 'MATCH_NOT_COMPLETED'")));
    });

    test('correction is for a played match, by the authoritative rule', () {
      expect(body, contains("v_match.status <> 'completed'"));
      expect(body, contains('v_match.end_at > now()'));
    });

    test('a malformed payload and a doubled player are both INVALID_CHANGES',
        () {
      expect(body, contains("jsonb_typeof(p_changes) <> 'array'"));
      // Duplicates are counted rather than assumed away: the entries and the
      // distinct players have to be the same number, compared as uuids.
      expect(body, contains("count(distinct (e->>'user_id')::uuid)"));
      expect(body, contains('v_entries <> v_players'));
      expect(
          RegExp("raise exception 'INVALID_CHANGES'").allMatches(body).length,
          greaterThanOrEqualTo(3),
          reason: 'shape, element vocabulary and duplicates');
    });

    test('an empty batch is refused, and refused before anything is detached',
        () {
      // [] reaching detach/attach would reverse every rating the match produced
      // and recalculate it from an unchanged lineup: a fresh audit trail and no
      // correction to show for it.
      expect(body, contains('jsonb_array_length(p_changes) = 0'));
      expect(body.indexOf('jsonb_array_length(p_changes) = 0'),
          lessThan(detach));
    });

    test('duplicates are compared as uuids, not as the text they arrived in',
        () {
      // The same uuid in two cases is one player. Comparing the strings would
      // let a doubled entry past the only check meant to catch it.
      expect(body, contains("count(distinct (e->>'user_id')::uuid)"));
      expect(body.indexOf('!~*'),
          lessThan(body.indexOf("count(distinct (e->>'user_id')::uuid)")),
          reason: 'the malformed-uuid test runs first, so the cast is safe');
    });

    test('an UPSERT must name a valid side and position', () {
      expect(body, contains("not in ('A', 'B')"));
      expect(body, contains("not in ('GK', 'DEF', 'MID', 'FWD')"));
    });

    test('membership is required to be added and not to be removed', () {
      // A player who has left the community may still be wrongly recorded as
      // having played, and removing them is the correction — so the membership
      // test is scoped to UPSERT.
      final membership = body.indexOf('is_community_member');
      final scoped =
          body.lastIndexOf("upper(e->>'action') = 'UPSERT'", membership);
      expect(scoped, greaterThan(-1));
      expect(body.substring(scoped, membership), isNot(contains('end if;')),
          reason: 'the membership test sits inside the UPSERT-only predicate');
    });

    test('the basis is derived from the profile, never taken from the caller',
        () {
      expect(body, contains('u.primary_position'));
      expect(body, contains('u.secondary_position'));
      expect(body, contains("then 'PRIMARY'"));
      expect(body, contains("then 'SECONDARY'"));
      expect(body, contains("else 'TRANSITION'"));
      expect(body, isNot(contains("e->>'assignment_basis'")),
          reason: 'assignment_basis is not accepted from Flutter');
    });

    test('the result guard is asked once, about the projected final lineup',
        () {
      final guard = body.indexOf('assert_result_survives_lineup');
      expect(RegExp('assert_result_survives_lineup').allMatches(body),
          hasLength(1));
      expect(guard, lessThan(detach),
          reason: 'asked before anything is written');
      // The projection: who is in the lineup now, minus everyone the batch
      // mentions, plus everyone it upserts.
      expect(body, contains('from match_team_assignments a'));
      expect(body, contains("upper(e->>'action') = 'UPSERT'"));
      expect(body.indexOf('v_user_ids'), lessThan(guard));
      expect(body.indexOf('v_guest_ids'), lessThan(guard));
    });

    test('guests are carried into the projection and never modified', () {
      expect(body, contains('a.professional_guest_id is not null'));
      // Nothing in this function writes a guest row.
      expect(body, isNot(contains('update match_team_assignments')));
      expect(body, isNot(contains('match_professional_guests')));
      expect(body, isNot(contains('remove_professional_guest')));
    });

    test('a removal takes the lineup row and the roster seat together', () {
      expect(body, contains('delete from match_team_assignments'));
      expect(body, contains('delete from match_registrations'));
    });

    test('an upsert confirms a seat, creating one where there was none', () {
      expect(body, contains('insert into match_registrations'));
      expect(body, contains('coalesce(max(registration_order), 0) + 1'));
      expect(body, contains("status = 'confirmed'"));
      expect(
          body,
          contains(
              'on conflict (match_id, user_id) where user_id is not null'));
    });
  });

  group('A1 security: who may call it', () {
    test('authenticated only, and never anon or public', () {
      expect(
          statements,
          contains('revoke execute on function '
              'public.correct_completed_match_players(uuid, jsonb)\n'
              '  from anon, public;'));
      expect(
          statements,
          contains('grant execute on function '
              'public.correct_completed_match_players(uuid, jsonb)\n'
              '  to authenticated;'));
      expect(executable, isNot(contains('to anon')));
      expect(executable, isNot(contains('to public')));
    });

    test('it exposes no helper that was not already exposed', () {
      for (final helper in const [
        'detach_match_effects',
        'attach_match_effects',
        'assert_result_survives_lineup',
        'apply_match_rating_effects',
        'apply_match_statistics',
      ]) {
        expect(executable,
            isNot(contains('grant execute on function public.$helper')),
            reason: helper);
      }
    });

    test('it documents itself', () {
      expect(
          statements,
          contains(
              'comment on function public.correct_completed_match_players'));
    });
  });

  group('A2: the lifecycle moves forward only', () {
    final body = bodyOf('update_match');

    test('the original state is read from the locked row', () {
      // Asked of the row as it stands, before the new times are written —
      // otherwise the question would be asked of the answer.
      expect(
          body,
          contains(
              'select * into v_match from matches where id = p_match_id for update'));
      expect(
          body,
          contains(
              "v_played := v_match.status = 'completed' or v_match.end_at <= now();"));
      expect(
          body,
          contains(
              'v_was_active := not v_played and v_match.start_at <= now();'));
    });

    test('a completed match may not be reopened', () {
      // COMPLETED -> ACTIVE and COMPLETED -> FUTURE are the same request: an end
      // that has not happened yet.
      expect(body, contains('if v_played then'));
      expect(
          body,
          contains("if not v_becomes_completed then "
              "raise exception 'MATCH_COMPLETED'; end if;"));
    });

    test('a started match may not be returned to the schedule', () {
      expect(body, contains('elsif v_was_active then'));
      // Staying active and ending are both forward moves; only a start in the
      // future would put a match that has kicked off back on the schedule.
      expect(body,
          contains('if not (v_becomes_completed or v_becomes_active) then'));
      expect(body, contains("raise exception 'MATCH_LOCKED'"));
    });

    test('the guard runs after the times are validated and before the write',
        () {
      final range = body.indexOf("raise exception 'INVALID_TIME_RANGE'");
      final guard = body.indexOf('if v_played then');
      final write = body.indexOf('update matches set');
      expect(range, lessThan(guard));
      expect(guard, lessThan(write));
    });

    test('every field stays editable, in every state, without a limit', () {
      for (final field in const [
        'title = trim(p_title)',
        'location = trim(p_location)',
        'start_at = p_start_at',
        'end_at = p_end_at',
        'starting_players = p_starting_players',
        'description =',
      ]) {
        expect(body, contains(field), reason: field);
      }
      // No gate counts edits or refuses a second one.
      expect(body, isNot(contains('edit_count')));
      expect(statements, isNot(contains('MATCH_EDIT_LIMIT')));
    });

    test('the preserved rules are still preserved', () {
      for (final rule in const [
        "raise exception 'NOT_AUTHENTICATED'",
        'is_current_user_active',
        'has_active_community_role',
        "raise exception 'INVALID_TITLE'",
        "raise exception 'INVALID_STARTING_PLAYERS'",
        "raise exception 'MAX_BELOW_REGISTERED'",
        'create_notification',
      ]) {
        expect(body, contains(rule), reason: rule);
      }
      expect(
          body, contains('p_starting_players < 4 or p_starting_players > 30'));
    });

    test('the resulting state is derived from the new times', () {
      // The original state decides which transitions are allowed; the resulting
      // state decides what happens to the roster. Two questions, two flags.
      expect(body, contains('v_becomes_completed := p_end_at <= now();'));
      expect(
          body,
          contains('v_becomes_active := not v_becomes_completed '
              'and p_start_at <= now();'));
    });

    test('the roster is re-cut only where the match is still a plan', () {
      // The defect this replaces: keying the post-update branch on the ORIGINAL
      // state rebalanced an active match, a future match corrected into an
      // active one, and a future match entered as a record of one already
      // played. Once the resulting state is active or completed, editing the
      // details must not promote, demote or rewrite participation.
      expect(RegExp('rebalance_roster').allMatches(body), hasLength(1));
      expect(RegExp('recompute_match_status').allMatches(body), hasLength(1));

      final completed = body.indexOf('if v_becomes_completed then');
      final active = body.indexOf('elsif v_becomes_active then', completed);
      final future = body.indexOf('  else\n', active);
      expect(completed, greaterThan(body.indexOf('update matches set\n')),
          reason: 'the decision is made after the fields are written');
      expect(active, greaterThan(completed));
      expect(future, greaterThan(active));

      // RESULTING COMPLETED: settle the stored status, touch nothing else.
      final completedBranch = body.substring(completed, active);
      expect(completedBranch, contains("update matches set status = 'completed'"));
      // RESULTING ACTIVE: do nothing at all.
      final activeBranch = body.substring(active, future);
      expect(activeBranch, contains('null;'));
      expect(activeBranch, isNot(contains('update matches')),
          reason: 'a match in progress keeps the status it has');
      // Neither may re-cut the roster, the status or the stored lineup.
      for (final behaviour in const [
        'rebalance_roster',
        'recompute_match_status',
        'reconcile_match_lineup',
        'replace_match_lineup',
        'match_team_assignments',
      ]) {
        expect(completedBranch, isNot(contains(behaviour)),
            reason: '$behaviour must not run for a completed match');
        expect(activeBranch, isNot(contains(behaviour)),
            reason: '$behaviour must not run for a match in progress');
      }

      // RESULTING FUTURE: the ordinary behaviour, exactly as before.
      final futureBranch = body.substring(future);
      expect(futureBranch, contains('perform rebalance_roster(p_match_id);'));
      expect(
          futureBranch, contains('perform recompute_match_status(p_match_id);'));
    });

    test('the old-state flag no longer decides the roster', () {
      // v_played still decides which transitions are allowed, and nothing else.
      final decision = body.indexOf('if v_becomes_completed then');
      expect(body.indexOf('if v_played then'), lessThan(decision),
          reason: 'the original state is used for the guard, above');
      expect(body.substring(decision), isNot(contains('v_played')),
          reason: 'and never again below it');
    });
  });

  group('A3: a result belongs to a played match', () {
    final body = bodyOf('record_match_result');
    final guard = body.indexOf("raise exception 'MATCH_NOT_COMPLETED'");

    test('the locked row is read so its state can be tested', () {
      expect(
          body,
          contains(
              'select * into v_match from matches where id = p_match_id for update'));
    });

    test('an unplayed match is refused with the existing token', () {
      expect(guard, greaterThan(-1));
      expect(body, contains("v_match.status <> 'completed'"));
      expect(body, contains('v_match.end_at > now()'));
    });

    test('it is refused after authorization and before every mutation', () {
      expect(body.indexOf("raise exception 'NOT_AUTHORIZED'"), lessThan(guard));
      for (final mutation in const [
        'reverse_match_rating_effects',
        'apply_match_statistics',
        'delete from match_goals',
        'insert into match_results',
        'insert into match_goals',
        'apply_match_rating_effects',
      ]) {
        expect(guard, lessThan(body.indexOf(mutation)),
            reason: 'nothing is $mutation before the guard');
      }
    });

    test('after completion the result may be corrected without limit', () {
      // The same reverse-then-reapply as before, and an upsert rather than an
      // insert, which is what makes repeated edits work.
      expect(body, contains('on conflict (match_id) do update set'));
      expect(body.indexOf('reverse_match_rating_effects'),
          lessThan(body.indexOf('insert into match_results')));
      expect(body.indexOf('insert into match_goals'),
          lessThan(body.indexOf('apply_match_rating_effects')));
    });

    test('no provisional score and no new result state are introduced', () {
      for (final token in const [
        'provisional',
        'live_score',
        'is_final',
        'result_state',
      ]) {
        // `executable` rather than `statements`: the function's own comment
        // body says there is no provisional score, and prose must not satisfy
        // an assertion about executable text.
        expect(executable.toLowerCase(), isNot(contains(token)), reason: token);
      }
    });
  });

  group('0075: a played guest is a factual correction', () {
    const guestPath =
        '../supabase/migrations/0075_completed_professional_guest_correction.sql';
    final guestSql =
        File(guestPath).readAsStringSync().replaceAll('\r\n', '\n');
    final guestStatements = guestSql
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');
    final guestExecutable = guestStatements
        .split('\n')
        .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
        .join('\n');
    final guestBody = () {
      final start = guestStatements
          .indexOf('create or replace function public.add_played_professional_guest');
      if (start < 0) throw StateError('0075 defines no such function');
      final end = guestStatements.indexOf('\n\$\$;', start);
      return guestStatements.substring(
          start, end == -1 ? guestStatements.length : end);
    }();

    test('the file exists once, under the number the brief fixed', () {
      expect(File(guestPath).existsSync(), isTrue);
      final numbered = Directory('../supabase/migrations')
          .listSync()
          .map((entry) => entry.uri.pathSegments.last)
          .where((name) => name.startsWith('0075'))
          .toList();
      expect(numbered, hasLength(1));
    });

    test('it is append-only, and leaves 0074 alone', () {
      for (final forbidden in const [
        'alter table',
        'drop table',
        'drop view',
        'create table',
        'create trigger',
        'drop function',
        'drop index',
      ]) {
        expect(guestExecutable.toLowerCase(), isNot(contains(forbidden)),
            reason: forbidden);
      }
      // The community-player correction, the lifecycle guard and the result
      // guard are 0074's and are not touched.
      for (final untouched in const [
        'function public.correct_completed_match_players',
        'function public.update_match',
        'function public.record_match_result',
        'function public.add_professional_guest',
        'function public.remove_professional_guest',
        'function public.remove_played_professional_guest',
      ]) {
        expect(guestStatements, isNot(contains(untouched)), reason: untouched);
      }
    });

    test('it is security definer, pinned, and authenticated-only', () {
      expect(guestBody, contains('security definer'));
      expect(guestBody, contains('set search_path = public'));
      expect(
          guestStatements,
          contains('revoke execute on function\n'
              '  public.add_played_professional_guest(uuid, text, text, text)\n'
              '  from anon, public;'));
      expect(
          guestStatements,
          contains('grant execute on function\n'
              '  public.add_played_professional_guest(uuid, text, text, text)\n'
              '  to authenticated;'));
      expect(guestExecutable, isNot(contains('to anon')));
      expect(guestStatements,
          contains('comment on function public.add_played_professional_guest'));
    });

    test('it takes the name, the side and the position, and returns the id', () {
      expect(guestBody, contains('p_match_id uuid'));
      expect(guestBody, contains('p_name text'));
      expect(guestBody, contains('p_team text'));
      expect(guestBody, contains('p_assigned_position text'));
      expect(guestBody, contains('returns uuid'));
      expect(guestBody, contains('return v_guest_id;'));
    });

    test('only a played match, and only an organizer of an active community',
        () {
      expect(guestBody, contains("raise exception 'NOT_AUTHENTICATED'"));
      expect(guestBody, contains('is_current_user_active'));
      expect(guestBody, contains('for update'));
      expect(guestBody, contains("raise exception 'MATCH_NOT_FOUND'"));
      expect(guestBody, contains("raise exception 'COMMUNITY_INACTIVE'"));
      expect(guestBody, contains('has_active_community_role'));
      expect(guestBody, contains("v_match.status <> 'completed'"));
      expect(guestBody, contains("raise exception 'MATCH_NOT_COMPLETED'"));
    });

    test('the name, the side and the position are all validated', () {
      expect(guestBody, contains("raise exception 'INVALID_GUEST_NAME'"));
      expect(guestBody, contains('char_length(trim(p_name)) < 2'));
      expect(guestBody, contains('char_length(trim(p_name)) > 60'));
      expect(guestBody, contains("p_team not in ('A', 'B')"));
      expect(guestBody, contains("raise exception 'INVALID_TEAM'"));
      expect(guestBody,
          contains("p_assigned_position not in ('GK', 'DEF', 'MID', 'FWD')"));
      expect(guestBody, contains("raise exception 'INVALID_POSITION'"));
    });

    test('every refusal comes before the first row is written', () {
      final firstWrite = guestBody.indexOf('insert into');
      for (final token in const [
        'NOT_AUTHENTICATED',
        'ACCOUNT_SUSPENDED',
        'MATCH_NOT_FOUND',
        'COMMUNITY_INACTIVE',
        'NOT_AUTHORIZED',
        'MATCH_NOT_COMPLETED',
        'INVALID_GUEST_NAME',
        'INVALID_TEAM',
        'INVALID_POSITION',
      ]) {
        final at = guestBody.indexOf("raise exception '$token'");
        expect(at, greaterThan(-1), reason: '$token is raised');
        expect(at, lessThan(firstWrite),
            reason: '$token is refused before anything is inserted');
      }
    });

    test('the recorded side is marked as chosen, so nothing may alternate it',
        () {
      // `assign_professional_guest_teams` (0058) moves guests whose side was
      // never chosen, and it reads this flag to know which those are. A side
      // entered as historical fact must therefore say it was chosen, or a later
      // lineup write could alternate a recorded Team B guest onto Team A.
      expect(guestBody, contains('team_manually_overridden'));
      expect(
          guestBody,
          contains("values (p_match_id, v_guest_id, p_team, "
              "p_assigned_position, 'GUEST', true);"));
      // And the flag is written by this function rather than left to the column
      // default, which is false.
      expect(
          guestBody.indexOf('team_manually_overridden'),
          lessThan(guestBody.indexOf("'GUEST', true)")),
          reason: 'named in the column list, then given its value');
    });

    test('it neither redefines nor calls the guest placement it protects', () {
      // 0058 and its function stay exactly as they are: this migration opts out
      // of alternation rather than changing how alternation works.
      expect(guestStatements,
          isNot(contains('function public.assign_professional_guest_teams')));
      expect(guestBody, isNot(contains('assign_professional_guest_teams')));
    });

    test('it writes the guest, a confirmed seat and the factual lineup row', () {
      expect(guestBody, contains('insert into match_professional_guests'));
      expect(guestBody, contains('insert into match_registrations'));
      expect(guestBody, contains('insert into match_team_assignments'));
      expect(guestBody, contains("'confirmed'"));
      expect(guestBody, contains('coalesce(max(registration_order), 0) + 1'));
      expect(guestBody, contains("'GUEST'"),
          reason: 'the basis a participant with no profile gets (0044)');
      // The lineup row is the one the roster path never wrote.
      expect(guestBody.indexOf('insert into match_professional_guests'),
          lessThan(guestBody.indexOf('insert into match_team_assignments')));
    });

    test('it applies no roster behaviour and moves no rating', () {
      // The whole reason it is not the roster function: none of this may run on
      // a match that has been played, and a guest owns no rating or statistic.
      for (final forbidden in const [
        'rebalance_roster',
        'recompute_match_status',
        'detach_match_effects',
        'attach_match_effects',
        'apply_match_rating_effects',
        'reverse_match_rating_effects',
        'apply_match_statistics',
        'apply_rating_delta',
        'create_notification',
        'max_registration',
        'add_professional_guest',
        "'reserve'",
      ]) {
        expect(guestBody, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('it leaves the result alone', () {
      for (final untouched in const [
        'match_results',
        'match_goals',
        'mvp_user_id',
      ]) {
        expect(guestBody, isNot(contains(untouched)), reason: untouched);
      }
    });
  });

  group('the completed-guest seam in Dart', () {
    test('the repository hands the batch-free call straight through', () async {
      final adapter = _GuestAdapter();

      final id = await TeamRepository(adapter).addPlayedProfessionalGuest(
        'm1',
        'Faisal',
        team: TeamId.b,
        position: Position.fwd,
      );

      expect(id, 'g-new', reason: 'the new guest id reaches the caller');
      expect(adapter.calls, 1);
      expect(adapter.matchId, 'm1');
      expect(adapter.name, 'Faisal');
      expect(adapter.team, TeamId.b);
      expect(adapter.position, Position.fwd);
    });

    test('the Supabase adapter sends one RPC, with the wire vocabulary', () {
      final source =
          File('lib/infrastructure/supabase/supabase_team_adapter.dart')
              .readAsStringSync();
      final start = source.indexOf('Future<String> addPlayedProfessionalGuest');
      expect(start, greaterThan(-1));
      final method = source.substring(start, source.indexOf('      });', start));

      expect(RegExp("_client.rpc\\('add_played_professional_guest'")
              .allMatches(method),
          hasLength(1));
      for (final param in const [
        "'p_match_id': matchId",
        "'p_name': name",
        "'p_team': teamToDb(team)",
        "'p_assigned_position': positionToDb(position)",
      ]) {
        expect(method, contains(param), reason: param);
      }
      expect(method, contains('guarded('));
      expect(method, isNot(contains('add_professional_guest(')),
          reason: 'the roster function is not what this calls');
    });

    test('the older guest operations are still there', () {
      final port =
          File('lib/features/teams/team_adapter.dart').readAsStringSync();
      for (final method in const [
        'removePlayedProfessionalGuest',
        'addPlayedProfessionalGuest',
      ]) {
        expect(port, contains(method), reason: method);
      }
      // And the roster's own guest add still lives where it always did.
      expect(File('lib/features/matches/match_service.dart').readAsStringSync(),
          contains('addProfessionalGuest'));
    });
  });

  group('both profile positions reach the picker', () {
    test('the mapper reads the secondary position, and tolerates its absence',
        () {
      final member = communityMemberFromRow(const {
        'role': 'player',
        'user': {
          'id': 'u5',
          'full_name': 'Layla Al Riyami',
          'primary_position': 'MID',
          'secondary_position': 'DEF',
          'avatar_path': null,
        },
      });
      expect(member.position, 'MID');
      expect(member.secondaryPosition, 'DEF');

      final single = communityMemberFromRow(const {
        'role': 'player',
        'user': {
          'id': 'u6',
          'full_name': 'Maha Al Saidi',
          'primary_position': 'GK',
          'secondary_position': null,
          'avatar_path': null,
        },
      });
      expect(single.position, 'GK');
      expect(single.secondaryPosition, isNull,
          reason: 'a profile may name one position and stop');
    });

    test('the member query asks the database for it', () {
      final source =
          File('lib/infrastructure/supabase/supabase_member_adapter.dart')
              .readAsStringSync();
      expect(source, contains('secondary_position'));
      expect(source, contains('primary_position'));
    });

    test('the sheet shows both and decides nothing from them', () {
      final source =
          File('lib/features/teams/played_participants_sheet.dart')
              .readAsStringSync();
      // Both are rendered...
      expect(source, contains('member.secondaryPosition'));
      expect(source, contains('positionLabel(member.position)'));
      // ...and neither is ever assigned into what the organizer must answer.
      expect(source, isNot(contains('team = member')));
      expect(source, isNot(contains('position = member')));
      expect(source, isNot(contains('_PlayedAssignment(member')));
    });
  });

  group('the Dart domain model', () {
    test('a player who played carries a side and a position', () {
      const correction = CompletedPlayerCorrection.played(
        'u1',
        team: TeamId.a,
        position: Position.mid,
      );

      expect(correction.userId, 'u1');
      expect(correction.action, CompletedPlayerAction.upsert);
      expect(correction.team, TeamId.a);
      expect(correction.position, Position.mid);
    });

    test('a player who did not play carries neither', () {
      const correction = CompletedPlayerCorrection.removed('u2');

      expect(correction.action, CompletedPlayerAction.remove);
      expect(correction.team, isNull);
      expect(correction.position, isNull);
    });
  });

  group('the wire shape', () {
    test('an UPSERT says the side and the position in the database vocabulary',
        () {
      expect(
        completedPlayerCorrectionToRow(const CompletedPlayerCorrection.played(
          'u1',
          team: TeamId.b,
          position: Position.gk,
        )),
        {
          'user_id': 'u1',
          'action': 'UPSERT',
          'team': 'B',
          'assigned_position': 'GK',
        },
      );
    });

    test('a REMOVE says only who', () {
      expect(
        completedPlayerCorrectionToRow(
            const CompletedPlayerCorrection.removed('u2')),
        {'user_id': 'u2', 'action': 'REMOVE'},
      );
    });

    test('the basis is never sent', () {
      // §5.1: which rule produced the position is a fact about the profile, so
      // the database derives it and a client claim about it would be ignored.
      for (final correction in const [
        CompletedPlayerCorrection.played('u1',
            team: TeamId.a, position: Position.fwd),
        CompletedPlayerCorrection.removed('u2'),
      ]) {
        expect(completedPlayerCorrectionToRow(correction).keys,
            isNot(contains('assignment_basis')));
      }
    });
  });

  group('the repository and the adapter', () {
    test('one batch crosses the boundary as one call', () async {
      final adapter = _BatchAdapter();
      const corrections = [
        CompletedPlayerCorrection.played('u1',
            team: TeamId.a, position: Position.mid),
        CompletedPlayerCorrection.played('u2',
            team: TeamId.b, position: Position.def),
        CompletedPlayerCorrection.removed('u3'),
      ];

      await TeamRepository(adapter).correctCompletedPlayers('m1', corrections);

      expect(adapter.calls, 1, reason: 'not one call per player');
      expect(adapter.matchId, 'm1');
      expect(adapter.corrections, corrections);
    });

    test('the Supabase adapter sends the batch in a single RPC', () {
      // Read as source because a live client is what the integration suite
      // brings: what matters here is that the implementation holds no loop over
      // the per-player functions.
      final source =
          File('lib/infrastructure/supabase/supabase_team_adapter.dart')
              .readAsStringSync();
      final start = source.indexOf('Future<void> correctCompletedPlayers');
      expect(start, greaterThan(-1));
      final method =
          source.substring(start, source.indexOf('      });', start));

      expect(
          RegExp("_client.rpc\\('correct_completed_match_players'")
              .allMatches(method),
          hasLength(1));
      expect(method, contains('completedPlayerCorrectionToRow'));
      expect(method, isNot(contains('set_completed_match_player')));
      expect(method, contains('guarded('),
          reason: 'failures map through the existing mapper');
    });

    test('the older per-player operations are still there', () {
      // Backward compatibility: this cycle adds a path and removes none.
      final port =
          File('lib/features/teams/team_adapter.dart').readAsStringSync();
      for (final method in const [
        'addPlayedPlayer',
        'removePlayedPlayer',
        'correctCompletedPlayers',
      ]) {
        expect(port, contains(method), reason: method);
      }
    });

    test('exactly one screen calls the batch, and calls it once', () {
      // Cycle A built the path and left it unused; Cycle B wires it to the
      // Teams screen, which is the canonical surface for correcting who played.
      // One call site, because the batch is the whole intent of one save -- a
      // second would be a loop wearing a different name.
      final teams =
          File('lib/features/teams/teams_screen.dart').readAsStringSync();
      expect(RegExp('correctCompletedPlayers').allMatches(teams), hasLength(1));

      // And nowhere else: the roster screens administer a roster, which is a
      // different question from who actually played.
      for (final screen in const [
        'lib/features/matches/match_details_screen.dart',
        'lib/features/matches/manage_roster_screen.dart',
        'lib/features/matches/match_management_screen.dart',
      ]) {
        expect(File(screen).readAsStringSync(),
            isNot(contains('correctCompletedPlayers')),
            reason: screen);
      }
    });
  });
}

/// Only the batch correction is exercised through this, so everything else is
/// deliberately unimplemented.
class _BatchAdapter implements TeamAdapter {
  int calls = 0;
  String? matchId;
  List<CompletedPlayerCorrection>? corrections;

  @override
  Future<void> correctCompletedPlayers(
    String matchId,
    List<CompletedPlayerCorrection> corrections,
  ) async {
    calls += 1;
    this.matchId = matchId;
    this.corrections = corrections;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('only the batch correction is used here');
}

/// Only the completed-guest correction is exercised through this.
class _GuestAdapter implements TeamAdapter {
  int calls = 0;
  String? matchId;
  String? name;
  TeamId? team;
  Position? position;

  @override
  Future<String> addPlayedProfessionalGuest(
    String matchId,
    String name, {
    required TeamId team,
    required Position position,
  }) async {
    calls += 1;
    this.matchId = matchId;
    this.name = name;
    this.team = team;
    this.position = position;
    return 'g-new';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('only the guest correction is used here');
}
