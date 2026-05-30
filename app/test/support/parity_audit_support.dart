import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_code_parser.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_field_schema.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';
import 'package:reactify_gacha/src/gacha/render/character_renderer.dart';
import 'package:reactify_gacha/src/gacha/render/render_part.dart';
import 'package:reactify_gacha/src/gacha/render/transform_graph.dart';
import 'package:reactify_gacha/src/gacha/ui/editor_helpers.dart';
import 'world_transform_helper.dart';

const priorityFixtureIds = <String>[
  'default-girl',
  'gacha-dj-girl',
  'gacha-dj-boy',
  'limea',
  'luni',
  'ramunade',
  'yuni',
];

const knownUnsupportedFamilies = <String>{'special', 'special2'};
const _helperOnlyAccessoryFrames = <int>{63, 64, 65, 66, 67};

const auditGroupOrder = <String>[
  'Body / Pose',
  'Hair',
  'Face',
  'Clothes',
  'Other',
  'Props',
  'Effects / Special',
];

class PriorityFixtureContext {
  const PriorityFixtureContext({
    required this.descriptor,
    required this.state,
    required this.scene,
    required this.tables,
  });

  final ValidationCaseDescriptor descriptor;
  final GachaCharacterState state;
  final ResolvedScene scene;
  final ResolverTables tables;
}

class GeneratedPriorityAuditArtifacts {
  const GeneratedPriorityAuditArtifacts({
    required this.fixtures,
    required this.matrixJsonPath,
    required this.matrixMdPath,
    required this.contactSheetPaths,
    required this.matrixJson,
  });

  final List<PriorityFixtureContext> fixtures;
  final String matrixJsonPath;
  final String matrixMdPath;
  final List<String> contactSheetPaths;
  final Map<String, dynamic> matrixJson;
}

Future<List<PriorityFixtureContext>> loadPriorityFixtureContexts({
  required ResolverTables tables,
  required GachaCodeParser parser,
  required CharacterRenderer renderer,
}) async {
  final byId = {
    for (final fixture in tables.builtinFixtures) fixture.id: fixture,
  };
  final result = <PriorityFixtureContext>[];
  for (final id in priorityFixtureIds) {
    final descriptor = byId[id];
    if (descriptor == null) {
      throw StateError('Missing curated builtin fixture $id');
    }
    final code = await rootBundle.loadString(descriptor.fixtureAsset);
    final state = parser.parse(code);
    final scene = await renderer.buildScene(state);
    result.add(
      PriorityFixtureContext(
        descriptor: descriptor,
        state: state,
        scene: scene,
        tables: tables,
      ),
    );
  }
  return result;
}

Future<GeneratedPriorityAuditArtifacts> generatePriorityAuditArtifacts({
  required ResolverTables tables,
  required GachaCodeParser parser,
  required CharacterRenderer renderer,
  String builtinOutputDirPath = 'tmp/render_exports/builtin',
  String contactSheetDirPath = 'tmp/render_exports/audit_contact_sheets',
}) async {
  final fixtures = await loadPriorityFixtureContexts(
    tables: tables,
    parser: parser,
    renderer: renderer,
  );
  final builtinOutputDir = Directory(builtinOutputDirPath)
    ..createSync(recursive: true);
  final contactSheetDir = Directory(contactSheetDirPath);
  if (contactSheetDir.existsSync()) {
    contactSheetDir.deleteSync(recursive: true);
  }
  contactSheetDir.createSync(recursive: true);

  final matrixJson = buildPriorityAuditMatrixJson(
    tables: tables,
    fixtures: fixtures,
  );
  final matrixMd = buildPriorityAuditMatrixMarkdown(matrixJson);

  final matrixJsonPath = '${builtinOutputDir.path}/parity_audit_matrix.json';
  final matrixMdPath = '${builtinOutputDir.path}/parity_audit_matrix.md';
  File(
    matrixJsonPath,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(matrixJson));
  File(matrixMdPath).writeAsStringSync(matrixMd);

  final contactSheetPaths = <String>[];
  for (final fixture in fixtures) {
    final path =
        '${contactSheetDir.path}/${fixture.descriptor.id}_contact_sheet.png';
    await writeContactSheetForFixture(fixture: fixture, path: path);
    contactSheetPaths.add(path);
  }

  return GeneratedPriorityAuditArtifacts(
    fixtures: fixtures,
    matrixJsonPath: matrixJsonPath,
    matrixMdPath: matrixMdPath,
    contactSheetPaths: contactSheetPaths,
    matrixJson: matrixJson,
  );
}

Map<String, dynamic> buildPriorityAuditMatrixJson({
  required ResolverTables tables,
  required List<PriorityFixtureContext> fixtures,
}) {
  return {
    'generated_at': DateTime.now().toIso8601String(),
    'fixture_ids': priorityFixtureIds,
    'known_unsupported_families': knownUnsupportedFamilies.toList()..sort(),
    'fixtures': [
      for (final fixture in fixtures) _fixtureAuditJson(tables, fixture),
    ],
  };
}

