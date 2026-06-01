import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';
import 'eye_renderer.dart';
import 'hair_renderer.dart';
import 'tint_pipeline.dart';

class HeadRenderer {
  const HeadRenderer({
    this.eyeRenderer = const EyeRenderer(),
    this.hairRenderer = const HairRenderer(),
  });

  final EyeRenderer eyeRenderer;
  final HairRenderer hairRenderer;

  List<RenderCatalogPart> resolve(
    GachaCharacterState state,
    ResolverTables tables,
  ) {
    final parts = <RenderCatalogPart>[];
    if (state.numeric('displayhead') != 0) {
      parts.addAll(tables.partsFor('head_shape', state.numeric('headshape')));
    }
    if (state.numeric('displayface') != 0 && state.numeric('mouth') > 0) {
      parts.addAll(tables.partsFor('mouth', state.numeric('mouth')));
    }
    if (state.numeric('displayface') != 0 && state.numeric('nose') > 0) {
      parts.addAll(tables.partsFor('nose', state.numeric('nose')));
    }
    if (state.numeric('displayface') != 0 && state.numeric('blush') > 0) {
      parts.addAll(tables.partsFor('blush', state.numeric('blush')));
    }
    if (state.numeric('displayface') != 0 && state.numeric('faceshadow') > 0) {
      parts.addAll(tables.partsFor('faceshadow', state.numeric('faceshadow')));
    }
    if (state.numeric('displayhead') != 0) {
      if (state.numeric('hat') > 0) {
        parts.addAll(tables.partsFor('hat', state.numeric('hat')));
      }
      if (state.numeric('glasses') > 0) {
        parts.addAll(tables.partsFor('glasses', state.numeric('glasses')));
      }
      if (state.numeric('accessory1x') > 0) {
        parts.addAll(
          tables.partsFor('accessory1', state.numeric('accessory1x')),
        );
      }
      if (state.numeric('accessory2x') > 0) {
        parts.addAll(
          tables.partsFor('accessory2', state.numeric('accessory2x')),
        );
      }
      if (state.numeric('accessory3x') > 0) {
        parts.addAll(
          tables.partsFor('accessory3', state.numeric('accessory3x')),
        );
      }
      if (state.numeric('other1x') > 0) {
        parts.addAll(tables.partsFor('other1', state.numeric('other1x')));
      }
      if (state.numeric('other2x') > 0) {
        parts.addAll(tables.partsFor('other2', state.numeric('other2x')));
      }
      if (state.numeric('other3x') > 0) {
        parts.addAll(tables.partsFor('other3', state.numeric('other3x')));
      }
      if (state.numeric('other4x') > 0) {
        parts.addAll(tables.partsFor('other4', state.numeric('other4x')));
      }
    }
    parts.addAll(hairRenderer.resolve(state, tables));
    parts.addAll(eyeRenderer.resolve(state, tables));
    return [
      for (final part in parts)
        if (TintPipeline.evaluateVisibility(part.visibilityRule, state)) part,
    ];
  }
}
