import 'community_models.dart';

/// The community aggregate's port into the data provider.
///
/// Every type named here is a Domain Model (OP-3), and every implementation
/// converts its provider's exceptions into a `Failure` before returning
/// (OP-5). Nothing in this contract knows that Supabase exists, which is what
/// lets the provider be replaced without touching a repository, a use case or
/// a screen.
abstract interface class CommunityAdapter {
  /// Communities the signed-in user belongs to.
  Future<List<Community>> fetchMyCommunities();

  /// Every community the signed-in user is allowed to see. The split between
  /// joined and discoverable is a product decision and belongs above this
  /// layer (OP-2).
  Future<List<Community>> fetchAllCommunities();

  Future<Community> fetchCommunity(String communityId);

  /// Creates a community with the caller as owner. Returns its id.
  Future<String> createCommunity({
    required String name,
    String? description,
    required JoinPolicy joinPolicy,
  });

  /// Joins a community whose policy is open. Returns the community id.
  Future<String> joinCommunity(String communityId);

  /// Joins a community by its join code. Returns the community id.
  Future<String> joinCommunityByCode(String code);

  Future<void> setJoinPolicy(
    String communityId, {
    required JoinPolicy joinPolicy,
  });

  /// The community's join code, for an owner or an admin.
  ///
  /// A call of its own rather than a field of [Community], because it is a
  /// credential and not a property: migration `0056` revoked SELECT on the
  /// column, so no community read carries one and this is the only path to it.
  /// Anyone below the admin role is refused with an `AuthorizationFailure`,
  /// which is the server's answer and not a check made above this layer.
  Future<String> fetchJoinCode(String communityId);

  /// What a shared invitation offers. Readable without a session.
  Future<CommunityInvitePreview> previewInvite(String code);

  /// Issues a new join code and returns it.
  Future<String> regenerateJoinCode(String communityId);

  Future<void> deleteCommunity(String communityId);
}
