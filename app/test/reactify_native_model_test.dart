import 'dart:convert';
import 'dart:ui' as ui;

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

  test(
    'scene editor persists multi-character selection overrides and drawings',
    () async {
      final baseCharacter = _editableTestCharacter('char.left');
      final rightCharacter = _editableTestCharacter('char.right');
      final editor = ReactifySceneEditingState(
        selectedSceneCharacterId: 'scene_char.left',
        characters: {
          baseCharacter.id: baseCharacter,
          rightCharacter.id: rightCharacter,
        },
        scene: const ReactifySceneDocument(
          id: 'scene.editing',
          name: 'Editing',
          characters: [
            ReactifySceneCharacter(
              id: 'scene_char.left',
              characterId: 'char.left',
              transform: AffineMatrix.identity(),
            ),
            ReactifySceneCharacter(
              id: 'scene_char.right',
              characterId: 'char.right',
              transform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 160, ty: 0),
            ),
          ],
        ),
      );
      const drawing = ReactifySlot(
        id: 'custom.drawing.persisted',
        kind: ReactifySlotKind.custom,
        family: 'custom',
        name: 'Persisted Drawing',
        anchorId: 'head',
        localTransform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 8, ty: 9),
        depth: 10,
        visible: true,
        asset: ReactifyAssetRef(
          id: 'custom.drawing.persisted.asset',
          kind: ReactifyAssetKind.drawing,
          uri: 'reactify://drawing/custom.drawing.persisted',
          source: 'user',
        ),
        metadata: {
          'source': 'user_drawing',
          'drawingColor': '#00F5FF',
          'drawingStrokeWidth': 4.0,
          'drawingStrokes': [
            [
              {'x': 1.0, 'y': 2.0},
              {'x': 5.0, 'y': 8.0},
            ],
          ],
        },
      );

      final edited = editor
          .selectSceneCharacter('scene_char.right')
          .updateSelectedCharacterTransform(
            const AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 42, ty: 24),
          )
          .toggleSelectedSemanticSlotOverride(family: 'hair', hidden: true)
          .addCustomSlotToSelectedCharacter(drawing);
      final reparsed = ReactifySceneEditingState.fromJson(
        Map<String, Object?>.from(jsonDecode(jsonEncode(edited.toJson()))),
      );
      final rightScene = reparsed.scene.characters.firstWhere(
        (character) => character.id == 'scene_char.right',
      );
      final leftScene = reparsed.scene.characters.firstWhere(
        (character) => character.id == 'scene_char.left',
      );
      final rightDocument = reparsed.characters['char.right']!;

      expect(reparsed.toJson(), edited.toJson());
      expect(reparsed.scene.characters, hasLength(2));
      expect(reparsed.selectedSceneCharacterId, 'scene_char.right');
      expect(rightScene.transform.tx, 42);
      expect(rightScene.transform.ty, 24);
      expect(leftScene.transform.tx, 0);
      expect(leftScene.slotOverrides, isEmpty);
      expect(rightScene.slotOverrides['semantic.hair']?.visible, isFalse);
      expect(
        rightDocument.slots.map((slot) => slot.id),
        contains('custom.drawing.persisted'),
      );
      expect(
        rightDocument.slots
            .firstWhere((slot) => slot.id == 'custom.drawing.persisted')
            .metadata['drawingStrokes'],
        drawing.metadata['drawingStrokes'],
      );
    },
  );

  test(
    'native preview svg and png exports share scene transform semantics',
    () async {
      final character = _transformEquivalenceCharacter();
      const scene = ReactifySceneDocument(
        id: 'scene.export.transforms',
        name: 'Export Transforms',
        canvasSize: Size(160, 140),
        cameraTransform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 5, ty: 7),
        characters: [
          ReactifySceneCharacter(
            id: 'scene_char.export',
            characterId: 'char.export',
            transform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 20, ty: 30),
          ),
        ],
      );
      final characters = {character.id: character};
      final bridge = ReactifyRenderBridge(assetStore: GachaAssetStore());
      final previewPart = bridge
          .resolveRenderableSceneParts(scene, characters)
          .single
          .part;
      final resolved = await bridge.buildRenderableScene(scene, characters);
      final image = await ReactifyPngExporter.renderResolvedScene(
        resolved,
        scene.canvasSize,
      );
      final rawPixels = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose();
      final svg = await ReactifySvgExporter().exportPackage(scene, characters);
      final pngBytes = await ReactifyPngExporter(
        bridge: bridge,
      ).exportScene(scene, characters);

      expect(previewPart.localTransform.tx, 75);
      expect(previewPart.localTransform.ty, 102);
      expect(svg.svg, contains('transform="matrix(1 0 0 1 5 7)"'));
      expect(svg.svg, contains('transform="matrix(1 0 0 1 20 30)"'));
      expect(svg.svg, contains('transform="matrix(1 0 0 1 50 65)"'));
      expect(rawPixels, isNotNull);
      final pixels = rawPixels!;
      expect(
        _hasPaintedPixel(
          pixels,
          scene.canvasSize.width.toInt(),
          left: 75,
          top: 102,
          right: 92,
          bottom: 116,
        ),
        isTrue,
      );
      expect(
        _hasPaintedPixel(
          pixels,
          scene.canvasSize.width.toInt(),
          left: 10,
          top: 15,
          right: 30,
          bottom: 35,
        ),
        isFalse,
      );
      expect(pngBytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    },
  );

  test('native editing does not regress Gacha 445 import export', () async {
    final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
    final state = parser.parse(code);
    final exported = state.serializeCode();
    final reparsed = parser.parse(exported);

    expect(exported.split('|'), hasLength(445));
    expect(reparsed.rawFields, orderedEquals(state.rawFields));
  });

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

