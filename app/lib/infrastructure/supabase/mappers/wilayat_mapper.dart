import '../../../features/locations/wilayat_models.dart';

// Conversion between the two reference tables and the Wilayat Domain Models.
//
// Every column the locations feature reads appears here and nowhere else (OP-3).
// The codes are `smallint`, which PostgREST sends as plain JSON numbers.

Governorate governorateFromRow(Map<String, dynamic> row) => Governorate(
      code: row['code'] as int,
      nameAr: row['name_ar'] as String,
      nameEn: row['name_en'] as String,
      sortOrder: row['sort_order'] as int,
    );

Wilayat wilayatFromRow(Map<String, dynamic> row) => Wilayat(
      code: row['code'] as int,
      governorateCode: row['governorate_code'] as int,
      nameAr: row['name_ar'] as String,
      nameEn: row['name_en'] as String,
      sortOrder: row['sort_order'] as int,
      searchTerms: [
        for (final term in (row['search_terms'] as List<dynamic>? ?? const []))
          term as String,
      ],
      isActive: row['is_active'] as bool? ?? true,
    );
