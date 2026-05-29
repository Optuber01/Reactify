import 'package:flutter/painting.dart';

import 'gacha_field_schema.dart';

class GachaFieldChange {
  const GachaFieldChange({
    required this.index,
    required this.field,
    required this.previousRawValue,
    required this.rawValue,
  });

  final int index;
  final String field;
  final String previousRawValue;
  final String rawValue;
}

class GachaCharacterState {
  const GachaCharacterState({
    required this.rawFields,
    required this.metadataFields,
    required this.numericFields,
    required this.colorFields,
  });

  final List<String> rawFields;
  final Map<String, String> metadataFields;
  final Map<String, int> numericFields;
  final Map<String, Color> colorFields;

  String metadata(String field, {String fallback = ''}) {
    return metadataFields[field] ?? fallback;
  }

  int numeric(String field, {int fallback = 0}) {
    return numericFields[field] ?? fallback;
  }

  Color color(String field, {Color fallback = const Color(0xFF020202)}) {
    return colorFields[field] ?? fallback;
  }

  String rawValue(
    GachaFieldSchema schema,
    String field, {
    String fallback = '',
  }) {
    final definition = schema.byName[field];
    if (definition == null) {
      return fallback;
    }
    return rawFields[definition.index];
  }

  String serializeCode() {
    return rawFields.join('|');
  }

  GachaCharacterState updateMetadataField(
    GachaFieldSchema schema,
    String field,
    String value,
  ) {
    return _replace(
      schema: schema,
      field: field,
      rawValue: value,
      metadataValue: value,
    );
  }

  GachaCharacterState updateNumericField(
    GachaFieldSchema schema,
    String field,
    int value,
  ) {
    return _replace(
      schema: schema,
      field: field,
      rawValue: value.toString(),
      numericValue: value,
    );
  }

  GachaCharacterState updateColorField(
    GachaFieldSchema schema,
    String field,
    Color value,
  ) {
    return _replace(
      schema: schema,
      field: field,
      rawValue: _rawColor(value),
      colorValue: Color(value.toARGB32()),
    );
  }

  GachaCharacterState updateRawField(
    GachaFieldSchema schema,
    String field,
    String rawValue,
  ) {
    final definition = schema.byName[field];
    if (definition == null) {
      throw ArgumentError.value(field, 'field', 'Unknown Gacha field.');
    }
    switch (definition.kind) {
      case GachaFieldKind.metadata:
        return updateMetadataField(schema, field, rawValue);
      case GachaFieldKind.numeric:
        final parsed = int.tryParse(rawValue);
        if (parsed == null) {
          throw FormatException('Invalid numeric value for $field: $rawValue');
        }
        return updateNumericField(schema, field, parsed);
      case GachaFieldKind.color:
        if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(rawValue)) {
          throw FormatException('Invalid color value for $field: $rawValue');
        }
        return updateColorField(
          schema,
          field,
          Color(int.parse('FF${rawValue.toUpperCase()}', radix: 16)),
        );
    }
  }

  List<GachaFieldChange> diff(
    GachaCharacterState baseline,
    GachaFieldSchema schema,
  ) {
    return [
      for (final definition in schema.definitions)
        if (baseline.rawFields[definition.index] != rawFields[definition.index])
          GachaFieldChange(
            index: definition.index,
            field: definition.field,
            previousRawValue: baseline.rawFields[definition.index],
            rawValue: rawFields[definition.index],
          ),
    ];
  }

  Map<String, Object?> toDebugJson() {
    return {
      'namex': metadata('namex'),
      'pose': numeric('pose'),
      'headlayer': numeric('headlayer'),
      'headshape': numeric('headshape'),
      'rearhair': numeric('rearhair'),
      'fronthair': numeric('fronthair'),
      'backhair': numeric('backhair'),
      'ponytail': numeric('ponytail'),
      'ahoge': numeric('ahoge'),
      'eyes1x': numeric('eyes1x'),
      'eyes2x': numeric('eyes2x'),
      'pupil1x': numeric('pupil1x'),
      'pupil2x': numeric('pupil2x'),
      'eyebrows1x': numeric('eyebrows1x'),
      'eyebrows2x': numeric('eyebrows2x'),
      'facepreset': numeric('facepreset'),
      'highlights': numeric('highlights'),
      'mouth': numeric('mouth'),
      'shirt': numeric('shirt'),
      'shirtex': numeric('shirtex'),
      'pants1x': numeric('pants1x'),
      'pants2x': numeric('pants2x'),
      'shoes1x': numeric('shoes1x'),
      'shoes2x': numeric('shoes2x'),
      'displayhead': numeric('displayhead'),
      'displayface': numeric('displayface'),
      'displayhair': numeric('displayhair'),
      'displayoutline': numeric('displayoutline'),
    };
  }

  GachaCharacterState _replace({
    required GachaFieldSchema schema,
    required String field,
    required String rawValue,
    String? metadataValue,
    int? numericValue,
    Color? colorValue,
  }) {
    final definition = schema.byName[field];
    if (definition == null) {
      throw ArgumentError.value(field, 'field', 'Unknown Gacha field.');
    }
    final nextRawFields = List<String>.from(rawFields);
    nextRawFields[definition.index] = rawValue;
    final nextMetadata = Map<String, String>.from(metadataFields);
    final nextNumeric = Map<String, int>.from(numericFields);
    final nextColors = Map<String, Color>.from(colorFields);
    switch (definition.kind) {
      case GachaFieldKind.metadata:
        nextMetadata[field] = metadataValue ?? rawValue;
      case GachaFieldKind.numeric:
        nextNumeric[field] = numericValue ?? int.parse(rawValue);
      case GachaFieldKind.color:
        nextColors[field] =
            colorValue ?? Color(int.parse('FF$rawValue', radix: 16));
    }
    return GachaCharacterState(
      rawFields: nextRawFields,
      metadataFields: nextMetadata,
      numericFields: nextNumeric,
      colorFields: nextColors,
    );
  }

  static String _rawColor(Color color) {
    final value = color.toARGB32() & 0x00FFFFFF;
    return value.toRadixString(16).padLeft(6, '0').toUpperCase();
  }
}
