import '../project/project.dart';
import 'project_command.dart';

class UpdateReactionCharacterCommand implements ProjectCommand {
  const UpdateReactionCharacterCommand({
    required this.reactionStateId,
    required this.instanceId,
    this.characterId,
    this.expressionId = absentValue,
    this.poseId = absentValue,
    this.visible,
    this.transform = absentValue,
  });

  final ReactionStateId reactionStateId;
  final String instanceId;
  final CharacterId? characterId;
  final Object? expressionId;
  final Object? poseId;
  final bool? visible;
  final Object? transform;

  factory UpdateReactionCharacterCommand.fromJson(Map<String, Object?> json) {
    return UpdateReactionCharacterCommand(
      reactionStateId: jsonString(json, 'reactionStateId'),
      instanceId: jsonString(json, 'instanceId'),
      characterId: jsonNullableString(json, 'characterId'),
      expressionId: json.containsKey('expressionId')
          ? json['expressionId']
          : absentValue,
      poseId: json.containsKey('poseId') ? json['poseId'] : absentValue,
      visible: jsonNullableBool(json, 'visible'),
      transform: json.containsKey('transform')
          ? (json['transform'] == null
                ? null
                : AffineTransform.fromJson(jsonMap(json['transform'])))
          : absentValue,
    );
  }

  @override
  String get type => 'reaction.character.update';

  @override
  String get summary => 'Update reaction character $instanceId';

  @override
  Set<String> get affectedIds => {reactionStateId, instanceId};

  @override
  ReactifyProjectDocument apply(ReactifyProjectDocument project) {
    final state = project.reactionStates[reactionStateId];
    if (state == null) {
      throw missingEntity('reaction state', reactionStateId);
    }
    var found = false;
    final characters = [
      for (final instance in state.characters)
        if (instance.id == instanceId)
          (() {
            found = true;
            return instance.copyWith(
              characterId: characterId,
              expressionId: expressionId,
              poseId: poseId,
              visible: visible,
              transform: transform,
            );
          })()
        else
          instance,
    ];
    if (!found) {
      throw missingEntity('reaction character instance', instanceId);
    }
    return project.copyWith(
      reactionStates: {
        ...project.reactionStates,
        state.id: state.copyWith(characters: characters),
      },
    );
  }

  @override
  ProjectCommand invert(ReactifyProjectDocument project) {
    final state = project.reactionStates[reactionStateId];
    if (state == null) {
      throw missingEntity('reaction state', reactionStateId);
    }
    final instance = state.characters
        .where((value) => value.id == instanceId)
        .firstOrNull;
    if (instance == null) {
      throw missingEntity('reaction character instance', instanceId);
    }
    return UpdateReactionCharacterCommand(
      reactionStateId: reactionStateId,
      instanceId: instanceId,
      characterId: characterId == null ? null : instance.characterId,
      expressionId: identical(expressionId, absentValue)
          ? absentValue
          : instance.expressionId,
      poseId: identical(poseId, absentValue) ? absentValue : instance.poseId,
      visible: visible == null ? null : instance.visible,
      transform: identical(transform, absentValue)
          ? absentValue
          : instance.transform,
    );
  }

  @override
  Map<String, Object?> toJson() => canonicalJsonMap({
    if (characterId != null) 'characterId': characterId,
    if (!identical(expressionId, absentValue)) 'expressionId': expressionId,
    'instanceId': instanceId,
    if (!identical(poseId, absentValue)) 'poseId': poseId,
    'reactionStateId': reactionStateId,
    if (!identical(transform, absentValue))
      'transform': (transform as AffineTransform?)?.toJson(),
    'type': type,
    if (visible != null) 'visible': visible,
  });
}
