import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'render_part.dart';
import 'gacha_vector_cache.dart';
import 'transform_graph.dart';

class GachaJointComponent extends PositionComponent {
  GachaJointComponent({required this.name}) {
    _cachedTransformList[2] = 0.0;
    _cachedTransformList[3] = 0.0;
    _cachedTransformList[6] = 0.0;
    _cachedTransformList[7] = 0.0;
    _cachedTransformList[8] = 0.0;
    _cachedTransformList[9] = 0.0;
    _cachedTransformList[10] = 1.0;
    _cachedTransformList[11] = 0.0;
    _cachedTransformList[14] = 0.0;
    _cachedTransformList[15] = 1.0;
  }

  final String name;
  AffineMatrix localMatrix = const AffineMatrix.identity();

  final Float64List _cachedTransformList = Float64List(16);
  AffineMatrix? _lastLocalMatrix;

  @override
  void renderTree(Canvas canvas) {
    if (isMounted) {
      canvas.save();

      if (_lastLocalMatrix != localMatrix) {
        _lastLocalMatrix = localMatrix;

        _cachedTransformList[0] = localMatrix.a;
        _cachedTransformList[1] = localMatrix.b;
        _cachedTransformList[4] = localMatrix.c;
        _cachedTransformList[5] = localMatrix.d;
        _cachedTransformList[12] = localMatrix.tx;
        _cachedTransformList[13] = localMatrix.ty;
      }

      canvas.transform(_cachedTransformList);

      render(canvas);
      for (final child in children) {
        child.renderTree(canvas);
      }

      canvas.restore();
    }
  }

  void addDrawingStroke(List<Offset> stroke) {
    if (stroke.length < 2) return;

    final localPoints = stroke.map((p) {
      final localVec = absoluteToLocal(Vector2(p.dx, p.dy));
      return Offset(localVec.x, localVec.y);
    }).toList();

    final existing = children
        .whereType<GachaDrawingPartComponent>()
        .firstOrNull;
    if (existing != null) {
      existing.addStroke(localPoints);
    } else {
      final drawingComp = GachaDrawingPartComponent(initialStroke: localPoints);
      add(drawingComp);
    }
  }
}

class GachaDrawingPartComponent extends PositionComponent {
  GachaDrawingPartComponent({required List<Offset> initialStroke})
    : super(priority: 9999999) {
    addStroke(initialStroke);
  }

  final Path _cachedPath = Path();
  final Paint _paint = Paint()
    ..color = const Color(0xFF00F5FF)
    ..strokeWidth = 3.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  void addStroke(List<Offset> stroke) {
    if (stroke.length < 2) return;
    _cachedPath.moveTo(stroke.first.dx, stroke.first.dy);
    for (var i = 1; i < stroke.length; i++) {
      _cachedPath.lineTo(stroke[i].dx, stroke[i].dy);
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPath(_cachedPath, _paint);
  }
}

class GachaPartComponent extends PositionComponent {
  GachaPartComponent({
    required this.part,
    required this.asset,
    required this.tintColor,
    required int globalDepth,
    required this.localMatrix,
  }) : super(priority: globalDepth) {
    _cachedLocalMatrixList[2] = 0.0;
    _cachedLocalMatrixList[3] = 0.0;
    _cachedLocalMatrixList[6] = 0.0;
    _cachedLocalMatrixList[7] = 0.0;
    _cachedLocalMatrixList[8] = 0.0;
    _cachedLocalMatrixList[9] = 0.0;
    _cachedLocalMatrixList[10] = 1.0;
    _cachedLocalMatrixList[11] = 0.0;
    _cachedLocalMatrixList[14] = 0.0;
    _cachedLocalMatrixList[15] = 1.0;
    _updateCachedList();
    _scheduleRasterCache();
  }

  ResolvedRenderPart part;
  PreparedAsset? asset;
  Color? tintColor;
  AffineMatrix localMatrix;

  final Float64List _cachedLocalMatrixList = Float64List(16);

  void _updateCachedList() {
    _cachedLocalMatrixList[0] = localMatrix.a;
    _cachedLocalMatrixList[1] = localMatrix.b;
    _cachedLocalMatrixList[4] = localMatrix.c;
    _cachedLocalMatrixList[5] = localMatrix.d;
    _cachedLocalMatrixList[12] = localMatrix.tx;
    _cachedLocalMatrixList[13] = localMatrix.ty;
  }

  ui.Image? _cachedGpuImage;
  Rect? _cachedGpuSourceRect;
  Rect? _cachedGpuDestinationRect;
  bool _loadingCache = false;
  int _cacheSerial = 0;
  final Paint _paint = Paint();

  void updatePart(
    ResolvedRenderPart newPart,
    PreparedAsset? newAsset,
    AffineMatrix newLocalMatrix,
  ) {
    if (part.catalogPart.appAssetPath != newPart.catalogPart.appAssetPath ||
        tintColor != newPart.tintColor) {
      _cachedGpuImage = null;
      _cachedGpuSourceRect = null;
      _cachedGpuDestinationRect = null;
      _loadingCache = false;
    }

    part = newPart;
    asset = newAsset;

    if (localMatrix != newLocalMatrix) {
      localMatrix = newLocalMatrix;
      _updateCachedList();
    }

    tintColor = newPart.tintColor;
    priority = newPart.globalDepth;
    _scheduleRasterCache();
  }

  void _scheduleRasterCache() {
    final currentAsset = asset;
    if (currentAsset == null || _cachedGpuImage != null || _loadingCache) {
      return;
    }
    _loadingCache = true;
    final serial = ++_cacheSerial;
    GachaVectorCache.instance.getRasterized(currentAsset, tintColor).then((
      image,
    ) {
      if (serial != _cacheSerial || asset != currentAsset) {
        return;
      }
      _cachedGpuImage = image;
      _cachedGpuSourceRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      _cachedGpuDestinationRect = Rect.fromLTWH(
        0,
        0,
        currentAsset.size.width,
        currentAsset.size.height,
      );
      _loadingCache = false;
    });
  }

  @override
  void render(Canvas canvas) {
    if (asset == null) return;
    canvas.save();

    canvas.transform(_cachedLocalMatrixList);

    if (_cachedGpuImage != null) {
      canvas.drawImageRect(
        _cachedGpuImage!,
        _cachedGpuSourceRect!,
        _cachedGpuDestinationRect!,
        _paint,
      );
    } else {
      asset!.paint(canvas, tintColor);
    }

    canvas.restore();
  }
}
