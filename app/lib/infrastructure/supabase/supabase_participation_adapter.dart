import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/results/participation_adapter.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

class SupabaseParticipationAdapter implements ParticipationAdapter {
  SupabaseParticipationAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<void> confirm(String matchId) => guarded(
        () async {
          await _client.rpc(
            'confirm_match_participation',
            params: {'p_match_id': matchId},
          );
        },
        operation: 'rpc confirm_match_participation',
      );
}
