import 'project_model.dart';

enum ProjectReferenceKind {
  asset,
  character,
  expression,
  pose,
  layout,
  reactionState,
  textPreset,
  speakerRule,
  timeline,
  track,
  clip,
  bin,
  exportPreset,
}

enum ProjectValidationSeverity { error, warning }

class ProjectReference {
  const ProjectReference({
    required this.sourceKind,
    required this.sourceId,
    required this.path,
    required this.targetKind,
    required this.targetId,
  });

  final ProjectReferenceKind sourceKind;
  final String sourceId;
  final String path;
  final ProjectReferenceKind targetKind;
  final String targetId;
}

class ProjectValidationIssue {
  const ProjectValidationIssue({
    required this.code,
    required this.path,
    required this.message,
    this.severity = ProjectValidationSeverity.error,
  });

  final String code;
  final String path;
  final String message;
  final ProjectValidationSeverity severity;
}

class ProjectReferenceIndex {
  ProjectReferenceIndex._(this.references, this._byTarget);

  final List<ProjectReference> references;
  final Map<String, List<ProjectReference>> _byTarget;

  factory ProjectReferenceIndex.forProject(ReactifyProjectDocument project) {
    final references = <ProjectReference>[];

    void add({
      required ProjectReferenceKind sourceKind,
      required String sourceId,
      required String path,
      required ProjectReferenceKind targetKind,
      required String? targetId,
    }) {
      if (targetId == null || targetId.isEmpty) {
        return;
      }
      references.add(
        ProjectReference(
          sourceKind: sourceKind,
          sourceId: sourceId,
          path: path,
          targetKind: targetKind,
          targetId: targetId,
        ),
      );
    }

    for (final character in project.characters.values) {
      add(
        sourceKind: ProjectReferenceKind.character,
        sourceId: character.id,
        path: 'characters.${character.id}.thumbnailAssetId',
        targetKind: ProjectReferenceKind.asset,
        targetId: character.thumbnailAssetId,
      );
    }
    for (final expression in project.expressions.values) {
      add(
        sourceKind: ProjectReferenceKind.expression,
        sourceId: expression.id,
        path: 'expressions.${expression.id}.characterId',
        targetKind: ProjectReferenceKind.character,
        targetId: expression.characterId,
      );
    }
    for (final pose in project.poses.values) {
      add(
        sourceKind: ProjectReferenceKind.pose,
        sourceId: pose.id,
        path: 'poses.${pose.id}.characterId',
        targetKind: ProjectReferenceKind.character,
        targetId: pose.characterId,
      );
    }
    for (final layout in project.layouts.values) {
      add(
        sourceKind: ProjectReferenceKind.layout,
        sourceId: layout.id,
        path: 'layouts.${layout.id}.backgroundAssetId',
        targetKind: ProjectReferenceKind.asset,
        targetId: layout.backgroundAssetId,
      );
      add(
        sourceKind: ProjectReferenceKind.layout,
        sourceId: layout.id,
        path: 'layouts.${layout.id}.watermarkAssetId',
        targetKind: ProjectReferenceKind.asset,
        targetId: layout.watermarkAssetId,
      );
      for (var index = 0; index < layout.placements.length; index += 1) {
        final placement = layout.placements[index];
        add(
          sourceKind: ProjectReferenceKind.layout,
          sourceId: layout.id,
          path: 'layouts.${layout.id}.placements.$index.characterId',
          targetKind: ProjectReferenceKind.character,
          targetId: placement.characterId,
        );
      }
    }
    for (final state in project.reactionStates.values) {
      add(
        sourceKind: ProjectReferenceKind.reactionState,
        sourceId: state.id,
        path: 'reactionStates.${state.id}.layoutId',
        targetKind: ProjectReferenceKind.layout,
        targetId: state.layoutId,
      );
      add(
        sourceKind: ProjectReferenceKind.reactionState,
        sourceId: state.id,
        path: 'reactionStates.${state.id}.backgroundAssetId',
        targetKind: ProjectReferenceKind.asset,
        targetId: state.backgroundAssetId,
      );
      add(
        sourceKind: ProjectReferenceKind.reactionState,
        sourceId: state.id,
        path: 'reactionStates.${state.id}.media.assetId',
        targetKind: ProjectReferenceKind.asset,
        targetId: state.media.assetId,
      );
      for (var index = 0; index < state.characters.length; index += 1) {
        final character = state.characters[index];
        final path = 'reactionStates.${state.id}.characters.$index';
        add(
          sourceKind: ProjectReferenceKind.reactionState,
          sourceId: state.id,
          path: '$path.characterId',
          targetKind: ProjectReferenceKind.character,
          targetId: character.characterId,
        );
        add(
          sourceKind: ProjectReferenceKind.reactionState,
          sourceId: state.id,
          path: '$path.expressionId',
          targetKind: ProjectReferenceKind.expression,
          targetId: character.expressionId,
        );
        add(
          sourceKind: ProjectReferenceKind.reactionState,
          sourceId: state.id,
          path: '$path.poseId',
          targetKind: ProjectReferenceKind.pose,
          targetId: character.poseId,
        );
      }
    }
    for (final preset in project.textPresets.values) {
      add(
        sourceKind: ProjectReferenceKind.textPreset,
        sourceId: preset.id,
        path: 'textPresets.${preset.id}.parentPresetId',
        targetKind: ProjectReferenceKind.textPreset,
        targetId: preset.parentPresetId,
      );
    }
    for (final rule in project.speakerRules.values) {
      add(
        sourceKind: ProjectReferenceKind.speakerRule,
        sourceId: rule.id,
        path: 'speakerRules.${rule.id}.textPresetId',
        targetKind: ProjectReferenceKind.textPreset,
        targetId: rule.textPresetId,
      );
    }
    for (final timeline in project.timelines.values) {
      for (final track in timeline.tracks.values) {
        for (final clip in track.clips.values) {
          final path =
              'timelines.${timeline.id}.tracks.${track.id}.clips.${clip.id}';
          switch (clip) {
            case ReactionTimelineClip():
              add(
                sourceKind: ProjectReferenceKind.clip,
                sourceId: clip.id,
                path: '$path.reactionStateId',
                targetKind: ProjectReferenceKind.reactionState,
                targetId: clip.reactionStateId,
              );
            case VideoTimelineClip():
              add(
                sourceKind: ProjectReferenceKind.clip,
                sourceId: clip.id,
                path: '$path.assetId',
                targetKind: ProjectReferenceKind.asset,
                targetId: clip.assetId,
              );
              add(
                sourceKind: ProjectReferenceKind.clip,
                sourceId: clip.id,
                path: '$path.linkedClipId',
                targetKind: ProjectReferenceKind.clip,
                targetId: clip.linkedClipId,
              );
            case ImageTimelineClip():
              add(
                sourceKind: ProjectReferenceKind.clip,
                sourceId: clip.id,
                path: '$path.assetId',
                targetKind: ProjectReferenceKind.asset,
                targetId: clip.assetId,
              );
            case RichTextTimelineClip():
              add(
                sourceKind: ProjectReferenceKind.clip,
                sourceId: clip.id,
                path: '$path.textPresetId',
                targetKind: ProjectReferenceKind.textPreset,
                targetId: clip.textPresetId,
              );
              for (var index = 0; index < clip.lines.length; index += 1) {
                add(
                  sourceKind: ProjectReferenceKind.clip,
                  sourceId: clip.id,
                  path: '$path.lines.$index.speakerRuleId',
                  targetKind: ProjectReferenceKind.speakerRule,
                  targetId: clip.lines[index].speakerRuleId,
                );
              }
            case AudioTimelineClip():
              add(
                sourceKind: ProjectReferenceKind.clip,
                sourceId: clip.id,
                path: '$path.assetId',
                targetKind: ProjectReferenceKind.asset,
                targetId: clip.assetId,
              );
              add(
                sourceKind: ProjectReferenceKind.clip,
                sourceId: clip.id,
                path: '$path.linkedClipId',
                targetKind: ProjectReferenceKind.clip,
                targetId: clip.linkedClipId,
              );
            case WatermarkTimelineClip():
              add(
                sourceKind: ProjectReferenceKind.clip,
                sourceId: clip.id,
                path: '$path.assetId',
                targetKind: ProjectReferenceKind.asset,
                targetId: clip.assetId,
              );
          }
        }
      }
    }
    for (final bin in project.bins.values) {
      final targetKind = switch (bin.kind) {
        ProjectBinKind.asset => ProjectReferenceKind.asset,
        ProjectBinKind.character => ProjectReferenceKind.character,
        ProjectBinKind.expression => ProjectReferenceKind.expression,
        ProjectBinKind.pose => ProjectReferenceKind.pose,
        ProjectBinKind.layout => ProjectReferenceKind.layout,
        ProjectBinKind.reactionState => ProjectReferenceKind.reactionState,
        ProjectBinKind.textPreset => ProjectReferenceKind.textPreset,
        ProjectBinKind.speakerRule => ProjectReferenceKind.speakerRule,
        ProjectBinKind.exportPreset => ProjectReferenceKind.exportPreset,
      };
      for (var index = 0; index < bin.itemIds.length; index += 1) {
        add(
          sourceKind: ProjectReferenceKind.bin,
          sourceId: bin.id,
          path: 'bins.${bin.id}.itemIds.$index',
          targetKind: targetKind,
          targetId: bin.itemIds[index],
        );
      }
    }

    final byTarget = <String, List<ProjectReference>>{};
    for (final reference in references) {
      byTarget
          .putIfAbsent(
            _targetKey(reference.targetKind, reference.targetId),
            () => [],
          )
          .add(reference);
    }
    return ProjectReferenceIndex._(List.unmodifiable(references), {
      for (final entry in byTarget.entries)
        entry.key: List.unmodifiable(entry.value),
    });
  }

