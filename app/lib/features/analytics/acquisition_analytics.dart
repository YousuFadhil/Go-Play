import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../sharing/public_link.dart';
import 'acquisition_analytics_repository.dart';

/// Same-session public-link acquisition (Wave 3, design §4).
///
/// Measures one thing: a signed-out reader who arrived through an external
/// public link, and then created a new account in the same running app.
///
/// **Memory only.** Everything below is an ordinary field of this object and
/// dies with the process. Nothing is written to the device, the browser, the
/// account or the profile, so a refresh, a restart or another device is never
/// stitched to an earlier visit — the approved privacy boundary.
///
/// **Never blocking.** Every entry point returns void and does its network work
/// unawaited through a repository that swallows every failure.
///
/// A singleton for the reason `ProductAnalytics` is one: it is observed from
/// the public screens, the registration form and the gate, which share nothing
/// else. Screens reach for [instance]; tests replace it.
class AcquisitionAnalytics {
  AcquisitionAnalytics({
    AcquisitionAnalyticsRepository? repository,
    bool Function()? isSignedIn,
    ValueListenable<PublicLinkTarget?>? pendingTarget,
  })  : _repository = repository ?? AcquisitionAnalyticsRepository(),
        _isSignedInOverride = isSignedIn,
        _pendingTarget = pendingTarget ?? PendingPublicLink.instance.target;

  /// The one every screen uses. Assignable for tests only.
  static AcquisitionAnalytics instance = AcquisitionAnalytics();

  final AcquisitionAnalyticsRepository _repository;
  final bool Function()? _isSignedInOverride;

  /// Which destination arrived from outside the app. [PendingPublicLink] is
  /// the source of truth for that: a screen reached by browsing or by
  /// navigating inside a public page is never the pending target.
  final ValueListenable<PublicLinkTarget?> _pendingTarget;

  AuthService? _auth;

  /// The external arrival recorded (or being recorded) anonymously. Used to
  /// ignore rebuilds and reloads of the same arrival, and to keep the resume
  /// after sign-in from counting it a second time as an authenticated open.
  PublicLinkTarget? _anonymousArrival;

  /// Bumped per arrival and on sign-out, so a late answer for an arrival that
  /// has since been superseded is dropped rather than attributed.
  int _arrival = 0;

  /// The server-generated id of the anonymous open, until it converts or the
  /// reader signs out.
  String? _acquisitionId;

  /// Set by the registration form, only once a new account was created.
  bool _registrationSucceeded = false;

  /// Set by the gate once the signed-in account is confirmed active.
  bool _accountActive = false;

  /// A public destination has finished loading successfully.
  ///
  /// Recorded only when it is the external arrival, the reader is signed out,
  /// and this arrival has not been recorded already. Failed or not-found
  /// destinations never call this, so they record nothing.
  void externalArrivalLoaded(PublicLinkTarget target) {
    if (_pendingTarget.value != target) return;
    if (_anonymousArrival == target) return;
    if (!_isSignedOut) return;

    _anonymousArrival = target;
    _acquisitionId = null;
    final arrival = ++_arrival;
    unawaited(_recordOpen(target, arrival));
  }

  Future<void> _recordOpen(PublicLinkTarget target, int arrival) async {
    final id = await _repository.recordAnonymousOpen(target.kind);
    if (arrival != _arrival) return;
    if (id == null) {
      // Nothing was recorded, so there is nothing to deduplicate against.
      if (_anonymousArrival == target) _anonymousArrival = null;
      return;
    }
    _acquisitionId = id;
    _tryComplete();
  }

  /// Whether [target] is the arrival already recorded anonymously — consumed,
  /// because the resume after sign-in is the one place that asks.
  ///
  /// True means the signed-in resume of this target must not record another
  /// `public_link_opened`: the arrival was counted once already.
  bool takeAnonymousArrival(PublicLinkTarget target) {
    if (_anonymousArrival != target) return false;
    _anonymousArrival = null;
    return true;
  }

  /// A **new** account was just created. Login never calls this.
  void registrationSucceeded() {
    _registrationSucceeded = true;
    _tryComplete();
  }

  /// The gate confirmed the signed-in account is active.
  void accountActive() {
    _accountActive = true;
    _tryComplete();
  }

  /// The session ended. Whatever acquisition was pending ends with it.
  void signedOut() {
    _arrival++;
    _anonymousArrival = null;
    _acquisitionId = null;
    _registrationSucceeded = false;
    _accountActive = false;
  }

  /// Records the conversion once all three halves are known, in whichever
  /// order they arrived, then forgets it. The database remains the final
  /// guard: it refuses an account created before the open.
  void _tryComplete() {
    final id = _acquisitionId;
    if (id == null || !_registrationSucceeded || !_accountActive) return;
    _acquisitionId = null;
    _registrationSucceeded = false;
    unawaited(_repository.recordSignupCompleted(id));
  }

  /// Fails closed: when the session cannot be read, nothing is recorded.
  bool get _isSignedOut {
    try {
      final override = _isSignedInOverride;
      if (override != null) return !override();
      return !(_auth ??= AuthService()).isSignedIn;
    } catch (_) {
      return false;
    }
  }
}
