import 'package:reactify_gacha/src/gacha/render/render_part.dart';
import 'package:reactify_gacha/src/gacha/render/transform_graph.dart';
import 'package:reactify_gacha/src/gacha/code/gacha_character_state.dart';
import 'package:reactify_gacha/src/gacha/data/resolver_tables.dart';

AffineMatrix resolveTestWorldTransform(ResolvedRenderPart part, GachaCharacterState state, ResolverTables tables) {
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

    final torsoWorld = rootLocal.multiply(torsoLocalBase);
    final headWorld = torsoWorld.multiply(headLocalBase);
    final shoulderFrontWorld = torsoWorld.multiply(shoulderFrontLocalBase);
    final shoulderBackWorld = torsoWorld.multiply(shoulderBackLocalBase);
    final forearmFrontWorld = shoulderFrontWorld.multiply(forearmFrontLocalBase);
    final forearmBackWorld = shoulderBackWorld.multiply(forearmBackLocalBase);
    final hipWorld = torsoWorld.multiply(hipLocalBase);
    final thighFrontWorld = hipWorld.multiply(thighFrontLocalBase);
    final thighBackWorld = hipWorld.multiply(thighBackLocalBase);
    final feetFrontWorld = thighFrontWorld.multiply(feetFrontLocalBase);
    final feetBackWorld = thighBackWorld.multiply(feetBackLocalBase);

    AffineMatrix parentWorld;
    switch (part.targetJoint) {
      case 'head': parentWorld = headWorld; break;
      case 'shoulder_front': parentWorld = shoulderFrontWorld; break;
      case 'shoulder_back': parentWorld = shoulderBackWorld; break;
      case 'forearm_front': parentWorld = forearmFrontWorld; break;
      case 'forearm_back': parentWorld = forearmBackWorld; break;
      case 'hip': parentWorld = hipWorld; break;
      case 'thigh_front': parentWorld = thighFrontWorld; break;
      case 'thigh_back': parentWorld = thighBackWorld; break;
      case 'feet_front': parentWorld = feetFrontWorld; break;
      case 'feet_back': parentWorld = feetBackWorld; break;
      default: parentWorld = torsoWorld; break;
    }
    return parentWorld.multiply(part.localTransform);
}
