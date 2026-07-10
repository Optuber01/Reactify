import '../project/project.dart';
import 'project_command.dart';
import 'project_entity_commands.dart';

class AddTrackCommand implements ProjectCommand {
  const AddTrackCommand({
    required this.timelineId,
    required this.track,
    this.orderIndex,
  });

  final TimelineId timelineId;
  final TimelineTrack track;
  final int? orderIndex;

  factory AddTrackCommand.fromJson(Map<String, Object?> json) {
    return AddTrackCommand(
      timelineId: jsonString(json, 'timelineId'),
      track: TimelineTrack.fromJson(jsonMap(json['track'])),
      orderIndex: jsonNullableInt(json, 'orderIndex'),
    );
  }

  @override
  String get type => 'track.add';

  @override
  String get summary => 'Add track ${track.id}';

  @override
  Set<String> get affectedIds => {timelineId, track.id};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final timeline = _timeline(project, timelineId);
    if (timeline.tracks.containsKey(track.id)) {
      throw duplicateEntity('track', track.id);
    }
    for (final clip in track.clips.values) {
      _validateClipControls(clip);
    }
    final order = [...timeline.trackOrder];
    final index = orderIndex ?? order.length;
    if (index < 0 || index > order.length) {
      throw const ProjectCommandException('Track order index is out of range.');
    }
    order.insert(index, track.id);
    final tracks = <TrackId, TimelineTrack>{
      ...timeline.tracks,
      track.id: track,
    };
    for (var trackIndex = 0; trackIndex < order.length; trackIndex += 1) {
      final current = tracks[order[trackIndex]]!;
      tracks[current.id] = current.copyWith(order: trackIndex);
    }
    return _replaceTimeline(
      project,
      timeline.copyWith(tracks: tracks, trackOrder: order),
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    return RemoveTrackCommand(timelineId: timelineId, trackId: track.id);
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'timelineId': timelineId,
    'track': track.toJson(),
    if (orderIndex != null) 'orderIndex': orderIndex,
    'type': type,
  });
}

class RemoveTrackCommand implements ProjectCommand {
  const RemoveTrackCommand({required this.timelineId, required this.trackId});

  final TimelineId timelineId;
  final TrackId trackId;

  factory RemoveTrackCommand.fromJson(Map<String, Object?> json) {
    return RemoveTrackCommand(
      timelineId: jsonString(json, 'timelineId'),
      trackId: jsonString(json, 'trackId'),
    );
  }

  @override
  String get type => 'track.remove';

  @override
  String get summary => 'Remove track $trackId';

  @override
  Set<String> get affectedIds => {timelineId, trackId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final timeline = _timeline(project, timelineId);
    final track = timeline.tracks[trackId];
    if (track == null) {
      throw missingEntity('track', trackId);
    }
    final removedClipIds = track.clips.keys.toSet();
    final references = ProjectReferenceIndex.forProject(project).references;
    final external = references.where(
      (reference) =>
          reference.targetKind == ProjectReferenceKind.clip &&
          removedClipIds.contains(reference.targetId) &&
          !removedClipIds.contains(reference.sourceId),
    );
    if (external.isNotEmpty) {
      throw ProjectCommandException(
        'Cannot remove track $trackId because one or more clips are externally linked.',
      );
    }
    final tracks = {...timeline.tracks}..remove(trackId);
    final order = timeline.trackOrder.where((id) => id != trackId).toList();
    for (var index = 0; index < order.length; index += 1) {
      final current = tracks[order[index]]!;
      tracks[current.id] = current.copyWith(order: index);
    }
    return _replaceTimeline(
      project,
      timeline.copyWith(tracks: tracks, trackOrder: order),
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    final track = _timeline(project, timelineId).tracks[trackId];
    if (track == null) {
      throw missingEntity('track', trackId);
    }
    return AddTrackCommand(
      timelineId: timelineId,
      track: track,
      orderIndex: _timeline(project, timelineId).trackOrder.indexOf(trackId),
    );
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'timelineId': timelineId,
    'trackId': trackId,
    'type': type,
  });
}

class ReorderTracksCommand implements ProjectCommand {
  const ReorderTracksCommand({
    required this.timelineId,
    required this.trackOrder,
  });

