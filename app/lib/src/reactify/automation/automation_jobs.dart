import '../project/project.dart';

const int reactifyAutomationJobProtocolVersion = 1;

enum AutomationRenderMode { timelineRange, reactionStates }

class RenderJobRequestEnvelope {
  const RenderJobRequestEnvelope({
    required this.jobId,
    required this.projectId,
    required this.mode,
    required this.outputUri,
    this.timelineId,
    this.range,
    this.reactionStateIds = const [],
    this.transparent = false,
    this.includeDialogue = true,
    this.includeMedia = true,
    this.protocolVersion = reactifyAutomationJobProtocolVersion,
    this.metadata = const {},
  });

  final int protocolVersion;
  final String jobId;
  final ProjectId projectId;
  final AutomationRenderMode mode;
  final TimelineId? timelineId;
  final FrameRange? range;
  final List<ReactionStateId> reactionStateIds;
  final String outputUri;
  final bool transparent;
  final bool includeDialogue;
  final bool includeMedia;
  final Map<String, Object?> metadata;

  factory RenderJobRequestEnvelope.fromJson(Map<String, Object?> json) {
    return RenderJobRequestEnvelope(
      protocolVersion: jsonInt(json, 'protocolVersion'),
      jobId: jsonString(json, 'jobId'),
      projectId: jsonString(json, 'projectId'),
      mode: enumByName(AutomationRenderMode.values, jsonString(json, 'mode')),
      timelineId: jsonNullableString(json, 'timelineId'),
      range: json['range'] == null
          ? null
          : FrameRange.fromJson(jsonMap(json['range'])),
      reactionStateIds: stringList(json['reactionStateIds']),
      outputUri: jsonString(json, 'outputUri'),
      transparent: jsonBool(json, 'transparent'),
      includeDialogue: jsonBool(json, 'includeDialogue', fallback: true),
      includeMedia: jsonBool(json, 'includeMedia', fallback: true),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  void validateFor(ReactifyProjectDocument project) {
    _validateEnvelope(project, protocolVersion, jobId, projectId, outputUri);
    switch (mode) {
      case AutomationRenderMode.timelineRange:
        final id = timelineId;
        final requestedRange = range;
        if (id == null || requestedRange == null) {
          throw const FormatException(
            'Timeline range render requires timelineId and range.',
          );
        }
        _validateTimelineRange(project, id, requestedRange);
        if (reactionStateIds.isNotEmpty) {
          throw const FormatException(
            'Timeline range render cannot include reactionStateIds.',
          );
        }
      case AutomationRenderMode.reactionStates:
        if (reactionStateIds.isEmpty) {
          throw const FormatException(
            'Reaction-state render requires at least one state id.',
          );
        }
        if (timelineId != null || range != null) {
          throw const FormatException(
            'Reaction-state render cannot include a timeline range.',
          );
        }
        for (final id in reactionStateIds) {
          if (!project.reactionStates.containsKey(id)) {
            throw FormatException('Missing reaction state $id.');
          }
        }
    }
  }

  Map<String, Object?> toJson() => canonicalJsonMap({
    'includeDialogue': includeDialogue,
    'includeMedia': includeMedia,
    'jobId': jobId,
    'metadata': metadata,
    'mode': mode.name,
    'outputUri': outputUri,
    'projectId': projectId,
    'protocolVersion': protocolVersion,
    'requestType': 'render',
    'range': range?.toJson(),
    'reactionStateIds': reactionStateIds,
    'timelineId': timelineId,
    'transparent': transparent,
  });
}

class ExportJobRequestEnvelope {
  const ExportJobRequestEnvelope({
    required this.jobId,
    required this.projectId,
    required this.timelineId,
    required this.exportPresetId,
    required this.outputUri,
    this.range,
    this.protocolVersion = reactifyAutomationJobProtocolVersion,
    this.metadata = const {},
  });

  final int protocolVersion;
  final String jobId;
  final ProjectId projectId;
  final TimelineId timelineId;
  final ExportPresetId exportPresetId;
  final FrameRange? range;
  final String outputUri;
  final Map<String, Object?> metadata;

  factory ExportJobRequestEnvelope.fromJson(Map<String, Object?> json) {
    return ExportJobRequestEnvelope(
      protocolVersion: jsonInt(json, 'protocolVersion'),
      jobId: jsonString(json, 'jobId'),
      projectId: jsonString(json, 'projectId'),
      timelineId: jsonString(json, 'timelineId'),
      exportPresetId: jsonString(json, 'exportPresetId'),
      range: json['range'] == null
          ? null
          : FrameRange.fromJson(jsonMap(json['range'])),
      outputUri: jsonString(json, 'outputUri'),
      metadata: jsonMetadata(json['metadata']),
    );
  }

  void validateFor(ReactifyProjectDocument project) {
    _validateEnvelope(project, protocolVersion, jobId, projectId, outputUri);
    final timeline = project.timelines[timelineId];
    if (timeline == null) {
      throw FormatException('Missing timeline $timelineId.');
    }
    if (!project.exportPresets.containsKey(exportPresetId)) {
      throw FormatException('Missing export preset $exportPresetId.');
    }
    final requestedRange = range;
    if (requestedRange != null) {
      _validateTimelineRange(project, timelineId, requestedRange);
    }
  }

  Map<String, Object?> toJson() => canonicalJsonMap({
    'exportPresetId': exportPresetId,
    'jobId': jobId,
    'metadata': metadata,
    'outputUri': outputUri,
    'projectId': projectId,
    'protocolVersion': protocolVersion,
    'requestType': 'export',
    'range': range?.toJson(),
    'timelineId': timelineId,
  });
}

void _validateEnvelope(
  ReactifyProjectDocument project,
  int protocolVersion,
  String jobId,
  String projectId,
  String outputUri,
) {
  if (protocolVersion != reactifyAutomationJobProtocolVersion) {
    throw FormatException('Unsupported job protocol $protocolVersion.');
  }
  if (jobId.trim().isEmpty || outputUri.trim().isEmpty) {
    throw const FormatException('Job id and output URI are required.');
  }
  if (project.id != projectId) {
    throw FormatException(
      'Job project $projectId does not match ${project.id}.',
    );
  }
}

void _validateTimelineRange(
  ReactifyProjectDocument project,
  TimelineId timelineId,
  FrameRange range,
) {
  final timeline = project.timelines[timelineId];
  if (timeline == null) {
    throw FormatException('Missing timeline $timelineId.');
  }
  if (range.start.frame < 0 ||
      range.duration <= 0 ||
      range.endExclusive.frame > timeline.durationFrames) {
    throw FormatException('Requested range is outside timeline $timelineId.');
  }
}
