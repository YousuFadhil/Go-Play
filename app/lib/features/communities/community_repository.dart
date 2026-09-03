import 'dart:typed_data';

import '../../core/failures.dart';
import '../../infrastructure/supabase/supabase_community_adapter.dart';
import 'community_adapter.dart';
import 'community_models.dart';

/// Data access for the community aggregate itself: what exists, what the user
/// can see, and creating, joining or deleting one. Membership lives in
/// MemberRepository.
///
/// Everything provider-specific is behind [CommunityAdapter]. What remains
/// here is the product's own reasoning: how the overview is split, what a join
/// attempt means, and how input is normalised before it is stored.
class CommunityRepository {
  CommunityRepository([CommunityAdapter? adapter])
      : _adapter = adapter ?? SupabaseCommunityAdapter();

  final CommunityAdapter _adapter;

  /// Communities the current user belongs to.
  Future<List<Community>> fetchMyCommunities() => _adapter.fetchMyCommunities();

  /// What the user can see and act on: [mine] are joined communities,
  /// [discover] is everything else. Every community is visible now; what
  /// differs is whether joining needs the code.
  Future<({List<Community> mine, List<Community> discover})>
      fetchCommunitiesOverview() async {
    final mine = await _adapter.fetchMyCommunities();
    final myIds = {for (final community in mine) community.id};
    final all = await _adapter.fetchAllCommunities();

    final discover = [
      for (final community in all)
        if (!myIds.contains(community.id)) community,
    ];
    return (mine: mine, discover: discover);
  }

  /// The community's join code — an owner's or an admin's read.
  ///
  /// Not part of [fetchCommunity]: the code is a credential, and migration
  /// `0056` took it out of every community read so that holding a community row
  /// is no longer the same thing as holding the way into it. A Player asking is
  /// refused by the server, which is where the rule lives.
  Future<String> fetchJoinCode(String communityId) =>
      _adapter.fetchJoinCode(communityId);

  /// Creates a community and adds the creator as owner. Returns its id.
  Future<String> createCommunity({
    required String name,
    String? description,
    required JoinPolicy joinPolicy,
  }) {
    final trimmed = description?.trim();
    return _adapter.createCommunity(
      name: name.trim(),
      description: trimmed == null || trimmed.isEmpty ? null : trimmed,
      joinPolicy: joinPolicy,
    );
  }

  /// Joins a community whose policy is OPEN. One that requires its code
  /// answers [NeedsJoinCode] instead, and is joined through
  /// [joinCommunityByCode].
  Future<JoinCommunityOutcome> joinCommunity(String communityId) =>
      _join(() => _adapter.joinCommunity(communityId));

  /// Joins a community by its join code, however the user typed it.
  Future<JoinCommunityOutcome> joinCommunityByCode(String code) =>
      _join(() => _adapter.joinCommunityByCode(code.trim().toUpperCase()));

  /// Both join paths share their outcomes. Reading the reason is this layer's
  /// job precisely so that no screen has to: above here these are three normal
  /// answers, not failures carrying a reason. Anything else is still a failure
  /// and travels on untouched.
  Future<JoinCommunityOutcome> _join(Future<String> Function() attempt) async {
    try {
      return JoinedCommunity(await attempt());
    } on ValidationFailure catch (failure) {
      if (failure.reason == FailureReason.joinCodeRequired) {
        return const NeedsJoinCode();
      }
      rethrow;
    } on ConflictFailure catch (failure) {
      if (failure.reason == FailureReason.alreadyMember) {
        return const AlreadyMember();
      }
      rethrow;
    }
  }

  /// Owner only; the database enforces that.
  Future<void> setJoinPolicy(
    String communityId, {
    required JoinPolicy joinPolicy,
  }) =>
      _adapter.setJoinPolicy(communityId, joinPolicy: joinPolicy);

  /// What a shared invitation offers. Works signed out, which is the point:
  /// someone deciding whether to install the app can see what they are joining.
  Future<CommunityInvitePreview> previewInvite(String code) =>
      _adapter.previewInvite(code);

  /// Issues a new join code, which is how a leaked invitation is invalidated:
  /// the code is the only invitation identifier, so replacing it retires the
  /// old one. Members, matches and registrations are untouched. Owner and admin.
  Future<String> regenerateJoinCode(String communityId) =>
      _adapter.regenerateJoinCode(communityId);

  Future<Community> fetchCommunity(String communityId) =>
      _adapter.fetchCommunity(communityId);

  /// Owner only. Removes the community and everything belonging to it.
  Future<void> deleteCommunity(String communityId) =>
      _adapter.deleteCommunity(communityId);

  // --- the community's picture ----------------------------------------------

  /// Gives the community a new picture, and answers where it is.
  ///
  /// **The order is the product rule, and it is this:**
  ///
  ///   1. upload the new object, under a name nothing is pointing at yet;
  ///   2. point the community at it;
  ///   3. only then remove the old object.
  ///
  /// Every other order has a window in which the community shows nothing.
  /// Deleting first and uploading second leaves a broken picture if the upload
  /// fails; overwriting the same object name leaves the previous picture in
  /// caches with no way to tell them otherwise. This way the community is
  /// showing a real picture at every instant — the old one until step 2
  /// commits, the new one after.
  ///
  /// **If step 2 fails the community keeps the picture it had.** The new object
  /// is then an orphan nobody is pointing at, and it is removed on a best-effort
  /// basis before the failure is passed on. The failure is what the caller
  /// hears: the change did not happen.
  ///
  /// Owner and admin, decided by `set_community_logo` on the server.
  Future<String> changeCommunityLogo({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
    String? previousLogoUrl,
  }) async {
    final url = await _adapter.uploadCommunityLogo(
      communityId: communityId,
      bytes: bytes,
      fileExtension: fileExtension,
    );

    try {
      await _adapter.setCommunityLogo(communityId, url);
    } catch (_) {
      // Nothing points at what was just uploaded, so removing it loses nothing
      // — and leaving it would accumulate a file per failed attempt. The
      // original failure is what matters, so a failure to tidy up is swallowed.
      await _forget(url);
      rethrow;
    }

    // Last, and only once the community is demonstrably showing the new one.
    if (previousLogoUrl != null && previousLogoUrl != url) {
      await _forget(previousLogoUrl);
    }
    return url;
  }

  /// Takes the community's picture away, leaving its initials.
  ///
  /// The reverse order, for the same reason: the column is cleared first, so
  /// the moment the object goes there is already nothing pointing at it. A
  /// community that fails to clear the column keeps a picture that still works.
  ///
  /// **A failed cleanup does not undo the removal.** Restoring the URL to make
  /// storage tidy would put back a picture the organizer asked to be rid of,
  /// and would point at an object that may or may not still exist. A stray file
  /// is the cheaper of the two problems.
  Future<void> removeCommunityLogo({
    required String communityId,
    String? previousLogoUrl,
  }) async {
    await _adapter.setCommunityLogo(communityId, null);
    if (previousLogoUrl != null) await _forget(previousLogoUrl);
  }

  /// Removes an object nobody is pointing at any more, and does not care
  /// whether it worked.
  ///
  /// Cleanup is never the operation the caller asked for. Letting it fail the
  /// call would turn "your picture was changed" into "that did not work" over a
  /// file the reader will never see.
  Future<void> _forget(String url) async {
    try {
      await _adapter.deleteCommunityLogoObject(url);
    } catch (_) {
      // Deliberately swallowed. See above.
    }
  }
}
