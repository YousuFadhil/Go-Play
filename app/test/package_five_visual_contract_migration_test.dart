import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0080 says — a static review of the file, not a runtime
/// result, exactly as `package_five_migration_test.dart` reviews `0079`.
///
/// `0080` exists to make two facts printable: the scoreline under a Recent Form
/// badge, and the week a stored Team of Period award is about. What this suite
/// is for is the other half — proving that making them printable did not widen
/// anything. A migration that adds two integers to a public contract is exactly
/// the kind that gets waved through, and the assertions below are the review
/// that says it stayed narrow.
void main() {
  // Normalised on the way in: Git checks these files out with CRLF endings on
  // Windows, and several assertions below span two lines.
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  final sql =
      read('../supabase/migrations/0080_package_five_visual_contract.sql');
  final rollback = read(
      '../supabase/rollback/0080_package_five_visual_contract.rollback.sql');

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

  /// The body of one `create function public.<name>(`, up to its `$$;`.
  String functionBody(String name) {
    final start = statements.indexOf('function public.$name(');
    expect(start, isNot(-1), reason: '$name is not created by this migration');
    final end = statements.indexOf(r'$$;', start);
    expect(end, isNot(-1), reason: '$name has no body');
    return statements.substring(start, end);
  }

  group('the four read models are replaced, and only those four', () {
    const replaced = [
      'player_recent_form(uuid, int)',
      'public_player_recent_form(uuid, int)',
      'player_recent_highlights(uuid)',
      'public_player_recent_highlight(uuid)',
    ];

    test('each is dropped and recreated with its original signature', () {
      for (final signature in replaced) {
        expect(
            statements, contains('drop function if exists public.$signature;'),
            reason: signature);
      }
      // A create for each drop: an OUT column cannot be changed in place, and a
      // drop without the matching create is an outage.
      expect('drop function if exists'.allMatches(statements).length,
          replaced.length);
      expect('\ncreate function public.'.allMatches(statements).length,
          replaced.length);
    });

    test('nothing else is created, altered or dropped', () {
      for (final forbidden in [
        'create table',
        'alter table',
        'create policy',
        'alter policy',
        'drop policy',
        'create trigger',
        'create index',
        'create view',
        'create materialized view',
        'insert into',
        'update ',
        'delete from',
        'truncate',
        'alter column',
        'drop column',
      ]) {
        expect(executable.toLowerCase(), isNot(contains(forbidden)),
            reason: forbidden);
      }
    });

    test('and no earlier migration is edited', () {
      // Append-only: the file names 0079 in prose and touches none of its other
      // objects.
      for (final untouched = [
        'public_player_profile',
        'public_match_detail',
        'public_match_lineup',
        'record_team_of_period_snapshot',
        'record_product_event',
        'team_of_period_snapshots',
        'team_of_period_awards',
      ];
          true;) {
        for (final name in untouched) {
          expect(executable, isNot(contains('function public.$name(')),
              reason: name);
          expect(executable, isNot(contains('table public.$name')),
              reason: name);
        }
        break;
      }
    });
  });

  group('the privileges are the ones 0079 granted, restated', () {
    test('anon keeps exactly the two public contracts', () {
      for (final signature in [
        'public_player_recent_form(uuid, int)',
        'public_player_recent_highlight(uuid)',
      ]) {
        expect(
          statements,
          contains('grant execute on function public.$signature\n'
              '  to anon, authenticated, service_role;'),
          reason: signature,
        );
      }
    });

    test('and gains nothing on the authenticated ones', () {
      for (final signature in [
        'player_recent_form(uuid, int)',
        'player_recent_highlights(uuid)',
      ]) {
        expect(
          statements,
          contains('revoke execute on function public.$signature\n'
              '  from anon, public;'),
          reason: signature,
        );
        expect(
          statements,
          contains('grant execute on function public.$signature\n'
              '  to authenticated;'),
          reason: signature,
        );
      }
      // Every executable mention of anon is either a revoke or one of the two
      // public grants above -- the statements wrap, so a continuation line is
      // matched by what it says rather than by the verb above it.
      for (final line in executable.split('\n')) {
        if (!line.contains('anon')) continue;
        expect(
          line.contains('revoke execute') ||
              line.trim() == 'from anon, public;' ||
              line.contains('to anon, authenticated, service_role;'),
          isTrue,
          reason: line,
        );
      }
    });

    test('every new function still pins its search_path and is definer', () {
      for (final name in [
        'player_recent_form',
        'public_player_recent_form',
        'player_recent_highlights',
        'public_player_recent_highlight',
      ]) {
        final body = functionBody(name);
        expect(body, contains('security definer'), reason: name);
        expect(body, contains('set search_path = public'), reason: name);
        expect(body, contains('stable'), reason: name);
      }
    });
  });

  group('what the scoreline is, and what it is not', () {
    test('it is the recorded result, read from the player own side', () {
      final body = functionBody('player_recent_form');
      expect(
        body,
        contains("case when a.team = 'A' then r.team_a_score "
            'else r.team_b_score end'),
      );
      expect(
        body,
        contains("case when a.team = 'A' then r.team_b_score "
            'else r.team_a_score end'),
      );
      // The outcome is still the one the career counters were applied from.
      expect(body, contains('match_result_contribution(recent.match_id)'));
    });

    test('the public form still names no fixture', () {
      final body = functionBody('public_player_recent_form');
      // Its returned columns, and nothing else.
      final returns = body.substring(
        body.indexOf('returns table ('),
        body.indexOf(')\nlanguage sql'),
      );
      for (final forbidden in [
        'match_id',
        'community_id',
        'community_name',
        'start_at',
      ]) {
        expect(returns, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(returns, contains('score_for int'));
      expect(returns, contains('score_against int'));
      // And it is still bounded by the authenticated window's own clamp.
      expect(body, contains('public.player_recent_form(p_user_id, p_limit)'));
    });

    test('the window is still clamped to ten', () {
      expect(
        functionBody('player_recent_form'),
        contains('limit least(greatest(coalesce(p_limit, 5), 1), 10)'),
      );
    });
  });

  group('the period key is read, never derived', () {
    test('it is the stored snapshot column', () {
      final body = functionBody('player_recent_highlights');
      expect(body, contains('s.period_key'));
      // An MVP is a match, not a period: both period columns are null on it.
      expect(body, contains("'MVP'::text"));
      expect(body, contains('null::text,\n      null::text'));
    });

    test('and the public contract returns it too, with still no ids', () {
      final body = functionBody('public_player_recent_highlight');
      final returns = body.substring(
        body.indexOf('returns table ('),
        body.indexOf(')\nlanguage sql'),
      );
      expect(returns, contains('period_key text'));
      expect(returns, isNot(contains('community_id')));
      expect(returns, isNot(contains('match_id')));
    });

    test('an active player and an active community are still required', () {
      expect(functionBody('public_player_recent_highlight'),
          contains('join users u on u.id = p_user_id and u.is_active'));
      expect(
          functionBody('player_recent_highlights'),
          contains(
              'join communities c on c.id = s.community_id and c.is_active'));
    });
  });

  group('the rollback puts 0079 back', () {
    test('it drops and recreates the same four functions', () {
      for (final signature in [
        'player_recent_form(uuid, int)',
        'public_player_recent_form(uuid, int)',
        'player_recent_highlights(uuid)',
        'public_player_recent_highlight(uuid)',
      ]) {
        expect(rollback, contains('drop function if exists public.$signature;'),
            reason: signature);
      }
    });

    test('and restores the 0079 shape, without the 0080 columns', () {
      expect(rollback, isNot(contains('score_for')));
      expect(rollback, isNot(contains('score_against')));
      expect(rollback, isNot(contains('period_key')));
    });

    test('it destroys nothing', () {
      for (final forbidden in [
        'drop table',
        'delete from',
        'truncate',
        'drop column',
        'alter table',
      ]) {
        expect(rollback.toLowerCase(), isNot(contains(forbidden)),
            reason: forbidden);
      }
    });

    test('and it restores the privileges rather than assuming them', () {
      expect(
          rollback,
          contains('grant execute on function '
              'public.public_player_recent_form(uuid, int)'));
      expect(
          rollback,
          contains('revoke execute on function '
              'public.player_recent_form(uuid, int)'));
    });
  });
}
