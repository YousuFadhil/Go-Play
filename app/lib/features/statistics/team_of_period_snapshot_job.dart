import '../../infrastructure/supabase/mappers/team_of_period_mapper.dart';
import 'team_of_period_models.dart';
import 'team_of_period_selector.dart';
import 'team_of_period_snapshot.dart';

/// What the snapshot job needs from the database, and nothing more.
///
/// Four calls, all service-role (migration `0079`): the communities to
/// evaluate, the closed-period window and evidence for one of them, and the
/// one writer. **Pure Dart**, like everything this job imports, so it runs
/// from a plain `dart run` without the Flutter app around it.
abstract interface class TeamOfPeriodSnapshotPort {
  /// Active communities, in a stable order.
  Future<List<String>> activeCommunityIds();

  /// `community_period_xi_closed_window` — exactly one row.
  Future<Map<String, dynamic>> closedWindow(
    String communityId,
    String periodType,
  );

  /// `community_period_xi_closed_evidence` — one row per candidate.
  Future<List<Map<String, dynamic>>> closedEvidence(
    String communityId,
    String periodType,
  );

  /// `record_team_of_period_snapshot`. Throws [SnapshotRefused] carrying the
  /// database's error token when the writer refuses.
  Future<void> record(Map<String, Object?> params);
}

/// The writer said no, with one of its stable tokens
/// (`SNAPSHOT_ALREADY_FINAL`, `PERIOD_NOT_CLOSED`, ...).
class SnapshotRefused implements Exception {
  const SnapshotRefused(this.token);

  final String token;

  @override
  String toString() => 'SnapshotRefused($token)';
}

/// What happened for one community.
enum SnapshotStatus {
  /// Dry run: the snapshot was built and nothing was written.
  planned,

  /// Written, and now final.
  written,

  /// A snapshot for this period already existed. Final means final, so this is
  /// success — which is what makes a retried or duplicated run harmless.
  alreadyFinal,

  /// Anything else. The job carries on with the next community and reports
  /// failure at the end.
  failed,
}

class SnapshotOutcome {
  const SnapshotOutcome({
    required this.communityId,
    required this.status,
    this.snapshot,
    this.detail,
  });

  final String communityId;
  final SnapshotStatus status;
  final TeamOfPeriodSnapshot? snapshot;
  final String? detail;

  bool get ok => status != SnapshotStatus.failed;
}

/// Stores the Team of Period of the period that has just closed.
///
/// **It decides nothing.** For each active community it reads the closed
/// period's evidence, hands it to [TeamOfPeriodSelector] — the one selection
/// algorithm — and writes down what the selector returned. The mapping is the
/// app's own mapper and the payload is [TeamOfPeriodSnapshot]'s, so a stored
/// award and the award the Team of Period screen shows for the same evidence
/// cannot differ.
class TeamOfPeriodSnapshotJob {
  const TeamOfPeriodSnapshotJob(this._port);

  final TeamOfPeriodSnapshotPort _port;

  Future<List<SnapshotOutcome>> run({
    required TeamOfPeriodKind kind,
    required String selectorVersion,
    required bool write,
  }) async {
    final periodType = teamOfPeriodKindToDb(kind);
    final outcomes = <SnapshotOutcome>[];

    for (final communityId in await _port.activeCommunityIds()) {
      try {
        final window = teamOfPeriodWindowFromRow(
          await _port.closedWindow(communityId, periodType),
        );
        final candidates = [
          for (final row in await _port.closedEvidence(communityId, periodType))
            teamOfPeriodCandidateFromRow(row),
        ];

        // The same guard the repository applies before selecting: evidence
        // and window read either side of a boundary describe two periods, and
        // an award built from both would be about neither.
        for (final candidate in candidates) {
          if (candidate.periodIdentity != window.identity) {
            throw StateError('window and evidence describe different periods');
          }
        }

        final snapshot = TeamOfPeriodSnapshot.fromSelection(
          communityId: communityId,
          team: TeamOfPeriodSelector.select(
            window: window,
            candidates: candidates,
          ),
          selectorVersion: selectorVersion,
        );

        if (!write) {
          outcomes.add(SnapshotOutcome(
            communityId: communityId,
            status: SnapshotStatus.planned,
            snapshot: snapshot,
          ));
          continue;
        }

        try {
          await _port.record(snapshot.toRpcParams());
          outcomes.add(SnapshotOutcome(
            communityId: communityId,
            status: SnapshotStatus.written,
            snapshot: snapshot,
          ));
        } on SnapshotRefused catch (refusal) {
          outcomes.add(SnapshotOutcome(
            communityId: communityId,
            status: refusal.token == 'SNAPSHOT_ALREADY_FINAL'
                ? SnapshotStatus.alreadyFinal
                : SnapshotStatus.failed,
            snapshot: snapshot,
            detail: refusal.token,
          ));
        }
      } catch (error) {
        outcomes.add(SnapshotOutcome(
          communityId: communityId,
          status: SnapshotStatus.failed,
          detail: '$error',
        ));
      }
    }
    return outcomes;
  }
}
