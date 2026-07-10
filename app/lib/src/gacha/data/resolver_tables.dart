import '../code/gacha_field_schema.dart';
import 'dart:math' as math;

import '../render/transform_graph.dart';
import 'asset_manifest.dart';
import 'csv_loaders.dart';
import 'platform_file_exists.dart';

class RenderCatalogPart {
  const RenderCatalogPart({
    required this.family,
    required this.chooserFrame,
    required this.partRole,
    required this.orderedPartIndex,
    required this.leafId,
    required this.originalAssetPath,
    required this.appAssetPath,
    required this.assetKind,
    required this.tintChannel,
    required this.visibilityRule,
    required this.namePath,
    required this.characterPath,
    required this.depthPath,
    required this.framePath,
    required this.hostScope,
    required this.hostName,
    required this.hostChildName,
    required this.hostDepthPath,
    required this.runtimeAnchorX,
    required this.runtimeAnchorY,
    required this.dependencyField,
    required this.dependencyValue,
    required this.sizeTable,
    required this.rootSpriteId,
    required this.localMatrix,
    required this.notes,
  });

  final String family;
  final int chooserFrame;
  final String partRole;
  final int orderedPartIndex;
  final String leafId;
  final String originalAssetPath;
  final String appAssetPath;
  final String assetKind;
  final String tintChannel;
  final String visibilityRule;
  final String namePath;
  final String characterPath;
  final String depthPath;
  final String framePath;
  final String hostScope;
  final String hostName;
  final String hostChildName;
  final String hostDepthPath;
  final double runtimeAnchorX;
  final double runtimeAnchorY;
  final String dependencyField;
  final int? dependencyValue;
  final String sizeTable;
  final String rootSpriteId;
  final AffineMatrix localMatrix;
  final String notes;

  factory RenderCatalogPart.fromRow(Map<String, String> row) {
    return RenderCatalogPart(
      family: row['family']!,
      chooserFrame: int.parse(row['chooser_frame']!),
      partRole: row['part_role']!,
      orderedPartIndex: int.parse(row['ordered_part_index']!),
      leafId: row['leaf_id']!,
      originalAssetPath: row['original_asset_path'] ?? '',
      appAssetPath: row['app_asset_path']!,
      assetKind: row['asset_kind']!,
      tintChannel: row['tint_channel']!,
      visibilityRule: row['visibility_rule']!,
      namePath: row['name_path']!,
      characterPath: row['character_path']!,
      depthPath: row['depth_path']!,
      framePath: row['frame_path']!,
      hostScope: row['host_scope']!,
      hostName: row['host_name']!,
      hostChildName: row['host_child_name']!,
      hostDepthPath: row['host_depth_path'] ?? '',
      runtimeAnchorX: double.parse(row['runtime_anchor_x']!),
      runtimeAnchorY: double.parse(row['runtime_anchor_y']!),
      dependencyField: row['dependency_field'] ?? '',
      dependencyValue: _parseOptionalInt(row['dependency_value']),
      sizeTable: row['size_table']!,
      rootSpriteId: row['root_sprite_id']!,
      localMatrix: AffineMatrix(
        a: double.parse(row['local_a']!),
        b: double.parse(row['local_b']!),
        c: double.parse(row['local_c']!),
        d: double.parse(row['local_d']!),
        tx: _twipsToPixels(double.parse(row['local_tx']!)),
        ty: _twipsToPixels(double.parse(row['local_ty']!)),
      ),
      notes: row['notes']!,
    );
  }

  bool matchesStateValue(int Function(String field) numericValueForField) {
    if (dependencyField.isEmpty || dependencyValue == null) {
      return true;
    }
    return numericValueForField(dependencyField) == dependencyValue;
  }
}

class HostPlacement {
  const HostPlacement({
    required this.name,
    required this.depth,
    required this.matrix,
  });

  final String name;
  final int depth;
  final AffineMatrix matrix;

