import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'render_part.dart';
import 'gacha_joint_component.dart';
import 'transform_graph.dart';
import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';

class GachaGameCanvas extends FlameGame {
  GachaGameCanvas();

  ResolvedScene? _scene;
  GachaCharacterState? _state;
  ResolverTables? _tables;
  GachaJointComponent? _rootComponent;

  final Map<String, GachaPartComponent> _componentsByKey = {};

  late GachaJointComponent _torso;
  late GachaJointComponent _head;
  late GachaJointComponent _shoulderFront;
  late GachaJointComponent _shoulderBack;
  late GachaJointComponent _forearmFront;
  late GachaJointComponent _forearmBack;
  late GachaJointComponent _hip;
  late GachaJointComponent _thighFront;
  late GachaJointComponent _thighBack;
  late GachaJointComponent _feetFront;
  late GachaJointComponent _feetBack;

  ResolvedScene? get scene => _scene;
  int get activePartComponentCount => _componentsByKey.length;
  AffineMatrix? get rootTransform => _rootComponent?.localMatrix;

  set scene(ResolvedScene? newScene) {
    if (_scene == newScene) return;
    _scene = newScene;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final scene = _scene;
    final state = _state;
    final tables = _tables;
    if (scene != null && state != null && tables != null) {
      updateScene(scene, state, tables);
    }
  }

