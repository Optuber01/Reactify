import 'dart:io';

import 'project_codec.dart';
import 'project_document.dart';
import 'project_error.dart';

enum ProjectFileSource { primary, pendingWrite, recoveryBackup }

class ProjectFileDiagnostic {
  const ProjectFileDiagnostic({
    required this.source,
    required this.path,
    required this.failure,
  });

  final ProjectFileSource source;
  final String path;
  final ProjectFailure failure;

  Map<String, Object?> toJson() {
    return {'source': source.name, 'path': path, 'failure': failure.toJson()};
  }
}

class ProjectOpenResult {
  const ProjectOpenResult({
    required this.project,
    required this.source,
    required this.path,
    required this.sourcePath,
    required this.diagnostics,
  });

  final ReactifyProject project;
  final ProjectFileSource source;
  final String path;
  final String sourcePath;
  final List<ProjectFileDiagnostic> diagnostics;

  bool get recovered => source != ProjectFileSource.primary;
  bool get requiresSave => recovered;
}

class ProjectSaveResult {
  const ProjectSaveResult({
    required this.path,
    required this.revision,
    required this.recoveryBackupAvailable,
  });

  final String path;
  final int revision;
  final bool recoveryBackupAvailable;
}

class ProjectFileStore {
  const ProjectFileStore({required this.codec});

  final ProjectCodec codec;
  static final Map<String, Future<void>> _saveTails = {};

  Future<ProjectSaveResult> save(String path, ReactifyProject project) {
    final target = _targetFile(
      path,
      operation: 'save',
      failureCode: ProjectErrorCode.fileWriteFailed,
    );
    final key = _pathKey(target);
    final predecessor = _saveTails[key] ?? Future<void>.value();
    final operation = predecessor.then((_) => _saveToTarget(target, project));
    final tail = operation.then<void>((_) {}, onError: (_, _) {});
    _saveTails[key] = tail;
    tail.then((_) {
      if (identical(_saveTails[key], tail)) {
        _saveTails.remove(key);
      }
    });
    return operation;
  }

  Future<ProjectSaveResult> _saveToTarget(
    File target,
    ReactifyProject project,
  ) async {
    final pending = File('${target.path}.reactify-tmp');
    final backup = File('${target.path}.reactify-bak');
    var targetMoved = false;
    try {
      await target.parent.create(recursive: true);
      if (await pending.exists()) {
        await pending.delete();
      }
      final encoded = codec.encode(project);
      await pending.writeAsString(encoded, flush: true);
      final stagedSource = await pending.readAsString();
      if (stagedSource != encoded) {
        throw const ProjectFailure(
          code: ProjectErrorCode.fileWriteFailed,
          message: 'Staged project bytes did not match the encoded project.',
          operation: 'save',
        );
      }
      final staged = codec.decode(stagedSource);
      if (staged.id != project.id ||
          staged.revision != project.revision ||
          codec.encode(staged) != encoded) {
        throw const ProjectFailure(
          code: ProjectErrorCode.fileWriteFailed,
          message:
              'Staged project verification did not preserve project content.',
          operation: 'save',
        );
      }
      if (await target.exists()) {
        if (await backup.exists()) {
          await backup.delete();
        }
        await target.rename(backup.path);
        targetMoved = true;
      }
      await pending.rename(target.path);
      return ProjectSaveResult(
        path: target.path,
        revision: project.revision,
        recoveryBackupAvailable: targetMoved,
      );
    } on ProjectFailure catch (failure) {
      if (targetMoved) {
        await _restoreAfterFailedSave(target, backup, failure);
      }
      rethrow;
    } on FileSystemException catch (error) {
      final failure = ProjectFailure(
        code: ProjectErrorCode.fileWriteFailed,
        message: 'Could not save the Reactify project.',
        operation: 'save',
        path: target.path,
        details: {'osError': error.osError?.message},
      );
      if (targetMoved) {
        await _restoreAfterFailedSave(target, backup, failure);
      }
      throw failure;
    }
  }

