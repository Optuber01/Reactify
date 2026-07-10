import 'dart:ui';

import '../../gacha/data/resolver_tables.dart';
import '../../gacha/render/character_renderer.dart';
import '../../gacha/render/render_part.dart';
import '../../gacha/render/transform_graph.dart';
import '../model/reactify_document.dart';

class ReactifyRenderBridge {
  const ReactifyRenderBridge({required this.assetStore});

  final GachaAssetStore assetStore;
  static final Map<String, ReactifyDrawingPreparedAsset> _drawingAssetCache =
      {};

  Future<ResolvedScene> buildRenderableScene(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
  ) async {
    final entries = resolveRenderableSceneParts(scene, characters);
    final assetPaths = {
      for (final entry in entries)
        if (!_isInlineDrawing(entry.asset) &&
            entry.asset.uri.isNotEmpty &&
            entry.part.catalogPart.appAssetPath.isNotEmpty)
          entry.part.catalogPart.appAssetPath,
    };
    final assets = await assetStore.loadAll(assetPaths);
    for (final entry in entries) {
      if (_isInlineDrawing(entry.asset)) {
        final cacheKey = _drawingCacheKey(entry.asset, entry.slot.metadata);
        assets[entry.asset.uri] = _drawingAssetCache.putIfAbsent(
          cacheKey,
          () => ReactifyDrawingPreparedAsset(
            assetPath: entry.asset.uri,
            strokes: _drawingStrokes(entry.slot.metadata),
            strokeWidth: _metadataDouble(
              entry.slot.metadata,
              'drawingStrokeWidth',
              fallback: 3.5,
            ),
            color: _metadataColor(entry.slot.metadata, 'drawingColor'),
          ),
        );
      }
    }
    return ResolvedScene(
      parts: [for (final entry in entries) entry.part],
      assets: assets,
      worldBounds: _boundsForRenderableEntries(entries, assets),
      warnings: const [],
    );
  }

  Future<ResolvedScene> buildScene(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
  ) async {
    final parts = resolveSceneParts(scene, characters);
    final assetPaths = {
      for (final part in parts)
        if (part.catalogPart.appAssetPath.isNotEmpty)
          part.catalogPart.appAssetPath,
    };
    final assets = await assetStore.loadAll(assetPaths);
    return ResolvedScene(
      parts: parts,
      assets: assets,
      worldBounds: _worldBounds(scene, characters, assets),
      warnings: const [],
    );
  }

  List<ReactifyRenderableScenePart> resolveRenderableSceneParts(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
  ) {
    final entries = <ReactifyRenderableScenePart>[];
    final sceneDepths = {
      for (var index = 0; index < scene.characters.length; index++)
        scene.characters[index].id: index * 1000000000000,
    };
    for (final sceneCharacter in scene.characters) {
      final character = characters[sceneCharacter.characterId];
      if (character == null) {
        continue;
      }
      final anchorWorld = _anchorWorldTransforms(character.rig);
      for (final slot in _effectiveSlots(character, sceneCharacter)) {
        final asset = slot.asset;
        if (!slot.visible || asset == null) {
          continue;
        }
        final basePart = _partForSlot(slot, sceneCharacter.transform);
        final parentWorld =
            anchorWorld[slot.anchorId] ??
            anchorWorld['torso'] ??
            const AffineMatrix.identity();
        final flattened = scene.cameraTransform
            .multiply(sceneCharacter.transform)
            .multiply(parentWorld)
            .multiply(slot.localTransform);
        entries.add(
          ReactifyRenderableScenePart(
            slot: slot,
            asset: asset,
            part: ResolvedRenderPart(
              catalogPart: _catalogPartFor(
                slot,
                asset,
                leafIdPrefix: sceneCharacter.id,
              ),
              localTransform: flattened,
              targetJoint: 'torso',
              tintColor: basePart.tintColor,
              tintStrength: basePart.tintStrength,
              opacity: basePart.opacity,
              globalDepth:
                  (sceneDepths[sceneCharacter.id] ?? 0) + basePart.globalDepth,
            ),
          ),
        );
      }
    }
    entries.sort((left, right) {
      final depthCompare = left.part.globalDepth.compareTo(
        right.part.globalDepth,
      );
      if (depthCompare != 0) return depthCompare;
      return left.part.catalogPart.leafId.compareTo(
        right.part.catalogPart.leafId,
      );
    });
    return entries;
  }