  final TimelineId timelineId;
  final List<TrackId> trackOrder;

  factory ReorderTracksCommand.fromJson(Map<String, Object?> json) {
    return ReorderTracksCommand(
      timelineId: jsonString(json, 'timelineId'),
      trackOrder: stringList(json['trackOrder']),
    );
  }

  @override
  String get type => 'track.reorder';

  @override
  String get summary => 'Reorder tracks in $timelineId';

  @override
  Set<String> get affectedIds => {timelineId, ...trackOrder};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final timeline = _timeline(project, timelineId);
    if (!_sameIds(trackOrder, timeline.tracks.keys)) {
      throw const ProjectCommandException(
        'Track order must contain every track exactly once.',
      );
    }
    final tracks = <TrackId, TimelineTrack>{};
    for (var index = 0; index < trackOrder.length; index += 1) {
      final track = timeline.tracks[trackOrder[index]]!;
      tracks[track.id] = track.copyWith(order: index);
    }
    return _replaceTimeline(
      project,
      timeline.copyWith(trackOrder: trackOrder, tracks: tracks),
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    return ReorderTracksCommand(
      timelineId: timelineId,
      trackOrder: _timeline(project, timelineId).trackOrder,
    );
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'timelineId': timelineId,
    'trackOrder': trackOrder,
    'type': type,
  });
}

class InsertClipCommand implements ProjectCommand {
  const InsertClipCommand({
    required this.timelineId,
    required this.trackId,
    required this.clip,
    this.orderIndex,
  });

  final TimelineId timelineId;
  final TrackId trackId;
  final TimelineClip clip;
  final int? orderIndex;

  factory InsertClipCommand.fromJson(Map<String, Object?> json) {
    return InsertClipCommand(
      timelineId: jsonString(json, 'timelineId'),
      trackId: jsonString(json, 'trackId'),
      clip: TimelineClip.fromJson(jsonMap(json['clip'])),
      orderIndex: jsonNullableInt(json, 'orderIndex'),
    );
  }

  @override
  String get type => 'clip.insert';

  @override
  String get summary => 'Insert clip ${clip.id}';

  @override
  Set<String> get affectedIds => {timelineId, trackId, clip.id};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    _validateClipControls(clip);
    if (_findClip(project, clip.id) != null) {
      throw duplicateEntity('clip', clip.id);
    }
    final timeline = _timeline(project, timelineId);
    final track = _track(timeline, trackId);
    if (track.type != clip.trackType) {
      throw ProjectCommandException(
        '${clip.trackType.name} clip cannot be inserted into ${track.type.name}.',
      );
    }
    final order = [...track.clipOrder];
    final index = orderIndex ?? order.length;
    if (index < 0 || index > order.length) {
      throw const ProjectCommandException('Clip order index is out of range.');
    }
    order.insert(index, clip.id);
    return _replaceTrack(
      project,
      timeline,
      track.copyWith(clips: {...track.clips, clip.id: clip}, clipOrder: order),
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    return DeleteClipCommand(clipId: clip.id);
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'clip': clip.toJson(),
    if (orderIndex != null) 'orderIndex': orderIndex,
    'timelineId': timelineId,
    'trackId': trackId,
    'type': type,
  });
}

class DeleteClipCommand implements ProjectCommand {
  const DeleteClipCommand({required this.clipId});

  final ClipId clipId;

  factory DeleteClipCommand.fromJson(Map<String, Object?> json) {
    return DeleteClipCommand(clipId: jsonString(json, 'clipId'));
  }

  @override
  String get type => 'clip.delete';

  @override
  String get summary => 'Delete clip $clipId';

