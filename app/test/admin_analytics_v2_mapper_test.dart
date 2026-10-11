import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/auth/auth_models.dart' show PlayerPosition;
import 'package:go_play/features/profile/profile_models.dart'
    show ProfileVisibility;
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

  group('admin_get_user_account (0095)', () {
    final row = <String, dynamic>{
      'id': 'u1',
      'full_name': 'Ali Al Amri',
      'phone': '+96891234567',
      'email': 'ali@example.com',
      'date_of_birth': '2000-05-05',
      'primary_position': 'DEF',
      'secondary_position': 'MID',
      'profile_visibility': 'COMMUNITY_MEMBERS',
      'age_visible': false,
      'default_wilayat_code': 7,
      'avatar_path': 'u1/avatar.jpg',
      'is_active': false,
      'suspended_at': '2026-08-01T00:00:00+00:00',
      'suspension_reason': 'Repeated no-shows',
      'is_system_admin': false,
      'match_push': false,
      'community_push': true,
      'mute_all': true,
      'sign_in_providers': ['email', 'google'],
      'email_confirmed_at': '2026-01-15T09:00:00+00:00',
      'last_sign_in_at': '2026-09-03T18:30:00+00:00',
      'created_at': '2026-01-15T09:00:00+00:00',
    };

    test('every column the RPC returns is read', () {
      final account =
          adminUserAccountFromRow(row, avatarUrl: 'https://x/a.jpg');

      expect(account.id, 'u1');
      expect(account.fullName, 'Ali Al Amri');
      expect(account.phone, '+96891234567');
      expect(account.email, 'ali@example.com');
      expect(account.dateOfBirth, DateTime(2000, 5, 5));
      expect(account.primaryPosition, PlayerPosition.def);
      expect(account.secondaryPosition, PlayerPosition.mid);
      expect(account.profileVisibility, ProfileVisibility.communityMembersOnly);
      expect(account.ageVisible, isFalse);
      expect(account.defaultWilayatCode, 7);
      expect(account.avatarUrl, 'https://x/a.jpg');
      expect(account.isActive, isFalse);
      expect(account.suspendedAt, DateTime.utc(2026, 8, 1));
      expect(account.suspensionReason, 'Repeated no-shows');
      expect(account.isSystemAdmin, isFalse);
      expect(account.matchPush, isFalse);
      expect(account.communityPush, isTrue);
      expect(account.muteAll, isTrue);
      expect(account.signInProviders, ['email', 'google']);
      expect(account.emailConfirmedAt, DateTime.utc(2026, 1, 15, 9));
      expect(account.lastSignInAt, DateTime.utc(2026, 9, 3, 18, 30));
      expect(account.createdAt, DateTime.utc(2026, 1, 15, 9));
    });

    test(
        'a null date of birth, secondary position and Default Location stay null',
        () {
      final account = adminUserAccountFromRow({
        ...row,
        'date_of_birth': null,
        'secondary_position': null,
        'default_wilayat_code': null,
      });

      expect(account.dateOfBirth, isNull);
      expect(account.secondaryPosition, isNull);
      expect(account.defaultWilayatCode, isNull);
    });

    test('never signed in and never confirmed read as absent, not as a date',
        () {
      final account = adminUserAccountFromRow({
        ...row,
        'email_confirmed_at': null,
        'last_sign_in_at': null,
      });

      expect(account.emailConfirmedAt, isNull);
      expect(account.lastSignInAt, isNull);
    });

    test('a row without the booleans reads as the ordinary account', () {
      final account = adminUserAccountFromRow({
        'id': 'u2',
        'primary_position': 'GK',
        'created_at': '2026-01-15T09:00:00+00:00',
      });

      expect(account.isActive, isTrue);
      expect(account.isSystemAdmin, isFalse);
      expect(account.ageVisible, isTrue);
      expect(account.matchPush, isTrue);
      expect(account.communityPush, isTrue);
      expect(account.muteAll, isFalse);
      expect(account.profileVisibility, ProfileVisibility.everyone);
      expect(account.signInProviders, isEmpty);
    });

    test('the provider list tolerates what is not a string', () {
      expect(
        adminUserAccountFromRow({
          ...row,
          'sign_in_providers': ['email', 7, '', null, 'google'],
        }).signInProviders,
        ['email', 'google'],
      );
      expect(
        adminUserAccountFromRow({...row, 'sign_in_providers': null})
            .signInProviders,
        isEmpty,
      );
    });
  });

  group('the five account edits send their own group and nothing else', () {
    test('name and phone carry no date of birth', () {
      expect(
        adminUpdateAccountParams('u1',
            fullName: 'Ali', phone: '+96891234567', reason: 'typo'),
        {
          'p_user_id': 'u1',
          'p_full_name': 'Ali',
          'p_phone': '+96891234567',
          'p_reason': 'typo',
        },
      );
    });

    test('the player profile sends a date, not an instant, and keeps nulls',
        () {
      expect(
        adminUpdatePlayerProfileParams('u1',
            dateOfBirth: DateTime(2000, 5, 5, 23, 59),
            primaryPosition: PlayerPosition.fwd,
            secondaryPosition: null),
        {
          'p_user_id': 'u1',
          'p_date_of_birth': '2000-05-05',
          'p_primary_position': 'FWD',
          'p_secondary_position': null,
          'p_reason': null,
        },
      );
      expect(
        adminUpdatePlayerProfileParams('u1',
            dateOfBirth: null,
            primaryPosition: PlayerPosition.gk,
            secondaryPosition: PlayerPosition.def)['p_date_of_birth'],
        isNull,
      );
    });

    test('privacy uses the database tokens', () {
      expect(
        adminUpdatePrivacyParams('u1',
            visibility: ProfileVisibility.communityMembersOnly,
            ageVisible: false),
        {
          'p_user_id': 'u1',
          'p_profile_visibility': 'COMMUNITY_MEMBERS',
          'p_age_visible': false,
          'p_reason': null,
        },
      );
      expect(
        adminUpdatePrivacyParams('u1',
            visibility: ProfileVisibility.everyone,
            ageVisible: true)['p_profile_visibility'],
        'EVERYONE',
      );
    });

    test('the Default Location sends the code, or null to clear it', () {
      expect(
        adminUpdateDefaultWilayatParams('u1', wilayatCode: 7),
        {'p_user_id': 'u1', 'p_wilayat_code': 7, 'p_reason': null},
      );
      expect(
        adminUpdateDefaultWilayatParams('u1', wilayatCode: null)
            .containsKey('p_wilayat_code'),
        isTrue,
        reason: 'a clear is an explicit null, not an omitted key',
      );
    });

    test('push preferences send all three switches', () {
      expect(
        adminUpdatePushPreferencesParams('u1',
            matchPush: true, communityPush: false, muteAll: false),
        {
          'p_user_id': 'u1',
          'p_match_push': true,
          'p_community_push': false,
          'p_mute_all': false,
          'p_reason': null,
        },
      );
    });
  });
}
