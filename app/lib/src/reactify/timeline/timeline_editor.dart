import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../commands/commands.dart';
import '../project/project.dart';
import '../studio/studio_project_controller.dart';
import 'media_kit_playback_node.dart';
import 'project_bin_browser.dart';
import 'timeline_interval_index.dart';
import 'timeline_playback_engine.dart';
import 'timeline_preview.dart';
import 'timeline_shortcuts.dart';

class TimelineWorkspace extends StatelessWidget {
  const TimelineWorkspace({super.key, required this.controller});

  final StudioProjectController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1050) {
          return Row(
            children: [
              SizedBox(
                width: 286,
                child: ProjectBinBrowser(controller: controller),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: TimelineEditor(controller: controller)),
            ],
          );
        }
        return TimelineEditor(controller: controller);
      },
    );
  }
}

class TimelineEditor extends StatefulWidget {
  const TimelineEditor({
    super.key,
    required this.controller,
    this.playbackNodeFactory,
  });

  final StudioProjectController controller;
  final TimelinePlaybackNodeFactory? playbackNodeFactory;

  @override
  State<TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineEditorState extends State<TimelineEditor> {
  static const _headerWidth = 224.0;
  static const _rulerHeight = 38.0;
  static const _trackHeight = 58.0;

  final _horizontalController = ScrollController();
  final _headerVerticalController = ScrollController();
  final _trackVerticalController = ScrollController();
  final Set<ClipId> _selectedClipIds = {};
  final List<_ClipboardClip> _clipboard = [];
  bool _syncingVertical = false;
  bool _snapping = true;
  double _zoom = 1;
  TimelineTool _tool = TimelineTool.selection;
  Timer? _playbackTimer;
  int _shuttleDirection = 0;
  int _shuttleSpeed = 1;
  int _idSerial = 0;
  late TimelinePlaybackEngine _playbackEngine;

  double get _pixelsPerFrame => 1.2 * _zoom;

  @override
  void initState() {
    super.initState();
    _createPlaybackEngine();
    widget.controller.addListener(_handleProjectChange);
    _headerVerticalController.addListener(_syncFromHeaders);
    _trackVerticalController.addListener(_syncFromTracks);
  }

  @override
  void didUpdateWidget(covariant TimelineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleProjectChange);
      widget.controller.addListener(_handleProjectChange);
      _selectedClipIds.clear();
      _replacePlaybackEngine();
    } else if (oldWidget.playbackNodeFactory != widget.playbackNodeFactory) {
      _replacePlaybackEngine();
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    widget.controller.removeListener(_handleProjectChange);
    _playbackEngine.removeListener(_handlePlaybackChange);
    unawaited(_playbackEngine.close());
    _headerVerticalController
      ..removeListener(_syncFromHeaders)
      ..dispose();
    _trackVerticalController
      ..removeListener(_syncFromTracks)
      ..dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final timeline = widget.controller.selectedTimeline;
        final index = TimelineIntervalIndex(timeline);
        final validClipIds = {
          for (final track in timeline.tracks.values) ...track.clips.keys,
        };
        _selectedClipIds.removeWhere((id) => !validClipIds.contains(id));
        return TimelineShortcutActions(
          callbacks: TimelineShortcutCallbacks(
            togglePlayback: _togglePlayback,
            shuttle: _shuttle,
            stop: _stopPlayback,
            stepFrame: _stepFrame,
            split: () => _guard(_splitSelection),
            delete: (ripple) => _guard(() => _deleteSelection(ripple)),
            copy: _copySelection,
            paste: () => _guard(_pasteSelection),
            undo: () => _guard(widget.controller.undo),
            redo: () => _guard(widget.controller.redo),
            toggleSnapping: () => setState(() => _snapping = !_snapping),
            addMarker: () => _guard(_addMarker),
            zoom: _changeZoom,
            navigateEdit: (direction) => _navigateEdit(index, direction),
            selectTool: (tool) => setState(() => _tool = tool),
          ),
          child: Material(
            color: const Color(0xFF0D1017),
            child: Column(
              children: [
                SizedBox(
                  height: 190,
                  child: TimelinePreview(
                    engine: _playbackEngine,
                    timeline: timeline,
                  ),
                ),
                const Divider(height: 1),
                _TransportBar(
                  timeline: timeline,
                  playheadFrame: widget.controller.playheadFrame,
                  playing: _playbackEngine.isPlaying || _shuttleDirection != 0,
                  shuttleDirection: _shuttleDirection,
                  shuttleSpeed: _shuttleSpeed,
                  snapping: _snapping,
                  zoom: _zoom,
                  selectedCount: _selectedClipIds.length,
                  tool: _tool,
                  onTogglePlayback: _togglePlayback,
                  onStop: _stopPlayback,
                  onSnappingChanged: (value) =>
                      setState(() => _snapping = value),
                  onZoomChanged: (value) => _setZoom(value),
                  onToolChanged: (value) => setState(() => _tool = value),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: _headerWidth,
                        child: Column(
                          children: [
                            const SizedBox(
                              height: _rulerHeight,
                              child: _TrackHeaderTitle(),
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: _headerVerticalController,
                                itemExtent: _trackHeight,
                                itemCount: timeline.trackOrder.length,
                                itemBuilder: (context, row) {
                                  final track = timeline
                                      .tracks[timeline.trackOrder[row]]!;
                                  return _TrackHeader(
                                    track: track,
                                    onChanged: (next) =>
                                        _guard(() => _updateTrack(next)),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final timelineWidth = math.max(
                              constraints.maxWidth,
                              timeline.durationFrames * _pixelsPerFrame,
                            );
                            return Scrollbar(
                              controller: _horizontalController,
                              thumbVisibility: true,
                              notificationPredicate: (notification) =>
                                  notification.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: _horizontalController,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: timelineWidth,
                                  height: constraints.maxHeight,
                                  child: Column(
                                    children: [
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: (details) =>
                                            _setPlayheadFromPixels(
                                              details.localPosition.dx,
                                              timeline,
                                            ),
                                        child: SizedBox(
                                          height: _rulerHeight,
                                          child: CustomPaint(
                                            painter: _TimelineRulerPainter(
                                              timeline: timeline,
                                              pixelsPerFrame: _pixelsPerFrame,
                                              playheadFrame: widget
                                                  .controller
                                                  .playheadFrame,
                                            ),
                                            child: const SizedBox.expand(),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: ListView.builder(
                                          controller: _trackVerticalController,
                                          itemExtent: _trackHeight,
                                          itemCount: timeline.trackOrder.length,
                                          itemBuilder: (context, row) {
                                            final track =
                                                timeline.tracks[timeline
                                                    .trackOrder[row]]!;
                                            return _TrackLane(
                                              track: track,
                                              index: index,
                                              horizontalController:
                                                  _horizontalController,
                                              viewportWidth:
                                                  constraints.maxWidth,
                                              pixelsPerFrame: _pixelsPerFrame,
                                              playheadFrame: widget
                                                  .controller
                                                  .playheadFrame,
                                              selectedClipIds: _selectedClipIds,
                                              tool: _tool,
                                              onEmptyTap: (pixels) =>
                                                  _setPlayheadFromPixels(
                                                    pixels,
                                                    timeline,
                                                  ),
                                              onClipTap: _selectClip,
                                              onClipMove: (clip, frame) =>
                                                  _guard(
                                                    () => _moveClip(
                                                      track,
                                                      clip,
                                                      frame,
                                                      index,
                                                    ),
                                                  ),
                                              onClipTrim:
                                                  (
                                                    clip,
                                                    startDelta,
                                                    endDelta,
                                                  ) => _guard(
                                                    () => _trimClip(
                                                      clip,
                                                      startDelta,
                                                      endDelta,
                                                      index,
                                                    ),
                                                  ),
                                              onBlade: (clip, frame) => _guard(
                                                () => _splitClipAt(clip, frame),
                                              ),
                                            );
                                          },
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleProjectChange() {
    _playbackEngine.updateProject(
      project: widget.controller.project,
      timeline: widget.controller.selectedTimeline,
      frame: widget.controller.playheadFrame,
      projectLocation: widget.controller.projectLocation,
    );
    if (mounted) setState(() {});
  }

  void _handlePlaybackChange() {
    if (mounted) setState(() {});
  }

  void _createPlaybackEngine() {
    _playbackEngine = TimelinePlaybackEngine(
      project: widget.controller.project,
      timeline: widget.controller.selectedTimeline,
      initialFrame: widget.controller.playheadFrame,
      projectLocation: widget.controller.projectLocation,
      nodeFactory:
          widget.playbackNodeFactory ??
          const MediaKitTimelinePlaybackNodeFactory(),
      onFrameChanged: _handlePlaybackFrame,
    )..addListener(_handlePlaybackChange);
  }

  void _replacePlaybackEngine() {
    final previous = _playbackEngine;
    previous.removeListener(_handlePlaybackChange);
    unawaited(previous.close());
    _createPlaybackEngine();
  }

  void _handlePlaybackFrame(int frame) {
    if (widget.controller.playheadFrame != frame) {
      widget.controller.setPlayhead(frame);
    }
  }

  void _syncFromHeaders() =>
      _syncVertical(_headerVerticalController, _trackVerticalController);

  void _syncFromTracks() =>
      _syncVertical(_trackVerticalController, _headerVerticalController);

  void _syncVertical(ScrollController source, ScrollController target) {
    if (_syncingVertical || !source.hasClients || !target.hasClients) return;
    _syncingVertical = true;
    target.jumpTo(source.offset.clamp(0, target.position.maxScrollExtent));
    _syncingVertical = false;
  }

  void _updateTrack(TimelineTrack track) {
    final timeline = widget.controller.selectedTimeline;
    widget.controller.executeCommand(
      UpsertProjectEntityCommand(
        kind: ProjectEntityKind.timeline,
        entity: timeline.copyWith(
          tracks: {...timeline.tracks, track.id: track},
        ),
      ),
    );
  }

  void _selectClip(TimelineClip clip, bool additive) {
    setState(() {
      if (!additive) _selectedClipIds.clear();
      if (additive && _selectedClipIds.contains(clip.id)) {
        _selectedClipIds.remove(clip.id);
      } else {
        _selectedClipIds.add(clip.id);
      }
    });
    if (clip is ReactionTimelineClip &&
        widget.controller.project.reactionStates.containsKey(
          clip.reactionStateId,
        )) {
      widget.controller.selectReactionState(clip.reactionStateId);
    }
  }

  void _moveClip(
    TimelineTrack track,
    TimelineClip clip,
    int requestedStart,
    TimelineIntervalIndex index,
  ) {
    final start = _snapping
        ? _snapFrame(requestedStart, index, excludeClipId: clip.id)
        : requestedStart;
    widget.controller.executeCommand(
      MoveClipCommand(
        clipId: clip.id,
        targetTimelineId: widget.controller.selectedTimelineId,
        targetTrackId: track.id,
        newStart: FrameTime(
          start.clamp(
            0,
            widget.controller.selectedTimeline.durationFrames -
                clip.range.duration,
          ),
        ),
      ),
    );
  }

  void _trimClip(
    TimelineClip clip,
    int startDelta,
    int endDelta,
    TimelineIntervalIndex index,
  ) {
    var start = clip.range.start.frame + startDelta;
    var end = clip.range.endExclusive.frame + endDelta;
    if (_snapping) {
      start = _snapFrame(start, index, excludeClipId: clip.id);
      end = _snapFrame(end, index, excludeClipId: clip.id);
    }
    start = start.clamp(0, end - 1);
    end = end.clamp(
      start + 1,
      widget.controller.selectedTimeline.durationFrames,
    );
    widget.controller.executeCommand(
      TrimClipCommand(
        clipId: clip.id,
        range: FrameRange(start: FrameTime(start), duration: end - start),
      ),
    );
  }

  void _splitClipAt(TimelineClip clip, int frame) {
    if (frame <= clip.range.start.frame ||
        frame >= clip.range.endExclusive.frame) {
      return;
    }
    widget.controller.executeCommand(
      SplitClipCommand(
        clipId: clip.id,
        splitTime: FrameTime(frame),
        rightClipId: _nextId('${clip.id}.split'),
      ),
    );
  }

  void _splitSelection() {
    final timeline = widget.controller.selectedTimeline;
    final clips = _selectedClips().where((clip) {
      return timeline.tracks.values
              .where((track) => track.clips.containsKey(clip.id))
              .firstOrNull
              ?.locked !=
          true;
    });
    final commands = <ProjectCommand>[];
    for (final clip in clips) {
      final frame = widget.controller.playheadFrame;
      if (frame > clip.range.start.frame &&
          frame < clip.range.endExclusive.frame) {
        commands.add(
          SplitClipCommand(
            clipId: clip.id,
            splitTime: FrameTime(frame),
            rightClipId: _nextId('${clip.id}.split'),
          ),
        );
      }
    }
    if (commands.isNotEmpty) {
      widget.controller.executeCommandBatch(
        ProjectCommandBatch(label: 'Split selected clips', commands: commands),
      );
    }
  }

  void _deleteSelection(bool ripple) {
    if (_selectedClipIds.isEmpty) return;
    final timeline = widget.controller.selectedTimeline;
    final selected = _selectedClips().where((clip) {
      return timeline.tracks.values
              .where((track) => track.clips.containsKey(clip.id))
              .firstOrNull
              ?.locked !=
          true;
    }).toList();
    if (selected.isEmpty) return;
    final commands = <ProjectCommand>[
      for (final clip in selected) DeleteClipCommand(clipId: clip.id),
    ];
    if (ripple) {
      for (final track in timeline.tracks.values) {
        final removed = selected
            .where((clip) => track.clips.containsKey(clip.id))
            .toList();
        if (removed.isEmpty) continue;
        for (final clip in track.clips.values) {
          if (_selectedClipIds.contains(clip.id)) continue;
          final shift = removed
              .where(
                (removedClip) =>
                    removedClip.range.endExclusive.frame <=
                    clip.range.start.frame,
              )
              .fold<int>(0, (sum, value) => sum + value.range.duration);
          if (shift > 0) {
            commands.add(
              MoveClipCommand(
                clipId: clip.id,
                targetTimelineId: timeline.id,
                targetTrackId: track.id,
                newStart: FrameTime(
                  math.max(0, clip.range.start.frame - shift),
                ),
              ),
            );
          }
        }
      }
    }
    widget.controller.executeCommandBatch(
      ProjectCommandBatch(
        label: ripple
            ? 'Ripple delete selected clips'
            : 'Delete selected clips',
        commands: commands,
      ),
    );
    setState(_selectedClipIds.clear);
  }

  void _copySelection() {
    final timeline = widget.controller.selectedTimeline;
    final copied = <_ClipboardClip>[];
    for (final trackId in timeline.trackOrder) {
      final track = timeline.tracks[trackId]!;
      for (final clipId in track.clipOrder) {
        if (_selectedClipIds.contains(clipId)) {
          copied.add(
            _ClipboardClip(trackId: track.id, clip: track.clips[clipId]!),
          );
        }
      }
    }
    setState(() {
      _clipboard
        ..clear()
        ..addAll(copied);
    });
  }

  void _pasteSelection() {
    if (_clipboard.isEmpty) return;
    final timeline = widget.controller.selectedTimeline;
    final firstStart = _clipboard
        .map((item) => item.clip.range.start.frame)
        .reduce(math.min);
    final commands = <ProjectCommand>[];
    final newIds = <String>{};
    for (final item in _clipboard) {
      final track =
          timeline.tracks[item.trackId] ??
          timeline.tracks.values
              .where((value) => value.type == item.clip.trackType)
              .firstOrNull;
      if (track == null || track.locked) continue;
      final json = item.clip.toJson();
      final newId = _nextId('${item.clip.id}.copy');
      newIds.add(newId);
      json['id'] = newId;
      json['range'] = item.clip.range
          .copyWith(
            start: FrameTime(
              widget.controller.playheadFrame +
                  item.clip.range.start.frame -
                  firstStart,
            ),
          )
          .toJson();
      json.remove('linkedClipId');
      commands.add(
        InsertClipCommand(
          timelineId: timeline.id,
          trackId: track.id,
          clip: TimelineClip.fromJson(json),
        ),
      );
    }
    if (commands.isEmpty) return;
    widget.controller.executeCommandBatch(
      ProjectCommandBatch(label: 'Paste clips', commands: commands),
    );
    setState(() {
      _selectedClipIds
        ..clear()
        ..addAll(newIds);
    });
  }

  void _addMarker() {
    final timeline = widget.controller.selectedTimeline;
    widget.controller.executeCommand(
      AddMarkerCommand(
        timelineId: timeline.id,
        marker: TimelineMarker(
          id: _nextId('marker'),
          time: FrameTime(widget.controller.playheadFrame),
          name: 'Marker ${timeline.markers.length + 1}',
          color: '#FFCA6E',
        ),
      ),
    );
  }

  List<TimelineClip> _selectedClips() {
    return [
      for (final track in widget.controller.selectedTimeline.tracks.values)
        for (final clip in track.clips.values)
          if (_selectedClipIds.contains(clip.id)) clip,
    ];
  }

  int _snapFrame(
    int requested,
    TimelineIntervalIndex index, {
    ClipId? excludeClipId,
  }) {
    final candidates = <int>{
      widget.controller.playheadFrame,
      for (final point in index.editPoints()) point.frame,
      for (final marker in widget.controller.selectedTimeline.markers.values)
        marker.time.frame,
    };
    if (excludeClipId != null) {
      final excluded = _selectedClips()
          .where((clip) => clip.id == excludeClipId)
          .firstOrNull;
      if (excluded != null) {
        candidates
          ..remove(excluded.range.start.frame)
          ..remove(excluded.range.endExclusive.frame);
      }
    }
    final threshold = math.max(1, (10 / _pixelsPerFrame).round());
    int? nearest;
    var distance = threshold + 1;
    for (final candidate in candidates) {
      final nextDistance = (candidate - requested).abs();
      if (nextDistance < distance) {
        nearest = candidate;
        distance = nextDistance;
      }
    }
    return distance <= threshold ? nearest! : requested;
  }

  void _setPlayheadFromPixels(double pixels, ProjectTimeline timeline) {
    unawaited(
      _playbackEngine.seekFrame(
        (pixels / _pixelsPerFrame).round().clamp(
          0,
          timeline.durationFrames - 1,
        ),
      ),
    );
  }

  void _stepFrame(int delta) {
    _stopPlayback();
    unawaited(_playbackEngine.stepFrame(delta));
  }

  void _togglePlayback() {
    if (_shuttleDirection == 0) {
      _startPlayback(1, 1);
    } else {
      _stopPlayback();
    }
  }

  void _shuttle(int direction) {
    final speed = _shuttleDirection == direction
        ? math.min(8, _shuttleSpeed * 2)
        : 1;
    _startPlayback(direction, speed);
  }

  void _startPlayback(int direction, int speed) {
    _playbackTimer?.cancel();
    setState(() {
      _shuttleDirection = direction;
      _shuttleSpeed = speed;
    });
    if (direction == 1 && speed == 1) {
      unawaited(_playbackEngine.play());
      return;
    }
    unawaited(_playbackEngine.pause());
    final frameRate =
        widget.controller.selectedTimeline.frameRate.framesPerSecond;
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final delta = math.max(1, (frameRate / 30 * speed).round()) * direction;
      final current = widget.controller.playheadFrame;
      final next = current + delta;
      if (next < 0 ||
          next >= widget.controller.selectedTimeline.durationFrames) {
        widget.controller.setPlayhead(
          next.clamp(0, widget.controller.selectedTimeline.durationFrames - 1),
        );
        _stopPlayback();
      } else {
        widget.controller.setPlayhead(next);
      }
    });
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    unawaited(_playbackEngine.pause());
    if (mounted && (_shuttleDirection != 0 || _shuttleSpeed != 1)) {
      setState(() {
        _shuttleDirection = 0;
        _shuttleSpeed = 1;
      });
    }
  }

  void _navigateEdit(TimelineIntervalIndex index, int direction) {
    final current = FrameTime(widget.controller.playheadFrame);
    final target = direction < 0
        ? index.previousEdit(current)
        : index.nextEdit(current);
    if (target != null) widget.controller.setPlayhead(target.frame);
  }

  void _changeZoom(double delta) => _setZoom(_zoom + delta);

  void _setZoom(double value) {
    final oldPixels = _pixelsPerFrame;
    final playhead = widget.controller.playheadFrame;
    setState(() => _zoom = value.clamp(0.2, 8));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontalController.hasClients) return;
      final anchor = playhead * oldPixels - _horizontalController.offset;
      final target = playhead * _pixelsPerFrame - anchor;
      _horizontalController.jumpTo(
        target.clamp(0, _horizontalController.position.maxScrollExtent),
      );
    });
  }

  String _nextId(String prefix) {
    final existing = <String>{
      for (final track in widget.controller.selectedTimeline.tracks.values)
        ...track.clips.keys,
      ...widget.controller.selectedTimeline.markers.keys,
    };
    String id;
    do {
      _idSerial += 1;
      id = '$prefix.$_idSerial';
    } while (existing.contains(id));
    return id;
  }

  void _guard(void Function() action) {
    try {
      action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _ClipboardClip {
  const _ClipboardClip({required this.trackId, required this.clip});

  final TrackId trackId;
  final TimelineClip clip;
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.timeline,
    required this.playheadFrame,
    required this.playing,
    required this.shuttleDirection,
    required this.shuttleSpeed,
    required this.snapping,
    required this.zoom,
    required this.selectedCount,
    required this.tool,
    required this.onTogglePlayback,
    required this.onStop,
    required this.onSnappingChanged,
    required this.onZoomChanged,
    required this.onToolChanged,
  });

  final ProjectTimeline timeline;
  final int playheadFrame;
  final bool playing;
  final int shuttleDirection;
  final int shuttleSpeed;
  final bool snapping;
  final double zoom;
  final int selectedCount;
  final TimelineTool tool;
  final VoidCallback onTogglePlayback;
  final VoidCallback onStop;
  final ValueChanged<bool> onSnappingChanged;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<TimelineTool> onToolChanged;

  @override
  Widget build(BuildContext context) {
    final seconds = playheadFrame / timeline.frameRate.framesPerSecond;
    return SizedBox(
      height: 54,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showTools = constraints.maxWidth >= 760;
          final showZoom = constraints.maxWidth >= 920;
          final showDetails = constraints.maxWidth >= 640;
          return Row(
            children: [
              const SizedBox(width: 8),
              if (showTools)
                SegmentedButton<TimelineTool>(
                  segments: const [
                    ButtonSegment(
                      value: TimelineTool.selection,
                      icon: Icon(Icons.near_me_outlined, size: 18),
                      tooltip: 'Selection tool (A)',
                    ),
                    ButtonSegment(
                      value: TimelineTool.blade,
                      icon: Icon(Icons.content_cut, size: 18),
                      tooltip: 'Blade tool (B)',
                    ),
                  ],
                  selected: {tool},
                  showSelectedIcon: false,
                  onSelectionChanged: (values) => onToolChanged(values.single),
                ),
              IconButton(
                tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
                onPressed: onTogglePlayback,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                tooltip: 'Stop (K)',
                onPressed: onStop,
                icon: const Icon(Icons.stop),
              ),
              Text(
                showDetails
                    ? '${_timecode(seconds, timeline.frameRate.framesPerSecond)} · F$playheadFrame'
                    : 'F$playheadFrame',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (showDetails && shuttleDirection != 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '${shuttleDirection < 0 ? 'J' : 'L'} $shuttleSpeed×',
                  ),
                ),
              const Spacer(),
              if (showDetails && selectedCount > 0)
                Text('$selectedCount selected'),
              const SizedBox(width: 4),
              if (showDetails)
                FilterChip(
                  selected: snapping,
                  onSelected: onSnappingChanged,
                  avatar: const Icon(Icons.vertical_align_center, size: 16),
                  label: const Text('Snap N'),
                )
              else
                IconButton(
                  tooltip: 'Toggle snapping (N)',
                  isSelected: snapping,
                  onPressed: () => onSnappingChanged(!snapping),
                  icon: const Icon(Icons.vertical_align_center),
                ),
              if (showZoom) ...[
                const SizedBox(width: 6),
                const Icon(Icons.zoom_out, size: 18),
                SizedBox(
                  width: 120,
                  child: Slider(
                    value: zoom,
                    min: 0.2,
                    max: 8,
                    onChanged: onZoomChanged,
                  ),
                ),
                const Icon(Icons.zoom_in, size: 18),
              ],
              const SizedBox(width: 8),
            ],
          );
        },
      ),
    );
  }
}

class _TrackHeaderTitle extends StatelessWidget {
  const _TrackHeaderTitle();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF151B26),
      alignment: Alignment.centerLeft,
      child: Text(
        'TRACKS',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(letterSpacing: 1.2),
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.track, required this.onChanged});

  final TimelineTrack track;
  final ValueChanged<TimelineTrack> onChanged;

  @override
  Widget build(BuildContext context) {
    final audio = track.type == TimelineTrackType.audio;
    final audible = audio || track.type == TimelineTrackType.video;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111620),
        border: Border(bottom: BorderSide(color: Color(0xFF252C38))),
      ),
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          Icon(
            _trackIcon(track.type),
            size: 17,
            color: _trackColor(track.type),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              track.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (!audio)
            _SmallTrackButton(
              tooltip: track.visible ? 'Hide track' : 'Show track',
              icon: track.visible ? Icons.visibility : Icons.visibility_off,
              active: track.visible,
              onPressed: () =>
                  onChanged(track.copyWith(visible: !track.visible)),
            ),
          if (audible) ...[
            _SmallTrackButton(
              tooltip: track.muted ? 'Unmute track' : 'Mute track',
              label: 'M',
              active: track.muted,
              onPressed: () => onChanged(track.copyWith(muted: !track.muted)),
            ),
            _SmallTrackButton(
              tooltip: track.solo ? 'Clear solo' : 'Solo track',
              label: 'S',
              active: track.solo,
              onPressed: () => onChanged(track.copyWith(solo: !track.solo)),
            ),
          ],
          _SmallTrackButton(
            tooltip: track.locked ? 'Unlock track' : 'Lock track',
            icon: track.locked ? Icons.lock : Icons.lock_open,
            active: track.locked,
            onPressed: () => onChanged(track.copyWith(locked: !track.locked)),
          ),
        ],
      ),
    );
  }
}

class _SmallTrackButton extends StatelessWidget {
  const _SmallTrackButton({
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.icon,
    this.label,
  });

  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  final IconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        isSelected: active,
        onPressed: onPressed,
        icon: icon == null
            ? Text(
                label!,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              )
            : Icon(icon, size: 16),
      ),
    );
  }
}

class _TrackLane extends StatelessWidget {
  const _TrackLane({
    required this.track,
    required this.index,
    required this.horizontalController,
    required this.viewportWidth,
    required this.pixelsPerFrame,
    required this.playheadFrame,
    required this.selectedClipIds,
    required this.tool,
    required this.onEmptyTap,
    required this.onClipTap,
    required this.onClipMove,
    required this.onClipTrim,
    required this.onBlade,
  });

  final TimelineTrack track;
  final TimelineIntervalIndex index;
  final ScrollController horizontalController;
  final double viewportWidth;
  final double pixelsPerFrame;
  final int playheadFrame;
  final Set<ClipId> selectedClipIds;
  final TimelineTool tool;
  final ValueChanged<double> onEmptyTap;
  final void Function(TimelineClip clip, bool additive) onClipTap;
  final void Function(TimelineClip clip, int frame) onClipMove;
  final void Function(TimelineClip clip, int startDelta, int endDelta)
  onClipTrim;
  final void Function(TimelineClip clip, int frame) onBlade;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: horizontalController,
      builder: (context, _) {
        final offset = horizontalController.hasClients
            ? horizontalController.offset
            : 0.0;
        final start = math.max(0, (offset / pixelsPerFrame).floor() - 2);
        final duration = math.max(
          1,
          ((viewportWidth / pixelsPerFrame).ceil() + 4),
        );
        final clips = index.clipsInRange(
          track.id,
          FrameRange(start: FrameTime(start), duration: duration),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => onEmptyTap(details.localPosition.dx),
          child: Container(
            decoration: BoxDecoration(
              color: track.visible
                  ? const Color(0xFF10151E)
                  : const Color(0xFF0B0E14),
              border: const Border(
                bottom: BorderSide(color: Color(0xFF252C38)),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (final clip in clips)
                  Positioned(
                    left: clip.range.start.frame * pixelsPerFrame,
                    top: 5,
                    width: math.max(5, clip.range.duration * pixelsPerFrame),
                    height: 48,
                    child: _ClipBlock(
                      clip: clip,
                      track: track,
                      pixelsPerFrame: pixelsPerFrame,
                      selected: selectedClipIds.contains(clip.id),
                      tool: tool,
                      onTap: onClipTap,
                      onMove: onClipMove,
                      onTrim: onClipTrim,
                      onBlade: onBlade,
                    ),
                  ),
                Positioned(
                  left: playheadFrame * pixelsPerFrame,
                  top: 0,
                  bottom: 0,
                  child: const IgnorePointer(
                    child: SizedBox(
                      width: 1,
                      child: ColoredBox(color: Color(0xFFFF5B66)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClipBlock extends StatefulWidget {
  const _ClipBlock({
    required this.clip,
    required this.track,
    required this.pixelsPerFrame,
    required this.selected,
    required this.tool,
    required this.onTap,
    required this.onMove,
    required this.onTrim,
    required this.onBlade,
  });

  final TimelineClip clip;
  final TimelineTrack track;
  final double pixelsPerFrame;
  final bool selected;
  final TimelineTool tool;
  final void Function(TimelineClip clip, bool additive) onTap;
  final void Function(TimelineClip clip, int frame) onMove;
  final void Function(TimelineClip clip, int startDelta, int endDelta) onTrim;
  final void Function(TimelineClip clip, int frame) onBlade;

  @override
  State<_ClipBlock> createState() => _ClipBlockState();
}

class _ClipBlockState extends State<_ClipBlock> {
  double _dragPixels = 0;
  double _trimStartPixels = 0;
  double _trimEndPixels = 0;

  @override
  Widget build(BuildContext context) {
    final color = _trackColor(widget.track.type);
    return Transform.translate(
      offset: Offset(_dragPixels + _trimStartPixels, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          if (widget.track.locked) return;
          if (widget.tool == TimelineTool.blade) {
            final frame =
                widget.clip.range.start.frame +
                (details.localPosition.dx / widget.pixelsPerFrame).round();
            widget.onBlade(widget.clip, frame);
            return;
          }
          final keyboard = HardwareKeyboard.instance;
          widget.onTap(
            widget.clip,
            keyboard.isControlPressed ||
                keyboard.isMetaPressed ||
                keyboard.isShiftPressed,
          );
        },
        onHorizontalDragUpdate: widget.track.locked
            ? null
            : (details) => setState(() => _dragPixels += details.delta.dx),
        onHorizontalDragEnd: widget.track.locked
            ? null
            : (_) {
                final delta = (_dragPixels / widget.pixelsPerFrame).round();
                setState(() => _dragPixels = 0);
                if (delta != 0) {
                  widget.onMove(
                    widget.clip,
                    widget.clip.range.start.frame + delta,
                  );
                }
              },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: widget.clip.enabled ? 0.74 : 0.32),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.selected ? Colors.white : color,
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _clipLabel(widget.clip),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '${widget.clip.range.duration}f',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.track.locked) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: _TrimHandle(
                    onUpdate: (delta) =>
                        setState(() => _trimStartPixels += delta),
                    onEnd: () {
                      final frames = (_trimStartPixels / widget.pixelsPerFrame)
                          .round();
                      setState(() => _trimStartPixels = 0);
                      if (frames != 0) widget.onTrim(widget.clip, frames, 0);
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _TrimHandle(
                    onUpdate: (delta) =>
                        setState(() => _trimEndPixels += delta),
                    onEnd: () {
                      final frames = (_trimEndPixels / widget.pixelsPerFrame)
                          .round();
                      setState(() => _trimEndPixels = 0);
                      if (frames != 0) widget.onTrim(widget.clip, 0, frames);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle({required this.onUpdate, required this.onEnd});

  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => onUpdate(details.delta.dx),
      onHorizontalDragEnd: (_) => onEnd(),
      child: const SizedBox(width: 7, height: double.infinity),
    );
  }
}

class _TimelineRulerPainter extends CustomPainter {
  _TimelineRulerPainter({
    required this.timeline,
    required this.pixelsPerFrame,
    required this.playheadFrame,
  });

  final ProjectTimeline timeline;
  final double pixelsPerFrame;
  final int playheadFrame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF151B26),
    );
    final targetPixels = 90.0;
    final roughFrames = targetPixels / pixelsPerFrame;
    final interval = _niceInterval(roughFrames);
    final minor = math.max(1, interval ~/ 5);
    final linePaint = Paint()..color = const Color(0xFF566071);
    final markerPaint = Paint()..color = const Color(0xFFFFCA6E);
    for (var frame = 0; frame <= timeline.durationFrames; frame += minor) {
      final x = frame * pixelsPerFrame;
      final major = frame % interval == 0;
      canvas.drawLine(Offset(x, major ? 16 : 27), Offset(x, 38), linePaint);
      if (major) {
        final text = TextPainter(
          text: TextSpan(
            text:
                '${(frame / timeline.frameRate.framesPerSecond).toStringAsFixed(1)}s',
            style: const TextStyle(color: Color(0xFFBBC3D0), fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(x + 3, 2));
      }
    }
    for (final marker in timeline.markers.values) {
      final x = marker.time.frame * pixelsPerFrame;
      final path = Path()
        ..moveTo(x, 18)
        ..lineTo(x - 5, 11)
        ..lineTo(x, 4)
        ..lineTo(x + 5, 11)
        ..close();
      canvas.drawPath(path, markerPaint);
    }
    final playheadX = playheadFrame * pixelsPerFrame;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      Paint()
        ..color = const Color(0xFFFF5B66)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return oldDelegate.timeline != timeline ||
        oldDelegate.pixelsPerFrame != pixelsPerFrame ||
        oldDelegate.playheadFrame != playheadFrame;
  }
}

int _niceInterval(double rough) {
  const values = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200, 3000];
  for (final value in values) {
    if (value >= rough) return value;
  }
  return values.last;
}

String _timecode(double seconds, double frameRate) {
  final totalFrames = (seconds * frameRate).round();
  final fps = frameRate.round();
  final frames = totalFrames % fps;
  final totalSeconds = totalFrames ~/ fps;
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;
  final secs = totalSeconds % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
}

String _clipLabel(TimelineClip clip) {
  return switch (clip) {
    ReactionTimelineClip() => clip.reactionStateId,
    VideoTimelineClip() => clip.assetId,
    ImageTimelineClip() => clip.assetId,
    RichTextTimelineClip() =>
      clip.lines.isEmpty ? 'Text' : clip.lines.first.text,
    AudioTimelineClip() => clip.assetId,
    WatermarkTimelineClip() => clip.assetId,
  };
}

Color _trackColor(TimelineTrackType type) {
  return switch (type) {
    TimelineTrackType.reactionState => const Color(0xFF6EA8FE),
    TimelineTrackType.video => const Color(0xFF7ED6A5),
    TimelineTrackType.imageOverlay => const Color(0xFFA7D98B),
    TimelineTrackType.richText => const Color(0xFFD6A6FF),
    TimelineTrackType.audio => const Color(0xFFFFB86C),
    TimelineTrackType.watermark => const Color(0xFF86D7E8),
  };
}

IconData _trackIcon(TimelineTrackType type) {
  return switch (type) {
    TimelineTrackType.reactionState => Icons.groups_2_outlined,
    TimelineTrackType.video => Icons.movie_outlined,
    TimelineTrackType.imageOverlay => Icons.image_outlined,
    TimelineTrackType.richText => Icons.subtitles_outlined,
    TimelineTrackType.audio => Icons.graphic_eq,
    TimelineTrackType.watermark => Icons.branding_watermark_outlined,
  };
}
