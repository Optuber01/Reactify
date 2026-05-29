import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'render_part.dart';

class VideoExportManager {
  const VideoExportManager._();

  static Future<String> exportScene({
    required ResolvedScene scene,
    required String outputFileName,
    required int width,
    required int height,
    int durationSeconds = 3,
    int fps = 30,
  }) async {
    // Generate writable local path
    final tempDir = Directory.systemTemp;
    final filepath = '${tempDir.path}/$outputFileName';

    // 1. Setup encoder
    await FlutterQuickVideoEncoder.setup(
      width: width,
      height: height,
      fps: fps,
      videoBitrate: 2500000,
      audioChannels: 0,
      audioBitrate: 0,
      sampleRate: 0,
      filepath: filepath,
    );

    // 2. Render frames sequentially
    final totalFrames = durationSeconds * fps;
    for (var i = 0; i < totalFrames; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Draw background
      final bgPaint = Paint()..color = const Color(0xFF1E262F);
      canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), bgPaint);

      // Render character scene parts
      if (scene.parts.isNotEmpty && !scene.worldBounds.isEmpty) {
        final paddedBounds = scene.worldBounds.inflate(48);
        final scale = ui.lerpDouble(1.0, 1.2, i / totalFrames)! * 0.8;
        final cameraX = (width - paddedBounds.width * scale) / 2 - paddedBounds.left * scale;
        final cameraY = (height - paddedBounds.height * scale) / 2 - paddedBounds.top * scale;

        canvas.save();
        canvas.translate(cameraX, cameraY);
        canvas.scale(scale, scale);

        for (final part in scene.parts) {
          final asset = scene.assets[part.catalogPart.appAssetPath];
          if (asset == null) continue;
          canvas.save();
          canvas.transform(part.worldTransform.toFloat64List());
          asset.paint(canvas, part.tintColor);
          canvas.restore();
        }
        canvas.restore();
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      
      if (byteData != null) {
        final rawBytes = byteData.buffer.asUint8List();
        // Feed frame to hardware encoder
        await FlutterQuickVideoEncoder.feedVideoEncoder(rawBytes);
      }
    }

    // 3. Finish and output file
    await FlutterQuickVideoEncoder.finish();
    return filepath;
  }
}
