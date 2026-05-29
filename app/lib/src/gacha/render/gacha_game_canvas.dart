import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'render_part.dart';
import 'gacha_joint_component.dart';
import 'transform_graph.dart';
import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';
import 'tween_engine.dart';

class GachaGameCanvas extends FlameGame {
  GachaGameCanvas();

  ResolvedScene? _scene;
  PositionComponent? _rootComponent;

  // Cache components by a unique family role key to keep them persistent
  final Map<String, GachaPartComponent> _componentsByKey = {};

  // Store logical parent world matrices
  AffineMatrix rootWorld = const AffineMatrix.identity();
  AffineMatrix torsoWorld = const AffineMatrix.identity();
  AffineMatrix headWorld = const AffineMatrix.identity();
  AffineMatrix shoulderFrontWorld = const AffineMatrix.identity();
  AffineMatrix shoulderBackWorld = const AffineMatrix.identity();
  AffineMatrix forearmFrontWorld = const AffineMatrix.identity();
  AffineMatrix forearmBackWorld = const AffineMatrix.identity();
  AffineMatrix hipWorld = const AffineMatrix.identity();
  AffineMatrix thighFrontWorld = const AffineMatrix.identity();
  AffineMatrix thighBackWorld = const AffineMatrix.identity();
  AffineMatrix feetFrontWorld = const AffineMatrix.identity();
  AffineMatrix feetBackWorld = const AffineMatrix.identity();

  // Animation tween offsets
  final Map<String, double> jointRotationTweens = {};

  ResolvedScene? get scene => _scene;

  set scene(ResolvedScene? newScene) {
    if (_scene == newScene) return;
    _scene = newScene;
  }

