import 'package:flame/game.dart';
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
  GachaJointComponent? _rootComponent;

  // Cache components by a unique family role key to keep them persistent
  final Map<String, GachaPartComponent> _componentsByKey = {};

  // Store logical joints
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

  set scene(ResolvedScene? newScene) {
    if (_scene == newScene) return;
    _scene = newScene;
  }

  // Update scene in-place (persistent tree updates)
  void updateScene(ResolvedScene scene, GachaCharacterState state, ResolverTables tables) {
    _scene = scene;

    if (_rootComponent == null) {
      final root = GachaJointComponent(name: 'root');
      _rootComponent = root;
      add(root);

      // Rig physical Gacha skeleton hierarchy
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

    // 1. Calculate base joint matrices relative to parents
    final heightX = tables.runtimeValueMaps.resolve(field: 'heightx', fieldValue: state.numeric('heightx'), op: 'scaleX', targetContains: 'char.char', fallback: 1);
    final heightY = tables.runtimeValueMaps.resolve(field: 'heighty', fieldValue: state.numeric('heighty'), op: 'scaleY', targetContains: 'char.char', fallback: 1);
    
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

    // 2. Set native position, scale, and rotations on logical joints
    _applyLocalTransform(_rootComponent!, AffineMatrix.scale(heightX, heightY));
    _applyLocalTransform(_torso, poseTorso);
    
    _applyLocalTransform(_head, poseTorso.inverse().multiply(poseHead), tweenKey: 'head');

    // Shoulders relative to Torso
    _applyLocalTransform(_shoulderFront, poseTorso.inverse().multiply(poseShoulderFront), tweenKey: 'shoulder_front');
    _applyLocalTransform(_shoulderBack, poseTorso.inverse().multiply(poseShoulderBack), tweenKey: 'shoulder_back');

    // Forearms relative to Shoulders
    _applyLocalTransform(_forearmFront, poseShoulderFront.inverse().multiply(poseForearmFront), tweenKey: 'forearm_front');
    _applyLocalTransform(_forearmBack, poseShoulderBack.inverse().multiply(poseForearmBack), tweenKey: 'forearm_back');

    // Hip relative to Torso
    _applyLocalTransform(_hip, const AffineMatrix.identity());

    // Thighs relative to Hip
    _applyLocalTransform(_thighFront, poseTorso.inverse().multiply(poseThighFront), tweenKey: 'thigh_front');
    _applyLocalTransform(_thighBack, poseTorso.inverse().multiply(poseThighBack), tweenKey: 'thigh_back');

    // Feet relative to Thighs
    _applyLocalTransform(_feetFront, poseThighFront.inverse().multiply(poseFeetFront), tweenKey: 'foot_front');
    _applyLocalTransform(_feetBack, poseThighBack.inverse().multiply(poseFeetBack), tweenKey: 'foot_back');

    // 3. Track and update part components dynamically
    final newKeys = <String>{};
    for (final part in scene.parts) {
      final key = _partKey(part);
      newKeys.add(key);

      final targetJoint = _getJointByName(part.targetJoint);
      final asset = scene.assets[part.catalogPart.appAssetPath];

      if (_componentsByKey.containsKey(key)) {
        final comp = _componentsByKey[key]!;
        comp.updatePart(part, asset, part.localTransform);
        
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
          localMatrix: part.localTransform,
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

  GachaJointComponent _getJointByName(String name) {
    switch (name) {
      case 'head': return _head;
      case 'shoulder_front': return _shoulderFront;
      case 'shoulder_back': return _shoulderBack;
      case 'forearm_front': return _forearmFront;
      case 'forearm_back': return _forearmBack;
      case 'hip': return _hip;
      case 'thigh_front': return _thighFront;
      case 'thigh_back': return _thighBack;
      case 'feet_front': return _feetFront;
      case 'feet_back': return _feetBack;
      default: return _torso;
    }
  }

  // Animation tween offsets
  final Map<String, double> jointRotationTweens = {};

  // Set local matrix and tween angle directly on the GachaJointComponent
  void _applyLocalTransform(GachaJointComponent component, AffineMatrix matrix, {String? tweenKey}) {
    component.localMatrix = matrix;
    component.tweenAngle = (tweenKey != null && jointRotationTweens.containsKey(tweenKey)) 
        ? jointRotationTweens[tweenKey]! 
        : 0.0;
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
  Color backgroundColor() => const Color(0x00000000);
}