String buildPriorityAuditMatrixMarkdown(Map<String, dynamic> json) {
  final buffer = StringBuffer();
  buffer.writeln('# Built-in parity audit matrix');
  buffer.writeln();
  buffer.writeln('Generated: ${json['generated_at']}  ');
  buffer.writeln(
    'Priority fixtures: ${(json['fixture_ids'] as List).join(', ')}',
  );
  buffer.writeln();

  for (final fixture in json['fixtures'] as List<dynamic>) {
    final fixtureMap = fixture as Map<String, dynamic>;
    buffer.writeln('## ${fixtureMap['display_name']} (`${fixtureMap['id']}`)');
    buffer.writeln();
    buffer.writeln('- Fixture asset: `${fixtureMap['fixture_asset']}`');
    buffer.writeln(
      '- Warnings: ${_markdownList(fixtureMap['warnings'] as List<dynamic>)}',
    );
    buffer.writeln();

    for (final group in fixtureMap['groups'] as List<dynamic>) {
      final groupMap = group as Map<String, dynamic>;
      buffer.writeln('### ${groupMap['group']}');
      buffer.writeln();
      buffer.writeln(
        '- Expected families: ${_markdownList(groupMap['expected_families'] as List<dynamic>)}',
      );
      buffer.writeln(
        '- Resolved families: ${_markdownList(groupMap['resolved_families'] as List<dynamic>)}',
      );
      buffer.writeln();
      buffer.writeln(
        '| Family | Fields | Frame | Leaf IDs | Assets | Tint | Host | Transform | Depth | Bounds vs refs | Classification | Notes |',
      );
      buffer.writeln(
        '| --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
      );
      for (final row in groupMap['rows'] as List<dynamic>) {
        final rowMap = row as Map<String, dynamic>;
        buffer.writeln(
          '| `${rowMap['family']}` '
          '| ${_escapeMarkdown(_inlineFieldMap(rowMap['selected_field_values'] as Map<String, dynamic>))} '
          '| ${rowMap['selected_chooser_frame'] ?? ''} '
          '| ${_escapeMarkdown(_joinList(rowMap['selected_leaf_ids'] as List<dynamic>))} '
          '| ${_escapeMarkdown(_joinList(rowMap['asset_paths'] as List<dynamic>, maxItems: 3))} '
          '| ${_escapeMarkdown(_joinList(rowMap['tint_channels'] as List<dynamic>))} '
          '| ${_escapeMarkdown(_hostSummary(rowMap['host'] as Map<String, dynamic>))} '
          '| ${_escapeMarkdown(_transformSummary(rowMap['runtime_transform_summary'] as Map<String, dynamic>?))} '
          '| ${_escapeMarkdown(_depthSummaryLabel(rowMap['depth_global_order'] as Map<String, dynamic>?))} '
          '| ${_escapeMarkdown(_boundsSummary(rowMap['bounds_relative'] as Map<String, dynamic>))} '
          '| ${rowMap['issue_classification']} '
          '| ${_escapeMarkdown(_joinList(rowMap['notes'] as List<dynamic>, maxItems: 3))} |',
        );
      }
      buffer.writeln();
    }
  }

  return buffer.toString();
}

Map<String, dynamic> auditSummaryWithCatalog({
  required ResolverTables tables,
  required PriorityFixtureContext fixture,
}) {
  final unresolved =
      expectedRenderableFamiliesForState(
          tables,
          fixture.state,
        ).difference(resolvedFamilyCounts(fixture.scene).keys.toSet()).toList()
        ..sort();
  final unsupported = unsupportedFamiliesForState(
    tables,
    fixture.state,
  ).toList()..sort();
  final familyBounds = familyBoundsForScene(fixture.scene, fixture.state, tables);
  final suspicious = <Map<String, dynamic>>[];
  final world = fixture.scene.worldBounds;
  for (final entry in familyBounds.entries) {
    final bounds = entry.value;
    final detached =
        (bounds.center - world.center).distance > (world.longestSide * 0.85);
    final outlierSize =
        bounds.width > world.width * 0.9 || bounds.height > world.height * 0.9;
    if (detached || outlierSize) {
      suspicious.add({
        'family': entry.key,
        'bounds': rectJson(bounds),
        'detached': detached,
        'oversized': outlierSize,
      });
    }
  }

  return {
    'id': fixture.descriptor.id,
    'display_name': fixture.descriptor.displayName,
    'fixture_asset': fixture.descriptor.fixtureAsset,
    'feature_tags': fixture.descriptor.featureTags,
    'part_count': fixture.scene.parts.length,
    'resolved_families': resolvedFamilyCounts(fixture.scene).keys.toList()
      ..sort(),
    'resolved_family_counts': Map.fromEntries(
      (resolvedFamilyCounts(fixture.scene).entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key)))
          .map((entry) => MapEntry(entry.key, entry.value)),
    ),
    'unresolved_expected_families': unresolved,
    'unsupported_selected_families': unsupported,
    'warnings': fixture.scene.warnings,
    'world_bounds': rectJson(world),
    'suspicious_detached_bounds_outliers': suspicious,
  };
}

Set<String> expectedRenderableFamiliesForState(
  ResolverTables tables,
  GachaCharacterState state,
) {
  final expected = <String>{};
  for (final config in _auditFamilyConfigs) {
    if (!config.isActive(state)) {
      continue;
    }
    final frame = config.chooserFrame(state);
    if (frame <= 0) {
      continue;
    }
    if (tables.partsFor(config.family, frame).isNotEmpty ||
        config.includeWhenCatalogMissing) {
      expected.add(config.family);
    }
  }
  return expected;
}

Set<String> unsupportedFamiliesForState(
  ResolverTables tables,
  GachaCharacterState state,
) {
  final unsupported = <String>{};
  for (final config in _auditFamilyConfigs) {
    if (!config.isActive(state)) {
      continue;
    }
    final frame = config.chooserFrame(state);
    if (frame <= 0) {
      continue;
    }
    final familyFrames = tables.catalogByFamilyFrame[config.family];
    if (familyFrames == null || familyFrames.isEmpty) {
      unsupported.add(config.family);
    }
  }
  return unsupported;
}

