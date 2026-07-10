import 'dart:convert';
import 'dart:io';

import '../project/project.dart';
import 'portable_asset_uri.dart';
import 'project_repository.dart';

class IoAssetAvailabilityProbe implements AssetAvailabilityProbe {
  const IoAssetAvailabilityProbe();

  @override
  Future<bool> exists(String location) async {
    if (location.trim().isEmpty) {
      return false;
    }
    return File(location).exists();
  }
}

class IoProjectRepository implements ProjectRepository {
  IoProjectRepository({
    this.serializer = const ProjectDocumentSerializer(),
    PortableAssetUriPolicy uriPolicy = const PortableAssetUriPolicy(),
  }) : diagnostics = ProjectMediaDiagnostics(
         probe: const IoAssetAvailabilityProbe(),
         uriPolicy: uriPolicy,
       );

  final ProjectDocumentSerializer serializer;
  final ProjectMediaDiagnostics diagnostics;
  final List<ProjectSaveMetadata> _recent = [];

  @override
  Future<ProjectLoadResult> load(String location) async {
    final primary = File(location);
    final backup = File(_backupLocation(location));
    Object? primaryError;
    if (await primary.exists()) {
      try {
        return await _loadFile(primary, location, ProjectLoadSource.primary);
      } catch (error) {
        primaryError = error;
      }
    }
    if (await backup.exists()) {
      try {
        return await _loadFile(backup, location, ProjectLoadSource.backup);
      } catch (backupError) {
        throw ProjectRepositoryException(
          'Primary and backup project files are unreadable.',
          cause: backupError,
        );
      }
    }
    throw ProjectRepositoryException(
      'Project does not exist or is unreadable at $location.',
      cause: primaryError,
    );
  }

  @override
  Future<ProjectSaveResult> save(
    ReactifyProjectDocument project,
    String location,
  ) async {
    final encoded = serializer.encode(project);
    final target = File(location);
    final hadPrimary = await target.exists();
    await _atomicReplace(
      target,
      encoded,
      backupLocation: _backupLocation(location),
    );
    final metadata = _metadata(
      project,
      location,
      utf8.encode(encoded).length,
      autosave: false,
    );
    _remember(metadata);
    return ProjectSaveResult(
      metadata: metadata,
      backupLocation: hadPrimary ? _backupLocation(location) : null,
    );
  }

  @override
  Future<ProjectAutosaveResult> autosave(
    ReactifyProjectDocument project,
    String location,
  ) async {
    final encoded = serializer.encode(project);
    final autosaveLocation = _autosaveLocation(location);
    await _atomicReplace(File(autosaveLocation), encoded);
    final metadata = _metadata(
      project,
      autosaveLocation,
      utf8.encode(encoded).length,
      autosave: true,
    );
    _remember(metadata);
    return ProjectAutosaveResult(metadata: metadata);
  }

  @override
  Future<ProjectRecoveryResult> recover(String location) async {
    final attempted = <String>[];
    final candidates = <(String, ProjectLoadSource)>[
      (_autosaveLocation(location), ProjectLoadSource.autosave),
      (_backupLocation(location), ProjectLoadSource.backup),
      (location, ProjectLoadSource.primary),
    ];
    Object? lastError;
    for (final candidate in candidates) {
      attempted.add(candidate.$1);
      final file = File(candidate.$1);
      if (!await file.exists()) {
        continue;
      }
      try {
        final result = await _loadFile(file, location, candidate.$2);
        return ProjectRecoveryResult(
          loadResult: result,
          attemptedLocations: List.unmodifiable(attempted),
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw ProjectRepositoryException(
      'No valid recovery project was found.',
      cause: lastError,
    );
  }

  @override
  Future<List<ProjectSaveMetadata>> recentSaves() async {
    return List.unmodifiable(_recent);
  }

  Future<ProjectLoadResult> _loadFile(
    File file,
    String projectLocation,
    ProjectLoadSource source,
  ) async {
    final decoded = serializer.decode(await file.readAsString());
    return ProjectLoadResult(
      project: decoded.project,
      source: source,
      location: projectLocation,
      loadedAt: DateTime.now().toUtc(),
      missingMedia: await diagnostics.scan(decoded.project, projectLocation),
      migration: decoded.migration,
    );
  }

  Future<void> _atomicReplace(
    File target,
    String contents, {
    String? backupLocation,
  }) async {
    await target.parent.create(recursive: true);
    final temp = File(
      '${target.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    File? previous;
    try {
      await temp.writeAsString(contents, flush: true);
      if (await target.exists()) {
        previous = File(
          backupLocation ??
              '${target.path}.swap.${DateTime.now().microsecondsSinceEpoch}',
        );
        if (await previous.exists()) {
          await previous.delete();
        }
        await target.rename(previous.path);
      }
      try {
        await temp.rename(target.path);
      } catch (error) {
        if (previous != null && await previous.exists()) {
          await previous.rename(target.path);
        }
        rethrow;
      }
      if (backupLocation == null &&
          previous != null &&
          await previous.exists()) {
        await previous.delete();
      }
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  ProjectSaveMetadata _metadata(
    ReactifyProjectDocument project,
    String location,
    int byteLength, {
    required bool autosave,
  }) {
    return ProjectSaveMetadata(
      location: location,
      projectId: project.id,
      projectName: project.name,
      savedAt: DateTime.now().toUtc(),
      byteLength: byteLength,
      autosave: autosave,
    );
  }

  void _remember(ProjectSaveMetadata metadata) {
    _recent.removeWhere((item) => item.location == metadata.location);
    _recent.insert(0, metadata);
  }

  String _backupLocation(String location) => '$location.bak';

  String _autosaveLocation(String location) => '$location.autosave';
}

ProjectRepository createPlatformProjectRepository({
  ProjectDocumentSerializer serializer = const ProjectDocumentSerializer(),
  PortableAssetUriPolicy uriPolicy = const PortableAssetUriPolicy(),
}) {
  return IoProjectRepository(serializer: serializer, uriPolicy: uriPolicy);
}
