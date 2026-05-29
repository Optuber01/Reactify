import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_field_schema.dart';
import 'package:reactify_gacha/src/gacha/data/csv_loaders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GachaFieldSchema> loadSchema() async {
    final rows = await CsvLoaders.loadAssetCsv(
      'assets/data/schema/gacha_code_schema.csv',
    );
    return GachaFieldSchema.fromRows(rows);
  }

  test(
    'import edit export preserves field count and only changes intended fields',
    () async {
      final schema = await loadSchema();
      final parser = GachaCodeParser(schema);
      final source = await rootBundle.loadString('fixtures/default_boy.gc.txt');
      final original = parser.parse(source);

      final edited = original
          .updateNumericField(schema, 'fronthair', 7)
          .updateNumericField(schema, 'displayhair', 0)
          .updateColorField(
            schema,
            'fronthaircolor1x',
            const Color(0xFF123456),
          );

      final exported = edited.serializeCode();
      final reparsed = parser.parse(exported);
      final diffIndices = <int>[
        for (var index = 0; index < original.rawFields.length; index += 1)
          if (original.rawFields[index] != reparsed.rawFields[index]) index,
      ];

      expect(exported.split('|'), hasLength(GachaFieldSchema.totalFieldCount));
      expect(reparsed.rawFields.length, GachaFieldSchema.totalFieldCount);
      expect(diffIndices, [22, 225, 284]);
      expect(reparsed.numeric('fronthair'), 7);
      expect(reparsed.numeric('displayhair'), 0);
      expect(reparsed.color('fronthaircolor1x').toARGB32(), 0xFF123456);
    },
  );

  test(
    'raw field updates validate schema kinds and preserve export order',
    () async {
      final schema = await loadSchema();
      final parser = GachaCodeParser(schema);
      final source = await rootBundle.loadString('fixtures/default_boy.gc.txt');
      final original = parser.parse(source);

      final edited = original
          .updateMetadataField(schema, 'namex', 'Debug Boy')
          .updateRawField(schema, 'mouth', '14')
          .updateRawField(schema, 'shirtcolor1x', 'ABC123');
      final reparsed = parser.parse(edited.serializeCode());

      expect(reparsed.metadata('namex'), 'Debug Boy');
      expect(reparsed.numeric('mouth'), 14);
      expect(reparsed.color('shirtcolor1x').toARGB32(), 0xFFABC123);
      expect(
        () => original.updateRawField(schema, 'mouth', 'oops'),
        throwsFormatException,
      );
      expect(
        () => original.updateRawField(schema, 'shirtcolor1x', 'ZZZZZZ'),
        throwsFormatException,
      );
    },
  );
}
