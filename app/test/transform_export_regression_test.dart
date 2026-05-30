import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/render_part.dart';
import 'package:reactify_gacha/src/gacha/render/transform_graph.dart';

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

  test(
    'representative SVG exports preserve registration origin and viewBox',
    () async {
      await _expectSvgHeader(
        assetPath: 'assets/gacha/clothes/3610.svg',
        width: '163.35',
        height: '100.85',
        translateX: '81.65',
        translateY: '50.45',
      );
      await _expectSvgHeader(
        assetPath: 'assets/gacha/hair/19902.svg',
        width: '142.15',
        height: '130.35',
        translateX: '71.05',
        translateY: '65.15',
      );
      await _expectSvgHeader(
        assetPath: 'assets/gacha/hair/4554.svg',
        width: '90.45',
        height: '147.85',
        translateX: '45.25',
        translateY: '73.9',
      );
      await _expectSvgHeader(
        assetPath: 'assets/gacha/props/8685.svg',
        width: '22.55',
        height: '143.6',
        translateX: '11.15',
        translateY: '123.8',
      );
    },
  );

  test(
    'fronthairrot selects a source-backed wrapper branch instead of a geometric rotation',
    () async {
      final base = await _stateForFixture(
        parser,
        'fixtures/builtin/gacha-dj-girl.gc.txt',
      );
      final frame1 = await renderer.buildScene(base);
      final frame11State = GachaCharacterState(
        rawFields: base.rawFields,
        metadataFields: base.metadataFields,
        numericFields: {...base.numericFields, 'fronthairrot': 11},
        colorFields: base.colorFields,
      );
      final frame11 = await renderer.buildScene(frame11State);

      final frame1Part = _part(frame1, family: 'front_hair', leafId: '19902');
      final frame11Part = _part(frame11, family: 'front_hair', leafId: '19902');

      expect(frame1Part.catalogPart.dependencyField, 'fronthairrot');
      expect(frame1Part.catalogPart.dependencyValue, 1);
      expect(frame11Part.catalogPart.dependencyField, 'fronthairrot');
      expect(frame11Part.catalogPart.dependencyValue, 11);
      expect(
        frame11Part.catalogPart.localMatrix.ty,
        isNot(equals(frame1Part.catalogPart.localMatrix.ty)),
      );
      _expectMatrixClose(
        frame11Part.localTransform,
        _expectedlocalTransform(
          tables: tables,
          state: frame11State,
          part: frame11Part,
        ),
        'front_hair 19902 frame 11',
      );
    },
  );

  test(
    'backhair and ponytail keep the source-backed headflip baseline delta chain',
    () async {
      final state = await _stateForFixture(
        parser,
        'fixtures/builtin/gacha-dj-girl.gc.txt',
      );
      final scene = await renderer.buildScene(state);
      final backHair = _part(scene, family: 'back_hair', leafId: '5424');
      final ponytail = _part(scene, family: 'ponytail', leafId: '4554');

      _expectMatrixClose(
        backHair.localTransform,
        _expectedlocalTransform(tables: tables, state: state, part: backHair),
        'back_hair 5424',
      );
      _expectMatrixClose(
        ponytail.localTransform,
        _expectedlocalTransform(tables: tables, state: state, part: ponytail),
        'ponytail 4554',
      );
    },
  );

  test(
    'prop slots use source-backed scale rotate translate composition for weapon and shield',
    () async {
      final base = await _stateForFixture(
        parser,
        'fixtures/builtin/gacha-dj-girl.gc.txt',
      );
      final state = GachaCharacterState(
        rawFields: base.rawFields,
        metadataFields: base.metadataFields,
        numericFields: {
          ...base.numericFields,
          'propxpos1x': 5,
          'propypos1x': -3,
          'propsize1x': 4,
          'proprot1x': 15,
          'shield': 1,
          'shieldxpos': 6,
          'shieldypos': -4,
          'shieldsize': 5,
          'shieldrot': 12,
        },
        colorFields: base.colorFields,
      );
      final scene = await renderer.buildScene(state);
      final weapon = _part(scene, family: 'weapon_front', leafId: '9220');
      final shield = scene.parts.firstWhere(
        (part) => part.catalogPart.family == 'shield',
      );

      _expectMatrixClose(
        weapon.localTransform,
        _expectedlocalTransform(tables: tables, state: state, part: weapon),
        'weapon_front 9220',
      );
      _expectMatrixClose(
        shield.localTransform,
        _expectedlocalTransform(tables: tables, state: state, part: shield),
        'shield ${shield.catalogPart.leafId}',
      );
    },
  );
}

