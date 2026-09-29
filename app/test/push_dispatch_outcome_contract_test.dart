import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static contract for the Wave 4 change to `push-dispatch`: one best-effort
/// outcome record per terminal branch, with the transport, the secret check
/// and the stale-token cleanup left exactly as they were.
///
/// The Edge Function is TypeScript and is not deployed or executed here, so the
/// contract is pinned against its source.
void main() {
  final source = File('../supabase/functions/push-dispatch/index.ts')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final flat = source.replaceAll(RegExp(r'\s+'), ' ');

  String functionSource(String signature) {
    final start = source.indexOf(signature);
    if (start < 0) throw StateError('$signature not found');
    final end = source.indexOf('\n}\n', start);
    return source.substring(start, end);
  }

  final handler = source.substring(source.indexOf('Deno.serve('));

  test('every terminal outcome is recorded through conclude, once', () {
    for (final outcome in [
      'not_found',
      'suppressed',
      'no_devices',
      'unrenderable',
      'dispatched',
      'internal_error',
    ]) {
      expect(
        RegExp('outcome: "$outcome"').allMatches(handler).length,
        1,
        reason: outcome,
      );
    }
    // Six terminal branches, six conclude calls, and no other return after
    // the payload is loaded.
    expect(RegExp(r'return await conclude\(').allMatches(handler).length, 6);
    final afterAuthentication =
        handler.substring(handler.indexOf('let payload'));
    expect(
      RegExp(r'return (?!await conclude)').hasMatch(afterAuthentication),
      isFalse,
      reason: 'a terminal return that skipped the evidence',
    );
    // conclude records exactly once, then returns the response it was given.
    final conclude = functionSource('async function conclude(');
    expect(RegExp(r'recordOutcome\(').allMatches(conclude).length, 1);
    expect(conclude, contains('return response;'));
  });

  test('the dispatched record carries the counts the response reports', () {
    expect(
      flat,
      contains('outcome: "dispatched", priority: loaded.priority, '
          'tokenCount: loaded.tokens.length, sent, stale, failed,'),
    );
    expect(
        flat,
        contains(
            'Response.json({ status: "dispatched", sent, stale, failed })'));
  });

  test('recording evidence can never fail the push', () {
    final record = functionSource('async function recordOutcome(');
    // Everything inside one try, and the catch only logs.
    expect(record.trimLeft(), contains('try {'));
    expect(record, contains('} catch (error) {'));
    final catchBlock = record.substring(record.indexOf('} catch (error) {'));
    expect(catchBlock, isNot(contains('throw')));
    expect(record, isNot(contains('throw ')));
    // Bounded, and no retry loop.
    expect(record, contains('signal: AbortSignal.timeout(OUTCOME_TIMEOUT_MS)'));
    expect(record, isNot(contains('while (')));
    expect(record, isNot(contains('for (')));
    // Logged by status or error name only, never a body.
    expect(record, isNot(contains('.text()')));
    expect(record, isNot(contains('.json()')));
  });

  test('it writes through the service-role outcome RPC and nothing else', () {
    final record = functionSource('async function recordOutcome(');
    expect(record, contains('/rest/v1/rpc/record_push_dispatch_outcome_v1'));
    expect(record, contains('Authorization: `Bearer \${SERVICE_ROLE_KEY}`'));
    // Only these arguments: no token, notice text, recipient or response.
    final body = record.substring(
        record.indexOf('JSON.stringify({'), record.indexOf('}),'));
    final keys = RegExp(r'(p_[a-z_]+):').allMatches(body).map((m) => m[1]);
    expect(keys.toSet(), {
      'p_notification_id',
      'p_outcome',
      'p_priority',
      'p_token_count',
      'p_sent_count',
      'p_stale_count',
      'p_failed_count',
    });
    for (final forbidden in [
      'user_id',
      'token:',
      'title',
      'body:',
      'message'
    ]) {
      expect(body, isNot(contains(forbidden)), reason: forbidden);
    }
    // The payload's "unregistered" is not a priority.
    expect(
        source,
        contains(
            'const REGISTRY_PRIORITIES = new Set(["high", "medium", "low"]);'));
  });

  test('stale tokens are still forgotten, before anything is recorded', () {
    final send = functionSource('async function send(');
    expect(send, contains('await forgetToken(deviceToken);'));
    expect(send, contains('return "stale";'));
    // The dispatched record is made only after every send has settled.
    expect(handler.indexOf('await Promise.all('),
        lessThan(handler.indexOf('outcome: "dispatched"')));
  });

  test('the secret check and transport are unchanged', () {
    expect(
      flat,
      contains('DISPATCH_SECRET === "" || '
          'request.headers.get("x-push-secret") !== DISPATCH_SECRET'),
    );
    expect(
        flat, contains('return new Response("Forbidden", { status: 403 });'));
    expect(
        flat,
        contains(
            'return new Response("Method not allowed", { status: 405 });'));
    expect(
        flat, contains('return new Response(String(error), { status: 400 });'));
    // The internal failure still answers 500, with the evidence beside it.
    expect(flat, contains('new Response(String(error), { status: 500 }),'));
    expect(source, contains('/rest/v1/rpc/push_dispatch_payload'));
  });

  test('the README describes the evidence, not "no delivery log"', () {
    final readme = File('../supabase/functions/push-dispatch/README.md')
        .readAsStringSync()
        .toLowerCase();
    expect(readme, contains('## outcome evidence'));
    expect(readme, contains('record_push_dispatch_outcome_v1'));
    expect(readme, isNot(contains('no delivery log')));
    expect(source.toLowerCase(), isNot(contains('no delivery log')));
  });
}
