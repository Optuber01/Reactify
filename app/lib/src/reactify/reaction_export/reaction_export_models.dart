import 'dart:convert';
import 'dart:typed_data';

import '../media/media.dart';
import '../project/project.dart';

enum ReactionExportComposition { transparent, composited }

enum ReactionExportStage { render, write, materialize, manifest }

enum ReactionExportRunState {
  idle,
  running,
  completed,
  completedWithErrors,
  cancelled,
}

class ReactionContentKey {
  const ReactionContentKey._({
    required this.value,
    required this.canonicalJson,
  });

  factory ReactionContentKey.fromJsonValue(Object? value) {
    return ReactionContentKey.fromCanonicalJson(encodeCanonicalJson(value));
  }

  factory ReactionContentKey.fromCanonicalJson(String canonicalJson) {
    final bytes = utf8.encode(canonicalJson);
    var first = 0x811c9dc5;
    var second = 0x9e3779b9;
    for (final byte in bytes) {
      first ^= byte;
      first = _multiply32(first, 0x01000193);
      second = (second + byte) & 0xffffffff;
      second = ((second << 5) | (second >>> 27)) & 0xffffffff;
      second = _multiply32(second, 33);
    }
    final left = first.toRadixString(16).padLeft(8, '0');
    final right = second.toRadixString(16).padLeft(8, '0');
    final length = bytes.length.toRadixString(16).padLeft(8, '0');
    return ReactionContentKey._(
      value: '$left$right$length',
      canonicalJson: canonicalJson,
    );
  }

  final String value;
  final String canonicalJson;
}

sealed class ReactionExportSelection {
  const ReactionExportSelection();

  String get kind;

  Map<String, Object?> toJson();
}

class AllReactionEventsSelection extends ReactionExportSelection {
  const AllReactionEventsSelection();

  @override
  String get kind => 'allEvents';

  @override
  Map<String, Object?> toJson() => {'kind': kind};
}

class UniqueReactionStatesSelection extends ReactionExportSelection {
  const UniqueReactionStatesSelection();

  @override
  String get kind => 'uniqueStates';

  @override
  Map<String, Object?> toJson() => {'kind': kind};
}

class TimelineFrameRangeSelection extends ReactionExportSelection {
  const TimelineFrameRangeSelection(this.range);

  final FrameRange range;

  @override
  String get kind => 'timelineFrameRange';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'range': range.toJson()};
}

class SelectedReactionStatesSelection extends ReactionExportSelection {
  SelectedReactionStatesSelection(Iterable<ReactionStateId> stateIds)
    : stateIds = Set.unmodifiable(stateIds);

  final Set<ReactionStateId> stateIds;

  @override
  String get kind => 'selectedStates';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'stateIds': stateIds.toList()..sort(),
  };
}

class SelectedCharactersSelection extends ReactionExportSelection {
  SelectedCharactersSelection(Iterable<CharacterId> characterIds)
    : characterIds = Set.unmodifiable(characterIds);

  final Set<CharacterId> characterIds;

  @override
  String get kind => 'selectedCharacters';

  @override
  Map<String, Object?> toJson() => {
    'characterIds': characterIds.toList()..sort(),
    'kind': kind,
  };
}

class ReactionExportOptions {
  const ReactionExportOptions({
    this.composition = ReactionExportComposition.composited,
    this.includeDialogue = true,
    this.includeMedia = true,
    this.materializeEventFiles = true,
    this.filePrefix = 'reaction',
    this.manifestFileName = 'reaction_manifest.json',
  });

  final ReactionExportComposition composition;
  final bool includeDialogue;
  final bool includeMedia;
  final bool materializeEventFiles;
  final String filePrefix;
  final String manifestFileName;

  Map<String, Object?> toJson() => {
    'composition': composition.name,
    'filePrefix': filePrefix,
    'includeDialogue': includeDialogue,
    'includeMedia': includeMedia,
    'manifestFileName': manifestFileName,
    'materializeEventFiles': materializeEventFiles,
  };

  void validate() {
    final safeName = RegExp(r'^[A-Za-z0-9._-]+$');
    if (!safeName.hasMatch(filePrefix) ||
        !safeName.hasMatch(manifestFileName) ||
        !manifestFileName.toLowerCase().endsWith('.json')) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Export file names contain unsupported characters.',
      );
    }
  }
}

class ReactionExportRequest {
  const ReactionExportRequest({
    required this.project,
    required this.selection,
    this.timelineId,
    this.options = const ReactionExportOptions(),
  });

  final ReactifyProjectDocument project;
  final TimelineId? timelineId;
  final ReactionExportSelection selection;
  final ReactionExportOptions options;
}

class ReactionExportEvent {
  const ReactionExportEvent({
    required this.timelineId,
    required this.trackId,
    required this.clip,
  });

  final TimelineId timelineId;
  final TrackId trackId;
  final ReactionTimelineClip clip;

  String get eventId => '$timelineId/$trackId/${clip.id}';
}

