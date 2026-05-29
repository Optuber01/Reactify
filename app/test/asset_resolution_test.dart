import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/render_part.dart';

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

  test('resolver tables pass bundled asset coverage checks', () async {
    expect(tables.renderCatalog, isNotEmpty);
    expect(tables.assetManifest.entries, isNotEmpty);
  });

  test(
    'default boy resolves expected head and body families with no missing assets',
    () async {
      final scene = await _sceneForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/default_boy.gc.txt',
      );
      final families = _families(scene);

      expect(families.contains('head_shape'), isTrue);
      expect(families.contains('mouth'), isTrue);
      expect(families.contains('rear_hair'), isTrue);
      expect(families.contains('left_eye'), isTrue);
      expect(families.contains('right_eye'), isTrue);
      expect(families.contains('left_eyebrow'), isTrue);
      expect(families.contains('right_eyebrow'), isTrue);
      expect(families.contains('body_base'), isTrue);
      expect(families.contains('shoulder_front_base'), isTrue);
      expect(families.contains('hand_front_base'), isTrue);
      expect(families.contains('thigh_front_base'), isTrue);
      expect(families.contains('foot_front_base'), isTrue);
      expect(
        scene.parts.every(
          (part) => part.catalogPart.appAssetPath.startsWith('assets/gacha/'),
        ),
        isTrue,
      );
      expect(
        scene.warnings.where(
          (warning) => warning.contains('follow-up validation track'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'body base probe resolves scaffold families without optional clothing or props',
    () async {
      final scene = await _sceneForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/body_base_probe.gc.txt',
      );
      final families = _families(scene);

      expect(families.contains('body_base'), isTrue);
      expect(families.contains('shoulder_front_base'), isTrue);
      expect(families.contains('hand_front_base'), isTrue);
      expect(families.contains('back_shoulder_base'), isTrue);
      expect(families.contains('hand_back_base'), isTrue);
      expect(families.contains('thigh_front_base'), isTrue);
      expect(families.contains('foot_front_base'), isTrue);
      expect(families.contains('thigh_back_base'), isTrue);
      expect(families.contains('foot_back_base'), isTrue);
      expect(families.contains('body_shirt'), isFalse);
      expect(families.contains('body_jacket'), isFalse);
      expect(families.contains('weapon_front'), isFalse);
      expect(families.contains('weapon_back'), isFalse);
      expect(families.contains('shield'), isFalse);
      expect(families.contains('cape'), isFalse);
    },
  );

  test(
    'upper clothing probe resolves torso clothing and belt layers',
    () async {
      final scene = await _sceneForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/upper_clothing_probe.gc.txt',
      );
      final families = _families(scene);

      expect(families.contains('body_shirt'), isTrue);
      expect(families.contains('body_jacket'), isTrue);
      expect(families.contains('belt1'), isTrue);
      expect(families.contains('belt2'), isTrue);
      expect(families.contains('belt_shirt'), isTrue);
      expect(families.contains('belt_jacket'), isTrue);
      expect(families.contains('cape'), isFalse);
      expect(families.contains('weapon_front'), isFalse);
    },
  );

  test(
    'arm layers probe resolves sleeve shoulder glove and wrist layers on both sides',
    () async {
      final scene = await _sceneForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/arm_layers_probe.gc.txt',
      );
      final families = _families(scene);

      expect(families.contains('shoulder_front'), isTrue);
      expect(families.contains('upper_sleeve_front'), isTrue);
      expect(families.contains('lower_sleeve_front'), isTrue);
      expect(families.contains('glove_front'), isTrue);
      expect(families.contains('wrist_front'), isTrue);
      expect(families.contains('shoulder_back'), isTrue);
      expect(families.contains('upper_sleeve_back'), isTrue);
      expect(families.contains('lower_sleeve_back'), isTrue);
      expect(families.contains('glove_back'), isTrue);
      expect(families.contains('wrist_back'), isTrue);
      expect(families.contains('shoe_front'), isFalse);
      expect(families.contains('weapon_front'), isFalse);
    },
  );

  test(
    'lower clothing probe resolves pants socks shoes and knees on both sides',
    () async {
      final scene = await _sceneForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/lower_clothing_probe.gc.txt',
      );
      final families = _families(scene);

      expect(families.contains('body_pants'), isTrue);
      expect(families.contains('thigh_pants_front'), isTrue);
      expect(families.contains('thigh_socks_front'), isTrue);
      expect(families.contains('foot_pants_front'), isTrue);
      expect(families.contains('foot_socks_front'), isTrue);
      expect(families.contains('shoe_front'), isTrue);
      expect(families.contains('knee_front'), isTrue);
      expect(families.contains('thigh_pants_back'), isTrue);
      expect(families.contains('thigh_socks_back'), isTrue);
      expect(families.contains('foot_pants_back'), isTrue);
      expect(families.contains('foot_socks_back'), isTrue);
      expect(families.contains('shoe_back'), isTrue);
      expect(families.contains('knee_back'), isTrue);
      expect(families.contains('cape'), isFalse);
      expect(families.contains('weapon_front'), isFalse);
    },
  );

  test('outerwear probe resolves scarf cape wings and tail layers', () async {
    final scene = await _sceneForFixture(
      parser: parser,
      renderer: renderer,
      fixtureAsset: 'fixtures/outerwear_probe.gc.txt',
    );
    final families = _families(scene);

    expect(families.contains('scarf1'), isTrue);
    expect(families.contains('scarf2'), isTrue);
    expect(families.contains('cape'), isTrue);
    expect(families.contains('wings1'), isTrue);
    expect(families.contains('wings2'), isTrue);
    expect(families.contains('tail'), isTrue);
    expect(families.contains('weapon_front'), isFalse);
    expect(families.contains('shield'), isFalse);
  });

  test('props probe resolves shield and front/back weapon layers', () async {
    final scene = await _sceneForFixture(
      parser: parser,
      renderer: renderer,
      fixtureAsset: 'fixtures/props_probe.gc.txt',
    );
    final families = _families(scene);

    expect(families.contains('weapon_front'), isTrue);
    expect(families.contains('weapon_back'), isTrue);
    expect(families.contains('shield'), isTrue);
    expect(families.contains('cape'), isFalse);
    expect(families.contains('tail'), isFalse);
  });

  test(
    'non-default headflip uses source-backed outer placements without the old fallback warnings',
    () async {
      final code = await rootBundle.loadString('fixtures/default_boy.gc.txt');
      final state = parser.parse(code);
      final baselineScene = await renderer.buildScene(state);
      final followUpScene = await renderer.buildScene(
        GachaCharacterState(
          rawFields: state.rawFields,
          metadataFields: state.metadataFields,
          numericFields: {...state.numericFields, 'headflip': 2, 'pose': 2},
          colorFields: state.colorFields,
        ),
      );

      expect(
        followUpScene.warnings.any(
          (warning) => warning.contains('Head flip variants remain'),
        ),
        isFalse,
      );
      expect(
        followUpScene.warnings.any(
          (warning) => warning.contains('Pose wrapper placement is currently'),
        ),
        isFalse,
      );
      final baselineHead = baselineScene.parts
          .where((part) => part.catalogPart.family == 'head_shape')
          .toList();
      final followUpHead = followUpScene.parts
          .where((part) => part.catalogPart.family == 'head_shape')
          .toList();
      expect(baselineHead, isNotEmpty);
      expect(followUpHead, isNotEmpty);
      expect(
        followUpHead.first.worldTransform.tx !=
                baselineHead.first.worldTransform.tx ||
            followUpHead.first.worldTransform.ty !=
                baselineHead.first.worldTransform.ty ||
            followUpHead.first.worldTransform.a !=
                baselineHead.first.worldTransform.a ||
            followUpHead.first.worldTransform.b !=
                baselineHead.first.worldTransform.b ||
            followUpHead.first.worldTransform.c !=
                baselineHead.first.worldTransform.c ||
            followUpHead.first.worldTransform.d !=
                baselineHead.first.worldTransform.d,
        isTrue,
      );
    },
  );

  test(
    'pose-side back hair and ponytail probes resolve the source-backed parts',
    () async {
      final backHairScene = await _sceneForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/back_hair_probe.gc.txt',
      );
      final backHairFamilies = _families(backHairScene);
      expect(backHairFamilies.contains('back_hair'), isTrue);
      expect(backHairFamilies.contains('ponytail'), isFalse);
      expect(
        backHairScene.parts.where(
          (part) => part.catalogPart.family == 'back_hair',
        ),
        hasLength(6),
      );
      expect(backHairScene.warnings, isNot(contains('source-verified')));

      final ponytailScene = await _sceneForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/ponytail_probe.gc.txt',
      );
      final ponytailFamilies = _families(ponytailScene);
      expect(ponytailFamilies.contains('back_hair'), isTrue);
      expect(ponytailFamilies.contains('ponytail'), isTrue);
      expect(
        ponytailScene.parts.where(
          (part) => part.catalogPart.family == 'back_hair',
        ),
        hasLength(6),
      );
      expect(
        ponytailScene.parts.where(
          (part) => part.catalogPart.family == 'ponytail',
        ),
        hasLength(3),
      );
      expect(ponytailScene.warnings, isNot(contains('source-verified')));
      expect(
        ponytailScene.parts.any((part) => part.catalogPart.leafId == '4756'),
        isFalse,
      );
    },
  );
}

Future<ResolvedScene> _sceneForFixture({
  required GachaCodeParser parser,
  required CharacterRenderer renderer,
  required String fixtureAsset,
}) async {
  final code = await rootBundle.loadString(fixtureAsset);
  return renderer.buildScene(parser.parse(code));
}

Set<String> _families(ResolvedScene scene) {
  return scene.parts.map((part) => part.catalogPart.family).toSet();
}
