import 'package:flutter/painting.dart';

import '../code/gacha_character_state.dart';

class _VisibilityClause {
  _VisibilityClause(this.clause) {
    if (clause == 'pose wrapper is visible') {
      isPoseWrapper = true;
    } else {
      final match = RegExp(r'^([A-Za-z0-9_]+)\s*([!=]=)\s*(-?\d+)$').firstMatch(clause);
      if (match != null) {
        field = match.group(1)!;
        isEquals = match.group(2) == '==';
        expected = int.parse(match.group(3)!);
      }
    }
  }

  final String clause;
  bool isPoseWrapper = false;
  String? field;
  bool? isEquals;
  int? expected;
}

class TintPipeline {
  const TintPipeline._();

  static final Map<String, List<_VisibilityClause>> _parsedRulesCache = {};

  static Color? resolveTint(GachaCharacterState state, String tintChannel) {
    if (tintChannel.isEmpty || tintChannel == 'none') {
      return null;
    }
    return state.color(tintChannel);
  }

  static bool evaluateVisibility(String rule, GachaCharacterState state) {
    final trimmedRule = rule.trim();
    if (trimmedRule.isEmpty) {
      return true;
    }

    final clauses = _parsedRulesCache.putIfAbsent(trimmedRule, () {
      return trimmedRule
          .split('&&')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .map((v) => _VisibilityClause(v))
          .toList();
    });

    for (final clause in clauses) {
      if (clause.isPoseWrapper) {
        if (state.numeric('displayhead') == 0) {
          return false;
        }
        continue;
      }
      final field = clause.field;
      if (field == null) {
        continue;
      }
      final actual = state.numeric(field);
      final expected = clause.expected!;
      if (clause.isEquals!) {
        if (actual != expected) {
          return false;
        }
      } else {
        if (actual == expected) {
          return false;
        }
      }
    }
    return true;
  }
}
