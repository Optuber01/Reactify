import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/transform_graph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('affine matrix multiplication composes translation and scale', () {
    final parent = AffineMatrix.translation(10, 20);
    final child = AffineMatrix.scale(2, 3);
    final combined = parent.multiply(child);

    expect(combined.a, 2);
    expect(combined.d, 3);
    expect(combined.tx, 10);
    expect(combined.ty, 20);
  });

  test('runtime value maps expose exact headsize scale path', () async {
    final tables = await ResolverTables.load();
    final value = tables.runtimeValueMaps.resolve(
      field: 'headsize',
      fieldValue: 2,
      op: 'scaleX',
      targetContains: 'head.head',
      fallback: -1,
    );
    expect(value, 1.03);
  });

  test('front hair case resolves a transformed front hair part', () async {
    final tables = await ResolverTables.load();
    final parser = GachaCodeParser(tables.schema);
    final code = await rootBundle.loadString(
      'fixtures/front_hair_heavy.gc.txt',
    );
    final state = parser.parse(code);
    final renderer = CharacterRenderer(
      tables: tables,
      assetStore: GachaAssetStore(),
    );
    final parts = renderer.resolveParts(state);
    final frontHairPart = parts.firstWhere(
      (part) => part.catalogPart.family == 'front_hair',
    );

    expect(frontHairPart.worldTransform.tx, isNonZero);
    expect(frontHairPart.worldTransform.ty, isNonZero);
  });
}
