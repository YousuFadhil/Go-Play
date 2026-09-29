import 'package:go_play/features/locations/wilayat_adapter.dart';
import 'package:go_play/features/locations/wilayat_models.dart';

/// A small slice of the real reference data, for tests.
///
/// Real codes and real names -- Sohar is 7, North Al Batinah is 2 -- so a test
/// reads as the product does. `Sadh` (55) is retired here on purpose, to have
/// something an old community may still name and nobody may choose.
WilayatCatalog wilayatFixtureCatalog() => WilayatCatalog(
      governorates: const [
        Governorate(code: 1, nameAr: 'مسقط', nameEn: 'Muscat', sortOrder: 1),
        Governorate(
            code: 2,
            nameAr: 'شمال الباطنة',
            nameEn: 'Al Batinah North',
            sortOrder: 2),
        Governorate(
            code: 6, nameAr: 'الداخلية', nameEn: 'Ad Dakhiliyah', sortOrder: 6),
        Governorate(code: 9, nameAr: 'ظفار', nameEn: 'Dhofar', sortOrder: 9),
      ],
      wilayats: const [
        Wilayat(
            code: 1,
            governorateCode: 1,
            nameAr: 'مسقط',
            nameEn: 'Muscat',
            sortOrder: 1),
        Wilayat(
            code: 7,
            governorateCode: 2,
            nameAr: 'صحار',
            nameEn: 'Sohar',
            searchTerms: ['مجيس', 'Majees'],
            sortOrder: 7),
        Wilayat(
            code: 9,
            governorateCode: 2,
            nameAr: 'شناص',
            nameEn: 'Shinas',
            sortOrder: 8),
        Wilayat(
            code: 28,
            governorateCode: 6,
            nameAr: 'نزوى',
            nameEn: 'Nizwa',
            sortOrder: 28),
        Wilayat(
            code: 31,
            governorateCode: 6,
            nameAr: 'أدم',
            nameEn: 'Adam',
            sortOrder: 29),
        Wilayat(
            code: 34,
            governorateCode: 6,
            nameAr: 'إزكي',
            nameEn: 'Izki',
            sortOrder: 30),
        Wilayat(
            code: 51,
            governorateCode: 9,
            nameAr: 'صلالة',
            nameEn: 'Salalah',
            sortOrder: 51),
        Wilayat(
            code: 55,
            governorateCode: 9,
            nameAr: 'سدح',
            nameEn: 'Sadh',
            sortOrder: 55,
            isActive: false),
      ],
    );

/// A port that answers immediately with [wilayatFixtureCatalog], or fails.
class FakeWilayatAdapter implements WilayatAdapter {
  FakeWilayatAdapter({this.failure});

  final Object? failure;

  @override
  Future<WilayatCatalog> fetchCatalog() async {
    if (failure != null) throw failure!;
    return wilayatFixtureCatalog();
  }
}
