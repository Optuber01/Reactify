import 'dart:async';

import '../media/media.dart';
import 'reaction_export_models.dart';

abstract interface class ReactionExportJob {
  Stream<ExportProgress> get progress;

  bool get isRunning;

  ReactionExportResumeSnapshot get resumeSnapshot;

  Future<ReactionExportSummary> run();

  Future<ReactionExportSummary> resume();

  Future<ReactionExportSummary> retryFailures();

  Future<void> cancel();

  Future<void> dispose();
}

class ReactionBulkExportJob implements ReactionExportJob {
  ReactionBulkExportJob({
    required this.plan,
    required this.renderer,
    required this.writer,
    ReactionExportResumeSnapshot? resumeSnapshot,
  }) : _renderedArtifacts = {},
       _materializedArtifacts = {} {
    if (resumeSnapshot != null && resumeSnapshot.planKey != plan.planKey) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'The resume snapshot belongs to a different export plan.',
      );
    }
    final renderKeys = plan.artifacts
        .map((artifact) => artifact.contentKey)
        .toSet();
    final materializationIds = plan.materializations
        .map((mapping) => mapping.id)
        .toSet();
    if (resumeSnapshot != null) {
      for (final entry in resumeSnapshot.renderedArtifacts.entries) {
        if (renderKeys.contains(entry.key)) {
          _renderedArtifacts[entry.key] = entry.value;
        }
      }
      for (final entry in resumeSnapshot.materializedArtifacts.entries) {
        if (materializationIds.contains(entry.key)) {
          _materializedArtifacts[entry.key] = entry.value;
        }
      }
    }
  }

  final ReactionExportPlan plan;
  final ReactionStateRenderer renderer;
  final ExportArtifactWriter writer;
  final StreamController<ExportProgress> _progressController =
      StreamController<ExportProgress>.broadcast();
  final Map<String, WrittenReactionArtifact> _renderedArtifacts;
  final Map<String, WrittenReactionArtifact> _materializedArtifacts;
  final Map<String, int> _attempts = {};
  final List<ReactionExportFailureRecord> _failures = [];
  ExportCancellationController? _cancellation;
  WrittenReactionArtifact? _manifestArtifact;
  bool _isRunning = false;
  bool _disposed = false;

  @override
  Stream<ExportProgress> get progress => _progressController.stream;

  @override
  bool get isRunning => _isRunning;

  @override
  ReactionExportResumeSnapshot get resumeSnapshot {
    return ReactionExportResumeSnapshot(
      planKey: plan.planKey,
      renderedArtifacts: _renderedArtifacts,
      materializedArtifacts: _materializedArtifacts,
    );
  }

  @override
  Future<ReactionExportSummary> run() => _execute();

  @override
  Future<ReactionExportSummary> resume() => _execute();

  @override
  Future<ReactionExportSummary> retryFailures() => _execute();

  @override
  Future<void> cancel() async {
    _cancellation?.cancel();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await cancel();
    _disposed = true;
    await _progressController.close();
  }

  Future<ReactionExportSummary> _execute() async {
    if (_disposed) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'The reaction export job has been disposed.',
      );
    }
    if (_isRunning) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'The reaction export job is already running.',
      );
    }
    _isRunning = true;
    _failures.clear();
    _manifestArtifact = null;
    _cancellation = ExportCancellationController();
    final cancellation = _cancellation!.token;
    final manifestJson = plan.manifest.toDeterministicJson();
    final totalTasks = plan.artifacts.length + plan.materializations.length + 1;
    var processed = _renderedArtifacts.length + _materializedArtifacts.length;
    var cancelled = false;
    _emit(
      phase: ExportPhase.preparing,
      processed: processed,
      total: totalTasks,
      message: 'Preparing reaction export.',
    );

    try {
      for (final artifact in plan.artifacts) {
        if (_renderedArtifacts.containsKey(artifact.contentKey)) continue;
        if (cancellation.isCancelled) {
          cancelled = true;
          break;
        }
        final taskId = 'render:${artifact.contentKey}';
        final attempt = _nextAttempt(taskId);
        RenderedReactionArtifact rendered;
        try {
          rendered = await renderer.render(
            artifact.renderRequest,
            cancellation,
          );
          cancellation.throwIfCancelled();
        } catch (error) {
          if (_isCancellation(error, cancellation)) {
            cancelled = true;
            break;
          }
          _failures.add(
            ReactionExportFailureRecord(
              taskId: taskId,
              stage: ReactionExportStage.render,
              message: error.toString(),
              contentKey: artifact.contentKey,
              attempt: attempt,
            ),
          );
          processed += 1;
          _emit(
            phase: ExportPhase.rendering,
            processed: processed,
            total: totalTasks,
            message: 'A reaction state failed to render.',
          );
          continue;
        }
        try {
          final written = await writer.writeArtifact(
            fileName: artifact.fileName,
            bytes: rendered.pngBytes,
            cancellation: cancellation,
          );
          cancellation.throwIfCancelled();
          _renderedArtifacts[artifact.contentKey] = written;
        } catch (error) {
          if (_isCancellation(error, cancellation)) {
            cancelled = true;
            break;
          }
          _failures.add(
            ReactionExportFailureRecord(
              taskId: taskId,
              stage: ReactionExportStage.write,
              message: error.toString(),
              contentKey: artifact.contentKey,
              attempt: attempt,
            ),
          );
        }
        processed += 1;
        _emit(
          phase: ExportPhase.rendering,
          processed: processed,
          total: totalTasks,
          message:
              'Rendered ${_renderedArtifacts.length} unique reaction states.',
        );
      }

      if (!cancelled) {
        for (final mapping in plan.materializations) {
          if (_materializedArtifacts.containsKey(mapping.id)) continue;
          if (cancellation.isCancelled) {
            cancelled = true;
            break;
          }
          final source = _renderedArtifacts[mapping.contentKey];
          if (source == null) continue;
          final taskId = 'materialize:${mapping.id}';
          final attempt = _nextAttempt(taskId);
          try {
            final written = await writer.materializeArtifact(
              source: source,
              fileName: mapping.fileName,
              cancellation: cancellation,
            );
            cancellation.throwIfCancelled();
            _materializedArtifacts[mapping.id] = written;
          } catch (error) {
            if (_isCancellation(error, cancellation)) {
              cancelled = true;
              break;
            }
            _failures.add(
              ReactionExportFailureRecord(
                taskId: taskId,
                stage: ReactionExportStage.materialize,
                message: error.toString(),
                contentKey: mapping.contentKey,
                eventId: mapping.eventId,
                attempt: attempt,
              ),
            );
          }
          processed += 1;
          _emit(
            phase: ExportPhase.finalizing,
            processed: processed,
            total: totalTasks,
            message:
                'Materialized ${_materializedArtifacts.length} event files.',
          );
        }
      }

      final completeArtifacts =
          _renderedArtifacts.length == plan.artifacts.length;
      final completeMappings =
          _materializedArtifacts.length == plan.materializations.length;
      if (!cancelled &&
          _failures.isEmpty &&
          completeArtifacts &&
          completeMappings) {
        final taskId = 'manifest';
        final attempt = _nextAttempt(taskId);
        try {
          _manifestArtifact = await writer.writeManifest(
            fileName: plan.request.options.manifestFileName,
            json: manifestJson,
            cancellation: cancellation,
          );
          cancellation.throwIfCancelled();
          processed += 1;
        } catch (error) {
          if (_isCancellation(error, cancellation)) {
            cancelled = true;
          } else {
            _failures.add(
              ReactionExportFailureRecord(
                taskId: taskId,
                stage: ReactionExportStage.manifest,
                message: error.toString(),
                attempt: attempt,
              ),
            );
          }
        }
      }
    } finally {
      _isRunning = false;
    }

    final allComplete =
        _renderedArtifacts.length == plan.artifacts.length &&
        _materializedArtifacts.length == plan.materializations.length &&
        _manifestArtifact != null;
    if (!cancelled && _failures.isEmpty && !allComplete) {
      _failures.add(
        ReactionExportFailureRecord(
          taskId: 'completion',
          stage: ReactionExportStage.manifest,
          message:
              'The export stopped before every planned artifact completed.',
        ),
      );
    }

    final state = cancelled
        ? ReactionExportRunState.cancelled
        : _failures.isNotEmpty
        ? ReactionExportRunState.completedWithErrors
        : ReactionExportRunState.completed;
    _emit(
      phase: switch (state) {
        ReactionExportRunState.cancelled => ExportPhase.cancelled,
        ReactionExportRunState.completedWithErrors => ExportPhase.failed,
        ReactionExportRunState.completed => ExportPhase.completed,
        ReactionExportRunState.idle ||
        ReactionExportRunState.running => ExportPhase.failed,
      },
      processed: processed,
      total: totalTasks,
      message: switch (state) {
        ReactionExportRunState.cancelled => 'Reaction export cancelled.',
        ReactionExportRunState.completedWithErrors =>
          'Reaction export completed with errors.',
        ReactionExportRunState.completed => 'Reaction export completed.',
        ReactionExportRunState.idle ||
        ReactionExportRunState.running => 'Reaction export stopped.',
      },
    );
    return ReactionExportSummary(
      state: state,
      plannedEvents: plan.manifest.entries.length,
      plannedUniqueRenders: plan.artifacts.length,
      completedUniqueRenders: _renderedArtifacts.length,
      completedMaterializations: _materializedArtifacts.length,
      manifestJson: manifestJson,
      manifestArtifact: _manifestArtifact,
      resumeSnapshot: resumeSnapshot,
      failures: _failures,
    );
  }

  int _nextAttempt(String taskId) {
    final attempt = (_attempts[taskId] ?? 0) + 1;
    _attempts[taskId] = attempt;
    return attempt;
  }

  bool _isCancellation(Object error, ExportCancellationToken token) {
    return token.isCancelled ||
        error is MediaFailure && error.code == MediaFailureCode.cancelled;
  }

  void _emit({
    required ExportPhase phase,
    required int processed,
    required int total,
    required String message,
  }) {
    if (_progressController.isClosed) return;
    _progressController.add(
      ExportProgress(
        phase: phase,
        fraction: total == 0 ? 1 : (processed / total).clamp(0, 1),
        message: message,
        renderedFrames: _renderedArtifacts.length,
        totalFrames: plan.artifacts.length,
        diagnostics: [
          for (final failure in _failures)
            MediaDiagnostic(
              severity: MediaDiagnosticSeverity.error,
              code: 'reaction_export.${failure.stage.name}',
              message: failure.message,
              context: failure.toJson(),
            ),
        ],
      ),
    );
  }
}
