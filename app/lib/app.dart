import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/l10n.dart';
import 'core/locale_controller.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';

class GoPlayApp extends StatelessWidget {
  const GoPlayApp({super.key});

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
        );
      },
    );
  }
}

/// Shows [LoginScreen] or [HomeShell] based on the current auth session.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const HomeShell();
        }
        return const LoginScreen();
      },
    );
  }
}
