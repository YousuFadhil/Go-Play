import '../../../features/auth/auth_models.dart';

/// How a player position is stored. The only encoding identity needs.
String playerPositionToDb(PlayerPosition position) => switch (position) {
      PlayerPosition.gk => 'GK',
      PlayerPosition.def => 'DEF',
      PlayerPosition.mid => 'MID',
      PlayerPosition.fwd => 'FWD',
    };
