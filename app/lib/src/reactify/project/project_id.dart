import 'dart:math';

import 'project_error.dart';

final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,127}$');

abstract class ProjectEntityId {
  const ProjectEntityId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ProjectEntityId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

class ProjectId extends ProjectEntityId {
  ProjectId(String value) : super(_validatedId(value, 'projectId'));
}

class CharacterId extends ProjectEntityId {
  CharacterId(String value) : super(_validatedId(value, 'characterId'));
}

class ProjectIdGenerator {
  ProjectIdGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  int _sequence = 0;

  ProjectId nextProjectId() => ProjectId(_next('project'));

  CharacterId nextCharacterId() => CharacterId(_next('character'));

  String _next(String prefix) {
    _sequence += 1;
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final sequence = _sequence.toRadixString(36);
    final entropy = List.generate(
      3,
      (_) => _random.nextInt(0x100000000).toRadixString(36).padLeft(7, '0'),
    ).join();
    return '${prefix}_${time}_${sequence}_$entropy';
  }
}

String _validatedId(String value, String field) {
  if (!_idPattern.hasMatch(value)) {
    throw ProjectFailure(
      code: ProjectErrorCode.invalidId,
      message:
          '$field must contain 1-128 lowercase letters, numbers, dots, underscores, or hyphens.',
      field: field,
      details: {'value': value},
    );
  }
  return value;
}
