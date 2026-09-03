import 'dart:typed_data';

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

  // --- the community's picture ----------------------------------------------
  //
  // Three operations rather than one, because they are three different things
  // to the server: an object written into a bucket, a column written through a
  // function, and an object removed. The order they are used in is a product
  // decision and belongs to the repository, which is the only place that knows
  // what a *replacement* is.

  /// Uploads [bytes] as the community's picture and answers where it now is.
  ///
  /// A new object each time — the name carries a version — so this never
  /// overwrites the picture the community is currently showing. Nothing about
  /// the community row changes here: until [setLogoUrl] is called this is an
  /// object nobody is pointing at.
  Future<String> uploadCommunityLogo({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
  });

  /// Points the community at [logoUrl], or at nothing when it is null.
  ///
  /// Goes through `set_community_logo`, which is the only path there is: the
  /// table's UPDATE policy is owner-only and an admin may still do this. The
  /// server decides whether the caller may, and refuses with an
  /// [AuthorizationFailure] when they may not.
  Future<void> setCommunityLogo(String communityId, String? logoUrl);

  /// Removes the object [logoUrl] names, if it names one in this app's bucket.
  ///
  /// Separate from [setCommunityLogo] because tidying up storage is not the
  /// same event as changing what a community shows, and must never be able to
  /// undo it. A URL from anywhere else is left alone.
  Future<void> deleteCommunityLogoObject(String logoUrl);
}
