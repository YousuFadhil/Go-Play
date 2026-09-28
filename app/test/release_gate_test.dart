import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/release_gate.dart' hide main;

/// Wave 4 release integrity (OI-04): the build identity both deployment
/// workflows derive and publish, and the post-deploy smoke gate — tested
/// without a network by driving the gate with a fake fetch.
void main() {
  const sha = '0123456789abcdef0123456789abcdef01234567';
  const otherSha = 'fedcba9876543210fedcba9876543210fedcba98';
  final base = Uri.parse('https://go-play-staging.pages.dev');

  String deployedInfo({String sha = sha, String environment = 'staging'}) =>
      buildInfoJson(
          version: '0.4.1-public-beta+2', sha: sha, environment: environment);

  const goodBundle = 'var u="https://odhimoxvuhiyunwutzff.supabase.co";';

  /// A site answering every smoke path, with overrides.
  SmokeFetch site({
    Map<String, SmokeResponse> overrides = const {},
    String? info,
  }) =>
      (uri) async =>
          overrides[uri.path] ??
          switch (uri.path) {
            '/build-info.json' => SmokeResponse(200, info ?? deployedInfo()),
            '/main.dart.js' => const SmokeResponse(200, goodBundle),
            _ => const SmokeResponse(200, '<html></html>'),
          };

  group('build-info.json', () {
    test('holds exactly the version, the commit and the environment', () {
      final decoded =
          jsonDecode(deployedInfo(environment: 'production')) as Map;
      expect(decoded, {
        'version': '0.4.1-public-beta+2',
        'sha': sha,
        'environment': 'production',
      });
    });

    test('refuses anything the smoke check could never match', () {
      expect(() => buildInfoJson(version: '', sha: sha, environment: 'staging'),
          throwsFormatException);
      expect(
          () => buildInfoJson(
              version: '1.0', sha: 'HEAD', environment: 'staging'),
          throwsFormatException);
      expect(() => buildInfoJson(version: '1.0', sha: sha, environment: 'prod'),
          throwsFormatException);
    });
  });

  group('what a deployed site is checked for', () {
    test('the exact SHA and environment', () {
      expect(checkBuildInfo(deployedInfo(), sha: sha, environment: 'staging'),
          isEmpty);
      expect(
          checkBuildInfo(deployedInfo(sha: otherSha),
              sha: sha, environment: 'staging'),
          [contains('sha')]);
      expect(
          checkBuildInfo(deployedInfo(environment: 'production'),
              sha: sha, environment: 'staging'),
          [contains('environment')]);
      expect(checkBuildInfo('<html>', sha: sha, environment: 'staging'),
          [contains('not valid JSON')]);
    });

    test('a Supabase URL and no service_role in the bundle', () {
      expect(checkBundle(goodBundle), isEmpty);
      expect(checkBundle('var nothing;'), [contains('Supabase URL')]);
      expect(
          checkBundle('$goodBundle service_role'), [contains('service_role')]);
    });

    test('every path, cache-busted by the commit', () async {
      final asked = <Uri>[];
      final problems = await smokeOnce(
        base,
        (uri) {
          asked.add(uri);
          return site()(uri);
        },
        sha: sha,
        environment: 'staging',
      );

      expect(problems, isEmpty);
      expect([for (final uri in asked) uri.path], smokePaths);
      expect(asked.every((uri) => uri.queryParameters['smoke'] == sha), isTrue);
      expect(smokeUri(Uri.parse('https://x.dev/'), '/main.dart.js', sha).path,
          '/main.dart.js');
    });

    test('a non-200 or a failed request is a problem', () async {
      final problems = await smokeOnce(
        base,
        (uri) async => uri.path == '/flutter_bootstrap.js'
            ? const SmokeResponse(404, '')
            : uri.path == '/'
                ? throw const SocketException('down')
                : site()(uri),
        sha: sha,
        environment: 'staging',
      );
      expect(problems, [contains('/: request failed'), contains('HTTP 404')]);
    });
  });

  group('the bounded retry', () {
    test('passes as soon as the site serves the build', () async {
      var calls = 0;
      final sleeps = <Duration>[];
      final passed = await smoke(
        base,
        (uri) async {
          if (uri.path == '/build-info.json') calls++;
          return uri.path == '/build-info.json' && calls < 3
              ? const SmokeResponse(404, '')
              : site()(uri);
        },
        sha: sha,
        environment: 'staging',
        attempts: 5,
        delay: const Duration(seconds: 15),
        sleep: (d) async => sleeps.add(d),
        log: (_) {},
      );

      expect(passed, isTrue);
      expect(sleeps, hasLength(2));
    });

    test('a deliberately mismatched SHA fails after the last attempt',
        () async {
      var sleeps = 0;
      final passed = await smoke(
        base,
        site(info: deployedInfo(sha: otherSha)),
        sha: sha,
        environment: 'staging',
        attempts: 4,
        sleep: (_) async => sleeps++,
        log: (_) {},
      );

      expect(passed, isFalse);
      expect(sleeps, 3, reason: 'bounded: attempts - 1 waits, then it stops');
    });
  });

  group('the deployment workflows', () {
    final production =
        File('../.github/workflows/deploy-web.yml').readAsStringSync();
    final staging =
        File('../.github/workflows/deploy-staging.yml').readAsStringSync();
    final workflows = {'production': production, 'staging': staging};

    test('derive the build identity from the checked-out commit', () {
      for (final MapEntry(key: name, value: yaml) in workflows.entries) {
        expect(yaml, contains('BUILD_SHA="\$(git rev-parse HEAD)"'),
            reason: name);
        expect(
          yaml,
          contains("APP_VERSION=\"\$(sed -n 's/^version:[[:space:]]*//p' "
              "app/pubspec.yaml"),
          reason: name,
        );
        expect(yaml, contains(r"grep -Eq '^[0-9a-f]{40}$'"), reason: name);
        for (final define in [
          '--dart-define=GOPLAY_DEPLOYMENT_ENV="\$DEPLOYMENT_ENV"',
          '--dart-define=GOPLAY_APP_VERSION="\$APP_VERSION"',
          '--dart-define=GOPLAY_BUILD_SHA="\$BUILD_SHA"',
          '--dart-define=PUBLIC_WEB_BASE="\$PUBLIC_WEB_BASE"',
        ]) {
          expect(yaml, contains(define), reason: '$name: $define');
        }
      }
    });

    test('declare different deployment environments', () {
      expect(production, contains('DEPLOYMENT_ENV: production'));
      expect(production, isNot(contains('DEPLOYMENT_ENV: staging')));
      expect(staging, contains('DEPLOYMENT_ENV: staging'));
      expect(staging, isNot(contains('DEPLOYMENT_ENV: production')));
    });

    test('state the production public base, unchanged from the app default',
        () {
      expect(production,
          contains('PUBLIC_WEB_BASE: https://go-play-44y.pages.dev'));
      expect(
        File('lib/core/config.dart').readAsStringSync(),
        contains("defaultValue: 'https://go-play-44y.pages.dev'"),
      );
      expect(staging,
          contains('PUBLIC_WEB_BASE: https://go-play-staging.pages.dev'));
    });

    test('write build-info.json after the build and before publishing', () {
      for (final MapEntry(key: name, value: yaml) in workflows.entries) {
        final build = yaml.indexOf('flutter build web --release');
        final write = yaml.indexOf('tool/release_gate.dart write-build-info');
        final publish = yaml.indexOf('name: Publish to Cloudflare Pages');
        expect(write, greaterThan(build), reason: name);
        expect(publish, greaterThan(write), reason: name);
        expect(yaml, contains('--out build/web/build-info.json'), reason: name);
      }
    });

    test('smoke-check the primary site after publishing', () {
      for (final MapEntry(key: name, value: yaml) in workflows.entries) {
        final publish = yaml.indexOf('name: Publish to Cloudflare Pages');
        final smoke = yaml.indexOf('tool/release_gate.dart smoke');
        expect(smoke, greaterThan(publish), reason: name);
        // Shell line continuations joined, then whitespace collapsed.
        final command = yaml
            .replaceAll(RegExp(r'\\\s*\n'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ');
        expect(
          command,
          contains(
              'dart run tool/release_gate.dart smoke --url "\$PUBLIC_WEB_BASE" '
              '--sha "\$BUILD_SHA" --environment "\$DEPLOYMENT_ENV"'),
          reason: name,
        );
      }
    });

    test('keep their Cloudflare projects, branches and triggers', () {
      expect(
          production,
          contains(
              'pages deploy app/build/web --project-name=go-play --branch=main'));
      expect(
          staging,
          contains(
              'pages deploy app/build/web --project-name=go-play-staging --branch=staging'));
      expect(production, contains('    branches: [main]'));
      expect(production, contains('group: cloudflare-pages\n'));
      expect(staging, contains('group: cloudflare-pages-staging'));
      expect(staging, contains('ref: \${{ inputs.source_ref }}'));
      expect(production, contains('environment: github-pages'));
      expect(staging, contains('environment: staging'));
    });
  });
}
