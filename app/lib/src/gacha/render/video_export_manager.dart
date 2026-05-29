import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'render_part.dart';
import 'tween_engine.dart';
import 'transform_graph.dart';
import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';

class VideoExportManager {
  const VideoExportManager._();

  static Future<String> exportScene({
    required ResolvedScene scene,
    required GachaCharacterState state,
    required ResolverTables tables,
    required Map<String, List<GachaKeyframe>> animationTracks,
    required String outputFileName,
    required int width,
    required int height,
    int durationSeconds = 3,
    int fps = 30,
  }) async {
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

    // 2. Pre-calculate parent world rest pose matrices to compute local matrices
    final heightX = tables.runtimeValueMaps.resolve(field: 'heightx', fieldValue: state.numeric('heightx'), op: 'scaleX', targetContains: 'char.char', fallback: 1);
    final heightY = tables.runtimeValueMaps.resolve(field: 'heighty', fieldValue: state.numeric('heighty'), op: 'scaleY', targetContains: 'char.char', fallback: 1);
    final rootRest = AffineMatrix.scale(heightX, heightY);

    final posePlacement = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'torso');
    final torsoRest = rootRest.multiply(posePlacement?.matrix ?? const AffineMatrix.identity());

    final headFlipMatrix = tables.headFlipPlacementFor(headflip: state.numeric('headflip'), name: 'head') ?? const AffineMatrix.identity();
    final headScaleX = tables.runtimeValueMaps.resolve(field: 'headsize', fieldValue: state.numeric('headsize'), op: 'scaleX', targetContains: 'head.head', fallback: 1);
    final headScaleY = tables.runtimeValueMaps.resolve(field: 'headsizey', fieldValue: state.numeric('headsizey'), op: 'scaleY', targetContains: 'head.head', fallback: 1);
    final headGroup = headFlipMatrix.multiply(AffineMatrix.scale(headScaleX, headScaleY));
    final headPlacement = tables.headPlacements['head'];
    final headHost = headPlacement?.matrix ?? const AffineMatrix.identity();
    final headRest = torsoRest.multiply(headGroup).multiply(headHost);