class ReactionRenderRequest {
  ReactionRenderRequest({
    required this.project,
    required this.state,
    required this.contentKey,
    required this.composition,
    required this.includeDialogue,
    required this.includeMedia,
    required Iterable<CharacterId> characterIds,
    this.mediaFrameIdentity,
    this.timeline,
    this.event,
  }) : characterIds = Set.unmodifiable(characterIds);

  final ReactifyProjectDocument project;
  final ReactionState state;
  final String contentKey;
  final ReactionExportComposition composition;
  final bool includeDialogue;
  final bool includeMedia;
  final Set<CharacterId> characterIds;
  final String? mediaFrameIdentity;
  final ProjectTimeline? timeline;
  final ReactionExportEvent? event;
}

class RenderedReactionArtifact {
  const RenderedReactionArtifact({
    required this.pngBytes,
    this.width,
    this.height,
  });

  final Uint8List pngBytes;
  final int? width;
  final int? height;
}

class WrittenReactionArtifact {
  const WrittenReactionArtifact({
    required this.location,
    required this.byteLength,
  });

  final MediaLocation location;
  final int byteLength;

  Map<String, Object?> toJson() => {
    'byteLength': byteLength,
    'location': location.value,
  };

  factory WrittenReactionArtifact.fromJson(Map<String, Object?> json) {
    return WrittenReactionArtifact(
      location: MediaLocation(json['location'] as String),
      byteLength: json['byteLength'] as int,
    );
  }
}

abstract interface class ReactionStateRenderer {
  Future<RenderedReactionArtifact> render(
    ReactionRenderRequest request,
    ExportCancellationToken cancellation,
  );
}

abstract interface class ExportArtifactWriter {
  Future<WrittenReactionArtifact> writeArtifact({
    required String fileName,
    required Uint8List bytes,
    required ExportCancellationToken cancellation,
  });

  Future<WrittenReactionArtifact> materializeArtifact({
    required WrittenReactionArtifact source,
    required String fileName,
    required ExportCancellationToken cancellation,
  });

  Future<WrittenReactionArtifact> writeManifest({
    required String fileName,
    required String json,
    required ExportCancellationToken cancellation,
  });
}

class ReactionRenderArtifactPlan {
  ReactionRenderArtifactPlan({
    required this.contentKey,
    required this.stateId,
    required this.fileName,
    required this.renderRequest,
    required this.canonicalContent,
  });

  final String contentKey;
  final ReactionStateId stateId;
  final String fileName;
  final ReactionRenderRequest renderRequest;
  final String canonicalContent;
}

class ReactionMaterializationPlan {
  const ReactionMaterializationPlan({
    required this.id,
    required this.contentKey,
    required this.fileName,
    required this.eventId,
  });

  final String id;
  final String contentKey;
  final String fileName;
  final String eventId;
}

class ReactionExportManifestEntry {
  ReactionExportManifestEntry({
    required this.stateId,
    required this.contentKey,
    required this.renderFile,
    required Iterable<CharacterId> characterIds,
    this.eventId,
    this.timelineId,
    this.trackId,
    this.clipId,
    this.startFrame,
    this.durationFrames,
    this.timestampMicroseconds,
    this.eventFile,
  }) : characterIds = List.unmodifiable(characterIds);

  final ReactionStateId stateId;
  final String contentKey;
  final String renderFile;
  final List<CharacterId> characterIds;
  final String? eventId;
  final TimelineId? timelineId;
  final TrackId? trackId;
  final ClipId? clipId;
  final int? startFrame;
  final int? durationFrames;
  final int? timestampMicroseconds;
  final String? eventFile;

  Map<String, Object?> toJson() => {
    'characterIds': characterIds,
    'clipId': clipId,
    'contentKey': contentKey,
    'durationFrames': durationFrames,
    'eventFile': eventFile,
    'eventId': eventId,
    'renderFile': renderFile,
    'startFrame': startFrame,
    'stateId': stateId,
    'timelineId': timelineId,
    'timestampMicroseconds': timestampMicroseconds,
    'trackId': trackId,
  };
}

class ReactionExportManifest {
  ReactionExportManifest({
    required this.projectId,
    required this.timelineId,
    required this.selection,
    required this.options,
    required this.frameRate,
    required List<ReactionExportManifestEntry> entries,
    required List<ReactionRenderArtifactPlan> artifacts,
  }) : entries = List.unmodifiable(entries),
       artifacts = List.unmodifiable(artifacts);

  static const schemaVersion = 1;

  final ProjectId projectId;
  final TimelineId? timelineId;
  final ReactionExportSelection selection;
  final ReactionExportOptions options;
  final RationalFrameRate? frameRate;
  final List<ReactionExportManifestEntry> entries;
  final List<ReactionRenderArtifactPlan> artifacts;

  Map<String, Object?> toJson() => {
    'artifacts': [
      for (final artifact in artifacts)
        {
          'contentKey': artifact.contentKey,
          'file': artifact.fileName,
          'stateId': artifact.stateId,
        },
    ],
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'frameRate': frameRate?.toJson(),
    'options': options.toJson(),
    'projectId': projectId,
    'schemaVersion': schemaVersion,
    'selection': selection.toJson(),
    'timelineId': timelineId,
  };

