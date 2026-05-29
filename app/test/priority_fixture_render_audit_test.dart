import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/render_part.dart';
import 'package:reactify_gacha/src/gacha/ui/editor_helpers.dart';

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
    'priority built-ins resolve supported body outerwear and prop families',
    () async {
      final missingSupported = <String>[];

      for (final fixtureId in _priorityFixtureIds) {
        final state = await _loadStateForFixture(parser, fixtureId);
        final scene = await renderer.buildScene(state);
        final resolvedFamilies = resolvedFamilyCounts(scene).keys.toSet();

        for (final binding in _bodyBindings) {
          final frame = state.numeric(binding.field);
          if (frame <= 0) {
            continue;
          }
          final label = '$fixtureId ${binding.family}#$frame';
          if (_isExplicitlyUnsupported(binding.family, frame)) {
            expect(
              resolvedFamilies.contains(binding.family),
              isFalse,
              reason: '$label should stay explicitly unsupported.',
            );
            continue;
          }
          if (!resolvedFamilies.contains(binding.family)) {
            missingSupported.add(label);
          }
        }
      }

      expect(missingSupported, isEmpty);
    },
  );

  test(
    'priority fixtures keep props outerwear and hair attachments near expected anchors',
    () async {
      for (final fixtureId in _priorityFixtureIds) {
        final state = await _loadStateForFixture(parser, fixtureId);
        final scene = await renderer.buildScene(state);
        final bounds = _familyBounds(scene);
        final head = bounds['head_shape'];
        final body = bounds['body_base'];
        expect(head, isNotNull, reason: '$fixtureId missing head_shape');
        expect(body, isNotNull, reason: '$fixtureId missing body_base');

        final backHair = bounds['back_hair'];
        if (state.numeric('backhair') > 0 && backHair != null) {
          expect(
            (backHair.center - head!.center).distance,
            lessThan(head.longestSide * 1.75),
            reason: '$fixtureId back_hair detached from the head stack.',
          );
        }
        final ponytail = bounds['ponytail'];
        if (state.numeric('ponytail') > 0 && ponytail != null) {
          expect(
            (ponytail.center - head!.center).distance,
            lessThan(head.longestSide * 2.1),
            reason: '$fixtureId ponytail detached from the head stack.',
          );
        }
        final cape = bounds['cape'];
        if (state.numeric('cape') > 0 && cape != null) {
          expect(
            cape.inflate(24).overlaps(body!.inflate(body.longestSide * 0.45)),
            isTrue,
            reason: '$fixtureId cape drifted too far from the body.',
          );
        }
        final tail = bounds['tail'];
        if (state.numeric('tail') > 0 && tail != null) {
          expect(
            tail.inflate(24).overlaps(body!.inflate(body.longestSide * 0.55)),
            isTrue,
            reason: '$fixtureId tail drifted too far from the body.',
          );
        }
        final wings = bounds['wings1'];
        if (state.numeric('wings1x') > 0 && wings != null) {
          expect(
            wings.inflate(24).overlaps(body!.inflate(body.longestSide * 0.65)),
            isTrue,
            reason: '$fixtureId wings1 drifted too far from the body.',
          );
        }
        final frontWeapon = bounds['weapon_front'];
        if (state.numeric('weapon1x') > 0 && frontWeapon != null) {
          final hand = bounds['hand_front_base'];
          expect(hand, isNotNull, reason: '$fixtureId missing hand_front_base');
          expect(
            (frontWeapon.center - hand!.center).distance,
            lessThan(body!.longestSide * 1.6),
            reason: '$fixtureId weapon_front detached from the front hand.',
          );
        }
        final backWeapon = bounds['weapon_back'];
        if (state.numeric('weapon2x') > 0 && backWeapon != null) {
          final hand = bounds['hand_back_base'];
          expect(hand, isNotNull, reason: '$fixtureId missing hand_back_base');
          expect(
            (backWeapon.center - hand!.center).distance,
            lessThan(body!.longestSide * 1.8),
            reason: '$fixtureId weapon_back detached from the back hand.',
          );
        }
        final shield = bounds['shield'];
        if (state.numeric('shield') > 0 && shield != null) {
          final hand = bounds['hand_back_base'];
          expect(hand, isNotNull, reason: '$fixtureId missing hand_back_base');
          expect(
            (shield.center - hand!.center).distance,
            lessThan(body!.longestSide * 1.5),
            reason: '$fixtureId shield detached from the back hand.',
          );
        }
      }
    },
  );

  test(
    'source-backed representative families keep the expected leaf selections',
    () {
      expect(
        _filteredLeafIds(tables.partsFor('glove_front', 2), {'hand1x': 1}),
        equals({'7154', '7150', '7156'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('knee_front', 14), const {}),
        equals({'10770', '77', '10772'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('cape', 9), const {}),
        equals({'5513', '5515', '5517'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('tail', 62), const {}),
        equals({'6179', '77', '6181'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('wings1', 56), const {}),
        equals({'6697', '77', '6699'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('weapon_front', 253), const {}),
        equals({'9220', '9222', '9224', '9225'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('ponytail', 53), const {}),
        equals({'4554', '4556', '4558'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('hat', 2), const {}),
        equals({'3610', '3612', '3614'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('glasses', 48), const {}),
        equals({'19676'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('other1', 12), const {}),
        equals({'13605', '13607', '13609'}),
      );
      expect(
        _filteredLeafIds(tables.partsFor('accessory1', 116), const {}),
        equals({'15195', '15197', '15199'}),
      );
    },
  );

  test(
    'gacha dj and limea regressions keep previously missing families alive',
    () async {
      for (final fixtureId in const [
        'gacha-dj-girl',
        'gacha-dj-boy',
        'limea',
      ]) {
        final scene = await renderer.buildScene(
          await _loadStateForFixture(parser, fixtureId),
        );
        final families = resolvedFamilyCounts(scene).keys.toSet();
        if (fixtureId.startsWith('gacha-dj')) {
          expect(families.contains('wings1'), isTrue, reason: fixtureId);
          expect(families.contains('wings2'), isTrue, reason: fixtureId);
        }
        if (fixtureId == 'limea') {
          expect(families.contains('cape'), isTrue, reason: fixtureId);
          expect(families.contains('tail'), isTrue, reason: fixtureId);
        }
        expect(
          scene.warnings.any(
            (warning) => warning.contains('Head flip variants remain'),
          ),
          isFalse,
          reason: fixtureId,
        );
      }
    },
  );
}

const _priorityFixtureIds = <String>[
  'gacha-dj-girl',
  'gacha-dj-boy',
  'limea',
  'default-girl',
  'luni',
  'ramunade',
  'yuni',
  'default-boy',
];

class _FixtureBinding {
  const _FixtureBinding(this.field, this.family);

  final String field;
  final String family;
}

const _bodyBindings = <_FixtureBinding>[
  _FixtureBinding('shirt', 'body_shirt'),
  _FixtureBinding('shirtex', 'body_jacket'),
  _FixtureBinding('sleeves1x', 'upper_sleeve_front'),
  _FixtureBinding('sleeves2x', 'upper_sleeve_back'),
  _FixtureBinding('gloves1x', 'glove_front'),
  _FixtureBinding('gloves2x', 'glove_back'),
  _FixtureBinding('wrist1x', 'wrist_front'),
  _FixtureBinding('wrist2x', 'wrist_back'),
  _FixtureBinding('pants1x', 'body_pants'),
  _FixtureBinding('pants1x', 'thigh_pants_front'),
  _FixtureBinding('pants2x', 'thigh_pants_back'),
  _FixtureBinding('socks1x', 'thigh_socks_front'),
  _FixtureBinding('socks2x', 'thigh_socks_back'),
  _FixtureBinding('shoes1x', 'shoe_front'),
  _FixtureBinding('shoes2x', 'shoe_back'),
  _FixtureBinding('knee1x', 'knee_front'),
  _FixtureBinding('knee2x', 'knee_back'),
  _FixtureBinding('cape', 'cape'),
  _FixtureBinding('tail', 'tail'),
  _FixtureBinding('wings1x', 'wings1'),
  _FixtureBinding('wings2x', 'wings2'),
  _FixtureBinding('shield', 'shield'),
  _FixtureBinding('weapon1x', 'weapon_front'),
  _FixtureBinding('weapon2x', 'weapon_back'),
  _FixtureBinding('backhair', 'back_hair'),
  _FixtureBinding('ponytail', 'ponytail'),
];

const _unsupportedFamilies = {'special', 'special2'};

bool _isExplicitlyUnsupported(String family, int frame) {
  if (_unsupportedFamilies.contains(family)) {
    return true;
  }
  return false;
}

Future<GachaCharacterState> _loadStateForFixture(
  GachaCodeParser parser,
  String fixtureId,
) async {
  final code = await rootBundle.loadString(
    'fixtures/builtin/$fixtureId.gc.txt',
  );
  return parser.parse(code);
}

Set<String> _filteredLeafIds(
  List<RenderCatalogPart> parts,
  Map<String, int> requiredFieldValues,
) {
  return {
    for (final part in parts)
      if (requiredFieldValues.entries.every(
        (entry) =>
            part.dependencyField != entry.key ||
            part.dependencyValue == entry.value,
      ))
        part.leafId,
  };
}

Map<String, Rect> _familyBounds(ResolvedScene scene) {
  final result = <String, Rect>{};
  for (final part in scene.parts) {
    final asset = scene.assets[part.catalogPart.appAssetPath];
    if (asset == null) {
      continue;
    }
    final bounds = part.worldTransform.transformRect(
      Rect.fromLTWH(0, 0, asset.size.width, asset.size.height),
    );
    result.update(
      part.catalogPart.family,
      (current) => current.expandToInclude(bounds),
      ifAbsent: () => bounds,
    );
  }
  return result;
}
