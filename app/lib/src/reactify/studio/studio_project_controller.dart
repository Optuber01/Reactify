import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../commands/commands.dart';
import '../io/io.dart';
import '../project/project.dart';

class StudioProjectController extends ChangeNotifier {
  StudioProjectController({
    ReactifyProjectDocument? initialProject,
    ProjectRepository? repository,
    this.autosaveDelay = const Duration(seconds: 20),
  }) : repository = repository ?? createProjectRepository(),
       _store = ProjectCommandStore(
         initialProject ?? buildReactionStudioTemplate(),
       ) {
    _projectWriter = SerializedProjectWriter(this.repository);
    _store.addListener(_handleStoreChange);
    selectedTimelineId = _store.project.timelines.keys.first;
    selectedReactionStateId = _store.project.reactionStates.keys.first;
    selectedCharacterId = _store.project.characters.isEmpty
        ? null
        : _store.project.characters.keys.first;
  }

  ProjectCommandStore _store;
  final ProjectRepository repository;
  late final SerializedProjectWriter _projectWriter;
  final Duration autosaveDelay;
  late TimelineId selectedTimelineId;
  late ReactionStateId selectedReactionStateId;
  CharacterId? selectedCharacterId;
  int playheadFrame = 0;
  int _stateSerial = 0;
  int _timelineSerial = 0;
  Timer? _autosaveTimer;
  String? _cleanProjectJson;
  ProjectChangeSummary? lastChange;
  String? projectLocation;
  bool isBusy = false;
  String workspaceStatus = 'Unsaved project';
  ProjectLoadSource? lastLoadSource;
  ProjectSaveMetadata? lastSaveMetadata;
  ProjectSaveMetadata? lastAutosaveMetadata;
  List<MissingMediaDiagnostic> missingMedia = const [];

  ReactifyProjectDocument get project => _store.project;
  ProjectTimeline get selectedTimeline =>
      project.timelines[selectedTimelineId]!;
  ReactionState get selectedReactionState =>
      project.reactionStates[selectedReactionStateId]!;
  bool get canUndo => _store.canUndo;
  bool get canRedo => _store.canRedo;
  bool get hasActiveDraft => _store.hasActiveDraft;
  bool get isDirty =>
      _cleanProjectJson == null ||
      project.toDeterministicJson() != _cleanProjectJson;
  bool get canSave => projectLocation != null && !isBusy;
  bool get recoveredProject =>
      lastLoadSource == ProjectLoadSource.backup ||
      lastLoadSource == ProjectLoadSource.autosave;

  void newProject({String name = 'Untitled Project'}) {
    final slug = _slug(name);
    final next = buildReactionStudioTemplate().copyWith(
      id: 'project.$slug.${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Untitled Project' : name.trim(),
      metadata: const {'template': 'reaction-studio'},
    );
    _installProject(next);
    projectLocation = null;
    _cleanProjectJson = null;
    lastLoadSource = null;
    lastSaveMetadata = null;
    lastAutosaveMetadata = null;
    missingMedia = const [];
    workspaceStatus = 'New unsaved project';
    notifyListeners();
  }

  Future<ProjectLoadResult> openProject(String location) async {
    return _withBusy(() async {
      final result = await repository.load(location);
      final recovered =
          result.source == ProjectLoadSource.backup ||
          result.source == ProjectLoadSource.autosave;
      _installLoadedProject(result, clean: !recovered);
      workspaceStatus = recovered
          ? 'Recovered ${result.source.name} copy'
          : 'Project opened';
      return result;
    });
  }

  Future<ProjectRecoveryResult> recoverProject(String location) async {
    return _withBusy(() async {
      final recovery = await repository.recover(location);
      _installLoadedProject(recovery.loadResult, clean: false);
      workspaceStatus = 'Recovery loaded; save to keep it';
      return recovery;
    });
  }

  Future<ProjectSaveResult> saveProject() async {
    final location = projectLocation;
    if (location == null) {
      throw const ProjectRepositoryException(
        'Choose a project location before saving.',
      );
    }
    return saveProjectAs(location);
  }

