import 'package:flutter/foundation.dart';

import 'notification_models.dart';

/// Where a tapped notification lands.
enum NotificationDestination {
  /// Match Details for [NotificationTarget.matchId].
  match,

  /// The Notification Center. The destination for everything that names no
  /// entity, and the fallback for everything that names one that cannot be
  /// opened.
  centre,
}

/// The decision of where a tapped notification should take the reader.
///
/// This is the whole of the routing policy, and it is deliberately one rule:
/// **a notice that carries a `match_id` opens that match; everything else opens
/// the Notification Center.**
///
/// `type` is not consulted, and that is the point. `notifications.match_id` is
/// already the answer to "which entity is this notice about" — every
/// match-scoped producer writes it and no community-scoped one does — so a
/// second table mapping type to destination would be a copy of that fact,
/// kept in step by hand, and wrong the first time a producer was added without
/// anybody remembering it. `notificationDisplays` maps type to *appearance*,
/// which is a genuinely separate question; this maps presence-of-an-id to
/// *destination*, and needs no registry at all.
///
/// A deleted match is handled by the same rule rather than by a special case:
/// `notifications.match_id` is `on delete set null`, so the notices of a match
/// that no longer exists have already stopped naming it and route to the
/// Center on their own.
@immutable
class NotificationTarget {
  const NotificationTarget._(this.destination, this.matchId);

  /// The Notification Center — nothing else is actionable.
  const NotificationTarget.centre()
      : this._(NotificationDestination.centre, null);

  final NotificationDestination destination;

  /// Set when and only when [destination] is [NotificationDestination.match].
  final String? matchId;

  /// The destination for a notice read out of the Notification Center.
  factory NotificationTarget.of(AppNotification notification) =>
      NotificationTarget._forMatch(notification.matchId);

  /// The destination for a tapped push.
  ///
  /// The data block is `push-dispatch`'s: `notification_id`, `type`, `match_id`.
  /// **`match_id` arrives as an empty string rather than absent** — FCM data
  /// values are strings, so the function writes `payload.match_id ?? ""` for a
  /// notice that names no match. Blank is therefore the ordinary way "no match"
  /// is spelled here, and is treated as absence rather than as an id.
  factory NotificationTarget.fromPushData(Map<String, dynamic> data) =>
      NotificationTarget._forMatch(data['match_id'] as String?);

  factory NotificationTarget._forMatch(String? matchId) {
    final id = matchId?.trim() ?? '';
    return id.isEmpty
        ? const NotificationTarget.centre()
        : NotificationTarget._(NotificationDestination.match, id);
  }

  bool get opensMatch => destination == NotificationDestination.match;

  /// The same decision, taken again once it is known whether the match can
  /// actually be opened.
  ///
  /// The Notification Center does not need this: it is already showing the
  /// fallback, and a match it cannot load renders its own error state. The push
  /// path does, because it navigates blind — the tap may be a cold start, hours
  /// after the notice was written, into a match the reader has since lost access
  /// to. Landing on an error screen they did not ask for is worse than landing
  /// on the list of what they were told.
  Future<NotificationTarget> resolved(
    Future<bool> Function(String matchId) canOpenMatch,
  ) async {
    final id = matchId;
    if (id == null) return this;
    return await canOpenMatch(id) ? this : const NotificationTarget.centre();
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget &&
      other.destination == destination &&
      other.matchId == matchId;

  @override
  int get hashCode => Object.hash(destination, matchId);

  @override
  String toString() => matchId == null
      ? 'NotificationTarget.centre()'
      : 'NotificationTarget.match($matchId)';
}

/// The link a tapped **web** push opens, and the one place that knows how a
/// notification target is written into a URL and read back out of one.
///
/// Android and iOS hand the notice's data block to `onMessageOpenedApp`. A
/// browser cannot: the click is handled inside the service worker, which can
/// only open a URL. So on the web the target travels *as* the URL, and this is
/// the format on both sides of it — `webLink()` in `push-dispatch` writes it,
/// [parse] reads it. **The two must agree; they are documented against each
/// other, and [format] exists so the shape can be asserted here rather than
/// only in an Edge Function this suite cannot run.**
///
/// The target lives in the **fragment**, `…/#/notification?match_id=<uuid>`,
/// and that is not cosmetic. This app uses Flutter's default hash URL strategy,
/// which means:
///
///   * the fragment is what `PlatformDispatcher.defaultRouteName` and
///     `didPushRouteInformation` report, so it is readable with no new
///     dependency and no change of URL strategy;
///   * it is what `SystemNavigator.routeInformationUpdated` rewrites, so the
///     target can be *taken out of the address bar* once used. A query string
///     before the `#` would be readable only through `Uri.base` and could not
///     be cleared without reaching for `window.history` — and an uncleared
///     target reopens the same match on every refresh.
class NotificationLink {
  const NotificationLink._();

