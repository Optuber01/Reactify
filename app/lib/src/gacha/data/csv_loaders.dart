import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart';

class CsvLoaders {
  const CsvLoaders._();

  static Future<List<Map<String, String>>> loadAssetCsv(
    String assetPath,
  ) async {
    final raw = await rootBundle.loadString(assetPath);
    return parseCsv(raw);
  }

  static Future<List<T>> loadAssetCsvMapped<T>(
    String assetPath,
    T Function(Map<String, String> row) convert,
  ) async {
    final raw = await rootBundle.loadString(assetPath);
    return parseCsvMapped(raw, convert);
  }

  static List<T> parseCsvMapped<T>(
    String raw,
    T Function(Map<String, String> row) convert,
  ) {
    if (raw.isEmpty) return <T>[];
    final output = <T>[];
    List<String>? headers;
    final fields = <String>[];
    final field = StringBuffer();
    var quoted = false;

    void finishField() {
      fields.add(field.toString().trim());
      field.clear();
    }

    void finishRow() {
      finishField();
      if (headers == null) {
        headers = [
          for (final value in fields) value.replaceFirst('\ufeff', '').trim(),
        ];
      } else if (fields.any((value) => value.isNotEmpty)) {
        final row = <String, String>{};
        for (var index = 0; index < headers!.length; index++) {
          row[headers![index]] = index < fields.length ? fields[index] : '';
        }
        output.add(convert(row));
      }
      fields.clear();
    }

    for (var index = 0; index < raw.length; index++) {
      final code = raw.codeUnitAt(index);
      if (code == 34) {
        if (quoted &&
            index + 1 < raw.length &&
            raw.codeUnitAt(index + 1) == 34) {
          field.writeCharCode(34);
          index += 1;
        } else {
          quoted = !quoted;
        }
      } else if (code == 44 && !quoted) {
        finishField();
      } else if ((code == 10 || code == 13) && !quoted) {
        if (code == 13 &&
            index + 1 < raw.length &&
            raw.codeUnitAt(index + 1) == 10) {
          index += 1;
        }
        finishRow();
      } else {
        field.writeCharCode(code);
      }
    }
    if (field.isNotEmpty || fields.isNotEmpty) finishRow();
    return output;
  }

  static Future<Map<String, dynamic>> loadJsonAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> loadJsonListAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return jsonDecode(raw) as List<dynamic>;
  }

  static const _crlfConverter = CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\r\n',
  );
  static const _lfConverter = CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  );

  static List<Map<String, String>> parseCsv(String raw) {
    final converter = raw.contains('\r\n') ? _crlfConverter : _lfConverter;
    final rows = converter.convert(raw);
    if (rows.isEmpty) {
      return const [];
    }
    final headers = rows.first
        .map((value) => value.toString().replaceFirst('\ufeff', '').trim())
        .toList(growable: false);
    return [
      for (final row in rows.skip(1))
        {
          for (var i = 0; i < headers.length; i++)
            headers[i]: i < row.length ? row[i].toString().trim() : '',
        },
    ];
  }
}
