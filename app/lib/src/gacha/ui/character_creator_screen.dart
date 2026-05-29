import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../code/gacha_character_state.dart';
import '../code/gacha_code_parser.dart';
import '../code/gacha_field_schema.dart';
import '../data/resolver_tables.dart';
import '../render/character_renderer.dart';
import '../render/render_part.dart';
import '../render/gacha_game_canvas.dart';
import '../render/gacha_joint_component.dart';
import '../render/tween_engine.dart';
import '../render/video_export_manager.dart';
import 'widgets/timeline_track.dart';
import 'widgets/collapsible_sidebar.dart';
import 'widgets/canvas_preview.dart';
import 'debug_render_panel.dart';
import 'editor_helpers.dart';

class CharacterCreatorScreen extends StatefulWidget {
  const CharacterCreatorScreen({super.key});

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
            );
          },
        ),
      ),
    );
  }
}

class _CharacterEditorShell extends StatefulWidget {
  const _CharacterEditorShell({required this.tables, required this.assetStore});

  final ResolverTables tables;
  final GachaAssetStore assetStore;

  @override
  State<_CharacterEditorShell> createState() => _CharacterEditorShellState();
}

class _CharacterEditorShellState extends State<_CharacterEditorShell> {
  late final GachaCodeParser _parser = GachaCodeParser(widget.tables.schema);
  late final CharacterRenderer _renderer = CharacterRenderer(
    tables: widget.tables,
    assetStore: widget.assetStore,
  );

  final GachaGameCanvas _game = GachaGameCanvas();
  final TextEditingController _codeController = TextEditingController();
  final Map<String, Future<String>> _fixtureCodeCache = {};
  final Map<String, String> _colorDrafts = {};

  String? _selectedCaseId;
  String _baselineLabel = 'fixture';
  String? _selectedField;
  GachaCharacterState? _baselineState;
  GachaCharacterState? _currentState;
  ResolvedScene? _scene;
  bool _sceneLoading = false;
  String? _messageText;
  bool _messageIsError = false;
  int _renderSerial = 0;

  // Animation timeline state
  double _currentTime = 0.0;
  final double _maxDuration = 4.0;
  bool _isPlaying = false;
  final List<double> _keyframes = [0.0, 1.0, 2.0, 3.0];