Future<GachaCharacterState> _stateForFixture(
  GachaCodeParser parser,
  String fixtureAsset,
) async {
  return parser.parse(await rootBundle.loadString(fixtureAsset));
}

Future<void> _expectSvgHeader({
  required String assetPath,
  required String width,
  required String height,
  required String translateX,
  required String translateY,
}) async {
  final svg = await rootBundle.loadString(assetPath);
  expect(svg, contains('width="${width}px"'));
  expect(svg, contains('height="${height}px"'));
  expect(svg, contains('viewBox="0 0 $width $height"'));
  expect(
    svg,
    contains(
      'transform="matrix(1.0, 0.0, 0.0, 1.0, $translateX, $translateY)"',
    ),
  );
}

ResolvedRenderPart _part(
  ResolvedScene scene, {
  required String family,
  required String leafId,
}) {
  return scene.parts.firstWhere(
    (part) =>
        part.catalogPart.family == family && part.catalogPart.leafId == leafId,
  );
}

AffineMatrix _expectedlocalTransform({
  required ResolverTables tables,
  required GachaCharacterState state,
  required ResolvedRenderPart part,
}) {
  final catalog = part.catalogPart;
  final groupMatrix = _groupAdjustmentFor(tables, catalog, state);
  final hostMatrix = catalog.hostScope == 'head'
      ? (tables.headPlacements[catalog.hostName]?.matrix ??
            const AffineMatrix.identity())
      : const AffineMatrix.identity();
  final anchorMatrix = catalog.hostScope == 'pose'
      ? AffineMatrix.translation(catalog.runtimeAnchorX, catalog.runtimeAnchorY)
      : const AffineMatrix.identity();
  final slotMatrix = _slotAdjustmentFor(tables, catalog, state);
  return groupMatrix
      .multiply(hostMatrix)
      .multiply(anchorMatrix)
      .multiply(slotMatrix)
      .multiply(catalog.localMatrix);
}



AffineMatrix _groupAdjustmentFor(
  ResolverTables tables,
  RenderCatalogPart part,
  GachaCharacterState state,
) {
  if (part.hostScope == 'head') {
    final headFlip =
        tables
            .headFlipPlacementFor(
              headflip: state.numeric('headflip'),
              name: 'head',
            )
            ?.matrix ??
        const AffineMatrix.identity();
    return headFlip.multiply(
      AffineMatrix.scale(
        tables.runtimeValueMaps.resolve(
          field: 'headsize',
          fieldValue: state.numeric('headsize'),
          op: 'scaleX',
          targetContains: 'head.head',
          fallback: 1,
        ),
        tables.runtimeValueMaps.resolve(
          field: 'headsizey',
          fieldValue: state.numeric('headsizey'),
          op: 'scaleY',
          targetContains: 'head.head',
          fallback: 1,
        ),
      ),
    );
  }
  if (part.hostName == 'backhair') {
    final selected =
        tables
            .headFlipPlacementFor(
              headflip: state.numeric('headflip'),
              name: 'backhair',
            )
            ?.matrix ??
        const AffineMatrix.identity();
    final baseline =
        tables.headFlipPlacementFor(headflip: 1, name: 'backhair')?.matrix ??
        const AffineMatrix.identity();
    return selected
        .multiply(
          AffineMatrix.scale(
            tables.runtimeValueMaps.resolve(
              field: 'headsize',
              fieldValue: state.numeric('headsize'),
              op: 'scaleX',
              targetContains: 'backhair.backhair',
              fallback: 1,
            ),
            tables.runtimeValueMaps.resolve(
              field: 'headsizey',
              fieldValue: state.numeric('headsizey'),
              op: 'scaleY',
              targetContains: 'backhair.backhair',
              fallback: 1,
            ),
          ),
        )
        .multiply(baseline.inverse());
  }
  return const AffineMatrix.identity();
}

