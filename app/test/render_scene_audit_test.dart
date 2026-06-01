import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/render_part.dart';
import 'support/world_transform_helper.dart';

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
    'approved validation scenes stay within sane bounds envelopes',
    () async {
      for (final descriptor in tables.validationCases) {
        final audit = await _auditForFixture(
          parser: parser,
          renderer: renderer,
          fixtureAsset: descriptor.fixtureAsset,
        );

        expect(
          audit.scene.worldBounds.width,
          lessThan(400),
          reason:
              '${descriptor.id} width drifted outside the approved envelope',
        );
        expect(
          audit.scene.worldBounds.height,
          lessThan(400),
          reason:
              '${descriptor.id} height drifted outside the approved envelope',
        );

        for (final entry in audit.families.entries) {
          expect(
            entry.value.bounds.width.isFinite &&
                entry.value.bounds.height.isFinite,
            isTrue,
            reason: '${descriptor.id}:${entry.key} produced non-finite bounds',
          );
        }

        for (var index = 1; index < audit.scene.parts.length; index++) {
          expect(
            audit.scene.parts[index - 1].globalDepth,
            lessThanOrEqualTo(audit.scene.parts[index].globalDepth),
            reason:
                '${descriptor.id} scene parts are not sorted by global depth',
          );
        }
      }
    },
  );

  test('body head alignment stays coherent on the base scaffold', () async {
    final audit = await _auditForFixture(
      parser: parser,
      renderer: renderer,
      fixtureAsset: 'fixtures/body_base_probe.gc.txt',
    );
    final head = audit.family('head_shape');
    final body = audit.family('body_base');
    final backThigh = audit.family('thigh_back_base');

    expect((head.bounds.center.dx - body.bounds.center.dx).abs(), lessThan(12));
    expect(body.bounds.top, lessThan(head.bounds.bottom));
    expect(
      body.bounds.top,
      greaterThan(head.bounds.bottom - 22),
      reason: 'body scaffold drifted too far below the head overlap zone',
    );
    expect(
      (backThigh.bounds.center.dx - body.bounds.center.dx).abs(),
      lessThan(12),
    );
  });

  test(
    'arm layering keeps sleeves shoulders gloves and wrists ordered',
    () async {
      final audit = await _auditForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/arm_layers_probe.gc.txt',
      );

      _expectOrderedFamilies(audit, [
        'back_shoulder_base',
        'upper_sleeve_back',
        'shoulder_back',
        'hand_back_base',
        'lower_sleeve_back',
        'glove_back',
        'wrist_back',
      ]);
      _expectOrderedFamilies(audit, [
        'shoulder_front_base',
        'upper_sleeve_front',
        'shoulder_front',
        'hand_front_base',
        'lower_sleeve_front',
        'glove_front',
        'wrist_front',
      ]);
      _expectTintedColorLayers(audit, [
        'upper_sleeve_back',
        'shoulder_back',
        'lower_sleeve_back',
        'glove_back',
        'wrist_back',
        'upper_sleeve_front',
        'shoulder_front',
        'lower_sleeve_front',
        'glove_front',
        'wrist_front',
      ]);
    },
  );

  test(
    'lower clothing layering keeps pants socks shoes and knees ordered',
    () async {
      final audit = await _auditForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/lower_clothing_probe.gc.txt',
      );

      _expectOrderedFamilies(audit, [
        'thigh_back_base',
        'thigh_socks_back',
        'thigh_pants_back',
        'foot_back_base',
        'foot_socks_back',
        'foot_pants_back',
        'shoe_back',
        'knee_back',
      ]);
      _expectOrderedFamilies(audit, [
        'thigh_front_base',
        'thigh_socks_front',
        'thigh_pants_front',
        'foot_front_base',
        'foot_socks_front',
        'foot_pants_front',
        'shoe_front',
        'knee_front',
      ]);
      _expectTintedColorLayers(audit, [
        'body_pants',
        'thigh_socks_back',
        'thigh_pants_back',
        'foot_socks_back',
        'foot_pants_back',
        'shoe_back',
        'knee_back',
        'thigh_socks_front',
        'thigh_pants_front',
        'foot_socks_front',
        'foot_pants_front',
        'shoe_front',
        'knee_front',
      ]);
    },
  );

  test('upper clothing stacking and tint channels stay coherent', () async {
    final audit = await _auditForFixture(
      parser: parser,
      renderer: renderer,
      fixtureAsset: 'fixtures/upper_clothing_probe.gc.txt',
    );

    _expectOrderedFamilies(audit, [
      'body_base',
      'body_shirt',
      'body_jacket',
      'belt2',
      'belt1',
      'belt_shirt',
      'belt_jacket',
    ]);
    _expectTintedColorLayers(audit, [
      'body_shirt',
      'body_jacket',
      'belt2',
      'belt1',
      'belt_shirt',
      'belt_jacket',
    ]);
  });

  test('outerwear families stay finite ordered and bounded', () async {
    final audit = await _auditForFixture(
      parser: parser,
      renderer: renderer,
      fixtureAsset: 'fixtures/outerwear_probe.gc.txt',
    );

    expect(audit.family('cape').count, 3);
    expect(audit.family('tail').count, 3);
    expect(audit.family('wings1').count, 3);
    expect(audit.family('wings2').count, 3);
    expect(audit.family('scarf1').count, 4);
    expect(audit.family('scarf2').count, 4);

    expect(
      audit.family('cape').lastIndex,
      lessThan(audit.family('body_base').firstIndex),
    );
    expect(
      audit.family('tail').lastIndex,
      lessThan(audit.family('body_base').firstIndex),
    );
    expect(
      audit.family('wings1').lastIndex,
      lessThan(audit.family('body_base').firstIndex),
    );
    expect(
      audit.family('wings2').lastIndex,
      lessThan(audit.family('body_base').firstIndex),
    );
    expect(
      audit.family('scarf2').firstIndex,
      greaterThan(audit.family('hand_front_base').lastIndex),
    );
    expect(
      audit.family('scarf1').firstIndex,
      greaterThan(audit.family('hand_front_base').lastIndex),
    );

    _expectTintedColorLayers(audit, [
      'cape',
      'tail',
      'wings1',
      'wings2',
      'scarf1',
      'scarf2',
    ]);
  });

  test(
    'props keep back weapon behind body and front props ahead of it',
    () async {
      final audit = await _auditForFixture(
        parser: parser,
        renderer: renderer,
        fixtureAsset: 'fixtures/props_probe.gc.txt',
      );

      expect(
        audit.family('weapon_back').lastIndex,
        lessThan(audit.family('body_base').firstIndex),
      );
      expect(
        audit.family('body_base').lastIndex,
        lessThan(audit.family('shield').firstIndex),
      );
      expect(
        audit.family('shield').lastIndex,
        lessThan(audit.family('weapon_front').firstIndex),
      );

      _expectTintedColorLayers(audit, [
        'weapon_back',
        'shield',
        'weapon_front',
      ]);
    },
  );

  test(
    'body and prop visibility toggles hide the corresponding subsystems',
    () async {
      final outerwearBase = await _stateForFixture(
        parser: parser,
        fixtureAsset: 'fixtures/outerwear_probe.gc.txt',
      );
      final propsBase = await _stateForFixture(
        parser: parser,
        fixtureAsset: 'fixtures/props_probe.gc.txt',
      );

      final hiddenBodyScene = await renderer.buildScene(
        _overrideState(outerwearBase, {
          'displaybody': 0,
          'displayhand': 0,
          'displaybackhand': 0,
          'displayshoulder': 0,
          'displaybackshoulder': 0,
          'displaythigh': 0,
          'displaybackthigh': 0,
          'displayfoot': 0,
          'displaybackfoot': 0,
        }),
      );
      final hiddenBodyFamilies = hiddenBodyScene.parts
          .map((part) => part.catalogPart.family)
          .toSet();
      expect(hiddenBodyFamilies.contains('head_shape'), isTrue);
      expect(hiddenBodyFamilies.contains('body_base'), isFalse);
      expect(hiddenBodyFamilies.contains('cape'), isFalse);
      expect(hiddenBodyFamilies.contains('tail'), isFalse);
      expect(hiddenBodyFamilies.contains('wings1'), isFalse);
      expect(hiddenBodyFamilies.contains('wings2'), isFalse);
      expect(hiddenBodyFamilies.contains('scarf1'), isFalse);
      expect(hiddenBodyFamilies.contains('scarf2'), isFalse);

      final hiddenPropsScene = await renderer.buildScene(
        _overrideState(propsBase, {'displayhand': 0, 'displaybackhand': 0}),
      );
      final hiddenPropsFamilies = hiddenPropsScene.parts
          .map((part) => part.catalogPart.family)
          .toSet();
      expect(hiddenPropsFamilies.contains('weapon_front'), isFalse);
      expect(hiddenPropsFamilies.contains('weapon_back'), isFalse);
      expect(hiddenPropsFamilies.contains('shield'), isFalse);
    },
  );
}

