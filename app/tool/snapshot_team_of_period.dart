// Stores the Team of Period of the period that has just closed.
//
//   dart run tool/snapshot_team_of_period.dart --period weekly            (dry run)
//   dart run tool/snapshot_team_of_period.dart --period weekly --write
//
// Environment: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
//
// **Dry run unless `--write` is given.** The Supabase project is shared by the
// staging and production front ends, so a write here is a write to live data;
// making it explicit is the one safety this script can add on top of the
// database's own (service-role only, closed period only, final once written).
//
// Timing (approved): weekly just after Sunday closes, ~Monday 00:05
// Asia/Muscat; monthly ~1st 00:05. Run manually during Package 5 validation.
// It always stores the *last closed* period, so an early or repeated run is
// harmless: a period already stored answers SNAPSHOT_ALREADY_FINAL.
import 'dart:convert';
import 'dart:io';

import 'package:go_play/features/statistics/team_of_period_models.dart';
import 'package:go_play/features/statistics/team_of_period_snapshot_job.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final period = _option(args, '--period');
  final write = args.contains('--write');
  final kind = switch (period) {
    'weekly' => TeamOfPeriodKind.weekly,
    'monthly' => TeamOfPeriodKind.monthly,
    _ => null,
  };
  if (kind == null) {
    stderr.writeln('usage: --period weekly|monthly [--write]');
    exitCode = 64;
    return;
  }

  final url = Platform.environment['SUPABASE_URL'] ?? '';
  final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] ?? '';
  if (url.isEmpty || key.isEmpty) {
    stderr.writeln('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required');
    exitCode = 64;
    return;
  }

  // The commit whose selector decided the award, so a stored team can always be
  // traced to the code that chose it.
  final sha = Platform.environment['GITHUB_SHA'] ?? 'local';
  final selectorVersion = sha.length > 12 ? sha.substring(0, 12) : sha;

  final client = http.Client();
  try {
    final outcomes = await TeamOfPeriodSnapshotJob(
      RestSnapshotPort(client, url: url, serviceKey: key),
    ).run(kind: kind, selectorVersion: selectorVersion, write: write);

    stdout.writeln('${write ? 'WRITE' : 'DRY RUN'} $period '
        '(selector $selectorVersion): ${outcomes.length} communities');
    for (final o in outcomes) {
      final s = o.snapshot;
      stdout.writeln([
        o.communityId,
        o.status.name,
        if (s != null) '${s.periodKey} ${s.state} seats=${s.awards.length}',
        if (o.detail != null) o.detail,
      ].join(' | '));
    }
    if (outcomes.any((o) => !o.ok)) exitCode = 1;
  } finally {
    client.close();
  }
}

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

/// PostgREST over HTTP with the service-role key. No Supabase SDK: the four
/// calls are plain RPCs and a select, and this keeps the script pure Dart.
class RestSnapshotPort implements TeamOfPeriodSnapshotPort {
  RestSnapshotPort(this._client,
      {required String url, required String serviceKey})
      : _base = '${url.replaceAll(RegExp(r'/+$'), '')}/rest/v1',
        _headers = {
          'apikey': serviceKey,
          'Authorization': 'Bearer $serviceKey',
          'Content-Type': 'application/json',
        };

  final http.Client _client;
  final String _base;
  final Map<String, String> _headers;

  @override
  Future<List<String>> activeCommunityIds() async {
    final rows = await _get('communities?select=id&is_active=eq.true&order=id');
    return [for (final row in rows) row['id'] as String];
  }

  @override
  Future<Map<String, dynamic>> closedWindow(
    String communityId,
    String periodType,
  ) async {
    final rows = await _rpc('community_period_xi_closed_window', {
      'p_community_id': communityId,
      'p_period_type': periodType,
    });
    if (rows.length != 1) {
      throw StateError('expected one window row, got ${rows.length}');
    }
    return rows.single;
  }

  @override
  Future<List<Map<String, dynamic>>> closedEvidence(
    String communityId,
    String periodType,
  ) =>
      _rpc('community_period_xi_closed_evidence', {
        'p_community_id': communityId,
        'p_period_type': periodType,
      });

  @override
  Future<void> record(Map<String, Object?> params) async {
    final response = await _client.post(
      Uri.parse('$_base/rpc/record_team_of_period_snapshot'),
      headers: _headers,
      body: jsonEncode(params),
    );
    if (response.statusCode >= 300) {
      throw SnapshotRefused(_errorToken(response.body));
    }
  }

  Future<List<Map<String, dynamic>>> _get(String path) async {
    final response =
        await _client.get(Uri.parse('$_base/$path'), headers: _headers);
    return _rows(response);
  }

  Future<List<Map<String, dynamic>>> _rpc(
    String function,
    Map<String, Object?> params,
  ) async {
    final response = await _client.post(
      Uri.parse('$_base/rpc/$function'),
      headers: _headers,
      body: jsonEncode(params),
    );
    return _rows(response);
  }

  List<Map<String, dynamic>> _rows(http.Response response) {
    if (response.statusCode >= 300) {
      throw StateError(
          'HTTP ${response.statusCode}: ${_errorToken(response.body)}');
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  /// The database's error token (`message`), never the whole body.
  static String _errorToken(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['message'] is String) {
        return json['message'] as String;
      }
    } catch (_) {}
    return 'UNKNOWN_ERROR';
  }
}
