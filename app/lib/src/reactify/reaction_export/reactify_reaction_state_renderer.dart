import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../gacha/render/transform_graph.dart';
import '../../gacha/render/render_part.dart';
import '../export/reactify_svg_exporter.dart';
import '../media/media.dart';
import '../model/reactify_document.dart';
import '../project/project.dart';
import '../text/project_text_adapter.dart';
import '../text/reaction_text_renderer.dart';
import 'reaction_dialogue_selection.dart';
import 'reaction_export_models.dart';
import 'reaction_media_frame.dart';

class ReactionDialogueOverlay {
  const ReactionDialogueOverlay({
    required this.trackId,
    required this.clip,
    required this.textLayout,
    required this.safeBounds,
    required this.offset,
    required this.scale,
    required this.transform,
    required this.opacity,
  });

  final String trackId;
  final RichTextTimelineClip clip;
  final ReactionTextLayout textLayout;
  final ui.Rect safeBounds;
  final ui.Offset offset;
  final double scale;
  final AffineMatrix transform;
  final double opacity;
}

class ReactifyReactionStateRenderer implements ReactionStateRenderer {
  const ReactifyReactionStateRenderer({
    required this.pngExporter,
    this.mediaFrameResolver,
  });

  final ReactifyPngExporter pngExporter;
  final ReactionMediaFrameResolver? mediaFrameResolver;

