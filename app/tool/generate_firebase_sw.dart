// Writes `web/firebase-messaging-sw.js` from `tool/firebase-messaging-sw.template.js`.
//
// The service worker needs the Firebase Web configuration and cannot be given
// it the way the Dart side is: a worker is a static file the browser fetches,
// so `String.fromEnvironment` and `--dart-define` do not reach it. Committing
// the configuration into the worker is the alternative this project does not
// take — `android/app/google-services.json` is gitignored for the same reason.
// So the file is generated, from a template that names no project, immediately
// before the build that consumes it.
//
// Usage — arguments, or the same variable names the `--dart-define`s use:
//
//   dart run tool/generate_firebase_sw.dart \
//     --api-key=... --app-id=... --sender-id=... --project-id=... \
//     [--auth-domain=...]
//
//   FIREBASE_WEB_API_KEY, FIREBASE_WEB_APP_ID, FIREBASE_MESSAGING_SENDER_ID,
//   FIREBASE_PROJECT_ID, FIREBASE_AUTH_DOMAIN
//
// Arguments win over the environment, so CI can export once and a developer can
// override one value without unsetting anything.
//
// **Missing values are not an error.** A build without them is a build without
// web push, which `FirebaseWebConfig.isConfigured` already allows and the rest
// of the app is indifferent to. What this must never do is leave the *previous*
// run's worker in place, so an unconfigured run overwrites the file with an
// inert one rather than skipping it: the generated worker always describes the
// build standing next to it.

import 'dart:io';

/// Keyed by placeholder; the value is (flag, environment variable).
const _values = <String, (String, String)>{
  '__FIREBASE_WEB_API_KEY__': ('api-key', 'FIREBASE_WEB_API_KEY'),
  '__FIREBASE_WEB_APP_ID__': ('app-id', 'FIREBASE_WEB_APP_ID'),
  '__FIREBASE_MESSAGING_SENDER_ID__': ('sender-id', 'FIREBASE_MESSAGING_SENDER_ID'),
  '__FIREBASE_PROJECT_ID__': ('project-id', 'FIREBASE_PROJECT_ID'),
};

// The template lives in `tool/` rather than beside its output: `flutter build
// web` copies everything in `web/` verbatim, so a template kept there would be
// published to the site root alongside the file it generated.
const _templatePath = 'tool/firebase-messaging-sw.template.js';
const _outputPath = 'web/firebase-messaging-sw.js';

void main(List<String> args) {
  final flags = _parseFlags(args);

  String? read(String flag, String variable) {
    final value = flags[flag] ?? Platform.environment[variable];
    return (value == null || value.trim().isEmpty) ? null : value.trim();
  }

  final resolved = <String, String>{};
  final missing = <String>[];
  for (final entry in _values.entries) {
    final (flag, variable) = entry.value;
    final value = read(flag, variable);
    if (value == null) {
      missing.add(variable);
    } else {
      resolved[entry.key] = value;
    }
  }

  final output = File(_outputPath);

  if (missing.isNotEmpty) {
    output.writeAsStringSync(_inertWorker(missing));
    stdout.writeln(
      'firebase-messaging-sw.js: written inert — web push disabled '
      '(missing ${missing.join(', ')}).',
    );
    return;
  }

  // Derived rather than required, exactly as `FirebaseWebConfig.authDomain`
  // derives it, so the two cannot disagree about a value neither was told.
  resolved['__FIREBASE_AUTH_DOMAIN__'] = read('auth-domain', 'FIREBASE_AUTH_DOMAIN') ??
      '${resolved['__FIREBASE_PROJECT_ID__']}.firebaseapp.com';

  final template = File(_templatePath);
  if (!template.existsSync()) {
    stderr.writeln('$_templatePath not found. Run this from the `app` directory.');
    exitCode = 1;
    return;
  }

  var contents = template.readAsStringSync();
  for (final entry in resolved.entries) {
    // Single-quoted string literals in the template: a value carrying a quote
    // or a backslash would end the literal and change the meaning of the file.
    // None of these values ever contains one, which is why this rejects rather
    // than escapes — an identifier that needs escaping is a wrong identifier.
    if (entry.value.contains("'") || entry.value.contains(r'\')) {
      stderr.writeln('${entry.key}: refusing a value containing a quote or backslash.');
      exitCode = 1;
      return;
    }
    contents = contents.replaceAll(entry.key, entry.value);
  }

  if (contents.contains('__FIREBASE_')) {
    stderr.writeln('$_templatePath has a placeholder this tool does not fill.');
    exitCode = 1;
    return;
  }

  output.writeAsStringSync(_header + _strippedTemplateNotes(contents));
  stdout.writeln('firebase-messaging-sw.js: generated for '
      '${resolved['__FIREBASE_PROJECT_ID__']}.');
}

Map<String, String> _parseFlags(List<String> args) {
  final flags = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final split = arg.indexOf('=');
    if (split == -1) continue;
    flags[arg.substring(2, split)] = arg.substring(split + 1);
  }
  return flags;
}

const _header = '''
// GENERATED FILE — DO NOT EDIT, DO NOT COMMIT.
//
// Written by `tool/generate_firebase_sw.dart` from
// `tool/firebase-messaging-sw.template.js`. Edit the template; this file is
// gitignored and is overwritten by every run of the generator.

''';

/// The template's header explains how to generate the file, which is noise once
/// it has been. Everything from the first `importScripts` is kept verbatim.
String _strippedTemplateNotes(String contents) {
  final start = contents.indexOf('importScripts(');
  return start == -1 ? contents : contents.substring(start);
}

String _inertWorker(List<String> missing) => '''
// GENERATED FILE — DO NOT EDIT, DO NOT COMMIT.
//
// Web push is **off** in this build: ${missing.join(', ')} ${missing.length == 1 ? 'was' : 'were'} not set
// when `tool/generate_firebase_sw.dart` ran.
//
// This file exists rather than being absent so that a worker left over from a
// configured build cannot be served beside an unconfigured one. It registers
// nothing and receives nothing. `FirebaseWebConfig.isConfigured` is false in
// the same build, so the app never asks for a token and never reaches here.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
''';