  factory HostPlacement.fromRow(Map<String, String> row) {
    return HostPlacement(
      name: row['name']!,
      depth: int.parse(row['depth']!),
      matrix: AffineMatrix.fromComponents(
        scaleX: _scalePlacementValue(row['scale_x']),
        scaleY: _scalePlacementValue(row['scale_y']),
        rotateSkew0: _placementValue(row['rotate_skew_1']),
        rotateSkew1: _placementValue(row['rotate_skew_0']),
        translateX: _twipsToPixels(double.parse(row['translate_x']!)),
        translateY: _twipsToPixels(double.parse(row['translate_y']!)),
      ),
    );
  }

  static double _scalePlacementValue(String? raw) {
    if (raw == null || raw.isEmpty || raw == '0' || raw == '0.0') {
      return 1;
    }
    return double.parse(raw);
  }

  static double _placementValue(String? raw, {double defaultValue = 0}) {
    if (raw == null || raw.isEmpty || raw == '0' || raw == '0.0') {
      return defaultValue;
    }
    return double.parse(raw);
  }
}

double _twipsToPixels(double value) => value / 20.0;

int? _parseOptionalInt(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return int.parse(raw);
}

void _validateHeadPlacementRows(List<Map<String, String>> rows) {
  for (var frame = 1; frame <= 4; frame++) {
    final frameRows = rows.where(
      (row) => int.tryParse(row['frame'] ?? '') == frame,
    );
    if (frameRows.length != 21) {
      throw StateError(
        'Expected 21 head placements for frame $frame, got ${frameRows.length}.',
      );
    }
    final activeCount = frameRows
        .where((row) => int.tryParse(row['character_id'] ?? '') != 0)
        .length;
    final expectedActiveCount = frame == 4 ? 0 : 21;
    if (activeCount != expectedActiveCount) {
      throw StateError(
        'Expected $expectedActiveCount active head placements for frame $frame, got $activeCount.',
      );
    }
  }
}

class FacePresetRule {
  const FacePresetRule({
    required this.facepreset,
    required this.leftEyeOuter,
    required this.rightEyeOuter,
  });

  final int facepreset;
  final String leftEyeOuter;
  final String rightEyeOuter;

  factory FacePresetRule.fromRow(Map<String, String> row) {
    return FacePresetRule(
      facepreset: int.parse(row['facepreset']!),
      leftEyeOuter: row['left_eye_outer']!,
      rightEyeOuter: row['right_eye_outer']!,
    );
  }
}

class RuntimeValueRule {
  const RuntimeValueRule({
    required this.field,
    required this.target,
    required this.op,
    required this.matchValue,
    required this.value,
  });

  final String field;
  final String target;
  final String op;
  final int matchValue;
  final double value;

  factory RuntimeValueRule.fromRow(Map<String, String> row) {
    final condition = row['condition']!;
    final match = RegExp(r'^field:([^ ]+) == (-?\d+)$').firstMatch(condition);
    if (match == null) {
      throw StateError('Unsupported condition in field value map: $condition');
    }
    return RuntimeValueRule(
      field: row['field']!,
      target: row['target']!,
      op: row['op']!,
      matchValue: int.parse(match.group(2)!),
      value: double.parse(row['value']!),
    );
  }
}

class RuntimeValueMaps {
  RuntimeValueMaps(this.rules) {
    for (final rule in rules) {
      final fieldRules = _rulesByField.putIfAbsent(rule.field, () => {});
      final valueRules = fieldRules.putIfAbsent(rule.matchValue, () => {});
      final opRules = valueRules.putIfAbsent(rule.op, () => []);
      opRules.add(rule);
    }
  }

  final List<RuntimeValueRule> rules;
  final Map<String, Map<int, Map<String, List<RuntimeValueRule>>>>
  _rulesByField = {};

  double? resolveOrNull({
    required String field,
    required int fieldValue,
    required String op,
    String? targetContains,
  }) {
    final candidates = _rulesByField[field]?[fieldValue]?[op];
    if (candidates == null) {
      return null;
    }
    for (final rule in candidates) {
      if (targetContains != null && !rule.target.contains(targetContains)) {
        continue;
      }
      return rule.value;
    }
    return null;
  }

  double resolve({
    required String field,
    required int fieldValue,
    required String op,
    String? targetContains,
    required double fallback,
  }) {
    return resolveOrNull(
          field: field,
          fieldValue: fieldValue,
          op: op,
          targetContains: targetContains,
        ) ??
        fallback;
  }
}

