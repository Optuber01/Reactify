import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'render_part.dart';

class GachaVectorCache {
  static final GachaVectorCache instance = GachaVectorCache._();
  GachaVectorCache._();

  final Map<String, ui.Image> _gpuCache = {};
  final Map<String, Future<ui.Image>> _pendingGpuCache = {};

  String _cacheKey(
    String path,
    Color? tintColor,
    double tintStrength,
    double opacity,
  ) {
    final hex = tintColor?.toARGB32().toRadixString(16) ?? 'none';
    return '$path|$hex|$tintStrength|$opacity';
  }

  Future<ui.Image> getRasterized(
    PreparedAsset asset,
    Color? tintColor, {
    double tintStrength = 1,
    double opacity = 1,
  }) async {
    final key = _cacheKey(asset.assetPath, tintColor, tintStrength, opacity);
    if (_gpuCache.containsKey(key)) {
      return _gpuCache[key]!;
    }
    final pending = _pendingGpuCache[key];
    if (pending != null) {
      return pending;
    }

    final future = _rasterize(
      asset,
      tintColor,
      tintStrength: tintStrength,
      opacity: opacity,
    );
    _pendingGpuCache[key] = future;
    try {
      final image = await future;
      if (_gpuCache.length >= 150) {
        final firstKey = _gpuCache.keys.first;
        final oldImage = _gpuCache.remove(firstKey);
        oldImage?.dispose();
      }
      _gpuCache[key] = image;
      return image;
    } finally {
      _pendingGpuCache.remove(key);
    }
  }

  Future<ui.Image> _rasterize(
    PreparedAsset asset,
    Color? tintColor, {
    required double tintStrength,
    required double opacity,
  }) async {
    const scale = 2.0;
    final width = (asset.size.width * scale).ceil();
    final height = (asset.size.height * scale).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale, scale);

    asset.paint(
      canvas,
      tintColor,
      tintStrength: tintStrength,
      opacity: opacity,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }
}
