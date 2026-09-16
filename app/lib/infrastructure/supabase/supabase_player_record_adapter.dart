import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/profile/player_record_adapter.dart';
import '../../features/profile/player_record_models.dart';
import 'mappers/player_record_mapper.dart';
import 'mappers/profile_mapper.dart';
import 'supabase_avatars.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the player-record port.
///
/// Five RPCs, in two families that are never mixed:
///
///   * `player_recent_form`, `player_recent_highlights` — `authenticated`
///     only, and the richer answer: which match, which community, when.
///   * `public_player_profile`, `public_player_recent_form`,
///     `public_player_recent_highlight` — the narrow contracts migration `0079`
///     grants `anon`, which carry no match id and no kick-off time.
///
/// **Which family is called is decided by the caller having a session, never
/// by what a screen would like to show.** There is no fallback from one to the
/// other in this class: a signed-in reader whose authenticated read fails gets
/// a failure, not a quietly reduced answer that would look like the public one
/// and could not be told apart from it.
class SupabasePlayerRecordAdapter implements PlayerRecordAdapter {
  SupabasePlayerRecordAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<RecentForm> fetchRecentForm(String userId, {int limit = 5}) => guarded(
        () async {
          final rows = await _client.rpc(
            'player_recent_form',
            params: {'p_user_id': userId, 'p_limit': limit},
          ) as List<dynamic>;
          return recentFormFromRows(rows);
        },
        operation: 'rpc player_recent_form',
      );

  @override
  Future<List<RecentHighlight>> fetchRecentHighlights(String userId) => guarded(
        () async {
          final rows = await _client.rpc(
            'player_recent_highlights',
            params: {'p_user_id': userId},
          ) as List<dynamic>;
          // No rows is "nothing eligible", the ordinary answer for most
          // players and never an error.
          return highlightCandidatesFromRows(rows);
        },
        operation: 'rpc player_recent_highlights',
      );

  @override
  Future<PublicPlayerRecord?> fetchPublicRecord(
    String userId, {
    int limit = 5,
  }) =>
      guarded(
        () async {
          // Issued together because they are independent and the screen needs
          // all three before it can draw anything. Three round trips in
          // parallel is one wait, and asking in sequence would make a public
          // profile the slowest screen in the product.
          final reads = await Future.wait([
            _client.rpc(
              'public_player_profile',
              params: {'p_user_id': userId},
            ),
            _client.rpc(
              'public_player_recent_form',
              params: {'p_user_id': userId, 'p_limit': limit},
            ),
            _client.rpc(
              'public_player_recent_highlight',
              params: {'p_user_id': userId},
            ),
          ]);

          final profileRows = reads[0] as List<dynamic>;
          // No profile is no record: the player does not exist, or is not
          // active. The same answer for both, so a guessed id cannot tell them
          // apart — which is the database's rule and is simply carried here.
          if (profileRows.isEmpty) return null;

          final profileRow = profileRows.first as Map<String, dynamic>;
          return PublicPlayerRecord(
            profile: playerProfileViewFromRow(
              // `is_self` is not a column of the public contract — there is no
              // session for it to be about — and the mapper already reads a
              // missing one as false.
              profileRow,
              avatarUrl: SupabaseAvatars.publicUrl(
                _client,
                profileRow['avatar_path'] as String?,
              ),
            ),
            form: publicRecentFormFromRows(reads[1] as List<dynamic>),
            // The same rule the signed-in reading applies, over the public
            // candidates.
            highlight: RecentHighlight.mostRecent(
              highlightCandidatesFromRows(reads[2] as List<dynamic>),
            ),
          );
        },
        operation: 'rpc public_player_profile',
      );
}
