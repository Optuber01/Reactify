import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../gacha/code/gacha_character_state.dart';
import '../../gacha/data/resolver_tables.dart';
import '../../gacha/render/character_renderer.dart';
import '../../gacha/render/render_part.dart';
import '../../gacha/render/transform_graph.dart';
import '../export/reactify_svg_exporter.dart';
import '../legacy/gacha_to_reactify_adapter.dart';
import '../model/reactify_document.dart';
import 'reactify_render_bridge.dart';

class CharacterRenderResult {
  const CharacterRenderResult({
    required this.character,
    required this.scene,
    required this.resolvedScene,
    required this.backgroundColor,
  });

  final ReactifyCharacterDocument character;
  final ReactifySceneDocument scene;
  final ResolvedScene resolvedScene;
  final Color? backgroundColor;
}

class CharacterRenderService {
  CharacterRenderService({
    required ResolverTables tables,
    required GachaAssetStore assetStore,
  }) : _adapter = GachaToReactifyAdapter(
         renderer: CharacterRenderer(tables: tables, assetStore: assetStore),
       ),
       _bridge = ReactifyRenderBridge(assetStore: assetStore);

  final GachaToReactifyAdapter _adapter;
  final ReactifyRenderBridge _bridge;

  ReactifyRenderBridge get bridge => _bridge;

  Future<CharacterRenderResult> renderCharacter({
    required String characterId,
    required GachaCharacterState state,
    Size canvasSize = const Size(1000, 1000),
    double padding = 80,
    Color? backgroundColor = const Color(0xFFF4F0E4),
  }) async {
    final character = _adapter.migrate(state, id: characterId);
    final baseScene = ReactifySceneDocument(
      id: 'preview.$characterId',
      name: '${character.name} Preview',
      canvasSize: canvasSize,
      characters: [
        ReactifySceneCharacter(
          id: 'preview.instance.$characterId',
          characterId: character.id,
          transform: const AffineMatrix.identity(),
        ),
      ],
    );
    final characters = {character.id: character};
    final baseResolved = await _bridge.buildRenderableScene(
      baseScene,
      characters,
    );
    if (baseResolved.parts.isEmpty || baseResolved.worldBounds.isEmpty) {
      throw StateError(
        'Character ${character.name} did not resolve to visible production parts.',
      );
    }
    final fittedScene = baseScene.copyWith(
      cameraTransform: _fitTransform(
        baseResolved.worldBounds,
        canvasSize,
        padding,
      ),
    );
    final resolved = await _bridge.buildRenderableScene(
      fittedScene,
      characters,
    );
    if (resolved.parts.isEmpty || resolved.assets.isEmpty) {
      throw StateError(
        'Character ${character.name} could not load production render assets.',
      );
    }
    return CharacterRenderResult(
      character: character,
      scene: fittedScene,
      resolvedScene: resolved,
      backgroundColor: backgroundColor,
    );
  }

  Future<Uint8List> exportPng(CharacterRenderResult result) async {
    final image = await ReactifyPngExporter.renderResolvedScene(
      result.resolvedScene,
      result.scene.canvasSize,
      backgroundColor: result.backgroundColor,
    );
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('Unable to encode character PNG.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<String> exportSvg(CharacterRenderResult result) {
    return ReactifySvgExporter().exportResolvedScene(
      result.resolvedScene,
      result.scene.canvasSize,
      backgroundColor: result.backgroundColor,
    );
  }

  static AffineMatrix _fitTransform(
    Rect bounds,
    Size canvasSize,
    double padding,
  ) {
    final safePadding = padding.clamp(
      0,
      math.min(canvasSize.width, canvasSize.height) * 0.45,
    );
    final availableWidth = math.max(1, canvasSize.width - safePadding * 2);
    final availableHeight = math.max(1, canvasSize.height - safePadding * 2);
    final scale = math.min(
      availableWidth / bounds.width,
      availableHeight / bounds.height,
    );
    final tx =
        (canvasSize.width - bounds.width * scale) * 0.5 - bounds.left * scale;
    final ty =
        (canvasSize.height - bounds.height * scale) * 0.5 - bounds.top * scale;
    return AffineMatrix.translation(
      tx,
      ty,
    ).multiply(AffineMatrix.scale(scale, scale));
  }
}
