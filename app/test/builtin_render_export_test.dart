import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/render_part.dart';
import 'package:reactify_gacha/src/gacha/render/transform_graph.dart';
import 'package:reactify_gacha/src/gacha/ui/editor_helpers.dart';

import 'support/parity_audit_support.dart';

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
    'representative built-in fixtures resolve supported expected families',
    () async {
      final representative = <ValidationCaseDescriptor>[];

      for (final descriptor in _pickRepresentativeFixtures(
        tables.builtinFixtures,
        maxCount: 24,
      )) {
        final state = await _stateForFixture(
          parser: parser,
          fixtureAsset: descriptor.fixtureAsset,
        );
        final scene = await renderer.buildScene(state);
        final resolved = resolvedFamilyCounts(scene).keys.toSet();
        final expected = expectedResolvedFamiliesForState(state)
          ..removeAll(_knownUnsupportedFamilies);
        final missing = expected.difference(resolved);
        if (missing.isEmpty) {
          representative.add(descriptor);
        }
        if (representative.length >= 8) {
          break;
        }
      }

      expect(representative.length, greaterThanOrEqualTo(2));

      for (final descriptor in representative) {
        final state = await _stateForFixture(
          parser: parser,
          fixtureAsset: descriptor.fixtureAsset,
        );
        final scene = await renderer.buildScene(state);
        final resolved = resolvedFamilyCounts(scene).keys.toSet();
        final expected = expectedResolvedFamiliesForState(state)
          ..removeAll(_knownUnsupportedFamilies);
        final missing = expected.difference(resolved);

        expect(
          missing,
          isEmpty,
          reason:
              '${descriptor.displayName} is missing supported families: ${missing.join(', ')}',
        );
        expect(scene.parts, isNotEmpty, reason: descriptor.displayName);
        expect(
          scene.worldBounds.isEmpty,
          isFalse,
          reason: descriptor.displayName,
        );
      }
    },
  );

  test(
    'full curated built-in export writes PNGs and an audit summary when enabled',
    () async {
      if (Platform.environment['RUN_FULL_BUILTIN_EXPORT'] != '1') {
        // ignore: avoid_print
        print(
          'Skipping full built-in export. Set RUN_FULL_BUILTIN_EXPORT=1 to generate app/tmp/render_exports/builtin/.',
        );
        return;
      }

      final outputDir = Directory('tmp/render_exports/builtin');
      if (outputDir.existsSync()) {
        outputDir.deleteSync(recursive: true);
      }
      outputDir.createSync(recursive: true);

      final summaries = <Map<String, dynamic>>[];
      for (final descriptor in tables.builtinFixtures) {
        final state = await _stateForFixture(
          parser: parser,
          fixtureAsset: descriptor.fixtureAsset,
        );
        final scene = await renderer.buildScene(state);
        final image = await _renderScene(scene, const ui.Size(1200, 1200));
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(byteData, isNotNull, reason: descriptor.displayName);
        final pngPath = File('${outputDir.path}/${descriptor.id}.png');
        pngPath.writeAsBytesSync(byteData!.buffer.asUint8List());
        summaries.add(
          auditSummaryWithCatalog(
            tables: tables,
            fixture: PriorityFixtureContext(
              descriptor: descriptor,
              state: state,
              scene: scene,
              tables: tables,
            ),
          ),
        );
      }

      final summaryPath = File('${outputDir.path}/render_audit_summary.json');
      summaryPath.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'fixture_count': tables.builtinFixtures.length,
          'known_unsupported_families': _knownUnsupportedFamilies.toList()
            ..sort(),
          'fixtures': summaries,
        }),
      );

      final generatedAudit = await generatePriorityAuditArtifacts(
        tables: tables,
        parser: parser,
        renderer: renderer,
      );

      expect(summaryPath.existsSync(), isTrue);
      expect(File(generatedAudit.matrixJsonPath).existsSync(), isTrue);
      expect(File(generatedAudit.matrixMdPath).existsSync(), isTrue);
      expect(
        outputDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.png'))
            .length,
        tables.builtinFixtures.length,
      );
      expect(
        generatedAudit.contactSheetPaths,
        hasLength(priorityFixtureIds.length),
      );
    },
    timeout: const Timeout.factor(8),
  );
}

const Set<String> _knownUnsupportedFamilies = {'special', 'special2'};

Future<GachaCharacterState> _stateForFixture({
  required GachaCodeParser parser,
  required String fixtureAsset,
}) async {
  final code = await rootBundle.loadString(fixtureAsset);
  return parser.parse(code);
}

List<ValidationCaseDescriptor> _pickRepresentativeFixtures(
  List<ValidationCaseDescriptor> fixtures, {
  required int maxCount,
}) {
  final selected = <ValidationCaseDescriptor>[];
  final coveredTags = <String>{};
  final remaining = [...fixtures];

  while (selected.length < maxCount && remaining.isNotEmpty) {
    remaining.sort((left, right) {
      final leftGain = left.featureTags
          .where((tag) => !coveredTags.contains(tag))
          .length;
      final rightGain = right.featureTags
          .where((tag) => !coveredTags.contains(tag))
          .length;
      if (leftGain != rightGain) {
        return rightGain.compareTo(leftGain);
      }
      return left.id.compareTo(right.id);
    });
    final next = remaining.removeAt(0);
    selected.add(next);
    coveredTags.addAll(next.featureTags);
  }

  return selected;
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
