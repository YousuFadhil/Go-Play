import '../../infrastructure/supabase/supabase_player_intelligence_adapter.dart';
import 'player_intelligence_adapter.dart';

/// Player-facing derived intelligence.
///
/// Product reasoning stays above the provider. The database returns the one
/// aggregate that cannot be read safely through the membership-scoped
/// rating_history policy; the screen only decides how to present it.
class PlayerIntelligenceRepository {
  PlayerIntelligenceRepository([PlayerIntelligenceAdapter? adapter])
      : _adapter = adapter ?? SupabasePlayerIntelligenceAdapter();

  final PlayerIntelligenceAdapter _adapter;

  Future<PlayerRatingTrend> fetchRatingTrend(String userId) =>
      _adapter.fetchRatingTrend(userId);
}
