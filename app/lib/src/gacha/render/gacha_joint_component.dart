import 'dart:io';
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
  });

  final String name;
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
      worldTransform: const AffineMatrix.identity(),
      tintColor: null,
      globalDepth: 999999,
    );

    _swappedPart = GachaPartComponent(
      part: newPart,
      asset: customAsset,
      tintColor: null,
      globalDepth: 999999,
    );

    add(_swappedPart!);
  }
}

class GachaPartComponent extends PositionComponent {
  GachaPartComponent({
    required this.part,
    required this.asset,
    required this.tintColor,
    required int globalDepth,
  }) : super(priority: globalDepth);

  final ResolvedRenderPart part;
  final PreparedAsset? asset;
  final Color? tintColor;

  ui.Image? _cachedGpuImage;
  bool _loadingCache = false;

  @override
  void render(Canvas canvas) {
    if (asset == null) return;
    canvas.save();
    
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
