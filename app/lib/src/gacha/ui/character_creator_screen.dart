import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../code/gacha_character_state.dart';
import '../code/gacha_code_parser.dart';
import '../code/gacha_field_schema.dart';
import '../data/resolver_tables.dart';
import '../../reactify/export/reactify_svg_exporter.dart';
import '../../reactify/legacy/gacha_to_reactify_adapter.dart';
import '../../reactify/model/reactify_document.dart';
import '../../reactify/project/project.dart' hide TextCapitalization;
import '../../reactify/render/reactify_render_bridge.dart';
import '../render/character_renderer.dart';
import '../render/gacha_game_canvas.dart';
import '../render/render_part.dart';
import '../render/transform_graph.dart';
import 'widgets/collapsible_sidebar.dart';
import 'widgets/canvas_preview.dart';
import 'debug_render_panel.dart';
import 'editor_helpers.dart';

class CharacterCreatorScreen extends StatefulWidget {
  const CharacterCreatorScreen({
    super.key,
    this.characterLibrary = const {},
    this.selectedLibraryCharacterId,
    this.onAddLibraryCharacter,
    this.onUpdateLibraryCharacter,
    this.onSelectLibraryCharacter,
    this.onDuplicateLibraryCharacter,
    this.onRenameLibraryCharacter,
    this.onDeleteLibraryCharacter,
  });

  final Map<CharacterId, CharacterResource> characterLibrary;
  final CharacterId? selectedLibraryCharacterId;
  final CharacterId Function(CharacterResource resource)? onAddLibraryCharacter;
  final void Function(CharacterResource resource)? onUpdateLibraryCharacter;
  final void Function(CharacterId id)? onSelectLibraryCharacter;
  final CharacterId Function(CharacterId id, {String? name})?
  onDuplicateLibraryCharacter;
  final void Function(CharacterId id, String name)? onRenameLibraryCharacter;
  final void Function(CharacterId id)? onDeleteLibraryCharacter;

  @override
  State<CharacterCreatorScreen> createState() => _CharacterCreatorScreenState();
}

class _CharacterCreatorScreenState extends State<CharacterCreatorScreen> {
  final GachaAssetStore _assetStore = GachaAssetStore();
  late final Future<ResolverTables> _tablesFuture =
      ResolverTables.loadForEditor();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<ResolverTables>(
          future: _tablesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load renderer data: ${snapshot.error}',
                  ),
                ),
              );
            }
            return _CharacterEditorShell(
              tables: snapshot.data!,
              assetStore: _assetStore,
              characterLibrary: widget.characterLibrary,
              selectedLibraryCharacterId: widget.selectedLibraryCharacterId,
              onAddLibraryCharacter: widget.onAddLibraryCharacter,
              onUpdateLibraryCharacter: widget.onUpdateLibraryCharacter,
              onSelectLibraryCharacter: widget.onSelectLibraryCharacter,
              onDuplicateLibraryCharacter: widget.onDuplicateLibraryCharacter,
              onRenameLibraryCharacter: widget.onRenameLibraryCharacter,
              onDeleteLibraryCharacter: widget.onDeleteLibraryCharacter,
            );
          },
        ),
      ),
    );
  }
}

class _CharacterEditorShell extends StatefulWidget {
  const _CharacterEditorShell({
    required this.tables,
    required this.assetStore,
    required this.characterLibrary,
    this.selectedLibraryCharacterId,
    this.onAddLibraryCharacter,
    this.onUpdateLibraryCharacter,
    this.onSelectLibraryCharacter,
    this.onDuplicateLibraryCharacter,
    this.onRenameLibraryCharacter,
    this.onDeleteLibraryCharacter,
  });

  final ResolverTables tables;
  final GachaAssetStore assetStore;
  final Map<CharacterId, CharacterResource> characterLibrary;
  final CharacterId? selectedLibraryCharacterId;
  final CharacterId Function(CharacterResource resource)? onAddLibraryCharacter;
  final void Function(CharacterResource resource)? onUpdateLibraryCharacter;
  final void Function(CharacterId id)? onSelectLibraryCharacter;
  final CharacterId Function(CharacterId id, {String? name})?
  onDuplicateLibraryCharacter;
  final void Function(CharacterId id, String name)? onRenameLibraryCharacter;
  final void Function(CharacterId id)? onDeleteLibraryCharacter;

  @override
  State<_CharacterEditorShell> createState() => _CharacterEditorShellState();
}

class _CharacterEditorShellState extends State<_CharacterEditorShell> {
  late final GachaCodeParser _parser = GachaCodeParser(widget.tables.schema);
  late final CharacterRenderer _renderer = CharacterRenderer(
    tables: widget.tables,
    assetStore: widget.assetStore,
  );
  late final GachaToReactifyAdapter _reactifyAdapter = GachaToReactifyAdapter(
    renderer: _renderer,
  );
  late final ReactifyRenderBridge _reactifyBridge = ReactifyRenderBridge(
    assetStore: widget.assetStore,
  );

  final GachaGameCanvas _game = GachaGameCanvas();
  final TextEditingController _codeController = TextEditingController();
  final Map<String, Future<String>> _fixtureCodeCache = {};
  final Map<String, String> _colorDrafts = {};
  final List<GachaCharacterState> _undoStates = [];
  final List<GachaCharacterState> _redoStates = [];

