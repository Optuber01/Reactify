import 'dart:ui';

import '../../gacha/render/transform_graph.dart';

const int reactifyCharacterDocumentVersion = 1;
const int reactifySceneDocumentVersion = 1;

enum ReactifyAssetKind { svg, png, vector, raster, drawing, unknown }

enum ReactifySlotKind { semantic, renderLeaf, custom }

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

  factory ReactifyAssetRef.fromJson(Map<String, Object?> json) {
    return ReactifyAssetRef(
      id: _string(json, 'id'),
      kind: _enumByName(ReactifyAssetKind.values, _string(json, 'kind')),
      uri: _string(json, 'uri'),
      source: _string(json, 'source', fallback: 'reactify'),
      preserveVector: _bool(json, 'preserveVector', fallback: true),
    );
  }

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

  factory ReactifyTintChannel.fromJson(Map<String, Object?> json) {
    return ReactifyTintChannel(
      id: _string(json, 'id'),
      color: _colorFromHex(_string(json, 'color')),
    );
  }

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

  factory ReactifyAnchor.fromJson(Map<String, Object?> json) {
    return ReactifyAnchor(
      id: _string(json, 'id'),
      parentId: json['parentId'] as String?,
      localTransform: _matrix(json['localTransform']),
    );
  }

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

  factory ReactifyRigTemplate.fromJson(Map<String, Object?> json) {
    final anchorsJson = _map(json, 'anchors');
    return ReactifyRigTemplate(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      anchors: {
        for (final entry in anchorsJson.entries)
          entry.key: ReactifyAnchor.fromJson(_asMap(entry.value)),
      },
    );
  }

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

class ReactifySlotOverride {
  const ReactifySlotOverride({
    this.visible,
    this.localTransform,
    this.depth,
    this.asset,
    this.tintChannels,
    this.metadata = const {},
  });

  final bool? visible;
  final AffineMatrix? localTransform;
  final int? depth;
  final ReactifyAssetRef? asset;
  final List<ReactifyTintChannel>? tintChannels;
  final Map<String, Object?> metadata;

  factory ReactifySlotOverride.fromJson(Map<String, Object?> json) {
    return ReactifySlotOverride(
      visible: json['visible'] as bool?,
      localTransform: json['localTransform'] == null
          ? null
          : _matrix(json['localTransform']),
      depth: json['depth'] as int?,
      asset: json['asset'] == null
          ? null
          : ReactifyAssetRef.fromJson(_asMap(json['asset'])),
      tintChannels: json['tintChannels'] == null
          ? null
          : [
              for (final entry in _list(json, 'tintChannels'))
                ReactifyTintChannel.fromJson(_asMap(entry)),
            ],
      metadata: _metadata(json['metadata']),
    );
  }

  ReactifySlot applyTo(ReactifySlot slot) {
    return slot.copyWith(
      localTransform: localTransform,
      depth: depth,
      visible: visible,
      asset: asset,
      tintChannels: tintChannels,
      metadata: {...slot.metadata, ...metadata},
    );
  }

  Map<String, Object?> toJson() {
    return {
      'visible': visible,
      'localTransform': localTransform?.toDebugJson(),
      'depth': depth,
      'asset': asset?.toJson(),
      'tintChannels': tintChannels == null
          ? null
          : [for (final channel in tintChannels!) channel.toJson()],
      'metadata': metadata,
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
    this.kind = ReactifySlotKind.renderLeaf,
    this.name,
    this.asset,
    this.tintChannels = const [],
    this.childSlotIds = const [],
    this.overrides = const {},
    this.metadata = const {},
  });

  final String id;
  final String family;
  final ReactifySlotKind kind;
  final String? name;
  final String anchorId;
  final AffineMatrix localTransform;
  final int depth;
  final bool visible;
  final ReactifyAssetRef? asset;
  final List<ReactifyTintChannel> tintChannels;
  final List<String> childSlotIds;
  final Map<String, ReactifySlotOverride> overrides;
  final Map<String, Object?> metadata;

  bool get isRenderable => kind != ReactifySlotKind.semantic && asset != null;

