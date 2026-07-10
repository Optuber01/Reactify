import '../commands/commands.dart';
import '../io/io.dart';
import '../project/project.dart';
import 'automation_protocol.dart';
import 'draft_revision.dart';
import 'draft_revision_storage.dart';
import 'draft_revision_storage_factory.dart';

class ProjectAutomationException implements Exception {
  const ProjectAutomationException(
    this.code,
    this.message, {
    this.details = const {},
  });

  final String code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => 'ProjectAutomationException: $message';
}

class ProjectAutomationService {
  ProjectAutomationService({
    ProjectRepository? repository,
    DraftRevisionStorage? draftStorage,
    this.validator = const ReactifyProjectValidator(),
  }) : repository = repository ?? createProjectRepository(),
       draftStorage = draftStorage ?? createDraftRevisionStorage();

  final ProjectRepository repository;
  final DraftRevisionStorage draftStorage;
  final ReactifyProjectValidator validator;

  static String defaultDraftLocation(String projectLocation) {
    return '$projectLocation.draft.json';
  }

  Future<AutomationOperationResult> inspect(
    String projectLocation, {
    String? draftLocation,
  }) async {
    if (draftLocation != null) {
      final draft = await _readDraft(projectLocation, draftLocation);
      return AutomationOperationResult(
        action: 'inspect',
        inspection: ProjectInspection.fromProject(draft.workingProject),
        summary: draft.summary,
        draftId: draft.draftId,
        draftLocation: draftLocation,
      );
    }
    final loaded = await repository.load(projectLocation);
    return AutomationOperationResult(
      action: 'inspect',
      inspection: _inspection(loaded),
    );
  }

  Future<AutomationValidationResult> validate(
    String projectLocation, {
    String? draftLocation,
  }) async {
    if (draftLocation != null) {
      final draft = await _readDraft(projectLocation, draftLocation);
      final issues = validator.validate(draft.workingProject);
      return AutomationValidationResult(
        inspection: ProjectInspection.fromProject(draft.workingProject),
        issues: issues,
      );
    }
    final loaded = await repository.load(projectLocation);
    return AutomationValidationResult(
      inspection: _inspection(loaded),
      issues: validator.validate(loaded.project),
    );
  }

  Future<AutomationOperationResult> apply(
    String projectLocation,
    ProjectCommandFileEnvelope envelope,
  ) async {
    final loaded = await repository.load(projectLocation);
    _requireWritablePrimary(loaded);
    envelope.validateFor(loaded.project);
    final next = envelope.batch.applyValidated(loaded.project, validator);
    await repository.save(next, projectLocation);
    return AutomationOperationResult(
      action: 'apply',
      inspection: ProjectInspection.fromProject(next),
      summary: envelope.batch.changeSummary,
    );
  }

  Future<AutomationOperationResult> createDraft(
    String projectLocation,
    ProjectCommandFileEnvelope envelope, {
    String? draftLocation,
  }) async {
    final location = draftLocation ?? defaultDraftLocation(projectLocation);
    if (await draftStorage.exists(location)) {
      throw ProjectAutomationException(
        'draft.exists',
        'A draft already exists at $location.',
      );
    }
    final loaded = await repository.load(projectLocation);
    _requireWritablePrimary(loaded);
    envelope.validateFor(loaded.project);
    final working = envelope.batch.applyValidated(loaded.project, validator);
    final revision = PersistentDraftRevision(
      draftId: envelope.transactionId,
      projectLocation: projectLocation,
      baseFingerprint: projectFingerprint(loaded.project),
      commandEnvelope: envelope,
      workingProject: working,
      summary: envelope.batch.changeSummary,
    );
    await draftStorage.write(location, revision);
    return AutomationOperationResult(
      action: 'draft',
      inspection: ProjectInspection.fromProject(working),
      summary: revision.summary,
      draftId: revision.draftId,
      draftLocation: location,
    );
  }