Map<String, Rect> familyBoundsForScene(ResolvedScene scene, GachaCharacterState state, ResolverTables tables) {
  final result = <String, Rect>{};
  for (final part in scene.parts) {
    final asset = scene.assets[part.catalogPart.appAssetPath];
    if (asset == null) {
      continue;
    }
    final worldTransform = resolveTestWorldTransform(part, state, tables);
    final bounds = worldTransform.transformRect(
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

Map<String, double> rectJson(Rect rect) => {
  'left': rect.left,
  'top': rect.top,
  'right': rect.right,
  'bottom': rect.bottom,
  'width': rect.width,
  'height': rect.height,
};

Future<ui.Image> renderSceneToImage(
  ResolvedScene scene,
  ui.Size size,
  GachaCharacterState state,
  ResolverTables tables, {
  Set<String>? includeFamilies,
  Set<String>? contextFamilies,
  Rect? focusBounds,
  String? title,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final background = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
  final sheet = ui.Rect.fromLTWH(0, 0, size.width, size.height);
  canvas.drawRect(sheet, background);

  final filteredParts = [
    for (final part in scene.parts)
      if (includeFamilies == null ||
          includeFamilies.contains(part.catalogPart.family))
        part,
  ];
  final contextParts = [
    for (final part in scene.parts)
      if (contextFamilies != null &&
          contextFamilies.contains(part.catalogPart.family))
        part,
  ];
  final cameraBounds =
      focusBounds ??
      _partsBounds(scene, [...contextParts, ...filteredParts]) ??
      scene.worldBounds;

  if (!cameraBounds.isEmpty) {
    final paddedBounds = cameraBounds.inflate(32);
    const availableTop = 16.0;
    final scale = math.min(
      (size.width - 32) / math.max(paddedBounds.width, 1),
      (size.height - availableTop - 16) / math.max(paddedBounds.height, 1),
    );
    final camera = AffineMatrix.translation(
      (size.width - paddedBounds.width * scale) / 2 - paddedBounds.left * scale,
      availableTop +
          (size.height - availableTop - paddedBounds.height * scale) / 2 -
          paddedBounds.top * scale,
    ).multiply(AffineMatrix.scale(scale, scale));

    for (final part in contextParts) {
      final asset = scene.assets[part.catalogPart.appAssetPath];
      if (asset == null) {
        continue;
      }
      final worldTransform = resolveTestWorldTransform(part, state, tables);
      canvas.save();
      canvas.transform(camera.multiply(worldTransform).toFloat64List());
      asset.paint(canvas, const ui.Color(0x66C8CCD4));
      canvas.restore();
    }

    for (final part in filteredParts) {
      final asset = scene.assets[part.catalogPart.appAssetPath];
      if (asset == null) {
        continue;
      }
      final worldTransform = resolveTestWorldTransform(part, state, tables);
      canvas.save();
      canvas.transform(camera.multiply(worldTransform).toFloat64List());
      asset.paint(canvas, part.tintColor);
      canvas.restore();
    }
  }

  canvas.drawRect(
    ui.Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
    ui.Paint()
      ..color = const ui.Color(0x1A1C2430)
      ..style = ui.PaintingStyle.stroke,
  );

  return recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
}

Future<void> writeContactSheetForFixture({
  required PriorityFixtureContext fixture,
  required String path,
}) async {
  const panelSize = ui.Size(560, 420);
  final sheetSize = ui.Size(panelSize.width * 2, panelSize.height * 3);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, sheetSize.width, sheetSize.height),
    ui.Paint()..color = const ui.Color(0xFFF7F8FB),
  );

  final familyBounds = familyBoundsForScene(fixture.scene, fixture.state, fixture.tables);
  final headBounds = familyBounds['head_shape'];
  final bodyBounds = familyBounds['body_base'];
  final effectFamilies = const {'special', 'special2'};
  final headFamilies = {
    ..._groupFamilies['Hair']!,
    ..._groupFamilies['Face']!,
    ..._headAccessoryFamilies,
  };
  final clothesFamilies = {
    ..._groupFamilies['Clothes']!,
    'body_base',
    'body_pants',
    'thigh_front_base',
    'thigh_back_base',
    'foot_front_base',
    'foot_back_base',
    'hand_front_base',
    'hand_back_base',
  };
  final propFamilies = {..._groupFamilies['Props']!, ...effectFamilies};
  final contextFamilies = {
    'head_shape',
    'body_base',
    'hand_front_base',
    'hand_back_base',
  };

  final panels = [
    _ContactSheetPanel(
      title: 'Full character',
      includeFamilies: null,
      contextFamilies: null,
      focusBounds: fixture.scene.worldBounds,
    ),
    _ContactSheetPanel(
      title: 'Head-only crop',
      includeFamilies: null,
      contextFamilies: null,
      focusBounds: headBounds?.inflate(36),
    ),
    _ContactSheetPanel(
      title: 'Hair / head accessory debug',
      includeFamilies: headFamilies,
      contextFamilies: {'head_shape'},
      focusBounds: _expandRects([
        headBounds,
        _familySubsetBounds(familyBounds, headFamilies),
      ], 40),
    ),
    _ContactSheetPanel(
      title: 'Clothes / body debug',
      includeFamilies: clothesFamilies,
      contextFamilies: {'head_shape'},
      focusBounds: _expandRects([
        bodyBounds,
        _familySubsetBounds(familyBounds, clothesFamilies),
      ], 40),
    ),
    _ContactSheetPanel(
      title: 'Props / effects debug',
      includeFamilies: propFamilies,
      contextFamilies: contextFamilies,
      focusBounds: _expandRects([
        _familySubsetBounds(familyBounds, propFamilies),
        bodyBounds,
      ], 48),
    ),
  ];

  for (var index = 0; index < panels.length; index++) {
    final panel = panels[index];
    final row = index ~/ 2;
    final col = index % 2;
    final image = await renderSceneToImage(
      fixture.scene,
      panelSize,
      fixture.state,
      fixture.tables,
      includeFamilies: panel.includeFamilies,
      contextFamilies: panel.contextFamilies,
      focusBounds: panel.focusBounds,
      title: panel.title,
    );
    final dx = col * panelSize.width;
    final dy = row * panelSize.height;
    canvas.drawImage(image, ui.Offset(dx, dy), ui.Paint());
  }

  final image = await recorder.endRecording().toImage(
    sheetSize.width.toInt(),
    sheetSize.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    throw StateError(
      'Failed to encode contact sheet for ${fixture.descriptor.id}',
    );
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

Map<String, dynamic> _fixtureAuditJson(
  ResolverTables tables,
  PriorityFixtureContext fixture,
) {
  final familyBounds = familyBoundsForScene(fixture.scene, fixture.state, tables);
  final groups = <Map<String, dynamic>>[];
  for (final groupName in auditGroupOrder) {
    final active = [
      for (final config in _auditFamilyConfigs)
        if (config.group == groupName && config.isActive(fixture.state)) config,
    ];
    final rows = <Map<String, dynamic>>[];
    final expectedFamilies = <String>{};
    final resolvedFamilies = <String>{
      for (final part in fixture.scene.parts)
        if (_groupFamilies[groupName]!.contains(part.catalogPart.family))
          part.catalogPart.family,
    };

    for (final config in active) {
      final frame = config.chooserFrame(fixture.state);
      final catalogParts = frame > 0
          ? tables.partsFor(config.family, frame)
          : const <RenderCatalogPart>[];
      final resolvedParts = fixture.scene.parts
          .where((part) => part.catalogPart.family == config.family)
          .toList(growable: false);
      if (frame > 0 &&
          (catalogParts.isNotEmpty || config.includeWhenCatalogMissing)) {
        expectedFamilies.add(config.family);
      }
      if (frame <= 0 && resolvedParts.isEmpty) {
        continue;
      }
      if (frame > 0 &&
          catalogParts.isEmpty &&
          resolvedParts.isEmpty &&
          !config.includeWhenCatalogMissing) {
        continue;
      }
      rows.add(
        _familyRowJson(
          tables: tables,
          fixture: fixture,
          config: config,
          familyBounds: familyBounds,
          catalogParts: catalogParts,
          resolvedParts: resolvedParts,
        ),
      );
    }

    groups.add({
      'group': groupName,
      'expected_families': expectedFamilies.toList()..sort(),
      'resolved_families': resolvedFamilies.toList()..sort(),
      'rows': rows,
    });
  }

  return {
    'id': fixture.descriptor.id,
    'display_name': fixture.descriptor.displayName,
    'fixture_asset': fixture.descriptor.fixtureAsset,
    'feature_tags': fixture.descriptor.featureTags,
    'warnings': fixture.scene.warnings,
    'groups': groups,
  };
}

Map<String, dynamic> _familyRowJson({
  required ResolverTables tables,
  required PriorityFixtureContext fixture,
  required _AuditFamilyConfig config,
  required Map<String, Rect> familyBounds,
  required List<RenderCatalogPart> catalogParts,
  required List<ResolvedRenderPart> resolvedParts,
}) {
  final frame = config.chooserFrame(fixture.state);
  final selectedParts = resolvedParts.isNotEmpty
      ? resolvedParts.map((part) => part.catalogPart).toList(growable: false)
      : catalogParts;
  final bounds = resolvedParts.isNotEmpty ? familyBounds[config.family] : null;
  final notes = <String>[];

  if (catalogParts.isEmpty && frame > 0) {
    final familyFrames = tables.catalogByFamilyFrame[config.family];
    if (familyFrames == null || familyFrames.isEmpty) {
      notes.add('No catalog family extracted for ${config.family}.');
    } else if (_isAccessoryHelperOnlyUnsupported(config.family, frame)) {
      notes.add(
        'Chooser frame $frame is intentionally unsupported: the source frame collapses to helper-only leaves 50/77 with no visible exported art. See assets/data/asset-resolution/excluded_leaf_evidence.csv and docs/data/swf-layer-paths/accessory.csv.',
      );
    } else {
      notes.add(
        'Chooser frame $frame is missing from the extracted ${config.family} catalog.',
      );
    }
  }
  if (config.family == 'body_logo' &&
      selectedParts.any((part) => part.leafId == '11386')) {
    notes.add(
      'Source intentionally reuses SWF leaf 11386 for logo_art frame 1 even though the same leaf also appears under left-eye pupil branches; compare docs/data/swf-layer-paths/logo_art.csv and assets/data/asset-resolution/eye_asset_resolution.csv.',
    );
  }
  if (resolvedParts.isEmpty && catalogParts.isNotEmpty) {
    notes.add('Catalog rows exist but no render parts resolved at runtime.');
  }
  if (fixture.scene.warnings.isNotEmpty &&
      knownUnsupportedFamilies.contains(config.family)) {
    notes.add('Runtime currently warns that special effects are not rendered.');
  }

  final classification = _classifyRow(
    tables: tables,
    config: config,
    frame: frame,
    fixture: fixture,
    selectedParts: selectedParts,
    resolvedParts: resolvedParts,
    familyBounds: familyBounds,
    bounds: bounds,
  );

  return {
    'family': config.family,
    'selected_field_values': _selectedFieldValues(
      tables.schema,
      fixture.state,
      config,
      selectedParts,
    ),
    'selected_chooser_frame': frame,
    'selected_leaf_ids': _uniqueStrings(
      selectedParts.map((part) => part.leafId),
    ),
    'asset_paths': _uniqueStrings(
      selectedParts.map((part) => part.appAssetPath),
    ),
    'tint_channels': _uniqueStrings(
      selectedParts
          .map((part) => part.tintChannel)
          .where((value) => value.isNotEmpty),
    ),
    'host': _hostJson(selectedParts),
    'local_matrix_summary': _matrixSummary(
      selectedParts.map((part) => part.localMatrix),
    ),
    'runtime_transform_summary': _runtimeTransformSummary(resolvedParts),
    'depth_global_order': _depthSummary(resolvedParts, fixture.scene),
    'bounds_relative': _boundsRelativeJson(config.family, bounds, familyBounds),
    'issue_classification': classification,
    'resolved_families': _uniqueStrings(
      resolvedParts.map((part) => part.catalogPart.family),
    ),
    'notes': notes,
  };
}

String _classifyRow({
  required ResolverTables tables,
  required _AuditFamilyConfig config,
  required int frame,
  required PriorityFixtureContext fixture,
  required List<RenderCatalogPart> selectedParts,
  required List<ResolvedRenderPart> resolvedParts,
  required Map<String, Rect> familyBounds,
  required Rect? bounds,
}) {
  if (frame <= 0) {
    return 'OK';
  }
  final familyFrames = tables.catalogByFamilyFrame[config.family];
  if (familyFrames == null || familyFrames.isEmpty) {
    return 'unsupported';
  }
  if (resolvedParts.isEmpty && tables.partsFor(config.family, frame).isEmpty) {
    if (_isAccessoryHelperOnlyUnsupported(config.family, frame)) {
      return 'unsupported';
    }
    return 'missing family';
  }
  if (resolvedParts.isEmpty) {
    return 'missing family';
  }
  if (_isTintSuspect(resolvedParts)) {
    return 'tint suspect';
  }
  if (_isLayerOrderSuspect(config.family, fixture.scene)) {
    return 'layer-order suspect';
  }
  if (_isTransformOutlier(config.family, bounds, familyBounds)) {
    return 'transform outlier';
  }
  if (_isScaleOutlier(config.family, bounds, familyBounds)) {
    return 'scale outlier';
  }
  if (_isNestedFrameFilterSuspect(config.family, selectedParts)) {
    return 'nested-frame-filter suspect';
  }
  return 'OK';
}

bool _isAccessoryHelperOnlyUnsupported(String family, int frame) {
  return family.startsWith('accessory') &&
      _helperOnlyAccessoryFrames.contains(frame);
}

bool _isTintSuspect(List<ResolvedRenderPart> resolvedParts) {
  return resolvedParts.any(
    (part) => part.catalogPart.tintChannel != 'none' && part.tintColor == null,
  );
}

bool _isLayerOrderSuspect(String family, ResolvedScene scene) {
  final families = _familyDepthRanges(scene);
  final body = families['body_base'];
  final weaponFront = families['weapon_front'];
  final shield = families['shield'];
  if (family == 'weapon_front' && body != null && weaponFront != null) {
    return weaponFront.$1 <= body.$2;
  }
  if (family == 'shield' && body != null && shield != null) {
    final afterBody = shield.$1 > body.$2;
    final beforeFront = weaponFront == null || shield.$2 < weaponFront.$1;
    return !(afterBody && beforeFront);
  }
  return false;
}

Map<String, (int, int)> _familyDepthRanges(ResolvedScene scene) {
  final result = <String, (int, int)>{};
  for (final part in scene.parts) {
    final family = part.catalogPart.family;
    final current = result[family];
    if (current == null) {
      result[family] = (part.globalDepth, part.globalDepth);
      continue;
    }
    result[family] = (
      math.min(current.$1, part.globalDepth),
      math.max(current.$2, part.globalDepth),
    );
  }
  return result;
}

bool _isTransformOutlier(
  String family,
  Rect? bounds,
  Map<String, Rect> familyBounds,
) {
  if (family == 'weapon_back' ||
      family == 'weapon_front' ||
      family == 'shield') {
    return false;
  }
  if (bounds == null) {
    return false;
  }
  final reference = _referenceBoundsForFamily(family, familyBounds);
  if (reference == null) {
    return false;
  }
  final dx = (bounds.center.dx - reference.center.dx).abs();
  final dy = (bounds.center.dy - reference.center.dy).abs();
  return dx > reference.width * 1.9 || dy > reference.height * 1.9;
}

bool _isScaleOutlier(
  String family,
  Rect? bounds,
  Map<String, Rect> familyBounds,
) {
  if (family == 'weapon_back' ||
      family == 'weapon_front' ||
      family == 'shield') {
    return false;
  }
  if (bounds == null) {
    return false;
  }
  final reference = _referenceBoundsForFamily(family, familyBounds);
  if (reference == null) {
    return false;
  }
  final widthRatio = bounds.width / math.max(reference.width, 1);
  final heightRatio = bounds.height / math.max(reference.height, 1);
  return widthRatio > 3.0 || heightRatio > 3.0;
}

bool _isNestedFrameFilterSuspect(String family, List<RenderCatalogPart> parts) {
  if (family != 'ponytail') {
    return false;
  }
  return parts.any((part) => part.leafId == '4756');
}

Map<String, dynamic> _selectedFieldValues(
  GachaFieldSchema schema,
  GachaCharacterState state,
  _AuditFamilyConfig config,
  List<RenderCatalogPart> selectedParts,
) {
  final fields = <String>{
    'pose',
    if (config.activeField != null) config.activeField!,
    if (config.chooserField != null) config.chooserField!,
    ..._contextFieldsForFamily(config.family),
    for (final part in selectedParts)
      if (part.tintChannel.isNotEmpty && part.tintChannel != 'none')
        part.tintChannel,
  };
  final result = <String, dynamic>{};
  for (final field in fields) {
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
  final orderedKeys = result.keys.toList()..sort();
  return Map.fromEntries(orderedKeys.map((key) => MapEntry(key, result[key])));
}

List<String> _contextFieldsForFamily(String family) {
  const map = <String, List<String>>{
    'head_shape': ['displayhead', 'headflip', 'headsize', 'headsizey'],
    'rear_hair': ['displayhair', 'headflip', 'headsize', 'headsizey'],
    'front_hair': [
      'displayhair',
      'headflip',
      'headsize',
      'headsizey',
      'fronthairxpos',
      'fronthairypos',
      'fronthairxscale',
      'fronthairyscale',
      'fronthairrot',
    ],
    'back_hair': [
      'displayhair',
      'headflip',
      'headsize',
      'headsizey',
      'backhairxpos',
      'backhairypos',
      'backhairxscale',
      'backhairyscale',
      'backhairrot',
    ],
    'ponytail': [
      'displayhair',
      'headflip',
      'headsize',
      'headsizey',
      'ponytailxpos',
      'ponytailypos',
      'ponytailxscale',
      'ponytailyscale',
      'ponytailrot',
    ],
    'ahoge': [
      'displayhair',
      'headflip',
      'headsize',
      'headsizey',
      'ahogexpos',
      'ahogeypos',
      'ahogexscale',
      'ahogeyscale',
      'ahogerot',
    ],
    'left_eye': [
      'displayface',
      'facepreset',
      'eyecam',
      'eyehigh',
      'leyexpos',
      'leyeypos',
      'leyesize',
      'leyesizey',
      'leyerot',
      'lpupilxpos',
      'lpupilypos',
      'lpupilsize',
      'lpupilsizey',
      'lpupilrot',
    ],
    'right_eye': [
      'displayface',
      'facepreset',
      'eyecam',
      'eyehigh',
      'reyexpos',
      'reyeypos',
      'reyesize',
      'reyesizey',
      'reyerot',
      'rpupilxpos',
      'rpupilypos',
      'rpupilsize',
      'rpupilsizey',
      'rpupilrot',
    ],
    'left_eyebrow': [
      'displayface',
      'leyebrowxpos',
      'leyebrowypos',
      'leyebrowsize',
      'leyebrowsizey',
      'leyebrowrot',
    ],
    'right_eyebrow': [
      'displayface',
      'reyebrowxpos',
      'reyebrowypos',
      'reyebrowsize',
      'reyebrowsizey',
      'reyebrowrot',
    ],
    'mouth': [
      'displayface',
      'mouthxpos',
      'mouthypos',
      'mouthsize',
      'mouthsizey',
      'mouthrot',
    ],
    'nose': [
      'displayface',
      'nosexpos',
      'noseypos',
      'nosesize',
      'nosesizey',
      'noserot',
    ],
    'hat': [
      'displayhead',
      'headflip',
      'headsize',
      'headsizey',
      'hatxpos',
      'hatypos',
      'hatsize',
      'hatsizey',
      'hatrot',
    ],
    'glasses': [
      'displayhead',
      'headflip',
      'headsize',
      'headsizey',
      'glassesxpos',
      'glassesypos',
      'glassessize',
      'glassessizey',
      'glassesrot',
    ],
    'accessory1': [
      'displayhead',
      'headflip',
      'headsize',
      'headsizey',
      'acc1xpos',
      'acc1ypos',
      'acc1size',
      'acc1sizey',
      'acc1rot',
    ],
    'accessory2': [
      'displayhead',
      'headflip',
      'headsize',
      'headsizey',
      'acc2xpos',
      'acc2ypos',
      'acc2size',
      'acc2sizey',
      'acc2rot',
    ],
    'accessory3': [
      'displayhead',
      'headflip',
      'headsize',
      'headsizey',
      'acc3xpos',
      'acc3ypos',
      'acc3size',
      'acc3sizey',
      'acc3rot',
    ],
    'other1': [
      'displayhead',
      'headflip',
      'headsize',
      'headsizey',
      'other1xpos',
      'other1ypos',
      'other1size',
      'other1sizey',
      'other1rot',
    ],
    'other2': [
      'displayhead',
      'headflip',
      'headsize',
      'headsizey',
      'other2xpos',
      'other2ypos',
      'other2size',
      'other2sizey',
      'other2rot',
    ],
    'other3': [
      'displayhead',
      'headflip',
      'headsize',
      'headsizey',
      'other3xpos',
      'other3ypos',
      'other3size',
      'other3sizey',
      'other3rot',
    ],
    'other4': [
      'displayhead',
      'headflip',
      'headsize',
      'headsizey',
      'other4xpos',
      'other4ypos',
      'other4size',
      'other4sizey',
      'other4rot',
    ],
    'weapon_front': [
      'displayhand',
      'propxpos1x',
      'propypos1x',
      'propsize1x',
      'proprot1x',
    ],
    'weapon_back': [
      'displaybackhand',
      'propxpos2x',
      'propypos2x',
      'propsize2x',
      'proprot2x',
    ],
    'shield': [
      'displaybackhand',
      'shieldxpos',
      'shieldypos',
      'shieldsize',
      'shieldrot',
    ],
    'cape': [
      'displaybody',
      'capexpos',
      'capeypos',
      'capesize',
      'capesizey',
      'caperot',
    ],
    'tail': [
      'displaybody',
      'tailxpos',
      'tailypos',
      'tailsize',
      'tailsizey',
      'tailrot',
    ],
    'wings1': [
      'displaybody',
      'wingxpos',
      'wingypos',
      'wingsize',
      'wingsizey',
      'wingrot',
    ],
    'wings2': [
      'displaybody',
      'wingxpos',
      'wingypos',
      'wingsize',
      'wingsizey',
      'wingrot',
    ],
    'body_logo': ['displaybody', 'logopos', 'logocolorx'],
    'special': ['special'],
    'special2': ['special2x'],
  };
  return map[family] ?? const ['displaybody', 'heightx', 'heighty'];
}

Map<String, dynamic> _hostJson(List<RenderCatalogPart> parts) {
  return {
    'scopes': _uniqueStrings(parts.map((part) => part.hostScope)),
    'names': _uniqueStrings(parts.map((part) => part.hostName)),
    'child_names': _uniqueStrings(
      parts
          .map((part) => part.hostChildName)
          .where((value) => value.isNotEmpty),
    ),
  };
}

Map<String, dynamic> _matrixSummary(Iterable<AffineMatrix> matrices) {
  final unique = <String, AffineMatrix>{};
  for (final matrix in matrices) {
    unique.putIfAbsent(jsonEncode(matrix.toDebugJson()), () => matrix);
  }
  return {
    'count': unique.length,
    'samples': [
      for (final matrix in unique.values.take(4)) matrix.toDebugJson(),
    ],
  };
}

Map<String, dynamic>? _runtimeTransformSummary(List<ResolvedRenderPart> parts) {
  if (parts.isEmpty) {
    return null;
  }
  final tx = parts
      .map((part) => part.localTransform.tx)
      .toList(growable: false);
  final ty = parts
      .map((part) => part.localTransform.ty)
      .toList(growable: false);
  final scaleX = parts
      .map(
        (part) => math.sqrt(
          part.localTransform.a * part.localTransform.a +
              part.localTransform.b * part.localTransform.b,
        ),
      )
      .toList(growable: false);
  final scaleY = parts
      .map(
        (part) => math.sqrt(
          part.localTransform.c * part.localTransform.c +
              part.localTransform.d * part.localTransform.d,
        ),
      )
      .toList(growable: false);
  final rotation = parts
      .map(
        (part) =>
            math.atan2(part.localTransform.b, part.localTransform.a) *
            180 /
            math.pi,
      )
      .toList(growable: false);
  return {
    'count': parts.length,
    'world_transform_samples': [
      for (final matrix in parts.take(4).map((part) => part.localTransform))
        matrix.toDebugJson(),
    ],
    'translate_x_range': [tx.reduce(math.min), tx.reduce(math.max)],
    'translate_y_range': [ty.reduce(math.min), ty.reduce(math.max)],
    'scale_x_range': [scaleX.reduce(math.min), scaleX.reduce(math.max)],
    'scale_y_range': [scaleY.reduce(math.min), scaleY.reduce(math.max)],
    'rotation_deg_range': [
      rotation.reduce(math.min),
      rotation.reduce(math.max),
    ],
  };
}

Map<String, dynamic>? _depthSummary(
  List<ResolvedRenderPart> parts,
  ResolvedScene scene,
) {
  if (parts.isEmpty) {
    return null;
  }
  final sceneIndexes = <int>[];
  for (final part in parts) {
    final index = scene.parts.indexOf(part);
    if (index >= 0) {
      sceneIndexes.add(index);
    }
  }
  return {
    'global_depth_range': [
      parts.map((part) => part.globalDepth).reduce(math.min),
      parts.map((part) => part.globalDepth).reduce(math.max),
    ],
    'scene_index_range': sceneIndexes.isEmpty
        ? null
        : [sceneIndexes.reduce(math.min), sceneIndexes.reduce(math.max)],
  };
}

Map<String, dynamic> _boundsRelativeJson(
  String family,
  Rect? bounds,
  Map<String, Rect> familyBounds,
) {
  final result = <String, dynamic>{};
  if (bounds == null) {
    return result;
  }
  final head = familyBounds['head_shape'];
  final body = familyBounds['body_base'];
  final host = _referenceBoundsForFamily(family, familyBounds);
  if (head != null) {
    result['head'] = _relativeRect(bounds, head);
  }
  if (body != null) {
    result['body'] = _relativeRect(bounds, body);
  }
  if (host != null) {
    result['host'] = _relativeRect(bounds, host);
  }
  return result;
}

Map<String, dynamic> _relativeRect(Rect bounds, Rect reference) {
  return {
    'center_dx': bounds.center.dx - reference.center.dx,
    'center_dy': bounds.center.dy - reference.center.dy,
    'width_ratio': bounds.width / math.max(reference.width, 1),
    'height_ratio': bounds.height / math.max(reference.height, 1),
    'overlap_ratio': _overlapRatio(bounds, reference),
  };
}

Rect? _referenceBoundsForFamily(String family, Map<String, Rect> familyBounds) {
  if (_headAttachedFamilies.contains(family)) {
    return familyBounds['head_shape'];
  }
  if (_bodyAttachedFamilies.contains(family)) {
    return familyBounds['body_base'];
  }
  if (family == 'weapon_front') {
    return familyBounds['hand_front_base'] ?? familyBounds['body_base'];
  }
  if (family == 'weapon_back' || family == 'shield') {
    return familyBounds['hand_back_base'] ?? familyBounds['body_base'];
  }
  if (family == 'ponytail') {
    return familyBounds['back_hair'] ?? familyBounds['head_shape'];
  }
  return familyBounds[family];
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

Rect? _familySubsetBounds(
  Map<String, Rect> familyBounds,
  Set<String> families,
) {
  Rect? result;
  for (final family in families) {
    final bounds = familyBounds[family];
    if (bounds == null) {
      continue;
    }
    result = result == null ? bounds : result.expandToInclude(bounds);
  }
  return result;
}

Rect? _expandRects(List<Rect?> rects, double padding) {
  Rect? result;
  for (final rect in rects) {
    if (rect == null) {
      continue;
    }
    result = result == null ? rect : result.expandToInclude(rect);
  }
  return result?.inflate(padding);
}

String _markdownList(List<dynamic> values) {
  if (values.isEmpty) {
    return '—';
  }
  return values.join(', ');
}

String _inlineFieldMap(Map<String, dynamic> values) {
  if (values.isEmpty) {
    return '—';
  }
  return values.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join(', ');
}

String _hostSummary(Map<String, dynamic> host) {
  final scopes = _joinList(host['scopes'] as List<dynamic>);
  final names = _joinList(host['names'] as List<dynamic>);
  final children = _joinList(host['child_names'] as List<dynamic>);
  return 'scope=$scopes; name=$names${children.isEmpty ? '' : '; child=$children'}';
}

String _transformSummary(Map<String, dynamic>? summary) {
  if (summary == null) {
    return '—';
  }
  String range(String key) {
    final values = summary[key] as List<dynamic>;
    return '${(values[0] as num).toStringAsFixed(2)}..${(values[1] as num).toStringAsFixed(2)}';
  }

  return 'tx ${range('translate_x_range')}; ty ${range('translate_y_range')}; sx ${range('scale_x_range')}; sy ${range('scale_y_range')}';
}

String _depthSummaryLabel(Map<String, dynamic>? summary) {
  if (summary == null) {
    return '—';
  }
  final depth = summary['global_depth_range'] as List<dynamic>;
  final scene = summary['scene_index_range'] as List<dynamic>?;
  return scene == null
      ? '${depth[0]}..${depth[1]}'
      : '${depth[0]}..${depth[1]} @ ${scene[0]}..${scene[1]}';
}

String _boundsSummary(Map<String, dynamic> summary) {
  if (summary.isEmpty) {
    return '—';
  }
  final parts = <String>[];
  for (final key in ['head', 'body', 'host']) {
    final value = summary[key] as Map<String, dynamic>?;
    if (value == null) {
      continue;
    }
    parts.add(
      '$key(dx=${(value['center_dx'] as num).toStringAsFixed(1)}, dy=${(value['center_dy'] as num).toStringAsFixed(1)}, ov=${(value['overlap_ratio'] as num).toStringAsFixed(2)})',
    );
  }
  return parts.join('; ');
}

String _joinList(List<dynamic> values, {int maxItems = 6}) {
  if (values.isEmpty) {
    return '';
  }
  final items = values.map((value) => '$value').toList(growable: false);
  if (items.length <= maxItems) {
    return items.join(', ');
  }
  return '${items.take(maxItems).join(', ')}, +${items.length - maxItems} more';
}

String _escapeMarkdown(String value) =>
    value.replaceAll('|', '\\|').replaceAll('\n', ' ');

List<String> _uniqueStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    if (value.isEmpty || !seen.add(value)) {
      continue;
    }
    result.add(value);
  }
  return result;
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

final _groupFamilies = <String, Set<String>>{
  'Body / Pose': {
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
  },
  'Hair': {'rear_hair', 'front_hair', 'back_hair', 'ponytail', 'ahoge'},
  'Face': {
    'left_eye',
    'right_eye',
    'left_eyebrow',
    'right_eyebrow',
    'mouth',
    'nose',
    'blush',
    'faceshadow',
  },
  'Clothes': {
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
  },
  'Other': {
    'hat',
    'glasses',
    'accessory1',
    'accessory2',
    'accessory3',
    'other1',
    'other2',
    'other3',
    'other4',
    'cape',
    'tail',
    'wings1',
    'wings2',
    'scarf1',
    'scarf2',
  },
  'Props': {'weapon_front', 'weapon_back', 'shield'},
  'Effects / Special': {'special', 'special2'},
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

const _bodyAttachedFamilies = <String>{
  'body_base',
  'body_pants',
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
  'scarf1',
  'scarf2',
  'cape',
  'tail',
  'wings1',
  'wings2',
};

class _AuditFamilyConfig {
  const _AuditFamilyConfig({
    required this.group,
    required this.family,
    this.chooserField,
    this.fixedFrame,
    this.activeField,
    this.includeWhenCatalogMissing = true,
  });

  final String group;
  final String family;
  final String? chooserField;
  final int? fixedFrame;
  final String? activeField;
  final bool includeWhenCatalogMissing;

  bool isActive(GachaCharacterState state) {
    if (activeField != null && state.numeric(activeField!) == 0) {
      return false;
    }
    return chooserFrame(state) > 0;
  }

  int chooserFrame(GachaCharacterState state) {
    if (chooserField != null) {
      return state.numeric(chooserField!);
    }
    return fixedFrame ?? 0;
  }
}

class _ContactSheetPanel {
  const _ContactSheetPanel({
    required this.title,
    required this.includeFamilies,
    required this.contextFamilies,
    required this.focusBounds,
  });

  final String title;
  final Set<String>? includeFamilies;
  final Set<String>? contextFamilies;
  final Rect? focusBounds;
}

const _auditFamilyConfigs = <_AuditFamilyConfig>[
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'head_shape',
    chooserField: 'headshape',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'body_base',
    fixedFrame: 1,
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'body_pants',
    chooserField: 'pants1x',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'shoulder_front_base',
    fixedFrame: 1,
    activeField: 'displayshoulder',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'back_shoulder_base',
    fixedFrame: 1,
    activeField: 'displaybackshoulder',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'hand_front_base',
    chooserField: 'hand1x',
    activeField: 'displayhand',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'hand_back_base',
    chooserField: 'hand2x',
    activeField: 'displaybackhand',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'thigh_front_base',
    fixedFrame: 1,
    activeField: 'displaythigh',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'thigh_back_base',
    fixedFrame: 1,
    activeField: 'displaybackthigh',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'foot_front_base',
    fixedFrame: 1,
    activeField: 'displayfoot',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'foot_back_base',
    fixedFrame: 1,
    activeField: 'displaybackfoot',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'knee_front',
    chooserField: 'knee1x',
    activeField: 'displaythigh',
  ),
  _AuditFamilyConfig(
    group: 'Body / Pose',
    family: 'knee_back',
    chooserField: 'knee2x',
    activeField: 'displaybackthigh',
  ),
  _AuditFamilyConfig(
    group: 'Hair',
    family: 'rear_hair',
    chooserField: 'rearhair',
    activeField: 'displayhair',
  ),
  _AuditFamilyConfig(
    group: 'Hair',
    family: 'front_hair',
    chooserField: 'fronthair',
    activeField: 'displayhair',
  ),
  _AuditFamilyConfig(
    group: 'Hair',
    family: 'back_hair',
    chooserField: 'backhair',
    activeField: 'displayhair',
  ),
  _AuditFamilyConfig(
    group: 'Hair',
    family: 'ponytail',
    chooserField: 'ponytail',
    activeField: 'displayhair',
  ),
  _AuditFamilyConfig(
    group: 'Hair',
    family: 'ahoge',
    chooserField: 'ahoge',
    activeField: 'displayhair',
  ),
  _AuditFamilyConfig(
    group: 'Face',
    family: 'left_eye',
    chooserField: 'eyes1x',
    activeField: 'displayface',
  ),
  _AuditFamilyConfig(
    group: 'Face',
    family: 'right_eye',
    chooserField: 'eyes2x',
    activeField: 'displayface',
  ),
  _AuditFamilyConfig(
    group: 'Face',
    family: 'left_eyebrow',
    chooserField: 'eyebrows1x',
    activeField: 'displayface',
  ),
  _AuditFamilyConfig(
    group: 'Face',
    family: 'right_eyebrow',
    chooserField: 'eyebrows2x',
    activeField: 'displayface',
  ),
  _AuditFamilyConfig(
    group: 'Face',
    family: 'mouth',
    chooserField: 'mouth',
    activeField: 'displayface',
  ),
  _AuditFamilyConfig(
    group: 'Face',
    family: 'nose',
    chooserField: 'nose',
    activeField: 'displayface',
  ),
  _AuditFamilyConfig(
    group: 'Face',
    family: 'blush',
    chooserField: 'blush',
    activeField: 'displayface',
  ),
  _AuditFamilyConfig(
    group: 'Face',
    family: 'faceshadow',
    chooserField: 'faceshadow',
    activeField: 'displayface',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'body_shirt',
    chooserField: 'shirt',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'body_logo',
    chooserField: 'logo',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'body_jacket',
    chooserField: 'shirtex',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'upper_sleeve_front',
    chooserField: 'sleeves1x',
    activeField: 'displayshoulder',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'upper_sleeve_back',
    chooserField: 'sleeves2x',
    activeField: 'displaybackshoulder',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'lower_sleeve_front',
    chooserField: 'sleeves1x',
    activeField: 'displayshoulder',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'lower_sleeve_back',
    chooserField: 'sleeves2x',
    activeField: 'displaybackshoulder',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'glove_front',
    chooserField: 'gloves1x',
    activeField: 'displayhand',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'glove_back',
    chooserField: 'gloves2x',
    activeField: 'displaybackhand',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'wrist_front',
    chooserField: 'wrist1x',
    activeField: 'displayhand',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'wrist_back',
    chooserField: 'wrist2x',
    activeField: 'displaybackhand',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'thigh_pants_front',
    chooserField: 'pants1x',
    activeField: 'displaythigh',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'thigh_pants_back',
    chooserField: 'pants2x',
    activeField: 'displaybackthigh',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'foot_pants_front',
    chooserField: 'pants1x',
    activeField: 'displayfoot',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'foot_pants_back',
    chooserField: 'pants2x',
    activeField: 'displaybackfoot',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'thigh_socks_front',
    chooserField: 'socks1x',
    activeField: 'displaythigh',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'thigh_socks_back',
    chooserField: 'socks2x',
    activeField: 'displaybackthigh',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'foot_socks_front',
    chooserField: 'socks1x',
    activeField: 'displayfoot',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'foot_socks_back',
    chooserField: 'socks2x',
    activeField: 'displaybackfoot',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'shoe_front',
    chooserField: 'shoes1x',
    activeField: 'displayfoot',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'shoe_back',
    chooserField: 'shoes2x',
    activeField: 'displaybackfoot',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'belt1',
    chooserField: 'belt1x',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'belt2',
    chooserField: 'belt2x',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'belt_shirt',
    chooserField: 'shirt',
    activeField: 'displaybody',
    includeWhenCatalogMissing: false,
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'belt_jacket',
    chooserField: 'shirtex',
    activeField: 'displaybody',
    includeWhenCatalogMissing: false,
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'shoulder_front',
    chooserField: 'shoulder1x',
    activeField: 'displayshoulder',
  ),
  _AuditFamilyConfig(
    group: 'Clothes',
    family: 'shoulder_back',
    chooserField: 'shoulder2x',
    activeField: 'displaybackshoulder',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'hat',
    chooserField: 'hat',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'glasses',
    chooserField: 'glasses',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'accessory1',
    chooserField: 'accessory1x',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'accessory2',
    chooserField: 'accessory2x',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'accessory3',
    chooserField: 'accessory3x',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'other1',
    chooserField: 'other1x',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'other2',
    chooserField: 'other2x',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'other3',
    chooserField: 'other3x',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'other4',
    chooserField: 'other4x',
    activeField: 'displayhead',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'cape',
    chooserField: 'cape',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'tail',
    chooserField: 'tail',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'wings1',
    chooserField: 'wings1x',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'wings2',
    chooserField: 'wings2x',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'scarf1',
    chooserField: 'scarf1x',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Other',
    family: 'scarf2',
    chooserField: 'scarf2x',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Props',
    family: 'weapon_front',
    chooserField: 'weapon1x',
    activeField: 'displayhand',
  ),
  _AuditFamilyConfig(
    group: 'Props',
    family: 'weapon_back',
    chooserField: 'weapon2x',
    activeField: 'displaybackhand',
  ),
  _AuditFamilyConfig(
    group: 'Props',
    family: 'shield',
    chooserField: 'shield',
    activeField: 'displaybackhand',
  ),
  _AuditFamilyConfig(
    group: 'Effects / Special',
    family: 'special',
    chooserField: 'special',
    activeField: 'displaybody',
  ),
  _AuditFamilyConfig(
    group: 'Effects / Special',
    family: 'special2',
    chooserField: 'special2x',
    activeField: 'displaybody',
  ),
];
