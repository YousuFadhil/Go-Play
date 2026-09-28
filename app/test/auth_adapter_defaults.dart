import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';

/// The [AuthAdapter] members added by the authentication modernization, with
/// defaults, for the fakes that predate them.
///
/// About a dozen tests fake the whole port by hand, and none of them is about
/// Google, password recovery or the profile-completion path. Mixing this in
/// keeps each of them compiling — and honest — without a copy of six unrelated
/// stubs apiece: anything that is *called* and was not expected still throws.
///
/// The one member with real behaviour is [fetchAccountState], and it derives
/// from [isCurrentUserActive] so a fake that already says whether its account is
/// active keeps saying it. It can never answer "profile required": a fake that
/// wants that overrides it, as `auth_modernization_test.dart` does.
mixin AuthAdapterDefaults implements AuthAdapter {
  @override
  Stream<AuthEvent> get authEvents => const Stream.empty();

  @override
  String? get suggestedFullName => null;

  @override
  Future<AccountState> fetchAccountState() async =>
      await isCurrentUserActive() ? AccountState.active : AccountState.suspended;

  @override
  Future<void> resendSignupConfirmation({
    required String email,
    required String redirectTo,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signInWithGoogle({required String redirectTo}) =>
      throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(
    String email, {
    required String redirectTo,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> completePlayerProfile({
    required String fullName,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition position,
    required PlayerPosition? secondaryPosition,
  }) =>
      throw UnimplementedError();
}
