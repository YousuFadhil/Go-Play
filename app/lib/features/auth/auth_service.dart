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

  /// Basic sanity check for an email address.
  static bool isValidEmail(String input) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input.trim());
  }

  /// Identity is email+password; phone is stored as profile contact info
  /// (see Docs/10-Design-Decisions.md DD-02).
  Future<void> register({
    required String email,
    required String phone,
    required String password,
    required String fullName,
    required PlayerPosition position,
  }) async {
    await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'primary_position': position.dbValue,
        'phone': normalizePhone(phone),
      },
    );
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> logout() => _auth.signOut();
}