  List<ProjectReference> referencesTo(
    ProjectReferenceKind kind,
    String targetId,
  ) {
    return _byTarget[_targetKey(kind, targetId)] ?? const [];
  }

  Map<String, List<ProjectReference>> reverseReferences() {
    return Map.unmodifiable(_byTarget);
  }

  static String _targetKey(ProjectReferenceKind kind, String id) {
    return '${kind.name}:$id';
  }
}

class ReactifyProjectValidator {
  const ReactifyProjectValidator();

  List<ProjectValidationIssue> validate(ReactifyProjectDocument project) {
    final issues = <ProjectValidationIssue>[];
    if (project.schemaVersion != reactifyReactionProjectSchemaVersion) {
      issues.add(
        ProjectValidationIssue(
          code: 'schema.version',
          path: 'schemaVersion',
          message: 'Expected schema $reactifyReactionProjectSchemaVersion.',
        ),
      );
    }
    _validateId(project.id, 'id', issues);
    _validateMapIds(project.assets, (value) => value.id, 'assets', issues);
    _validateMapIds(
      project.characters,
      (value) => value.id,
      'characters',
      issues,
    );
    _validateMapIds(
      project.expressions,
      (value) => value.id,
      'expressions',
      issues,
    );
    _validateMapIds(project.poses, (value) => value.id, 'poses', issues);
    _validateMapIds(project.layouts, (value) => value.id, 'layouts', issues);
    _validateMapIds(
      project.reactionStates,
      (value) => value.id,
      'reactionStates',
      issues,
    );
    _validateMapIds(
      project.textPresets,
      (value) => value.id,
      'textPresets',
      issues,
    );
    _validateMapIds(
      project.speakerRules,
      (value) => value.id,
      'speakerRules',
      issues,
    );
    _validateMapIds(
      project.timelines,
      (value) => value.id,
      'timelines',
      issues,
    );
    _validateMapIds(project.bins, (value) => value.id, 'bins', issues);
    _validateMapIds(
      project.exportPresets,
      (value) => value.id,
      'exportPresets',
      issues,
    );

    final clipIds = <String>{};
    for (final timeline in project.timelines.values) {
      final timelinePath = 'timelines.${timeline.id}';
      if (timeline.durationFrames <= 0) {
        _issue(issues, 'timeline.duration', '$timelinePath.durationFrames');
      }
      _validateOrder(
        timeline.trackOrder,
        timeline.tracks.keys,
        '$timelinePath.trackOrder',
        issues,
      );
      _validateMapIds(
        timeline.tracks,
        (value) => value.id,
        '$timelinePath.tracks',
        issues,
      );
      for (final marker in timeline.markers.values) {
        if (marker.time.frame > timeline.durationFrames) {
          _issue(
            issues,
            'marker.outOfRange',
            '$timelinePath.markers.${marker.id}.time',
          );
        }
      }
      for (final track in timeline.tracks.values) {
        final trackPath = '$timelinePath.tracks.${track.id}';
        _validateOrder(
          track.clipOrder,
          track.clips.keys,
          '$trackPath.clipOrder',
          issues,
        );
        _validateMapIds(
          track.clips,
          (value) => value.id,
          '$trackPath.clips',
          issues,
        );
        for (final clip in track.clips.values) {
          final clipPath = '$trackPath.clips.${clip.id}';
          if (!clipIds.add(clip.id)) {
            issues.add(
              ProjectValidationIssue(
                code: 'clip.duplicateGlobalId',
                path: clipPath,
                message: 'Clip id ${clip.id} is not globally unique.',
              ),
            );
          }
          if (clip.trackType != track.type) {
            issues.add(
              ProjectValidationIssue(
                code: 'clip.trackType',
                path: clipPath,
                message:
                    '${clip.trackType.name} clip cannot be placed on ${track.type.name}.',
              ),
            );
          }
          if (clip.range.duration <= 0 ||
              clip.range.endExclusive.frame > timeline.durationFrames) {
            _issue(issues, 'clip.range', '$clipPath.range');
          }
          if (clip
              case VideoTimelineClip(sourceInFrame: final value) ||
                  AudioTimelineClip(sourceInFrame: final value)) {
            if (value < 0) {
              _issue(issues, 'clip.sourceRange', '$clipPath.sourceInFrame');
            }
          }
        }
      }
    }

    final references = ProjectReferenceIndex.forProject(project);
    for (final reference in references.references) {
      if (!_containsTarget(project, reference.targetKind, reference.targetId)) {
        issues.add(
          ProjectValidationIssue(
            code: 'reference.missing',
            path: reference.path,
            message:
                'Missing ${reference.targetKind.name} ${reference.targetId}.',
          ),
        );
      }
    }

    final defaultSpeakers = project.speakerRules.values
        .where((rule) => rule.isDefault)
        .length;
    if (defaultSpeakers > 1) {
      issues.add(
        const ProjectValidationIssue(
          code: 'speaker.multipleDefaults',
          path: 'speakerRules',
          message: 'Only one speaker rule may be the default.',
        ),
      );
    }
    _validateTextPresetCycles(project, issues);
    return List.unmodifiable(issues);
  }

