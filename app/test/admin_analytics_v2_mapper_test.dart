import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';

void main() {
  test('maps Wave 1 admin overview v2 field names', () {
    final overview = adminAnalyticsOverviewFromRow({
      'total_users': 37,
      'new_users_today': 1,
      'new_users_7d': 3,
      'new_users_30d': 5,
      'dau': 2,
      'wau': 10,
      'mau': 12,
      'weekly_active_communities': 1,
      'matches_created_7d': 4,
      'matches_created_30d': 9,
      'tracked_registrations_7d': 2,
      'tracked_registrations_30d': 4,
      'results_recorded_7d': 4,
      'results_recorded_30d': 9,
      'retention_previous_week_users': 7,
      'retention_returning_users': 6,
      'weekly_retention_percent': 85.7,
    });

    expect(overview.totalUsers, 37);
    expect(overview.matches7d, 4);
    expect(overview.matches30d, 9);
    expect(overview.registrations7d, 2);
    expect(overview.registrations30d, 4);
    expect(overview.results7d, 4);
    expect(overview.results30d, 9);
    expect(overview.weeklyRetentionPercent, 85.7);
  });

  test('keeps v1 field fallback during the staging transition', () {
    final overview = adminAnalyticsOverviewFromRow({
      'matches_7d': 2,
      'matches_30d': 6,
      'registrations_7d': 3,
      'registrations_30d': 8,
      'results_7d': 1,
      'results_30d': 5,
    });

    expect(overview.matches7d, 2);
    expect(overview.matches30d, 6);
    expect(overview.registrations7d, 3);
    expect(overview.registrations30d, 8);
    expect(overview.results7d, 1);
    expect(overview.results30d, 5);
  });
}