  factory ReactifySlot.fromJson(Map<String, Object?> json) {
    return ReactifySlot(
      id: _string(json, 'id'),
      family: _string(json, 'family'),
      kind: _enumByName(
        ReactifySlotKind.values,
        _string(json, 'kind', fallback: ReactifySlotKind.renderLeaf.name),
      ),
      name: json['name'] as String?,
      anchorId: _string(json, 'anchorId'),
      localTransform: _matrix(json['localTransform']),
      depth: _int(json, 'depth'),
      visible: _bool(json, 'visible', fallback: true),
      asset: json['asset'] == null
          ? null
          : ReactifyAssetRef.fromJson(_asMap(json['asset'])),
      tintChannels: [
        for (final entry in _list(json, 'tintChannels'))
          ReactifyTintChannel.fromJson(_asMap(entry)),
      ],
      childSlotIds: [for (final entry in _list(json, 'childSlotIds')) '$entry'],
      overrides: {
        for (final entry in _map(json, 'overrides').entries)
          entry.key: ReactifySlotOverride.fromJson(_asMap(entry.value)),
      },
      metadata: _metadata(json['metadata']),
    );
  }

  ReactifySlot copyWith({
    String? id,
    String? family,
    ReactifySlotKind? kind,
    String? name,
    String? anchorId,
    AffineMatrix? localTransform,
    int? depth,
    bool? visible,
    ReactifyAssetRef? asset,
    List<ReactifyTintChannel>? tintChannels,
    List<String>? childSlotIds,
    Map<String, ReactifySlotOverride>? overrides,
    Map<String, Object?>? metadata,
  }) {
    return ReactifySlot(
      id: id ?? this.id,
      family: family ?? this.family,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      anchorId: anchorId ?? this.anchorId,
      localTransform: localTransform ?? this.localTransform,
      depth: depth ?? this.depth,
      visible: visible ?? this.visible,
      asset: asset ?? this.asset,
      tintChannels: tintChannels ?? this.tintChannels,
      childSlotIds: childSlotIds ?? this.childSlotIds,
      overrides: overrides ?? this.overrides,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'family': family,
      'kind': kind.name,
      'name': name,
      'anchorId': anchorId,
      'localTransform': localTransform.toDebugJson(),
      'depth': depth,
      'visible': visible,
      'asset': asset?.toJson(),
      'tintChannels': [for (final channel in tintChannels) channel.toJson()],
      'childSlotIds': childSlotIds,
      'overrides': {
        for (final entry in overrides.entries) entry.key: entry.value.toJson(),
      },
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
    this.schemaVersion = reactifyCharacterDocumentVersion,
    this.legacyGachaCode,
    this.metadata = const {},
  });

  final int schemaVersion;
  final String id;
  final String name;
  final ReactifyRigTemplate rig;
  final List<ReactifySlot> slots;
  final String? legacyGachaCode;
  final Map<String, Object?> metadata;

  Iterable<ReactifySlot> slotsForFamily(String family) {
    return slots.where((slot) => slot.family == family);
  }

  Iterable<ReactifySlot> get semanticSlots {
    return slots.where((slot) => slot.kind == ReactifySlotKind.semantic);
  }

  Iterable<ReactifySlot> get renderableSlots {
    return slots.where((slot) => slot.isRenderable);
  }

  factory ReactifyCharacterDocument.fromJson(Map<String, Object?> json) {
    final version = _int(
      json,
      'schemaVersion',
      fallback: reactifyCharacterDocumentVersion,
    );
    if (version > reactifyCharacterDocumentVersion) {
      throw StateError('Unsupported Reactify character schema $version.');
    }
    return ReactifyCharacterDocument(
      schemaVersion: version,
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      rig: ReactifyRigTemplate.fromJson(_asMap(json['rig'])),
      slots: [
        for (final entry in _list(json, 'slots'))
          ReactifySlot.fromJson(_asMap(entry)),
      ],
      legacyGachaCode: json['legacyGachaCode'] as String?,
      metadata: _metadata(json['metadata']),
    );
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
    int? schemaVersion,
    String? id,
    String? name,
    ReactifyRigTemplate? rig,
    List<ReactifySlot>? slots,
    String? legacyGachaCode,
    Map<String, Object?>? metadata,
  }) {
    return ReactifyCharacterDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
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
      'schemaVersion': schemaVersion,
      'id': id,
      'name': name,
      'rig': rig.toJson(),
      'slots': [for (final slot in slots) slot.toJson()],
      'legacyGachaCode': legacyGachaCode,
      'metadata': metadata,
    };
  }
}

