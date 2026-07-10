import 'dart:async';
import 'dart:typed_data';

import 'media_render_plan.dart';

enum MediaKind { video, audio, image, unknown }

enum MediaStreamKind { video, audio, subtitle, data, unknown }

enum MediaFailureCode {
  invalidRequest,
  sourceMissing,
  sourceUnreadable,
  unsupportedFormat,
  unsupportedCapability,
  backendUnavailable,
  backendRejected,
  probeFailed,
  decodeFailed,
  encodeFailed,
  outputUnavailable,
  cancelled,
  timedOut,
  internal,
}

enum MediaDiagnosticSeverity { info, warning, error }

enum PreviewPlaybackState {
  idle,
  loading,
  ready,
  playing,
  paused,
  ended,
  failed,
}

enum ExportPhase {
  queued,
  preparing,
  rendering,
  encoding,
  finalizing,
  completed,
  cancelled,
  failed,
}

class MediaLocation {
  const MediaLocation(this.value);

  final String value;

  void validate(String fieldName) {
    if (value.trim().isEmpty || value.contains('\u0000')) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: '$fieldName must be a non-empty location.',
        context: {'field': fieldName},
      );
    }
  }

  @override
  String toString() => value;
}

class MediaDiagnostic {
  MediaDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    Map<String, Object?> context = const {},
  }) : context = Map.unmodifiable(context);

  final MediaDiagnosticSeverity severity;
  final String code;
  final String message;
  final Map<String, Object?> context;
}

class MediaFailure implements Exception {
  MediaFailure({
    required this.code,
    required this.message,
    this.cause,
    Map<String, Object?> context = const {},
    List<MediaDiagnostic> diagnostics = const [],
  }) : context = Map.unmodifiable(context),
       diagnostics = List.unmodifiable(diagnostics);

  final MediaFailureCode code;
  final String message;
  final Object? cause;
  final Map<String, Object?> context;
  final List<MediaDiagnostic> diagnostics;

  @override
  String toString() => 'MediaFailure(${code.name}): $message';
}

class MediaStreamInfo {
  MediaStreamInfo({
    required this.index,
    required this.kind,
    required this.codec,
    this.duration,
    this.width,
    this.height,
    this.frameRate,
    this.sampleRate,
    this.channels,
    this.language,
    Map<String, String> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata);

  final int index;
  final MediaStreamKind kind;
  final String codec;
  final Duration? duration;
  final int? width;
  final int? height;
  final FrameRate? frameRate;
  final int? sampleRate;
  final int? channels;
  final String? language;
  final Map<String, String> metadata;
}

class MediaProbeResult {
  MediaProbeResult({
    required this.source,
    required this.kind,
    required this.duration,
    required List<MediaStreamInfo> streams,
    this.container,
    this.byteLength,
    this.seekable = true,
    List<MediaDiagnostic> diagnostics = const [],
    Map<String, String> metadata = const {},
  }) : streams = List.unmodifiable(streams),
       diagnostics = List.unmodifiable(diagnostics),
       metadata = Map.unmodifiable(metadata);

  final MediaLocation source;
  final MediaKind kind;
  final Duration duration;
  final List<MediaStreamInfo> streams;
  final String? container;
  final int? byteLength;
  final bool seekable;
  final List<MediaDiagnostic> diagnostics;
  final Map<String, String> metadata;

  Iterable<MediaStreamInfo> streamsOf(MediaStreamKind kind) {
    return streams.where((stream) => stream.kind == kind);
  }
}

class MediaBackendCapabilities {
  MediaBackendCapabilities({
    required this.backendId,
    required this.backendVersion,
    this.canProbe = false,
    this.canPreviewVideo = false,
    this.canPreviewAudio = false,
    this.canSeek = false,
    this.canChangeRate = false,
    this.canChangePitch = false,
    this.canGenerateThumbnails = false,
    this.canGenerateWaveforms = false,
    this.canEncodeVideo = false,
    this.canEncodeAudio = false,
    this.canEncodeAlpha = false,
    Set<String> decoders = const {},
    Set<String> encoders = const {},
    Set<String> containers = const {},
    Set<String> filters = const {},
    List<MediaDiagnostic> diagnostics = const [],
  }) : decoders = Set.unmodifiable(decoders),
       encoders = Set.unmodifiable(encoders),
       containers = Set.unmodifiable(containers),
       filters = Set.unmodifiable(filters),
       diagnostics = List.unmodifiable(diagnostics);

  final String backendId;
  final String backendVersion;
  final bool canProbe;
  final bool canPreviewVideo;
  final bool canPreviewAudio;
  final bool canSeek;
  final bool canChangeRate;
  final bool canChangePitch;
  final bool canGenerateThumbnails;
  final bool canGenerateWaveforms;
  final bool canEncodeVideo;
  final bool canEncodeAudio;
  final bool canEncodeAlpha;
  final Set<String> decoders;
  final Set<String> encoders;
  final Set<String> containers;
  final Set<String> filters;
  final List<MediaDiagnostic> diagnostics;

