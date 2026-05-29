import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/data/csv_loaders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generated render catalog loads and contains expected head/body families',
    () async {
      final rows = await CsvLoaders.loadAssetCsv(
        'assets/data/generated/render_parts.csv',
      );
      expect(rows, isNotEmpty);
      expect(rows.first['family'], isNotEmpty);
      expect(rows.any((row) => row['family'] == 'head_shape'), isTrue);
      expect(rows.any((row) => row['family'] == 'left_eye'), isTrue);
      expect(rows.any((row) => row['family'] == 'rear_hair'), isTrue);
      expect(rows.any((row) => row['family'] == 'body_base'), isTrue);
      expect(rows.any((row) => row['family'] == 'hand_front_base'), isTrue);
      expect(rows.any((row) => row['family'] == 'weapon_front'), isTrue);
      expect(rows.any((row) => row['family'] == 'cape'), isTrue);
    },
  );

  test(
    'validation case manifest lists the validated bundled fixtures',
    () async {
      final items = await CsvLoaders.loadJsonListAsset(
        'assets/data/generated/validation_cases.json',
      );
      expect(items, [
        {'id': 'default_boy', 'fixture_asset': 'fixtures/default_boy.gc.txt'},
        {
          'id': 'front_hair_heavy',
          'fixture_asset': 'fixtures/front_hair_heavy.gc.txt',
        },
        {'id': 'eye_heavy', 'fixture_asset': 'fixtures/eye_heavy.gc.txt'},
        {
          'id': 'body_base_probe',
          'fixture_asset': 'fixtures/body_base_probe.gc.txt',
        },
        {
          'id': 'upper_clothing_probe',
          'fixture_asset': 'fixtures/upper_clothing_probe.gc.txt',
        },
        {
          'id': 'arm_layers_probe',
          'fixture_asset': 'fixtures/arm_layers_probe.gc.txt',
        },
        {
          'id': 'lower_clothing_probe',
          'fixture_asset': 'fixtures/lower_clothing_probe.gc.txt',
        },
        {
          'id': 'outerwear_probe',
          'fixture_asset': 'fixtures/outerwear_probe.gc.txt',
        },
        {'id': 'props_probe', 'fixture_asset': 'fixtures/props_probe.gc.txt'},
      ]);
    },
  );

  test(
    'editor slot ranges asset includes the editable baseline controls',
    () async {
      final rows = await CsvLoaders.loadAssetCsv(
        'assets/data/schema/gacha_editor_slot_ranges.csv',
      );
      expect(rows, isNotEmpty);
      expect(rows.any((row) => row['field'] == 'fronthair'), isTrue);
      expect(rows.any((row) => row['field'] == 'mouth'), isTrue);
      expect(rows.any((row) => row['field'] == 'shirt'), isTrue);
      expect(rows.any((row) => row['field'] == 'shoes2x'), isTrue);
    },
  );
}
