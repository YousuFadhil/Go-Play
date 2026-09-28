import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/l10n.dart';
import 'core/states.dart';
import 'core/locale_controller.dart';
import 'core/theme.dart';
import 'features/analytics/acquisition_analytics.dart';
import 'features/analytics/analytics_models.dart';
import 'features/analytics/analytics_service.dart';
import 'features/auth/account_suspended_screen.dart';
import 'features/auth/auth_models.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/complete_profile_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/recovery_link.dart';
import 'features/auth/reset_password_screen.dart';
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

  /// Opens a public link for a reader who is signed in. See
  /// [openPendingPublicLink], which holds the rule so it can be asserted
  /// directly.
  Future<void> _openPendingPublicLink() => openPendingPublicLink(
        _navigatorKey.currentState,
        signedIn: _authService.isSignedIn,
      );

  /// The gate's signal that the signed-in account is confirmed active.
  ///
  /// A visitor who opened a public link and then registered or signed in still
  /// has that target pending; nothing else would open it, because the target
  /// itself did not change. This is what takes them back to it (Wave 3). With
  /// nothing pending it does nothing, so the gate may call it on every check.
  void _accountActive() => unawaited(_openPendingPublicLink());

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

    // A password-recovery link is tested first of all: it is the one link that
    // must never be mistaken for anything else, and never be lost. It is
    // recorded durably here -- the running app has been handed the link, and the
    // provider's own event may or may not follow -- and consumed, so it is not
    // also pushed as a route.
    if (RecoveryLink.isRecoveryCallback(route)) {
      unawaited(_authService.beginPasswordRecovery());
      return Future.value(true);
    }

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
          home: AuthGate(onAccountActive: _accountActive),
          // A cold start from a deep link hands Navigator a route name it has
          // no table for; without this it asserts and falls back noisily. The
          // invitation itself has already been captured in initState.
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => AuthGate(onAccountActive: _accountActive),
          ),
          onGenerateInitialRoutes: (initialRoute) => initialRoutesFor(
            initialRoute,
            onAccountActive: _accountActive,
          ),
        );
      },
    );
  }
}