class EditorValueRange {
  const EditorValueRange({
    required this.field,
    required this.minValue,
    required this.maxValue,
  });

  final String field;
  final int minValue;
  final int maxValue;

  factory EditorValueRange.fromRow(Map<String, String> row) {
    return EditorValueRange(
      field: row['field']!,
      minValue: int.parse(row['min_value']!),
      maxValue: int.parse(row['max_value']!),
    );
  }
}

class ValidationCaseDescriptor {
  const ValidationCaseDescriptor({
    required this.id,
    required this.fixtureAsset,
    required this.displayName,
    required this.group,
    required this.featureTags,
    this.sourceLine,
  });

  final String id;
  final String fixtureAsset;
  final String displayName;
  final String group;
  final List<String> featureTags;
  final int? sourceLine;

  factory ValidationCaseDescriptor.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return ValidationCaseDescriptor(
      id: id,
      fixtureAsset: json['fixture_asset'] as String,
      displayName: (json['display_name'] as String?) ?? _prettyFixtureLabel(id),
      group: (json['group'] as String?) ?? 'Probe Fixtures',
      featureTags: [
        for (final tag in (json['feature_tags'] as List<dynamic>? ?? const []))
          tag as String,
      ],
      sourceLine: json['source_line'] as int?,
    );
  }

  factory ValidationCaseDescriptor.fromBuiltinManifest(
    Map<String, dynamic> json,
  ) {
    return ValidationCaseDescriptor(
      id: json['id'] as String,
      fixtureAsset: json['fixture_asset_path'] as String,
      displayName: json['display_name'] as String,
      group: 'Built-in Fixtures',
      featureTags: [
        for (final tag in (json['feature_tags'] as List<dynamic>? ?? const []))
          tag as String,
      ],
      sourceLine: json['source_line'] as int?,
    );
  }
}

String _prettyFixtureLabel(String id) {
  return id
      .split('_')
      .where((segment) => segment.isNotEmpty)
      .map((segment) => '${segment[0].toUpperCase()}${segment.substring(1)}')
      .join(' ');
}

class HeadPlacementKey {
  const HeadPlacementKey({required this.frame, required this.name});

  final int frame;
  final String name;

  @override
  bool operator ==(Object other) {
    return other is HeadPlacementKey &&
        other.frame == frame &&
        other.name == name;
  }

  @override
  int get hashCode => Object.hash(frame, name);
}

class PosePlacementKey {
  const PosePlacementKey._({
    required this.page,
    required this.localFrame,
    required this.name,
  });

  final int page;
  final int localFrame;
  final String name;

  static final Map<String, PosePlacementKey> _cache = {};

  factory PosePlacementKey({
    required int page,
    required int localFrame,
    required String name,
  }) {
    final key = '$page|$localFrame|$name';
    return _cache.putIfAbsent(
      key,
      () => PosePlacementKey._(page: page, localFrame: localFrame, name: name),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PosePlacementKey &&
        other.page == page &&
        other.localFrame == localFrame &&
        other.name == name;
  }

  @override
  int get hashCode => Object.hash(page, localFrame, name);
}

class ResolverTables {
  const ResolverTables({
    required this.schema,
    required this.assetManifest,
    required this.renderCatalog,
    required this.catalogByFamilyFrame,
    required this.headPlacements,
    required this.headFlipPlacements,
    required this.logoPlacements,
    required this.posePlacements,
    required this.facePresetRules,
    required this.runtimeValueMaps,
    required this.editorValueRanges,
    required this.validationCases,
    required this.builtinFixtures,
    required this.eyeResolutionRows,
    required this.hairResolutionRows,
    required this.transformAnchorRows,
    required this.compositeSlotRows,
  });

  static const int minPose = 1;
  static const int maxPose = 603;
  static const int _posesPerPage = 25;

