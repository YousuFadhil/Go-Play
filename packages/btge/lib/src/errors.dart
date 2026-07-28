/// Input rejection. Specification §4.3 and `BTGE-PF-2`.
///
/// A player missing a required input is a caller error. The engine rejects the
/// request rather than substituting a default — it must never invent a rating,
/// a date of birth, or a primary position.
library;

enum BtgeErrorCode {
  /// Fewer players than the configured minimum (`OP-2`).
  tooFewPlayers,

  /// More than 30 players (`BTGE-PF-1`, `BTGE-PF-2`).
  tooManyPlayers,

  /// Two players share an id (§4.3).
  duplicatePlayerId,

  /// A required Core Player Input was absent or unusable (§4.1).
  missingRequiredInput,
}

class BtgeInputError implements Exception {
  const BtgeInputError(this.code, this.message);

  final BtgeErrorCode code;
  final String message;

  @override
  String toString() => 'BtgeInputError(${code.name}): $message';
}
