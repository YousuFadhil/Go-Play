/// Balanced Team Generation Engine.
///
/// Pure Dart. No Flutter, no Supabase, no PostgreSQL, no schema. The database
/// is an adapter layer implemented elsewhere; this package operates only on the
/// input contract of `Docs/engineering/BTGE_Engineering_Specification.md` §4.
///
/// Authority, in order:
///   1. `Docs/engineering/BTGE_Design_Knowledge_Base.md` — Design Authority.
///   2. `Docs/engineering/BTGE_Engineering_Specification.md` — Implementation
///      Authority.
///
/// Where this code and those documents disagree, this code is the defect.
library;

export 'src/assignment.dart' show TeamPlan, assignTeam;
export 'src/configuration.dart'
    show BtgeConfiguration, OddCountRule, ToleranceBand;
export 'src/distribution.dart' show TargetPair, TargetShape, deriveTargets;
export 'src/engine.dart'
    show BtgeEngine, candidateRetentionLimit, maxSupportedPlayers;
export 'src/errors.dart' show BtgeErrorCode, BtgeInputError;
export 'src/models.dart'
    show
        AssignmentBasis,
        GoalkeeperMode,
        MatchHistory,
        MatchSettings,
        PastMatch,
        Player,
        Position,
        TeamId;
export 'src/result.dart'
    show Diagnostics, GenerationResult, PlayerAssignment, QualityMetrics;
export 'src/scoring.dart';
