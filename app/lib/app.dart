import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/l10n.dart';
import 'core/locale_controller.dart';
import 'core/theme.dart';
import 'features/auth/auth_service.dart';
import 'features/discover/discover_screen.dart';
import 'features/home/home_shell.dart';
import 'features/invitations/invite_landing_screen.dart';
import 'features/invitations/invite_link.dart';
import 'features/matches/match_details_screen.dart';
import 'features/matches/match_service.dart';
import 'features/notifications/notification_route.dart';
import 'features/notifications/notification_service.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/notifications/push_service.dart';

class GoPlayApp extends StatefulWidget {
  const GoPlayApp({super.key});

  @override
  State<GoPlayApp> createState() => _GoPlayAppState();
}

class _GoPlayAppState extends State<GoPlayApp> with WidgetsBindingObserver {
  /// The one Navigator, named so a tapped push can reach it.
  ///
  /// A push tap is not a widget event: it arrives from the platform, at a moment
  /// nothing on screen chose, and often before there is a screen at all. The
  /// invitation path does not need this because an invitation *replaces* what
  /// the app opens on — it is a different starting point. A notification does
  /// the opposite: it adds a destination on top of wherever the reader already
  /// was, and Back has to return them there. That is a push onto this Navigator
  /// and nothing more, which is why no routing package is introduced.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Attached before anything can be offered, so a tap that arrives during
    // this method is not published to an empty room.
    PendingNotificationTap.instance.target.addListener(_openTappedNotification);

    // A cold start from a tapped invitation arrives here, before any frame.
    PendingInvite.instance.offer(PlatformDispatcher.instance.defaultRouteName);
    // And a cold start from a tapped **web** push, which arrives the same way
    // and for the same reason: the browser can only hand a notification click
    // over as a URL. Left after the invitation offer, which ignores it — a
    // notification route carries no join code and is rejected by
    // `InviteLink.parse` before this runs.
    _consumeNotificationLink(PlatformDispatcher.instance.defaultRouteName);

