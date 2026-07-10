import '../project/project.dart';
import 'project_command.dart';

enum ProjectEntityKind {
  asset,
  character,
  expression,
  pose,
  layout,
  reactionState,
  textPreset,
  speakerRule,
  timeline,
  bin,
  exportPreset,
}

class UpsertProjectEntityCommand implements ProjectCommand {
  UpsertProjectEntityCommand({required this.kind, required this.entity}) {
    _requireEntityKind(kind, entity);
  }

  final ProjectEntityKind kind;
  final Object entity;

  String get entityId => _entityId(kind, entity);

  factory UpsertProjectEntityCommand.fromJson(Map<String, Object?> json) {
    final kind = enumByName(ProjectEntityKind.values, jsonString(json, 'kind'));
    return UpsertProjectEntityCommand(
      kind: kind,
      entity: _parseEntity(kind, jsonMap(json['entity'])),
    );
  }

  @override
  String get type => 'entity.upsert';

  @override
  String get summary => 'Upsert ${kind.name} $entityId';

  @override
  Set<String> get affectedIds => {entityId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    return _setEntity(project, kind, entityId, entity);
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    final existing = _getEntity(project, kind, entityId);
    if (existing == null) {
      return RemoveProjectEntityCommand(kind: kind, entityId: entityId);
    }
    return UpsertProjectEntityCommand(kind: kind, entity: existing);
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    'entity': _entityJson(kind, entity),
    'kind': kind.name,
    'type': type,
  });
}

class RemoveProjectEntityCommand implements ProjectCommand {
  const RemoveProjectEntityCommand({
    required this.kind,
    required this.entityId,
  });

  final ProjectEntityKind kind;
  final String entityId;

  factory RemoveProjectEntityCommand.fromJson(Map<String, Object?> json) {
    return RemoveProjectEntityCommand(
      kind: enumByName(ProjectEntityKind.values, jsonString(json, 'kind')),
      entityId: jsonString(json, 'entityId'),
    );
  }

  @override
  String get type => 'entity.remove';

  @override
  String get summary => 'Remove ${kind.name} $entityId';

  @override
  Set<String> get affectedIds => {entityId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    if (_getEntity(project, kind, entityId) == null) {
      throw missingEntity(kind.name, entityId);
    }
    final referenceKind = _referenceKind(kind);
    final references = ProjectReferenceIndex.forProject(
      project,
    ).referencesTo(referenceKind, entityId);
    if (references.isNotEmpty) {
      final paths = references.map((reference) => reference.path).toList()
        ..sort();
      throw ProjectCommandException(
        'Cannot remove ${kind.name} $entityId because it is referenced by ${paths.join(', ')}.',
      );
    }
    return _removeEntity(project, kind, entityId);
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    final existing = _getEntity(project, kind, entityId);
    if (existing == null) {
      throw missingEntity(kind.name, entityId);
    }
    return UpsertProjectEntityCommand(kind: kind, entity: existing);
  }

  @override
  Map<String, Object?> toJson() =>
      canonicalJsonMap({'entityId': entityId, 'kind': kind.name, 'type': type});
}

Object _parseEntity(ProjectEntityKind kind, Map<String, Object?> json) {
  return switch (kind) {
    ProjectEntityKind.asset => ProjectAsset.fromJson(json),
    ProjectEntityKind.character => CharacterResource.fromJson(json),
    ProjectEntityKind.expression => ExpressionPreset.fromJson(json),
    ProjectEntityKind.pose => PosePreset.fromJson(json),
    ProjectEntityKind.layout => LayoutTemplate.fromJson(json),
    ProjectEntityKind.reactionState => ReactionState.fromJson(json),
    ProjectEntityKind.textPreset => TextPreset.fromJson(json),
    ProjectEntityKind.speakerRule => SpeakerRule.fromJson(json),
    ProjectEntityKind.timeline => ProjectTimeline.fromJson(json),
    ProjectEntityKind.bin => ProjectBin.fromJson(json),
    ProjectEntityKind.exportPreset => ExportPreset.fromJson(json),
  };
}

void _requireEntityKind(ProjectEntityKind kind, Object entity) {
  final valid = switch (kind) {
    ProjectEntityKind.asset => entity is ProjectAsset,
    ProjectEntityKind.character => entity is CharacterResource,
    ProjectEntityKind.expression => entity is ExpressionPreset,
    ProjectEntityKind.pose => entity is PosePreset,
    ProjectEntityKind.layout => entity is LayoutTemplate,
    ProjectEntityKind.reactionState => entity is ReactionState,
    ProjectEntityKind.textPreset => entity is TextPreset,
    ProjectEntityKind.speakerRule => entity is SpeakerRule,
    ProjectEntityKind.timeline => entity is ProjectTimeline,
    ProjectEntityKind.bin => entity is ProjectBin,
    ProjectEntityKind.exportPreset => entity is ExportPreset,
  };
  if (!valid) {
    throw ArgumentError('Entity does not match ${kind.name}.');
  }
}

String _entityId(ProjectEntityKind kind, Object entity) {
  _requireEntityKind(kind, entity);
  return switch (kind) {
    ProjectEntityKind.asset => (entity as ProjectAsset).id,
    ProjectEntityKind.character => (entity as CharacterResource).id,
    ProjectEntityKind.expression => (entity as ExpressionPreset).id,
    ProjectEntityKind.pose => (entity as PosePreset).id,
    ProjectEntityKind.layout => (entity as LayoutTemplate).id,
    ProjectEntityKind.reactionState => (entity as ReactionState).id,
    ProjectEntityKind.textPreset => (entity as TextPreset).id,
    ProjectEntityKind.speakerRule => (entity as SpeakerRule).id,
    ProjectEntityKind.timeline => (entity as ProjectTimeline).id,
    ProjectEntityKind.bin => (entity as ProjectBin).id,
    ProjectEntityKind.exportPreset => (entity as ExportPreset).id,
  };
}

