import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart' as vg;

import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';
import 'body_renderer.dart';
import 'head_renderer.dart';
import 'render_part.dart';
import 'tint_pipeline.dart';
import 'transform_graph.dart';

class CharacterRenderer {
  CharacterRenderer({
    required this.tables,
    required this.assetStore,
    this.headRenderer = const HeadRenderer(),
    this.bodyRenderer = const BodyRenderer(),
  });

  final ResolverTables tables;
  final GachaAssetStore assetStore;
  final HeadRenderer headRenderer;
  final BodyRenderer bodyRenderer;

  Future<ResolvedScene> buildScene(GachaCharacterState state) async {
    final resolvedParts = resolveParts(state);
    final assets = await assetStore.loadAll(
      resolvedParts.map((part) => part.catalogPart.appAssetPath).toSet(),
    );
    Rect? bounds;
    for (final part in resolvedParts) {
      final asset = assets[part.catalogPart.appAssetPath];
      if (asset == null) {
        continue;
      }
      final rect = part.worldTransform.transformRect(
        Rect.fromLTWH(0, 0, asset.size.width, asset.size.height),
      );
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    return ResolvedScene(
      parts: resolvedParts,
      assets: assets,
      worldBounds: bounds ?? Rect.zero,
      warnings: _warningsFor(state, resolvedParts),
    );
  }

  List<ResolvedRenderPart> resolveParts(GachaCharacterState state) {
    final catalogParts = [
      ...headRenderer.resolve(state, tables),
      ...bodyRenderer.resolve(state, tables),
    ];
    final resolved = <ResolvedRenderPart>[];
    for (final part in catalogParts) {
      if (!part.matchesStateValue((field) => state.numeric(field))) {
        continue;
      }
      final matrix = _worldTransformFor(part, state);
      resolved.add(
        ResolvedRenderPart(
          catalogPart: part,
          worldTransform: matrix,
          tintColor: TintPipeline.resolveTint(state, part.tintChannel),
          globalDepth: _globalDepthFor(part, state),
        ),
      );
    }
    resolved.sort(
      (left, right) => left.globalDepth.compareTo(right.globalDepth),
    );
    return resolved;
  }

  AffineMatrix _worldTransformFor(
    RenderCatalogPart part,
    GachaCharacterState state,
  ) {
    final rootMatrix = _rootCharacterAdjustment(state);
    final posePlacement = tables.posePlacementFor(
      pose: state.numeric('pose'),
      hostName: part.hostScope == 'head' ? 'head' : part.hostName,
    );
    final headPlacement = part.hostScope == 'head'
        ? tables.headPlacements[part.hostName]
        : null;
    final poseMatrix = posePlacement?.matrix ?? const AffineMatrix.identity();
    final groupMatrix = _groupAdjustmentFor(part, state);
    final hostMatrix = headPlacement?.matrix ?? const AffineMatrix.identity();
    final anchorMatrix = part.hostScope == 'pose'
        ? AffineMatrix.translation(part.runtimeAnchorX, part.runtimeAnchorY)
        : const AffineMatrix.identity();
    final slotMatrix = _slotAdjustment(part, state);
    return rootMatrix
        .multiply(poseMatrix)
        .multiply(groupMatrix)
        .multiply(hostMatrix)
        .multiply(anchorMatrix)
        .multiply(slotMatrix)
        .multiply(part.localMatrix);
  }

  int _globalDepthFor(RenderCatalogPart part, GachaCharacterState state) {
    final poseDepth =
        tables
            .posePlacementFor(
              pose: state.numeric('pose'),
              hostName: part.hostScope == 'head' ? 'head' : part.hostName,
            )
            ?.depth ??
        0;
    if (part.hostScope == 'head') {
      final headDepth = tables.headPlacements[part.hostName]?.depth ?? 0;
      return poseDepth * 1000000000 + headDepth * 10000 + part.orderedPartIndex;
    }
    return poseDepth * 1000000000 +
        _depthPathOrder(_combinedPoseDepthPath(part)) * 10 +
        part.orderedPartIndex;
  }

  String _combinedPoseDepthPath(RenderCatalogPart part) {
    final prefix = part.hostDepthPath.trim();
    final suffix = part.depthPath.trim();
    if (prefix.isEmpty) {
      return suffix;
    }
    if (suffix.isEmpty) {
      return prefix;
    }
    return '$prefix/$suffix';
  }

  int _depthPathOrder(String depthPath) {
    if (depthPath.trim().isEmpty) {
      return 0;
    }
    final segments = depthPath
        .split('/')
        .map((segment) => int.tryParse(segment) ?? 0)
        .toList(growable: false);
    var order = 0;
    for (final depth in segments) {
      order = order * 1000 + depth;
    }
    return order;
  }

  AffineMatrix _rootCharacterAdjustment(GachaCharacterState state) {
    final scaleX = tables.runtimeValueMaps.resolve(
      field: 'heightx',
      fieldValue: state.numeric('heightx'),
      op: 'scaleX',
      targetContains: 'char.char',
      fallback: 1,
    );
    final scaleY = tables.runtimeValueMaps.resolve(
      field: 'heighty',
      fieldValue: state.numeric('heighty'),
      op: 'scaleY',
      targetContains: 'char.char',
      fallback: 1,
    );
    return AffineMatrix.scale(scaleX, scaleY);
  }

  AffineMatrix _groupAdjustmentFor(
    RenderCatalogPart part,
    GachaCharacterState state,
  ) {
    if (part.hostScope == 'head') {
      return _headGroupAdjustment(state);
    }
    if (part.hostName == 'backhair') {
      return _backHairGroupAdjustment(state);
    }
    return const AffineMatrix.identity();
  }

  AffineMatrix _headGroupAdjustment(GachaCharacterState state) {
    final headFlipMatrix =
        tables
            .headFlipPlacementFor(
              headflip: state.numeric('headflip'),
              name: 'head',
            )
            ?.matrix ??
        const AffineMatrix.identity();
    final scaleX = tables.runtimeValueMaps.resolve(
      field: 'headsize',
      fieldValue: state.numeric('headsize'),
      op: 'scaleX',
      targetContains: 'head.head',
      fallback: 1,
    );
    final scaleY = tables.runtimeValueMaps.resolve(
      field: 'headsizey',
      fieldValue: state.numeric('headsizey'),
      op: 'scaleY',
      targetContains: 'head.head',
      fallback: 1,
    );
    return headFlipMatrix.multiply(AffineMatrix.scale(scaleX, scaleY));
  }

  AffineMatrix _backHairGroupAdjustment(GachaCharacterState state) {
    final selectedHeadFlipMatrix =
        tables
            .headFlipPlacementFor(
              headflip: state.numeric('headflip'),
              name: 'backhair',
            )
            ?.matrix ??
        const AffineMatrix.identity();
    final baselineHeadFlipMatrix =
        tables.headFlipPlacementFor(headflip: 1, name: 'backhair')?.matrix ??
        const AffineMatrix.identity();
    final scaleX = tables.runtimeValueMaps.resolve(
      field: 'headsize',
      fieldValue: state.numeric('headsize'),
      op: 'scaleX',
      targetContains: 'backhair.backhair',
      fallback: 1,
    );
    final scaleY = tables.runtimeValueMaps.resolve(
      field: 'headsizey',
      fieldValue: state.numeric('headsizey'),
      op: 'scaleY',
      targetContains: 'backhair.backhair',
      fallback: 1,
    );
    return selectedHeadFlipMatrix
        .multiply(AffineMatrix.scale(scaleX, scaleY))
        .multiply(baselineHeadFlipMatrix.inverse());
  }

  AffineMatrix _slotAdjustment(
    RenderCatalogPart part,
    GachaCharacterState state,
  ) {
    if (part.family == 'body_logo') {
      return tables.logoPlacementFor(state.numeric('logopos'))?.matrix ??
          const AffineMatrix.identity();
    }
    final binding = _bindingFor(part);
    if (binding == null) {
      return const AffineMatrix.identity();
    }
    final x = _resolveSlotTransformValue(
      state: state,
      field: binding.xField,
      op: 'x',
      targetContains: binding.targetContains,
      fallback: 0,
      directFieldFallback: true,
    );
    final y = _resolveSlotTransformValue(
      state: state,
      field: binding.yField,
      op: 'y',
      targetContains: binding.targetContains,
      fallback: 0,
      directFieldFallback: true,
    );
    final scaleX = _resolveSlotTransformValue(
      state: state,
      field: binding.scaleXField,
      op: 'scaleX',
      targetContains: binding.targetContains,
      fallback: 1,
    );
    final scaleY = _resolveSlotTransformValue(
      state: state,
      field: binding.scaleYField,
      op: 'scaleY',
      targetContains: binding.targetContains,
      fallback: 1,
    );
    final double rotation = binding.appliesGeometricRotation
        ? _resolveSlotTransformValue(
            state: state,
            field: binding.rotationField,
            op: 'rotation',
            targetContains: binding.targetContains,
            fallback: 0,
            directFieldFallback: binding.rotationUsesDirectFieldFallback,
          )
        : 0;
    return AffineMatrix.translation(x, y)
        .multiply(AffineMatrix.rotationDegrees(rotation))
        .multiply(AffineMatrix.scale(scaleX, scaleY));
  }

  double _resolveSlotTransformValue({
    required GachaCharacterState state,
    required String field,
    required String op,
    required String targetContains,
    required double fallback,
    bool directFieldFallback = false,
  }) {
    final fieldValue = state.numeric(field);
    final resolved = tables.runtimeValueMaps.resolveOrNull(
      field: field,
      fieldValue: fieldValue,
      op: op,
      targetContains: targetContains,
    );
    if (resolved != null) {
      return resolved;
    }
    if (directFieldFallback) {
      return fieldValue.toDouble();
    }
    return fallback;
  }

  _SlotBinding? _bindingFor(RenderCatalogPart part) {
    if (part.family == 'left_eye') {
      if (part.partRole.startsWith('pupil_')) {
        return const _SlotBinding(
          targetContains: 'eye1.eye1.pupil.pupil',
          xField: 'lpupilxpos',
          yField: 'lpupilypos',
          scaleXField: 'lpupilsize',
          scaleYField: 'lpupilsizey',
          rotationField: 'lpupilrot',
        );
      }
      return const _SlotBinding(
        targetContains: 'head.head.eye1',
        xField: 'leyexpos',
        yField: 'leyeypos',
        scaleXField: 'leyesize',
        scaleYField: 'leyesizey',
        rotationField: 'leyerot',
      );
    }
    if (part.family == 'right_eye') {
      if (part.partRole.startsWith('pupil_')) {
        return const _SlotBinding(
          targetContains: 'eye2.eye2.pupil.pupil',
          xField: 'rpupilxpos',
          yField: 'rpupilypos',
          scaleXField: 'rpupilsize',
          scaleYField: 'rpupilsizey',
          rotationField: 'rpupilrot',
        );
      }
      return const _SlotBinding(
        targetContains: 'head.head.eye2',
        xField: 'reyexpos',
        yField: 'reyeypos',
        scaleXField: 'reyesize',
        scaleYField: 'reyesizey',
        rotationField: 'reyerot',
      );
    }
    if (part.family == 'left_eyebrow') {
      return const _SlotBinding(
        targetContains: 'head.head.eyebrow1',
        xField: 'leyebrowxpos',
        yField: 'leyebrowypos',
        scaleXField: 'leyebrowsize',
        scaleYField: 'leyebrowsizey',
        rotationField: 'leyebrowrot',
      );
    }
    if (part.family == 'right_eyebrow') {
      return const _SlotBinding(
        targetContains: 'head.head.eyebrow2',
        xField: 'reyebrowxpos',
        yField: 'reyebrowypos',
        scaleXField: 'reyebrowsize',
        scaleYField: 'reyebrowsizey',
        rotationField: 'reyebrowrot',
      );
    }
    if (part.family == 'front_hair') {
      return const _SlotBinding(
        targetContains: 'head.head.fronthair',
        xField: 'fronthairxpos',
        yField: 'fronthairypos',
        scaleXField: 'fronthairxscale',
        scaleYField: 'fronthairyscale',
        rotationField: 'fronthairrot',
        rotationUsesDirectFieldFallback: false,
        appliesGeometricRotation: false,
      );
    }
    if (part.family == 'back_hair') {
      return const _SlotBinding(
        targetContains: 'backhair.backhair',
        xField: 'backhairxpos',
        yField: 'backhairypos',
        scaleXField: 'backhairxscale',
        scaleYField: 'backhairyscale',
        rotationField: 'backhairrot',
      );
    }
    if (part.family == 'ponytail') {
      return const _SlotBinding(
        targetContains: 'backhair.backhair.ponytail',
        xField: 'ponytailxpos',
        yField: 'ponytailypos',
        scaleXField: 'ponytailxscale',
        scaleYField: 'ponytailyscale',
        rotationField: 'ponytailrot',
      );
    }
    if (part.family == 'ahoge') {
      return const _SlotBinding(
        targetContains: 'head.head.ahoge',
        xField: 'ahogexpos',
        yField: 'ahogeypos',
        scaleXField: 'ahogexscale',
        scaleYField: 'ahogeyscale',
        rotationField: 'ahogerot',
      );
    }
    if (part.family == 'mouth') {
      return const _SlotBinding(
        targetContains: 'head.head.mouth',
        xField: 'mouthxpos',
        yField: 'mouthypos',
        scaleXField: 'mouthsize',
        scaleYField: 'mouthsizey',
        rotationField: 'mouthrot',
      );
    }
    if (part.family == 'nose') {
      return const _SlotBinding(
        targetContains: 'head.head.nose',
        xField: 'nosexpos',
        yField: 'noseypos',
        scaleXField: 'nosesize',
        scaleYField: 'nosesizey',
        rotationField: 'noserot',
      );
    }
    if (part.family == 'hat') {
      return const _SlotBinding(
        targetContains: 'head.head.hat',
        xField: 'hatxpos',
        yField: 'hatypos',
        scaleXField: 'hatsize',
        scaleYField: 'hatsizey',
        rotationField: 'hatrot',
      );
    }
    if (part.family == 'glasses') {
      return const _SlotBinding(
        targetContains: 'head.head.glasses',
        xField: 'glassesxpos',
        yField: 'glassesypos',
        scaleXField: 'glassessize',
        scaleYField: 'glassessizey',
        rotationField: 'glassesrot',
      );
    }
    if (part.family == 'accessory1') {
      return const _SlotBinding(
        targetContains: 'head.head.accessory1',
        xField: 'acc1xpos',
        yField: 'acc1ypos',
        scaleXField: 'acc1size',
        scaleYField: 'acc1sizey',
        rotationField: 'acc1rot',
      );
    }
    if (part.family == 'accessory2') {
      return const _SlotBinding(
        targetContains: 'head.head.accessory2',
        xField: 'acc2xpos',
        yField: 'acc2ypos',
        scaleXField: 'acc2size',
        scaleYField: 'acc2sizey',
        rotationField: 'acc2rot',
      );
    }
    if (part.family == 'accessory3') {
      return const _SlotBinding(
        targetContains: 'head.head.accessory3',
        xField: 'acc3xpos',
        yField: 'acc3ypos',
        scaleXField: 'acc3size',
        scaleYField: 'acc3sizey',
        rotationField: 'acc3rot',
      );
    }
    if (part.family == 'other1') {
      return const _SlotBinding(
        targetContains: 'head.head.other1',
        xField: 'other1xpos',
        yField: 'other1ypos',
        scaleXField: 'other1size',
        scaleYField: 'other1sizey',
        rotationField: 'other1rot',
      );
    }
    if (part.family == 'other2') {
      return const _SlotBinding(
        targetContains: 'head.head.other2',
        xField: 'other2xpos',
        yField: 'other2ypos',
        scaleXField: 'other2size',
        scaleYField: 'other2sizey',
        rotationField: 'other2rot',
      );
    }
    if (part.family == 'other3') {
      return const _SlotBinding(
        targetContains: 'head.head.other3',
        xField: 'other3xpos',
        yField: 'other3ypos',
        scaleXField: 'other3size',
        scaleYField: 'other3sizey',
        rotationField: 'other3rot',
      );
    }
    if (part.family == 'other4') {
      return const _SlotBinding(
        targetContains: 'head.head.other4',
        xField: 'other4xpos',
        yField: 'other4ypos',
        scaleXField: 'other4size',
        scaleYField: 'other4sizey',
        rotationField: 'other4rot',
      );
    }
    if (part.family == 'cape') {
      return const _SlotBinding(
        targetContains: 'cape.cape.cape',
        xField: 'capexpos',
        yField: 'capeypos',
        scaleXField: 'capesize',
        scaleYField: 'capesizey',
        rotationField: 'caperot',
      );
    }
    if (part.family == 'tail') {
      return const _SlotBinding(
        targetContains: 'tail.tail.tail',
        xField: 'tailxpos',
        yField: 'tailypos',
        scaleXField: 'tailsize',
        scaleYField: 'tailsizey',
        rotationField: 'tailrot',
      );
    }
    if (part.family == 'wings1') {
      return const _SlotBinding(
        targetContains: 'wings.wing1.wing',
        xField: 'wingxpos',
        yField: 'wingypos',
        scaleXField: 'wingsize',
        scaleYField: 'wingsizey',
        rotationField: 'wingrot',
      );
    }
    if (part.family == 'wings2') {
      return const _SlotBinding(
        targetContains: 'wings.wing2.wing',
        xField: 'wingxpos',
        yField: 'wingypos',
        scaleXField: 'wingsize',
        scaleYField: 'wingsizey',
        rotationField: 'wingrot',
      );
    }
    if (part.family == 'weapon_front') {
      return const _SlotBinding(
        targetContains: 'weapon.weapon',
        xField: 'propxpos1x',
        yField: 'propypos1x',
        scaleXField: 'propsize1x',
        scaleYField: 'propsize1x',
        rotationField: 'proprot1x',
      );
    }
    if (part.family == 'weapon_back') {
      return const _SlotBinding(
        targetContains: 'backweapon.weapon',
        xField: 'propxpos2x',
        yField: 'propypos2x',
        scaleXField: 'propsize2x',
        scaleYField: 'propsize2x',
        rotationField: 'proprot2x',
      );
    }
    if (part.family == 'shield') {
      return const _SlotBinding(
        targetContains: 'shield.shield',
        xField: 'shieldxpos',
        yField: 'shieldypos',
        scaleXField: 'shieldsize',
        scaleYField: 'shieldsize',
        rotationField: 'shieldrot',
      );
    }
    return null;
  }

  List<String> _warningsFor(
    GachaCharacterState state,
    List<ResolvedRenderPart> parts,
  ) {
    final warnings = <String>[];
    if (parts.isEmpty) {
      warnings.add('No renderable head parts resolved for this case.');
    }
    if (state.numeric('special') > 0 || state.numeric('special2x') > 0) {
      warnings.add('Special effects are not rendered yet.');
    }
    final normalizedPose = tables.normalizePose(state.numeric('pose'));
    if (normalizedPose != state.numeric('pose')) {
      warnings.add(
        'Pose ${state.numeric('pose')} was normalized to supported runtime pose $normalizedPose.',
      );
    }
    return warnings;
  }
}

class GachaAssetStore {
  final Map<String, Future<PreparedAsset>> _cache = {};

