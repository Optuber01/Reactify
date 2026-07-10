import 'dart:collection';

import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';
import '../render/render_part.dart';

final RegExp _rgbHexRegExp = RegExp(r'^[0-9A-Fa-f]{6}$');

bool isValidRgbHex(String value) {
  return _rgbHexRegExp.hasMatch(value.trim());
}

String? canonicalRgbHexOrNull(String value) {
  final normalized = value.trim().toUpperCase();
  return isValidRgbHex(normalized) ? normalized : null;
}

({int? min, int? max}) effectiveEditorDomain({
  required int currentValue,
  int? declaredMin,
  int? declaredMax,
  List<int> supportedValues = const [],
}) {
  if (declaredMin == null && declaredMax == null && supportedValues.isEmpty) {
    return (min: null, max: null);
  }
  final minimums = <int>[currentValue];
  final maximums = <int>[currentValue];
  if (declaredMin != null) minimums.add(declaredMin);
  if (declaredMax != null) maximums.add(declaredMax);
  if (supportedValues.isNotEmpty) {
    minimums.add(supportedValues.first);
    maximums.add(supportedValues.last);
  }
  minimums.sort();
  maximums.sort();
  return (min: minimums.first, max: maximums.last);
}

int constrainToEditorDomain({
  required int currentValue,
  required int proposedValue,
  required EditorValueRange? declaredRange,
  List<int> supportedValues = const [],
}) {
  if (declaredRange == null && supportedValues.isEmpty) return proposedValue;
  final domain = effectiveEditorDomain(
    currentValue: currentValue,
    declaredMin: declaredRange?.minValue,
    declaredMax: declaredRange?.maxValue,
    supportedValues: supportedValues,
  );
  return proposedValue.clamp(domain.min!, domain.max!);
}

const Map<String, List<String>> _previewFieldFamilies = {
  'headshape': ['head_shape'],
  'rearhair': ['rear_hair'],
  'fronthair': ['front_hair'],
  'backhair': ['back_hair'],
  'ponytail': ['ponytail'],
  'ahoge': ['ahoge'],
  'eyes1x': ['left_eye'],
  'eyes2x': ['right_eye'],
  'eyebrows1x': ['left_eyebrow'],
  'eyebrows2x': ['right_eyebrow'],
  'mouth': ['mouth'],
  'nose': ['nose'],
  'blush': ['blush'],
  'faceshadow': ['faceshadow'],
  'hat': ['hat'],
  'glasses': ['glasses'],
  'accessory1x': ['accessory1'],
  'accessory2x': ['accessory2'],
  'accessory3x': ['accessory3'],
  'other1x': ['other1'],
  'other2x': ['other2'],
  'other3x': ['other3'],
  'other4x': ['other4'],
  'shirt': ['body_shirt'],
  'shirtex': ['body_jacket'],
  'sleeves1x': ['upper_sleeve_front', 'lower_sleeve_front'],
  'sleeves2x': ['upper_sleeve_back', 'lower_sleeve_back'],
  'pants1x': ['body_pants', 'thigh_pants_front', 'foot_pants_front'],
  'pants2x': ['thigh_pants_back', 'foot_pants_back'],
  'socks1x': ['thigh_socks_front', 'foot_socks_front'],
  'socks2x': ['thigh_socks_back', 'foot_socks_back'],
  'shoes1x': ['shoe_front'],
  'shoes2x': ['shoe_back'],
  'belt1x': ['belt1'],
  'belt2x': ['belt2'],
  'gloves1x': ['glove_front'],
  'gloves2x': ['glove_back'],
  'wrist1x': ['wrist_front'],
  'wrist2x': ['wrist_back'],
  'cape': ['cape'],
  'scarf1x': ['scarf1'],
  'scarf2x': ['scarf2'],
  'wings1x': ['wings1'],
  'wings2x': ['wings2'],
  'tail': ['tail'],
  'shoulder1x': ['shoulder_front'],
  'shoulder2x': ['shoulder_back'],
  'weapon1x': ['weapon_front'],
  'weapon2x': ['weapon_back'],
  'shield': ['shield'],
  'special': ['special'],
  'special2x': ['special2'],
};