  Future<ProjectSaveResult> saveProjectAs(String location) async {
    return _withBusy(() async {
      final savingProject = project;
      final versionedResult = await _projectWriter.save(
        savingProject,
        location,
      );
      final result = versionedResult.result;
      projectLocation = location;
      _cleanProjectJson = versionedResult.project.toDeterministicJson();
      lastSaveMetadata = result.metadata;
      lastLoadSource = ProjectLoadSource.primary;
      _autosaveTimer?.cancel();
      if (isDirty) {
        workspaceStatus = 'Newer changes remain unsaved';
        _scheduleAutosave();
      } else {
        workspaceStatus = 'Saved';
      }
      return result;
    });
  }

  Future<ProjectAutosaveResult?> autosaveNow() async {
    final location = projectLocation;
    if (location == null || !isDirty || isBusy) return null;
    final result = await repository.autosave(project, location);
    lastAutosaveMetadata = result.metadata;
    workspaceStatus = 'Autosaved recovery copy';
    notifyListeners();
    return result;
  }

  void relinkMissingMedia(Map<AssetId, String> replacements) {
    final location = projectLocation;
    if (location == null) {
      throw const ProjectRepositoryException(
        'Save the project before relinking media.',
      );
    }
    if (replacements.isEmpty) return;
    final batch = const ProjectRelinkPlanner().prepare(
      project: project,
      projectLocation: location,
      replacements: replacements,
    );
    _store.executeBatch(batch);
    missingMedia = List.unmodifiable(
      missingMedia.where(
        (diagnostic) => !replacements.containsKey(diagnostic.assetId),
      ),
    );
    workspaceStatus = 'Media relinked';
    notifyListeners();
  }

  TimelineId createTimeline({String name = 'New Timeline'}) {
    _timelineSerial += 1;
    final id = _uniqueTimelineId('${_slug(name)}.$_timelineSerial');
    final source = selectedTimeline;
    final tracks = <TrackId, TimelineTrack>{};
    final trackOrder = <TrackId>[];
    for (var index = 0; index < source.trackOrder.length; index += 1) {
      final sourceTrack = source.tracks[source.trackOrder[index]]!;
      final trackId = '$id.track.${index + 1}';
      trackOrder.add(trackId);
      tracks[trackId] = sourceTrack.copyWith(
        id: trackId,
        order: index,
        clipOrder: const [],
        clips: const {},
      );
    }
    final timeline = ProjectTimeline(
      id: id,
      name: name.trim().isEmpty ? 'New Timeline' : name.trim(),
      canvas: source.canvas,
      frameRate: source.frameRate,
      durationFrames: source.durationFrames,
      trackOrder: trackOrder,
      tracks: tracks,
    );
    _store.execute(
      UpsertProjectEntityCommand(
        kind: ProjectEntityKind.timeline,
        entity: timeline,
      ),
    );
    selectTimeline(id);
    return id;
  }

