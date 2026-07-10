enum ReactionTextAlign { left, center, right }

enum ReactionTextCapitalization { preserve, uppercase, lowercase }

class ReactionTextStyle {
  const ReactionTextStyle({
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.italic,
    this.fillColor,
    this.outlineColor,
    this.outlineWidth,
    this.shadowColor,
    this.shadowOffsetX,
    this.shadowOffsetY,
    this.shadowSoftness,
    this.shadowOpacity,
    this.glowColor,
    this.glowSize,
    this.tracking,
    this.lineSpacing,
    this.alignment,
    this.capitalization,
  });

  final String? fontFamily;
  final double? fontSize;
  final int? fontWeight;
  final bool? italic;
  final int? fillColor;
  final int? outlineColor;
  final double? outlineWidth;
  final int? shadowColor;
  final double? shadowOffsetX;
  final double? shadowOffsetY;
  final double? shadowSoftness;
  final double? shadowOpacity;
  final int? glowColor;
  final double? glowSize;
  final double? tracking;
  final double? lineSpacing;
  final ReactionTextAlign? alignment;
  final ReactionTextCapitalization? capitalization;

  static const defaults = ReactionTextStyle(
    fontFamily: 'Arial',
    fontSize: 42,
    fontWeight: 700,
    italic: false,
    fillColor: 0xffffffff,
    outlineColor: 0xff000000,
    outlineWidth: 3,
    shadowColor: 0xff000000,
    shadowOffsetX: 3,
    shadowOffsetY: 3,
    shadowSoftness: 2,
    shadowOpacity: 0.85,
    glowColor: 0x00000000,
    glowSize: 0,
    tracking: 0,
    lineSpacing: 1.1,
    alignment: ReactionTextAlign.center,
    capitalization: ReactionTextCapitalization.preserve,
  );

  ReactionTextStyle merge(ReactionTextStyle? override) {
    if (override == null) return this;
    return ReactionTextStyle(
      fontFamily: override.fontFamily ?? fontFamily,
      fontSize: override.fontSize ?? fontSize,
      fontWeight: override.fontWeight ?? fontWeight,
      italic: override.italic ?? italic,
      fillColor: override.fillColor ?? fillColor,
      outlineColor: override.outlineColor ?? outlineColor,
      outlineWidth: override.outlineWidth ?? outlineWidth,
      shadowColor: override.shadowColor ?? shadowColor,
      shadowOffsetX: override.shadowOffsetX ?? shadowOffsetX,
      shadowOffsetY: override.shadowOffsetY ?? shadowOffsetY,
      shadowSoftness: override.shadowSoftness ?? shadowSoftness,
      shadowOpacity: override.shadowOpacity ?? shadowOpacity,
      glowColor: override.glowColor ?? glowColor,
      glowSize: override.glowSize ?? glowSize,
      tracking: override.tracking ?? tracking,
      lineSpacing: override.lineSpacing ?? lineSpacing,
      alignment: override.alignment ?? alignment,
      capitalization: override.capitalization ?? capitalization,
    );
  }

  Map<String, Object?> toJson() => {
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    'italic': italic,
    'fillColor': fillColor,
    'outlineColor': outlineColor,
    'outlineWidth': outlineWidth,
    'shadowColor': shadowColor,
    'shadowOffsetX': shadowOffsetX,
    'shadowOffsetY': shadowOffsetY,
    'shadowSoftness': shadowSoftness,
    'shadowOpacity': shadowOpacity,
    'glowColor': glowColor,
    'glowSize': glowSize,
    'tracking': tracking,
    'lineSpacing': lineSpacing,
    'alignment': alignment?.name,
    'capitalization': capitalization?.name,
  };

