import 'dart:collection';

import 'project_character.dart';
import 'project_error.dart';
import 'project_id.dart';

const String reactifyProjectFormat = 'reactify-project';
const int reactifyProjectSchemaVersion = 1;

class ReactifyProject {
  ReactifyProject({
    required this.id,
    required String name,
    required Map<CharacterId, ProjectCharacter> characters,
    this.selectedCharacterId,
    this.revision = 0,
  }) : name = validatedProjectName(name, field: 'project.name'),
       characters = UnmodifiableMapView(Map.of(characters)) {
    validate();
  }

  final ProjectId id;
  final String name;
  final Map<CharacterId, ProjectCharacter> characters;
  final CharacterId? selectedCharacterId;
  final int revision;

  factory ReactifyProject.empty({required ProjectId id, required String name}) {
    return ReactifyProject(id: id, name: name, characters: const {});
  }

  ProjectCharacter? get selectedCharacter =>
      selectedCharacterId == null ? null : characters[selectedCharacterId];

  void validate() {
    if (revision < 0) {
      throw const ProjectFailure(
        code: ProjectErrorCode.invalidProject,
        message: 'Project revision cannot be negative.',
        field: 'revision',
      );
    }
    for (final entry in characters.entries) {
      if (entry.key != entry.value.id) {
        throw ProjectFailure(
          code: ProjectErrorCode.invalidProject,
          message: 'Character map key does not match the character ID.',
          field: 'characters',
          details: {
            'mapId': entry.key.value,
            'characterId': entry.value.id.value,
          },
        );
      }
    }
    if (selectedCharacterId != null &&
        !characters.containsKey(selectedCharacterId)) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidProject,
        message: 'Selected character does not exist in this project.',
        field: 'selectedCharacterId',
        details: {'characterId': selectedCharacterId!.value},
      );
    }
  }

  ReactifyProject copyWith({
    String? name,
    Map<CharacterId, ProjectCharacter>? characters,
    Object? selectedCharacterId = _unchanged,
    int? revision,
  }) {
    return ReactifyProject(
      id: id,
      name: name ?? this.name,
      characters: characters ?? this.characters,
      selectedCharacterId: identical(selectedCharacterId, _unchanged)
          ? this.selectedCharacterId
          : selectedCharacterId as CharacterId?,
      revision: revision ?? this.revision,
    );
  }

  Map<String, Object?> toJson() {
    final orderedCharacters = characters.values.toList()
      ..sort((left, right) => left.id.value.compareTo(right.id.value));
    return {
      'format': reactifyProjectFormat,
      'schemaVersion': reactifyProjectSchemaVersion,
      'id': id.value,
      'name': name,
      'revision': revision,
      'selectedCharacterId': selectedCharacterId?.value,
      'characters': [
        for (final character in orderedCharacters) character.toJson(),
      ],
    };
  }
}

const Object _unchanged = Object();
