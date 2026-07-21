import 'package:flutter/material.dart';

/// Shown instead of the real app when Supabase configuration is missing or
/// invalid. Developer-facing by design (bilingual, no localization setup
/// needed this early in startup).
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  static const _runCommand = 'flutter run `\n'
      '  --dart-define=SUPABASE_URL=https://<project>.supabase.co `\n'
      '  --dart-define=SUPABASE_ANON_KEY=<publishable-key>';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.settings_suggest,
                      size: 64, color: Colors.orangeAccent),
                  const SizedBox(height: 24),
                  const Text(
                    'Supabase configuration missing',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'إعدادات Supabase غير موجودة',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'The app was launched without --dart-define values, so '
                    'SUPABASE_URL / SUPABASE_ANON_KEY are empty.\n\n'
                    'شُغِّل التطبيق بدون تمرير --dart-define، لذلك قيم '
                    'الاتصال بالخادم فارغة. هذه ليست مشكلة في الخادم ولا في '
                    'الإنترنت.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Run it like this (PowerShell):\n\n$_runCommand',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontFamily: 'monospace',
                          fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'See SETUP.md §4 for the full instructions.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