  Future<ProjectOpenResult> open(String path) async {
    final target = _targetFile(
      path,
      operation: 'open',
      failureCode: ProjectErrorCode.fileReadFailed,
    );
    final candidates = <_ProjectFileCandidate>[
      _ProjectFileCandidate(ProjectFileSource.primary, target),
      _ProjectFileCandidate(
        ProjectFileSource.pendingWrite,
        File('${target.path}.reactify-tmp'),
      ),
      _ProjectFileCandidate(
        ProjectFileSource.recoveryBackup,
        File('${target.path}.reactify-bak'),
      ),
    ];
    final valid = <_DecodedCandidate>[];
    final diagnostics = <ProjectFileDiagnostic>[];
    var existingCandidateCount = 0;
    for (final candidate in candidates) {
      if (!await candidate.file.exists()) {
        continue;
      }
      existingCandidateCount += 1;
      try {
        final source = await candidate.file.readAsString();
        valid.add(
          _DecodedCandidate(
            source: candidate.source,
            file: candidate.file,
            project: codec.decode(source),
          ),
        );
      } on ProjectFailure catch (failure) {
        diagnostics.add(
          ProjectFileDiagnostic(
            source: candidate.source,
            path: candidate.file.path,
            failure: failure,
          ),
        );
      } on FileSystemException catch (error) {
        diagnostics.add(
          ProjectFileDiagnostic(
            source: candidate.source,
            path: candidate.file.path,
            failure: ProjectFailure(
              code: ProjectErrorCode.fileReadFailed,
              message: 'Could not read project candidate.',
              operation: 'open',
              path: candidate.file.path,
              details: {'osError': error.osError?.message},
            ),
          ),
        );
      }
    }
    if (valid.isEmpty) {
      if (diagnostics.isNotEmpty &&
          diagnostics.length == existingCandidateCount &&
          diagnostics.every(
            (diagnostic) =>
                diagnostic.failure.code == ProjectErrorCode.unsupportedVersion,
          )) {
        final failure = diagnostics.first.failure;
        throw ProjectFailure(
          code: failure.code,
          message: failure.message,
          operation: 'open',
          path: target.path,
          field: failure.field,
          details: {
            ...failure.details,
            'diagnostics': [
              for (final diagnostic in diagnostics) diagnostic.toJson(),
            ],
          },
        );
      }
      throw ProjectFailure(
        code: ProjectErrorCode.fileReadFailed,
        message: existingCandidateCount == 0
            ? 'Project file and recovery files do not exist.'
            : 'No valid project or recovery file could be opened.',
        operation: 'open',
        path: target.path,
        details: {
          'candidateCount': existingCandidateCount,
          'diagnostics': [
            for (final diagnostic in diagnostics) diagnostic.toJson(),
          ],
        },
      );
    }
    final primaryCandidates = valid
        .where((candidate) => candidate.source == ProjectFileSource.primary)
        .toList();
    final eligible = <_DecodedCandidate>[];
    if (primaryCandidates.isNotEmpty) {
      final primary = primaryCandidates.single;
      for (final candidate in valid) {
        if (candidate.project.id == primary.project.id) {
          eligible.add(candidate);
          continue;
        }
        diagnostics.add(
          ProjectFileDiagnostic(
            source: candidate.source,
            path: candidate.file.path,
            failure: ProjectFailure(
              code: ProjectErrorCode.recoveryRequired,
              message:
                  'Recovery candidate belongs to a different project and was ignored.',
              operation: 'open',
              path: candidate.file.path,
              details: {
                'primaryProjectId': primary.project.id.value,
                'candidateProjectId': candidate.project.id.value,
              },
            ),
          ),
        );
      }
    } else {
      final projectIds = valid
          .map((candidate) => candidate.project.id.value)
          .toSet();
      if (projectIds.length > 1) {
        throw ProjectFailure(
          code: ProjectErrorCode.recoveryRequired,
          message:
              'Recovery files belong to different projects and cannot be selected safely.',
          operation: 'open',
          path: target.path,
          details: {
            'candidates': [for (final candidate in valid) candidate.toJson()],
            'diagnostics': [
              for (final diagnostic in diagnostics) diagnostic.toJson(),
            ],
          },
        );
      }
      eligible.addAll(valid);
    }
    eligible.sort((left, right) {
      final revisionOrder = right.project.revision.compareTo(
        left.project.revision,
      );
      if (revisionOrder != 0) {
        return revisionOrder;
      }
      return _sourcePriority(
        left.source,
      ).compareTo(_sourcePriority(right.source));
    });
    final selected = eligible.first;
    return ProjectOpenResult(
      project: selected.project,
      source: selected.source,
      path: target.path,
      sourcePath: selected.file.path,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  Future<void> _restoreAfterFailedSave(
    File target,
    File backup,
    ProjectFailure originalFailure,
  ) async {
    try {
      await _restoreBackup(target, backup);
    } on ProjectFailure catch (restoreFailure) {
      throw ProjectFailure(
        code: ProjectErrorCode.recoveryRequired,
        message:
            'Save failed and the previous project requires manual recovery.',
        operation: 'save',
        path: target.path,
        details: {
          'originalFailure': originalFailure.toJson(),
          'restoreFailure': restoreFailure.toJson(),
          'backupPath': backup.path,
        },
      );
    }
  }

  Future<void> _restoreBackup(File target, File backup) async {
    try {
      if (await target.exists()) {
        throw ProjectFailure(
          code: ProjectErrorCode.recoveryRequired,
          message:
              'Both the replacement target and recovery backup exist after a failed save.',
          operation: 'restore',
          path: target.path,
          details: {'backupPath': backup.path},
        );
      }
      if (!await backup.exists()) {
        throw ProjectFailure(
          code: ProjectErrorCode.recoveryRequired,
          message: 'The previous project backup is missing.',
          operation: 'restore',
          path: target.path,
          details: {'backupPath': backup.path},
        );
      }
      await backup.rename(target.path);
    } on ProjectFailure {
      rethrow;
    } on FileSystemException catch (error) {
      throw ProjectFailure(
        code: ProjectErrorCode.recoveryRequired,
        message: 'Save failed and the previous project could not be restored.',
        operation: 'restore',
        path: target.path,
        details: {'backupPath': backup.path, 'osError': error.osError?.message},
      );
    }
  }
}

class _ProjectFileCandidate {
  const _ProjectFileCandidate(this.source, this.file);

  final ProjectFileSource source;
  final File file;
}

class _DecodedCandidate extends _ProjectFileCandidate {
  const _DecodedCandidate({
    required ProjectFileSource source,
    required File file,
    required this.project,
  }) : super(source, file);

  final ReactifyProject project;

  Map<String, Object?> toJson() {
    return {
      'source': source.name,
      'path': file.path,
      'projectId': project.id.value,
      'revision': project.revision,
    };
  }
}

int _sourcePriority(ProjectFileSource source) {
  return switch (source) {
    ProjectFileSource.primary => 0,
    ProjectFileSource.pendingWrite => 1,
    ProjectFileSource.recoveryBackup => 2,
  };
}

File _targetFile(
  String path, {
  required String operation,
  required ProjectErrorCode failureCode,
}) {
  if (path.trim().isEmpty || path.contains('\u0000')) {
    throw ProjectFailure(
      code: failureCode,
      message: 'Project path must be a non-empty filesystem path.',
      operation: operation,
      path: path,
    );
  }
  try {
    return File.fromUri(File(path).absolute.uri.normalizePath());
  } on FileSystemException catch (error) {
    throw ProjectFailure(
      code: failureCode,
      message: 'Project path could not be resolved.',
      operation: operation,
      path: path,
      details: {'osError': error.osError?.message},
    );
  }
}

String _pathKey(File file) {
  final path = file.path.replaceAll('\\', '/');
  return Platform.isWindows ? path.toLowerCase() : path;
}
