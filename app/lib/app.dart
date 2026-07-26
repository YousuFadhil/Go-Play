import 'dart:ui';

import 'package:flutter/material.dart';

import 'core/l10n.dart';
import 'core/locale_controller.dart';
import 'core/theme.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/invitations/invite_landing_screen.dart';
import 'features/invitations/invite_link.dart';

class GoPlayApp extends StatefulWidget {
  const GoPlayApp({super.key});

  @override
  State<GoPlayApp> createState() => _GoPlayAppState();
}

class _GoPlayAppState extends State<GoPlayApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A cold start from a tapped invitation arrives here, before any frame.
    PendingInvite.instance.offer(PlatformDispatcher.instance.defaultRouteName);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// An invitation tapped while the app is already running. Anything that is
  /// not an invitation is left to the default handling.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    final token = InviteLink.parse(routeInformation.uri.toString());
    if (token == null) return super.didPushRouteInformation(routeInformation);
    PendingInvite.instance.offer(token);
    return Future.value(true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LocaleController.instance.locale,
      builder: (context, locale, _) {
        return MaterialApp(
          onGenerateTitle: (context) => context.l10n.appName,
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          // Arabic by default; overridable from the Login screen and persisted.
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
      valueListenable: PendingInvite.instance.token,
      builder: (context, token, _) {
        if (token != null) {
          // Keyed so a second invitation replaces the first rather than
          // reusing the previous one's state.
          return InviteLandingScreen(key: ValueKey(token), token: token);
        }
        return StreamBuilder<bool>(
          stream: _authService.signedInChanges,
          initialData: _authService.currentSession != null,
          builder: (context, snapshot) {
            return (snapshot.data ?? false)
                ? const HomeShell()
                : const LoginScreen();
          },
        );
      },
    );
  }
}