  String toDeterministicJson({bool pretty = true}) {
    return encodeCanonicalJson(toJson(), pretty: pretty);
  }
}

class ReactionExportPlan {
  ReactionExportPlan({
    required this.request,
    required this.timeline,
    required List<ReactionRenderArtifactPlan> artifacts,
    required List<ReactionMaterializationPlan> materializations,
    required this.manifest,
  }) : artifacts = List.unmodifiable(artifacts),
       materializations = List.unmodifiable(materializations);

  final ReactionExportRequest request;
  final ProjectTimeline? timeline;
  final List<ReactionRenderArtifactPlan> artifacts;
  final List<ReactionMaterializationPlan> materializations;
  final ReactionExportManifest manifest;

  int get uniqueRenderCount => artifacts.length;

  String get planKey => ReactionContentKey.fromCanonicalJson(
    manifest.toDeterministicJson(pretty: false),
  ).value;
}

class ReactionExportFailureRecord {
  ReactionExportFailureRecord({
    required this.taskId,
    required this.stage,
    required this.message,
    this.contentKey,
    this.eventId,
    this.attempt = 1,
  });

  final String taskId;
  final ReactionExportStage stage;
  final String message;
  final String? contentKey;
  final String? eventId;
  final int attempt;

  Map<String, Object?> toJson() => {
    'attempt': attempt,
    'contentKey': contentKey,
    'eventId': eventId,
    'message': message,
    'stage': stage.name,
    'taskId': taskId,
  };
}

class ReactionExportResumeSnapshot {
  ReactionExportResumeSnapshot({
    required this.planKey,
    required Map<String, WrittenReactionArtifact> renderedArtifacts,
    required Map<String, WrittenReactionArtifact> materializedArtifacts,
  }) : renderedArtifacts = Map.unmodifiable(renderedArtifacts),
       materializedArtifacts = Map.unmodifiable(materializedArtifacts);

  final String planKey;
  final Map<String, WrittenReactionArtifact> renderedArtifacts;
  final Map<String, WrittenReactionArtifact> materializedArtifacts;

  Map<String, Object?> toJson() => {
    'materializedArtifacts': {
      for (final key in materializedArtifacts.keys.toList()..sort())
        key: materializedArtifacts[key]!.toJson(),
    },
    'renderedArtifacts': {
      for (final key in renderedArtifacts.keys.toList()..sort())
        key: renderedArtifacts[key]!.toJson(),
    },
    'planKey': planKey,
  };

  factory ReactionExportResumeSnapshot.fromJson(Map<String, Object?> json) {
    Map<String, WrittenReactionArtifact> decodeMap(Object? value) {
      final source = Map<String, Object?>.from(value as Map);
      return {
        for (final entry in source.entries)
          entry.key: WrittenReactionArtifact.fromJson(
            Map<String, Object?>.from(entry.value as Map),
          ),
      };
    }

    return ReactionExportResumeSnapshot(
      planKey: json['planKey'] as String,
      renderedArtifacts: decodeMap(json['renderedArtifacts']),
      materializedArtifacts: decodeMap(json['materializedArtifacts']),
    );
  }
}

class ReactionExportSummary {
  ReactionExportSummary({
    required this.state,
    required this.plannedEvents,
    required this.plannedUniqueRenders,
    required this.completedUniqueRenders,
    required this.completedMaterializations,
    required this.manifestJson,
    required this.resumeSnapshot,
    required List<ReactionExportFailureRecord> failures,
    this.manifestArtifact,
  }) : failures = List.unmodifiable(failures);

  final ReactionExportRunState state;
  final int plannedEvents;
  final int plannedUniqueRenders;
  final int completedUniqueRenders;
  final int completedMaterializations;
  final String manifestJson;
  final WrittenReactionArtifact? manifestArtifact;
  final ReactionExportResumeSnapshot resumeSnapshot;
  final List<ReactionExportFailureRecord> failures;

  bool get succeeded => state == ReactionExportRunState.completed;
}

String encodeCanonicalJson(Object? value, {bool pretty = false}) {
  final canonical = canonicalJsonValue(value);
  if (pretty) {
    return const JsonEncoder.withIndent('  ').convert(canonical);
  }
  return jsonEncode(canonical);
}

Object? canonicalJsonValue(Object? value) {
  if (value is Map) {
    final source = <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
    final keys = source.keys.toList()..sort();
    return {for (final key in keys) key: canonicalJsonValue(source[key])};
  }
  if (value is Iterable) {
    return [for (final item in value) canonicalJsonValue(item)];
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw MediaFailure(
    code: MediaFailureCode.invalidRequest,
    message: 'Canonical JSON contains an unsupported value.',
    context: {'type': value.runtimeType.toString()},
  );
}

int _multiply32(int left, int right) {
  final leftLow = left & 0xffff;
  final leftHigh = (left >>> 16) & 0xffff;
  final rightLow = right & 0xffff;
  final rightHigh = (right >>> 16) & 0xffff;
  final low = leftLow * rightLow;
  final cross = (leftHigh * rightLow + leftLow * rightHigh) & 0xffff;
  return (low + (cross << 16)) & 0xffffffff;
}