class ReactifyBackgroundRef {
  const ReactifyBackgroundRef({
    required this.id,
    required this.asset,
    this.transform = const AffineMatrix.identity(),
    this.visible = true,
  });

  final String id;
  final ReactifyAssetRef asset;
  final AffineMatrix transform;
  final bool visible;

  factory ReactifyBackgroundRef.fromJson(Map<String, Object?> json) {
    return ReactifyBackgroundRef(
      id: _string(json, 'id'),
      asset: ReactifyAssetRef.fromJson(_asMap(json['asset'])),
      transform: _matrix(json['transform']),
      visible: _bool(json, 'visible', fallback: true),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'asset': asset.toJson(),
      'transform': transform.toDebugJson(),
      'visible': visible,
    };
  }
}

class ReactifySceneCharacter {
  const ReactifySceneCharacter({
    required this.id,
    required this.characterId,
    required this.transform,
    this.slotOverrides = const {},
    this.expression,
    this.pose,
    this.dialogue,
    this.metadata = const {},
  });

  final String id;
  final String characterId;
  final AffineMatrix transform;
  final Map<String, ReactifySlotOverride> slotOverrides;
  final String? expression;
  final String? pose;
  final String? dialogue;
  final Map<String, Object?> metadata;

  factory ReactifySceneCharacter.fromJson(Map<String, Object?> json) {
    return ReactifySceneCharacter(
      id: _string(json, 'id'),
      characterId: _string(json, 'characterId'),
      transform: _matrix(json['transform']),
      slotOverrides: {
        for (final entry in _map(json, 'slotOverrides').entries)
          entry.key: ReactifySlotOverride.fromJson(_asMap(entry.value)),
      },
      expression: json['expression'] as String?,
      pose: json['pose'] as String?,
      dialogue: json['dialogue'] as String?,
      metadata: _metadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'characterId': characterId,
      'transform': transform.toDebugJson(),
      'slotOverrides': {
        for (final entry in slotOverrides.entries)
          entry.key: entry.value.toJson(),
      },
      'expression': expression,
      'pose': pose,
      'dialogue': dialogue,
      'metadata': metadata,
    };
  }

  ReactifySceneCharacter copyWith({
    String? id,
    String? characterId,
    AffineMatrix? transform,
    Map<String, ReactifySlotOverride>? slotOverrides,
    String? expression,
    String? pose,
    String? dialogue,
    Map<String, Object?>? metadata,
  }) {
    return ReactifySceneCharacter(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      transform: transform ?? this.transform,
      slotOverrides: slotOverrides ?? this.slotOverrides,
      expression: expression ?? this.expression,
      pose: pose ?? this.pose,
      dialogue: dialogue ?? this.dialogue,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ReactifySceneDocument {
  const ReactifySceneDocument({
    required this.id,
    required this.name,
    required this.characters,
    this.schemaVersion = reactifySceneDocumentVersion,
    this.canvasSize = const Size(1200, 1200),
    this.background,
    this.cameraTransform = const AffineMatrix.identity(),
    this.metadata = const {},
  });

  final int schemaVersion;
  final String id;
  final String name;
  final Size canvasSize;
  final ReactifyBackgroundRef? background;
  final AffineMatrix cameraTransform;
  final List<ReactifySceneCharacter> characters;
  final Map<String, Object?> metadata;

  factory ReactifySceneDocument.fromJson(Map<String, Object?> json) {
    final version = _int(
      json,
      'schemaVersion',
      fallback: reactifySceneDocumentVersion,
    );
    if (version > reactifySceneDocumentVersion) {
      throw StateError('Unsupported Reactify scene schema $version.');
    }
    final canvas = _map(json, 'canvasSize');
    return ReactifySceneDocument(
      schemaVersion: version,
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      canvasSize: Size(
        _double(canvas, 'width', fallback: 1200),
        _double(canvas, 'height', fallback: 1200),
      ),
      background: json['background'] == null
          ? null
          : ReactifyBackgroundRef.fromJson(_asMap(json['background'])),
      cameraTransform: _matrix(json['cameraTransform']),
      characters: [
        for (final entry in _list(json, 'characters'))
          ReactifySceneCharacter.fromJson(_asMap(entry)),
      ],
      metadata: _metadata(json['metadata']),
    );
  }

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
    int? schemaVersion,
    String? id,
    String? name,
    Size? canvasSize,
    ReactifyBackgroundRef? background,
    AffineMatrix? cameraTransform,
    List<ReactifySceneCharacter>? characters,
    Map<String, Object?>? metadata,
  }) {
    return ReactifySceneDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      name: name ?? this.name,
      canvasSize: canvasSize ?? this.canvasSize,
      background: background ?? this.background,
      cameraTransform: cameraTransform ?? this.cameraTransform,
      characters: characters ?? this.characters,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'id': id,
      'name': name,
      'canvasSize': {'width': canvasSize.width, 'height': canvasSize.height},
      'background': background?.toJson(),
      'cameraTransform': cameraTransform.toDebugJson(),
      'characters': [for (final character in characters) character.toJson()],
      'metadata': metadata,
    };
  }
}

