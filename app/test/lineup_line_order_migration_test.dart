import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0107 says -- a static review of the file, not a runtime
/// result. Behaviour was shown by a rolled-back dry run on the live database
/// and is checked after the apply by `supabase/tool/0107_..._verify.sql`.
///
/// What this catches is the mistake that is invisible in review: the writer
/// losing its role check or gaining an `owner_id` shortcut, a grant reaching
/// `anon`, a search path without `pg_temp`, or the reset trigger disappearing.
void main() {
  const path = '../supabase/migrations/0107_lineup_line_order.sql';

  // Git checks these files out with CRLF endings on Windows.
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');

  /// The SQL without `--` comment lines, so prose cannot satisfy a check.
  final code = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  String body(String function) {
    final start = code.indexOf('function public.$function(');
    expect(start, greaterThan(-1), reason: '$function is defined');
    final open = code.indexOf(r'$$', start);
    final close = code.indexOf(r'$$', open + 2);
    return code.substring(start, close);
  }

  test('the column is nullable and has no default', () {
    expect(
      RegExp(r'add column line_order smallint\s+check \(line_order is null or '
              r'line_order >= 1\);')
          .hasMatch(code),
      isTrue,
    );
    expect(RegExp(r'line_order smallint[^;]*default').hasMatch(code), isFalse);
  });

  test('the writer checks the role, never an owner column', () {
    final writer = body('set_match_lineup_line_order');
    expect(writer,
        contains('public.is_match_community_admin(p_match_id, auth.uid())'));
    expect(writer, contains("raise exception 'NOT_AUTHORIZED'"));
    expect(writer, contains('public.is_current_user_active()'));
    expect(writer, contains("raise exception 'ROSTER_MISMATCH'"));
    expect(RegExp(r'owner_id|created_by').hasMatch(writer), isFalse);
    // Presentation only: no match effect is touched.
    expect(
        RegExp(r'detach_match_effects|attach_match_effects').hasMatch(writer),
        isFalse);
  });

  test('every SECURITY DEFINER function pins pg_temp last', () {
    for (final function in [
      'set_match_lineup_line_order',
      'replace_match_lineup',
      'advance_match_participation_revision',
      'public_match_lineup',
    ]) {
      expect(body(function), contains('set search_path = public, pg_temp'),
          reason: function);
    }
  });

  test('grants: the writer to signed-in users only, the public read as before',
      () {
    expect(
      code,
      contains('revoke all on function\n'
          '  public.set_match_lineup_line_order(uuid, text, text, uuid[]) '
          'from public, anon;'),
    );
    expect(
      code,
      contains('grant execute on function\n'
          '  public.set_match_lineup_line_order(uuid, text, text, uuid[])\n'
          '  to authenticated, service_role;'),
    );
    expect(
      code,
      contains('revoke execute on function public.reset_lineup_line_order()\n'
          '  from public, anon, authenticated;'),
    );
    expect(
      code,
      contains('grant execute on function public.public_match_lineup(uuid)\n'
          '  to anon, authenticated, service_role;'),
    );
  });

  test('the reset happens in the database, on a team or position change', () {
    expect(body('reset_lineup_line_order'),
        contains('new.team is distinct from old.team'));
    expect(
        body('reset_lineup_line_order'),
        contains(
            'new.assigned_position is distinct from old.assigned_position'));
    expect(
      code,
      contains('create trigger match_team_assignments_reset_line_order\n'
          'before update on public.match_team_assignments'),
    );
    // The replace path keeps an unchanged row's order, never a generation's.
    final replace = body('replace_match_lineup');
    expect(
        replace, contains('case when not coalesce(p_from_generation, false)'));
    expect(replace, contains("prev->>'team' = assignment->>'team'"));
    expect(
        replace,
        contains(
            "prev->>'assigned_position' = assignment->>'assigned_position'"));
  });

  test('an order-only update leaves participation evidence alone', () {
    expect(
      body('advance_match_participation_revision'),
      contains("(to_jsonb(new) - 'line_order' - 'updated_at')\n"
          "       = (to_jsonb(old) - 'line_order' - 'updated_at')"),
    );
  });

  test('both pitch read models return the order', () {
    expect(
        code,
        contains(
            '    false)                                        as is_mvp,\n'
            '  a.line_order\n'));
    expect(body('public_match_lineup'), contains('l.line_order'));
  });
}
