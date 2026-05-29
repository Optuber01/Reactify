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
    'default boy fixture parses as 445 fields with expected boundaries',
    () async {
      final schema = await loadSchema();
      final parser = GachaCodeParser(schema);
      final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
      final state = parser.parse(code);

      expect(state.rawFields.length, 445);
      expect(state.metadataFields.length, GachaFieldSchema.metadataFieldCount);
      expect(
        state.numericFields.length,
        GachaFieldSchema.colorStartIndex - GachaFieldSchema.numericStartIndex,
      );
      expect(
        state.colorFields.length,
        GachaFieldSchema.totalFieldCount - GachaFieldSchema.colorStartIndex,
      );
      expect(state.metadata('namex'), 'Default Boy');
      expect(state.numeric('headshape'), 1);
      expect(state.numeric('eyes1x'), 1);
      expect(state.color('skincolor1x').toARGB32(), 0xFFFFE2D4);
    },
  );

  test('parser rejects wrong field count', () async {
    final schema = await loadSchema();
    final parser = GachaCodeParser(schema);
    expect(() => parser.parse('Default Boy|1|2'), throwsFormatException);
  });

  test(
    'focused validation fixtures only change their intended chooser fields',
    () async {
      final schema = await loadSchema();
      final parser = GachaCodeParser(schema);
      final defaultBoy = parser.parse(
        await rootBundle.loadString('fixtures/default_boy.gc.txt'),
      );
      final frontHairHeavy = parser.parse(
        await rootBundle.loadString('fixtures/front_hair_heavy.gc.txt'),
      );
      final eyeHeavy = parser.parse(
        await rootBundle.loadString('fixtures/eye_heavy.gc.txt'),
      );

      final frontHairDiffs = <int>[
        for (var i = 0; i < defaultBoy.rawFields.length; i += 1)
          if (defaultBoy.rawFields[i] != frontHairHeavy.rawFields[i]) i,
      ];
      final eyeDiffs = <int>[
        for (var i = 0; i < defaultBoy.rawFields.length; i += 1)
          if (defaultBoy.rawFields[i] != eyeHeavy.rawFields[i]) i,
      ];

      expect(frontHairDiffs, [22, 204]);
      expect(eyeDiffs, [27, 28, 31, 32]);
    },
  );
}