  final GachaFieldSchema schema;
  final AppAssetManifest assetManifest;
  final List<RenderCatalogPart> renderCatalog;
  final Map<String, Map<int, List<RenderCatalogPart>>> catalogByFamilyFrame;
  final Map<HeadPlacementKey, HostPlacement> headPlacements;
  final Map<String, Map<int, HostPlacement>> headFlipPlacements;
  final Map<int, HostPlacement> logoPlacements;
  final Map<PosePlacementKey, HostPlacement> posePlacements;
  final Map<int, FacePresetRule> facePresetRules;
  final RuntimeValueMaps runtimeValueMaps;
  final Map<String, EditorValueRange> editorValueRanges;
  final List<ValidationCaseDescriptor> validationCases;
  final List<ValidationCaseDescriptor> builtinFixtures;
  final List<Map<String, String>> eyeResolutionRows;
  final List<Map<String, String>> hairResolutionRows;
  final List<Map<String, String>> transformAnchorRows;
  final List<Map<String, String>> compositeSlotRows;

  List<ValidationCaseDescriptor> get editorFixtures => [
    ...validationCases,
    ...builtinFixtures,
  ];

  static Future<ResolverTables> load({
    bool includeResolutionRows = true,
    bool validateAssetCoverage = true,
  }) async {
    final schemaRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/schema/gacha_code_schema.csv',
    );
    final manifestJsonFuture = CsvLoaders.loadJsonAsset(
      'assets/data/generated/app_asset_manifest.json',
    );
    final renderRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/generated/render_parts.csv',
    );
    final renderExtraRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/generated/render_parts_extras.csv',
    );
    final headPlacementRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/swf-frame-placements/head_layout.csv',
    );
    final headFlipPlacementRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/swf-frame-placements/head_flip_layout.csv',
    );
    final logoPlacementRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/swf-frame-placements/logo_layout.csv',
    );
    final posePlacementRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/swf-frame-placements/gacha_pose_frame_placements.csv',
    );
    final facePresetRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/generated/gacha_facepreset_map.csv',
    );
    final fieldMapRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/generated/gacha_field_value_maps_render.csv',
    );
    final validationCaseJsonFuture = CsvLoaders.loadJsonListAsset(
      'assets/data/generated/validation_cases.json',
    );
    final builtinManifestJsonFuture = CsvLoaders.loadJsonListAsset(
      'assets/data/generated/builtin_character_manifest.json',
    );
    final editorRangeRowsFuture = CsvLoaders.loadAssetCsv(
      'assets/data/schema/gacha_editor_slot_ranges.csv',
    );
    final eyeResolutionRowsFuture = includeResolutionRows
        ? CsvLoaders.loadAssetCsv(
            'assets/data/asset-resolution/eye_asset_resolution.csv',
          )
        : Future.value(const <Map<String, String>>[]);
    final hairResolutionRowsFuture = includeResolutionRows
        ? CsvLoaders.loadAssetCsv(
            'assets/data/asset-resolution/hair_asset_resolution.csv',
          )
        : Future.value(const <Map<String, String>>[]);
    final transformAnchorRowsFuture = includeResolutionRows
        ? CsvLoaders.loadAssetCsv(
            'assets/data/asset-resolution/transform_anchor_map.csv',
          )
        : Future.value(const <Map<String, String>>[]);
    final compositeSlotRowsFuture = includeResolutionRows
        ? CsvLoaders.loadAssetCsv(
            'assets/data/asset-resolution/composite_slot_parts.csv',
          )
        : Future.value(const <Map<String, String>>[]);

    final schemaRows = await schemaRowsFuture;
    final manifestJson = await manifestJsonFuture;
    final renderRows = await renderRowsFuture;
    final renderExtraRows = await renderExtraRowsFuture;
    final headPlacementRows = await headPlacementRowsFuture;
    final headFlipPlacementRows = await headFlipPlacementRowsFuture;
    final logoPlacementRows = await logoPlacementRowsFuture;
    final posePlacementRows = await posePlacementRowsFuture;
    final facePresetRows = await facePresetRowsFuture;
    final fieldMapRows = await fieldMapRowsFuture;
    final validationCaseJson = await validationCaseJsonFuture;
    final builtinManifestJson = await builtinManifestJsonFuture;
    final editorRangeRows = await editorRangeRowsFuture;
    final eyeResolutionRows = await eyeResolutionRowsFuture;
    final hairResolutionRows = await hairResolutionRowsFuture;
    final transformAnchorRows = await transformAnchorRowsFuture;
    final compositeSlotRows = await compositeSlotRowsFuture;

    _validateHeadPlacementRows(headPlacementRows);
    final schema = GachaFieldSchema.fromRows(schemaRows);
    final assetManifest = AppAssetManifest.fromJson(manifestJson);
    final renderCatalog = [
      ...renderRows,
      ...renderExtraRows,
    ].map(RenderCatalogPart.fromRow).toList(growable: true);
    final catalogByFamilyFrame = <String, Map<int, List<RenderCatalogPart>>>{};
    for (final part in renderCatalog) {
      final familyFrames = catalogByFamilyFrame.putIfAbsent(
        part.family,
        () => {},
      );
      final parts = familyFrames.putIfAbsent(part.chooserFrame, () => []);
      parts.add(part);
    }
    final headPlacements = {
      for (final row in headPlacementRows)
        if (int.tryParse(row['character_id'] ?? '') != 0)
          HeadPlacementKey(frame: int.parse(row['frame']!), name: row['name']!):
              HostPlacement.fromRow(row),
    };
    final headFlipPlacements = <String, Map<int, HostPlacement>>{};
    for (final row in headFlipPlacementRows) {
      final name = row['name']!;
      final frame = int.parse(row['frame']!);
      final placementsByFrame = headFlipPlacements.putIfAbsent(name, () => {});
      placementsByFrame[frame] = HostPlacement.fromRow(row);
    }
    final logoPlacements = {
      for (final row in logoPlacementRows)
        int.parse(row['frame']!): HostPlacement.fromRow(row),
    };
    final posePlacements = {
      for (final row in posePlacementRows)
        PosePlacementKey(
          page: int.parse(row['page']!),
          localFrame: int.parse(row['local_frame']!),
          name: row['name']!,
        ): HostPlacement.fromRow(
          row,
        ),
    };
    final facePresetRules = {
      for (final row in facePresetRows)
        int.parse(row['facepreset']!): FacePresetRule.fromRow(row),
    };
    final runtimeValueMaps = RuntimeValueMaps([
      for (final row in fieldMapRows)
        if (row['function'] == 'updatechar' &&
            row['value']!.isNotEmpty &&
            RegExp(r'^field:[^ ]+ == -?\d+$').hasMatch(row['condition']!) &&
            double.tryParse(row['value']!) != null)
          RuntimeValueRule.fromRow(row),
    ]);
    final validationCases = [
      for (final entry in validationCaseJson)
        ValidationCaseDescriptor.fromJson(entry as Map<String, dynamic>),
    ];
    final builtinFixtures = [
      for (final entry in builtinManifestJson)
        if ((entry as Map<String, dynamic>)['curated'] == true &&
            ((entry['fixture_asset_path'] as String?) ?? '').isNotEmpty)
          ValidationCaseDescriptor.fromBuiltinManifest(entry),
    ];
    final editorValueRanges = {
      for (final row in editorRangeRows)
        row['field']!: EditorValueRange.fromRow(row),
    };

    final tables = ResolverTables(
      schema: schema,
      assetManifest: assetManifest,
      renderCatalog: renderCatalog,
      catalogByFamilyFrame: catalogByFamilyFrame,
      headPlacements: headPlacements,
      headFlipPlacements: headFlipPlacements,
      logoPlacements: logoPlacements,
      posePlacements: posePlacements,
      facePresetRules: facePresetRules,
      runtimeValueMaps: runtimeValueMaps,
      editorValueRanges: editorValueRanges,
      validationCases: validationCases,
      builtinFixtures: builtinFixtures,
      eyeResolutionRows: eyeResolutionRows,
      hairResolutionRows: hairResolutionRows,
      transformAnchorRows: transformAnchorRows,
      compositeSlotRows: compositeSlotRows,
    );
    if (validateAssetCoverage) {
      tables.assertAssetCoverage();
    }
    return tables;
  }

  static Future<ResolverTables> loadForEditor() {
    return load(includeResolutionRows: false, validateAssetCoverage: false);
  }

  void assertAssetCoverage() {
    for (final part in renderCatalog) {
      if (part.appAssetPath.isEmpty) {
        throw StateError(
          'Missing app asset path for ${part.family}:${part.leafId}',
        );
      }
      if (!assetManifest.containsAppAsset(part.appAssetPath) &&
          !localFileExists(part.appAssetPath)) {
        throw StateError('Asset manifest missing ${part.appAssetPath}');
      }
    }
  }

  List<RenderCatalogPart> partsFor(String family, int chooserFrame) {
    return catalogByFamilyFrame[family]?[chooserFrame] ?? const [];
  }

  int normalizePose(int pose) {
    if (pose < minPose) {
      return minPose;
    }
    if (pose > maxPose) {
      return maxPose;
    }
    return pose;
  }

  int posePageFor(int pose) => ((normalizePose(pose) - 1) ~/ _posesPerPage) + 1;

  int poseLocalFrameFor(int pose) =>
      ((normalizePose(pose) - 1) % _posesPerPage) + 1;

  HostPlacement? posePlacementFor({
    required int pose,
    required String hostName,
  }) {
    final key = PosePlacementKey(
      page: posePageFor(pose),
      localFrame: poseLocalFrameFor(pose),
      name: hostName,
    );
    return posePlacements[key];
  }

  HostPlacement? logoPlacementFor(int logopos) {
    if (logoPlacements.isEmpty) {
      return null;
    }
    return logoPlacements[logopos] ?? logoPlacements[1];
  }

  HostPlacement? headPlacementFor({
    required int headlayer,
    required String name,
  }) {
    return headPlacements[HeadPlacementKey(
      frame: normalizeHeadlayer(headlayer),
      name: name,
    )];
  }

  int normalizeHeadlayer(int headlayer) {
    if (headlayer == 4) {
      return 4;
    }
    if (headlayer < 1 || headlayer > 3) {
      return 1;
    }
    return headlayer;
  }

  HostPlacement? headFlipPlacementFor({
    required int headflip,
    required String name,
  }) {
    final placementsByFrame = headFlipPlacements[name];
    if (placementsByFrame == null || placementsByFrame.isEmpty) {
      return null;
    }
    return placementsByFrame[headflip] ?? placementsByFrame[1];
  }

  EditorValueRange? editorValueRangeFor(String field) {
    return editorValueRanges[field];
  }
}

