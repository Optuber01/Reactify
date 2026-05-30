import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/render_part.dart';
import 'package:reactify_gacha/src/gacha/render/transform_graph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'export focused preview renders for inspection',
    () async {
      final tables = await ResolverTables.load();
      final parser = GachaCodeParser(tables.schema);
      final renderer = CharacterRenderer(
        tables: tables,
        assetStore: GachaAssetStore(),
      );
      final outputDir = Directory('tmp/render_exports/previews');
      if (outputDir.existsSync()) {
        outputDir.deleteSync(recursive: true);
      }
      outputDir.createSync(recursive: true);

      for (final descriptor in tables.validationCases) {
        final code = await rootBundle.loadString(descriptor.fixtureAsset);
        final state = parser.parse(code);
        final scene = await renderer.buildScene(state);
        final image = await _renderScene(scene, const ui.Size(1200, 1200));
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(byteData, isNotNull);
        final outPath = File('${outputDir.path}/${descriptor.id}.png');
        outPath.writeAsBytesSync(byteData!.buffer.asUint8List());
        // ignore: avoid_print
        print('wrote ${outPath.path}');
      }
    },
    timeout: const Timeout.factor(6),
  );
}

Future<ui.Image> _renderScene(ResolvedScene scene, ui.Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final background = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, size.height), background);
  if (scene.parts.isNotEmpty && !scene.worldBounds.isEmpty) {
    final paddedBounds = scene.worldBounds.inflate(48);
    final scale = [
      (size.width - 32) / paddedBounds.width,
      (size.height - 32) / paddedBounds.height,
    ].reduce((left, right) => left < right ? left : right);
    final camera = AffineMatrix.translation(
      (size.width - paddedBounds.width * scale) / 2 - paddedBounds.left * scale,
      (size.height - paddedBounds.height * scale) / 2 -
          paddedBounds.top * scale,
    ).multiply(AffineMatrix.scale(scale, scale));
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
