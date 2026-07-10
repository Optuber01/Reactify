import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'gacha_joint_component.dart';
import 'gacha_pose_graph.dart';
import 'render_part.dart';
import 'transform_graph.dart';
import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';

class GachaGameCanvas extends FlameGame {
  GachaGameCanvas();

  ResolvedScene? _scene;
  GachaCharacterState? _state;
  ResolverTables? _tables;
  GachaJointComponent? _rootComponent;
  bool _jointRigInitialized = false;

  final Map<String, GachaPartComponent> _componentsByKey = {};
  final Map<String, GachaJointComponent> _jointsByAnchor = {};

  ResolvedScene? get scene => _scene;
  int get activePartComponentCount => _componentsByKey.length;
  AffineMatrix? get rootTransform => _rootComponent?.localMatrix;
  AffineMatrix? partTransformForDebug(ResolvedRenderPart part) {
    return _componentsByKey[_partKey(part)]?.localMatrix;
  }

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
    } else if (scene != null) {
      updateFlatScene(scene);
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

    _ensureRootComponent();
    if (!_jointRigInitialized) {
      for (final anchor in GachaPoseGraph.anchors) {
        final component = GachaJointComponent(name: anchor.id);
        _jointsByAnchor[anchor.id] = component;
        final parentId = anchor.parentId;
        if (parentId == null) {
          _rootComponent!.add(component);
        } else {
          _jointsByAnchor[parentId]!.add(component);
        }
      }
      _jointRigInitialized = true;
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
    final jointLocal = GachaPoseGraph.localTransforms(tables, pose);
    final jointWorld = GachaPoseGraph.worldTransforms(tables, pose);
    final rootScale = AffineMatrix.scale(heightX, heightY);
    final rootMatrix = _viewportTransform(scene).multiply(rootScale);
    _applyLocalTransform(_rootComponent!, rootMatrix);
    for (final entry in jointLocal.entries) {
      _applyLocalTransform(_jointsByAnchor[entry.key]!, entry.value);
    }

    final newKeys = <String>{};
    for (final part in scene.parts) {
      final key = _partKey(part);
      newKeys.add(key);

      final asset = scene.assets[part.catalogPart.appAssetPath];
      final parentMatrix = jointWorld[part.targetJoint];
      if (parentMatrix == null) {
        throw StateError(
          'Missing logical pose anchor ${part.targetJoint} for ${part.catalogPart.family}.',
        );
      }
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

  void updateFlatScene(ResolvedScene scene) {
    _scene = scene;
    _state = null;
    _tables = null;

    _ensureRootComponent();

    _applyLocalTransform(_rootComponent!, _viewportTransform(scene));

    final newKeys = <String>{};
    for (final part in scene.parts) {
      final key = _partKey(part);
      newKeys.add(key);

      final asset = scene.assets[part.catalogPart.appAssetPath];
      if (_componentsByKey.containsKey(key)) {
        final comp = _componentsByKey[key]!;
        comp.updatePart(part, asset, part.localTransform);

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
          localMatrix: part.localTransform,
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

  void _ensureRootComponent() {
    if (_rootComponent != null) {
      return;
    }
    final root = GachaJointComponent(name: 'root');
    _rootComponent = root;
    add(root);
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