  Future<Map<String, PreparedAsset>> loadAll(Set<String> assetPaths) async {
    final pending = <String, Future<PreparedAsset>>{};
    for (final assetPath in assetPaths) {
      pending[assetPath] = _cache.putIfAbsent(
        assetPath,
        () => _load(assetPath),
      );
    }
    final resolvedEntries = await Future.wait(
      pending.entries.map(
        (entry) async => MapEntry(entry.key, await entry.value),
      ),
    );
    final result = <String, PreparedAsset>{};
    for (final entry in resolvedEntries) {
      result[entry.key] = entry.value;
    }
    return result;
  }

  Future<PreparedAsset> _load(String assetPath) async {
    if (assetPath.toLowerCase().endsWith('.svg')) {
      final pictureInfo = await vg.vg.loadPicture(
        vg.SvgAssetLoader(assetPath),
        null,
      );
      return SvgPreparedAsset(assetPath: assetPath, pictureInfo: pictureInfo);
    }
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return RasterPreparedAsset(assetPath: assetPath, image: frame.image);
  }
}

class RasterPreparedAsset extends PreparedAsset {
  RasterPreparedAsset({required super.assetPath, required this.image})
    : super(
        size: Size(
          image.width / _rasterExportScale,
          image.height / _rasterExportScale,
        ),
      );

