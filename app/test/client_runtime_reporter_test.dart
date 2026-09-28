import 'dart:async';
import 'dart:io';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/runtime/client_runtime_adapter.dart';
import 'package:go_play/features/runtime/client_runtime_fingerprint.dart';
import 'package:go_play/features/runtime/client_runtime_models.dart';
import 'package:go_play/features/runtime/client_runtime_reporter.dart';
import 'package:go_play/features/runtime/client_runtime_repository.dart';

/// Wave 4 client runtime evidence, from the client's side: which builds
/// report, one run per process, only uncaught errors, only a fingerprint, and
/// never at the cost of the error handling that was there before.
void main() {
  const sha = 'abcdef0123456789abcdef0123456789abcdef01';
  const production = ClientRuntimeIdentity(
    platform: 'web',
    appVersion: '0.4.1-public-beta+2',
    buildSha: sha,
  );

  late FlutterExceptionHandler? originalFlutterHandler;
  late ErrorCallback? originalPlatformHandler;
  late List<FlutterErrorDetails> previousFlutterCalls;
  late List<Object> previousPlatformCalls;
  late _FakeRuntimeAdapter adapter;

  setUp(() {
    originalFlutterHandler = FlutterError.onError;
    originalPlatformHandler = PlatformDispatcher.instance.onError;
    previousFlutterCalls = [];
    previousPlatformCalls = [];
    // What the app had before the reporter: recorded, so chaining is visible.
    FlutterError.onError = previousFlutterCalls.add;
    PlatformDispatcher.instance.onError = (error, stack) {
      previousPlatformCalls.add(error);
      return true;
    };
    adapter = _FakeRuntimeAdapter();
  });

  tearDown(() {
    FlutterError.onError = originalFlutterHandler;
    PlatformDispatcher.instance.onError = originalPlatformHandler;
  });

  ClientRuntimeReporter reporter(
          {ClientRuntimeIdentity? identity = production}) =>
      ClientRuntimeReporter(
        repository: ClientRuntimeRepository(adapter),
        identity: identity,
      );

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  FlutterErrorDetails frameworkError(Object exception, {bool silent = false}) =>
      FlutterErrorDetails(
        exception: exception,
        stack: StackTrace.current,
        library: 'widgets library',
        silent: silent,
      );

  group('which builds report', () {
    test('a staging build reports nothing and touches no handler', () async {
      final identity = ClientRuntimeIdentity.resolve(
        environment: 'staging',
        appVersion: '0.4.1-public-beta+2',
        buildSha: sha,
        platform: 'web',
      );
      expect(identity, isNull);

      final before = FlutterError.onError;
      final platformBefore = PlatformDispatcher.instance.onError;
      reporter(identity: identity).start();
      await settle();

      expect(adapter.starts, isEmpty);
      expect(FlutterError.onError, same(before));
      expect(PlatformDispatcher.instance.onError, same(platformBefore));
    });

    test('a local, debug or unconfigured build reports nothing', () {
      for (final environment in ['', 'development', 'Production']) {
        expect(
          ClientRuntimeIdentity.resolve(
            environment: environment,
            appVersion: '0.4.1',
            buildSha: sha,
            platform: 'web',
          ),
          isNull,
          reason: '"$environment"',
        );
      }
      // Production, but without a usable build identity: left off rather than
      // sent malformed.
      expect(
        ClientRuntimeIdentity.resolve(
            environment: 'production',
            appVersion: '',
            buildSha: sha,
            platform: 'web'),
        isNull,
      );
      expect(
        ClientRuntimeIdentity.resolve(
            environment: 'production',
            appVersion: '0.4.1',
            buildSha: 'HEAD',
            platform: 'web'),
        isNull,
      );
      expect(
        ClientRuntimeIdentity.resolve(
            environment: 'production',
            appVersion: '0.4.1',
            buildSha: sha,
            platform: null),
        isNull,
      );
      // And the test build itself, which carries no deployment defines.
      expect(ClientRuntimeReporter.instance.enabled, isFalse);
    });

    test('a production build with a valid identity reports', () {
      expect(
        ClientRuntimeIdentity.resolve(
          environment: 'production',
          appVersion: '0.4.1-public-beta+2',
          buildSha: sha,
          platform: 'android',
        ),
        const ClientRuntimeIdentity(
          platform: 'android',
          appVersion: '0.4.1-public-beta+2',
          buildSha: sha,
        ),
      );
    });
  });

  group('the run', () {
    test('production starts exactly one run with the build identity', () async {
      reporter().start();
      await settle();

      expect(adapter.starts, [production]);
    });

    test('repeated start is idempotent and chains the handlers once', () async {
      final subject = reporter()..start();
      subject
        ..start()
        ..start();
      await settle();

      expect(adapter.starts, hasLength(1));

      FlutterError.onError!(frameworkError(StateError('boom')));
      await settle();
      expect(previousFlutterCalls, hasLength(1),
          reason: 'installed once, so the previous handler runs once');
      expect(adapter.reports, hasLength(1));
    });

    test('the run id lives in memory: a new process starts a new run',
        () async {
      reporter().start();
      await settle();
      adapter.runId = 'run-2';
      reporter().start();
      await settle();

      expect(adapter.starts, hasLength(2));
    });

    test('runtime code references no persistent storage', () {
      const files = [
        'lib/features/runtime/client_runtime_models.dart',
        'lib/features/runtime/client_runtime_adapter.dart',
        'lib/features/runtime/client_runtime_repository.dart',
        'lib/features/runtime/client_runtime_fingerprint.dart',
        'lib/features/runtime/client_runtime_reporter.dart',
        'lib/infrastructure/supabase/supabase_client_runtime_adapter.dart',
      ];
      for (final path in files) {
        final code = File(path)
            .readAsLinesSync()
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n')
            .toLowerCase();
        for (final forbidden in [
          'shared_preferences',
          'sharedpreferences',
          'localstorage',
          'sessionstorage',
          'indexeddb',
          'secure_storage',
          'cookie',
          'device_info',
          'dart:html',
          'package:web',
          'path_provider',
        ]) {
          expect(code, isNot(contains(forbidden)), reason: '$path: $forbidden');
        }
      }
    });
  });

  group('uncaught errors', () {
    test('a framework error reports flutter_framework only', () async {
      reporter().start();
      FlutterError.onError!(frameworkError(StateError('boom')));
      await settle();

      expect(adapter.reports, hasLength(1));
      final report = adapter.reports.single;
      expect(report.runId, 'run-1');
      expect(report.category, ClientErrorCategory.flutterFramework);
      expect(report.fingerprint, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(report.contextCode, 'StateError');
    });

    test('a silent framework report is not an uncaught error', () async {
      reporter().start();
      FlutterError
          .onError!(frameworkError(StateError('image failed'), silent: true));
      await settle();

      expect(adapter.reports, isEmpty);
      expect(previousFlutterCalls, hasLength(1),
          reason: 'still handed on exactly as before');
    });

    test('a platform error reports platform_unhandled only', () async {
      reporter().start();
      final handled = PlatformDispatcher.instance.onError!(
          ArgumentError('bad'), StackTrace.current);
      await settle();

      expect(adapter.reports.single.category,
          ClientErrorCategory.platformUnhandled);
      expect(adapter.reports.single.contextCode, 'ArgumentError');
      expect(handled, isTrue, reason: "the previous handler's answer");
    });

    test('the previous FlutterError handler still receives every error',
        () async {
      reporter().start();
      final details = frameworkError(StateError('boom'));
      FlutterError.onError!(details);
      await settle();

      expect(previousFlutterCalls, [same(details)]);
    });

    test('the previous platform handler keeps deciding the outcome', () async {
      reporter().start();
      final error = StateError('boom');
      PlatformDispatcher.instance.onError!(error, StackTrace.current);
      expect(previousPlatformCalls, [same(error)]);
    });

    test('with no previous platform handler the error stays unhandled',
        () async {
      PlatformDispatcher.instance.onError = null;
      reporter().start();

      final handled = PlatformDispatcher.instance.onError!(
          StateError('boom'), StackTrace.current);
      await settle();

      expect(handled, isFalse,
          reason: 'reporting must not turn a crash into a handled success');
      expect(adapter.reports, hasLength(1));
    });

    test('an error before the run is known waits for it', () async {
      adapter.startGate = Completer<String>();
      reporter().start();
      FlutterError.onError!(frameworkError(StateError('early')));
      await settle();
      expect(adapter.reports, isEmpty);

      adapter.startGate!.complete('run-late');
      await settle();
      expect(adapter.reports.single.runId, 'run-late');
    });

    test('without a run nothing is reported', () async {
      adapter.failStart = true;
      reporter().start();
      FlutterError.onError!(frameworkError(StateError('boom')));
      await settle();

      expect(adapter.reports, isEmpty,
          reason: 'an error with no run would be fabricated evidence');
      expect(previousFlutterCalls, hasLength(1));
    });

    test('reporting failures never throw into the app', () async {
      adapter
        ..failStart = false
        ..failReport = true;
      final subject = reporter();
      expect(subject.start, returnsNormally);
      expect(() => FlutterError.onError!(frameworkError(StateError('a'))),
          returnsNormally);
      expect(
        () => PlatformDispatcher.instance.onError!(
            StateError('b'), StackTrace.current),
        returnsNormally,
      );
      await settle();
      expect(adapter.reports, hasLength(2), reason: 'attempted, and swallowed');
      expect(previousFlutterCalls, hasLength(1));
    });

    test('a failure repeating every frame is bounded per run', () async {
      reporter().start();
      for (var i = 0; i < ClientRuntimeReporter.maxReportsPerRun + 15; i++) {
        FlutterError.onError!(frameworkError(StateError('loop')));
      }
      await settle();

      expect(
          adapter.reports, hasLength(ClientRuntimeReporter.maxReportsPerRun));
      expect(previousFlutterCalls,
          hasLength(ClientRuntimeReporter.maxReportsPerRun + 15));
    });
  });

  group('the fingerprint', () {
    StackTrace stackAt(String location) => StackTrace.fromString(
          '#0      Foo.bar (package:go_play/$location.dart:12:5)\n'
          '#1      Baz.qux (package:go_play/other.dart:40:9)\n',
        );

    test('is deterministic for the same failure at the same place', () {
      final first = clientErrorFingerprint(StateError('x'), stackAt('a'));
      final second = clientErrorFingerprint(StateError('y'), stackAt('a'));

      expect(first, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(second, first,
          reason: 'the message is not part of it, so it cannot change it');
    });

    test('differs by type and by place', () {
      final base = clientErrorFingerprint(StateError('x'), stackAt('a'));
      expect(clientErrorFingerprint(ArgumentError('x'), stackAt('a')),
          isNot(base));
      expect(
          clientErrorFingerprint(StateError('x'), stackAt('b')), isNot(base));
    });

    test('ignores line numbers, frame indexes and URL origins', () {
      final native = StackTrace.fromString(
          '#0      Foo.bar (package:go_play/a.dart:12:5)\n');
      final moved = StackTrace.fromString(
          '#3      Foo.bar (package:go_play/a.dart:99:1)\n');
      expect(clientErrorFingerprint(StateError('x'), moved),
          clientErrorFingerprint(StateError('x'), native));

      expect(
        normalizedTopFrames(StackTrace.fromString(
            'at Object.a2 (https://go-play-44y.pages.dev/main.dart.js:1234:56)')),
        ['at Object.a2 (/main.dart.js)'],
      );
    });

    test('is the same pinned value everywhere it is computed', () {
      // Every intermediate stays below 2^53, so the VM and the web agree.
      expect(fingerprintOf(''), '0000000000000000');
      expect(fingerprintOf('a'), '0000006100000068');
    });

    test('neither it nor what is sent carries the message', () async {
      const secret = 'sara@example.com said 90123456';
      reporter().start();
      FlutterError.onError!(frameworkError(StateError(secret)));
      await settle();

      final report = adapter.reports.single;
      final sent = '${report.runId}|${report.category.wireName}|'
          '${report.fingerprint}|${report.contextCode}';
      for (final fragment in ['sara', 'example', '90123456', 'said']) {
        expect(sent, isNot(contains(fragment)));
      }
    });

    test('the context code is sanitized and bounded', () {
      expect(clientErrorContextCode(StateError('x')), 'StateError');
      expect(clientErrorContextCode(const NetworkFailure()), 'NetworkFailure');
      expect(clientErrorContextCode(<String, int>{}),
          matches(RegExp(r'^[A-Za-z0-9_]{1,64}$')));
      expect(
          clientErrorContextCode(
              _AVeryLongExceptionNameThatKeepsGoingPastTheLimitOfSixtyFourCharactersForSure()),
          hasLength(64));
    });
  });
}

class _AVeryLongExceptionNameThatKeepsGoingPastTheLimitOfSixtyFourCharactersForSure
    implements Exception {}

class _Report {
  _Report(this.runId, this.category, this.fingerprint, this.contextCode);

  final String runId;
  final ClientErrorCategory category;
  final String fingerprint;
  final String? contextCode;
}

class _FakeRuntimeAdapter implements ClientRuntimeAdapter {
  final starts = <ClientRuntimeIdentity>[];
  final reports = <_Report>[];
  String runId = 'run-1';
  bool failStart = false;
  bool failReport = false;
  Completer<String>? startGate;

  @override
  Future<String> startRun(ClientRuntimeIdentity identity) async {
    starts.add(identity);
    if (failStart) throw const NetworkFailure();
    final gate = startGate;
    if (gate != null) return gate.future;
    return runId;
  }

  @override
  Future<void> reportError({
    required String runId,
    required ClientErrorCategory category,
    required String fingerprint,
    String? contextCode,
  }) async {
    reports.add(_Report(runId, category, fingerprint, contextCode));
    if (failReport) throw StateError('reporting failed');
  }
}
