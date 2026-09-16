import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/l10n.dart';
import 'core/states.dart';
import 'core/locale_controller.dart';
import 'core/theme.dart';
import 'features/analytics/analytics_models.dart';
import 'features/analytics/analytics_service.dart';
import 'features/auth/account_suspended_screen.dart';
import 'features/auth/auth_service.dart';
import 'features/discover/discover_screen.dart';
import 'features/discover/public_community_screen.dart';
import 'features/discover/public_match_screen.dart';
import 'features/football/football_community_screen.dart';
import 'features/home/home_shell.dart';
import 'features/invitations/invite_landing_screen.dart';
import 'features/invitations/invite_link.dart';
import 'features/matches/match_details_screen.dart';
import 'features/matches/match_service.dart';
import 'features/notifications/notification_route.dart';
import 'features/notifications/notification_service.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/notifications/push_service.dart';
import 'features/profile/profile_screen.dart';
import 'features/sharing/public_link.dart';

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

  /// Identity, for the one question this widget asks of it: whether a tapped
  /// notification belongs to an account that may still act on it.
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Attached before anything can be offered, so a tap that arrives during
    // this method is not published to an empty room.
    PendingNotificationTap.instance.target.addListener(_openTappedNotification);
    // A public link tapped while the app is already running reaches
    // `didPushRouteInformation`, which offers it here; this is what acts on it.
    PendingPublicLink.instance.target.addListener(_openPendingPublicLink);

    // A cold start from a tapped invitation arrives here, before any frame.
    PendingInvite.instance.offer(PlatformDispatcher.instance.defaultRouteName);
    // And a cold start from a tapped **web** push, which arrives the same way
    // and for the same reason: the browser can only hand a notification click
    // over as a URL. Left after the invitation offer, which ignores it — a
    // notification route carries no join code and is rejected by
    // `InviteLink.parse` before this runs.
    _consumeNotificationLink(PlatformDispatcher.instance.defaultRouteName);

    // And a cold start from a tapped **public link** — `/player/{id}`,
    // `/community/{id}`, `/match/{id}`. Offered last of the three because it
    // is the broadest: an invitation and a notification route are each one
    // exact shape, and neither is public-link-shaped, so neither can be taken
    // by mistake. Nothing here navigates; where a public target is opened
    // depends on whether there is a session, which is decided below.
    PendingPublicLink.instance.offer(
      PlatformDispatcher.instance.defaultRouteName,
    );

    // The cold-start case needs one more nudge. Everything above runs before
    // the first frame, so there is no Navigator yet and the listener above can
    // only decline — which it does *without* consuming the tap. This is where
    // it is picked up, once there is something to navigate with.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openTappedNotification();
      // Same reason: on a cold start there was no Navigator when the link was
      // offered, so the signed-in path could not take it.
      _openPendingPublicLink();
    });
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
    PendingPublicLink.instance.target.removeListener(_openPendingPublicLink);
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

    // A suspended account does not get into the product through a notification
    // tap. The gate below decides what a signed-in reader sees; without this,
    // one tap would push Match Details straight over the top of it.
    //
    // Fails closed: only an account the database confirms is active proceeds.
    // A refusal or an unanswerable question both stop here, and the notice is
    // still marked read above, so nothing is lost by not navigating.
    if (_authService.isSignedIn) {
      bool active;
      try {
        active = await _authService.isCurrentUserActive();
      } catch (_) {
        active = false;
      }
      if (!active) return;
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

  /// Opens a public link for a reader who is signed in.
  ///
  /// **Signed out, this does nothing, and that is the whole routing rule.** A
  /// visitor has no stack to push onto — the app opens on Discover — so their
  /// target stays pending and [AuthGate] renders it as what the app opens on,
  /// exactly as a pending invitation already works. A signed-in reader has a
  /// stack, and a link should add a destination to it rather than replace
  /// wherever they were, so theirs is pushed.
  ///
  /// Nothing here decides what may be read. Each destination asks the server
  /// with the reader's own session when it loads, so a link to something they
  /// may not see fails on that screen, in that screen's own words — which is
  /// the same thing that happens when they arrive from anywhere else.
  Future<void> _openPendingPublicLink() async {
    // No Navigator yet: a cold start reaches here before the first frame.
    // Returning *without* consuming is the point — the post-frame callback in
    // `initState` collects it.
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    final target = PendingPublicLink.instance.target.value;
    if (target == null) return;

    // A visitor's target belongs to the gate, not to this push. Left pending.
    if (!_authService.isSignedIn) return;

    // Cleared before navigating, so a second link arriving while this one is
    // opening is not mistaken for a duplicate of one already consumed.
    PendingPublicLink.instance.clear();

    // The arrival, recorded — for a signed-in reader only, which is the whole
    // of Package 5's link telemetry. A signed-out visitor's open is
    // deliberately not recorded anywhere: `record_product_event` takes its
    // actor from `auth.uid()` and `anon` cannot call it, and back-dating the
    // event once they register would be inventing one.
    ProductAnalytics.instance.track(
      ProductEvent.publicLinkOpened,
      communityId: target.kind == PublicLinkKind.community ? target.id : null,
      matchId: target.kind == PublicLinkKind.match ? target.id : null,
      source: ShareSource.publicLink,
    );

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => switch (target.kind) {
          PublicLinkKind.player => ProfileScreen(userId: target.id),
          // The screen a signed-in reader gets for a community they may or may
          // not belong to. It loads the public part for everyone and the
          // football part for whoever may read it, and offers Join — so a
          // link never lands on a screen that refuses the reader outright,
          // which `CommunityDetailsScreen` would for a non-member.
          PublicLinkKind.community =>
            FootballCommunityScreen(communityId: target.id),
          PublicLinkKind.match => MatchDetailsScreen(matchId: target.id),
        },
      ),
    );
  }

  /// Tells the screens that watch the Notification Center to re-read it.
  ///
  /// This is the signal `HomeTab` and `MatchDetailsScreen` already listen to.
  /// Reused rather than duplicated: its meaning is "the notification state has
  /// moved, re-read the record", and marking a notice read moves it exactly as
  /// a push arriving does.
  void _notificationsChanged() => PushService.instance.foregroundPushes.value++;

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
    if (code != null) {
      PendingInvite.instance.offer(code);
      return Future.value(true);
    }

    // Tried last, for the reason the cold-start offers are ordered the same
    // way: this is the broadest of the three shapes. Offering it publishes to
    // the listener above, which opens it for a signed-in reader and leaves it
    // for the gate otherwise.
    if (PendingPublicLink.instance.offer(route)) return Future.value(true);

    return super.didPushRouteInformation(routeInformation);
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
  const AuthGate({super.key, AuthService? authService})
      : _authService = authService;

  final AuthService? _authService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