  // Update scene in-place (persistent tree updates)
  void updateScene(ResolvedScene scene, GachaCharacterState state, ResolverTables tables) {
    _scene = scene;

    if (_rootComponent == null) {
      final root = PositionComponent();
      _rootComponent = root;
      add(root);

      // Rig physical Gacha skeleton hierarchy
      final torso = GachaJointComponent(name: 'torso');
      final head = GachaJointComponent(name: 'head');
      final shoulderFront = GachaJointComponent(name: 'shoulder_front');
      final shoulderBack = GachaJointComponent(name: 'shoulder_back');
      final forearmFront = GachaJointComponent(name: 'forearm_front');
      final forearmBack = GachaJointComponent(name: 'forearm_back');
      final hip = GachaJointComponent(name: 'hip');
      final thighFront = GachaJointComponent(name: 'thigh_front');
      final thighBack = GachaJointComponent(name: 'thigh_back');
      final feetFront = GachaJointComponent(name: 'feet_front');
      final feetBack = GachaJointComponent(name: 'feet_back');

      root.add(torso);
      torso.add(head);
      torso.add(shoulderFront);
      torso.add(shoulderBack);
      shoulderFront.add(forearmFront);
      shoulderBack.add(forearmBack);
      torso.add(hip);
      hip.add(thighFront);
      hip.add(thighBack);
      thighFront.add(feetFront);
      thighBack.add(feetBack);
    }

    final root = _rootComponent!;
    final torso = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'torso');
    final head = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'head');
    final shoulderFront = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'shoulder_front');
    final shoulderBack = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'shoulder_back');
    final forearmFront = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'forearm_front');
    final forearmBack = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'forearm_back');
    final hip = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'hip');
    final thighFront = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'thigh_front');
    final thighBack = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'thigh_back');
    final feetFront = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'feet_front');
    final feetBack = root.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'feet_back');

    // 1. Calculate and update logical joint matrices
    _updateJointMatrices(state, tables);

    // 2. Set native position, scale, and rotations on logical joints
    _applyLocalTransform(root, rootWorld);
    
    final posePlacement = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'torso');
    _applyLocalTransform(torso, posePlacement?.matrix ?? const AffineMatrix.identity());

    final headFlipMatrix = tables.headFlipPlacementFor(headflip: state.numeric('headflip'), name: 'head')?.matrix ?? const AffineMatrix.identity();
    final headScaleX = tables.runtimeValueMaps.resolve(field: 'headsize', fieldValue: state.numeric('headsize'), op: 'scaleX', targetContains: 'head.head', fallback: 1);
    final headScaleY = tables.runtimeValueMaps.resolve(field: 'headsizey', fieldValue: state.numeric('headsizey'), op: 'scaleY', targetContains: 'head.head', fallback: 1);
    final headGroup = headFlipMatrix.multiply(AffineMatrix.scale(headScaleX, headScaleY));
    final headPlacement = tables.headPlacements['head'];
    final headHost = headPlacement?.matrix ?? const AffineMatrix.identity();
    
    // Combine head transform with keyframed animation rotation
    var headLocal = headGroup.multiply(headHost);
    if (jointRotationTweens.containsKey('head')) {
      headLocal = headLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['head']!));
    }
    _applyLocalTransform(head, headLocal);

    // Shoulders
    var shoulderFrontLocal = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'shoulder_front')?.matrix ?? const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('shoulder_front')) {
      shoulderFrontLocal = shoulderFrontLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['shoulder_front']!));
    }
    _applyLocalTransform(shoulderFront, shoulderFrontLocal);

    var shoulderBackLocal = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'shoulder_back')?.matrix ?? const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('shoulder_back')) {
      shoulderBackLocal = shoulderBackLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['shoulder_back']!));
    }
    _applyLocalTransform(shoulderBack, shoulderBackLocal);

    // Forearms (local identity modified by rotation tweens relative to shoulder parents)
    var forearmFrontLocal = const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('forearm_front')) {
      forearmFrontLocal = forearmFrontLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['forearm_front']!));
    }
    _applyLocalTransform(forearmFront, forearmFrontLocal);

    var forearmBackLocal = const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('forearm_back')) {
      forearmBackLocal = forearmBackLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['forearm_back']!));
    }
    _applyLocalTransform(forearmBack, forearmBackLocal);

    // Hip (local identity relative to torso parent)
    _applyLocalTransform(hip, const AffineMatrix.identity());

    // Thighs (local matrix relative to hip parent)
    var thighFrontLocal = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'thigh_front')?.matrix ?? const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('thigh_front')) {
      thighFrontLocal = thighFrontLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['thigh_front']!));
    }
    _applyLocalTransform(thighFront, thighFrontLocal);

    var thighBackLocal = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'thigh_back')?.matrix ?? const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('thigh_back')) {
      thighBackLocal = thighBackLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['thigh_back']!));
    }
    _applyLocalTransform(thighBack, thighBackLocal);

    // Feet (local identity modified by rotation tweens relative to thigh parents)
    var feetFrontLocal = const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('foot_front')) {
      feetFrontLocal = feetFrontLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['foot_front']!));
    }
    _applyLocalTransform(feetFront, feetFrontLocal);

    var feetBackLocal = const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('foot_back')) {
      feetBackLocal = feetBackLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['foot_back']!));
    }
    _applyLocalTransform(feetBack, feetBackLocal);

    // 3. Track and update part components dynamically
    final newKeys = <String>{};
    for (final part in scene.parts) {
      final key = _partKey(part);
      newKeys.add(key);

      final targetJoint = _findTargetJoint(part, torso, head, shoulderFront, shoulderBack, forearmFront, forearmBack, hip, thighFront, thighBack, feetFront, feetBack);
      final parentWorldMatrix = _jointWorldMatrix(targetJoint.name);
      
      // Rig using inverse matrices: localMatrix = parentWorldMatrix.inverse() * worldTransform
      final localMatrix = parentWorldMatrix.inverse().multiply(part.worldTransform);
      final asset = scene.assets[part.catalogPart.appAssetPath];

      if (_componentsByKey.containsKey(key)) {
        final comp = _componentsByKey[key]!;
        comp.updatePart(part, asset, localMatrix);
        
        if (comp.parent != targetJoint) {
          comp.removeFromParent();
          targetJoint.add(comp);
        }
      } else {
        final comp = GachaPartComponent(
          part: part,
          asset: asset,
          tintColor: part.tintColor,
          globalDepth: part.globalDepth,
          localMatrix: localMatrix,
        );
        targetJoint.add(comp);
        _componentsByKey[key] = comp;
      }
    }

    // 4. Remove component nodes no longer active
    final keysToRemove = _componentsByKey.keys.where((k) => !newKeys.contains(k)).toList();
    for (final key in keysToRemove) {
      final comp = _componentsByKey.remove(key)!;
      comp.removeFromParent();
    }
  }

  // Set local position, scale, angle on target PositionComponent
  void _applyLocalTransform(PositionComponent component, AffineMatrix matrix) {
    final scaleX = ui.lerpDouble(0, 1, math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b)) ?? 1.0;
    final scaleY = ui.lerpDouble(0, 1, math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d)) ?? 1.0;
    final angle = math.atan2(matrix.b, matrix.a);

    component.position = Vector2(matrix.tx, matrix.ty);
    component.scale = Vector2(scaleX, scaleY);
    component.angle = angle;
  }

  // Deconstruct full body joint world matrix references
  void _updateJointMatrices(GachaCharacterState state, ResolverTables tables) {
    final heightX = tables.runtimeValueMaps.resolve(field: 'heightx', fieldValue: state.numeric('heightx'), op: 'scaleX', targetContains: 'char.char', fallback: 1);
    final heightY = tables.runtimeValueMaps.resolve(field: 'heighty', fieldValue: state.numeric('heighty'), op: 'scaleY', targetContains: 'char.char', fallback: 1);
    rootWorld = AffineMatrix.scale(heightX, heightY);

    final posePlacement = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'torso');
    torsoWorld = rootWorld.multiply(posePlacement?.matrix ?? const AffineMatrix.identity());

    final headFlipMatrix = tables.headFlipPlacementFor(headflip: state.numeric('headflip'), name: 'head')?.matrix ?? const AffineMatrix.identity();
    final headScaleX = tables.runtimeValueMaps.resolve(field: 'headsize', fieldValue: state.numeric('headsize'), op: 'scaleX', targetContains: 'head.head', fallback: 1);
    final headScaleY = tables.runtimeValueMaps.resolve(field: 'headsizey', fieldValue: state.numeric('headsizey'), op: 'scaleY', targetContains: 'head.head', fallback: 1);
    final headGroup = headFlipMatrix.multiply(AffineMatrix.scale(headScaleX, headScaleY));
    final headPlacement = tables.headPlacements['head'];
    final headHost = headPlacement?.matrix ?? const AffineMatrix.identity();
    
    var headLocal = headGroup.multiply(headHost);
    if (jointRotationTweens.containsKey('head')) {
      headLocal = headLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['head']!));
    }
    headWorld = torsoWorld.multiply(headLocal);

    var shoulderFrontLocal = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'shoulder_front')?.matrix ?? const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('shoulder_front')) {
      shoulderFrontLocal = shoulderFrontLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['shoulder_front']!));
    }
    shoulderFrontWorld = torsoWorld.multiply(shoulderFrontLocal);

    var shoulderBackLocal = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'shoulder_back')?.matrix ?? const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('shoulder_back')) {
      shoulderBackLocal = shoulderBackLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['shoulder_back']!));
    }
    shoulderBackWorld = torsoWorld.multiply(shoulderBackLocal);

    var forearmFrontLocal = const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('forearm_front')) {
      forearmFrontLocal = forearmFrontLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['forearm_front']!));
    }
    forearmFrontWorld = shoulderFrontWorld.multiply(forearmFrontLocal);

    var forearmBackLocal = const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('forearm_back')) {
      forearmBackLocal = forearmBackLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['forearm_back']!));
    }
    forearmBackWorld = shoulderBackWorld.multiply(forearmBackLocal);

    hipWorld = torsoWorld;

    var thighFrontLocal = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'thigh_front')?.matrix ?? const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('thigh_front')) {
      thighFrontLocal = thighFrontLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['thigh_front']!));
    }
    thighFrontWorld = hipWorld.multiply(thighFrontLocal);

    var thighBackLocal = tables.posePlacementFor(pose: state.numeric('pose'), hostName: 'thigh_back')?.matrix ?? const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('thigh_back')) {
      thighBackLocal = thighBackLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['thigh_back']!));
    }
    thighBackWorld = hipWorld.multiply(thighBackLocal);

    var feetFrontLocal = const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('foot_front')) {
      feetFrontLocal = feetFrontLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['foot_front']!));
    }
    feetFrontWorld = thighFrontWorld.multiply(feetFrontLocal);

    var feetBackLocal = const AffineMatrix.identity();
    if (jointRotationTweens.containsKey('foot_back')) {
      feetBackLocal = feetBackLocal.multiply(AffineMatrix.rotationDegrees(jointRotationTweens['foot_back']!));
    }
    feetBackWorld = thighBackWorld.multiply(feetBackLocal);
  }

  AffineMatrix _jointWorldMatrix(String name) {
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
      case 'torso': return torsoWorld;
      default: return rootWorld;
    }
  }

  // Logical target bone mapping
  GachaJointComponent _findTargetJoint(
    ResolvedRenderPart part,
    GachaJointComponent torso,
    GachaJointComponent head,
    GachaJointComponent shoulderFront,
    GachaJointComponent shoulderBack,
    GachaJointComponent forearmFront,
    GachaJointComponent forearmBack,
    GachaJointComponent hip,
    GachaJointComponent thighFront,
    GachaJointComponent thighBack,
    GachaJointComponent feetFront,
    GachaJointComponent feetBack,
  ) {
    final host = part.catalogPart.hostName.toLowerCase();
    final scope = part.catalogPart.hostScope.toLowerCase();
    final family = part.catalogPart.family.toLowerCase();

    if (scope == 'head' || family.contains('eye') || family.contains('eyebrow') || family.contains('hair') || family == 'hat' || family == 'glasses' || family.contains('accessory') || family.contains('other') || family == 'mouth' || family == 'nose' || family == 'blush' || family == 'faceshadow') {
      return head;
    }
    if (host.contains('sleeve_front') || host.contains('hand_front') || host.contains('glove_front') || host.contains('wrist_front') || family.contains('weapon_front') || family == 'shield') {
      return forearmFront;
    }
    if (host.contains('sleeve_back') || host.contains('hand_back') || host.contains('glove_back') || host.contains('wrist_back') || family.contains('weapon_back')) {
      return forearmBack;
    }
    if (host.contains('shoulder_front')) {
      return shoulderFront;
    }
    if (host.contains('shoulder_back')) {
      return shoulderBack;
    }
    if (host.contains('socks_front') || host.contains('shoe_front') || host.contains('foot_front') || host.contains('knee_front')) {
      return feetFront;
    }
    if (host.contains('socks_back') || host.contains('shoe_back') || host.contains('foot_back') || host.contains('knee_back')) {
      return feetBack;
    }
    if (host.contains('thigh_front')) {
      return thighFront;
    }
    if (host.contains('thigh_back')) {
      return thighBack;
    }
    if (host.contains('hip') || family.contains('belt')) {
      return hip;
    }
    return torso;
  }

  String _partKey(ResolvedRenderPart part) {
    return '${part.catalogPart.family}|${part.catalogPart.partRole}|${part.catalogPart.leafId}';
  }

  // Interpolate joint rotations smoothly based on timeline scrubber
  void updateAnimations(double time, Map<String, List<GachaKeyframe>> keyframeTracks) {
    jointRotationTweens.clear();
    for (final entry in keyframeTracks.entries) {
      final trackName = entry.key;
      final keyframes = entry.value;
      if (keyframes.isNotEmpty) {
        final interpolated = TweenEngine.interpolate(keyframes: keyframes, time: time);
        jointRotationTweens[trackName] = interpolated.angle; // Eased rotation angle
      }
    }
  }

  @override
  void renderTree(Canvas canvas) {
    // Collect nested parts and draw in global priority depth order
    final parts = descendants().whereType<GachaPartComponent>().toList();
    parts.sort((a, b) => a.priority.compareTo(b.priority));
    
    for (final part in parts) {
      canvas.save();
      // Apply the absolute world matrix calculated by our parent-child skeletal math!
      canvas.transform(part.part.worldTransform.toFloat64List());
      part.render(canvas);
      canvas.restore();
    }
  }

  @override
  Color backgroundColor() => const Color(0x00000000);
}
