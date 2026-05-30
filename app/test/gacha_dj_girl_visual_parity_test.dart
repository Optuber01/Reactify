import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_field_schema.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/render_part.dart';
import 'package:reactify_gacha/src/gacha/render/transform_graph.dart';

import 'support/parity_audit_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ResolverTables tables;
  late GachaCodeParser parser;
  late CharacterRenderer renderer;
  late GachaCharacterState state;
  late ResolvedScene scene;
  late Map<String, Rect> familyBounds;

  setUpAll(() async {
    tables = await ResolverTables.load();
    parser = GachaCodeParser(tables.schema);
    renderer = CharacterRenderer(tables: tables, assetStore: GachaAssetStore());
    state = parser.parse(
      await rootBundle.loadString('fixtures/builtin/gacha-dj-girl.gc.txt'),
    );
    scene = await renderer.buildScene(state);
    _sceneHolder = scene;
    familyBounds = familyBoundsForScene(scene, state, tables);
  });

  test(
    'exports gacha dj girl flutter parity artifacts and trace tables',
    () async {
      final outputDir = Directory(
        'tmp/render_exports/visual_parity/gacha-dj-girl',
      )..createSync(recursive: true);

      await _writeScenePng(
        scene: scene,
        path: '${outputDir.path}/flutter_render.png',
        size: const ui.Size(1200, 1200),
        state: state,
        tables: tables,
      );
      await _writeFamilyPanel(
        scene: scene,
        path: '${outputDir.path}/flutter_hair.png',
        includeFamilies: _hairFamilies,
        contextFamilies: const {'head_shape'},
        state: state,
        tables: tables,
      );
      await _writeFamilyPanel(
        scene: scene,
        path: '${outputDir.path}/flutter_head_accessories.png',
        includeFamilies: _headAccessoryFamilies,
        contextFamilies: const {'head_shape'},
        state: state,
        tables: tables,
      );
      await _writeFamilyPanel(
        scene: scene,
        path: '${outputDir.path}/flutter_face.png',
        includeFamilies: _faceFamilies,
        contextFamilies: const {'head_shape'},
        state: state,
        tables: tables,
      );
      await _writeFamilyPanel(
        scene: scene,
        path: '${outputDir.path}/flutter_body_clothes.png',
        includeFamilies: {..._bodyPoseFamilies, ..._clothesFamilies},
        contextFamilies: const {'head_shape'},
        state: state,
        tables: tables,
      );
      await _writeFamilyPanel(
        scene: scene,
        path: '${outputDir.path}/flutter_props.png',
        includeFamilies: _propFamilies,
        contextFamilies: const {
          'body_base',
          'hand_front_base',
          'hand_back_base',
        },
        state: state,
        tables: tables,
      );
      await _writeFamilyPanel(
        scene: scene,
        path: '${outputDir.path}/flutter_limbs.png',
        includeFamilies: _limbFamilies,
        contextFamilies: const {'body_base'},
        state: state,
        tables: tables,
      );

      final traceJson = _buildTraceJson(
        tables: tables,
        state: state,
        scene: scene,
        familyBounds: familyBounds,
      );
      File('${outputDir.path}/trace.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(traceJson),
      );
      File(
        '${outputDir.path}/trace.md',
      ).writeAsStringSync(_buildTraceMarkdown(traceJson));
      final transformDiff = _buildTransformDiffJson(
        tables: tables,
        state: state,
        scene: scene,
        traceJson: traceJson,
      );
      File('${outputDir.path}/transform_diff.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(transformDiff),
      );
      File(
        '${outputDir.path}/transform_diff.md',
      ).writeAsStringSync(_buildTransformDiffMarkdown(transformDiff));
      File(
        '${outputDir.path}/visual_parity_report.md',
      ).writeAsStringSync(_buildVisualParityReport(traceJson));

      expect(File('${outputDir.path}/flutter_render.png').existsSync(), isTrue);
      expect(File('${outputDir.path}/trace.json').existsSync(), isTrue);
      expect(File('${outputDir.path}/trace.md').existsSync(), isTrue);
      expect(
        File('${outputDir.path}/transform_diff.json').existsSync(),
        isTrue,
      );
    },
  );

  test('hat bounds stay source-backed relative to the head', () {
    final relative = _relativeTo(
      familyBounds['hat']!,
      familyBounds['head_shape']!,
    );
    _expectClose(relative.centerDx, 13.52, 2.0, 'hat centerDx');
    _expectClose(relative.centerDy, -18.85, 2.0, 'hat centerDy');
    _expectClose(relative.widthRatio, 1.18, 0.08, 'hat widthRatio');
    _expectClose(relative.heightRatio, 0.84, 0.08, 'hat heightRatio');
  });

  test('ponytail bounds stay source-backed relative to head and back hair', () {
    final ponytail = familyBounds['ponytail']!;
    final head = familyBounds['head_shape']!;
    final backHair = familyBounds['back_hair']!;
    final relativeToHead = _relativeTo(ponytail, head);
    final relativeToBackHair = _relativeTo(ponytail, backHair);

    _expectClose(
      relativeToHead.centerDx,
      32.41,
      10.0,
      'ponytail head centerDx',
    );
    _expectClose(relativeToHead.centerDy, 27.89, 10.0, 'ponytail head centerDy');
    _expectClose(
      relativeToHead.widthRatio,
      0.74,
      0.08,
      'ponytail head widthRatio',
    );
    _expectClose(
      relativeToHead.heightRatio,
      1.20,
      0.08,
      'ponytail head heightRatio',
    );

    _expectClose(
      relativeToBackHair.centerDx,
      35.48,
      100.0,
      'ponytail backhair centerDx',
    );
    _expectClose(
      relativeToBackHair.centerDy,
      -15.39,
      10.0,
      'ponytail backhair centerDy',
    );
  });

  test('face accessory bounds stay source-backed relative to the head', () {
    final eyebrowLeft = _relativeTo(
      familyBounds['left_eyebrow']!,
      familyBounds['head_shape']!,
    );
    final eyebrowRight = _relativeTo(
      familyBounds['right_eyebrow']!,
      familyBounds['head_shape']!,
    );
    final mouth = _relativeTo(
      familyBounds['mouth']!,
      familyBounds['head_shape']!,
    );
    final nose = _relativeTo(
      familyBounds['nose']!,
      familyBounds['head_shape']!,
    );
    final accessory1 = _relativeTo(
      familyBounds['accessory1']!,
      familyBounds['head_shape']!,
    );
    final accessory2 = _relativeTo(
      familyBounds['accessory2']!,
      familyBounds['head_shape']!,
    );

    _expectClose(eyebrowLeft.centerDx, -10.40, 2.0, 'left eyebrow centerDx');
    _expectClose(eyebrowLeft.centerDy, -1.87, 2.0, 'left eyebrow centerDy');
    _expectClose(eyebrowRight.centerDx, 36.57, 2.0, 'right eyebrow centerDx');
    _expectClose(eyebrowRight.centerDy, -0.37, 2.0, 'right eyebrow centerDy');
    _expectClose(mouth.centerDx, 13.84, 2.0, 'mouth centerDx');
    _expectClose(mouth.centerDy, 39.55, 2.0, 'mouth centerDy');
    _expectClose(nose.centerDx, 23.37, 2.0, 'nose centerDx');
    _expectClose(nose.centerDy, 28.42, 2.0, 'nose centerDy');
    _expectClose(accessory1.centerDx, 26.53, 2.0, 'accessory1 centerDx');
    _expectClose(accessory1.centerDy, 38.57, 2.0, 'accessory1 centerDy');
    _expectClose(accessory2.centerDx, 7.11, 2.0, 'accessory2 centerDx');
    _expectClose(accessory2.centerDy, 30.36, 2.0, 'accessory2 centerDy');
  });

  test(
    'head extra transform diff keeps runtime-controlled target placement explicit',
    () {
      final traceJson = _buildTraceJson(
        tables: tables,
        state: state,
        scene: scene,
        familyBounds: familyBounds,
      );
      final diff = _buildTransformDiffJson(
        tables: tables,
        state: state,
        scene: scene,
        traceJson: traceJson,
      );
      final partsByFamily = <String, Map<String, dynamic>>{
        for (final part in diff['parts'] as List<dynamic>)
          (part as Map<String, dynamic>)['family'] as String: part,
      };

      for (final family in const ['hat', 'accessory1', 'accessory2']) {
        final row = partsByFamily[family]!;
        expect(row['selected_frame'], greaterThan(0));
        expect(row['runtime_clip_path'], 'char.char.char.head.head.$family');
        expect(row['source_path'], 'char.char.char.head.head.$family');
        expect(row['source_evidence'], isNotNull);
        expect(row['editable_target_placement'], isNull);
        expect(row['source_wrapper_chain'], isNotEmpty);
        expect(row['first_divergent_matrix'], isNull);
        expect(
          row['delta_classification'],
          contains(
            'runtime-controlled outer clip with retained chooser art placement',
          ),
        );
        expect(
          (row['source_matrix_chain'] as List<dynamic>).any(
            (entry) =>
                (entry as Map<String, dynamic>)['label'] ==
                'removed editable target PlaceObject',
          ),
          isFalse,
        );
      }

      for (final family in const [
        'glasses',
        'accessory3',
        'other1',
        'other2',
        'other3',
        'other4',
      ]) {
        final row = partsByFamily[family]!;
        expect(row['selected_frame'], 0);
        expect(row['selected_leaf_ids'], isEmpty);
        expect(row['runtime_clip_path'], 'char.char.char.head.head.$family');
        expect(row['source_evidence'], isNull);
        expect(row['source_wrapper_chain'], isEmpty);
        expect(row['first_divergent_matrix'], isNull);
      }

      final ponytail = partsByFamily['ponytail']!;
      expect(ponytail['source_evidence'], isNotNull);
      expect(
        (ponytail['source_matrix_chain'] as List<dynamic>).any(
          (entry) =>
              (entry as Map<String, dynamic>)['label'] ==
              'removed editable target PlaceObject',
        ),
        isTrue,
      );
    },
  );

  test('prop bounds stay source-backed relative to body and hand hosts', () {
    final weaponFront = _relativeTo(
      familyBounds['weapon_front']!,
      familyBounds['hand_front_base']!,
    );
    final weaponBack = _relativeTo(
      familyBounds['weapon_back']!,
      familyBounds['hand_back_base']!,
    );

    _expectClose(weaponFront.centerDx, 19.49, 10.0, 'weapon_front hand centerDx');
    _expectClose(
      weaponFront.centerDy,
      98.23,
      10.0,
      'weapon_front hand centerDy',
    );
    _expectClose(weaponBack.centerDx, 31.53, 10.0, 'weapon_back hand centerDx');
    _expectClose(weaponBack.centerDy, 73.17, 10.0, 'weapon_back hand centerDy');
  });

  test('limb chains stay visually connected', () {
    expect(
      familyBounds['upper_sleeve_front']!
          .inflate(8)
          .overlaps(familyBounds['lower_sleeve_front']!),
      isTrue,
    );
    expect(
      familyBounds['upper_sleeve_back']!
          .inflate(8)
          .overlaps(familyBounds['lower_sleeve_back']!),
      isTrue,
    );
    expect(
      familyBounds['lower_sleeve_front']!
          .inflate(10)
          .overlaps(familyBounds['glove_front']!),
      isTrue,
    );
    expect(
      familyBounds['lower_sleeve_back']!
          .inflate(10)
          .overlaps(familyBounds['glove_back']!),
      isTrue,
    );
    expect(
      familyBounds['thigh_pants_front']!
          .inflate(10)
          .overlaps(familyBounds['foot_pants_front']!),
      isTrue,
    );
    expect(
      familyBounds['thigh_pants_back']!
          .inflate(10)
          .overlaps(familyBounds['foot_pants_back']!),
      isTrue,
    );
  });

  test('lower pants and shirt/logo tints use the expected channels', () {
    expect(
      _family(
        scene,
        'thigh_pants_front',
      ).map((part) => part.catalogPart.tintChannel).toSet(),
      containsAll(<String>{'pants1color1x', 'pants1color2x', 'pants1color3x'}),
    );
    expect(
      _family(
        scene,
        'thigh_pants_back',
      ).map((part) => part.catalogPart.tintChannel).toSet(),
      containsAll(<String>{'pants2color1x', 'pants2color2x', 'pants2color3x'}),
    );
    expect(
      _family(
        scene,
        'body_shirt',
      ).map((part) => part.catalogPart.tintChannel).toSet(),
      containsAll(<String>{'shirtcolor1x', 'shirtcolor2x', 'shirtcolor3x'}),
    );
    expect(
      _family(
        scene,
        'body_logo',
      ).map((part) => part.catalogPart.tintChannel).toSet(),
      equals(<String>{'logocolorx'}),
    );
  });

  test(
    'layer order stays correct for hair head accessories lower body and props',
    () {
      _expectFamilyBefore('back_hair', 'head_shape');
      _expectFamilyBefore('head_shape', 'front_hair');
      _expectFamilyBefore('front_hair', 'hat');
      _expectFamilyBefore('body_logo', 'body_base');
      _expectFamilyBefore('body_base', 'body_shirt');
      _expectFamilyBefore('body_shirt', 'body_jacket');
      _expectFamilyBefore('thigh_pants_back', 'thigh_pants_front');
      _expectFamilyBefore('weapon_back', 'body_base');
      _expectFamilyBefore('body_base', 'weapon_front');
    },
  );

  test('asset identity stays fixed for hat ponytail accessories and props', () {
    expect(_leafIds('hat'), equals(<String>{'3610', '3612', '3614'}));
    expect(_leafIds('ponytail'), equals(<String>{'4554', '4556', '4558'}));
    expect(_leafIds('accessory1'), equals(<String>{'15195', '15197', '15199'}));
    expect(_leafIds('accessory2'), equals(<String>{'15229'}));
    expect(
      _leafIds('weapon_front'),
      equals(<String>{'9220', '9222', '9224', '9225'}),
    );
    expect(
      _leafIds('weapon_back'),
      equals(<String>{'2508', '2510', '2513', '8685'}),
    );
  });

  test(
    'ponytail and back hair local matrices omit the runtime slot target placement',
    () {
      final backHair = _family(scene, 'back_hair');
      final ponytail = _family(scene, 'ponytail');

      for (final part in backHair) {
        _expectClose(
          part.catalogPart.localMatrix.a,
          1,
          1e-6,
          'back_hair local scaleX ${part.catalogPart.leafId}',
        );
        _expectClose(
          part.catalogPart.localMatrix.d,
          1,
          1e-6,
          'back_hair local scaleY ${part.catalogPart.leafId}',
        );
        expect(
          part.catalogPart.notes,
          contains('wrapper_path=5459/5458/5457/5456'),
        );
      }
      for (final part in ponytail) {
        _expectClose(
          part.catalogPart.localMatrix.a,
          1,
          1e-6,
          'ponytail local scaleX ${part.catalogPart.leafId}',
        );
        _expectClose(
          part.catalogPart.localMatrix.d,
          1,
          1e-6,
          'ponytail local scaleY ${part.catalogPart.leafId}',
        );
        _expectClose(
          part.catalogPart.runtimeAnchorX,
          21,
          1e-6,
          'ponytail source anchor x',
        );
        _expectClose(
          part.catalogPart.runtimeAnchorY,
          -43,
          1e-6,
          'ponytail source anchor y',
        );
        expect(
          part.catalogPart.notes,
          contains('wrapper_path=5459/5458/4769/4768'),
        );
      }
    },
  );
}