  void _validateTextPresetCycles(
    ReactifyProjectDocument project,
    List<ProjectValidationIssue> issues,
  ) {
    for (final preset in project.textPresets.values) {
      final seen = <String>{preset.id};
      var current = preset.parentPresetId;
      while (current != null) {
        if (!seen.add(current)) {
          issues.add(
            ProjectValidationIssue(
              code: 'textPreset.cycle',
              path: 'textPresets.${preset.id}.parentPresetId',
              message: 'Text preset inheritance contains a cycle.',
            ),
          );
          break;
        }
        current = project.textPresets[current]?.parentPresetId;
      }
    }
  }

  bool _containsTarget(
    ReactifyProjectDocument project,
    ProjectReferenceKind kind,
    String id,
  ) {
    return switch (kind) {
      ProjectReferenceKind.asset => project.assets.containsKey(id),
      ProjectReferenceKind.character => project.characters.containsKey(id),
      ProjectReferenceKind.expression => project.expressions.containsKey(id),
      ProjectReferenceKind.pose => project.poses.containsKey(id),
      ProjectReferenceKind.layout => project.layouts.containsKey(id),
      ProjectReferenceKind.reactionState => project.reactionStates.containsKey(
        id,
      ),
      ProjectReferenceKind.textPreset => project.textPresets.containsKey(id),
      ProjectReferenceKind.speakerRule => project.speakerRules.containsKey(id),
      ProjectReferenceKind.timeline => project.timelines.containsKey(id),
      ProjectReferenceKind.track => project.timelines.values.any(
        (timeline) => timeline.tracks.containsKey(id),
      ),
      ProjectReferenceKind.clip => project.timelines.values.any(
        (timeline) =>
            timeline.tracks.values.any((track) => track.clips.containsKey(id)),
      ),
      ProjectReferenceKind.bin => project.bins.containsKey(id),
      ProjectReferenceKind.exportPreset => project.exportPresets.containsKey(
        id,
      ),
    };
  }

