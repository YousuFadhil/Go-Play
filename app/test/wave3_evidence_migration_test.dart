import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static contract for migration 0089 (Wave 3 evidence capture).
///
/// The migration is reviewed before it is applied to the shared live project,
/// so what it may and may not do is pinned here against the file itself.
void main() {
  const path = '../supabase/migrations/0089_wave3_evidence_capture.sql';
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');

  // Comment lines stripped: the prose may name what the SQL refuses to do.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  // Whitespace collapsed, so a multi-line statement can be asserted whole.
  final flat = statements.replaceAll(RegExp(r'\s+'), ' ');

  String tableBody(String name) {
    final start = statements.indexOf('create table public.$name (');
    if (start < 0) throw StateError('$name is not created');
    final end = statements.indexOf('\n);', start);
    if (end < 0) throw StateError('$name table body is not closed');
    return statements.substring(start, end);
  }

  String functionBody(String name) {
    final start =
        statements.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('$name is not created');
    final end = statements.indexOf('\n\$\$;', start);
    if (end < 0) throw StateError('$name body is not closed');
    return statements.substring(start, end);
  }

  String flatFunction(String name) =>
      functionBody(name).replaceAll(RegExp(r'\s+'), ' ');

  Set<String> parametersOf(String name) {
    final body = functionBody(name);
    final open = body.indexOf('(');
    final close = body.indexOf(')\nreturns');
    return RegExp(r'\b(p_[a-z_]+)\b')
        .allMatches(body.substring(open, close))
        .map((m) => m.group(1)!)
        .toSet();
  }

  test('0089 is the one Wave 3 migration', () {
    final numbered = Directory('../supabase/migrations')
        .listSync()
        .map((entry) => entry.uri.pathSegments.last)
        .where((name) => name.startsWith('0089'))
        .toList();
    expect(numbered, ['0089_wave3_evidence_capture.sql']);

    // The Supabase CLI's timestamp name was reconciled, not kept beside it.
    final timestamped = Directory('../supabase/migrations')
        .listSync()
        .map((entry) => entry.uri.pathSegments.last)
        .where((name) => RegExp(r'^\d{14}_').hasMatch(name));
    expect(timestamped, isEmpty);
  });

  group('BTGE generation evidence', () {
    test('creates exactly one table, the evidence table', () {
      final created = RegExp(r'create table public\.([a-z_]+) \(')
          .allMatches(statements)
          .map((m) => m.group(1))
          .toSet();
      expect(created, {'btge_generation_runs'});
    });

    test('has the approved columns and a per-match sequence key', () {
      final body = tableBody('btge_generation_runs');
      for (final column in [
        'id uuid primary key default gen_random_uuid()',
        'match_id uuid not null',
        'community_id uuid not null',
        'generated_by uuid not null',
        'generation_sequence bigint not null',
        'generated_at timestamptz not null default now()',
        'variant_index integer not null',
        'configuration jsonb not null',
        'player_inputs jsonb not null',
        'history_context jsonb not null',
        'generated_lineup jsonb not null',
      ]) {
        expect(body, contains(column));
      }
      expect(flat, contains('unique (match_id, generation_sequence)'));
    });

    test('has no foreign key to any business table', () {
      expect(tableBody('btge_generation_runs'), isNot(contains('references')));
      // The SQL forms only: the table comment says "No foreign keys" in prose,
      // and `references` is also a privilege name in the revoke list.
      expect(flat, isNot(contains('foreign key (')));
      expect(RegExp(r'references\s+public\.').hasMatch(flat), isFalse);
    });

    test('is RLS-closed to every client role, with no policy', () {
      expect(
        flat,
        contains(
            'alter table public.btge_generation_runs enable row level security;'),
      );
      expect(
        flat,
        contains('revoke all on table public.btge_generation_runs '
            'from anon, authenticated, public;'),
      );
      expect(flat, isNot(contains('create policy')));
      expect(
        RegExp(r'grant [^;]* on table public\.btge_generation_runs to [^;]*'
                r'(anon|authenticated|public)')
            .hasMatch(flat),
        isFalse,
      );
      // service_role reads; nothing updates or deletes evidence.
      expect(
        flat,
        contains(
            'grant select on table public.btge_generation_runs to service_role;'),
      );
    });

    test('stores no derived BTGE quality or diagnostic metric', () {
      for (final metric in [
        'position_distribution_score',
        'rating_delta',
        'rating_delta_total',
        'out_of_position_count',
        'out_of_position_cost',
        'out_of_position_imbalance',
        'age_delta',
        'age_split_imbalance',
        'repeat_pair_count',
        'elapsed_ms',
        'candidates_evaluated',
        'equally_optimal_solutions',
        'solution_count',
      ]) {
        expect(statements, isNot(contains(metric)), reason: metric);
      }
    });

    test('player inputs are exactly the five minimal fields', () {
      final body = flatFunction('save_generated_lineup_v1');
      expect(
        body,
        contains("array[ 'age_at_match', 'overall_rating', 'primary_position', "
            "'secondary_position', 'user_id' ]"),
      );
      for (final personal in [
        'full_name',
        'date_of_birth',
        'email',
        'phone',
        'avatar',
        'raw_user_meta_data',
      ]) {
        expect(statements, isNot(contains(personal)), reason: personal);
      }
    });

    test('professional guests cannot be captured as BTGE inputs', () {
      final body = flatFunction('save_generated_lineup_v1');
      expect(body, contains("if v_element ? 'professional_guest_id' then"));
      expect(
        body,
        contains("array['assigned_position', 'assignment_basis', 'team', "
            "'user_id']"),
      );
      // A guest id placed in user_id is refused too: guests have no users row.
      expect(body, contains('from public.users u'));
      expect(body, contains("raise exception 'INVALID_GENERATION_EVIDENCE'"));
    });

    test('generated and input user ids must match exactly, without duplicates',
        () {
      final body = flatFunction('save_generated_lineup_v1');
      expect(body, contains('count(distinct x) from unnest(v_lineup_ids)'));
      expect(body, contains('count(distinct x) from unnest(v_input_ids)'));
      expect(
        body,
        contains('v_lineup_ids @> v_input_ids and v_input_ids @> v_lineup_ids'),
      );
    });

    test('saves through the existing authoritative lineup writer', () {
      final body = flatFunction('save_generated_lineup_v1');
      expect(
        body,
        contains('perform public.replace_match_lineup( p_match_id, '
            'p_generated_lineup, true, false );'),
      );
      // The legacy writer itself is not touched.
      expect(
          statements, isNot(contains('function public.replace_match_lineup(')));
      expect(flat, isNot(contains('on function public.replace_match_lineup')));
    });

    test('lineup save and evidence insert are one transaction', () {
      final body = flatFunction('save_generated_lineup_v1');
      final save = body.indexOf('perform public.replace_match_lineup(');
      final insert = body.indexOf('insert into public.btge_generation_runs');
      expect(save, greaterThan(0));
      expect(insert, greaterThan(save));
      // Nothing is committed part-way and no failure is swallowed.
      expect(body, isNot(contains('commit')));
      expect(body, isNot(contains('exception when')));
      expect(body, isNot(contains('dblink')));
    });

    test('the server derives actor, community and sequence', () {
      final body = flatFunction('save_generated_lineup_v1');
      expect(body, contains('v_actor uuid := auth.uid();'));
      expect(body, contains('v_match.community_id'));
      expect(
        body,
        contains('select coalesce(max(r.generation_sequence), 0) + 1 '
            'into v_sequence'),
      );
      expect(
        body,
        contains('values ( p_match_id, v_match.community_id, v_actor, '
            'v_sequence,'),
      );
      expect(parametersOf('save_generated_lineup_v1'), {
        'p_match_id',
        'p_generated_lineup',
        'p_variant_index',
        'p_configuration',
        'p_player_inputs',
        'p_history_context',
      });
    });

    test('authorizes owner/admin of an active, uncompleted match', () {
      final body = flatFunction('save_generated_lineup_v1');
      expect(body, contains("raise exception 'NOT_AUTHENTICATED'"));
      expect(body, contains('if not public.is_current_user_active() then'));
      expect(
        body,
        contains('if not public.is_match_community_admin(p_match_id, v_actor)'),
      );
      expect(
        body,
        contains("if v_match.status = 'completed' or v_match.end_at <= now() "
            "then raise exception 'MATCH_COMPLETED';"),
      );
      expect(body, contains("set search_path = ''"));
    });

    test('is executable by authenticated and service_role only', () {
      expect(
        flat,
        contains('revoke execute on function public.save_generated_lineup_v1( '
            'uuid, jsonb, integer, jsonb, jsonb, jsonb ) from public, anon;'),
      );
      expect(
        flat,
        contains('grant execute on function public.save_generated_lineup_v1( '
            'uuid, jsonb, integer, jsonb, jsonb, jsonb ) '
            'to authenticated, service_role;'),
      );
    });

    test('contains no historical backfill', () {
      expect(statements, isNot(contains('generate_series')));
      expect(flat,
          isNot(contains('insert into public.btge_generation_runs select')));
      expect(
        RegExp(r'insert into public\.btge_generation_runs \([^)]*\) values')
            .allMatches(flat)
            .length,
        1,
      );
    });
  });

  group('Anonymous acquisition', () {
    test('product_events stays the one analytics table', () {
      expect(statements, isNot(contains('create table public.product_events')));
      expect(
        RegExp(r'create table public\.[a-z_]*event').hasMatch(statements),
        isFalse,
      );
    });

    test('adds acquisition_id and no other column, so no target or PII', () {
      final added = RegExp(r'add column (?:if not exists )?([a-z_]+)')
          .allMatches(flat)
          .map((m) => m.group(1))
          .toList();
      expect(added, ['acquisition_id']);
      expect(flat, contains('add column if not exists acquisition_id uuid;'));
    });

    test('user_id is nullable only under the constrained anonymous shape', () {
      expect(
        flat,
        contains(
            'alter table public.product_events alter column user_id drop not null;'),
      );
      expect(
        flat,
        contains("check ( user_id is not null or ( event_name = "
            "'public_link_opened' and acquisition_id is not null and source "
            "is not null and source in ( 'public_link_player', "
            "'public_link_community', 'public_link_match' ) ) )"),
      );
    });

    test('signup completion requires an account and an acquisition', () {
      expect(
        flat,
        contains("check ( event_name <> 'public_link_signup_completed' or "
            "(user_id is not null and acquisition_id is not null) )"),
      );
      expect(
        flat,
        contains("check ( acquisition_id is null or (event_name = "
            "'public_link_opened' and user_id is null) or event_name = "
            "'public_link_signup_completed' )"),
      );
    });

    test('adds public_link_signup_completed to the eleven event names', () {
      expect(
        flat,
        contains("'share_used', 'public_link_opened', "
            "'public_link_signup_completed' ));"),
      );
      // The generic writer keeps its own eleven-name contract.
      expect(
          statements, isNot(contains('function public.record_product_event')));
    });

    test('indexes acquisition lookup and idempotent completion', () {
      expect(
        flat,
        contains('create unique index if not exists '
            'product_events_anonymous_open_acquisition_key on '
            'public.product_events (acquisition_id) where event_name = '
            "'public_link_opened' and user_id is null;"),
      );
      expect(
        flat,
        contains('create unique index if not exists '
            'product_events_signup_completed_acquisition_key on '
            'public.product_events (acquisition_id) where event_name = '
            "'public_link_signup_completed';"),
      );
    });

    test('direct table privileges stay revoked', () {
      expect(
        flat,
        contains('revoke all on public.product_events '
            'from anon, authenticated, public;'),
      );
      expect(
        RegExp(r'grant [^;]* on (table )?public\.product_events')
            .hasMatch(flat),
        isFalse,
      );
      expect(
        flat,
        contains(
            'alter table public.product_events enable row level security;'),
      );
    });

    test('the anonymous writer accepts only kind, platform and version', () {
      expect(parametersOf('record_anonymous_public_link_open'),
          {'p_kind', 'p_platform', 'p_app_version'});
      expect(statements, isNot(contains('p_user_id')));

      final body = flatFunction('record_anonymous_public_link_open');
      expect(
          body,
          contains("if auth.uid() is not null then raise exception "
              "'ANONYMOUS_ONLY';"));
      expect(body, contains("when 'player' then 'public_link_player'"));
      expect(body, contains("when 'community' then 'public_link_community'"));
      expect(body, contains("when 'match' then 'public_link_match'"));
      expect(body, contains("p_platform not in ('web', 'android')"));
      // Reads nothing.
      expect(body, isNot(contains(' from ')));
      expect(body, contains("set search_path = ''"));
      expect(body, contains('security definer'));
    });

    test('the anonymous writer generates the acquisition id on the server', () {
      final body = flatFunction('record_anonymous_public_link_open');
      expect(body, contains('returns uuid'));
      expect(body, contains('v_acquisition_id := gen_random_uuid();'));
      expect(body, contains('return v_acquisition_id;'));
      expect(
        body,
        contains("values ( null, 'public_link_opened', v_acquisition_id, "
            'v_source, p_platform,'),
      );
    });

    test('the anonymous writer is anon + service_role only', () {
      expect(
        flat,
        contains('revoke execute on function '
            'public.record_anonymous_public_link_open(text, text, text) '
            'from public, authenticated;'),
      );
      expect(
        flat,
        contains('grant execute on function '
            'public.record_anonymous_public_link_open(text, text, text) '
            'to anon, service_role;'),
      );
    });

    test('completion takes the actor from auth.uid()', () {
      expect(parametersOf('record_public_link_signup_completed'),
          {'p_acquisition_id'});
      final body = flatFunction('record_public_link_signup_completed');
      expect(body, contains('v_actor uuid := auth.uid();'));
      expect(
          body,
          contains("values ( v_actor, 'public_link_signup_completed', "
              'p_acquisition_id, v_open.source, v_open.platform, '
              'v_open.app_version )'));
    });

    test('completion validates the anonymous open and account creation time',
        () {
      final body = flatFunction('record_public_link_signup_completed');
      expect(
        body,
        contains("where pe.acquisition_id = p_acquisition_id and "
            "pe.event_name = 'public_link_opened' and pe.user_id is null;"),
      );
      expect(body, contains("raise exception 'INVALID_ACQUISITION'"));
      expect(body, contains('v_account_created_at < v_open.created_at'));
      expect(body, contains("raise exception 'ACQUISITION_NOT_ELIGIBLE'"));
      expect(body, contains('if not public.is_current_user_active() then'));
    });

    test('completion is idempotent per acquisition id', () {
      final body = flatFunction('record_public_link_signup_completed');
      expect(
        body,
        contains("on conflict (acquisition_id) where event_name = "
            "'public_link_signup_completed' do nothing;"),
      );
      // The anonymous open is read, never rewritten.
      expect(body, isNot(contains('update public.product_events')));
    });

    test('completion is authenticated + service_role only', () {
      expect(
        flat,
        contains('revoke execute on function '
            'public.record_public_link_signup_completed(uuid) from public, anon;'),
      );
      expect(
        flat,
        contains('grant execute on function '
            'public.record_public_link_signup_completed(uuid) '
            'to authenticated, service_role;'),
      );
    });

    test('contains no historical backfill', () {
      expect(flat, isNot(contains('insert into public.product_events select')));
      expect(flat, isNot(contains('update public.product_events')));
      expect(flat, isNot(contains('delete from public.product_events')));
    });
  });
}