  void renameTimeline(TimelineId id, String name) {
    final timeline = project.timelines[id];
    if (timeline == null) {
      throw ProjectCommandException('Timeline $id does not exist.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == timeline.name) return;
    _store.execute(
      UpsertProjectEntityCommand(
        kind: ProjectEntityKind.timeline,
        entity: timeline.copyWith(name: trimmed),
      ),
    );
  }

  TimelineId duplicateTimeline(TimelineId id, {String? name}) {
    final source = project.timelines[id];
    if (source == null) {
      throw ProjectCommandException('Timeline $id does not exist.');
    }
    _timelineSerial += 1;
    final newId = _uniqueTimelineId(
      '${_slug(source.name)}.copy.$_timelineSerial',
    );
    _store.execute(
      DuplicateTimelineCommand(
        sourceTimelineId: id,
        newTimelineId: newId,
        newName: name?.trim().isNotEmpty == true
            ? name!.trim()
            : '${source.name} Copy',
      ),
    );
    selectTimeline(newId);
    return newId;
  }

  void deleteTimeline(TimelineId id) {
    if (project.timelines.length == 1) {
      throw const ProjectCommandException(
        'A project must contain at least one timeline.',
      );
    }
    _store.execute(
      RemoveProjectEntityCommand(
        kind: ProjectEntityKind.timeline,
        entityId: id,
      ),
    );
  }

  TimelineId importTimelineJson(String source) {
    final decoded = jsonDecode(source);
    final timeline = ProjectTimeline.fromJson(jsonMap(decoded));
    if (project.timelines.containsKey(timeline.id)) {
      throw ProjectCommandException(
        'Timeline ${timeline.id} already exists in this project.',
      );
    }
    _store.execute(
      UpsertProjectEntityCommand(
        kind: ProjectEntityKind.timeline,
        entity: timeline,
      ),
    );
    selectTimeline(timeline.id);
    return timeline.id;
  }

  String exportTimelineJson([TimelineId? id]) {
    final timeline = project.timelines[id ?? selectedTimelineId];
    if (timeline == null) {
      throw ProjectCommandException(
        'Timeline ${id ?? selectedTimelineId} does not exist.',
      );
    }
    return '${const JsonEncoder.withIndent('  ').convert(canonicalJsonMap(timeline.toJson()))}\n';
  }

  Future<T> _withBusy<T>(Future<T> Function() operation) async {
    if (isBusy) {
      throw const ProjectRepositoryException(
        'Another project operation is already running.',
      );
    }
    isBusy = true;
    workspaceStatus = 'Working';
    notifyListeners();
    try {
      return await operation();
    } catch (_) {
      workspaceStatus = 'Operation failed';
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void _installLoadedProject(ProjectLoadResult result, {required bool clean}) {
    _installProject(result.project);
    projectLocation = result.location;
    _cleanProjectJson = clean ? result.project.toDeterministicJson() : null;
    lastLoadSource = result.source;
    lastSaveMetadata = null;
    lastAutosaveMetadata = null;
    missingMedia = List.unmodifiable(result.missingMedia);
  }

  void _installProject(ReactifyProjectDocument next) {
    _autosaveTimer?.cancel();
    _store.removeListener(_handleStoreChange);
    _store = ProjectCommandStore(next);
    _store.addListener(_handleStoreChange);
    selectedTimelineId = next.timelines.keys.first;
    selectedReactionStateId = next.reactionStates.keys.first;
    selectedCharacterId = next.characters.isEmpty
        ? null
        : next.characters.keys.first;
    playheadFrame = 0;
    lastChange = null;
  }

  TimelineId _uniqueTimelineId(String stem) {
    final prefix = 'timeline.$stem';
    var candidate = prefix;
    var suffix = 2;
    while (project.timelines.containsKey(candidate)) {
      candidate = '$prefix.$suffix';
      suffix += 1;
    }
    return candidate;
  }

  CharacterId _uniqueCharacterId(String stem) {
    final prefix = 'character.${_slug(stem)}';
    var candidate = prefix;
    var suffix = 2;
    while (project.characters.containsKey(candidate)) {
      candidate = '$prefix.$suffix';
      suffix += 1;
    }
    return candidate;
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    if (projectLocation == null || !isDirty) return;
    _autosaveTimer = Timer(autosaveDelay, () async {
      try {
        await autosaveNow();
      } catch (_) {
        workspaceStatus = 'Autosave failed';
        notifyListeners();
      }
    });
  }

  ProjectChangeSummary executeCommand(ProjectCommand command) {
    return _store.execute(command);
  }

  ProjectChangeSummary executeCommandBatch(ProjectCommandBatch batch) {
    return _store.executeBatch(batch);
  }

  void selectTimeline(TimelineId id) {
    if (!project.timelines.containsKey(id) || id == selectedTimelineId) return;
    selectedTimelineId = id;
    playheadFrame = 0;
    notifyListeners();
  }

  void selectReactionState(ReactionStateId id) {
    if (!project.reactionStates.containsKey(id) ||
        id == selectedReactionStateId) {
      return;
    }
    selectedReactionStateId = id;
    notifyListeners();
  }

  void selectCharacter(CharacterId id) {
    if (!project.characters.containsKey(id) || id == selectedCharacterId) {
      return;
    }
    selectedCharacterId = id;
    notifyListeners();
  }

  CharacterId addCharacter(CharacterResource resource) {
    final id = project.characters.containsKey(resource.id)
        ? _uniqueCharacterId(resource.name)
        : resource.id;
    final name = resource.name.trim().isEmpty
        ? 'Untitled Character'
        : resource.name.trim();
    final document = {...resource.document, 'id': id, 'name': name};
    _store.execute(
      UpsertProjectEntityCommand(
        kind: ProjectEntityKind.character,
        entity: resource.copyWith(id: id, name: name, document: document),
      ),
    );
    selectedCharacterId = id;
    notifyListeners();
    return id;
  }

  void updateCharacter(CharacterResource resource) {
    if (!project.characters.containsKey(resource.id)) {
      throw ProjectCommandException(
        'Character ${resource.id} does not exist in this project.',
      );
    }
    final name = resource.name.trim().isEmpty
        ? 'Untitled Character'
        : resource.name.trim();
    _store.execute(
      UpsertProjectEntityCommand(
        kind: ProjectEntityKind.character,
        entity: resource.copyWith(
          name: name,
          document: {...resource.document, 'id': resource.id, 'name': name},
        ),
      ),
    );
    selectedCharacterId = resource.id;
    notifyListeners();
  }

  CharacterId duplicateCharacter(CharacterId id, {String? name}) {
    final source = project.characters[id];
    if (source == null) {
      throw ProjectCommandException('Character $id does not exist.');
    }
    final duplicateName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : '${source.name} Copy';
    final duplicateId = _uniqueCharacterId(duplicateName);
    final duplicate = source.copyWith(
      id: duplicateId,
      name: duplicateName,
      document: {...source.document, 'id': duplicateId, 'name': duplicateName},
      metadata: {...source.metadata, 'duplicatedFromCharacterId': id},
    );
    _store.execute(
      UpsertProjectEntityCommand(
        kind: ProjectEntityKind.character,
        entity: duplicate,
      ),
    );
    selectedCharacterId = duplicateId;
    notifyListeners();
    return duplicateId;
  }

  void renameCharacter(CharacterId id, String name) {
    final source = project.characters[id];
    if (source == null) {
      throw ProjectCommandException('Character $id does not exist.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == source.name) {
      return;
    }
    updateCharacter(
      source.copyWith(
        name: trimmed,
        document: {...source.document, 'name': trimmed},
      ),
    );
  }

  void deleteCharacter(CharacterId id) {
    _store.execute(
      RemoveProjectEntityCommand(
        kind: ProjectEntityKind.character,
        entityId: id,
      ),
    );
    if (selectedCharacterId == id) {
      selectedCharacterId = project.characters.isEmpty
          ? null
          : project.characters.keys.first;
      notifyListeners();
    }
  }

  void setPlayhead(int frame) {
    final next = frame.clamp(0, selectedTimeline.durationFrames - 1);
    if (next == playheadFrame) return;
    playheadFrame = next;
    notifyListeners();
  }

  void setCharacterExpression(String instanceId, ExpressionId? expressionId) {
    _store.execute(
      UpdateReactionCharacterCommand(
        reactionStateId: selectedReactionStateId,
        instanceId: instanceId,
        expressionId: expressionId,
      ),
    );
  }

  void setCharacterPose(String instanceId, PoseId? poseId) {
    _store.execute(
      UpdateReactionCharacterCommand(
        reactionStateId: selectedReactionStateId,
        instanceId: instanceId,
        poseId: poseId,
      ),
    );
  }

  void setCharacterVisibility(String instanceId, bool visible) {
    _store.execute(
      UpdateReactionCharacterCommand(
        reactionStateId: selectedReactionStateId,
        instanceId: instanceId,
        visible: visible,
      ),
    );
  }

  void setCharacterTransform(String instanceId, AffineTransform? transform) {
    _store.execute(
      UpdateReactionCharacterCommand(
        reactionStateId: selectedReactionStateId,
        instanceId: instanceId,
        transform: transform,
      ),
    );
  }

  void applyExpressionToCharacters(
    Iterable<String> instanceIds,
    ExpressionId? expressionId,
  ) {
    _store.executeBatch(
      ProjectCommandBatch(
        label: 'Apply expression to selected characters',
        commands: [
          for (final instanceId in instanceIds)
            UpdateReactionCharacterCommand(
              reactionStateId: selectedReactionStateId,
              instanceId: instanceId,
              expressionId: expressionId,
            ),
        ],
      ),
    );
  }

  void applyExpressionNameToCharacters(
    Iterable<String> instanceIds,
    String expressionName,
  ) {
    final instances = {
      for (final instance in selectedReactionState.characters)
        instance.id: instance,
    };
    _store.executeBatch(
      ProjectCommandBatch(
        label: 'Apply $expressionName expression',
        commands: [
          for (final instanceId in instanceIds)
            if (instances[instanceId] case final instance?)
              UpdateReactionCharacterCommand(
                reactionStateId: selectedReactionStateId,
                instanceId: instanceId,
                expressionId:
                    'expression.${instance.characterId.split('.').last}.$expressionName',
              ),
        ],
      ),
    );
  }

  void duplicateCurrentState({int durationFrames = 90}) {
    final source = selectedReactionState;
    _stateSerial += 1;
    final id = '${source.id}.copy.$_stateSerial';
    final copy = source.copyWith(id: id, name: '${source.name} Copy');
    final reactionTrack = selectedTimeline.tracks.values.firstWhere(
      (track) => track.type == TimelineTrackType.reactionState,
    );
    final clip = ReactionTimelineClip(
      id: 'clip.$id',
      range: FrameRange(
        start: FrameTime(playheadFrame),
        duration: durationFrames.clamp(
          1,
          selectedTimeline.durationFrames - playheadFrame,
        ),
      ),
      reactionStateId: id,
    );
    _store.executeBatch(
      ProjectCommandBatch(
        label: 'Duplicate reaction state',
        commands: [
          UpsertProjectEntityCommand(
            kind: ProjectEntityKind.reactionState,
            entity: copy,
          ),
          InsertClipCommand(
            timelineId: selectedTimelineId,
            trackId: reactionTrack.id,
            clip: clip,
          ),
        ],
      ),
    );
    selectedReactionStateId = id;
    notifyListeners();
  }

  void undo() {
    _store.undo();
    _repairSelection();
  }

  void redo() {
    _store.redo();
    _repairSelection();
  }

  DraftRevisionState startDraft(String label) => _store.startDraft(label);

  ProjectChangeSummary applyDraft(ProjectCommand command) {
    return _store.applyDraft(command);
  }

  ProjectChangeSummary commitDraft() => _store.commitDraft();

  ProjectChangeSummary rollbackDraft() => _store.rollbackDraft();

  void _handleStoreChange(
    ReactifyProjectDocument project,
    ProjectChangeSummary summary,
  ) {
    lastChange = summary;
    _repairSelection();
    workspaceStatus = isDirty ? 'Unsaved changes' : 'All changes saved';
    _scheduleAutosave();
    notifyListeners();
  }

  void _repairSelection() {
    if (!project.timelines.containsKey(selectedTimelineId)) {
      selectedTimelineId = project.timelines.keys.first;
    }
    if (!project.reactionStates.containsKey(selectedReactionStateId)) {
      selectedReactionStateId = project.reactionStates.keys.first;
    }
    if (selectedCharacterId != null &&
        !project.characters.containsKey(selectedCharacterId)) {
      selectedCharacterId = project.characters.isEmpty
          ? null
          : project.characters.keys.first;
    }
    playheadFrame = playheadFrame.clamp(0, selectedTimeline.durationFrames - 1);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _store.removeListener(_handleStoreChange);
    super.dispose();
  }
}

String _slug(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('(^-+|-+\$)'), '');
  return normalized.isEmpty ? 'untitled' : normalized;
}

ReactifyProjectDocument buildReactionStudioTemplate() {
  const canvas = ProjectCanvas(width: 1920, height: 1080);
  const characterNames = <String>[];
  final characters = <CharacterId, CharacterResource>{};
  final expressions = <ExpressionId, ExpressionPreset>{};
  final poses = <PoseId, PosePreset>{};
  final placements = <LayoutPlacement>[];
  final instances = <ReactionCharacterInstance>[];
  for (var index = 0; index < characterNames.length; index++) {
    final name = characterNames[index];
    final slug = name.toLowerCase();
    final characterId = 'character.$slug';
    characters[characterId] = CharacterResource(
      id: characterId,
      name: name,
      document: const {},
      metadata: {'accent': _characterAccents[index]},
    );
    for (final expression in const ['neutral', 'happy', 'shock']) {
      final id = 'expression.$slug.$expression';
      expressions[id] = ExpressionPreset(
        id: id,
        name: '${expression[0].toUpperCase()}${expression.substring(1)}',
        characterId: characterId,
        semanticValues: {'expression': expression},
      );
    }
    final poseId = 'pose.$slug.default';
    poses[poseId] = PosePreset(
      id: poseId,
      name: 'Default',
      characterId: characterId,
    );
    final row = index < 3 ? 0 : 1;
    final column = index % 3;
    final placementId = 'placement.$slug';
    placements.add(
      LayoutPlacement(
        id: placementId,
        characterId: characterId,
        transform: AffineTransform(
          a: 0.82,
          d: 0.82,
          tx: 240 + column * 710,
          ty: row == 0 ? 120 : 720,
        ),
        layer: index,
      ),
    );
    instances.add(
      ReactionCharacterInstance(
        id: 'instance.$slug',
        characterId: characterId,
        expressionId: 'expression.$slug.neutral',
        poseId: poseId,
        layoutPlacementId: placementId,
        layer: index,
      ),
    );
  }

  const layout = LayoutTemplate(
    id: 'layout.shadow-slave-six',
    name: 'Shadow Slave Six Character',
    canvas: canvas,
    mediaRegion: NormalizedRect(
      left: 0.25,
      top: 0.22,
      width: 0.5,
      height: 0.48,
    ),
    textSafeRegions: [
      NormalizedRect(left: 0.08, top: 0.02, width: 0.84, height: 0.17),
    ],
  );
  final resolvedLayout = layout.copyWith(placements: placements);
  final states = <ReactionStateId, ReactionState>{
    'reaction.intro': ReactionState(
      id: 'reaction.intro',
      name: 'Intro Neutral',
      layoutId: resolvedLayout.id,
      characters: instances,
    ),
    'reaction.reveal': ReactionState(
      id: 'reaction.reveal',
      name: 'Reveal Shock',
      layoutId: resolvedLayout.id,
      characters: [
        for (var index = 0; index < instances.length; index++)
          instances[index].copyWith(
            expressionId:
                'expression.${characterNames[index].toLowerCase()}.${index.isEven ? 'shock' : 'happy'}',
          ),
      ],
    ),
    'reaction.resolve': ReactionState(
      id: 'reaction.resolve',
      name: 'Resolve',
      layoutId: resolvedLayout.id,
      characters: [
        for (var index = 0; index < instances.length; index++)
          instances[index].copyWith(
            expressionId:
                'expression.${characterNames[index].toLowerCase()}.${index == 2 ? 'shock' : 'neutral'}',
          ),
      ],
    ),
  };

  final textPresets = _templateTextPresets();
  final speakers = <SpeakerRuleId, SpeakerRule>{
    for (final name in const [
      'Cassie',
      'Nephis',
      'Kai',
      'Jet',
      'Sunny',
      'Effie',
    ])
      'speaker.${name.toLowerCase()}': SpeakerRule(
        id: 'speaker.${name.toLowerCase()}',
        speakerId: name.toLowerCase(),
        displayName: name,
        aliases: name == 'Cassie' ? const ['Cass'] : const [],
        textPresetId: 'text.all-character-dialogue',
        styleOverride: TextStyleSpec(
          fillColor:
              _characterAccents[const [
                'Cassie',
                'Nephis',
                'Kai',
                'Jet',
                'Sunny',
                'Effie',
              ].indexOf(name)],
        ),
      ),
    'speaker.default': const SpeakerRule(
      id: 'speaker.default',
      speakerId: 'default',
      displayName: 'Default',
      textPresetId: 'text.all-character-dialogue',
      isDefault: true,
    ),
  };

  const watermark = ProjectAsset(
    id: 'asset.watermark',
    name: 'Reactify Watermark',
    kind: ProjectAssetKind.svg,
    uri: 'reactify://watermark/default',
  );
  const editMedia = ProjectAsset(
    id: 'asset.edit-media',
    name: 'Imported Edit',
    kind: ProjectAssetKind.video,
    uri: 'missing://imported-edit',
    missing: true,
  );
  const editAudio = ProjectAsset(
    id: 'asset.edit-audio',
    name: 'Edit Audio',
    kind: ProjectAssetKind.audio,
    uri: 'missing://edit-audio',
    missing: true,
  );
  const vocals = ProjectAsset(
    id: 'asset.vocals',
    name: 'Replacement Vocals',
    kind: ProjectAssetKind.audio,
    uri: 'missing://replacement-vocals',
    missing: true,
  );
  const instrumental = ProjectAsset(
    id: 'asset.instrumental',
    name: 'Replacement Instrumental',
    kind: ProjectAssetKind.audio,
    uri: 'missing://replacement-instrumental',
    missing: true,
  );

  final tracks = _templateTracks(
    watermark: watermark,
    editMedia: editMedia,
    editAudio: editAudio,
    vocals: vocals,
    instrumental: instrumental,
  );
  final timeline = ProjectTimeline(
    id: 'timeline.public-part-1',
    name: 'Public Part 1',
    canvas: canvas,
    frameRate: RationalFrameRate(30, 1),
    durationFrames: 900,
    trackOrder: tracks.values
        .toList()
        .map((track) => track.id)
        .toList(growable: false),
    tracks: tracks,
    markers: const {
      'marker.intro': TimelineMarker(
        id: 'marker.intro',
        time: FrameTime(0),
        name: 'Intro',
        color: '#6EA8FE',
      ),
      'marker.reveal': TimelineMarker(
        id: 'marker.reveal',
        time: FrameTime(300),
        name: 'Reveal',
        color: '#FFCA6E',
      ),
    },
  );
  return ReactifyProjectDocument(
    id: 'project.shadow-slave-template',
    name: 'Shadow Slave Reaction',
    canvasDefaults: canvas,
    assets: {
      watermark.id: watermark,
      editMedia.id: editMedia,
      editAudio.id: editAudio,
      vocals.id: vocals,
      instrumental.id: instrumental,
    },
    characters: characters,
    expressions: expressions,
    poses: poses,
    layouts: {resolvedLayout.id: resolvedLayout},
    reactionStates: states,
    textPresets: textPresets,
    speakerRules: speakers,
    timelines: {timeline.id: timeline},
    metadata: const {'template': 'shadow-slave-public-part-1'},
  );
}

Map<TextPresetId, TextPreset> _templateTextPresets() {
  const dialogueStyle = TextStyleSpec(
    fontFamily: 'Roboto Condensed',
    fontSize: 46,
    fontWeight: 800,
    fillColor: '#FFFFFF',
    outlineColor: '#050505',
    outlineWidth: 4,
    shadow: TextShadowStyle(
      color: '#000000',
      offsetX: 4,
      offsetY: 4,
      softness: 2,
      opacity: 0.9,
    ),
    lineSpacing: 1.12,
    alignment: TextAlignment.center,
  );
  const definitions = [
    ('all-character-dialogue', 'All Character Dialogue', 'character-dialogue'),
    ('audience-talk', 'Audience Talk', 'viewer-text'),
    ('copyright-notice', 'Copyright Notice', 'copyright-notice'),
    (
      'copyright-notice-compact',
      'Copyright Notice Compact',
      'copyright-notice',
    ),
    ('members-disclaimer', 'Members Disclaimer and Shoutout', 'members'),
    ('quick-break', 'Quick Break', 'break'),
  ];
  return {
    for (final definition in definitions)
      'text.${definition.$1}': TextPreset(
        id: 'text.${definition.$1}',
        name: definition.$2,
        category: definition.$3,
        style: dialogueStyle,
      ),
  };
}

Map<TrackId, TimelineTrack> _templateTracks({
  required ProjectAsset watermark,
  required ProjectAsset editMedia,
  required ProjectAsset editAudio,
  required ProjectAsset vocals,
  required ProjectAsset instrumental,
}) {
  final reactionClips = <ClipId, TimelineClip>{
    'clip.reaction.intro': const ReactionTimelineClip(
      id: 'clip.reaction.intro',
      range: FrameRange(start: FrameTime(0), duration: 300),
      reactionStateId: 'reaction.intro',
    ),
    'clip.reaction.reveal': const ReactionTimelineClip(
      id: 'clip.reaction.reveal',
      range: FrameRange(start: FrameTime(300), duration: 300),
      reactionStateId: 'reaction.reveal',
    ),
    'clip.reaction.resolve': const ReactionTimelineClip(
      id: 'clip.reaction.resolve',
      range: FrameRange(start: FrameTime(600), duration: 300),
      reactionStateId: 'reaction.resolve',
    ),
  };
  final definitions = <TimelineTrack>[
    TimelineTrack(
      id: 'track.reaction.main',
      name: 'Main Reaction States',
      type: TimelineTrackType.reactionState,
      order: 0,
      clipOrder: reactionClips.keys.toList(),
      clips: reactionClips,
    ),
    const TimelineTrack(
      id: 'track.reaction.secondary',
      name: 'Secondary Reaction Overlay',
      type: TimelineTrackType.reactionState,
      order: 1,
    ),
    TimelineTrack(
      id: 'track.edit-media',
      name: 'Imported Edit',
      type: TimelineTrackType.video,
      order: 2,
      clipOrder: const ['clip.edit-media'],
      clips: {
        'clip.edit-media': VideoTimelineClip(
          id: 'clip.edit-media',
          range: const FrameRange(start: FrameTime(0), duration: 900),
          assetId: editMedia.id,
        ),
      },
    ),
    const TimelineTrack(
      id: 'track.dialogue',
      name: 'Character Dialogue',
      type: TimelineTrackType.richText,
      order: 3,
      clipOrder: ['clip.dialogue'],
      clips: {
        'clip.dialogue': RichTextTimelineClip(
          id: 'clip.dialogue',
          range: FrameRange(start: FrameTime(0), duration: 900),
          textPresetId: 'text.all-character-dialogue',
          lines: [
            DialogueLine(
              id: 'line.cassie',
              text: 'Kill them all...',
              speakerRuleId: 'speaker.cassie',
              sourcePrefix: 'Cassie',
            ),
            DialogueLine(
              id: 'line.kai',
              text: 'What do I even say to this...',
              speakerRuleId: 'speaker.kai',
              sourcePrefix: 'Kai',
            ),
          ],
        ),
      },
    ),
    const TimelineTrack(
      id: 'track.viewer-text',
      name: 'Viewer Notices',
      type: TimelineTrackType.richText,
      order: 4,
    ),
    TimelineTrack(
      id: 'track.watermark',
      name: 'Watermark',
      type: TimelineTrackType.watermark,
      order: 5,
      clipOrder: const ['clip.watermark'],
      clips: {
        'clip.watermark': WatermarkTimelineClip(
          id: 'clip.watermark',
          range: const FrameRange(start: FrameTime(0), duration: 900),
          assetId: watermark.id,
        ),
      },
    ),
    _audioTrack('track.audio.edit', 'Edit Audio', 6, editAudio.id, 0),
    _audioTrack('track.audio.vocals', 'Replacement Vocals', 7, vocals.id, -3),
    _audioTrack(
      'track.audio.instrumental',
      'Replacement Instrumental',
      8,
      instrumental.id,
      -6,
    ),
  ];
  return {for (final track in definitions) track.id: track};
}

TimelineTrack _audioTrack(
  String id,
  String name,
  int order,
  AssetId assetId,
  double volumeDb,
) {
  final clipId = 'clip.$id';
  return TimelineTrack(
    id: id,
    name: name,
    type: TimelineTrackType.audio,
    order: order,
    clipOrder: [clipId],
    clips: {
      clipId: AudioTimelineClip(
        id: clipId,
        range: const FrameRange(start: FrameTime(0), duration: 900),
        assetId: assetId,
        audio: AudioClipControls(gainDb: volumeDb),
      ),
    },
  );
}

const _characterAccents = [
  '#FFE082',
  '#FFF8E1',
  '#B3E5FC',
  '#FF8A80',
  '#B39DDB',
  '#A5D6A7',
];
