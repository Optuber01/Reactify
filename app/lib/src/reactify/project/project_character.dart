import '../../gacha/code/gacha_character_state.dart';
import '../../gacha/code/gacha_code_parser.dart';
import '../../gacha/code/gacha_field_schema.dart';
import 'project_error.dart';
import 'project_id.dart';

enum CharacterOrigin { created, imported }

class ReactifyCharacterMetadata {
  ReactifyCharacterMetadata({
    required this.origin,
    this.nativeModelVersion = 1,
    String rigTemplateId = 'gacha_compat_2d_v1',
    List<String> customAssetIds = const [],
    Map<String, Object?> extensions = const {},
  }) : rigTemplateId = _validatedReference(rigTemplateId, 'rigTemplateId'),
       customAssetIds = List.unmodifiable(_validatedAssetIds(customAssetIds)),
       extensions = Map.unmodifiable(_validateExtensions(extensions));

  final CharacterOrigin origin;
  final int nativeModelVersion;
  final String rigTemplateId;
  final List<String> customAssetIds;
  final Map<String, Object?> extensions;

  void validate() {
    if (nativeModelVersion < 1) {
      throw const ProjectFailure(
        code: ProjectErrorCode.invalidMetadata,
        message: 'Character nativeModelVersion must be a positive integer.',
        field: 'nativeModelVersion',
      );
    }
  }

  factory ReactifyCharacterMetadata.fromJson(Map<String, Object?> json) {
    final version = json['nativeModelVersion'];
    if (version is! int || version < 1) {
      throw const ProjectFailure(
        code: ProjectErrorCode.invalidMetadata,
        message: 'Character nativeModelVersion must be a positive integer.',
        field: 'nativeModelVersion',
      );
    }
    final originName = json['origin'];
    final origin = CharacterOrigin.values.where((value) {
      return value.name == originName;
    }).firstOrNull;
    if (origin == null) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidMetadata,
        message: 'Unknown character origin: $originName.',
        field: 'origin',
      );
    }
    final rigTemplateId = json['rigTemplateId'];
    if (rigTemplateId is! String || rigTemplateId.trim().isEmpty) {
      throw const ProjectFailure(
        code: ProjectErrorCode.invalidMetadata,
        message: 'Character rigTemplateId must be a non-empty string.',
        field: 'rigTemplateId',
      );
    }
    final assetValues = json['customAssetIds'];
    if (assetValues is! List || assetValues.any((value) => value is! String)) {
      throw const ProjectFailure(
        code: ProjectErrorCode.invalidMetadata,
        message: 'customAssetIds must be a list of string references.',
        field: 'customAssetIds',
      );
    }
    final extensionValues = json['extensions'];
    return ReactifyCharacterMetadata(
      origin: origin,
      nativeModelVersion: version,
      rigTemplateId: rigTemplateId,
      customAssetIds: assetValues.cast<String>(),
      extensions: extensionValues == null
          ? const {}
          : _jsonObject(extensionValues, 'extensions'),
    );
  }

  ReactifyCharacterMetadata copyWith({
    CharacterOrigin? origin,
    int? nativeModelVersion,
    String? rigTemplateId,
    List<String>? customAssetIds,
    Map<String, Object?>? extensions,
  }) {
    return ReactifyCharacterMetadata(
      origin: origin ?? this.origin,
      nativeModelVersion: nativeModelVersion ?? this.nativeModelVersion,
      rigTemplateId: rigTemplateId ?? this.rigTemplateId,
      customAssetIds: customAssetIds ?? this.customAssetIds,
      extensions: extensions ?? this.extensions,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'origin': origin.name,
      'nativeModelVersion': nativeModelVersion,
      'rigTemplateId': rigTemplateId,
      'customAssetIds': customAssetIds,
      'extensions': extensions,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ReactifyCharacterMetadata &&
        other.origin == origin &&
        other.nativeModelVersion == nativeModelVersion &&
        other.rigTemplateId == rigTemplateId &&
        _listEquals(other.customAssetIds, customAssetIds) &&
        _jsonEquals(other.extensions, extensions);
  }

  @override
  int get hashCode => Object.hash(
    origin,
    nativeModelVersion,
    rigTemplateId,
    Object.hashAll(customAssetIds),
    _jsonHash(extensions),
  );
}

