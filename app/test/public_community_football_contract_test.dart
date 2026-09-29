import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/discover_mapper.dart';

/// The narrow public read contract behind a community's football record and its
/// Top 11 -- migration `0093` -- and the client path that reads it.
///
/// **What this proves and what it cannot.** The migration cannot be executed
/// from a widget test, so the first group reads the file, exactly as
/// `package_five_migration_test.dart` reads `0079`: it proves the file *says*
/// the right things -- which functions, which grants, which columns, which
/// order -- and a run against a real Postgres is what proves the database *does*
/// them. The class of mistake it catches is the one that is invisible in review
/// and expensive in production: a grant to `anon` that should not be there, a
/// column that should not be reachable, a `security definer` function with a
/// searchable `search_path`, a ranking that quietly changed.
void main() {
  const file = '0093_public_community_football_contract.sql';

  // Normalised on the way in: Git checks the file out with CRLF endings on
  // Windows, and several assertions below span lines.
  final sql = File('../supabase/migrations/$file')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with every SQL string literal blanked as well -- the `comment
  /// on` bodies legitimately name things the migration does not touch.
  final executable = statements
      .split('\n')
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  String squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// One `create ... function public.<name>(`, up to its closing `$$;`.
  String functionBody(String name) {
    final start = statements.indexOf('function public.$name(');
    expect(start, isNot(-1), reason: '$name is not created by this migration');
    final end = statements.indexOf(r'$$;', start);
    expect(end, isNot(-1), reason: '$name has no body');
    return statements.substring(start, end);
  }

  /// The column list a function declares it returns, in order.
  List<String> returnsOf(String name) {
    final body = functionBody(name);
    final block = body.substring(
      body.indexOf('returns table (') + 'returns table ('.length,
      body.indexOf('\n)\nlanguage sql'),
    );
    return [
      for (final line in block.split('\n'))
        if (line.trim().isNotEmpty) line.trim().replaceAll(RegExp(r',$'), ''),
    ];
  }

  const record = 'public_community_football_record';
  const topPlayers = 'public_community_top_players';

  group('the migration is additive and stands alone', () {
    test('is 0093, once, appended after 0092', () {
      final names = [
        for (final entry in Directory('../supabase/migrations').listSync())
          entry.uri.pathSegments.last,
      ];
      expect(names.where((n) => n.startsWith('0093')), [file]);
      expect(names.where((n) => n.startsWith('0092')), isNotEmpty,
          reason: 'appended after 0092, not written over it');
      expect(names.where((n) => RegExp(r'^\d{14}_').hasMatch(n)), isEmpty,
          reason: 'no CLI timestamp name is kept beside the sequence');
    });

    test('creates exactly two functions and nothing else', () {
      final created = RegExp(r'create (?:or replace )?function public\.(\w+)\(')
          .allMatches(executable)
          .map((m) => m.group(1))
          .toSet();
      expect(created, {record, topPlayers});

      for (final forbidden in [
        'create table',
        'create view',
        'create policy',
        'create trigger',
        'create index',
        'alter table',
        'alter view',
        'alter policy',
        'drop ',
        'insert into',
        'update public.',
        'delete from',
        'truncate',
      ]) {
        expect(executable, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('changes no policy, no view and no existing grant', () {
      // Every grant and revoke in the file is on one of the two functions.
      final privileges = RegExp(r'\b(?:grant|revoke)\b[^;]*;', dotAll: true)
          .allMatches(executable)
          .map((m) => squash(m.group(0)!))
          .toList();
      expect(privileges, hasLength(4));
      for (final statement in privileges) {
        expect(
          statement,
          anyOf(contains('on function public.$record(uuid)'),
              contains('on function public.$topPlayers(uuid)')),
        );
        expect(statement, isNot(contains(' on table ')));
        expect(statement, isNot(contains(' on public.v_')));
      }
    });
  });

  group('anon gains exactly two functions and no relation', () {
    test('each is revoked from everybody first, then granted on purpose', () {
      final flat = squash(statements);
      for (final name in [record, topPlayers]) {
        final revoke = 'revoke all on function public.$name(uuid) '
            'from public, anon, authenticated, service_role;';
        final grant = 'grant execute on function public.$name(uuid) '
            'to anon, authenticated, service_role;';
        expect(flat, contains(revoke), reason: '$name: revoke');
        expect(flat, contains(grant), reason: '$name: grant');
        expect(flat.indexOf(revoke), lessThan(flat.indexOf(grant)),
            reason: '$name: the defaults are cleared before the grant');
      }
    });

    test('and there are only two grants to anon in the whole file', () {
      expect(
        RegExp(r'grant execute[^;]*to anon').allMatches(executable).length,
        2,
      );
      expect(RegExp(r'grant select[^;]*anon').hasMatch(executable), isFalse);
      expect(RegExp(r'grant (insert|update|delete|all)').hasMatch(executable),
          isFalse);
    });

    test('none of the five broad football views is touched', () {
      // Comments name them to explain why they are left alone; the executable
      // text -- the only part that can change a privilege -- never does.
      expect(executable, isNot(contains('v_football')));
      for (final view in [
        'v_football_completed_matches',
        'v_football_match_participants',
        'v_football_match_lineup',
        'v_football_community_stats',
        'v_football_community_player_stats',
      ]) {
        expect(executable, isNot(contains(view)), reason: view);
      }
    });

    test('across every migration, no broad football view is left to anon', () {
      // Replayed in order: a later revoke undoes an earlier grant, so what is
      // asserted is the schema's final state rather than any one file. 0093 is
      // in the replay, which is the point.
      const broad = [
        'v_football_completed_matches',
        'v_football_match_participants',
        'v_football_match_lineup',
        'v_football_community_stats',
        'v_football_community_player_stats',
      ];
      final files = Directory('../supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) =>
            a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last));
      expect(files.map((f) => f.uri.pathSegments.last), contains(file));

      final granted = <String>{};
      final statement = RegExp(r'\b(grant|revoke)\b[^;]*;', dotAll: true);
      for (final f in files) {
        final text = f
            .readAsStringSync()
            .replaceAll('\r\n', '\n')
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('--'))
            .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
            .join('\n');
        for (final match in statement.allMatches(text)) {
          final part = match.group(0)!;
          if (!RegExp(r'\banon\b').hasMatch(part)) continue;
          for (final view in broad) {
            if (!RegExp('public\\.$view\\b').hasMatch(part)) continue;
            match.group(1) == 'grant'
                ? granted.add(view)
                : granted.remove(view);
          }
        }
      }
      expect(granted, isEmpty);
    });
  });

  group('what a visitor may learn', () {
    test('the record is exactly the four figures and the community id', () {
      expect(returnsOf(record), [
        'community_id uuid',
        'completed_matches int',
        'players int',
        'goals int',
        'mvp_count int',
      ]);
    });

    test('a Top Players row is exactly the approved columns, in order', () {
      expect(returnsOf(topPlayers), [
        'community_id uuid',
        'user_id uuid',
        'display_name text',
        'avatar_path text',
        'overall_rating numeric',
        'matches_played int',
        'goals int',
        'mvp_count int',
      ]);
    });

    test('no private column is reachable through either', () {
      for (final name in [record, topPlayers]) {
        final body = functionBody(name);
        for (final forbidden in [
          'phone',
          'email',
          'date_of_birth',
          'auth_user_id',
          'join_code',
          'invitation',
          'owner_id',
          'created_by',
          'recorded_by',
          'is_system_admin',
          'suspended',
          'suspension',
          'profile_visibility',
          'age_visible',
          'primary_position',
          'secondary_position',
          'professional_guest',
          'select *',
        ]) {
          expect(body, isNot(contains(forbidden)),
              reason: '$name must not be able to return $forbidden');
        }
      }
    });

    test('an upcoming match has no roster to leak', () {
      // The only way a future registration could reach a visitor is through
      // these tables; neither function joins one.
      for (final name in [record, topPlayers]) {
        final body = functionBody(name);
        for (final table in [
          'match_registrations',
          'match_results',
          'match_goals',
          'match_team_assignments',
          'match_professional_guests',
        ]) {
          expect(body, isNot(contains(table)), reason: '$name reads $table');
        }
      }
      // `matches` is read only to count the ones already played.
      final counted = functionBody(record);
      expect(counted, contains("m.status = 'completed' or m.end_at <= now()"));
      expect(counted, contains('select count(*)'));
    });

    test('a Professional Guest cannot appear: the source is keyed by user', () {
      final body = functionBody(topPlayers);
      expect(body, contains('from public.community_statistics cs'));
      expect(body, contains('cs.period_type = \'overall\''));
      expect(body, isNot(contains('professional')));
    });
  });

  group('visibility and safety', () {
    test('both require an active community', () {
      for (final name in [record, topPlayers]) {
        expect(functionBody(name), contains('c.is_active'), reason: name);
      }
    });

    test('Top Players additionally requires an active player', () {
      expect(
          functionBody(topPlayers),
          contains(
              'join public.users u       on u.id = cs.user_id and u.is_active'));
    });

    test('joining policy decides joining, never visibility', () {
      expect(executable, isNot(contains('join_policy')));
    });

    test('every function pins an empty search_path and is read-only', () {
      for (final name in [record, topPlayers]) {
        final body = squash(functionBody(name));
        expect(
          body,
          contains("language sql security definer stable set search_path = ''"),
          reason: '$name is definer, stable, with a fixed empty search_path',
        );
      }
      // Every relation is schema-qualified, which is what an empty search_path
      // requires.
      for (final name in [record, topPlayers]) {
        final body = functionBody(name);
        for (final relation in RegExp(r'\b(?:from|join)\s+(\w+)')
            .allMatches(body)
            .map((m) => m.group(1)!)) {
          expect(relation, anyOf('public', 'lateral'),
              reason: '$name: `$relation` is not schema-qualified');
        }
      }
    });

    test('the same rule as the count of players the record already reports',
        () {
      // 0057's sums, over the `overall` period only.
      final body = functionBody(record);
      expect(body, contains('sum(cs.goals)::int'));
      expect(body, contains('sum(cs.mvp_count)::int'));
      expect(body, contains("cs.period_type = 'overall'"));
    });
  });

  group('the ranking is the approved one, and the cap is eleven', () {
    test('rating, then goals, then MVPs, then name', () {
      final body = squash(functionBody(topPlayers));
      expect(
        body,
        contains('order by coalesce(u.overall_rating, 5.0) desc, '
            'cs.goals desc, cs.mvp_count desc, '
            'u.full_name collate "C" asc, cs.user_id asc limit 11'),
      );
    });

    test('the rating is the Global Rating, not the community one', () {
      final body = functionBody(topPlayers);
      expect(body, contains('coalesce(u.overall_rating, 5.0)::numeric(5,3)'));
      expect(body, isNot(contains('community_scoped_rating')));
    });

    test('the function takes no limit -- a caller cannot ask for more', () {
      expect(executable, isNot(contains('p_limit')));
      expect(
          RegExp(r'\blimit\b').allMatches(functionBody(topPlayers)).length, 1);
      expect(functionBody(topPlayers), contains('limit 11;'));
      // One argument, and it is the community.
      expect(
        squash(functionBody(topPlayers)),
        contains('function public.$topPlayers( p_community_id uuid )'),
      );
    });
  });

  // --------------------------------------------------------------------------
  // The client path
  // --------------------------------------------------------------------------
  group('the guest adapter reads only the narrow contract', () {
    final adapter = File(
      'lib/infrastructure/supabase/supabase_discover_adapter.dart',
    ).readAsStringSync();
    final mapper = File(
      'lib/infrastructure/supabase/mappers/discover_mapper.dart',
    ).readAsStringSync();

    test('through the two functions, by name', () {
      expect(adapter, contains("'public_community_football_record'"));
      expect(adapter, contains("'public_community_top_players'"));
      expect(adapter, contains("params: {'p_community_id': communityId}"));
    });

    test('and through none of the authenticated football views', () {
      // The guest and the signed-in non-member share this adapter's answer, so
      // neither can reach a view the guest may not.
      for (final source in [adapter, mapper]) {
        expect(source, isNot(contains('v_football')));
      }
      expect(adapter, isNot(contains('football_repository')));
      expect(adapter, isNot(contains('supabase_football_adapter')));
    });

    test('the ranking is not re-implemented here or in the repository', () {
      final repository = File(
        'lib/features/discover/discover_repository.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      // The repository also holds Discover's own ordering now (migration 0094:
      // the reader's Wilayat first), and that sorts. What must stay true is that
      // the *players* are taken as the database ranked them, so the repository
      // is checked through the one method that reads them.
      final start = repository
          .indexOf('Future<PublicCommunityFootball> fetchCommunityFootball(');
      expect(start, greaterThanOrEqualTo(0));
      final football = repository.substring(
        start,
        repository.indexOf('\n  }\n', start),
      );
      for (final source in [adapter, mapper, football]) {
        expect(source, isNot(contains('.sort(')));
        expect(source, isNot(contains('.order(\'overall_rating\'')));
      }
      expect(adapter, isNot(contains(".order('overall_rating'")));
    });
  });

  group('the repository', () {
    PublicCommunityTopPlayer player(int n) => PublicCommunityTopPlayer(
          communityId: 'c1',
          userId: 'u$n',
          displayName: 'P$n',
          overallRating: 9.0 - n * 0.1,
          matchesPlayed: 10,
          goals: 20 - n,
          mvpCount: 1,
        );

    const record = PublicCommunityFootballRecord(
      communityId: 'c1',
      completedMatches: 5,
      players: 6,
      goals: 7,
      mvpCount: 8,
    );

    test('takes the Top Players in the order they arrive, capped at eleven',
        () async {
      // Out of rating order on purpose: the repository must not re-rank.
      final arrival = [
        player(3),
        player(1),
        for (var i = 4; i <= 15; i++) player(i),
        player(2)
      ];
      final football = await DiscoverRepository(_Adapter(
        record: record,
        players: arrival,
      )).fetchCommunityFootball('c1');

      expect(football.topPlayers, hasLength(11));
      expect(football.topPlayers.map((p) => p.userId).toList(),
          arrival.take(11).map((p) => p.userId).toList());
      expect(football.topPlayers.first.userId, 'u3');
      expect(football.record.goals, 7);
    });

    test('an empty ranking is an ordinary answer', () async {
      final football = await DiscoverRepository(_Adapter(record: record))
          .fetchCommunityFootball('c1');

      expect(football.topPlayers, isEmpty);
      expect(football.record.completedMatches, 5);
    });

    test('asks for the community it was given, from both contracts', () async {
      final adapter = _Adapter(record: record);
      await DiscoverRepository(adapter).fetchCommunityFootball('c-42');

      expect(adapter.reads, ['record:c-42', 'players:c-42']);
    });

    test('is one section: either read failing fails it', () async {
      expect(
        DiscoverRepository(_Adapter(record: record, failRecord: true))
            .fetchCommunityFootball('c1'),
        throwsA(isA<NotFoundFailure>()),
      );
      expect(
        DiscoverRepository(_Adapter(record: record, failPlayers: true))
            .fetchCommunityFootball('c1'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('and is separate from the community details', () async {
      // A football read that fails must not take the community's name off the
      // page, so the two are different reads with different failure modes.
      final adapter = _Adapter(record: record, failRecord: true);
      final repository = DiscoverRepository(adapter);

      final details = await repository.fetchCommunityDetails('c1');
      expect(details.community.name, 'Al Amerat FC');
      expect(adapter.reads, isEmpty,
          reason: 'loading the community reads no football at all');
    });
  });

  group('the row mappers', () {
    String? avatar(String? path) => path == null ? null : 'https://cdn/$path';

    test('reads a record row', () {
      final value = publicCommunityFootballRecordFromRow({
        'community_id': 'c1',
        'completed_matches': 14,
        'players': 33,
        'goals': 91,
        'mvp_count': 4,
      });

      expect(value.communityId, 'c1');
      expect(value.completedMatches, 14);
      expect(value.players, 33);
      expect(value.goals, 91);
      expect(value.mvpCount, 4);
    });

    test('reads a player row, resolving the picture path', () {
      final value = publicCommunityTopPlayerFromRow({
        'community_id': 'c1',
        'user_id': 'u1',
        'display_name': 'Salim',
        'avatar_path': 'a/b.png',
        'overall_rating': 7.456,
        'matches_played': 12,
        'goals': 9,
        'mvp_count': 2,
      }, avatarUrl: avatar);

      expect(value.userId, 'u1');
      expect(value.displayName, 'Salim');
      expect(value.avatarUrl, 'https://cdn/a/b.png');
      expect(value.overallRating, 7.456);
      expect(value.matchesPlayed, 12);
      expect(value.goals, 9);
      expect(value.mvpCount, 2);
    });

    test('a numeric that arrives as a string, an int or nothing', () {
      double? rating(Object? raw) => publicCommunityTopPlayerFromRow({
            'community_id': 'c1',
            'user_id': 'u1',
            'display_name': 'x',
            'overall_rating': raw,
          }, avatarUrl: avatar)
              .overallRating;

      expect(rating('7.250'), 7.25);
      expect(rating(8), 8.0);
      expect(rating(null), 5.0,
          reason: 'the 5.0 everybody starts on, as the function substitutes');
    });

    test('counters and picture default rather than fail', () {
      final value = publicCommunityTopPlayerFromRow({
        'community_id': 'c1',
        'user_id': 'u1',
        'display_name': null,
        'avatar_path': null,
      }, avatarUrl: avatar);

      expect(value.displayName, '');
      expect(value.avatarUrl, isNull);
      expect(value.matchesPlayed, 0);
      expect(value.goals, 0);
      expect(value.mvpCount, 0);
    });

    test('the model carries no private field to leak', () {
      // Every field a Top Players row has, by construction. A field added here
      // has to be added to the contract and to this list on purpose.
      final source =
          File('lib/features/discover/discover_models.dart').readAsStringSync();
      final start = source.indexOf('class PublicCommunityTopPlayer');
      final body = source.substring(start);
      final fields = RegExp(r'^  final [\w<>?]+ (\w+);', multiLine: true)
          .allMatches(body)
          .map((m) => m.group(1))
          .toList();
      expect(fields, [
        'communityId',
        'userId',
        'displayName',
        'avatarUrl',
        'overallRating',
        'matchesPlayed',
        'goals',
        'mvpCount',
      ]);
    });
  });
}

class _Adapter implements DiscoverAdapter {
  _Adapter({
    required this.record,
    this.players = const [],
    this.failRecord = false,
    this.failPlayers = false,
  });

  final PublicCommunityFootballRecord record;
  final List<PublicCommunityTopPlayer> players;
  final bool failRecord;
  final bool failPlayers;

  final List<String> reads = [];

  @override
  Future<PublicCommunityFootballRecord> fetchCommunityFootballRecord(
    String communityId,
  ) async {
    reads.add('record:$communityId');
    if (failRecord) throw const NotFoundFailure();
    return record;
  }

  @override
  Future<List<PublicCommunityTopPlayer>> fetchCommunityTopPlayers(
    String communityId,
  ) async {
    reads.add('players:$communityId');
    if (failPlayers) throw const NetworkFailure();
    return players;
  }

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) async =>
      const PublicCommunity(
        id: 'c1',
        name: 'Al Amerat FC',
        memberCount: 12,
        upcomingMatchCount: 0,
      );

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async =>
      const [];

  @override
  Future<List<PublicResult>> fetchRecentResults({
    String? communityId,
    int limit = 6,
  }) async =>
      const [];

  @override
  Future<List<PublicCommunity>> fetchCommunities() async => const [];

  @override
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) async => null;

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) async =>
      const [];
}
