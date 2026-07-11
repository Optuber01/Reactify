enum ProjectErrorCode {
  invalidId,
  invalidName,
  invalidCharacterCode,
  invalidMetadata,
  invalidReference,
  invalidProject,
  unsupportedVersion,
  duplicateId,
  notFound,
  referenceConflict,
  commandRejected,
  nothingToUndo,
  nothingToRedo,
  fileReadFailed,
  fileWriteFailed,
  recoveryRequired,
  internal,
}

class ProjectFailure implements Exception {
  const ProjectFailure({
    required this.code,
    required this.message,
    this.operation,
    this.path,
    this.field,
    this.details = const {},
  });

  final ProjectErrorCode code;
  final String message;
  final String? operation;
  final String? path;
  final String? field;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return {
      'code': code.name,
      'message': message,
      if (operation != null) 'operation': operation,
      if (path != null) 'path': path,
      if (field != null) 'field': field,
      if (details.isNotEmpty) 'details': details,
    };
  }

  @override
  String toString() => 'ProjectFailure(${code.name}): $message';
}
