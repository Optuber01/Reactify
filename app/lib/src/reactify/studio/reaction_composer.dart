import 'package:flutter/material.dart';

import '../project/project.dart';
import 'studio_project_controller.dart';

class ReactionComposer extends StatefulWidget {
  const ReactionComposer({this.controller, super.key});

  final StudioProjectController? controller;

  @override
  State<ReactionComposer> createState() => _ReactionComposerState();
}

class _ReactionComposerState extends State<ReactionComposer> {
  late final StudioProjectController _controller =
      widget.controller ?? StudioProjectController();
  late final bool _ownsController = widget.controller == null;
  final Set<String> _selectedInstances = {};

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 850) {
              return _buildCompact(context);
            }
            return Column(
              children: [
                _ComposerToolbar(
                  controller: _controller,
                  onDuplicate: _controller.duplicateCurrentState,
                ),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 230, child: _buildStateLibrary(context)),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildCanvasPanel(context)),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 300, child: _buildInspector(context)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCompact(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          _ComposerToolbar(
            controller: _controller,
            onDuplicate: _controller.duplicateCurrentState,
            compact: true,
          ),
          const SizedBox(height: 12),
          SizedBox(height: 420, child: _buildCanvasPanel(context)),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'Reaction states',
            child: SizedBox(height: 220, child: _buildStateLibrary(context)),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'Selection',
            child: _buildInspector(context, embedded: true),
          ),
        ],
      ),
    );
  }

  Widget _buildStateLibrary(BuildContext context) {
    final states = _controller.project.reactionStates.values.toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('States', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final state in states)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                selected: state.id == _controller.selectedReactionStateId,
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                title: Text(state.name),
                subtitle: Text('${state.characters.length} characters'),
                onTap: () {
                  _selectedInstances.clear();
                  _controller.selectReactionState(state.id);
                },
              ),
            ),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: _controller.duplicateCurrentState,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Duplicate current'),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasPanel(BuildContext context) {
    final state = _controller.selectedReactionState;
    final layout = _controller.project.layouts[state.layoutId]!;
    return ColoredBox(
      color: const Color(0xFF090C12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${layout.canvas.width} × ${layout.canvas.height}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: layout.canvas.width / layout.canvas.height,
                  child: _ReactionCanvas(
                    project: _controller.project,
                    layout: layout,
                    state: state,
                    selectedIds: _selectedInstances,
                    onSelect: _toggleSelection,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspector(BuildContext context, {bool embedded = false}) {
    final state = _controller.selectedReactionState;
    final selected = state.characters
        .where((instance) => _selectedInstances.contains(instance.id))
        .toList();
    final content = ListView(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      children: [
        Text('Inspector', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (selected.isEmpty)
          const Text('Select one or more characters in the canvas.')
        else ...[
          Text('${selected.length} selected'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Apply expression',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'neutral', child: Text('Neutral')),
              DropdownMenuItem(value: 'happy', child: Text('Happy')),
              DropdownMenuItem(value: 'shock', child: Text('Shock')),
            ],
            onChanged: (value) {
              if (value != null) {
                _controller.applyExpressionNameToCharacters(
                  selected.map((instance) => instance.id),
                  value,
                );
              }
            },
          ),
          const SizedBox(height: 16),
          if (selected.length == 1)
            _SingleCharacterInspector(
              controller: _controller,
              instance: selected.single,
              layout: _controller.project.layouts[state.layoutId]!,
            ),
          const SizedBox(height: 12),
          for (final instance in selected)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _controller.project.characters[instance.characterId]!.name,
              ),
              subtitle: Text(
                _controller.project.expressions[instance.expressionId]?.name ??
                    'No expression',
              ),
              value: instance.visible,
              onChanged: (value) =>
                  _controller.setCharacterVisibility(instance.id, value),
            ),
        ],
      ],
    );
    if (embedded) return content;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: content,
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  void _toggleSelection(String id, bool additive) {
    setState(() {
      if (!additive) _selectedInstances.clear();
      if (!_selectedInstances.add(id) && additive) {
        _selectedInstances.remove(id);
      }
    });
  }
}

class _ComposerToolbar extends StatelessWidget {
  const _ComposerToolbar({
    required this.controller,
    required this.onDuplicate,
    this.compact = false,
  });

  final StudioProjectController controller;
  final VoidCallback onDuplicate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 18,
          vertical: 10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reaction Composer',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (!compact)
                    Text(
                      'Reuse states, expressions, poses, and layouts',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Undo',
              onPressed: controller.canUndo ? controller.undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: controller.canRedo ? controller.redo : null,
              icon: const Icon(Icons.redo),
            ),
            if (!compact)
              FilledButton.icon(
                onPressed: onDuplicate,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Duplicate state'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReactionCanvas extends StatelessWidget {
  const _ReactionCanvas({
    required this.project,
    required this.layout,
    required this.state,
    required this.selectedIds,
    required this.onSelect,
  });

  final ReactifyProjectDocument project;
  final LayoutTemplate layout;
  final ReactionState state;
  final Set<String> selectedIds;
  final void Function(String id, bool additive) onSelect;

  @override
  Widget build(BuildContext context) {
    final placements = {for (final item in layout.placements) item.id: item};
    return LayoutBuilder(
      builder: (context, constraints) {
        final sx = constraints.maxWidth / layout.canvas.width;
        final sy = constraints.maxHeight / layout.canvas.height;
        final media = layout.mediaRegion;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: const Color(0xFF202838),
            child: Stack(
              children: [
                if (media != null)
                  Positioned(
                    left: media.left * constraints.maxWidth,
                    top: media.top * constraints.maxHeight,
                    width: media.width * constraints.maxWidth,
                    height: media.height * constraints.maxHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0F17),
                        border: Border.all(color: const Color(0xFF53647D)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text(
                          'Imported edit / media region',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
                for (final instance in state.characters)
                  if (instance.visible)
                    _positionedCharacter(
                      context,
                      constraints,
                      sx,
                      sy,
                      instance,
                      placements[instance.layoutPlacementId],
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _positionedCharacter(
    BuildContext context,
    BoxConstraints constraints,
    double sx,
    double sy,
    ReactionCharacterInstance instance,
    LayoutPlacement? placement,
  ) {
    final transform = instance.transform ?? placement?.transform;
    final x = (transform?.tx ?? constraints.maxWidth / 2) * sx;
    final y = (transform?.ty ?? constraints.maxHeight / 2) * sy;
    final scale = ((transform?.a ?? 1) + (transform?.d ?? 1)) / 2;
    final character = project.characters[instance.characterId]!;
    final expression = project.expressions[instance.expressionId];
    final accent = _parseColor(character.metadata['accent'] as String?);
    final selected = selectedIds.contains(instance.id);
    return Positioned(
      left: x - 38 * scale,
      top: y - 38 * scale,
      child: GestureDetector(
        onTap: () => onSelect(instance.id, false),
        onLongPress: () => onSelect(instance.id, true),
        child: Transform.scale(
          scale: scale.clamp(0.45, 1.4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 76,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xE61A202B),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : accent,
                width: selected ? 3 : 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: accent.withValues(alpha: 0.22),
                  foregroundColor: accent,
                  child: Text(
                    character.name.substring(0, 1),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  character.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                Text(
                  expression?.name ?? 'Default',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _parseColor(String? value) {
    final hex = value?.replaceFirst('#', '') ?? '6EA8FE';
    return Color(int.parse('FF$hex', radix: 16));
  }
}

class _SingleCharacterInspector extends StatelessWidget {
  const _SingleCharacterInspector({
    required this.controller,
    required this.instance,
    required this.layout,
  });

  final StudioProjectController controller;
  final ReactionCharacterInstance instance;
  final LayoutTemplate layout;

  @override
  Widget build(BuildContext context) {
    final placement = layout.placements
        .where((item) => item.id == instance.layoutPlacementId)
        .firstOrNull;
    final transform =
        instance.transform ?? placement?.transform ?? const AffineTransform();
    final slug = instance.characterId.split('.').last;
    final expressions = controller.project.expressions.values
        .where((value) => value.characterId == instance.characterId)
        .toList();
    final poses = controller.project.poses.values
        .where((value) => value.characterId == instance.characterId)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${instance.id}-${instance.expressionId}'),
          initialValue: instance.expressionId,
          decoration: const InputDecoration(
            labelText: 'Expression',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final expression in expressions)
              DropdownMenuItem(
                value: expression.id,
                child: Text(expression.name),
              ),
          ],
          onChanged: (value) =>
              controller.setCharacterExpression(instance.id, value),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('${instance.id}-${instance.poseId}'),
          initialValue: instance.poseId,
          decoration: const InputDecoration(
            labelText: 'Pose',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final pose in poses)
              DropdownMenuItem(value: pose.id, child: Text(pose.name)),
          ],
          onChanged: (value) => controller.setCharacterPose(instance.id, value),
        ),
        const SizedBox(height: 12),
        Text('Position X ${transform.tx.round()}'),
        Slider(
          value: transform.tx.clamp(0, layout.canvas.width.toDouble()),
          min: 0,
          max: layout.canvas.width.toDouble(),
          onChanged: (_) {},
          onChangeEnd: (value) => controller.setCharacterTransform(
            instance.id,
            transform.copyWith(tx: value),
          ),
        ),
        Text('Position Y ${transform.ty.round()}'),
        Slider(
          value: transform.ty.clamp(0, layout.canvas.height.toDouble()),
          min: 0,
          max: layout.canvas.height.toDouble(),
          onChanged: (_) {},
          onChangeEnd: (value) => controller.setCharacterTransform(
            instance.id,
            transform.copyWith(ty: value),
          ),
        ),
        Text('Scale ${transform.a.toStringAsFixed(2)}'),
        Slider(
          value: transform.a.clamp(0.3, 1.5),
          min: 0.3,
          max: 1.5,
          onChanged: (_) {},
          onChangeEnd: (value) => controller.setCharacterTransform(
            instance.id,
            transform.copyWith(a: value, d: value),
          ),
        ),
        Text(
          'Character key: $slug',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