// ignore: unused_element
List<RenderCatalogPart> _synthesizeCatalogParts(
  List<RenderCatalogPart> existing,
  AppAssetManifest manifest, {
  required List<Map<String, String>> eyeResolutionRows,
  required List<Map<String, String>> hairResolutionRows,
  required List<Map<String, String>> transformAnchorRows,
  required List<Map<String, String>> compositeSlotRows,
}) {
  const supportedFamilies = {
    'left_eye',
    'right_eye',
    'left_eyebrow',
    'right_eyebrow',
    'front_hair',
    'rear_hair',
    'back_hair',
    'ponytail',
    'ahoge',
  };

  final existingFrames = <String>{
    for (final part in existing)
      if (supportedFamilies.contains(part.family))
        '${part.family}:${part.chooserFrame}',
  };
  final manifestByBasename = <String, AppAssetManifestEntry>{
    for (final entry in manifest.entries.values)
      entry.appAssetPath.split('/').last: entry,
  };
  final compositeByKey = <String, Map<String, String>>{};
  for (final row in compositeSlotRows) {
    final key = _resolutionCompositeKey(
      family: row['family'] ?? '',
      chooserFrame: int.tryParse(row['chooser_frame'] ?? '') ?? 0,
      partRole: row['part_role'] ?? '',
      leafId: row['leaf_id'] ?? '',
      depthPath: row['depth_path'] ?? '',
    );
    compositeByKey.putIfAbsent(key, () => row);
  }
  final transformByKey = <String, Map<String, String>>{};
  for (final row in transformAnchorRows) {
    final key = _transformKey(
      family: row['family'] ?? '',
      chooserFrame: int.tryParse(row['chooser_frame'] ?? '') ?? 0,
      partRole: row['part_role'] ?? '',
      namePath: row['name_path'] ?? '',
    );
    transformByKey[key] = row;
  }

  final synthesized = <RenderCatalogPart>[];
  for (final row in [...eyeResolutionRows, ...hairResolutionRows]) {
    final family = row['family'] ?? '';
    final chooserFrame = int.tryParse(row['chooser_frame'] ?? '') ?? 0;
    if (!supportedFamilies.contains(family) || chooserFrame <= 0) {
      continue;
    }
    if (existingFrames.contains('$family:$chooserFrame')) {
      continue;
    }
    final composite =
        compositeByKey[_resolutionCompositeKey(
          family: family,
          chooserFrame: chooserFrame,
          partRole: _normalizedPartRole(family, row),
          leafId: row['leaf_id'] ?? '',
          depthPath: row['depth_path'] ?? '',
        )];
    if (composite == null) {
      continue;
    }
    final basename = (row['matched_asset_path'] ?? '').split('/').last;
    final manifestEntry = manifestByBasename[basename];
    final fallbackAssetPath = _fallbackAppAssetPathForFamily(family, basename);
    final appAssetPath = manifestEntry?.appAssetPath ?? fallbackAssetPath;
    final assetKind =
        manifestEntry?.kind ?? (basename.endsWith('.svg') ? 'svg' : 'png');
    if (appAssetPath.isEmpty) {
      continue;
    }
    final transform =
        transformByKey[_transformKey(
          family: family,
          chooserFrame: chooserFrame,
          partRole: composite['part_role'] ?? '',
          namePath: row['name_path'] ?? '',
        )];
    final localMatrix = _matrixFromResolutionRow(row, transform);
    final runtimeAnchor = _parseRuntimeAnchor(row['notes'] ?? '');
    synthesized.add(
      RenderCatalogPart(
        family: family,
        chooserFrame: chooserFrame,
        partRole: composite['part_role'] ?? '',
        orderedPartIndex:
            int.tryParse(composite['ordered_part_index'] ?? '') ?? 0,
        leafId: row['leaf_id'] ?? '',
        originalAssetPath: row['matched_asset_path'] ?? '',
        appAssetPath: appAssetPath,
        assetKind: assetKind,
        tintChannel: composite['tint_channel'] ?? 'none',
        visibilityRule: composite['visibility_rule'] ?? '',
        namePath: row['name_path'] ?? '',
        characterPath: row['character_path'] ?? '',
        depthPath: row['depth_path'] ?? '',
        framePath: row['frame_path'] ?? '',
        hostScope: _hostScopeForFamily(family),
        hostName: _hostNameForFamily(family),
        hostChildName: family == 'ponytail' ? 'ponytail' : '',
        hostDepthPath: '',
        runtimeAnchorX: runtimeAnchor.$1,
        runtimeAnchorY: runtimeAnchor.$2,
        dependencyField: '',
        dependencyValue: null,
        sizeTable: family.contains('eye') || family.contains('eyebrow')
            ? 'eye_standard'
            : family == 'front_hair'
            ? 'hair_extended'
            : 'hair_compact',
        rootSpriteId: row['direct_character_id'] ?? '',
        localMatrix: localMatrix,
        notes: row['notes'] ?? '',
      ),
    );
  }
  synthesized.sort((a, b) {
    final familyCompare = a.family.compareTo(b.family);
    if (familyCompare != 0) return familyCompare;
    final frameCompare = a.chooserFrame.compareTo(b.chooserFrame);
    if (frameCompare != 0) return frameCompare;
    return a.orderedPartIndex.compareTo(b.orderedPartIndex);
  });
  return synthesized;
}

