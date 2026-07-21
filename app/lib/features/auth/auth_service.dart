import 'package:supabase_flutter/supabase_flutter.dart';

/// Player field positions stored in the database.
enum PlayerPosition {
  gk('GK'),
  def('DEF'),
  mid('MID'),
  fwd('FWD');

  const PlayerPosition(this.dbValue);

  final String dbValue;
}

/// Wraps Supabase authentication for phone + password sign-up and sign-in.
class AuthService {
  AuthService([GoTrueClient? auth])
      : _auth = auth ?? Supabase.instance.client.auth;

  final GoTrueClient _auth;

  Session? get currentSession => _auth.currentSession;

  /// Normalizes user input to digits only (E.164 without the plus sign),
  /// e.g. "+966 50 123 4567" -> "966501234567".
  static String normalizePhone(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Basic sanity check for an international phone number.
  static bool isValidPhone(String normalized) {
    return RegExp(r'^[1-9][0-9]{9,14}$').hasMatch(normalized);
  }

  Future<void> register({
    required String phone,
    required String password,
    required String fullName,
    required PlayerPosition position,
  }) async {
    await _auth.signUp(
      phone: normalizePhone(phone),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'primary_position': position.dbValue,
      },
    );
  }

  Future<void> login({
    required String phone,
    required String password,
  }) async {
    await _auth.signInWithPassword(
      phone: normalizePhone(phone),
      password: password,
    );
  }

  Future<void> logout() => _auth.signOut();
}
