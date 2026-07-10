import '../project/project.dart';
import 'project_command.dart';

typedef ProjectStoreListener =
    void Function(
      ReactifyProjectDocument project,
      ProjectChangeSummary summary,
    );

class DraftRevisionState {
  const DraftRevisionState({
    required this.id,
    required this.label,
    required this.commandCount,
  });

  final String id;
  final String label;
  final int commandCount;
}

class ProjectCommandStore {
  ProjectCommandStore(
    ReactifyProjectDocument initialProject, {
    ReactifyProjectValidator validator = const ReactifyProjectValidator(),
    this.historyLimit = 200,
  }) : _project = initialProject,
       _validator = validator {
    final issues = _errorsFor(initialProject);
    if (issues.isNotEmpty) {
      throw ProjectCommandException(
        'Initial project failed structural validation.',
        issues: issues,
      );
    }
  }

  final ReactifyProjectValidator _validator;
  final int historyLimit;
  ReactifyProjectDocument _project;
  final List<_HistoryEntry> _undoStack = [];
  final List<_HistoryEntry> _redoStack = [];
  final List<ProjectStoreListener> _listeners = [];
  _DraftRevision? _draft;
  int _draftSerial = 0;

  ReactifyProjectDocument get project => _project;

  bool get canUndo => _draft == null && _undoStack.isNotEmpty;

  bool get canRedo => _draft == null && _redoStack.isNotEmpty;

  bool get hasActiveDraft => _draft != null;

  DraftRevisionState? get activeDraft {
    final draft = _draft;
    if (draft == null) {
      return null;
    }
    return DraftRevisionState(
      id: draft.id,
      label: draft.label,
      commandCount: draft.commands.length,
    );
  }

  void addListener(ProjectStoreListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(ProjectStoreListener listener) {
    _listeners.remove(listener);
  }

  ProjectChangeSummary execute(ProjectCommand command, {String? label}) {
    return executeBatch(
      ProjectCommandBatch(label: label ?? command.summary, commands: [command]),
    );
  }

  ProjectChangeSummary executeBatch(ProjectCommandBatch batch) {
    if (_draft != null) {
      throw const ProjectCommandException(
        'Use applyDraft while a draft revision is active.',
      );
    }
    final inverse = batch.invert(_project);
    final next = batch.applyValidated(_project, _validator);
    final entry = _HistoryEntry(
      forward: batch,
      inverse: inverse,
      summary: batch.changeSummary,
    );
    _project = next;
    _undoStack.add(entry);
    if (_undoStack.length > historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _notify(entry.summary);
    return entry.summary;
  }

  ProjectChangeSummary undo() {
    if (_draft != null) {
      throw const ProjectCommandException(
        'Commit or roll back the active draft before undo.',
      );
    }
    if (_undoStack.isEmpty) {
      throw const ProjectCommandException('Nothing to undo.');
    }
    final entry = _undoStack.removeLast();
    _project = entry.inverse.applyValidated(_project, _validator);
    _redoStack.add(entry);
    final summary = ProjectChangeSummary(
      label: 'Undo ${entry.summary.label}',
      commandSummaries: entry.inverse.changeSummary.commandSummaries,
      affectedIds: entry.summary.affectedIds,
    );
    _notify(summary);
    return summary;
  }

  ProjectChangeSummary redo() {
    if (_draft != null) {
      throw const ProjectCommandException(
        'Commit or roll back the active draft before redo.',
      );
    }
    if (_redoStack.isEmpty) {
      throw const ProjectCommandException('Nothing to redo.');
    }
    final entry = _redoStack.removeLast();
    _project = entry.forward.applyValidated(_project, _validator);
    _undoStack.add(entry);
    final summary = ProjectChangeSummary(
      label: 'Redo ${entry.summary.label}',
      commandSummaries: entry.forward.changeSummary.commandSummaries,
      affectedIds: entry.summary.affectedIds,
    );
    _notify(summary);
    return summary;
  }

  DraftRevisionState startDraft(String label) {
    if (_draft != null) {
      throw const ProjectCommandException(
        'A draft revision is already active.',
      );
    }
    _draftSerial += 1;
    final draft = _DraftRevision(
      id: 'draft.$_draftSerial',
      label: label,
      base: _project,
    );
    _draft = draft;
    return DraftRevisionState(id: draft.id, label: label, commandCount: 0);
  }

  ProjectChangeSummary applyDraft(ProjectCommand command) {
    return applyDraftBatch(
      ProjectCommandBatch(label: command.summary, commands: [command]),
    );
  }

  ProjectChangeSummary applyDraftBatch(ProjectCommandBatch batch) {
    final draft = _draft;
    if (draft == null) {
      throw const ProjectCommandException('No draft revision is active.');
    }
    final next = batch.applyValidated(_project, _validator);
    draft.commands.addAll(batch.commands);
    _project = next;
    final summary = ProjectChangeSummary(
      label: 'Draft ${draft.label}: ${batch.label}',
      commandSummaries: batch.changeSummary.commandSummaries,
      affectedIds: batch.affectedIds,
    );
    _notify(summary);
    return summary;
  }

  ProjectChangeSummary commitDraft() {
    final draft = _draft;
    if (draft == null) {
      throw const ProjectCommandException('No draft revision is active.');
    }
    final forward = ProjectCommandBatch(
      label: draft.label,
      commands: List.unmodifiable(draft.commands),
    );
    final inverse = forward.invert(draft.base);
    final summary = forward.changeSummary;
    _draft = null;
    if (forward.commands.isNotEmpty) {
      _undoStack.add(
        _HistoryEntry(forward: forward, inverse: inverse, summary: summary),
      );
      if (_undoStack.length > historyLimit) {
        _undoStack.removeAt(0);
      }
      _redoStack.clear();
    }
    _notify(summary);
    return summary;
  }

  ProjectChangeSummary rollbackDraft() {
    final draft = _draft;
    if (draft == null) {
      throw const ProjectCommandException('No draft revision is active.');
    }
    final affectedIds = <String>{
      for (final command in draft.commands) ...command.affectedIds,
    };
    _project = draft.base;
    _draft = null;
    final summary = ProjectChangeSummary(
      label: 'Roll back ${draft.label}',
      commandSummaries: [
        for (final command in draft.commands.reversed)
          'Roll back ${command.summary}',
      ],
      affectedIds: affectedIds,
    );
    _notify(summary);
    return summary;
  }

  List<ProjectValidationIssue> _errorsFor(ReactifyProjectDocument project) {
    return _validator
        .validate(project)
        .where((issue) => issue.severity == ProjectValidationSeverity.error)
        .toList(growable: false);
  }

  void _notify(ProjectChangeSummary summary) {
    for (final listener in List<ProjectStoreListener>.from(_listeners)) {
      listener(_project, summary);
    }
  }
}

class _HistoryEntry {
  const _HistoryEntry({
    required this.forward,
    required this.inverse,
    required this.summary,
  });

  final ProjectCommandBatch forward;
  final ProjectCommandBatch inverse;
  final ProjectChangeSummary summary;
}

class _DraftRevision {
  _DraftRevision({required this.id, required this.label, required this.base});

  final String id;
  final String label;
  final ReactifyProjectDocument base;
  final List<ProjectCommand> commands = [];
}