  final ui.Image image;
  static const double _rasterExportScale = 10;

  @override
  void paint(ui.Canvas canvas, ui.Color? tintColor) {
    final paint = ui.Paint();
    if (tintColor != null) {
      paint.colorFilter = ui.ColorFilter.mode(tintColor, ui.BlendMode.srcIn);
    }
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }
}

class SvgPreparedAsset extends PreparedAsset {
  SvgPreparedAsset({required super.assetPath, required this.pictureInfo})
    : super(size: pictureInfo.size);

  final vg.PictureInfo pictureInfo;

  @override
  void paint(ui.Canvas canvas, ui.Color? tintColor) {
    final bounds = ui.Rect.fromLTWH(0, 0, size.width, size.height);
    if (tintColor != null) {
      canvas.saveLayer(
        bounds,
        ui.Paint()
          ..colorFilter = ui.ColorFilter.mode(tintColor, ui.BlendMode.srcIn),
      );
      canvas.drawPicture(pictureInfo.picture);
      canvas.restore();
      return;
    }
    canvas.drawPicture(pictureInfo.picture);
  }
}

class _SlotBinding {
  const _SlotBinding({
    required this.targetContains,
    required this.xField,
    required this.yField,
    required this.scaleXField,
    required this.scaleYField,
    required this.rotationField,
    this.rotationUsesDirectFieldFallback = true,
    this.appliesGeometricRotation = true,
  });

  final String targetContains;
  final String xField;
  final String yField;
  final String scaleXField;
  final String scaleYField;
  final String rotationField;
  final bool rotationUsesDirectFieldFallback;
  final bool appliesGeometricRotation;
}
