import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'ffmpeg_backend.dart';
import 'ffmpeg_progress.dart';
import 'media_contracts.dart';
import 'process_execution.dart';

class InjectedFfmpegExportEncoder implements ExportEncoder {
  InjectedFfmpegExportEncoder({
    required this.configuration,
    required this.ffmpegCapabilities,
    required this.processLauncher,
    required this.temporaryArtifacts,
    required this.outputInspector,
  }) {
    configuration.validate();
    if (ffmpegCapabilities.candidate.ffmpeg != configuration.candidate.ffmpeg ||
        !ffmpegCapabilities.supportsExport(configuration.settings)) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message:
            'The configured FFmpeg executable cannot encode the target format.',
        context: {
          'executable': configuration.candidate.ffmpeg,
          'videoEncoder': configuration.settings.videoEncoder,
          'audioEncoder': configuration.settings.audioEncoder,
          'muxer': configuration.settings.muxer,
        },
      );
    }
  }

  final FfmpegExecutionConfiguration configuration;
  final FfmpegExecutableCapabilities ffmpegCapabilities;
  final OwnedProcessLauncher processLauncher;
  final TemporaryArtifactStore temporaryArtifacts;
  final ExportOutputInspector outputInspector;

  @override
  MediaBackendCapabilities get capabilities =>
      ffmpegCapabilities.backendCapabilities;

  @override
  Future<ExportJob> start(ExportRequest request) async {
    final exportPlan = FfmpegExportPlanner(
      candidate: configuration.candidate,
      settings: configuration.settings,
      capabilities: ffmpegCapabilities,
    ).build(request);
    final job = _FfmpegProcessExportJob(
      encoder: this,
      request: request,
      exportPlan: exportPlan,
    );
    job.begin();
    return job;
  }
}

class _FfmpegProcessExportJob implements ExportJob {
  _FfmpegProcessExportJob({
    required this.encoder,
    required this.request,
    required this.exportPlan,
  }) : id = 'ffmpeg-${DateTime.now().microsecondsSinceEpoch}';

  final InjectedFfmpegExportEncoder encoder;
  final ExportRequest request;
  final FfmpegExportPlan exportPlan;
  final StreamController<ExportProgress> _progressController =
      StreamController<ExportProgress>.broadcast();
  final Completer<ExportResult> _completion = Completer<ExportResult>();
  final ExportCancellationController _cancellation =
      ExportCancellationController();
  OwnedProcess? _ownedProcess;
  bool _begun = false;

  @override
  final String id;

  @override
  Stream<ExportProgress> get progress => _progressController.stream;

  @override
  Future<ExportResult> get completion => _completion.future;

  void begin() {
    if (_begun) return;
    _begun = true;
    unawaited(_run());
  }

  @override
  Future<void> cancel() async {
    _cancellation.cancel();
    await _ownedProcess?.terminate();
  }

  @override
  Future<ExportJob> retry() => encoder.start(request);