    final shoulderFrontPlacement = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'shoulder_front');
    final shoulderFrontRest = torsoRest.multiply(shoulderFrontPlacement?.matrix ?? const AffineMatrix.identity());

    final shoulderBackPlacement = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'shoulder_back');
    final shoulderBackRest = torsoRest.multiply(shoulderBackPlacement?.matrix ?? const AffineMatrix.identity());

    final thighFrontPlacement = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'thigh_front');
    final thighFrontRest = torsoRest.multiply(thighFrontPlacement?.matrix ?? const AffineMatrix.identity());

    final thighBackPlacement = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'thigh_back');
    final thighBackRest = torsoRest.multiply(thighBackPlacement?.matrix ?? const AffineMatrix.identity());

    AffineMatrix _jointRestWorld(String name) {
      switch (name) {
        case 'head': return headRest;
        case 'shoulder_front': return shoulderFrontRest;
        case 'shoulder_back': return shoulderBackRest;
        case 'thigh_front': return thighFrontRest;
        case 'thigh_back': return thighBackRest;
        case 'torso': return torsoRest;
        default: return rootRest;
      }
    }

    String _findTargetJointName(ResolvedRenderPart part) {
      final host = part.catalogPart.hostName.toLowerCase();
      final scope = part.catalogPart.hostScope.toLowerCase();
      final family = part.catalogPart.family.toLowerCase();

      if (scope == 'head' || family.contains('eye') || family.contains('eyebrow') || family.contains('hair') || family == 'hat' || family == 'glasses' || family.contains('accessory') || family.contains('other') || family == 'mouth' || family == 'nose' || family == 'blush' || family == 'faceshadow') {
        return 'head';
      }
      if (host.contains('shoulder_front') || host.contains('sleeve_front') || host.contains('hand_front') || host.contains('glove_front') || host.contains('wrist_front') || family.contains('weapon_front') || family == 'shield') {
        return 'shoulder_front';
      }
      if (host.contains('shoulder_back') || host.contains('sleeve_back') || host.contains('hand_back') || host.contains('glove_back') || host.contains('wrist_back') || family.contains('weapon_back')) {
        return 'shoulder_back';
      }
      if (host.contains('thigh_front') || host.contains('foot_front') || host.contains('socks_front') || host.contains('shoe_front') || host.contains('knee_front')) {
        return 'thigh_front';
      }
      if (host.contains('thigh_back') || host.contains('foot_back') || host.contains('socks_back') || host.contains('shoe_back') || host.contains('knee_back')) {
        return 'thigh_back';
      }
      return 'torso';
    }

    // Pre-calculate local matrices relative to respective parent joints
    final partsLocalMatrices = <String, AffineMatrix>{};
    for (final part in scene.parts) {
      final key = '${part.catalogPart.family}|${part.catalogPart.partRole}|${part.catalogPart.leafId}';
      final jointName = _findTargetJointName(part);
      final parentRest = _jointRestWorld(jointName);
      partsLocalMatrices[key] = parentRest.inverse().multiply(part.worldTransform);
    }

    // 3. Render frames sequentially evaluating keyframe timeline frame-by-frame
    final totalFrames = durationSeconds * fps;
    for (var i = 0; i < totalFrames; i++) {
      final t = i / fps;
      
      // Interpolate joint rotations at frame time t
      final tweens = <String, double>{};
      for (final entry in animationTracks.entries) {
        final trackName = entry.key;
        final keyframes = entry.value;
        if (keyframes.isNotEmpty) {
          final interpolated = TweenEngine.interpolate(keyframes: keyframes, time: t);
          tweens[trackName] = interpolated.angle;
        }
      }

      // Compute animated parent joint world matrices at frame time t
      final rootWorld = rootRest;
      final torsoWorld = torsoRest;

      var headLocal = headGroup.multiply(headHost);
      if (tweens.containsKey('head')) {
        headLocal = headLocal.multiply(AffineMatrix.rotationDegrees(tweens['head']!));
      }
      final headWorld = torsoWorld.multiply(headLocal);

      var shoulderFrontLocal = shoulderFrontPlacement?.matrix ?? const AffineMatrix.identity();
      if (tweens.containsKey('shoulder_front')) {
        shoulderFrontLocal = shoulderFrontLocal.multiply(AffineMatrix.rotationDegrees(tweens['shoulder_front']!));
      }
      final shoulderFrontWorld = torsoWorld.multiply(shoulderFrontLocal);

      var shoulderBackLocal = shoulderBackPlacement?.matrix ?? const AffineMatrix.identity();
      if (tweens.containsKey('shoulder_back')) {
        shoulderBackLocal = shoulderBackLocal.multiply(AffineMatrix.rotationDegrees(tweens['shoulder_back']!));
      }
      final shoulderBackWorld = torsoWorld.multiply(shoulderBackLocal);

      var thighFrontLocal = thighFrontPlacement?.matrix ?? const AffineMatrix.identity();
      if (tweens.containsKey('thigh_front')) {
        thighFrontLocal = thighFrontLocal.multiply(AffineMatrix.rotationDegrees(tweens['thigh_front']!));
      }
      final thighFrontWorld = torsoWorld.multiply(thighFrontLocal);

      var thighBackLocal = thighBackPlacement?.matrix ?? const AffineMatrix.identity();
      if (tweens.containsKey('thigh_back')) {
        thighBackLocal = thighBackLocal.multiply(AffineMatrix.rotationDegrees(tweens['thigh_back']!));
      }
      final thighBackWorld = torsoWorld.multiply(thighBackLocal);

      AffineMatrix _jointAnimatedWorld(String name) {
        switch (name) {
          case 'head': return headWorld;
          case 'shoulder_front': return shoulderFrontWorld;
          case 'shoulder_back': return shoulderBackWorld;
          case 'thigh_front': return thighFrontWorld;
          case 'thigh_back': return thighBackWorld;
          case 'torso': return torsoWorld;
          default: return rootWorld;
        }
      }

      // Start rendering this frame
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      final bgPaint = Paint()..color = const Color(0xFF1E262F);
      canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), bgPaint);

      if (scene.parts.isNotEmpty && !scene.worldBounds.isEmpty) {
        final paddedBounds = scene.worldBounds.inflate(48);
        const scale = 0.8;
        final cameraX = (width - paddedBounds.width * scale) / 2 - paddedBounds.left * scale;
        final cameraY = (height - paddedBounds.height * scale) / 2 - paddedBounds.top * scale;

        canvas.save();
        canvas.translate(cameraX, cameraY);
        canvas.scale(scale, scale);

        // Sort globally by priority depth during render
        final sortedParts = List<ResolvedRenderPart>.from(scene.parts);
        sortedParts.sort((a, b) => a.globalDepth.compareTo(b.globalDepth));

        for (final part in sortedParts) {
          final asset = scene.assets[part.catalogPart.appAssetPath];
          if (asset == null) continue;

          final key = '${part.catalogPart.family}|${part.catalogPart.partRole}|${part.catalogPart.leafId}';
          final localMatrix = partsLocalMatrices[key] ?? const AffineMatrix.identity();
          final jointName = _findTargetJointName(part);
          final parentWorld = _jointAnimatedWorld(jointName);
          final finalWorldMatrix = parentWorld.multiply(localMatrix);

          canvas.save();
          canvas.transform(finalWorldMatrix.toFloat64List());
          
          // Apply anchor translations
          final anchorX = part.catalogPart.runtimeAnchorX;
          final anchorY = part.catalogPart.runtimeAnchorY;
          canvas.translate(anchorX, anchorY);

          asset.paint(canvas, part.tintColor);
          canvas.restore();
        }
        canvas.restore();
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      
      if (byteData != null) {
        await FlutterQuickVideoEncoder.feedVideoEncoder(byteData.buffer.asUint8List());
      }
    }

    // 4. Finish encoding and output the finished MP4 file
    await FlutterQuickVideoEncoder.finish();
    return filepath;
  }
}
