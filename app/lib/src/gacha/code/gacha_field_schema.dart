enum GachaFieldKind { metadata, numeric, color }

class GachaFieldDefinition {
  const GachaFieldDefinition({
    required this.index,
    required this.subsystem,
    required this.field,
    required this.kind,
  });

  final int index;
  final String subsystem;
  final String field;
  final GachaFieldKind kind;
}

class GachaFieldSchema {
  const GachaFieldSchema({required this.definitions, required this.byName});

  static const int totalFieldCount = 445;
  static const int metadataFieldCount = 10;
  static const int numericStartIndex = 10;
  static const int colorStartIndex = 279;

  final List<GachaFieldDefinition> definitions;
  final Map<String, GachaFieldDefinition> byName;

  factory GachaFieldSchema.fromRows(List<Map<String, String>> rows) {
    if (rows.length != totalFieldCount) {
      throw StateError(
        'Expected $totalFieldCount schema rows, got ${rows.length}.',
      );
    }
    final definitions = <GachaFieldDefinition>[];
    for (final row in rows) {
      final index = int.parse(row['index']!);
      final field = row['field']!;
      final subsystem = row['subsystem']!;
      definitions.add(
        GachaFieldDefinition(
          index: index,
          subsystem: subsystem,
          field: field,
          kind: _kindForIndex(index),
        ),
      );
    }
    definitions.sort((left, right) => left.index.compareTo(right.index));
    for (var i = 0; i < definitions.length; i++) {
      if (definitions[i].index != i) {
        throw StateError('Schema index mismatch at row $i.');
      }
    }
    final byName = {
      for (final definition in definitions) definition.field: definition,
    };
    return GachaFieldSchema(definitions: definitions, byName: byName);
  }

  static GachaFieldKind _kindForIndex(int index) {
    if (index < metadataFieldCount) {
      return GachaFieldKind.metadata;
    }
    if (index < colorStartIndex) {
      return GachaFieldKind.numeric;
    }
    return GachaFieldKind.color;
  }
}
