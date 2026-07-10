import 'media_contracts.dart';
import 'media_render_plan.dart';

class PngSequenceSettings {
  const PngSequenceSettings({
    required this.outputDirectory,
    this.filePrefix = 'frame',
    this.digits = 8,
    this.firstFrame = 0,
    this.frameCount,
    this.includeAlpha = true,
    this.pathSeparator = '/',
  });

  final MediaLocation outputDirectory;
  final String filePrefix;
  final int digits;
  final int firstFrame;
  final int? frameCount;
  final bool includeAlpha;
  final String pathSeparator;

  void validate(int totalFrames) {
    outputDirectory.validate('PNG sequence output directory');
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(filePrefix)) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'PNG sequence prefix contains unsupported characters.',
        context: {'filePrefix': filePrefix},
      );
    }
    if (digits < 1 || digits > 16) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'PNG sequence digits must be between 1 and 16.',
      );
    }
    if (firstFrame < 0 || firstFrame >= totalFrames) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'PNG sequence first frame is outside the render plan.',
      );
    }
    final count = frameCount ?? totalFrames - firstFrame;
    if (count <= 0 || firstFrame + count > totalFrames) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'PNG sequence frame range is outside the render plan.',
      );
    }
    if (pathSeparator != '/' && pathSeparator != '\\') {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'PNG sequence path separator must be slash or backslash.',
      );
    }
  }
}

class PngFrameRequest {
  const PngFrameRequest({
    required this.frame,
    required this.position,
    required this.output,
    required this.includeAlpha,
  });

  final int frame;
  final Duration position;
  final MediaLocation output;
  final bool includeAlpha;
}

class PngSequenceExportPlan {
  PngSequenceExportPlan({
    required this.sourcePlan,
    required this.settings,
    required List<PngFrameRequest> frames,
    List<MediaDiagnostic> diagnostics = const [],
  }) : frames = List.unmodifiable(frames),
       diagnostics = List.unmodifiable(diagnostics);

  final MediaRenderPlan sourcePlan;
  final PngSequenceSettings settings;
  final List<PngFrameRequest> frames;
  final List<MediaDiagnostic> diagnostics;

  String get ffmpegInputPattern {
    final directory = _trimTrailingSeparators(
      settings.outputDirectory.value,
      settings.pathSeparator,
    );
    return '$directory${settings.pathSeparator}${settings.filePrefix}_'
        '%0${settings.digits}d.png';
  }
}

class PngSequencePlanner {
  const PngSequencePlanner();

  PngSequenceExportPlan build(
    MediaRenderPlan sourcePlan,
    PngSequenceSettings settings,
  ) {
    sourcePlan.validate();
    settings.validate(sourcePlan.totalFrames);
    final total =
        settings.frameCount ?? sourcePlan.totalFrames - settings.firstFrame;
    final directory = _trimTrailingSeparators(
      settings.outputDirectory.value,
      settings.pathSeparator,
    );
    final frames = <PngFrameRequest>[];
    for (var offset = 0; offset < total; offset += 1) {
      final frame = settings.firstFrame + offset;
      final index = frame.toString().padLeft(settings.digits, '0');
      frames.add(
        PngFrameRequest(
          frame: frame,
          position: sourcePlan.frameRate.frameStart(frame),
          output: MediaLocation(
            '$directory${settings.pathSeparator}${settings.filePrefix}_$index.png',
          ),
          includeAlpha: settings.includeAlpha,
        ),
      );
    }
    final diagnostics = <MediaDiagnostic>[];
    if (sourcePlan.visualLayers.any(
      (layer) => layer.enabled && layer.source is VideoVisualSource,
    )) {
      diagnostics.add(
        MediaDiagnostic(
          severity: MediaDiagnosticSeverity.warning,
          code: 'png_sequence.video_frames_required',
          message:
              'Video layers require a frame provider during PNG rendering.',
        ),
      );
    }
    if (sourcePlan.audioLayers.any((layer) => layer.enabled && !layer.muted)) {
      diagnostics.add(
        MediaDiagnostic(
          severity: MediaDiagnosticSeverity.info,
          code: 'png_sequence.audio_not_included',
          message: 'PNG sequences do not contain audio.',
        ),
      );
    }
    return PngSequenceExportPlan(
      sourcePlan: sourcePlan,
      settings: settings,
      frames: frames,
      diagnostics: diagnostics,
    );
  }
}

String _trimTrailingSeparators(String value, String separator) {
  var result = value;
  while (result.endsWith(separator) && result.length > 1) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
