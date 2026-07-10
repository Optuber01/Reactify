import '../media/media.dart';
import '../project/project.dart';
import 'reaction_dialogue_selection.dart';
import 'reaction_export_models.dart';

class ReactionExportPlanner {
  const ReactionExportPlanner();

  ReactionExportPlan build(ReactionExportRequest request) {
    request.options.validate();
    final timeline = _resolveTimeline(request);
    final selection = request.selection;
    final events = switch (selection) {
      AllReactionEventsSelection() => _timelineEvents(timeline!),
      TimelineFrameRangeSelection(:final range) => _timelineEvents(
        timeline!,
      ).where((event) => event.clip.range.overlaps(range)).toList(),
      SelectedCharactersSelection(:final characterIds) =>
        _timelineEvents(timeline!).where((event) {
          final state =
              request.project.reactionStates[event.clip.reactionStateId];
          return state != null &&
              state.characters.any(
                (character) => characterIds.contains(character.characterId),
              );
        }).toList(),
      UniqueReactionStatesSelection() ||
      SelectedReactionStatesSelection() => const <ReactionExportEvent>[],
    };
    final stateCandidates = _stateCandidates(request, timeline, events);
    final artifactByKey = <String, ReactionRenderArtifactPlan>{};
    final canonicalByKey = <String, String>{};
    final manifestEntries = <ReactionExportManifestEntry>[];
    final materializations = <ReactionMaterializationPlan>[];

    if (events.isNotEmpty) {
      for (final event in events) {
        final state =
            request.project.reactionStates[event.clip.reactionStateId];
        if (state == null) {
          throw MediaFailure(
            code: MediaFailureCode.invalidRequest,
            message: 'A reaction event references a missing state.',
            context: {
              'eventId': event.eventId,
              'stateId': event.clip.reactionStateId,
            },
          );
        }
        final characterIds = _effectiveCharacterIds(request, state);
        final includeDialogue =
            request.options.includeDialogue && event.clip.showDialogue;
        final includeMedia =
            request.options.includeMedia && event.clip.showMedia;
        final effective = _effectiveContent(
          request: request,
          timeline: timeline,
          state: state,
          event: event,
          characterIds: characterIds,
          includeDialogue: includeDialogue,
          includeMedia: includeMedia,
        );
        final artifact = _artifactFor(
          request: request,
          timeline: timeline,
          state: state,
          event: event,
          characterIds: characterIds,
          includeDialogue: includeDialogue,
          includeMedia: includeMedia,
          effectiveContent: effective,
          artifacts: artifactByKey,
          canonicalByKey: canonicalByKey,
        );
        final eventFile = request.options.materializeEventFiles
            ? _eventFileName(request.options, event, artifact.contentKey)
            : null;
        if (eventFile != null) {
          materializations.add(
            ReactionMaterializationPlan(
              id: event.eventId,
              contentKey: artifact.contentKey,
              fileName: eventFile,
              eventId: event.eventId,
            ),
          );
        }
        manifestEntries.add(
          ReactionExportManifestEntry(
            stateId: state.id,
            contentKey: artifact.contentKey,
            renderFile: artifact.fileName,
            characterIds: characterIds,
            eventId: event.eventId,
            timelineId: event.timelineId,
            trackId: event.trackId,
            clipId: event.clip.id,
            startFrame: event.clip.range.start.frame,
            durationFrames: event.clip.range.duration,
            timestampMicroseconds: _timestampMicroseconds(
              event.clip.range.start.frame,
              timeline!.frameRate,
            ),
            eventFile: eventFile,
          ),
        );
      }
    } else {
      for (final state in stateCandidates) {
        final characterIds = _effectiveCharacterIds(request, state);
        final effective = _effectiveContent(
          request: request,
          timeline: timeline,
          state: state,
          characterIds: characterIds,
          includeDialogue: request.options.includeDialogue,
          includeMedia: request.options.includeMedia,
        );
        final artifact = _artifactFor(
          request: request,
          timeline: timeline,
          state: state,
          characterIds: characterIds,
          includeDialogue: request.options.includeDialogue,
          includeMedia: request.options.includeMedia,
          effectiveContent: effective,
          artifacts: artifactByKey,
          canonicalByKey: canonicalByKey,
        );
        manifestEntries.add(
          ReactionExportManifestEntry(
            stateId: state.id,
            contentKey: artifact.contentKey,
            renderFile: artifact.fileName,
            characterIds: characterIds,
          ),
        );
      }
    }

    final artifacts = artifactByKey.values.toList()
      ..sort((left, right) => left.contentKey.compareTo(right.contentKey));
    manifestEntries.sort(_compareManifestEntries);
    materializations.sort((left, right) => left.id.compareTo(right.id));
    final manifest = ReactionExportManifest(
      projectId: request.project.id,
      timelineId: timeline?.id,
      selection: request.selection,
      options: request.options,
      frameRate: timeline?.frameRate,
      entries: manifestEntries,
      artifacts: artifacts,
    );
    return ReactionExportPlan(
      request: request,
      timeline: timeline,
      artifacts: artifacts,
      materializations: materializations,
      manifest: manifest,
    );
  }

