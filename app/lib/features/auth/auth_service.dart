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

  /// Oman country calling code. The MVP is Oman-only, so the code is fixed
  /// and the user enters just the 8-digit local number.
  static const String omanCallingCode = '+968';

  /// Keeps digits only from user input, e.g. "9012 3456" -> "90123456".
  static String digitsOnly(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// An Oman local mobile number is exactly 8 digits.
  static bool isValidOmanLocalPhone(String input) {
    return RegExp(r'^[0-9]{8}$').hasMatch(digitsOnly(input));
  }

  /// Builds the stored E.164 phone from an 8-digit local number,
  /// e.g. "90123456" -> "+96890123456".
  static String toOmanE164(String localPhone) {
    return '$omanCallingCode${digitsOnly(localPhone)}';
  }

  /// Basic sanity check for an email address.
  static bool isValidEmail(String input) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input.trim());
  }

  /// Identity is email+password; phone is stored as profile contact info
  /// (see Docs/10-Design-Decisions.md DD-02). [localPhone] is the 8-digit
  /// Oman number; it is stored as +968XXXXXXXX.
  Future<void> register({
    required String email,
    required String localPhone,
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
        'phone': toOmanE164(localPhone),
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
