import 'dart:convert';

import '../commands/commands.dart';
import '../project/project.dart';
import 'portable_asset_uri.dart';
import 'project_migrations.dart';

enum ProjectLoadSource { primary, backup, autosave, memory }

enum MissingMediaReason { emptyUri, declaredMissing, fileNotFound }

class MissingMediaDiagnostic {
  const MissingMediaDiagnostic({
    required this.assetId,
    required this.storedUri,
    required this.resolvedLocation,
    required this.reason,
  });

  final AssetId assetId;
  final String storedUri;
  final String resolvedLocation;
  final MissingMediaReason reason;
}

class ProjectSaveMetadata {
  const ProjectSaveMetadata({
    required this.location,
    required this.projectId,
    required this.projectName,
    required this.savedAt,
    required this.byteLength,
    required this.autosave,
  });

  final String location;
  final ProjectId projectId;
  final String projectName;
  final DateTime savedAt;
  final int byteLength;
  final bool autosave;
}

class ProjectLoadResult {
  const ProjectLoadResult({
    required this.project,
    required this.source,
    required this.location,
    required this.loadedAt,
    required this.missingMedia,
    required this.migration,
  });

  final ReactifyProjectDocument project;
  final ProjectLoadSource source;
  final String location;
  final DateTime loadedAt;
  final List<MissingMediaDiagnostic> missingMedia;
  final ProjectMigrationResult migration;

  bool get recovered => source != ProjectLoadSource.primary;
}

class ProjectSaveResult {
  const ProjectSaveResult({
    required this.metadata,
    required this.backupLocation,
  });

  final ProjectSaveMetadata metadata;
  final String? backupLocation;
}

class ProjectAutosaveResult {
  const ProjectAutosaveResult({required this.metadata});

  final ProjectSaveMetadata metadata;
}

class ProjectRecoveryResult {
  const ProjectRecoveryResult({
    required this.loadResult,
    required this.attemptedLocations,
  });

  final ProjectLoadResult loadResult;
  final List<String> attemptedLocations;
}

class DecodedProjectDocument {
  const DecodedProjectDocument({
    required this.project,
    required this.migration,
  });

  final ReactifyProjectDocument project;
  final ProjectMigrationResult migration;
}

class ProjectRepositoryException implements Exception {
  const ProjectRepositoryException(
    this.message, {
    this.cause,
    this.validationIssues = const [],
  });

  final String message;
  final Object? cause;
  final List<ProjectValidationIssue> validationIssues;

  @override
  String toString() => 'ProjectRepositoryException: $message';
}

abstract interface class ProjectRepository {
  Future<ProjectLoadResult> load(String location);

  Future<ProjectSaveResult> save(
    ReactifyProjectDocument project,
    String location,
  );

  Future<ProjectAutosaveResult> autosave(
    ReactifyProjectDocument project,
    String location,
  );

  Future<ProjectRecoveryResult> recover(String location);

  Future<List<ProjectSaveMetadata>> recentSaves();
}

abstract interface class AssetAvailabilityProbe {
  Future<bool> exists(String location);
}

class ProjectDocumentSerializer {
  const ProjectDocumentSerializer({
    this.validator = const ReactifyProjectValidator(),
    this.migrations = const ProjectSchemaMigrationRegistry(),
  });

  final ReactifyProjectValidator validator;
  final ProjectSchemaMigrationRegistry migrations;

  String encode(ReactifyProjectDocument project) {
    _requireValid(project, 'Project cannot be saved.');
    return '${project.toDeterministicJson(pretty: true)}\n';
  }

  DecodedProjectDocument decode(String source) {
    try {
      final decoded = jsonDecode(source);
      final migration = migrations.migrate(jsonMap(decoded));
      final project = ReactifyProjectDocument.fromJson(migration.json);
      _requireValid(project, 'Loaded project is structurally invalid.');
      return DecodedProjectDocument(project: project, migration: migration);
    } on ProjectRepositoryException {
      rethrow;
    } catch (error) {
      throw ProjectRepositoryException(
        'Unable to decode Reactify project.',
        cause: error,
      );
    }
  }

  void _requireValid(ReactifyProjectDocument project, String message) {
    final issues = validator
        .validate(project)
        .where((issue) => issue.severity == ProjectValidationSeverity.error)
        .toList(growable: false);
    if (issues.isNotEmpty) {
      throw ProjectRepositoryException(message, validationIssues: issues);
    }
  }
}

class ProjectMediaDiagnostics {
  const ProjectMediaDiagnostics({
    required this.probe,
    this.uriPolicy = const PortableAssetUriPolicy(),
  });

  final AssetAvailabilityProbe probe;
  final PortableAssetUriPolicy uriPolicy;

  Future<List<MissingMediaDiagnostic>> scan(
    ReactifyProjectDocument project,
    String projectLocation,
  ) async {
    final diagnostics = <MissingMediaDiagnostic>[];
    final assets = project.assets.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    for (final asset in assets) {
      if (asset.uri.trim().isEmpty) {
        diagnostics.add(
          MissingMediaDiagnostic(
            assetId: asset.id,
            storedUri: asset.uri,
            resolvedLocation: '',
            reason: MissingMediaReason.emptyUri,
          ),
        );
        continue;
      }
      final resolved = uriPolicy.resolve(
        projectLocation: projectLocation,
        storedUri: asset.uri,
      );
      if (asset.missing) {
        diagnostics.add(
          MissingMediaDiagnostic(
            assetId: asset.id,
            storedUri: asset.uri,
            resolvedLocation: resolved,
            reason: MissingMediaReason.declaredMissing,
          ),
        );
        continue;
      }
      if (uriPolicy.isExternal(asset.uri)) {
        continue;
      }
      if (!await probe.exists(resolved)) {
        diagnostics.add(
          MissingMediaDiagnostic(
            assetId: asset.id,
            storedUri: asset.uri,
            resolvedLocation: resolved,
            reason: MissingMediaReason.fileNotFound,
          ),
        );
      }
    }
    return List.unmodifiable(diagnostics);
  }
}

class ProjectRelinkPlanner {
  const ProjectRelinkPlanner({this.uriPolicy = const PortableAssetUriPolicy()});

  final PortableAssetUriPolicy uriPolicy;

  ProjectCommandBatch prepare({
    required ReactifyProjectDocument project,
    required String projectLocation,
    required Map<AssetId, String> replacements,
  }) {
    final ids = replacements.keys.toList()..sort();
    final commands = <ProjectCommand>[];
    for (final id in ids) {
      final asset = project.assets[id];
      if (asset == null) {
        throw ProjectRepositoryException('Cannot relink missing asset $id.');
      }
      final replacement = replacements[id]!;
      final portableUri = uriPolicy.makePortable(
        projectLocation: projectLocation,
        assetLocation: replacement,
      );
      commands.add(
        UpsertProjectEntityCommand(
          kind: ProjectEntityKind.asset,
          entity: asset.copyWith(
            uri: portableUri,
            missing: false,
            metadata: {...asset.metadata, 'relinkedFromUri': asset.uri},
          ),
        ),
      );
    }
    return ProjectCommandBatch(label: 'Relink media', commands: commands);
  }
}