  factory ReactionTextStyle.fromJson(Map<String, Object?> json) {
    T? enumValue<T extends Enum>(List<T> values, Object? value) {
      if (value == null) return null;
      return values.where((item) => item.name == value).firstOrNull;
    }

    double? number(String key) => (json[key] as num?)?.toDouble();
    return ReactionTextStyle(
      fontFamily: json['fontFamily'] as String?,
      fontSize: number('fontSize'),
      fontWeight: (json['fontWeight'] as num?)?.toInt(),
      italic: json['italic'] as bool?,
      fillColor: (json['fillColor'] as num?)?.toInt(),
      outlineColor: (json['outlineColor'] as num?)?.toInt(),
      outlineWidth: number('outlineWidth'),
      shadowColor: (json['shadowColor'] as num?)?.toInt(),
      shadowOffsetX: number('shadowOffsetX'),
      shadowOffsetY: number('shadowOffsetY'),
      shadowSoftness: number('shadowSoftness'),
      shadowOpacity: number('shadowOpacity'),
      glowColor: (json['glowColor'] as num?)?.toInt(),
      glowSize: number('glowSize'),
      tracking: number('tracking'),
      lineSpacing: number('lineSpacing'),
      alignment: enumValue(ReactionTextAlign.values, json['alignment']),
      capitalization: enumValue(
        ReactionTextCapitalization.values,
        json['capitalization'],
      ),
    );
  }
}

class ReactionTextPreset {
  const ReactionTextPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.style,
  });

  final String id;
  final String name;
  final String category;
  final ReactionTextStyle style;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'style': style.toJson(),
  };

  factory ReactionTextPreset.fromJson(Map<String, Object?> json) {
    return ReactionTextPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      style: ReactionTextStyle.fromJson(
        Map<String, Object?>.from(json['style'] as Map),
      ),
    );
  }
}

class ReactionSpeakerRule {
  const ReactionSpeakerRule({
    required this.speakerId,
    required this.displayName,
    required this.aliases,
    required this.style,
  });

  final String speakerId;
  final String displayName;
  final List<String> aliases;
  final ReactionTextStyle style;

  Iterable<String> get matchingTokens sync* {
    yield speakerId;
    yield displayName;
    yield* aliases;
  }

  Map<String, Object?> toJson() => {
    'speakerId': speakerId,
    'displayName': displayName,
    'aliases': aliases,
    'style': style.toJson(),
  };

  factory ReactionSpeakerRule.fromJson(Map<String, Object?> json) {
    return ReactionSpeakerRule(
      speakerId: json['speakerId'] as String,
      displayName: json['displayName'] as String,
      aliases: (json['aliases'] as List).cast<String>(),
      style: ReactionTextStyle.fromJson(
        Map<String, Object?>.from(json['style'] as Map),
      ),
    );
  }
}

class ReactionDialogueLine {
  const ReactionDialogueLine({
    required this.id,
    required this.text,
    this.speakerId,
    this.sourcePrefix,
    this.styleOverride,
  });

  final String id;
  final String text;
  final String? speakerId;
  final String? sourcePrefix;
  final ReactionTextStyle? styleOverride;

  ReactionDialogueLine copyWith({
    String? text,
    Object? speakerId = _unset,
    Object? sourcePrefix = _unset,
    Object? styleOverride = _unset,
  }) {
    return ReactionDialogueLine(
      id: id,
      text: text ?? this.text,
      speakerId: identical(speakerId, _unset)
          ? this.speakerId
          : speakerId as String?,
      sourcePrefix: identical(sourcePrefix, _unset)
          ? this.sourcePrefix
          : sourcePrefix as String?,
      styleOverride: identical(styleOverride, _unset)
          ? this.styleOverride
          : styleOverride as ReactionTextStyle?,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'speakerId': speakerId,
    'sourcePrefix': sourcePrefix,
    'styleOverride': styleOverride?.toJson(),
  };

  factory ReactionDialogueLine.fromJson(Map<String, Object?> json) {
    final style = json['styleOverride'];
    return ReactionDialogueLine(
      id: json['id'] as String,
      text: json['text'] as String,
      speakerId: json['speakerId'] as String?,
      sourcePrefix: json['sourcePrefix'] as String?,
      styleOverride: style == null
          ? null
          : ReactionTextStyle.fromJson(Map<String, Object?>.from(style as Map)),
    );
  }
}

class ReactionDialogueDocument {
  const ReactionDialogueDocument({required this.lines, required this.issues});

