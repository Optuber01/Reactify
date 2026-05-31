import 'dart:ui';

import '../../gacha/render/transform_graph.dart';

enum ReactifyAssetKind { svg, png, vector, raster, drawing, unknown }

class ReactifyAssetRef {
  const ReactifyAssetRef({
    required this.id,
    required this.kind,
    required this.uri,
    this.source = 'reactify',
    this.preserveVector = true,
  });

  final String id;
  final ReactifyAssetKind kind;
  final String uri;
  final String source;
  final bool preserveVector;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'uri': uri,
      'source': source,
      'preserveVector': preserveVector,
    };
  }
}

class ReactifyTintChannel {
  const ReactifyTintChannel({required this.id, required this.color});

  final String id;
  final Color color;

  Map<String, Object?> toJson() {
    return {'id': id, 'color': _hexColor(color)};
  }
}

class ReactifyAnchor {
  const ReactifyAnchor({
    required this.id,
    required this.localTransform,
    this.parentId,
  });

  final String id;
  final String? parentId;
  final AffineMatrix localTransform;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'localTransform': localTransform.toDebugJson(),
    };
  }
}

class ReactifyRigTemplate {
  const ReactifyRigTemplate({
    required this.id,
    required this.name,
    required this.anchors,
  });

  final String id;
  final String name;
  final Map<String, ReactifyAnchor> anchors;

  static const ReactifyRigTemplate gachaCompatibility = ReactifyRigTemplate(
    id: 'gacha_compat_2d_v1',
    name: 'Gacha Compatibility 2D Rig',
    anchors: {
      'torso': ReactifyAnchor(
        id: 'torso',
        localTransform: AffineMatrix.identity(),
      ),
      'head': ReactifyAnchor(
        id: 'head',
        parentId: 'torso',
        localTransform: AffineMatrix.identity(),
      ),
      'shoulder_front': ReactifyAnchor(
        id: 'shoulder_front',
        parentId: 'torso',
        localTransform: AffineMatrix.identity(),
      ),
      'shoulder_back': ReactifyAnchor(
        id: 'shoulder_back',
        parentId: 'torso',
        localTransform: AffineMatrix.identity(),
      ),
      'forearm_front': ReactifyAnchor(
        id: 'forearm_front',
        parentId: 'shoulder_front',
        localTransform: AffineMatrix.identity(),
      ),
      'forearm_back': ReactifyAnchor(
        id: 'forearm_back',
        parentId: 'shoulder_back',
        localTransform: AffineMatrix.identity(),
      ),
      'hip': ReactifyAnchor(
        id: 'hip',
        parentId: 'torso',
        localTransform: AffineMatrix.identity(),
      ),
      'thigh_front': ReactifyAnchor(
        id: 'thigh_front',
        parentId: 'hip',
        localTransform: AffineMatrix.identity(),
      ),
      'thigh_back': ReactifyAnchor(
        id: 'thigh_back',
        parentId: 'hip',
        localTransform: AffineMatrix.identity(),
      ),
      'feet_front': ReactifyAnchor(
        id: 'feet_front',
        parentId: 'thigh_front',
        localTransform: AffineMatrix.identity(),
      ),
      'feet_back': ReactifyAnchor(
        id: 'feet_back',
        parentId: 'thigh_back',
        localTransform: AffineMatrix.identity(),
      ),
    },
  );

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'anchors': {
        for (final entry in anchors.entries) entry.key: entry.value.toJson(),
      },
    };
  }
}

class ReactifySlot {
  const ReactifySlot({
    required this.id,
    required this.family,
    required this.anchorId,
    required this.localTransform,
    required this.depth,
    required this.visible,
    this.name,
    this.asset,
    this.tintChannels = const [],
    this.metadata = const {},
  });

  final String id;
  final String family;
  final String? name;
  final String anchorId;
  final AffineMatrix localTransform;
  final int depth;
  final bool visible;
  final ReactifyAssetRef? asset;
  final List<ReactifyTintChannel> tintChannels;
  final Map<String, Object?> metadata;

