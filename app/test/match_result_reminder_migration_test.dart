import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static migration contract; behavioral SQL tests still run in isolated PG.
void main() {
  final sql = File('../supabase/migrations/0100_match_result_reminder.sql')
      .readAsStringSync()
      .toLowerCase();

  test('one reminder runs 30 minutes after a future match ends', () {
    expect(sql, contains("interval '30 minutes'"));
    expect(sql, contains("interval '35 minutes' > now()"));
    expect(sql, contains('m.end_at > a.activated_at'));
    expect(sql, contains('m.is_historical = false'));
    expect(sql, contains('match_result_reminder_activation'));
    expect(sql, contains('on conflict (id) do nothing'));
  });

  test('a saved result and an inactive community suppress delivery', () {
    expect(sql, contains('from public.match_results r'));
    expect(sql, contains('where r.match_id = m.id'));
    expect(sql, contains('c.is_active = true'));
    expect(sql, contains('for update of m skip locked'));
    expect(sql, contains('r.match_id = v_match.id'));
  });

  test('only active owner and community admins are recipients', () {
    expect(sql, contains('select c.owner_id as user_id'));
    expect(sql, contains("cm.role = 'admin'"));
    expect(sql, contains('where u.is_active = true'));
    expect(sql, contains('union'));
  });

  test('persistent claim prevents replays even if notice is deleted', () {
    expect(sql, contains('match_result_reminder_dispatches'));
    expect(sql, contains('match_id uuid primary key'));
    expect(sql, contains('on conflict (match_id) do nothing'));
    expect(sql, contains('from claimed cl'));
  });

  test('existing medium match push pipeline and routing are reused', () {
    expect(sql, contains("'match_result_reminder'"));
    expect(sql, contains("'medium'"));
    expect(sql, contains("'match'"));
    expect(sql, contains('insert into public.notifications'));
    expect(sql, contains('user_id, match_id, type, message'));
    expect(sql, isNot(contains('net.http_post')));
  });

  test('scheduler is unique, every minute, and not client callable', () {
    expect(sql, contains('create extension if not exists pg_cron'));
    expect(sql, contains("'go-play-missing-match-result-v1'"));
    expect(sql, contains("'* * * * *'"));
    expect(sql, contains('security invoker'));
    expect(sql, contains("set search_path = ''"));
    expect(
      sql,
      contains(
        'revoke all on function public.emit_missing_match_result_reminders_v1()',
      ),
    );
    expect(sql, contains('from public, anon, authenticated, service_role'));
  });
}
