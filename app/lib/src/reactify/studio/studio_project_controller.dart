import 'package:flutter/foundation.dart';

import '../commands/commands.dart';
import '../project/project.dart';

class StudioProjectController extends ChangeNotifier {
  StudioProjectController({ReactifyProjectDocument? initialProject})
    : _store = ProjectCommandStore(
        initialProject ?? buildReactionStudioTemplate(),
      ) {
    _store.addListener(_handleStoreChange);
    selectedTimelineId = _store.project.timelines.keys.first;
    selectedReactionStateId = _store.project.reactionStates.keys.first;
  }

  final ProjectCommandStore _store;
  late TimelineId selectedTimelineId;
  late ReactionStateId selectedReactionStateId;
  int playheadFrame = 0;
  int _stateSerial = 0;
  ProjectChangeSummary? lastChange;

  ReactifyProjectDocument get project => _store.project;
  ProjectTimeline get selectedTimeline =>
      project.timelines[selectedTimelineId]!;
  ReactionState get selectedReactionState =>
      project.reactionStates[selectedReactionStateId]!;
  bool get canUndo => _store.canUndo;
  bool get canRedo => _store.canRedo;
  bool get hasActiveDraft => _store.hasActiveDraft;

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
    notifyListeners();
  }

  void _repairSelection() {
    if (!project.timelines.containsKey(selectedTimelineId)) {
      selectedTimelineId = project.timelines.keys.first;
    }
    if (!project.reactionStates.containsKey(selectedReactionStateId)) {
      selectedReactionStateId = project.reactionStates.keys.first;
    }
    playheadFrame = playheadFrame.clamp(0, selectedTimeline.durationFrames - 1);
  }

  @override
  void dispose() {
    _store.removeListener(_handleStoreChange);
    super.dispose();
  }
}

ReactifyProjectDocument buildReactionStudioTemplate() {
  const canvas = ProjectCanvas(width: 1920, height: 1080);
  const characterNames = ['Cassie', 'Nephis', 'Kai', 'Jet', 'Sunny', 'Effie'];
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
      document: const {'schemaVersion': 1, 'source': 'template'},
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
    for (final name in characterNames)
      'speaker.${name.toLowerCase()}': SpeakerRule(
        id: 'speaker.${name.toLowerCase()}',
        speakerId: name.toLowerCase(),
        displayName: name,
        aliases: name == 'Cassie' ? const ['Cass'] : const [],
        textPresetId: 'text.all-character-dialogue',
        styleOverride: TextStyleSpec(
          fillColor: _characterAccents[characterNames.indexOf(name)],
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
    fontFamily: 'Arial Narrow',
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
