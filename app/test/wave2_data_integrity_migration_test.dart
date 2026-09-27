import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path = '../supabase/migrations/0088_wave2_data_integrity.sql';
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  String tableBody(String name) {
    final start = statements.indexOf('create table public.$name (');
    if (start < 0) throw StateError('$name is not created');
    final end = statements.indexOf('\n);', start);
    if (end < 0) throw StateError('$name table body is not closed');
    return statements.substring(start, end);
  }

  String functionBody(String name) {
    final start = statements.indexOf('create or replace function public.$name');
    if (start < 0) throw StateError('$name is not created');
    final end = statements.indexOf('\n\$\$;', start);
    return statements.substring(start, end == -1 ? statements.length : end);
  }

  group('Wave 2 schema is additive evidence', () {
    test('0088 is unique', () {
      final numbered = Directory('../supabase/migrations')
          .listSync()
          .map((entry) => entry.uri.pathSegments.last)
          .where((name) => name.startsWith('0088'))
          .toList();
      expect(numbered, hasLength(1));
      expect(File(path).existsSync(), isTrue);
    });

    test('creates exactly the two lifecycle logs and one participation state',
        () {
      final created = RegExp(r'create table public\.([a-z_]+) \(')
          .allMatches(statements)
          .map((m) => m.group(1))
          .toSet();
      expect(
        created,
        {
          'match_registration_events',
          'community_membership_events',
          'match_participation_state',
        },
      );
    });

    test('contains no historical data backfill', () {
      expect(statements, isNot(contains('generate_series')));
      expect(
          statements,
          isNot(contains(
              'insert into public.match_registration_events\nselect')));
      expect(
          statements,
          isNot(contains(
              'insert into public.community_membership_events\nselect')));
      expect(
          statements,
          isNot(contains(
              'insert into public.match_participation_state\nselect')));
    });
  });

  group('lifecycle evidence cannot be erased with current-state rows', () {
    test('registration events have no business-table foreign key', () {
      final body = tableBody('match_registration_events');
      expect(body, isNot(contains('references public.matches')));
      expect(body, isNot(contains('references public.users')));
      expect(body, isNot(contains('references public.communities')));
    });

    test('membership events have no business-table foreign key', () {
      final body = tableBody('community_membership_events');
      expect(body, isNot(contains('references public.users')));
      expect(body, isNot(contains('references public.communities')));
    });

    test('both lifecycle tables are RLS closed to client roles', () {
      for (final table in [
        'match_registration_events',
        'community_membership_events',
      ]) {
        expect(
          statements,
          contains('alter table public.$table enable row level security;'),
        );
        expect(
          statements,
          contains(
              'revoke all on table public.$table from anon, authenticated;'),
        );
      }
      expect(statements, isNot(contains('create policy')));
    });
  });

  group('registration lifecycle capture', () {
    final body = functionBody('capture_match_registration_event');

    test('records account participants only', () {
      expect(body, contains('if new.user_id is null then return new;'));
      expect(body, contains('if old.user_id is null then return old;'));
    });

    test('records creation, status movement and deletion', () {
      expect(body, contains("v_operation := 'created';"));
      expect(body, contains("v_operation := 'status_changed';"));
      expect(body, contains("v_operation := 'deleted';"));
      expect(
        body,
        contains(
            'new.user_id is null or new.status is not distinct from old.status'),
      );
    });

    test('captures actor and completion context from the database', () {
      expect(body, contains('auth.uid()'));
      expect(body, contains("(m.status = 'completed' or m.end_at <= now())"));
    });
  });

  group('membership lifecycle capture', () {
    final body = functionBody('capture_community_membership_event');

    test('records join, role change and deletion only', () {
      expect(body, contains("'joined'"));
      expect(body, contains("'role_changed'"));
      expect(body, contains("'deleted'"));
      expect(
        body,
        contains('new.role is not distinct from old.role'),
      );
    });

    test('takes the actor from the authenticated request', () {
      expect(body, contains('auth.uid()'));
    });
  });

  group('participation truth has one participant source', () {
    final state = tableBody('match_participation_state');
    final revision = functionBody('advance_match_participation_revision');
    final confirm = functionBody('confirm_match_participation');

    test('the state table stores revisions, not player identities', () {
      expect(state, contains('lineup_revision bigint'));
      expect(state, contains('confirmed_revision bigint'));
      expect(state, isNot(contains('user_id')));
      expect(state, isNot(contains('professional_guest_id')));
    });

    test('only match_team_assignments advances the lineup revision', () {
      expect(
        statements,
        contains(
            'after insert or update or delete on public.match_team_assignments'),
      );
      expect(
        revision,
        contains('public.match_participation_state.lineup_revision + 1'),
      );
    });

    test('completed organizer corrections confirm their resulting revision',
        () {
      expect(
        revision,
        contains("(v_status = 'completed' or v_end_at <= now())"),
      );
      expect(revision, contains('public.has_active_community_role('));
      expect(revision, contains('confirmed_revision = v_revision'));
    });

    test('explicit confirmation is organizer-only and completed-only', () {
      expect(confirm, contains("raise exception 'NOT_AUTHENTICATED'"));
      expect(confirm, contains('public.is_current_user_active()'));
      expect(confirm, contains('public.has_active_community_role('));
      expect(confirm, contains("raise exception 'MATCH_NOT_COMPLETED'"));
      expect(confirm, contains("raise exception 'LINEUP_REQUIRED'"));
    });

    test('explicit confirmation changes no football business row', () {
      for (final forbidden in [
        'update public.matches',
        'update public.match_team_assignments',
        'insert into public.match_team_assignments',
        'update public.match_results',
        'insert into public.match_results',
        'update public.users',
        'update public.player_statistics',
        'update public.community_statistics',
        'insert into public.rating_history',
      ]) {
        expect(confirm, isNot(contains(forbidden)));
      }
      expect(confirm, contains('update public.match_participation_state'));
    });

    test('client roles cannot touch participation state directly', () {
      expect(
        statements,
        contains(
            'alter table public.match_participation_state enable row level security;'),
      );
      expect(
        statements,
        contains(
            'revoke all on table public.match_participation_state from anon, authenticated;'),
      );
      expect(
        statements,
        contains(
            'revoke execute on function public.confirm_match_participation(uuid)\n  from public, anon;'),
      );
      expect(
        statements,
        contains(
            'grant execute on function public.confirm_match_participation(uuid)\n  to authenticated, service_role;'),
      );
    });
  });
}
