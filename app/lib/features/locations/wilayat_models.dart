// Domain Models for the one location unit Go Play uses: the Wilayat (OP-3).
//
// A Wilayat is the only place a community, a match or a player is ever "near".
// There is no locality, no coordinate and no distance: a village is a search
// alias of the Wilayat it belongs to (`search_terms`), never a place of its own.
//
// The codes are the Ministry of Interior's own numeric codes (Sohar is 7) and
// are Go Play's keys from migration `0094` on. They identify; they are never
// shown, so nothing here formats one.

/// One of the eleven Governorates. Only ever a heading the picker groups under.
class Governorate {
  const Governorate({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.sortOrder,
  });

  final int code;
  final String nameAr;
  final String nameEn;
  final int sortOrder;

  String name({required bool arabic}) => arabic ? nameAr : nameEn;
}

/// One of the 63 Wilayats.
class Wilayat {
  const Wilayat({
    required this.code,
    required this.governorateCode,
    required this.nameAr,
    required this.nameEn,
    required this.sortOrder,
    this.searchTerms = const [],
    this.isActive = true,
  });

  final int code;
  final int governorateCode;
  final String nameAr;
  final String nameEn;

  /// Search aliases only -- a village, a variant spelling (`مجيس` for Sohar).
  final List<String> searchTerms;
  final int sortOrder;

  /// A retired Wilayat is still a valid label for a community that already
  /// carries it, and is no longer offered for anyone to choose.
  final bool isActive;

  String name({required bool arabic}) => arabic ? nameAr : nameEn;
}

/// A Governorate and the Wilayats in it, as the picker lists them.
class WilayatGroup {
  const WilayatGroup({required this.governorate, required this.wilayats});

  final Governorate governorate;
  final List<Wilayat> wilayats;
}

/// The whole reference data set, read once and held in memory.
///
/// 74 small rows that change on the timescale of a royal decree: fetching them
/// per screen would be a round trip for a value that cannot have moved.
class WilayatCatalog {
  WilayatCatalog({
    required Iterable<Governorate> governorates,
    required Iterable<Wilayat> wilayats,
  })  : governorates = List.unmodifiable(
          [...governorates]..sort(_bySort((g) => g.sortOrder, (g) => g.code)),
        ),
        wilayats = List.unmodifiable(
          [...wilayats]..sort(_bySort((w) => w.sortOrder, (w) => w.code)),
        ),
        _byCode = {for (final w in wilayats) w.code: w};

  final List<Governorate> governorates;
  final List<Wilayat> wilayats;
  final Map<int, Wilayat> _byCode;

  static int Function(T, T) _bySort<T>(
    int Function(T) order,
    int Function(T) code,
  ) =>
      (a, b) {
        final byOrder = order(a).compareTo(order(b));
        return byOrder != 0 ? byOrder : code(a).compareTo(code(b));
      };

  /// The Wilayat with [code], retired or not, or null for null or an unknown
  /// code. What a card's label is read from.
  Wilayat? byCode(int? code) => code == null ? null : _byCode[code];

  /// The same, but only a Wilayat that may still be chosen. What a stored
  /// preference is checked against: an inactive or unknown code is treated as
  /// no location at all.
  Wilayat? activeByCode(int? code) {
    final wilayat = byCode(code);
    return wilayat != null && wilayat.isActive ? wilayat : null;
  }

  /// The label for [code], or null when there is nothing to show.
  String? nameOf(int? code, {required bool arabic}) =>
      byCode(code)?.name(arabic: arabic);

  /// The Wilayats a reader may choose, grouped by Governorate in display order.
  ///
  /// [query] is matched after [normalizeWilayatSearch] against both names, every
  /// alias and the Governorate's own names, so typing a Governorate lists what is
  /// in it. A Governorate with nothing left is omitted rather than shown empty.
  List<WilayatGroup> groups({String query = ''}) {
    final needle = normalizeWilayatSearch(query);
    final result = <WilayatGroup>[];
    for (final governorate in governorates) {
      final governorateHit = needle.isNotEmpty &&
          _matches(needle, [governorate.nameAr, governorate.nameEn]);
      final members = [
        for (final wilayat in wilayats)
          if (wilayat.isActive &&
              wilayat.governorateCode == governorate.code &&
              (needle.isEmpty ||
                  governorateHit ||
                  _matches(needle, [
                    wilayat.nameAr,
                    wilayat.nameEn,
                    ...wilayat.searchTerms,
                  ])))
            wilayat,
      ];
      if (members.isNotEmpty) {
        result.add(WilayatGroup(governorate: governorate, wilayats: members));
      }
    }
    return result;
  }

  static bool _matches(String needle, Iterable<String> haystack) =>
      haystack.any((text) => normalizeWilayatSearch(text).contains(needle));
}

/// Folds the spelling differences an Arabic search must not care about.
///
/// The seed keeps MOI's hamza (`إزكي`, `أدم`, `إبراء`) and NCSI writes none, so a
/// reader typing either has to find the same Wilayat. Hamza forms of alef fold to
/// a bare alef, taa marbuta folds to haa (`الباطنة` and `الباطنه`), and tatweel is
/// dropped. Latin is lower-cased; runs of whitespace collapse to one space.
String normalizeWilayatSearch(String input) {
  final out = StringBuffer();
  for (final rune in input.trim().toLowerCase().runes) {
    switch (rune) {
      case 0x0640: // tatweel
        break;
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0622: // آ
      case 0x0671: // ٱ
        out.writeCharCode(0x0627); // ا
      case 0x0629: // ة
        out.writeCharCode(0x0647); // ه
      default:
        out.writeCharCode(rune);
    }
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ');
}
