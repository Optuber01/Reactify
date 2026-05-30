import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/csv_loaders.dart';
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
    'faceshadow rows keep source-backed opacity in the exported asset instead of tinting the family',
    () async {
      final rows = await CsvLoaders.loadAssetCsv(
        'assets/data/generated/render_parts_extras.csv',
      );
      final faceshadowRows = rows.where((row) => row['family'] == 'faceshadow');

      expect(faceshadowRows, isNotEmpty);
      for (final row in faceshadowRows) {
        expect(row['tint_channel'], 'none');
      }

      final asset = await rootBundle.loadString('assets/gacha/face/17902.svg');
      expect(asset.contains('<linearGradient'), isTrue);
      expect(asset.contains('stop-opacity="0.298039"'), isTrue);
      expect(asset.contains('fill="url(#fill-gradient-1)"'), isTrue);
    },
  );

  test(
    'gacha dj boy faceshadow no longer renders as an opaque black face overlay',
    () async {
      final state = await _stateForFixture(parser, 'gacha-dj-boy');
      final scene = await renderer.buildScene(state);
      final families = _familyBounds(scene);

      expect(families.containsKey('faceshadow'), isTrue);
      expect(families.containsKey('head_shape'), isTrue);
      expect(families.containsKey('mouth'), isTrue);

      final image = await _renderScene(scene, const ui.Size(1200, 1200));
      final head = families['head_shape']!;
      final mouth = families['mouth']!;
      final camera = _cameraFor(scene, const ui.Size(1200, 1200));

      final leftCheek = camera.transformPoint(
        ui.Offset(
          head.center.dx - head.width * 0.18,
          mouth.center.dy - mouth.height * 0.4,
        ),
      );
      final rightCheek = camera.transformPoint(
        ui.Offset(
          head.center.dx + head.width * 0.18,
          mouth.center.dy - mouth.height * 0.4,
        ),
      );

      final leftColor = await _averageColorAt(image, leftCheek);
      final rightColor = await _averageColorAt(image, rightCheek);

      expect(
        !_isNearBlack(leftColor) || !_isNearBlack(rightColor),
        isTrue,
        reason:
            'Expected at least one cheek sample to stay out of opaque black. '
            'left=$leftColor right=$rightColor',
      );
    },
  );

  test(
    'priority visual sanity keeps head-face samples out of black domination',
    () async {
      for (final fixtureId in const [
        'gacha-dj-boy',
        'default-boy',
        'default-girl',
      ]) {
        final state = await _stateForFixture(parser, fixtureId);
        final scene = await renderer.buildScene(state);
        final families = _familyBounds(scene);
        final head = families['head_shape'];
        final mouth = families['mouth'];
        expect(head, isNotNull, reason: '$fixtureId missing head_shape');
        expect(mouth, isNotNull, reason: '$fixtureId missing mouth');

        final image = await _renderScene(scene, const ui.Size(900, 900));
        final camera = _cameraFor(scene, const ui.Size(900, 900));
        final samplePoint = camera.transformPoint(
          ui.Offset(head!.center.dx, (head.center.dy + mouth!.center.dy) / 2),
        );
        final color = await _averageColorAt(image, samplePoint);

        expect(
          _isNearBlack(color),
          isFalse,
          reason:
              '$fixtureId face sample drifted into black domination: $color',
        );
      }
    },
  );

  test(
    'default boy and default girl remain unaffected by faceshadow regressions',
    () async {
      for (final fixtureId in const ['default-boy', 'default-girl']) {
        final scene = await renderer.buildScene(
          await _stateForFixture(parser, fixtureId),
        );
        expect(
          scene.parts.any((part) => part.catalogPart.family == 'faceshadow'),
          isFalse,
          reason: fixtureId,
        );
      }
    },
  );
}

Future<GachaCharacterState> _stateForFixture(
  GachaCodeParser parser,
  String fixtureId,
) async {
  final code = await rootBundle.loadString(
    'fixtures/builtin/$fixtureId.gc.txt',
  );
  return parser.parse(code);
}

Map<String, ui.Rect> _familyBounds(ResolvedScene scene) {
  final result = <String, ui.Rect>{};
  for (final part in scene.parts) {
    final asset = scene.assets[part.catalogPart.appAssetPath];
    if (asset == null) {
      continue;
    }
    final bounds = part.localTransform.transformRect(
      ui.Rect.fromLTWH(0, 0, asset.size.width, asset.size.height),
    );
    result.update(
      part.catalogPart.family,
      (current) => current.expandToInclude(bounds),
      ifAbsent: () => bounds,
    );
  }
  return result;
}

AffineMatrix _cameraFor(ResolvedScene scene, ui.Size size) {
  final paddedBounds = scene.worldBounds.inflate(48);
  final scale = [
    (size.width - 32) / paddedBounds.width,
    (size.height - 32) / paddedBounds.height,
  ].reduce((left, right) => left < right ? left : right);
  return AffineMatrix.translation(
    (size.width - paddedBounds.width * scale) / 2 - paddedBounds.left * scale,
    (size.height - paddedBounds.height * scale) / 2 - paddedBounds.top * scale,
  ).multiply(AffineMatrix.scale(scale, scale));
}

Future<ui.Image> _renderScene(ResolvedScene scene, ui.Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.width, size.height),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  if (scene.parts.isNotEmpty && !scene.worldBounds.isEmpty) {
    final camera = _cameraFor(scene, size);
    for (final part in scene.parts) {
      final asset = scene.assets[part.catalogPart.appAssetPath];
      if (asset == null) {
        continue;
      }
      canvas.save();
      canvas.transform(camera.multiply(part.localTransform).toFloat64List());
      asset.paint(canvas, part.tintColor);
      canvas.restore();
    }
  }
  return recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
}

Future<ui.Color> _averageColorAt(ui.Image image, ui.Offset point) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    throw StateError('Failed to read rendered image bytes.');
  }
  final bytes = byteData.buffer.asUint8List();
  final width = image.width;
  final height = image.height;
  var red = 0;
  var green = 0;
  var blue = 0;
  var alpha = 0;
  var count = 0;
  for (var dy = -2; dy <= 2; dy++) {
    for (var dx = -2; dx <= 2; dx++) {
      final x = (point.dx.round() + dx).clamp(0, width - 1);
      final y = (point.dy.round() + dy).clamp(0, height - 1);
      final index = (y * width + x) * 4;
      red += bytes[index];
      green += bytes[index + 1];
      blue += bytes[index + 2];
      alpha += bytes[index + 3];
      count += 1;
    }
  }
  return ui.Color.fromARGB(
    (alpha / count).round(),
    (red / count).round(),
    (green / count).round(),
    (blue / count).round(),
  );
}

bool _isNearBlack(ui.Color color) {
  final value = color.toARGB32();
  final red = (value >> 16) & 0xFF;
  final green = (value >> 8) & 0xFF;
  final blue = value & 0xFF;
  return red < 24 && green < 24 && blue < 24;
}
