import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/discover/discover_adapter.dart';
import '../../features/discover/discover_models.dart';
import 'mappers/discover_mapper.dart';
import 'supabase_avatars.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the public browsing port.
///
/// Every read here goes through a view rather than a table, and that is the
/// design rather than a convenience. `v_public_communities` and
/// `v_public_upcoming_matches` (migration `0033`) are not `security_invoker`, so
/// they run with the view owner's privileges and answer a request that carries
/// no session — which is what makes browsing before signing in possible without
/// loosening a single policy on `communities`, `matches`, `community_members` or
/// `match_registrations`.
///
/// The views also decide what a guest is given. Neither exposes a join code or a
/// user id, so there is no column list here that could accidentally ask for one.
class SupabaseDiscoverAdapter implements DiscoverAdapter {
  SupabaseDiscoverAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  static const _communityColumns =
      'id, name, description, member_count, upcoming_match_count, logo_url';

  static const _matchColumns =
      'id, community_id, community_name, title, location, start_at, end_at, '
      'starting_players, open_slots';

  /// Newest first, so a community created today leads the list. The view keeps
  /// `created_at` for exactly this and for nothing the guest is shown.
  @override
  Future<List<PublicCommunity>> fetchCommunities() => guarded(() async {
        final rows = await _client
            .from('v_public_communities')
            .select(_communityColumns)
            .order('created_at', ascending: false);
        return [for (final row in rows) publicCommunityFromRow(row)];
      });

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) =>
      guarded(() async {
        final row = await _client
            .from('v_public_communities')
            .select(_communityColumns)
            .eq('id', communityId)
            .single();
        return publicCommunityFromRow(row);
      });

  /// One match, upcoming or completed, through `public_match_detail`
  /// (migration `0079`). No rows means the match is not publicly visible — see
  /// the port.
  @override
  Future<List<PublicResult>> fetchRecentResults({
    String? communityId,
    int limit = 5,
  }) =>
      guarded(
        () async {
          // Two functions rather than one with a nullable argument: the
          // community-scoped one is what a community page is allowed to ask,
          // and keeping them apart is what makes each one's grant reviewable.
          final rows = await (communityId == null
              ? _client.rpc('public_recent_results', params: {'p_limit': limit})
              : _client.rpc(
                  'public_community_recent_results',
                  params: {'p_community_id': communityId, 'p_limit': limit},
                )) as List<dynamic>;

          return [
            for (final row in rows.cast<Map<String, dynamic>>())
              publicResultFromRow(row, avatarUrl: _avatar),
          ];
        },
        operation: 'rpc public_recent_results',
      );

  @override
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) =>
      guarded(() async {
        final rows = await _client.rpc(
          'public_match_detail',
          params: {'p_match_id': matchId},
        ) as List<dynamic>;
        if (rows.isEmpty) return null;
        return publicMatchDetailFromRow(
          rows.first as Map<String, dynamic>,
          avatarUrl: _avatar,
        );
      }, operation: 'rpc public_match_detail');

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) =>
      guarded(() async {
        final rows = await _client.rpc(
          'public_match_lineup',
          params: {'p_match_id': matchId},
        ) as List<dynamic>;
        return [
          for (final row in rows.cast<Map<String, dynamic>>())
            publicLineupEntryFromRow(row, avatarUrl: _avatar),
        ];
      }, operation: 'rpc public_match_lineup');

  String? _avatar(String? path) => SupabaseAvatars.publicUrl(_client, path);

  /// Soonest first: a landing page is about what happens next, so the ordering
  /// is the opposite of the community list's on purpose.
  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) =>
      guarded(() async {
        var query =
            _client.from('v_public_upcoming_matches').select(_matchColumns);
        if (communityId != null) {
          query = query.eq('community_id', communityId);
        }
        final rows = await query.order('start_at', ascending: true);
        return [for (final row in rows) publicMatchFromRow(row)];
      });
}