  @override
  Future<RenderedReactionArtifact> render(
    ReactionRenderRequest request,
    ExportCancellationToken cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final layout = request.project.layouts[request.state.layoutId];
    if (layout == null) {
      throw MediaFailure(
        code: MediaFailureCode.sourceMissing,
        message: 'The reaction state layout is missing.',
        context: {
          'stateId': request.state.id,
          'layoutId': request.state.layoutId,
        },
      );
    }
    _validateRequestedSemantics(request);
    final stateCharacterIds = request.state.characters
        .map((instance) => instance.characterId)
        .toSet();
    if (request.characterIds.any((id) => !stateCharacterIds.contains(id))) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'A selected character is not present in the reaction state.',
        context: {'stateId': request.state.id},
      );
    }
    final canvas = request.timeline?.canvas ?? request.project.canvasDefaults;
    final backgroundCharacters = <_LayeredSceneCharacter>[];
    final sceneCharacters = <_LayeredSceneCharacter>[];
    final nativeCharacters = <String, ReactifyCharacterDocument>{};
    if (request.composition == ReactionExportComposition.composited) {
      final backgroundId =
          request.state.backgroundAssetId ?? layout.backgroundAssetId;
      if (backgroundId != null) {
        _addAssetLayer(
          project: request.project,
          assetId: backgroundId,
          sceneId: 'background.${request.state.id}',
          layer: -0x3fffffff,
          canvas: canvas,
          fitCanvas: true,
          sceneCharacters: backgroundCharacters,
          nativeCharacters: nativeCharacters,
        );
      }
    }
    final placements = {for (final value in layout.placements) value.id: value};
    for (var index = 0; index < request.state.characters.length; index += 1) {
      final instance = request.state.characters[index];
      if (!instance.visible ||
          !request.characterIds.contains(instance.characterId)) {
        continue;
      }
      final placement = _placementFor(instance, layout, placements);
      final resource = request.project.characters[instance.characterId];
      if (resource == null) {
        throw MediaFailure(
          code: MediaFailureCode.sourceMissing,
          message: 'A reaction character resource is missing.',
          context: {
            'stateId': request.state.id,
            'instanceId': instance.id,
            'characterId': instance.characterId,
          },
        );
      }
      var character = _nativeCharacter(resource, instance.id);
      final expression = _expressionFor(request.project, instance);
      final pose = _poseFor(request.project, instance);
      if (pose != null) {
        character = _applyPoseRig(character, pose, instance);
      }
      final overrides = <String, ReactifySlotOverride>{};
      if (expression != null) {
        _applyExpression(overrides, character, expression, instance);
      }
      if (pose != null) {
        for (final entry in pose.slotTransforms.entries) {
          _requireSlot(character, entry.key, instance.id);
          _mergeInto(
            overrides,
            entry.key,
            ReactifySlotOverride(localTransform: _matrix(entry.value)),
          );
        }
      }
      _applyRawOverrides(
        overrides,
        character,
        instance.slotOverrides,
        instance.id,
      );
      final normalized = _normalizeDepths(character, overrides);
      character = normalized.character;
      final nativeKey = '${instance.characterId}::${instance.id}';
      nativeCharacters[nativeKey] = character;
      final placementTransform = placement == null
          ? const AffineMatrix.identity()
          : _matrix(placement.transform);
      final instanceTransform = instance.transform == null
          ? const AffineMatrix.identity()
          : _matrix(instance.transform!);
      sceneCharacters.add(
        _LayeredSceneCharacter(
          layer: (placement?.layer ?? 0) + instance.layer,
          sourceIndex: index,
          character: ReactifySceneCharacter(
            id: instance.id,
            characterId: nativeKey,
            transform: placementTransform.multiply(instanceTransform),
            slotOverrides: normalized.overrides,
            expression: expression?.id,
            pose: pose?.id,
            metadata: instance.metadata,
          ),
        ),
      );
    }
    final watermarkId = layout.watermarkAssetId;
    if (watermarkId != null) {
      _addAssetLayer(
        project: request.project,
        assetId: watermarkId,
        sceneId: 'watermark.${request.state.id}',
        layer: 0x3fffffff,
        canvas: canvas,
        fitCanvas: false,
        sceneCharacters: sceneCharacters,
        nativeCharacters: nativeCharacters,
      );
    }
    sceneCharacters.sort((left, right) {
      final layer = left.layer.compareTo(right.layer);
      return layer != 0 ? layer : left.sourceIndex.compareTo(right.sourceIndex);
    });
    final scale = AffineMatrix.scale(
      canvas.width / layout.canvas.width,
      canvas.height / layout.canvas.height,
    );
    final clipTransform = request.event == null
        ? const AffineMatrix.identity()
        : _matrix(request.event!.clip.visual.transform);
    final scene = ReactifySceneDocument(
      id: 'reaction.${request.contentKey}',
      name: request.state.name,
      canvasSize: ui.Size(canvas.width.toDouble(), canvas.height.toDouble()),
      cameraTransform: clipTransform.multiply(scale),
      characters: [for (final entry in sceneCharacters) entry.character],
      metadata: {'contentKey': request.contentKey, 'stateId': request.state.id},
    );
    final backgroundScene = backgroundCharacters.isEmpty
        ? null
        : ReactifySceneDocument(
            id: 'reaction.${request.contentKey}.background',
            name: '${request.state.name} Background',
            canvasSize: scene.canvasSize,
            cameraTransform: scene.cameraTransform,
            characters: [
              for (final entry in backgroundCharacters) entry.character,
            ],
          );
    final backgroundColor =
        request.composition == ReactionExportComposition.composited
        ? _color(canvas.backgroundColor)
        : null;
    final dialogue = dialogueOverlays(request);
    final media = await _resolveMediaOverlay(
      request,
      layout,
      canvas,
      cancellation,
    );
    Uint8List pngBytes;
    try {
      pngBytes = dialogue.isEmpty && media == null && backgroundScene == null
          ? await pngExporter.exportScene(
              scene,
              nativeCharacters,
              backgroundColor: backgroundColor,
            )
          : await _exportLayeredScene(
              backgroundScene,
              scene,
              nativeCharacters,
              backgroundColor,
              media,
              dialogue,
            );
    } on MediaFailure {
      rethrow;
    } catch (error) {
      throw MediaFailure(
        code: MediaFailureCode.encodeFailed,
        message: 'The native reaction scene could not be rendered as PNG.',
        cause: error,
        context: {
          'stateId': request.state.id,
          'contentKey': request.contentKey,
        },
      );
    } finally {
      media?.dispose();
    }
    cancellation.throwIfCancelled();
    if (!_isPng(pngBytes)) {
      throw MediaFailure(
        code: MediaFailureCode.encodeFailed,
        message: 'The native reaction renderer returned invalid PNG data.',
        context: {'stateId': request.state.id},
      );
    }
    return RenderedReactionArtifact(
      pngBytes: pngBytes,
      width: canvas.width,
      height: canvas.height,
    );
  }

  List<ReactionDialogueOverlay> dialogueOverlays(
    ReactionRenderRequest request,
  ) {
    final timeline = request.timeline;
    final event = request.event;
    if (!request.includeDialogue ||
        timeline == null ||
        event == null ||
        !event.clip.showDialogue) {
      return const [];
    }
    final layout = request.project.layouts[request.state.layoutId];
    if (layout == null) {
      throw MediaFailure(
        code: MediaFailureCode.sourceMissing,
        message: 'The reaction state layout is missing.',
        context: {'layoutId': request.state.layoutId},
      );
    }
    final canvas = timeline.canvas;
    final active = activeReactionDialogueClips(timeline, event);
    final safeRegions = layout.textSafeRegions.isEmpty
        ? const [NormalizedRect(left: 0, top: 0, width: 1, height: 1)]
        : layout.textSafeRegions;
    const adapter = ProjectReactionTextAdapter();
    final overlays = <ReactionDialogueOverlay>[];
    for (var index = 0; index < active.length; index += 1) {
      final entry = active[index];
      final clip = entry.clip;
      _validateTextVisual(clip);
      final safeIndex = _safeRegionIndex(clip, index, safeRegions.length);
      final normalized = safeRegions[safeIndex];
      final safeBounds = _safeBounds(normalized, canvas, clip.id);
      final textDirection = _textDirection(clip);
      final textLayout = adapter.layoutClip(
        project: request.project,
        timeline: timeline,
        clip: clip,
        maxWidth: safeBounds.width,
        textDirection: textDirection,
      );
      final scale = textLayout.size.height <= 0
          ? 1.0
          : (safeBounds.height / textLayout.size.height).clamp(0.0, 1.0);
      final paintedWidth = textLayout.size.width * scale;
      final paintedHeight = textLayout.size.height * scale;
      overlays.add(
        ReactionDialogueOverlay(
          trackId: entry.track.id,
          clip: clip,
          textLayout: textLayout,
          safeBounds: safeBounds,
          offset: ui.Offset(
            safeBounds.left + (safeBounds.width - paintedWidth) / 2,
            safeBounds.top + (safeBounds.height - paintedHeight) / 2,
          ),
          scale: scale,
          transform: _matrix(clip.visual.transform),
          opacity: clip.visual.opacity,
        ),
      );
    }
    return List.unmodifiable(overlays);
  }

  Future<Uint8List> _exportLayeredScene(
    ReactifySceneDocument? backgroundScene,
    ReactifySceneDocument foregroundScene,
    Map<String, ReactifyCharacterDocument> characters,
    ui.Color? backgroundColor,
    _ResolvedMediaOverlay? media,
    List<ReactionDialogueOverlay> overlays,
  ) async {
    final foregroundResolved = await pngExporter.bridge.buildRenderableScene(
      foregroundScene,
      characters,
    );
    final foregroundImage = await ReactifyPngExporter.renderResolvedScene(
      foregroundResolved,
      foregroundScene.canvasSize,
    );
    ui.Image? backgroundImage;
    ui.Image? outputImage;
    try {
      if (backgroundScene != null) {
        final backgroundResolved = await pngExporter.bridge
            .buildRenderableScene(backgroundScene, characters);
        backgroundImage = await ReactifyPngExporter.renderResolvedScene(
          backgroundResolved,
          backgroundScene.canvasSize,
          backgroundColor: backgroundColor,
        );
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (backgroundImage != null) {
        canvas.drawImage(backgroundImage, ui.Offset.zero, ui.Paint());
      } else if (backgroundColor != null) {
        canvas.drawRect(
          ui.Offset.zero & foregroundScene.canvasSize,
          ui.Paint()..color = backgroundColor,
        );
      }
      media?.paint(canvas);
      canvas.drawImage(foregroundImage, ui.Offset.zero, ui.Paint());
      const textRenderer = ReactionTextBlockRenderer();
      for (final overlay in overlays) {
        if (overlay.opacity <= 0) continue;
        canvas.save();
        canvas.clipRect(overlay.safeBounds);
        if (overlay.opacity < 1) {
          canvas.saveLayer(
            overlay.safeBounds,
            ui.Paint()
              ..color = ui.Color.fromARGB(
                (overlay.opacity * 255).round(),
                255,
                255,
                255,
              ),
          );
        }
        canvas.transform(overlay.transform.toFloat64List());
        canvas.translate(overlay.offset.dx, overlay.offset.dy);
        canvas.scale(overlay.scale);
        textRenderer.paint(canvas, overlay.textLayout);
        if (overlay.opacity < 1) canvas.restore();
        canvas.restore();
      }
      outputImage = await recorder.endRecording().toImage(
        foregroundScene.canvasSize.width.toInt(),
        foregroundScene.canvasSize.height.toInt(),
      );
      final data = await outputImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw MediaFailure(
          code: MediaFailureCode.encodeFailed,
          message: 'Unable to encode reaction dialogue PNG.',
        );
      }
      return data.buffer.asUint8List();
    } finally {
      backgroundImage?.dispose();
      foregroundImage.dispose();
      outputImage?.dispose();
    }
  }

  void _validateRequestedSemantics(ReactionRenderRequest request) {
    if (request.includeDialogue && request.state.dialogueMetadata.isNotEmpty) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message:
            'Unstructured reaction-state dialogue metadata is not supported.',
        context: {'stateId': request.state.id},
      );
    }
    if (request.timeline?.layoutOverrides.isNotEmpty == true) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message:
            'Timeline layout overrides are not supported by reaction PNG export.',
        context: {'timelineId': request.timeline!.id},
      );
    }
    final visual = request.event?.clip.visual;
    if (visual != null &&
        (visual.crop != null ||
            visual.opacity != 1 ||
            visual.fadeInFrames != 0 ||
            visual.fadeOutFrames != 0 ||
            visual.transitionIn != null ||
            visual.transitionOut != null ||
            visual.effects.isNotEmpty)) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message:
            'Reaction clip crop, opacity, fades, transitions, and effects are not supported by PNG export.',
        context: {'clipId': request.event!.clip.id},
      );
    }
  }

  void _validateTextVisual(RichTextTimelineClip clip) {
    final visual = clip.visual;
    if (!visual.opacity.isFinite || visual.opacity < 0 || visual.opacity > 1) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Dialogue clip opacity must be between zero and one.',
        context: {'clipId': clip.id},
      );
    }
    if (visual.crop != null ||
        visual.fadeInFrames != 0 ||
        visual.fadeOutFrames != 0 ||
        visual.transitionIn != null ||
        visual.transitionOut != null ||
        visual.effects.isNotEmpty) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message:
            'Dialogue crop, fades, transitions, and effects are not supported by PNG export.',
        context: {'clipId': clip.id},
      );
    }
  }

  int _safeRegionIndex(
    RichTextTimelineClip clip,
    int fallback,
    int regionCount,
  ) {
    final value =
        clip.metadata['safeRegionIndex'] ??
        clip.metadata['textSafeRegionIndex'];
    if (value == null) return fallback % regionCount;
    if (value is! int || value < 0 || value >= regionCount) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Dialogue safe-region index is invalid.',
        context: {'clipId': clip.id, 'safeRegionIndex': value},
      );
    }
    return value;
  }

  ui.Rect _safeBounds(
    NormalizedRect region,
    ProjectCanvas canvas,
    String clipId,
  ) {
    final values = [region.left, region.top, region.width, region.height];
    if (values.any((value) => !value.isFinite) ||
        region.left < 0 ||
        region.top < 0 ||
        region.width <= 0 ||
        region.height <= 0 ||
        region.left + region.width > 1 ||
        region.top + region.height > 1) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message:
            'Dialogue safe region must be a normalized in-bounds rectangle.',
        context: {'clipId': clipId},
      );
    }
    return ui.Rect.fromLTWH(
      region.left * canvas.width,
      region.top * canvas.height,
      region.width * canvas.width,
      region.height * canvas.height,
    );
  }

  ui.TextDirection _textDirection(RichTextTimelineClip clip) {
    final value = clip.metadata['textDirection'];
    return switch (value) {
      null || 'ltr' => ui.TextDirection.ltr,
      'rtl' => ui.TextDirection.rtl,
      _ => throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Dialogue text direction must be ltr or rtl.',
        context: {'clipId': clip.id, 'textDirection': value},
      ),
    };
  }

  LayoutPlacement? _placementFor(
    ReactionCharacterInstance instance,
    LayoutTemplate layout,
    Map<String, LayoutPlacement> placements,
  ) {
    final placementId = instance.layoutPlacementId;
    if (placementId != null) {
      final placement = placements[placementId];
      if (placement == null) {
        throw MediaFailure(
          code: MediaFailureCode.sourceMissing,
          message: 'A reaction character layout placement is missing.',
          context: {'instanceId': instance.id, 'placementId': placementId},
        );
      }
      if (placement.characterId != null &&
          placement.characterId != instance.characterId) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'A layout placement belongs to a different character.',
          context: {'instanceId': instance.id, 'placementId': placementId},
        );
      }
      return placement;
    }
    final matches = layout.placements
        .where((value) => value.characterId == instance.characterId)
        .toList();
    if (matches.length > 1) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message:
            'A reaction character has multiple implicit layout placements.',
        context: {'instanceId': instance.id},
      );
    }
    return matches.firstOrNull;
  }

  ReactifyCharacterDocument _nativeCharacter(
    CharacterResource resource,
    String instanceId,
  ) {
    if (resource.document.isEmpty ||
        resource.document['rig'] is! Map ||
        resource.document['slots'] is! List) {
      throw MediaFailure(
        code: MediaFailureCode.sourceMissing,
        message: 'A character has no native Reactify character document.',
        context: {'characterId': resource.id, 'instanceId': instanceId},
      );
    }
    ReactifyCharacterDocument character;
    try {
      character = ReactifyCharacterDocument.fromJson(resource.document);
    } catch (error) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedFormat,
        message: 'A native Reactify character document is invalid.',
        cause: error,
        context: {'characterId': resource.id, 'instanceId': instanceId},
      );
    }
    final slotIds = <String>{};
    if (character.id.trim().isEmpty ||
        character.rig.id.trim().isEmpty ||
        character.rig.anchors.isEmpty ||
        character.slots.isEmpty ||
        character.slots.any(
          (slot) =>
              slot.id.trim().isEmpty ||
              !slotIds.add(slot.id) ||
              !character.rig.anchors.containsKey(slot.anchorId) ||
              !_validMatrix(slot.localTransform) ||
              slot.overrides.values.any(
                (value) =>
                    value.localTransform != null &&
                    !_validMatrix(value.localTransform!),
              ) ||
              (slot.isRenderable && slot.asset!.uri.trim().isEmpty),
        )) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedFormat,
        message: 'A native Reactify character document is incomplete.',
        context: {'characterId': resource.id, 'instanceId': instanceId},
      );
    }
    _validateRig(character, resource.id, instanceId);
    return character;
  }

  void _validateRig(
    ReactifyCharacterDocument character,
    String characterId,
    String instanceId,
  ) {
    final anchors = character.rig.anchors;
    for (final entry in anchors.entries) {
      if (entry.key != entry.value.id ||
          !_validMatrix(entry.value.localTransform) ||
          (entry.value.parentId != null &&
              !anchors.containsKey(entry.value.parentId))) {
        throw MediaFailure(
          code: MediaFailureCode.unsupportedFormat,
          message: 'A native Reactify character rig is invalid.',
          context: {'characterId': characterId, 'instanceId': instanceId},
        );
      }
    }
    final resolved = <String>{};
    final active = <String>{};
    void visit(String id) {
      if (resolved.contains(id)) return;
      if (!active.add(id)) {
        throw MediaFailure(
          code: MediaFailureCode.unsupportedFormat,
          message: 'A native Reactify character rig contains a cycle.',
          context: {'characterId': characterId, 'instanceId': instanceId},
        );
      }
      final parent = anchors[id]!.parentId;
      if (parent != null) visit(parent);
      active.remove(id);
      resolved.add(id);
    }

    for (final id in anchors.keys) {
      visit(id);
    }
  }

  ExpressionPreset? _expressionFor(
    ReactifyProjectDocument project,
    ReactionCharacterInstance instance,
  ) {
    final id = instance.expressionId;
    if (id == null) return null;
    final expression = project.expressions[id];
    if (expression == null) {
      throw MediaFailure(
        code: MediaFailureCode.sourceMissing,
        message: 'A reaction character expression is missing.',
        context: {'instanceId': instance.id, 'expressionId': id},
      );
    }
    if (expression.characterId != null &&
        expression.characterId != instance.characterId) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'A reaction expression belongs to a different character.',
        context: {'instanceId': instance.id, 'expressionId': id},
      );
    }
    return expression;
  }

  PosePreset? _poseFor(
    ReactifyProjectDocument project,
    ReactionCharacterInstance instance,
  ) {
    final id = instance.poseId;
    if (id == null) return null;
    final pose = project.poses[id];
    if (pose == null) {
      throw MediaFailure(
        code: MediaFailureCode.sourceMissing,
        message: 'A reaction character pose is missing.',
        context: {'instanceId': instance.id, 'poseId': id},
      );
    }
    if (pose.characterId != null && pose.characterId != instance.characterId) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'A reaction pose belongs to a different character.',
        context: {'instanceId': instance.id, 'poseId': id},
      );
    }
    return pose;
  }

  ReactifyCharacterDocument _applyPoseRig(
    ReactifyCharacterDocument character,
    PosePreset pose,
    ReactionCharacterInstance instance,
  ) {
    final anchors = Map<String, ReactifyAnchor>.of(character.rig.anchors);
    for (final entry in pose.anchorTransforms.entries) {
      final anchor = anchors[entry.key];
      if (anchor == null) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'A pose references an unknown native rig anchor.',
          context: {
            'instanceId': instance.id,
            'poseId': pose.id,
            'anchorId': entry.key,
          },
        );
      }
      anchors[entry.key] = ReactifyAnchor(
        id: anchor.id,
        parentId: anchor.parentId,
        localTransform: _matrix(entry.value),
      );
    }
    return character.copyWith(
      rig: ReactifyRigTemplate(
        id: character.rig.id,
        name: character.rig.name,
        anchors: anchors,
      ),
    );
  }

  void _applyExpression(
    Map<String, ReactifySlotOverride> overrides,
    ReactifyCharacterDocument character,
    ExpressionPreset expression,
    ReactionCharacterInstance instance,
  ) {
    for (final semantic in expression.semanticValues.entries) {
      final value = semantic.value;
      if (value is! String && value is! num && value is! bool) {
        throw MediaFailure(
          code: MediaFailureCode.unsupportedCapability,
          message: 'An expression semantic value has an unsupported type.',
          context: {
            'instanceId': instance.id,
            'expressionId': expression.id,
            'semantic': semantic.key,
          },
        );
      }
      final option = '$value';
      var candidates = character.slots
          .where(
            (slot) =>
                (slot.id == semantic.key || slot.family == semantic.key) &&
                slot.overrides.containsKey(option),
          )
          .toList();
      if (candidates.isEmpty) {
        candidates = character.semanticSlots
            .where((slot) => slot.overrides.containsKey(option))
            .toList();
      }
      if (candidates.isEmpty) {
        throw MediaFailure(
          code: MediaFailureCode.unsupportedCapability,
          message:
              'A native character cannot resolve an expression semantic value.',
          context: {
            'instanceId': instance.id,
            'expressionId': expression.id,
            'semantic': semantic.key,
            'value': option,
          },
        );
      }
      for (final slot in candidates) {
        _mergeInto(overrides, slot.id, slot.overrides[option]!);
      }
    }
    _applyRawOverrides(
      overrides,
      character,
      expression.slotOverrides,
      instance.id,
    );
    for (final entry in expression.visibilityOverrides.entries) {
      _requireSlot(character, entry.key, instance.id);
      _mergeInto(
        overrides,
        entry.key,
        ReactifySlotOverride(visible: entry.value),
      );
    }
  }

  void _applyRawOverrides(
    Map<String, ReactifySlotOverride> target,
    ReactifyCharacterDocument character,
    Map<String, Map<String, Object?>> source,
    String instanceId,
  ) {
    for (final entry in source.entries) {
      _requireSlot(character, entry.key, instanceId);
      ReactifySlotOverride value;
      try {
        value = ReactifySlotOverride.fromJson(entry.value);
      } catch (error) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'A native slot override is invalid.',
          cause: error,
          context: {'instanceId': instanceId, 'slotId': entry.key},
        );
      }
      _mergeInto(target, entry.key, value);
    }
  }

  void _requireSlot(
    ReactifyCharacterDocument character,
    String slotId,
    String instanceId,
  ) {
    if (!character.slots.any((slot) => slot.id == slotId)) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'An override references an unknown native character slot.',
        context: {'instanceId': instanceId, 'slotId': slotId},
      );
    }
  }

  void _mergeInto(
    Map<String, ReactifySlotOverride> target,
    String slotId,
    ReactifySlotOverride value,
  ) {
    if (value.localTransform != null && !_validMatrix(value.localTransform!)) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'A native slot override contains a non-finite transform.',
        context: {'slotId': slotId},
      );
    }
    final base = target[slotId];
    target[slotId] = base == null
        ? value
        : ReactifySlotOverride(
            visible: value.visible ?? base.visible,
            localTransform: value.localTransform ?? base.localTransform,
            depth: value.depth ?? base.depth,
            asset: value.asset ?? base.asset,
            tintChannels: value.tintChannels ?? base.tintChannels,
            metadata: {...base.metadata, ...value.metadata},
          );
  }

  ({
    ReactifyCharacterDocument character,
    Map<String, ReactifySlotOverride> overrides,
  })
  _normalizeDepths(
    ReactifyCharacterDocument character,
    Map<String, ReactifySlotOverride> overrides,
  ) {
    final depths = <int>{for (final slot in character.slots) slot.depth};
    for (final slot in character.slots) {
      for (final value in slot.overrides.values) {
        if (value.depth != null) depths.add(value.depth!);
      }
    }
    for (final value in overrides.values) {
      if (value.depth != null) depths.add(value.depth!);
    }
    final ordered = depths.toList()..sort();
    final ranks = {
      for (var index = 0; index < ordered.length; index += 1)
        ordered[index]: index,
    };
    ReactifySlotOverride normalizeOverride(ReactifySlotOverride value) {
      return ReactifySlotOverride(
        visible: value.visible,
        localTransform: value.localTransform,
        depth: value.depth == null ? null : ranks[value.depth],
        asset: value.asset,
        tintChannels: value.tintChannels,
        metadata: value.metadata,
      );
    }

    return (
      character: character.copyWith(
        slots: [
          for (final slot in character.slots)
            slot.copyWith(
              depth: ranks[slot.depth],
              overrides: {
                for (final entry in slot.overrides.entries)
                  entry.key: normalizeOverride(entry.value),
              },
            ),
        ],
      ),
      overrides: {
        for (final entry in overrides.entries)
          entry.key: normalizeOverride(entry.value),
      },
    );
  }

  Future<_ResolvedMediaOverlay?> _resolveMediaOverlay(
    ReactionRenderRequest request,
    LayoutTemplate layout,
    ProjectCanvas canvas,
    ExportCancellationToken cancellation,
  ) async {
    final configuration = request.state.media;
    if (!request.includeMedia ||
        request.event?.clip.showMedia == false ||
        !configuration.visible ||
        configuration.assetId == null) {
      return null;
    }
    cancellation.throwIfCancelled();
    final assetId = configuration.assetId!;
    final asset = request.project.assets[assetId];
    if (asset == null || asset.missing || asset.uri.trim().isEmpty) {
      throw MediaFailure(
        code: MediaFailureCode.sourceMissing,
        message: 'The reacted-to media asset is missing.',
        context: {'stateId': request.state.id, 'assetId': assetId},
      );
    }
    final region = layout.mediaRegion;
    if (region == null) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Reacted-to media requires a layout media region.',
        context: {'stateId': request.state.id, 'layoutId': layout.id},
      );
    }
    final bounds = _mediaBounds(region, canvas, request.state.id);
    final crop =
        configuration.crop ??
        const NormalizedRect(left: 0, top: 0, width: 1, height: 1);
    _validateMediaCrop(crop, request.state.id);
    if (!configuration.opacity.isFinite ||
        configuration.opacity < 0 ||
        configuration.opacity > 1) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Reacted-to media opacity must be between zero and one.',
        context: {'stateId': request.state.id},
      );
    }
    final frameIdentity =
        request.mediaFrameIdentity ??
        _defaultMediaFrameIdentity(request, asset);
    final _MediaSurface surface;
    switch (asset.kind) {
      case ProjectAssetKind.image ||
          ProjectAssetKind.svg ||
          ProjectAssetKind.drawing:
        surface = await _staticMediaSurface(asset, canvas);
      case ProjectAssetKind.video:
        surface = await _videoMediaSurface(
          request,
          asset,
          frameIdentity,
          bounds,
          cancellation,
        );
      default:
        throw MediaFailure(
          code: MediaFailureCode.unsupportedFormat,
          message: 'The reacted-to media asset format is unsupported.',
          context: {'assetId': asset.id, 'kind': asset.kind.name},
        );
    }
    try {
      cancellation.throwIfCancelled();
      if (surface.width <= 0 ||
          surface.height <= 0 ||
          !surface.width.isFinite ||
          !surface.height.isFinite) {
        throw MediaFailure(
          code: MediaFailureCode.sourceUnreadable,
          message: 'The reacted-to media frame has invalid dimensions.',
          context: {'assetId': asset.id},
        );
      }
      return _ResolvedMediaOverlay(
        surface: surface,
        bounds: bounds,
        crop: crop,
        transform: _matrix(configuration.transform),
        opacity: configuration.opacity,
        frameIdentity: frameIdentity,
      );
    } catch (_) {
      surface.dispose();
      rethrow;
    }
  }

  Future<_MediaSurface> _staticMediaSurface(
    ProjectAsset asset,
    ProjectCanvas canvas,
  ) async {
    final sceneCharacters = <_LayeredSceneCharacter>[];
    final characters = <String, ReactifyCharacterDocument>{};
    _addAssetLayer(
      project: ReactifyProjectDocument(
        id: 'media-surface',
        name: 'Media Surface',
        canvasDefaults: canvas,
        assets: {asset.id: asset},
      ),
      assetId: asset.id,
      sceneId: 'media.${asset.id}',
      layer: 0,
      canvas: canvas,
      fitCanvas: false,
      sceneCharacters: sceneCharacters,
      nativeCharacters: characters,
    );
    final scene = ReactifySceneDocument(
      id: 'media.${asset.id}',
      name: asset.name,
      canvasSize: ui.Size(canvas.width.toDouble(), canvas.height.toDouble()),
      characters: [for (final entry in sceneCharacters) entry.character],
    );
    final resolved = await pngExporter.bridge.buildRenderableScene(
      scene,
      characters,
    );
    if (resolved.parts.length != 1) {
      throw MediaFailure(
        code: MediaFailureCode.sourceUnreadable,
        message: 'The reacted-to media asset did not resolve to one image.',
        context: {'assetId': asset.id},
      );
    }
    final part = resolved.parts.single;
    final prepared = resolved.assets[part.catalogPart.appAssetPath];
    if (prepared == null) {
      throw MediaFailure(
        code: MediaFailureCode.sourceUnreadable,
        message: 'The reacted-to media asset could not be prepared.',
        context: {'assetId': asset.id},
      );
    }
    return _PreparedMediaSurface(prepared, part);
  }

  Future<_MediaSurface> _videoMediaSurface(
    ReactionRenderRequest request,
    ProjectAsset asset,
    String frameIdentity,
    ui.Rect bounds,
    ExportCancellationToken cancellation,
  ) async {
    final resolver = mediaFrameResolver;
    if (resolver == null) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message: 'Video reaction media requires a configured frame resolver.',
        context: {'assetId': asset.id},
      );
    }
    final sourceFrame = request.event?.clip.range.start.frame ?? 0;
    final sourceTimestamp = _mediaTimestamp(request, sourceFrame);
    ReactionMediaFrame frame;
    try {
      frame = await resolver.resolve(
        ReactionMediaFrameRequest(
          asset: asset,
          frameIdentity: frameIdentity,
          sourceFrame: sourceFrame,
          sourceTimestamp: sourceTimestamp,
          targetWidth: bounds.width.ceil().clamp(1, 16384).toInt(),
          targetHeight: bounds.height.ceil().clamp(1, 16384).toInt(),
          event: request.event,
        ),
        cancellation,
      );
    } on MediaFailure {
      rethrow;
    } catch (error) {
      throw MediaFailure(
        code: MediaFailureCode.decodeFailed,
        message: 'The reacted-to video frame resolver failed.',
        cause: error,
        context: {'assetId': asset.id, 'frameIdentity': frameIdentity},
      );
    }
    cancellation.throwIfCancelled();
    if (frame.identity != frameIdentity || !_isPng(frame.pngBytes)) {
      throw MediaFailure(
        code: MediaFailureCode.decodeFailed,
        message: 'The reacted-to video resolver returned the wrong frame.',
        context: {
          'assetId': asset.id,
          'expectedIdentity': frameIdentity,
          'actualIdentity': frame.identity,
        },
      );
    }
    final codec = await ui.instantiateImageCodec(frame.pngBytes);
    try {
      final decoded = await codec.getNextFrame();
      return _ImageMediaSurface(decoded.image);
    } finally {
      codec.dispose();
    }
  }

  String _defaultMediaFrameIdentity(
    ReactionRenderRequest request,
    ProjectAsset asset,
  ) {
    if (asset.kind != ProjectAssetKind.video) {
      return ReactionContentKey.fromJsonValue({
        'assetId': asset.id,
        'contentHash': asset.contentHash,
        'uri': asset.uri,
      }).value;
    }
    final frame = request.event?.clip.range.start.frame ?? 0;
    final canvas = request.timeline?.canvas ?? request.project.canvasDefaults;
    final region = request.project.layouts[request.state.layoutId]?.mediaRegion;
    return ReactionContentKey.fromJsonValue({
      'assetId': asset.id,
      'contentHash': asset.contentHash,
      'uri': asset.uri,
      'frame': frame,
      'timestampMicroseconds': _mediaTimestamp(request, frame).inMicroseconds,
      'eventId': request.event?.eventId,
      'targetWidth': region == null
          ? null
          : (region.width * canvas.width).ceil(),
      'targetHeight': region == null
          ? null
          : (region.height * canvas.height).ceil(),
    }).value;
  }

  Duration _mediaTimestamp(ReactionRenderRequest request, int frame) {
    final rate = request.timeline?.frameRate;
    if (rate == null) return Duration.zero;
    return Duration(
      microseconds:
          frame *
          rate.denominator *
          Duration.microsecondsPerSecond ~/
          rate.numerator,
    );
  }

  ui.Rect _mediaBounds(
    NormalizedRect region,
    ProjectCanvas canvas,
    String stateId,
  ) {
    final values = [region.left, region.top, region.width, region.height];
    if (values.any((value) => !value.isFinite) ||
        region.left < 0 ||
        region.top < 0 ||
        region.width <= 0 ||
        region.height <= 0 ||
        region.left + region.width > 1 ||
        region.top + region.height > 1) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'The layout media region must be normalized and in bounds.',
        context: {'stateId': stateId},
      );
    }
    return ui.Rect.fromLTWH(
      region.left * canvas.width,
      region.top * canvas.height,
      region.width * canvas.width,
      region.height * canvas.height,
    );
  }

  void _validateMediaCrop(NormalizedRect crop, String stateId) {
    final values = [crop.left, crop.top, crop.width, crop.height];
    if (values.any((value) => !value.isFinite) ||
        crop.left < 0 ||
        crop.top < 0 ||
        crop.width <= 0 ||
        crop.height <= 0 ||
        crop.left + crop.width > 1 ||
        crop.top + crop.height > 1) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Reacted-to media crop must be normalized and in bounds.',
        context: {'stateId': stateId},
      );
    }
  }

  void _addAssetLayer({
    required ReactifyProjectDocument project,
    required String assetId,
    required String sceneId,
    required int layer,
    required ProjectCanvas canvas,
    required bool fitCanvas,
    required List<_LayeredSceneCharacter> sceneCharacters,
    required Map<String, ReactifyCharacterDocument> nativeCharacters,
  }) {
    final asset = project.assets[assetId];
    if (asset == null || asset.missing || asset.uri.trim().isEmpty) {
      throw MediaFailure(
        code: MediaFailureCode.sourceMissing,
        message: 'A reaction composition asset is missing.',
        context: {'assetId': assetId},
      );
    }
    final kind = switch (asset.kind) {
      ProjectAssetKind.svg => ReactifyAssetKind.svg,
      ProjectAssetKind.image => ReactifyAssetKind.raster,
      ProjectAssetKind.drawing => ReactifyAssetKind.drawing,
      _ => throw MediaFailure(
        code: MediaFailureCode.unsupportedFormat,
        message: 'A reaction composition asset has an unsupported format.',
        context: {'assetId': assetId, 'kind': asset.kind.name},
      ),
    };
    final width = _dimension(asset.metadata['width']);
    final height = _dimension(asset.metadata['height']);
    final assetTransform = fitCanvas && width != null && height != null
        ? AffineMatrix.scale(canvas.width / width, canvas.height / height)
        : const AffineMatrix.identity();
    final nativeKey = 'asset::$sceneId';
    nativeCharacters[nativeKey] = ReactifyCharacterDocument(
      id: nativeKey,
      name: asset.name,
      rig: const ReactifyRigTemplate(
        id: 'asset-layer-rig',
        name: 'Asset Layer',
        anchors: {
          'torso': ReactifyAnchor(
            id: 'torso',
            localTransform: AffineMatrix.identity(),
          ),
        },
      ),
      slots: [
        ReactifySlot(
          id: '$sceneId.slot',
          family: 'composition',
          kind: ReactifySlotKind.custom,
          anchorId: 'torso',
          localTransform: assetTransform,
          depth: 0,
          visible: true,
          asset: ReactifyAssetRef(
            id: asset.id,
            kind: kind,
            uri: asset.uri,
            source: 'project',
            dimensions: width == null || height == null
                ? null
                : ui.Size(width, height),
            metadata: asset.metadata,
          ),
          metadata: asset.metadata,
        ),
      ],
    );
    sceneCharacters.add(
      _LayeredSceneCharacter(
        layer: layer,
        sourceIndex: layer,
        character: ReactifySceneCharacter(
          id: sceneId,
          characterId: nativeKey,
          transform: const AffineMatrix.identity(),
        ),
      ),
    );
  }

  double? _dimension(Object? value) {
    if (value is num && value.isFinite && value > 0) return value.toDouble();
    return null;
  }

  AffineMatrix _matrix(AffineTransform value) {
    final components = [value.a, value.b, value.c, value.d, value.tx, value.ty];
    if (components.any((component) => !component.isFinite)) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'A reaction transform contains a non-finite value.',
      );
    }
    return AffineMatrix(
      a: value.a,
      b: value.b,
      c: value.c,
      d: value.d,
      tx: value.tx,
      ty: value.ty,
    );
  }

  bool _validMatrix(AffineMatrix value) {
    return [
      value.a,
      value.b,
      value.c,
      value.d,
      value.tx,
      value.ty,
    ].every((component) => component.isFinite);
  }

  ui.Color _color(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null || (normalized.length != 6 && normalized.length != 8)) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'The reaction canvas background color is invalid.',
        context: {'color': value},
      );
    }
    return ui.Color(normalized.length == 6 ? 0xff000000 | parsed : parsed);
  }

  bool _isPng(Uint8List bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index += 1) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }
}