  @override
  Set<String> get affectedIds => {clipId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final location = _requireClip(project, clipId);
    final references = ProjectReferenceIndex.forProject(
      project,
    ).referencesTo(ProjectReferenceKind.clip, clipId);
    if (references.isNotEmpty) {
      throw ProjectCommandException(
        'Cannot delete clip $clipId because it is linked from another clip.',
      );
    }
    final clips = {...location.track.clips}..remove(clipId);
    final order = location.track.clipOrder.where((id) => id != clipId).toList();
    return _replaceTrack(
      project,
      location.timeline,
      location.track.copyWith(clips: clips, clipOrder: order),
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    final location = _requireClip(project, clipId);
    return InsertClipCommand(
      timelineId: location.timeline.id,
      trackId: location.track.id,
      clip: location.clip,
      orderIndex: location.track.clipOrder.indexOf(clipId),
    );
  }

  @override
  Map<String, Object?> toJson() =>
      canonicalJsonMap({'clipId': clipId, 'type': type});
}

class MoveClipCommand implements ProjectCommand {
  const MoveClipCommand({
    required this.clipId,
    required this.targetTimelineId,
    required this.targetTrackId,
    required this.newStart,
    this.targetOrderIndex,
  });

  final ClipId clipId;
  final TimelineId targetTimelineId;
  final TrackId targetTrackId;
  final FrameTime newStart;
  final int? targetOrderIndex;

  factory MoveClipCommand.fromJson(Map<String, Object?> json) {
    return MoveClipCommand(
      clipId: jsonString(json, 'clipId'),
      targetTimelineId: jsonString(json, 'targetTimelineId'),
      targetTrackId: jsonString(json, 'targetTrackId'),
      newStart: FrameTime.fromJson(json['newStart']),
      targetOrderIndex: jsonNullableInt(json, 'targetOrderIndex'),
    );
  }

  @override
  String get type => 'clip.move';

  @override
  String get summary => 'Move clip $clipId';

  @override
  Set<String> get affectedIds => {clipId, targetTimelineId, targetTrackId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final source = _requireClip(project, clipId);
    final targetTimeline = _timeline(project, targetTimelineId);
    final targetTrack = _track(targetTimeline, targetTrackId);
    if (source.clip.trackType != targetTrack.type) {
      throw const ProjectCommandException(
        'Clip cannot move to a track of a different type.',
      );
    }
    final moved = _copyClip(
      source.clip,
      range: source.clip.range.copyWith(start: newStart),
    );
    if (source.timeline.id == targetTimelineId &&
        source.track.id == targetTrackId) {
      final order = [...source.track.clipOrder];
      if (targetOrderIndex != null) {
        order.remove(clipId);
        if (targetOrderIndex! < 0 || targetOrderIndex! > order.length) {
          throw const ProjectCommandException(
            'Target clip order index is out of range.',
          );
        }
        order.insert(targetOrderIndex!, clipId);
      }
      return _replaceTrack(
        project,
        source.timeline,
        source.track.copyWith(
          clips: {...source.track.clips, clipId: moved},
          clipOrder: order,
        ),
      );
    }
    final sourceClips = {...source.track.clips}..remove(clipId);
    final sourceOrder = source.track.clipOrder
        .where((id) => id != clipId)
        .toList();
    var next = _replaceTrack(
      project,
      source.timeline,
      source.track.copyWith(clips: sourceClips, clipOrder: sourceOrder),
    );
    final refreshedTimeline = _timeline(next, targetTimelineId);
    final refreshedTrack = _track(refreshedTimeline, targetTrackId);
    final targetOrder = [...refreshedTrack.clipOrder];
    final insertIndex = targetOrderIndex ?? targetOrder.length;
    if (insertIndex < 0 || insertIndex > targetOrder.length) {
      throw const ProjectCommandException(
        'Target clip order index is out of range.',
      );
    }
    targetOrder.insert(insertIndex, clipId);
    next = _replaceTrack(
      next,
      refreshedTimeline,
      refreshedTrack.copyWith(
        clips: {...refreshedTrack.clips, clipId: moved},
        clipOrder: targetOrder,
      ),
    );
    return next;
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    final location = _requireClip(project, clipId);
    return MoveClipCommand(
      clipId: clipId,
      targetTimelineId: location.timeline.id,
      targetTrackId: location.track.id,
      newStart: location.clip.range.start,
      targetOrderIndex: location.track.clipOrder.indexOf(clipId),
    );
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'clipId': clipId,
    'newStart': newStart.toJson(),
    'targetTimelineId': targetTimelineId,
    if (targetOrderIndex != null) 'targetOrderIndex': targetOrderIndex,
    'targetTrackId': targetTrackId,
    'type': type,
  });
}