  void updateScene(
    ResolvedScene scene,
    GachaCharacterState state,
    ResolverTables tables,
  ) {
    _scene = scene;
    _state = state;
    _tables = tables;

    if (_rootComponent == null) {
      final root = GachaJointComponent(name: 'root');
      _rootComponent = root;
      add(root);

      _torso = GachaJointComponent(name: 'torso');
      _head = GachaJointComponent(name: 'head');
      _shoulderFront = GachaJointComponent(name: 'shoulder_front');
      _shoulderBack = GachaJointComponent(name: 'shoulder_back');
      _forearmFront = GachaJointComponent(name: 'forearm_front');
      _forearmBack = GachaJointComponent(name: 'forearm_back');
      _hip = GachaJointComponent(name: 'hip');
      _thighFront = GachaJointComponent(name: 'thigh_front');
      _thighBack = GachaJointComponent(name: 'thigh_back');
      _feetFront = GachaJointComponent(name: 'feet_front');
      _feetBack = GachaJointComponent(name: 'feet_back');

      root.add(_torso);
      _torso.add(_head);
      _torso.add(_shoulderFront);
      _torso.add(_shoulderBack);
      _shoulderFront.add(_forearmFront);
      _shoulderBack.add(_forearmBack);
      _torso.add(_hip);
      _hip.add(_thighFront);
      _hip.add(_thighBack);
      _thighFront.add(_feetFront);
      _thighBack.add(_feetBack);
    }

    final heightX = tables.runtimeValueMaps.resolve(
      field: 'heightx',
      fieldValue: state.numeric('heightx'),
      op: 'scaleX',
      targetContains: 'char.char',
      fallback: 1,
    );
    final heightY = tables.runtimeValueMaps.resolve(
      field: 'heighty',
      fieldValue: state.numeric('heighty'),
      op: 'scaleY',
      targetContains: 'char.char',
      fallback: 1,
    );
    final pose = state.numeric('pose');
    final poseTorso =
        tables.posePlacementFor(pose: pose, hostName: 'body')?.matrix ??
        const AffineMatrix.identity();
    final poseHead =
        tables.posePlacementFor(pose: pose, hostName: 'head')?.matrix ??
        const AffineMatrix.identity();
    final poseShoulderFront =
        tables
            .posePlacementFor(pose: pose, hostName: 'shoulder_front')
            ?.matrix ??
        const AffineMatrix.identity();
    final poseShoulderBack =
        tables
            .posePlacementFor(pose: pose, hostName: 'shoulder_back')
            ?.matrix ??
        const AffineMatrix.identity();
    final poseForearmFront =
        tables.posePlacementFor(pose: pose, hostName: 'sleeve_front')?.matrix ??
        const AffineMatrix.identity();
    final poseForearmBack =
        tables.posePlacementFor(pose: pose, hostName: 'sleeve_back')?.matrix ??
        const AffineMatrix.identity();
    final poseThighFront =
        tables.posePlacementFor(pose: pose, hostName: 'thigh_front')?.matrix ??
        const AffineMatrix.identity();
    final poseThighBack =
        tables.posePlacementFor(pose: pose, hostName: 'thigh_back')?.matrix ??
        const AffineMatrix.identity();
    final poseFeetFront =
        tables.posePlacementFor(pose: pose, hostName: 'foot_front')?.matrix ??
        const AffineMatrix.identity();
    final poseFeetBack =
        tables.posePlacementFor(pose: pose, hostName: 'foot_back')?.matrix ??
        const AffineMatrix.identity();

    final rootScale = AffineMatrix.scale(heightX, heightY);
    final rootMatrix = _viewportTransform(scene).multiply(rootScale);
    final headLocal = poseTorso.inverse().multiply(poseHead);
    final shoulderFrontLocal = poseTorso.inverse().multiply(poseShoulderFront);
    final shoulderBackLocal = poseTorso.inverse().multiply(poseShoulderBack);
    final forearmFrontLocal = poseShoulderFront.inverse().multiply(
      poseForearmFront,
    );
    final forearmBackLocal = poseShoulderBack.inverse().multiply(
      poseForearmBack,
    );
    final thighFrontLocal = poseTorso.inverse().multiply(poseThighFront);
    final thighBackLocal = poseTorso.inverse().multiply(poseThighBack);
    final feetFrontLocal = poseThighFront.inverse().multiply(poseFeetFront);
    final feetBackLocal = poseThighBack.inverse().multiply(poseFeetBack);

    _applyLocalTransform(_rootComponent!, rootMatrix);
    _applyLocalTransform(_torso, poseTorso);
    _applyLocalTransform(_head, headLocal);
    _applyLocalTransform(_shoulderFront, shoulderFrontLocal);
    _applyLocalTransform(_shoulderBack, shoulderBackLocal);
    _applyLocalTransform(_forearmFront, forearmFrontLocal);
    _applyLocalTransform(_forearmBack, forearmBackLocal);
    _applyLocalTransform(_hip, const AffineMatrix.identity());
    _applyLocalTransform(_thighFront, thighFrontLocal);
    _applyLocalTransform(_thighBack, thighBackLocal);
    _applyLocalTransform(_feetFront, feetFrontLocal);
    _applyLocalTransform(_feetBack, feetBackLocal);

    final jointWorld = <String, AffineMatrix>{
      'torso': poseTorso,
      'head': poseTorso.multiply(headLocal),
      'shoulder_front': poseTorso.multiply(shoulderFrontLocal),
      'shoulder_back': poseTorso.multiply(shoulderBackLocal),
      'forearm_front': poseTorso
          .multiply(shoulderFrontLocal)
          .multiply(forearmFrontLocal),
      'forearm_back': poseTorso
          .multiply(shoulderBackLocal)
          .multiply(forearmBackLocal),
      'hip': poseTorso,
      'thigh_front': poseTorso.multiply(thighFrontLocal),
      'thigh_back': poseTorso.multiply(thighBackLocal),
      'feet_front': poseTorso
          .multiply(thighFrontLocal)
          .multiply(feetFrontLocal),
      'feet_back': poseTorso.multiply(thighBackLocal).multiply(feetBackLocal),
    };

    final newKeys = <String>{};
    for (final part in scene.parts) {
      final key = _partKey(part);
      newKeys.add(key);

      final asset = scene.assets[part.catalogPart.appAssetPath];
      final parentMatrix = jointWorld[part.targetJoint] ?? jointWorld['torso']!;
      final localMatrix = part.sceneTransform
          .multiply(parentMatrix)
          .multiply(part.localTransform);

      if (_componentsByKey.containsKey(key)) {
        final comp = _componentsByKey[key]!;
        comp.updatePart(part, asset, localMatrix);

        if (comp.parent != _rootComponent) {
          comp.removeFromParent();
          _rootComponent!.add(comp);
        }
      } else {
        final comp = GachaPartComponent(
          part: part,
          asset: asset,
          tintColor: part.tintColor,
          globalDepth: part.globalDepth,
          localMatrix: localMatrix,
        );
        _rootComponent!.add(comp);
        _componentsByKey[key] = comp;
      }
    }

    final keysToRemove = _componentsByKey.keys
        .where((key) => !newKeys.contains(key))
        .toList();
    for (final key in keysToRemove) {
      final comp = _componentsByKey.remove(key)!;
      comp.removeFromParent();
    }
  }

  AffineMatrix _viewportTransform(ResolvedScene scene) {
    final bounds = scene.worldBounds;
    if (size.x <= 0 || size.y <= 0 || bounds.isEmpty) {
      return const AffineMatrix.identity();
    }
    const padding = 32.0;
    final availableWidth = (size.x - padding * 2).clamp(1.0, double.infinity);
    final availableHeight = (size.y - padding * 2).clamp(1.0, double.infinity);
    final fitScale = math.max(
      0.01,
      math.min(availableWidth / bounds.width, availableHeight / bounds.height),
    );
    final cameraX =
        (size.x - bounds.width * fitScale) * 0.5 - bounds.left * fitScale;
    final cameraY =
        (size.y - bounds.height * fitScale) * 0.5 - bounds.top * fitScale;
    return AffineMatrix.translation(
      cameraX,
      cameraY,
    ).multiply(AffineMatrix.scale(fitScale, fitScale));
  }

  void _applyLocalTransform(
    GachaJointComponent component,
    AffineMatrix matrix,
  ) {
    component.localMatrix = matrix;
  }

  String _partKey(ResolvedRenderPart part) {
    return '${part.catalogPart.family}|${part.catalogPart.partRole}|${part.catalogPart.leafId}';
  }

  @override
  Color backgroundColor() => const Color(0x00000000);
}