  ProjectTimeline? _resolveTimeline(ReactionExportRequest request) {
    final requiresTimeline =
        request.selection is AllReactionEventsSelection ||
        request.selection is TimelineFrameRangeSelection ||
        request.selection is SelectedCharactersSelection;
    final id = request.timelineId;
    if (id == null) {
      if (requiresTimeline) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'The selected export mode requires a timeline.',
        );
      }
      return null;
    }
    final timeline = request.project.timelines[id];
    if (timeline == null) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'The requested export timeline does not exist.',
        context: {'timelineId': id},
      );
    }
    if (request.selection case TimelineFrameRangeSelection(:final range)) {
      if (range.endExclusive.frame > timeline.durationFrames) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'The selected export range exceeds the timeline.',
        );
      }
    }
    if (request.selection case SelectedCharactersSelection(
      :final characterIds,
    )) {
      if (characterIds.isEmpty ||
          characterIds.any(
            (characterId) =>
                !request.project.characters.containsKey(characterId),
          )) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'Selected character IDs must exist and cannot be empty.',
        );
      }
    }
    return timeline;
  }

  List<ReactionState> _stateCandidates(
    ReactionExportRequest request,
    ProjectTimeline? timeline,
    List<ReactionExportEvent> events,
  ) {
    final selection = request.selection;
    if (selection is SelectedReactionStatesSelection) {
      if (selection.stateIds.isEmpty ||
          selection.stateIds.any(
            (stateId) => !request.project.reactionStates.containsKey(stateId),
          )) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'Selected state IDs must exist and cannot be empty.',
        );
      }
      return [
        for (final id in selection.stateIds.toList()..sort())
          request.project.reactionStates[id]!,
      ];
    }
    if (selection is UniqueReactionStatesSelection) {
      final ids = timeline == null
          ? request.project.reactionStates.keys.toSet()
          : _timelineEvents(
              timeline,
            ).map((event) => event.clip.reactionStateId).toSet();
      final states = <ReactionState>[];
      for (final id in ids.toList()..sort()) {
        final state = request.project.reactionStates[id];
        if (state != null) states.add(state);
      }
      return states;
    }
    final states = <ReactionState>[];
    for (final id
        in events.map((event) => event.clip.reactionStateId).toSet()) {
      final state = request.project.reactionStates[id];
      if (state != null) states.add(state);
    }
    return states;
  }

  List<ReactionExportEvent> _timelineEvents(ProjectTimeline timeline) {
    final orderedTrackIds = <TrackId>[
      for (final id in timeline.trackOrder)
        if (timeline.tracks.containsKey(id)) id,
      ...timeline.tracks.keys
          .where((id) => !timeline.trackOrder.contains(id))
          .toList()
        ..sort((left, right) {
          final leftTrack = timeline.tracks[left]!;
          final rightTrack = timeline.tracks[right]!;
          final order = leftTrack.order.compareTo(rightTrack.order);
          return order != 0 ? order : left.compareTo(right);
        }),
    ];
    final trackRanks = {
      for (var index = 0; index < orderedTrackIds.length; index += 1)
        orderedTrackIds[index]: index,
    };
    final events = <ReactionExportEvent>[];
    for (final trackId in orderedTrackIds) {
      final track = timeline.tracks[trackId]!;
      if (track.type != TimelineTrackType.reactionState ||
          !track.enabled ||
          !track.visible) {
        continue;
      }
      final orderedClipIds = <ClipId>[
        for (final id in track.clipOrder)
          if (track.clips.containsKey(id)) id,
        ...track.clips.keys
            .where((id) => !track.clipOrder.contains(id))
            .toList()
          ..sort(),
      ];
      for (final clipId in orderedClipIds) {
        final clip = track.clips[clipId];
        if (clip is ReactionTimelineClip && clip.enabled) {
          events.add(
            ReactionExportEvent(
              timelineId: timeline.id,
              trackId: track.id,
              clip: clip,
            ),
          );
        }
      }
    }
    events.sort((left, right) {
      var result = left.clip.range.start.compareTo(right.clip.range.start);
      if (result != 0) return result;
      result = trackRanks[left.trackId]!.compareTo(trackRanks[right.trackId]!);
      if (result != 0) return result;
      return left.clip.id.compareTo(right.clip.id);
    });
    return events;
  }

  List<CharacterId> _effectiveCharacterIds(
    ReactionExportRequest request,
    ReactionState state,
  ) {
    final selected = request.selection is SelectedCharactersSelection
        ? (request.selection as SelectedCharactersSelection).characterIds
        : null;
    final ids = <CharacterId>[];
    for (final character in state.characters) {
      if ((selected == null || selected.contains(character.characterId)) &&
          !ids.contains(character.characterId)) {
        ids.add(character.characterId);
      }
    }
    return ids;
  }

  String _effectiveContent({
    required ReactionExportRequest request,
    required ProjectTimeline? timeline,
    required ReactionState state,
    required Iterable<CharacterId> characterIds,
    required bool includeDialogue,
    required bool includeMedia,
    ReactionExportEvent? event,
  }) {
    final selected = characterIds.toSet();
    final characterEntries = <Object?>[];
    for (final instance in state.characters) {
      if (!selected.contains(instance.characterId)) continue;
      final instanceJson = Map<String, Object?>.from(instance.toJson())
        ..remove('id')
        ..remove('metadata');
      characterEntries.add({
        'instance': instanceJson,
        'character': _resourceJson(
          request.project.characters[instance.characterId]?.toJson(),
        ),
        'expression': _resourceJson(
          request.project.expressions[instance.expressionId]?.toJson(),
        ),
        'pose': _resourceJson(request.project.poses[instance.poseId]?.toJson()),
      });
    }
    final layout = _resourceJson(
      request.project.layouts[state.layoutId]?.toJson(),
    );
    final background =
        request.options.composition == ReactionExportComposition.composited &&
            state.backgroundAssetId != null
        ? _resourceJson(
            request.project.assets[state.backgroundAssetId]?.toJson(),
          )
        : null;
    final media = includeMedia
        ? {
            'configuration': state.media.toJson(),
            'asset': _resourceJson(
              request.project.assets[state.media.assetId]?.toJson(),
            ),
          }
        : null;
    final payload = {
      'background': background,
      'canvas': (timeline?.canvas ?? request.project.canvasDefaults).toJson(),
      'characters': characterEntries,
      'clipVisual': event?.clip.visual.toJson(),
      'composition': request.options.composition.name,
      'dialogue': includeDialogue
          ? {
              'state': state.dialogueMetadata,
              'clips': [
                if (timeline != null && event != null)
                  for (final active in activeReactionDialogueClips(
                    timeline,
                    event,
                  ))
                    {'trackId': active.track.id, 'clip': active.clip.toJson()},
              ],
            }
          : null,
      'includeDialogue': includeDialogue,
      'includeMedia': includeMedia,
      'layout': layout,
      'layoutOverrides': timeline?.layoutOverrides,
      'media': media,
      'speakerRules': includeDialogue
          ? {
              for (final entry in request.project.speakerRules.entries)
                entry.key: entry.value.toJson(),
            }
          : null,
      'stateMetadata': state.metadata,
      'styleOverrides': includeDialogue ? timeline?.styleOverrides : null,
      'textPresets': includeDialogue
          ? {
              for (final entry in request.project.textPresets.entries)
                entry.key: entry.value.toJson(),
            }
          : null,
    };
    return encodeCanonicalJson(payload);
  }

  ReactionRenderArtifactPlan _artifactFor({
    required ReactionExportRequest request,
    required ProjectTimeline? timeline,
    required ReactionState state,
    required Iterable<CharacterId> characterIds,
    required bool includeDialogue,
    required bool includeMedia,
    required String effectiveContent,
    required Map<String, ReactionRenderArtifactPlan> artifacts,
    required Map<String, String> canonicalByKey,
    ReactionExportEvent? event,
  }) {
    final baseKey = ReactionContentKey.fromCanonicalJson(
      effectiveContent,
    ).value;
    var key = baseKey;
    var collision = 1;
    while (canonicalByKey.containsKey(key) &&
        canonicalByKey[key] != effectiveContent) {
      collision += 1;
      key = '$baseKey-c$collision';
    }
    canonicalByKey[key] = effectiveContent;
    return artifacts.putIfAbsent(
      key,
      () => ReactionRenderArtifactPlan(
        contentKey: key,
        stateId: state.id,
        fileName: '${request.options.filePrefix}_$key.png',
        canonicalContent: effectiveContent,
        renderRequest: ReactionRenderRequest(
          project: request.project,
          state: state,
          contentKey: key,
          composition: request.options.composition,
          includeDialogue: includeDialogue,
          includeMedia: includeMedia,
          characterIds: characterIds,
          timeline: timeline,
          event: event,
        ),
      ),
    );
  }

  Map<String, Object?>? _resourceJson(Map<String, Object?>? source) {
    if (source == null) return null;
    return Map<String, Object?>.from(source)
      ..remove('id')
      ..remove('name')
      ..remove('metadata');
  }

  static int _compareManifestEntries(
    ReactionExportManifestEntry left,
    ReactionExportManifestEntry right,
  ) {
    var result = (left.startFrame ?? -1).compareTo(right.startFrame ?? -1);
    if (result != 0) return result;
    result = (left.eventId ?? '').compareTo(right.eventId ?? '');
    if (result != 0) return result;
    return left.stateId.compareTo(right.stateId);
  }

  static int _timestampMicroseconds(int frame, RationalFrameRate rate) {
    return frame *
        rate.denominator *
        Duration.microsecondsPerSecond ~/
        rate.numerator;
  }

  static String _eventFileName(
    ReactionExportOptions options,
    ReactionExportEvent event,
    String contentKey,
  ) {
    final frame = event.clip.range.start.frame.toString().padLeft(10, '0');
    final track = _slug(event.trackId);
    final clip = _slug(event.clip.id);
    final eventKey = ReactionContentKey.fromJsonValue(event.eventId).value;
    return '${options.filePrefix}_event_${frame}_${track}_${clip}_${eventKey}_$contentKey.png';
  }

  static String _slug(String value) {
    var slug = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'item' : slug;
  }
}
