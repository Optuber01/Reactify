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

      expect(baseParts, isNotEmpty);
      expect(
        bridgeParts
            .where((part) => part.catalogPart.family.contains('hair'))
            .toList(),
        isEmpty,
      );
      expect(bridgeParts.first.localTransform.tx, isNotNull);
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
}
