import 'dart:async';

import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';

/// One call to [AuthAdapter.signUp], as the port received it.
class SignUpCall {
  const SignUpCall({
    required this.email,
    required this.password,
    required this.fullName,
    required this.position,
    required this.phone,
    required this.dateOfBirth,
    required this.secondaryPosition,
    required this.redirectTo,
  });

  final String email;
  final String password;
  final String fullName;
  final PlayerPosition position;
  final String phone;
  final DateTime dateOfBirth;
  final PlayerPosition? secondaryPosition;
  final String redirectTo;
}

/// One call to [AuthAdapter.completePlayerProfile].
class CompletionCall {
  const CompletionCall({
    required this.fullName,
    required this.phone,
    required this.dateOfBirth,
    required this.position,
    required this.secondaryPosition,
  });

  final String fullName;
  final String phone;
  final DateTime dateOfBirth;
  final PlayerPosition position;
  final PlayerPosition? secondaryPosition;
}

/// The whole identity port, scriptable and recording.
///
/// It behaves like the provider where that matters to the tests written against
/// it: every session event updates whether there is a session and is announced on
/// both streams, and signing out ends the session before it returns.
///
/// **[authEvents] carries live events only** — a listener that starts late sees
/// nothing from before. That is the contract the application is written against
/// (`AuthAdapter.authEvents`), and it is why the tests for a recovery that
/// survives a restart drive the application's own durable state rather than a
/// fake that remembers an event for them.
///
/// Nothing here knows about Supabase.
class ScriptedAuthAdapter implements AuthAdapter {
  ScriptedAuthAdapter({
    bool signedIn = false,
    this.accountState = AccountState.active,
    this.suggestedName,
    String email = 'player@example.com',
  })  : _signedIn = signedIn,
        _email = email;

  bool _signedIn;
  final String _email;

  // ---- scripted answers ------------------------------------------------------

  AccountState accountState;
  Object? accountStateError;
  String? suggestedName;
  SignUpOutcome signUpOutcome = SignUpOutcome.signedIn;
  Object? signUpFailure;
  Object? resendFailure;
  Object? googleFailure;
  Object? resetFailure;
  Object? changePasswordFailure;
  Object? signOutFailure;

  /// What verifying an emailed code raises, for either purpose. Null means the
  /// code is accepted.
  Object? verifyFailure;

  /// Called at the moment a code is being verified, **before** the provider
  /// would create a session, so a test can observe what was already true then --
  /// for instance, that the durable recovery record was already on disk.
  void Function()? onVerify;

  /// With [signOutFailure] set: the failure happens before the session is
  /// cleared, so the session is still there afterwards.
  bool signOutLeavesSession = false;

  /// Called at the moment of sign-out, before the session ends, so a test can
  /// observe what else was true then (for instance, that the durable recovery
  /// record is still set).
  void Function()? onSignOut;
  Object? completionFailure;

  /// A completed profile is what makes the account `active`; leave it true to
  /// script the ordinary case, or set false to script a database that has not
  /// caught up.
  bool completionActivatesAccount = true;

  // ---- what the port was asked -------------------------------------------------

  int accountStateChecks = 0;
  int signOuts = 0;
  final signUps = <SignUpCall>[];
  final resends = <({String email, String redirectTo})>[];
  final googleRedirects = <String>[];
  final resetRequests = <({String email, String redirectTo})>[];
  final completions = <CompletionCall>[];
  final passwordChanges = <String>[];

  /// Every code the port was asked to verify. The tests read these to prove what
  /// reached the provider; nothing else in the application keeps a code.
  final recoveryVerifications = <({String email, String code})>[];
  final signupVerifications = <({String email, String code})>[];

  /// Everything that touched the session, in order, so a test can assert that a
  /// password was changed *before* the session was ended.
  final journal = <String>[];

  // ---- the streams -------------------------------------------------------------

  final _signedInController = StreamController<bool>.broadcast();
  final _eventController = StreamController<AuthEvent>.broadcast();

