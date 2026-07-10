import '../project/project.dart';

typedef ProjectJsonMigration =
    Map<String, Object?> Function(Map<String, Object?> source);

class ProjectMigrationResult {
  const ProjectMigrationResult({
    required this.json,
    required this.fromVersion,
    required this.toVersion,
  });

  final Map<String, Object?> json;
  final int fromVersion;
  final int toVersion;

  bool get migrated => fromVersion != toVersion;
}

class ProjectSchemaMigrationRegistry {
  const ProjectSchemaMigrationRegistry({
    this.currentVersion = reactifyReactionProjectSchemaVersion,
    this.migrations = const {},
  });

  final int currentVersion;
  final Map<int, ProjectJsonMigration> migrations;

  ProjectMigrationResult migrate(Map<String, Object?> source) {
    final fromVersion = jsonInt(source, 'schemaVersion');
    if (fromVersion < 1) {
      throw FormatException('Invalid project schema $fromVersion.');
    }
    if (fromVersion > currentVersion) {
      throw FormatException(
        'Project schema $fromVersion is newer than supported schema $currentVersion.',
      );
    }
    var version = fromVersion;
    var json = canonicalJsonMap(source);
    while (version < currentVersion) {
      final migration = migrations[version];
      if (migration == null) {
        throw FormatException(
          'No project migration is registered from schema $version.',
        );
      }
      json = canonicalJsonMap(migration(json));
      final nextVersion = jsonInt(json, 'schemaVersion');
      if (nextVersion != version + 1) {
        throw FormatException(
          'Migration from schema $version produced schema $nextVersion.',
        );
      }
      version = nextVersion;
    }
    return ProjectMigrationResult(
      json: json,
      fromVersion: fromVersion,
      toVersion: version,
    );
  }
}