Map<String, Object?> _entityJson(ProjectEntityKind kind, Object entity) {
  _requireEntityKind(kind, entity);
  return (entity as dynamic).toJson() as Map<String, Object?>;
}

Object? _getEntity(
  ReactifyProjectDocument project,
  ProjectEntityKind kind,
  String id,
) {
  return switch (kind) {
    ProjectEntityKind.asset => project.assets[id],
    ProjectEntityKind.character => project.characters[id],
    ProjectEntityKind.expression => project.expressions[id],
    ProjectEntityKind.pose => project.poses[id],
    ProjectEntityKind.layout => project.layouts[id],
    ProjectEntityKind.reactionState => project.reactionStates[id],
    ProjectEntityKind.textPreset => project.textPresets[id],
    ProjectEntityKind.speakerRule => project.speakerRules[id],
    ProjectEntityKind.timeline => project.timelines[id],
    ProjectEntityKind.bin => project.bins[id],
    ProjectEntityKind.exportPreset => project.exportPresets[id],
  };
}

ReactifyProjectDocument _setEntity(
  ReactifyProjectDocument project,
  ProjectEntityKind kind,
  String id,
  Object entity,
) {
  _requireEntityKind(kind, entity);
  return switch (kind) {
    ProjectEntityKind.asset => project.copyWith(
      assets: {...project.assets, id: entity as ProjectAsset},
    ),
    ProjectEntityKind.character => project.copyWith(
      characters: {...project.characters, id: entity as CharacterResource},
    ),
    ProjectEntityKind.expression => project.copyWith(
      expressions: {...project.expressions, id: entity as ExpressionPreset},
    ),
    ProjectEntityKind.pose => project.copyWith(
      poses: {...project.poses, id: entity as PosePreset},
    ),
    ProjectEntityKind.layout => project.copyWith(
      layouts: {...project.layouts, id: entity as LayoutTemplate},
    ),
    ProjectEntityKind.reactionState => project.copyWith(
      reactionStates: {...project.reactionStates, id: entity as ReactionState},
    ),
    ProjectEntityKind.textPreset => project.copyWith(
      textPresets: {...project.textPresets, id: entity as TextPreset},
    ),
    ProjectEntityKind.speakerRule => project.copyWith(
      speakerRules: {...project.speakerRules, id: entity as SpeakerRule},
    ),
    ProjectEntityKind.timeline => project.copyWith(
      timelines: {...project.timelines, id: entity as ProjectTimeline},
    ),
    ProjectEntityKind.bin => project.copyWith(
      bins: {...project.bins, id: entity as ProjectBin},
    ),
    ProjectEntityKind.exportPreset => project.copyWith(
      exportPresets: {...project.exportPresets, id: entity as ExportPreset},
    ),
  };
}

ReactifyProjectDocument _removeEntity(
  ReactifyProjectDocument project,
  ProjectEntityKind kind,
  String id,
) {
  switch (kind) {
    case ProjectEntityKind.asset:
      final values = {...project.assets}..remove(id);
      return project.copyWith(assets: values);
    case ProjectEntityKind.character:
      final values = {...project.characters}..remove(id);
      return project.copyWith(characters: values);
    case ProjectEntityKind.expression:
      final values = {...project.expressions}..remove(id);
      return project.copyWith(expressions: values);
    case ProjectEntityKind.pose:
      final values = {...project.poses}..remove(id);
      return project.copyWith(poses: values);
    case ProjectEntityKind.layout:
      final values = {...project.layouts}..remove(id);
      return project.copyWith(layouts: values);
    case ProjectEntityKind.reactionState:
      final values = {...project.reactionStates}..remove(id);
      return project.copyWith(reactionStates: values);
    case ProjectEntityKind.textPreset:
      final values = {...project.textPresets}..remove(id);
      return project.copyWith(textPresets: values);
    case ProjectEntityKind.speakerRule:
      final values = {...project.speakerRules}..remove(id);
      return project.copyWith(speakerRules: values);
    case ProjectEntityKind.timeline:
      final values = {...project.timelines}..remove(id);
      return project.copyWith(timelines: values);
    case ProjectEntityKind.bin:
      final values = {...project.bins}..remove(id);
      return project.copyWith(bins: values);
    case ProjectEntityKind.exportPreset:
      final values = {...project.exportPresets}..remove(id);
      return project.copyWith(exportPresets: values);
  }
}

ProjectReferenceKind _referenceKind(ProjectEntityKind kind) {
  return switch (kind) {
    ProjectEntityKind.asset => ProjectReferenceKind.asset,
    ProjectEntityKind.character => ProjectReferenceKind.character,
    ProjectEntityKind.expression => ProjectReferenceKind.expression,
    ProjectEntityKind.pose => ProjectReferenceKind.pose,
    ProjectEntityKind.layout => ProjectReferenceKind.layout,
    ProjectEntityKind.reactionState => ProjectReferenceKind.reactionState,
    ProjectEntityKind.textPreset => ProjectReferenceKind.textPreset,
    ProjectEntityKind.speakerRule => ProjectReferenceKind.speakerRule,
    ProjectEntityKind.timeline => ProjectReferenceKind.timeline,
    ProjectEntityKind.bin => ProjectReferenceKind.bin,
    ProjectEntityKind.exportPreset => ProjectReferenceKind.exportPreset,
  };
}
