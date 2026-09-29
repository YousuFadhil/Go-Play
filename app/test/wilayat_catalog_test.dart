import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/locations/guest_location_store.dart';
import 'package:go_play/features/locations/wilayat_adapter.dart';
import 'package:go_play/features/locations/wilayat_models.dart';
import 'package:go_play/features/locations/wilayat_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/wilayat_mapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wilayat_fixtures.dart';

/// The Wilayat reference data as a feature: what is searched, what is offered,
/// what is cached, and what a guest's stored choice is worth.
void main() {
  group('search normalisation', () {
    test('hamza, taa marbuta and tatweel fold; Latin is lower-cased', () {
      expect(normalizeWilayatSearch('إزكي'), normalizeWilayatSearch('ازكي'));
      expect(normalizeWilayatSearch('أدم'), normalizeWilayatSearch('ادم'));
      expect(normalizeWilayatSearch('إبراء'), normalizeWilayatSearch('ابراء'));
      expect(
          normalizeWilayatSearch('الباطنة'), normalizeWilayatSearch('الباطنه'));
      expect(normalizeWilayatSearch('مـسـقط'), normalizeWilayatSearch('مسقط'));
      expect(normalizeWilayatSearch('SoHar'), 'sohar');
      expect(normalizeWilayatSearch('  as   seeb '), 'as seeb');
    });

    test('unrelated letters are left alone', () {
      expect(normalizeWilayatSearch('صحار'), 'صحار');
      expect(
          normalizeWilayatSearch('صحار'), isNot(normalizeWilayatSearch('صحم')));
    });
  });

  group('the catalog', () {
    final catalog = wilayatFixtureCatalog();

    List<int> codes(String query) => [
          for (final group in catalog.groups(query: query))
            for (final wilayat in group.wilayats) wilayat.code,
        ];

    test('lists active Wilayats grouped by Governorate in display order', () {
      final groups = catalog.groups();

      expect([for (final g in groups) g.governorate.code], [1, 2, 6, 9]);
      expect([for (final w in groups[1].wilayats) w.code], [7, 9]);
    });

    test('an inactive Wilayat is not offered, but still names its label', () {
      expect(codes('').contains(55), isFalse);
      expect(catalog.byCode(55)?.nameEn, 'Sadh');
      expect(catalog.nameOf(55, arabic: false), 'Sadh');
      expect(catalog.activeByCode(55), isNull);
    });

    test('an unknown or null code is no Wilayat at all', () {
      expect(catalog.byCode(999), isNull);
      expect(catalog.byCode(null), isNull);
      expect(catalog.activeByCode(999), isNull);
      expect(catalog.nameOf(null, arabic: true), isNull);
    });

    test('the name follows the reader\'s language', () {
      expect(catalog.nameOf(7, arabic: false), 'Sohar');
      expect(catalog.nameOf(7, arabic: true), 'صحار');
    });

    test('search finds a Wilayat by either spelling', () {
      expect(codes('ازكي'), [34]);
      expect(codes('إزكي'), [34]);
      expect(codes('ادم'), [31]);
      expect(codes('أدم'), [31]);
    });

    test('search finds a Wilayat by its English name, in any case', () {
      expect(codes('sohar'), [7]);
      expect(codes('SOH'), [7]);
      expect(codes('nizwa'), [28]);
    });

    test('a village alias finds its Wilayat: Majees is Sohar', () {
      expect(codes('مجيس'), [7]);
      expect(codes('majees'), [7]);
    });

    test('typing a Governorate lists what is in it', () {
      expect(codes('الباطنه'), [7, 9]);
      expect(codes('الباطنة'), [7, 9]);
    });

    test('nothing matching leaves no group, not an empty one', () {
      expect(catalog.groups(query: 'zzz'), isEmpty);
    });
  });

  group('the repository', () {
    test('reads once and holds the answer in memory', () async {
      final adapter = CountingWilayatAdapter();
      final repository = WilayatRepository(adapter);

      expect(repository.cached, isNull);
      final first = await repository.load();
      final second = await repository.load();

      expect(adapter.reads, 1);
      expect(identical(first, second), isTrue);
      expect(repository.cached, same(first));
    });

    test('concurrent callers share one read', () async {
      final adapter = CountingWilayatAdapter();
      final repository = WilayatRepository(adapter);

      await Future.wait(
          [repository.load(), repository.load(), repository.load()]);

      expect(adapter.reads, 1);
    });

    test('a failed read is not cached, so a retry asks again', () async {
      final adapter = CountingWilayatAdapter(failFirst: true);
      final repository = WilayatRepository(adapter);

      await expectLater(repository.load(), throwsA(isA<StateError>()));
      expect(repository.cached, isNull);

      final catalog = await repository.load();

      expect(catalog.wilayats, isNotEmpty);
      expect(adapter.reads, 2);
    });
  });

  group('the mapper', () {
    test('reads a row of each table, aliases included', () {
      final wilayat = wilayatFromRow({
        'code': 7,
        'governorate_code': 2,
        'name_ar': 'صحار',
        'name_en': 'Sohar',
        'search_terms': ['مجيس', 'Majees'],
        'sort_order': 7,
        'is_active': true,
      });

      expect(wilayat.code, 7);
      expect(wilayat.governorateCode, 2);
      expect(wilayat.searchTerms, ['مجيس', 'Majees']);
      expect(wilayat.isActive, isTrue);

      final governorate = governorateFromRow({
        'code': 2,
        'name_ar': 'شمال الباطنة',
        'name_en': 'Al Batinah North',
        'sort_order': 2,
      });
      expect(governorate.code, 2);
      expect(governorate.name(arabic: false), 'Al Batinah North');
    });

    test('a row with no aliases reads as none', () {
      final wilayat = wilayatFromRow({
        'code': 1,
        'governorate_code': 1,
        'name_ar': 'مسقط',
        'name_en': 'Muscat',
        'sort_order': 1,
      });

      expect(wilayat.searchTerms, isEmpty);
    });
  });

  group('a guest\'s stored choice', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is kept on the device and read back', () async {
      final store = GuestLocationStore();
      expect(await store.load(), isNull);

      await store.save(7);

      expect(await GuestLocationStore().load(), 7);
    });

    test('can be cleared', () async {
      final store = GuestLocationStore();
      await store.save(7);
      await store.save(null);

      expect(await store.load(), isNull);
    });

    test('storage that fails reads as no choice and never throws', () async {
      final store = GuestLocationStore(
        preferences: () async => throw StateError('blocked'),
      );

      expect(await store.load(), isNull);
      await store.save(7);
    });

    test('an inactive or unknown stored code is treated as no location', () {
      final catalog = wilayatFixtureCatalog();

      expect(catalog.activeByCode(55)?.code, isNull, reason: 'inactive');
      expect(catalog.activeByCode(999)?.code, isNull, reason: 'unknown');
      expect(catalog.activeByCode(7)?.code, 7);
    });
  });
}

/// A port that counts its reads, and can fail the first.
class CountingWilayatAdapter implements WilayatAdapter {
  CountingWilayatAdapter({this.failFirst = false});

  final bool failFirst;
  int reads = 0;

  @override
  Future<WilayatCatalog> fetchCatalog() async {
    reads++;
    if (failFirst && reads == 1) throw StateError('offline');
    return wilayatFixtureCatalog();
  }
}