class TrimClipCommand implements ProjectCommand {
  const TrimClipCommand({
    required this.clipId,
    required this.range,
    this.adjustSourceIn = true,
  });

  final ClipId clipId;
  final FrameRange range;
  final bool adjustSourceIn;

  factory TrimClipCommand.fromJson(Map<String, Object?> json) {
    return TrimClipCommand(
      clipId: jsonString(json, 'clipId'),
      range: FrameRange.fromJson(jsonMap(json['range'])),
      adjustSourceIn: jsonBool(json, 'adjustSourceIn', fallback: true),
    );
  }

  @override
  String get type => 'clip.trim';

  @override
  String get summary => 'Trim clip $clipId';

  @override
  Set<String> get affectedIds => {clipId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final location = _requireClip(project, clipId);
    final sourceDelta = adjustSourceIn
        ? range.start.difference(location.clip.range.start)
        : 0;
    final clip = _copyClip(
      location.clip,
      range: range,
      sourceInDelta: sourceDelta,
    );
    return _replaceTrack(
      project,
      location.timeline,
      location.track.copyWith(clips: {...location.track.clips, clipId: clip}),
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    return TrimClipCommand(
      clipId: clipId,
      range: _requireClip(project, clipId).clip.range,
      adjustSourceIn: adjustSourceIn,
    );
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'adjustSourceIn': adjustSourceIn,
    'clipId': clipId,
    'range': range.toJson(),
    'type': type,
  });
}

class SplitClipCommand implements ProjectCommand {
  const SplitClipCommand({
    required this.clipId,
    required this.splitTime,
    required this.rightClipId,
  });

  final ClipId clipId;
  final FrameTime splitTime;
  final ClipId rightClipId;

  factory SplitClipCommand.fromJson(Map<String, Object?> json) {
    return SplitClipCommand(
      clipId: jsonString(json, 'clipId'),
      splitTime: FrameTime.fromJson(json['splitTime']),
      rightClipId: jsonString(json, 'rightClipId'),
    );
  }

  @override
  String get type => 'clip.split';

  @override
  String get summary => 'Split clip $clipId';

  @override
  Set<String> get affectedIds => {clipId, rightClipId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    if (_findClip(project, rightClipId) != null) {
      throw duplicateEntity('clip', rightClipId);
    }
    final location = _requireClip(project, clipId);
    final offset = splitTime.difference(location.clip.range.start);
    if (offset <= 0 || offset >= location.clip.range.duration) {
      throw const ProjectCommandException(
        'Split time must be inside the clip range.',
      );
    }
    final leftRange = FrameRange(
      start: location.clip.range.start,
      duration: offset,
    );
    final rightRange = FrameRange(
      start: splitTime,
      duration: location.clip.range.duration - offset,
    );
    final left = _copyClip(location.clip, range: leftRange);
    final right = _copyClip(
      location.clip,
      id: rightClipId,
      range: rightRange,
      sourceInDelta: offset,
    );
    final order = [...location.track.clipOrder];
    final index = order.indexOf(clipId);
    order.insert(index + 1, rightClipId);
    return _replaceTrack(
      project,
      location.timeline,
      location.track.copyWith(
        clips: {...location.track.clips, clipId: left, rightClipId: right},
        clipOrder: order,
      ),
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    final original = _requireClip(project, clipId).clip;
    return ProjectCommandBatch(
      label: 'Undo split $clipId',
      commands: [
        DeleteClipCommand(clipId: rightClipId),
        TrimClipCommand(
          clipId: clipId,
          range: original.range,
          adjustSourceIn: false,
        ),
      ],
    );
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'clipId': clipId,
    'rightClipId': rightClipId,
    'splitTime': splitTime.toJson(),
    'type': type,
  });
}

class AddMarkerCommand implements ProjectCommand {
  const AddMarkerCommand({required this.timelineId, required this.marker});

  final TimelineId timelineId;
  final TimelineMarker marker;