String _resolutionCompositeKey({
  required String family,
  required int chooserFrame,
  required String partRole,
  required String leafId,
  required String depthPath,
}) => '$family|$chooserFrame|$partRole|$leafId|$depthPath';

String _transformKey({
  required String family,
  required int chooserFrame,
  required String partRole,
  required String namePath,
}) => '$family|$chooserFrame|$partRole|$namePath';

String _normalizedPartRole(String family, Map<String, String> row) {
  final slotRole = row['slot_role'] ?? '';
  final namePath = row['name_path'] ?? '';
  if (family.contains('eye')) {
    if (namePath.contains('/pupil/') && slotRole == 'eye') {
      if (namePath.contains('/c1/')) return 'pupil_fill_1';
      if (namePath.contains('/c2/')) return 'pupil_fill_2';
      return 'pupil_outline';
    }
    if (namePath.startsWith('highlight')) return 'highlight';
    if (namePath.startsWith('blinkx')) return 'blink';
    if (namePath.contains('/c1/')) return 'outer_eye_fill_1';
    if (namePath.contains('/c2/')) return 'outer_eye_fill_2';
    if (namePath.contains('/c3/')) return 'outer_eye_fill_3';
    return 'outer_eye_outline';
  }
  if (family.contains('eyebrow')) {
    return 'eyebrow_fill';
  }
  return slotRole == 'hair'
      ? (namePath.contains('/c5/')
            ? 'hair_fill_3'
            : namePath.contains('/c4/')
            ? 'hair_accessory'
            : namePath.contains('/c3/')
            ? 'hair_tips'
            : namePath.contains('/c2/')
            ? 'hair_fill_2'
            : namePath.contains('/<anon>') && !namePath.contains('/c')
            ? 'hair_outline'
            : 'hair_fill_1')
      : slotRole;
}

