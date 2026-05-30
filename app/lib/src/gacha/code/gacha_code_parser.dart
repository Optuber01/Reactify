import 'package:flutter/painting.dart';

import 'gacha_character_state.dart';
import 'gacha_field_schema.dart';

class GachaCodeParser {
  const GachaCodeParser(this.schema);

  final GachaFieldSchema schema;
  static final RegExp _colorRegExp = RegExp(r'^[0-9A-Fa-f]{6}$');

  GachaCharacterState parse(String code) {
    final fields = code.trim().split('|');
    if (fields.length != GachaFieldSchema.totalFieldCount) {
      throw FormatException(
        'Expected ${GachaFieldSchema.totalFieldCount} fields, got ${fields.length}.',
      );
    }
    final metadataFields = <String, String>{};
    final numericFields = <String, int>{};
    final colorFields = <String, Color>{};
    for (final definition in schema.definitions) {
      final value = fields[definition.index];
      switch (definition.kind) {
        case GachaFieldKind.metadata:
          metadataFields[definition.field] = value;
        case GachaFieldKind.numeric:
          final parsed = int.tryParse(value);
          if (parsed == null) {
            throw FormatException(
              'Invalid numeric value for ${definition.field}: $value',
            );
          }
          numericFields[definition.field] = parsed;
        case GachaFieldKind.color:
          if (!_colorRegExp.hasMatch(value)) {
            throw FormatException(
              'Invalid color value for ${definition.field}: $value',
            );
          }
          colorFields[definition.field] = Color(
            int.parse('FF$value', radix: 16),
          );
      }
    }
    return GachaCharacterState(
      rawFields: fields,
      metadataFields: metadataFields,
      numericFields: numericFields,
      colorFields: colorFields,
    );
  }
}
