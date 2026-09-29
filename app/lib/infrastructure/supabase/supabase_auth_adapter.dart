import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/auth/auth_adapter.dart';
import '../../features/auth/auth_models.dart';
import 'mappers/auth_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the identity port: email + password sign-up and
/// sign-in, Google through the provider's redirect flow, password recovery, and
/// the profile row the trigger creates alongside the account.
class SupabaseAuthAdapter implements AuthAdapter {
  SupabaseAuthAdapter([SupabaseClient? client])
      : this._(
          client ?? SupabaseBootstrap.client,
          SupabaseBootstrap.newImplicitAuthClient,
          kIsWeb,
        );

  /// For tests: the auth client used for the web recovery request, and whether
  /// this run counts as the web, are supplied rather than read from the platform.
  @visibleForTesting
  SupabaseAuthAdapter.forRecoveryTest(
    SupabaseClient client, {
    required GoTrueClient Function() implicitAuthClient,
    required bool web,
  }) : this._(client, implicitAuthClient, web);

  SupabaseAuthAdapter._(
    this._client,
    this._implicitAuthClient,
    this._recoveryWithoutPkce,
  );

  final SupabaseClient _client;
  final GoTrueClient Function() _implicitAuthClient;
  final bool _recoveryWithoutPkce;

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

  /// The provider's event, restated in the application's own terms so nothing
  /// above this file names `AuthChangeEvent`.
  ///
  /// Errors are dropped rather than forwarded. The provider reports a failed
  /// token refresh or a rejected redirect as an error on this same stream, and a
  /// listener with no handler would turn each into an uncaught exception; there
  /// is nothing an event consumer could do with one that the session change
  /// itself does not already say.
  @override
  Stream<AuthEvent> get authEvents => _auth.onAuthStateChange
      .map((state) => _eventFor(state.event))
      .handleError((Object _) {});

  static AuthEvent _eventFor(AuthChangeEvent event) => switch (event) {
        AuthChangeEvent.passwordRecovery => AuthEvent.passwordRecovery,
        AuthChangeEvent.signedIn => AuthEvent.signedIn,
        AuthChangeEvent.signedOut => AuthEvent.signedOut,
        _ => AuthEvent.sessionUpdated,
      };