  List<ResolvedRenderPart> resolveSceneParts(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
  ) {
    final resolved = <ResolvedRenderPart>[];
    for (final sceneCharacter in scene.characters) {
      final character = characters[sceneCharacter.characterId];
      if (character == null) {
        continue;
      }
      resolved.addAll(
        resolveCharacterParts(
          character,
          sceneCharacter,
          scene.cameraTransform.multiply(sceneCharacter.transform),
        ),
      );
    }
    resolved.sort((left, right) {
      final depthCompare = left.globalDepth.compareTo(right.globalDepth);
      if (depthCompare != 0) return depthCompare;
      return left.catalogPart.leafId.compareTo(right.catalogPart.leafId);
    });
    return resolved;
  }

  List<ResolvedRenderPart> resolveCharacterParts(
    ReactifyCharacterDocument character, [
    ReactifySceneCharacter? sceneCharacter,
    AffineMatrix? resolvedSceneTransform,
  ]) {
    final slotsById = {for (final slot in character.slots) slot.id: slot};
    final semanticOverrides = <String, ReactifySlotOverride>{};
    final sceneOverrides = sceneCharacter?.slotOverrides ?? const {};
    for (final entry in sceneOverrides.entries) {
      final slot = slotsById[entry.key];
      if (slot?.kind == ReactifySlotKind.semantic) {
        for (final childId in slot!.childSlotIds) {
          semanticOverrides[childId] = entry.value;
        }
      }
    }
    final sceneTransform =
        resolvedSceneTransform ??
        sceneCharacter?.transform ??
        const AffineMatrix.identity();
    final parts = <ResolvedRenderPart>[];
    for (final baseSlot in character.renderableSlots) {
      final semanticOverride = semanticOverrides[baseSlot.id];
      final directOverride = sceneOverrides[baseSlot.id];
      var slot = baseSlot;
      if (semanticOverride != null) {
        slot = semanticOverride.applyTo(slot);
      }
      if (directOverride != null) {
        slot = directOverride.applyTo(slot);
      }
      if (!slot.visible || slot.asset == null) {
        continue;
      }
      parts.add(_partForSlot(slot, sceneTransform));
    }
    parts.sort((left, right) {
      final depthCompare = left.globalDepth.compareTo(right.globalDepth);
      if (depthCompare != 0) return depthCompare;
      return left.catalogPart.leafId.compareTo(right.catalogPart.leafId);
    });
    return parts;
  }

  ResolvedRenderPart _partForSlot(
    ReactifySlot slot,
    AffineMatrix sceneTransform,
  ) {
    final asset = slot.asset!;
    return ResolvedRenderPart(
      catalogPart: _catalogPartFor(slot, asset),
      localTransform: slot.localTransform,
      sceneTransform: sceneTransform,
      targetJoint: slot.anchorId,
      tintColor: slot.tintChannels.isEmpty
          ? null
          : slot.tintChannels.first.color,
      tintStrength: _metadataDouble(
        slot.metadata,
        'legacyTintStrength',
        fallback: 1,
      ),
      opacity: _metadataDouble(slot.metadata, 'legacyOpacity', fallback: 1),
      globalDepth: slot.depth,
    );
  }

