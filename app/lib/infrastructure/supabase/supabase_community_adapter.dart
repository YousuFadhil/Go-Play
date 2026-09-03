import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/communities/community_adapter.dart';
import '../../features/communities/community_models.dart';
import 'mappers/community_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_community_logos.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the community port.
///
/// Writes go through Postgres RPCs so multi-step operations stay atomic and
/// RLS stays simple (no custom backend).
class SupabaseCommunityAdapter implements CommunityAdapter {
  SupabaseCommunityAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  /// What a community read is allowed to ask for.
  ///
  /// `join_code` is not on this list and cannot be put back: migration `0056`
  /// revoked SELECT on the column for both client roles, so a request naming it
  /// is refused by the server rather than filtered here. The organizer's read is
  /// [fetchJoinCode].
  ///
  /// `logo_url` is named here and is granted by migration `0061`: `0056`
  /// revoked table SELECT and granted columns one at a time, so a column that
  /// is not on this list is a column the server refuses rather than one the
  /// client merely forgot to ask for.
  static const _columns =
      'id, owner_id, name, description, join_policy, logo_url';

  @override
  Future<List<Community>> fetchMyCommunities() => guarded(() async {
        final userId = _client.auth.currentUser!.id;
        final rows = await _client
            .from('community_members')
            .select('community:communities($_columns)')
            .eq('user_id', userId)
            .order('created_at', ascending: false);

        return [
          for (final row in rows)
            communityFromRow(row['community'] as Map<String, dynamic>),
        ];
      });

  @override
  Future<List<Community>> fetchAllCommunities() => guarded(() async {
        final rows = await _client
            .from('communities')
            .select(_columns)
            .order('created_at', ascending: false);
        return [for (final row in rows) communityFromRow(row)];
      });

  @override
  Future<Community> fetchCommunity(String communityId) => guarded(() async {
        final row = await _client
            .from('communities')
            .select(_columns)
            .eq('id', communityId)
            .single();
        return communityFromRow(row);
      });

  @override
  Future<String> createCommunity({
    required String name,
    String? description,
    required JoinPolicy joinPolicy,
  }) =>
      guarded(() async {
        final result = await _client.rpc('create_community', params: {
          'p_name': name,
          'p_description': description,
          'p_join_policy': joinPolicyToDb(joinPolicy),
        });
        return result as String;
      });

  @override
  Future<String> joinCommunity(String communityId) => guarded(() async {
        final result = await _client
            .rpc('join_community', params: {'p_community_id': communityId});
        return result as String;
      });

  @override
  Future<String> joinCommunityByCode(String code) => guarded(() async {
        final result = await _client
            .rpc('join_community_by_code', params: {'p_code': code});
        return result as String;
      });

  /// The `communities_update_owner` policy is what enforces ownership here;
  /// RLS filters the row out for anyone else, so the update would silently
  /// match nothing — asking for the row back is how that becomes an error
  /// instead of a no-op that looks like success.
  @override
  Future<void> setJoinPolicy(
    String communityId, {
    required JoinPolicy joinPolicy,
  }) =>
      guarded(() async {
        final rows = await _client
            .from('communities')
            .update({'join_policy': joinPolicyToDb(joinPolicy)})
            .eq('id', communityId)
            .select('id');
        if (rows.isEmpty) throw const AuthorizationFailure();
      });

  /// The join code, through `community_join_code` (migration `0055`).
  ///
  /// An RPC rather than a column, because the question is not "which row" but
  /// "may this caller hold the credential" — and the function is what decides,
  /// from `has_community_role(..., 'admin')`. It refuses with `NOT_AUTHORIZED`,
  /// which reaches this layer as an `AuthorizationFailure`.
  @override
  Future<String> fetchJoinCode(String communityId) => guarded(
        () async {
          final code = await _client.rpc(
            'community_join_code',
            params: {'p_community_id': communityId},
          );
          return code as String;
        },
        operation: 'rpc community_join_code',
      );

  @override
  Future<CommunityInvitePreview> previewInvite(String code) =>
      guarded(() async {
        final rows = await _client.rpc('preview_community_invite', params: {
          'p_code': code,
        }) as List<dynamic>;
        if (rows.isEmpty) return const CommunityInvitePreview(isValid: false);
        return invitePreviewFromRow(rows.first as Map<String, dynamic>);
      });

  @override
  Future<String> regenerateJoinCode(String communityId) => guarded(() async {
        final code = await _client.rpc('regenerate_join_code', params: {
          'p_community_id': communityId,
        });
        return code as String;
      });

  @override
  Future<void> deleteCommunity(String communityId) => guarded(() async {
        await _client.rpc('delete_community', params: {
          'p_community_id': communityId,
        });
      });

  // --- the community's picture ----------------------------------------------

  /// Writes a new object into `community-logos`.
  ///
  /// `upsert: false`, unlike the avatar upload. An avatar overwrites one fixed
  /// name; a logo's name carries a timestamp and is new every time, so an
  /// upsert here would only mean "silently overwrite whatever happened to
  /// collide" — which, if it ever did, is a bug worth hearing about.
  ///
  /// The write is authorized by `community_logos_insert_organizer`, which reads
  /// the community out of the object's first folder and asks the caller's role
  /// in it. This layer sends no role and could not: there is nowhere to put one.
  @override
  Future<String> uploadCommunityLogo({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      guarded(() async {
        final path = SupabaseCommunityLogos.pathFor(communityId, fileExtension);
        await _client.storage.from(SupabaseCommunityLogos.bucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType:
                    SupabaseCommunityLogos.contentTypeFor(fileExtension),
              ),
            );
        return SupabaseCommunityLogos.publicUrl(_client, path);
      });

  /// The only write to `communities.logo_url` there is.
  ///
  /// An RPC rather than an update, and not for convenience: generic UPDATE on
  /// the table is owner-only (`communities_update_owner`) and an admin may
  /// still change the picture. `set_community_logo` is the narrow authority
  /// that difference requires — it checks `auth.uid()`'s community role itself
  /// and writes one column.
  @override
  Future<void> setCommunityLogo(String communityId, String? logoUrl) =>
      guarded(() async {
        await _client.rpc('set_community_logo', params: {
          'p_community_id': communityId,
          'p_logo_url': logoUrl,
        });
      });

  /// Removes the object, when the URL names one of ours.
  ///
  /// A URL this app did not write returns no path and nothing is deleted. That
  /// is the safe direction: a stray object costs storage, and deleting the
  /// wrong one costs somebody their picture.
  @override
  Future<void> deleteCommunityLogoObject(String logoUrl) => guarded(() async {
        final path = SupabaseCommunityLogos.pathOf(logoUrl);
        if (path == null) return;
        await _client.storage
            .from(SupabaseCommunityLogos.bucket)
            .remove([path]);
      });
}
