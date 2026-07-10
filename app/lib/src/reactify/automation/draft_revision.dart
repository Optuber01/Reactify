import 'dart:convert';

import '../commands/commands.dart';
import '../project/project.dart';
import 'automation_protocol.dart';

class PersistentDraftRevision {
  const PersistentDraftRevision({
    required this.draftId,
    required this.projectLocation,
    required this.baseFingerprint,
    required this.commandEnvelope,
    required this.workingProject,
    required this.summary,
    this.protocolVersion = reactifyAutomationProtocolVersion,
  });

  final int protocolVersion;
  final String draftId;
  final String projectLocation;
  final String baseFingerprint;
  final ProjectCommandFileEnvelope commandEnvelope;
  final ReactifyProjectDocument workingProject;
  final ProjectChangeSummary summary;

  factory PersistentDraftRevision.fromJson(Map<String, Object?> json) {
    final protocolVersion = jsonInt(json, 'protocolVersion');
    if (protocolVersion != reactifyAutomationProtocolVersion) {
      throw FormatException('Unsupported draft protocol $protocolVersion.');
    }
    final summaryJson = jsonMap(json['summary']);
    return PersistentDraftRevision(
      protocolVersion: protocolVersion,
      draftId: jsonString(json, 'draftId'),
      projectLocation: jsonString(json, 'projectLocation'),
      baseFingerprint: jsonString(json, 'baseFingerprint'),
      commandEnvelope: ProjectCommandFileEnvelope.fromJson(
        jsonMap(json['commandEnvelope']),
      ),
      workingProject: ReactifyProjectDocument.fromJson(
        jsonMap(json['workingProject']),
      ),
      summary: ProjectChangeSummary(
        label: jsonString(summaryJson, 'label'),
        commandSummaries: stringList(summaryJson['commandSummaries']),
        affectedIds: stringList(summaryJson['affectedIds']).toSet(),
      ),
    );
  }

  factory PersistentDraftRevision.decode(String source) {
    return PersistentDraftRevision.fromJson(jsonMap(jsonDecode(source)));
  }

  Map<String, Object?> toJson() => canonicalJsonMap({
    'baseFingerprint': baseFingerprint,
    'commandEnvelope': commandEnvelope.toJson(),
    'draftId': draftId,
    'projectLocation': projectLocation,
    'protocolVersion': protocolVersion,
    'summary': summary.toJson(),
    'workingProject': workingProject.toJson(),
  });

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}

String projectFingerprint(ReactifyProjectDocument project) {
  var hash = 0x811c9dc5;
  for (final codeUnit in project.toDeterministicJson().codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193).toUnsigned(32);
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