  factory AddMarkerCommand.fromJson(Map<String, Object?> json) {
    return AddMarkerCommand(
      timelineId: jsonString(json, 'timelineId'),
      marker: TimelineMarker.fromJson(jsonMap(json['marker'])),
    );
  }

  @override
  String get type => 'marker.add';

  @override
  String get summary => 'Add marker ${marker.id}';

  @override
  Set<String> get affectedIds => {timelineId, marker.id};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final timeline = _timeline(project, timelineId);
    if (timeline.markers.containsKey(marker.id)) {
      throw duplicateEntity('marker', marker.id);
    }
    return _replaceTimeline(
      project,
      timeline.copyWith(markers: {...timeline.markers, marker.id: marker}),
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    return RemoveMarkerCommand(timelineId: timelineId, markerId: marker.id);
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'marker': marker.toJson(),
    'timelineId': timelineId,
    'type': type,
  });
}

class RemoveMarkerCommand implements ProjectCommand {
  const RemoveMarkerCommand({required this.timelineId, required this.markerId});

  final TimelineId timelineId;
  final MarkerId markerId;

  factory RemoveMarkerCommand.fromJson(Map<String, Object?> json) {
    return RemoveMarkerCommand(
      timelineId: jsonString(json, 'timelineId'),
      markerId: jsonString(json, 'markerId'),
    );
  }

  @override
  String get type => 'marker.remove';

  @override
  String get summary => 'Remove marker $markerId';

  @override
  Set<String> get affectedIds => {timelineId, markerId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final timeline = _timeline(project, timelineId);
    if (!timeline.markers.containsKey(markerId)) {
      throw missingEntity('marker', markerId);
    }
    final markers = {...timeline.markers}..remove(markerId);
    return _replaceTimeline(project, timeline.copyWith(markers: markers));
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    final marker = _timeline(project, timelineId).markers[markerId];
    if (marker == null) {
      throw missingEntity('marker', markerId);
    }
    return AddMarkerCommand(timelineId: timelineId, marker: marker);
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'markerId': markerId,
    'timelineId': timelineId,
    'type': type,
  });
}

class UpdateAudioControlsCommand implements ProjectCommand {
  const UpdateAudioControlsCommand({
    required this.clipId,
    required this.controls,
  });

  final ClipId clipId;
  final AudioClipControls controls;

  factory UpdateAudioControlsCommand.fromJson(Map<String, Object?> json) {
    return UpdateAudioControlsCommand(
      clipId: jsonString(json, 'clipId'),
      controls: AudioClipControls.fromJson(jsonMap(json['controls'])),
    );
  }

  @override
  String get type => 'clip.audio.update';

  @override
  String get summary => 'Update audio controls for $clipId';

  @override
  Set<String> get affectedIds => {clipId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    _validateAudioControls(controls);
    final location = _requireClip(project, clipId);
    final existing = location.clip;
    final clip = switch (existing) {
      VideoTimelineClip() => existing.copyWith(audio: controls),
      AudioTimelineClip() => existing.copyWith(audio: controls),
      _ => throw const ProjectCommandException(
        'Audio controls require a video or audio clip.',
      ),
    };
    return _replaceTrack(
      project,
      location.timeline,
      location.track.copyWith(clips: {...location.track.clips, clipId: clip}),
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    final clip = _requireClip(project, clipId).clip;
    final previous = switch (clip) {
      VideoTimelineClip() => clip.audio,
      AudioTimelineClip() => clip.audio,
      _ => throw const ProjectCommandException(
        'Audio controls require a video or audio clip.',
      ),
    };
    return UpdateAudioControlsCommand(clipId: clipId, controls: previous);
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'clipId': clipId,
    'controls': controls.toJson(),
    'type': type,
  });
}

class DuplicateTimelineCommand implements ProjectCommand {
  const DuplicateTimelineCommand({
    required this.sourceTimelineId,
    required this.newTimelineId,
    required this.newName,
  });

  final TimelineId sourceTimelineId;
  final TimelineId newTimelineId;
  final String newName;

  factory DuplicateTimelineCommand.fromJson(Map<String, Object?> json) {
    return DuplicateTimelineCommand(
      sourceTimelineId: jsonString(json, 'sourceTimelineId'),
      newTimelineId: jsonString(json, 'newTimelineId'),
      newName: jsonString(json, 'newName'),
    );
  }