class _LayeredSceneCharacter {
  const _LayeredSceneCharacter({
    required this.layer,
    required this.sourceIndex,
    required this.character,
  });

  final int layer;
  final int sourceIndex;
  final ReactifySceneCharacter character;
}

class _ResolvedMediaOverlay {
  const _ResolvedMediaOverlay({
    required this.surface,
    required this.bounds,
    required this.crop,
    required this.transform,
    required this.opacity,
    required this.frameIdentity,
  });

  final _MediaSurface surface;
  final ui.Rect bounds;
  final NormalizedRect crop;
  final AffineMatrix transform;
  final double opacity;
  final String frameIdentity;

  void paint(ui.Canvas canvas) {
    if (opacity <= 0) return;
    canvas.save();
    canvas.clipRect(bounds);
    canvas.transform(transform.toFloat64List());
    canvas.translate(bounds.left, bounds.top);
    canvas.scale(
      bounds.width / (crop.width * surface.width),
      bounds.height / (crop.height * surface.height),
    );
    canvas.translate(-crop.left * surface.width, -crop.top * surface.height);
    surface.paint(canvas, opacity);
    canvas.restore();
  }

  void dispose() {
    surface.dispose();
  }
}

abstract interface class _MediaSurface {
  double get width;

  double get height;

  void paint(ui.Canvas canvas, double opacity);

  void dispose();
}

class _PreparedMediaSurface implements _MediaSurface {
  const _PreparedMediaSurface(this.asset, this.part);

  final PreparedAsset asset;
  final ResolvedRenderPart part;

  @override
  double get width => asset.size.width;

  @override
  double get height => asset.size.height;

  @override
  void paint(ui.Canvas canvas, double opacity) {
    asset.paint(
      canvas,
      part.tintColor,
      tintStrength: part.tintStrength,
      opacity: part.opacity * opacity,
    );
  }

  @override
  void dispose() {}
}

class _ImageMediaSurface implements _MediaSurface {
  const _ImageMediaSurface(this.image);

  final ui.Image image;

  @override
  double get width => image.width.toDouble();

  @override
  double get height => image.height.toDouble();

  @override
  void paint(ui.Canvas canvas, double opacity) {
    canvas.drawImage(
      image,
      ui.Offset.zero,
      ui.Paint()
        ..color = ui.Color.fromARGB((opacity * 255).round(), 255, 255, 255),
    );
  }

  @override
  void dispose() {
    image.dispose();
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