  Future<AutomationOperationResult> commitDraft(
    String projectLocation, {
    String? draftLocation,
  }) async {
    final location = draftLocation ?? defaultDraftLocation(projectLocation);
    final draft = await _readDraft(projectLocation, location);
    final loaded = await repository.load(projectLocation);
    _requireWritablePrimary(loaded);
    final currentFingerprint = projectFingerprint(loaded.project);
    if (currentFingerprint != draft.baseFingerprint) {
      if (currentFingerprint == projectFingerprint(draft.workingProject)) {
        await draftStorage.delete(location);
        return AutomationOperationResult(
          action: 'commit-draft',
          inspection: ProjectInspection.fromProject(draft.workingProject),
          summary: draft.summary,
          draftId: draft.draftId,
          draftLocation: location,
        );
      }
      throw ProjectAutomationException(
        'draft.conflict',
        'The primary project changed after the draft was created.',
        details: {
          'actualFingerprint': currentFingerprint,
          'expectedFingerprint': draft.baseFingerprint,
        },
      );
    }
    draft.commandEnvelope.validateFor(loaded.project);
    final issues = validator
        .validate(draft.workingProject)
        .where((issue) => issue.severity == ProjectValidationSeverity.error)
        .toList(growable: false);
    if (issues.isNotEmpty) {
      throw ProjectAutomationException(
        'draft.invalid',
        'Draft project failed validation.',
        details: {
          'issues': [
            for (final issue in issues)
              {
                'code': issue.code,
                'message': issue.message,
                'path': issue.path,
              },
          ],
        },
      );
    }
    await repository.save(draft.workingProject, projectLocation);
    await draftStorage.delete(location);
    return AutomationOperationResult(
      action: 'commit-draft',
      inspection: ProjectInspection.fromProject(draft.workingProject),
      summary: draft.summary,
      draftId: draft.draftId,
      draftLocation: location,
    );
  }

  Future<AutomationOperationResult> rollbackDraft(
    String projectLocation, {
    String? draftLocation,
  }) async {
    final location = draftLocation ?? defaultDraftLocation(projectLocation);
    final draft = await _readDraft(projectLocation, location);
    await draftStorage.delete(location);
    final loaded = await repository.load(projectLocation);
    return AutomationOperationResult(
      action: 'rollback-draft',
      inspection: _inspection(loaded),
      summary: ProjectChangeSummary(
        label: 'Roll back ${draft.summary.label}',
        commandSummaries: [
          for (final command in draft.summary.commandSummaries.reversed)
            'Discard $command',
        ],
        affectedIds: draft.summary.affectedIds,
      ),
      draftId: draft.draftId,
      draftLocation: location,
    );
  }

  Future<PersistentDraftRevision> _readDraft(
    String projectLocation,
    String draftLocation,
  ) async {
    if (!await draftStorage.exists(draftLocation)) {
      throw ProjectAutomationException(
        'draft.missing',
        'Draft does not exist at $draftLocation.',
      );
    }
    final draft = await draftStorage.read(draftLocation);
    if (draft.projectLocation != projectLocation) {
      throw ProjectAutomationException(
        'draft.projectMismatch',
        'Draft belongs to ${draft.projectLocation}.',
      );
    }
    return draft;
  }

  void _requireWritablePrimary(ProjectLoadResult loaded) {
    if (loaded.source != ProjectLoadSource.primary &&
        loaded.source != ProjectLoadSource.memory) {
      throw ProjectAutomationException(
        'project.recovered',
        'Refusing to mutate a project loaded from ${loaded.source.name}.',
      );
    }
  }

  ProjectInspection _inspection(ProjectLoadResult loaded) {
    return ProjectInspection.fromProject(
      loaded.project,
      missingMedia: [
        for (final item in loaded.missingMedia)
          (
            assetId: item.assetId,
            reason: item.reason.name,
            resolvedLocation: item.resolvedLocation,
          ),
      ],
    );
  }
}