  /// Google puts the name in `full_name` and, on some accounts, only in `name`.
  /// Either is a suggestion; neither is stored from here.
  @override
  String? get suggestedFullName {
    final metadata = _auth.currentUser?.userMetadata;
    if (metadata == null) return null;
    for (final key in const ['full_name', 'name']) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

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
  /// it creates the row (migration `0021`, and `0092` for when it does not).
  ///
  /// `overall_rating` is not in the payload. The column default is what sets it
  /// to 5.0 (`OP-1`), and metadata is client-supplied — a rating sent from here
  /// would be a system-managed value taken from the sign-up request.
  ///
  /// Whether a session comes back is the project's Email Confirmation setting.
  /// With it off, the response carries one and the account is signed in; with it
  /// on, it carries none. That is read off the response rather than assumed, so
  /// the same build is right under both.
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
  }) =>
      guarded(() async {
        final response = await _auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: redirectTo,
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
        return response.session != null
            ? SignUpOutcome.signedIn
            : SignUpOutcome.confirmationRequired;
      });

  @override
  Future<void> resendSignupConfirmation({
    required String email,
    required String redirectTo,
  }) =>
      guarded(() async {
        await _auth.resend(
          type: OtpType.signup,
          email: email,
          emailRedirectTo: redirectTo,
        );
      });

  /// The provider's own redirect flow, through the deep-link handling
  /// `supabase_flutter` already carries: on Android the browser returns to
  /// `goplay://login-callback`, on the web the page navigates away and comes
  /// back to `<origin>/login-callback`, and the SDK completes the exchange
  /// either way. No Google SDK is involved and nothing in the app parses the
  /// callback.
  ///
  /// `false` from the launcher means the browser could not be opened, which is
  /// the only failure that can be known here; anything the provider refuses
  /// arrives later, on the return trip.
  @override
  Future<void> signInWithGoogle({required String redirectTo}) =>
      guarded(() async {
        final launched = await _auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: redirectTo,
        );
        if (!launched) throw const AuthenticationFailure();
      });

  /// **On the web the recovery email is requested without a PKCE challenge.**
  ///
  /// The app's Auth flow is PKCE: a request stores a one-time *verifier* in the
  /// browser that made it, and the emailed link can only be redeemed by a browser
  /// that still holds that verifier. That is right for everything that returns to
  /// the page it started from, and wrong for an email: a phone opens the link in
  /// whatever its mail app is set to use, which is routinely not the browser the
  /// person asked in. Requested in Safari and opened in Chrome, the link reached
  /// a page with no verifier, the SDK refused the exchange **before making any
  /// request**, and the person was left on the public page with no session and
  /// nothing said.
  ///
  /// So the web asks the provider for the implicit form instead: the link returns
  /// with the session in its address fragment
  /// (`.../login-callback/recovery#access_token=...&type=recovery`) and redeems in
  /// any browser. The app's own client, which is PKCE, already understands that
  /// form: it exchanges the fragment for a session and reports a recovery, and
  /// the rest of the recovery path -- the durable record, the gate, the reset
  /// screen -- is identical.
  ///
  /// What stays PKCE: sign-up, Google, and every other flow, and recovery on
  /// Android, where the link opens the installed app and its own storage holds
  /// the verifier. The trade is tokens in a URL fragment for the length of one
  /// redirect -- the form these links took before PKCE -- and the SDK removes them
  /// from the address as soon as it has read them. A recovery link that carries
  /// no session in the URL at all (`token_hash`, from a custom email template)
  /// would need no such trade; that is provider configuration and is not assumed
  /// here.
  @override
  Future<void> requestPasswordReset(
    String email, {
    required String redirectTo,
  }) =>
      guarded(() async {
        if (!_recoveryWithoutPkce) {
          await _auth.resetPasswordForEmail(email, redirectTo: redirectTo);
          return;
        }
        final implicit = _implicitAuthClient();
        try {
          await implicit.resetPasswordForEmail(email, redirectTo: redirectTo);
        } finally {
          implicit.dispose();
        }
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

  /// `get_my_account_state()` (migration `0092`), about the caller only and
  /// with three answers where [isCurrentUserActive] has two.
  ///
  /// **An answer this file does not recognise is a failure, not a default.** The
  /// gate fails closed on a failure; mapping a token it has never heard of to
  /// `active` would be the one mistake that opens the door.
  @override
  Future<AccountState> fetchAccountState() => guarded(
        () async {
          if (_auth.currentUser == null) {
            throw const AuthenticationFailure();
          }
          final result = await _client.rpc('get_my_account_state');
          return switch (result) {
            'ACTIVE' => AccountState.active,
            'SUSPENDED' => AccountState.suspended,
            'PROFILE_REQUIRED' => AccountState.profileRequired,
            _ => throw const UnknownFailure(),
          };
        },
        operation: 'rpc get_my_account_state',
      );

  /// `complete_my_player_profile` (migration `0092`). The database acts for the
  /// session's own user, so no id is sent, and it sets the rating and every
  /// other system-managed column itself, so none is sent either.
  @override
  Future<void> completePlayerProfile({
    required String fullName,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition position,
    required PlayerPosition? secondaryPosition,
  }) =>
      guarded(
        () async {
          await _client.rpc('complete_my_player_profile', params: {
            'p_full_name': fullName,
            'p_phone': phone,
            'p_date_of_birth': dateOnlyToDb(dateOfBirth),
            'p_primary_position': playerPositionToDb(position),
            // Left out when there is none, so the function's own default is
            // what says "no secondary position".
            if (secondaryPosition != null)
              'p_secondary_position': playerPositionToDb(secondaryPosition),
          });
        },
        operation: 'rpc complete_my_player_profile',
      );

  @override
  Future<void> signOut() => guarded(() => _auth.signOut());
}