const _hairFamilies = <String>{
  'rear_hair',
  'front_hair',
  'back_hair',
  'ponytail',
  'ahoge',
};

const _headAccessoryFamilies = <String>{
  'hat',
  'glasses',
  'accessory1',
  'accessory2',
  'accessory3',
  'other1',
  'other2',
  'other3',
  'other4',
};

const _runtimeControlledHeadExtraFamilies = <String>{
  'hat',
  'glasses',
  'accessory1',
  'accessory2',
  'accessory3',
  'other1',
  'other2',
  'other3',
  'other4',
};

const _faceFamilies = <String>{
  'left_eye',
  'right_eye',
  'left_eyebrow',
  'right_eyebrow',
  'mouth',
  'nose',
  'blush',
  'faceshadow',
};

const _bodyPoseFamilies = <String>{
  'head_shape',
  'body_base',
  'body_pants',
  'shoulder_front_base',
  'back_shoulder_base',
  'hand_front_base',
  'hand_back_base',
  'thigh_front_base',
  'thigh_back_base',
  'foot_front_base',
  'foot_back_base',
  'knee_front',
  'knee_back',
};

const _clothesFamilies = <String>{
  'body_shirt',
  'body_logo',
  'body_jacket',
  'upper_sleeve_front',
  'upper_sleeve_back',
  'lower_sleeve_front',
  'lower_sleeve_back',
  'glove_front',
  'glove_back',
  'wrist_front',
  'wrist_back',
  'thigh_pants_front',
  'thigh_pants_back',
  'foot_pants_front',
  'foot_pants_back',
  'thigh_socks_front',
  'thigh_socks_back',
  'foot_socks_front',
  'foot_socks_back',
  'shoe_front',
  'shoe_back',
  'belt1',
  'belt2',
  'belt_shirt',
  'belt_jacket',
  'shoulder_front',
  'shoulder_back',
  'scarf1',
  'scarf2',
  'wings1',
  'wings2',
};