  final Map<String, List<GachaKeyframe>> _animationTracks = {
    'head': [
      const GachaKeyframe(time: 0.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
      const GachaKeyframe(time: 1.0, position: Offset.zero, scale: Offset(1, 1), angle: -10.0),
      const GachaKeyframe(time: 2.0, position: Offset.zero, scale: Offset(1, 1), angle: 10.0),
      const GachaKeyframe(time: 3.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
    ],
    'shoulder_front': [
      const GachaKeyframe(time: 0.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
      const GachaKeyframe(time: 1.0, position: Offset.zero, scale: Offset(1, 1), angle: 15.0),
      const GachaKeyframe(time: 2.0, position: Offset.zero, scale: Offset(1, 1), angle: -15.0),
      const GachaKeyframe(time: 3.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
    ],
    'shoulder_back': [
      const GachaKeyframe(time: 0.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
      const GachaKeyframe(time: 1.0, position: Offset.zero, scale: Offset(1, 1), angle: -15.0),
      const GachaKeyframe(time: 2.0, position: Offset.zero, scale: Offset(1, 1), angle: 15.0),
      const GachaKeyframe(time: 3.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
    ],
    'thigh_front': [
      const GachaKeyframe(time: 0.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
      const GachaKeyframe(time: 1.0, position: Offset.zero, scale: Offset(1, 1), angle: 8.0),
      const GachaKeyframe(time: 2.0, position: Offset.zero, scale: Offset(1, 1), angle: -8.0),
      const GachaKeyframe(time: 3.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
    ],
    'thigh_back': [
      const GachaKeyframe(time: 0.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
      const GachaKeyframe(time: 1.0, position: Offset.zero, scale: Offset(1, 1), angle: -8.0),
      const GachaKeyframe(time: 2.0, position: Offset.zero, scale: Offset(1, 1), angle: 8.0),
      const GachaKeyframe(time: 3.0, position: Offset.zero, scale: Offset(1, 1), angle: 0.0),
    ],
  };

  @override
  void initState() {
    super.initState();
    final firstCase = widget.tables.editorFixtures.first;
    _selectedCaseId = firstCase.id;
    _loadFixture(firstCase.id);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
    if (_isPlaying) {
      _runPlaybackLoop();
    }
  }

  Future<void> _updateFrameAtTime(double time) async {
    _game.updateAnimations(time, _animationTracks);
    final currentState = _currentState;
    if (currentState == null) return;

    var stateForFrame = currentState;

    // Speech mouth lip-sync animation (cycles every 0.8 seconds)
    final speechTime = time % 0.8;
    int mouthOverride = currentState.numeric('mouth');
    if (speechTime < 0.2) {
      mouthOverride = 2; // partially open
    } else if (speechTime < 0.4) {
      mouthOverride = 5; // wide open
    } else if (speechTime < 0.6) {
      mouthOverride = 7; // narrow speak
    }

    // Dynamic eyes blink animation (every 2.5 seconds, lasts for 0.15s)
    final blinkTime = time % 2.5;
    final isBlinking = blinkTime < 0.15;
    int eyeOverride = currentState.numeric('eyes1x');
    if (isBlinking) {
      eyeOverride = 3; // closed eyes
    }

    if (mouthOverride != currentState.numeric('mouth')) {
      stateForFrame = stateForFrame.updateNumericField(widget.tables.schema, 'mouth', mouthOverride);
    }
    if (isBlinking) {
      stateForFrame = stateForFrame.updateNumericField(widget.tables.schema, 'eyes1x', eyeOverride);
      stateForFrame = stateForFrame.updateNumericField(widget.tables.schema, 'eyes2x', eyeOverride);
    }

    final frameScene = await _renderer.buildScene(stateForFrame);
    _game.updateScene(frameScene, stateForFrame, widget.tables);
  }

  void _runPlaybackLoop() async {
    while (_isPlaying && mounted) {
      await Future.delayed(const Duration(milliseconds: 33));
      if (!_isPlaying || !mounted) break;
      
      final nextTime = _currentTime + 0.033;
      final time = nextTime >= _maxDuration ? 0.0 : nextTime;

      // Update Gacha joints, child part local propagation, speech, and blinks natively
      await _updateFrameAtTime(time);

      setState(() {
        _currentTime = time;
      });
    }
  }

  void _onTimeChanged(double time) async {
    await _updateFrameAtTime(time);
    setState(() {
      _currentTime = time;
    });
  }

  void _addKeyframe() {
    setState(() {
      if (!_keyframes.contains(_currentTime)) {
        _keyframes.add(_currentTime);
        _keyframes.sort();
        _messageText = 'Added skeletal keyframe marker at ${_currentTime.toStringAsFixed(2)}s';
        _messageIsError = false;
      }
    });
  }

  void _handleStrokesDrawn(List<Offset> stroke) {
    try {
      final headJoint = _game.descendants().whereType<GachaJointComponent>().firstWhere((j) => j.name == 'head');
      headJoint.addDrawingStroke(stroke);
      setState(() {
        _messageText = 'Rigged vector stroke with ${stroke.length} points directly onto the head joint!';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _messageText = 'Captured stroke with ${stroke.length} points, but failed to rig onto head joint: $e';
        _messageIsError = true;
      });
    }
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
      color: const Color(0xFF0F1216), // Neutral dark mode backdrop
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
              onChanged: _loadFixture,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Main canvas & timeline workspace
                  Expanded(
                    child: Column(
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
                        const SizedBox(height: 16),
                        TimelineTrack(
                          currentTime: _currentTime,
                          maxDuration: _maxDuration,
                          isPlaying: _isPlaying,
                          onTimeChanged: _onTimeChanged,
                          onPlaybackToggle: _togglePlayback,
                          keyframes: _keyframes,
                          onAddKeyframe: _addKeyframe,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Collapsible inspector sidebar
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
                      schema: widget.tables.schema,
                      tables: widget.tables,
                      colorDrafts: _colorDrafts,
                      selectedField: _selectedField,
                      onImportPressed: _importFromTextarea,
                      onExportPressed: _exportCurrentState,
                      onExportVideoPressed: _exportVideo,
                      onResetToFixturePressed: _resetToSelectedFixture,
                      onResetToBaselinePressed: _resetToBaseline,
                      onNumericFieldChanged: _updateNumericField,
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

  Future<void> _exportVideo() async {
    final scene = _scene;
    final currentState = _currentState;
    if (scene == null || currentState == null) {
      setState(() {
        _messageText = 'Failed to export video: scene or state is not loaded.';
        _messageIsError = true;
      });
      return;
    }
    setState(() {
      _sceneLoading = true;
      _messageText = 'Rendering rigged keyframe animation frame-by-frame...';
      _messageIsError = false;
    });
    try {
      final path = await VideoExportManager.exportScene(
        scene: scene,
        state: currentState,
        tables: widget.tables,
        animationTracks: _animationTracks,
        outputFileName: 'gacha_anim_${DateTime.now().millisecondsSinceEpoch}.mp4',
        width: 720,
        height: 1280,
      );
      setState(() {
        _sceneLoading = false;
        _messageText = 'Video exported successfully to: $path';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _sceneLoading = false;
        _messageText = 'Failed to export video: $e';
        _messageIsError = true;
      });
    }
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
    final nextValue = clampToEditorRange(
      widget.tables.editorValueRangeFor(field),
      value,
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
    );
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
  }) async {
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
      final scene = await _renderer.buildScene(next);
      if (!mounted || serial != _renderSerial) {
        return;
      }
      setState(() {
        _scene = scene;
        _sceneLoading = false;
      });
      _game.updateAnimations(_currentTime, _animationTracks);
      _game.updateScene(scene, next, widget.tables);
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

  ValidationCaseDescriptor _fixtureDescriptorFor(String id) {
    return widget.tables.editorFixtures.firstWhere((item) => item.id == id);
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.selectedCaseId,
    required this.cases,
    required this.changeCount,
    required this.resolvedPartCount,
    required this.onChanged,
  });

  final String selectedCaseId;
  final List<ValidationCaseDescriptor> cases;
  final int changeCount;
  final int resolvedPartCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = cases.firstWhere(
      (item) => item.id == selectedCaseId,
      orElse: () => cases.first,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFB9C2CA)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gacha Character Editor / Renderer Harness',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Dense schema-driven editing against the canonical 445-field character state.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$changeCount changed fields • $resolvedPartCount resolved parts',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 320,
            child: OutlinedButton(
              onPressed: () async {
                final selectedId = await showDialog<String>(
                  context: context,
                  builder: (context) => _FixturePickerDialog(
                    cases: cases,
                    selectedCaseId: selectedCaseId,
                  ),
                );
                if (selectedId != null) {
                  onChanged(selectedId);
                }
              },
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selected.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          selected.group,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    required this.schema,
    required this.tables,
    required this.colorDrafts,
    required this.selectedField,
    required this.onImportPressed,
    required this.onExportPressed,
    required this.onExportVideoPressed,
    required this.onResetToFixturePressed,
    required this.onResetToBaselinePressed,
    required this.onNumericFieldChanged,
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
  final GachaFieldSchema schema;
  final ResolverTables tables;
  final Map<String, String> colorDrafts;
  final String? selectedField;
  final VoidCallback onImportPressed;
  final VoidCallback onExportPressed;
  final VoidCallback onExportVideoPressed;
  final VoidCallback onResetToFixturePressed;
  final VoidCallback onResetToBaselinePressed;
  final Future<void> Function(String field, int value) onNumericFieldChanged;
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
                    OutlinedButton(
                      onPressed: onExportPressed,
                      child: const Text('Export To Buffer'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.video_library),
                      onPressed: onExportVideoPressed,
                      label: const Text('Export Video (MP4)'),
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
    final minValue = spec.minValue ?? fallbackRange?.minValue;
    final maxValue = spec.maxValue ?? fallbackRange?.maxValue;
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
