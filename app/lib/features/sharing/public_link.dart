import 'package:flutter/foundation.dart';

import '../../core/config.dart';

/// What a public link points at.
///
/// Three kinds and no fourth. A link names a player, a community or a match —
/// the three things the product publishes — and each is identified by its own
/// `uuid`. Adding a kind is a product decision and means editing this enum
/// deliberately, exactly as adding a share card format means editing the
/// canvas.
enum PublicLinkKind {
  player('player'),
  community('community'),
  match('match');

  const PublicLinkKind(this.segment);

  /// The path segment the link is written with: `/player/<id>`.
  final String segment;

  /// The kind [segment] names, or null when it names none.
  static PublicLinkKind? fromSegment(String segment) {
    for (final kind in values) {
      if (kind.segment == segment) return kind;
    }
    return null;
  }
}

/// One public destination: a kind and the thing's id.
@immutable
class PublicLinkTarget {
  const PublicLinkTarget(this.kind, this.id);

  final PublicLinkKind kind;
  final String id;

  /// The link a reader would share for this target.
  String get url => PublicLink.format(kind, id);

  @override
  bool operator ==(Object other) =>
      other is PublicLinkTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'PublicLinkTarget(${kind.segment}, $id)';
}

/// The shareable form of a player, a community or a match, and the one place
/// that knows how one is written into a link and read back out of one.
///
/// **Built the way `InviteLink` is, deliberately.** The product has one
/// deep-link idiom already — a well-known path, parsed from whatever the
/// platform hands over, offered to a holder that a screen picks up — and this
/// is a second destination inside it rather than a second routing system. No
/// router package is introduced and `app.dart`'s Navigator arrangement is
/// unchanged.
///
/// Three shapes are parsed, because a link arrives in three states:
///
///  * `https://<base>/#/player/<id>` — what is shared. The web build serves the
///    app from a hash route (see `NotificationLink`), so the path a browser
///    hands back sits after the `#`; what reaches [parse] is already the part
///    after it.
///  * `goplay://player/<id>` — the app's own scheme, which is what opens the
///    app from a tapped link today.
///  * `/player/<id>` — the bare route, which is what
///    `PlatformDispatcher.defaultRouteName` is on a cold start.
///
/// **Parsing is shape-checking and never authorization.** A well-formed id is
/// only a destination; whether anything may be read at it is answered by the
/// server, against the reader's session, exactly as it is when they arrive from
/// anywhere else in the app.
class PublicLink {
  const PublicLink._();

  /// The public host, from the build configuration. See
  /// [AppConfig.publicWebBase] for why it is not a hard-coded domain.
  static String get webBase => AppConfig.publicWebBase;

  static const scheme = 'goplay';

  /// A `uuid`, which is what every id in this schema is. Restated here rather
  /// than shared with `NotificationLink`: that one guards a notification route
  /// and this one guards a public route, and a single constant would make a
  /// change to either a change to both.
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// The path a target lives at, with no host: `/player/<id>`.
  static String path(PublicLinkKind kind, String id) => '/${kind.segment}/$id';

  /// What gets shared: the web form, so it stays a link in a message.
  ///
  /// The `#` is what makes it a route the deployed single-page app resolves
  /// without server-side rewriting — the same arrangement web push already
  /// relies on.
  static String format(PublicLinkKind kind, String id) =>
      '$webBase/#${path(kind, id)}';

  /// What opens the app directly on a device that has it.
  static String appLink(PublicLinkKind kind, String id) =>
      '$scheme://${kind.segment}/$id';

  /// Pulls a target out of whatever the platform handed over, or null when
  /// there is no public destination in it.
  ///
  /// Anchored to the two-segment shape rather than searching: a URL that merely
  /// contains the word "match" somewhere is not a match link, and an id that is
  /// not id-shaped is not a destination.
  static PublicLinkTarget? parse(String? input) {
    if (input == null) return null;
    final text = input.trim();
    if (text.isEmpty) return null;

    // `Uri.parse` handles `goplay://match/<id>`, `/match/<id>` and a full https
    // URL alike; what differs between them is only where the segments start.
    final uri = Uri.tryParse(text);
    if (uri == null) return null;

    // A custom scheme puts the kind in the authority (`goplay://match/<id>`
    // parses as host `match`, path `/<id>`), while every other form puts both
    // in the path. Both are reduced to one list of segments here so the rule
    // below is stated once.
    final segments = <String>[
      if (uri.scheme == scheme && uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments,
      // A shared web link carries the route in the fragment, and `Uri` does not
      // split that for us.
      if (uri.fragment.isNotEmpty)
        ...Uri.tryParse(uri.fragment)?.pathSegments ?? const <String>[],
    ].where((segment) => segment.isNotEmpty).toList();

    // Read from the end, so a link served from a sub-path — or one the platform
    // handed over with the origin still attached — resolves to the same target.
    for (var i = segments.length - 2; i >= 0; i--) {
      final kind = PublicLinkKind.fromSegment(segments[i].toLowerCase());
      if (kind == null) continue;
      final id = segments[i + 1];
      if (!_uuid.hasMatch(id)) continue;
      return PublicLinkTarget(kind, id.toLowerCase());
    }
    return null;
  }
}

/// Holds a public destination that arrived from outside the app until a screen
/// can act on it.
///
/// **The same shape as `PendingInvite`, and for the same reason.** A tapped
/// link can arrive before there is a Navigator to use — on a cold start it
/// arrives before the first frame — so it is offered here and collected when
/// there is somewhere to put it.
///
/// It outlives sign-in deliberately: a visitor who opens a player's profile and
/// then registers should still be looking at that player afterwards.
class PendingPublicLink {
  PendingPublicLink._();

  static final instance = PendingPublicLink._();

  final target = ValueNotifier<PublicLinkTarget?>(null);

  /// Offers whatever arrived. Anything that is not a public link is ignored,
  /// which is what lets the invitation and notification handlers be tried
  /// against the same string without any of them having to know about the
  /// others.
  ///
  /// Returns whether it was taken.
  bool offer(String? input) {
    final parsed = PublicLink.parse(input);
    if (parsed == null) return false;
    target.value = parsed;
    return true;
  }

  /// Taken by the screen that is about to open it. Cleared before navigating,
  /// so a second link arriving while the first is being opened is not mistaken
  /// for a duplicate of it.
  void clear() => target.value = null;
}
