import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ffmpeg_backend.dart';
import 'ffmpeg_export_executor.dart';
import 'media_contracts.dart';
import 'process_execution.dart';

Future<ExportEncoder> createFfmpegExportEncoder(
  FfmpegExecutionConfiguration configuration,
) async {
  configuration.validate();
  final runner = IoExecutableRunner(
    timeout: configuration.capabilityProbeTimeout,
  );
  FfmpegExecutableCapabilities capabilities;
  try {
    capabilities = await FfmpegCapabilityProbe(
      runner: runner,
      candidate: configuration.candidate,
    ).probe();
  } on ProcessException catch (error) {
    throw MediaFailure(
      code: MediaFailureCode.backendUnavailable,
      message: 'The configured FFmpeg executable could not be started.',
      cause: error,
      context: {'executable': configuration.candidate.ffmpeg},
    );
  } on TimeoutException catch (error) {
    throw MediaFailure(
      code: MediaFailureCode.timedOut,
      message: 'FFmpeg capability probing timed out.',
      cause: error,
      context: {'executable': configuration.candidate.ffmpeg},
    );
  }
  return InjectedFfmpegExportEncoder(
    configuration: configuration,
    ffmpegCapabilities: capabilities,
    processLauncher: IoOwnedProcessLauncher(
      terminationGracePeriod: configuration.terminationGracePeriod,
    ),
    temporaryArtifacts: const IoTemporaryArtifactStore(),
    outputInspector: const IoExportOutputInspector(),
  );
}

class IoExecutableRunner implements ExecutableRunner {
  const IoExecutableRunner({required this.timeout});

  final Duration timeout;

  @override
  Future<ExecutableResult> run(ExecutableInvocation invocation) async {
    final process = await Process.start(
      invocation.executable,
      invocation.arguments,
      workingDirectory: invocation.workingDirectory,
      environment: invocation.environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    final outputFuture = process.stdout.transform(utf8.decoder).join();
    final errorFuture = process.stderr.transform(utf8.decoder).join();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      rethrow;
    }
    return ExecutableResult(
      exitCode: exitCode,
      standardOutput: await outputFuture,
      standardError: await errorFuture,
    );
  }
}

class IoOwnedProcessLauncher implements OwnedProcessLauncher {
  const IoOwnedProcessLauncher({required this.terminationGracePeriod});

  final Duration terminationGracePeriod;

  @override
  Future<OwnedProcess> start(ExecutableInvocation invocation) async {
    final process = await Process.start(
      invocation.executable,
      invocation.arguments,
      workingDirectory: invocation.workingDirectory,
      environment: invocation.environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    return _IoOwnedProcess(
      process: process,
      terminationGracePeriod: terminationGracePeriod,
    );
  }
}

class _IoOwnedProcess implements OwnedProcess {
  _IoOwnedProcess({
    required Process process,
    required this.terminationGracePeriod,
  }) : _process = process,
       standardOutput = process.stdout.map(Uint8List.fromList),
       standardError = process.stderr.map(Uint8List.fromList),
       exitCode = process.exitCode;

  final Process _process;
  final Duration terminationGracePeriod;
  bool _terminationRequested = false;

  @override
  final Stream<Uint8List> standardOutput;

  @override
  final Stream<Uint8List> standardError;

  @override
  final Future<int> exitCode;

  @override
  Future<void> terminate() async {
    if (_terminationRequested) return;
    _terminationRequested = true;
    _process.kill();
    try {
      await exitCode.timeout(terminationGracePeriod);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await exitCode;
    }
  }
}

class IoTemporaryArtifactStore implements TemporaryArtifactStore {
  const IoTemporaryArtifactStore({this.baseDirectory});

  final String? baseDirectory;

  @override
  Future<TemporaryTextArtifact> writeText({
    required String prefix,
    required String suffix,
    required String contents,
  }) async {
    final root = baseDirectory == null
        ? Directory.systemTemp
        : Directory(baseDirectory!);
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final directory = await root.createTemp(prefix);
    final file = File(
      '${directory.path}${Platform.pathSeparator}filter$suffix',
    );
    await file.writeAsString(contents, encoding: utf8, flush: true);
    return _IoTemporaryTextArtifact(directory: directory, file: file);
  }
}

class _IoTemporaryTextArtifact implements TemporaryTextArtifact {
  _IoTemporaryTextArtifact({required this.directory, required this.file});

  final Directory directory;
  final File file;
  bool _disposed = false;

  @override
  String get path => file.path;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class IoExportOutputInspector implements ExportOutputInspector {
  const IoExportOutputInspector();

  @override
  Future<int?> byteLength(MediaLocation output) async {
    final path = _localPath(output.value);
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.length();
  }

  String? _localPath(String value) {
    if (value.startsWith('file:')) {
      return Uri.parse(value).toFilePath();
    }
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.hasScheme &&
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
      return null;
    }
    return value;
  }
}