  @override
  String get type => 'timeline.duplicate';

  @override
  String get summary => 'Duplicate timeline $sourceTimelineId';

  @override
  Set<String> get affectedIds => {sourceTimelineId, newTimelineId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final source = _timeline(project, sourceTimelineId);
    if (project.timelines.containsKey(newTimelineId)) {
      throw duplicateEntity('timeline', newTimelineId);
    }
    final trackIds = <String, String>{};
    for (var index = 0; index < source.trackOrder.length; index += 1) {
      trackIds[source.trackOrder[index]] = '$newTimelineId.track.${index + 1}';
    }
    final clipIds = <String, String>{};
    var clipIndex = 0;
    for (final trackId in source.trackOrder) {
      for (final clipId in source.tracks[trackId]!.clipOrder) {
        clipIndex += 1;
        clipIds[clipId] = '$newTimelineId.clip.$clipIndex';
      }
    }
    final tracks = <TrackId, TimelineTrack>{};
    for (var index = 0; index < source.trackOrder.length; index += 1) {
      final sourceTrack = source.tracks[source.trackOrder[index]]!;
      final clips = <ClipId, TimelineClip>{};
      for (final sourceClipId in sourceTrack.clipOrder) {
        final sourceClip = sourceTrack.clips[sourceClipId]!;
        final newClipId = clipIds[sourceClipId]!;
        final linkedId = _linkedClipId(sourceClip);
        clips[newClipId] = _copyClip(
          sourceClip,
          id: newClipId,
          linkedClipId: linkedId == null
              ? null
              : (clipIds[linkedId] ?? linkedId),
          replaceLinkedClipId: true,
        );
      }
      final newTrackId = trackIds[sourceTrack.id]!;
      tracks[newTrackId] = sourceTrack.copyWith(
        id: newTrackId,
        order: index,
        clipOrder: [
          for (final sourceClipId in sourceTrack.clipOrder)
            clipIds[sourceClipId]!,
        ],
        clips: clips,
      );
    }
    final markers = <MarkerId, TimelineMarker>{};
    final sourceMarkers = source.markers.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    for (var index = 0; index < sourceMarkers.length; index += 1) {
      final id = '$newTimelineId.marker.${index + 1}';
      markers[id] = sourceMarkers[index].copyWith(id: id);
    }
    final duplicate = source.copyWith(
      id: newTimelineId,
      name: newName,
      trackOrder: [for (final id in source.trackOrder) trackIds[id]!],
      tracks: tracks,
      markers: markers,
      relationshipMetadata: {
        ...source.relationshipMetadata,
        'duplicatedFromTimelineId': sourceTimelineId,
      },
    );
    return project.copyWith(
      timelines: {...project.timelines, duplicate.id: duplicate},
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    return RemoveProjectEntityCommand(
      kind: ProjectEntityKind.timeline,
      entityId: newTimelineId,
    );
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'newName': newName,
    'newTimelineId': newTimelineId,
    'sourceTimelineId': sourceTimelineId,
    'type': type,
  });
}

class _ClipLocation {
  const _ClipLocation({
    required this.timeline,
    required this.track,
    required this.clip,
  });

  final ProjectTimeline timeline;
  final TimelineTrack track;
  final TimelineClip clip;
}

ProjectTimeline _timeline(ReactifyProjectDocument project, TimelineId id) {
  final timeline = project.timelines[id];
  if (timeline == null) {
    throw missingEntity('timeline', id);
  }
  return timeline;
}

TimelineTrack _track(ProjectTimeline timeline, TrackId id) {
  final track = timeline.tracks[id];
  if (track == null) {
    throw missingEntity('track', id);
  }
  return track;
}

_ClipLocation? _findClip(ReactifyProjectDocument project, ClipId id) {
  for (final timeline in project.timelines.values) {
    for (final track in timeline.tracks.values) {
      final clip = track.clips[id];
      if (clip != null) {
        return _ClipLocation(timeline: timeline, track: track, clip: clip);
      }
    }
  }
  return null;
}

