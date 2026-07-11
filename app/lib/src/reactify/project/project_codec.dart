import 'dart:convert';

import '../../gacha/code/gacha_code_parser.dart';
import 'project_character.dart';
import 'project_document.dart';
import 'project_error.dart';
import 'project_id.dart';

class ProjectCodec {
  const ProjectCodec({required this.parser});

  final GachaCodeParser parser;

  String encode(ReactifyProject project) {
    try {
      project.validate();
      return '${const JsonEncoder.withIndent('  ').convert(_canonicalize(project.toJson()))}\n';
    } on ProjectFailure {
      rethrow;
    } catch (error) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidProject,
        message: 'Project could not be encoded as deterministic JSON.',
        operation: 'encode',
        details: {'runtimeType': error.runtimeType.toString()},
      );
    }
  }

  ReactifyProject decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidProject,
        message: 'Project file is not valid JSON: ${error.message}',
        operation: 'decode',
      );
    }
    try {
      final root = _object(decoded, 'root');
      final migrated = _migrate(root);
      return _decodeCurrent(migrated);
    } on ProjectFailure {
      rethrow;
    } catch (error) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidProject,
        message: 'Project data is malformed and could not be decoded.',
        operation: 'decode',
        details: {'runtimeType': error.runtimeType.toString()},
      );
    }
  }

  Map<String, Object?> _migrate(Map<String, Object?> root) {
    final rawVersion = root['schemaVersion'];
    final version = rawVersion == null
        ? 0
        : _integer(rawVersion, 'schemaVersion');
    if (version > reactifyProjectSchemaVersion) {
      throw ProjectFailure(
        code: ProjectErrorCode.unsupportedVersion,
        message:
            'Project schema $version is newer than supported schema $reactifyProjectSchemaVersion.',
        field: 'schemaVersion',
        details: {'found': version, 'supported': reactifyProjectSchemaVersion},
      );
    }
    if (version < 0) {
      throw const ProjectFailure(
        code: ProjectErrorCode.unsupportedVersion,
        message: 'Project schema version cannot be negative.',
        field: 'schemaVersion',
      );
    }
    final format = root['format'];
    if (version == 0 && format != null && format != reactifyProjectFormat) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidProject,
        message: 'Legacy project has an unrecognized format.',
        field: 'format',
        details: {'found': format},
      );
    }
    var migrated = Map<String, Object?>.of(root);
    var currentVersion = version;
    while (currentVersion < reactifyProjectSchemaVersion) {
      switch (currentVersion) {
        case 0:
          migrated = _migrateVersionZero(migrated);
        default:
          throw ProjectFailure(
            code: ProjectErrorCode.unsupportedVersion,
            message: 'No migration exists for project schema $currentVersion.',
            field: 'schemaVersion',
          );
      }
      currentVersion += 1;
    }
    return migrated;
  }

  Map<String, Object?> _migrateVersionZero(Map<String, Object?> root) {
    final characters = _list(root['characters'], 'characters');
    final migratedCharacters = <Object?>[];
    for (var index = 0; index < characters.length; index += 1) {
      final character = _object(characters[index], 'characters[$index]');
      final code = character['canonicalGachaCode'] ?? character['gachaCode'];
      if (code is! String) {
        throw ProjectFailure(
          code: ProjectErrorCode.invalidProject,
          message: 'Version 0 character is missing its Gacha code.',
          field: 'characters[$index].gachaCode',
        );
      }
      migratedCharacters.add({
        'id': character['id'],
        'name': character['name'],
        'canonicalGachaCode': code,
        'reactify':
            character['reactify'] ??
            {
              'origin': CharacterOrigin.imported.name,
              'nativeModelVersion': 1,
              'rigTemplateId': 'gacha_compat_2d_v1',
              'customAssetIds': const <Object?>[],
              'extensions': const <String, Object?>{},
            },
      });
    }
    return {
      'format': reactifyProjectFormat,
      'schemaVersion': 1,
      'id': root['id'],
      'name': root['name'],
      'revision': root['revision'] ?? 0,
      'selectedCharacterId': root['selectedCharacterId'],
      'characters': migratedCharacters,
    };
  }

  ReactifyProject _decodeCurrent(Map<String, Object?> root) {
    if (root['format'] != reactifyProjectFormat) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidProject,
        message: 'File is not a Reactify project.',
        field: 'format',
        details: {'found': root['format']},
      );
    }
    final version = _integer(root['schemaVersion'], 'schemaVersion');
    if (version != reactifyProjectSchemaVersion) {
      throw ProjectFailure(
        code: ProjectErrorCode.unsupportedVersion,
        message: 'Unsupported project schema $version.',
        field: 'schemaVersion',
      );
    }
    final characters = <CharacterId, ProjectCharacter>{};
    final rawCharacters = _list(root['characters'], 'characters');
    for (var index = 0; index < rawCharacters.length; index += 1) {
      final json = _object(rawCharacters[index], 'characters[$index]');
      final id = CharacterId(_string(json['id'], 'characters[$index].id'));
      if (characters.containsKey(id)) {
        throw ProjectFailure(
          code: ProjectErrorCode.duplicateId,
          message: 'Project contains duplicate character ID ${id.value}.',
          field: 'characters[$index].id',
        );
      }
      final metadata = ReactifyCharacterMetadata.fromJson(
        _object(json['reactify'], 'characters[$index].reactify'),
      );
      characters[id] = ProjectCharacter.fromCode(
        id: id,
        name: _string(json['name'], 'characters[$index].name'),
        canonicalGachaCode: _string(
          json['canonicalGachaCode'],
          'characters[$index].canonicalGachaCode',
        ),
        metadata: metadata,
        parser: parser,
      );
    }
    final selectedValue = root['selectedCharacterId'];
    if (selectedValue != null && selectedValue is! String) {
      throw const ProjectFailure(
        code: ProjectErrorCode.invalidProject,
        message: 'selectedCharacterId must be a string or null.',
        field: 'selectedCharacterId',
      );
    }
    return ReactifyProject(
      id: ProjectId(_string(root['id'], 'id')),
      name: _string(root['name'], 'name'),
      revision: _integer(root['revision'], 'revision'),
      characters: characters,
      selectedCharacterId: selectedValue == null
          ? null
          : CharacterId(selectedValue as String),
    );
  }
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw const ProjectFailure(
        code: ProjectErrorCode.invalidProject,
        message: 'Project JSON object keys must be strings.',
        operation: 'encode',
      );
    }
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return [for (final entry in value) _canonicalize(entry)];
  }
  return value;
}

Map<String, Object?> _object(Object? value, String field) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {for (final entry in value.entries) '${entry.key}': entry.value};
  }
  throw ProjectFailure(
    code: ProjectErrorCode.invalidProject,
    message: '$field must be a JSON object.',
    field: field,
  );
}

List<Object?> _list(Object? value, String field) {
  if (value is List) {
    return [for (final entry in value) entry];
  }
  throw ProjectFailure(
    code: ProjectErrorCode.invalidProject,
    message: '$field must be a JSON list.',
    field: field,
  );
}

String _string(Object? value, String field) {
  if (value is String) {
    return value;
  }
  throw ProjectFailure(
    code: ProjectErrorCode.invalidProject,
    message: '$field must be a string.',
    field: field,
  );
}

int _integer(Object? value, String field) {
  if (value is int) {
    return value;
  }
  throw ProjectFailure(
    code: ProjectErrorCode.invalidProject,
    message: '$field must be an integer.',
    field: field,
  );
}
