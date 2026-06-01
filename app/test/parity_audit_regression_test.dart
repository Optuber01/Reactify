import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/render_part.dart';

import 'support/parity_audit_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ResolverTables tables;
  late GachaCodeParser parser;
  late CharacterRenderer renderer;
  late List<PriorityFixtureContext> fixtures;
  late GeneratedPriorityAuditArtifacts artifacts;

  setUpAll(() async {
    tables = await ResolverTables.load();
    parser = GachaCodeParser(tables.schema);
    renderer = CharacterRenderer(tables: tables, assetStore: GachaAssetStore());
    fixtures = await loadPriorityFixtureContexts(
      tables: tables,
      parser: parser,
      renderer: renderer,
    );
    artifacts = await generatePriorityAuditArtifacts(
      tables: tables,
      parser: parser,
      renderer: renderer,
    );
  });

  test(
    'audit report generation writes the priority parity matrix and contact sheets',
    () {
      expect(
        fixtures.map((fixture) => fixture.descriptor.id),
        priorityFixtureIds,
      );
      expect(File(artifacts.matrixJsonPath).existsSync(), isTrue);
      expect(File(artifacts.matrixMdPath).existsSync(), isTrue);
      expect(artifacts.contactSheetPaths, hasLength(priorityFixtureIds.length));
      expect(
        artifacts.matrixJson['fixtures'],
        hasLength(priorityFixtureIds.length),
      );
    },
  );

  test(
    'pupil regression keeps selected pupil families on the correct eye for three priority fixtures',
    () {
      for (final fixtureId in ['limea', 'luni', 'yuni']) {
        final fixture = _fixtureById(fixtures, fixtureId);
        final state = fixture.state;
        expect(state.numeric('pupil1x'), greaterThan(0), reason: fixtureId);
        expect(state.numeric('pupil2x'), greaterThan(0), reason: fixtureId);

        final left = _familyParts(fixture.scene, 'left_eye')
            .where((part) => part.catalogPart.partRole.startsWith('pupil_'))
            .toList(growable: false);
        final right = _familyParts(fixture.scene, 'right_eye')
            .where((part) => part.catalogPart.partRole.startsWith('pupil_'))
            .toList(growable: false);
        expect(left, isNotEmpty, reason: '$fixtureId missing left pupil');
        expect(right, isNotEmpty, reason: '$fixtureId missing right pupil');

        final leftBounds = _partsBounds(fixture.scene, left)!;
        final rightBounds = _partsBounds(fixture.scene, right)!;
        expect(
          leftBounds.center.dx,
          lessThan(rightBounds.center.dx),
          reason: '$fixtureId pupil sides swapped',
        );
      }
    },
  );

  test(
    'shirt logo regression keeps selected logo families renderable with source-backed tint and placement fields',
    () {
      final fixtureJsonById = {
        for (final fixture in artifacts.matrixJson['fixtures'] as List<dynamic>)
          (fixture as Map<String, dynamic>)['id'] as String: fixture,
      };

      for (final fixtureId in [
        'default-girl',
        'gacha-dj-girl',
        'gacha-dj-boy',
        'luni',
      ]) {
        final fixture = _fixtureById(fixtures, fixtureId);
        final state = fixture.state;
        expect(state.numeric('logo'), greaterThan(0), reason: fixtureId);

        final parts = _familyParts(fixture.scene, 'body_logo');
        expect(parts, isNotEmpty, reason: '$fixtureId missing body_logo');
        expect(
          parts.every(
            (part) => part.catalogPart.chooserFrame == state.numeric('logo'),
          ),
          isTrue,
          reason: '$fixtureId body_logo chooser mismatch',
        );
        expect(
          parts.every((part) => part.catalogPart.hostName == 'body'),
          isTrue,
          reason: '$fixtureId body_logo host mismatch',
        );
        expect(
          parts.every((part) => part.catalogPart.tintChannel == 'logocolorx'),
          isTrue,
          reason: '$fixtureId body_logo tint channel drifted',
        );
        expect(
          parts.every(
            (part) => part.catalogPart.appAssetPath.contains('/clothes/'),
          ),
          isTrue,
          reason: '$fixtureId body_logo asset folder drifted',
        );

        final auditFixture = fixtureJsonById[fixtureId] as Map<String, dynamic>;
        final clothesGroup = (auditFixture['groups'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((group) => group['group'] == 'Clothes');
        final bodyLogoRow = (clothesGroup['rows'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((row) => row['family'] == 'body_logo');
        final selectedFieldValues =
            bodyLogoRow['selected_field_values'] as Map<String, dynamic>;
        expect(bodyLogoRow['issue_classification'], 'OK');
        expect(selectedFieldValues['logopos'], state.numeric('logopos'));
        expect(
          selectedFieldValues['logocolorx'],
          state.rawValue(tables.schema, 'logocolorx'),
        );
      }
    },
  );

  test(
    'hat and head accessories stay attached to the head stack and remain above the head layer',
    () {
      for (final fixtureId in [
        'gacha-dj-girl',
        'gacha-dj-boy',
        'luni',
        'ramunade',
        'yuni',
      ]) {
        final fixture = _fixtureById(fixtures, fixtureId);
        final bounds = familyBoundsForScene(
          fixture.scene,
          fixture.state,
          tables,
        );
        final head = bounds['head_shape'];
        expect(head, isNotNull, reason: fixtureId);
        for (final family in [
          'hat',
          'accessory1',
          'accessory2',
          'accessory3',
          'other1',
          'other2',
          'other3',
          'other4',
        ]) {
          final parts = _familyParts(fixture.scene, family);
          if (parts.isEmpty) {
            continue;
          }
          final familyBounds = _partsBounds(fixture.scene, parts)!;
          expect(
            (familyBounds.center - head!.center).distance,
            lessThan(head.longestSide * 1.8),
            reason: '$fixtureId $family detached from head',
          );
          expect(
            _minDepth(parts),
            greaterThan(_minDepth(_familyParts(fixture.scene, 'head_shape'))),
            reason: '$fixtureId $family slipped behind the head base',
          );
        }
      }
    },
  );

  test(
    'weapon back audit rows keep source-backed prop transforms and folder mapping',
    () {
      final fixtureJsonById = {
        for (final fixture in artifacts.matrixJson['fixtures'] as List<dynamic>)
          (fixture as Map<String, dynamic>)['id'] as String: fixture,
      };

      for (final fixtureId in [
        'gacha-dj-girl',
        'gacha-dj-boy',
        'limea',
        'luni',
      ]) {
        final fixture = _fixtureById(fixtures, fixtureId);
        final back = _familyParts(fixture.scene, 'weapon_back');
        expect(back, isNotEmpty, reason: '$fixtureId missing weapon_back');
        expect(
          back.every(
            (part) => part.catalogPart.appAssetPath.contains('/props/'),
          ),
          isTrue,
          reason: '$fixtureId weapon_back asset folder drifted',
        );

        final auditFixture = fixtureJsonById[fixtureId] as Map<String, dynamic>;
        final propsGroup = (auditFixture['groups'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((group) => group['group'] == 'Props');
        final backRow = (propsGroup['rows'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((row) => row['family'] == 'weapon_back');
        expect(backRow['issue_classification'], 'OK');
      }
    },
  );

  test(
    'ponytail and back hair stay attached and remain behind front hair when selected',
    () {
      for (final fixtureId in [
        'default-girl',
        'gacha-dj-girl',
        'gacha-dj-boy',
      ]) {
        final fixture = _fixtureById(fixtures, fixtureId);
        final bounds = familyBoundsForScene(
          fixture.scene,
          fixture.state,
          tables,
        );
        final head = bounds['head_shape'];
        expect(head, isNotNull, reason: fixtureId);

        final backHair = _familyParts(fixture.scene, 'back_hair');
        if (backHair.isNotEmpty) {
          final backBounds = _partsBounds(fixture.scene, backHair)!;
          expect(
            (backBounds.center - head!.center).distance,
            lessThan(head.longestSide * 1.8),
            reason: '$fixtureId back_hair detached from head',
          );
        }

        final ponytail = _familyParts(fixture.scene, 'ponytail');
        if (ponytail.isNotEmpty) {
          final ponytailBounds = _partsBounds(fixture.scene, ponytail)!;
          expect(
            (ponytailBounds.center - head!.center).distance,
            lessThan(head.longestSide * 1.7),
            reason: '$fixtureId ponytail detached from head',
          );
        }

        final frontHair = _familyParts(fixture.scene, 'front_hair');
        if (frontHair.isNotEmpty && ponytail.isNotEmpty) {
          expect(
            _maxDepth(ponytail),
            lessThan(_minDepth(frontHair)),
            reason: '$fixtureId ponytail moved in front of front hair',
          );
        }
      }
    },
  );

  test(
    'accessory helper-only frames remain explicitly unsupported with source evidence',
    () {
      final fixtureJsonById = {
        for (final fixture in artifacts.matrixJson['fixtures'] as List<dynamic>)
          (fixture as Map<String, dynamic>)['id'] as String: fixture,
      };
      final auditFixture = fixtureJsonById['ramunade'] as Map<String, dynamic>;
      final otherGroup = (auditFixture['groups'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((group) => group['group'] == 'Other');
      final row = (otherGroup['rows'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((entry) => entry['family'] == 'accessory3');
      expect(row['selected_chooser_frame'], 63);
      expect(row['issue_classification'], 'unsupported');
      expect(
        (row['notes'] as List<dynamic>).join(' '),
        contains('helper-only leaves 50/77'),
      );
      expect(
        (row['notes'] as List<dynamic>).join(' '),
        contains('excluded_leaf_evidence.csv'),
      );
    },
  );

  test(
    'special and special2 remain explicitly unsupported in the audit with evidence',
    () {
      final fixtureJsonById = {
        for (final fixture in artifacts.matrixJson['fixtures'] as List<dynamic>)
          (fixture as Map<String, dynamic>)['id'] as String: fixture,
      };

      for (final fixtureId in ['gacha-dj-boy', 'limea', 'luni', 'ramunade']) {
        final fixture = _fixtureById(fixtures, fixtureId);
        expect(
          fixture.scene.warnings,
          contains('Special effects are not rendered yet.'),
          reason: fixtureId,
        );

        final auditFixture = fixtureJsonById[fixtureId] as Map<String, dynamic>;
        final effectGroup = (auditFixture['groups'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((group) => group['group'] == 'Effects / Special');
        final rows = (effectGroup['rows'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(
          rows.where((row) => row['issue_classification'] == 'unsupported'),
          isNotEmpty,
          reason:
              '$fixtureId should mark missing special families as unsupported',
        );
      }
    },
  );
}

PriorityFixtureContext _fixtureById(
  List<PriorityFixtureContext> fixtures,
  String id,
) {
  return fixtures.firstWhere((fixture) => fixture.descriptor.id == id);
}

List<ResolvedRenderPart> _familyParts(ResolvedScene scene, String family) {
  return scene.parts
      .where((part) => part.catalogPart.family == family)
      .toList(growable: false);
}

Rect? _partsBounds(ResolvedScene scene, List<ResolvedRenderPart> parts) {
  Rect? result;
  for (final part in parts) {
    final asset = scene.assets[part.catalogPart.appAssetPath];
    if (asset == null) {
      continue;
    }
    final bounds = part.localTransform.transformRect(
      Rect.fromLTWH(0, 0, asset.size.width, asset.size.height),
    );
    result = result == null ? bounds : result.expandToInclude(bounds);
  }
  return result;
}

int _minDepth(List<ResolvedRenderPart> parts) =>
    parts.map((part) => part.globalDepth).reduce(math.min);
int _maxDepth(List<ResolvedRenderPart> parts) =>
    parts.map((part) => part.globalDepth).reduce(math.max);
