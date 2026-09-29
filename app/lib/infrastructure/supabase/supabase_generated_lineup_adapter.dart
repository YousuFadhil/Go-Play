import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/teams/generated_lineup_adapter.dart';
import '../../features/teams/generation_evidence.dart';
import 'mappers/generation_evidence_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the generated-lineup port.
///
/// One RPC, `save_generated_lineup_v1` (migration `0089`). It saves the lineup
/// through the existing `replace_match_lineup` rules and appends the
/// `btge_generation_runs` row in the same transaction, so this class has
/// nothing to sequence. Who generated, which community and which sequence
/// number are all decided by the database.
class SupabaseGeneratedLineupAdapter implements GeneratedLineupAdapter {
  SupabaseGeneratedLineupAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<void> saveGeneratedLineup(String matchId, GeneratedTeams generated) =>
      guarded(
        () async {
          await _client.rpc(
            'save_generated_lineup_v1',
            params: generatedLineupParams(matchId, generated.evidence),
          );
        },
        operation: 'rpc save_generated_lineup_v1',
      );
}