AffineMatrix _matrixFromResolutionRow(
  Map<String, String> resolution,
  Map<String, String>? transform,
) {
  final tx =
      double.tryParse(transform?['translate_x'] ?? '') ??
      double.tryParse(resolution['anchor_x'] ?? '') ??
      0;
  final ty =
      double.tryParse(transform?['translate_y'] ?? '') ??
      double.tryParse(resolution['anchor_y'] ?? '') ??
      0;
  final scaleX =
      double.tryParse(transform?['scale_x'] ?? '') ??
      double.tryParse(resolution['scale_x'] ?? '') ??
      1;
  final scaleY =
      double.tryParse(transform?['scale_y'] ?? '') ??
      double.tryParse(resolution['scale_y'] ?? '') ??
      1;
  final rotation = double.tryParse(resolution['rotation'] ?? '') ?? 0;
  final radians = rotation * math.pi / 180.0;
  final cosV = math.cos(radians);
  final sinV = math.sin(radians);
  return AffineMatrix(
    a: scaleX * cosV,
    b: scaleX * sinV,
    c: -scaleY * sinV,
    d: scaleY * cosV,
    tx: tx,
    ty: ty,
  );
}

(double, double) _parseRuntimeAnchor(String notes) {
  final match = RegExp(
    r'runtime_anchor=([-0-9.]+),([-0-9.]+)',
  ).firstMatch(notes);
  return (
    double.tryParse(match?.group(1) ?? '') ?? 0,
    double.tryParse(match?.group(2) ?? '') ?? 0,
  );
}

String _fallbackAppAssetPathForFamily(String family, String basename) {
  if (basename.isEmpty) {
    return '';
  }
  final folder = switch (family) {
    'left_eye' || 'right_eye' || 'left_eyebrow' || 'right_eyebrow' => 'eyes',
    'front_hair' ||
    'rear_hair' ||
    'back_hair' ||
    'ponytail' ||
    'ahoge' => 'hair',
    _ => '',
  };
  if (folder.isEmpty) {
    return '';
  }
  return 'assets/gacha/$folder/$basename';
}

String _hostScopeForFamily(String family) {
  switch (family) {
    case 'back_hair':
    case 'ponytail':
      return 'pose';
    default:
      return 'head';
  }
}

String _hostNameForFamily(String family) {
  switch (family) {
    case 'left_eye':
      return 'eye1';
    case 'right_eye':
      return 'eye2';
    case 'left_eyebrow':
      return 'eyebrow1';
    case 'right_eyebrow':
      return 'eyebrow2';
    case 'front_hair':
      return 'fronthair';
    case 'rear_hair':
      return 'rearhair';
    case 'back_hair':
    case 'ponytail':
      return 'backhair';
    case 'ahoge':
      return 'ahoge';
    default:
      return family;
  }
}
