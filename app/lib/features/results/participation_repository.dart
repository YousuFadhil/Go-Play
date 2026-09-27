import '../../infrastructure/supabase/supabase_participation_adapter.dart';
import 'participation_adapter.dart';

class ParticipationRepository {
  ParticipationRepository([ParticipationAdapter? adapter])
      : _adapter = adapter ?? SupabaseParticipationAdapter();

  final ParticipationAdapter _adapter;

  Future<void> confirm(String matchId) => _adapter.confirm(matchId);
}
