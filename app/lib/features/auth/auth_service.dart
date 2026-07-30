import '../../infrastructure/supabase/supabase_auth_adapter.dart';
import 'auth_adapter.dart';
import 'auth_models.dart';

/// Identity: sign-up, sign-in, the session stream, and the profile name.
///
/// Everything provider-specific is behind [AuthAdapter]. What stays here is
/// the product's own rules — what a valid Oman number looks like, how it is
/// stored, and what counts as a first name.
class AuthService {
  AuthService([AuthAdapter? adapter])
      : _adapter = adapter ?? SupabaseAuthAdapter();

  final AuthAdapter _adapter;

  /// Whether a session exists. The auth gate reads this so the widget layer
  /// never sees a provider's session object.
  bool get isSignedIn => _adapter.isSignedIn;

  /// Emits true while a session exists.
  Stream<bool> get signedInChanges => _adapter.signedInChanges;

  /// Id of the signed-in user, or null when there is no session.
  String? get currentUserId => _adapter.currentUserId;

  /// First name of the signed-in user, for greetings. Empty when there is no
  /// session or the profile has no name yet.
  Future<String> fetchCurrentUserFirstName() async {
    final fullName = (await _adapter.fetchCurrentUserFullName())?.trim() ?? '';
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
      _adapter.signUp(
        email: email.trim(),
        password: password,
        fullName: fullName.trim(),
        position: position,
        phone: toOmanE164(localPhone),
      );

  Future<void> login({
    required String email,
    required String password,
  }) =>
      _adapter.signIn(email: email.trim(), password: password);

  Future<void> logout() => _adapter.signOut();
}
