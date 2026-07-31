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
}
