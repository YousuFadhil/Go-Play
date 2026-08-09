import 'package:flutter/foundation.dart';

/// The shareable form of a community invitation, and the one place that knows
/// how a join code is written into a link and read back out of one.
///
/// There is a single identifier: the community's join code. The link carries
/// it, the join dialog accepts it typed by hand, and `join_community_by_code`
/// redeems it. Nothing else identifies an invitation.
///
/// Two shapes are produced, because they fail differently:
///
/// * `https://goplay.app/join/<code>` is what gets shared. Messaging apps make
///   it tappable, and someone without the app reaches a page rather than a dead
///   link — once the domain exists. It does not yet: see [webBase].
/// * `goplay://join/<code>` is the app's own scheme, registered in the Android
///   manifest, and is what actually opens the app today.
///
/// Both are parsed, as is a bare code, so an invitation survives being pasted
/// as plain text by an app that flattened the link.
class InviteLink {
  const InviteLink._();

  /// The public host. **Not yet registered**, so an https link only works for
  /// someone who already has the app and whose launcher hands it over. Once the
  /// domain exists it needs `/join/<code>` serving a page and
  /// `/.well-known/assetlinks.json` naming this app, and the https intent
  /// filter in the manifest can be enabled. Nothing else here changes.
  static const webBase = 'https://goplay.app/join/';

  static const scheme = 'goplay';
  static const appBase = '$scheme://join/';

  /// A join code is a number of up to four digits (migration `0030`).
  ///
  /// Four is what `generate_join_code` issues, and the shorter forms are here so
  /// that a code entered by hand is read the same way the database would read
  /// it — the length constraint on the column is `1..4`, and a parser stricter
  /// than the column would reject a code the column accepts.
  static const _codePattern = r'[0-9]{1,4}';

  /// What gets shared. The web form, so it stays a link when the domain lands.
  static String format(String code) => '$webBase$code';

  /// What opens the app today.
  static String appLink(String code) => '$appBase$code';

  /// Pulls a join code out of a link, a pasted message, or a bare code.
  /// Returns null when there is nothing code-shaped in [input].
  static String? parse(String? input) {
    if (input == null) return null;
    final text = input.trim().toUpperCase();
    if (text.isEmpty) return null;

    // Anchored to a join path when one is present, so an unrelated URL that
    // happens to contain code-shaped characters is not mistaken for one. The
    // trailing guard matters now the code is digits: without it a longer number
    // in the path would have its first six taken and read as a code.
    final inLink = RegExp('JOIN/($_codePattern)(?![0-9])').firstMatch(text);
    if (inLink != null) return inLink.group(1);
    if (text.contains('/') || text.contains(':')) return null;

    final bare = RegExp('^($_codePattern)\$').firstMatch(text);
    return bare?.group(1);
  }
}

/// Holds an invitation that arrived from outside the app until a screen can act
/// on it.
///
/// It outlives sign-in on purpose: someone who opens an invitation without an
/// account registers first, and the invitation must still be waiting when they
/// come back. That is also the hook deferred deep linking needs — a code
/// recovered after an install is offered here and travels the same path as a
/// tapped link, so the rest of the app needs no knowledge of where it came from.
class PendingInvite {
  PendingInvite._();

  static final instance = PendingInvite._();

  final code = ValueNotifier<String?>(null);

  /// Accepts anything link-shaped; ignores everything else, so an unrelated
  /// route or a stray paste cannot open the invitation screen.
  void offer(String? input) {
    final parsed = InviteLink.parse(input);
    if (parsed != null) code.value = parsed;
  }

  void clear() => code.value = null;
}
