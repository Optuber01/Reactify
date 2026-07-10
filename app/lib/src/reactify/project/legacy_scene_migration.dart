import 'project_model.dart';
import 'project_time.dart';

abstract interface class LegacySceneMigrationHook {
  ReactifyProjectDocument migrate(
    Map<String, Object?> legacySceneJson, {
    required ProjectId projectId,
    required String projectName,
  });
}

class ReactifyLegacySceneMigrator implements LegacySceneMigrationHook {
  const ReactifyLegacySceneMigrator({
    this.defaultFrameRateNumerator = 30,
    this.defaultFrameRateDenominator = 1,
  });

  final int defaultFrameRateNumerator;
  final int defaultFrameRateDenominator;

  @override
  ReactifyProjectDocument migrate(
    Map<String, Object?> legacySceneJson, {
    required ProjectId projectId,
    required String projectName,
  }) {
    final scene = jsonMap(legacySceneJson['scene']);
    if (scene.isEmpty) {
      throw const FormatException('Legacy scene JSON has no scene object.');
    }
    final canvasJson = jsonMap(scene['canvasSize']);
    final canvas = ProjectCanvas(
      width: jsonDouble(canvasJson, 'width', fallback: 1200).round(),
      height: jsonDouble(canvasJson, 'height', fallback: 1200).round(),
    );
    final assets = <AssetId, ProjectAsset>{};
    for (final value in jsonList(legacySceneJson['assetRegistry'])) {
      final asset = _migrateAsset(jsonMap(value));
      assets[asset.id] = asset;
    }
    final backgroundJson = scene['background'] == null
        ? const <String, Object?>{}
        : jsonMap(scene['background']);
    final backgroundAssetJson = backgroundJson['asset'] == null
        ? const <String, Object?>{}
        : jsonMap(backgroundJson['asset']);
    ProjectAsset? backgroundAsset;
    if (backgroundAssetJson.isNotEmpty) {
      backgroundAsset = _migrateAsset(backgroundAssetJson);
      assets.putIfAbsent(backgroundAsset.id, () => backgroundAsset!);
    }

    final characters = <CharacterId, CharacterResource>{};
    for (final value in jsonList(legacySceneJson['characters'])) {
      final characterJson = jsonMap(value);
      final character = CharacterResource(
        id: jsonString(characterJson, 'id'),
        name: jsonString(
          characterJson,
          'name',
          fallback: jsonString(characterJson, 'id'),
        ),
        document: characterJson,
        legacyGachaCode: jsonNullableString(characterJson, 'legacyGachaCode'),
        metadata: {
          'migrationSource': 'reactify_native_scene_v1',
          ...jsonMetadata(characterJson['metadata']),
        },
      );
      characters[character.id] = character;
    }

    final sceneCharacters = jsonList(scene['characters']);
    final placements = <LayoutPlacement>[];
    final reactionCharacters = <ReactionCharacterInstance>[];
    for (var index = 0; index < sceneCharacters.length; index += 1) {
      final value = jsonMap(sceneCharacters[index]);
      final sceneCharacterId = jsonString(value, 'id');
      final characterId = jsonString(value, 'characterId');
      final transform = AffineTransform.fromJson(jsonMap(value['transform']));
      placements.add(
        LayoutPlacement(
          id: 'placement.$sceneCharacterId',
          characterId: characterId,
          transform: transform,
          layer: index,
        ),
      );
      reactionCharacters.add(
        ReactionCharacterInstance(
          id: sceneCharacterId,
          characterId: characterId,
          layoutPlacementId: 'placement.$sceneCharacterId',
          transform: transform,
          layer: index,
          slotOverrides: nestedJsonMap(value['slotOverrides']),
          metadata: {
            if (value['expression'] != null)
              'legacyExpression': value['expression'],
            if (value['pose'] != null) 'legacyPose': value['pose'],
            if (value['dialogue'] != null) 'legacyDialogue': value['dialogue'],
            ...jsonMetadata(value['metadata']),
          },
        ),
      );
    }

    final sceneId = jsonString(scene, 'id', fallback: 'legacy.scene');
    final layoutId = 'layout.$sceneId';
    final stateId = 'reaction.$sceneId';
    final timelineId = 'timeline.$sceneId';
    final trackId = 'track.$sceneId.reaction';
    final clipId = 'clip.$sceneId.reaction';
    final layout = LayoutTemplate(
      id: layoutId,
      name: '${jsonString(scene, 'name', fallback: projectName)} Layout',
      canvas: canvas,
      backgroundAssetId: backgroundAsset?.id,
      placements: placements,
      metadata: {
        'legacyCameraTransform': jsonMap(scene['cameraTransform']),
        'legacyBackground': backgroundJson,
        'migrationSource': 'reactify_native_scene_v1',
      },
    );
    final state = ReactionState(
      id: stateId,
      name: jsonString(scene, 'name', fallback: projectName),
      layoutId: layout.id,
      characters: reactionCharacters,
      backgroundAssetId: backgroundAsset?.id,
      metadata: const {'migrationSource': 'reactify_native_scene_v1'},
    );
    final clip = ReactionTimelineClip(
      id: clipId,
      range: const FrameRange(start: FrameTime(0), duration: 1),
      reactionStateId: state.id,
    );
    final track = TimelineTrack(
      id: trackId,
      name: 'Reaction States',
      type: TimelineTrackType.reactionState,
      order: 0,
      clipOrder: [clip.id],
      clips: {clip.id: clip},
    );
    final timeline = ProjectTimeline(
      id: timelineId,
      name: jsonString(scene, 'name', fallback: projectName),
      canvas: canvas,
      frameRate: RationalFrameRate(
        defaultFrameRateNumerator,
        defaultFrameRateDenominator,
      ),
      durationFrames: 1,
      trackOrder: [track.id],
      tracks: {track.id: track},
    );
    return ReactifyProjectDocument(
      id: projectId,
      name: projectName,
      canvasDefaults: canvas,
      assets: assets,
      characters: characters,
      layouts: {layout.id: layout},
      reactionStates: {state.id: state},
      timelines: {timeline.id: timeline},
      metadata: {
        'legacySchemaVersion': legacySceneJson['schemaVersion'],
        'legacySelectedSceneCharacterId':
            legacySceneJson['selectedSceneCharacterId'],
        'migrationSource': 'reactify_native_scene_v1',
      },
    );
  }

  ProjectAsset _migrateAsset(Map<String, Object?> json) {
    final id = jsonString(json, 'id');
    final legacyKind = jsonString(json, 'kind', fallback: 'unknown');
    final metadata = jsonMetadata(json['metadata']);
    return ProjectAsset(
      id: id,
      name: metadata['label'] is String ? metadata['label']! as String : id,
      kind: switch (legacyKind) {
        'svg' || 'vector' => ProjectAssetKind.svg,
        'png' || 'raster' => ProjectAssetKind.image,
        'drawing' => ProjectAssetKind.drawing,
        _ => ProjectAssetKind.unknown,
      },
      uri: jsonString(json, 'uri'),
      metadata: {
        'legacyAssetKind': legacyKind,
        'legacyPreserveVector': json['preserveVector'],
        'legacyDimensions': json['dimensions'],
        'migrationSource': 'reactify_native_scene_v1',
        ...metadata,
      },
    );
  }
}
