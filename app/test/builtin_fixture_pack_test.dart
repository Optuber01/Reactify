import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/csv_loaders.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ResolverTables tables;
  late GachaCodeParser parser;
  late List<Map<String, dynamic>> manifest;
  late List<Map<String, dynamic>> curatedRows;

  setUpAll(() async {
    tables = await ResolverTables.loadForEditor();
    parser = GachaCodeParser(tables.schema);
    manifest = [
      for (final entry in await CsvLoaders.loadJsonListAsset(
        'assets/data/generated/builtin_character_manifest.json',
      ))
        entry as Map<String, dynamic>,
    ];
    curatedRows = [
      for (final row in manifest)
        if (row['curated'] == true &&
            ((row['fixture_asset_path'] as String?) ?? '').isNotEmpty)
          row,
    ];
  });

  test(
    'builtin extraction script regenerates the manifest and curated fixtures',
    () async {
      final result = await Process.run('python', [
        '../tools/extract_builtin_character_fixtures.py',
      ], workingDirectory: Directory.current.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      final stdoutText = '${result.stdout}';
      expect(stdoutText, contains('importcode_assignments='));
      expect(stdoutText, contains('valid_445_codes='));
      expect(stdoutText, contains('curated_fixtures='));

      final assignments = _captureInt(stdoutText, 'importcode_assignments');
      final valid = _captureInt(stdoutText, 'valid_445_codes');
      final curated = _captureInt(stdoutText, 'curated_fixtures');

      expect(assignments, greaterThanOrEqualTo(4200));
      expect(valid, greaterThanOrEqualTo(4000));
      expect(curated, inInclusiveRange(50, 100));
    },
    timeout: const Timeout.factor(4),
  );

  test(
    'curated builtin manifest rows have stable fixture assets and 445 fields',
    () async {
      expect(manifest.length, greaterThanOrEqualTo(4000));
      expect(curatedRows.length, inInclusiveRange(50, 100));

      for (final row in curatedRows) {
        final assetPath = row['fixture_asset_path'] as String;
        final code = await rootBundle.loadString(assetPath);
        final state = parser.parse(code);
        expect(state.rawFields, hasLength(445), reason: assetPath);
        expect(state.metadata('namex'), isNotEmpty);
        expect(
          (row['display_name'] as String).startsWith(state.metadata('namex')),
          isTrue,
          reason: assetPath,
        );
        expect(row['field_count'], 445);
      }
    },
  );

  test('builtin fixture assets exist on disk and manifest ids stay unique', () {
    final ids = <String>{};
    for (final row in curatedRows) {
      final id = row['id'] as String;
      expect(ids.add(id), isTrue, reason: 'duplicate manifest id: $id');
      final assetPath = row['fixture_asset_path'] as String;
      final diskPath = File('${Directory.current.path}/$assetPath');
      expect(diskPath.existsSync(), isTrue, reason: diskPath.path);
    }
  });

  test('editor tables expose grouped probe and built-in fixtures', () {
    expect(tables.validationCases, isNotEmpty);
    expect(tables.builtinFixtures, isNotEmpty);
    expect(
      tables.editorFixtures.length,
      greaterThan(tables.validationCases.length),
    );
    expect(
      tables.editorFixtures.any((fixture) => fixture.group == 'Probe Fixtures'),
      isTrue,
    );
    expect(
      tables.editorFixtures.any(
        (fixture) => fixture.group == 'Built-in Fixtures',
      ),
      isTrue,
    );
    expect(
      tables.builtinFixtures.any(
        (fixture) => fixture.displayName == 'Default Boy',
      ),
      isTrue,
    );
  });
}

int _captureInt(String text, String key) {
  final match = RegExp('$key=(\\d+)').firstMatch(text);
  if (match == null) {
    throw StateError('Missing $key in script output');
  }
  return int.parse(match.group(1)!);
}
