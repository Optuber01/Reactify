import 'dart:math' as math;

import 'media_contracts.dart';

class FrameRate {
  const FrameRate(this.numerator, [this.denominator = 1]);

  final int numerator;
  final int denominator;

  double get framesPerSecond => numerator / denominator;

  Duration frameStart(int frame) {
    if (frame < 0) {
      throw RangeError.value(frame, 'frame', 'Frame cannot be negative.');
    }
    return Duration(
      microseconds:
          (frame * denominator * Duration.microsecondsPerSecond) ~/ numerator,
    );
  }

  int frameAt(Duration position) {
    return (position.inMicroseconds * numerator) ~/
        (denominator * Duration.microsecondsPerSecond);
  }

  int framesFor(Duration duration) {
    final scaled =
        duration.inMicroseconds *
        numerator /
        (denominator * Duration.microsecondsPerSecond);
    return scaled.ceil();
  }

  void validate() {
    if (numerator <= 0 || denominator <= 0) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Frame-rate numerator and denominator must be positive.',
        context: {'numerator': numerator, 'denominator': denominator},
      );
    }
  }

  @override
  String toString() => '$numerator/$denominator';
}

class MediaCanvasSize {
  const MediaCanvasSize(this.width, this.height);

  final int width;
  final int height;

  void validate() {
    if (width <= 0 || height <= 0) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Canvas dimensions must be positive.',
        context: {'width': width, 'height': height},
      );
    }
  }
}

class MediaColor {
  const MediaColor({
    required this.red,
    required this.green,
    required this.blue,
    this.alpha = 255,
  });

  const MediaColor.transparent() : red = 0, green = 0, blue = 0, alpha = 0;

  final int red;
  final int green;
  final int blue;
  final int alpha;

  void validate() {
    if ([
      red,
      green,
      blue,
      alpha,
    ].any((channel) => channel < 0 || channel > 255)) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Color channels must be between 0 and 255.',
      );
    }
  }
}

class MediaTimeRange {
  const MediaTimeRange({required this.start, required this.duration});

  final Duration start;
  final Duration duration;

  Duration get end => start + duration;

  void validate(String fieldName) {
    if (start.isNegative || duration <= Duration.zero) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message:
            '$fieldName must have a non-negative start and positive duration.',
        context: {
          'field': fieldName,
          'startUs': start.inMicroseconds,
          'durationUs': duration.inMicroseconds,
        },
      );
    }
  }
}

sealed class VisualSourcePlan {
  const VisualSourcePlan();

  MediaLocation get source;

  Duration get sourceIn;

  bool get repeatsSingleFrame;

  bool get isImageSequence;
}

class VideoVisualSource extends VisualSourcePlan {
  const VideoVisualSource({
    required this.source,
    this.sourceIn = Duration.zero,
  });

  @override
  final MediaLocation source;

  @override
  final Duration sourceIn;

  @override
  bool get repeatsSingleFrame => false;

  @override
  bool get isImageSequence => false;
}

class StillImageVisualSource extends VisualSourcePlan {
  const StillImageVisualSource({required this.source});

  @override
  final MediaLocation source;

  @override
  Duration get sourceIn => Duration.zero;

  @override
  bool get repeatsSingleFrame => true;

  @override
  bool get isImageSequence => false;
}

class PngSequenceVisualSource extends VisualSourcePlan {
  const PngSequenceVisualSource({
    required this.source,
    this.sourceIn = Duration.zero,
    this.startNumber = 0,
    this.frameRate,
  });

  @override
  final MediaLocation source;

  @override
  final Duration sourceIn;

  final int startNumber;
  final FrameRate? frameRate;

  @override
  bool get repeatsSingleFrame => false;

  @override
  bool get isImageSequence => true;
}

class VisualCrop {
  const VisualCrop({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;

  void validate() {
    if (left < 0 || top < 0 || width <= 0 || height <= 0) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Crop dimensions must be positive and offsets non-negative.',
      );
    }
  }
}

class VisualTransformPlan {
  const VisualTransformPlan({
    this.x = 0,
    this.y = 0,
    this.width,
    this.height,
    this.rotationDegrees = 0,
    this.opacity = 1,
    this.crop,
  });

  final double x;
  final double y;
  final int? width;
  final int? height;
  final double rotationDegrees;
  final double opacity;
  final VisualCrop? crop;

  void validate() {
    final numbers = [x, y, rotationDegrees, opacity];
    if (numbers.any((value) => !value.isFinite)) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Visual transform values must be finite.',
      );
    }
    if (opacity < 0 || opacity > 1) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Visual opacity must be between 0 and 1.',
        context: {'opacity': opacity},
      );
    }
    if ((width != null && width! <= 0) || (height != null && height! <= 0)) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Scaled visual dimensions must be positive.',
      );
    }
    crop?.validate();
  }
}