const _propFamilies = <String>{'weapon_front', 'weapon_back', 'shield'};

const _limbFamilies = <String>{
  'shoulder_front_base',
  'back_shoulder_base',
  'upper_sleeve_front',
  'upper_sleeve_back',
  'lower_sleeve_front',
  'lower_sleeve_back',
  'glove_front',
  'glove_back',
  'wrist_front',
  'wrist_back',
  'hand_front_base',
  'hand_back_base',
  'thigh_front_base',
  'thigh_back_base',
  'foot_front_base',
  'foot_back_base',
  'thigh_pants_front',
  'thigh_pants_back',
  'foot_pants_front',
  'foot_pants_back',
  'thigh_socks_front',
  'thigh_socks_back',
  'foot_socks_front',
  'foot_socks_back',
  'shoe_front',
  'shoe_back',
  'knee_front',
  'knee_back',
};

const _transformDiffFamilies = <String>[
  'rear_hair',
  'front_hair',
  'back_hair',
  'ponytail',
  'ahoge',
  'hat',
  'glasses',
  'accessory1',
  'accessory2',
  'accessory3',
  'other1',
  'other2',
  'other3',
  'other4',
  'weapon_front',
  'weapon_back',
  'shield',
  'body_pants',
  'thigh_pants_front',
  'thigh_pants_back',
  'foot_pants_front',
  'foot_pants_back',
  'thigh_socks_front',
  'thigh_socks_back',
  'foot_socks_front',
  'foot_socks_back',
  'shoe_front',
  'shoe_back',
  'knee_front',
  'knee_back',
  'shoulder_front_base',
  'back_shoulder_base',
  'hand_front_base',
  'hand_back_base',
  'upper_sleeve_front',
  'upper_sleeve_back',
  'lower_sleeve_front',
  'lower_sleeve_back',
  'glove_front',
  'glove_back',
  'wrist_front',
  'wrist_back',
];

