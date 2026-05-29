import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/ui/editor_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ResolverTables tables;
  late GachaCodeParser parser;
  late CharacterRenderer renderer;

  setUpAll(() async {
    tables = await ResolverTables.load();
    parser = GachaCodeParser(tables.schema);
    renderer = CharacterRenderer(tables: tables, assetStore: GachaAssetStore());
  });

  Future<String> fixture(String path) => rootBundle.loadString(path);

  test('import -> export roundtrip preserves all 445 fields', () async {
    final source = await fixture('fixtures/default_boy.gc.txt');
    final state = parser.parse(source);
    final exported = state.serializeCode();
    final reparsed = parser.parse(exported);

    expect(exported.split('|'), hasLength(445));
    expect(reparsed.rawFields, hasLength(445));
    expect(reparsed.rawFields, orderedEquals(state.rawFields));
  });

  test('major editor groups mutate only intended fields', () async {
    final source = await fixture('fixtures/default_boy.gc.txt');
    final state = parser.parse(source);
    final schema = tables.schema;

    final bodyEdited = state.updateNumericField(schema, 'pose', 10);
    expect(
      bodyEdited.diff(state, schema).map((change) => change.field).toList(),
      ['pose'],
    );

    final headEdited = state.updateNumericField(schema, 'mouth', 14);
    expect(
      headEdited.diff(state, schema).map((change) => change.field).toList(),
      ['mouth'],
    );

    final hairEdited = state.updateNumericField(schema, 'fronthair', 7);
    expect(
      hairEdited.diff(state, schema).map((change) => change.field).toList(),
      ['fronthair'],
    );

    final clothingEdited = state.updateNumericField(schema, 'shirt', 10);
    expect(
      clothingEdited.diff(state, schema).map((change) => change.field).toList(),
      ['shirt'],
    );

    final accessoryEdited = state.updateNumericField(schema, 'hat', 1);
    expect(
      accessoryEdited
          .diff(state, schema)
          .map((change) => change.field)
          .toList(),
      ['hat'],
    );

    final propEdited = state.updateNumericField(schema, 'weapon1x', 4);
    expect(
      propEdited.diff(state, schema).map((change) => change.field).toList(),
      ['weapon1x'],
    );
  });

  test(
    'invalid color text does not produce an editable canonical hex',
    () async {
      final source = await fixture('fixtures/default_boy.gc.txt');
      final state = parser.parse(source);
      final before = state.serializeCode();

      expect(canonicalRgbHexOrNull('ZZZZZZ'), isNull);
      expect(canonicalRgbHexOrNull('12345'), isNull);
      expect(canonicalRgbHexOrNull('1234567'), isNull);
      expect(state.serializeCode(), before);
    },
  );

  test('slot control clamp stays within declared editor range', () {
    final hairRange = tables.editorValueRangeFor('fronthair');
    final poseRange = tables.editorValueRangeFor('pose');

    expect(hairRange, isNotNull);
    expect(poseRange, isNotNull);
    expect(clampToEditorRange(hairRange, -100), hairRange!.minValue);
    expect(clampToEditorRange(hairRange, 9999), hairRange.maxValue);
    expect(clampToEditorRange(poseRange, 0), poseRange!.minValue);
    expect(clampToEditorRange(poseRange, 9999), poseRange.maxValue);
  });

  test('display toggles hide and show resolved families', () async {
    final source = await fixture('fixtures/default_boy.gc.txt');
    final state = parser.parse(source);
    final schema = tables.schema;

    final visibleScene = await renderer.buildScene(state);
    final hiddenHairScene = await renderer.buildScene(
      state.updateNumericField(schema, 'displayhair', 0),
    );
    final hiddenBodyScene = await renderer.buildScene(
      state.updateNumericField(schema, 'displaybody', 0),
    );

    final visibleFamilies = resolvedFamilyCounts(visibleScene).keys.toSet();
    final hiddenHairFamilies = resolvedFamilyCounts(
      hiddenHairScene,
    ).keys.toSet();
    final hiddenBodyFamilies = resolvedFamilyCounts(
      hiddenBodyScene,
    ).keys.toSet();

    expect(visibleFamilies.contains('rear_hair'), isTrue);
    expect(hiddenHairFamilies.contains('rear_hair'), isFalse);
    expect(visibleFamilies.contains('body_base'), isTrue);
    expect(hiddenBodyFamilies.contains('body_base'), isFalse);
  });

  test('transform control fields update exported fields', () async {
    final source = await fixture('fixtures/default_boy.gc.txt');
    final state = parser.parse(source);
    final schema = tables.schema;

    final edited = state
        .updateNumericField(schema, 'leyexpos', state.numeric('leyexpos') + 2)
        .updateNumericField(schema, 'mouthrot', state.numeric('mouthrot') + 3)
        .updateNumericField(
          schema,
          'fronthairxpos',
          state.numeric('fronthairxpos') + 1,
        )
        .updateNumericField(
          schema,
          'shieldxpos',
          state.numeric('shieldxpos') + 4,
        );
    final reparsed = parser.parse(edited.serializeCode());

    expect(reparsed.numeric('leyexpos'), state.numeric('leyexpos') + 2);
    expect(reparsed.numeric('mouthrot'), state.numeric('mouthrot') + 3);
    expect(
      reparsed.numeric('fronthairxpos'),
      state.numeric('fronthairxpos') + 1,
    );
    expect(reparsed.numeric('shieldxpos'), state.numeric('shieldxpos') + 4);
  });
}