  /// What the provider does when something happens to the session.
  void emit(AuthEvent event, {required bool signedIn}) {
    _signedIn = signedIn;
    _signedInController.add(_signedIn);
    _eventController.add(event);
  }

  @override
  bool get isSignedIn => _signedIn;

  @override
  Stream<bool> get signedInChanges => _signedInController.stream;

  @override
  Stream<AuthEvent> get authEvents => _eventController.stream;

  @override
  String? get currentUserId => _signedIn ? 'u1' : null;

  @override
  String? get currentUserEmail => _signedIn ? _email : null;

  @override
  String? get suggestedFullName => suggestedName;

  @override
  Future<String?> fetchCurrentUserFullName() async => 'Ali';

  // ---- account state -----------------------------------------------------------

  @override
  Future<AccountState> fetchAccountState() async {
    accountStateChecks++;
    if (accountStateError != null) throw accountStateError!;
    return accountState;
  }

  @override
  Future<bool> isCurrentUserActive() async =>
      (await fetchAccountState()) == AccountState.active;

  @override
  Future<void> completePlayerProfile({
    required String fullName,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition position,
    required PlayerPosition? secondaryPosition,
  }) async {
    if (completionFailure != null) throw completionFailure!;
    completions.add(CompletionCall(
      fullName: fullName,
      phone: phone,
      dateOfBirth: dateOfBirth,
      position: position,
      secondaryPosition: secondaryPosition,
    ));
    if (completionActivatesAccount) accountState = AccountState.active;
  }

  // ---- registration and sign-in ------------------------------------------------

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
    required String redirectTo,
  }) async {
    if (signUpFailure != null) throw signUpFailure!;
    signUps.add(SignUpCall(
      email: email,
      password: password,
      fullName: fullName,
      position: position,
      phone: phone,
      dateOfBirth: dateOfBirth,
      secondaryPosition: secondaryPosition,
      redirectTo: redirectTo,
    ));
    return signUpOutcome;
  }

  @override
  Future<void> resendSignupConfirmation({
    required String email,
    required String redirectTo,
  }) async {
    if (resendFailure != null) throw resendFailure!;
    resends.add((email: email, redirectTo: redirectTo));
  }

  @override
  Future<void> signInWithGoogle({required String redirectTo}) async {
    if (googleFailure != null) throw googleFailure!;
    googleRedirects.add(redirectTo);
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  // ---- recovery ----------------------------------------------------------------

  @override
  Future<void> requestPasswordReset(
    String email, {
    required String redirectTo,
  }) async {
    if (resetFailure != null) throw resetFailure!;
    resetRequests.add((email: email, redirectTo: redirectTo));
  }

  /// Accepting a recovery code is what the provider does for a recovery link: it
  /// stores the session **and then** says so, both before the call returns.
  @override
  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    journal.add('verifyRecoveryCode');
    onVerify?.call();
    if (verifyFailure != null) throw verifyFailure!;
    recoveryVerifications.add((email: email, code: code));
    emit(AuthEvent.passwordRecovery, signedIn: true);
  }

  /// Accepting a sign-up code confirms the address and signs the account in.
  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    journal.add('verifySignupCode');
    onVerify?.call();
    if (verifyFailure != null) throw verifyFailure!;
    signupVerifications.add((email: email, code: code));
    emit(AuthEvent.signedIn, signedIn: true);
  }

  @override
  Future<void> changePassword(String password) async {
    if (changePasswordFailure != null) throw changePasswordFailure!;
    journal.add('changePassword');
    passwordChanges.add(password);
  }

  @override
  Future<void> changeEmail(String email, {required String redirectTo}) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {
    signOuts++;
    journal.add('signOut');
    onSignOut?.call();
    if (signOutFailure != null && signOutLeavesSession) throw signOutFailure!;
    // A provider clears its own copy of the session before it tells the server,
    // so the session is over even when the call then fails.
    emit(AuthEvent.signedOut, signedIn: false);
    if (signOutFailure != null) throw signOutFailure!;
  }

  Future<void> dispose() async {
    await _signedInController.close();
    await _eventController.close();
  }
}
