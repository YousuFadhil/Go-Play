import '../../infrastructure/supabase/supabase_community_insights_adapter.dart';
import 'community_insights_adapter.dart';

/// Organizer-only Community Intelligence.
///
/// Authorization is still the database's: the RPC refuses any caller below
/// community admin. This repository simply keeps provider details out of the UI.
class CommunityInsightsRepository {
  CommunityInsightsRepository([CommunityInsightsAdapter? adapter])
      : _adapter = adapter ?? SupabaseCommunityInsightsAdapter();

  final CommunityInsightsAdapter _adapter;

  Future<CommunityInsights> fetch(String communityId) =>
      _adapter.fetch(communityId);
}