  final List<ReactionDialogueLine> lines;
  final List<ReactionDialogueIssue> issues;

  Map<String, Object?> toJson() => {
    'lines': lines.map((line) => line.toJson()).toList(),
    'issues': issues.map((issue) => issue.toJson()).toList(),
  };
}

enum ReactionDialogueIssueKind { unknownSpeaker, duplicateAlias }

class ReactionDialogueIssue {
  const ReactionDialogueIssue({
    required this.kind,
    required this.lineIndex,
    required this.message,
    this.token,
  });

  final ReactionDialogueIssueKind kind;
  final int lineIndex;
  final String message;
  final String? token;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'lineIndex': lineIndex,
    'message': message,
    'token': token,
  };
}

class ReactionDialogueParser {
  const ReactionDialogueParser();

  ReactionDialogueDocument parse(
    String input, {
    required List<ReactionSpeakerRule> speakers,
    String idPrefix = 'line',
  }) {
    final tokenMap = <String, String>{};
    final issues = <ReactionDialogueIssue>[];
    for (final rule in speakers) {
      for (final token in rule.matchingTokens) {
        final normalized = _normalizeToken(token);
        if (normalized.isEmpty) continue;
        final existing = tokenMap[normalized];
        if (existing != null && existing != rule.speakerId) {
          issues.add(
            ReactionDialogueIssue(
              kind: ReactionDialogueIssueKind.duplicateAlias,
              lineIndex: -1,
              token: token,
              message: 'Alias "$token" is assigned to multiple speakers.',
            ),
          );
          continue;
        }
        tokenMap[normalized] = rule.speakerId;
      }
    }

    final sourceLines = input.replaceAll('\r\n', '\n').split('\n');
    final parsed = <ReactionDialogueLine>[];
    for (var index = 0; index < sourceLines.length; index++) {
      final source = sourceLines[index];
      if (source.trim().isEmpty) continue;
      final separator = _separatorIndex(source);
      String? prefix;
      String text = source.trim();
      String? speakerId;
      if (separator >= 0) {
        prefix = source.substring(0, separator).trim();
        text = source.substring(separator + 1).trimLeft();
        speakerId = tokenMap[_normalizeToken(prefix)];
        if (speakerId == null) {
          issues.add(
            ReactionDialogueIssue(
              kind: ReactionDialogueIssueKind.unknownSpeaker,
              lineIndex: parsed.length,
              token: prefix,
              message: 'Unknown speaker prefix "$prefix".',
            ),
          );
        }
      }
      parsed.add(
        ReactionDialogueLine(
          id: '$idPrefix-${parsed.length + 1}',
          text: text,
          speakerId: speakerId,
          sourcePrefix: prefix,
        ),
      );
    }
    return ReactionDialogueDocument(lines: parsed, issues: issues);
  }

  int _separatorIndex(String value) {
    final ascii = value.indexOf(':');
    final fullWidth = value.indexOf('：');
    if (ascii < 0) return fullWidth;
    if (fullWidth < 0) return ascii;
    return ascii < fullWidth ? ascii : fullWidth;
  }

  String _normalizeToken(String value) => value.trim().toLowerCase();
}

ReactionTextStyle resolveReactionLineStyle({
  ReactionTextStyle application = ReactionTextStyle.defaults,
  ReactionTextStyle? projectPreset,
  ReactionTextStyle? timelineOverride,
  ReactionTextStyle? speakerRule,
  ReactionTextStyle? lineOverride,
}) {
  return application
      .merge(projectPreset)
      .merge(timelineOverride)
      .merge(speakerRule)
      .merge(lineOverride);
}

