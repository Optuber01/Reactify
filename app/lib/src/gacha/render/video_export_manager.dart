import 'dart:io';
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
      profileLevel: ProfileLevel.any,
      audioChannels: 0,
      audioBitrate: 0,
      sampleRate: 0,
      filepath: filepath,
    );

    final partTransformList = Float64List(16);
    partTransformList[2] = 0.0;
    partTransformList[3] = 0.0;
    partTransformList[6] = 0.0;
    partTransformList[7] = 0.0;
    partTransformList[8] = 0.0;
    partTransformList[9] = 0.0;
    partTransformList[10] = 1.0;
    partTransformList[11] = 0.0;
    partTransformList[14] = 0.0;
    partTransformList[15] = 1.0;

    final heightX = tables.runtimeValueMaps.resolve(field: 'heightx', fieldValue: state.numeric('heightx'), op: 'scaleX', targetContains: 'char.char', fallback: 1);
    final heightY = tables.runtimeValueMaps.resolve(field: 'heighty', fieldValue: state.numeric('heighty'), op: 'scaleY', targetContains: 'char.char', fallback: 1);
    final rootLocal = AffineMatrix.scale(heightX, heightY);

    final poseTorso = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'body')?.matrix ?? const AffineMatrix.identity();
    final poseHead = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'head')?.matrix ?? const AffineMatrix.identity();
    final poseShoulderFront = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'shoulder_front')?.matrix ?? const AffineMatrix.identity();
    final poseShoulderBack = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'shoulder_back')?.matrix ?? const AffineMatrix.identity();
    final poseForearmFront = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'sleeve_front')?.matrix ?? const AffineMatrix.identity();
    final poseForearmBack = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'sleeve_back')?.matrix ?? const AffineMatrix.identity();
    final poseThighFront = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'thigh_front')?.matrix ?? const AffineMatrix.identity();
    final poseThighBack = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'thigh_back')?.matrix ?? const AffineMatrix.identity();
    final poseFeetFront = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'foot_front')?.matrix ?? const AffineMatrix.identity();
    final poseFeetBack = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'foot_back')?.matrix ?? const AffineMatrix.identity();

    final torsoLocalBase = poseTorso;
    final headLocalBase = poseTorso.inverse().multiply(poseHead);
    final shoulderFrontLocalBase = poseTorso.inverse().multiply(poseShoulderFront);
    final shoulderBackLocalBase = poseTorso.inverse().multiply(poseShoulderBack);
    final forearmFrontLocalBase = poseShoulderFront.inverse().multiply(poseForearmFront);
    final forearmBackLocalBase = poseShoulderBack.inverse().multiply(poseForearmBack);
    final hipLocalBase = const AffineMatrix.identity();
    final thighFrontLocalBase = poseTorso.inverse().multiply(poseThighFront);
    final thighBackLocalBase = poseTorso.inverse().multiply(poseThighBack);
    final feetFrontLocalBase = poseThighFront.inverse().multiply(poseFeetFront);
    final feetBackLocalBase = poseThighBack.inverse().multiply(poseFeetBack);

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
      final rootWorld = rootLocal;

      final torsoLocal = torsoLocalBase;
      final torsoWorld = rootWorld.multiply(tweens.containsKey('torso') ? torsoLocal.multiply(AffineMatrix.rotationDegrees(tweens['torso']!)) : torsoLocal);

      final headLocal = headLocalBase;
      final headWorld = torsoWorld.multiply(tweens.containsKey('head') ? headLocal.multiply(AffineMatrix.rotationDegrees(tweens['head']!)) : headLocal);

      final shoulderFrontLocal = shoulderFrontLocalBase;
      final shoulderFrontWorld = torsoWorld.multiply(tweens.containsKey('shoulder_front') ? shoulderFrontLocal.multiply(AffineMatrix.rotationDegrees(tweens['shoulder_front']!)) : shoulderFrontLocal);

      final shoulderBackLocal = shoulderBackLocalBase;
      final shoulderBackWorld = torsoWorld.multiply(tweens.containsKey('shoulder_back') ? shoulderBackLocal.multiply(AffineMatrix.rotationDegrees(tweens['shoulder_back']!)) : shoulderBackLocal);

      final forearmFrontLocal = forearmFrontLocalBase;
      final forearmFrontWorld = shoulderFrontWorld.multiply(tweens.containsKey('forearm_front') ? forearmFrontLocal.multiply(AffineMatrix.rotationDegrees(tweens['forearm_front']!)) : forearmFrontLocal);

      final forearmBackLocal = forearmBackLocalBase;
      final forearmBackWorld = shoulderBackWorld.multiply(tweens.containsKey('forearm_back') ? forearmBackLocal.multiply(AffineMatrix.rotationDegrees(tweens['forearm_back']!)) : forearmBackLocal);

      final hipLocal = hipLocalBase;
      final hipWorld = torsoWorld.multiply(tweens.containsKey('hip') ? hipLocal.multiply(AffineMatrix.rotationDegrees(tweens['hip']!)) : hipLocal);

      final thighFrontLocal = thighFrontLocalBase;
      final thighFrontWorld = hipWorld.multiply(tweens.containsKey('thigh_front') ? thighFrontLocal.multiply(AffineMatrix.rotationDegrees(tweens['thigh_front']!)) : thighFrontLocal);

      final thighBackLocal = thighBackLocalBase;
      final thighBackWorld = hipWorld.multiply(tweens.containsKey('thigh_back') ? thighBackLocal.multiply(AffineMatrix.rotationDegrees(tweens['thigh_back']!)) : thighBackLocal);

      final feetFrontLocal = feetFrontLocalBase;
      final feetFrontWorld = thighFrontWorld.multiply(tweens.containsKey('foot_front') ? feetFrontLocal.multiply(AffineMatrix.rotationDegrees(tweens['foot_front']!)) : feetFrontLocal);

      final feetBackLocal = feetBackLocalBase;
      final feetBackWorld = thighBackWorld.multiply(tweens.containsKey('foot_back') ? feetBackLocal.multiply(AffineMatrix.rotationDegrees(tweens['foot_back']!)) : feetBackLocal);

      AffineMatrix jointAnimatedWorld(String name) {
        switch (name) {
          case 'head': return headWorld;
          case 'shoulder_front': return shoulderFrontWorld;
          case 'shoulder_back': return shoulderBackWorld;
          case 'forearm_front': return forearmFrontWorld;
          case 'forearm_back': return forearmBackWorld;
          case 'hip': return hipWorld;
          case 'thigh_front': return thighFrontWorld;
          case 'thigh_back': return thighBackWorld;
          case 'feet_front': return feetFrontWorld;
          case 'feet_back': return feetBackWorld;
          default: return torsoWorld;
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

          final parentWorld = jointAnimatedWorld(part.targetJoint);
          final finalWorldMatrix = parentWorld.multiply(part.localTransform);

          partTransformList[0] = finalWorldMatrix.a;
          partTransformList[1] = finalWorldMatrix.b;
          partTransformList[4] = finalWorldMatrix.c;
          partTransformList[5] = finalWorldMatrix.d;
          partTransformList[12] = finalWorldMatrix.tx;
          partTransformList[13] = finalWorldMatrix.ty;

          canvas.save();
          canvas.transform(partTransformList);
          
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
        await FlutterQuickVideoEncoder.appendVideoFrame(byteData.buffer.asUint8List());
      }
    }

    // 4. Finish encoding and output the finished MP4 file
    await FlutterQuickVideoEncoder.finish();
    return filepath;
  }
}