  String? _selectedCaseId;
  String _baselineLabel = 'fixture';
  String? _selectedField;
  GachaCharacterState? _baselineState;
  GachaCharacterState? _currentState;
  ReactifyCharacterDocument? _reactifyCharacter;
  ReactifySceneEditingState? _nativeEditor;
  int _reactifyResolvedPartCount = 0;
  ResolvedScene? _scene;
  bool _sceneLoading = false;
  bool _hideNativeHair = false;
  String? _messageText;
  bool _messageIsError = false;
  int _renderSerial = 0;
  int _libraryLoadSerial = 0;
  CharacterId? _activeLibraryCharacterId;
  bool _libraryDocumentHasNoLegacyState = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeEditor());
  }

  @override
  void didUpdateWidget(covariant _CharacterEditorShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedId = widget.selectedLibraryCharacterId;
    if (selectedId != oldWidget.selectedLibraryCharacterId &&
        selectedId != _activeLibraryCharacterId) {
      if (selectedId == null) {
        _activeLibraryCharacterId = null;
      } else {
        unawaited(_loadLibraryCharacter(selectedId));
      }
    }
  }

  @override
  void dispose() {
    _libraryLoadSerial += 1;
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _initializeEditor() async {
    final firstCase = widget.tables.editorFixtures.first;
    _selectedCaseId = firstCase.id;
    await _loadFixture(firstCase.id);
    final selectedId = widget.selectedLibraryCharacterId;
    if (mounted && selectedId != null) {
      await _loadLibraryCharacter(selectedId);
    }
  }

  void _handleStrokesDrawn(List<Offset> stroke) {
    final editor = _nativeEditor;
    final character = editor?.selectedCharacterDocument;
    final sceneCharacter = editor?.selectedSceneCharacter;
    if (editor == null || character == null || sceneCharacter == null) {
      setState(() {
        _messageText =
            'Captured stroke with ${stroke.length} points, but no native scene is loaded.';
        _messageIsError = true;
      });
      return;
    }
    final slot = _customDrawingSlotForStroke(stroke, character, sceneCharacter);
    _applyNativeEditor(
      editor
          .registerAsset(_registeredAssetForSlot(slot))
          .addCustomSlotToSelectedCharacter(slot),
      messageText:
          'Added a native vector drawing slot with ${stroke.length} points.',
    );
  }

  ReactifySlot _customDrawingSlotForStroke(
    List<Offset> screenStroke,
    ReactifyCharacterDocument character,
    ReactifySceneCharacter sceneCharacter,
  ) {
    final anchorWorld = _anchorWorldTransforms(character.rig);
    final headWorld =
        anchorWorld['head'] ??
        anchorWorld['torso'] ??
        const AffineMatrix.identity();
    final viewport = _game.rootTransform ?? const AffineMatrix.identity();
    final screenToHead = viewport
        .multiply(sceneCharacter.transform)
        .multiply(headWorld)
        .inverse();
    final headPoints = [
      for (final point in screenStroke) screenToHead.transformPoint(point),
    ];
    final bounds = _pointBounds(headPoints).inflate(2);
    final normalized = [
      for (final point in headPoints)
        {'x': point.dx - bounds.left, 'y': point.dy - bounds.top},
    ];
    final slotId = 'custom.drawing.${DateTime.now().microsecondsSinceEpoch}';
    final customSlotCount = character.slots
        .where((slot) => slot.kind == ReactifySlotKind.custom)
        .length;
    return ReactifySlot(
      id: slotId,
      kind: ReactifySlotKind.custom,
      family: 'custom',
      name: 'Drawing',
      anchorId: 'head',
      localTransform: AffineMatrix.translation(bounds.left, bounds.top),
      depth: 900000000 + customSlotCount,
      visible: true,
      asset: ReactifyAssetRef(
        id: '$slotId.asset',
        kind: ReactifyAssetKind.drawing,
        uri: 'reactify://drawing/$slotId',
        source: 'user',
        dimensions: bounds.size,
        metadata: {'source': 'user_drawing'},
      ),
      metadata: {
        'source': 'user_drawing',
        'drawingColor': '#00F5FF',
        'drawingStrokeWidth': 3.5,
        'drawingStrokes': [normalized],
      },
    );
  }

  ReactifyRegisteredAsset _registeredAssetForSlot(ReactifySlot slot) {
    final asset = slot.asset;
    if (asset == null) {
      throw StateError('Custom slot has no asset to register.');
    }
    return ReactifyRegisteredAsset(
      id: asset.id,
      kind: asset.kind,
      uri: asset.uri,
      source: asset.source,
      preserveVector: asset.preserveVector,
      dimensions: asset.dimensions,
      metadata: {...asset.metadata, 'slotId': slot.id},
    );
  }

  Rect _pointBounds(List<Offset> points) {
    if (points.isEmpty) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    var left = points.first.dx;
    var right = points.first.dx;
    var top = points.first.dy;
    var bottom = points.first.dy;
    for (final point in points.skip(1)) {
      if (point.dx < left) left = point.dx;
      if (point.dx > right) right = point.dx;
      if (point.dy < top) top = point.dy;
      if (point.dy > bottom) bottom = point.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Map<String, AffineMatrix> _anchorWorldTransforms(ReactifyRigTemplate rig) {
    final resolved = <String, AffineMatrix>{};
    AffineMatrix resolve(String id) {
      final existing = resolved[id];
      if (existing != null) {
        return existing;
      }
      final anchor = rig.anchors[id];
      if (anchor == null) {
        return const AffineMatrix.identity();
      }
      final parentId = anchor.parentId;
      final matrix = parentId == null
          ? anchor.localTransform
          : resolve(parentId).multiply(anchor.localTransform);
      resolved[id] = matrix;
      return matrix;
    }

    for (final id in rig.anchors.keys) {
      resolve(id);
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final currentState = _currentState;
    if (currentState == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final scene =
        _scene ??
        const ResolvedScene(
          parts: [],
          assets: {},
          worldBounds: Rect.zero,
          warnings: [],
        );
    final baselineState = _baselineState ?? currentState;
    final changes = currentState.diff(baselineState, widget.tables.schema);
    final selectedDescriptor = _selectedCaseId == null
        ? null
        : _fixtureDescriptorFor(_selectedCaseId!);
    final fixtureLabel = selectedDescriptor == null
        ? _baselineLabel
        : '${selectedDescriptor.displayName} (${selectedDescriptor.id})';
    final fixtureTags = selectedDescriptor?.featureTags ?? const <String>[];

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -0.6),
          radius: 1.4,
          colors: [Color(0xFF1B2236), Color(0xFF0C0F12)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderBar(
              selectedCaseId:
                  _selectedCaseId ?? widget.tables.editorFixtures.first.id,
              cases: widget.tables.editorFixtures,
              changeCount: changes.length,
              resolvedPartCount: scene.parts.length,
              nativeSlotCount: _reactifyCharacter?.slots.length ?? 0,
              nativePartCount: _reactifyResolvedPartCount,
              canUndo: _undoStates.isNotEmpty,
              canRedo: _redoStates.isNotEmpty,
              onUndo: _undo,
              onRedo: _redo,
              onChanged: _loadFixture,
            ),
            if (widget.characterLibrary.isNotEmpty ||
                widget.onAddLibraryCharacter != null) ...[
              const SizedBox(height: 10),
              _CharacterLibraryBar(
                characters: widget.characterLibrary,
                selectedCharacterId:
                    widget.selectedLibraryCharacterId ??
                    _activeLibraryCharacterId,
                onSelected: _selectLibraryCharacter,
                onAdd: widget.onAddLibraryCharacter == null
                    ? null
                    : _addCurrentToLibrary,
                onUpdate:
                    widget.onUpdateLibraryCharacter == null ||
                        widget.selectedLibraryCharacterId == null
                    ? null
                    : _updateSelectedLibraryCharacter,
                onDuplicate:
                    widget.onDuplicateLibraryCharacter == null ||
                        widget.selectedLibraryCharacterId == null
                    ? null
                    : _duplicateSelectedLibraryCharacter,
                onRename:
                    widget.onRenameLibraryCharacter == null ||
                        widget.selectedLibraryCharacterId == null
                    ? null
                    : _renameSelectedLibraryCharacter,
                onDelete:
                    widget.onDeleteLibraryCharacter == null ||
                        widget.selectedLibraryCharacterId == null
                    ? null
                    : _deleteSelectedLibraryCharacter,
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CanvasPreview(
                            scene: scene,
                            game: _game,
                            onStrokesDrawn: _handleStrokesDrawn,
                          ),
                        ),
                        if (_sceneLoading)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF64B5F6),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  CollapsibleSidebar(
                    title: 'Editing Properties',
                    child: _EditorInspector(
                      baselineLabel: _baselineLabel,
                      fixtureLabel: fixtureLabel,
                      fixtureTags: fixtureTags,
                      messageText: _messageText,
                      messageIsError: _messageIsError,
                      codeController: _codeController,
                      currentState: currentState,
                      baselineState: baselineState,
                      scene: scene,
                      nativeEditor: _nativeEditor,
                      schema: widget.tables.schema,
                      tables: widget.tables,
                      colorDrafts: _colorDrafts,
                      selectedField: _selectedField,
                      hideNativeHair: _hideNativeHair,
                      onImportPressed: _importFromTextarea,
                      onOpenCodeFilePressed: _openGachaCodeFile,
                      onSaveCodeFilePressed: _saveGachaCodeFile,
                      onExportPressed: _exportCurrentState,
                      onExportNativeSvgPressed: _exportNativeSvg,
                      onExportNativePngPressed: _exportNativePng,
                      onExportNativeJsonPressed: _exportNativeJson,
                      onImportNativeJsonPressed: _importNativeJson,
                      onOpenNativeJsonFilePressed: _openNativeJsonFile,
                      onResetToFixturePressed: _resetToSelectedFixture,
                      onResetToBaselinePressed: _resetToBaseline,
                      onNativeHairOverrideChanged: _toggleNativeHairOverride,
                      onNativeSceneCharacterAdded: _addNativeSceneCharacter,
                      onNativeSceneCharacterRemoved:
                          _removeSelectedNativeSceneCharacter,
                      onNativeRegisteredAssetAttached:
                          _attachRegisteredNativeAssetSlot,
                      onNativeSceneCharacterSelected: (sceneCharacterId) {
                        _selectNativeSceneCharacter(sceneCharacterId);
                      },
                      onNativeTransformChanged: (transform) {
                        _updateSelectedNativeTransform(transform);
                      },
                      onNumericFieldChanged: _updateNumericField,
                      onRawFieldChanged: _updateRawField,
                      onColorDraftChanged: _updateColorDraft,
                      onColorCommit: _commitColorField,
                      onFieldSelected: _selectField,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectLibraryCharacter(CharacterId id) {
    if (id == widget.selectedLibraryCharacterId) return;
    final onSelect = widget.onSelectLibraryCharacter;
    if (onSelect == null) {
      unawaited(_loadLibraryCharacter(id));
      return;
    }
    onSelect(id);
  }

  Future<void> _loadLibraryCharacter(CharacterId id) async {
    final resource = widget.characterLibrary[id];
    if (resource == null) return;
    final serial = ++_libraryLoadSerial;
    _activeLibraryCharacterId = id;
    final legacyCode = resource.legacyGachaCode?.trim();
    ReactifyCharacterDocument? document;
    try {
      if (resource.document['rig'] is Map &&
          resource.document['slots'] is List) {
        document = ReactifyCharacterDocument.fromJson(resource.document);
      }
    } catch (_) {
      document = null;
    }
    if (legacyCode != null && legacyCode.isNotEmpty) {
      try {
        final state = _parser.parse(legacyCode);
        _codeController.text = legacyCode;
        _colorDrafts.clear();
        _undoStates.clear();
        _redoStates.clear();
        await _setCurrentState(
          state,
          baselineState: state,
          baselineLabel: resource.name,
          selectedField: null,
          messageText: 'Loaded ${resource.name} from the project library.',
        );
      } catch (error) {
        if (!mounted || serial != _libraryLoadSerial) return;
        setState(() {
          _messageText = 'Could not load ${resource.name}: $error';
          _messageIsError = true;
        });
        return;
      }
    }
    if (!mounted || serial != _libraryLoadSerial) return;
    if (document != null) {
      final editor = _nativeEditor;
      if (editor == null) return;
      final currentDocument = document.copyWith(
        id: 'char.current',
        name: resource.name,
        legacyGachaCode: legacyCode,
      );
      await _applyNativeEditor(
        editor.copyWith(
          characters: {
            ...editor.characters,
            currentDocument.id: currentDocument,
          },
        ),
        messageText: 'Loaded ${resource.name} from the project library.',
      );
      _libraryDocumentHasNoLegacyState =
          legacyCode == null || legacyCode.isEmpty;
      return;
    }
    if (legacyCode == null || legacyCode.isEmpty) {
      _libraryDocumentHasNoLegacyState = false;
      setState(() {
        _baselineLabel = resource.name;
        _messageText =
            '${resource.name} is a project placeholder. Edit the current character and choose Update to replace it.';
        _messageIsError = false;
      });
    }
  }

  Future<void> _addCurrentToLibrary() async {
    final callback = widget.onAddLibraryCharacter;
    final document = _currentLibraryDocument;
    if (callback == null || document == null) return;
    final suggested = _suggestedCharacterName();
    final name = await _requestCharacterName(
      title: 'Add character to project',
      actionLabel: 'Add Character',
      initialValue: suggested,
    );
    if (!mounted || name == null) return;
    final temporaryId = 'character.${_librarySlug(name)}';
    late final CharacterId id;
    try {
      id = callback(
        _buildLibraryResource(id: temporaryId, name: name, document: document),
      );
    } catch (error) {
      _showLibraryError('add $name', error);
      return;
    }
    _activeLibraryCharacterId = id;
    setState(() {
      _baselineLabel = name;
      _messageText = 'Added $name to the project character library.';
      _messageIsError = false;
    });
  }

  void _updateSelectedLibraryCharacter() {
    final callback = widget.onUpdateLibraryCharacter;
    final id = widget.selectedLibraryCharacterId;
    final document = _currentLibraryDocument;
    final existing = id == null ? null : widget.characterLibrary[id];
    if (callback == null ||
        id == null ||
        document == null ||
        existing == null) {
      return;
    }
    try {
      callback(
        _buildLibraryResource(
          id: id,
          name: existing.name,
          document: document,
          existing: existing,
        ),
      );
    } catch (error) {
      _showLibraryError('update ${existing.name}', error);
      return;
    }
    setState(() {
      _messageText = 'Updated ${existing.name} in the project library.';
      _messageIsError = false;
    });
  }

  Future<void> _duplicateSelectedLibraryCharacter() async {
    final callback = widget.onDuplicateLibraryCharacter;
    final id = widget.selectedLibraryCharacterId;
    final existing = id == null ? null : widget.characterLibrary[id];
    if (callback == null || id == null || existing == null) return;
    final name = await _requestCharacterName(
      title: 'Duplicate character',
      actionLabel: 'Duplicate',
      initialValue: '${existing.name} Copy',
    );
    if (!mounted || name == null) return;
    late final CharacterId duplicateId;
    try {
      duplicateId = callback(id, name: name);
    } catch (error) {
      _showLibraryError('duplicate ${existing.name}', error);
      return;
    }
    _activeLibraryCharacterId = duplicateId;
    setState(() {
      _baselineLabel = name;
      _messageText = 'Duplicated ${existing.name} as $name.';
      _messageIsError = false;
    });
  }

  Future<void> _renameSelectedLibraryCharacter() async {
    final callback = widget.onRenameLibraryCharacter;
    final id = widget.selectedLibraryCharacterId;
    final existing = id == null ? null : widget.characterLibrary[id];
    if (callback == null || id == null || existing == null) return;
    final name = await _requestCharacterName(
      title: 'Rename character',
      actionLabel: 'Rename',
      initialValue: existing.name,
    );
    if (!mounted || name == null || name == existing.name) return;
    try {
      callback(id, name);
    } catch (error) {
      _showLibraryError('rename ${existing.name}', error);
      return;
    }
    final editor = _nativeEditor;
    final current = _currentLibraryDocument;
    if (editor != null && current != null) {
      await _applyNativeEditor(
        editor.copyWith(
          characters: {
            ...editor.characters,
            current.id: current.copyWith(name: name),
          },
        ),
        messageText: 'Renamed ${existing.name} to $name.',
      );
    }
    _baselineLabel = name;
  }

  Future<void> _deleteSelectedLibraryCharacter() async {
    final callback = widget.onDeleteLibraryCharacter;
    final id = widget.selectedLibraryCharacterId;
    final existing = id == null ? null : widget.characterLibrary[id];
    if (callback == null || id == null || existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete character?'),
        content: Text(
          '${existing.name} will be removed from this project. This can be undone from the studio history.',
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
    if (!mounted || confirmed != true) return;
    try {
      callback(id);
    } catch (error) {
      _showLibraryError('delete ${existing.name}', error);
      return;
    }
    _activeLibraryCharacterId = null;
    setState(() {
      _messageText = 'Deleted ${existing.name} from the project library.';
      _messageIsError = false;
    });
  }

  ReactifyCharacterDocument? get _currentLibraryDocument {
    final editor = _nativeEditor;
    if (editor == null) return _reactifyCharacter;
    return editor.characters['char.current'] ?? _reactifyCharacter;
  }

  CharacterResource _buildLibraryResource({
    required CharacterId id,
    required String name,
    required ReactifyCharacterDocument document,
    CharacterResource? existing,
  }) {
    final code = _libraryDocumentHasNoLegacyState
        ? existing?.legacyGachaCode
        : _currentState?.serializeCode();
    return CharacterResource(
      id: id,
      name: name,
      document: document
          .copyWith(id: id, name: name, legacyGachaCode: code)
          .toJson(),
      legacyGachaCode: code,
      thumbnailAssetId: existing?.thumbnailAssetId,
      metadata: {...?existing?.metadata, 'source': 'character_editor'},
    );
  }

  String _suggestedCharacterName() {
    final documentName = _currentLibraryDocument?.name.trim();
    if (documentName != null &&
        documentName.isNotEmpty &&
        documentName != 'Partner') {
      return documentName == 'Migrated Gacha Character'
          ? 'New Character'
          : documentName;
    }
    return _baselineLabel == 'fixture' ? 'New Character' : _baselineLabel;
  }

  void _showLibraryError(String action, Object error) {
    if (!mounted) return;
    setState(() {
      _messageText = 'Could not $action: $error';
      _messageIsError = true;
    });
  }

  Future<String?> _requestCharacterName({
    required String title,
    required String actionLabel,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Character name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  String _librarySlug(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'untitled' : normalized;
  }

  Future<void> _loadFixture(String caseId) async {
    setState(() {
      _selectedCaseId = caseId;
      _messageText = 'Loading fixture $caseId...';
      _messageIsError = false;
    });
    final descriptor = _fixtureDescriptorFor(caseId);
    final code = await _fixtureCodeCache.putIfAbsent(
      descriptor.fixtureAsset,
      () => rootBundle.loadString(descriptor.fixtureAsset),
    );
    if (!mounted || _selectedCaseId != caseId) {
      return;
    }
    _codeController.text = code.trim();
    await _adoptCode(
      code,
      baselineLabel: caseId,
      successMessage: 'Loaded fixture ${descriptor.displayName}.',
    );
  }

  Future<void> _importFromTextarea() async {
    await _adoptCode(
      _codeController.text,
      baselineLabel: 'custom_import',
      successMessage: 'Imported 445-field code from the editor buffer.',
    );
  }

  Future<void> _openGachaCodeFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open Gacha Club character code',
      type: FileType.custom,
      allowedExtensions: const ['txt', 'gc'],
      withData: true,
      allowMultiple: false,
      lockParentWindow: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    final code = utf8.decode(bytes).trim();
    _codeController.text = code;
    await _adoptCode(
      code,
      baselineLabel: result!.files.single.name,
      successMessage: 'Opened ${result.files.single.name}.',
    );
  }

  Future<void> _openNativeJsonFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open Reactify character scene',
      type: FileType.custom,
      allowedExtensions: const ['json', 'reactify'],
      withData: true,
      allowMultiple: false,
      lockParentWindow: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    _codeController.text = utf8.decode(bytes);
    await _importNativeJson();
  }

  Future<void> _saveGachaCodeFile() async {
    final currentState = _currentState;
    if (currentState == null) return;
    await _saveBytes(
      fileName: '${_exportFileStem()}.gc.txt',
      allowedExtensions: const ['txt'],
      bytes: Uint8List.fromList(utf8.encode(currentState.serializeCode())),
    );
  }

  Future<void> _adoptCode(
    String rawCode, {
    required String baselineLabel,
    required String successMessage,
  }) async {
    try {
      final normalized = rawCode.trim();
      final state = _parser.parse(normalized);
      _codeController.text = normalized;
      _colorDrafts.clear();
      _undoStates.clear();
      _redoStates.clear();
      await _setCurrentState(
        state,
        baselineState: state,
        baselineLabel: baselineLabel,
        selectedField: null,
        messageText: successMessage,
      );
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messageText = error.message;
        _messageIsError = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messageText = 'Failed to import code: $error';
        _messageIsError = true;
      });
    }
  }

  Future<void> _exportCurrentState() async {
    final currentState = _currentState;
    if (currentState == null) {
      return;
    }
    _codeController.text = currentState.serializeCode();
    setState(() {
      _messageText =
          'Exported the current 445-field code to the editor buffer.';
      _messageIsError = false;
    });
  }

  Future<void> _exportNativeSvg() async {
    final editor = _nativeEditor;
    if (editor == null || editor.characters.isEmpty) {
      return;
    }
    try {
      final package = await ReactifySvgExporter().exportPackage(
        editor.scene,
        editor.characters,
      );
      _codeController.text = package.svg;
      await _saveBytes(
        fileName: '${_exportFileStem()}.svg',
        allowedExtensions: const ['svg'],
        bytes: Uint8List.fromList(utf8.encode(package.svg)),
      );
      setState(() {
        _messageText =
            'Exported editable native SVG with ${package.assets.length} asset references to the editor buffer.';
        _messageIsError = false;
      });
    } catch (error) {
      setState(() {
        _messageText = 'Failed to export native SVG: $error';
        _messageIsError = true;
      });
    }
  }

  Future<void> _exportNativePng() async {
    final editor = _nativeEditor;
    if (editor == null || editor.characters.isEmpty) {
      return;
    }
    try {
      final bytes = await ReactifyPngExporter(
        bridge: _reactifyBridge,
      ).exportScene(editor.scene, editor.characters);
      _codeController.text = 'data:image/png;base64,${base64Encode(bytes)}';
      await _saveBytes(
        fileName: '${_exportFileStem()}.png',
        allowedExtensions: const ['png'],
        bytes: bytes,
      );
      setState(() {
        _messageText = 'Exported native PNG data URI to the editor buffer.';
        _messageIsError = false;
      });
    } catch (error) {
      setState(() {
        _messageText = 'Failed to export native PNG: $error';
        _messageIsError = true;
      });
    }
  }

  Future<void> _exportNativeJson() async {
    final editor = _nativeEditor;
    if (editor == null) {
      return;
    }
    final json = const JsonEncoder.withIndent('  ').convert(editor.toJson());
    _codeController.text = json;
    await _saveBytes(
      fileName: '${_exportFileStem()}.reactify.json',
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(json)),
    );
    setState(() {
      _messageText = 'Exported native scene JSON to the editor buffer.';
      _messageIsError = false;
    });
  }

  Future<String?> _saveBytes({
    required String fileName,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  }) {
    return FilePicker.saveFile(
      dialogTitle: 'Save Reactify export',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
      lockParentWindow: true,
    );
  }

  String _exportFileStem() {
    final source = _baselineLabel.trim().isEmpty ? 'character' : _baselineLabel;
    final normalized = source
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'character' : normalized;
  }

  Future<void> _importNativeJson() async {
    try {
      final decoded = jsonDecode(_codeController.text.trim());
      if (decoded is! Map) {
        throw const FormatException('Native scene JSON must be an object.');
      }
      final editor = ReactifySceneEditingState.fromJson(
        Map<String, Object?>.from(decoded),
      );
      await _applyNativeEditor(
        editor,
        messageText: 'Imported native scene JSON from the editor buffer.',
      );
    } on FormatException catch (error) {
      setState(() {
        _messageText = error.message;
        _messageIsError = true;
      });
    } catch (error) {
      setState(() {
        _messageText = 'Failed to import native scene JSON: $error';
        _messageIsError = true;
      });
    }
  }

  Future<void> _toggleNativeHairOverride(bool value) async {
    final editor = _nativeEditor;
    if (editor == null || _hideNativeHair == value) {
      return;
    }
    await _applyNativeEditor(
      editor.toggleSelectedSemanticSlotOverride(family: 'hair', hidden: value),
      messageText: value
          ? 'Applied a native semantic hair-slot override.'
          : 'Removed the native semantic hair-slot override.',
    );
  }

  Future<void> _resetToBaseline() async {
    final baselineState = _baselineState;
    if (baselineState == null) {
      return;
    }
    _colorDrafts.clear();
    await _setCurrentState(
      baselineState,
      baselineState: baselineState,
      baselineLabel: _baselineLabel,
      selectedField: _selectedField,
      messageText: 'Reset the editor back to the imported baseline.',
      recordHistory: true,
    );
  }

  Future<void> _resetToSelectedFixture() async {
    final caseId = _selectedCaseId;
    if (caseId == null) {
      return;
    }
    await _loadFixture(caseId);
  }

  Future<void> _updateNumericField(String field, int value) async {
    final currentState = _currentState;
    if (currentState == null) {
      return;
    }
    final nextValue = constrainToEditorDomain(
      currentValue: currentState.numeric(field),
      proposedValue: value,
      declaredRange: widget.tables.editorValueRangeFor(field),
      supportedValues: previewSupportedValues(widget.tables, field),
    );
    final next = currentState.updateNumericField(
      widget.tables.schema,
      field,
      nextValue,
    );
    final previewLabel = previewSupportLabel(widget.tables, field);
    await _setCurrentState(
      next,
      selectedField: field,
      messageText: 'Updated $field to $nextValue ($previewLabel).',
      recordHistory: true,
    );
  }

  Future<void> _updateRawField(String field, String rawValue) async {
    final currentState = _currentState;
    if (currentState == null) {
      return;
    }
    final definition = widget.tables.schema.byName[field];
    if (definition?.kind == GachaFieldKind.metadata && rawValue.contains('|')) {
      setState(() {
        _selectedField = field;
        _messageText = 'The | delimiter is not valid inside $field.';
        _messageIsError = true;
      });
      return;
    }
    try {
      final next = currentState.updateRawField(
        widget.tables.schema,
        field,
        rawValue,
      );
      await _setCurrentState(
        next,
        selectedField: field,
        messageText: 'Updated $field without applying preview-range clamping.',
        recordHistory: true,
      );
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedField = field;
        _messageText = error.message;
        _messageIsError = true;
      });
    }
  }

  void _updateColorDraft(String field, String value) {
    setState(() {
      _selectedField = field;
      _colorDrafts[field] = value.toUpperCase();
    });
  }

  Future<void> _commitColorField(String field) async {
    final currentState = _currentState;
    if (currentState == null) {
      return;
    }
    final draft =
        _colorDrafts[field] ??
        currentState.rawValue(widget.tables.schema, field);
    final normalized = canonicalRgbHexOrNull(draft);
    if (normalized == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedField = field;
        _messageText =
            'Invalid color for $field. Enter a 6-character RGB hex value.';
        _messageIsError = true;
      });
      return;
    }
    final currentHex = currentState
        .rawValue(widget.tables.schema, field)
        .toUpperCase();
    if (normalized == currentHex) {
      setState(() {
        _selectedField = field;
        _colorDrafts[field] = normalized;
      });
      return;
    }
    final next = currentState.updateRawField(
      widget.tables.schema,
      field,
      normalized,
    );
    _colorDrafts[field] = normalized;
    await _setCurrentState(
      next,
      selectedField: field,
      messageText: 'Updated $field to $normalized.',
      recordHistory: true,
    );
  }

  void _selectField(String field) {
    if (_selectedField == field) {
      return;
    }
    setState(() {
      _selectedField = field;
    });
  }

  Future<void> _setCurrentState(
    GachaCharacterState next, {
    GachaCharacterState? baselineState,
    String? baselineLabel,
    String? selectedField,
    String? messageText,
    bool recordHistory = false,
  }) async {
    _libraryDocumentHasNoLegacyState = false;
    final previousState = _currentState;
    if (recordHistory &&
        previousState != null &&
        previousState.serializeCode() != next.serializeCode()) {
      _undoStates.add(previousState);
      if (_undoStates.length > 100) _undoStates.removeAt(0);
      _redoStates.clear();
    }
    final serial = ++_renderSerial;
    final previousScene = _scene;
    setState(() {
      _currentState = next;
      _baselineState = baselineState ?? _baselineState ?? next;
      _baselineLabel = baselineLabel ?? _baselineLabel;
      _selectedField = selectedField ?? _selectedField;
      _sceneLoading = true;
      if (messageText != null) {
        _messageText = messageText;
        _messageIsError = false;
      }
    });
    try {
      final editor = _buildNativeEditorForState(
        next,
        resetScene: baselineState != null,
      );
      final scene = await _reactifyBridge.buildRenderableScene(
        editor.scene,
        editor.characters,
      );
      final reactifyResolvedPartCount = _reactifyBridge
          .resolveSceneParts(editor.scene, editor.characters)
          .length;
      if (!mounted || serial != _renderSerial) {
        return;
      }
      setState(() {
        _scene = scene;
        _nativeEditor = editor;
        _reactifyCharacter = editor.selectedCharacterDocument;
        _reactifyResolvedPartCount = reactifyResolvedPartCount;
        _hideNativeHair = _selectedHairOverrideHidden(editor);
        _sceneLoading = false;
      });
      _game.updateFlatScene(scene);
    } catch (error) {
      if (!mounted || serial != _renderSerial) {
        return;
      }
      setState(() {
        _scene = previousScene;
        _sceneLoading = false;
        _messageText = 'Failed to rebuild the scene: $error';
        _messageIsError = true;
      });
    }
  }

  Future<void> _undo() async {
    final current = _currentState;
    if (current == null || _undoStates.isEmpty) return;
    final previous = _undoStates.removeLast();
    _redoStates.add(current);
    await _setCurrentState(
      previous,
      selectedField: _selectedField,
      messageText: 'Undid the last character edit.',
    );
  }

  Future<void> _redo() async {
    final current = _currentState;
    if (current == null || _redoStates.isEmpty) return;
    final next = _redoStates.removeLast();
    _undoStates.add(current);
    await _setCurrentState(
      next,
      selectedField: _selectedField,
      messageText: 'Redid the character edit.',
    );
  }

  Future<void> _applyNativeEditor(
    ReactifySceneEditingState editor, {
    String? messageText,
  }) async {
    final serial = ++_renderSerial;
    final previousScene = _scene;
    setState(() {
      _sceneLoading = true;
      if (messageText != null) {
        _messageText = messageText;
        _messageIsError = false;
      }
    });
    try {
      final scene = await _reactifyBridge.buildRenderableScene(
        editor.scene,
        editor.characters,
      );
      final reactifyResolvedPartCount = _reactifyBridge
          .resolveSceneParts(editor.scene, editor.characters)
          .length;
      if (!mounted || serial != _renderSerial) {
        return;
      }
      setState(() {
        _scene = scene;
        _nativeEditor = editor;
        _reactifyCharacter = editor.selectedCharacterDocument;
        _reactifyResolvedPartCount = reactifyResolvedPartCount;
        _hideNativeHair = _selectedHairOverrideHidden(editor);
        _sceneLoading = false;
      });
      _game.updateFlatScene(scene);
    } catch (error) {
      if (!mounted || serial != _renderSerial) {
        return;
      }
      setState(() {
        _scene = previousScene;
        _sceneLoading = false;
        _messageText = 'Failed to rebuild the native scene: $error';
        _messageIsError = true;
      });
    }
  }

  ReactifySceneEditingState _buildNativeEditorForState(
    GachaCharacterState currentState, {
    required bool resetScene,
  }) {
    var currentCharacter = _reactifyAdapter.migrate(
      currentState,
      id: 'char.current',
    );
    final existing = resetScene ? null : _nativeEditor;
    final previousCurrent = existing?.characters[currentCharacter.id];
    for (final slot in previousCurrent?.slots ?? const <ReactifySlot>[]) {
      if (slot.kind != ReactifySlotKind.custom) {
        continue;
      }
      currentCharacter = currentCharacter.addSlot(slot);
    }
    if (existing == null) {
      final partnerCharacter = currentCharacter.copyWith(
        id: 'char.partner',
        name: 'Partner',
      );
      return ReactifySceneEditingState(
        selectedSceneCharacterId: 'scene_char.current',
        scene: const ReactifySceneDocument(
          id: 'scene.current',
          name: 'Current Native Scene',
          characters: [
            ReactifySceneCharacter(
              id: 'scene_char.current',
              characterId: 'char.current',
              transform: AffineMatrix(
                a: 0.92,
                b: 0,
                c: 0,
                d: 0.92,
                tx: -180,
                ty: 0,
              ),
              pose: 'current',
            ),
            ReactifySceneCharacter(
              id: 'scene_char.partner',
              characterId: 'char.partner',
              transform: AffineMatrix(
                a: 0.92,
                b: 0,
                c: 0,
                d: 0.92,
                tx: 180,
                ty: 0,
              ),
              pose: 'partner',
            ),
          ],
        ),
        characters: {
          currentCharacter.id: currentCharacter,
          partnerCharacter.id: partnerCharacter,
        },
      );
    }
    final characters = <String, ReactifyCharacterDocument>{
      ...existing.characters,
      currentCharacter.id: currentCharacter,
    };
    characters.putIfAbsent(
      'char.partner',
      () => currentCharacter.copyWith(id: 'char.partner', name: 'Partner'),
    );
    final sceneCharacters = [...existing.scene.characters];
    if (!sceneCharacters.any(
      (character) => character.id == 'scene_char.current',
    )) {
      sceneCharacters.insert(
        0,
        const ReactifySceneCharacter(
          id: 'scene_char.current',
          characterId: 'char.current',
          transform: AffineMatrix(
            a: 0.92,
            b: 0,
            c: 0,
            d: 0.92,
            tx: -180,
            ty: 0,
          ),
          pose: 'current',
        ),
      );
    }
    if (!sceneCharacters.any(
      (character) => character.id == 'scene_char.partner',
    )) {
      sceneCharacters.add(
        const ReactifySceneCharacter(
          id: 'scene_char.partner',
          characterId: 'char.partner',
          transform: AffineMatrix(a: 0.92, b: 0, c: 0, d: 0.92, tx: 180, ty: 0),
          pose: 'partner',
        ),
      );
    }
    return existing.copyWith(
      scene: existing.scene.copyWith(characters: sceneCharacters),
      characters: characters,
    );
  }

  bool _selectedHairOverrideHidden(ReactifySceneEditingState editor) {
    final sceneCharacter = editor.selectedSceneCharacter;
    final character = editor.selectedCharacterDocument;
    if (sceneCharacter == null || character == null) {
      return false;
    }
    for (final slot in character.semanticSlots) {
      if (slot.family != 'hair') {
        continue;
      }
      return sceneCharacter.slotOverrides[slot.id]?.visible == false;
    }
    return false;
  }

  Future<void> _selectNativeSceneCharacter(String sceneCharacterId) async {
    final editor = _nativeEditor;
    if (editor == null) {
      return;
    }
    await _applyNativeEditor(
      editor.selectSceneCharacter(sceneCharacterId),
      messageText: 'Selected native scene character $sceneCharacterId.',
    );
  }

  Future<void> _addNativeSceneCharacter() async {
    final editor = _nativeEditor;
    final selectedDocument = editor?.selectedCharacterDocument;
    if (editor == null || selectedDocument == null) {
      return;
    }
    final id = _nextSceneCharacterId(editor, 'scene_char.native');
    final index = editor.scene.characters.length;
    await _applyNativeEditor(
      editor.addSceneCharacter(
        sceneCharacter: ReactifySceneCharacter(
          id: id,
          characterId: selectedDocument.id,
          transform: AffineMatrix(
            a: 0.92,
            b: 0,
            c: 0,
            d: 0.92,
            tx: -120 + index * 80,
            ty: 0,
          ),
          pose: 'native',
        ),
      ),
      messageText: 'Added native scene character $id.',
    );
  }

  Future<void> _removeSelectedNativeSceneCharacter() async {
    final editor = _nativeEditor;
    final selected = editor?.selectedSceneCharacter;
    if (editor == null || selected == null) {
      return;
    }
    if (editor.scene.characters.length <= 1) {
      setState(() {
        _messageText = 'Keep at least one native scene character.';
        _messageIsError = true;
      });
      return;
    }
    await _applyNativeEditor(
      editor.removeSceneCharacter(selected.id),
      messageText: 'Removed native scene character ${selected.id}.',
    );
  }

  Future<void> _attachRegisteredNativeAssetSlot() async {
    final editor = _nativeEditor;
    if (editor == null) {
      return;
    }
    const asset = ReactifyRegisteredAsset(
      id: 'user.asset.sample.svg',
      kind: ReactifyAssetKind.svg,
      uri: 'assets/gacha/head/head_1.svg',
      source: 'user',
      dimensions: Size(600, 600),
      metadata: {'label': 'Sample SVG', 'source': 'editor_sample'},
    );
    await _applyNativeEditor(
      editor
          .registerAsset(asset)
          .attachRegisteredAssetSlotToSelectedCharacter(
            assetId: asset.id,
            name: 'Registered SVG',
            localTransform: const AffineMatrix(
              a: 0.18,
              b: 0,
              c: 0,
              d: 0.18,
              tx: 72,
              ty: -48,
            ),
          ),
      messageText: 'Attached registered native asset ${asset.id}.',
    );
  }

  String _nextSceneCharacterId(
    ReactifySceneEditingState editor,
    String baseId,
  ) {
    final existingIds = {
      for (final character in editor.scene.characters) character.id,
    };
    if (!existingIds.contains(baseId)) {
      return baseId;
    }
    var index = 2;
    while (existingIds.contains('$baseId.$index')) {
      index += 1;
    }
    return '$baseId.$index';
  }

  Future<void> _updateSelectedNativeTransform(AffineMatrix transform) async {
    final editor = _nativeEditor;
    if (editor == null) {
      return;
    }
    await _applyNativeEditor(
      editor.updateSelectedCharacterTransform(transform),
      messageText: 'Updated the selected native character transform.',
    );
  }

  ValidationCaseDescriptor _fixtureDescriptorFor(String id) {
    return widget.tables.editorFixtures.firstWhere((item) => item.id == id);
  }
}

class _CharacterLibraryBar extends StatelessWidget {
  const _CharacterLibraryBar({
    required this.characters,
    required this.selectedCharacterId,
    required this.onSelected,
    required this.onAdd,
    required this.onUpdate,
    required this.onDuplicate,
    required this.onRename,
    required this.onDelete,
  });

  final Map<CharacterId, CharacterResource> characters;
  final CharacterId? selectedCharacterId;
  final ValueChanged<CharacterId> onSelected;
  final VoidCallback? onAdd;
  final VoidCallback? onUpdate;
  final VoidCallback? onDuplicate;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final entries = characters.values.toList()
      ..sort((left, right) {
        final name = left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        );
        return name != 0 ? name : left.id.compareTo(right.id);
      });
    final selected = characters.containsKey(selectedCharacterId)
        ? selectedCharacterId
        : null;
    final selector = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF00F5FF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF00F5FF).withValues(alpha: 0.28),
            ),
          ),
          child: const Icon(
            Icons.people_alt_outlined,
            size: 18,
            color: Color(0xFF65F7FF),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'PROJECT CAST',
          style: TextStyle(
            color: Color(0xFFB7C4D8),
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CharacterId>(
              value: selected,
              isExpanded: true,
              hint: Text(
                entries.isEmpty
                    ? 'No project characters yet'
                    : 'Select character',
              ),
              borderRadius: BorderRadius.circular(14),
              items: [
                for (final character in entries)
                  DropdownMenuItem(
                    value: character.id,
                    child: Text(
                      character.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF070B12).withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '${characters.length}',
            style: const TextStyle(
              color: Color(0xFF65F7FF),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 4,
      children: [
        _LibraryAction(
          tooltip: 'Add the current character to this project',
          icon: Icons.person_add_alt_1_outlined,
          onPressed: onAdd,
        ),
        _LibraryAction(
          tooltip: 'Save current edits to the selected character',
          icon: Icons.save_outlined,
          onPressed: onUpdate,
        ),
        _LibraryAction(
          tooltip: 'Duplicate selected character',
          icon: Icons.copy_outlined,
          onPressed: onDuplicate,
        ),
        _LibraryAction(
          tooltip: 'Rename selected character',
          icon: Icons.drive_file_rename_outline,
          onPressed: onRename,
        ),
        _LibraryAction(
          tooltip: 'Delete selected character',
          icon: Icons.delete_outline,
          destructive: true,
          onPressed: onDelete,
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF29364A)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 780) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                selector,
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: selector),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _LibraryAction extends StatelessWidget {
  const _LibraryAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: destructive
            ? const Color(0xFFFF8D99)
            : const Color(0xFFC8D3E2),
        disabledForegroundColor: const Color(0xFF5C6879),
        backgroundColor: onPressed == null
            ? Colors.transparent
            : const Color(0xFF202B3C),
        hoverColor: destructive
            ? const Color(0xFF5C1F2B)
            : const Color(0xFF2B3B51),
      ),
      icon: Icon(icon, size: 18),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.selectedCaseId,
    required this.cases,
    required this.changeCount,
    required this.resolvedPartCount,
    required this.nativeSlotCount,
    required this.nativePartCount,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onChanged,
  });

  final String selectedCaseId;
  final List<ValidationCaseDescriptor> cases;
  final int changeCount;
  final int resolvedPartCount;
  final int nativeSlotCount;
  final int nativePartCount;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = cases.firstWhere(
      (item) => item.id == selectedCaseId,
      orElse: () => cases.first,
    );
    const borderRadius = BorderRadius.all(Radius.circular(24));

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07090C).withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: CustomPaint(
            foregroundPainter: _HeaderGlassBorderPainter(
              borderRadius: borderRadius,
              strokeWidth: 1.2,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E293B).withValues(alpha: 0.45),
                    const Color(0xFF0F172A).withValues(alpha: 0.65),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gacha Character Editor / Renderer Harness',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dense schema-driven editing against the canonical 445-field character state.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '$changeCount fields • $resolvedPartCount legacy • $nativeSlotCount slots • $nativePartCount native',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF00F5FF),
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    tooltip: 'Undo character edit',
                    onPressed: canUndo ? onUndo : null,
                    color: Colors.white,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: 'Redo character edit',
                    onPressed: canRedo ? onRedo : null,
                    color: Colors.white,
                    icon: const Icon(Icons.redo),
                  ),
                  const SizedBox(width: 8),
                  _SpringDropdownButton(
                    selected: selected,
                    cases: cases,
                    selectedCaseId: selectedCaseId,
                    onChanged: onChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpringDropdownButton extends StatefulWidget {
  const _SpringDropdownButton({
    required this.selected,
    required this.cases,
    required this.selectedCaseId,
    required this.onChanged,
  });

  final ValidationCaseDescriptor selected;
  final List<ValidationCaseDescriptor> cases;
  final String selectedCaseId;
  final ValueChanged<String> onChanged;

  @override
  State<_SpringDropdownButton> createState() => _SpringDropdownButtonState();
}

class _SpringDropdownButtonState extends State<_SpringDropdownButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.93),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: () async {
        final selectedId = await showDialog<String>(
          context: context,
          builder: (context) => _FixturePickerDialog(
            cases: widget.cases,
            selectedCaseId: widget.selectedCaseId,
          ),
        );
        if (selectedId != null) {
          widget.onChanged(selectedId);
        }
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.decelerate,
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: const Color(0xFF00F5FF).withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00F5FF).withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.selected.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.selected.group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more, color: Color(0xFF00F5FF), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderGlassBorderPainter extends CustomPainter {
  const _HeaderGlassBorderPainter({
    required this.borderRadius,
    required this.strokeWidth,
  });

  final BorderRadius borderRadius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.05),
          Colors.black.withValues(alpha: 0.2),
          Colors.white.withValues(alpha: 0.14),
        ],
        stops: const [0.0, 0.45, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _HeaderGlassBorderPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _FixturePickerDialog extends StatefulWidget {
  const _FixturePickerDialog({
    required this.cases,
    required this.selectedCaseId,
  });

  final List<ValidationCaseDescriptor> cases;
  final String selectedCaseId;

  @override
  State<_FixturePickerDialog> createState() => _FixturePickerDialogState();
}

class _FixturePickerDialogState extends State<_FixturePickerDialog> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = [
      for (final item in widget.cases)
        if (normalizedQuery.isEmpty ||
            item.displayName.toLowerCase().contains(normalizedQuery) ||
            item.id.toLowerCase().contains(normalizedQuery) ||
            item.featureTags.any(
              (tag) => tag.toLowerCase().contains(normalizedQuery),
            ))
          item,
    ];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose Fixture',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _queryController,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search name, id, or tag',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('No fixtures match this search.'),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final previousGroup = index == 0
                              ? null
                              : filtered[index - 1].group;
                          final showGroupHeader = item.group != previousGroup;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showGroupHeader)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    16,
                                    4,
                                    6,
                                  ),
                                  child: Text(
                                    item.group,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF5D6A75),
                                        ),
                                  ),
                                ),
                              _FixturePickerRow(
                                item: item,
                                selected: item.id == widget.selectedCaseId,
                                onTap: () => Navigator.of(context).pop(item.id),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FixturePickerRow extends StatelessWidget {
  const _FixturePickerRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ValidationCaseDescriptor item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tags = item.featureTags.take(8).join(', ');
    return ListTile(
      dense: true,
      selected: selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(
        item.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: tags.isEmpty
          ? Text(item.id, maxLines: 1, overflow: TextOverflow.ellipsis)
          : Text(
              '${item.id} • $tags',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: selected ? const Icon(Icons.check, size: 20) : null,
      onTap: onTap,
    );
  }
}

class _NativeSceneControls extends StatelessWidget {
  const _NativeSceneControls({
    required this.editor,
    required this.hideNativeHair,
    required this.onCharacterSelected,
    required this.onTransformChanged,
    required this.onHairOverrideChanged,
    required this.onCharacterAdded,
    required this.onCharacterRemoved,
    required this.onRegisteredAssetAttached,
  });

  final ReactifySceneEditingState editor;
  final bool hideNativeHair;
  final ValueChanged<String> onCharacterSelected;
  final ValueChanged<AffineMatrix> onTransformChanged;
  final ValueChanged<bool> onHairOverrideChanged;
  final VoidCallback onCharacterAdded;
  final VoidCallback onCharacterRemoved;
  final VoidCallback onRegisteredAssetAttached;

  @override
  Widget build(BuildContext context) {
    final selected =
        editor.selectedSceneCharacter ??
        (editor.scene.characters.isEmpty
            ? null
            : editor.scene.characters.first);
    if (selected == null) {
      return const SizedBox.shrink();
    }
    final transform = selected.transform;
    return _PanelCard(
      title: 'Native Scene',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: selected.id,
            decoration: const InputDecoration(
              labelText: 'Selected character',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final sceneCharacter in editor.scene.characters)
                DropdownMenuItem(
                  value: sceneCharacter.id,
                  child: Text(sceneCharacter.id),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                onCharacterSelected(value);
              }
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _NativeTransformField(
                label: 'X',
                value: transform.tx,
                onSubmitted: (value) => onTransformChanged(
                  AffineMatrix(
                    a: transform.a,
                    b: transform.b,
                    c: transform.c,
                    d: transform.d,
                    tx: value,
                    ty: transform.ty,
                  ),
                ),
              ),
              _NativeTransformField(
                label: 'Y',
                value: transform.ty,
                onSubmitted: (value) => onTransformChanged(
                  AffineMatrix(
                    a: transform.a,
                    b: transform.b,
                    c: transform.c,
                    d: transform.d,
                    tx: transform.tx,
                    ty: value,
                  ),
                ),
              ),
              _NativeTransformField(
                label: 'Scale X',
                value: transform.a,
                onSubmitted: (value) => onTransformChanged(
                  AffineMatrix(
                    a: value,
                    b: transform.b,
                    c: transform.c,
                    d: transform.d,
                    tx: transform.tx,
                    ty: transform.ty,
                  ),
                ),
              ),
              _NativeTransformField(
                label: 'Scale Y',
                value: transform.d,
                onSubmitted: (value) => onTransformChanged(
                  AffineMatrix(
                    a: transform.a,
                    b: transform.b,
                    c: transform.c,
                    d: value,
                    tx: transform.tx,
                    ty: transform.ty,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide selected hair slot'),
              value: hideNativeHair,
              onChanged: onHairOverrideChanged,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onCharacterAdded,
                child: const Text('Add Character'),
              ),
              OutlinedButton(
                onPressed: editor.scene.characters.length <= 1
                    ? null
                    : onCharacterRemoved,
                child: const Text('Remove Selected'),
              ),
              OutlinedButton(
                onPressed: onRegisteredAssetAttached,
                child: const Text('Attach Registered Asset'),
              ),
            ],
          ),
          if (editor.assetRegistry.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${editor.assetRegistry.length} registered native asset(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _NativeTransformField extends StatelessWidget {
  const _NativeTransformField({
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  final String label;
  final double value;
  final ValueChanged<double> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 106,
      child: TextFormField(
        key: ValueKey('$label-$value'),
        initialValue: _formatNumber(value),
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onFieldSubmitted: (raw) {
          final parsed = double.tryParse(raw.trim());
          if (parsed != null) {
            onSubmitted(parsed);
          }
        },
      ),
    );
  }
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _EditorInspector extends StatelessWidget {
  const _EditorInspector({
    required this.baselineLabel,
    required this.fixtureLabel,
    required this.fixtureTags,
    required this.messageText,
    required this.messageIsError,
    required this.codeController,
    required this.currentState,
    required this.baselineState,
    required this.scene,
    required this.nativeEditor,
    required this.schema,
    required this.tables,
    required this.colorDrafts,
    required this.selectedField,
    required this.hideNativeHair,
    required this.onImportPressed,
    required this.onOpenCodeFilePressed,
    required this.onSaveCodeFilePressed,
    required this.onExportPressed,
    required this.onExportNativeSvgPressed,
    required this.onExportNativePngPressed,
    required this.onExportNativeJsonPressed,
    required this.onImportNativeJsonPressed,
    required this.onOpenNativeJsonFilePressed,
    required this.onResetToFixturePressed,
    required this.onResetToBaselinePressed,
    required this.onNativeHairOverrideChanged,
    required this.onNativeSceneCharacterAdded,
    required this.onNativeSceneCharacterRemoved,
    required this.onNativeRegisteredAssetAttached,
    required this.onNativeSceneCharacterSelected,
    required this.onNativeTransformChanged,
    required this.onNumericFieldChanged,
    required this.onRawFieldChanged,
    required this.onColorDraftChanged,
    required this.onColorCommit,
    required this.onFieldSelected,
  });

  final String baselineLabel;
  final String fixtureLabel;
  final List<String> fixtureTags;
  final String? messageText;
  final bool messageIsError;
  final TextEditingController codeController;
  final GachaCharacterState currentState;
  final GachaCharacterState baselineState;
  final ResolvedScene scene;
  final ReactifySceneEditingState? nativeEditor;
  final GachaFieldSchema schema;
  final ResolverTables tables;
  final Map<String, String> colorDrafts;
  final String? selectedField;
  final bool hideNativeHair;
  final VoidCallback onImportPressed;
  final VoidCallback onOpenCodeFilePressed;
  final VoidCallback onSaveCodeFilePressed;
  final VoidCallback onExportPressed;
  final VoidCallback onExportNativeSvgPressed;
  final VoidCallback onExportNativePngPressed;
  final VoidCallback onExportNativeJsonPressed;
  final VoidCallback onImportNativeJsonPressed;
  final VoidCallback onOpenNativeJsonFilePressed;
  final VoidCallback onResetToFixturePressed;
  final VoidCallback onResetToBaselinePressed;
  final ValueChanged<bool> onNativeHairOverrideChanged;
  final VoidCallback onNativeSceneCharacterAdded;
  final VoidCallback onNativeSceneCharacterRemoved;
  final VoidCallback onNativeRegisteredAssetAttached;
  final ValueChanged<String> onNativeSceneCharacterSelected;
  final ValueChanged<AffineMatrix> onNativeTransformChanged;
  final Future<void> Function(String field, int value) onNumericFieldChanged;
  final Future<void> Function(String field, String rawValue) onRawFieldChanged;
  final void Function(String field, String value) onColorDraftChanged;
  final Future<void> Function(String field) onColorCommit;
  final ValueChanged<String> onFieldSelected;

  @override
  Widget build(BuildContext context) {
    final changes = currentState.diff(baselineState, schema);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelCard(
            title: 'Presets / Import Export',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Selected fixture: $fixtureLabel'),
                if (fixtureTags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Tags: ${fixtureTags.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Text('Baseline source: $baselineLabel'),
                const SizedBox(height: 12),
                TextField(
                  controller: codeController,
                  minLines: 6,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Raw Gacha Code',
                    hintText: 'Paste a full 445-field Gacha Club code here.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'Consolas',
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: onImportPressed,
                      child: const Text('Import'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenCodeFilePressed,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open Code File'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onSaveCodeFilePressed,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Save Code File'),
                    ),
                    OutlinedButton(
                      onPressed: onExportPressed,
                      child: const Text('Export To Buffer'),
                    ),
                    OutlinedButton(
                      onPressed: onExportNativeSvgPressed,
                      child: const Text('Export Native SVG'),
                    ),
                    OutlinedButton(
                      onPressed: onExportNativePngPressed,
                      child: const Text('Export Native PNG'),
                    ),
                    OutlinedButton(
                      onPressed: onExportNativeJsonPressed,
                      child: const Text('Export Native JSON'),
                    ),
                    OutlinedButton(
                      onPressed: onImportNativeJsonPressed,
                      child: const Text('Import Native JSON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenNativeJsonFilePressed,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open Native JSON'),
                    ),
                    OutlinedButton(
                      onPressed: onResetToFixturePressed,
                      child: const Text('Reset To Selected Fixture'),
                    ),
                    OutlinedButton(
                      onPressed: onResetToBaselinePressed,
                      child: const Text('Reset To Imported Baseline'),
                    ),
                  ],
                ),
                if (nativeEditor != null) ...[
                  const SizedBox(height: 12),
                  _NativeSceneControls(
                    editor: nativeEditor!,
                    hideNativeHair: hideNativeHair,
                    onCharacterSelected: onNativeSceneCharacterSelected,
                    onTransformChanged: onNativeTransformChanged,
                    onHairOverrideChanged: onNativeHairOverrideChanged,
                    onCharacterAdded: onNativeSceneCharacterAdded,
                    onCharacterRemoved: onNativeSceneCharacterRemoved,
                    onRegisteredAssetAttached: onNativeRegisteredAssetAttached,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(
                      '${currentState.rawFields.length} / ${GachaFieldSchema.totalFieldCount} fields',
                    ),
                    Text('${changes.length} changed field(s)'),
                  ],
                ),
                if (messageText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    messageText!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: messageIsError
                          ? const Color(0xFF8A2B2B)
                          : const Color(0xFF2B5A39),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Changed field list',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  changes.isEmpty
                      ? 'No fields changed.'
                      : _formatChanges(changes),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'Consolas',
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _FieldSectionCard(
            title: 'Body',
            groups: [_NumericFieldGroupSpec('Body Meta', _bodyFields)],
            currentState: currentState,
            tables: tables,
            onChanged: onNumericFieldChanged,
            onFieldSelected: onFieldSelected,
          ),
          const SizedBox(height: 16),
          _FieldSectionCard(
            title: 'Head / Face',
            groups: [
              _NumericFieldGroupSpec('Head / Face Slots', _headFaceFields),
            ],
            currentState: currentState,
            tables: tables,
            onChanged: onNumericFieldChanged,
            onFieldSelected: onFieldSelected,
          ),
          const SizedBox(height: 16),
          _FieldSectionCard(
            title: 'Hair',
            groups: [_NumericFieldGroupSpec('Hair Slots', _hairFields)],
            currentState: currentState,
            tables: tables,
            onChanged: onNumericFieldChanged,
            onFieldSelected: onFieldSelected,
          ),
          const SizedBox(height: 16),
          _FieldSectionCard(
            title: 'Clothing',
            groups: [
              _NumericFieldGroupSpec('Upper / Lower Clothing', _clothingFields),
            ],
            currentState: currentState,
            tables: tables,
            onChanged: onNumericFieldChanged,
            onFieldSelected: onFieldSelected,
          ),
          const SizedBox(height: 16),
          _FieldSectionCard(
            title: 'Accessories',
            groups: [
              _NumericFieldGroupSpec(
                'Head / Face Accessories',
                _accessoryFields,
              ),
            ],
            currentState: currentState,
            tables: tables,
            onChanged: onNumericFieldChanged,
            onFieldSelected: onFieldSelected,
          ),
          const SizedBox(height: 16),
          _FieldSectionCard(
            title: 'Props',
            groups: [_NumericFieldGroupSpec('Props / Effects', _propFields)],
            currentState: currentState,
            tables: tables,
            onChanged: onNumericFieldChanged,
            onFieldSelected: onFieldSelected,
          ),
          const SizedBox(height: 16),
          _PanelCard(
            title: 'Transforms / Positioning',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var index = 0;
                  index < _transformGroups.length;
                  index += 1
                ) ...[
                  _TransformFieldGroup(
                    spec: _transformGroups[index],
                    currentState: currentState,
                    tables: tables,
                    onChanged: onNumericFieldChanged,
                    onFieldSelected: onFieldSelected,
                  ),
                  if (index != _transformGroups.length - 1)
                    const SizedBox(height: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PanelCard(
            title: 'Display Toggles',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final spec in _displayFields)
                  SizedBox(
                    width: 265,
                    child: Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFB9C2CA)),
                        ),
                        title: Text(spec.label),
                        value: currentState.numeric(spec.field) != 0,
                        onChanged: (enabled) {
                          onFieldSelected(spec.field);
                          onNumericFieldChanged(spec.field, enabled ? 1 : 0);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PanelCard(
            title: 'Colors',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var index = 0;
                  index < _colorGroups.length;
                  index += 1
                ) ...[
                  _ColorFieldGroup(
                    spec: _colorGroups[index],
                    currentState: currentState,
                    schema: schema,
                    drafts: colorDrafts,
                    onDraftChanged: onColorDraftChanged,
                    onCommit: onColorCommit,
                    onFieldSelected: onFieldSelected,
                  ),
                  if (index != _colorGroups.length - 1)
                    const SizedBox(height: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AdvancedFieldsSection(
            schema: schema,
            state: currentState,
            colorDrafts: colorDrafts,
            onRawFieldChanged: onRawFieldChanged,
            onColorDraftChanged: onColorDraftChanged,
            onColorCommit: onColorCommit,
            onFieldSelected: onFieldSelected,
          ),
          const SizedBox(height: 16),
          DebugRenderPanel(
            fixtureLabel: fixtureLabel,
            fixtureTags: fixtureTags,
            schema: schema,
            baselineState: baselineState,
            state: currentState,
            scene: scene,
            selectedField: selectedField,
          ),
        ],
      ),
    );
  }

  static String _formatChanges(List<GachaFieldChange> changes) {
    final buffer = StringBuffer();
    for (final change in changes) {
      buffer.writeln(
        '[${change.index.toString().padLeft(3, '0')}] '
        '${change.field}: ${change.previousRawValue} -> ${change.rawValue}',
      );
    }
    return buffer.toString().trimRight();
  }
}

class _FieldSectionCard extends StatelessWidget {
  const _FieldSectionCard({
    required this.title,
    required this.groups,
    required this.currentState,
    required this.tables,
    required this.onChanged,
    required this.onFieldSelected,
  });

  final String title;
  final List<_NumericFieldGroupSpec> groups;
  final GachaCharacterState currentState;
  final ResolverTables tables;
  final Future<void> Function(String field, int value) onChanged;
  final ValueChanged<String> onFieldSelected;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < groups.length; index += 1) ...[
            _NumericFieldGroup(
              spec: groups[index],
              currentState: currentState,
              tables: tables,
              onChanged: onChanged,
              onFieldSelected: onFieldSelected,
            ),
            if (index != groups.length - 1) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _NumericFieldGroup extends StatelessWidget {
  const _NumericFieldGroup({
    required this.spec,
    required this.currentState,
    required this.tables,
    required this.onChanged,
    required this.onFieldSelected,
  });

  final _NumericFieldGroupSpec spec;
  final GachaCharacterState currentState;
  final ResolverTables tables;
  final Future<void> Function(String field, int value) onChanged;
  final ValueChanged<String> onFieldSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(spec.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final field in spec.fields)
              _CompactNumericField(
                spec: field,
                value: currentState.numeric(field.field),
                tables: tables,
                fallbackRange: tables.editorValueRangeFor(field.field),
                onChanged: onChanged,
                onFieldSelected: onFieldSelected,
              ),
          ],
        ),
      ],
    );
  }
}

class _TransformFieldGroup extends StatelessWidget {
  const _TransformFieldGroup({
    required this.spec,
    required this.currentState,
    required this.tables,
    required this.onChanged,
    required this.onFieldSelected,
  });

  final _TransformGroupSpec spec;
  final GachaCharacterState currentState;
  final ResolverTables tables;
  final Future<void> Function(String field, int value) onChanged;
  final ValueChanged<String> onFieldSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(spec.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final field in spec.fields)
              _CompactNumericField(
                spec: field,
                value: currentState.numeric(field.field),
                tables: tables,
                fallbackRange: tables.editorValueRangeFor(field.field),
                onChanged: onChanged,
                onFieldSelected: onFieldSelected,
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorFieldGroup extends StatelessWidget {
  const _ColorFieldGroup({
    required this.spec,
    required this.currentState,
    required this.schema,
    required this.drafts,
    required this.onDraftChanged,
    required this.onCommit,
    required this.onFieldSelected,
  });

  final _ColorFieldGroupSpec spec;
  final GachaCharacterState currentState;
  final GachaFieldSchema schema;
  final Map<String, String> drafts;
  final void Function(String field, String value) onDraftChanged;
  final Future<void> Function(String field) onCommit;
  final ValueChanged<String> onFieldSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(spec.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final field in spec.fields)
              _ColorFieldTile(
                field: field.field,
                label: field.label,
                currentHex: currentState
                    .rawValue(schema, field.field)
                    .toUpperCase(),
                color: currentState.color(field.field),
                draft: drafts[field.field],
                onDraftChanged: onDraftChanged,
                onCommit: onCommit,
                onFieldSelected: onFieldSelected,
              ),
          ],
        ),
      ],
    );
  }
}

class _CompactNumericField extends StatelessWidget {
  const _CompactNumericField({
    required this.spec,
    required this.value,
    required this.tables,
    required this.fallbackRange,
    required this.onChanged,
    required this.onFieldSelected,
  });

  final _NumericFieldSpec spec;
  final int value;
  final ResolverTables tables;
  final EditorValueRange? fallbackRange;
  final Future<void> Function(String field, int value) onChanged;
  final ValueChanged<String> onFieldSelected;

  @override
  Widget build(BuildContext context) {
    final supportedValues = previewSupportedValues(tables, spec.field);
    final domain = effectiveEditorDomain(
      currentValue: value,
      declaredMin: spec.minValue ?? fallbackRange?.minValue,
      declaredMax: spec.maxValue ?? fallbackRange?.maxValue,
      supportedValues: supportedValues,
    );
    final minValue = domain.min;
    final maxValue = domain.max;
    final supportLabel = previewSupportLabel(tables, spec.field);
    final previewBacked = isPreviewBackedField(spec.field);

    return SizedBox(
      width: spec.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB9C2CA)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spec.label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                minValue == null || maxValue == null
                    ? spec.field
                    : '${spec.field} ($minValue-$maxValue)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(
                supportLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: previewBacked
                      ? const Color(0xFF2B5A39)
                      : const Color(0xFF8A5A2B),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      onFieldSelected(spec.field);
                      onChanged(spec.field, value - 1);
                    },
                    icon: const Icon(Icons.remove, size: 18),
                  ),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('${spec.field}:$value'),
                      initialValue: '$value',
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      onTap: () => onFieldSelected(spec.field),
                      onFieldSubmitted: (draft) {
                        final parsed = int.tryParse(draft);
                        if (parsed != null) {
                          onFieldSelected(spec.field);
                          onChanged(spec.field, parsed);
                        }
                      },
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      onFieldSelected(spec.field);
                      onChanged(spec.field, value + 1);
                    },
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorFieldTile extends StatelessWidget {
  const _ColorFieldTile({
    required this.field,
    required this.label,
    required this.currentHex,
    required this.color,
    required this.draft,
    required this.onDraftChanged,
    required this.onCommit,
    required this.onFieldSelected,
  });

  final String field;
  final String label;
  final String currentHex;
  final Color color;
  final String? draft;
  final void Function(String field, String value) onDraftChanged;
  final Future<void> Function(String field) onCommit;
  final ValueChanged<String> onFieldSelected;

  @override
  Widget build(BuildContext context) {
    final displayValue = draft ?? currentHex;
    final isValid = isValidRgbHex(displayValue);

    return SizedBox(
      width: 280,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: isValid ? const Color(0xFFB9C2CA) : const Color(0xFFB00020),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF8090A0)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          field,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: ValueKey('$field:$displayValue:$currentHex'),
                initialValue: displayValue,
                textCapitalization: TextCapitalization.characters,
                onTap: () => onFieldSelected(field),
                onChanged: (value) {
                  onFieldSelected(field);
                  onDraftChanged(field, value);
                },
                onFieldSubmitted: (_) => onCommit(field),
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: '#',
                  labelText: 'RGB Hex',
                  helperText: isValid
                      ? 'Current: #$currentHex'
                      : 'Enter 6 hex characters',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => onCommit(field),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AdvancedFieldFilter { all, metadata, numeric, color }

class _AdvancedFieldsSection extends StatefulWidget {
  const _AdvancedFieldsSection({
    required this.schema,
    required this.state,
    required this.colorDrafts,
    required this.onRawFieldChanged,
    required this.onColorDraftChanged,
    required this.onColorCommit,
    required this.onFieldSelected,
  });

  final GachaFieldSchema schema;
  final GachaCharacterState state;
  final Map<String, String> colorDrafts;
  final Future<void> Function(String field, String rawValue) onRawFieldChanged;
  final void Function(String field, String value) onColorDraftChanged;
  final Future<void> Function(String field) onColorCommit;
  final ValueChanged<String> onFieldSelected;

  @override
  State<_AdvancedFieldsSection> createState() => _AdvancedFieldsSectionState();
}

class _AdvancedFieldsSectionState extends State<_AdvancedFieldsSection> {
  final TextEditingController _searchController = TextEditingController();
  _AdvancedFieldFilter _filter = _AdvancedFieldFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final advancedDefinitions = advancedEditorDefinitions(widget.schema);
    final query = _searchController.text.trim().toLowerCase();
    final visible = advancedDefinitions
        .where((definition) {
          if (!_matchesAdvancedFilter(definition.kind, _filter)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return definition.field.toLowerCase().contains(query) ||
              definition.subsystem.toLowerCase().contains(query) ||
              _fieldKindLabel(definition.kind).toLowerCase().contains(query);
        })
        .toList(growable: false);
    final groups = <String, List<GachaFieldDefinition>>{};
    for (final definition in visible) {
      groups.putIfAbsent(definition.subsystem, () => []).add(definition);
    }

    return _PanelCard(
      title: 'Advanced Fields',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${advancedDefinitions.length} canonical fields not exposed in the primary controls. Values are committed exactly and are not clamped to renderer preview ranges.',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              final search = TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search field or subsystem',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              );
              final filter = DropdownButtonFormField<_AdvancedFieldFilter>(
                initialValue: _filter,
                decoration: const InputDecoration(
                  labelText: 'Field type',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: _AdvancedFieldFilter.all,
                    child: Text('All fields'),
                  ),
                  DropdownMenuItem(
                    value: _AdvancedFieldFilter.metadata,
                    child: Text('Text'),
                  ),
                  DropdownMenuItem(
                    value: _AdvancedFieldFilter.numeric,
                    child: Text('Number'),
                  ),
                  DropdownMenuItem(
                    value: _AdvancedFieldFilter.color,
                    child: Text('Color'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _filter = value);
                  }
                },
              );
              if (narrow) {
                return Column(
                  children: [search, const SizedBox(height: 10), filter],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  SizedBox(width: 190, child: filter),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text('${visible.length} field(s) shown'),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No advanced fields match this filter.'),
            )
          else
            for (final entry in groups.entries)
              _AdvancedFieldGroup(
                subsystem: entry.key,
                definitions: entry.value,
                schema: widget.schema,
                state: widget.state,
                colorDrafts: widget.colorDrafts,
                onRawFieldChanged: widget.onRawFieldChanged,
                onColorDraftChanged: widget.onColorDraftChanged,
                onColorCommit: widget.onColorCommit,
                onFieldSelected: widget.onFieldSelected,
                expanded: query.isNotEmpty || groups.length == 1,
              ),
        ],
      ),
    );
  }
}

class _AdvancedFieldGroup extends StatelessWidget {
  const _AdvancedFieldGroup({
    required this.subsystem,
    required this.definitions,
    required this.schema,
    required this.state,
    required this.colorDrafts,
    required this.onRawFieldChanged,
    required this.onColorDraftChanged,
    required this.onColorCommit,
    required this.onFieldSelected,
    required this.expanded,
  });

  final String subsystem;
  final List<GachaFieldDefinition> definitions;
  final GachaFieldSchema schema;
  final GachaCharacterState state;
  final Map<String, String> colorDrafts;
  final Future<void> Function(String field, String rawValue) onRawFieldChanged;
  final void Function(String field, String value) onColorDraftChanged;
  final Future<void> Function(String field) onColorCommit;
  final ValueChanged<String> onFieldSelected;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: ValueKey('$subsystem:$expanded'),
      initiallyExpanded: expanded,
      tilePadding: EdgeInsets.zero,
      title: Text(_humanizeFieldName(subsystem)),
      subtitle: Text('${definitions.length} field(s)'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final definition in definitions)
                if (definition.kind == GachaFieldKind.color)
                  _ColorFieldTile(
                    field: definition.field,
                    label: _humanizeFieldName(definition.field),
                    currentHex: state
                        .rawValue(schema, definition.field)
                        .toUpperCase(),
                    color: state.color(definition.field),
                    draft: colorDrafts[definition.field],
                    onDraftChanged: onColorDraftChanged,
                    onCommit: onColorCommit,
                    onFieldSelected: onFieldSelected,
                  )
                else
                  _AdvancedRawFieldTile(
                    definition: definition,
                    rawValue: state.rawValue(schema, definition.field),
                    onChanged: onRawFieldChanged,
                    onFieldSelected: onFieldSelected,
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _AdvancedRawFieldTile extends StatefulWidget {
  const _AdvancedRawFieldTile({
    required this.definition,
    required this.rawValue,
    required this.onChanged,
    required this.onFieldSelected,
  });

  final GachaFieldDefinition definition;
  final String rawValue;
  final Future<void> Function(String field, String rawValue) onChanged;
  final ValueChanged<String> onFieldSelected;

  @override
  State<_AdvancedRawFieldTile> createState() => _AdvancedRawFieldTileState();
}

class _AdvancedRawFieldTileState extends State<_AdvancedRawFieldTile> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.rawValue,
  );
  String? _errorText;

  @override
  void didUpdateWidget(covariant _AdvancedRawFieldTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawValue != widget.rawValue &&
        _controller.text == oldWidget.rawValue) {
      _controller.text = widget.rawValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final raw = _controller.text;
    if (widget.definition.kind == GachaFieldKind.numeric &&
        int.tryParse(raw) == null) {
      setState(() => _errorText = 'Enter a whole number');
      return;
    }
    if (widget.definition.kind == GachaFieldKind.metadata &&
        raw.contains('|')) {
      setState(() => _errorText = 'The | delimiter is not allowed');
      return;
    }
    setState(() => _errorText = null);
    widget.onFieldSelected(widget.definition.field);
    await widget.onChanged(widget.definition.field, raw);
  }

  @override
  Widget build(BuildContext context) {
    final definition = widget.definition;
    return SizedBox(
      width: definition.kind == GachaFieldKind.metadata ? 330 : 240,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB9C2CA)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _humanizeFieldName(definition.field),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                '[${definition.index}] ${definition.field} · ${_fieldKindLabel(definition.kind)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                keyboardType: definition.kind == GachaFieldKind.numeric
                    ? const TextInputType.numberWithOptions(signed: true)
                    : TextInputType.text,
                minLines: 1,
                maxLines: definition.kind == GachaFieldKind.metadata ? 3 : 1,
                onTap: () => widget.onFieldSelected(definition.field),
                onSubmitted: (_) => _apply(),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  errorText: _errorText,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _apply,
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _matchesAdvancedFilter(GachaFieldKind kind, _AdvancedFieldFilter filter) {
  return switch (filter) {
    _AdvancedFieldFilter.all => true,
    _AdvancedFieldFilter.metadata => kind == GachaFieldKind.metadata,
    _AdvancedFieldFilter.numeric => kind == GachaFieldKind.numeric,
    _AdvancedFieldFilter.color => kind == GachaFieldKind.color,
  };
}

String _fieldKindLabel(GachaFieldKind kind) {
  return switch (kind) {
    GachaFieldKind.metadata => 'Text',
    GachaFieldKind.numeric => 'Number',
    GachaFieldKind.color => 'Color',
  };
}

String _humanizeFieldName(String value) {
  final spaced = value.replaceAll('_', ' ').replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) {
      return '${match.group(1)} ${match.group(2)}';
    },
  );
  if (spaced.isEmpty) {
    return value;
  }
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

Set<String> _primaryEditorFieldNames() {
  return {
    for (final field in _bodyFields) field.field,
    for (final field in _headFaceFields) field.field,
    for (final field in _hairFields) field.field,
    for (final field in _clothingFields) field.field,
    for (final field in _accessoryFields) field.field,
    for (final field in _propFields) field.field,
    for (final field in _displayFields) field.field,
    for (final group in _transformGroups)
      for (final field in group.fields) field.field,
    for (final group in _colorGroups)
      for (final field in group.fields) field.field,
  };
}

List<GachaFieldDefinition> advancedEditorDefinitions(GachaFieldSchema schema) {
  final primaryFields = _primaryEditorFieldNames();
  return schema.definitions
      .where((definition) => !primaryFields.contains(definition.field))
      .toList(growable: false);
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFB9C2CA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _NumericFieldSpec {
  const _NumericFieldSpec(
    this.field,
    this.label, {
    this.minValue,
    this.maxValue,
    this.width = 208,
  });

  final String field;
  final String label;
  final int? minValue;
  final int? maxValue;
  final double width;
}

class _NumericFieldGroupSpec {
  const _NumericFieldGroupSpec(this.title, this.fields);

  final String title;
  final List<_NumericFieldSpec> fields;
}

class _TransformGroupSpec {
  const _TransformGroupSpec(this.title, this.fields);

  final String title;
  final List<_NumericFieldSpec> fields;
}

class _ColorFieldSpec {
  const _ColorFieldSpec(this.field, this.label);

  final String field;
  final String label;
}

class _ColorFieldGroupSpec {
  const _ColorFieldGroupSpec(this.title, this.fields);

  final String title;
  final List<_ColorFieldSpec> fields;
}

const List<_NumericFieldSpec> _bodyFields = [
  _NumericFieldSpec('pose', 'Pose', width: 220),
  _NumericFieldSpec('heightx', 'Height X'),
  _NumericFieldSpec('heighty', 'Height Y'),
  _NumericFieldSpec('headlayer', 'Head Layer'),
  _NumericFieldSpec('rotation', 'Rotation'),
  _NumericFieldSpec('flip', 'Flip'),
  _NumericFieldSpec('shadow', 'Shadow'),
  _NumericFieldSpec('headsize', 'Head Size', minValue: 1, maxValue: 20),
  _NumericFieldSpec('headsizey', 'Head Size Y', minValue: 1, maxValue: 20),
  _NumericFieldSpec('headflip', 'Head Flip'),
];

const List<_NumericFieldSpec> _headFaceFields = [
  _NumericFieldSpec('headshape', 'Head Shape'),
  _NumericFieldSpec('eyes1x', 'Left Eye'),
  _NumericFieldSpec('eyes2x', 'Right Eye'),
  _NumericFieldSpec('eyebrows1x', 'Left Eyebrow'),
  _NumericFieldSpec('eyebrows2x', 'Right Eyebrow'),
  _NumericFieldSpec('pupil1x', 'Left Pupil'),
  _NumericFieldSpec('pupil2x', 'Right Pupil'),
  _NumericFieldSpec('mouth', 'Mouth'),
  _NumericFieldSpec('nose', 'Nose'),
  _NumericFieldSpec('blush', 'Blush'),
  _NumericFieldSpec('faceshadow', 'Face Shadow'),
  _NumericFieldSpec('facepreset', 'Face Preset'),
  _NumericFieldSpec('highlights', 'Highlights'),
  _NumericFieldSpec('eyehigh', 'Eye Highlight'),
  _NumericFieldSpec('eyecam', 'Eye Cam'),
  _NumericFieldSpec('blushpos', 'Blush Position'),
  _NumericFieldSpec('nosepos', 'Nose Position'),
];

const List<_NumericFieldSpec> _hairFields = [
  _NumericFieldSpec('fronthair', 'Front Hair'),
  _NumericFieldSpec('rearhair', 'Rear Hair'),
  _NumericFieldSpec('backhair', 'Back Hair'),
  _NumericFieldSpec('ponytail', 'Ponytail'),
  _NumericFieldSpec('ahoge', 'Ahoge'),
];

const List<_NumericFieldSpec> _clothingFields = [
  _NumericFieldSpec('shirt', 'Shirt'),
  _NumericFieldSpec('shirtex', 'Jacket'),
  _NumericFieldSpec('sleeves1x', 'Sleeve Front'),
  _NumericFieldSpec('sleeves2x', 'Sleeve Back'),
  _NumericFieldSpec('pants1x', 'Pants Front'),
  _NumericFieldSpec('pants2x', 'Pants Back'),
  _NumericFieldSpec('socks1x', 'Socks Front'),
  _NumericFieldSpec('socks2x', 'Socks Back'),
  _NumericFieldSpec('shoes1x', 'Shoes Front'),
  _NumericFieldSpec('shoes2x', 'Shoes Back'),
  _NumericFieldSpec('belt1x', 'Belt Front'),
  _NumericFieldSpec('belt2x', 'Belt Back'),
  _NumericFieldSpec('gloves1x', 'Gloves Front'),
  _NumericFieldSpec('gloves2x', 'Gloves Back'),
  _NumericFieldSpec('wrist1x', 'Wrist Front'),
  _NumericFieldSpec('wrist2x', 'Wrist Back'),
  _NumericFieldSpec('shoulder1x', 'Shoulder Front'),
  _NumericFieldSpec('shoulder2x', 'Shoulder Back'),
  _NumericFieldSpec('hand1x', 'Hand Front'),
  _NumericFieldSpec('hand2x', 'Hand Back'),
  _NumericFieldSpec('knee1x', 'Knee Front'),
  _NumericFieldSpec('knee2x', 'Knee Back'),
  _NumericFieldSpec('logo', 'Logo'),
];

const List<_NumericFieldSpec> _accessoryFields = [
  _NumericFieldSpec('hat', 'Hat'),
  _NumericFieldSpec('glasses', 'Glasses'),
  _NumericFieldSpec('accessory1x', 'Accessory 1'),
  _NumericFieldSpec('accessory2x', 'Accessory 2'),
  _NumericFieldSpec('accessory3x', 'Accessory 3'),
  _NumericFieldSpec('other1x', 'Other 1'),
  _NumericFieldSpec('other2x', 'Other 2'),
  _NumericFieldSpec('other3x', 'Other 3'),
  _NumericFieldSpec('other4x', 'Other 4'),
];

const List<_NumericFieldSpec> _propFields = [
  _NumericFieldSpec('cape', 'Cape'),
  _NumericFieldSpec('scarf1x', 'Scarf 1'),
  _NumericFieldSpec('scarf2x', 'Scarf 2'),
  _NumericFieldSpec('wings1x', 'Wing Left'),
  _NumericFieldSpec('wings2x', 'Wing Right'),
  _NumericFieldSpec('tail', 'Tail'),
  _NumericFieldSpec('weapon1x', 'Weapon Front'),
  _NumericFieldSpec('weapon2x', 'Weapon Back'),
  _NumericFieldSpec('weaponsize1x', 'Weapon Size Front'),
  _NumericFieldSpec('weaponsize2x', 'Weapon Size Back'),
  _NumericFieldSpec('shield', 'Shield'),
  _NumericFieldSpec('special', 'Special'),
  _NumericFieldSpec('special2x', 'Special 2'),
  _NumericFieldSpec(
    'specialsizex',
    'Special Size X',
    minValue: 1,
    maxValue: 20,
  ),
  _NumericFieldSpec(
    'specialsizey',
    'Special Size Y',
    minValue: 1,
    maxValue: 20,
  ),
  _NumericFieldSpec(
    'specialsizex2x',
    'Special 2 Size X',
    minValue: 1,
    maxValue: 20,
  ),
  _NumericFieldSpec(
    'specialsizey2x',
    'Special 2 Size Y',
    minValue: 1,
    maxValue: 20,
  ),
];

const List<_NumericFieldSpec> _displayFields = [
  _NumericFieldSpec('displayhead', 'Display Head'),
  _NumericFieldSpec('displayface', 'Display Face'),
  _NumericFieldSpec('displayhair', 'Display Hair'),
  _NumericFieldSpec('displaybody', 'Display Body'),
  _NumericFieldSpec('displayshoulder', 'Display Front Shoulder'),
  _NumericFieldSpec('displayhand', 'Display Front Hand'),
  _NumericFieldSpec('displaybackshoulder', 'Display Back Shoulder'),
  _NumericFieldSpec('displaybackhand', 'Display Back Hand'),
  _NumericFieldSpec('displaythigh', 'Display Front Thigh'),
  _NumericFieldSpec('displayfoot', 'Display Front Foot'),
  _NumericFieldSpec('displaybackthigh', 'Display Back Thigh'),
  _NumericFieldSpec('displaybackfoot', 'Display Back Foot'),
  _NumericFieldSpec('displayoutline', 'Display Outline'),
];

const List<_TransformGroupSpec> _transformGroups = [
  _TransformGroupSpec('Eyes', [
    _NumericFieldSpec('leyexpos', 'Left Eye X'),
    _NumericFieldSpec('leyeypos', 'Left Eye Y'),
    _NumericFieldSpec(
      'leyesize',
      'Left Eye Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'leyesizey',
      'Left Eye Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('leyerot', 'Left Eye Rotation'),
    _NumericFieldSpec('reyexpos', 'Right Eye X'),
    _NumericFieldSpec('reyeypos', 'Right Eye Y'),
    _NumericFieldSpec(
      'reyesize',
      'Right Eye Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'reyesizey',
      'Right Eye Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('reyerot', 'Right Eye Rotation'),
  ]),
  _TransformGroupSpec('Pupils', [
    _NumericFieldSpec('lpupilxpos', 'Left Pupil X'),
    _NumericFieldSpec('lpupilypos', 'Left Pupil Y'),
    _NumericFieldSpec(
      'lpupilsize',
      'Left Pupil Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'lpupilsizey',
      'Left Pupil Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('lpupilrot', 'Left Pupil Rotation'),
    _NumericFieldSpec('rpupilxpos', 'Right Pupil X'),
    _NumericFieldSpec('rpupilypos', 'Right Pupil Y'),
    _NumericFieldSpec(
      'rpupilsize',
      'Right Pupil Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'rpupilsizey',
      'Right Pupil Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('rpupilrot', 'Right Pupil Rotation'),
  ]),
  _TransformGroupSpec('Eyebrows', [
    _NumericFieldSpec('leyebrowxpos', 'Left Brow X'),
    _NumericFieldSpec('leyebrowypos', 'Left Brow Y'),
    _NumericFieldSpec(
      'leyebrowsize',
      'Left Brow Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'leyebrowsizey',
      'Left Brow Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('leyebrowrot', 'Left Brow Rotation'),
    _NumericFieldSpec('reyebrowxpos', 'Right Brow X'),
    _NumericFieldSpec('reyebrowypos', 'Right Brow Y'),
    _NumericFieldSpec(
      'reyebrowsize',
      'Right Brow Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'reyebrowsizey',
      'Right Brow Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('reyebrowrot', 'Right Brow Rotation'),
  ]),
  _TransformGroupSpec('Mouth / Nose', [
    _NumericFieldSpec('mouthxpos', 'Mouth X'),
    _NumericFieldSpec('mouthypos', 'Mouth Y'),
    _NumericFieldSpec('mouthsize', 'Mouth Scale X', minValue: 1, maxValue: 20),
    _NumericFieldSpec('mouthsizey', 'Mouth Scale Y', minValue: 1, maxValue: 20),
    _NumericFieldSpec('mouthrot', 'Mouth Rotation'),
    _NumericFieldSpec('nosexpos', 'Nose X'),
    _NumericFieldSpec('noseypos', 'Nose Y'),
    _NumericFieldSpec('nosesize', 'Nose Scale X', minValue: 1, maxValue: 20),
    _NumericFieldSpec('nosesizey', 'Nose Scale Y', minValue: 1, maxValue: 20),
    _NumericFieldSpec('noserot', 'Nose Rotation'),
  ]),
  _TransformGroupSpec('Hair Transforms', [
    _NumericFieldSpec('fronthairxpos', 'Front Hair X'),
    _NumericFieldSpec('fronthairypos', 'Front Hair Y'),
    _NumericFieldSpec(
      'fronthairxscale',
      'Front Hair Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'fronthairyscale',
      'Front Hair Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('fronthairrot', 'Front Hair Rotation'),
    _NumericFieldSpec('backhairxpos', 'Back Hair X'),
    _NumericFieldSpec('backhairypos', 'Back Hair Y'),
    _NumericFieldSpec(
      'backhairxscale',
      'Back Hair Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'backhairyscale',
      'Back Hair Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('backhairrot', 'Back Hair Rotation'),
    _NumericFieldSpec('ponytailxpos', 'Ponytail X'),
    _NumericFieldSpec('ponytailypos', 'Ponytail Y'),
    _NumericFieldSpec(
      'ponytailxscale',
      'Ponytail Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'ponytailyscale',
      'Ponytail Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('ponytailrot', 'Ponytail Rotation'),
    _NumericFieldSpec('ahogexpos', 'Ahoge X'),
    _NumericFieldSpec('ahogeypos', 'Ahoge Y'),
    _NumericFieldSpec(
      'ahogexscale',
      'Ahoge Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'ahogeyscale',
      'Ahoge Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('ahogerot', 'Ahoge Rotation'),
  ]),
  _TransformGroupSpec('Accessory Transforms', [
    _NumericFieldSpec('hatxpos', 'Hat X'),
    _NumericFieldSpec('hatypos', 'Hat Y'),
    _NumericFieldSpec('hatsize', 'Hat Scale X', minValue: 1, maxValue: 20),
    _NumericFieldSpec('hatsizey', 'Hat Scale Y', minValue: 1, maxValue: 20),
    _NumericFieldSpec('hatrot', 'Hat Rotation'),
    _NumericFieldSpec('glassesxpos', 'Glasses X'),
    _NumericFieldSpec('glassesypos', 'Glasses Y'),
    _NumericFieldSpec(
      'glassessize',
      'Glasses Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'glassessizey',
      'Glasses Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('glassesrot', 'Glasses Rotation'),
    _NumericFieldSpec('acc1xpos', 'Accessory 1 X'),
    _NumericFieldSpec('acc1ypos', 'Accessory 1 Y'),
    _NumericFieldSpec(
      'acc1size',
      'Accessory 1 Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'acc1sizey',
      'Accessory 1 Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('acc1rot', 'Accessory 1 Rotation'),
    _NumericFieldSpec('acc2xpos', 'Accessory 2 X'),
    _NumericFieldSpec('acc2ypos', 'Accessory 2 Y'),
    _NumericFieldSpec(
      'acc2size',
      'Accessory 2 Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'acc2sizey',
      'Accessory 2 Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('acc2rot', 'Accessory 2 Rotation'),
    _NumericFieldSpec('acc3xpos', 'Accessory 3 X'),
    _NumericFieldSpec('acc3ypos', 'Accessory 3 Y'),
    _NumericFieldSpec(
      'acc3size',
      'Accessory 3 Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'acc3sizey',
      'Accessory 3 Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('acc3rot', 'Accessory 3 Rotation'),
    _NumericFieldSpec('other1xpos', 'Other 1 X'),
    _NumericFieldSpec('other1ypos', 'Other 1 Y'),
    _NumericFieldSpec(
      'other1size',
      'Other 1 Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'other1sizey',
      'Other 1 Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('other1rot', 'Other 1 Rotation'),
    _NumericFieldSpec('other2xpos', 'Other 2 X'),
    _NumericFieldSpec('other2ypos', 'Other 2 Y'),
    _NumericFieldSpec(
      'other2size',
      'Other 2 Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'other2sizey',
      'Other 2 Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('other2rot', 'Other 2 Rotation'),
    _NumericFieldSpec('other3xpos', 'Other 3 X'),
    _NumericFieldSpec('other3ypos', 'Other 3 Y'),
    _NumericFieldSpec(
      'other3size',
      'Other 3 Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'other3sizey',
      'Other 3 Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('other3rot', 'Other 3 Rotation'),
    _NumericFieldSpec('other4xpos', 'Other 4 X'),
    _NumericFieldSpec('other4ypos', 'Other 4 Y'),
    _NumericFieldSpec(
      'other4size',
      'Other 4 Scale X',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec(
      'other4sizey',
      'Other 4 Scale Y',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('other4rot', 'Other 4 Rotation'),
  ]),
  _TransformGroupSpec('Props / Outerwear', [
    _NumericFieldSpec('propxpos1x', 'Front Prop X'),
    _NumericFieldSpec('propypos1x', 'Front Prop Y'),
    _NumericFieldSpec(
      'propsize1x',
      'Front Prop Scale',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('proprot1x', 'Front Prop Rotation'),
    _NumericFieldSpec('propxpos2x', 'Back Prop X'),
    _NumericFieldSpec('propypos2x', 'Back Prop Y'),
    _NumericFieldSpec(
      'propsize2x',
      'Back Prop Scale',
      minValue: 1,
      maxValue: 20,
    ),
    _NumericFieldSpec('proprot2x', 'Back Prop Rotation'),
    _NumericFieldSpec('shieldxpos', 'Shield X'),
    _NumericFieldSpec('shieldypos', 'Shield Y'),
    _NumericFieldSpec('shieldsize', 'Shield Scale', minValue: 1, maxValue: 20),
    _NumericFieldSpec('shieldrot', 'Shield Rotation'),
    _NumericFieldSpec('capexpos', 'Cape X'),
    _NumericFieldSpec('capeypos', 'Cape Y'),
    _NumericFieldSpec('capesize', 'Cape Scale X', minValue: 1, maxValue: 20),
    _NumericFieldSpec('capesizey', 'Cape Scale Y', minValue: 1, maxValue: 20),
    _NumericFieldSpec('caperot', 'Cape Rotation'),
    _NumericFieldSpec('tailxpos', 'Tail X'),
    _NumericFieldSpec('tailypos', 'Tail Y'),
    _NumericFieldSpec('tailsize', 'Tail Scale X', minValue: 1, maxValue: 20),
    _NumericFieldSpec('tailsizey', 'Tail Scale Y', minValue: 1, maxValue: 20),
    _NumericFieldSpec('tailrot', 'Tail Rotation'),
    _NumericFieldSpec('wingxpos', 'Wing X'),
    _NumericFieldSpec('wingypos', 'Wing Y'),
    _NumericFieldSpec('wingsize', 'Wing Scale X', minValue: 1, maxValue: 20),
    _NumericFieldSpec('wingsizey', 'Wing Scale Y', minValue: 1, maxValue: 20),
    _NumericFieldSpec('wingrot', 'Wing Rotation'),
    _NumericFieldSpec('specialxpos', 'Special X'),
    _NumericFieldSpec('specialypos', 'Special Y'),
    _NumericFieldSpec('specialxpos2x', 'Special 2 X'),
    _NumericFieldSpec('specialypos2x', 'Special 2 Y'),
    _NumericFieldSpec('specialrot', 'Special Rotation'),
    _NumericFieldSpec('specialrot2x', 'Special 2 Rotation'),
  ]),
];

const List<_ColorFieldGroupSpec> _colorGroups = [
  _ColorFieldGroupSpec('Skin', [
    _ColorFieldSpec('skincolor1x', 'Skin Fill'),
    _ColorFieldSpec('skincolor2x', 'Skin Outline'),
  ]),
  _ColorFieldGroupSpec('Hair', [
    _ColorFieldSpec('rearhaircolor1x', 'Rear Hair 1'),
    _ColorFieldSpec('rearhaircolor2x', 'Rear Hair 2'),
    _ColorFieldSpec('rearhaircolor3x', 'Rear Hair 3'),
    _ColorFieldSpec('fronthaircolor1x', 'Front Hair 1'),
    _ColorFieldSpec('fronthaircolor2x', 'Front Hair 2'),
    _ColorFieldSpec('fronthaircolor3x', 'Front Hair 3'),
    _ColorFieldSpec('backhaircolor1x', 'Back Hair 1'),
    _ColorFieldSpec('backhaircolor2x', 'Back Hair 2'),
    _ColorFieldSpec('backhaircolor3x', 'Back Hair 3'),
    _ColorFieldSpec('ponytailcolor1x', 'Ponytail 1'),
    _ColorFieldSpec('ponytailcolor2x', 'Ponytail 2'),
    _ColorFieldSpec('ponytailcolor3x', 'Ponytail 3'),
    _ColorFieldSpec('ahogecolor1x', 'Ahoge 1'),
    _ColorFieldSpec('ahogecolor2x', 'Ahoge 2'),
    _ColorFieldSpec('ahogecolor3x', 'Ahoge 3'),
    _ColorFieldSpec('hairacccolorx', 'Hair Accessory'),
    _ColorFieldSpec('hairtipscolorx', 'Hair Tips'),
  ]),
  _ColorFieldGroupSpec('Eyes / Pupils', [
    _ColorFieldSpec('eye1color1x', 'Left Eye 1'),
    _ColorFieldSpec('eye1color2x', 'Left Eye 2'),
    _ColorFieldSpec('eye1color3x', 'Left Eye 3'),
    _ColorFieldSpec('eye2color1x', 'Right Eye 1'),
    _ColorFieldSpec('eye2color2x', 'Right Eye 2'),
    _ColorFieldSpec('eye2color3x', 'Right Eye 3'),
    _ColorFieldSpec('pupil1color1x', 'Left Pupil 1'),
    _ColorFieldSpec('pupil1color2x', 'Left Pupil 2'),
    _ColorFieldSpec('pupil2color1x', 'Right Pupil 1'),
    _ColorFieldSpec('pupil2color2x', 'Right Pupil 2'),
  ]),
  _ColorFieldGroupSpec('Face', [
    _ColorFieldSpec('eyebrows1color1x', 'Left Brow 1'),
    _ColorFieldSpec('eyebrows1color2x', 'Left Brow 2'),
    _ColorFieldSpec('eyebrows2color1x', 'Right Brow 1'),
    _ColorFieldSpec('eyebrows2color2x', 'Right Brow 2'),
    _ColorFieldSpec('blushcolorx', 'Blush'),
    _ColorFieldSpec('nosecolor1x', 'Nose 1'),
    _ColorFieldSpec('nosecolor2x', 'Nose 2'),
    _ColorFieldSpec('mouthcolor1x', 'Mouth 1'),
    _ColorFieldSpec('mouthcolor2x', 'Mouth 2'),
    _ColorFieldSpec('mouthcolor3x', 'Mouth 3'),
    _ColorFieldSpec('faceshadowcolorx', 'Face Shadow'),
  ]),
  _ColorFieldGroupSpec('Clothing Upper', [
    _ColorFieldSpec('shirtcolor1x', 'Shirt 1'),
    _ColorFieldSpec('shirtcolor2x', 'Shirt 2'),
    _ColorFieldSpec('shirtcolor3x', 'Shirt 3'),
    _ColorFieldSpec('shirtexcolor1x', 'Jacket 1'),
    _ColorFieldSpec('shirtexcolor2x', 'Jacket 2'),
    _ColorFieldSpec('shirtexcolor3x', 'Jacket 3'),
    _ColorFieldSpec('shoulder1color1x', 'Shoulder Front 1'),
    _ColorFieldSpec('shoulder1color2x', 'Shoulder Front 2'),
    _ColorFieldSpec('shoulder1color3x', 'Shoulder Front 3'),
    _ColorFieldSpec('shoulder2color1x', 'Shoulder Back 1'),
    _ColorFieldSpec('shoulder2color2x', 'Shoulder Back 2'),
    _ColorFieldSpec('shoulder2color3x', 'Shoulder Back 3'),
    _ColorFieldSpec('sleeves1color1x', 'Sleeve Front 1'),
    _ColorFieldSpec('sleeves1color2x', 'Sleeve Front 2'),
    _ColorFieldSpec('sleeves1color3x', 'Sleeve Front 3'),
    _ColorFieldSpec('sleeves2color1x', 'Sleeve Back 1'),
    _ColorFieldSpec('sleeves2color2x', 'Sleeve Back 2'),
    _ColorFieldSpec('sleeves2color3x', 'Sleeve Back 3'),
    _ColorFieldSpec('belt1color1x', 'Belt Front 1'),
    _ColorFieldSpec('belt1color2x', 'Belt Front 2'),
    _ColorFieldSpec('belt1color3x', 'Belt Front 3'),
    _ColorFieldSpec('belt2color1x', 'Belt Back 1'),
    _ColorFieldSpec('belt2color2x', 'Belt Back 2'),
    _ColorFieldSpec('belt2color3x', 'Belt Back 3'),
    _ColorFieldSpec('gloves1color1x', 'Glove Front 1'),
    _ColorFieldSpec('gloves1color2x', 'Glove Front 2'),
    _ColorFieldSpec('gloves1color3x', 'Glove Front 3'),
    _ColorFieldSpec('gloves2color1x', 'Glove Back 1'),
    _ColorFieldSpec('gloves2color2x', 'Glove Back 2'),
    _ColorFieldSpec('gloves2color3x', 'Glove Back 3'),
    _ColorFieldSpec('wrist1color1x', 'Wrist Front 1'),
    _ColorFieldSpec('wrist1color2x', 'Wrist Front 2'),
    _ColorFieldSpec('wrist1color3x', 'Wrist Front 3'),
    _ColorFieldSpec('wrist2color1x', 'Wrist Back 1'),
    _ColorFieldSpec('wrist2color2x', 'Wrist Back 2'),
    _ColorFieldSpec('wrist2color3x', 'Wrist Back 3'),
    _ColorFieldSpec('logocolorx', 'Logo'),
  ]),
  _ColorFieldGroupSpec('Clothing Lower', [
    _ColorFieldSpec('pants1color1x', 'Pants Front 1'),
    _ColorFieldSpec('pants1color2x', 'Pants Front 2'),
    _ColorFieldSpec('pants1color3x', 'Pants Front 3'),
    _ColorFieldSpec('pants2color1x', 'Pants Back 1'),
    _ColorFieldSpec('pants2color2x', 'Pants Back 2'),
    _ColorFieldSpec('pants2color3x', 'Pants Back 3'),
    _ColorFieldSpec('socks1color1x', 'Socks Front 1'),
    _ColorFieldSpec('socks1color2x', 'Socks Front 2'),
    _ColorFieldSpec('socks1color3x', 'Socks Front 3'),
    _ColorFieldSpec('socks2color1x', 'Socks Back 1'),
    _ColorFieldSpec('socks2color2x', 'Socks Back 2'),
    _ColorFieldSpec('socks2color3x', 'Socks Back 3'),
    _ColorFieldSpec('shoes1color1x', 'Shoes Front 1'),
    _ColorFieldSpec('shoes1color2x', 'Shoes Front 2'),
    _ColorFieldSpec('shoes1color3x', 'Shoes Front 3'),
    _ColorFieldSpec('shoes2color1x', 'Shoes Back 1'),
    _ColorFieldSpec('shoes2color2x', 'Shoes Back 2'),
    _ColorFieldSpec('shoes2color3x', 'Shoes Back 3'),
    _ColorFieldSpec('knee1color1x', 'Knee Front 1'),
    _ColorFieldSpec('knee1color2x', 'Knee Front 2'),
    _ColorFieldSpec('knee1color3x', 'Knee Front 3'),
    _ColorFieldSpec('knee2color1x', 'Knee Back 1'),
    _ColorFieldSpec('knee2color2x', 'Knee Back 2'),
    _ColorFieldSpec('knee2color3x', 'Knee Back 3'),
  ]),
  _ColorFieldGroupSpec('Accessories / Props', [
    _ColorFieldSpec('glassescolor1x', 'Glasses 1'),
    _ColorFieldSpec('glassescolor2x', 'Glasses 2'),
    _ColorFieldSpec('glassescolor3x', 'Glasses 3'),
    _ColorFieldSpec('accessory1color1x', 'Accessory 1 / 1'),
    _ColorFieldSpec('accessory1color2x', 'Accessory 1 / 2'),
    _ColorFieldSpec('accessory1color3x', 'Accessory 1 / 3'),
    _ColorFieldSpec('accessory2color1x', 'Accessory 2 / 1'),
    _ColorFieldSpec('accessory2color2x', 'Accessory 2 / 2'),
    _ColorFieldSpec('accessory2color3x', 'Accessory 2 / 3'),
    _ColorFieldSpec('accessory3color1x', 'Accessory 3 / 1'),
    _ColorFieldSpec('accessory3color2x', 'Accessory 3 / 2'),
    _ColorFieldSpec('accessory3color3x', 'Accessory 3 / 3'),
    _ColorFieldSpec('hatcolor1x', 'Hat 1'),
    _ColorFieldSpec('hatcolor2x', 'Hat 2'),
    _ColorFieldSpec('hatcolor3x', 'Hat 3'),
    _ColorFieldSpec('other1color1x', 'Other 1 / 1'),
    _ColorFieldSpec('other1color2x', 'Other 1 / 2'),
    _ColorFieldSpec('other1color3x', 'Other 1 / 3'),
    _ColorFieldSpec('other2color1x', 'Other 2 / 1'),
    _ColorFieldSpec('other2color2x', 'Other 2 / 2'),
    _ColorFieldSpec('other2color3x', 'Other 2 / 3'),
    _ColorFieldSpec('other3color1x', 'Other 3 / 1'),
    _ColorFieldSpec('other3color2x', 'Other 3 / 2'),
    _ColorFieldSpec('other3color3x', 'Other 3 / 3'),
    _ColorFieldSpec('other4color1x', 'Other 4 / 1'),
    _ColorFieldSpec('other4color2x', 'Other 4 / 2'),
    _ColorFieldSpec('other4color3x', 'Other 4 / 3'),
    _ColorFieldSpec('capecolor1x', 'Cape 1'),
    _ColorFieldSpec('capecolor2x', 'Cape 2'),
    _ColorFieldSpec('capecolor3x', 'Cape 3'),
    _ColorFieldSpec('scarf1color1x', 'Scarf 1 / 1'),
    _ColorFieldSpec('scarf1color2x', 'Scarf 1 / 2'),
    _ColorFieldSpec('scarf1color3x', 'Scarf 1 / 3'),
    _ColorFieldSpec('scarf2color1x', 'Scarf 2 / 1'),
    _ColorFieldSpec('scarf2color2x', 'Scarf 2 / 2'),
    _ColorFieldSpec('scarf2color3x', 'Scarf 2 / 3'),
    _ColorFieldSpec('wings1color1x', 'Wing Left 1'),
    _ColorFieldSpec('wings1color2x', 'Wing Left 2'),
    _ColorFieldSpec('wings1color3x', 'Wing Left 3'),
    _ColorFieldSpec('wings2color1x', 'Wing Right 1'),
    _ColorFieldSpec('wings2color2x', 'Wing Right 2'),
    _ColorFieldSpec('wings2color3x', 'Wing Right 3'),
    _ColorFieldSpec('tailcolor1x', 'Tail 1'),
    _ColorFieldSpec('tailcolor2x', 'Tail 2'),
    _ColorFieldSpec('tailcolor3x', 'Tail 3'),
    _ColorFieldSpec('weapon1color1x', 'Weapon Front 1'),
    _ColorFieldSpec('weapon1color2x', 'Weapon Front 2'),
    _ColorFieldSpec('weapon1color3x', 'Weapon Front 3'),
    _ColorFieldSpec('weapon2color1x', 'Weapon Back 1'),
    _ColorFieldSpec('weapon2color2x', 'Weapon Back 2'),
    _ColorFieldSpec('weapon2color3x', 'Weapon Back 3'),
    _ColorFieldSpec('shieldcolor1x', 'Shield 1'),
    _ColorFieldSpec('shieldcolor2x', 'Shield 2'),
    _ColorFieldSpec('shieldcolor3x', 'Shield 3'),
  ]),
  _ColorFieldGroupSpec('Outlines / UI / Background', [
    _ColorFieldSpec('tintcolorx', 'Tint'),
    _ColorFieldSpec('tintspecialcolorx', 'Special Tint'),
    _ColorFieldSpec('tintspecialcolor2x', 'Special Tint 2'),
    _ColorFieldSpec('namecolorx', 'Name'),
    _ColorFieldSpec('chatcolorx', 'Chat'),
    _ColorFieldSpec('bubblecolorx', 'Bubble 1'),
    _ColorFieldSpec('bubblecolor2x', 'Bubble 2'),
    _ColorFieldSpec('bgtintcolorx', 'Background Tint'),
    _ColorFieldSpec('bgcolor1x', 'Background 1'),
    _ColorFieldSpec('bgcolor2x', 'Background 2'),
    _ColorFieldSpec('fgtintcolorx', 'Foreground Tint'),
  ]),
];