class ReactifySceneEditingState {
  const ReactifySceneEditingState({
    required this.scene,
    required this.characters,
    required this.selectedSceneCharacterId,
  });

  final ReactifySceneDocument scene;
  final Map<String, ReactifyCharacterDocument> characters;
  final String selectedSceneCharacterId;

  ReactifySceneCharacter? get selectedSceneCharacter {
    for (final character in scene.characters) {
      if (character.id == selectedSceneCharacterId) {
        return character;
      }
    }
    return scene.characters.isEmpty ? null : scene.characters.first;
  }

  ReactifyCharacterDocument? get selectedCharacterDocument {
    final selected = selectedSceneCharacter;
    return selected == null ? null : characters[selected.characterId];
  }

  factory ReactifySceneEditingState.fromJson(Map<String, Object?> json) {
    final scene = ReactifySceneDocument.fromJson(_asMap(json['scene']));
    final parsedCharacters = <String, ReactifyCharacterDocument>{};
    for (final entry in _list(json, 'characters')) {
      final character = ReactifyCharacterDocument.fromJson(_asMap(entry));
      parsedCharacters[character.id] = character;
    }
    final selectedId = _string(
      json,
      'selectedSceneCharacterId',
      fallback: scene.characters.isEmpty ? '' : scene.characters.first.id,
    );
    return ReactifySceneEditingState(
      scene: scene,
      characters: parsedCharacters,
      selectedSceneCharacterId:
          scene.characters.any((character) => character.id == selectedId)
          ? selectedId
          : (scene.characters.isEmpty ? '' : scene.characters.first.id),
    );
  }

  ReactifySceneEditingState copyWith({
    ReactifySceneDocument? scene,
    Map<String, ReactifyCharacterDocument>? characters,
    String? selectedSceneCharacterId,
  }) {
    final nextScene = scene ?? this.scene;
    final requestedSelection =
        selectedSceneCharacterId ?? this.selectedSceneCharacterId;
    final nextSelection =
        nextScene.characters.any(
          (character) => character.id == requestedSelection,
        )
        ? requestedSelection
        : (nextScene.characters.isEmpty ? '' : nextScene.characters.first.id);
    return ReactifySceneEditingState(
      scene: nextScene,
      characters: characters ?? this.characters,
      selectedSceneCharacterId: nextSelection,
    );
  }

  ReactifySceneEditingState selectSceneCharacter(String sceneCharacterId) {
    return copyWith(selectedSceneCharacterId: sceneCharacterId);
  }

  ReactifySceneEditingState updateSelectedCharacterTransform(
    AffineMatrix transform,
  ) {
    return _replaceSelectedSceneCharacter(
      (character) => character.copyWith(transform: transform),
    );
  }