  void _validateMapIds<T>(
    Map<String, T> values,
    String Function(T value) idOf,
    String path,
    List<ProjectValidationIssue> issues,
  ) {
    for (final entry in values.entries) {
      _validateId(entry.key, '$path.${entry.key}', issues);
      if (entry.key != idOf(entry.value)) {
        issues.add(
          ProjectValidationIssue(
            code: 'id.keyMismatch',
            path: '$path.${entry.key}.id',
            message: 'Map key ${entry.key} does not match object id.',
          ),
        );
      }
    }
  }

  void _validateOrder(
    List<String> order,
    Iterable<String> keys,
    String path,
    List<ProjectValidationIssue> issues,
  ) {
    final expected = keys.toSet();
    final actual = order.toSet();
    if (actual.length != order.length ||
        actual.length != expected.length ||
        !actual.containsAll(expected)) {
      issues.add(
        ProjectValidationIssue(
          code: 'order.invalid',
          path: path,
          message: 'Order must contain every item exactly once.',
        ),
      );
    }
  }

  void _validateId(
    String id,
    String path,
    List<ProjectValidationIssue> issues,
  ) {
    if (id.trim().isEmpty) {
      _issue(issues, 'id.empty', path);
    }
  }

  void _issue(List<ProjectValidationIssue> issues, String code, String path) {
    issues.add(ProjectValidationIssue(code: code, path: path, message: code));
  }
}