/// Opens the pending public link for a reader who is signed in.
///
/// **Signed out, this does nothing, and that is the whole routing rule.** A
/// visitor has no stack to push onto — the app opens on Discover — so their
/// target stays pending and [AuthGate] renders it as what the app opens on,
/// exactly as a pending invitation already works. A signed-in reader has a
/// stack, and a link should add a destination to it rather than replace
/// wherever they were, so theirs is pushed.
///
/// Reached three ways: a link tapped while signed in, a cold start, and — since
/// Wave 3 — the gate confirming an account that has just signed in or
/// registered while a visitor's target was still pending.
///
/// Nothing here decides what may be read. Each destination asks the server
/// with the reader's own session when it loads, so a link to something they
/// may not see fails on that screen, in that screen's own words — which is
/// the same thing that happens when they arrive from anywhere else.
///
/// Top-level, like [initialRoutesFor], so the rule can be asserted directly.
Future<void> openPendingPublicLink(
  NavigatorState? navigator, {
  required bool signedIn,
}) async {
  // No Navigator yet: a cold start reaches here before the first frame.
  // Returning *without* consuming is the point — the post-frame callback in
  // `initState` collects it.
  if (navigator == null) return;

  final target = PendingPublicLink.instance.target.value;
  if (target == null) return;

  // A visitor's target belongs to the gate, not to this push. Left pending.
  if (!signedIn) return;

  // Cleared before navigating, so a second link arriving while this one is
  // opening is not mistaken for a duplicate of one already consumed.
  PendingPublicLink.instance.clear();

  // The arrival, recorded for a signed-in reader — Package 5's link
  // telemetry, unchanged for anybody who was signed in when they opened it.
  //
  // Not recorded again when this is the resume of an arrival already counted
  // anonymously (Wave 3): the visitor opened one link once, and signing in on
  // top of it is not a second open.
  if (!AcquisitionAnalytics.instance.takeAnonymousArrival(target)) {
    ProductAnalytics.instance.track(
      ProductEvent.publicLinkOpened,
      communityId: target.kind == PublicLinkKind.community ? target.id : null,
      matchId: target.kind == PublicLinkKind.match ? target.id : null,
      source: ShareSource.publicLink,
    );
  }

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

/// What a cold start opens, whatever path it started on: one page.
///
/// **The fix for a deep link being read three times.** Navigator's default
/// expansion of an initial route builds one route per path segment -- `/`,
/// `/player`, `/player/<id>` for a shared profile -- so a single link produced
/// three [AuthGate]s, three profile screens and three identical reads of the
/// same public record. The app has one entry point and takes the link from
/// [PendingPublicLink] rather than from the route name, so one route is not a
/// simplification: it is the whole truth about what a cold start opens.
///
/// Named, rather than a closure on the `MaterialApp`, so the rule can be
/// asserted directly. [onAccountActive] is passed through to the gate.
List<Route<dynamic>> initialRoutesFor(
  String initialRoute, {
  VoidCallback? onAccountActive,
}) =>
    [
      MaterialPageRoute(
        builder: (_) => AuthGate(onAccountActive: onAccountActive),
      ),
    ];

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
///
/// **A password-recovery session outranks all of it.** A recovery link creates a
/// session that is indistinguishable, by "is there a session", from a sign-in,
/// and one that is restored from storage after a restart is indistinguishable
/// from any other. What tells them apart is a durable record the application
/// keeps itself ([PasswordRecoveryState]), set by the launch or resume that came
/// from the recovery callback and, as a backup, by the provider's recovery
/// event -- which cannot be relied on alone, because it may be emitted before
/// this gate is listening.
///
/// The record is consulted **first**, before an account check, Home or a pending
/// destination: while it is set and a session is behind it the gate shows
/// [ResetPasswordScreen] and nothing else, because that session exists to choose
/// a password and must never become a way into the product. It survives the app
/// being killed on that screen. Finishing or cancelling ends the session and the
/// record; a record with no session behind it is stale and is dropped.
///
/// A signed-in account is then one of three things ([AccountState]): active,
/// which is Home; suspended, which is the suspension screen; or one that has no
/// player profile yet, which is asked for it ([CompletePlayerProfileScreen]).
/// The last is not a suspension and is never worded as one.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, AuthService? authService, this.onAccountActive})
      : _authService = authService;

  final AuthService? _authService;

  /// Called every time the signed-in account is confirmed active: after a
  /// sign-in or a registration, and on each later re-check.
  ///
  /// The one seam between the gate and the app: [GoPlayApp] uses it to resume
  /// a public link a visitor opened before authenticating. The gate itself
  /// knows nothing about links.
  final VoidCallback? onAccountActive;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

/// What the gate knows about the signed-in account right now.
enum _AccountStatus {
  checking,
  active,
  profileRequired,
  suspended,
  unavailable,
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late final AuthService _authService = widget._authService ?? AuthService();

  _AccountStatus _status = _AccountStatus.checking;

  /// Which check is current. A check that finishes after a newer one started —
  /// a resume landing on top of a sign-in, say — is discarded rather than
  /// allowed to overwrite a fresher answer.
  int _checkId = 0;

  bool _signedIn = false;

  /// Whether the gate is showing the password-recovery screen.
  ///
  /// Entered when the durable record says a recovery is in progress and a
  /// session is behind it, or when the provider reports one; left only by the
  /// two ways out of the reset screen. While it is true that screen is all the
  /// gate shows, whatever else is true of the session -- including the session
  /// ending, so that finishing a recovery does not drop the reader onto Discover
  /// for the moment between signing out and being taken to the login.
  bool _recovering = false;

  StreamSubscription<AuthEvent>? _events;

  ValueListenable<bool> get _recoveryRecord => _authService.recoveryInProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _signedIn = _authService.isSignedIn;

    // The durable record is read **before anything else about the account**, so a
    // session that is a recovery never reaches an account check, Home, an
    // invitation or onboarding -- however it got here, and whether or not the
    // provider's own event was ever seen.
    _recoveryRecord.addListener(_onRecoveryRecordChanged);
    if (_recoveryRecord.value) {
      if (_signedIn) {
        _recovering = true;
      } else {
        // A record with no session behind it is stale: the app was killed after
        // the recovery ended but before it was cleared, or a link was recorded
        // whose exchange never produced a session. Drop it and carry on as a
        // visitor. If a link is still being exchanged, the provider's event
        // records it again when it lands -- which is what that backup is for.
        unawaited(_authService.discardPasswordRecovery());
      }
    }

    // Live events only: a listener sees what happens after it starts, not what
    // happened before, which is exactly why the durable record above exists.
    // Errors are the provider's own noise and are dropped one layer down; the
    // handler here is only a belt for a listener that would otherwise rethrow
    // them.
    _events = _authService.authEvents.listen(_onAuthEvent, onError: (_) {});

    if (_signedIn && !_recovering) _checkAccount();
  }

  @override
  void dispose() {
    _recoveryRecord.removeListener(_onRecoveryRecordChanged);
    unawaited(_events?.cancel());
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
    // A recovery session is not entering the product, so nothing about the
    // account behind it is asked or acted on.
    if (_recovering) return;

    final id = ++_checkId;
    if (_status != _AccountStatus.checking) {
      setState(() => _status = _AccountStatus.checking);
    }
    _AccountStatus next;
    try {
      next = switch (await _authService.fetchAccountState()) {
        AccountState.active => _AccountStatus.active,
        AccountState.profileRequired => _AccountStatus.profileRequired,
        AccountState.suspended => _AccountStatus.suspended,
      };
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
    // measure the wrong thing twice over. Neither does an account that has not
    // given its player profile yet.
    //
    // Called on every check, and it is `startSession` that makes that safe: a
    // resume and a rebuild both arrive here and neither is a new session.
    if (next == _AccountStatus.active) {
      ProductAnalytics.instance.startSession();
      // Wave 3. A new registration made from a public link converts here, once
      // the account is known to be active; a login never does. Both are
      // non-blocking and safe to repeat.
      AcquisitionAnalytics.instance.accountActive();
      widget.onAccountActive?.call();
    }
  }

  /// The session did something. Only one thing matters here: it began as a
  /// password recovery, which is what makes it not a product session.
  ///
  /// This is the **backup** to the durable record, not the way recovery is
  /// normally known: it is recorded here so that a recovery the link handling
  /// missed is still remembered across a restart.
  void _onAuthEvent(AuthEvent event) {
    if (event != AuthEvent.passwordRecovery || !mounted) return;
    unawaited(_authService.beginPasswordRecovery());
    _enterRecovery();
  }

  /// The durable record changed under us: a link handed to the running app, or
  /// the provider's event, started a recovery. It is only shown when there is a
  /// session to recover -- a record with none is either about to be met by one
  /// (a link still being exchanged) or is stale, and neither is a screen.
  void _onRecoveryRecordChanged() {
    if (_recoveryRecord.value && _authService.isSignedIn) _enterRecovery();
  }

  void _enterRecovery() {
    if (_recovering || !mounted) return;
    // Any account check already in flight belongs to a session that is not
    // going into the product; its answer is discarded when it lands.
    _checkId++;
    setState(() => _recovering = true);
    // A recovery link opened while the app was already running lands on top of
    // whatever was pushed -- the login form, the registration form -- and the
    // reset screen the gate is about to show would sit hidden underneath it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  /// The new password is set and the recovery session is over. What is left is
  /// the ordinary login, with the news that it worked.
  ///
  /// Pushed rather than rendered as the gate's own content, so it is a
  /// destination with Back like any other login and the visitor can still go
  /// back to Discover from it.
  void _recoveryCompleted() {
    setState(() => _recovering = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            authService: _authService,
            passwordResetSucceeded: true,
          ),
        ),
      );
    });
  }

  /// The person left without choosing a password. The screen ended the session
  /// and the durable record before reporting it; the gate goes back to what a
  /// signed-out visitor sees.
  void _recoveryCancelled() => setState(() => _recovering = false);

  /// The session changed under us: re-ask, or forget the answer entirely.
  void _onSignedInChanged(bool signedIn) {
    if (!mounted || signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (signedIn) {
      // A recovery link that was recorded while nobody was signed in and then
      // never produced a recovery session -- it had expired -- is still armed.
      // An ordinary sign-in has just happened instead, and it must not be
      // mistaken for the recovery: a real recovery announces itself with its own
      // event and is already `_recovering` by now.
      if (!_recovering && _recoveryRecord.value) {
        unawaited(_authService.discardPasswordRecovery());
      }
      // Whatever was pushed while nobody was signed in -- the login form, the
      // registration form -- is over. Password sign-in already unwinds itself;
      // this is for the ways in that are not a form submission, such as coming
      // back from Google, where nothing on this side knows the moment it lands.
      Navigator.of(context).popUntil((route) => route.isFirst);
      _checkAccount();
    } else {
      // Signed out: no account to have a state. Bumping the id abandons any
      // check still in flight so it cannot land on the signed-out screen.
      _checkId++;
      // And the session is over. Signing back in is a genuinely new session and
      // must be able to record one; without this the app would record a single
      // session for as long as it stayed open, however many people used it.
      ProductAnalytics.instance.endSession();
      // And any acquisition this session was carrying ends with it.
      AcquisitionAnalytics.instance.signedOut();
      // `_recovering` and the durable record are deliberately left alone. While
      // the reset screen is up, finishing a recovery ends the session *before*
      // the screen reports it is done, and both ways out of it clear the record
      // themselves; and a record with no session behind it that is *not* on
      // screen cannot arise here -- a link that arrives while signed out only
      // arms it, and the next start or the next sign-in drops it.
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

        // A password-recovery session is decided before anything else, the
        // sign-in state included: it looks like a signed-in reader and must not
        // be treated as one.
        if (_recovering) {
          return ResetPasswordScreen(
            authService: _authService,
            onCompleted: _recoveryCompleted,
            onCancelled: _recoveryCancelled,
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
        // pending invitation either -- and neither may somebody who has not
        // given a player profile yet.
        return switch (_status) {
          _AccountStatus.checking => const Scaffold(body: LoadingState()),
          _AccountStatus.suspended =>
            AccountSuspendedScreen(authService: _authService),
          _AccountStatus.profileRequired => CompletePlayerProfileScreen(
              authService: _authService,
              // Asks the database again and lets the player in only if the
              // answer is now "active"; the screen decides nothing itself.
              onCompleted: _checkAccount,
            ),
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
