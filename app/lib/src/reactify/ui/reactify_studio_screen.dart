import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../gacha/code/gacha_character_state.dart';
import '../../gacha/code/gacha_code_parser.dart';
import '../../gacha/data/resolver_tables.dart';
import '../../gacha/render/character_renderer.dart';
import '../project/project_codec.dart';
import '../project/project_command.dart';
import '../project/project_controller.dart';
import '../project/project_document.dart';
import '../project/project_error.dart';
import '../project/project_file_store.dart';
import '../project/project_id.dart';
import '../render/character_render_service.dart';
import 'creator_controls.dart';
import 'production_scene_preview.dart';

const _ink = Color(0xFF171A19);
const _paper = Color(0xFFECE9DF);
const _canvas = Color(0xFFD8D5CB);
const _panel = Color(0xFFF8F5EA);
const _line = Color(0xFF343936);
const _signal = Color(0xFFD4FF32);
const _danger = Color(0xFFFF735C);

class ReactifyStudioScreen extends StatefulWidget {
  const ReactifyStudioScreen({super.key});

  @override
  State<ReactifyStudioScreen> createState() => _ReactifyStudioScreenState();
}

class _ReactifyStudioScreenState extends State<ReactifyStudioScreen> {
  final ProjectIdGenerator _ids = ProjectIdGenerator();
  final GachaAssetStore _assetStore = GachaAssetStore();
  ResolverTables? _tables;
  GachaCodeParser? _parser;
  ProjectFileStore? _store;
  CharacterRenderService? _renderService;
  ProjectController? _controller;
  CharacterRenderResult? _renderResult;
  String? _projectPath;
  String? _message;
  Object? _startupError;
  bool _busy = true;
  bool _operationBusy = false;
  bool _rendering = false;
  int _renderSerial = 0;
  late String _defaultCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _controller?.removeListener(_onProjectChanged);
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final results = await Future.wait<Object>([
        ResolverTables.loadForEditor(),
        rootBundle.loadString('fixtures/default_boy.gc.txt'),
      ]);
      final tables = results[0] as ResolverTables;
      final defaultCode = results[1] as String;
      final parser = GachaCodeParser(tables.schema);
      parser.parse(defaultCode);
      _tables = tables;
      _parser = parser;
      _defaultCode = defaultCode.trim();
      _store = ProjectFileStore(codec: ProjectCodec(parser: parser));
      _renderService = CharacterRenderService(
        tables: tables,
        assetStore: _assetStore,
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _startupError = error;
          _busy = false;
        });
      }
    }
  }

  ProjectController _newProject(String name) {
    final controller = ProjectController(
      project: ReactifyProject.empty(id: _ids.nextProjectId(), name: name),
      context: _commandContext,
    );
    final outcome = controller.execute(
      CreateCharacterCommand(
        id: _ids.nextCharacterId(),
        nameValue: 'Default Boy',
        canonicalGachaCode: _defaultCode,
      ),
    );
    if (outcome is ProjectRejected<ReactifyProject>) {
      throw outcome.failure;
    }
    return controller;
  }

  ProjectCommandContext get _commandContext => ProjectCommandContext(
    parser: _parser!,
    schema: _tables!.schema,
    referenceResolver: const NoCharacterReferences(),
  );

  void _installController(ProjectController controller, {String? path}) {
    _controller?.removeListener(_onProjectChanged);
    _controller = controller;
    _projectPath = path;
    _renderResult = null;
    controller.addListener(_onProjectChanged);
  }

  void _onProjectChanged(ReactifyProject project) {
    if (!mounted) {
      return;
    }
    setState(() {});
    _scheduleRender();
  }

  Future<void> _scheduleRender() async {
    final controller = _controller;
    final service = _renderService;
    final character = controller?.project.selectedCharacter;
    final serial = ++_renderSerial;
    if (character == null || service == null) {
      if (mounted) {
        setState(() {
          _rendering = false;
          _renderResult = null;
        });
      }
      return;
    }
    setState(() => _rendering = true);
    try {
      final result = await service.renderCharacter(
        characterId: character.id.value,
        state: character.gachaState,
      );
      if (!mounted || serial != _renderSerial) {
        return;
      }
      setState(() {
        _renderResult = result;
        _rendering = false;
        _message = null;
      });
    } catch (error) {
      if (!mounted || serial != _renderSerial) {
        return;
      }
      setState(() {
        _renderResult = null;
        _rendering = false;
        _message = 'Render failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const _StartupState(
        title: 'LOADING GACHA CREATOR',
        detail: 'Loading production renderer and the bundled 445-field base.',
      );
    }
    if (_startupError != null) {
      return _StartupState(
        title: 'GACHA CREATOR FAILED TO START',
        detail: '$_startupError',
        isError: true,
      );
    }
    if (_controller == null) {
      if (_operationBusy) {
        return _StartupState(
          title: 'OPENING PROJECT',
          detail: _message ?? 'Reading and validating project data.',
        );
      }
      return _ProjectLanding(onCreate: _createProject, onOpen: _open);
    }
    final controller = _controller!;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyZ, control: true): _UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, control: true): _RedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true): _SaveIntent(),
      },
      child: Actions(
        actions: {
          _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) => _undo()),
          _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) => _redo()),
          _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) => _save()),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  _StudioHeader(
                    controller: controller,
                    path: _projectPath,
                    busy: _operationBusy,
                    onNew: _createProject,
                    onOpen: _open,
                    onSave: _save,
                    onSaveAs: _saveAs,
                    onUndo: _undo,
                    onRedo: _redo,
                    onExportCode: _exportCode,
                    onExportPng: _renderResult == null ? null : _exportPng,
                    onExportSvg: _renderResult == null ? null : _exportSvg,
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 252,
                          child: _CharacterLibrary(
                            controller: controller,
                            onSelect: _selectCharacter,
                            onImport: _importCharacter,
                            onRename: _renameCharacter,
                            onDuplicate: _duplicateCharacter,
                            onDelete: _deleteCharacter,
                          ),
                        ),
                        Expanded(
                          child: _CanvasStage(
                            result: _renderResult,
                            rendering: _rendering,
                            message: _message,
                          ),
                        ),
                        SizedBox(
                          width: 318,
                          child: CharacterCreatorPanel(
                            tables: _tables!,
                            character: controller.project.selectedCharacter,
                            onNumericChanged: _updateNumeric,
                            onColorChanged: _updateColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    if (!(_controller?.isDirty ?? false)) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text(
              'The current project has changes that have not been saved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _createProject() async {
    if (!await _confirmDiscard() || !mounted) {
      return;
    }
    final name = await _askText(
      title: 'New Gacha project',
      label: 'Project name',
      initialValue: 'Untitled Gacha Project',
      confirmLabel: 'Create',
    );
    if (name == null || !mounted) {
      return;
    }
    try {
      _installController(_newProject(name));
      setState(() => _message = 'New project created from bundled base.');
      _scheduleRender();
    } catch (error) {
      _showFailure(error);
    }
  }

  Future<void> _open() async {
    if (!await _confirmDiscard()) {
      return;
    }
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open Reactify project',
      type: FileType.custom,
      allowedExtensions: const ['reactify'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    _setBusy(true, 'Opening project...');
    try {
      final opened = await _store!.open(path);
      final controller = ProjectController(
        project: opened.project,
        context: _commandContext,
        initiallySaved: !opened.requiresSave,
      );
      _installController(controller, path: opened.path);
      setState(() {
        _operationBusy = false;
        _message = opened.recovered
            ? 'Recovered ${opened.source.name}. Save to confirm recovery.'
            : 'Project opened.';
      });
      _scheduleRender();
    } catch (error) {
      _setBusy(false);
      _showFailure(error);
    }
  }

  Future<void> _save() async {
    final path = _projectPath;
    if (path == null) {
      return _saveAs();
    }
    await _saveTo(path);
  }

  Future<void> _saveAs() async {
    final suggested = '${_safeFileName(_controller!.project.name)}.reactify';
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save Reactify project',
      fileName: suggested,
      type: FileType.custom,
      allowedExtensions: const ['reactify'],
    );
    if (path != null) {
      await _saveTo(_withExtension(path, '.reactify'));
    }
  }

  Future<void> _saveTo(String path) async {
    _setBusy(true, 'Saving project...');
    final outcome = await _controller!.save(_store!, path);
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case ProjectSuccess<ProjectSaveResult>(:final value):
        setState(() {
          _operationBusy = false;
          _projectPath = value.path;
          _message = 'Saved revision ${value.revision}.';
        });
      case ProjectRejected<ProjectSaveResult>(:final failure):
        _setBusy(false);
        _showFailure(failure);
    }
  }

  void _selectCharacter(CharacterId id) {
    _runCommand(SelectCharacterCommand(id));
  }

  Future<void> _importCharacter() async {
    final code = await _askMultiline(
      title: 'Import Gacha character',
      label: 'Paste exactly 445 pipe-delimited fields',
    );
    if (code == null || !mounted) {
      return;
    }
    final name = await _askText(
      title: 'Name imported character',
      label: 'Character name',
      initialValue: 'Imported Character',
      confirmLabel: 'Import',
    );
    if (name == null) {
      return;
    }
    _runCommand(
      ImportCharacterCommand(
        id: _ids.nextCharacterId(),
        nameValue: name,
        canonicalGachaCode: code,
      ),
    );
  }

  Future<void> _renameCharacter() async {
    final character = _controller!.project.selectedCharacter;
    if (character == null) {
      return;
    }
    final name = await _askText(
      title: 'Rename character',
      label: 'Character name',
      initialValue: character.name,
      confirmLabel: 'Rename',
    );
    if (name != null) {
      _runCommand(
        RenameCharacterCommand(characterId: character.id, newName: name),
      );
    }
  }

  void _duplicateCharacter() {
    final character = _controller!.project.selectedCharacter;
    if (character == null) {
      return;
    }
    _runCommand(
      DuplicateCharacterCommand(
        characterId: character.id,
        newCharacterId: _ids.nextCharacterId(),
        newName: '${character.name} Copy',
      ),
    );
  }

  Future<void> _deleteCharacter() async {
    final character = _controller!.project.selectedCharacter;
    if (character == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${character.name}?'),
        content: const Text(
          'Gate 1 has no timeline or scene references. The guarded reference check will still run.',
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
      _runCommand(DeleteCharacterCommand(character.id));
    }
  }

  void _updateNumeric(String field, int value) {
    final character = _controller!.project.selectedCharacter;
    if (character == null) {
      return;
    }
    _updateState(
      character.gachaState.updateNumericField(_tables!.schema, field, value),
    );
  }

  void _updateColor(String field, Color value) {
    final character = _controller!.project.selectedCharacter;
    if (character == null) {
      return;
    }
    _updateState(
      character.gachaState.updateColorField(_tables!.schema, field, value),
    );
  }

  void _updateState(GachaCharacterState state) {
    final character = _controller!.project.selectedCharacter;
    if (character != null) {
      _runCommand(
        UpdateCharacterCommand(characterId: character.id, gachaState: state),
      );
    }
  }

  void _undo() {
    _handleOutcome(_controller!.undo());
  }

  void _redo() {
    _handleOutcome(_controller!.redo());
  }

  void _runCommand(ProjectCommand command) {
    _handleOutcome(_controller!.execute(command));
  }

  void _handleOutcome(ProjectOutcome<ReactifyProject> outcome) {
    if (outcome is ProjectRejected<ReactifyProject>) {
      _showFailure(outcome.failure);
    }
  }

  Future<void> _exportCode() async {
    final character = _controller!.project.selectedCharacter;
    if (character == null) {
      _showFailure('Select a character before exporting.');
      return;
    }
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export canonical Gacha code',
      fileName: '${_safeFileName(character.name)}.gc.txt',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (path == null) {
      return;
    }
    try {
      await File(path).writeAsString(character.canonicalGachaCode, flush: true);
      _showMessage('Canonical 445-field code exported.');
    } catch (error) {
      _showFailure(error);
    }
  }

  Future<void> _exportPng() async {
    final result = _renderResult;
    final service = _renderService;
    if (result == null || service == null) {
      _showFailure('Wait for the current character to finish rendering.');
      return;
    }
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export rendered character PNG',
      fileName: '${_safeFileName(result.character.name)}.png',
      type: FileType.custom,
      allowedExtensions: const ['png'],
    );
    if (path == null) {
      return;
    }
    try {
      final bytes = await service.exportPng(result);
      await File(_withExtension(path, '.png')).writeAsBytes(bytes, flush: true);
      _showMessage('PNG exported from the visible production scene.');
    } catch (error) {
      _showFailure(error);
    }
  }

  Future<void> _exportSvg() async {
    final result = _renderResult;
    final service = _renderService;
    if (result == null || service == null) {
      _showFailure('Wait for the current character to finish rendering.');
      return;
    }
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export rendered character SVG',
      fileName: '${_safeFileName(result.character.name)}.svg',
      type: FileType.custom,
      allowedExtensions: const ['svg'],
    );
    if (path == null) {
      return;
    }
    try {
      final svg = await service.exportSvg(result);
      await File(_withExtension(path, '.svg')).writeAsString(svg, flush: true);
      _showMessage('SVG exported from the visible production scene.');
    } catch (error) {
      _showFailure(error);
    }
  }

  Future<String?> _askText({
    required String title,
    required String label,
    required String initialValue,
    required String confirmLabel,
  }) async {
    final text = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (_) => Navigator.pop(context, text.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    text.dispose();
    return value?.trim().isEmpty == true ? null : value;
  }

  Future<String?> _askMultiline({
    required String title,
    required String label,
  }) async {
    final text = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 640,
          child: TextField(
            controller: text,
            autofocus: true,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(
              labelText: label,
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    text.dispose();
    return value?.trim().isEmpty == true ? null : value;
  }

  void _setBusy(bool value, [String? message]) {
    if (mounted) {
      setState(() {
        _operationBusy = value;
        if (message != null) {
          _message = message;
        }
      });
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      setState(() => _message = message);
    }
  }

  void _showFailure(Object error) {
    final message = error is ProjectFailure
        ? '${error.code.name}: ${error.message}'
        : '$error';
    if (mounted) {
      setState(() => _message = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: _danger),
      );
    }
  }
}

class _StudioHeader extends StatelessWidget {
  const _StudioHeader({
    required this.controller,
    required this.path,
    required this.busy,
    required this.onNew,
    required this.onOpen,
    required this.onSave,
    required this.onSaveAs,
    required this.onUndo,
    required this.onRedo,
    required this.onExportCode,
    required this.onExportPng,
    required this.onExportSvg,
  });

  final ProjectController controller;
  final String? path;
  final bool busy;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onExportCode;
  final VoidCallback? onExportPng;
  final VoidCallback? onExportSvg;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: _ink,
        border: Border(bottom: BorderSide(color: _signal, width: 3)),
      ),
      child: Row(
        children: [
          const Text(
            'REACTIFY',
            style: TextStyle(
              color: _signal,
              fontWeight: FontWeight.w900,
              fontSize: 21,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(width: 20),
          Container(width: 1, height: 34, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${controller.isDirty ? 'UNSAVED' : 'SAVED'}  /  REV ${project.revision}  /  ${path ?? 'NO FILE'}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: controller.isDirty ? _signal : Colors.white54,
                    fontSize: 10,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
          _HeaderButton(label: 'NEW', onPressed: busy ? null : onNew),
          _HeaderButton(label: 'OPEN', onPressed: busy ? null : onOpen),
          _HeaderButton(label: 'SAVE', onPressed: busy ? null : onSave),
          _HeaderButton(label: 'SAVE AS', onPressed: busy ? null : onSaveAs),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Undo',
            onPressed: controller.canUndo ? onUndo : null,
            color: Colors.white,
            icon: const Icon(Icons.undo, size: 19),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: controller.canRedo ? onRedo : null,
            color: Colors.white,
            icon: const Icon(Icons.redo, size: 19),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<VoidCallback>(
            tooltip: 'Export',
            color: _panel,
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: onExportCode,
                child: const Text('Canonical code'),
              ),
              if (onExportPng != null)
                PopupMenuItem(
                  value: onExportPng,
                  child: const Text('PNG image'),
                ),
              if (onExportSvg != null)
                PopupMenuItem(
                  value: onExportSvg,
                  child: const Text('SVG image'),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              color: _signal,
              child: const Text(
                'EXPORT',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: Colors.white70),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, letterSpacing: 0.8),
      ),
    );
  }
}

class _CharacterLibrary extends StatelessWidget {
  const _CharacterLibrary({
    required this.controller,
    required this.onSelect,
    required this.onImport,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final ProjectController controller;
  final ValueChanged<CharacterId> onSelect;
  final VoidCallback onImport;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    final characters = project.characters.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Container(
      color: _panel,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(index: '01', title: 'CAST LIBRARY'),
          Expanded(
            child: characters.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'NO CHARACTERS\nIMPORT A 445-FIELD CODE',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: characters.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final character = characters[index];
                      final selected =
                          character.id == project.selectedCharacterId;
                      return Material(
                        color: selected ? _ink : _paper,
                        child: InkWell(
                          onTap: () => onSelect(character.id),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  color: selected ? _signal : _ink,
                                  child: Text(
                                    '${index + 1}'.padLeft(2, '0'),
                                    style: TextStyle(
                                      color: selected ? _ink : _signal,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        character.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: selected ? Colors.white : _ink,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        character.metadata.origin.name
                                            .toUpperCase(),
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white54
                                              : Colors.black45,
                                          fontSize: 9,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('IMPORT CHARACTER'),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _LibraryAction(
                        label: 'RENAME',
                        onPressed: project.selectedCharacter == null
                            ? null
                            : onRename,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: _LibraryAction(
                        label: 'DUPLICATE',
                        onPressed: project.selectedCharacter == null
                            ? null
                            : onDuplicate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                _LibraryAction(
                  label: 'DELETE SELECTED',
                  onPressed: project.selectedCharacter == null
                      ? null
                      : onDelete,
                  danger: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryAction extends StatelessWidget {
  const _LibraryAction({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? const Color(0xFF9F2F22) : _ink,
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CanvasStage extends StatelessWidget {
  const _CanvasStage({
    required this.result,
    required this.rendering,
    required this.message,
  });

  final CharacterRenderResult? result;
  final bool rendering;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _canvas,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                margin: const EdgeInsets.all(36),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F0E4),
                  border: Border.all(color: _line, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      offset: Offset(12, 12),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: result == null
                    ? Center(
                        child: Text(
                          rendering
                              ? 'RESOLVING PRODUCTION SCENE'
                              : 'SELECT A CHARACTER',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      )
                    : ProductionScenePreview(
                        key: ValueKey(
                          '${result!.character.id}.${result!.resolvedScene.parts.length}',
                        ),
                        scene: result!.resolvedScene,
                        canvasSize: result!.scene.canvasSize,
                        backgroundColor: result!.backgroundColor,
                      ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            top: 16,
            child: _StageLabel(
              text: result == null
                  ? 'CREATOR PREVIEW / IDLE'
                  : 'CREATOR PREVIEW / ${result!.scene.canvasSize.width.toInt()} × ${result!.scene.canvasSize.height.toInt()} / ${result!.resolvedScene.parts.length} PARTS',
            ),
          ),
          if (rendering)
            const Positioned(
              top: 16,
              right: 18,
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3, color: _ink),
              ),
            ),
          if (message != null)
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                color: _ink,
                child: Text(
                  message!,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StageLabel extends StatelessWidget {
  const _StageLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      color: _signal,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.index, required this.title});

  final String index;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Text(
            index,
            style: const TextStyle(
              color: Color(0xFF777A75),
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x18717670)
      ..strokeWidth = 1;
    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StartupState extends StatelessWidget {
  const _StartupState({
    required this.title,
    required this.detail,
    this.isError = false,
  });

  final String title;
  final String detail;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ink,
      body: Center(
        child: Container(
          width: 540,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            border: Border.all(color: isError ? _danger : _signal, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isError ? _danger : _signal,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                detail,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              if (!isError) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(
                  color: _signal,
                  backgroundColor: Colors.white12,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectLanding extends StatelessWidget {
  const _ProjectLanding({required this.onCreate, required this.onOpen});

  final VoidCallback onCreate;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              color: _ink,
              padding: const EdgeInsets.all(56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'REACTIFY',
                    style: TextStyle(
                      color: _signal,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'GACHA\nCREATOR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 58,
                      height: 0.88,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(width: 88, height: 7, color: _signal),
                  const SizedBox(height: 22),
                  const SizedBox(
                    width: 440,
                    child: Text(
                      'Create canonical Gacha Club characters, then place the saved cast in Studio.',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 16,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'PROJECT FORMAT 01  /  445-FIELD CHARACTER CORE',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'PROJECT LIBRARY',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Start a Gacha project or reopen a saved .reactify file.',
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.35,
                      color: Color(0xFF555853),
                    ),
                  ),
                  const SizedBox(height: 40),
                  _LandingAction(
                    index: '01',
                    title: 'CREATE PROJECT',
                    detail:
                        'Begin with the verified bundled 445-field default character.',
                    onTap: onCreate,
                    emphasized: true,
                  ),
                  const SizedBox(height: 12),
                  _LandingAction(
                    index: '02',
                    title: 'OPEN PROJECT',
                    detail: 'Choose an existing .reactify project from disk.',
                    onTap: onOpen,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingAction extends StatelessWidget {
  const _LandingAction({
    required this.index,
    required this.title,
    required this.detail,
    required this.onTap,
    this.emphasized = false,
  });

  final String index;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasized ? _signal : _panel,
      shape: const BeveledRectangleBorder(
        side: BorderSide(color: _ink, width: 2),
        borderRadius: BorderRadius.only(topRight: Radius.circular(18)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Text(
                index,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      style: const TextStyle(fontSize: 11, height: 1.35),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

String _safeFileName(String value) {
  final normalized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  return normalized.isEmpty ? 'reactify-character' : normalized;
}

String _withExtension(String path, String extension) {
  return path.toLowerCase().endsWith(extension) ? path : '$path$extension';
}