    // The cold-start case needs one more nudge. Everything above runs before
    // the first frame, so there is no Navigator yet and the listener above can
    // only decline — which it does *without* consuming the tap. This is where
    // it is picked up, once there is something to navigate with.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _openTappedNotification());
  }

  /// Takes a notification target out of an incoming route and clears it from
  /// the address bar.
  ///
  /// The clearing is the half that is easy to forget and impossible to miss
  /// once it bites: without it the target is still in the URL, so every refresh
  /// — and every restore of that tab — reopens the same match as though the
  /// reader had tapped the notification again. The route is replaced rather
  /// than pushed, so it also does not become a Back destination.
  bool _consumeNotificationLink(String? route) {
    if (!PendingNotificationTap.instance.consumeRoute(route)) return false;
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(NotificationLink.consumedRoute),
      replace: true,
    );
    return true;
  }

  @override
  void dispose() {
    PendingNotificationTap.instance.target
        .removeListener(_openTappedNotification);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Navigates for a tapped push, once.
  ///
  /// Cleared before navigating rather than after: the value is the *pending*
  /// tap, and a tap being acted on is no longer pending. Clearing late would
  /// leave it set while the match is being checked, and a second tap arriving in
  /// that window would be dropped as a duplicate of one already consumed.
  Future<void> _openTappedNotification() async {
    // Nothing to navigate with yet. A cold start reaches here before the first
    // frame, and **returning without consuming is the whole point**: the tap
    // stays pending and the post-frame callback in `initState` collects it.
    // Clearing first would have destroyed exactly the taps this feature is for.
    if (_navigatorKey.currentState == null) return;

    final requested = PendingNotificationTap.instance.target.value;
    if (requested == null) return;
    PendingNotificationTap.instance.clear();

    // The reader acted on this notice, so it is read — before navigating, and
    // regardless of where they land. Best-effort: a notice that stays unread is
    // a stale badge, never a lost notice, and is not worth failing a tap over.
    final noticeId = requested.notificationId;
    if (noticeId != null) {
      try {
        await NotificationService().markRead(noticeId);
      } catch (_) {
        // See above.
      }
    }

    final target = await requested.resolved(_matchOpens);

    // Already looking at it. Refresh in place rather than stacking a second
    // copy of the same screen — otherwise Back returns to a stale duplicate of
    // where the reader already was.
    if (target.opensMatch &&
        CurrentMatchDetails.instance.reloadIfShowing(target.matchId!)) {
      _notificationsChanged();
      return;
    }

    // Read after the awaits: the app may have been torn down meanwhile.
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => target.opensMatch
            ? MatchDetailsScreen(matchId: target.matchId!)
            : const NotificationsScreen(),
      ),
    );

    // Back from the destination. Whatever was underneath was rendered before
    // the notice was read and before the roster moved, so it is told to re-read.
    _notificationsChanged();
  }

  /// Tells the screens that watch the Notification Center to re-read it.
  ///
  /// This is the signal `HomeTab` and `MatchDetailsScreen` already listen to.
  /// Reused rather than duplicated: its meaning is "the notification state has
  /// moved, re-read the record", and marking a notice read moves it exactly as
  /// a push arriving does.
  void _notificationsChanged() =>
      PushService.instance.foregroundPushes.value++;

  /// Whether Match Details would have something to show.
  ///
  /// Any failure is a no: gone, forbidden and unreachable are different reasons
  /// and the same outcome for a reader who tapped a notification — the
  /// Notification Center, which is the one screen that cannot fail them, because
  /// the notice they tapped is on it.
  Future<bool> _matchOpens(String matchId) async {
    try {
      await MatchService().fetchMatch(matchId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// An invitation or a web push tapped while the app is already running.
  /// Anything that is neither is left to the default handling.
  ///
  /// The notification link is tested first because it is the narrower of the
  /// two — one exact route — while `InviteLink.parse` accepts anything
  /// code-shaped, including a bare number.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    final route = routeInformation.uri.toString();
    if (_consumeNotificationLink(route)) return Future.value(true);

    final code = InviteLink.parse(route);
    if (code == null) return super.didPushRouteInformation(routeInformation);
    PendingInvite.instance.offer(code);
    return Future.value(true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleController.instance.locale,
      builder: (context, locale, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          onGenerateTitle: (context) => context.l10n.appName,
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          // Null means the device's own language, which is the default and what
          // most readers will ever see. A choice made in Settings replaces it
          // and is persisted; nothing else in the product sets a language.
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const AuthGate(),
          // A cold start from a deep link hands Navigator a route name it has
          // no table for; without this it asserts and falls back noisily. The
          // invitation itself has already been captured in initState.
          onGenerateRoute: (_) =>
              MaterialPageRoute(builder: (_) => const AuthGate()),
        );
      },
    );
  }
}

/// Decides what the app opens on: a pending invitation outranks both, because
/// someone who tapped an invitation asked for that and nothing else.
///
/// Without a session the answer is now [DiscoverScreen] rather than the login
/// form. That is the whole of Sprint 1's entry change, and it is made here
/// because here is where "signed in or not" was already being asked — the login
/// screen still exists, unchanged, and is reached by pushing it from Discover
/// when a visitor asks to sign in or tries something that needs an account.
///
/// A signed-in player still lands on [HomeShell] directly. Sending them through
/// a public landing page they would immediately be moved off would be a flicker,
/// not a first impression.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: PendingInvite.instance.code,
      builder: (context, code, _) {
        if (code != null) {
          // Keyed so a second invitation replaces the first rather than
          // reusing the previous one's state.
          return InviteLandingScreen(key: ValueKey(code), code: code);
        }
        return StreamBuilder<bool>(
          stream: _authService.signedInChanges,
          initialData: _authService.isSignedIn,
          builder: (context, snapshot) {
            return (snapshot.data ?? false)
                ? const HomeShell()
                : const DiscoverScreen();
          },
        );
      },
    );
  }
}
