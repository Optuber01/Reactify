import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/csv_loaders.dart';
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
    'generated catalog contains the supported priority built-in head frames directly in CSV outputs',
    () async {
      final rows = [
        ...await CsvLoaders.loadAssetCsv(
          'assets/data/generated/render_parts.csv',
        ),
        ...await CsvLoaders.loadAssetCsv(
          'assets/data/generated/render_parts_extras.csv',
        ),
      ];
      final catalogFrames = <String>{
        for (final row in rows)
          if ((row['family'] ?? '').isNotEmpty &&
              (row['chooser_frame'] ?? '').isNotEmpty)
            '${row['family']}:${row['chooser_frame']}',
      };

      final missingSupported = <String>[];
      final explicitUnsupported = <String>[];

      for (final fixtureId in _priorityFixtureIds) {
        final state = await _loadStateForFixture(parser, fixtureId);
        for (final binding in _priorityBindings) {
          final frame = state.numeric(binding.field);
          if (frame <= 0) {
            continue;
          }
          final label = '$fixtureId ${binding.family}#$frame';
          if (_isExplicitlyUnsupported(binding.family, frame)) {
            explicitUnsupported.add(label);
            expect(
              catalogFrames.contains('${binding.family}:$frame'),
              isFalse,
              reason: '$label should stay explicit unsupported for now.',
            );
            continue;
          }
          if (!catalogFrames.contains('${binding.family}:$frame')) {
            missingSupported.add(label);
          }
        }
      }

      expect(missingSupported, isEmpty);
      expect(explicitUnsupported, contains('ramunade accessory3#63'));
    },
  );

  test(
    'priority built-ins resolve all supported head families in scenes',
    () async {
      final missingSupported = <String>[];

      for (final fixtureId in _priorityFixtureIds) {
        final state = await _loadStateForFixture(parser, fixtureId);
        final scene = await renderer.buildScene(state);
        final resolvedFamilies = resolvedFamilyCounts(scene).keys.toSet();

        for (final binding in _priorityBindings) {
          final frame = state.numeric(binding.field);
          if (frame <= 0) {
            continue;
          }
          final label = '$fixtureId ${binding.family}#$frame';
          if (_isExplicitlyUnsupported(binding.family, frame)) {
            expect(
              resolvedFamilies.contains(binding.family),
              isFalse,
              reason:
                  '$label should remain absent until helper-only frames gain source-backed art.',
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
    'priority built-in head-attached families stay near the head bounds',
    () async {
      for (final fixtureId in _priorityFixtureIds) {
        final state = await _loadStateForFixture(parser, fixtureId);
        final scene = await renderer.buildScene(state);
        final familyBounds = _familyBounds(scene);
        final headBounds = familyBounds['head_shape'];
        expect(headBounds, isNotNull, reason: '$fixtureId missing head_shape');
        final head = headBounds!;
        final inflatedHead = head.inflate(head.longestSide * 1.75);

        for (final binding in _priorityBindings) {
          final frame = state.numeric(binding.field);
          if (frame <= 0 || _isExplicitlyUnsupported(binding.family, frame)) {
            continue;
          }
          final bounds = familyBounds[binding.family];
          expect(
            bounds,
            isNotNull,
            reason: '$fixtureId missing ${binding.family}',
          );
          final rect = bounds!;
          final centerDistance = (rect.center - head.center).distance;
          expect(
            centerDistance,
            lessThan(head.longestSide * 2.25),
            reason:
                '$fixtureId ${binding.family} detached too far from the head.',
          );
          expect(
            rect.overlaps(inflatedHead) ||
                rect.inflate(24).overlaps(inflatedHead),
            isTrue,
            reason:
                '$fixtureId ${binding.family} no longer overlaps the expected head neighborhood.',
          );
        }
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

class _PriorityBinding {
  const _PriorityBinding(this.field, this.family);

  final String field;
  final String family;
}

const _priorityBindings = <_PriorityBinding>[
  _PriorityBinding('headshape', 'head_shape'),
  _PriorityBinding('fronthair', 'front_hair'),
  _PriorityBinding('rearhair', 'rear_hair'),
  _PriorityBinding('backhair', 'back_hair'),
  _PriorityBinding('ponytail', 'ponytail'),
  _PriorityBinding('ahoge', 'ahoge'),
  _PriorityBinding('eyes1x', 'left_eye'),
  _PriorityBinding('eyes2x', 'right_eye'),
  _PriorityBinding('eyebrows1x', 'left_eyebrow'),
  _PriorityBinding('eyebrows2x', 'right_eyebrow'),
  _PriorityBinding('hat', 'hat'),
  _PriorityBinding('glasses', 'glasses'),
  _PriorityBinding('accessory1x', 'accessory1'),
  _PriorityBinding('accessory2x', 'accessory2'),
  _PriorityBinding('accessory3x', 'accessory3'),
  _PriorityBinding('other1x', 'other1'),
  _PriorityBinding('other2x', 'other2'),
  _PriorityBinding('other3x', 'other3'),
  _PriorityBinding('other4x', 'other4'),
  _PriorityBinding('nose', 'nose'),
  _PriorityBinding('blush', 'blush'),
  _PriorityBinding('faceshadow', 'faceshadow'),
  _PriorityBinding('mouth', 'mouth'),
  _PriorityBinding('special', 'special'),
  _PriorityBinding('special2x', 'special2'),
];

const _unsupportedAllFramesFamilies = {'special', 'special2'};
const _unsupportedAccessoryHelperOnlyFrames = <int>{63, 64, 65, 66, 67};

bool _isExplicitlyUnsupported(String family, int frame) {
  if (_unsupportedAllFramesFamilies.contains(family)) {
    return true;
  }
  if (family.startsWith('accessory')) {
    return _unsupportedAccessoryHelperOnlyFrames.contains(frame);
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
