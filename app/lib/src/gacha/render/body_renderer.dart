import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';
import 'tint_pipeline.dart';

class BodyRenderer {
  const BodyRenderer();

  List<RenderCatalogPart> resolve(
    GachaCharacterState state,
    ResolverTables tables,
  ) {
    final parts = <RenderCatalogPart>[];
    for (final selection in _selections) {
      final chooserFrame = selection.chooserFrame(state);
      if (chooserFrame <= 0) {
        continue;
      }
      parts.addAll(tables.partsFor(selection.family, chooserFrame));
    }
    return [
      for (final part in parts)
        if (TintPipeline.evaluateVisibility(part.visibilityRule, state)) part,
    ];
  }
}

class _FamilySelection {
  const _FamilySelection(this.family, this.chooserFrame);

  final String family;
  final int Function(GachaCharacterState state) chooserFrame;
}

const List<_FamilySelection> _selections = [
  _FamilySelection('special_back', _special2),
  _FamilySelection('ground_shadow', _shadow),
  _FamilySelection('body_base', _fixedOne),
  _FamilySelection('body_pants', _pants1),
  _FamilySelection('body_shirt', _shirt),
  _FamilySelection('body_logo', _logo),
  _FamilySelection('body_jacket', _shirtex),
  _FamilySelection('shoulder_front_base', _fixedOne),
  _FamilySelection('shoulder_front', _shoulder1),
  _FamilySelection('upper_sleeve_front', _sleeves1),
  _FamilySelection('hand_front_base', _hand1),
  _FamilySelection('lower_sleeve_front', _sleeves1),
  _FamilySelection('glove_front', _gloves1),
  _FamilySelection('wrist_front', _wrist1),
  _FamilySelection('back_shoulder_base', _fixedOne),
  _FamilySelection('shoulder_back', _shoulder2),
  _FamilySelection('upper_sleeve_back', _sleeves2),
  _FamilySelection('hand_back_base', _hand2),
  _FamilySelection('lower_sleeve_back', _sleeves2),
  _FamilySelection('glove_back', _gloves2),
  _FamilySelection('wrist_back', _wrist2),
  _FamilySelection('thigh_front_base', _fixedOne),
  _FamilySelection('thigh_pants_front', _pants1),
  _FamilySelection('thigh_socks_front', _socks1),
  _FamilySelection('foot_front_base', _fixedOne),
  _FamilySelection('foot_pants_front', _pants1),
  _FamilySelection('foot_socks_front', _socks1),
  _FamilySelection('shoe_front', _shoes1),
  _FamilySelection('knee_front', _knee1),
  _FamilySelection('thigh_back_base', _fixedOne),
  _FamilySelection('thigh_pants_back', _pants2),
  _FamilySelection('thigh_socks_back', _socks2),
  _FamilySelection('foot_back_base', _fixedOne),
  _FamilySelection('foot_pants_back', _pants2),
  _FamilySelection('foot_socks_back', _socks2),
  _FamilySelection('shoe_back', _shoes2),
  _FamilySelection('knee_back', _knee2),
  _FamilySelection('belt2', _belt2),
  _FamilySelection('belt1', _belt1),
  _FamilySelection('belt_shirt', _shirt),
  _FamilySelection('belt_jacket', _shirtex),
  _FamilySelection('scarf2', _scarf2),
  _FamilySelection('scarf1', _scarf1),
  _FamilySelection('cape', _cape),
  _FamilySelection('tail', _tail),
  _FamilySelection('wings1', _wings1),
  _FamilySelection('wings2', _wings2),
  _FamilySelection('shield', _shield),
  _FamilySelection('weapon_back', _weapon2),
  _FamilySelection('weapon_front', _weapon1),
  _FamilySelection('special_front', _special),
];

int _fixedOne(GachaCharacterState _) => 1;
int _shirt(GachaCharacterState state) => state.numeric('shirt');
int _shirtex(GachaCharacterState state) => state.numeric('shirtex');
int _sleeves1(GachaCharacterState state) => state.numeric('sleeves1x');
int _sleeves2(GachaCharacterState state) => state.numeric('sleeves2x');
int _pants1(GachaCharacterState state) => state.numeric('pants1x');
int _pants2(GachaCharacterState state) => state.numeric('pants2x');
int _socks1(GachaCharacterState state) => state.numeric('socks1x');
int _socks2(GachaCharacterState state) => state.numeric('socks2x');
int _shoes1(GachaCharacterState state) => state.numeric('shoes1x');
int _shoes2(GachaCharacterState state) => state.numeric('shoes2x');
int _belt1(GachaCharacterState state) => state.numeric('belt1x');
int _belt2(GachaCharacterState state) => state.numeric('belt2x');
int _gloves1(GachaCharacterState state) => state.numeric('gloves1x');
int _gloves2(GachaCharacterState state) => state.numeric('gloves2x');
int _wrist1(GachaCharacterState state) => state.numeric('wrist1x');
int _wrist2(GachaCharacterState state) => state.numeric('wrist2x');
int _cape(GachaCharacterState state) => state.numeric('cape');
int _scarf1(GachaCharacterState state) => state.numeric('scarf1x');
int _scarf2(GachaCharacterState state) => state.numeric('scarf2x');
int _wings1(GachaCharacterState state) => state.numeric('wings1x');
int _wings2(GachaCharacterState state) => state.numeric('wings2x');
int _tail(GachaCharacterState state) => state.numeric('tail');
int _shoulder1(GachaCharacterState state) => state.numeric('shoulder1x');
int _shoulder2(GachaCharacterState state) => state.numeric('shoulder2x');
int _weapon1(GachaCharacterState state) => state.numeric('weapon1x');
int _weapon2(GachaCharacterState state) => state.numeric('weapon2x');
int _shield(GachaCharacterState state) => state.numeric('shield');
int _hand1(GachaCharacterState state) => state.numeric('hand1x');
int _hand2(GachaCharacterState state) => state.numeric('hand2x');
int _knee1(GachaCharacterState state) => state.numeric('knee1x');
int _knee2(GachaCharacterState state) => state.numeric('knee2x');
int _logo(GachaCharacterState state) => state.numeric('logo');
int _shadow(GachaCharacterState state) => state.numeric('shadow');
int _special(GachaCharacterState state) => state.numeric('special');
int _special2(GachaCharacterState state) => state.numeric('special2x');
