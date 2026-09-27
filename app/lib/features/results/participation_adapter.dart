/// Port for the one Wave 2 participation assertion.
///
/// The participant list itself remains the stored match lineup. This port only
/// records that an authorized organizer confirmed that current lineup as the
/// factual record of who actually played.
abstract interface class ParticipationAdapter {
  Future<void> confirm(String matchId);
}