String applyReactionCapitalization(
  String value,
  ReactionTextCapitalization capitalization,
) {
  return switch (capitalization) {
    ReactionTextCapitalization.preserve => value,
    ReactionTextCapitalization.uppercase => value.toUpperCase(),
    ReactionTextCapitalization.lowercase => value.toLowerCase(),
  };
}

const Object _unset = Object();

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

class ReactionTextPresetLibrary {
  static const allCharacterDialogue = ReactionTextPreset(
    id: 'all-character-dialogue',
    name: 'All Character Dialogue',
    category: 'character-dialogue',
    style: ReactionTextStyle(
      fontFamily: 'Arial Narrow',
      fontSize: 46,
      fontWeight: 800,
      fillColor: 0xffffffff,
      outlineColor: 0xff050505,
      outlineWidth: 4,
      shadowColor: 0xff000000,
      shadowOffsetX: 4,
      shadowOffsetY: 4,
      shadowSoftness: 2,
      shadowOpacity: 0.9,
      lineSpacing: 1.12,
      alignment: ReactionTextAlign.center,
    ),
  );

  static const audienceTalk = ReactionTextPreset(
    id: 'audience-talk',
    name: 'Audience Talk',
    category: 'viewer-text',
    style: ReactionTextStyle(
      fontFamily: 'Arial',
      fontSize: 40,
      fontWeight: 700,
      fillColor: 0xfffff4cf,
      outlineColor: 0xff131313,
      outlineWidth: 3,
      shadowColor: 0xff000000,
      shadowOffsetX: 3,
      shadowOffsetY: 3,
      shadowOpacity: 0.8,
      alignment: ReactionTextAlign.center,
    ),
  );

  static const copyrightNotice = ReactionTextPreset(
    id: 'copyright-notice',
    name: 'Copyright Notice',
    category: 'copyright-notice',
    style: ReactionTextStyle(
      fontFamily: 'Arial',
      fontSize: 34,
      fontWeight: 700,
      fillColor: 0xffffffff,
      outlineColor: 0xff000000,
      outlineWidth: 3,
      glowColor: 0xffef5350,
      glowSize: 5,
      alignment: ReactionTextAlign.center,
    ),
  );

  static const copyrightNoticeCompact = ReactionTextPreset(
    id: 'copyright-notice-compact',
    name: 'Copyright Notice Compact',
    category: 'copyright-notice',
    style: ReactionTextStyle(
      fontFamily: 'Arial',
      fontSize: 28,
      fontWeight: 700,
      fillColor: 0xffffffff,
      outlineColor: 0xff000000,
      outlineWidth: 2,
      shadowColor: 0xff000000,
      shadowOffsetX: 2,
      shadowOffsetY: 2,
      shadowOpacity: 0.8,
      alignment: ReactionTextAlign.center,
    ),
  );

  static const membersDisclaimer = ReactionTextPreset(
    id: 'members-disclaimer',
    name: 'Members Disclaimer and Shoutout',
    category: 'members',
    style: ReactionTextStyle(
      fontFamily: 'Arial',
      fontSize: 38,
      fontWeight: 700,
      fillColor: 0xffffe082,
      outlineColor: 0xff311b00,
      outlineWidth: 3,
      glowColor: 0xffffb300,
      glowSize: 4,
      alignment: ReactionTextAlign.center,
    ),
  );

  static const quickBreak = ReactionTextPreset(
    id: 'quick-break',
    name: 'Quick Break',
    category: 'break',
    style: ReactionTextStyle(
      fontFamily: 'Arial',
      fontSize: 52,
      fontWeight: 900,
      fillColor: 0xffffffff,
      outlineColor: 0xff0d47a1,
      outlineWidth: 5,
      glowColor: 0xff42a5f5,
      glowSize: 7,
      tracking: 1.5,
      alignment: ReactionTextAlign.center,
      capitalization: ReactionTextCapitalization.uppercase,
    ),
  );

  static const values = [
    allCharacterDialogue,
    audienceTalk,
    copyrightNotice,
    copyrightNoticeCompact,
    membersDisclaimer,
    quickBreak,
  ];
}
