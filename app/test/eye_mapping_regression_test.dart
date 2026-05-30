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

  test(
    'source-backed eye leaf selections stay stable for default boy and key built-ins',
    () async {
      for (final entry in _expectedEyeLeafIds.entries) {
        final state = await _loadFixtureState(parser, entry.key);
        final resolved = renderer.resolveParts(state);
        for (final familyEntry in entry.value.entries) {
          expect(
            _leafIdsForFamily(resolved, familyEntry.key),
            unorderedEquals(familyEntry.value),
            reason: '${entry.key} ${familyEntry.key}',
          );
        }
      }
    },
  );

  test(
    'pupils use pupil fields, stay on the correct side, and built-ins do not collapse to default boy eyes',
    () async {
      final defaultBoyState = await _loadFixtureState(parser, 'default-boy');
      final defaultBoyParts = renderer.resolveParts(defaultBoyState);
      final defaultBoyLeafIds = _combinedEyeLeafIds(defaultBoyParts);

      final defaultGirlState = await _loadFixtureState(parser, 'default-girl');
      final defaultGirlParts = renderer.resolveParts(defaultGirlState);
      expect(_pupilLeafIds(defaultGirlParts, 'left_eye'), isEmpty);
      expect(_pupilLeafIds(defaultGirlParts, 'right_eye'), isEmpty);

      for (final fixtureId in _priorityFixtureIds) {
        final state = await _loadFixtureState(parser, fixtureId);
        final parts = renderer.resolveParts(state);

        expect(
          _pupilLeafIds(parts, 'left_eye').isEmpty,
          state.numeric('pupil1x') == 0,
          reason: '$fixtureId left pupil field mismatch',
        );
        expect(
          _pupilLeafIds(parts, 'right_eye').isEmpty,
          state.numeric('pupil2x') == 0,
          reason: '$fixtureId right pupil field mismatch',
        );

        if (fixtureId != 'default-boy') {
          expect(
            _combinedEyeLeafIds(parts),
            isNot(unorderedEquals(defaultBoyLeafIds)),
            reason: '$fixtureId unexpectedly rendered Default Boy eye assets.',
          );
        }

        if (state.numeric('pupil1x') > 0 && state.numeric('pupil2x') > 0) {
          final scene = await renderer.buildScene(state);
          final leftBounds = _combinedBounds(
            scene,
            family: 'left_eye',
            partRolePrefix: 'pupil_',
          );
          final rightBounds = _combinedBounds(
            scene,
            family: 'right_eye',
            partRolePrefix: 'pupil_',
          );
          expect(
            leftBounds,
            isNotNull,
            reason: '$fixtureId missing left pupil',
          );
          expect(
            rightBounds,
            isNotNull,
            reason: '$fixtureId missing right pupil',
          );
          expect(
            leftBounds!.center.dx,
            lessThan(rightBounds!.center.dx),
            reason: '$fixtureId pupil sides swapped or detached',
          );
        }
      }
    },
  );
}

const _priorityFixtureIds = <String>[
  'default-boy',
  'gacha-dj-girl',
  'gacha-dj-boy',
  'limea',
  'default-girl',
  'luni',
  'ramunade',
  'yuni',
];

const _expectedEyeLeafIds = <String, Map<String, Set<String>>>{
  'default-boy': {
    'left_eye': {
      '16593',
      '16594',
      '16596',
      '16598',
      '16599',
      '16601',
      '16831',
      '16832',
      '16837',
    },
    'right_eye': {
      '16593',
      '16594',
      '16596',
      '16598',
      '16599',
      '16601',
      '16831',
      '16832',
      '16837',
    },
  },
  'luni': {
    'left_eye': {
      '16663',
      '16665',
      '16865',
      '16868',
      '16870',
      '16871',
      '16873',
      '16874',
    },
    'right_eye': {
      '16663',
      '16665',
      '16865',
      '16867',
      '16868',
      '16871',
      '16875',
      '16876',
    },
  },
  'ramunade': {
    'left_eye': {
      '16631',
      '16633',
      '17654',
      '17655',
      '17657',
      '17659',
      '17660',
      '17662',
    },
    'right_eye': {'16631', '16633', '17108', '17110'},
  },
};

Future<GachaCharacterState> _loadFixtureState(
  GachaCodeParser parser,
  String fixtureId,
) async {
  final code = await rootBundle.loadString(
    'fixtures/builtin/$fixtureId.gc.txt',
  );
  return parser.parse(code);
}

Set<String> _leafIdsForFamily(List<ResolvedRenderPart> parts, String family) =>
    {
      for (final part in parts)
        if (part.catalogPart.family == family) part.catalogPart.leafId,
    };

Set<String> _pupilLeafIds(List<ResolvedRenderPart> parts, String family) => {
  for (final part in parts)
    if (part.catalogPart.family == family &&
        part.catalogPart.partRole.startsWith('pupil_'))
      part.catalogPart.leafId,
};

Set<String> _combinedEyeLeafIds(List<ResolvedRenderPart> parts) => {
  ..._leafIdsForFamily(parts, 'left_eye'),
  ..._leafIdsForFamily(parts, 'right_eye'),
};

Rect? _combinedBounds(
  ResolvedScene scene, {
  required String family,
  String? partRolePrefix,
}) {
  Rect? bounds;
  for (final part in scene.parts) {
    if (part.catalogPart.family != family) {
      continue;
    }
    if (partRolePrefix != null &&
        !part.catalogPart.partRole.startsWith(partRolePrefix)) {
      continue;
    }
    final asset = scene.assets[part.catalogPart.appAssetPath];
    if (asset == null) {
      continue;
    }
    final rect = part.localTransform.transformRect(
      Rect.fromLTWH(0, 0, asset.size.width, asset.size.height),
    );
    bounds = bounds == null ? rect : bounds.expandToInclude(rect);
  }
  return bounds;
}