class VisualLayerPlan {
  const VisualLayerPlan({
    required this.id,
    required this.range,
    required this.source,
    this.transform = const VisualTransformPlan(),
    this.enabled = true,
  });

  final String id;
  final MediaTimeRange range;
  final VisualSourcePlan source;
  final VisualTransformPlan transform;
  final bool enabled;

  void validate() {
    _validateId(id, 'visual layer');
    range.validate('Visual layer $id');
    source.source.validate('Visual layer $id source');
    if (source.sourceIn.isNegative) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Visual source-in cannot be negative.',
        context: {'layerId': id},
      );
    }
    if (source is PngSequenceVisualSource) {
      final sequence = source as PngSequenceVisualSource;
      if (sequence.startNumber < 0) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'PNG sequence start number cannot be negative.',
          context: {'layerId': id},
        );
      }
      sequence.frameRate?.validate();
    }
    transform.validate();
  }
}

class AudioLayerPlan {
  const AudioLayerPlan({
    required this.id,
    required this.range,
    required this.source,
    this.sourceIn = Duration.zero,
    this.volumeDb = 0,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.pan = 0,
    this.pitchSemitones = 0,
    this.enabled = true,
    this.muted = false,
  });

  final String id;
  final MediaTimeRange range;
  final MediaLocation source;
  final Duration sourceIn;
  final double volumeDb;
  final Duration fadeIn;
  final Duration fadeOut;
  final double pan;
  final double pitchSemitones;
  final bool enabled;
  final bool muted;

  double get volumeFactor => math.pow(10, volumeDb / 20).toDouble();

  double get pitchFactor => math.pow(2, pitchSemitones / 12).toDouble();

  void validate() {
    _validateId(id, 'audio layer');
    range.validate('Audio layer $id');
    source.validate('Audio layer $id source');
    if (sourceIn.isNegative || fadeIn.isNegative || fadeOut.isNegative) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Audio source-in and fades cannot be negative.',
        context: {'layerId': id},
      );
    }
    if (!volumeDb.isFinite ||
        !pan.isFinite ||
        !pitchSemitones.isFinite ||
        pan < -1 ||
        pan > 1) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Audio controls are outside their supported range.',
        context: {'layerId': id},
      );
    }
    if (fadeIn + fadeOut > range.duration) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Combined audio fades exceed the clip duration.',
        context: {'layerId': id},
      );
    }
    if (pitchFactor <= 0 || !pitchFactor.isFinite) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Audio pitch produces an invalid factor.',
        context: {'layerId': id},
      );
    }
  }
}

class MediaRenderPlan {
  MediaRenderPlan({
    required this.id,
    required this.canvas,
    required this.frameRate,
    required this.duration,
    required List<VisualLayerPlan> visualLayers,
    required List<AudioLayerPlan> audioLayers,
    this.background = const MediaColor.transparent(),
    this.audioSampleRate = 48000,
    Map<String, Object?> metadata = const {},
  }) : visualLayers = List.unmodifiable(visualLayers),
       audioLayers = List.unmodifiable(audioLayers),
       metadata = Map.unmodifiable(metadata);

  final String id;
  final MediaCanvasSize canvas;
  final FrameRate frameRate;
  final Duration duration;
  final MediaColor background;
  final int audioSampleRate;
  final List<VisualLayerPlan> visualLayers;
  final List<AudioLayerPlan> audioLayers;
  final Map<String, Object?> metadata;

  int get totalFrames => frameRate.framesFor(duration);

  void validate() {
    _validateId(id, 'render plan');
    canvas.validate();
    frameRate.validate();
    background.validate();
    if (duration <= Duration.zero) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Render-plan duration must be positive.',
      );
    }
    if (audioSampleRate <= 0) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Audio sample rate must be positive.',
      );
    }
    final ids = <String>{};
    for (final layer in visualLayers) {
      layer.validate();
      if (!ids.add(layer.id)) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'Layer IDs must be unique.',
          context: {'layerId': layer.id},
        );
      }
      if (layer.range.end > duration) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'A layer extends beyond the render-plan duration.',
          context: {'layerId': layer.id},
        );
      }
    }
    for (final layer in audioLayers) {
      layer.validate();
      if (!ids.add(layer.id)) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'Layer IDs must be unique.',
          context: {'layerId': layer.id},
        );
      }
      if (layer.range.end > duration) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'A layer extends beyond the render-plan duration.',
          context: {'layerId': layer.id},
        );
      }
    }
  }
}

void _validateId(String id, String kind) {
  if (id.trim().isEmpty || id.contains('\u0000')) {
    throw MediaFailure(
      code: MediaFailureCode.invalidRequest,
      message: 'The $kind ID must be non-empty.',
    );
  }
}
