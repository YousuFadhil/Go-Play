import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/diagnostics.dart';
import '../../features/matches/match_adapter.dart';
import '../../features/matches/match_models.dart';
import 'mappers/match_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the match port. Every write is an RPC that
/// carries its own authorization check and its own validation server-side.
class SupabaseMatchAdapter implements MatchAdapter {
  SupabaseMatchAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  static const _columns =
      'id, community_id, created_by, location, start_at, end_at, '
      'starting_players, max_registration, status, title, description, '
      'roster_order_mode';

  @override
  Future<List<Match>> fetchCommunityMatches(String communityId) =>
      guarded(() async {
        final rows = await _client
            .from('matches')
            .select(_columns)
            .eq('community_id', communityId)
            .order('start_at', ascending: false);
        return [for (final row in rows) matchFromRow(row)];
      });

  @override
  Future<List<Match>> fetchUpcomingMatches() => guarded(() async {
        final rows = await _client
            .from('matches')
            .select('$_columns, community:communities(name)')
            .gt('end_at', DateTime.now().toUtc().toIso8601String())
            .order('start_at', ascending: true);
        return [for (final row in rows) matchFromRow(row)];
      });

  @override
  Future<Match> fetchMatch(String matchId) => guarded(() async {
        final row = await _client
            .from('matches')
            .select('$_columns, community:communities(name)')
            .eq('id', matchId)
            .single();
        return matchFromRow(row);
      });

  /// Why a match did not load, through `match_membership_context` (migration
  /// `0042`).
  ///
  /// `matches_select_community_members` filters a match out of every read for a
  /// non-member, so [fetchMatch] above answers a missing match and an
  /// unreadable one identically. This is the follow-up question, and it is
  /// deliberately a separate call rather than something folded into the read:
  /// the ordinary path is a member opening their own community's match, and it
  /// stays one request.
  @override
  Future<MatchAccessContext> fetchAccessContext(String matchId) => guarded(
        () async {
          final rows = await _client.rpc(
            'match_membership_context',
            params: {'p_match_id': matchId},
          ) as List<dynamic>;
          if (rows.isEmpty) {
            return const MatchAccessContext(
              matchExists: false,
              isMember: false,
            );
          }
          return matchAccessContextFromRow(rows.first as Map<String, dynamic>);
        },
        operation: 'rpc match_membership_context',
      );

