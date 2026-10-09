import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The support writer may never authorize via email or a community role.
/// Production users must not gain direct UPDATE access to app_settings.
void main() {
  final sql = File('../supabase/migrations/0095_support_whatsapp_contact.sql')
      .readAsStringSync()
      .toLowerCase();

  test('support field is optional and never assigned a guessed default', () {
    expect(sql, contains('add column if not exists support_whatsapp_phone text'));
    expect(sql, isNot(contains('default +968')));
    expect(sql, contains('grant select (support_whatsapp_phone)'));
  });

  test('writer explicitly checks System Admin and limits execution', () {
    expect(sql, contains('public.is_system_admin()'));
    expect(sql, contains('revoke execute on function public.admin_set_support_whatsapp_phone(text)'));
    expect(sql, contains('grant execute on function public.admin_set_support_whatsapp_phone(text)'));
    expect(sql, contains('to authenticated;'));
    expect(sql, isNot(contains('grant update (support_whatsapp_phone)')));
    expect(sql, contains("set search_path = ''"));
  });
}
