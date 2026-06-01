import 'dart:ui';

import '../../gacha/data/resolver_tables.dart';
import '../../gacha/render/character_renderer.dart';
import '../../gacha/render/render_part.dart';
import '../../gacha/render/transform_graph.dart';
import '../model/reactify_document.dart';

class ReactifyRenderBridge {
  const ReactifyRenderBridge({required this.assetStore});

  final GachaAssetStore assetStore;

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
      resolved.addAll(resolveCharacterParts(character, sceneCharacter));
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
        sceneCharacter?.transform ?? const AffineMatrix.identity();
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
      globalDepth: slot.depth,
    );
  }

  RenderCatalogPart _catalogPartFor(ReactifySlot slot, ReactifyAssetRef asset) {
    final metadata = slot.metadata;
    return RenderCatalogPart(
      family: _metadataString(metadata, 'legacyFamily', fallback: slot.family),
      chooserFrame: _metadataInt(metadata, 'legacyChooserFrame'),
      partRole: _metadataString(metadata, 'legacyPartRole'),
      orderedPartIndex: _metadataInt(metadata, 'legacyOrderedPartIndex'),
      leafId: _metadataString(metadata, 'legacyLeafId', fallback: asset.id),
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
      for (final part in resolveCharacterParts(character, sceneCharacter)) {
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
