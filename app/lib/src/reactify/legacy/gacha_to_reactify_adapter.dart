import '../../gacha/code/gacha_character_state.dart';
import '../../gacha/render/character_renderer.dart';
import '../../gacha/render/gacha_pose_graph.dart';
import '../../gacha/render/render_part.dart';
import '../../gacha/render/transform_graph.dart';
import '../model/reactify_document.dart';

class GachaToReactifyAdapter {
  const GachaToReactifyAdapter({required this.renderer});

  final CharacterRenderer renderer;

  ReactifyCharacterDocument migrate(GachaCharacterState state, {String? id}) {
    final parts = renderer.resolveParts(state);
    final leafSlots = [for (final part in parts) _slotForPart(state, part)];
    return ReactifyCharacterDocument(
      id: id ?? _stableCharacterId(state),
      name: state.metadata('namex', fallback: 'Imported Gacha Character'),
      rig: _rigForState(state),
      legacyGachaCode: state.serializeCode(),
      metadata: {
        'source': 'gacha_445',
        'pose': state.numeric('pose'),
        'headlayer': state.numeric('headlayer'),
      },
      slots: [..._semanticSlotsFor(leafSlots), ...leafSlots],
    );
  }

  ReactifySlot _slotForPart(
    GachaCharacterState state,
    ResolvedRenderPart part,
  ) {
    final catalog = part.catalogPart;
    final tint = part.tintColor;
    final tintChannels = tint == null || catalog.tintChannel == 'none'
        ? const <ReactifyTintChannel>[]
        : [ReactifyTintChannel(id: catalog.tintChannel, color: tint)];
    return ReactifySlot(
      id: _slotId(part),
      family: _nativeFamilyFor(catalog.family),
      kind: ReactifySlotKind.renderLeaf,
      name: catalog.partRole.isEmpty ? catalog.family : catalog.partRole,
      anchorId: part.targetJoint,
      localTransform: part.localTransform,
      depth: part.globalDepth,
      visible: true,
      asset: ReactifyAssetRef(
        id: catalog.leafId,
        kind: _assetKind(catalog.assetKind, catalog.appAssetPath),
        uri: catalog.appAssetPath,
        source: 'gacha',
        preserveVector: catalog.appAssetPath.toLowerCase().endsWith('.svg'),
      ),
      tintChannels: tintChannels,
      metadata: {
        'legacyFamily': catalog.family,
        'legacyChooserFrame': catalog.chooserFrame,
        'legacyPartRole': catalog.partRole,
        'legacyOrderedPartIndex': catalog.orderedPartIndex,
        'legacyLeafId': catalog.leafId,
        'legacyOriginalAssetPath': catalog.originalAssetPath,
        'legacyTintChannel': catalog.tintChannel,
        'legacyTintStrength': part.tintStrength,
        'legacyOpacity': part.opacity,
        'legacyVisibilityRule': catalog.visibilityRule,
        'legacyHostScope': catalog.hostScope,
        'legacyHostName': catalog.hostName,
        'legacyHostChildName': catalog.hostChildName,
        'legacyHostDepthPath': catalog.hostDepthPath,
        'legacyNamePath': catalog.namePath,
        'legacyCharacterPath': catalog.characterPath,
        'legacyDepthPath': catalog.depthPath,
        'legacyFramePath': catalog.framePath,
        'legacyRuntimeAnchorX': catalog.runtimeAnchorX,
        'legacyRuntimeAnchorY': catalog.runtimeAnchorY,
        'legacyDependencyField': catalog.dependencyField,
        'legacyDependencyValue': catalog.dependencyValue,
        'legacySizeTable': catalog.sizeTable,
        'legacyRootSpriteId': catalog.rootSpriteId,
        'legacyNotes': catalog.notes,
        'statePose': state.numeric('pose'),
      },
    );
  }

  ReactifyRigTemplate _rigForState(GachaCharacterState state) {
    final heightX = renderer.tables.runtimeValueMaps.resolve(
      field: 'heightx',
      fieldValue: state.numeric('heightx'),
      op: 'scaleX',
      targetContains: 'char.char',
      fallback: 1,
    );
    final heightY = renderer.tables.runtimeValueMaps.resolve(
      field: 'heighty',
      fieldValue: state.numeric('heighty'),
      op: 'scaleY',
      targetContains: 'char.char',
      fallback: 1,
    );
    final pose = state.numeric('pose');
    final localTransforms = GachaPoseGraph.localTransforms(
      renderer.tables,
      pose,
    );
    return ReactifyRigTemplate(
      id: 'gacha_compat_2d_v1',
      name: 'Gacha Compatibility 2D Rig',
      anchors: {
        for (final anchor in GachaPoseGraph.anchors)
          anchor.id: ReactifyAnchor(
            id: anchor.id,
            parentId: anchor.parentId,
            localTransform: anchor.id == 'torso'
                ? AffineMatrix.scale(
                    heightX,
                    heightY,
                  ).multiply(localTransforms[anchor.id]!)
                : localTransforms[anchor.id]!,
          ),
      },
    );
  }