  ReactifySlot copyWith({
    String? id,
    String? family,
    String? name,
    String? anchorId,
    AffineMatrix? localTransform,
    int? depth,
    bool? visible,
    ReactifyAssetRef? asset,
    List<ReactifyTintChannel>? tintChannels,
    Map<String, Object?>? metadata,
  }) {
    return ReactifySlot(
      id: id ?? this.id,
      family: family ?? this.family,
      name: name ?? this.name,
      anchorId: anchorId ?? this.anchorId,
      localTransform: localTransform ?? this.localTransform,
      depth: depth ?? this.depth,
      visible: visible ?? this.visible,
      asset: asset ?? this.asset,
      tintChannels: tintChannels ?? this.tintChannels,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'family': family,
      'name': name,
      'anchorId': anchorId,
      'localTransform': localTransform.toDebugJson(),
      'depth': depth,
      'visible': visible,
      'asset': asset?.toJson(),
      'tintChannels': [
        for (final channel in tintChannels) channel.toJson(),
      ],
      'metadata': metadata,
    };
  }
}

class ReactifyCharacterDocument {
  const ReactifyCharacterDocument({
    required this.id,
    required this.name,
    required this.rig,
    required this.slots,
    this.legacyGachaCode,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final ReactifyRigTemplate rig;
  final List<ReactifySlot> slots;
  final String? legacyGachaCode;
  final Map<String, Object?> metadata;

  Iterable<ReactifySlot> slotsForFamily(String family) {
    return slots.where((slot) => slot.family == family);
  }

  ReactifyCharacterDocument addSlot(ReactifySlot slot) {
    if (slots.any((existing) => existing.id == slot.id)) {
      throw ArgumentError.value(slot.id, 'slot.id', 'Duplicate slot id.');
    }
    final nextSlots = [...slots, slot]
      ..sort((left, right) {
        final depthCompare = left.depth.compareTo(right.depth);
        if (depthCompare != 0) return depthCompare;
        return left.id.compareTo(right.id);
      });
    return copyWith(slots: nextSlots);
  }

  ReactifyCharacterDocument copyWith({
    String? id,
    String? name,
    ReactifyRigTemplate? rig,
    List<ReactifySlot>? slots,
    String? legacyGachaCode,
    Map<String, Object?>? metadata,
  }) {
    return ReactifyCharacterDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      rig: rig ?? this.rig,
      slots: slots ?? this.slots,
      legacyGachaCode: legacyGachaCode ?? this.legacyGachaCode,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'rig': rig.toJson(),
      'slots': [for (final slot in slots) slot.toJson()],
      'legacyGachaCode': legacyGachaCode,
      'metadata': metadata,
    };
  }
}

class ReactifySceneCharacter {
  const ReactifySceneCharacter({
    required this.id,
    required this.characterId,
    required this.transform,
    this.slotOverrides = const {},
  });

  final String id;
  final String characterId;
  final AffineMatrix transform;
  final Map<String, ReactifySlot> slotOverrides;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'characterId': characterId,
      'transform': transform.toDebugJson(),
      'slotOverrides': {
        for (final entry in slotOverrides.entries)
          entry.key: entry.value.toJson(),
      },
    };
  }
}

class ReactifySceneDocument {
  const ReactifySceneDocument({
    required this.id,
    required this.name,
    required this.characters,
    this.canvasSize = const Size(1200, 1200),
    this.metadata = const {},
  });

  final String id;
  final String name;
  final Size canvasSize;
  final List<ReactifySceneCharacter> characters;
  final Map<String, Object?> metadata;

  ReactifySceneDocument addCharacter(ReactifySceneCharacter character) {
    if (characters.any((existing) => existing.id == character.id)) {
      throw ArgumentError.value(
        character.id,
        'character.id',
        'Duplicate scene character id.',
      );
    }
    return copyWith(characters: [...characters, character]);
  }

  ReactifySceneDocument copyWith({
    String? id,
    String? name,
    Size? canvasSize,
    List<ReactifySceneCharacter>? characters,
    Map<String, Object?>? metadata,
  }) {
    return ReactifySceneDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      canvasSize: canvasSize ?? this.canvasSize,
      characters: characters ?? this.characters,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'canvasSize': {'width': canvasSize.width, 'height': canvasSize.height},
      'characters': [for (final character in characters) character.toJson()],
      'metadata': metadata,
    };
  }
}

String _hexColor(Color color) {
  final value = color.toARGB32() & 0x00FFFFFF;
  return value.toRadixString(16).padLeft(6, '0').toUpperCase();
}
