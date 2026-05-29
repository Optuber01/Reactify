import 'package:flutter/painting.dart';

import '../code/gacha_character_state.dart';

class TintPipeline {
  const TintPipeline._();

  static Color? resolveTint(GachaCharacterState state, String tintChannel) {
    if (tintChannel.isEmpty || tintChannel == 'none') {
      return null;
    }
    return state.color(tintChannel);
  }

  static bool evaluateVisibility(String rule, GachaCharacterState state) {
    if (rule.trim().isEmpty) {
      return true;
    }
    final clauses = rule.split('&&').map((value) => value.trim());
    for (final clause in clauses) {
      if (clause.isEmpty) {
        continue;
      }
      if (clause == 'pose wrapper is visible') {
        if (state.numeric('displayhead') == 0) {
          return false;
        }
        continue;
      }
      final match = RegExp(
        r'^([A-Za-z0-9_]+)\s*([!=]=)\s*(-?\d+)$',
      ).firstMatch(clause);
      if (match == null) {
        continue;
      }
      final field = match.group(1)!;
      final op = match.group(2)!;
      final expected = int.parse(match.group(3)!);
      final actual = state.numeric(field);
      if (op == '==' && actual != expected) {
        return false;
      }
      if (op == '!=' && actual == expected) {
        return false;
      }
    }
    return true;
  }
}
