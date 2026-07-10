import '../project/project.dart';
import 'project_repository.dart';

class PermissiveAssetAvailabilityProbe implements AssetAvailabilityProbe {
  const PermissiveAssetAvailabilityProbe();

  @override
  Future<bool> exists(String location) async => true;
}

class InMemoryAssetAvailabilityProbe implements AssetAvailabilityProbe {
  InMemoryAssetAvailabilityProbe([Iterable<String> available = const []])
    : availableLocations = available.toSet();

  final Set<String> availableLocations;

  @override
  Future<bool> exists(String location) async {
    return availableLocations.contains(location);
  }
}

class InMemoryProjectRepository implements ProjectRepository {
  InMemoryProjectRepository({
    this.serializer = const ProjectDocumentSerializer(),
    AssetAvailabilityProbe probe = const PermissiveAssetAvailabilityProbe(),
  }) : diagnostics = ProjectMediaDiagnostics(probe: probe);

  final ProjectDocumentSerializer serializer;
  final ProjectMediaDiagnostics diagnostics;
  final Map<String, String> storage = {};
  final List<ProjectSaveMetadata> _recent = [];

  @override
  Future<ProjectLoadResult> load(String location) async {
    final primary = storage[location];
    if (primary == null) {
      throw ProjectRepositoryException('Project does not exist at $location.');
    }
    try {
      return await _decode(primary, location, ProjectLoadSource.memory);
    } catch (primaryError) {
      final backup = storage[_backupLocation(location)];
      if (backup == null) {
        rethrow;
      }
      try {
        return await _decode(backup, location, ProjectLoadSource.backup);
      } catch (_) {
        throw ProjectRepositoryException(
          'Primary and backup project data are unreadable.',
          cause: primaryError,
        );
      }
    }
  }

  @override
  Future<ProjectSaveResult> save(
    ReactifyProjectDocument project,
    String location,
  ) async {
    final encoded = serializer.encode(project);
    final existing = storage[location];
    if (existing != null) {
      storage[_backupLocation(location)] = existing;
    }
    storage[location] = encoded;
    final metadata = _metadata(
      project,
      location,
      encoded.length,
      autosave: false,
    );
    _remember(metadata);
    return ProjectSaveResult(
      metadata: metadata,
      backupLocation: existing == null ? null : _backupLocation(location),
    );
  }

  @override
  Future<ProjectAutosaveResult> autosave(
    ReactifyProjectDocument project,
    String location,
  ) async {
    final encoded = serializer.encode(project);
    final autosaveLocation = _autosaveLocation(location);
    storage[autosaveLocation] = encoded;
    final metadata = _metadata(
      project,
      autosaveLocation,
      encoded.length,
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
      (location, ProjectLoadSource.memory),
    ];
    Object? lastError;
    for (final candidate in candidates) {
      attempted.add(candidate.$1);
      final source = storage[candidate.$1];
      if (source == null) {
        continue;
      }
      try {
        final result = await _decode(source, location, candidate.$2);
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

  Future<ProjectLoadResult> _decode(
    String source,
    String projectLocation,
    ProjectLoadSource loadSource,
  ) async {
    final decoded = serializer.decode(source);
    return ProjectLoadResult(
      project: decoded.project,
      source: loadSource,
      location: projectLocation,
      loadedAt: DateTime.now().toUtc(),
      missingMedia: await diagnostics.scan(decoded.project, projectLocation),
      migration: decoded.migration,
    );
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
