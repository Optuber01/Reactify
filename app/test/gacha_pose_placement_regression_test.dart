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

  test('ResolverTables keeps multiple pose placements for the same host', () {
    final pose1 = tables.posePlacementFor(pose: 1, hostName: 'head');
    final pose36 = tables.posePlacementFor(pose: 36, hostName: 'head');
    final pose601 = tables.posePlacementFor(pose: 601, hostName: 'head');

    expect(pose1, isNotNull);
    expect(pose36, isNotNull);
    expect(pose601, isNotNull);
    expect(
      pose36!.matrix.tx != pose1!.matrix.tx ||
          pose36.matrix.ty != pose1.matrix.ty ||
          pose36.matrix.a != pose1.matrix.a ||
          pose36.matrix.b != pose1.matrix.b ||
          pose36.matrix.c != pose1.matrix.c ||
          pose36.matrix.d != pose1.matrix.d,
      isTrue,
    );
    expect(
      pose601!.depth,
      isNot(equals(pose1.depth)),
      reason: 'page 25 poses should not collapse back to the baseline row',
    );
  });

  test(
    'pose 1 and a non-default built-in pose resolve different host transforms',
    () async {
      final state = await _stateForFixture(
        parser: parser,
        fixtureAsset: 'fixtures/builtin/gacha-dj-girl.gc.txt',
      );
      expect(state.numeric('pose'), isNot(1));

      final baseline = tables.posePlacementFor(pose: 1, hostName: 'weapon');
      final actual = tables.posePlacementFor(
        pose: state.numeric('pose'),
        hostName: 'weapon',
      );

      expect(baseline, isNotNull);
      expect(actual, isNotNull);
      expect(
        _sameMatrix(baseline!.matrix, actual!.matrix),
        isFalse,
        reason: 'non-default pose should not reuse the baseline weapon host',
      );
    },
  );

  test('curated built-ins no longer emit the baseline-pose warning', () async {
    for (final descriptor in tables.builtinFixtures) {
      final scene = await renderer.buildScene(
        await _stateForFixture(
          parser: parser,
          fixtureAsset: descriptor.fixtureAsset,
        ),
      );
      expect(
        scene.warnings,
        isNot(
          contains(
            'Pose wrapper placement is currently validated against the extracted baseline pose frame only.',
          ),
        ),
        reason: descriptor.displayName,
      );
    }
  });

  for (final fixture in const [
    ('gacha-dj-girl', 'Gacha DJ (Girl)'),
    ('gacha-dj-boy', 'Gacha DJ (Boy)'),
    ('limea', 'Limea'),
  ]) {
    test('${fixture.$2} head-related bounds stay coherent', () async {
      final state = await _stateForFixture(
        parser: parser,
        fixtureAsset: 'fixtures/builtin/${fixture.$1}.gc.txt',
      );
      final scene = await renderer.buildScene(state);
      final audit = _SceneAudit.fromScene(scene);

      final head = audit.family('head_shape');
      final body = audit.family('body_base');

      expect(
        (head.bounds.center.dx - body.bounds.center.dx).abs(),
        lessThan(head.bounds.width * 0.9),
        reason: '${fixture.$2} head drifted too far from the body axis',
      );
      expect(
        body.bounds.top,
        lessThan(head.bounds.bottom + head.bounds.height * 0.8),
        reason: '${fixture.$2} body is detached from the head stack',
      );

      _expectEnabledHairFamilies(state, audit, tables, fixture.$2);
      _expectHeadAttachedFamilies(audit, fixture.$2, [
        'left_eye',
        'right_eye',
        'mouth',
        'nose',
        'hat',
        'glasses',
        'accessory1',
        'accessory2',
        'accessory3',
        'other1',
        'other2',
        'other3',
        'other4',
      ]);

      for (final entry in audit.families.entries) {
        final family = entry.key;
        final bounds = entry.value.bounds;
        if (_allowedLargeFamilies.contains(family)) {
          continue;
        }
        expect(
          bounds.width,
          lessThan(scene.worldBounds.width * 0.92),
          reason: '${fixture.$2}:$family became a giant width outlier',
        );
        expect(
          bounds.height,
          lessThan(scene.worldBounds.height * 0.92),
          reason: '${fixture.$2}:$family became a giant height outlier',
        );
      }
    });
  }
}

