// Release integrity for the web deployment workflows (Wave 4, OI-04).
//
// Two commands, used by both `deploy-web.yml` and `deploy-staging.yml`:
//
//   dart run tool/release_gate.dart write-build-info \
//     --out build/web/build-info.json \
//     --version <app version> --sha <checked-out commit> \
//     --environment production|staging
//
//   dart run tool/release_gate.dart smoke \
//     --url <primary site> --sha <checked-out commit> \
//     --environment production|staging [--attempts 10] [--delay-seconds 15]
//
// `build-info.json` holds the version, the commit and the environment — no
// secret. The smoke check, run after Cloudflare publish, retries a bounded
// number of times and fails the workflow when the primary site never serves the
// expected build. It does not roll anything back.
//
// Everything that decides pass or fail is a plain function of strings, so it
// is tested without a network; only `main` performs requests.

import 'dart:convert';
import 'dart:io';

/// The two deployment environments a build can declare.
const Set<String> deploymentEnvironments = {'production', 'staging'};

/// The paths the smoke check reads from the primary site.
const List<String> smokePaths = [
  '/',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/build-info.json',
];

final RegExp _commitSha = RegExp(r'^[0-9a-f]{40}$');

/// The `build-info.json` for this build, after checking what goes into it.
///
/// Throws [FormatException] rather than writing a file the smoke check could
/// never match.
String buildInfoJson({
  required String version,
  required String sha,
  required String environment,
}) {
  final problems = [
    if (version.trim().isEmpty) 'version is empty',
    if (!_commitSha.hasMatch(sha)) 'sha is not a 40-hex commit: "$sha"',
    if (!deploymentEnvironments.contains(environment))
      'environment must be production or staging: "$environment"',
  ];
  if (problems.isNotEmpty) throw FormatException(problems.join('; '));
  final json = const JsonEncoder.withIndent('  ').convert({
    'version': version.trim(),
    'sha': sha,
    'environment': environment,
  });
  return '$json\n';
}

/// What is wrong with a deployed `build-info.json`, or nothing.
List<String> checkBuildInfo(
  String body, {
  required String sha,
  required String environment,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return ['build-info.json is not valid JSON'];
  }
  if (decoded is! Map) return ['build-info.json is not a JSON object'];
  final version = decoded['version'];
  return [
    if (decoded['sha'] != sha)
      'build-info.json sha is "${decoded['sha']}", expected "$sha"',
    if (decoded['environment'] != environment)
      'build-info.json environment is "${decoded['environment']}", '
          'expected "$environment"',
    if (version is! String || version.isEmpty) 'build-info.json has no version',
  ];
}

/// What is wrong with a deployed `main.dart.js`, or nothing.
List<String> checkBundle(String mainDartJs) => [
      if (!mainDartJs.contains('supabase.co'))
        'main.dart.js carries no Supabase URL marker',
      if (mainDartJs.contains('service_role'))
        'main.dart.js contains a service_role marker',
    ];

/// One HTTP answer, reduced to what the smoke check reads.
class SmokeResponse {
  const SmokeResponse(this.status, this.body);

  final int status;
  final String body;
}

typedef SmokeFetch = Future<SmokeResponse> Function(Uri uri);

/// [path] on [base], with a query naming the commit so no cache can answer
/// with a previous deployment's copy.
Uri smokeUri(Uri base, String path, String sha) {
  final root = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  return base.replace(path: '$root$path', queryParameters: {'smoke': sha});
}

/// Every problem one pass over [smokePaths] finds; empty means it passed.
Future<List<String>> smokeOnce(
  Uri base,
  SmokeFetch fetch, {
  required String sha,
  required String environment,
}) async {
  final problems = <String>[];
  for (final path in smokePaths) {
    final SmokeResponse response;
    try {
      response = await fetch(smokeUri(base, path, sha));
    } catch (error) {
      problems.add('$path: request failed (${error.runtimeType})');
      continue;
    }
    if (response.status != 200) {
      problems.add('$path: HTTP ${response.status}');
      continue;
    }
    if (path == '/main.dart.js') problems.addAll(checkBundle(response.body));
    if (path == '/build-info.json') {
      problems.addAll(
        checkBuildInfo(response.body, sha: sha, environment: environment),
      );
    }
  }
  return problems;
}

/// Runs [smokeOnce] up to [attempts] times, [delay] apart, and reports
/// whether any pass succeeded. Bounded: it never waits longer than
/// `attempts - 1` delays.
Future<bool> smoke(
  Uri base,
  SmokeFetch fetch, {
  required String sha,
  required String environment,
  int attempts = 10,
  Duration delay = const Duration(seconds: 15),
  Future<void> Function(Duration) sleep = _sleep,
  void Function(String) log = print,
}) async {
  for (var attempt = 1; attempt <= attempts; attempt++) {
    final problems =
        await smokeOnce(base, fetch, sha: sha, environment: environment);
    if (problems.isEmpty) {
      log('smoke check passed on attempt $attempt/$attempts');
      return true;
    }
    log('attempt $attempt/$attempts: ${problems.join('; ')}');
    if (attempt < attempts) await sleep(delay);
  }
  return false;
}

Future<void> _sleep(Duration duration) => Future<void>.delayed(duration);

/// A real request, bounded by a timeout.
Future<SmokeResponse> _httpFetch(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(seconds: 60));
    return SmokeResponse(response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

Map<String, String> _options(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final key = args[i];
    if (!key.startsWith('--') || i + 1 >= args.length) {
      throw FormatException('expected --name value pairs, got "$key"');
    }
    options[key.substring(2)] = args[++i];
  }
  return options;
}

String _required(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.isEmpty) {
    throw FormatException('--$name is required');
  }
  return value;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: release_gate.dart write-build-info|smoke --...');
    exit(64);
  }
  try {
    final options = _options(args.sublist(1));
    switch (args.first) {
      case 'write-build-info':
        final json = buildInfoJson(
          version: _required(options, 'version'),
          sha: _required(options, 'sha'),
          environment: _required(options, 'environment'),
        );
        File(_required(options, 'out')).writeAsStringSync(json);
        stdout.write(json);
      case 'smoke':
        final passed = await smoke(
          Uri.parse(_required(options, 'url')),
          _httpFetch,
          sha: _required(options, 'sha'),
          environment: _required(options, 'environment'),
          attempts: int.parse(options['attempts'] ?? '10'),
          delay: Duration(seconds: int.parse(options['delay-seconds'] ?? '15')),
        );
        if (!passed) {
          stderr.writeln('smoke check failed: the published site never served '
              'the expected build');
          exit(1);
        }
      default:
        throw FormatException('unknown command "${args.first}"');
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exit(64);
  }
}
