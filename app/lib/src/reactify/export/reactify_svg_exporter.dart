import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../../gacha/render/render_part.dart';
import '../../gacha/render/transform_graph.dart';
import '../model/reactify_document.dart';
import '../render/reactify_render_bridge.dart';

class ReactifySvgPackage {
  const ReactifySvgPackage({
    required this.svg,
    required this.assets,
    required this.inlinedAssetIds,
  });

  final String svg;
  final List<ReactifySvgPackageAsset> assets;
  final Set<String> inlinedAssetIds;

  Map<String, Object?> toJson() {
    return {
      'svg': svg,
      'assets': [for (final asset in assets) asset.toJson()],
      'inlinedAssetIds': inlinedAssetIds.toList()..sort(),
    };
  }
}

class ReactifySvgPackageAsset {
  const ReactifySvgPackageAsset({
    required this.id,
    required this.uri,
    required this.kind,
    required this.source,
    required this.inlined,
  });

  final String id;
  final String uri;
  final ReactifyAssetKind kind;
  final String source;
  final bool inlined;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'uri': uri,
      'kind': kind.name,
      'source': source,
      'inlined': inlined,
    };
  }
}

class ReactifySvgExporter {
  ReactifySvgExporter({AssetBundle? assetLoader})
    : assetLoader = assetLoader ?? rootBundle;

  final AssetBundle assetLoader;

  String exportScene(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
  ) {
    return _buildSceneSvg(scene, characters, const {}, const {}).toString();
  }

  Future<ReactifySvgPackage> exportPackage(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
  ) async {
    final assets = _collectAssets(scene, characters);
    final inlineSvgById = <String, String>{};
    for (final asset in assets.values) {
      if (asset.kind != ReactifyAssetKind.svg || !asset.preserveVector) {
        continue;
      }
      try {
        inlineSvgById[asset.id] = _cleanInlineSvg(
          await assetLoader.loadString(asset.uri),
        );
      } on Object {
        continue;
      }
    }
    return ReactifySvgPackage(
      svg: _buildSceneSvg(scene, characters, inlineSvgById, assets).toString(),
      assets: [
        for (final asset in assets.values)
          ReactifySvgPackageAsset(
            id: asset.id,
            uri: asset.uri,
            kind: asset.kind,
            source: asset.source,
            inlined:
                inlineSvgById.containsKey(asset.id) ||
                asset.kind == ReactifyAssetKind.drawing,
          ),
      ],
      inlinedAssetIds: inlineSvgById.keys.toSet(),
    );
  }

