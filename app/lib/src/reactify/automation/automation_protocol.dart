import '../commands/commands.dart';
import '../project/project.dart';

const int reactifyAutomationProtocolVersion = 1;

class ProjectCommandFileEnvelope {
  const ProjectCommandFileEnvelope({
    required this.transactionId,
    required this.projectId,
    required this.batch,
    this.protocolVersion = reactifyAutomationProtocolVersion,
    this.projectSchemaVersion = reactifyReactionProjectSchemaVersion,
    this.metadata = const {},
  });

  final int protocolVersion;
  final String transactionId;
  final ProjectId projectId;
  final int projectSchemaVersion;
  final ProjectCommandBatch batch;
  final Map<String, Object?> metadata;

  factory ProjectCommandFileEnvelope.fromJson(
    Map<String, Object?> json, {
    ProjectCommandCodec codec = const ProjectCommandCodec(),
  }) {
    final protocolVersion = jsonInt(json, 'protocolVersion');
    if (protocolVersion != reactifyAutomationProtocolVersion) {
      throw FormatException(
        'Unsupported automation protocol $protocolVersion.',
      );
    }
    final decoded = codec.decode(jsonMap(json['batch']));
    if (decoded is! ProjectCommandBatch) {
      throw const FormatException('Command envelope batch must be a batch.');
    }
    return ProjectCommandFileEnvelope(
      protocolVersion: protocolVersion,
      transactionId: jsonString(json, 'transactionId'),
      projectId: jsonString(json, 'projectId'),
      projectSchemaVersion: jsonInt(json, 'projectSchemaVersion'),
      batch: decoded,
      metadata: jsonMetadata(json['metadata']),
    );
  }

  void validateFor(ReactifyProjectDocument project) {
    if (transactionId.trim().isEmpty) {
      throw const FormatException('Transaction id cannot be empty.');
    }
    if (projectId != project.id) {
      throw FormatException(
        'Command project $projectId does not match ${project.id}.',
      );
    }
    if (projectSchemaVersion != project.schemaVersion) {
      throw FormatException(
        'Command schema $projectSchemaVersion does not match project schema ${project.schemaVersion}.',
      );
    }
    if (batch.commands.isEmpty) {
      throw const FormatException('Command batch cannot be empty.');
    }
  }

  Map<String, Object?> toJson() => canonicalJsonMap({
    'batch': batch.toJson(),
    'metadata': metadata,
    'projectId': projectId,
    'projectSchemaVersion': projectSchemaVersion,
    'protocolVersion': protocolVersion,
    'transactionId': transactionId,
  });
}

class ProjectInspection {
  const ProjectInspection({
    required this.projectId,
    required this.name,
    required this.schemaVersion,
    required this.libraryCounts,
    required this.timelines,
    required this.missingMedia,
  });

  final ProjectId projectId;
  final String name;
  final int schemaVersion;
  final Map<String, int> libraryCounts;
  final List<Map<String, Object?>> timelines;
  final List<Map<String, Object?>> missingMedia;

  factory ProjectInspection.fromProject(
    ReactifyProjectDocument project, {
    Iterable<({String assetId, String reason, String resolvedLocation})>
        missingMedia =
        const [],
  }) {
    final timelines = project.timelines.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    final missing = missingMedia.toList()
      ..sort((left, right) => left.assetId.compareTo(right.assetId));
    return ProjectInspection(
      projectId: project.id,
      name: project.name,
      schemaVersion: project.schemaVersion,
      libraryCounts: {
        'assets': project.assets.length,
        'bins': project.bins.length,
        'characters': project.characters.length,
        'exportPresets': project.exportPresets.length,
        'expressions': project.expressions.length,
        'layouts': project.layouts.length,
        'poses': project.poses.length,
        'reactionStates': project.reactionStates.length,
        'speakerRules': project.speakerRules.length,
        'textPresets': project.textPresets.length,
        'timelines': project.timelines.length,
      },
      timelines: [
        for (final timeline in timelines)
          canonicalJsonMap({
            'durationFrames': timeline.durationFrames,
            'frameRate': timeline.frameRate.toJson(),
            'id': timeline.id,
            'markerCount': timeline.markers.length,
            'name': timeline.name,
            'trackCount': timeline.tracks.length,
            'tracks': [
              for (final trackId in timeline.trackOrder)
                {
                  'clipCount': timeline.tracks[trackId]!.clips.length,
                  'id': trackId,
                  'name': timeline.tracks[trackId]!.name,
                  'type': timeline.tracks[trackId]!.type.name,
                },
            ],
          }),
      ],
      missingMedia: [
        for (final item in missing)
          {
            'assetId': item.assetId,
            'reason': item.reason,
            'resolvedLocation': item.resolvedLocation,
          },
      ],
    );
  }

  Map<String, Object?> toJson() => canonicalJsonMap({
    'libraryCounts': libraryCounts,
    'missingMedia': missingMedia,
    'name': name,
    'projectId': projectId,
    'schemaVersion': schemaVersion,
    'timelines': timelines,
  });
}

class AutomationOperationResult {
  const AutomationOperationResult({
    required this.action,
    required this.inspection,
    this.summary,
    this.draftId,
    this.draftLocation,
  });

  final String action;
  final ProjectInspection inspection;
  final ProjectChangeSummary? summary;
  final String? draftId;
  final String? draftLocation;

  Map<String, Object?> toJson() => canonicalJsonMap({
    'action': action,
    if (draftId != null) 'draftId': draftId,
    if (draftLocation != null) 'draftLocation': draftLocation,
    'inspection': inspection.toJson(),
    'ok': true,
    if (summary != null) 'summary': summary!.toJson(),
  });
}

class AutomationValidationResult {
  const AutomationValidationResult({
    required this.inspection,
    required this.issues,
  });

  final ProjectInspection inspection;
  final List<ProjectValidationIssue> issues;

  Map<String, Object?> toJson() => canonicalJsonMap({
    'action': 'validate',
    'inspection': inspection.toJson(),
    'issues': [
      for (final issue in issues)
        {
          'code': issue.code,
          'message': issue.message,
          'path': issue.path,
          'severity': issue.severity.name,
        },
    ],
    'ok': !issues.any(
      (issue) => issue.severity == ProjectValidationSeverity.error,
    ),
  });
}

class AutomationErrorResponse {
  const AutomationErrorResponse({
    required this.code,
    required this.message,
    this.details = const {},
  });

  final String code;
  final String message;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => canonicalJsonMap({
    'error': {'code': code, 'details': details, 'message': message},
    'ok': false,
  });
}