_ClipLocation _requireClip(ReactifyProjectDocument project, ClipId id) {
  final location = _findClip(project, id);
  if (location == null) {
    throw missingEntity('clip', id);
  }
  return location;
}

ReactifyProjectDocument _replaceTimeline(
  ReactifyProjectDocument project,
  ProjectTimeline timeline,
) {
  return project.copyWith(
    timelines: {...project.timelines, timeline.id: timeline},
  );
}

ReactifyProjectDocument _replaceTrack(
  ReactifyProjectDocument project,
  ProjectTimeline timeline,
  TimelineTrack track,
) {
  return _replaceTimeline(
    project,
    timeline.copyWith(tracks: {...timeline.tracks, track.id: track}),
  );
}

bool _sameIds(Iterable<String> left, Iterable<String> right) {
  final leftList = left.toList();
  final rightSet = right.toSet();
  return leftList.length == leftList.toSet().length &&
      leftList.length == rightSet.length &&
      leftList.toSet().containsAll(rightSet);
}

ClipId? _linkedClipId(TimelineClip clip) {
  return switch (clip) {
    VideoTimelineClip() => clip.linkedClipId,
    AudioTimelineClip() => clip.linkedClipId,
    _ => null,
  };
}

TimelineClip _copyClip(
  TimelineClip clip, {
  ClipId? id,
  FrameRange? range,
  int sourceInDelta = 0,
  ClipId? linkedClipId,
  bool replaceLinkedClipId = false,
}) {
  return switch (clip) {
    ReactionTimelineClip() => clip.copyWith(id: id, range: range),
    VideoTimelineClip() => clip.copyWith(
      id: id,
      range: range,
      sourceInFrame: clip.sourceInFrame + sourceInDelta,
      linkedClipId: replaceLinkedClipId ? linkedClipId : absentValue,
    ),
    ImageTimelineClip() => clip.copyWith(id: id, range: range),
    RichTextTimelineClip() => clip.copyWith(id: id, range: range),
    AudioTimelineClip() => clip.copyWith(
      id: id,
      range: range,
      sourceInFrame: clip.sourceInFrame + sourceInDelta,
      linkedClipId: replaceLinkedClipId ? linkedClipId : absentValue,
    ),
    WatermarkTimelineClip() => clip.copyWith(id: id, range: range),
  };
}

void _validateClipControls(TimelineClip clip) {
  switch (clip) {
    case ReactionTimelineClip():
      _validateVisualControls(clip.visual);
    case VideoTimelineClip():
      _validateVisualControls(clip.visual);
      _validateAudioControls(clip.audio);
    case ImageTimelineClip():
      _validateVisualControls(clip.visual);
    case RichTextTimelineClip():
      _validateVisualControls(clip.visual);
    case AudioTimelineClip():
      _validateAudioControls(clip.audio);
    case WatermarkTimelineClip():
      _validateVisualControls(clip.visual);
  }
}

void _validateVisualControls(VisualClipControls controls) {
  if (!controls.opacity.isFinite ||
      controls.opacity < 0 ||
      controls.opacity > 1 ||
      controls.fadeInFrames < 0 ||
      controls.fadeOutFrames < 0) {
    throw const ProjectCommandException('Invalid visual clip controls.');
  }
  final crop = controls.crop;
  if (crop != null &&
      (!crop.left.isFinite ||
          !crop.top.isFinite ||
          !crop.width.isFinite ||
          !crop.height.isFinite ||
          crop.left < 0 ||
          crop.top < 0 ||
          crop.width <= 0 ||
          crop.height <= 0 ||
          crop.left + crop.width > 1 ||
          crop.top + crop.height > 1)) {
    throw const ProjectCommandException('Invalid normalized crop controls.');
  }
}

void _validateAudioControls(AudioClipControls controls) {
  if (!controls.gainDb.isFinite ||
      !controls.pan.isFinite ||
      !controls.pitchSemitones.isFinite ||
      !controls.pitchCents.isFinite ||
      controls.pan < -1 ||
      controls.pan > 1 ||
      controls.fadeInFrames < 0 ||
      controls.fadeOutFrames < 0) {
    throw const ProjectCommandException('Invalid audio clip controls.');
  }
}
