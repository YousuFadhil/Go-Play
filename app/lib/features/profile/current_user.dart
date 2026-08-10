import 'package:flutter/foundation.dart';

import 'profile_models.dart';
import 'profile_repository.dart';

/// The signed-in player's own profile, held once for the whole session.
///
/// The header shows their name and picture on every screen, and every screen
/// reading that for itself would be one round trip per navigation for a value
/// that changes only when the player edits it. So it is read once, held here,
/// and re-read when something makes it stale — a profile save, or a sign-in by
/// somebody else.
///
/// It holds no failure state. A header is not worth an error message: a profile
/// that cannot be read leaves the notifier null, and the header falls back to a
/// generic figure. Whatever actually went wrong is reported by the screen whose
/// work depends on it.
class CurrentUser {
  CurrentUser._();

  static final CurrentUser instance = CurrentUser._();

  /// The loaded profile, or null when none has been read yet or the read
  /// failed. Widgets listen to this rather than fetching for themselves.
  final ValueNotifier<PlayerProfile?> profile = ValueNotifier(null);

  /// Built on first use rather than with this object. Constructing the
  /// production repository reaches the data provider's client, which does not
  /// exist in a widget test — and a header is not a reason for one to fail.
  ProfileRepository? _profiles;
  Future<void>? _inFlight;

  /// Replaces the port, exactly as the repositories take an optional one.
  /// Supplied only by tests; it also drops whatever was loaded, because a
  /// different port answers for a different player.
  @visibleForTesting
  void useRepository(ProfileRepository? repository) {
    _profiles = repository;
    profile.value = null;
    _inFlight = null;
  }

  /// Reads the profile unless it is already held or already being read.
  ///
  /// Several headers can be built in one frame — a screen pushed over another
  /// keeps both alive — and the guard is what stops each of them starting its
  /// own read of the same row.
  Future<void> ensureLoaded() {
    if (profile.value != null) return Future.value();
    return _inFlight ??= refresh();
  }

  /// Re-reads the profile. Called after a save, so the header stops showing the
  /// name the player has just changed.
  Future<void> refresh() async {
    final read = _read();
    _inFlight = read;
    profile.value = await read;
    _inFlight = null;
  }

  /// The read, with every way it can fail folded into "nothing to show".
  Future<PlayerProfile?> _read() async {
    try {
      return await (_profiles ??= ProfileRepository()).fetchMyProfile();
    } catch (_) {
      return null;
    }
  }

  /// Forgets the loaded profile. Signing out must, or the next account to sign
  /// in on this device is greeted by the previous one's name.
  void clear() {
    profile.value = null;
    _inFlight = null;
  }
}

/// The player's first name, or an empty string when there is nothing to use.
String firstNameOf(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp(r'\s+')).first;
}

/// One or two letters standing in for a picture the player has not set.
///
/// First and last word rather than the first two: "Ahmed Al Balushi" is A.B to
/// somebody who knows them, not A.A.
String initialsOf(String fullName) {
  final words = [
    for (final word in fullName.trim().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word.substring(0, 1),
  ];
  if (words.isEmpty) return '';
  if (words.length == 1) return words.first;
  return '${words.first}${words.last}';
}
