import 'package:flutter/material.dart';

import '../../gacha/render/render_part.dart';

class ProductionScenePreview extends StatelessWidget {
  const ProductionScenePreview({
    super.key,
    required this.scene,
    required this.canvasSize,
    required this.backgroundColor,
  });

  final ResolvedScene scene;
  final Size canvasSize;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ResolvedScenePainter(
        scene: scene,
        canvasSize: canvasSize,
        backgroundColor: backgroundColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ResolvedScenePainter extends CustomPainter {
  const _ResolvedScenePainter({
    required this.scene,
    required this.canvasSize,
    required this.backgroundColor,
  });

  final ResolvedScene scene;
  final Size canvasSize;
  final Color? backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (canvasSize.isEmpty || size.isEmpty) {
      return;
    }
    final scale = (size.width / canvasSize.width).clamp(
      0.0,
      size.height / canvasSize.height,
    );
    final offset = Offset(
      (size.width - canvasSize.width * scale) * 0.5,
      (size.height - canvasSize.height * scale) * 0.5,
    );
    canvas.save();
    canvas.clipRect(
      offset & Size(canvasSize.width * scale, canvasSize.height * scale),
    );
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    if (backgroundColor != null) {
      canvas.drawRect(
        Offset.zero & canvasSize,
        Paint()..color = backgroundColor!,
      );
    }
    for (final part in scene.parts) {
      final asset = scene.assets[part.catalogPart.appAssetPath];
      if (asset == null) {
        continue;
      }
      canvas.save();
      canvas.transform(part.localTransform.toFloat64List());
      asset.paint(canvas, part.tintColor);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ResolvedScenePainter oldDelegate) {
    return !identical(scene, oldDelegate.scene) ||
        canvasSize != oldDelegate.canvasSize ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
