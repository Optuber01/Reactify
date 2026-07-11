import '../../gacha/code/gacha_character_state.dart';
import '../../gacha/code/gacha_code_parser.dart';
import '../../gacha/code/gacha_field_schema.dart';
import 'project_character.dart';
import 'project_document.dart';
import 'project_error.dart';
import 'project_id.dart';

class CharacterReference {
  const CharacterReference({required this.entityId, required this.kind});

  final String entityId;
  final String kind;

  Map<String, Object?> toJson() => {'entityId': entityId, 'kind': kind};
}

class CharacterReferenceReport {
  const CharacterReferenceReport({
    required this.characterId,
    required this.references,
  });

  final CharacterId characterId;
  final List<CharacterReference> references;

  bool get canDelete => references.isEmpty;

  Map<String, Object?> toJson() {
    return {
      'characterId': characterId.value,
      'canDelete': canDelete,
      'referenceCount': references.length,
      'references': [for (final reference in references) reference.toJson()],
    };
  }
}

abstract interface class CharacterReferenceResolver {
  List<CharacterReference> referencesTo(
    ReactifyProject project,
    CharacterId characterId,
  );
}

class NoCharacterReferences implements CharacterReferenceResolver {
  const NoCharacterReferences();

  @override
  List<CharacterReference> referencesTo(
    ReactifyProject project,
    CharacterId characterId,
  ) => const [];
}

class ProjectCommandContext {
  const ProjectCommandContext({
    required this.parser,
    required this.schema,
    required this.referenceResolver,
  });

  final GachaCodeParser parser;
  final GachaFieldSchema schema;
  final CharacterReferenceResolver referenceResolver;

  CharacterReferenceReport referencesTo(
    ReactifyProject project,
    CharacterId characterId,
  ) {
    _requireCharacter(project, characterId);
    final unique = <String, CharacterReference>{};
    for (final reference in referenceResolver.referencesTo(
      project,
      characterId,
    )) {
      _validateCharacterReference(reference);
      unique['${reference.kind}\u0000${reference.entityId}'] = reference;
    }
    final references = unique.values.toList()
      ..sort((left, right) {
        final kindOrder = left.kind.compareTo(right.kind);
        return kindOrder != 0
            ? kindOrder
            : left.entityId.compareTo(right.entityId);
      });
    return CharacterReferenceReport(
      characterId: characterId,
      references: List.unmodifiable(references),
    );
  }
}

abstract interface class ProjectCommand {
  String get name;

  ReactifyProject apply(ReactifyProject project, ProjectCommandContext context);
}

class CreateCharacterCommand implements ProjectCommand {
  const CreateCharacterCommand({
    required this.id,
    required this.nameValue,
    required this.canonicalGachaCode,
    this.metadata,
  });

  final CharacterId id;
  final String nameValue;
  final String canonicalGachaCode;
  final ReactifyCharacterMetadata? metadata;

  @override
  String get name => 'createCharacter';

  @override
  ReactifyProject apply(
    ReactifyProject project,
    ProjectCommandContext context,
  ) {
    return _addCharacter(
      project,
      ProjectCharacter.fromCode(
        id: id,
        name: nameValue,
        canonicalGachaCode: canonicalGachaCode,
        metadata:
            metadata?.copyWith(origin: CharacterOrigin.created) ??
            ReactifyCharacterMetadata(origin: CharacterOrigin.created),
        parser: context.parser,
      ),
    );
  }
}

class ImportCharacterCommand implements ProjectCommand {
  const ImportCharacterCommand({
    required this.id,
    required this.nameValue,
    required this.canonicalGachaCode,
    this.metadata,
  });

  final CharacterId id;
  final String nameValue;
  final String canonicalGachaCode;
  final ReactifyCharacterMetadata? metadata;

  @override
  String get name => 'importCharacter';

  @override
  ReactifyProject apply(
    ReactifyProject project,
    ProjectCommandContext context,
  ) {
    return _addCharacter(
      project,
      ProjectCharacter.fromCode(
        id: id,
        name: nameValue,
        canonicalGachaCode: canonicalGachaCode,
        metadata:
            metadata?.copyWith(origin: CharacterOrigin.imported) ??
            ReactifyCharacterMetadata(origin: CharacterOrigin.imported),
        parser: context.parser,
      ),
    );
  }
}

class SelectCharacterCommand implements ProjectCommand {
  const SelectCharacterCommand(this.characterId);

  final CharacterId characterId;

  @override
  String get name => 'selectCharacter';

  @override
  ReactifyProject apply(
    ReactifyProject project,
    ProjectCommandContext context,
  ) {
    _requireCharacter(project, characterId);
    if (project.selectedCharacterId == characterId) {
      return project;
    }
    return project.copyWith(selectedCharacterId: characterId);
  }
}

class RenameCharacterCommand implements ProjectCommand {
  const RenameCharacterCommand({
    required this.characterId,
    required this.newName,
  });

  final CharacterId characterId;
  final String newName;

  @override
  String get name => 'renameCharacter';

  @override
  ReactifyProject apply(
    ReactifyProject project,
    ProjectCommandContext context,
  ) {
    final character = _requireCharacter(project, characterId);
    final normalized = validatedCharacterName(newName);
    final renamedState = context.schema.byName.containsKey('namex')
        ? character.gachaState.updateMetadataField(
            context.schema,
            'namex',
            normalized,
          )
        : character.gachaState;
    return _replaceCharacter(
      project,
      character.copyWith(name: normalized, gachaState: renamedState),
    );
  }
}

