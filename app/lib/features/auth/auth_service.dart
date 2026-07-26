import 'package:flutter/foundation.dart';
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

/// Why a sign-in or sign-up did not go through. The screens show a message
/// for each of these; the SDK exception behind it stays in this file.
enum AuthFailure {
  /// The request never reached the server.
  network,

  /// The credentials were rejected.
  rejected,

  /// Sign-up hit an address that is already registered.
  emailAlreadyUsed,

  /// Anything else.
  unknown,
}

class AuthFailureException implements Exception {
  const AuthFailureException(this.failure);

  final AuthFailure failure;

  @override
  String toString() => 'AuthFailureException($failure)';
}

/// Wraps Supabase authentication for email + password sign-up and sign-in.
class AuthService {
  AuthService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  Session? get currentSession => _auth.currentSession;

  /// Emits true while a session exists. The auth gate listens to this so the
  /// widget layer never subscribes to Supabase itself.
  Stream<bool> get signedInChanges =>
      _auth.onAuthStateChange.map((_) => _auth.currentSession != null);

  /// Id of the signed-in user, or null when there is no session. Screens read
  /// identity through here rather than reaching for the Supabase client.
  String? get currentUserId => _auth.currentUser?.id;

  /// First name of the signed-in user, for greetings. Empty when there is no
  /// session or the profile has no name yet.
  Future<String> fetchCurrentUserFirstName() async {
    final id = currentUserId;
    if (id == null) return '';
    final row = await _client
        .from('users')
        .select('full_name')
        .eq('id', id)
        .maybeSingle();
    final fullName = (row?['full_name'] as String?)?.trim() ?? '';
    return fullName.isEmpty ? '' : fullName.split(RegExp(r'\s+')).first;
  }

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
  }) =>
      _guard('register', () => _signUp(
            email: email,
            localPhone: localPhone,
            password: password,
            fullName: fullName,
            position: position,
          ));

  Future<void> _signUp({
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
  }) =>
      _guard(
        'login',
        () => _auth.signInWithPassword(email: email.trim(), password: password),
      );

  /// Turns the SDK failure into an [AuthFailureException] and keeps the
  /// diagnostic detail in the log, where it was needed to find the original
  /// registration bug.
  Future<void> _guard(String action, Future<void> Function() call) async {
    try {
      await call();
    } on AuthRetryableFetchException catch (e, st) {
      debugPrint('[GoPlay] $action network failure: $e\n$st');
      throw const AuthFailureException(AuthFailure.network);
    } on AuthException catch (e, st) {
      debugPrint(
          '[GoPlay] $action auth failure (${e.statusCode}/${e.code}): $e\n$st');
      final alreadyUsed =
          e.statusCode == '422' || e.message.toLowerCase().contains('already');
      throw AuthFailureException(
          alreadyUsed ? AuthFailure.emailAlreadyUsed : AuthFailure.rejected);
    } catch (e, st) {
      debugPrint('[GoPlay] $action unexpected failure: $e\n$st');
      throw const AuthFailureException(AuthFailure.unknown);
    }
  }

  Future<void> logout() => _auth.signOut();
}
