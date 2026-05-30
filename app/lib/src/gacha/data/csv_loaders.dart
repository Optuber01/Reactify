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

  static Future<Map<String, dynamic>> loadJsonAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> loadJsonListAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return jsonDecode(raw) as List<dynamic>;
  }

  static List<Map<String, String>> parseCsv(String raw) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(raw);
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