Future<_SceneAudit> _auditForFixture({
  required GachaCodeParser parser,
  required CharacterRenderer renderer,
  required String fixtureAsset,
}) async {
  final state = await _stateForFixture(
    parser: parser,
    fixtureAsset: fixtureAsset,
  );
  final scene = await renderer.buildScene(state);
  return _SceneAudit.fromScene(scene, state, renderer.tables);
}

Future<GachaCharacterState> _stateForFixture({
  required GachaCodeParser parser,
  required String fixtureAsset,
}) async {
  final code = await rootBundle.loadString(fixtureAsset);
  return parser.parse(code);
}

GachaCharacterState _overrideState(
  GachaCharacterState base,
  Map<String, int> numericOverrides,
) {
  return GachaCharacterState(
    rawFields: base.rawFields,
    metadataFields: base.metadataFields,
    numericFields: {...base.numericFields, ...numericOverrides},
    colorFields: base.colorFields,
  );
}

void _expectOrderedFamilies(_SceneAudit audit, List<String> families) {
  for (var index = 1; index < families.length; index++) {
    final previous = audit.family(families[index - 1]);
    final current = audit.family(families[index]);
    expect(
      previous.lastIndex,
      lessThan(current.firstIndex),
      reason:
          'Expected ${families[index - 1]} to resolve before ${families[index]}',
    );
  }
}

