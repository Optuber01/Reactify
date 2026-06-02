import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/transform_graph.dart';
import 'package:reactify_gacha/src/reactify/export/reactify_svg_exporter.dart';
import 'package:reactify_gacha/src/reactify/legacy/gacha_to_reactify_adapter.dart';
import 'package:reactify_gacha/src/reactify/model/reactify_document.dart';
import 'package:reactify_gacha/src/reactify/render/reactify_render_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ResolverTables tables;
  late GachaCodeParser parser;
  late GachaToReactifyAdapter adapter;

  setUpAll(() async {
    tables = await ResolverTables.load(
      includeResolutionRows: false,
      validateAssetCoverage: false,
    );
    parser = GachaCodeParser(tables.schema);
    adapter = GachaToReactifyAdapter(
      renderer: CharacterRenderer(
        tables: tables,
        assetStore: GachaAssetStore(),
      ),
    );
  });

  test('migrates a Gacha code into stable native slots', () async {
    final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
    final state = parser.parse(code);
    final character = adapter.migrate(state, id: 'char.default_boy');

    expect(character.id, 'char.default_boy');
    expect(character.legacyGachaCode!.split('|'), hasLength(445));
    expect(character.rig.anchors.keys, containsAll(['torso', 'head']));
    expect(character.slots, isNotEmpty);
    expect(
      character.slots.map((slot) => slot.id).toSet(),
      hasLength(character.slots.length),
    );
    expect(character.semanticSlots, isNotEmpty);
    expect(
      character.semanticSlots.every((slot) => slot.childSlotIds.isNotEmpty),
      isTrue,
    );
    expect(
      character.renderableSlots.every(
        (slot) => slot.metadata.containsKey('legacyLeafId'),
      ),
      isTrue,
    );
    expect(character.slotsForFamily('head'), isNotEmpty);
    expect(character.slotsForFamily('hair'), isNotEmpty);
    expect(character.slots.every((slot) => slot.anchorId.isNotEmpty), isTrue);
  });

  test('round-trips versioned character and scene JSON', () async {
    final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
    final character = adapter.migrate(parser.parse(code), id: 'char.default');
    final scene = ReactifySceneDocument(
      id: 'scene.roundtrip',
      name: 'Roundtrip',
      background: const ReactifyBackgroundRef(
        id: 'background.grid',
        asset: ReactifyAssetRef(
          id: 'background.grid.svg',
          kind: ReactifyAssetKind.svg,
          uri: 'assets/gacha/head/head_1.svg',
        ),
      ),
      cameraTransform: AffineMatrix.translation(12, 18),
      characters: const [
        ReactifySceneCharacter(
          id: 'scene_char.one',
          characterId: 'char.default',
          transform: AffineMatrix.identity(),
          expression: 'surprised',
          pose: 'standing',
          dialogue: 'Hello & welcome',
        ),
      ],
    );

    final reparsedCharacter = ReactifyCharacterDocument.fromJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(character.toJson()))),
    );
    final reparsedScene = ReactifySceneDocument.fromJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(scene.toJson()))),
    );

    expect(reparsedCharacter.schemaVersion, reactifyCharacterDocumentVersion);
    expect(reparsedCharacter.toJson(), character.toJson());
    expect(reparsedScene.schemaVersion, reactifySceneDocumentVersion);
    expect(reparsedScene.toJson(), scene.toJson());
  });

  test('supports custom reusable slots without touching legacy code', () async {
    final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
    final state = parser.parse(code);
    final character = adapter
        .migrate(state)
        .addSlot(
          const ReactifySlot(
            id: 'custom.face.spark',
            kind: ReactifySlotKind.custom,
            family: 'custom',
            name: 'Spark',
            anchorId: 'head',
            localTransform: AffineMatrix.identity(),
            depth: 900000000,
            visible: true,
            asset: ReactifyAssetRef(
              id: 'custom.spark.svg',
              kind: ReactifyAssetKind.svg,
              uri: 'user-assets/spark.svg',
              source: 'user',
            ),
          ),
        );

    expect(character.legacyGachaCode, state.serializeCode());
    expect(character.slotsForFamily('custom').single.id, 'custom.face.spark');
    expect(
      character.renderableSlots.map((slot) => slot.id),
      contains('custom.face.spark'),
    );
  });

  test(
    'render bridge resolves native parts and scene semantic overrides',
    () async {
      final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
      final character = adapter.migrate(
        parser.parse(code),
        id: 'char.default_boy',
      );
      final hairSlot = character.semanticSlots.firstWhere(
        (slot) => slot.family == 'hair',
      );
      final baseParts = ReactifyRenderBridge(
        assetStore: GachaAssetStore(),
      ).resolveCharacterParts(character);
      final scene = ReactifySceneDocument(
        id: 'scene.override',
        name: 'Override',
        characters: [
          ReactifySceneCharacter(
            id: 'scene_char.host',
            characterId: 'char.default_boy',
            transform: AffineMatrix.translation(20, 30),
            slotOverrides: {
              hairSlot.id: const ReactifySlotOverride(visible: false),
            },
          ),
        ],
      );

      final bridgeParts = ReactifyRenderBridge(
        assetStore: GachaAssetStore(),
      ).resolveSceneParts(scene, {character.id: character});
      final shiftedPart = bridgeParts.first;
      final baseMatch = baseParts.firstWhere(
        (part) => part.catalogPart.leafId == shiftedPart.catalogPart.leafId,
      );

      expect(baseParts, isNotEmpty);
      expect(
        bridgeParts
            .where((part) => part.catalogPart.family.contains('hair'))
            .toList(),
        isEmpty,
      );
      expect(shiftedPart.sceneTransform.tx, 20);
      expect(shiftedPart.sceneTransform.ty, 30);
      expect(
        shiftedPart.localTransform.toDebugJson(),
        baseMatch.localTransform.toDebugJson(),
      );
    },
  );

  test('render bridge bounds include scene and rig transforms', () async {
    const character = ReactifyCharacterDocument(
      id: 'char.bounds',
      name: 'Bounds',
      rig: ReactifyRigTemplate(
        id: 'test_rig',
        name: 'Test Rig',
        anchors: {
          'torso': ReactifyAnchor(
            id: 'torso',
            localTransform: AffineMatrix(
              a: 1,
              b: 0,
              c: 0,
              d: 1,
              tx: 40,
              ty: 50,
            ),
          ),
        },
      ),
      slots: [
        ReactifySlot(
          id: 'slot.bounds',
          kind: ReactifySlotKind.custom,
          family: 'test',
          name: 'Bounds Slot',
          anchorId: 'torso',
          localTransform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 10, ty: 15),
          depth: 1,
          visible: true,
          asset: ReactifyAssetRef(
            id: 'asset.bounds',
            kind: ReactifyAssetKind.svg,
            uri: 'assets/gacha/body/10803.svg',
          ),
        ),
      ],
    );
    const scene = ReactifySceneDocument(
      id: 'scene.bounds',
      name: 'Bounds',
      characters: [
        ReactifySceneCharacter(
          id: 'scene_char.bounds',
          characterId: 'char.bounds',
          transform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 20, ty: 30),
        ),
      ],
    );

    final resolved = await ReactifyRenderBridge(
      assetStore: GachaAssetStore(),
    ).buildScene(scene, {character.id: character});

    expect(resolved.worldBounds.left, 70);
    expect(resolved.worldBounds.top, 95);
  });

  test(
    'svg nested transforms match flattened native render transforms',
    () async {
      const character = ReactifyCharacterDocument(
        id: 'char.transform',
        name: 'Transform',
        rig: ReactifyRigTemplate(
          id: 'test_rig',
          name: 'Test Rig',
          anchors: {
            'torso': ReactifyAnchor(
              id: 'torso',
              localTransform: AffineMatrix(
                a: 1,
                b: 0,
                c: 0,
                d: 1,
                tx: 40,
                ty: 50,
              ),
            ),
          },
        ),
        slots: [
          ReactifySlot(
            id: 'slot.transform',
            kind: ReactifySlotKind.custom,
            family: 'test',
            name: 'Transform Slot',
            anchorId: 'torso',
            localTransform: AffineMatrix(
              a: 1,
              b: 0,
              c: 0,
              d: 1,
              tx: 10,
              ty: 15,
            ),
            depth: 1,
            visible: true,
            asset: ReactifyAssetRef(
              id: 'asset.transform',
              kind: ReactifyAssetKind.svg,
              uri: 'assets/gacha/body/10803.svg',
            ),
          ),
        ],
      );
      const scene = ReactifySceneDocument(
        id: 'scene.transform',
        name: 'Transform',
        cameraTransform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 5, ty: 7),
        characters: [
          ReactifySceneCharacter(
            id: 'scene_char.transform',
            characterId: 'char.transform',
            transform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 20, ty: 30),
          ),
        ],
      );

      final bridge = ReactifyRenderBridge(assetStore: GachaAssetStore());
      final flattened = bridge
          .resolveRenderableSceneParts(scene, {character.id: character})
          .single
          .part
          .localTransform;
      final package = await ReactifySvgExporter().exportPackage(scene, {
        character.id: character,
      });

      expect(flattened.tx, 75);
      expect(flattened.ty, 102);
      expect(package.svg, contains('transform="matrix(1 0 0 1 5 7)"'));
      expect(package.svg, contains('transform="matrix(1 0 0 1 20 30)"'));
      expect(package.svg, contains('transform="matrix(1 0 0 1 50 65)"'));
    },
  );

  test('exports editable SVG scene groups for characters and slots', () async {
    final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
    final character = adapter.migrate(
      parser.parse(code),
      id: 'char.default_boy',
    );
    final scene = const ReactifySceneDocument(
      id: 'scene.reaction',
      name: 'Reaction',
      characters: [
        ReactifySceneCharacter(
          id: 'scene_char.host',
          characterId: 'char.default_boy',
          transform: AffineMatrix.identity(),
        ),
      ],
    );

    final package = await ReactifySvgExporter().exportPackage(scene, {
      character.id: character,
    });
    final svg = package.svg;

    expect(svg, contains('data-reactify-type="scene"'));
    expect(svg, contains('data-reactify-type="character"'));
    expect(svg, contains('data-reactify-type="slot"'));
    expect(svg, contains('data-slot-kind="semantic"'));
    expect(svg, contains('legacyFamily'));
    expect(svg, contains('data-family="hair"'));
    expect(svg, contains('transform="matrix('));
    expect(package.assets, isNotEmpty);
    expect(
      package.assets.any((asset) => asset.uri.startsWith('assets/gacha/')),
      isTrue,
    );
    expect(
      package.assets.any((asset) => asset.inlined) ||
          svg.contains('href="assets/gacha/'),
      isTrue,
    );
  });

  test(
    'svg export applies semantic slot overrides to child render leaves',
    () async {
      final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
      final character = adapter.migrate(
        parser.parse(code),
        id: 'char.default_boy',
      );
      final hairSlot = character.semanticSlots.firstWhere(
        (slot) => slot.family == 'hair',
      );
      final scene = ReactifySceneDocument(
        id: 'scene.svg.override',
        name: 'SVG Override',
        characters: [
          ReactifySceneCharacter(
            id: 'scene_char.host',
            characterId: 'char.default_boy',
            transform: const AffineMatrix.identity(),
            slotOverrides: {
              hairSlot.id: const ReactifySlotOverride(visible: false),
            },
          ),
        ],
      );

      final package = await ReactifySvgExporter().exportPackage(scene, {
        character.id: character,
      });

      expect(package.svg, isNot(contains(hairSlot.id)));
      for (final childId in hairSlot.childSlotIds) {
        expect(package.svg, isNot(contains(childId)));
      }
    },
  );

  test(
    'renderable native scene flattens multi-character transforms and overrides',
    () async {
      final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
      final character = adapter.migrate(
        parser.parse(code),
        id: 'char.default_boy',
      );
      final hairSlot = character.semanticSlots.firstWhere(
        (slot) => slot.family == 'hair',
      );
      final scene = ReactifySceneDocument(
        id: 'scene.multi',
        name: 'Multi',
        characters: [
          const ReactifySceneCharacter(
            id: 'scene_char.left',
            characterId: 'char.default_boy',
            transform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: -120, ty: 0),
          ),
          ReactifySceneCharacter(
            id: 'scene_char.right',
            characterId: 'char.default_boy',
            transform: const AffineMatrix(
              a: 1,
              b: 0,
              c: 0,
              d: 1,
              tx: 120,
              ty: 0,
            ),
            slotOverrides: {
              hairSlot.id: const ReactifySlotOverride(visible: false),
            },
          ),
        ],
      );

      final resolved = await ReactifyRenderBridge(
        assetStore: GachaAssetStore(),
      ).buildRenderableScene(scene, {character.id: character});

      expect(resolved.parts, isNotEmpty);
      expect(
        resolved.parts.any(
          (part) => part.catalogPart.leafId.startsWith('scene_char.left.'),
        ),
        isTrue,
      );
      expect(
        resolved.parts.any(
          (part) => part.catalogPart.leafId.startsWith('scene_char.right.'),
        ),
        isTrue,
      );
      expect(
        resolved.parts
            .where(
              (part) =>
                  part.catalogPart.leafId.startsWith('scene_char.right.') &&
                  part.catalogPart.family.contains('hair'),
            )
            .toList(),
        isEmpty,
      );
      expect(
        resolved.parts
            .where(
              (part) =>
                  part.catalogPart.leafId.startsWith('scene_char.left.') &&
                  part.catalogPart.family.contains('hair'),
            )
            .toList(),
        isNotEmpty,
      );
      expect(resolved.worldBounds.isEmpty, isFalse);
    },
  );

  test('exports native drawing slots as editable SVG and PNG', () async {
    const drawingSlot = ReactifySlot(
      id: 'custom.drawing.test',
      kind: ReactifySlotKind.custom,
      family: 'custom',
      name: 'Drawing',
      anchorId: 'torso',
      localTransform: AffineMatrix.identity(),
      depth: 1,
      visible: true,
      asset: ReactifyAssetRef(
        id: 'custom.drawing.test.asset',
        kind: ReactifyAssetKind.drawing,
        uri: 'reactify://drawing/custom.drawing.test',
        source: 'user',
      ),
      metadata: {
        'source': 'user_drawing',
        'drawingColor': '#00F5FF',
        'drawingStrokeWidth': 4.0,
        'drawingStrokes': [
          [
            {'x': 10.0, 'y': 10.0},
            {'x': 40.0, 'y': 22.0},
            {'x': 80.0, 'y': 12.0},
          ],
        ],
      },
    );
    const character = ReactifyCharacterDocument(
      id: 'char.drawing',
      name: 'Drawing',
      rig: ReactifyRigTemplate.gachaCompatibility,
      slots: [drawingSlot],
    );
    const scene = ReactifySceneDocument(
      id: 'scene.drawing',
      name: 'Drawing',
      canvasSize: Size(160, 120),
      characters: [
        ReactifySceneCharacter(
          id: 'scene_char.drawing',
          characterId: 'char.drawing',
          transform: AffineMatrix.identity(),
        ),
      ],
    );

    final svgPackage = await ReactifySvgExporter().exportPackage(scene, {
      character.id: character,
    });
    final pngBytes = await ReactifyPngExporter(
      bridge: ReactifyRenderBridge(assetStore: GachaAssetStore()),
    ).exportScene(scene, {character.id: character});

    expect(svgPackage.svg, contains('data-reactify-drawing="stroke"'));
    expect(svgPackage.svg, contains('M 10 10 L 40 22 L 80 12'));
    expect(svgPackage.assets.single.inlined, isTrue);
    expect(pngBytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