  /// Creates a match through `create_match` (migration `0026`).
  ///
  /// This was a direct insert, guarded by `matches_insert_community_admins`.
  /// That policy was correct — it pinned `created_by` to `auth.uid()` and
  /// required the admin role — but it left match creation as the only write in
  /// the product whose guards lived in the client, and a policy can only refuse
  /// a row, not say why. `update_match` and `delete_match` were already RPCs
  /// that validate before they write; this joins them and fails the same way on
  /// the same input.
  ///
  /// One guard is new, and it is not a new rule: `START_IN_PAST`. `update_match`
  /// refuses any match whose start has passed, so a match created in that state
  /// could never be edited or cancelled by its organizer. The insert path
  /// allowed it; this does not.
  ///
  /// `created_by` is no longer sent. The function takes it from `auth.uid()`,
  /// which is what the policy checked it against anyway.
  ///
  /// `max_registration` is still left to the `matches_set_capacity` trigger —
  /// the function does not compute it, and neither does this.
  ///
  /// The function returns the new match's id. Nothing above this needs it: the
  /// create screen pops back to the caller, exactly as it did when the insert
  /// returned nothing. It is discarded here rather than propagated, which keeps
  /// the port's contract unchanged.
  @override
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
  }) =>
      guarded(() async {
        await _client.rpc('create_match', params: {
          'p_community_id': communityId,
          'p_title': title,
          'p_location': location,
          'p_start_at': startAt.toUtc().toIso8601String(),
          'p_end_at': endAt.toUtc().toIso8601String(),
          'p_starting_players': startingPlayers,
          'p_description': null,
        });
      });

  @override
  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    String? description,
  }) =>
      guarded(() async {
        await _client.rpc('update_match', params: {
          'p_match_id': matchId,
          'p_title': title,
          'p_location': location,
          'p_start_at': startAt.toUtc().toIso8601String(),
          'p_end_at': endAt.toUtc().toIso8601String(),
          'p_starting_players': startingPlayers,
          'p_description': description,
        });
      });

  @override
  Future<void> deleteMatch(String matchId) => guarded(
        () async {
          final response =
              await _client.rpc('delete_match', params: {'p_match_id': matchId});
          // `delete_match` returns void, so the body is null. Traced anyway:
          // "the RPC came back, and this is what it came back with" is exactly
          // the fact that separates a server refusal from a client-side fault.
          Diagnostics.trace('rpc', 'delete_match returned ${response.runtimeType}');
        },
        operation: 'rpc delete_match',
      );

  /// The roster, community players and Professional Guests alike, through
  /// `v_match_registrations` (migrations `0048`, `0053`).
  ///
  /// The view rather than the table, and the change is about ordering. A roster
  /// is read in the authoritative participant order — the owner/admin
  /// arrangement when the match has one, community-before-guest arrival order
  /// otherwise — and that is a rule, not a column: it reads a null
  /// `admin_order` as "nobody has arranged this" and falls through to two
  /// derived terms, one of which (`user_id is null`) is not a column at all.
  /// The view computes it once as `roster_position`, using the same expression
  /// `rebalance_roster` cuts at `starting_players`, so ordering by it is
  /// ordering by the thing the starting/reserve split was made over.
  ///
  /// Both identity joins in the view are outer, so a guest's seat is a row with
  /// no profile rather than no row. The split itself is the `status` the server
  /// wrote and is never recomputed from these rows.
  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) =>
      guarded(() async {
        final rows = await _client
            .from('v_match_registrations')
            .select('registration_id, user_id, professional_guest_id, '
                'participant_type, display_name, primary_position, '
                'status, registration_order, admin_order, roster_position')
            .eq('match_id', matchId)
            .order('roster_position', ascending: true);
        return [for (final row in rows) matchRegistrationFromRow(row)];
      });

  /// The two administrative arrangement operations (migration `0053`).
  ///
  /// Each locks the match row, authorizes the caller against the match's
  /// community, activates administrative ordering if this is the first
  /// arrangement, writes the order, re-cuts the starting/reserve split and
  /// reconciles the stored lineup — in one transaction. Nothing here decides
  /// any of it, and neither asks whether the match has started or finished:
  /// the server allows an owner or admin to arrange a roster in every state,
  /// and keeps a played match's split as the record it is.
  @override
  Future<void> setRosterOrder(String matchId, List<String> registrationIds) =>
      guarded(
        () async {
          await _client.rpc('set_match_roster_order', params: {
            'p_match_id': matchId,
            'p_registration_ids': registrationIds,
          });
        },
        operation: 'rpc set_match_roster_order',
      );

  @override
  Future<void> swapParticipants(
    String matchId,
    String firstRegistrationId,
    String secondRegistrationId,
  ) =>
      guarded(
        () async {
          await _client.rpc('swap_match_participants', params: {
            'p_match_id': matchId,
            'p_first_registration_id': firstRegistrationId,
            'p_second_registration_id': secondRegistrationId,
          });
        },
        operation: 'rpc swap_match_participants',
      );

  /// The three Professional Guest operations (migration `0047`).
  ///
  /// Each is a single RPC that locks the match row, authorizes the caller
  /// against the match's community, and applies the approved capacity and
  /// ordering rules. Nothing here decides any of that, and nothing here asks
  /// whether the match is locked or completed — the server allows an owner or
  /// admin to manage guests in every state.
  @override
  Future<String> addProfessionalGuest(String matchId, String name) => guarded(
        () async {
          final id = await _client.rpc('add_professional_guest', params: {
            'p_match_id': matchId,
            'p_name': name,
          });
          return id as String;
        },
        operation: 'rpc add_professional_guest',
      );

  @override
  Future<void> removeProfessionalGuest(String matchId, String guestId) =>
      guarded(
        () async {
          await _client.rpc('remove_professional_guest', params: {
            'p_match_id': matchId,
            'p_guest_id': guestId,
          });
        },
        operation: 'rpc remove_professional_guest',
      );

  @override
  Future<void> renameProfessionalGuest(
    String matchId,
    String guestId,
    String name,
  ) =>
      guarded(
        () async {
          await _client.rpc('rename_professional_guest', params: {
            'p_match_id': matchId,
            'p_guest_id': guestId,
            'p_name': name,
          });
        },
        operation: 'rpc rename_professional_guest',
      );

  @override
  Future<RegistrationStatus> registerForMatch(String matchId) =>
      guarded(() async {
        final result = await _client
            .rpc('register_for_match', params: {'p_match_id': matchId});
        return registrationStatusFromDb(result as String);
      });

  /// Owner/admin registration of another member (`0041`).
  ///
  /// A separate RPC from `register_for_match` rather than a parameter on it:
  /// the actor is always `auth.uid()` server-side and only the *target* travels
  /// from here, so nothing the client sends can decide who is acting. Both
  /// funnel into the same registration transaction, which is why the result is
  /// the same `confirmed`/`reserve` string.
  @override
  Future<RegistrationStatus> addPlayerToMatch(String matchId, String userId) =>
      guarded(() async {
        final result = await _client.rpc(
          'admin_add_player_to_match',
          params: {'p_match_id': matchId, 'p_user_id': userId},
        );
        return registrationStatusFromDb(result as String);
      });

  @override
  Future<void> withdrawFromMatch(String matchId) => guarded(() async {
        await _client
            .rpc('withdraw_from_match', params: {'p_match_id': matchId});
      });

  @override
  Future<void> removePlayer(String matchId, String userId) => guarded(() async {
        await _client.rpc('remove_player', params: {
          'p_match_id': matchId,
          'p_user_id': userId,
        });
      });

  @override
  Future<int?> fetchReservePlayers() => guarded(() async {
        final row = await _client
            .from('app_settings')
            .select('reserve_players')
            .limit(1)
            .maybeSingle();
        return row?['reserve_players'] as int?;
      });
}