  bool supportsEncoder(String encoder) => encoders.contains(encoder);

  bool supportsFilter(String filter) => filters.contains(filter);
}

abstract interface class MediaProbe {
  Future<MediaProbeResult> probe(MediaLocation source);
}

class PreviewLoadRequest {
  const PreviewLoadRequest({
    required this.source,
    this.start = Duration.zero,
    this.end,
    this.videoStreamIndex,
    this.audioStreamIndex,
    this.muted = false,
  });

  final MediaLocation source;
  final Duration start;
  final Duration? end;
  final int? videoStreamIndex;
  final int? audioStreamIndex;
  final bool muted;
}

class PreviewSnapshot {
  const PreviewSnapshot({
    required this.state,
    required this.position,
    required this.duration,
    required this.playbackRate,
    required this.pitchSemitones,
    required this.volume,
    this.buffered = Duration.zero,
    this.failure,
  });

  final PreviewPlaybackState state;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double playbackRate;
  final double pitchSemitones;
  final double volume;
  final MediaFailure? failure;
}

abstract interface class PreviewTransport {
  Stream<PreviewSnapshot> get snapshots;

  PreviewSnapshot get current;

  Future<void> load(PreviewLoadRequest request);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> setPlaybackRate(double rate);

  Future<void> setPitchSemitones(double semitones);

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

class ThumbnailRequest {
  const ThumbnailRequest({
    required this.source,
    required this.position,
    required this.width,
    required this.height,
    this.fit = ThumbnailFit.contain,
  });

  final MediaLocation source;
  final Duration position;
  final int width;
  final int height;
  final ThumbnailFit fit;
}

enum ThumbnailFit { contain, cover, stretch }

class ThumbnailResult {
  const ThumbnailResult({
    required this.position,
    required this.width,
    required this.height,
    required this.pngBytes,
  });

  final Duration position;
  final int width;
  final int height;
  final Uint8List pngBytes;
}

abstract interface class ThumbnailProvider {
  Future<ThumbnailResult> generate(ThumbnailRequest request);
}

class WaveformRequest {
  const WaveformRequest({
    required this.source,
    required this.start,
    required this.duration,
    required this.bucketCount,
    this.channel = -1,
  });

  final MediaLocation source;
  final Duration start;
  final Duration duration;
  final int bucketCount;
  final int channel;
}

class WaveformBucket {
  const WaveformBucket({required this.minimum, required this.maximum});

  final double minimum;
  final double maximum;
}

class WaveformResult {
  WaveformResult({
    required this.start,
    required this.duration,
    required this.sampleRate,
    required List<WaveformBucket> buckets,
  }) : buckets = List.unmodifiable(buckets);

  final Duration start;
  final Duration duration;
  final int sampleRate;
  final List<WaveformBucket> buckets;
}

abstract interface class WaveformProvider {
  Future<WaveformResult> generate(WaveformRequest request);
}

class ExportCancellationToken {
  ExportCancellationToken._(this._controller);

  final ExportCancellationController _controller;

  bool get isCancelled => _controller.isCancelled;

  Future<void> get whenCancelled => _controller.whenCancelled;

  void throwIfCancelled() {
    if (isCancelled) {
      throw MediaFailure(
        code: MediaFailureCode.cancelled,
        message: 'The export was cancelled.',
      );
    }
  }
}

class ExportCancellationController {
  ExportCancellationController() : _cancelled = Completer<void>() {
    token = ExportCancellationToken._(this);
  }

  final Completer<void> _cancelled;
  late final ExportCancellationToken token;

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

class ExportProgress {
  ExportProgress({
    required this.phase,
    required this.fraction,
    required this.message,
    this.renderedFrames = 0,
    this.totalFrames = 0,
    this.elapsed = Duration.zero,
    this.remaining,
    List<MediaDiagnostic> diagnostics = const [],
  }) : diagnostics = List.unmodifiable(diagnostics);

  final ExportPhase phase;
  final double fraction;
  final String message;
  final int renderedFrames;
  final int totalFrames;
  final Duration elapsed;
  final Duration? remaining;
  final List<MediaDiagnostic> diagnostics;
}

class ExportResult {
  ExportResult({
    required this.output,
    required this.elapsed,
    required this.byteLength,
    required this.cancelled,
    List<MediaDiagnostic> diagnostics = const [],
  }) : diagnostics = List.unmodifiable(diagnostics);

  final MediaLocation output;
  final Duration elapsed;
  final int? byteLength;
  final bool cancelled;
  final List<MediaDiagnostic> diagnostics;
}

abstract interface class ExportJob {
  String get id;

  Stream<ExportProgress> get progress;

  Future<ExportResult> get completion;

  Future<void> cancel();

  Future<ExportJob> retry();
}

class ExportRequest {
  const ExportRequest({
    required this.plan,
    required this.output,
    this.overwrite = false,
  });

  final MediaRenderPlan plan;
  final MediaLocation output;
  final bool overwrite;
}

abstract interface class ExportEncoder {
  MediaBackendCapabilities get capabilities;

  Future<ExportJob> start(ExportRequest request);
}