  RenderCatalogPart _catalogPartFor(
    ReactifySlot slot,
    ReactifyAssetRef asset, {
    String? leafIdPrefix,
  }) {
    final metadata = slot.metadata;
    final leafId = _metadataString(
      metadata,
      'legacyLeafId',
      fallback: asset.id,
    );
    return RenderCatalogPart(
      family: _metadataString(metadata, 'legacyFamily', fallback: slot.family),
      chooserFrame: _metadataInt(metadata, 'legacyChooserFrame'),
      partRole: _metadataString(metadata, 'legacyPartRole'),
      orderedPartIndex: _metadataInt(metadata, 'legacyOrderedPartIndex'),
      leafId: leafIdPrefix == null ? leafId : '$leafIdPrefix.$leafId',
      originalAssetPath: _metadataString(
        metadata,
        'legacyOriginalAssetPath',
        fallback: asset.uri,
      ),
      appAssetPath: asset.uri,
      assetKind: asset.kind.name,
      tintChannel: _metadataString(
        metadata,
        'legacyTintChannel',
        fallback: slot.tintChannels.isEmpty
            ? 'none'
            : slot.tintChannels.first.id,
      ),
      visibilityRule: _metadataString(metadata, 'legacyVisibilityRule'),
      namePath: _metadataString(metadata, 'legacyNamePath'),
      characterPath: _metadataString(metadata, 'legacyCharacterPath'),
      depthPath: _metadataString(metadata, 'legacyDepthPath'),
      framePath: _metadataString(metadata, 'legacyFramePath'),
      hostScope: _metadataString(metadata, 'legacyHostScope'),
      hostName: _metadataString(metadata, 'legacyHostName'),
      hostChildName: _metadataString(metadata, 'legacyHostChildName'),
      hostDepthPath: _metadataString(metadata, 'legacyHostDepthPath'),
      runtimeAnchorX: _metadataDouble(metadata, 'legacyRuntimeAnchorX'),
      runtimeAnchorY: _metadataDouble(metadata, 'legacyRuntimeAnchorY'),
      dependencyField: _metadataString(metadata, 'legacyDependencyField'),
      dependencyValue: _metadataNullableInt(metadata, 'legacyDependencyValue'),
      sizeTable: _metadataString(metadata, 'legacySizeTable'),
      rootSpriteId: _metadataString(metadata, 'legacyRootSpriteId'),
      localMatrix: slot.localTransform,
      notes: _metadataString(metadata, 'legacyNotes'),
    );
  }

  Iterable<ReactifySlot> _effectiveSlots(
    ReactifyCharacterDocument character,
    ReactifySceneCharacter sceneCharacter,
  ) sync* {
    final slotsById = {for (final slot in character.slots) slot.id: slot};
    final semanticOverrides = <String, ReactifySlotOverride>{};
    for (final entry in sceneCharacter.slotOverrides.entries) {
      final slot = slotsById[entry.key];
      if (slot?.kind == ReactifySlotKind.semantic) {
        for (final childId in slot!.childSlotIds) {
          semanticOverrides[childId] = entry.value;
        }
      }
    }
    for (final baseSlot in character.renderableSlots) {
      var slot = baseSlot;
      final semanticOverride = semanticOverrides[baseSlot.id];
      final directOverride = sceneCharacter.slotOverrides[baseSlot.id];
      if (semanticOverride != null) {
        slot = semanticOverride.applyTo(slot);
      }
      if (directOverride != null) {
        slot = directOverride.applyTo(slot);
      }
      yield slot;
    }
  }

  Rect _worldBounds(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
    Map<String, PreparedAsset> assets,
  ) {
    var bounds = Rect.zero;
    var hasBounds = false;
    for (final sceneCharacter in scene.characters) {
      final character = characters[sceneCharacter.characterId];
      if (character == null) {
        continue;
      }
      final anchorWorld = _anchorWorldTransforms(character.rig);
      for (final part in resolveCharacterParts(
        character,
        sceneCharacter,
        scene.cameraTransform.multiply(sceneCharacter.transform),
      )) {
        final asset = assets[part.catalogPart.appAssetPath];
        if (asset == null) {
          continue;
        }
        final parentWorld =
            anchorWorld[part.targetJoint] ??
            anchorWorld['torso'] ??
            const AffineMatrix.identity();
        final worldMatrix = part.sceneTransform
            .multiply(parentWorld)
            .multiply(part.localTransform);
        final partBounds = worldMatrix.transformRect(
          Rect.fromLTWH(0, 0, asset.size.width, asset.size.height),
        );
        bounds = hasBounds ? bounds.expandToInclude(partBounds) : partBounds;
        hasBounds = true;
      }
    }
    return bounds;
  }

  Map<String, AffineMatrix> _anchorWorldTransforms(ReactifyRigTemplate rig) {
    final resolved = <String, AffineMatrix>{};
    AffineMatrix resolve(String id) {
      final existing = resolved[id];
      if (existing != null) {
        return existing;
      }
      final anchor = rig.anchors[id];
      if (anchor == null) {
        return const AffineMatrix.identity();
      }
      final parentId = anchor.parentId;
      final matrix = parentId == null
          ? anchor.localTransform
          : resolve(parentId).multiply(anchor.localTransform);
      resolved[id] = matrix;
      return matrix;
    }

    for (final id in rig.anchors.keys) {
      resolve(id);
    }
    return resolved;
  }

