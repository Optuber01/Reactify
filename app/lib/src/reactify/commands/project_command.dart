import '../project/project.dart';

abstract interface class ProjectCommand {
  String get type;

  String get summary;

  Set<String> get affectedIds;

  ReactifyProjectDocument apply(ReactifyProjectDocument project);

  ProjectCommand invert(ReactifyProjectDocument project);

  Map<String, Object?> toJson();
}

class ProjectCommandException implements Exception {
  const ProjectCommandException(this.message, {this.issues = const []});

  final String message;
  final List<ProjectValidationIssue> issues;

  @override
  String toString() => 'ProjectCommandException: $message';
}

class ProjectChangeSummary {
  const ProjectChangeSummary({
    required this.label,
    required this.commandSummaries,
    required this.affectedIds,
  });

  final String label;
  final List<String> commandSummaries;
  final Set<String> affectedIds;

  Map<String, Object?> toJson() => canonicalJsonMap({
    'affectedIds': affectedIds.toList()..sort(),
    'commandSummaries': commandSummaries,
    'label': label,
  });
}

class ProjectCommandBatch implements ProjectCommand {
  const ProjectCommandBatch({required this.label, required this.commands});

  final String label;
  final List<ProjectCommand> commands;

  @override
  String get type => 'batch';

  @override
  String get summary => label;

  @override
  Set<String> get affectedIds => {
    for (final command in commands) ...command.affectedIds,
  };

  ProjectChangeSummary get changeSummary => ProjectChangeSummary(
    label: label,
    commandSummaries: [for (final command in commands) command.summary],
    affectedIds: affectedIds,
  );

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    var next = project;
    for (final command in commands) {
      next = command.apply(next);
    }
    return next;
  }

  ReactifyProjectDocument applyValidated(
    ReactifyProjectDocument project,
    ReactifyProjectValidator validator,
  ) {
    final next = apply(project);
    final issues = validator
        .validate(next)
        .where((issue) => issue.severity == ProjectValidationSeverity.error)
        .toList(growable: false);
    if (issues.isNotEmpty) {
      throw ProjectCommandException(
        'Command batch failed structural validation.',
        issues: issues,
      );
    }
    return next;
  }

  @override
  ProjectCommandBatch invert(ReactifyProjectDocument project) {
    var cursor = project;
    final inverses = <ProjectCommand>[];
    for (final command in commands) {
      inverses.insert(0, command.invert(cursor));
      cursor = command.apply(cursor);
    }
    return ProjectCommandBatch(label: 'Undo $label', commands: inverses);
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'commands': [for (final command in commands) command.toJson()],
    'label': label,
    'type': type,
  });
}

ProjectCommandException missingEntity(String kind, String id) {
  return ProjectCommandException('Missing $kind $id.');
}

ProjectCommandException duplicateEntity(String kind, String id) {
  return ProjectCommandException('$kind $id already exists.');
}