class DuplicateCharacterCommand implements ProjectCommand {
  const DuplicateCharacterCommand({
    required this.characterId,
    required this.newCharacterId,
    required this.newName,
  });

  final CharacterId characterId;
  final CharacterId newCharacterId;
  final String newName;

  @override
  String get name => 'duplicateCharacter';

  @override
  ReactifyProject apply(
    ReactifyProject project,
    ProjectCommandContext context,
  ) {
    final source = _requireCharacter(project, characterId);
    final normalized = validatedCharacterName(newName);
    final duplicateState = context.schema.byName.containsKey('namex')
        ? source.gachaState.updateMetadataField(
            context.schema,
            'namex',
            normalized,
          )
        : source.gachaState;
    return _addCharacter(
      project,
      source.copyWith(
        id: newCharacterId,
        name: normalized,
        gachaState: duplicateState,
      ),
    );
  }
}

class UpdateCharacterCommand implements ProjectCommand {
  const UpdateCharacterCommand({
    required this.characterId,
    required this.gachaState,
    this.metadata,
  });

  final CharacterId characterId;
  final GachaCharacterState gachaState;
  final ReactifyCharacterMetadata? metadata;

  @override
  String get name => 'updateCharacter';

  @override
  ReactifyProject apply(
    ReactifyProject project,
    ProjectCommandContext context,
  ) {
    final existing = _requireCharacter(project, characterId);
    GachaCharacterState validated;
    try {
      validated = context.parser.parse(gachaState.serializeCode());
    } on FormatException catch (error) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidCharacterCode,
        message: error.message.toString(),
        field: 'canonicalGachaCode',
      );
    }
    return _replaceCharacter(
      project,
      existing.copyWith(
        gachaState: validated,
        metadata: metadata ?? existing.metadata,
      ),
    );
  }
}

class ReplaceCharacterCodeCommand implements ProjectCommand {
  const ReplaceCharacterCodeCommand({
    required this.characterId,
    required this.canonicalGachaCode,
    this.metadata,
  });

  final CharacterId characterId;
  final String canonicalGachaCode;
  final ReactifyCharacterMetadata? metadata;

  @override
  String get name => 'replaceCharacterCode';

  @override
  ReactifyProject apply(
    ReactifyProject project,
    ProjectCommandContext context,
  ) {
    final existing = _requireCharacter(project, characterId);
    final replacement = ProjectCharacter.fromCode(
      id: characterId,
      name: existing.name,
      canonicalGachaCode: canonicalGachaCode,
      metadata: metadata ?? existing.metadata,
      parser: context.parser,
    );
    return _replaceCharacter(project, replacement);
  }
}

class DeleteCharacterCommand implements ProjectCommand {
  const DeleteCharacterCommand(this.characterId);

  final CharacterId characterId;

  @override
  String get name => 'deleteCharacter';

  @override
  ReactifyProject apply(
    ReactifyProject project,
    ProjectCommandContext context,
  ) {
    _requireCharacter(project, characterId);
    final report = context.referencesTo(project, characterId);
    if (!report.canDelete) {
      throw ProjectFailure(
        code: ProjectErrorCode.referenceConflict,
        message: 'Character is still referenced and cannot be deleted.',
        operation: name,
        details: {
          'characterId': characterId.value,
          'referenceCount': report.references.length,
          'references': report.toJson()['references'],
        },
      );
    }
    final nextCharacters = Map<CharacterId, ProjectCharacter>.of(
      project.characters,
    )..remove(characterId);
    CharacterId? nextSelection = project.selectedCharacterId;
    if (nextSelection == characterId) {
      final orderedIds = nextCharacters.keys.toList()
        ..sort((left, right) => left.value.compareTo(right.value));
      nextSelection = orderedIds.firstOrNull;
    }
    return project.copyWith(
      characters: nextCharacters,
      selectedCharacterId: nextSelection,
    );
  }
}

ReactifyProject _addCharacter(
  ReactifyProject project,
  ProjectCharacter character,
) {
  if (project.characters.containsKey(character.id)) {
    throw ProjectFailure(
      code: ProjectErrorCode.duplicateId,
      message: 'Character ID ${character.id.value} already exists.',
      field: 'character.id',
    );
  }
  return project.copyWith(
    characters: {...project.characters, character.id: character},
    selectedCharacterId: character.id,
  );
}

ReactifyProject _replaceCharacter(
  ReactifyProject project,
  ProjectCharacter character,
) {
  final existing = _requireCharacter(project, character.id);
  if (existing == character) {
    return project;
  }
  return project.copyWith(
    characters: {...project.characters, character.id: character},
  );
}

ProjectCharacter _requireCharacter(ReactifyProject project, CharacterId id) {
  final character = project.characters[id];
  if (character == null) {
    throw ProjectFailure(
      code: ProjectErrorCode.notFound,
      message: 'Character ${id.value} does not exist.',
      field: 'characterId',
      details: {'characterId': id.value},
    );
  }
  return character;
}

void _validateCharacterReference(CharacterReference reference) {
  for (final entry in {
    'reference.entityId': reference.entityId,
    'reference.kind': reference.kind,
  }.entries) {
    final value = entry.value;
    if (value.isEmpty ||
        value.length > 256 ||
        value.trim() != value ||
        value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      throw ProjectFailure(
        code: ProjectErrorCode.invalidReference,
        message: '${entry.key} must be a non-empty stable value.',
        field: entry.key,
        details: {'value': value},
      );
    }
  }
}