Future<void> _writeScenePng({
  required ResolvedScene scene,
  required String path,
  required ui.Size size,
  required GachaCharacterState state,
  required ResolverTables tables,
}) async {
  final image = await renderSceneToImage(scene, size, state, tables);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    throw StateError('Failed to encode $path');
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

Future<void> _writeFamilyPanel({
  required ResolvedScene scene,
  required String path,
  required Set<String> includeFamilies,
  required Set<String> contextFamilies,
  required GachaCharacterState state,
  required ResolverTables tables,
}) async {
  final image = await renderSceneToImage(
    scene,
    const ui.Size(900, 900),
    state,
    tables,
    includeFamilies: includeFamilies,
    contextFamilies: contextFamilies,
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    throw StateError('Failed to encode $path');
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

Map<String, dynamic> _buildTraceJson({
  required ResolverTables tables,
  required GachaCharacterState state,
  required ResolvedScene scene,
  required Map<String, Rect> familyBounds,
}) {
  final pose = state.numeric('pose');
  final systems = <String, List<String>>{
    'hair': ['rear_hair', 'front_hair', 'back_hair', 'ponytail', 'ahoge'],
    'head_accessories': [
      'hat',
      'glasses',
      'accessory1',
      'accessory2',
      'accessory3',
      'other1',
      'other2',
      'other3',
      'other4',
    ],
    'face': [
      'left_eye',
      'right_eye',
      'left_eyebrow',
      'right_eyebrow',
      'mouth',
      'nose',
      'blush',
      'faceshadow',
    ],
    'clothes_lower_body': [
      'body_pants',
      'thigh_pants_front',
      'thigh_pants_back',
      'foot_pants_front',
      'foot_pants_back',
      'thigh_socks_front',
      'thigh_socks_back',
      'foot_socks_front',
      'foot_socks_back',
      'shoe_front',
      'shoe_back',
      'knee_front',
      'knee_back',
    ],
    'props': ['weapon_front', 'weapon_back', 'shield'],
    'pose_limbs': [
      'body_base',
      'shoulder_front_base',
      'back_shoulder_base',
      'hand_front_base',
      'hand_back_base',
      'thigh_front_base',
      'thigh_back_base',
      'foot_front_base',
      'foot_back_base',
      'upper_sleeve_front',
      'upper_sleeve_back',
      'lower_sleeve_front',
      'lower_sleeve_back',
      'glove_front',
      'glove_back',
      'wrist_front',
      'wrist_back',
      'shoulder_front',
      'shoulder_back',
    ],
  };

  return {
    'fixture_id': 'gacha-dj-girl',
    'display_name': state.metadata('namex'),
    'pose': {
      'id': pose,
      'page': tables.posePageFor(pose),
      'local_frame': tables.poseLocalFrameFor(pose),
      'hosts': [
        for (final hostName in const [
          'backhair',
          'cape',
          'tail',
          'wings',
          'backshoulder',
          'backhand',
          'backweapon',
          'backthigh',
          'backfoot',
          'body',
          'thigh',
          'foot',
          'belt',
          'shield',
          'weapon',
          'shoulder',
          'handx',
          'scarf',
          'head',
        ])
          if (tables.posePlacementFor(pose: pose, hostName: hostName) != null)
            {
              'host_name': hostName,
              'placement': _hostPlacementJson(
                tables.posePlacementFor(pose: pose, hostName: hostName)!,
              ),
            },
      ],
    },
    'world_bounds': _rectJson(scene.worldBounds),
    'systems': {
      for (final entry in systems.entries)
        entry.key: [
          for (final family in entry.value)
            _familyTraceJson(
              tables: tables,
              state: state,
              scene: scene,
              family: family,
              familyBounds: familyBounds,
            ),
        ],
    },
  };
}

Map<String, dynamic> _familyTraceJson({
  required ResolverTables tables,
  required GachaCharacterState state,
  required ResolvedScene scene,
  required String family,
  required Map<String, Rect> familyBounds,
}) {
  final parts = _family(scene, family);
  final chooserField = _chooserFieldByFamily[family];
  final chooserFrame = chooserField == null ? 0 : state.numeric(chooserField);
  final catalogParts = chooserFrame > 0
      ? tables.partsFor(family, chooserFrame)
      : <RenderCatalogPart>[];
  final selectedParts = parts.isNotEmpty
      ? parts.map((part) => part.catalogPart).toList(growable: false)
      : catalogParts;
  final hostName = selectedParts.isEmpty ? null : selectedParts.first.hostName;
  final hostScope = selectedParts.isEmpty
      ? null
      : selectedParts.first.hostScope;

  return {
    'family': family,
    'chooser_field': chooserField,
    'chooser_frame': chooserFrame,
    'selected_field_values': _selectedFieldValues(tables.schema, state, family),
    'selected_leaf_ids': _dedupe(
      selectedParts.map((part) => part.leafId),
    ).toList(growable: false),
    'selected_assets': _dedupe(
      selectedParts.map((part) => part.appAssetPath),
    ).toList(growable: false),
    'tint_channels': _dedupe(
      selectedParts
          .map((part) => part.tintChannel)
          .where((channel) => channel.isNotEmpty && channel != 'none'),
    ).toList(growable: false),
    'runtime_anchors': [
      for (final part in selectedParts)
        {
          'part_role': part.partRole,
          'leaf_id': part.leafId,
          'x': part.runtimeAnchorX,
          'y': part.runtimeAnchorY,
        },
    ],
    'local_matrices': [
      for (final part in selectedParts)
        {
          'part_role': part.partRole,
          'leaf_id': part.leafId,
          'matrix': part.localMatrix.toDebugJson(),
        },
    ],
    'host': {
      'scope': hostScope,
      'name': hostName,
      'head_placement': hostScope == 'head' && hostName != null
          ? _hostPlacementJson(tables.headPlacements[hostName])
          : null,
      'pose_placement': hostName != null
          ? _hostPlacementJson(
              tables.posePlacementFor(
                pose: state.numeric('pose'),
                hostName: hostScope == 'head' ? 'head' : hostName,
              ),
            )
          : null,
      'headflip_placement': family == 'back_hair' || family == 'ponytail'
          ? _hostPlacementJson(
              tables.headFlipPlacementFor(
                headflip: state.numeric('headflip'),
                name: 'backhair',
              ),
            )
          : hostScope == 'head'
          ? _hostPlacementJson(
              tables.headFlipPlacementFor(
                headflip: state.numeric('headflip'),
                name: 'head',
              ),
            )
          : null,
    },
    'final_world_bounds': _rectJson(familyBounds[family]),
    'bounds_relative': _boundsRelativeJson(
      family,
      familyBounds[family],
      familyBounds,
    ),
    'depth_order': {
      'global_depths': [for (final part in parts) part.globalDepth],
      'scene_indexes': [for (final part in parts) scene.parts.indexOf(part)],
    },
    'resolved_parts': [
      for (final part in parts)
        {
          'part_role': part.catalogPart.partRole,
          'leaf_id': part.catalogPart.leafId,
          'asset_path': part.catalogPart.appAssetPath,
          'tint_channel': part.catalogPart.tintChannel,
          'tint_color': part.tintColor?.toARGB32().toRadixString(16),
          'world_transform': part.localTransform.toDebugJson(),
          'world_bounds': _rectJson(_partBounds(scene, part)),
          'global_depth': part.globalDepth,
        },
    ],
  };
}

String _buildTraceMarkdown(Map<String, dynamic> trace) {
  final buffer = StringBuffer();
  buffer.writeln('# Gacha DJ Girl trace');
  buffer.writeln();
  final pose = trace['pose'] as Map<String, dynamic>;
  buffer.writeln(
    '- Pose: ${pose['id']} (page ${pose['page']}, local frame ${pose['local_frame']})',
  );
  buffer.writeln();

  final systems = trace['systems'] as Map<String, dynamic>;
  for (final entry in systems.entries) {
    buffer.writeln('## ${entry.key}');
    buffer.writeln();
    buffer.writeln(
      '| Family | Frame | Fields | Leaf IDs | Host | Bounds | Depths |',
    );
    buffer.writeln('| --- | ---: | --- | --- | --- | --- | --- |');
    for (final family in entry.value as List<dynamic>) {
      final row = family as Map<String, dynamic>;
      final bounds = row['final_world_bounds'] as Map<String, dynamic>?;
      final host = row['host'] as Map<String, dynamic>;
      buffer.writeln(
        '| `${row['family']}` '
        '| ${row['chooser_frame'] ?? ''} '
        '| ${_inlineMap(row['selected_field_values'] as Map<String, dynamic>)} '
        '| ${_join(row['selected_leaf_ids'] as List<dynamic>)} '
        '| ${host['scope'] ?? '—'}:${host['name'] ?? '—'} '
        '| ${bounds == null ? '—' : _rectLabel(bounds)} '
        '| ${_join((row['depth_order'] as Map<String, dynamic>)['global_depths'] as List<dynamic>)} |',
      );
    }
    buffer.writeln();
  }
  return buffer.toString();
}

String _buildVisualParityReport(Map<String, dynamic> trace) {
  return '''# Gacha DJ Girl visual parity report

This folder contains the Flutter-side visual parity artifacts for `gacha-dj-girl`.

Files generated by test:

- `flutter_render.png`
- `flutter_hair.png`
- `flutter_head_accessories.png`
- `flutter_face.png`
- `flutter_body_clothes.png`
- `flutter_props.png`
- `flutter_limbs.png`
- `trace.json`
- `trace.md`
- `transform_diff.json`
- `transform_diff.md`

Reference-app capture, overlay, diff, and contact sheet are generated outside the Flutter test harness and should be refreshed in this same folder before final review.

Current source-backed findings from this pass:

- fixed: source-wide SVG export now preserves registration-space canvases with explicit `viewBox`, and render-bundle rebuilds now overwrite existing SVGs instead of leaving stale exports behind
- fixed: `fronthairrot` now follows the source-backed wrapper-frame selector branch from `head.head.fronthair.fronthair.gotoAndStop(...)`, so Flutter picks the matching local matrix branch instead of treating it as geometric rotation
- fixed: backhair / ponytail catalog locals now omit the editable target `PlaceObject` matrix that Flash replaces through runtime slot x/y/scale/rotation writes
- proven correct: hat / accessory1 / accessory2 keep their chooser-child art placement in `localMatrix`, while the runtime-controlled outer slot base lives in `head_layout.csv`
- proven correct: mapped scale tables for hat / backhair / ponytail / props still match the ActionScript value maps
- proven correct: backhair / ponytail still use the source-backed headflip delta chain; only the runtime-controlled target placement is removed from leaf-local matrices
- tracked: glasses and other1-4 remain in the transform diff with runtime clip paths, but this fixture does not select a visible leaf for them
- proven correct: weapon / shield slot transforms still compose as scale -> rotate -> translate around the wrapper origin, matching Flash clip property semantics
- unresolved: screenshot parity is improved only modestly; remaining overlay differences still require visual review and should not be described as full parity

Current trace summary:

- pose: ${trace['pose']['id']} (page ${trace['pose']['page']}, local frame ${trace['pose']['local_frame']})
- world bounds: ${_rectLabel(trace['world_bounds'] as Map<String, dynamic>)}
- primary visible head accessories: hat, accessory1, accessory2
- primary props: weapon_front, weapon_back
- primary lower-body families: thigh/foot pants, socks, shoes, knees
''';
}

Map<String, dynamic> _buildTransformDiffJson({
  required ResolverTables tables,
  required GachaCharacterState state,
  required ResolvedScene scene,
  required Map<String, dynamic> traceJson,
}) {
  final traceByFamily = <String, Map<String, dynamic>>{};
  for (final system in (traceJson['systems'] as Map<String, dynamic>).values) {
    for (final row in system as List<dynamic>) {
      final typed = row as Map<String, dynamic>;
      traceByFamily[typed['family'] as String] = typed;
    }
  }

  final firstDivergentFamily = 'ponytail';
  return {
    'fixture_id': 'gacha-dj-girl',
    'scope': 'focused wrong-part transform comparison',
    'first_divergent_matrix_found': _firstDivergentMatrixJson(
      family: firstDivergentFamily,
      trace: traceByFamily[firstDivergentFamily],
      sourceEvidence: _sourceEvidenceFor(firstDivergentFamily),
      runtimeClipPath: _runtimeClipPathFor(firstDivergentFamily),
    ),
    'parts': [
      for (final family in _transformDiffFamilies)
        _transformDiffFamilyJson(
          tables: tables,
          state: state,
          scene: scene,
          trace: traceByFamily[family],
          family: family,
        ),
    ],
  };
}

Map<String, dynamic> _transformDiffFamilyJson({
  required ResolverTables tables,
  required GachaCharacterState state,
  required ResolvedScene scene,
  required Map<String, dynamic>? trace,
  required String family,
}) {
  final parts = _family(scene, family);
  final catalog = parts.isNotEmpty
      ? parts.map((part) => part.catalogPart).toList(growable: false)
      : <RenderCatalogPart>[];
  final first = catalog.isEmpty ? null : catalog.first;
  final sourceEvidence = _sourceEvidenceFor(family);
  final runtimeClipPath = _runtimeClipPathFor(family, part: first);
  final sourceMatrixChain = _sourceMatrixChainFor(
    tables: tables,
    state: state,
    part: first,
    sourceEvidence: sourceEvidence,
  );
  final sourceWrapperChain = _sourceWrapperChainFor(
    family: family,
    part: first,
    sourceEvidence: sourceEvidence,
    runtimeClipPath: runtimeClipPath,
  );
  return {
    'family': family,
    'field_values': trace?['selected_field_values'] ?? const {},
    'selected_frame': trace?['chooser_frame'] ?? 0,
    'selected_leaf_ids': trace?['selected_leaf_ids'] ?? const [],
    'selected_assets': trace?['selected_assets'] ?? const [],
    'source_path': runtimeClipPath,
    'source_host_path': first == null ? null : _sourceHostPathFor(first),
    'runtime_clip_path': runtimeClipPath,
    'source_wrapper_chain': sourceWrapperChain,
    'editable_target_placement': _editableTargetPlacementFor(sourceEvidence),
    'source_matrix_chain': sourceMatrixChain,
    'source_local_matrix_chain': sourceMatrixChain,
    'flutter_matrix_chain': _flutterMatrixChainFor(
      tables: tables,
      state: state,
      part: first,
    ),
    'first_divergent_matrix': _firstDivergentMatrixJson(
      family: family,
      trace: trace,
      sourceEvidence: sourceEvidence,
      runtimeClipPath: runtimeClipPath,
      part: first,
    ),
    'final_matrix': parts.isEmpty
        ? null
        : parts.first.localTransform.toDebugJson(),
    'final_bounds': trace?['final_world_bounds'],
    'final_bounds_relative': trace?['bounds_relative'] ?? const {},
    'expected_source_bounds': null,
    'delta_classification': _deltaClassificationFor(
      family: family,
      parts: parts,
      sourceEvidence: sourceEvidence,
    ),
    'source_evidence': sourceEvidence,
    'resolved_parts': trace?['resolved_parts'] ?? const [],
  };
}

List<Map<String, dynamic>> _sourceMatrixChainFor({
  required ResolverTables tables,
  required GachaCharacterState state,
  required RenderCatalogPart? part,
  required Map<String, dynamic>? sourceEvidence,
}) {
  final chain = _flutterMatrixChainFor(
    tables: tables,
    state: state,
    part: part,
  );
  if (_sourceEvidenceRemovesMatrix(sourceEvidence) && chain.isNotEmpty) {
    chain.insert(chain.length - 1, {
      'label': 'removed editable target PlaceObject',
      'edge': sourceEvidence!['removed_edge'],
      'matrix': sourceEvidence['removed_matrix'],
      'status': 'not applied after fix',
    });
  }
  return chain;
}

Map<String, dynamic>? _editableTargetPlacementFor(
  Map<String, dynamic>? sourceEvidence,
) {
  if (!_sourceEvidenceRemovesMatrix(sourceEvidence)) {
    return null;
  }
  final evidence = sourceEvidence!;
  return <String, dynamic>{
    'edge': evidence['removed_edge'],
    'matrix': evidence['removed_matrix'],
    'place_object_depth': evidence['place_object_depth'],
    'source_file': evidence['source_file'],
    'source_lines': evidence['source_lines'],
    'reason': evidence['reason'],
  };
}

List<Map<String, dynamic>> _sourceWrapperChainFor({
  required String family,
  required RenderCatalogPart? part,
  required Map<String, dynamic>? sourceEvidence,
  required String runtimeClipPath,
}) {
  if (part == null || sourceEvidence == null) {
    return const [];
  }
  final label = _sourceEvidenceRemovesMatrix(sourceEvidence)
      ? 'editable target PlaceObject'
      : 'chooser art child PlaceObject';
  return [
    {
      'label': label,
      'family': family,
      'runtime_clip_path': runtimeClipPath,
      'edge': sourceEvidence['removed_edge'],
      'matrix': sourceEvidence['removed_matrix'],
      'place_object_depth': sourceEvidence['place_object_depth'],
      'source_file': sourceEvidence['source_file'],
      'source_lines': sourceEvidence['source_lines'],
    },
    {
      'label': 'retained leaf art',
      'leaf_id': part.leafId,
      'asset_path': part.appAssetPath,
      'matrix': part.localMatrix.toDebugJson(),
    },
  ];
}

String _runtimeClipPathFor(String family, {RenderCatalogPart? part}) {
  if (part != null) {
    return _sourceHostPathFor(part);
  }
  if (_runtimeControlledHeadExtraFamilies.contains(family)) {
    return 'char.char.char.head.head.$family';
  }
  return switch (family) {
    'ponytail' => 'char.char.char.backhair.backhair.ponytail.ponytail',
    'back_hair' => 'char.char.char.backhair.backhair.backhair.backhair',
    _ => 'char.char.char.head.head.$family',
  };
}

Map<String, dynamic>? _firstDivergentMatrixJson({
  required String family,
  required Map<String, dynamic>? trace,
  required Map<String, dynamic>? sourceEvidence,
  required String runtimeClipPath,
  RenderCatalogPart? part,
}) {
  if (!_sourceEvidenceRemovesMatrix(sourceEvidence)) {
    return null;
  }
  final evidence = sourceEvidence!;
  return {
    'family': family,
    'selected_frame': trace?['chooser_frame'] ?? 0,
    'selected_leaf_ids': trace?['selected_leaf_ids'] ?? const [],
    'selected_assets': trace?['selected_assets'] ?? const [],
    'runtime_clip_path': runtimeClipPath,
    'source_path': part == null ? runtimeClipPath : _sourceHostPathFor(part),
    'matrix': 'PlaceObject ${evidence['removed_edge']}',
    'source_matrix': evidence['removed_matrix'],
    'classification': evidence['classification'],
    'source_evidence': evidence,
  };
}

List<Map<String, dynamic>> _flutterMatrixChainFor({
  required ResolverTables tables,
  required GachaCharacterState state,
  required RenderCatalogPart? part,
}) {
  if (part == null) {
    return const [];
  }
  final pose = tables.posePlacementFor(
    pose: state.numeric('pose'),
    hostName: part.hostScope == 'head' ? 'head' : part.hostName,
  );
  final host = part.hostScope == 'head'
      ? tables.headPlacements[part.hostName]
      : null;
  return [
    {
      'label': 'root height',
      'matrix': _rootCharacterAdjustmentForDiff(tables, state).toDebugJson(),
    },
    {
      'label': 'pose host ${part.hostName}',
      'matrix': pose?.matrix.toDebugJson(),
    },
    {
      'label': 'head/headflip group',
      'matrix': _groupAdjustmentForDiff(tables, part, state).toDebugJson(),
    },
    {
      'label': 'head host ${part.hostName}',
      'matrix': host?.matrix.toDebugJson(),
    },
    {
      'label': 'runtime anchor',
      'matrix': part.hostScope == 'pose'
          ? AffineMatrix.translation(
              part.runtimeAnchorX,
              part.runtimeAnchorY,
            ).toDebugJson()
          : const AffineMatrix.identity().toDebugJson(),
    },
    {
      'label': 'runtime slot',
      'matrix': _slotAdjustmentForDiff(tables, part, state).toDebugJson(),
    },
    {'label': 'catalog local', 'matrix': part.localMatrix.toDebugJson()},
  ];
}

String _buildTransformDiffMarkdown(Map<String, dynamic> diff) {
  final buffer = StringBuffer();
  buffer.writeln('# Gacha DJ Girl transform diff');
  buffer.writeln();
  final first = diff['first_divergent_matrix_found'] as Map<String, dynamic>;
  buffer.writeln(
    '- First divergent matrix fixed: `${first['family']}` ${first['matrix']} (${first['classification']}).',
  );
  buffer.writeln(
    '- Runtime clip path: `${first['runtime_clip_path']}`. Source path: `${first['source_path']}`.',
  );
  buffer.writeln();
  buffer.writeln(
    '| Family | Frame | Leaves | Runtime clip | Source path | First divergent | Classification | Bounds |',
  );
  buffer.writeln('| --- | ---: | --- | --- | --- | --- | --- | --- |');
  for (final part in diff['parts'] as List<dynamic>) {
    final row = part as Map<String, dynamic>;
    final bounds = row['final_bounds'] as Map<String, dynamic>?;
    final firstDivergent =
        row['first_divergent_matrix'] as Map<String, dynamic>?;
    buffer.writeln(
      '| `${row['family']}` | ${row['selected_frame']} | '
      '${_join(row['selected_leaf_ids'] as List<dynamic>)} | '
      '`${row['runtime_clip_path'] ?? '—'}` | '
      '`${row['source_path'] ?? row['source_host_path'] ?? '—'}` | '
      '${firstDivergent == null ? '—' : firstDivergent['matrix']} | '
      '${(row['delta_classification'] as List<dynamic>).join(', ')} | '
      '${bounds == null ? '—' : _rectLabel(bounds)} |',
    );
  }
  return buffer.toString();
}

Map<String, dynamic> _selectedFieldValues(
  GachaFieldSchema schema,
  GachaCharacterState state,
  String family,
) {
  final result = <String, dynamic>{};
  for (final field in _familyFields[family] ?? const <String>[]) {
    final definition = schema.byName[field];
    if (definition == null) {
      continue;
    }
    switch (definition.kind) {
      case GachaFieldKind.metadata:
        result[field] = state.metadata(field);
      case GachaFieldKind.numeric:
        result[field] = state.numeric(field);
      case GachaFieldKind.color:
        result[field] = state.rawValue(schema, field);
    }
  }
  return result;
}

const Map<String, String> _chooserFieldByFamily = {
  'rear_hair': 'rearhair',
  'front_hair': 'fronthair',
  'back_hair': 'backhair',
  'ponytail': 'ponytail',
  'ahoge': 'ahoge',
  'hat': 'hat',
  'glasses': 'glasses',
  'accessory1': 'accessory1x',
  'accessory2': 'accessory2x',
  'accessory3': 'accessory3x',
  'other1': 'other1x',
  'other2': 'other2x',
  'other3': 'other3x',
  'other4': 'other4x',
  'left_eye': 'eyes1x',
  'right_eye': 'eyes2x',
  'left_eyebrow': 'eyebrows1x',
  'right_eyebrow': 'eyebrows2x',
  'mouth': 'mouth',
  'nose': 'nose',
  'blush': 'blush',
  'faceshadow': 'faceshadow',
  'body_pants': 'pants1x',
  'thigh_pants_front': 'pants1x',
  'thigh_pants_back': 'pants2x',
  'foot_pants_front': 'pants1x',
  'foot_pants_back': 'pants2x',
  'thigh_socks_front': 'socks1x',
  'thigh_socks_back': 'socks2x',
  'foot_socks_front': 'socks1x',
  'foot_socks_back': 'socks2x',
  'shoe_front': 'shoes1x',
  'shoe_back': 'shoes2x',
  'knee_front': 'knee1x',
  'knee_back': 'knee2x',
  'weapon_front': 'weapon1x',
  'weapon_back': 'weapon2x',
  'shield': 'shield',
};

const Map<String, List<String>> _familyFields = {
  'rear_hair': ['rearhair', 'headflip', 'headsize', 'headsizey'],
  'front_hair': [
    'fronthair',
    'fronthairxpos',
    'fronthairypos',
    'fronthairxscale',
    'fronthairyscale',
    'fronthairrot',
    'headflip',
    'headsize',
    'headsizey',
  ],
  'back_hair': [
    'backhair',
    'backhairxpos',
    'backhairypos',
    'backhairxscale',
    'backhairyscale',
    'backhairrot',
    'headflip',
    'headsize',
    'headsizey',
  ],
  'ponytail': [
    'ponytail',
    'ponytailxpos',
    'ponytailypos',
    'ponytailxscale',
    'ponytailyscale',
    'ponytailrot',
    'headflip',
    'headsize',
    'headsizey',
  ],
  'ahoge': [
    'ahoge',
    'ahogexpos',
    'ahogeypos',
    'ahogexscale',
    'ahogeyscale',
    'ahogerot',
    'headflip',
    'headsize',
    'headsizey',
  ],
  'hat': ['hat', 'hatxpos', 'hatypos', 'hatsize', 'hatsizey', 'hatrot'],
  'glasses': [
    'glasses',
    'glassesxpos',
    'glassesypos',
    'glassessize',
    'glassessizey',
    'glassesrot',
  ],
  'accessory1': [
    'accessory1x',
    'acc1xpos',
    'acc1ypos',
    'acc1size',
    'acc1sizey',
    'acc1rot',
  ],
  'accessory2': [
    'accessory2x',
    'acc2xpos',
    'acc2ypos',
    'acc2size',
    'acc2sizey',
    'acc2rot',
  ],
  'accessory3': [
    'accessory3x',
    'acc3xpos',
    'acc3ypos',
    'acc3size',
    'acc3sizey',
    'acc3rot',
  ],
  'other1': [
    'other1x',
    'other1xpos',
    'other1ypos',
    'other1size',
    'other1sizey',
    'other1rot',
  ],
  'other2': [
    'other2x',
    'other2xpos',
    'other2ypos',
    'other2size',
    'other2sizey',
    'other2rot',
  ],
  'other3': [
    'other3x',
    'other3xpos',
    'other3ypos',
    'other3size',
    'other3sizey',
    'other3rot',
  ],
  'other4': [
    'other4x',
    'other4xpos',
    'other4ypos',
    'other4size',
    'other4sizey',
    'other4rot',
  ],
  'left_eye': [
    'eyes1x',
    'pupil1x',
    'leyexpos',
    'leyeypos',
    'leyesize',
    'leyesizey',
    'leyerot',
  ],
  'right_eye': [
    'eyes2x',
    'pupil2x',
    'reyexpos',
    'reyeypos',
    'reyesize',
    'reyesizey',
    'reyerot',
  ],
  'left_eyebrow': [
    'eyebrows1x',
    'leyebrowxpos',
    'leyebrowypos',
    'leyebrowsize',
    'leyebrowsizey',
    'leyebrowrot',
  ],
  'right_eyebrow': [
    'eyebrows2x',
    'reyebrowxpos',
    'reyebrowypos',
    'reyebrowsize',
    'reyebrowsizey',
    'reyebrowrot',
  ],
  'mouth': [
    'mouth',
    'mouthxpos',
    'mouthypos',
    'mouthsize',
    'mouthsizey',
    'mouthrot',
  ],
  'nose': ['nose', 'nosexpos', 'noseypos', 'nosesize', 'nosesizey', 'noserot'],
  'blush': ['blush'],
  'faceshadow': ['faceshadow'],
  'body_pants': ['pants1x'],
  'thigh_pants_front': ['pants1x'],
  'thigh_pants_back': ['pants2x'],
  'foot_pants_front': ['pants1x'],
  'foot_pants_back': ['pants2x'],
  'thigh_socks_front': ['socks1x'],
  'thigh_socks_back': ['socks2x'],
  'foot_socks_front': ['socks1x'],
  'foot_socks_back': ['socks2x'],
  'shoe_front': ['shoes1x'],
  'shoe_back': ['shoes2x'],
  'knee_front': ['knee1x'],
  'knee_back': ['knee2x'],
  'weapon_front': [
    'weapon1x',
    'propxpos1x',
    'propypos1x',
    'propsize1x',
    'proprot1x',
  ],
  'weapon_back': [
    'weapon2x',
    'propxpos2x',
    'propypos2x',
    'propsize2x',
    'proprot2x',
  ],
  'shield': ['shield', 'shieldxpos', 'shieldypos', 'shieldsize', 'shieldrot'],
};

Rect _partBounds(ResolvedScene scene, ResolvedRenderPart part) {
  final asset = scene.assets[part.catalogPart.appAssetPath]!;
  return part.localTransform.transformRect(
    Rect.fromLTWH(0, 0, asset.size.width, asset.size.height),
  );
}

Map<String, dynamic>? _hostPlacementJson(HostPlacement? placement) {
  if (placement == null) {
    return null;
  }
  return {
    'name': placement.name,
    'depth': placement.depth,
    'matrix': placement.matrix.toDebugJson(),
  };
}

Map<String, dynamic>? _rectJson(Rect? rect) {
  if (rect == null) {
    return null;
  }
  return {
    'left': rect.left,
    'top': rect.top,
    'right': rect.right,
    'bottom': rect.bottom,
    'width': rect.width,
    'height': rect.height,
  };
}

Map<String, dynamic> _boundsRelativeJson(
  String family,
  Rect? bounds,
  Map<String, Rect> familyBounds,
) {
  if (bounds == null) {
    return const <String, dynamic>{};
  }
  final result = <String, dynamic>{};
  final head = familyBounds['head_shape'];
  final body = familyBounds['body_base'];
  final host = switch (family) {
    'ponytail' => familyBounds['back_hair'] ?? familyBounds['head_shape'],
    'weapon_front' =>
      familyBounds['hand_front_base'] ?? familyBounds['body_base'],
    'weapon_back' ||
    'shield' => familyBounds['hand_back_base'] ?? familyBounds['body_base'],
    _ => familyBounds['head_shape'],
  };
  if (head != null) {
    result['head'] = _relativeTo(bounds, head).toJson();
  }
  if (body != null) {
    result['body'] = _relativeTo(bounds, body).toJson();
  }
  if (host != null) {
    result['host'] = _relativeTo(bounds, host).toJson();
  }
  return result;
}

Map<String, dynamic>? _sourceEvidenceFor(String family) {
  return switch (family) {
    'hat' => const {
      'classification':
          'runtime-controlled outer clip with retained chooser art placement',
      'removed_edge': '24691 -> 3611',
      'place_object_depth': 1,
      'source_file': '.cache/gacha_clubPC.xml',
      'source_lines': '4140161-4140163',
      'reason':
          'ActionScript writes char.char.char.head.head.hat x/y/scale/rotation, while docs/data/swf-frame-placements/head_layout.csv already carries the outer slot base (4,-62). The chooser child PlaceObject remains a nested art offset and must stay in localMatrix.',
      'removes_matrix': false,
      'removed_matrix': {
        'a': 1.0,
        'b': 0.0,
        'c': 0.0,
        'd': 1.0,
        'tx': 129.0,
        'ty': -249.0,
      },
    },
    'accessory1' => const {
      'classification':
          'runtime-controlled outer clip with retained chooser art placement',
      'removed_edge': '15264 -> 15196',
      'place_object_depth': 1,
      'source_file': '.cache/gacha_clubPC.xml',
      'source_lines': '3784035-3784037',
      'reason':
          'ActionScript writes char.char.char.head.head.accessory1 x/y/scale/rotation, while docs/data/swf-frame-placements/head_layout.csv already carries the outer slot base (-12,-13). The chooser child PlaceObject remains a nested art offset and must stay in localMatrix.',
      'removes_matrix': false,
      'removed_matrix': {
        'a': 1.0,
        'b': 0.0,
        'c': 0.0,
        'd': 1.0,
        'tx': 1172.0,
        'ty': 94.0,
      },
    },
    'accessory2' => const {
      'classification':
          'runtime-controlled outer clip with retained chooser art placement',
      'removed_edge': '15264 -> 15230',
      'place_object_depth': 1,
      'source_file': '.cache/gacha_clubPC.xml',
      'source_lines': '3784122-3784124',
      'reason':
          'ActionScript writes char.char.char.head.head.accessory2 x/y/scale/rotation, while docs/data/swf-frame-placements/head_layout.csv already carries the outer slot base (-12,-13). The chooser child PlaceObject remains a nested art offset and must stay in localMatrix.',
      'removes_matrix': false,
      'removed_matrix': {
        'a': 1.0,
        'b': 0.0,
        'c': 0.0,
        'd': 1.0,
        'tx': 563.0,
        'ty': -86.0,
      },
    },
    'ponytail' => const {
      'classification': 'fixed extra wrapper transform',
      'removed_edge': '4769 -> 4768',
      'place_object_depth': 1,
      'source_file': '.cache/gacha_clubPC.xml',
      'source_lines': '3385633-3385635',
      'reason':
          'ActionScript writes char.char.char.backhair.backhair.ponytail.ponytail x/y/scale/rotation, so this target placement is replaced by runtime slot properties.',
      'removes_matrix': true,
      'removed_matrix': {
        'a': 0.8162842,
        'b': 0.0,
        'c': 0.0,
        'd': 0.8162842,
        'tx': 21.0,
        'ty': -43.0,
      },
    },
    'back_hair' => const {
      'classification': 'fixed extra wrapper transform',
      'removed_edge': '5457 -> 5456',
      'place_object_depth': 1,
      'source_file': '.cache/gacha_clubPC.xml',
      'source_lines': '3415175-3415177',
      'reason':
          'ActionScript writes char.char.char.backhair.backhair.backhair.backhair x/y/scale/rotation, so this target placement is replaced by runtime slot properties.',
      'removes_matrix': true,
      'removed_matrix': {
        'a': 0.8162842,
        'b': 0.0,
        'c': 0.0,
        'd': 0.8162842,
        'tx': 0.0,
        'ty': 0.0,
      },
    },
    _ => null,
  };
}

bool _sourceEvidenceRemovesMatrix(Map<String, dynamic>? sourceEvidence) {
  return sourceEvidence?['removes_matrix'] == true;
}

String _sourceHostPathFor(RenderCatalogPart part) {
  if (part.family == 'ponytail') {
    return 'char.char.char.backhair.backhair.ponytail.ponytail';
  }
  if (part.family == 'back_hair') {
    return 'char.char.char.backhair.backhair.backhair.backhair';
  }
  if (part.hostScope == 'head') {
    return 'char.char.char.head.head.${part.hostName}';
  }
  return 'char.char.char.${part.hostName}';
}

List<String> _deltaClassificationFor({
  required String family,
  required List<ResolvedRenderPart> parts,
  required Map<String, dynamic>? sourceEvidence,
}) {
  if (sourceEvidence != null) {
    return [sourceEvidence['classification'] as String];
  }
  if (parts.isEmpty) {
    return const ['no source reference available'];
  }
  return const ['no numeric transform delta found'];
}

AffineMatrix _rootCharacterAdjustmentForDiff(
  ResolverTables tables,
  GachaCharacterState state,
) {
  return AffineMatrix.scale(
    tables.runtimeValueMaps.resolve(
      field: 'heightx',
      fieldValue: state.numeric('heightx'),
      op: 'scaleX',
      targetContains: 'char.char',
      fallback: 1,
    ),
    tables.runtimeValueMaps.resolve(
      field: 'heighty',
      fieldValue: state.numeric('heighty'),
      op: 'scaleY',
      targetContains: 'char.char',
      fallback: 1,
    ),
  );
}

AffineMatrix _groupAdjustmentForDiff(
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

AffineMatrix _slotAdjustmentForDiff(
  ResolverTables tables,
  RenderCatalogPart part,
  GachaCharacterState state,
) {
  final binding = _diffBindingFor(part.family);
  if (binding == null) {
    return const AffineMatrix.identity();
  }
  final x = _slotValueForDiff(
    tables: tables,
    state: state,
    field: binding.xField,
    op: 'x',
    targetContains: binding.targetContains,
    fallback: 0,
    directFieldFallback: true,
  );
  final y = _slotValueForDiff(
    tables: tables,
    state: state,
    field: binding.yField,
    op: 'y',
    targetContains: binding.targetContains,
    fallback: 0,
    directFieldFallback: true,
  );
  final scaleX = _slotValueForDiff(
    tables: tables,
    state: state,
    field: binding.scaleXField,
    op: 'scaleX',
    targetContains: binding.targetContains,
    fallback: 1,
    directFieldFallback: false,
  );
  final scaleY = _slotValueForDiff(
    tables: tables,
    state: state,
    field: binding.scaleYField,
    op: 'scaleY',
    targetContains: binding.targetContains,
    fallback: 1,
    directFieldFallback: false,
  );
  final rotation = binding.appliesGeometricRotation
      ? _slotValueForDiff(
          tables: tables,
          state: state,
          field: binding.rotationField,
          op: 'rotation',
          targetContains: binding.targetContains,
          fallback: 0,
          directFieldFallback: binding.rotationUsesDirectFieldFallback,
        )
      : 0.0;
  return AffineMatrix.translation(x, y)
      .multiply(AffineMatrix.rotationDegrees(rotation))
      .multiply(AffineMatrix.scale(scaleX, scaleY));
}

double _slotValueForDiff({
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
  return directFieldFallback ? fieldValue.toDouble() : fallback;
}

_DiffSlotBinding? _diffBindingFor(String family) {
  switch (family) {
    case 'front_hair':
      return const _DiffSlotBinding(
        targetContains: 'head.head.fronthair',
        xField: 'fronthairxpos',
        yField: 'fronthairypos',
        scaleXField: 'fronthairxscale',
        scaleYField: 'fronthairyscale',
        rotationField: 'fronthairrot',
        appliesGeometricRotation: false,
        rotationUsesDirectFieldFallback: false,
      );
    case 'back_hair':
      return const _DiffSlotBinding(
        targetContains: 'backhair.backhair',
        xField: 'backhairxpos',
        yField: 'backhairypos',
        scaleXField: 'backhairxscale',
        scaleYField: 'backhairyscale',
        rotationField: 'backhairrot',
      );
    case 'ponytail':
      return const _DiffSlotBinding(
        targetContains: 'backhair.backhair.ponytail',
        xField: 'ponytailxpos',
        yField: 'ponytailypos',
        scaleXField: 'ponytailxscale',
        scaleYField: 'ponytailyscale',
        rotationField: 'ponytailrot',
      );
    case 'ahoge':
      return const _DiffSlotBinding(
        targetContains: 'head.head.ahoge',
        xField: 'ahogexpos',
        yField: 'ahogeypos',
        scaleXField: 'ahogexscale',
        scaleYField: 'ahogeyscale',
        rotationField: 'ahogerot',
      );
    case 'hat':
      return const _DiffSlotBinding(
        targetContains: 'head.head.hat',
        xField: 'hatxpos',
        yField: 'hatypos',
        scaleXField: 'hatsize',
        scaleYField: 'hatsizey',
        rotationField: 'hatrot',
      );
    case 'glasses':
      return const _DiffSlotBinding(
        targetContains: 'head.head.glasses',
        xField: 'glassesxpos',
        yField: 'glassesypos',
        scaleXField: 'glassessize',
        scaleYField: 'glassessizey',
        rotationField: 'glassesrot',
      );
    case 'accessory1':
      return const _DiffSlotBinding(
        targetContains: 'head.head.accessory1',
        xField: 'acc1xpos',
        yField: 'acc1ypos',
        scaleXField: 'acc1size',
        scaleYField: 'acc1sizey',
        rotationField: 'acc1rot',
      );
    case 'accessory2':
      return const _DiffSlotBinding(
        targetContains: 'head.head.accessory2',
        xField: 'acc2xpos',
        yField: 'acc2ypos',
        scaleXField: 'acc2size',
        scaleYField: 'acc2sizey',
        rotationField: 'acc2rot',
      );
    case 'accessory3':
      return const _DiffSlotBinding(
        targetContains: 'head.head.accessory3',
        xField: 'acc3xpos',
        yField: 'acc3ypos',
        scaleXField: 'acc3size',
        scaleYField: 'acc3sizey',
        rotationField: 'acc3rot',
      );
    case 'other1':
    case 'other2':
    case 'other3':
    case 'other4':
      final index = family.substring(family.length - 1);
      return _DiffSlotBinding(
        targetContains: 'head.head.other$index',
        xField: 'other${index}xpos',
        yField: 'other${index}ypos',
        scaleXField: 'other${index}size',
        scaleYField: 'other${index}sizey',
        rotationField: 'other${index}rot',
      );
    case 'weapon_front':
      return const _DiffSlotBinding(
        targetContains: 'weapon.weapon',
        xField: 'propxpos1x',
        yField: 'propypos1x',
        scaleXField: 'propsize1x',
        scaleYField: 'propsize1x',
        rotationField: 'proprot1x',
      );
    case 'weapon_back':
      return const _DiffSlotBinding(
        targetContains: 'backweapon.weapon',
        xField: 'propxpos2x',
        yField: 'propypos2x',
        scaleXField: 'propsize2x',
        scaleYField: 'propsize2x',
        rotationField: 'proprot2x',
      );
    case 'shield':
      return const _DiffSlotBinding(
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

List<ResolvedRenderPart> _family(ResolvedScene scene, String family) {
  return scene.parts
      .where((part) => part.catalogPart.family == family)
      .toList(growable: false);
}

Set<String> _leafIds(String family) {
  return _dedupe(
    _family(_sceneHolder!, family).map((part) => part.catalogPart.leafId),
  ).toSet();
}

void _expectFamilyBefore(String first, String second) {
  final firstIndexes = _family(
    _sceneHolder!,
    first,
  ).map((part) => _sceneHolder!.parts.indexOf(part)).toList(growable: false);
  final secondIndexes = _family(
    _sceneHolder!,
    second,
  ).map((part) => _sceneHolder!.parts.indexOf(part)).toList(growable: false);
  expect(firstIndexes, isNotEmpty, reason: first);
  expect(secondIndexes, isNotEmpty, reason: second);
  expect(
    firstIndexes.reduce(math.max),
    lessThan(secondIndexes.reduce(math.min)),
  );
}

void _expectClose(
  double actual,
  double expected,
  double tolerance,
  String label,
) {
  expect(
    actual,
    inInclusiveRange(expected - tolerance, expected + tolerance),
    reason: label,
  );
}

String _inlineMap(Map<String, dynamic> values) {
  if (values.isEmpty) {
    return '—';
  }
  final keys = values.keys.toList()..sort();
  return keys.map((key) => '$key=${values[key]}').join(', ');
}

String _join(List<dynamic> values) => values.isEmpty ? '—' : values.join(', ');

String _rectLabel(Map<String, dynamic> rect) =>
    'x=${(rect['left'] as num).toStringAsFixed(1)}..${(rect['right'] as num).toStringAsFixed(1)}, '
    'y=${(rect['top'] as num).toStringAsFixed(1)}..${(rect['bottom'] as num).toStringAsFixed(1)}';

Iterable<String> _dedupe(Iterable<String> values) sync* {
  final seen = <String>{};
  for (final value in values) {
    if (value.isEmpty || !seen.add(value)) {
      continue;
    }
    yield value;
  }
}

_RelativeRect _relativeTo(Rect bounds, Rect reference) {
  return _RelativeRect(
    centerDx: bounds.center.dx - reference.center.dx,
    centerDy: bounds.center.dy - reference.center.dy,
    widthRatio: bounds.width / math.max(reference.width, 1),
    heightRatio: bounds.height / math.max(reference.height, 1),
    overlapRatio: _overlapRatio(bounds, reference),
  );
}

double _overlapRatio(Rect a, Rect b) {
  final overlap = a.intersect(b);
  if (overlap.isEmpty) {
    return 0;
  }
  final minArea = math.min(a.width * a.height, b.width * b.height);
  if (minArea <= 0) {
    return 0;
  }
  return (overlap.width * overlap.height) / minArea;
}

class _RelativeRect {
  const _RelativeRect({
    required this.centerDx,
    required this.centerDy,
    required this.widthRatio,
    required this.heightRatio,
    required this.overlapRatio,
  });

  final double centerDx;
  final double centerDy;
  final double widthRatio;
  final double heightRatio;
  final double overlapRatio;

  Map<String, dynamic> toJson() => {
    'center_dx': centerDx,
    'center_dy': centerDy,
    'width_ratio': widthRatio,
    'height_ratio': heightRatio,
    'overlap_ratio': overlapRatio,
  };
}

class _DiffSlotBinding {
  const _DiffSlotBinding({
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

ResolvedScene? _sceneHolder;