  List<ReactifySlot> _semanticSlotsFor(List<ReactifySlot> leafSlots) {
    final groups = <String, List<ReactifySlot>>{};
    for (final slot in leafSlots) {
      final semanticId = _semanticSlotId(slot);
      groups.putIfAbsent(semanticId, () => []).add(slot);
    }
    final slots = <ReactifySlot>[];
    for (final entry in groups.entries) {
      final children = entry.value
        ..sort((left, right) {
          final depthCompare = left.depth.compareTo(right.depth);
          if (depthCompare != 0) return depthCompare;
          return left.id.compareTo(right.id);
        });
      final first = children.first;
      slots.add(
        ReactifySlot(
          id: entry.key,
          family: first.family,
          kind: ReactifySlotKind.semantic,
          name: _semanticName(first),
          anchorId: first.anchorId,
          localTransform: const AffineMatrix.identity(),
          depth: children.first.depth,
          visible: children.any((slot) => slot.visible),
          childSlotIds: [for (final child in children) child.id],
          metadata: {
            'source': 'gacha_semantic_slot',
            'legacyFamilies': {
              for (final child in children)
                child.metadata['legacyFamily'] as String? ?? child.family,
            }.toList()..sort(),
          },
        ),
      );
    }
    slots.sort((left, right) {
      final depthCompare = left.depth.compareTo(right.depth);
      if (depthCompare != 0) return depthCompare;
      return left.id.compareTo(right.id);
    });
    return slots;
  }

  static String _semanticSlotId(ReactifySlot slot) {
    final legacyFamily =
        slot.metadata['legacyFamily'] as String? ?? slot.family;
    final hostName = slot.metadata['legacyHostName'] as String? ?? '';
    if (legacyFamily == 'left_eye' || legacyFamily == 'right_eye') {
      return 'slot.face.$legacyFamily';
    }
    if (legacyFamily == 'left_eyebrow' || legacyFamily == 'right_eyebrow') {
      return 'slot.face.$legacyFamily';
    }
    if (legacyFamily.contains('hair')) {
      return 'slot.hair.$legacyFamily';
    }
    if (legacyFamily == 'hat' ||
        legacyFamily == 'glasses' ||
        legacyFamily.contains('accessory') ||
        legacyFamily.contains('other')) {
      return 'slot.accessory.$legacyFamily.$hostName';
    }
    if (legacyFamily.contains('weapon') || legacyFamily == 'shield') {
      return 'slot.prop.$legacyFamily.$hostName';
    }
    if (slot.family == 'clothing') {
      return 'slot.clothing.$legacyFamily.$hostName';
    }
    return 'slot.${slot.family}.$legacyFamily.$hostName';
  }

  static String _semanticName(ReactifySlot slot) {
    final legacyFamily =
        slot.metadata['legacyFamily'] as String? ?? slot.family;
    return legacyFamily
        .split('_')
        .where((segment) => segment.isNotEmpty)
        .map((segment) => '${segment[0].toUpperCase()}${segment.substring(1)}')
        .join(' ');
  }

  static String _slotId(ResolvedRenderPart part) {
    final catalog = part.catalogPart;
    return [
      'legacy',
      catalog.family,
      catalog.chooserFrame,
      catalog.partRole,
      catalog.orderedPartIndex,
      catalog.leafId,
    ].map((value) => _idSegment('$value')).join('.');
  }

  static String _stableCharacterId(GachaCharacterState state) {
    final name = _idSegment(state.metadata('namex', fallback: 'character'));
    final hash = _stableHash(state.serializeCode());
    return 'gacha.$name.$hash';
  }

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193).toUnsigned(32);
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _nativeFamilyFor(String legacyFamily) {
    if (legacyFamily.contains('hair')) return 'hair';
    if (legacyFamily.contains('eyebrow')) return 'eyebrows';
    if (legacyFamily.contains('eye') || legacyFamily.contains('pupil')) {
      return 'eyes';
    }
    if (legacyFamily == 'mouth' ||
        legacyFamily == 'nose' ||
        legacyFamily == 'blush' ||
        legacyFamily == 'faceshadow') {
      return 'face';
    }
    if (legacyFamily == 'hat' ||
        legacyFamily == 'glasses' ||
        legacyFamily.contains('accessory') ||
        legacyFamily.contains('other')) {
      return 'accessories';
    }
    if (legacyFamily.contains('weapon') || legacyFamily == 'shield') {
      return 'props';
    }
    if (legacyFamily.contains('body') ||
        legacyFamily.contains('shirt') ||
        legacyFamily.contains('jacket') ||
        legacyFamily.contains('pants') ||
        legacyFamily.contains('shoe') ||
        legacyFamily.contains('sock') ||
        legacyFamily.contains('sleeve') ||
        legacyFamily.contains('belt') ||
        legacyFamily.contains('glove') ||
        legacyFamily.contains('wrist') ||
        legacyFamily.contains('shoulder') ||
        legacyFamily.contains('knee')) {
      return 'clothing';
    }
    if (legacyFamily == 'cape' ||
        legacyFamily == 'tail' ||
        legacyFamily.contains('wings') ||
        legacyFamily.contains('scarf')) {
      return 'extras';
    }
    if (legacyFamily == 'head_shape') return 'head';
    return legacyFamily;
  }

  static ReactifyAssetKind _assetKind(String assetKind, String assetPath) {
    final normalized = assetKind.toLowerCase();
    if (normalized == 'svg' || assetPath.toLowerCase().endsWith('.svg')) {
      return ReactifyAssetKind.svg;
    }
    if (normalized == 'png' || assetPath.toLowerCase().endsWith('.png')) {
      return ReactifyAssetKind.png;
    }
    return ReactifyAssetKind.unknown;
  }

  static String _idSegment(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'slot' : normalized;
  }
}
