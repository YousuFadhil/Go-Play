import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/auth/auth_adapter.dart';
import '../../features/auth/auth_models.dart';
import 'mappers/auth_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the identity port: email + password sign-up and
/// sign-in, and the profile row the trigger creates alongside the account.
class SupabaseAuthAdapter implements AuthAdapter {
  SupabaseAuthAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  String? get currentUserEmail => _auth.currentUser?.email;

  @override
  bool get isSignedIn => _auth.currentSession != null;

  @override
  Stream<bool> get signedInChanges =>
      _auth.onAuthStateChange.map((_) => _auth.currentSession != null);

  /// The signed-in player's name, read through `v_user_profile` (migration
  /// `0025`) like every other profile read.
  ///
  /// The view is `security_invoker = on`, so this is still
  /// `authenticated_select_active_users` deciding what comes back; only the
  /// relation named has changed. A missing row stays a null name rather than a
  /// failure — a greeting is not worth refusing over.
  @override
  Future<String?> fetchCurrentUserFullName() => guarded(() async {
        final id = currentUserId;
        if (id == null) return null;
        final row = await _client
            .from('v_user_profile')
            .select('full_name')
            .eq('user_id', id)
            .maybeSingle();
        return row?['full_name'] as String?;
      });

  /// The profile arrives as Auth metadata, which `handle_new_user` reads when
  /// it creates the row (migration `0021`).
  ///
  /// `overall_rating` is not in the payload. The column default is what sets it
  /// to 5.0 (`OP-1`), and metadata is client-supplied — a rating sent from here
  /// would be a system-managed value taken from the sign-up request.
  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
  }) =>
      guarded(() async {
        await _auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': fullName,
            'primary_position': playerPositionToDb(position),
            'phone': phone,
            'date_of_birth': dateOnlyToDb(dateOfBirth),
            // Left out rather than sent as null: the trigger reads a missing
            // key and an empty one the same way, and no secondary position is
            // an absence rather than a value (`BTGE-SC-6`).
            if (secondaryPosition != null)
              'secondary_position': playerPositionToDb(secondaryPosition),
          },
        );
      });

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) =>
      guarded(() async {
        await _auth.signInWithPassword(email: email, password: password);
      });

  /// Both credentials move through `updateUser`, which is the only thing that
  /// may touch `auth.users`. Nothing in `public.users` mirrors either of them,
  /// so there is no second row to keep in step.
  ///
  /// Whether the new address has to be confirmed before it replaces the old one
  /// is the project's Auth setting, not this adapter's business: the call
  /// returns once the provider has accepted the request, and the screen says so
  /// rather than claiming the address has already changed.
  @override
  Future<void> changeEmail(String email, {required String redirectTo}) =>
      guarded(() async {
        await _auth.updateUser(
          UserAttributes(email: email),
          emailRedirectTo: redirectTo,
        );
      });

  @override
  Future<void> changePassword(String password) => guarded(() async {
        await _auth.updateUser(UserAttributes(password: password));
      });

  /// `is_current_user_active()` (migration `0062`), which answers only about
  /// the caller: it takes no argument, so it cannot be asked about anybody
  /// else. Without a session there is nobody to ask about, so this reports that
  /// rather than spending a request to be told the same thing.
  @override
  Future<bool> isCurrentUserActive() => guarded(
        () async {
          if (_auth.currentUser == null) {
            throw const AuthenticationFailure();
          }
          final result = await _client.rpc('is_current_user_active');
          return result == true;
        },
        operation: 'rpc is_current_user_active',
      );

  @override
  Future<void> signOut() => guarded(() => _auth.signOut());
}