AffineMatrix _slotAdjustmentFor(
  ResolverTables tables,
  RenderCatalogPart part,
  GachaCharacterState state,
) {
  final binding = _bindingFor(part.family);
  if (binding == null) {
    return const AffineMatrix.identity();
  }
  final x = _slotValue(
    tables: tables,
    state: state,
    field: binding.xField,
    op: 'x',
    targetContains: binding.targetContains,
    fallback: 0,
    directFieldFallback: true,
  );
  final y = _slotValue(
    tables: tables,
    state: state,
    field: binding.yField,
    op: 'y',
    targetContains: binding.targetContains,
    fallback: 0,
    directFieldFallback: true,
  );
  final scaleX = _slotValue(
    tables: tables,
    state: state,
    field: binding.scaleXField,
    op: 'scaleX',
    targetContains: binding.targetContains,
    fallback: 1,
    directFieldFallback: false,
  );
  final scaleY = _slotValue(
    tables: tables,
    state: state,
    field: binding.scaleYField,
    op: 'scaleY',
    targetContains: binding.targetContains,
    fallback: 1,
    directFieldFallback: false,
  );
  final double rotation = binding.appliesGeometricRotation
      ? _slotValue(
          tables: tables,
          state: state,
          field: binding.rotationField,
          op: 'rotation',
          targetContains: binding.targetContains,
          fallback: 0,
          directFieldFallback: binding.rotationUsesDirectFieldFallback,
        )
      : 0;
  return AffineMatrix.translation(x, y)
      .multiply(AffineMatrix.rotationDegrees(rotation))
      .multiply(AffineMatrix.scale(scaleX, scaleY));
}

double _slotValue({
  required ResolverTables tables,
  required GachaCharacterState state,
  required String field,
  required String op,
  required String targetContains,
  required double fallback,
  required bool directFieldFallback,
}) {
  final fieldValue = state.numeric(field);
  final resolved = tables.runtimeValueMaps.resolveOrNull(
    field: field,
    fieldValue: fieldValue,
    op: op,
    targetContains: targetContains,
  );
  if (resolved != null) {
    return resolved;
  }
  if (directFieldFallback) {
    return fieldValue.toDouble();
  }
  return fallback;
}

_TestSlotBinding? _bindingFor(String family) {
  switch (family) {
    case 'front_hair':
      return const _TestSlotBinding(
        targetContains: 'head.head.fronthair',
        xField: 'fronthairxpos',
        yField: 'fronthairypos',
        scaleXField: 'fronthairxscale',
        scaleYField: 'fronthairyscale',
        rotationField: 'fronthairrot',
        rotationUsesDirectFieldFallback: false,
        appliesGeometricRotation: false,
      );
    case 'back_hair':
      return const _TestSlotBinding(
        targetContains: 'backhair.backhair',
        xField: 'backhairxpos',
        yField: 'backhairypos',
        scaleXField: 'backhairxscale',
        scaleYField: 'backhairyscale',
        rotationField: 'backhairrot',
      );
    case 'ponytail':
      return const _TestSlotBinding(
        targetContains: 'backhair.backhair.ponytail',
        xField: 'ponytailxpos',
        yField: 'ponytailypos',
        scaleXField: 'ponytailxscale',
        scaleYField: 'ponytailyscale',
        rotationField: 'ponytailrot',
      );
    case 'weapon_front':
      return const _TestSlotBinding(
        targetContains: 'weapon.weapon',
        xField: 'propxpos1x',
        yField: 'propypos1x',
        scaleXField: 'propsize1x',
        scaleYField: 'propsize1x',
        rotationField: 'proprot1x',
      );
    case 'shield':
      return const _TestSlotBinding(
        targetContains: 'shield.shield',
        xField: 'shieldxpos',
        yField: 'shieldypos',
        scaleXField: 'shieldsize',
        scaleYField: 'shieldsize',
        rotationField: 'shieldrot',
      );
  }
  return null;
}

void _expectMatrixClose(
  AffineMatrix actual,
  AffineMatrix expected,
  String label,
) {
  _expectClose(actual.a, expected.a, '$label.a');
  _expectClose(actual.b, expected.b, '$label.b');
  _expectClose(actual.c, expected.c, '$label.c');
  _expectClose(actual.d, expected.d, '$label.d');
  _expectClose(actual.tx, expected.tx, '$label.tx');
  _expectClose(actual.ty, expected.ty, '$label.ty');
}

void _expectClose(double actual, double expected, String label) {
  expect(
    (actual - expected).abs(),
    lessThan(1e-6),
    reason: '$label expected $expected got $actual',
  );
}

class _TestSlotBinding {
  const _TestSlotBinding({
    required this.targetContains,
    required this.xField,
    required this.yField,
    required this.scaleXField,
    required this.scaleYField,
    required this.rotationField,
    this.rotationUsesDirectFieldFallback = true,
    this.appliesGeometricRotation = true,
  });

  final String targetContains;
  final String xField;
  final String yField;
  final String scaleXField;
  final String scaleYField;
  final String rotationField;
  final bool rotationUsesDirectFieldFallback;
  final bool appliesGeometricRotation;
}
