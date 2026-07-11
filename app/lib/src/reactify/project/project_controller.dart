import 'project_command.dart';
import 'project_document.dart';
import 'project_error.dart';
import 'project_file_store.dart';

sealed class ProjectOutcome<T> {
  const ProjectOutcome();
}

class ProjectSuccess<T> extends ProjectOutcome<T> {
  const ProjectSuccess(this.value);

  final T value;
}

class ProjectRejected<T> extends ProjectOutcome<T> {
  const ProjectRejected(this.failure);

  final ProjectFailure failure;
}

class ProjectController {
  ProjectController({
    required ReactifyProject project,
    required this.context,
    int undoLimit = 200,
    bool initiallySaved = false,
    this.onListenerError,
  }) : _project = project,
       _undoLimit = undoLimit,
       _savedStateToken = initiallySaved ? 0 : null,
       _savedRevision = initiallySaved ? project.revision : null {
    if (undoLimit < 1) {
      throw ArgumentError.value(undoLimit, 'undoLimit', 'Must be positive.');
    }
    project.validate();
  }

  final ProjectCommandContext context;
  final void Function(Object error, StackTrace stackTrace)? onListenerError;
  final int _undoLimit;
  ReactifyProject _project;
  final List<_ProjectHistoryEntry> _undo = [];
  final List<_ProjectHistoryEntry> _redo = [];
  final List<void Function(ReactifyProject)> _listeners = [];
  int _stateToken = 0;
  int _nextStateToken = 0;
  int? _savedStateToken;
  int? _savedRevision;
  String? _savedPath;
  Future<void> _saveTail = Future<void>.value();

  ReactifyProject get project => _project;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isDirty =>
      _savedStateToken != _stateToken || _savedRevision != _project.revision;
  String? get savedPath => _savedPath;

  void addListener(void Function(ReactifyProject) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function(ReactifyProject) listener) {
    _listeners.remove(listener);
  }

  ProjectOutcome<ReactifyProject> execute(ProjectCommand command) {
    try {
      final candidate = command.apply(_project, context);
      candidate.validate();
      if (identical(candidate, _project)) {
        return ProjectSuccess(_project);
      }
      final next = candidate.copyWith(revision: _project.revision + 1);
      _undo.add(_ProjectHistoryEntry(_project, _stateToken));
      if (_undo.length > _undoLimit) {
        _undo.removeAt(0);
      }
      _redo.clear();
      _nextStateToken += 1;
      _replace(next, _nextStateToken);
      return ProjectSuccess(next);
    } on ProjectFailure catch (failure) {
      return ProjectRejected(failure);
    } on FormatException catch (error) {
      return ProjectRejected(
        ProjectFailure(
          code: ProjectErrorCode.commandRejected,
          message: error.message.toString(),
          operation: command.name,
        ),
      );
    } on ArgumentError catch (error) {
      return ProjectRejected(
        ProjectFailure(
          code: ProjectErrorCode.commandRejected,
          message: error.message?.toString() ?? error.toString(),
          operation: command.name,
        ),
      );
    } catch (error) {
      return ProjectRejected(
        ProjectFailure(
          code: ProjectErrorCode.internal,
          message: 'Unexpected failure while applying ${command.name}.',
          operation: command.name,
          details: {'runtimeType': error.runtimeType.toString()},
        ),
      );
    }
  }

  ProjectOutcome<ReactifyProject> undo() {
    if (_undo.isEmpty) {
      return const ProjectRejected(
        ProjectFailure(
          code: ProjectErrorCode.nothingToUndo,
          message: 'There is no project change to undo.',
          operation: 'undo',
        ),
      );
    }
    final previous = _undo.removeLast();
    _redo.add(_ProjectHistoryEntry(_project, _stateToken));
    final restored = previous.project.copyWith(revision: _project.revision + 1);
    _replace(restored, previous.stateToken);
    return ProjectSuccess(restored);
  }

  ProjectOutcome<ReactifyProject> redo() {
    if (_redo.isEmpty) {
      return const ProjectRejected(
        ProjectFailure(
          code: ProjectErrorCode.nothingToRedo,
          message: 'There is no project change to redo.',
          operation: 'redo',
        ),
      );
    }
    final nextState = _redo.removeLast();
    _undo.add(_ProjectHistoryEntry(_project, _stateToken));
    if (_undo.length > _undoLimit) {
      _undo.removeAt(0);
    }
    final restored = nextState.project.copyWith(
      revision: _project.revision + 1,
    );
    _replace(restored, nextState.stateToken);
    return ProjectSuccess(restored);
  }

  Future<ProjectOutcome<ProjectSaveResult>> save(
    ProjectFileStore store,
    String path,
  ) {
    final savingProject = _project;
    final savingStateToken = _stateToken;
    final operation = _saveTail.then(
      (_) => _saveSnapshot(store, path, savingProject, savingStateToken),
    );
    _saveTail = operation.then<void>((_) {});
    return operation;
  }

  Future<ProjectOutcome<ProjectSaveResult>> _saveSnapshot(
    ProjectFileStore store,
    String path,
    ReactifyProject savingProject,
    int savingStateToken,
  ) async {
    try {
      final result = await store.save(path, savingProject);
      if (_stateToken == savingStateToken &&
          _project.revision == savingProject.revision) {
        _savedStateToken = savingStateToken;
        _savedRevision = savingProject.revision;
        _savedPath = result.path;
      }
      return ProjectSuccess(result);
    } on ProjectFailure catch (failure) {
      return ProjectRejected(failure);
    } catch (error) {
      return ProjectRejected(
        ProjectFailure(
          code: ProjectErrorCode.internal,
          message: 'Unexpected failure while saving the project.',
          operation: 'save',
          path: path,
          details: {'runtimeType': error.runtimeType.toString()},
        ),
      );
    }
  }

  void markSaved() {
    _savedStateToken = _stateToken;
    _savedRevision = _project.revision;
  }

  void _replace(ReactifyProject project, int stateToken) {
    _project = project;
    _stateToken = stateToken;
    for (final listener in List.of(_listeners)) {
      try {
        listener(project);
      } catch (error, stackTrace) {
        try {
          onListenerError?.call(error, stackTrace);
        } catch (_) {}
      }
    }
  }
}

class _ProjectHistoryEntry {
  const _ProjectHistoryEntry(this.project, this.stateToken);

  final ReactifyProject project;
  final int stateToken;
}
