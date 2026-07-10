import 'dart:convert';

import 'project_time.dart';

const int reactifyReactionProjectSchemaVersion = 1;

typedef ProjectId = String;
typedef AssetId = String;
typedef CharacterId = String;
typedef ExpressionId = String;
typedef PoseId = String;
typedef LayoutId = String;
typedef ReactionStateId = String;
typedef TextPresetId = String;
typedef SpeakerRuleId = String;
typedef TimelineId = String;
typedef TrackId = String;
typedef ClipId = String;
typedef MarkerId = String;
typedef BinId = String;
typedef ExportPresetId = String;

enum ProjectAssetKind { video, audio, image, svg, font, drawing, data, unknown }

enum ProjectBinKind {
  asset,
  character,
  expression,
  pose,
  layout,
  reactionState,
  textPreset,
  speakerRule,
  exportPreset,
}

enum TimelineTrackType {
  reactionState,
  video,
  imageOverlay,
  richText,
  audio,
  watermark,
}

enum TextAlignment { start, center, end, justify }

enum TextCapitalization { unchanged, uppercase, lowercase, titleCase }

enum ExportContainer { mp4, pngSequence, transparentPngSequence }

class ProjectCanvas {
  const ProjectCanvas({
    required this.width,
    required this.height,
    this.backgroundColor = '#00000000',
  }) : assert(width > 0),
       assert(height > 0);

  final int width;
  final int height;
  final String backgroundColor;

