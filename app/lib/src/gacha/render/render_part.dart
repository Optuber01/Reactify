import 'dart:ui';

import '../data/resolver_tables.dart';
import 'transform_graph.dart';

class ResolvedRenderPart {
  const ResolvedRenderPart({
    required this.catalogPart,
    required this.localTransform,
    required this.targetJoint,
    required this.tintColor,
    required this.globalDepth,
    this.tintStrength = 1,
    this.opacity = 1,
    this.sceneTransform = const AffineMatrix.identity(),
  });

  final RenderCatalogPart catalogPart;
  final AffineMatrix localTransform;
  final String targetJoint;
  final Color? tintColor;
  final double tintStrength;
  final double opacity;
  final int globalDepth;
  final AffineMatrix sceneTransform;

  Map<String, Object?> toDebugJson() {
    return {
      'family': catalogPart.family,
      'chooserFrame': catalogPart.chooserFrame,
      'partRole': catalogPart.partRole,
      'asset': catalogPart.appAssetPath,
      'tintChannel': catalogPart.tintChannel,
      'visibilityRule': catalogPart.visibilityRule,
      'hostScope': catalogPart.hostScope,
      'hostName': catalogPart.hostName,
      'runtimeAnchor': {
        'x': catalogPart.runtimeAnchorX,
        'y': catalogPart.runtimeAnchorY,
      },
      'localTransform': localTransform.toDebugJson(),
      'sceneTransform': sceneTransform.toDebugJson(),
      'targetJoint': targetJoint,
      'depth': globalDepth,
      'tintStrength': tintStrength,
      'opacity': opacity,
    };
  }
}

class ResolvedScene {
  const ResolvedScene({
    required this.parts,
    required this.assets,
    required this.worldBounds,
    required this.warnings,
    this.canvasBounds,
  });

  final List<ResolvedRenderPart> parts;
  final Map<String, PreparedAsset> assets;
  final Rect worldBounds;
  final List<String> warnings;
  final Rect? canvasBounds;
}

abstract class PreparedAsset {
  const PreparedAsset({required this.assetPath, required this.size});

  final String assetPath;
  final Size size;

  void paint(
    Canvas canvas,
    Color? tintColor, {
    double tintStrength = 1,
    double opacity = 1,
  });
}