  Future<void> _run() async {
    final stopwatch = Stopwatch()..start();
    TemporaryTextArtifact? filterScript;
    final diagnostics = <MediaDiagnostic>[...exportPlan.diagnostics];
    try {
      _emit(
        phase: ExportPhase.preparing,
        fraction: 0,
        message: 'Preparing FFmpeg export.',
      );
      _cancellation.token.throwIfCancelled();
      var invocation = exportPlan.invocation;
      if (exportPlan.filterGraph.length >
          encoder.configuration.filterScriptThreshold) {
        filterScript = await encoder.temporaryArtifacts.writeText(
          prefix: 'reactify_filter_',
          suffix: '.ffgraph',
          contents: exportPlan.filterGraph,
        );
        invocation = _withFilterScript(invocation, filterScript.path);
        diagnostics.add(
          MediaDiagnostic(
            severity: MediaDiagnosticSeverity.info,
            code: 'ffmpeg.filter_script',
            message: 'The filter graph was materialized as a temporary script.',
          ),
        );
      }
      _cancellation.token.throwIfCancelled();
      OwnedProcess process;
      try {
        process = await encoder.processLauncher.start(invocation);
      } catch (error) {
        final diagnostic = MediaDiagnostic(
          severity: MediaDiagnosticSeverity.error,
          code: 'ffmpeg.process_start',
          message: 'The configured FFmpeg executable could not be started.',
          context: {'executable': invocation.executable},
        );
        diagnostics.add(diagnostic);
        throw MediaFailure(
          code: MediaFailureCode.backendUnavailable,
          message: diagnostic.message,
          cause: error,
          context: {'executable': invocation.executable},
          diagnostics: diagnostics,
        );
      }
      _ownedProcess = process;
      if (_cancellation.token.isCancelled) {
        await process.terminate();
      }
      final standardError = _collectOutput(process.standardError);
      final progressReader = _readProgress(process.standardOutput, stopwatch);
      final exitCode = await process.exitCode;
      await progressReader;
      final errorText = await standardError;
      _ownedProcess = null;
      if (_cancellation.token.isCancelled) {
        final result = ExportResult(
          output: request.output,
          elapsed: stopwatch.elapsed,
          byteLength: null,
          cancelled: true,
          diagnostics: diagnostics,
        );
        _emit(
          phase: ExportPhase.cancelled,
          fraction: 0,
          message: 'FFmpeg export cancelled.',
          diagnostics: diagnostics,
        );
        _completion.complete(result);
        return;
      }
      if (exitCode != 0) {
        final failureDiagnostic = MediaDiagnostic(
          severity: MediaDiagnosticSeverity.error,
          code: 'ffmpeg.exit_code',
          message: errorText.isEmpty
              ? 'FFmpeg exited with code $exitCode.'
              : errorText,
          context: {'exitCode': exitCode},
        );
        diagnostics.add(failureDiagnostic);
        throw MediaFailure(
          code: MediaFailureCode.encodeFailed,
          message: 'FFmpeg failed to encode the export.',
          context: {'exitCode': exitCode, 'output': request.output.value},
          diagnostics: diagnostics,
        );
      }
      if (errorText.isNotEmpty) {
        diagnostics.add(
          MediaDiagnostic(
            severity: MediaDiagnosticSeverity.info,
            code: 'ffmpeg.stderr',
            message: errorText,
          ),
        );
      }
      final byteLength = await encoder.outputInspector.byteLength(
        request.output,
      );
      if (byteLength == null || byteLength <= 0) {
        throw MediaFailure(
          code: MediaFailureCode.outputUnavailable,
          message: 'FFmpeg completed without a readable output artifact.',
          context: {'output': request.output.value},
          diagnostics: diagnostics,
        );
      }
      final result = ExportResult(
        output: request.output,
        elapsed: stopwatch.elapsed,
        byteLength: byteLength,
        cancelled: false,
        diagnostics: diagnostics,
      );
      _emit(
        phase: ExportPhase.completed,
        fraction: 1,
        message: 'FFmpeg export completed.',
        diagnostics: diagnostics,
      );
      _completion.complete(result);
    } catch (error, stackTrace) {
      if (!_completion.isCompleted) {
        final failure = error is MediaFailure
            ? error
            : MediaFailure(
                code: _cancellation.token.isCancelled
                    ? MediaFailureCode.cancelled
                    : MediaFailureCode.internal,
                message: _cancellation.token.isCancelled
                    ? 'The export was cancelled.'
                    : 'The FFmpeg export failed unexpectedly.',
                cause: error,
                diagnostics: diagnostics,
              );
        if (failure.code == MediaFailureCode.cancelled) {
          _completion.complete(
            ExportResult(
              output: request.output,
              elapsed: stopwatch.elapsed,
              byteLength: null,
              cancelled: true,
              diagnostics: failure.diagnostics,
            ),
          );
          _emit(
            phase: ExportPhase.cancelled,
            fraction: 0,
            message: failure.message,
            diagnostics: failure.diagnostics,
          );
        } else {
          _emit(
            phase: ExportPhase.failed,
            fraction: 0,
            message: failure.message,
            diagnostics: failure.diagnostics,
          );
          _completion.completeError(failure, stackTrace);
        }
      }
    } finally {
      stopwatch.stop();
      _ownedProcess = null;
      try {
        await filterScript?.dispose();
      } catch (_) {}
      await _progressController.close();
    }
  }

  Future<void> _readProgress(
    Stream<Uint8List> output,
    Stopwatch stopwatch,
  ) async {
    await for (final record in const FfmpegProgressParser().parse(output)) {
      final totalFrames = request.plan.totalFrames;
      final frame = record.frame ?? 0;
      final timeFraction = record.outputMicroseconds == null
          ? null
          : record.outputMicroseconds! / request.plan.duration.inMicroseconds;
      final fraction =
          (timeFraction ?? (totalFrames == 0 ? 0 : frame / totalFrames)).clamp(
            0.0,
            1.0,
          );
      final speed = record.speed;
      _emit(
        phase: record.ended ? ExportPhase.finalizing : ExportPhase.encoding,
        fraction: fraction,
        message: speed == null
            ? 'Encoding export.'
            : 'Encoding export at ${speed.toStringAsFixed(2)}x.',
        renderedFrames: frame,
        totalFrames: totalFrames,
        elapsed: stopwatch.elapsed,
      );
    }
  }

  Future<String> _collectOutput(Stream<Uint8List> source) async {
    const limit = 65536;
    final chunks = <int>[];
    await for (final chunk in source) {
      chunks.addAll(chunk);
      if (chunks.length > limit) {
        chunks.removeRange(0, chunks.length - limit);
      }
    }
    return utf8.decode(chunks, allowMalformed: true).trim();
  }

  ExecutableInvocation _withFilterScript(
    ExecutableInvocation source,
    String scriptPath,
  ) {
    final arguments = source.arguments.toList();
    final index = arguments.indexOf('-filter_complex');
    if (index < 0 || index + 1 >= arguments.length) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'The FFmpeg plan has no replaceable filter graph.',
      );
    }
    arguments[index] = '-filter_complex_script';
    arguments[index + 1] = scriptPath;
    return ExecutableInvocation(
      executable: source.executable,
      arguments: arguments,
      environment: source.environment,
      workingDirectory: source.workingDirectory,
    );
  }

  void _emit({
    required ExportPhase phase,
    required double fraction,
    required String message,
    int renderedFrames = 0,
    int totalFrames = 0,
    Duration elapsed = Duration.zero,
    List<MediaDiagnostic> diagnostics = const [],
  }) {
    if (_progressController.isClosed) return;
    _progressController.add(
      ExportProgress(
        phase: phase,
        fraction: fraction,
        message: message,
        renderedFrames: renderedFrames,
        totalFrames: totalFrames,
        elapsed: elapsed,
        diagnostics: diagnostics,
      ),
    );
  }
}