bool isPreviewBackedField(String field) =>
    _previewFieldFamilies.containsKey(field);

final Map<String, List<int>> _previewSupportedValuesCache = {};

List<int> previewSupportedValues(ResolverTables tables, String field) {
  return _previewSupportedValuesCache.putIfAbsent(field, () {
    final families = _previewFieldFamilies[field];
    if (families == null) {
      return const [];
    }
    final values = SplayTreeSet<int>();
    for (final family in families) {
      final familyFrames = tables.catalogByFamilyFrame[family];
      if (familyFrames == null) {
        continue;
      }
      values.addAll(familyFrames.keys);
    }
    return values.toList(growable: false);
  });
}

String previewSupportLabel(ResolverTables tables, String field) {
  if (!isPreviewBackedField(field)) {
    return 'export-only';
  }
  final values = previewSupportedValues(tables, field);
  if (values.isEmpty) {
    return 'export-only';
  }
  if (values.length == 1) {
    return 'preview: ${values.first} only';
  }
  return 'preview: ${values.first}-${values.last} (${values.length} extracted)';
}

Map<String, int> resolvedFamilyCounts(ResolvedScene scene) {
  final counts = <String, int>{};
  for (final part in scene.parts) {
    counts.update(
      part.catalogPart.family,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  return counts;
}

Set<String> expectedResolvedFamiliesForState(GachaCharacterState state) {
  final families = <String>{};
  if (state.numeric('displayhead') != 0) {
    families.add('head_shape');
  }
  if (state.numeric('displayhair') != 0) {
    if (state.numeric('rearhair') > 0) {
      families.add('rear_hair');
    }
    if (state.numeric('fronthair') > 0) {
      families.add('front_hair');
    }
    if (state.numeric('backhair') > 0) {
      families.add('back_hair');
    }
    if (state.numeric('ponytail') > 0) {
      families.add('ponytail');
    }
    if (state.numeric('ahoge') > 0) {
      families.add('ahoge');
    }
  }
  if (state.numeric('displayface') != 0) {
    if (state.numeric('eyes1x') > 0) {
      families.add('left_eye');
    }
    if (state.numeric('eyes2x') > 0) {
      families.add('right_eye');
    }
    if (state.numeric('eyebrows1x') > 0) {
      families.add('left_eyebrow');
    }
    if (state.numeric('eyebrows2x') > 0) {
      families.add('right_eyebrow');
    }
    if (state.numeric('mouth') > 0) {
      families.add('mouth');
    }
    if (state.numeric('nose') > 0) {
      families.add('nose');
    }
    if (state.numeric('blush') > 0) {
      families.add('blush');
    }
    if (state.numeric('faceshadow') > 0) {
      families.add('faceshadow');
    }
    if (state.numeric('hat') > 0) {
      families.add('hat');
    }
    if (state.numeric('glasses') > 0) {
      families.add('glasses');
    }
    if (state.numeric('accessory1x') > 0) {
      families.add('accessory1');
    }
    if (state.numeric('accessory2x') > 0) {
      families.add('accessory2');
    }
    if (state.numeric('accessory3x') > 0) {
      families.add('accessory3');
    }
    if (state.numeric('other1x') > 0) {
      families.add('other1');
    }
    if (state.numeric('other2x') > 0) {
      families.add('other2');
    }
    if (state.numeric('other3x') > 0) {
      families.add('other3');
    }
    if (state.numeric('other4x') > 0) {
      families.add('other4');
    }
  }
  if (state.numeric('displaybody') != 0) {
    families.addAll(const {'body_base', 'body_pants'});
    if (state.numeric('shirt') > 0) {
      families.add('body_shirt');
      families.add('belt_shirt');
    }
    if (state.numeric('shirtex') > 0) {
      families.add('body_jacket');
      families.add('belt_jacket');
    }
    if (state.numeric('logo') > 0) {
      families.add('body_logo');
    }
  }
  if (state.numeric('displayshoulder') != 0) {
    families.add('shoulder_front_base');
    if (state.numeric('shoulder1x') > 0) {
      families.add('shoulder_front');
    }
    if (state.numeric('sleeves1x') > 0) {
      families.addAll(const {'upper_sleeve_front', 'lower_sleeve_front'});
    }
  }
  if (state.numeric('displaybackshoulder') != 0) {
    families.add('back_shoulder_base');
    if (state.numeric('shoulder2x') > 0) {
      families.add('shoulder_back');
    }
    if (state.numeric('sleeves2x') > 0) {
      families.addAll(const {'upper_sleeve_back', 'lower_sleeve_back'});
    }
  }
  if (state.numeric('displayhand') != 0) {
    if (state.numeric('hand1x') > 0) {
      families.add('hand_front_base');
    }
    if (state.numeric('gloves1x') > 0) {
      families.add('glove_front');
    }
    if (state.numeric('wrist1x') > 0) {
      families.add('wrist_front');
    }
  }
  if (state.numeric('displaybackhand') != 0) {
    if (state.numeric('hand2x') > 0) {
      families.add('hand_back_base');
    }
    if (state.numeric('gloves2x') > 0) {
      families.add('glove_back');
    }
    if (state.numeric('wrist2x') > 0) {
      families.add('wrist_back');
    }
  }
  if (state.numeric('displaythigh') != 0) {
    families.add('thigh_front_base');
    if (state.numeric('pants1x') > 0) {
      families.add('thigh_pants_front');
    }
    if (state.numeric('socks1x') > 0) {
      families.add('thigh_socks_front');
    }
    if (state.numeric('knee1x') > 0) {
      families.add('knee_front');
    }
  }
  if (state.numeric('displaybackthigh') != 0) {
    families.add('thigh_back_base');
    if (state.numeric('pants2x') > 0) {
      families.add('thigh_pants_back');
    }
    if (state.numeric('socks2x') > 0) {
      families.add('thigh_socks_back');
    }
    if (state.numeric('knee2x') > 0) {
      families.add('knee_back');
    }
  }
  if (state.numeric('displayfoot') != 0) {
    families.add('foot_front_base');
    if (state.numeric('pants1x') > 0) {
      families.add('foot_pants_front');
    }
    if (state.numeric('socks1x') > 0) {
      families.add('foot_socks_front');
    }
    if (state.numeric('shoes1x') > 0) {
      families.add('shoe_front');
    }
  }
  if (state.numeric('displaybackfoot') != 0) {
    families.add('foot_back_base');
    if (state.numeric('pants2x') > 0) {
      families.add('foot_pants_back');
    }
    if (state.numeric('socks2x') > 0) {
      families.add('foot_socks_back');
    }
    if (state.numeric('shoes2x') > 0) {
      families.add('shoe_back');
    }
  }
  if (state.numeric('belt1x') > 0) {
    families.add('belt1');
  }
  if (state.numeric('belt2x') > 0) {
    families.add('belt2');
  }
  if (state.numeric('cape') > 0) {
    families.add('cape');
  }
  if (state.numeric('scarf1x') > 0) {
    families.add('scarf1');
  }
  if (state.numeric('scarf2x') > 0) {
    families.add('scarf2');
  }
  if (state.numeric('wings1x') > 0) {
    families.add('wings1');
  }
  if (state.numeric('wings2x') > 0) {
    families.add('wings2');
  }
  if (state.numeric('tail') > 0) {
    families.add('tail');
  }
  if (state.numeric('weapon1x') > 0) {
    families.add('weapon_front');
  }
  if (state.numeric('weapon2x') > 0) {
    families.add('weapon_back');
  }
  if (state.numeric('shield') > 0) {
    families.add('shield');
  }
  if (state.numeric('special') > 0) {
    families.add('special');
  }
  if (state.numeric('special2x') > 0) {
    families.add('special2');
  }
  return families;
}
