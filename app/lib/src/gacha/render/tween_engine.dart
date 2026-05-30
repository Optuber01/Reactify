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

  static int _binarySearch(List<GachaKeyframe> keyframes, double time) {
    var low = 0;
    var high = keyframes.length - 2;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (time < keyframes[mid].time) {
        high = mid - 1;
      } else if (time > keyframes[mid + 1].time) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return low;
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

    final index = _binarySearch(keyframes, time);
    final startFrame = keyframes[index];
    final endFrame = keyframes[index + 1];

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

    final index = _binarySearch(keyframes, time);
    final startFrame = keyframes[index];
    final endFrame = keyframes[index + 1];

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
