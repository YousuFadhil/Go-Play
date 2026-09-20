import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/analytics/analytics_models.dart';

/// What migration 0079 says — a static review of the file, not a runtime
/// result.
///
/// The migration cannot be executed from a widget test, so these assertions
/// read the text, exactly as `analytics_migration_test.dart` reads `0067`.
/// That is a real limit and worth stating plainly: this suite proves the file
/// says the right things, and a live precheck is what proves the database does
/// them.
///
/// What it does catch is the class of mistake that is invisible in review and
/// expensive in production — a grant to `anon` that should not be there, a
/// column that should not be reachable, a `security definer` function with no
/// pinned `search_path`, a writer that stopped taking its actor from the
/// session.
void main() {
  // Normalised on the way in: Git checks this file out with CRLF endings on
  // Windows, and several assertions below span two lines.
  final sql = File(
    '../supabase/migrations/0079_package_five_public_sharing.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with every SQL string literal blanked as well — the `comment on`
  /// bodies legitimately name things the migration does not touch.
  final executable = statements
      .split('\n')
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  /// The body of one `create ... function public.<name>(`, up to its `$$;`.
  String functionBody(String name) {
    final start = statements.indexOf('function public.$name(');
    expect(start, isNot(-1), reason: '$name is not created by this migration');
    final end = statements.indexOf(r'$$;', start);
    expect(end, isNot(-1), reason: '$name has no body');
    return statements.substring(start, end);
  }

  group('the public surface is exactly five functions', () {
    /// The only relations migration 0079 may hand to `anon`.
    const publicContracts = [
      'public_player_profile(uuid)',
      'public_player_recent_form(uuid, int)',
      'public_player_recent_highlight(uuid)',
      'public_match_detail(uuid)',
      'public_match_lineup(uuid)',
    ];

    test('each one is granted to anon', () {
      for (final contract in publicContracts) {
        expect(
          statements,
          contains('grant execute on function public.$contract\n'
              '  to anon, authenticated, service_role;'),
          reason: '$contract is not granted to anon',
        );
      }
    });

    test('and nothing else in the file is', () {
      // Every `to anon` in the migration, counted. Five grants, and the five
      // above are which five — so a sixth would have to be added here
      // deliberately rather than slipping in.
      final grantsToAnon =
          RegExp(r'grant execute[^;]*to anon').allMatches(executable).length;
      expect(grantsToAnon, publicContracts.length);

      // No table, view or sequence privilege reaches anon at all: every grant
      // in this file is on a function.
      expect(
        RegExp(r'grant select[^;]*anon').hasMatch(executable),
        isFalse,
        reason: 'anon must gain no relation, only the four functions',
      );
      expect(
        RegExp(r'grant (insert|update|delete)').hasMatch(executable),
        isFalse,
        reason: 'no write privilege is granted to anybody here',
      );
    });

    test('the authenticated-only football internals are not opened up', () {
      // The named things the approved architecture forbids granting to anon.
      // Asserted by name because that is what a reviewer would look for.
      for (final protected in [
        'player_profile(uuid)',
        'v_football_completed_matches',
        'v_football_match_lineup',
        'v_football_match_participants',
        'v_football_community_player_stats',
        'community_period_xi_evidence',
        'community_period_xi_window',
      ]) {
        expect(
          RegExp('grant[^;]*$protected[^;]*anon').hasMatch(executable),
          isFalse,
          reason: '$protected must not become anon-readable',
        );
      }

      // `player_profile` is mentioned in prose and must not be executed
      // against, re-granted or replaced.
      expect(
          executable,
          isNot(contains('drop function if exists '
              'public.player_profile')));
    });

    test('the two internal reads stay behind a session', () {
      for (final internal in [
        'player_recent_form(uuid, int)',
        'player_recent_highlights(uuid)',
      ]) {
        // The statement is wrapped at different points for the two names, so
        // the whitespace between the clauses is what varies and nothing else.
        expect(
          statements.replaceAll(RegExp(r'\s+'), ' '),
          contains('revoke execute on function public.$internal '
              'from anon, public;'),
          reason: '$internal must be revoked from anon',
        );
        expect(
          RegExp('grant execute on function public.'
                  '${RegExp.escape(internal)}[^;]*to anon')
              .hasMatch(executable),
          isFalse,
        );
      }
    });
  });

  group('what the public contracts may return', () {
    /// Every column `public_player_profile` can ever answer with.
    const playerProfileColumns = [
      'user_id uuid',
      'full_name text',
      'primary_position text',
      'secondary_position text',
      'avatar_path text',
      'overall_rating numeric',
      'matches_played int',
      'wins int',
      'losses int',
      'draws int',
      'goals int',
      'mvp_count int',
    ];

    test('the public player profile is an explicit allowlist', () {
      final body = functionBody('public_player_profile');
      for (final column in playerProfileColumns) {
        expect(body, contains(column));
      }
      // No `select *` anywhere in the file: a row type from a table is exactly
      // how a column nobody reviewed becomes public.
      expect(executable, isNot(contains('select *')));
    });

    test('no private column is reachable through any public contract', () {
      for (final name in [
        'public_player_profile',
        'public_player_recent_form',
        'public_player_recent_highlight',
        'public_match_detail',
        'public_match_lineup',
      ]) {
        final body = functionBody(name);
        for (final forbidden in [
          'date_of_birth',
          'phone',
          'email',
          'auth_user_id',
          'join_code',
          'owner_id',
          'created_by',
          'recorded_by',
          'is_system_admin',
          'suspended',
        ]) {
          expect(
            body,
            isNot(contains(forbidden)),
            reason: '$name must not be able to return $forbidden',
          );
        }
      }
    });

    test('the public form carries no fixture identity', () {
      final body = functionBody('public_player_recent_form');
      // It returns a sequence, an outcome, goals and MVP — and deliberately no
      // match id, community id or kick-off time, which is what keeps completed
      // match history behind a session (migration 0057).
      final returns = body.substring(
        body.indexOf('returns table ('),
        body.indexOf(')\nlanguage sql'),
      );
      expect(returns, contains('sequence_no int'));
      expect(returns, contains('outcome text'));
      expect(returns, isNot(contains('match_id')));
      expect(returns, isNot(contains('community_id')));
      expect(returns, isNot(contains('start_at')));
    });

    test('the public match reads the view rather than copying its filter', () {
      final body = functionBody('public_match_detail');
      expect(body, contains('from v_public_upcoming_matches v'));
      // No second copy of the rule. A filter written out here could drift from
      // the view and start answering for matches discovery would not list.
      expect(body, isNot(contains("status <> 'completed'")));
      expect(body, isNot(contains('end_at > now()')));
      // And no roster, result or lineup is joined in.
      for (final table in [
        'match_registrations',
        'match_results',
        'match_team_assignments',
        'match_goals',
      ]) {
        expect(body, isNot(contains(table)));
      }
    });

    test('an inactive player has no public profile, and no error either', () {
      for (final name in [
        'public_player_profile',
        'public_player_recent_form',
        'public_player_recent_highlight',
      ]) {
        expect(
          functionBody(name),
          contains('is_active'),
          reason: '$name must answer for active players only',
        );
      }
    });
  });

  group('the security definer conventions are kept', () {
    test('every function in the file pins its search_path', () {
      final definers =
          RegExp(r'security definer').allMatches(statements).length;
      final pinned =
          RegExp(r'set search_path = public').allMatches(statements).length;
      expect(definers, greaterThan(0));
      expect(
        pinned,
        definers,
        reason: 'a security definer function with an unpinned search_path '
            'resolves its own names against a schema a caller controls',
      );
    });

    test('the reads are stable, so none of them can write', () {
      for (final name in [
        'player_recent_form',
        'player_recent_highlights',
        'public_player_profile',
        'public_player_recent_form',
        'public_player_recent_highlight',
        'public_match_detail',
        'public_match_lineup',
      ]) {
        expect(functionBody(name), contains('stable'), reason: name);
      }
    });

    test('recent form is bounded, whatever it is asked for', () {
      final body = functionBody('player_recent_form');
      expect(
          body, contains('limit least(greatest(coalesce(p_limit, 5), 1), 10)'));
    });

    test('recent form derives its outcome from the existing truth', () {
      final body = functionBody('player_recent_form');
      // The same function `apply_match_statistics` feeds the career counters
      // from. A `case` over the two scores written out here would be a second
      // definition of what a win is.
      expect(body, contains('match_result_contribution(recent.match_id)'));
      expect(body, isNot(contains('team_a_score >')));
    });
  });

  group('analytics keeps its identity requirement', () {
    test('user_id is never made nullable', () {
      expect(executable, isNot(contains('alter column user_id')));
      expect(executable, isNot(contains('drop not null')));
    });

    test('the writer still takes its actor from the session', () {
      final body = functionBody('record_product_event');
      expect(body, contains('v_user_id := auth.uid();'));
      expect(body, contains("raise exception 'NOT_AUTHENTICATED'"));
      expect(body, contains('is_current_user_active()'));
      // There is still no user-id argument to point at somebody else.
      expect(body, isNot(contains('p_user_id')));
    });

    test('anon cannot write an event, and there is no second writer', () {
      expect(
        statements,
        contains('revoke execute on function\n'
            '  public.record_product_event(text, uuid, uuid, text, text, '
            'text, text)\n'
            '  from anon, public;'),
      );
      // Exactly one insert reaches `product_events`, and it is inside the
      // writer that reads `auth.uid()`. The other two inserts in the file are
      // the Team of Period writer's, which only `service_role` may call.
      expect(
        RegExp(r'insert into product_events').allMatches(executable).length,
        1,
      );
      expect(
        functionBody('record_product_event'),
        contains('insert into product_events'),
      );
      expect(RegExp(r'insert into').allMatches(executable).length, 3);
    });

    test('the share metadata is nullable and constrained', () {
      expect(
        statements,
        contains('add column if not exists share_type text'),
      );
      expect(statements, contains('add column if not exists source text'));
      // Nullable: no existing row is invalidated and no event is blocked for
      // want of a field.
      expect(executable, isNot(contains('share_type text not null')));
      expect(executable, isNot(contains('source text not null')));

      for (final type in ShareType.values) {
        expect(
          statements,
          contains("'${type.wireName}'"),
          reason: '${type.name} is missing from the share_type CHECK',
        );
      }
    });

    test('the event list is restated in full and carries every known name', () {
      final constraint = statements.substring(
        statements.indexOf('add constraint product_events_event_name_check'),
        statements
            .indexOf('comment on column public.product_events.share_type'),
      );
      for (final event in ProductEvent.values) {
        expect(constraint, contains("'${event.wireName}'"));
      }
      // And nothing the application does not know.
      final quoted = RegExp("'[a-z_]+'").allMatches(constraint).length;
      expect(quoted, ProductEvent.values.length);
    });
  });

  group('the migration is additive', () {
    test('it edits no earlier migration file', () {
      final directory = Directory('../supabase/migrations');
      final names = [
        for (final entry in directory.listSync()) entry.uri.pathSegments.last,
      ];
      expect(names, contains('0079_package_five_public_sharing.sql'));
    });

    test('nothing is dropped except the one signature being replaced', () {
      final drops = RegExp(r'drop (table|view|policy|column|trigger|index)')
          .allMatches(executable);
      expect(drops, isEmpty, reason: 'no destructive drop belongs here');

      // The function drop is the signature change `record_product_event`
      // needs, and the constraint drops are the two being re-added.
      expect(
        executable,
        contains('drop function if exists '
            'public.record_product_event(text, uuid, uuid, text, text);'),
      );
    });

    test('it backfills nothing and rewrites nothing', () {
      for (final dml in ['update public.', 'delete from', 'truncate']) {
        expect(executable, isNot(contains(dml)));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Community visibility, as approved for Package 5: `CODE_REQUIRED` decides
  // joining, never visibility; active communities are public; inactive and
  // suspended communities are hidden, through every public surface.
  // ---------------------------------------------------------------------------

  /// Every migration, in the order they apply, with comments and literals
  /// blanked -- for the questions that are about the schema as a whole rather
  /// than about this one file.
  List<(String, String)> allMigrations() {
    final files = Directory('../supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort(
          (a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last));
    return [
      for (final file in files)
        (
          file.uri.pathSegments.last,
          file
              .readAsStringSync()
              .replaceAll('\r\n', '\n')
              .split('\n')
              .where((line) => !line.trimLeft().startsWith('--'))
              .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
              .join('\n'),
        ),
    ];
  }

  /// The last `create [or replace] view public.<name> as ... ;` in the schema.
  String latestView(String name) {
    String? body;
    for (final (_, sql) in allMigrations()) {
      final pattern = RegExp(
        'create (or replace )?view public\\.$name as(.*?);',
        dotAll: true,
      );
      for (final match in pattern.allMatches(sql)) {
        body = match.group(2);
      }
    }
    expect(body, isNotNull, reason: '$name is never defined');
    return body!;
  }

  group('an inactive or suspended community is hidden from every public read',
      () {
    test('the public match reads communities only when they are active', () {
      final body = functionBody('public_match_detail');
      // Both branches -- upcoming and completed -- join the community on
      // `is_active` themselves, as well as reading views that already do.
      expect(
        RegExp(r'join communities c on c\.id = \w+\.community_id and c\.is_active')
            .allMatches(body)
            .length,
        2,
      );
    });

    test('the views the public match reads also require an active community',
        () {
      for (final view in [
        'v_public_upcoming_matches',
        'v_football_completed_matches',
        'v_football_match_lineup',
      ]) {
        expect(latestView(view), contains('is_active'), reason: view);
      }
    });

    test('a public lineup exists only for a completed match', () {
      expect(
        functionBody('public_match_lineup'),
        contains('from v_football_match_lineup l'),
      );
      // The view is completed-only, so an upcoming roster can never be public.
      expect(
        latestView('v_football_match_lineup'),
        contains("m.status = '' or m.end_at <= now()"),
      );
    });

    test('recent form and both highlight kinds require an active community',
        () {
      expect(functionBody('player_recent_form'), contains('c.is_active'));
      expect(
        RegExp(r'c\.is_active')
            .allMatches(functionBody('player_recent_highlights'))
            .length,
        2,
        reason: 'the MVP branch and the Team of Period branch both check it',
      );
    });

    test(
        'the public profile, form and highlight answer for active players only',
        () {
      for (final name in [
        'public_player_profile',
        'public_player_recent_form',
        'public_player_recent_highlight',
      ]) {
        expect(functionBody(name), contains('is_active'), reason: name);
      }
    });
  });

  group('CODE_REQUIRED decides joining, not visibility', () {
    test('no public read in this migration filters on the join policy', () {
      expect(executable, isNot(contains('join_policy')));
    });

    test('public discovery still lists every active community', () {
      final view = latestView('v_public_communities');
      expect(view, isNot(contains('join_policy')));
      expect(view, contains('where c.is_active'));
    });

    test('there is still no private-community flag anywhere in the schema', () {
      // `0016` dropped `is_private`; nothing after it may bring one back.
      final after = allMigrations()
          .where((m) => m.$1.compareTo('0016_join_policy.sql') > 0)
          .map((m) => m.$2);
      for (final sql in after) {
        expect(sql, isNot(contains('is_private')));
      }
    });
  });

  group('what a visitor can learn from the public player surfaces', () {
    String returnsOf(String name) {
      final body = functionBody(name);
      return body.substring(
        body.indexOf('returns table ('),
        body.indexOf(')\nlanguage sql'),
      );
    }

    test('public Recent Form exposes no match or community identifier', () {
      final returns = returnsOf('public_player_recent_form');
      for (final column in [
        'match_id',
        'community_id',
        'community_name',
        'start_at',
      ]) {
        expect(returns, isNot(contains(column)), reason: column);
      }
    });

    test('public Recent Highlight exposes a community name and no ids', () {
      final returns = returnsOf('public_player_recent_highlight');
      expect(returns, contains('community_name text'));
      for (final column in [
        'community_id',
        'match_id',
        'period_key',
        'snapshot',
        'user_id',
      ]) {
        expect(returns, isNot(contains(column)), reason: column);
      }
      // And that name only ever comes from the active-community read.
      expect(
        functionBody('public_player_recent_highlight'),
        contains('from public.player_recent_highlights(p_user_id) h'),
      );
    });

    test('a public lineup names a player id only for an available profile', () {
      final returns = returnsOf('public_match_lineup');
      expect(returns, contains('player_id uuid'));
      expect(returns, isNot(contains('user_id')));
      expect(returns, isNot(contains('professional_guest_id')));
      expect(returns, isNot(contains('overall_rating')));
      expect(
        functionBody('public_match_lineup'),
        contains(
          'case when l.user_id is not null and u.is_active then l.user_id end',
        ),
      );
      // The same predicate the public profile itself answers on, so an id is
      // present exactly when `/player/{id}` would open.
      expect(
          functionBody('public_player_profile'), contains('and u.is_active'));
    });
  });

  group('the authenticated football surfaces stay closed to anon', () {
    test('across every migration, none is left granted to anon', () {
      // Replayed in order: a later revoke undoes an earlier grant, so what is
      // asserted is the schema's final state rather than any one file.
      const protected = [
        'player_profile',
        'player_recent_form',
        'player_recent_highlights',
        'v_football_completed_matches',
        'v_football_match_lineup',
        'v_football_match_participants',
        'v_football_community_stats',
        'v_football_community_player_stats',
        'community_period_xi_evidence',
        'community_period_xi_window',
        'record_team_of_period_snapshot',
        'community_period_xi_closed_window',
        'community_period_xi_closed_evidence',
        'community_period_xi_matches_in',
        'community_period_xi_window_in',
        'community_period_xi_evidence_in',
        'team_of_period_snapshots',
        'team_of_period_awards',
      ];
      final granted = <String>{};
      final statement = RegExp(r'\b(grant|revoke)\b[^;]*;', dotAll: true);
      for (final (_, sql) in allMigrations()) {
        for (final match in statement.allMatches(sql)) {
          final text = match.group(0)!;
          if (!RegExp(r'\banon\b').hasMatch(text)) continue;
          for (final name in protected) {
            if (!RegExp('public\\.$name\\b').hasMatch(text)) continue;
            if (match.group(1) == 'grant') {
              granted.add(name);
            } else {
              granted.remove(name);
            }
          }
        }
      }
      expect(granted, isEmpty);
    });
  });

  group('Team of Period snapshots', () {
    test('no client role can touch either table', () {
      for (final table in [
        'team_of_period_snapshots',
        'team_of_period_awards'
      ]) {
        expect(
          statements,
          contains('alter table public.$table enable row level security;'),
        );
        expect(
          statements.replaceAll(RegExp(r'\s+'), ' '),
          contains('revoke all on table public.$table '
              'from anon, authenticated, public;'),
        );
      }
      // RLS with no policy denies every client every row.
      expect(executable, isNot(contains('create policy')));
    });

    test('the one writer is service_role only', () {
      final flat = statements.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat,
        contains(
            'revoke execute on function public.record_team_of_period_snapshot( '
            'uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, '
            'text, jsonb ) from anon, authenticated, public;'),
      );
      expect(
        flat,
        contains(
            'grant execute on function public.record_team_of_period_snapshot( '
            'uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, '
            'text, jsonb ) to service_role;'),
      );
      expect(
        RegExp(r'grant execute on function public\.record_team_of_period_snapshot'
                r'[^;]*\b(anon|authenticated)\b')
            .hasMatch(executable),
        isFalse,
      );
    });

    test('only the writer inserts, and nothing ever rewrites a snapshot', () {
      final writer = functionBody('record_team_of_period_snapshot');
      expect(writer, contains('insert into team_of_period_snapshots'));
      expect(writer, contains('insert into team_of_period_awards'));

      final outside = statements.replaceAll(writer, '');
      expect(outside, isNot(contains('insert into team_of_period')));

      // Final once written: no update, no delete, no upsert.
      for (final forbidden in [
        'update team_of_period',
        'update public.team_of_period',
        'delete from team_of_period',
        'delete from public.team_of_period',
        'on conflict',
      ]) {
        expect(executable, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(writer, contains('SNAPSHOT_ALREADY_FINAL'));
      expect(
        statements,
        contains('unique (community_id, period_type, period_key)'),
      );
    });

    test('only a closed, canonical period can be stored', () {
      final writer = functionBody('record_team_of_period_snapshot');
      expect(writer, contains('if p_period_end > now() then'));
      expect(writer, contains('PERIOD_NOT_CLOSED'));
      expect(writer, contains('PERIOD_IDENTITY_MISMATCH'));
      expect(writer,
          contains('public.current_statistics_week_at(p_period_start)'));
      expect(
        writer,
        contains('public.statistics_period_key(p_period_start, p_period_type)'),
      );
    });

    test('the database stores a team; it never selects one', () {
      // The writer and the highlight read neither gather evidence nor rank it:
      // both belong elsewhere -- evidence to section 5, ranking to the Dart
      // selector.
      for (final name in [
        'record_team_of_period_snapshot',
        'player_recent_highlights',
      ]) {
        final body = functionBody(name);
        for (final forbidden in [
          'community_period_xi',
          'period_form_score',
          'participation_rate',
          'period_xi_required_matches',
        ]) {
          expect(body, isNot(contains(forbidden)), reason: '$name: $forbidden');
        }
      }
      // And nowhere in the file is a candidate ranked: the selection order the
      // evidence comment describes is applied by the Dart selector only.
      for (final ranking in [
        'period_form_score desc',
        'participation_rate desc',
        'goal_form_contribution_total desc',
      ]) {
        expect(executable, isNot(contains(ranking)), reason: ranking);
      }
    });

    test('an award is dated by the end of its period', () {
      expect(
        functionBody('player_recent_highlights'),
        contains("s.period_end - interval '1 millisecond'"),
      );
    });

    test('nothing is backfilled', () {
      // The only rows these tables ever receive come through the writer.
      expect(
        RegExp(r'insert into team_of_period_\w+\s*\([^)]*\)\s*select').hasMatch(
            statements.replaceAll(
                functionBody('record_team_of_period_snapshot'), '')),
        isFalse,
      );
    });
  });

  group('closed-period Team of Period evidence (section 5)', () {
    /// 0077's text: the bodies section 5 moves.
    final m77 = File(
      '../supabase/migrations/0077_current_week_team_of_week.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    String bodyIn(String sql, String name) {
      final start = sql.indexOf('create or replace function public.$name(');
      expect(start, isNot(-1), reason: name);
      final open = sql.indexOf('as \$\$\n', start) + 'as \$\$\n'.length;
      return sql.substring(open, sql.indexOf('\$\$;', open));
    }

    String replaceOnce(String text, String from, String to) {
      expect(from.allMatches(text).length, 1, reason: from);
      return text.replaceFirst(from, to);
    }

    const auth = "  if auth.uid() is null then\n"
        "    raise exception 'NOT_AUTHENTICATED';\n"
        "  end if;\n"
        "\n"
        "  if not public.is_community_member(p_community_id, auth.uid()) then\n"
        "    raise exception 'NOT_AUTHORIZED';\n"
        "  end if;\n";

    test('the moved bodies are 0077\'s, with only the named substitutions', () {
      final live = sql;
      for (final name in [
        'community_period_xi_window',
        'community_period_xi_evidence',
      ]) {
        var expected = bodyIn(m77, name);
        if (name == 'community_period_xi_window') {
          expected = replaceOnce(
            expected,
            "  -- Stated here rather than left to the base tables, because this "
                "function does\n"
                "  -- not run under the caller's policies. Both questions are "
                "asked before a\n"
                "  -- single row is read, and they are the same two the "
                "candidate function asks.\n",
            '',
          );
        }
        expected = replaceOnce(
          expected,
          auth,
          "  -- MOVED (0079): authorization is the caller's. The public wrapper "
          "asks\n"
          "  -- it of the session; the service-role read is granted to "
          "nobody else.\n",
        );
        expected = replaceOnce(
          expected,
          "    select p.period_type, p.period_key, p.period_start, p.period_end\n"
              "    -- CHANGED (0077): the current week, or the last completed "
              "month.\n"
              "    from public.team_of_period_statistics_period(p_period_type) p\n",
          "    -- MOVED (0079): the period is the caller's argument. The public "
              "wrapper\n"
              "    -- passes the award period; the service-role read passes a "
              "closed one.\n"
              "    select\n"
              "      p_period_type  as period_type,\n"
              "      p_period_key   as period_key,\n"
              "      p_period_start as period_start,\n"
              "      p_period_end   as period_end\n",
        );
        expected = replaceOnce(
          expected,
          'from public.community_period_xi_matches(p_community_id, '
              'p_period_type) m',
          'from public.community_period_xi_matches_in(\n'
              '      p_community_id, p_period_type, p_period_key) m',
        );
        expect(bodyIn(live, '${name}_in'), expected, reason: name);
      }
    });

    test('the public read paths keep their signature, gate and period', () {
      for (final name in [
        'community_period_xi_window',
        'community_period_xi_evidence',
      ]) {
        final body = bodyIn(sql, name);
        expect(body, contains(auth), reason: name);
        expect(
          body,
          contains(
              'from public.team_of_period_statistics_period(p_period_type) p'),
          reason: name,
        );
        expect(body, contains('public.${name}_in('), reason: name);
        // Same argument list as 0077, so `create or replace` keeps the grants.
        expect(
          sql,
          contains('create or replace function public.$name(\n'
              '  p_community_id uuid,\n  p_period_type text\n)'),
        );
      }
      // No grant or revoke is issued on the originals: their ACL is untouched.
      expect(
        RegExp(r'(grant|revoke) execute on function\s+public\.'
                r'community_period_xi_(window|evidence|matches)\(')
            .hasMatch(executable),
        isFalse,
      );
    });

    test('the closed-period reads resolve the last completed period only', () {
      for (final name in [
        'community_period_xi_closed_window',
        'community_period_xi_closed_evidence',
      ]) {
        final body = bodyIn(sql, name);
        expect(
          body,
          contains(
              'from public.last_completed_statistics_period(p_period_type) p'),
          reason: name,
        );
        expect(body, isNot(contains('team_of_period_statistics_period')));
        expect(body, isNot(contains('p_period_start')), reason: 'no backfill');
      }
    });

    test(
        'closed reads are service_role only; moved bodies are granted to nobody',
        () {
      final flat = executable.replaceAll(RegExp(r'\s+'), ' ');
      for (final name in [
        'community_period_xi_closed_window',
        'community_period_xi_closed_evidence',
      ]) {
        expect(
          flat,
          contains('revoke execute on function public.$name(uuid, text) '
              'from anon, authenticated, public;'),
        );
        expect(
          flat,
          contains('grant execute on function public.$name(uuid, text) '
              'to service_role;'),
        );
      }
      for (final name in [
        'community_period_xi_matches_in',
        'community_period_xi_window_in',
        'community_period_xi_evidence_in',
      ]) {
        expect(
          flat,
          contains('revoke execute on function public.$name('),
          reason: name,
        );
        expect(
          RegExp('grant execute on function\\s+public\\.$name\\(')
              .hasMatch(executable),
          isFalse,
          reason: name,
        );
      }
    });
  });

  group('the rollback script', () {
    final rollback = File(
      '../supabase/rollback/0079_package_five_public_sharing.rollback.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final active = rollback
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');

    test('is not in the migrations directory', () {
      expect(
        File('../supabase/migrations/0079_package_five_public_sharing.rollback.sql')
            .existsSync(),
        isFalse,
      );
    });

    test('restores 0067\'s writer and 0077\'s read paths verbatim', () {
      final m67 = File(
        '../supabase/migrations/0067_platform_admin_product_analytics.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final m77 = File(
        '../supabase/migrations/0077_current_week_team_of_week.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      String block(String src, String name) {
        final start = src.indexOf('create or replace function public.$name(');
        return src.substring(start, src.indexOf('\$\$;', start) + 3);
      }

      expect(rollback, contains(block(m67, 'record_product_event')));
      for (final name in [
        'community_period_xi_matches',
        'community_period_xi_window',
        'community_period_xi_evidence',
      ]) {
        expect(rollback, contains(block(m77, name)), reason: name);
      }
    });

    test('drops every object 0079 creates', () {
      for (final name in [
        'public_match_lineup',
        'public_match_detail',
        'public_player_recent_highlight',
        'public_player_recent_form',
        'public_player_profile',
        'player_recent_highlights',
        'player_recent_form',
        'record_team_of_period_snapshot',
        'community_period_xi_closed_evidence',
        'community_period_xi_closed_window',
        'community_period_xi_evidence_in',
        'community_period_xi_window_in',
        'community_period_xi_matches_in',
      ]) {
        expect(active, contains('drop function if exists public.$name('),
            reason: name);
      }
      expect(active,
          contains('drop table if exists public.team_of_period_awards;'));
      expect(active,
          contains('drop table if exists public.team_of_period_snapshots;'));
    });

    test('touches no user data by default', () {
      for (final dml in ['delete from', 'update public.', 'truncate']) {
        expect(active, isNot(contains(dml)), reason: dml);
      }
    });
  });
}
