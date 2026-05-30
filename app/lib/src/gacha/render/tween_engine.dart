import 'package:flutter/animation.dart';

class GachaKeyframe {
  const GachaKeyframe({
    required this.time, // Time in seconds
    required this.position,
    required this.scale,
    required this.angle,
    this.curve = Curves.easeInOut,
  });

  final double time;
  final Offset position;
  final Offset scale;
  final double angle;
  final Curve curve;
}

class TweenEngine {
  const TweenEngine._();

  static double lerpDouble(double start, double end, double t, Curve curve) {
    final double eased = curve.transform(t);
    return start + (end - start) * eased;
  }

  static Offset lerpOffset(Offset start, Offset end, double t, Curve curve) {
    final double eased = curve.transform(t);
    return Offset(
      start.dx + (end.dx - start.dx) * eased,
      start.dy + (end.dy - start.dy) * eased,
    );
  }

  static GachaKeyframe interpolate({
    required List<GachaKeyframe> keyframes,
    required double time,
  }) {
    if (keyframes.isEmpty) {
      return const GachaKeyframe(
        time: 0,
        position: Offset.zero,
        scale: Offset(1, 1),
        angle: 0,
      );
    }
    if (keyframes.length == 1 || time <= keyframes.first.time) {
      return keyframes.first;
    }
    if (time >= keyframes.last.time) {
      return keyframes.last;
    }

    // Find bounding keyframes
    GachaKeyframe? startFrame;
    GachaKeyframe? endFrame;

    for (var i = 0; i < keyframes.length - 1; i++) {
      if (time >= keyframes[i].time && time <= keyframes[i + 1].time) {
        startFrame = keyframes[i];
        endFrame = keyframes[i + 1];
        break;
      }
    }

    startFrame ??= keyframes.first;
    endFrame ??= keyframes.last;

    final range = endFrame.time - startFrame.time;
    final progress = range == 0 ? 0.0 : (time - startFrame.time) / range;

    return GachaKeyframe(
      time: time,
      position: lerpOffset(startFrame.position, endFrame.position, progress, endFrame.curve),
      scale: lerpOffset(startFrame.scale, endFrame.scale, progress, endFrame.curve),
      angle: lerpDouble(startFrame.angle, endFrame.angle, progress, endFrame.curve),
      curve: endFrame.curve,
    );
  }

  static double interpolateAngle({
    required List<GachaKeyframe> keyframes,
    required double time,
  }) {
    if (keyframes.isEmpty) return 0.0;
    if (keyframes.length == 1 || time <= keyframes.first.time) {
      return keyframes.first.angle;
    }
    if (time >= keyframes.last.time) {
      return keyframes.last.angle;
    }

    GachaKeyframe? startFrame;
    GachaKeyframe? endFrame;

    for (var i = 0; i < keyframes.length - 1; i++) {
      if (time >= keyframes[i].time && time <= keyframes[i + 1].time) {
        startFrame = keyframes[i];
        endFrame = keyframes[i + 1];
        break;
      }
    }

    startFrame ??= keyframes.first;
    endFrame ??= keyframes.last;

    final range = endFrame.time - startFrame.time;
    final progress = range == 0 ? 0.0 : (time - startFrame.time) / range;

    return lerpDouble(startFrame.angle, endFrame.angle, progress, endFrame.curve);
  }
}

class TimelineController {
  TimelineController({
    required this.maxDuration,
  });

  final double maxDuration;
  double currentTime = 0.0;
  bool isPlaying = false;

  void update(double dt) {
    if (!isPlaying) return;
    currentTime += dt;
    if (currentTime >= maxDuration) {
      currentTime = 0.0; // Loop playback
    }
  }
}