/// What the gate knows about the signed-in account right now.
enum _AccountStatus { checking, active, suspended, unavailable }

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late final AuthService _authService = widget._authService ?? AuthService();

  _AccountStatus _status = _AccountStatus.checking;

  /// Which check is current. A check that finishes after a newer one started —
  /// a resume landing on top of a sign-in, say — is discarded rather than
  /// allowed to overwrite a fresher answer.
  int _checkId = 0;

  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _signedIn = _authService.isSignedIn;
    if (_signedIn) _checkAccount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-asks on resume. A suspension applied while the app was in the
  /// background is caught the next time the reader comes back, which is the
  /// approved MVP cadence — no polling, no realtime subscription, no timer.
  /// The database refuses their writes in the meantime regardless.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _signedIn) _checkAccount();
  }

  Future<void> _checkAccount() async {
    final id = ++_checkId;
    if (_status != _AccountStatus.checking) {
      setState(() => _status = _AccountStatus.checking);
    }
    _AccountStatus next;
    try {
      next = await _authService.isCurrentUserActive()
          ? _AccountStatus.active
          : _AccountStatus.suspended;
    } catch (_) {
      // Fails closed. An unanswered question is not permission to enter.
      next = _AccountStatus.unavailable;
    }
    if (!mounted || id != _checkId) return;
    setState(() => _status = next);

    // The session is recorded here and nowhere else, because here is the only
    // point in the application that knows both halves of what a session is:
    // signed in **and** active. A suspended reader records nothing — they do
    // not enter the product, and counting them as a daily active user would
    // measure the wrong thing twice over.
    //
    // Called on every check, and it is `startSession` that makes that safe: a
    // resume and a rebuild both arrive here and neither is a new session.
    if (next == _AccountStatus.active) ProductAnalytics.instance.startSession();
  }

  /// The session changed under us: re-ask, or forget the answer entirely.
  void _onSignedInChanged(bool signedIn) {
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (signedIn) {
      _checkAccount();
    } else {
      // Signed out: no account to have a state. Bumping the id abandons any
      // check still in flight so it cannot land on the signed-out screen.
      _checkId++;
      // And the session is over. Signing back in is a genuinely new session and
      // must be able to record one; without this the app would record a single
      // session for as long as it stayed open, however many people used it.
      ProductAnalytics.instance.endSession();
      setState(() => _status = _AccountStatus.checking);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _authService.signedInChanges,
      initialData: _authService.isSignedIn,
      builder: (context, snapshot) {
        final signedIn = snapshot.data ?? false;
        // The stream can emit during build, so the reaction is deferred rather
        // than calling setState inside a builder.
        if (signedIn != _signedIn) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _onSignedInChanged(signedIn),
          );
        }

        if (!signedIn) {
          // Signed out. The invitation still outranks everything, exactly as
          // before: somebody who tapped an invitation asked for that and
          // nothing else. A public link comes next, and Discover is what the
          // app opens on when there is neither.
          //
          // A visitor's public target is *rendered here* rather than pushed,
          // because there is nothing to push onto — this is the app's first
          // screen, and the reader arrived at it by asking for this player,
          // this community or this match.
          return ValueListenableBuilder<String?>(
            valueListenable: PendingInvite.instance.code,
            builder: (context, code, _) {
              if (code != null) {
                return InviteLandingScreen(key: ValueKey(code), code: code);
              }
              return ValueListenableBuilder<PublicLinkTarget?>(
                valueListenable: PendingPublicLink.instance.target,
                builder: (context, target, _) => switch (target?.kind) {
                  null => const DiscoverScreen(),
                  // The one place in the app that opens a profile for
                  // somebody with no account, which is why it is the one place
                  // that says so.
                  PublicLinkKind.player => ProfileScreen(
                      key: ValueKey(target!.id),
                      userId: target.id,
                      asVisitor: true,
                    ),
                  PublicLinkKind.community => PublicCommunityScreen(
                      key: ValueKey(target!.id),
                      communityId: target.id,
                    ),
                  PublicLinkKind.match => PublicMatchScreen(
                      key: ValueKey(target!.id),
                      matchId: target.id,
                    ),
                },
              );
            },
          );
        }

        // Signed in. The account's state is decided before anything else,
        // because a suspended reader must not reach the product through a
        // pending invitation either.
        return switch (_status) {
          _AccountStatus.checking => const Scaffold(body: LoadingState()),
          _AccountStatus.suspended =>
            AccountSuspendedScreen(authService: _authService),
          _AccountStatus.unavailable =>
            AccountStatusUnavailableScreen(onRetry: _checkAccount),
          _AccountStatus.active => ValueListenableBuilder<String?>(
              valueListenable: PendingInvite.instance.code,
              builder: (context, code, _) => code != null
                  ? InviteLandingScreen(key: ValueKey(code), code: code)
                  : const HomeShell(),
            ),
        };
      },
    );
  }
}