  ReactifySceneEditingState toggleSelectedSemanticSlotOverride({
    required String family,
    required bool hidden,
  }) {
    final character = selectedCharacterDocument;
    ReactifySlot? semanticSlot;
    if (character != null) {
      for (final slot in character.semanticSlots) {
        if (slot.family == family) {
          semanticSlot = slot;
          break;
        }
      }
    }
    if (semanticSlot == null) {
      return this;
    }
    return updateSelectedSlotOverride(
      semanticSlot.id,
      hidden ? const ReactifySlotOverride(visible: false) : null,
    );
  }

  ReactifySceneEditingState updateSelectedSlotOverride(
    String slotId,
    ReactifySlotOverride? override,
  ) {
    return _replaceSelectedSceneCharacter((character) {
      final overrides = {...character.slotOverrides};
      if (override == null) {
        overrides.remove(slotId);
      } else {
        overrides[slotId] = override;
      }
      return character.copyWith(slotOverrides: overrides);
    });
  }

  ReactifySceneEditingState addCustomSlotToSelectedCharacter(
    ReactifySlot slot,
  ) {
    final character = selectedCharacterDocument;
    if (selectedSceneCharacter == null || character == null) {
      return this;
    }
    final nextCharacters = {...characters};
    nextCharacters[character.id] = character.addSlot(slot);
    return copyWith(characters: nextCharacters);
  }

  ReactifySceneEditingState _replaceSelectedSceneCharacter(
    ReactifySceneCharacter Function(ReactifySceneCharacter character) replace,
  ) {
    var found = false;
    final nextCharacters = <ReactifySceneCharacter>[];
    for (final character in scene.characters) {
      if (character.id == selectedSceneCharacterId) {
        found = true;
        nextCharacters.add(replace(character));
      } else {
        nextCharacters.add(character);
      }
    }
    if (!found) {
      return this;
    }
    return copyWith(scene: scene.copyWith(characters: nextCharacters));
  }

  Map<String, Object?> toJson() {
    final sortedCharacters = characters.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return {
      'schemaVersion': reactifySceneDocumentVersion,
      'selectedSceneCharacterId': selectedSceneCharacterId,
      'scene': scene.toJson(),
      'characters': [
        for (final character in sortedCharacters) character.toJson(),
      ],
    };
  }
}

String _hexColor(Color color) {
  final alpha = color.toARGB32() >>> 24;
  final value = color.toARGB32() & 0x00FFFFFF;
  final rgb = value.toRadixString(16).padLeft(6, '0').toUpperCase();
  if (alpha == 0xFF) {
    return rgb;
  }
  return '$rgb${alpha.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

Color _colorFromHex(String value) {
  final normalized = value.replaceFirst('#', '');
  if (normalized.length == 6) {
    return Color(0xFF000000 | int.parse(normalized, radix: 16));
  }
  if (normalized.length == 8) {
    final rgba = int.parse(normalized, radix: 16);
    return Color(((rgba & 0xFF) << 24) | (rgba >>> 8));
  }
  throw FormatException('Invalid color value: $value');
}

AffineMatrix _matrix(Object? value) {
  if (value == null) {
    return const AffineMatrix.identity();
  }
  final json = _asMap(value);
  return AffineMatrix(
    a: _double(json, 'a', fallback: 1),
    b: _double(json, 'b'),
    c: _double(json, 'c'),
    d: _double(json, 'd', fallback: 1),
    tx: _double(json, 'tx'),
    ty: _double(json, 'ty'),
  );
}

T _enumByName<T extends Enum>(List<T> values, String name) {
  return values.firstWhere((value) => value.name == name);
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {for (final entry in value.entries) '${entry.key}': entry.value};
  }
  throw FormatException('Expected JSON object, got $value');
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const {};
  }
  return _asMap(value);
}

Map<String, Object?> _metadata(Object? value) {
  if (value == null) {
    return const {};
  }
  return _asMap(value);
}

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const [];
  }
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return [for (final entry in value) entry];
  }
  throw FormatException('Expected JSON list for $key, got $value');
}

String _string(Map<String, Object?> json, String key, {String fallback = ''}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  return value as String;
}

int _int(Map<String, Object?> json, String key, {int fallback = 0}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  return value as int;
}

double _double(Map<String, Object?> json, String key, {double fallback = 0}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is int) {
    return value.toDouble();
  }
  return value as double;
}

bool _bool(Map<String, Object?> json, String key, {bool fallback = false}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  return value as bool;
}
