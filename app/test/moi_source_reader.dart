import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One row of the Ministry of Interior workbook, as published.
///
/// Read straight from the `.xlsx` kept beside the frozen specification, so a test
/// can hold the specification and the seed to the Ministry's own file rather than
/// to a transcription of it. The spelling is the Ministry's, tatweel and all.
class MoiRow {
  const MoiRow({
    required this.regionCode,
    required this.regionName,
    required this.wilayatCode,
    required this.wilayatName,
  });

  final int regionCode;
  final String regionName;
  final int wilayatCode;
  final String wilayatName;

  @override
  String toString() =>
      'MoiRow($regionCode, $regionName, $wilayatCode, $wilayatName)';
}

/// Reads the four columns of the Ministry's workbook: `Region Code`,
/// `Region Name`, `Wilayat Code`, `Wilayat Name`.
///
/// **A reader for this one file, not for spreadsheets.** An `.xlsx` is a zip of
/// XML parts, and the project has no archive dependency to open one with, so this
/// walks the zip's central directory, inflates the two parts it needs and reads
/// their cells. It refuses -- with an exception, never an empty answer -- anything
/// it does not recognise, so a replaced or damaged fixture fails the test that
/// reads it instead of quietly verifying nothing.
List<MoiRow> readMoiWorkbook(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('The Ministry source file is missing: $path');
  }
  final zip = _ZipParts(file.readAsBytesSync());
  final strings = _sharedStrings(zip.text('xl/sharedStrings.xml'));
  final cells = _sheetCells(zip.text('xl/worksheets/sheet1.xml'), strings);

  final header = cells[2];
  if (header == null ||
      header['B'] != 'Region Code' ||
      header['C'] != 'Region Name' ||
      header['D'] != 'Wilayat Code' ||
      header['E'] != 'Wilayat Name') {
    throw StateError('Unexpected header row in $path: $header');
  }

  final rows = <MoiRow>[];
  for (final row in cells.keys.toList()..sort()) {
    if (row == 2) continue;
    final cell = cells[row]!;
    rows.add(MoiRow(
      regionCode: int.parse(cell['B']!),
      regionName: cell['C']!,
      wilayatCode: int.parse(cell['D']!),
      wilayatName: cell['E']!,
    ));
  }
  return rows;
}

List<String> _sharedStrings(String xml) => [
      for (final item
          in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(xml))
        _unescape([
          for (final t in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
              .allMatches(item.group(1)!))
            t.group(1)!,
        ].join()),
    ];

/// Cell text by row number then column letter. A `t="s"` cell is an index into
/// the shared strings; any other cell is its number, as written.
Map<int, Map<String, String>> _sheetCells(String xml, List<String> strings) {
  final rows = <int, Map<String, String>>{};
  for (final cell in RegExp(
    r'<c r="([A-Z]+)(\d+)"([^>]*)><v>([^<]*)</v></c>',
  ).allMatches(xml)) {
    final value = cell.group(4)!;
    final isString = cell.group(3)!.contains('t="s"');
    (rows[int.parse(cell.group(2)!)] ??= {})[cell.group(1)!] =
        isString ? strings[int.parse(value)] : value;
  }
  return rows;
}

String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// The named parts of a zip archive, inflated on request.
class _ZipParts {
  _ZipParts(this._bytes) : _view = ByteData.sublistView(_bytes) {
    // The end-of-central-directory record: the last 0x06054b50 in the file.
    var eocd = _bytes.length - 22;
    while (eocd >= 0 && _view.getUint32(eocd, Endian.little) != 0x06054b50) {
      eocd--;
    }
    if (eocd < 0) throw StateError('Not a zip archive');
    final count = _view.getUint16(eocd + 10, Endian.little);
    var at = _view.getUint32(eocd + 16, Endian.little);
    for (var i = 0; i < count; i++) {
      if (_view.getUint32(at, Endian.little) != 0x02014b50) {
        throw StateError('Damaged zip central directory');
      }
      final nameLength = _view.getUint16(at + 28, Endian.little);
      final extraLength = _view.getUint16(at + 30, Endian.little);
      final commentLength = _view.getUint16(at + 32, Endian.little);
      final name = utf8.decode(_bytes.sublist(at + 46, at + 46 + nameLength));
      _entries[name] = (
        method: _view.getUint16(at + 10, Endian.little),
        compressedSize: _view.getUint32(at + 20, Endian.little),
        localOffset: _view.getUint32(at + 42, Endian.little),
      );
      at += 46 + nameLength + extraLength + commentLength;
    }
  }

  final Uint8List _bytes;
  final ByteData _view;
  final _entries =
      <String, ({int method, int compressedSize, int localOffset})>{};

  String text(String name) {
    final entry = _entries[name];
    if (entry == null) throw StateError('The workbook has no part $name');
    final local = entry.localOffset;
    if (_view.getUint32(local, Endian.little) != 0x04034b50) {
      throw StateError('Damaged zip entry $name');
    }
    final start = local +
        30 +
        _view.getUint16(local + 26, Endian.little) +
        _view.getUint16(local + 28, Endian.little);
    final data = _bytes.sublist(start, start + entry.compressedSize);
    final raw = switch (entry.method) {
      0 => data,
      8 => ZLibCodec(raw: true).decode(data),
      final other => throw StateError('Unsupported zip method $other'),
    };
    return utf8.decode(raw);
  }
}
