import 'package:flutter/material.dart';

import 'reaction_text.dart';
import 'reaction_text_renderer.dart';

class ReactionTextEditorValue {
  const ReactionTextEditorValue({
    required this.document,
    required this.preset,
    required this.speakers,
  });

  final ReactionDialogueDocument document;
  final ReactionTextPreset preset;
  final List<ReactionSpeakerRule> speakers;
}

class ReactionTextEditor extends StatefulWidget {
  const ReactionTextEditor({
    this.initialText = '',
    this.initialSpeakers = const [],
    this.onChanged,
    super.key,
  });

  final String initialText;
  final List<ReactionSpeakerRule> initialSpeakers;
  final ValueChanged<ReactionTextEditorValue>? onChanged;

  @override
  State<ReactionTextEditor> createState() => _ReactionTextEditorState();
}

class _ReactionTextEditorState extends State<ReactionTextEditor> {
  late final TextEditingController _controller;
  late List<ReactionSpeakerRule> _speakers;
  late ReactionDialogueDocument _document;
  final Set<String> _manualSpeakerLineIds = {};
  ReactionTextPreset _preset = ReactionTextPresetLibrary.allCharacterDialogue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _speakers = widget.initialSpeakers.isEmpty
        ? _defaultSpeakers
        : List.of(widget.initialSpeakers);
    _document = const ReactionDialogueParser().parse(
      _controller.text,
      speakers: _speakers,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse(String input) {
    final parsed = const ReactionDialogueParser().parse(
      input,
      speakers: _speakers,
    );
    final oldLines = _document.lines;
    final unusedOldIndexes = {for (var i = 0; i < oldLines.length; i++) i};
    final mergedLines = <ReactionDialogueLine>[];
    for (var index = 0; index < parsed.lines.length; index++) {
      final fresh = parsed.lines[index];
      int? oldIndex;
      for (final candidate in unusedOldIndexes) {
        final old = oldLines[candidate];
        if (old.text == fresh.text && old.sourcePrefix == fresh.sourcePrefix) {
          oldIndex = candidate;
          break;
        }
      }
      if (oldIndex == null && oldLines.length == parsed.lines.length) {
        oldIndex = index;
      }
      if (oldIndex == null && fresh.sourcePrefix != null) {
        final matches = unusedOldIndexes.where(
          (candidate) =>
              oldLines[candidate].sourcePrefix?.toLowerCase() ==
              fresh.sourcePrefix?.toLowerCase(),
        );
        if (matches.length == 1) oldIndex = matches.single;
      }
      if (oldIndex == null) {
        mergedLines.add(fresh);
        continue;
      }
      unusedOldIndexes.remove(oldIndex);
      final old = oldLines[oldIndex];
      mergedLines.add(
        ReactionDialogueLine(
          id: old.id,
          text: fresh.text,
          speakerId: _manualSpeakerLineIds.contains(old.id)
              ? old.speakerId
              : fresh.speakerId,
          sourcePrefix: fresh.sourcePrefix,
          styleOverride: old.styleOverride,
        ),
      );
    }
    final currentIds = mergedLines.map((line) => line.id).toSet();
    _manualSpeakerLineIds.removeWhere((id) => !currentIds.contains(id));
    setState(() {
      _document = ReactionDialogueDocument(
        lines: mergedLines,
        issues: parsed.issues,
      );
    });
    _emit();
  }

  void _setPreset(ReactionTextPreset? preset) {
    if (preset == null) return;
    setState(() => _preset = preset);
    _emit();
  }

  void _assignSpeaker(int lineIndex, String? speakerId) {
    final lines = List<ReactionDialogueLine>.of(_document.lines);
    _manualSpeakerLineIds.add(lines[lineIndex].id);
    lines[lineIndex] = lines[lineIndex].copyWith(speakerId: speakerId);
    setState(() {
      _document = ReactionDialogueDocument(
        lines: lines,
        issues: _document.issues
            .where(
              (issue) =>
                  issue.kind != ReactionDialogueIssueKind.unknownSpeaker ||
                  issue.lineIndex != lineIndex,
            )
            .toList(),
      );
    });
    _emit();
  }

  void _emit() {
    widget.onChanged?.call(
      ReactionTextEditorValue(
        document: _document,
        preset: _preset,
        speakers: _speakers,
      ),
    );
  }

  ReactionTextStyle? _speakerStyle(String? speakerId) {
    for (final speaker in _speakers) {
      if (speaker.speakerId == speakerId) return speaker.style;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final editor = _buildInputPanel(
          context,
          scrollable: constraints.maxWidth >= 800,
        );
        final preview = _buildPreviewPanel(context);
        if (constraints.maxWidth < 800) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [editor, const SizedBox(height: 16), preview],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 390, child: editor),
            const VerticalDivider(width: 1),
            Expanded(child: preview),
          ],
        );
      },
    );
  }

  Widget _buildInputPanel(BuildContext context, {required bool scrollable}) {
    final children = <Widget>[
      Text('Dialogue', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(
        'Enter one line per speaker. Prefixes and aliases are matched before the first colon.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<ReactionTextPreset>(
        initialValue: _preset,
        decoration: const InputDecoration(
          labelText: 'Text preset',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final preset in ReactionTextPresetLibrary.values)
            DropdownMenuItem(value: preset, child: Text(preset.name)),
        ],
        onChanged: _setPreset,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _controller,
        onChanged: _parse,
        minLines: 8,
        maxLines: 16,
        decoration: const InputDecoration(
          alignLabelWithHint: true,
          labelText: 'Multiline dialogue',
          hintText: 'Cassie: Kill them all...\nKai: What do I say?',
          border: OutlineInputBorder(),
        ),
      ),
      if (_document.issues.isNotEmpty) ...[
        const SizedBox(height: 16),
        for (final issue in _document.issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(issue.message)),
              ],
            ),
          ),
      ],
      if (_document.lines.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Line assignments',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < _document.lines.length; index++)
          _LineAssignment(
            line: _document.lines[index],
            speakers: _speakers,
            onChanged: (speakerId) => _assignSpeaker(index, speakerId),
          ),
      ],
    ];
    final child = scrollable
        ? ListView(padding: const EdgeInsets.all(16), children: children)
        : Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: child,
    );
  }

  Widget _buildPreviewPanel(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - 48).clamp(240.0, 1100.0)
            : 720.0;
        final contentWidth = (panelWidth - 40).clamp(200.0, 1060.0);
        final layout = const ReactionTextBlockRenderer().layout(
          lines: _document.lines,
          maxWidth: contentWidth,
          projectStyle: _preset.style,
          speakerStyle: _speakerStyle,
          textDirection: Directionality.of(context),
        );
        return ColoredBox(
          color: const Color(0xff11151d),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Container(
                  width: panelWidth,
                  constraints: const BoxConstraints(minHeight: 300),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xff202838),
                    border: Border.all(color: const Color(0xff465269)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: _document.lines.isEmpty
                      ? const Text(
                          'Dialogue preview appears here.',
                          style: TextStyle(color: Colors.white54),
                        )
                      : ReactionTextPreview(layout: layout),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LineAssignment extends StatelessWidget {
  const _LineAssignment({
    required this.line,
    required this.speakers,
    required this.onChanged,
  });

  final ReactionDialogueLine line;
  final List<ReactionSpeakerRule> speakers;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('${line.id}-${line.speakerId}'),
              initialValue: line.speakerId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Speaker',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Default')),
                for (final speaker in speakers)
                  DropdownMenuItem(
                    value: speaker.speakerId,
                    child: Text(speaker.displayName),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

const _defaultSpeakers = [
  ReactionSpeakerRule(
    speakerId: 'cassie',
    displayName: 'Cassie',
    aliases: ['Cass'],
    style: ReactionTextStyle(fillColor: 0xffffe082),
  ),
  ReactionSpeakerRule(
    speakerId: 'nephis',
    displayName: 'Nephis',
    aliases: ['Neph'],
    style: ReactionTextStyle(
      fillColor: 0xfffff8e1,
      glowColor: 0xffffd54f,
      glowSize: 3,
    ),
  ),
  ReactionSpeakerRule(
    speakerId: 'kai',
    displayName: 'Kai',
    aliases: [],
    style: ReactionTextStyle(fillColor: 0xffb3e5fc),
  ),
  ReactionSpeakerRule(
    speakerId: 'jet',
    displayName: 'Jet',
    aliases: [],
    style: ReactionTextStyle(fillColor: 0xffff8a80),
  ),
];