  /// The route a notification link lands on.
  static const path = '/notification';

  /// What the route is replaced with once its target has been taken. The app's
  /// ordinary starting route, so a refresh afterwards is an ordinary start.
  static const consumedRoute = '/';

  static const _matchParam = 'match_id';

  /// A match id is a `uuid` column. Validated because this arrives from the
  /// address bar, where anybody can type: an id that is not id-shaped is not a
  /// destination, and is answered with the Center rather than with a lookup.
  ///
  /// **This is shape-checking, never authorization.** A well-formed id is only
  /// a navigation target; whether the reader may see that match is Match
  /// Details' own question, asked against their session exactly as it is when
  /// they arrive from anywhere else.
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// The route for a notice, as `push-dispatch` writes it into
  /// `webpush.fcm_options.link` after the origin and the `#`.
  static String format({String? matchId}) {
    final id = matchId?.trim() ?? '';
    if (id.isEmpty) return path;
    // `encodeComponent`, not `encodeQueryComponent`: the latter writes a space
    // as `+` where the Edge Function's `encodeURIComponent` writes `%20`. No
    // id ever contains one — [parse] rejects anything that is not uuid-shaped —
    // but the two sides of a shared format should not differ at all.
    return '$path?$_matchParam=${Uri.encodeComponent(id)}';
  }

  /// Reads a target out of an incoming route.
  ///
  /// Returns null when [route] is not a notification link at all — which is
  /// every route on Android and iOS, and every invitation — so the caller can
  /// leave anything it does not own alone.
  static NotificationTarget? parse(String? route) {
    if (route == null || route.isEmpty) return null;
    final uri = Uri.tryParse(route);
    if (uri == null || uri.path != path) return null;

    final id = uri.queryParameters[_matchParam]?.trim() ?? '';
    // A link of ours that names no match, or names one that cannot be an id,
    // still opens the Center. It is a notification link either way: the reader
    // tapped a notice and must land somewhere they can read it.
    if (id.isEmpty || !_uuid.hasMatch(id)) return const NotificationTarget.centre();
    return NotificationTarget._forMatch(id);
  }
}

/// Holds a tapped push until something can navigate for it.
///
/// The same shape as `PendingInvite`, for the same reason: a tap can arrive
/// before there is a Navigator to receive it. A cold start is the case that
/// forces it — the launching notification is readable as soon as Firebase is up,
/// which is before the first frame and long before the reader is known to be
/// signed in.
///
/// Held rather than acted on, and cleared by whoever acts, so a tap is honoured
/// exactly once.
class PendingNotificationTap {
  PendingNotificationTap._();

  static final instance = PendingNotificationTap._();

  final target = ValueNotifier<NotificationTarget?>(null);

  void offer(NotificationTarget value) => target.value = value;

  /// Takes the target out of an incoming route, if it carries one.
  ///
  /// Returns whether the route was a notification link — which is what tells
  /// the caller to clear it from the address bar. Everything else, invitations
  /// included, is left untouched and reported as not ours.
  bool consumeRoute(String? route) {
    final value = NotificationLink.parse(route);
    if (value == null) return false;
    offer(value);
    return true;
  }

  /// Convenience for the push path, which holds a data block rather than a
  /// decision.
  void offerPushData(Map<String, dynamic> data) =>
      offer(NotificationTarget.fromPushData(data));

  void clear() => target.value = null;
}
