import 'dart:math' as math;
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'render_part.dart';
import 'gacha_joint_component.dart';

class GachaGameCanvas extends FlameGame {
  GachaGameCanvas();

  ResolvedScene? _scene;
  PositionComponent? _rootComponent;

  ResolvedScene? get scene => _scene;

  set scene(ResolvedScene? newScene) {
    if (_scene == newScene) return;
    _scene = newScene;
    _rebuildScene();
  }

  void _rebuildScene() {
    if (_rootComponent != null) {
      remove(_rootComponent!);
      _rootComponent = null;
    }
    final scene = _scene;
    if (scene == null || scene.parts.isEmpty) {
      return;
    }

    final root = PositionComponent();
    _rootComponent = root;
    add(root);

    // Build skeletal joints structure to represent skeleton rig
    final torsoJoint = GachaJointComponent(name: 'torso');
    final headJoint = GachaJointComponent(name: 'head');
    final shoulderFrontJoint = GachaJointComponent(name: 'shoulder_front');
    final shoulderBackJoint = GachaJointComponent(name: 'shoulder_back');

    root.add(torsoJoint);
    torsoJoint.add(headJoint);
    torsoJoint.add(shoulderFrontJoint);
    torsoJoint.add(shoulderBackJoint);

    // Create and attach GachaPartComponents representing parts rigged to their world properties
    for (final part in scene.parts) {
      final asset = scene.assets[part.catalogPart.appAssetPath];
      final comp = GachaPartComponent(
        part: part,
        asset: asset,
        tintColor: part.tintColor,
        globalDepth: part.globalDepth,
      );

      // Decompose 2D affine matrix into Flame component properties
      final matrix = part.worldTransform;
      final scaleX = math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b);
      final scaleY = math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d);
      final angle = math.atan2(matrix.b, matrix.a);

      comp.position = Vector2(matrix.tx, matrix.ty);
      comp.scale = Vector2(scaleX, scaleY);
      comp.angle = angle;

      // Add to root component to enable native global depth priority sorting
      root.add(comp);
    }
  }

  @override
  Color backgroundColor() => const Color(0x00000000);
}