void _expectTintedColorLayers(_SceneAudit audit, List<String> families) {
  for (final family in families) {
    final parts = audit.family(family).parts.where((part) {
      return part.catalogPart.partRole.startsWith('color_') &&
          part.catalogPart.partRole != 'color_extra';
    });
    expect(parts, isNotEmpty, reason: '$family has no tintable color layers');
    for (final part in parts) {
      expect(
        part.catalogPart.tintChannel,
        isNot('none'),
        reason: '$family:${part.catalogPart.partRole} lost its tint channel',
      );
      expect(
        part.tintColor,
        isNotNull,
        reason:
            '$family:${part.catalogPart.partRole} did not resolve a tint color',
      );
    }
  }
}

class _SceneAudit {
  const _SceneAudit({required this.scene, required this.families});

  final ResolvedScene scene;
  final Map<String, _FamilyAudit> families;

  factory _SceneAudit.fromScene(
    ResolvedScene scene,
    GachaCharacterState state,
    ResolverTables tables,
  ) {
    final groups = <String, List<_IndexedPart>>{};
    for (var index = 0; index < scene.parts.length; index++) {
      final part = scene.parts[index];
      final asset = scene.assets[part.catalogPart.appAssetPath];
      if (asset == null) {
        continue;
      }
      final bounds = resolveTestWorldTransform(
        part,
        state,
        tables,
      ).transformRect(Rect.fromLTWH(0, 0, asset.size.width, asset.size.height));
      groups
          .putIfAbsent(part.catalogPart.family, () => [])
          .add(_IndexedPart(index: index, part: part, bounds: bounds));
    }

    return _SceneAudit(
      scene: scene,
      families: {
        for (final entry in groups.entries)
          entry.key: _FamilyAudit.fromIndexedParts(entry.value),
      },
    );
  }

  _FamilyAudit family(String name) {
    final audit = families[name];
    if (audit == null) {
      throw StateError('Expected family $name to resolve in the audited scene');
    }
    return audit;
  }
}

class _FamilyAudit {
  const _FamilyAudit({
    required this.parts,
    required this.firstIndex,
    required this.lastIndex,
    required this.bounds,
  });

  final List<ResolvedRenderPart> parts;
  final int firstIndex;
  final int lastIndex;
  final Rect bounds;

  int get count => parts.length;

  factory _FamilyAudit.fromIndexedParts(List<_IndexedPart> parts) {
    final sorted = [...parts]
      ..sort((left, right) => left.index.compareTo(right.index));
    final union = sorted
        .map((item) => item.bounds)
        .reduce((left, right) => left.expandToInclude(right));
    return _FamilyAudit(
      parts: [for (final item in sorted) item.part],
      firstIndex: sorted.first.index,
      lastIndex: sorted.last.index,
      bounds: union,
    );
  }
}

class _IndexedPart {
  const _IndexedPart({
    required this.index,
    required this.part,
    required this.bounds,
  });

  final int index;
  final ResolvedRenderPart part;
  final Rect bounds;
}