class ProjectCharacter {
  ProjectCharacter({
    required this.id,
    required String name,
    required GachaCharacterState gachaState,
    required this.metadata,
  }) : name = validatedCharacterName(name),
       gachaState = _immutableState(gachaState) {
    metadata.validate();
    if (gachaState.rawFields.length != GachaFieldSchema.totalFieldCount) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidCharacterCode,
        message:
            'Character state must contain ${GachaFieldSchema.totalFieldCount} fields.',
        field: 'canonicalGachaCode',
        details: {'actualFieldCount': gachaState.rawFields.length},
      );
    }
  }

  final CharacterId id;
  final String name;
  final GachaCharacterState gachaState;
  final ReactifyCharacterMetadata metadata;

  String get canonicalGachaCode => gachaState.serializeCode();

  factory ProjectCharacter.fromCode({
    required CharacterId id,
    required String name,
    required String canonicalGachaCode,
    required ReactifyCharacterMetadata metadata,
    required GachaCodeParser parser,
  }) {
    try {
      return ProjectCharacter(
        id: id,
        name: name,
        gachaState: parser.parse(canonicalGachaCode),
        metadata: metadata,
      );
    } on ProjectFailure {
      rethrow;
    } on FormatException catch (error) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidCharacterCode,
        message: error.message.toString(),
        field: 'canonicalGachaCode',
      );
    }
  }

  ProjectCharacter copyWith({
    CharacterId? id,
    String? name,
    GachaCharacterState? gachaState,
    ReactifyCharacterMetadata? metadata,
  }) {
    return ProjectCharacter(
      id: id ?? this.id,
      name: name ?? this.name,
      gachaState: gachaState ?? this.gachaState,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id.value,
      'name': name,
      'canonicalGachaCode': canonicalGachaCode,
      'reactify': metadata.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectCharacter &&
        other.id == id &&
        other.name == name &&
        other.canonicalGachaCode == canonicalGachaCode &&
        other.metadata == metadata;
  }

  @override
  int get hashCode => Object.hash(id, name, canonicalGachaCode, metadata);
}

String validatedProjectName(String value, {required String field}) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 160) {
    throw ProjectFailure(
      code: ProjectErrorCode.invalidName,
      message: '$field must contain 1-160 non-whitespace characters.',
      field: field,
    );
  }
  if (normalized.runes.any((value) => value < 0x20 || value == 0x7f)) {
    throw ProjectFailure(
      code: ProjectErrorCode.invalidName,
      message: '$field cannot contain control characters.',
      field: field,
    );
  }
  return normalized;
}

String validatedCharacterName(String value) {
  final normalized = validatedProjectName(value, field: 'character.name');
  if (normalized.contains('|')) {
    throw const ProjectFailure(
      code: ProjectErrorCode.invalidName,
      message: 'character.name cannot contain the Gacha field delimiter.',
      field: 'character.name',
    );
  }
  return normalized;
}

Map<String, Object?> _validateExtensions(Map<String, Object?> extensions) {
  if (extensions.isNotEmpty) {
    throw const ProjectFailure(
      code: ProjectErrorCode.invalidMetadata,
      message:
          'Character extensions are not supported in this project version.',
      field: 'extensions',
    );
  }
  return const {};
}

List<String> _validatedAssetIds(List<String> values) {
  final unique = <String>{};
  for (var index = 0; index < values.length; index += 1) {
    final value = _validatedReference(values[index], 'customAssetIds[$index]');
    if (!unique.add(value)) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidMetadata,
        message: 'customAssetIds cannot contain duplicate references.',
        field: 'customAssetIds[$index]',
        details: {'assetId': value},
      );
    }
  }
  return unique.toList(growable: false)..sort();
}

String _validatedReference(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 256 ||
      normalized.runes.any((rune) => rune < 0x21 || rune == 0x7f)) {
    throw ProjectFailure(
      code: ProjectErrorCode.invalidMetadata,
      message: '$field must be a non-empty reference without whitespace.',
      field: field,
    );
  }
  return normalized;
}

Map<String, Object?> _jsonObject(Object? value, String field) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {for (final entry in value.entries) '${entry.key}': entry.value};
  }
  throw ProjectFailure(
    code: ProjectErrorCode.invalidMetadata,
    message: '$field must be a JSON object.',
    field: field,
  );
}

GachaCharacterState _immutableState(GachaCharacterState state) {
  return GachaCharacterState(
    rawFields: List<String>.unmodifiable(state.rawFields),
    metadataFields: Map<String, String>.unmodifiable(state.metadataFields),
    numericFields: Map<String, int>.unmodifiable(state.numericFields),
    colorFields: Map.unmodifiable(state.colorFields),
  );
}

bool _listEquals(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (!_jsonEquals(left[index], right[index])) {
      return false;
    }
  }
  return true;
}

bool _jsonEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is List && right is List) {
    return _listEquals(left, right);
  }
  if (left is Map && right is Map) {
    if (left.length != right.length || !left.keys.every(right.containsKey)) {
      return false;
    }
    for (final key in left.keys) {
      if (!_jsonEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _jsonHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(_jsonHash));
  }
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return Object.hashAll([
      for (final key in keys) Object.hash(key, _jsonHash(value[key])),
    ]);
  }
  return value.hashCode;
}
