import '../../infrastructure/supabase/supabase_generated_lineup_adapter.dart';
import 'generated_lineup_adapter.dart';
import 'generation_evidence.dart';

/// Stores what BTGE generated as the match's lineup, with its evidence.
///
/// The generation half of what `TeamRepository.saveLineup` used to do for the
/// Teams screen. The lineup is written by the same authoritative database
/// writer as before; what this adds is the immutable record of the proposal,
/// in the same transaction.
class GeneratedLineupRepository {
  GeneratedLineupRepository([GeneratedLineupAdapter? adapter])
      : _adapter = adapter ?? SupabaseGeneratedLineupAdapter();

  final GeneratedLineupAdapter _adapter;

  /// Saves [generated] as the lineup of [matchId] and records its evidence.
  ///
  /// Both or neither: a refused save leaves no evidence, and evidence that
  /// cannot be recorded leaves the lineup as it was.
  Future<void> save(String matchId, GeneratedTeams generated) =>
      _adapter.saveGeneratedLineup(matchId, generated);
}