  factory ProjectCanvas.fromJson(Map<String, Object?> json) {
    return ProjectCanvas(
      width: jsonInt(json, 'width'),
      height: jsonInt(json, 'height'),
      backgroundColor: jsonString(
        json,
        'backgroundColor',
        fallback: '#00000000',
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'backgroundColor': backgroundColor,
    'height': height,
    'width': width,
  };

  ProjectCanvas copyWith({int? width, int? height, String? backgroundColor}) {
    return ProjectCanvas(
      width: width ?? this.width,
      height: height ?? this.height,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }
}

class AffineTransform {
  const AffineTransform({
    this.a = 1,
    this.b = 0,
    this.c = 0,
    this.d = 1,
    this.tx = 0,
    this.ty = 0,
  });

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;

  factory AffineTransform.fromJson(Map<String, Object?> json) {
    return AffineTransform(
      a: jsonDouble(json, 'a', fallback: 1),
      b: jsonDouble(json, 'b'),
      c: jsonDouble(json, 'c'),
      d: jsonDouble(json, 'd', fallback: 1),
      tx: jsonDouble(json, 'tx'),
      ty: jsonDouble(json, 'ty'),
    );
  }

  Map<String, Object?> toJson() => {
    'a': a,
    'b': b,
    'c': c,
    'd': d,
    'tx': tx,
    'ty': ty,
  };

  AffineTransform copyWith({
    double? a,
    double? b,
    double? c,
    double? d,
    double? tx,
    double? ty,
  }) {
    return AffineTransform(
      a: a ?? this.a,
      b: b ?? this.b,
      c: c ?? this.c,
      d: d ?? this.d,
      tx: tx ?? this.tx,
      ty: ty ?? this.ty,
    );
  }
}

class NormalizedRect {
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  factory NormalizedRect.fromJson(Map<String, Object?> json) {
    return NormalizedRect(
      left: jsonDouble(json, 'left'),
      top: jsonDouble(json, 'top'),
      width: jsonDouble(json, 'width'),
      height: jsonDouble(json, 'height'),
    );
  }

  Map<String, Object?> toJson() => {
    'height': height,
    'left': left,
    'top': top,
    'width': width,
  };

  NormalizedRect copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return NormalizedRect(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

class ProjectAsset {
  const ProjectAsset({
    required this.id,
    required this.name,
    required this.kind,
    required this.uri,
    this.contentHash,
    this.mimeType,
    this.missing = false,
    this.metadata = const {},
  });

  final AssetId id;
  final String name;
  final ProjectAssetKind kind;
  final String uri;
  final String? contentHash;
  final String? mimeType;
  final bool missing;
  final Map<String, Object?> metadata;

  factory ProjectAsset.fromJson(Map<String, Object?> json) {
    return ProjectAsset(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      kind: enumByName(ProjectAssetKind.values, jsonString(json, 'kind')),
      uri: jsonString(json, 'uri'),
      contentHash: jsonNullableString(json, 'contentHash'),
      mimeType: jsonNullableString(json, 'mimeType'),
      missing: jsonBool(json, 'missing'),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'contentHash': contentHash,
    'id': id,
    'kind': kind.name,
    'metadata': metadata,
    'mimeType': mimeType,
    'missing': missing,
    'name': name,
    'uri': uri,
  };

  ProjectAsset copyWith({
    AssetId? id,
    String? name,
    ProjectAssetKind? kind,
    String? uri,
    Object? contentHash = absentValue,
    Object? mimeType = absentValue,
    bool? missing,
    Map<String, Object?>? metadata,
  }) {
    return ProjectAsset(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      uri: uri ?? this.uri,
      contentHash: optionalValue(contentHash, this.contentHash),
      mimeType: optionalValue(mimeType, this.mimeType),
      missing: missing ?? this.missing,
      metadata: metadata ?? this.metadata,
    );
  }
}

class CharacterResource {
  const CharacterResource({
    required this.id,
    required this.name,
    required this.document,
    this.legacyGachaCode,
    this.thumbnailAssetId,
    this.metadata = const {},
  });

  final CharacterId id;
  final String name;
  final Map<String, Object?> document;
  final String? legacyGachaCode;
  final AssetId? thumbnailAssetId;
  final Map<String, Object?> metadata;

  factory CharacterResource.fromJson(Map<String, Object?> json) {
    return CharacterResource(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      document: jsonMap(json['document']),
      legacyGachaCode: jsonNullableString(json, 'legacyGachaCode'),
      thumbnailAssetId: jsonNullableString(json, 'thumbnailAssetId'),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'document': document,
    'id': id,
    'legacyGachaCode': legacyGachaCode,
    'metadata': metadata,
    'name': name,
    'thumbnailAssetId': thumbnailAssetId,
  };

  CharacterResource copyWith({
    CharacterId? id,
    String? name,
    Map<String, Object?>? document,
    Object? legacyGachaCode = absentValue,
    Object? thumbnailAssetId = absentValue,
    Map<String, Object?>? metadata,
  }) {
    return CharacterResource(
      id: id ?? this.id,
      name: name ?? this.name,
      document: document ?? this.document,
      legacyGachaCode: optionalValue(legacyGachaCode, this.legacyGachaCode),
      thumbnailAssetId: optionalValue(thumbnailAssetId, this.thumbnailAssetId),
      metadata: metadata ?? this.metadata,
    );
  }
}

class ExpressionPreset {
  const ExpressionPreset({
    required this.id,
    required this.name,
    this.characterId,
    this.semanticValues = const {},
    this.slotOverrides = const {},
    this.visibilityOverrides = const {},
    this.metadata = const {},
  });

  final ExpressionId id;
  final String name;
  final CharacterId? characterId;
  final Map<String, Object?> semanticValues;
  final Map<String, Map<String, Object?>> slotOverrides;
  final Map<String, bool> visibilityOverrides;
  final Map<String, Object?> metadata;

  factory ExpressionPreset.fromJson(Map<String, Object?> json) {
    return ExpressionPreset(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      characterId: jsonNullableString(json, 'characterId'),
      semanticValues: jsonMap(json['semanticValues']),
      slotOverrides: nestedJsonMap(json['slotOverrides']),
      visibilityOverrides: boolMap(json['visibilityOverrides']),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'characterId': characterId,
    'id': id,
    'metadata': metadata,
    'name': name,
    'semanticValues': semanticValues,
    'slotOverrides': slotOverrides,
    'visibilityOverrides': visibilityOverrides,
  };

  ExpressionPreset copyWith({
    ExpressionId? id,
    String? name,
    Object? characterId = absentValue,
    Map<String, Object?>? semanticValues,
    Map<String, Map<String, Object?>>? slotOverrides,
    Map<String, bool>? visibilityOverrides,
    Map<String, Object?>? metadata,
  }) {
    return ExpressionPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      characterId: optionalValue(characterId, this.characterId),
      semanticValues: semanticValues ?? this.semanticValues,
      slotOverrides: slotOverrides ?? this.slotOverrides,
      visibilityOverrides: visibilityOverrides ?? this.visibilityOverrides,
      metadata: metadata ?? this.metadata,
    );
  }
}

class PosePreset {
  const PosePreset({
    required this.id,
    required this.name,
    this.characterId,
    this.anchorTransforms = const {},
    this.slotTransforms = const {},
    this.metadata = const {},
  });

  final PoseId id;
  final String name;
  final CharacterId? characterId;
  final Map<String, AffineTransform> anchorTransforms;
  final Map<String, AffineTransform> slotTransforms;
  final Map<String, Object?> metadata;

  factory PosePreset.fromJson(Map<String, Object?> json) {
    return PosePreset(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      characterId: jsonNullableString(json, 'characterId'),
      anchorTransforms: transformMap(json['anchorTransforms']),
      slotTransforms: transformMap(json['slotTransforms']),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'anchorTransforms': mapValuesJson(anchorTransforms),
    'characterId': characterId,
    'id': id,
    'metadata': metadata,
    'name': name,
    'slotTransforms': mapValuesJson(slotTransforms),
  };

  PosePreset copyWith({
    PoseId? id,
    String? name,
    Object? characterId = absentValue,
    Map<String, AffineTransform>? anchorTransforms,
    Map<String, AffineTransform>? slotTransforms,
    Map<String, Object?>? metadata,
  }) {
    return PosePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      characterId: optionalValue(characterId, this.characterId),
      anchorTransforms: anchorTransforms ?? this.anchorTransforms,
      slotTransforms: slotTransforms ?? this.slotTransforms,
      metadata: metadata ?? this.metadata,
    );
  }
}

class LayoutPlacement {
  const LayoutPlacement({
    required this.id,
    required this.transform,
    required this.layer,
    this.characterId,
    this.safeArea,
    this.metadata = const {},
  });

  final String id;
  final CharacterId? characterId;
  final AffineTransform transform;
  final int layer;
  final NormalizedRect? safeArea;
  final Map<String, Object?> metadata;

  factory LayoutPlacement.fromJson(Map<String, Object?> json) {
    return LayoutPlacement(
      id: jsonString(json, 'id'),
      characterId: jsonNullableString(json, 'characterId'),
      transform: AffineTransform.fromJson(jsonMap(json['transform'])),
      layer: jsonInt(json, 'layer'),
      safeArea: json['safeArea'] == null
          ? null
          : NormalizedRect.fromJson(jsonMap(json['safeArea'])),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'characterId': characterId,
    'id': id,
    'layer': layer,
    'metadata': metadata,
    'safeArea': safeArea?.toJson(),
    'transform': transform.toJson(),
  };

  LayoutPlacement copyWith({
    String? id,
    Object? characterId = absentValue,
    AffineTransform? transform,
    int? layer,
    Object? safeArea = absentValue,
    Map<String, Object?>? metadata,
  }) {
    return LayoutPlacement(
      id: id ?? this.id,
      characterId: optionalValue(characterId, this.characterId),
      transform: transform ?? this.transform,
      layer: layer ?? this.layer,
      safeArea: optionalValue(safeArea, this.safeArea),
      metadata: metadata ?? this.metadata,
    );
  }
}

class LayoutTemplate {
  const LayoutTemplate({
    required this.id,
    required this.name,
    required this.canvas,
    this.backgroundAssetId,
    this.mediaRegion,
    this.placements = const [],
    this.textSafeRegions = const [],
    this.watermarkAssetId,
    this.metadata = const {},
  });

  final LayoutId id;
  final String name;
  final ProjectCanvas canvas;
  final AssetId? backgroundAssetId;
  final NormalizedRect? mediaRegion;
  final List<LayoutPlacement> placements;
  final List<NormalizedRect> textSafeRegions;
  final AssetId? watermarkAssetId;
  final Map<String, Object?> metadata;

  factory LayoutTemplate.fromJson(Map<String, Object?> json) {
    return LayoutTemplate(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      canvas: ProjectCanvas.fromJson(jsonMap(json['canvas'])),
      backgroundAssetId: jsonNullableString(json, 'backgroundAssetId'),
      mediaRegion: json['mediaRegion'] == null
          ? null
          : NormalizedRect.fromJson(jsonMap(json['mediaRegion'])),
      placements: jsonList(json['placements'])
          .map((value) => LayoutPlacement.fromJson(jsonMap(value)))
          .toList(growable: false),
      textSafeRegions: jsonList(json['textSafeRegions'])
          .map((value) => NormalizedRect.fromJson(jsonMap(value)))
          .toList(growable: false),
      watermarkAssetId: jsonNullableString(json, 'watermarkAssetId'),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'backgroundAssetId': backgroundAssetId,
    'canvas': canvas.toJson(),
    'id': id,
    'mediaRegion': mediaRegion?.toJson(),
    'metadata': metadata,
    'name': name,
    'placements': placements.map((value) => value.toJson()).toList(),
    'textSafeRegions': textSafeRegions.map((value) => value.toJson()).toList(),
    'watermarkAssetId': watermarkAssetId,
  };

  LayoutTemplate copyWith({
    LayoutId? id,
    String? name,
    ProjectCanvas? canvas,
    Object? backgroundAssetId = absentValue,
    Object? mediaRegion = absentValue,
    List<LayoutPlacement>? placements,
    List<NormalizedRect>? textSafeRegions,
    Object? watermarkAssetId = absentValue,
    Map<String, Object?>? metadata,
  }) {
    return LayoutTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      canvas: canvas ?? this.canvas,
      backgroundAssetId: optionalValue(
        backgroundAssetId,
        this.backgroundAssetId,
      ),
      mediaRegion: optionalValue(mediaRegion, this.mediaRegion),
      placements: placements ?? this.placements,
      textSafeRegions: textSafeRegions ?? this.textSafeRegions,
      watermarkAssetId: optionalValue(watermarkAssetId, this.watermarkAssetId),
      metadata: metadata ?? this.metadata,
    );
  }
}

class ReactionCharacterInstance {
  const ReactionCharacterInstance({
    required this.id,
    required this.characterId,
    this.expressionId,
    this.poseId,
    this.layoutPlacementId,
    this.visible = true,
    this.transform,
    this.layer = 0,
    this.slotOverrides = const {},
    this.metadata = const {},
  });

  final String id;
  final CharacterId characterId;
  final ExpressionId? expressionId;
  final PoseId? poseId;
  final String? layoutPlacementId;
  final bool visible;
  final AffineTransform? transform;
  final int layer;
  final Map<String, Map<String, Object?>> slotOverrides;
  final Map<String, Object?> metadata;

  factory ReactionCharacterInstance.fromJson(Map<String, Object?> json) {
    return ReactionCharacterInstance(
      id: jsonString(json, 'id'),
      characterId: jsonString(json, 'characterId'),
      expressionId: jsonNullableString(json, 'expressionId'),
      poseId: jsonNullableString(json, 'poseId'),
      layoutPlacementId: jsonNullableString(json, 'layoutPlacementId'),
      visible: jsonBool(json, 'visible', fallback: true),
      transform: json['transform'] == null
          ? null
          : AffineTransform.fromJson(jsonMap(json['transform'])),
      layer: jsonInt(json, 'layer'),
      slotOverrides: nestedJsonMap(json['slotOverrides']),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'characterId': characterId,
    'expressionId': expressionId,
    'id': id,
    'layer': layer,
    'layoutPlacementId': layoutPlacementId,
    'metadata': metadata,
    'poseId': poseId,
    'slotOverrides': slotOverrides,
    'transform': transform?.toJson(),
    'visible': visible,
  };

  ReactionCharacterInstance copyWith({
    String? id,
    CharacterId? characterId,
    Object? expressionId = absentValue,
    Object? poseId = absentValue,
    Object? layoutPlacementId = absentValue,
    bool? visible,
    Object? transform = absentValue,
    int? layer,
    Map<String, Map<String, Object?>>? slotOverrides,
    Map<String, Object?>? metadata,
  }) {
    return ReactionCharacterInstance(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      expressionId: optionalValue(expressionId, this.expressionId),
      poseId: optionalValue(poseId, this.poseId),
      layoutPlacementId: optionalValue(
        layoutPlacementId,
        this.layoutPlacementId,
      ),
      visible: visible ?? this.visible,
      transform: optionalValue(transform, this.transform),
      layer: layer ?? this.layer,
      slotOverrides: slotOverrides ?? this.slotOverrides,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ReactionMediaConfiguration {
  const ReactionMediaConfiguration({
    this.assetId,
    this.visible = true,
    this.transform = const AffineTransform(),
    this.crop,
    this.opacity = 1,
  });

  final AssetId? assetId;
  final bool visible;
  final AffineTransform transform;
  final NormalizedRect? crop;
  final double opacity;

  factory ReactionMediaConfiguration.fromJson(Map<String, Object?> json) {
    return ReactionMediaConfiguration(
      assetId: jsonNullableString(json, 'assetId'),
      visible: jsonBool(json, 'visible', fallback: true),
      transform: json['transform'] == null
          ? const AffineTransform()
          : AffineTransform.fromJson(jsonMap(json['transform'])),
      crop: json['crop'] == null
          ? null
          : NormalizedRect.fromJson(jsonMap(json['crop'])),
      opacity: jsonDouble(json, 'opacity', fallback: 1),
    );
  }

  Map<String, Object?> toJson() => {
    'assetId': assetId,
    'crop': crop?.toJson(),
    'opacity': opacity,
    'transform': transform.toJson(),
    'visible': visible,
  };

  ReactionMediaConfiguration copyWith({
    Object? assetId = absentValue,
    bool? visible,
    AffineTransform? transform,
    Object? crop = absentValue,
    double? opacity,
  }) {
    return ReactionMediaConfiguration(
      assetId: optionalValue(assetId, this.assetId),
      visible: visible ?? this.visible,
      transform: transform ?? this.transform,
      crop: optionalValue(crop, this.crop),
      opacity: opacity ?? this.opacity,
    );
  }
}

class ReactionState {
  const ReactionState({
    required this.id,
    required this.name,
    required this.layoutId,
    this.characters = const [],
    this.backgroundAssetId,
    this.media = const ReactionMediaConfiguration(),
    this.dialogueMetadata = const {},
    this.metadata = const {},
  });

  final ReactionStateId id;
  final String name;
  final LayoutId layoutId;
  final List<ReactionCharacterInstance> characters;
  final AssetId? backgroundAssetId;
  final ReactionMediaConfiguration media;
  final Map<String, Object?> dialogueMetadata;
  final Map<String, Object?> metadata;

  factory ReactionState.fromJson(Map<String, Object?> json) {
    return ReactionState(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      layoutId: jsonString(json, 'layoutId'),
      characters: jsonList(json['characters'])
          .map((value) => ReactionCharacterInstance.fromJson(jsonMap(value)))
          .toList(growable: false),
      backgroundAssetId: jsonNullableString(json, 'backgroundAssetId'),
      media: json['media'] == null
          ? const ReactionMediaConfiguration()
          : ReactionMediaConfiguration.fromJson(jsonMap(json['media'])),
      dialogueMetadata: jsonMap(json['dialogueMetadata']),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'backgroundAssetId': backgroundAssetId,
    'characters': characters.map((value) => value.toJson()).toList(),
    'dialogueMetadata': dialogueMetadata,
    'id': id,
    'layoutId': layoutId,
    'media': media.toJson(),
    'metadata': metadata,
    'name': name,
  };

  ReactionState copyWith({
    ReactionStateId? id,
    String? name,
    LayoutId? layoutId,
    List<ReactionCharacterInstance>? characters,
    Object? backgroundAssetId = absentValue,
    ReactionMediaConfiguration? media,
    Map<String, Object?>? dialogueMetadata,
    Map<String, Object?>? metadata,
  }) {
    return ReactionState(
      id: id ?? this.id,
      name: name ?? this.name,
      layoutId: layoutId ?? this.layoutId,
      characters: characters ?? this.characters,
      backgroundAssetId: optionalValue(
        backgroundAssetId,
        this.backgroundAssetId,
      ),
      media: media ?? this.media,
      dialogueMetadata: dialogueMetadata ?? this.dialogueMetadata,
      metadata: metadata ?? this.metadata,
    );
  }
}

class TextShadowStyle {
  const TextShadowStyle({
    this.color,
    this.offsetX,
    this.offsetY,
    this.softness,
    this.opacity,
  });

  final String? color;
  final double? offsetX;
  final double? offsetY;
  final double? softness;
  final double? opacity;

  factory TextShadowStyle.fromJson(Map<String, Object?> json) {
    return TextShadowStyle(
      color: jsonNullableString(json, 'color'),
      offsetX: jsonNullableDouble(json, 'offsetX'),
      offsetY: jsonNullableDouble(json, 'offsetY'),
      softness: jsonNullableDouble(json, 'softness'),
      opacity: jsonNullableDouble(json, 'opacity'),
    );
  }

  Map<String, Object?> toJson() => {
    'color': color,
    'offsetX': offsetX,
    'offsetY': offsetY,
    'opacity': opacity,
    'softness': softness,
  };

  TextShadowStyle copyWith({
    Object? color = absentValue,
    Object? offsetX = absentValue,
    Object? offsetY = absentValue,
    Object? softness = absentValue,
    Object? opacity = absentValue,
  }) {
    return TextShadowStyle(
      color: optionalValue(color, this.color),
      offsetX: optionalValue(offsetX, this.offsetX),
      offsetY: optionalValue(offsetY, this.offsetY),
      softness: optionalValue(softness, this.softness),
      opacity: optionalValue(opacity, this.opacity),
    );
  }
}

class TextStyleSpec {
  const TextStyleSpec({
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.italic,
    this.fillColor,
    this.outlineColor,
    this.outlineWidth,
    this.shadow,
    this.borderColor,
    this.borderWidth,
    this.glowColor,
    this.glowSize,
    this.tracking,
    this.lineSpacing,
    this.alignment,
    this.capitalization,
  });

  final String? fontFamily;
  final double? fontSize;
  final int? fontWeight;
  final bool? italic;
  final String? fillColor;
  final String? outlineColor;
  final double? outlineWidth;
  final TextShadowStyle? shadow;
  final String? borderColor;
  final double? borderWidth;
  final String? glowColor;
  final double? glowSize;
  final double? tracking;
  final double? lineSpacing;
  final TextAlignment? alignment;
  final TextCapitalization? capitalization;

  factory TextStyleSpec.fromJson(Map<String, Object?> json) {
    return TextStyleSpec(
      fontFamily: jsonNullableString(json, 'fontFamily'),
      fontSize: jsonNullableDouble(json, 'fontSize'),
      fontWeight: jsonNullableInt(json, 'fontWeight'),
      italic: jsonNullableBool(json, 'italic'),
      fillColor: jsonNullableString(json, 'fillColor'),
      outlineColor: jsonNullableString(json, 'outlineColor'),
      outlineWidth: jsonNullableDouble(json, 'outlineWidth'),
      shadow: json['shadow'] == null
          ? null
          : TextShadowStyle.fromJson(jsonMap(json['shadow'])),
      borderColor: jsonNullableString(json, 'borderColor'),
      borderWidth: jsonNullableDouble(json, 'borderWidth'),
      glowColor: jsonNullableString(json, 'glowColor'),
      glowSize: jsonNullableDouble(json, 'glowSize'),
      tracking: jsonNullableDouble(json, 'tracking'),
      lineSpacing: jsonNullableDouble(json, 'lineSpacing'),
      alignment: json['alignment'] == null
          ? null
          : enumByName(TextAlignment.values, jsonString(json, 'alignment')),
      capitalization: json['capitalization'] == null
          ? null
          : enumByName(
              TextCapitalization.values,
              jsonString(json, 'capitalization'),
            ),
    );
  }

  Map<String, Object?> toJson() => {
    'alignment': alignment?.name,
    'borderColor': borderColor,
    'borderWidth': borderWidth,
    'capitalization': capitalization?.name,
    'fillColor': fillColor,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    'glowColor': glowColor,
    'glowSize': glowSize,
    'italic': italic,
    'lineSpacing': lineSpacing,
    'outlineColor': outlineColor,
    'outlineWidth': outlineWidth,
    'shadow': shadow?.toJson(),
    'tracking': tracking,
  };

  TextStyleSpec copyWith({
    Object? fontFamily = absentValue,
    Object? fontSize = absentValue,
    Object? fontWeight = absentValue,
    Object? italic = absentValue,
    Object? fillColor = absentValue,
    Object? outlineColor = absentValue,
    Object? outlineWidth = absentValue,
    Object? shadow = absentValue,
    Object? borderColor = absentValue,
    Object? borderWidth = absentValue,
    Object? glowColor = absentValue,
    Object? glowSize = absentValue,
    Object? tracking = absentValue,
    Object? lineSpacing = absentValue,
    Object? alignment = absentValue,
    Object? capitalization = absentValue,
  }) {
    return TextStyleSpec(
      fontFamily: optionalValue(fontFamily, this.fontFamily),
      fontSize: optionalValue(fontSize, this.fontSize),
      fontWeight: optionalValue(fontWeight, this.fontWeight),
      italic: optionalValue(italic, this.italic),
      fillColor: optionalValue(fillColor, this.fillColor),
      outlineColor: optionalValue(outlineColor, this.outlineColor),
      outlineWidth: optionalValue(outlineWidth, this.outlineWidth),
      shadow: optionalValue(shadow, this.shadow),
      borderColor: optionalValue(borderColor, this.borderColor),
      borderWidth: optionalValue(borderWidth, this.borderWidth),
      glowColor: optionalValue(glowColor, this.glowColor),
      glowSize: optionalValue(glowSize, this.glowSize),
      tracking: optionalValue(tracking, this.tracking),
      lineSpacing: optionalValue(lineSpacing, this.lineSpacing),
      alignment: optionalValue(alignment, this.alignment),
      capitalization: optionalValue(capitalization, this.capitalization),
    );
  }
}

class TextPreset {
  const TextPreset({
    required this.id,
    required this.name,
    required this.category,
    this.parentPresetId,
    this.style = const TextStyleSpec(),
    this.metadata = const {},
  });

  final TextPresetId id;
  final String name;
  final String category;
  final TextPresetId? parentPresetId;
  final TextStyleSpec style;
  final Map<String, Object?> metadata;

  factory TextPreset.fromJson(Map<String, Object?> json) {
    return TextPreset(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      category: jsonString(json, 'category'),
      parentPresetId: jsonNullableString(json, 'parentPresetId'),
      style: TextStyleSpec.fromJson(jsonMap(json['style'])),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'category': category,
    'id': id,
    'metadata': metadata,
    'name': name,
    'parentPresetId': parentPresetId,
    'style': style.toJson(),
  };

  TextPreset copyWith({
    TextPresetId? id,
    String? name,
    String? category,
    Object? parentPresetId = absentValue,
    TextStyleSpec? style,
    Map<String, Object?>? metadata,
  }) {
    return TextPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      parentPresetId: optionalValue(parentPresetId, this.parentPresetId),
      style: style ?? this.style,
      metadata: metadata ?? this.metadata,
    );
  }
}

class SpeakerRule {
  const SpeakerRule({
    required this.id,
    required this.speakerId,
    required this.displayName,
    this.aliases = const [],
    this.textPresetId,
    this.styleOverride = const TextStyleSpec(),
    this.isDefault = false,
    this.metadata = const {},
  });

  final SpeakerRuleId id;
  final String speakerId;
  final String displayName;
  final List<String> aliases;
  final TextPresetId? textPresetId;
  final TextStyleSpec styleOverride;
  final bool isDefault;
  final Map<String, Object?> metadata;

  factory SpeakerRule.fromJson(Map<String, Object?> json) {
    return SpeakerRule(
      id: jsonString(json, 'id'),
      speakerId: jsonString(json, 'speakerId'),
      displayName: jsonString(json, 'displayName'),
      aliases: stringList(json['aliases']),
      textPresetId: jsonNullableString(json, 'textPresetId'),
      styleOverride: TextStyleSpec.fromJson(jsonMap(json['styleOverride'])),
      isDefault: jsonBool(json, 'isDefault'),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'aliases': aliases,
    'displayName': displayName,
    'id': id,
    'isDefault': isDefault,
    'metadata': metadata,
    'speakerId': speakerId,
    'styleOverride': styleOverride.toJson(),
    'textPresetId': textPresetId,
  };

  SpeakerRule copyWith({
    SpeakerRuleId? id,
    String? speakerId,
    String? displayName,
    List<String>? aliases,
    Object? textPresetId = absentValue,
    TextStyleSpec? styleOverride,
    bool? isDefault,
    Map<String, Object?>? metadata,
  }) {
    return SpeakerRule(
      id: id ?? this.id,
      speakerId: speakerId ?? this.speakerId,
      displayName: displayName ?? this.displayName,
      aliases: aliases ?? this.aliases,
      textPresetId: optionalValue(textPresetId, this.textPresetId),
      styleOverride: styleOverride ?? this.styleOverride,
      isDefault: isDefault ?? this.isDefault,
      metadata: metadata ?? this.metadata,
    );
  }
}

class DialogueLine {
  const DialogueLine({
    required this.id,
    required this.text,
    this.speakerRuleId,
    this.sourcePrefix,
    this.styleOverride = const TextStyleSpec(),
    this.metadata = const {},
  });

  final String id;
  final String text;
  final SpeakerRuleId? speakerRuleId;
  final String? sourcePrefix;
  final TextStyleSpec styleOverride;
  final Map<String, Object?> metadata;

  factory DialogueLine.fromJson(Map<String, Object?> json) {
    return DialogueLine(
      id: jsonString(json, 'id'),
      text: jsonString(json, 'text'),
      speakerRuleId: jsonNullableString(json, 'speakerRuleId'),
      sourcePrefix: jsonNullableString(json, 'sourcePrefix'),
      styleOverride: TextStyleSpec.fromJson(jsonMap(json['styleOverride'])),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'metadata': metadata,
    'sourcePrefix': sourcePrefix,
    'speakerRuleId': speakerRuleId,
    'styleOverride': styleOverride.toJson(),
    'text': text,
  };

  DialogueLine copyWith({
    String? id,
    String? text,
    Object? speakerRuleId = absentValue,
    Object? sourcePrefix = absentValue,
    TextStyleSpec? styleOverride,
    Map<String, Object?>? metadata,
  }) {
    return DialogueLine(
      id: id ?? this.id,
      text: text ?? this.text,
      speakerRuleId: optionalValue(speakerRuleId, this.speakerRuleId),
      sourcePrefix: optionalValue(sourcePrefix, this.sourcePrefix),
      styleOverride: styleOverride ?? this.styleOverride,
      metadata: metadata ?? this.metadata,
    );
  }
}

class VisualClipControls {
  const VisualClipControls({
    this.transform = const AffineTransform(),
    this.crop,
    this.opacity = 1,
    this.fadeInFrames = 0,
    this.fadeOutFrames = 0,
    this.transitionIn,
    this.transitionOut,
    this.effects = const {},
  });

  final AffineTransform transform;
  final NormalizedRect? crop;
  final double opacity;
  final int fadeInFrames;
  final int fadeOutFrames;
  final String? transitionIn;
  final String? transitionOut;
  final Map<String, Object?> effects;

  factory VisualClipControls.fromJson(Map<String, Object?> json) {
    return VisualClipControls(
      transform: json['transform'] == null
          ? const AffineTransform()
          : AffineTransform.fromJson(jsonMap(json['transform'])),
      crop: json['crop'] == null
          ? null
          : NormalizedRect.fromJson(jsonMap(json['crop'])),
      opacity: jsonDouble(json, 'opacity', fallback: 1),
      fadeInFrames: jsonInt(json, 'fadeInFrames'),
      fadeOutFrames: jsonInt(json, 'fadeOutFrames'),
      transitionIn: jsonNullableString(json, 'transitionIn'),
      transitionOut: jsonNullableString(json, 'transitionOut'),
      effects: jsonMap(json['effects']),
    );
  }

  Map<String, Object?> toJson() => {
    'crop': crop?.toJson(),
    'effects': effects,
    'fadeInFrames': fadeInFrames,
    'fadeOutFrames': fadeOutFrames,
    'opacity': opacity,
    'transform': transform.toJson(),
    'transitionIn': transitionIn,
    'transitionOut': transitionOut,
  };

  VisualClipControls copyWith({
    AffineTransform? transform,
    Object? crop = absentValue,
    double? opacity,
    int? fadeInFrames,
    int? fadeOutFrames,
    Object? transitionIn = absentValue,
    Object? transitionOut = absentValue,
    Map<String, Object?>? effects,
  }) {
    return VisualClipControls(
      transform: transform ?? this.transform,
      crop: optionalValue(crop, this.crop),
      opacity: opacity ?? this.opacity,
      fadeInFrames: fadeInFrames ?? this.fadeInFrames,
      fadeOutFrames: fadeOutFrames ?? this.fadeOutFrames,
      transitionIn: optionalValue(transitionIn, this.transitionIn),
      transitionOut: optionalValue(transitionOut, this.transitionOut),
      effects: effects ?? this.effects,
    );
  }
}

class AudioClipControls {
  const AudioClipControls({
    this.gainDb = 0,
    this.pan = 0,
    this.pitchSemitones = 0,
    this.pitchCents = 0,
    this.fadeInFrames = 0,
    this.fadeOutFrames = 0,
    this.muted = false,
    this.effects = const {},
  });

  final double gainDb;
  final double pan;
  final double pitchSemitones;
  final double pitchCents;
  final int fadeInFrames;
  final int fadeOutFrames;
  final bool muted;
  final Map<String, Object?> effects;

  factory AudioClipControls.fromJson(Map<String, Object?> json) {
    return AudioClipControls(
      gainDb: jsonDouble(json, 'gainDb'),
      pan: jsonDouble(json, 'pan'),
      pitchSemitones: jsonDouble(json, 'pitchSemitones'),
      pitchCents: jsonDouble(json, 'pitchCents'),
      fadeInFrames: jsonInt(json, 'fadeInFrames'),
      fadeOutFrames: jsonInt(json, 'fadeOutFrames'),
      muted: jsonBool(json, 'muted'),
      effects: jsonMap(json['effects']),
    );
  }

  Map<String, Object?> toJson() => {
    'effects': effects,
    'fadeInFrames': fadeInFrames,
    'fadeOutFrames': fadeOutFrames,
    'gainDb': gainDb,
    'muted': muted,
    'pan': pan,
    'pitchCents': pitchCents,
    'pitchSemitones': pitchSemitones,
  };

  AudioClipControls copyWith({
    double? gainDb,
    double? pan,
    double? pitchSemitones,
    double? pitchCents,
    int? fadeInFrames,
    int? fadeOutFrames,
    bool? muted,
    Map<String, Object?>? effects,
  }) {
    return AudioClipControls(
      gainDb: gainDb ?? this.gainDb,
      pan: pan ?? this.pan,
      pitchSemitones: pitchSemitones ?? this.pitchSemitones,
      pitchCents: pitchCents ?? this.pitchCents,
      fadeInFrames: fadeInFrames ?? this.fadeInFrames,
      fadeOutFrames: fadeOutFrames ?? this.fadeOutFrames,
      muted: muted ?? this.muted,
      effects: effects ?? this.effects,
    );
  }
}

sealed class TimelineClip {
  const TimelineClip({
    required this.id,
    required this.range,
    this.enabled = true,
    this.metadata = const {},
  });

  final ClipId id;
  final FrameRange range;
  final bool enabled;
  final Map<String, Object?> metadata;

  TimelineTrackType get trackType;

  Map<String, Object?> toJson();

  static TimelineClip fromJson(Map<String, Object?> json) {
    final type = enumByName(TimelineTrackType.values, jsonString(json, 'type'));
    return switch (type) {
      TimelineTrackType.reactionState => ReactionTimelineClip.fromJson(json),
      TimelineTrackType.video => VideoTimelineClip.fromJson(json),
      TimelineTrackType.imageOverlay => ImageTimelineClip.fromJson(json),
      TimelineTrackType.richText => RichTextTimelineClip.fromJson(json),
      TimelineTrackType.audio => AudioTimelineClip.fromJson(json),
      TimelineTrackType.watermark => WatermarkTimelineClip.fromJson(json),
    };
  }
}

class ReactionTimelineClip extends TimelineClip {
  const ReactionTimelineClip({
    required super.id,
    required super.range,
    required this.reactionStateId,
    this.showDialogue = true,
    this.showMedia = true,
    this.visual = const VisualClipControls(),
    super.enabled,
    super.metadata,
  });

  final ReactionStateId reactionStateId;
  final bool showDialogue;
  final bool showMedia;
  final VisualClipControls visual;

  @override
  TimelineTrackType get trackType => TimelineTrackType.reactionState;

  factory ReactionTimelineClip.fromJson(Map<String, Object?> json) {
    return ReactionTimelineClip(
      id: jsonString(json, 'id'),
      range: FrameRange.fromJson(jsonMap(json['range'])),
      reactionStateId: jsonString(json, 'reactionStateId'),
      showDialogue: jsonBool(json, 'showDialogue', fallback: true),
      showMedia: jsonBool(json, 'showMedia', fallback: true),
      visual: VisualClipControls.fromJson(jsonMap(json['visual'])),
      enabled: jsonBool(json, 'enabled', fallback: true),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'id': id,
    'metadata': metadata,
    'range': range.toJson(),
    'reactionStateId': reactionStateId,
    'showDialogue': showDialogue,
    'showMedia': showMedia,
    'type': trackType.name,
    'visual': visual.toJson(),
  };

  ReactionTimelineClip copyWith({
    ClipId? id,
    FrameRange? range,
    ReactionStateId? reactionStateId,
    bool? showDialogue,
    bool? showMedia,
    VisualClipControls? visual,
    bool? enabled,
    Map<String, Object?>? metadata,
  }) {
    return ReactionTimelineClip(
      id: id ?? this.id,
      range: range ?? this.range,
      reactionStateId: reactionStateId ?? this.reactionStateId,
      showDialogue: showDialogue ?? this.showDialogue,
      showMedia: showMedia ?? this.showMedia,
      visual: visual ?? this.visual,
      enabled: enabled ?? this.enabled,
      metadata: metadata ?? this.metadata,
    );
  }
}

class VideoTimelineClip extends TimelineClip {
  const VideoTimelineClip({
    required super.id,
    required super.range,
    required this.assetId,
    this.sourceInFrame = 0,
    this.visual = const VisualClipControls(),
    this.audio = const AudioClipControls(),
    this.linkedClipId,
    super.enabled,
    super.metadata,
  });

  final AssetId assetId;
  final int sourceInFrame;
  final VisualClipControls visual;
  final AudioClipControls audio;
  final ClipId? linkedClipId;

  @override
  TimelineTrackType get trackType => TimelineTrackType.video;

  factory VideoTimelineClip.fromJson(Map<String, Object?> json) {
    return VideoTimelineClip(
      id: jsonString(json, 'id'),
      range: FrameRange.fromJson(jsonMap(json['range'])),
      assetId: jsonString(json, 'assetId'),
      sourceInFrame: jsonInt(json, 'sourceInFrame'),
      visual: VisualClipControls.fromJson(jsonMap(json['visual'])),
      audio: AudioClipControls.fromJson(jsonMap(json['audio'])),
      linkedClipId: jsonNullableString(json, 'linkedClipId'),
      enabled: jsonBool(json, 'enabled', fallback: true),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'assetId': assetId,
    'audio': audio.toJson(),
    'enabled': enabled,
    'id': id,
    'linkedClipId': linkedClipId,
    'metadata': metadata,
    'range': range.toJson(),
    'sourceInFrame': sourceInFrame,
    'type': trackType.name,
    'visual': visual.toJson(),
  };

  VideoTimelineClip copyWith({
    ClipId? id,
    FrameRange? range,
    AssetId? assetId,
    int? sourceInFrame,
    VisualClipControls? visual,
    AudioClipControls? audio,
    Object? linkedClipId = absentValue,
    bool? enabled,
    Map<String, Object?>? metadata,
  }) {
    return VideoTimelineClip(
      id: id ?? this.id,
      range: range ?? this.range,
      assetId: assetId ?? this.assetId,
      sourceInFrame: sourceInFrame ?? this.sourceInFrame,
      visual: visual ?? this.visual,
      audio: audio ?? this.audio,
      linkedClipId: optionalValue(linkedClipId, this.linkedClipId),
      enabled: enabled ?? this.enabled,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ImageTimelineClip extends TimelineClip {
  const ImageTimelineClip({
    required super.id,
    required super.range,
    required this.assetId,
    this.visual = const VisualClipControls(),
    super.enabled,
    super.metadata,
  });

  final AssetId assetId;
  final VisualClipControls visual;

  @override
  TimelineTrackType get trackType => TimelineTrackType.imageOverlay;

  factory ImageTimelineClip.fromJson(Map<String, Object?> json) {
    return ImageTimelineClip(
      id: jsonString(json, 'id'),
      range: FrameRange.fromJson(jsonMap(json['range'])),
      assetId: jsonString(json, 'assetId'),
      visual: VisualClipControls.fromJson(jsonMap(json['visual'])),
      enabled: jsonBool(json, 'enabled', fallback: true),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'assetId': assetId,
    'enabled': enabled,
    'id': id,
    'metadata': metadata,
    'range': range.toJson(),
    'type': trackType.name,
    'visual': visual.toJson(),
  };

  ImageTimelineClip copyWith({
    ClipId? id,
    FrameRange? range,
    AssetId? assetId,
    VisualClipControls? visual,
    bool? enabled,
    Map<String, Object?>? metadata,
  }) {
    return ImageTimelineClip(
      id: id ?? this.id,
      range: range ?? this.range,
      assetId: assetId ?? this.assetId,
      visual: visual ?? this.visual,
      enabled: enabled ?? this.enabled,
      metadata: metadata ?? this.metadata,
    );
  }
}

class RichTextTimelineClip extends TimelineClip {
  const RichTextTimelineClip({
    required super.id,
    required super.range,
    required this.lines,
    this.textPresetId,
    this.styleOverride = const TextStyleSpec(),
    this.visual = const VisualClipControls(),
    super.enabled,
    super.metadata,
  });

  final List<DialogueLine> lines;
  final TextPresetId? textPresetId;
  final TextStyleSpec styleOverride;
  final VisualClipControls visual;

  @override
  TimelineTrackType get trackType => TimelineTrackType.richText;

  factory RichTextTimelineClip.fromJson(Map<String, Object?> json) {
    return RichTextTimelineClip(
      id: jsonString(json, 'id'),
      range: FrameRange.fromJson(jsonMap(json['range'])),
      lines: jsonList(json['lines'])
          .map((value) => DialogueLine.fromJson(jsonMap(value)))
          .toList(growable: false),
      textPresetId: jsonNullableString(json, 'textPresetId'),
      styleOverride: TextStyleSpec.fromJson(jsonMap(json['styleOverride'])),
      visual: VisualClipControls.fromJson(jsonMap(json['visual'])),
      enabled: jsonBool(json, 'enabled', fallback: true),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'id': id,
    'lines': lines.map((value) => value.toJson()).toList(),
    'metadata': metadata,
    'range': range.toJson(),
    'styleOverride': styleOverride.toJson(),
    'textPresetId': textPresetId,
    'type': trackType.name,
    'visual': visual.toJson(),
  };

  RichTextTimelineClip copyWith({
    ClipId? id,
    FrameRange? range,
    List<DialogueLine>? lines,
    Object? textPresetId = absentValue,
    TextStyleSpec? styleOverride,
    VisualClipControls? visual,
    bool? enabled,
    Map<String, Object?>? metadata,
  }) {
    return RichTextTimelineClip(
      id: id ?? this.id,
      range: range ?? this.range,
      lines: lines ?? this.lines,
      textPresetId: optionalValue(textPresetId, this.textPresetId),
      styleOverride: styleOverride ?? this.styleOverride,
      visual: visual ?? this.visual,
      enabled: enabled ?? this.enabled,
      metadata: metadata ?? this.metadata,
    );
  }
}

class AudioTimelineClip extends TimelineClip {
  const AudioTimelineClip({
    required super.id,
    required super.range,
    required this.assetId,
    this.sourceInFrame = 0,
    this.audio = const AudioClipControls(),
    this.linkedClipId,
    super.enabled,
    super.metadata,
  });

  final AssetId assetId;
  final int sourceInFrame;
  final AudioClipControls audio;
  final ClipId? linkedClipId;

  @override
  TimelineTrackType get trackType => TimelineTrackType.audio;

  factory AudioTimelineClip.fromJson(Map<String, Object?> json) {
    return AudioTimelineClip(
      id: jsonString(json, 'id'),
      range: FrameRange.fromJson(jsonMap(json['range'])),
      assetId: jsonString(json, 'assetId'),
      sourceInFrame: jsonInt(json, 'sourceInFrame'),
      audio: AudioClipControls.fromJson(jsonMap(json['audio'])),
      linkedClipId: jsonNullableString(json, 'linkedClipId'),
      enabled: jsonBool(json, 'enabled', fallback: true),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'assetId': assetId,
    'audio': audio.toJson(),
    'enabled': enabled,
    'id': id,
    'linkedClipId': linkedClipId,
    'metadata': metadata,
    'range': range.toJson(),
    'sourceInFrame': sourceInFrame,
    'type': trackType.name,
  };

  AudioTimelineClip copyWith({
    ClipId? id,
    FrameRange? range,
    AssetId? assetId,
    int? sourceInFrame,
    AudioClipControls? audio,
    Object? linkedClipId = absentValue,
    bool? enabled,
    Map<String, Object?>? metadata,
  }) {
    return AudioTimelineClip(
      id: id ?? this.id,
      range: range ?? this.range,
      assetId: assetId ?? this.assetId,
      sourceInFrame: sourceInFrame ?? this.sourceInFrame,
      audio: audio ?? this.audio,
      linkedClipId: optionalValue(linkedClipId, this.linkedClipId),
      enabled: enabled ?? this.enabled,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WatermarkTimelineClip extends TimelineClip {
  const WatermarkTimelineClip({
    required super.id,
    required super.range,
    required this.assetId,
    this.visual = const VisualClipControls(),
    super.enabled,
    super.metadata,
  });

  final AssetId assetId;
  final VisualClipControls visual;

  @override
  TimelineTrackType get trackType => TimelineTrackType.watermark;

  factory WatermarkTimelineClip.fromJson(Map<String, Object?> json) {
    return WatermarkTimelineClip(
      id: jsonString(json, 'id'),
      range: FrameRange.fromJson(jsonMap(json['range'])),
      assetId: jsonString(json, 'assetId'),
      visual: VisualClipControls.fromJson(jsonMap(json['visual'])),
      enabled: jsonBool(json, 'enabled', fallback: true),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'assetId': assetId,
    'enabled': enabled,
    'id': id,
    'metadata': metadata,
    'range': range.toJson(),
    'type': trackType.name,
    'visual': visual.toJson(),
  };

  WatermarkTimelineClip copyWith({
    ClipId? id,
    FrameRange? range,
    AssetId? assetId,
    VisualClipControls? visual,
    bool? enabled,
    Map<String, Object?>? metadata,
  }) {
    return WatermarkTimelineClip(
      id: id ?? this.id,
      range: range ?? this.range,
      assetId: assetId ?? this.assetId,
      visual: visual ?? this.visual,
      enabled: enabled ?? this.enabled,
      metadata: metadata ?? this.metadata,
    );
  }
}

class TimelineTrack {
  const TimelineTrack({
    required this.id,
    required this.name,
    required this.type,
    required this.order,
    this.visible = true,
    this.locked = false,
    this.enabled = true,
    this.muted = false,
    this.solo = false,
    this.clipOrder = const [],
    this.clips = const {},
    this.metadata = const {},
  });

  final TrackId id;
  final String name;
  final TimelineTrackType type;
  final int order;
  final bool visible;
  final bool locked;
  final bool enabled;
  final bool muted;
  final bool solo;
  final List<ClipId> clipOrder;
  final Map<ClipId, TimelineClip> clips;
  final Map<String, Object?> metadata;

  factory TimelineTrack.fromJson(Map<String, Object?> json) {
    final clips = <ClipId, TimelineClip>{};
    for (final entry in jsonList(json['clips'])) {
      final clip = TimelineClip.fromJson(jsonMap(entry));
      clips[clip.id] = clip;
    }
    return TimelineTrack(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      type: enumByName(TimelineTrackType.values, jsonString(json, 'type')),
      order: jsonInt(json, 'order'),
      visible: jsonBool(json, 'visible', fallback: true),
      locked: jsonBool(json, 'locked'),
      enabled: jsonBool(json, 'enabled', fallback: true),
      muted: jsonBool(json, 'muted'),
      solo: jsonBool(json, 'solo'),
      clipOrder: stringList(json['clipOrder']),
      clips: clips,
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'clipOrder': clipOrder,
    'clips': sortedValues(clips).map((value) => value.toJson()).toList(),
    'enabled': enabled,
    'id': id,
    'locked': locked,
    'metadata': metadata,
    'muted': muted,
    'name': name,
    'order': order,
    'solo': solo,
    'type': type.name,
    'visible': visible,
  };

  TimelineTrack copyWith({
    TrackId? id,
    String? name,
    TimelineTrackType? type,
    int? order,
    bool? visible,
    bool? locked,
    bool? enabled,
    bool? muted,
    bool? solo,
    List<ClipId>? clipOrder,
    Map<ClipId, TimelineClip>? clips,
    Map<String, Object?>? metadata,
  }) {
    return TimelineTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      order: order ?? this.order,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      enabled: enabled ?? this.enabled,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      clipOrder: clipOrder ?? this.clipOrder,
      clips: clips ?? this.clips,
      metadata: metadata ?? this.metadata,
    );
  }
}

class TimelineMarker {
  const TimelineMarker({
    required this.id,
    required this.time,
    required this.name,
    required this.color,
    this.metadata = const {},
  });

  final MarkerId id;
  final FrameTime time;
  final String name;
  final String color;
  final Map<String, Object?> metadata;

  factory TimelineMarker.fromJson(Map<String, Object?> json) {
    return TimelineMarker(
      id: jsonString(json, 'id'),
      time: FrameTime.fromJson(json['time']),
      name: jsonString(json, 'name'),
      color: jsonString(json, 'color'),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'color': color,
    'id': id,
    'metadata': metadata,
    'name': name,
    'time': time.toJson(),
  };

  TimelineMarker copyWith({
    MarkerId? id,
    FrameTime? time,
    String? name,
    String? color,
    Map<String, Object?>? metadata,
  }) {
    return TimelineMarker(
      id: id ?? this.id,
      time: time ?? this.time,
      name: name ?? this.name,
      color: color ?? this.color,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ProjectTimeline {
  const ProjectTimeline({
    required this.id,
    required this.name,
    required this.canvas,
    required this.frameRate,
    required this.durationFrames,
    this.trackOrder = const [],
    this.tracks = const {},
    this.markers = const {},
    this.styleOverrides = const {},
    this.layoutOverrides = const {},
    this.relationshipMetadata = const {},
    this.metadata = const {},
  });

  final TimelineId id;
  final String name;
  final ProjectCanvas canvas;
  final RationalFrameRate frameRate;
  final int durationFrames;
  final List<TrackId> trackOrder;
  final Map<TrackId, TimelineTrack> tracks;
  final Map<MarkerId, TimelineMarker> markers;
  final Map<String, Object?> styleOverrides;
  final Map<String, Object?> layoutOverrides;
  final Map<String, Object?> relationshipMetadata;
  final Map<String, Object?> metadata;

  factory ProjectTimeline.fromJson(Map<String, Object?> json) {
    return ProjectTimeline(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      canvas: ProjectCanvas.fromJson(jsonMap(json['canvas'])),
      frameRate: RationalFrameRate.fromJson(jsonMap(json['frameRate'])),
      durationFrames: jsonInt(json, 'durationFrames'),
      trackOrder: stringList(json['trackOrder']),
      tracks: objectMap(
        json['tracks'],
        (value) => TimelineTrack.fromJson(jsonMap(value)),
      ),
      markers: objectMap(
        json['markers'],
        (value) => TimelineMarker.fromJson(jsonMap(value)),
      ),
      styleOverrides: jsonMap(json['styleOverrides']),
      layoutOverrides: jsonMap(json['layoutOverrides']),
      relationshipMetadata: jsonMap(json['relationshipMetadata']),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'canvas': canvas.toJson(),
    'durationFrames': durationFrames,
    'frameRate': frameRate.toJson(),
    'id': id,
    'layoutOverrides': layoutOverrides,
    'markers': mapValuesJson(markers),
    'metadata': metadata,
    'name': name,
    'relationshipMetadata': relationshipMetadata,
    'styleOverrides': styleOverrides,
    'trackOrder': trackOrder,
    'tracks': mapValuesJson(tracks),
  };

  ProjectTimeline copyWith({
    TimelineId? id,
    String? name,
    ProjectCanvas? canvas,
    RationalFrameRate? frameRate,
    int? durationFrames,
    List<TrackId>? trackOrder,
    Map<TrackId, TimelineTrack>? tracks,
    Map<MarkerId, TimelineMarker>? markers,
    Map<String, Object?>? styleOverrides,
    Map<String, Object?>? layoutOverrides,
    Map<String, Object?>? relationshipMetadata,
    Map<String, Object?>? metadata,
  }) {
    return ProjectTimeline(
      id: id ?? this.id,
      name: name ?? this.name,
      canvas: canvas ?? this.canvas,
      frameRate: frameRate ?? this.frameRate,
      durationFrames: durationFrames ?? this.durationFrames,
      trackOrder: trackOrder ?? this.trackOrder,
      tracks: tracks ?? this.tracks,
      markers: markers ?? this.markers,
      styleOverrides: styleOverrides ?? this.styleOverrides,
      layoutOverrides: layoutOverrides ?? this.layoutOverrides,
      relationshipMetadata: relationshipMetadata ?? this.relationshipMetadata,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ProjectBin {
  const ProjectBin({
    required this.id,
    required this.name,
    required this.kind,
    this.itemIds = const [],
    this.metadata = const {},
  });

  final BinId id;
  final String name;
  final ProjectBinKind kind;
  final List<String> itemIds;
  final Map<String, Object?> metadata;

  factory ProjectBin.fromJson(Map<String, Object?> json) {
    return ProjectBin(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      kind: enumByName(ProjectBinKind.values, jsonString(json, 'kind')),
      itemIds: stringList(json['itemIds']),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'itemIds': itemIds,
    'kind': kind.name,
    'metadata': metadata,
    'name': name,
  };

  ProjectBin copyWith({
    BinId? id,
    String? name,
    ProjectBinKind? kind,
    List<String>? itemIds,
    Map<String, Object?>? metadata,
  }) {
    return ProjectBin(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      itemIds: itemIds ?? this.itemIds,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ExportPreset {
  const ExportPreset({
    required this.id,
    required this.name,
    required this.container,
    required this.canvas,
    required this.frameRate,
    this.quality = 0.85,
    this.includeAudio = true,
    this.transparent = false,
    this.videoCodec,
    this.audioCodec,
    this.metadata = const {},
  });

  final ExportPresetId id;
  final String name;
  final ExportContainer container;
  final ProjectCanvas canvas;
  final RationalFrameRate frameRate;
  final double quality;
  final bool includeAudio;
  final bool transparent;
  final String? videoCodec;
  final String? audioCodec;
  final Map<String, Object?> metadata;

  factory ExportPreset.fromJson(Map<String, Object?> json) {
    return ExportPreset(
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      container: enumByName(
        ExportContainer.values,
        jsonString(json, 'container'),
      ),
      canvas: ProjectCanvas.fromJson(jsonMap(json['canvas'])),
      frameRate: RationalFrameRate.fromJson(jsonMap(json['frameRate'])),
      quality: jsonDouble(json, 'quality', fallback: 0.85),
      includeAudio: jsonBool(json, 'includeAudio', fallback: true),
      transparent: jsonBool(json, 'transparent'),
      videoCodec: jsonNullableString(json, 'videoCodec'),
      audioCodec: jsonNullableString(json, 'audioCodec'),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  Map<String, Object?> toJson() => {
    'audioCodec': audioCodec,
    'canvas': canvas.toJson(),
    'container': container.name,
    'frameRate': frameRate.toJson(),
    'id': id,
    'includeAudio': includeAudio,
    'metadata': metadata,
    'name': name,
    'quality': quality,
    'transparent': transparent,
    'videoCodec': videoCodec,
  };

  ExportPreset copyWith({
    ExportPresetId? id,
    String? name,
    ExportContainer? container,
    ProjectCanvas? canvas,
    RationalFrameRate? frameRate,
    double? quality,
    bool? includeAudio,
    bool? transparent,
    Object? videoCodec = absentValue,
    Object? audioCodec = absentValue,
    Map<String, Object?>? metadata,
  }) {
    return ExportPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      container: container ?? this.container,
      canvas: canvas ?? this.canvas,
      frameRate: frameRate ?? this.frameRate,
      quality: quality ?? this.quality,
      includeAudio: includeAudio ?? this.includeAudio,
      transparent: transparent ?? this.transparent,
      videoCodec: optionalValue(videoCodec, this.videoCodec),
      audioCodec: optionalValue(audioCodec, this.audioCodec),
      metadata: metadata ?? this.metadata,
    );
  }
}

class ReactifyProjectDocument {
  const ReactifyProjectDocument({
    required this.id,
    required this.name,
    required this.canvasDefaults,
    this.schemaVersion = reactifyReactionProjectSchemaVersion,
    this.assets = const {},
    this.characters = const {},
    this.expressions = const {},
    this.poses = const {},
    this.layouts = const {},
    this.reactionStates = const {},
    this.textPresets = const {},
    this.speakerRules = const {},
    this.timelines = const {},
    this.bins = const {},
    this.exportPresets = const {},
    this.metadata = const {},
  });

  final int schemaVersion;
  final ProjectId id;
  final String name;
  final ProjectCanvas canvasDefaults;
  final Map<AssetId, ProjectAsset> assets;
  final Map<CharacterId, CharacterResource> characters;
  final Map<ExpressionId, ExpressionPreset> expressions;
  final Map<PoseId, PosePreset> poses;
  final Map<LayoutId, LayoutTemplate> layouts;
  final Map<ReactionStateId, ReactionState> reactionStates;
  final Map<TextPresetId, TextPreset> textPresets;
  final Map<SpeakerRuleId, SpeakerRule> speakerRules;
  final Map<TimelineId, ProjectTimeline> timelines;
  final Map<BinId, ProjectBin> bins;
  final Map<ExportPresetId, ExportPreset> exportPresets;
  final Map<String, Object?> metadata;

  factory ReactifyProjectDocument.fromJson(Map<String, Object?> json) {
    final schemaVersion = jsonInt(json, 'schemaVersion');
    if (schemaVersion < 1 ||
        schemaVersion > reactifyReactionProjectSchemaVersion) {
      throw FormatException(
        'Unsupported Reactify reaction project schema $schemaVersion.',
      );
    }
    return ReactifyProjectDocument(
      schemaVersion: schemaVersion,
      id: jsonString(json, 'id'),
      name: jsonString(json, 'name'),
      canvasDefaults: ProjectCanvas.fromJson(jsonMap(json['canvasDefaults'])),
      assets: objectMap(
        json['assets'],
        (value) => ProjectAsset.fromJson(jsonMap(value)),
      ),
      characters: objectMap(
        json['characters'],
        (value) => CharacterResource.fromJson(jsonMap(value)),
      ),
      expressions: objectMap(
        json['expressions'],
        (value) => ExpressionPreset.fromJson(jsonMap(value)),
      ),
      poses: objectMap(
        json['poses'],
        (value) => PosePreset.fromJson(jsonMap(value)),
      ),
      layouts: objectMap(
        json['layouts'],
        (value) => LayoutTemplate.fromJson(jsonMap(value)),
      ),
      reactionStates: objectMap(
        json['reactionStates'],
        (value) => ReactionState.fromJson(jsonMap(value)),
      ),
      textPresets: objectMap(
        json['textPresets'],
        (value) => TextPreset.fromJson(jsonMap(value)),
      ),
      speakerRules: objectMap(
        json['speakerRules'],
        (value) => SpeakerRule.fromJson(jsonMap(value)),
      ),
      timelines: objectMap(
        json['timelines'],
        (value) => ProjectTimeline.fromJson(jsonMap(value)),
      ),
      bins: objectMap(
        json['bins'],
        (value) => ProjectBin.fromJson(jsonMap(value)),
      ),
      exportPresets: objectMap(
        json['exportPresets'],
        (value) => ExportPreset.fromJson(jsonMap(value)),
      ),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  factory ReactifyProjectDocument.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    return ReactifyProjectDocument.fromJson(jsonMap(decoded));
  }

  Map<String, Object?> toJson() => canonicalJsonMap({
    'assets': mapValuesJson(assets),
    'bins': mapValuesJson(bins),
    'canvasDefaults': canvasDefaults.toJson(),
    'characters': mapValuesJson(characters),
    'exportPresets': mapValuesJson(exportPresets),
    'expressions': mapValuesJson(expressions),
    'id': id,
    'layouts': mapValuesJson(layouts),
    'metadata': metadata,
    'name': name,
    'poses': mapValuesJson(poses),
    'reactionStates': mapValuesJson(reactionStates),
    'schemaVersion': schemaVersion,
    'speakerRules': mapValuesJson(speakerRules),
    'textPresets': mapValuesJson(textPresets),
    'timelines': mapValuesJson(timelines),
  });

  String toDeterministicJson({bool pretty = false}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJson());
    }
    return jsonEncode(toJson());
  }

  ReactifyProjectDocument copyWith({
    int? schemaVersion,
    ProjectId? id,
    String? name,
    ProjectCanvas? canvasDefaults,
    Map<AssetId, ProjectAsset>? assets,
    Map<CharacterId, CharacterResource>? characters,
    Map<ExpressionId, ExpressionPreset>? expressions,
    Map<PoseId, PosePreset>? poses,
    Map<LayoutId, LayoutTemplate>? layouts,
    Map<ReactionStateId, ReactionState>? reactionStates,
    Map<TextPresetId, TextPreset>? textPresets,
    Map<SpeakerRuleId, SpeakerRule>? speakerRules,
    Map<TimelineId, ProjectTimeline>? timelines,
    Map<BinId, ProjectBin>? bins,
    Map<ExportPresetId, ExportPreset>? exportPresets,
    Map<String, Object?>? metadata,
  }) {
    return ReactifyProjectDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      name: name ?? this.name,
      canvasDefaults: canvasDefaults ?? this.canvasDefaults,
      assets: assets ?? this.assets,
      characters: characters ?? this.characters,
      expressions: expressions ?? this.expressions,
      poses: poses ?? this.poses,
      layouts: layouts ?? this.layouts,
      reactionStates: reactionStates ?? this.reactionStates,
      textPresets: textPresets ?? this.textPresets,
      speakerRules: speakerRules ?? this.speakerRules,
      timelines: timelines ?? this.timelines,
      bins: bins ?? this.bins,
      exportPresets: exportPresets ?? this.exportPresets,
      metadata: metadata ?? this.metadata,
    );
  }
}

const Object absentValue = _AbsentValue();

class _AbsentValue {
  const _AbsentValue();
}

T? optionalValue<T>(Object? value, T? current) {
  if (identical(value, absentValue)) {
    return current;
  }
  return value as T?;
}

Map<String, Object?> jsonMap(Object? value) {
  if (value == null) {
    return const {};
  }
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  throw FormatException('Expected a JSON object.');
}

List<Object?> jsonList(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return List<Object?>.from(value);
  }
  throw FormatException('Expected a JSON array.');
}

String jsonString(Map<String, Object?> json, String key, {String? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('Expected a string at $key.');
}

String? jsonNullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is String) {
    return value as String?;
  }
  throw FormatException('Expected a nullable string at $key.');
}

int jsonInt(Map<String, Object?> json, String key, {int fallback = 0}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('Expected an integer at $key.');
}

int? jsonNullableInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is int) {
    return value as int?;
  }
  throw FormatException('Expected a nullable integer at $key.');
}

double jsonDouble(
  Map<String, Object?> json,
  String key, {
  double fallback = 0,
}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected a number at $key.');
}

double? jsonNullableDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected a nullable number at $key.');
}

bool jsonBool(Map<String, Object?> json, String key, {bool fallback = false}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected a boolean at $key.');
}

bool? jsonNullableBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is bool) {
    return value as bool?;
  }
  throw FormatException('Expected a nullable boolean at $key.');
}

Map<String, Object?> jsonMetadata(Object? value) => jsonMap(value);

List<String> stringList(Object? value) {
  return jsonList(value)
      .map((item) {
        if (item is! String) {
          throw FormatException('Expected a string array.');
        }
        return item;
      })
      .toList(growable: false);
}

Map<String, bool> boolMap(Object? value) {
  final map = jsonMap(value);
  return map.map((key, item) {
    if (item is! bool) {
      throw FormatException('Expected boolean value at $key.');
    }
    return MapEntry(key, item);
  });
}

Map<String, Map<String, Object?>> nestedJsonMap(Object? value) {
  return jsonMap(value).map((key, item) => MapEntry(key, jsonMap(item)));
}

Map<String, AffineTransform> transformMap(Object? value) {
  return jsonMap(
    value,
  ).map((key, item) => MapEntry(key, AffineTransform.fromJson(jsonMap(item))));
}

Map<String, T> objectMap<T>(Object? value, T Function(Object? value) parse) {
  return jsonMap(value).map((key, item) => MapEntry(key, parse(item)));
}

Map<String, Object?> mapValuesJson<T>(Map<String, T> values) {
  final keys = values.keys.toList()..sort();
  return {for (final key in keys) key: (values[key] as dynamic).toJson()};
}

List<T> sortedValues<T>(Map<String, T> values) {
  final keys = values.keys.toList()..sort();
  return [for (final key in keys) values[key] as T];
}

T enumByName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  throw FormatException('Unknown enum value $name.');
}

Map<String, Object?> canonicalJsonMap(Map<String, Object?> value) {
  return canonicalJsonValue(value) as Map<String, Object?>;
}

Object? canonicalJsonValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return {for (final key in keys) key: canonicalJsonValue(value[key])};
  }
  if (value is List) {
    return [for (final item in value) canonicalJsonValue(item)];
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw FormatException('Value is not JSON encodable: $value');
}
