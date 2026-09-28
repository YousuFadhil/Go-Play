import 'generation_evidence.dart';

/// Port for the one Wave 3 generation write: a generated lineup saved together
/// with the evidence of how BTGE produced it.
///
/// Kept apart from `TeamAdapter` on purpose. Every manual edit and every
/// completed-match correction still goes through `TeamAdapter.saveLineup`, and
/// none of them may create generation evidence; a separate port is what makes
/// that structural rather than a flag to remember.
///
/// An implementation saves the lineup and appends the evidence as one atomic
/// operation, and raises a `Failure` when either is refused.
abstract interface class GeneratedLineupAdapter {
  Future<void> saveGeneratedLineup(String matchId, GeneratedTeams generated);
}