ReactifyCharacterDocument _editableTestCharacter(String id) {
  return ReactifyCharacterDocument(
    id: id,
    name: id,
    rig: const ReactifyRigTemplate(
      id: 'editable_rig',
      name: 'Editable Rig',
      anchors: {
        'torso': ReactifyAnchor(
          id: 'torso',
          localTransform: AffineMatrix.identity(),
        ),
        'head': ReactifyAnchor(
          id: 'head',
          parentId: 'torso',
          localTransform: AffineMatrix.identity(),
        ),
      },
    ),
    slots: const [
      ReactifySlot(
        id: 'semantic.hair',
        kind: ReactifySlotKind.semantic,
        family: 'hair',
        name: 'Hair',
        anchorId: 'head',
        localTransform: AffineMatrix.identity(),
        depth: 0,
        visible: true,
        childSlotIds: ['hair.front'],
      ),
      ReactifySlot(
        id: 'hair.front',
        kind: ReactifySlotKind.renderLeaf,
        family: 'hair',
        name: 'Front Hair',
        anchorId: 'head',
        localTransform: AffineMatrix.identity(),
        depth: 1,
        visible: true,
        asset: ReactifyAssetRef(
          id: 'hair.front.asset',
          kind: ReactifyAssetKind.drawing,
          uri: 'reactify://drawing/hair.front',
        ),
        metadata: {
          'drawingColor': '#112233',
          'drawingStrokeWidth': 2.0,
          'drawingStrokes': [
            [
              {'x': 0.0, 'y': 0.0},
              {'x': 10.0, 'y': 0.0},
            ],
          ],
        },
      ),
    ],
  );
}

bool _hasPaintedPixel(
  ByteData pixels,
  int width, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final alpha = pixels.getUint8(((y * width) + x) * 4 + 3);
      if (alpha > 0) {
        return true;
      }
    }
  }
  return false;
}

ReactifyCharacterDocument _transformEquivalenceCharacter() {
  return const ReactifyCharacterDocument(
    id: 'char.export',
    name: 'Export',
    rig: ReactifyRigTemplate(
      id: 'export_rig',
      name: 'Export Rig',
      anchors: {
        'torso': ReactifyAnchor(
          id: 'torso',
          localTransform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 40, ty: 50),
        ),
      },
    ),
    slots: [
      ReactifySlot(
        id: 'slot.export',
        kind: ReactifySlotKind.custom,
        family: 'custom',
        name: 'Export Slot',
        anchorId: 'torso',
        localTransform: AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 10, ty: 15),
        depth: 1,
        visible: true,
        asset: ReactifyAssetRef(
          id: 'slot.export.asset',
          kind: ReactifyAssetKind.drawing,
          uri: 'reactify://drawing/slot.export',
        ),
        metadata: {
          'drawingColor': '#00F5FF',
          'drawingStrokeWidth': 2.0,
          'drawingStrokes': [
            [
              {'x': 0.0, 'y': 0.0},
              {'x': 12.0, 'y': 8.0},
            ],
          ],
        },
      ),
    ],
  );
}
