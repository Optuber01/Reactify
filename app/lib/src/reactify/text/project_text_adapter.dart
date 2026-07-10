import 'package:flutter/widgets.dart' show TextDirection;

import '../project/project.dart';
import 'reaction_text.dart';
import 'reaction_text_renderer.dart';

class ProjectReactionTextAdapter {
  const ProjectReactionTextAdapter();

  ReactionTextStyle resolvePreset(
    ReactifyProjectDocument project,
    TextPresetId? presetId,
  ) {
    if (presetId == null) return const ReactionTextStyle();
    final chain = <TextPreset>[];
    final seen = <String>{};
    var currentId = presetId;
    while (seen.add(currentId)) {
      final preset = project.textPresets[currentId];
      if (preset == null) break;
      chain.add(preset);
      final parent = preset.parentPresetId;
      if (parent == null) break;
      currentId = parent;
    }
    var resolved = const ReactionTextStyle();
    for (final preset in chain.reversed) {
      resolved = resolved.merge(styleFromProject(preset.style));
    }
    return resolved;
  }

  List<ReactionSpeakerRule> speakerRules(ReactifyProjectDocument project) {
    final rules = project.speakerRules.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return [
      for (final rule in rules)
        ReactionSpeakerRule(
          speakerId: rule.speakerId,
          displayName: rule.displayName,
          aliases: rule.aliases,
          style: resolvePreset(
            project,
            rule.textPresetId,
          ).merge(styleFromProject(rule.styleOverride)),
        ),
    ];
  }

  ReactionDialogueDocument dialogueDocument(
    ReactifyProjectDocument project,
    RichTextTimelineClip clip,
  ) {
    final rulesById = project.speakerRules;
    SpeakerRule? defaultRule;
    for (final rule in project.speakerRules.values) {
      if (rule.isDefault) {
        defaultRule = rule;
        break;
      }
    }
    return ReactionDialogueDocument(
      lines: [
        for (final line in clip.lines)
          ReactionDialogueLine(
            id: line.id,
            text: line.text,
            speakerId:
                (line.speakerRuleId == null
                        ? defaultRule
                        : rulesById[line.speakerRuleId])
                    ?.speakerId,
            sourcePrefix: line.sourcePrefix,
            styleOverride: styleFromProject(
              clip.styleOverride,
            ).merge(styleFromProject(line.styleOverride)),
          ),
      ],
      issues: const [],
    );
  }

  ReactionTextLayout layoutClip({
    required ReactifyProjectDocument project,
    required ProjectTimeline timeline,
    required RichTextTimelineClip clip,
    required double maxWidth,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final rules = speakerRules(project);
    final stylesBySpeaker = {
      for (final rule in rules) rule.speakerId: rule.style,
    };
    return const ReactionTextBlockRenderer().layout(
      lines: dialogueDocument(project, clip).lines,
      maxWidth: maxWidth,
      projectStyle: resolvePreset(project, clip.textPresetId),
      timelineStyle: styleFromProject(
        TextStyleSpec.fromJson(timeline.styleOverrides),
      ),
      speakerStyle: (speakerId) => stylesBySpeaker[speakerId],
      textDirection: textDirection,
    );
  }

  ReactionTextStyle styleFromProject(TextStyleSpec style) {
    final result = ReactionTextStyle(
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      italic: style.italic,
      fillColor: _color(style.fillColor),
      outlineColor: _color(style.outlineColor),
      outlineWidth: style.outlineWidth,
      shadowColor: _color(style.shadow?.color),
      shadowOffsetX: style.shadow?.offsetX,
      shadowOffsetY: style.shadow?.offsetY,
      shadowSoftness: style.shadow?.softness,
      shadowOpacity: style.shadow?.opacity,
      glowColor: _color(style.glowColor ?? style.borderColor),
      glowSize: style.glowSize ?? style.borderWidth,
      tracking: style.tracking,
      lineSpacing: style.lineSpacing,
      alignment: switch (style.alignment) {
        TextAlignment.start => ReactionTextAlign.left,
        TextAlignment.center => ReactionTextAlign.center,
        TextAlignment.end => ReactionTextAlign.right,
        TextAlignment.justify || null => null,
      },
      capitalization: switch (style.capitalization) {
        TextCapitalization.unchanged => ReactionTextCapitalization.preserve,
        TextCapitalization.uppercase => ReactionTextCapitalization.uppercase,
        TextCapitalization.lowercase => ReactionTextCapitalization.lowercase,
        TextCapitalization.titleCase || null => null,
      },
    );
    result.validate();
    return result;
  }

  TextStyleSpec styleToProject(ReactionTextStyle style) {
    style.validate();
    return TextStyleSpec(
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      italic: style.italic,
      fillColor: _hex(style.fillColor),
      outlineColor: _hex(style.outlineColor),
      outlineWidth: style.outlineWidth,
      shadow:
          style.shadowColor == null &&
              style.shadowOffsetX == null &&
              style.shadowOffsetY == null &&
              style.shadowSoftness == null &&
              style.shadowOpacity == null
          ? null
          : TextShadowStyle(
              color: _hex(style.shadowColor),
              offsetX: style.shadowOffsetX,
              offsetY: style.shadowOffsetY,
              softness: style.shadowSoftness,
              opacity: style.shadowOpacity,
            ),
      glowColor: _hex(style.glowColor),
      glowSize: style.glowSize,
      tracking: style.tracking,
      lineSpacing: style.lineSpacing,
      alignment: switch (style.alignment) {
        ReactionTextAlign.left => TextAlignment.start,
        ReactionTextAlign.center => TextAlignment.center,
        ReactionTextAlign.right => TextAlignment.end,
        null => null,
      },
      capitalization: switch (style.capitalization) {
        ReactionTextCapitalization.preserve => TextCapitalization.unchanged,
        ReactionTextCapitalization.uppercase => TextCapitalization.uppercase,
        ReactionTextCapitalization.lowercase => TextCapitalization.lowercase,
        null => null,
      },
    );
  }

  int? _color(String? value) {
    if (value == null) return null;
    final normalized = value.trim().replaceFirst('#', '');
    if (normalized.length != 6 && normalized.length != 8) {
      throw FormatException('Invalid text color "$value".');
    }
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) throw FormatException('Invalid text color "$value".');
    return normalized.length == 6 ? 0xff000000 | parsed : parsed;
  }

  String? _hex(int? value) {
    if (value == null) return null;
    return '#${value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}
