import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';

class HairRenderer {
  const HairRenderer();

  List<RenderCatalogPart> resolve(
    GachaCharacterState state,
    ResolverTables tables,
  ) {
    final parts = <RenderCatalogPart>[];
    if (state.numeric('displayhair') == 0) {
      return parts;
    }
    _addIfActive(parts, tables, 'rear_hair', state.numeric('rearhair'));
    _addIfActive(parts, tables, 'front_hair', state.numeric('fronthair'));
    _addIfActive(parts, tables, 'back_hair', state.numeric('backhair'));
    _addIfActive(parts, tables, 'ponytail', state.numeric('ponytail'));
    _addIfActive(parts, tables, 'ahoge', state.numeric('ahoge'));
    return parts;
  }

  void _addIfActive(
    List<RenderCatalogPart> target,
    ResolverTables tables,
    String family,
    int chooserFrame,
  ) {
    if (chooserFrame <= 0) {
      return;
    }
    target.addAll(tables.partsFor(family, chooserFrame));
  }
}