  Rect _boundsForRenderableEntries(
    List<ReactifyRenderableScenePart> entries,
    Map<String, PreparedAsset> assets,
  ) {
    var bounds = Rect.zero;
    var hasBounds = false;
    for (final entry in entries) {
      final asset = assets[entry.part.catalogPart.appAssetPath];
      if (asset == null) {
        continue;
      }
      final partBounds = entry.part.localTransform.transformRect(
        Rect.fromLTWH(0, 0, asset.size.width, asset.size.height),
      );
      bounds = hasBounds ? bounds.expandToInclude(partBounds) : partBounds;
      hasBounds = true;
    }
    return bounds;
  }

  static bool _isInlineDrawing(ReactifyAssetRef asset) {
    return asset.kind == ReactifyAssetKind.drawing ||
        asset.uri.startsWith('reactify://drawing/');
  }

  static String _drawingCacheKey(
    ReactifyAssetRef asset,
    Map<String, Object?> metadata,
  ) {
    return [
      asset.uri,
      metadata['drawingColor'] ?? '',
      metadata['drawingStrokeWidth'] ?? '',
      metadata['drawingStrokes'] ?? '',
    ].join('|');
  }

  static List<List<Offset>> _drawingStrokes(Map<String, Object?> metadata) {
    final raw = metadata['drawingStrokes'];
    if (raw is! List) {
      return const [];
    }
    return [
      for (final stroke in raw)
        if (stroke is List)
          [
            for (final point in stroke)
              if (point is Map)
                Offset(_objectDouble(point['x']), _objectDouble(point['y'])),
          ],
    ];
  }

  static Color _metadataColor(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is Color) {
      return value;
    }
    if (value is String) {
      final normalized = value.replaceFirst('#', '');
      final parsed = int.tryParse(normalized, radix: 16);
      if (parsed != null) {
        if (normalized.length == 6) {
          return Color(0xFF000000 | parsed);
        }
        if (normalized.length == 8) {
          return Color(parsed);
        }
      }
    }
    return const Color(0xFF00F5FF);
  }

  static double _objectDouble(Object? value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }
}

class ReactifyRenderableScenePart {
  const ReactifyRenderableScenePart({
    required this.slot,
    required this.asset,
    required this.part,
  });

  final ReactifySlot slot;
  final ReactifyAssetRef asset;
  final ResolvedRenderPart part;
}

class ReactifyDrawingPreparedAsset extends PreparedAsset {
  ReactifyDrawingPreparedAsset({
    required super.assetPath,
    required this.strokes,
    required this.strokeWidth,
    required this.color,
  }) : super(size: _boundsFor(strokes, strokeWidth).size) {
    final bounds = _boundsFor(strokes, strokeWidth);
    _offset = Offset(-bounds.left, -bounds.top);
  }

  final List<List<Offset>> strokes;
  final double strokeWidth;
  final Color color;
  late final Offset _offset;

  @override
  void paint(
    Canvas canvas,
    Color? tintColor, {
    double tintStrength = 1,
    double opacity = 1,
  }) {
    final paint = Paint()
      ..color = (tintColor ?? color).withValues(alpha: opacity)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.translate(_offset.dx, _offset.dy);
    for (final stroke in strokes) {
      if (stroke.length < 2) {
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  static Rect _boundsFor(List<List<Offset>> strokes, double strokeWidth) {
    var left = 0.0;
    var top = 0.0;
    var right = 1.0;
    var bottom = 1.0;
    var initialized = false;
    for (final stroke in strokes) {
      for (final point in stroke) {
        if (!initialized) {
          left = right = point.dx;
          top = bottom = point.dy;
          initialized = true;
        } else {
          if (point.dx < left) left = point.dx;
          if (point.dx > right) right = point.dx;
          if (point.dy < top) top = point.dy;
          if (point.dy > bottom) bottom = point.dy;
        }
      }
    }
    final padded = Rect.fromLTRB(
      left,
      top,
      right,
      bottom,
    ).inflate(strokeWidth * 0.5);
    return padded.isEmpty ? const Rect.fromLTWH(0, 0, 1, 1) : padded;
  }
}

String _metadataString(
  Map<String, Object?> metadata,
  String key, {
  String fallback = '',
}) {
  final value = metadata[key];
  if (value == null) {
    return fallback;
  }
  return '$value';
}

int _metadataInt(
  Map<String, Object?> metadata,
  String key, {
  int fallback = 0,
}) {
  final value = metadata[key];
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

int? _metadataNullableInt(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double _metadataDouble(
  Map<String, Object?> metadata,
  String key, {
  double fallback = 0,
}) {
  final value = metadata[key];
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}
