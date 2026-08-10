import '../../../core/failures.dart';
import '../../../features/auth/auth_models.dart';

/// How a player position is stored. The only encoding identity needs.
String playerPositionToDb(PlayerPosition position) => switch (position) {
      PlayerPosition.gk => 'GK',
      PlayerPosition.def => 'DEF',
      PlayerPosition.mid => 'MID',
      PlayerPosition.fwd => 'FWD',
    };

/// The same vocabulary read back.
///
/// It is constrained by the schema, so a value outside it means the database
/// and this build disagree — an infrastructure fault rather than something to
/// guess at, exactly as an unreadable position is in `team_mapper.dart`.
PlayerPosition playerPositionFromDb(String value) => switch (value) {
      'GK' => PlayerPosition.gk,
      'DEF' => PlayerPosition.def,
      'MID' => PlayerPosition.mid,
      'FWD' => PlayerPosition.fwd,
      _ => throw const InfrastructureFailure(),
    };

/// How a date of birth is stored: `YYYY-MM-DD`, which is the `date` column's
/// own form.
///
/// Never an ISO instant. `toIso8601String` would carry a time of day and a zone
/// towards a column that holds neither, and a birthday sent as UTC midnight
/// from east of Greenwich arrives as the previous day.
String dateOnlyToDb(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
