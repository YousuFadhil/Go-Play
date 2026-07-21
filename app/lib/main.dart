import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // Accepts either the new publishable key or the legacy anon key.
    publishableKey: AppConfig.supabaseAnonKey,
  );

  runApp(const GoPlayApp());
}
