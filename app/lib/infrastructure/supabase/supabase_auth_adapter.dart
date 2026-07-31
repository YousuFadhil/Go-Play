import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool get isSignedIn => _auth.currentSession != null;

  @override
  Stream<bool> get signedInChanges =>
      _auth.onAuthStateChange.map((_) => _auth.currentSession != null);

  @override
  Future<String?> fetchCurrentUserFullName() => guarded(() async {
        final id = currentUserId;
        if (id == null) return null;
        final row = await _client
            .from('users')
            .select('full_name')
            .eq('id', id)
            .maybeSingle();
        return row?['full_name'] as String?;
      });

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
  }) =>
      guarded(() async {
        await _auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': fullName,
            'primary_position': playerPositionToDb(position),
            'phone': phone,
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

  @override
  Future<void> signOut() => guarded(() => _auth.signOut());
}