  StringBuffer _buildSceneSvg(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
    Map<String, String> inlineSvgById,
    Map<String, ReactifyAssetRef> manifestAssets,
  ) {
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="${_num(scene.canvasSize.width)}" '
        'height="${_num(scene.canvasSize.height)}" '
        'viewBox="0 0 ${_num(scene.canvasSize.width)} '
        '${_num(scene.canvasSize.height)}">',
      )
      ..writeln('<metadata>')
      ..writeln(
        '<reactify-export schemaVersion="1" packageAssets="'
        '${manifestAssets.length}" />',
      )
      ..writeln('</metadata>')
      ..writeln(
        '<g id="${_xml(scene.id)}" data-reactify-type="scene" '
        'transform="${_matrix(scene.cameraTransform)}">',
      );
    final background = scene.background;
    if (background != null && background.visible) {
      _writeAssetGroup(
        buffer,
        id: background.id,
        type: 'background',
        family: 'background',
        anchorId: 'scene',
        transform: background.transform,
        asset: background.asset,
        inlineSvgById: inlineSvgById,
        metadata: const {},
      );
    }
    for (final sceneCharacter in scene.characters) {
      final character = characters[sceneCharacter.characterId];
      if (character == null) {
        continue;
      }
      _writeCharacter(buffer, sceneCharacter, character, inlineSvgById);
    }
    buffer
      ..writeln('</g>')
      ..writeln('</svg>');
    return buffer;
  }

  void _writeCharacter(
    StringBuffer buffer,
    ReactifySceneCharacter sceneCharacter,
    ReactifyCharacterDocument character,
    Map<String, String> inlineSvgById,
  ) {
    buffer.writeln(
      '<g id="${_xml(sceneCharacter.id)}" '
      'data-reactify-type="character" '
      'data-character-id="${_xml(character.id)}" '
      'data-expression="${_xml(sceneCharacter.expression ?? '')}" '
      'data-pose="${_xml(sceneCharacter.pose ?? '')}" '
      'transform="${_matrix(sceneCharacter.transform)}">',
    );
    final anchorWorld = _anchorWorldTransforms(character.rig);
    final slots = _effectiveSlots(character, sceneCharacter).toList()
      ..sort((left, right) {
        final depthCompare = left.depth.compareTo(right.depth);
        if (depthCompare != 0) return depthCompare;
        return left.id.compareTo(right.id);
      });
    for (final slot in slots) {
      if (!slot.visible) {
        continue;
      }
      final parentWorld =
          anchorWorld[slot.anchorId] ??
          anchorWorld['torso'] ??
          const AffineMatrix.identity();
      _writeSlot(
        buffer,
        slot,
        inlineSvgById,
        parentWorld.multiply(slot.localTransform),
      );
    }
    if (sceneCharacter.dialogue != null) {
      buffer.writeln(
        '<text data-reactify-type="dialogue">${_xml(sceneCharacter.dialogue!)}</text>',
      );
    }
    buffer.writeln('</g>');
  }

  void _writeSlot(
    StringBuffer buffer,
    ReactifySlot slot,
    Map<String, String> inlineSvgById,
    AffineMatrix transform,
  ) {
    buffer.writeln(
      '<g id="${_xml(slot.id)}" '
      'data-reactify-type="slot" '
      'data-slot-kind="${_xml(slot.kind.name)}" '
      'data-family="${_xml(slot.family)}" '
      'data-anchor="${_xml(slot.anchorId)}" '
      'data-depth="${slot.depth}" '
      '${_metadataAttributes(slot.metadata)}'
      'transform="${_matrix(transform)}">',
    );
    if (slot.childSlotIds.isNotEmpty) {
      buffer.writeln(
        '<metadata data-child-slots="${_xml(slot.childSlotIds.join(' '))}" />',
      );
    }
    final asset = slot.asset;
    if (asset != null && asset.uri.isNotEmpty) {
      if (asset.kind == ReactifyAssetKind.drawing) {
        _writeDrawingAsset(buffer, '${slot.id}.asset', asset, slot.metadata);
      } else {
        _writeAsset(buffer, '${slot.id}.asset', asset, inlineSvgById);
      }
    }
    buffer.writeln('</g>');
  }

  void _writeAssetGroup(
    StringBuffer buffer, {
    required String id,
    required String type,
    required String family,
    required String anchorId,
    required AffineMatrix transform,
    required ReactifyAssetRef asset,
    required Map<String, String> inlineSvgById,
    required Map<String, Object?> metadata,
  }) {
    buffer.writeln(
      '<g id="${_xml(id)}" data-reactify-type="${_xml(type)}" '
      'data-family="${_xml(family)}" data-anchor="${_xml(anchorId)}" '
      '${_metadataAttributes(metadata)}transform="${_matrix(transform)}">',
    );
    _writeAsset(buffer, '$id.asset', asset, inlineSvgById);
    buffer.writeln('</g>');
  }

  void _writeAsset(
    StringBuffer buffer,
    String id,
    ReactifyAssetRef asset,
    Map<String, String> inlineSvgById,
  ) {
    final inlineSvg = inlineSvgById[asset.id];
    if (inlineSvg != null) {
      buffer.writeln(
        '<g id="${_xml(id)}" data-reactify-asset-id="${_xml(asset.id)}" '
        'data-reactify-asset-uri="${_xml(asset.uri)}">',
      );
      buffer.writeln(inlineSvg);
      buffer.writeln('</g>');
      return;
    }
    buffer.writeln(
      '<image id="${_xml(id)}" href="${_xml(asset.uri)}" '
      'data-reactify-asset-id="${_xml(asset.id)}" '
      'data-reactify-asset-kind="${_xml(asset.kind.name)}" />',
    );
  }

  void _writeDrawingAsset(
    StringBuffer buffer,
    String id,
    ReactifyAssetRef asset,
    Map<String, Object?> metadata,
  ) {
    buffer.writeln(
      '<g id="${_xml(id)}" data-reactify-asset-id="${_xml(asset.id)}" '
      'data-reactify-asset-kind="${_xml(asset.kind.name)}">',
    );
    final color = _xml(_metadataString(metadata, 'drawingColor', '#00F5FF'));
    final strokeWidth = _num(
      _metadataDouble(metadata, 'drawingStrokeWidth', 3.5),
    );
    for (final path in _drawingPaths(metadata)) {
      buffer.writeln(
        '<path d="${_xml(path)}" fill="none" stroke="$color" '
        'stroke-width="$strokeWidth" stroke-linecap="round" '
        'stroke-linejoin="round" data-reactify-drawing="stroke" />',
      );
    }
    buffer.writeln('</g>');
  }

  Map<String, ReactifyAssetRef> _collectAssets(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
  ) {
    final assets = <String, ReactifyAssetRef>{};
    final background = scene.background;
    if (background != null) {
      assets[background.asset.id] = background.asset;
    }
    for (final sceneCharacter in scene.characters) {
      final character = characters[sceneCharacter.characterId];
      if (character == null) {
        continue;
      }
      for (final slot in _effectiveSlots(character, sceneCharacter)) {
        if (!slot.visible) {
          continue;
        }
        final asset = slot.asset;
        if (asset != null) {
          assets[asset.id] = asset;
        }
      }
    }
    return assets;
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
    for (final baseSlot in character.slots) {
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

  static String _metadataAttributes(Map<String, Object?> metadata) {
    final names = [
      'legacyFamily',
      'legacyLeafId',
      'legacyHostScope',
      'legacyHostName',
      'legacyFramePath',
      'source',
    ];
    final buffer = StringBuffer();
    for (final name in names) {
      final value = metadata[name];
      if (value == null) {
        continue;
      }
      buffer.write('data-$name="${_xml('$value')}" ');
    }
    return buffer.toString();
  }

  static String _cleanInlineSvg(String svg) {
    return svg
        .replaceFirst(RegExp(r'^\s*<\?xml[^>]*>\s*'), '')
        .replaceFirst(RegExp(r'^\s*<!DOCTYPE[^>]*>\s*'), '')
        .trim();
  }

  static List<String> _drawingPaths(Map<String, Object?> metadata) {
    final raw = metadata['drawingStrokes'];
    if (raw is! List) {
      return const [];
    }
    final paths = <String>[];
    for (final stroke in raw) {
      if (stroke is! List || stroke.length < 2) {
        continue;
      }
      final points = [
        for (final point in stroke)
          if (point is Map)
            (x: _objectDouble(point['x']), y: _objectDouble(point['y'])),
      ];
      if (points.length < 2) {
        continue;
      }
      final buffer = StringBuffer(
        'M ${_num(points.first.x)} ${_num(points.first.y)}',
      );
      for (var i = 1; i < points.length; i++) {
        buffer.write(' L ${_num(points[i].x)} ${_num(points[i].y)}');
      }
      paths.add(buffer.toString());
    }
    return paths;
  }

  static String _matrix(AffineMatrix matrix) {
    return 'matrix(${_num(matrix.a)} ${_num(matrix.b)} ${_num(matrix.c)} '
        '${_num(matrix.d)} ${_num(matrix.tx)} ${_num(matrix.ty)})';
  }

  static String _num(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static String _metadataString(
    Map<String, Object?> metadata,
    String key,
    String fallback,
  ) {
    final value = metadata[key];
    return value == null ? fallback : '$value';
  }

  static double _metadataDouble(
    Map<String, Object?> metadata,
    String key,
    double fallback,
  ) {
    final value = metadata[key];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static double _objectDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}

class ReactifyPngExporter {
  const ReactifyPngExporter({required this.bridge});

  final ReactifyRenderBridge bridge;

  Future<Uint8List> exportScene(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters, {
    ui.Color? backgroundColor,
  }) async {
    final resolved = await bridge.buildRenderableScene(scene, characters);
    final image = await renderResolvedScene(
      resolved,
      scene.canvasSize,
      backgroundColor: backgroundColor,
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('Unable to encode native scene PNG.');
    }
    return byteData.buffer.asUint8List();
  }

  static Future<ui.Image> renderResolvedScene(
    ResolvedScene scene,
    ui.Size size, {
    ui.Color? backgroundColor,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (backgroundColor != null) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, size.width, size.height),
        ui.Paint()..color = backgroundColor,
      );
    }
    for (final part in scene.parts) {
      final asset = scene.assets[part.catalogPart.appAssetPath];
      if (asset == null) {
        continue;
      }
      canvas.save();
      canvas.transform(part.localTransform.toFloat64List());
      canvas.translate(
        part.catalogPart.runtimeAnchorX,
        part.catalogPart.runtimeAnchorY,
      );
      asset.paint(canvas, part.tintColor);
      canvas.restore();
    }
    return recorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
  }
}
