import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'studio_project_controller.dart';

enum _WorkspaceAction { newProject, open, save, saveAs, recover, relink }

enum _TimelineAction { create, rename, duplicate, delete, import, export }

enum _DirtyChoice { cancel, discard, save }

class StudioWorkspaceBar extends StatelessWidget
    implements PreferredSizeWidget {
  const StudioWorkspaceBar({required this.controller, super.key});

  final StudioProjectController controller;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final compact = MediaQuery.sizeOf(context).width < 980;
        return AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              Flexible(
                child: Text(
                  '${controller.project.name}${controller.isDirty ? ' *' : ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 12),
                _StatusPill(
                  label: controller.workspaceStatus,
                  busy: controller.isBusy,
                ),
                if (controller.missingMedia.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.link_off, size: 16),
                    label: Text('${controller.missingMedia.length} missing'),
                    onPressed: () => _showRelinkDialog(context),
                  ),
                ],
              ],
            ],
          ),
          actions: [
            if (!compact)
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: controller.selectedTimelineId,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (final timeline in controller.project.timelines.values)
                      DropdownMenuItem(
                        value: timeline.id,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            timeline.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                  onChanged: controller.isBusy
                      ? null
                      : (id) {
                          if (id != null) controller.selectTimeline(id);
                        },
                ),
              ),
            PopupMenuButton<_TimelineAction>(
              tooltip: 'Timeline actions',
              icon: const Icon(Icons.video_library_outlined),
              enabled: !controller.isBusy,
              onSelected: (action) => _runTimelineAction(context, action),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _TimelineAction.create,
                  child: Text('New timeline'),
                ),
                PopupMenuItem(
                  value: _TimelineAction.rename,
                  child: Text('Rename timeline'),
                ),
                PopupMenuItem(
                  value: _TimelineAction.duplicate,
                  child: Text('Duplicate timeline'),
                ),
                PopupMenuItem(
                  value: _TimelineAction.delete,
                  child: Text('Delete timeline'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: _TimelineAction.import,
                  child: Text('Import timeline JSON'),
                ),
                PopupMenuItem(
                  value: _TimelineAction.export,
                  child: Text('Export timeline JSON'),
                ),
              ],
            ),
            PopupMenuButton<_WorkspaceAction>(
              tooltip: 'Project actions',
              enabled: !controller.isBusy,
              onSelected: (action) => _runWorkspaceAction(context, action),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _WorkspaceAction.newProject,
                  child: Text('New project'),
                ),
                const PopupMenuItem(
                  value: _WorkspaceAction.open,
                  child: Text('Open project'),
                ),
                PopupMenuItem(
                  value: _WorkspaceAction.save,
                  enabled: controller.isDirty,
                  child: const Text('Save'),
                ),
                const PopupMenuItem(
                  value: _WorkspaceAction.saveAs,
                  child: Text('Save as'),
                ),
                const PopupMenuItem(
                  value: _WorkspaceAction.recover,
                  child: Text('Recover project'),
                ),
                PopupMenuItem(
                  value: _WorkspaceAction.relink,
                  enabled: controller.missingMedia.isNotEmpty,
                  child: const Text('Relink missing media'),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }

  Future<void> _runWorkspaceAction(
    BuildContext context,
    _WorkspaceAction action,
  ) async {
    try {
      switch (action) {
        case _WorkspaceAction.newProject:
          if (!await _confirmDiscard(context)) return;
          if (!context.mounted) return;
          final name = await _requestName(
            context,
            'New project',
            'Project name',
          );
          if (name != null) controller.newProject(name: name);
        case _WorkspaceAction.open:
          if (!await _confirmDiscard(context)) return;
          if (!context.mounted) return;
          final location = await _pickProjectFile();
          if (location != null) await controller.openProject(location);
        case _WorkspaceAction.save:
          if (controller.projectLocation == null) {
            await _saveAs(context);
          } else {
            await controller.saveProject();
          }
        case _WorkspaceAction.saveAs:
          await _saveAs(context);
        case _WorkspaceAction.recover:
          if (!await _confirmDiscard(context)) return;
          if (!context.mounted) return;
          final location =
              controller.projectLocation ?? await _pickProjectFile();
          if (location != null) await controller.recoverProject(location);
        case _WorkspaceAction.relink:
          await _showRelinkDialog(context);
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _runTimelineAction(
    BuildContext context,
    _TimelineAction action,
  ) async {
    try {
      switch (action) {
        case _TimelineAction.create:
          final name = await _requestName(
            context,
            'New timeline',
            'Timeline name',
          );
          if (name != null) controller.createTimeline(name: name);
        case _TimelineAction.rename:
          final name = await _requestName(
            context,
            'Rename timeline',
            'Timeline name',
            initialValue: controller.selectedTimeline.name,
          );
          if (name != null) {
            controller.renameTimeline(controller.selectedTimelineId, name);
          }
        case _TimelineAction.duplicate:
          controller.duplicateTimeline(controller.selectedTimelineId);
        case _TimelineAction.delete:
          if (controller.project.timelines.length == 1) {
            throw StateError('A project must contain at least one timeline.');
          }
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete timeline?'),
              content: Text(
                'Delete “${controller.selectedTimeline.name}”? This can be undone until the project is closed.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            controller.deleteTimeline(controller.selectedTimelineId);
          }
        case _TimelineAction.import:
          final result = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['json'],
            withData: true,
          );
          final bytes = result?.files.single.bytes;
          if (bytes != null) {
            controller.importTimelineJson(utf8.decode(bytes));
          }
        case _TimelineAction.export:
          final timeline = controller.selectedTimeline;
          await FilePicker.saveFile(
            dialogTitle: 'Export timeline JSON',
            fileName: '${_fileSlug(timeline.name)}.timeline.json',
            type: FileType.custom,
            allowedExtensions: const ['json'],
            bytes: Uint8List.fromList(
              utf8.encode(controller.exportTimelineJson()),
            ),
          );
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<bool> _confirmDiscard(BuildContext context) async {
    if (!controller.isDirty) return true;
    final choice = await showDialog<_DirtyChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save your changes before continuing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _DirtyChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _DirtyChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _DirtyChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == _DirtyChoice.discard) return true;
    if (choice != _DirtyChoice.save || !context.mounted) return false;
    if (controller.projectLocation == null) return _saveAs(context);
    await controller.saveProject();
    return true;
  }

  Future<bool> _saveAs(BuildContext context) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Project workspace save locations are available in the desktop app.',
      );
    }
    final location = await FilePicker.saveFile(
      dialogTitle: 'Save Reactify project',
      fileName: '${_fileSlug(controller.project.name)}.reactify.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (location == null) return false;
    await controller.saveProjectAs(location);
    return true;
  }

  Future<String?> _pickProjectFile() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Project workspace file paths are available in the desktop app.',
      );
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'reactify'],
    );
    return result?.files.single.path;
  }

  Future<void> _showRelinkDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Missing media'),
        content: SizedBox(
          width: 560,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final diagnostic in controller.missingMedia)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link_off),
                  title: Text(
                    controller.project.assets[diagnostic.assetId]?.name ??
                        diagnostic.assetId,
                  ),
                  subtitle: Text(
                    diagnostic.resolvedLocation.isEmpty
                        ? diagnostic.storedUri
                        : diagnostic.resolvedLocation,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        final result = await FilePicker.pickFiles();
                        final path = result?.files.single.path;
                        if (path == null) return;
                        controller.relinkMissingMedia({
                          diagnostic.assetId: path,
                        });
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted) {
                          _showError(dialogContext, error);
                        }
                      }
                    },
                    child: const Text('Relink'),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<String?> _requestName(
    BuildContext context,
    String title,
    String label, {
    String initialValue = '',
  }) async {
    final textController = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = textController.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    textController.dispose();
    return result;
  }

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.busy});

  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 7),
          ],
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

String _fileSlug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('(^-+|-+\$)'), '');
  return slug.isEmpty ? 'untitled' : slug;
}
