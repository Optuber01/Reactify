import 'package:flutter/material.dart';

import '../commands/commands.dart';
import '../project/project.dart';
import '../studio/studio_project_controller.dart';

class ProjectBinBrowser extends StatefulWidget {
  const ProjectBinBrowser({
    super.key,
    required this.controller,
    this.onItemActivated,
  });

  final StudioProjectController controller;
  final ValueChanged<ProjectBinItem>? onItemActivated;

  @override
  State<ProjectBinBrowser> createState() => _ProjectBinBrowserState();
}

class _ProjectBinBrowserState extends State<ProjectBinBrowser> {
  final _searchController = TextEditingController();
  ProjectBinKind? _filter;
  String _query = '';
  String? _selectedId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final items = _items(widget.controller.project)
            .where(
              (item) =>
                  (_filter == null || item.kind == _filter) &&
                  (_query.isEmpty ||
                      item.searchText.contains(_query.toLowerCase())),
            )
            .toList();
        final selected = items
            .where((item) => item.id == _selectedId)
            .firstOrNull;
        return Material(
          color: const Color(0xFF111620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Text(
                  'Project bins',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search project resources',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: DropdownButtonFormField<ProjectBinKind?>(
                  initialValue: _filter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Resource type',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All resources'),
                    ),
                    for (final kind in ProjectBinKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(_kindLabel(kind)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              if (selected != null) _BinPreview(item: selected),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No matching resources'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemExtent: 58,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final references = ProjectReferenceIndex.forProject(
                            widget.controller.project,
                          ).referencesTo(item.referenceKind, item.id);
                          return ListTile(
                            selected: item.id == _selectedId,
                            dense: true,
                            leading: Icon(_kindIcon(item.kind), size: 20),
                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _kindLabel(item.kind),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Tooltip(
                              message: references.isEmpty
                                  ? 'Delete resource'
                                  : 'Used by ${references.length} project reference(s)',
                              child: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                onPressed: references.isEmpty
                                    ? () => _delete(item)
                                    : null,
                              ),
                            ),
                            onTap: () => setState(() => _selectedId = item.id),
                            onLongPress: () =>
                                widget.onItemActivated?.call(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _delete(ProjectBinItem item) {
    widget.controller.executeCommand(
      RemoveProjectEntityCommand(kind: item.entityKind, entityId: item.id),
    );
    setState(() {
      if (_selectedId == item.id) _selectedId = null;
    });
  }
}

class _BinPreview extends StatelessWidget {
  const _BinPreview({required this.item});

  final ProjectBinItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2230),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_kindIcon(item.kind), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.preview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class ProjectBinItem {
  const ProjectBinItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.entityKind,
    required this.referenceKind,
    required this.preview,
  });

  final String id;
  final String name;
  final ProjectBinKind kind;
  final ProjectEntityKind entityKind;
  final ProjectReferenceKind referenceKind;
  final String preview;

  String get searchText => '$id $name $preview'.toLowerCase();
}

List<ProjectBinItem> _items(ReactifyProjectDocument project) {
  final items = <ProjectBinItem>[
    for (final value in project.assets.values)
      ProjectBinItem(
        id: value.id,
        name: value.name,
        kind: ProjectBinKind.asset,
        entityKind: ProjectEntityKind.asset,
        referenceKind: ProjectReferenceKind.asset,
        preview: '${value.kind.name} · ${value.uri}',
      ),
    for (final value in project.characters.values)
      ProjectBinItem(
        id: value.id,
        name: value.name,
        kind: ProjectBinKind.character,
        entityKind: ProjectEntityKind.character,
        referenceKind: ProjectReferenceKind.character,
        preview: value.legacyGachaCode == null
            ? 'Reactify character'
            : 'Gacha-compatible character',
      ),
    for (final value in project.expressions.values)
      ProjectBinItem(
        id: value.id,
        name: value.name,
        kind: ProjectBinKind.expression,
        entityKind: ProjectEntityKind.expression,
        referenceKind: ProjectReferenceKind.expression,
        preview: value.characterId ?? 'Shared expression',
      ),
    for (final value in project.poses.values)
      ProjectBinItem(
        id: value.id,
        name: value.name,
        kind: ProjectBinKind.pose,
        entityKind: ProjectEntityKind.pose,
        referenceKind: ProjectReferenceKind.pose,
        preview: value.characterId ?? 'Shared pose',
      ),
    for (final value in project.layouts.values)
      ProjectBinItem(
        id: value.id,
        name: value.name,
        kind: ProjectBinKind.layout,
        entityKind: ProjectEntityKind.layout,
        referenceKind: ProjectReferenceKind.layout,
        preview: '${value.placements.length} placement(s)',
      ),
    for (final value in project.reactionStates.values)
      ProjectBinItem(
        id: value.id,
        name: value.name,
        kind: ProjectBinKind.reactionState,
        entityKind: ProjectEntityKind.reactionState,
        referenceKind: ProjectReferenceKind.reactionState,
        preview: '${value.characters.length} character(s)',
      ),
    for (final value in project.textPresets.values)
      ProjectBinItem(
        id: value.id,
        name: value.name,
        kind: ProjectBinKind.textPreset,
        entityKind: ProjectEntityKind.textPreset,
        referenceKind: ProjectReferenceKind.textPreset,
        preview: value.category,
      ),
    for (final value in project.speakerRules.values)
      ProjectBinItem(
        id: value.id,
        name: value.displayName,
        kind: ProjectBinKind.speakerRule,
        entityKind: ProjectEntityKind.speakerRule,
        referenceKind: ProjectReferenceKind.speakerRule,
        preview: value.aliases.join(', '),
      ),
    for (final value in project.exportPresets.values)
      ProjectBinItem(
        id: value.id,
        name: value.name,
        kind: ProjectBinKind.exportPreset,
        entityKind: ProjectEntityKind.exportPreset,
        referenceKind: ProjectReferenceKind.exportPreset,
        preview:
            '${value.container.name} · ${value.canvas.width}×${value.canvas.height}',
      ),
  ];
  items.sort((left, right) {
    final kind = left.kind.index.compareTo(right.kind.index);
    return kind != 0 ? kind : left.name.compareTo(right.name);
  });
  return items;
}

String _kindLabel(ProjectBinKind kind) {
  return switch (kind) {
    ProjectBinKind.asset => 'Media and assets',
    ProjectBinKind.character => 'Characters',
    ProjectBinKind.expression => 'Expressions',
    ProjectBinKind.pose => 'Poses',
    ProjectBinKind.layout => 'Layouts',
    ProjectBinKind.reactionState => 'Reaction states',
    ProjectBinKind.textPreset => 'Text presets',
    ProjectBinKind.speakerRule => 'Speaker styles',
    ProjectBinKind.exportPreset => 'Export presets',
  };
}

IconData _kindIcon(ProjectBinKind kind) {
  return switch (kind) {
    ProjectBinKind.asset => Icons.perm_media_outlined,
    ProjectBinKind.character => Icons.person_outline,
    ProjectBinKind.expression => Icons.mood_outlined,
    ProjectBinKind.pose => Icons.accessibility_new_outlined,
    ProjectBinKind.layout => Icons.dashboard_customize_outlined,
    ProjectBinKind.reactionState => Icons.auto_awesome_motion_outlined,
    ProjectBinKind.textPreset => Icons.text_fields,
    ProjectBinKind.speakerRule => Icons.record_voice_over_outlined,
    ProjectBinKind.exportPreset => Icons.ios_share_outlined,
  };
}