const _hairSelections = <String, String>{
  'rear_hair': 'rearhair',
  'front_hair': 'fronthair',
  'back_hair': 'backhair',
  'ponytail': 'ponytail',
  'ahoge': 'ahoge',
};

const _headAttachedFamilies = <String>{
  'rear_hair',
  'front_hair',
  'back_hair',
  'ponytail',
  'ahoge',
  'left_eye',
  'right_eye',
  'left_eyebrow',
  'right_eyebrow',
  'mouth',
  'nose',
  'blush',
  'faceshadow',
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

const _allowedLargeFamilies = <String>{
  'cape',
  'tail',
  'wings1',
  'wings2',
  'weapon_front',
  'weapon_back',
  'shield',
};

bool _sameMatrix(AffineMatrix left, AffineMatrix right) {
  return left.a == right.a &&
      left.b == right.b &&
      left.c == right.c &&
      left.d == right.d &&
      left.tx == right.tx &&
      left.ty == right.ty;
}

Future<GachaCharacterState> _stateForFixture({
  required GachaCodeParser parser,
  required String fixtureAsset,
}) async {
  final code = await rootBundle.loadString(fixtureAsset);
  return parser.parse(code);
}

void _expectEnabledHairFamilies(
  GachaCharacterState state,
  _SceneAudit audit,
  ResolverTables tables,
  String label,
) {
  if (state.numeric('displayhair') == 0) {
    for (final family in _hairSelections.keys) {
      expect(audit.families.containsKey(family), isFalse, reason: label);
    }
    return;
  }

  for (final entry in _hairSelections.entries) {
    final chooserFrame = state.numeric(entry.value);
    final supported =
        chooserFrame <= 0 ||
        tables.partsFor(entry.key, chooserFrame).isNotEmpty;
    if (!supported) {
      continue;
    }
    final selected = chooserFrame > 0;
    expect(
      audit.families.containsKey(entry.key),
      selected,
      reason:
          '$label expected hair family ${entry.key} to match ${entry.value}',
    );
  }
}

void _expectHeadAttachedFamilies(
  _SceneAudit audit,
  String label,
  List<String> candidateFamilies,
) {
  final head = audit.family('head_shape').bounds;
  final maxDx = head.width * 1.25;
  final maxDy = head.height * 1.25;

  for (final family in candidateFamilies) {
    final target = audit.families[family];
    if (target == null) {
      continue;
    }
    expect(
      (target.bounds.center.dx - head.center.dx).abs(),
      lessThan(maxDx),
      reason: '$label $family detached too far horizontally from the head',
    );
    expect(
      (target.bounds.center.dy - head.center.dy).abs(),
      lessThan(maxDy),
      reason: '$label $family detached too far vertically from the head',
    );
    if (_headAttachedFamilies.contains(family)) {
      expect(
        target.bounds.overlaps(head.inflate(head.longestSide * 0.45)),
        isTrue,
        reason: '$label $family no longer overlaps the expected head region',
      );
    }
  }
}

class _SceneAudit {
  const _SceneAudit({required this.families});

  final Map<String, _FamilyAudit> families;

  factory _SceneAudit.fromScene(ResolvedScene scene) {
    final groups = <String, List<Rect>>{};
    for (final part in scene.parts) {
      final asset = scene.assets[part.catalogPart.appAssetPath];
      if (asset == null) {
        continue;
      }
      final bounds = part.localTransform.transformRect(
        Rect.fromLTWH(0, 0, asset.size.width, asset.size.height),
      );
      groups.putIfAbsent(part.catalogPart.family, () => []).add(bounds);
    }

    return _SceneAudit(
      families: {
        for (final entry in groups.entries)
          entry.key: _FamilyAudit(
            bounds: entry.value.reduce((a, b) => a.expandToInclude(b)),
          ),
      },
    );
  }

  _FamilyAudit family(String name) {
    final family = families[name];
    if (family == null) {
      throw StateError('Expected family $name in audited scene');
    }
    return family;
  }
}

class _FamilyAudit {
  const _FamilyAudit({required this.bounds});

  final Rect bounds;
}
