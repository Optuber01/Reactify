import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart' as vg;
import 'character_renderer.dart';
import 'render_part.dart';
import 'gacha_vector_cache.dart';
import 'transform_graph.dart';
import '../data/resolver_tables.dart';

class GachaJointComponent extends PositionComponent {
  GachaJointComponent({
    required this.name,
  }) {
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
  double tweenAngle = 0.0;

  final Float64List _cachedTransformList = Float64List(16);
  AffineMatrix? _lastLocalMatrix;
  double? _lastTweenAngle;

  @override
  void renderTree(Canvas canvas) {
    if (isMounted) {
      canvas.save();
      
      if (_lastLocalMatrix != localMatrix || _lastTweenAngle != tweenAngle) {
        _lastLocalMatrix = localMatrix;
        _lastTweenAngle = tweenAngle;
        
        final radians = tweenAngle * 3.141592653589793 / 180;
        final cosVal = math.cos(radians);
        final sinVal = math.sin(radians);
        
        final la = localMatrix.a;
        final lb = localMatrix.b;
        final lc = localMatrix.c;
        final ld = localMatrix.d;
        
        _cachedTransformList[0] = la * cosVal + lc * sinVal;
        _cachedTransformList[1] = lb * cosVal + ld * sinVal;
        _cachedTransformList[4] = -la * sinVal + lc * cosVal;
        _cachedTransformList[5] = -lb * sinVal + ld * cosVal;
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

  GachaPartComponent? _swappedPart;

  void swapCustomAsset(String filePath, String assetKind) async {
    if (_swappedPart != null) {
      remove(_swappedPart!);
      _swappedPart = null;
    }

    PreparedAsset customAsset;
    final file = File(filePath);
    if (assetKind == 'svg' || filePath.toLowerCase().endsWith('.svg')) {
      final pictureInfo = await vg.vg.loadPicture(
        vg.SvgFileLoader(file),
        null,
      );
      customAsset = SvgPreparedAsset(assetPath: filePath, pictureInfo: pictureInfo);
    } else {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      customAsset = RasterPreparedAsset(assetPath: filePath, image: frame.image);
    }

    final newPart = ResolvedRenderPart(
      catalogPart: RenderCatalogPart(
        family: 'custom_swap',
        chooserFrame: 1,
        partRole: 'accessory',
        orderedPartIndex: 9999,
        leafId: 'custom',
        originalAssetPath: filePath,
        appAssetPath: filePath,
        assetKind: assetKind,
        tintChannel: 'none',
        visibilityRule: '',
        namePath: 'custom',
        characterPath: 'custom',
        depthPath: '9999',
        framePath: '1',
        hostScope: 'pose',
        hostName: name,
        hostChildName: '',
        hostDepthPath: '',
        runtimeAnchorX: 0.0,
        runtimeAnchorY: 0.0,
        dependencyField: '',
        dependencyValue: null,
        sizeTable: 'eye_standard',
        rootSpriteId: 'custom',
        localMatrix: const AffineMatrix.identity(),
        notes: '',
      ),
      localTransform: const AffineMatrix.identity(),
      targetJoint: name,
      tintColor: null,
      globalDepth: 999999,
    );

    _swappedPart = GachaPartComponent(
      part: newPart,
      asset: customAsset,
      tintColor: null,
      globalDepth: 999999,
      localMatrix: const AffineMatrix.identity(),
    );

    add(_swappedPart!);
  }

  // Convert global canvas drawing coordinates to local rigged joint coordinates
  void addDrawingStroke(List<Offset> stroke) {
    if (stroke.length < 2) return;
    
    final localPoints = stroke.map((p) {
      final localVec = absoluteToLocal(Vector2(p.dx, p.dy));
      return Offset(localVec.x, localVec.y);
    }).toList();

    final existing = children.whereType<GachaDrawingPartComponent>().firstOrNull;
    if (existing != null) {
      existing.strokes.add(localPoints);
    } else {
      final drawingComp = GachaDrawingPartComponent(strokes: [localPoints]);
      add(drawingComp);
    }
  }
}

class GachaDrawingPartComponent extends PositionComponent {
  GachaDrawingPartComponent({
    required this.strokes,
  }) : super(priority: 9999999);

  final List<List<Offset>> strokes;

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF64B5F6)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
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
  bool _loadingCache = false;

  void updatePart(ResolvedRenderPart newPart, PreparedAsset? newAsset, AffineMatrix newLocalMatrix) {
    if (part.catalogPart.appAssetPath != newPart.catalogPart.appAssetPath ||
        tintColor != newPart.tintColor) {
      _cachedGpuImage = null;
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
  }

  @override
  void render(Canvas canvas) {
    if (asset == null) return;
    canvas.save();

    canvas.transform(_cachedLocalMatrixList);
    
    final anchorX = part.catalogPart.runtimeAnchorX;
    final anchorY = part.catalogPart.runtimeAnchorY;
    canvas.translate(anchorX, anchorY);

    if (_cachedGpuImage != null) {
      final paint = Paint();
      final src = Rect.fromLTWH(0, 0, _cachedGpuImage!.width.toDouble(), _cachedGpuImage!.height.toDouble());
      final dst = Rect.fromLTWH(0, 0, asset!.size.width, asset!.size.height);
      canvas.drawImageRect(_cachedGpuImage!, src, dst, paint);
    } else {
      asset!.paint(canvas, tintColor);
      if (!_loadingCache) {
        _loadingCache = true;
        GachaVectorCache.instance.getRasterized(asset!, tintColor).then((image) {
          _cachedGpuImage = image;
        });
      }
    }
    
    canvas.restore();
  }
}
