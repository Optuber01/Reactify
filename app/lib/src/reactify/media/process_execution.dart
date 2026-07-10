import 'dart:typed_data';

import 'ffmpeg_backend.dart';
import 'media_contracts.dart';

abstract interface class OwnedProcess {
  Stream<Uint8List> get standardOutput;

  Stream<Uint8List> get standardError;

  Future<int> get exitCode;

  Future<void> terminate();
}

abstract interface class OwnedProcessLauncher {
  Future<OwnedProcess> start(ExecutableInvocation invocation);
}

abstract interface class TemporaryTextArtifact {
  String get path;

  Future<void> dispose();
}

abstract interface class TemporaryArtifactStore {
  Future<TemporaryTextArtifact> writeText({
    required String prefix,
    required String suffix,
    required String contents,
  });
}

abstract interface class ExportOutputInspector {
  Future<int?> byteLength(MediaLocation output);
}

class FfmpegExecutionConfiguration {
  const FfmpegExecutionConfiguration({
    required this.candidate,
    required this.settings,
    this.filterScriptThreshold = 7000,
    this.capabilityProbeTimeout = const Duration(seconds: 15),
    this.terminationGracePeriod = const Duration(seconds: 2),
  });

  final FfmpegExecutableCandidate candidate;
  final FfmpegExportSettings settings;
  final int filterScriptThreshold;
  final Duration capabilityProbeTimeout;
  final Duration terminationGracePeriod;

  void validate() {
    settings.validate();
    if (candidate.ffmpeg.trim().isEmpty || filterScriptThreshold < 256) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'FFmpeg execution configuration is invalid.',
      );
    }
    if (capabilityProbeTimeout <= Duration.zero ||
        terminationGracePeriod < Duration.zero) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'FFmpeg execution timeouts are invalid.',
      );
    }
  }
}
