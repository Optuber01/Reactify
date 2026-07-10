import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../io/io.dart';
import '../project/project.dart';

abstract interface class TimelinePlaybackNode {
  Object? get videoOutput;
  Duration get position;
  Stream<String> get errors;

  Future<void> open(String source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setPitch(double factor);
  Future<void> dispose();
}

abstract interface class TimelinePlaybackNodeFactory {
  Future<TimelinePlaybackNode> create({required bool videoOutput});
}

class TimelinePreviewDiagnostic {
  const TimelinePreviewDiagnostic({
    required this.code,
    required this.message,
    this.clipId,
  });

  final String code;
  final String message;
  final ClipId? clipId;
}

class TimelinePlaybackLayer {
  const TimelinePlaybackLayer({
    required this.clipId,
    required this.source,
    required this.startFrame,
    required this.endFrame,
    required this.sourceInFrame,
    required this.stackOrder,
    required this.videoVisible,
    required this.audioEnabled,
    required this.gainDb,
    required this.fadeInFrames,
    required this.fadeOutFrames,
    required this.pitchSemitones,
    required this.pan,
    this.visualTransform = const AffineTransform(),
    this.crop,
    this.opacity = 1,
    this.sourceWidth,
    this.sourceHeight,
  });

  final ClipId clipId;
  final String source;
  final int startFrame;
  final int endFrame;
  final int sourceInFrame;
  final int stackOrder;
  final bool videoVisible;
  final bool audioEnabled;
  final double gainDb;
  final int fadeInFrames;
  final int fadeOutFrames;
  final double pitchSemitones;
  final double pan;
  final AffineTransform visualTransform;
  final NormalizedRect? crop;
  final double opacity;
  final int? sourceWidth;
  final int? sourceHeight;
}

class TimelinePlaybackEvaluation {
  const TimelinePlaybackEvaluation({
    required this.layers,
    required this.diagnostics,
  });

  final List<TimelinePlaybackLayer> layers;
  final List<TimelinePreviewDiagnostic> diagnostics;
}

class TimelinePlaybackEvaluator {
  const TimelinePlaybackEvaluator({
    this.uriPolicy = const PortableAssetUriPolicy(),
  });

  final PortableAssetUriPolicy uriPolicy;

  TimelinePlaybackEvaluation evaluate({
    required ReactifyProjectDocument project,
    required ProjectTimeline timeline,
    required int frame,
    String? projectLocation,
  }) {
    final diagnostics = <TimelinePreviewDiagnostic>[];
    final layers = <TimelinePlaybackLayer>[];
    final tracks = _orderedTracks(timeline);
    final hasSolo = tracks.any((track) => track.enabled && track.solo);
    for (var stackOrder = 0; stackOrder < tracks.length; stackOrder += 1) {
      final track = tracks[stackOrder];
      if (!track.enabled || (hasSolo && !track.solo)) continue;
      for (final clip in _orderedClips(track)) {
        if (!clip.enabled ||
            frame < clip.range.start.frame ||
            frame >= clip.range.endExclusive.frame) {
          continue;
        }
        final String assetId;
        final int sourceInFrame;
        final AudioClipControls audio;
        final bool videoVisible;
        final VisualClipControls? visual;
        switch (clip) {
          case VideoTimelineClip():
            assetId = clip.assetId;
            sourceInFrame = clip.sourceInFrame;
            audio = clip.audio;
            videoVisible = track.visible && clip.visual.opacity > 0;
            visual = clip.visual;
          case AudioTimelineClip():
            assetId = clip.assetId;
            sourceInFrame = clip.sourceInFrame;
            audio = clip.audio;
            videoVisible = false;
            visual = null;
          default:
            continue;
        }
        final audioEnabled = !track.muted && !audio.muted;
        if (!videoVisible && !audioEnabled) continue;
        final asset = project.assets[assetId];
        if (asset == null ||
            asset.missing ||
            asset.uri.trim().isEmpty ||
            asset.uri.startsWith('missing:')) {
          diagnostics.add(
            TimelinePreviewDiagnostic(
              code: 'missingMedia',
              message: 'Media is missing for ${clip.id}.',
              clipId: clip.id,
            ),
          );
          continue;
        }
        final kindSupported = switch (clip) {
          VideoTimelineClip() => asset.kind == ProjectAssetKind.video,
          AudioTimelineClip() =>
            asset.kind == ProjectAssetKind.audio ||
                asset.kind == ProjectAssetKind.video,
          _ => false,
        };
        if (!kindSupported) {
          diagnostics.add(
            TimelinePreviewDiagnostic(
              code: 'unsupportedAssetKind',
              message: 'The asset type for ${clip.id} cannot be previewed.',
              clipId: clip.id,
            ),
          );
          continue;
        }
        if (audioEnabled && audio.pan.abs() > 0.000001) {
          diagnostics.add(
            TimelinePreviewDiagnostic(
              code: 'panPreviewUnsupported',
              message:
                  'Pan is preserved for export but preview plays ${clip.id} centered.',
              clipId: clip.id,
            ),
          );
        }
        final sourceWidth = _dimension(asset.metadata, 'width');
        final sourceHeight = _dimension(asset.metadata, 'height');
        if (videoVisible &&
            visual?.crop != null &&
            (sourceWidth == null || sourceHeight == null)) {
          diagnostics.add(
            TimelinePreviewDiagnostic(
              code: 'cropDimensionsApproximate',
              message:
                  'Crop preview for ${clip.id} uses canvas dimensions because source dimensions are unavailable.',
              clipId: clip.id,
            ),
          );
        }
        layers.add(
          TimelinePlaybackLayer(
            clipId: clip.id,
            source: projectLocation == null
                ? asset.uri
                : uriPolicy.resolve(
                    projectLocation: projectLocation,
                    storedUri: asset.uri,
                  ),
            startFrame: clip.range.start.frame,
            endFrame: clip.range.endExclusive.frame,
            sourceInFrame: sourceInFrame,
            stackOrder: stackOrder,
            videoVisible: videoVisible,
            audioEnabled: audioEnabled,
            gainDb: audio.gainDb,
            fadeInFrames: audio.fadeInFrames,
            fadeOutFrames: audio.fadeOutFrames,
            pitchSemitones: audio.pitchSemitones + audio.pitchCents / 100,
            pan: audio.pan,
            visualTransform: visual?.transform ?? const AffineTransform(),
            crop: visual?.crop,
            opacity: visual?.opacity ?? 1,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
        );
      }
    }
    layers.sort((left, right) {
      if (left.videoVisible != right.videoVisible) {
        return left.videoVisible ? -1 : 1;
      }
      final order = left.stackOrder.compareTo(right.stackOrder);
      return order != 0 ? order : left.clipId.compareTo(right.clipId);
    });
    return TimelinePlaybackEvaluation(
      layers: List.unmodifiable(layers),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  List<TimelineTrack> _orderedTracks(ProjectTimeline timeline) {
    final result = <TimelineTrack>[];
    final seen = <TrackId>{};
    for (final id in timeline.trackOrder) {
      final track = timeline.tracks[id];
      if (track != null && seen.add(id)) result.add(track);
    }
    final remaining =
        timeline.tracks.values.where((track) => seen.add(track.id)).toList()
          ..sort((left, right) {
            final order = left.order.compareTo(right.order);
            return order != 0 ? order : left.id.compareTo(right.id);
          });
    return [...result, ...remaining];
  }

  List<TimelineClip> _orderedClips(TimelineTrack track) {
    final result = <TimelineClip>[];
    final seen = <ClipId>{};
    for (final id in track.clipOrder) {
      final clip = track.clips[id];
      if (clip != null && seen.add(id)) result.add(clip);
    }
    final remaining =
        track.clips.values.where((clip) => seen.add(clip.id)).toList()
          ..sort((left, right) {
            final start = left.range.start.compareTo(right.range.start);
            return start != 0 ? start : left.id.compareTo(right.id);
          });
    return [...result, ...remaining];
  }

  int? _dimension(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is int && value > 0) return value;
    if (value is num && value.isFinite && value > 0 && value == value.round()) {
      return value.toInt();
    }
    return null;
  }
}

class ActiveTimelineVideo {
  const ActiveTimelineVideo({
    required this.clipId,
    required this.videoOutput,
    required this.stackOrder,
    required this.visualTransform,
    required this.crop,
    required this.opacity,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final ClipId clipId;
  final Object videoOutput;
  final int stackOrder;
  final AffineTransform visualTransform;
  final NormalizedRect? crop;
  final double opacity;
  final int? sourceWidth;
  final int? sourceHeight;
}

class TimelinePlaybackEngine extends ChangeNotifier {
  TimelinePlaybackEngine({
    required ReactifyProjectDocument project,
    required ProjectTimeline timeline,
    required this.nodeFactory,
    this.projectLocation,
    this.maxDecoderCount = 4,
    this.driftThreshold = const Duration(milliseconds: 90),
    this.tickInterval = const Duration(milliseconds: 33),
    this.evaluator = const TimelinePlaybackEvaluator(),
    this.onFrameChanged,
    int initialFrame = 0,
  }) : _project = project,
       _timeline = timeline,
       _frame = initialFrame.clamp(0, timeline.durationFrames - 1) {
    if (maxDecoderCount <= 0) {
      throw ArgumentError.value(maxDecoderCount, 'maxDecoderCount');
    }
    _requestSync(forceSeek: true);
  }

  final TimelinePlaybackNodeFactory nodeFactory;
  final int maxDecoderCount;
  final Duration driftThreshold;
  final Duration tickInterval;
  final TimelinePlaybackEvaluator evaluator;
  final ValueChanged<int>? onFrameChanged;
  ReactifyProjectDocument _project;
  ProjectTimeline _timeline;
  String? projectLocation;
  final List<_PlaybackSlot> _slots = [];
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  int _frame;
  int _clockStartFrame = 0;
  bool _playing = false;
  bool _disposed = false;
  bool _syncRunning = false;
  bool _syncRequested = false;
  bool _forceSeekRequested = false;
  List<TimelinePreviewDiagnostic> _diagnostics = const [];
  final Map<String, TimelinePreviewDiagnostic> _runtimeDiagnostics = {};
  Future<void>? _cleanup;

  int get frame => _frame;
  bool get isPlaying => _playing;
  int get decoderCount => _slots.length;
  List<TimelinePreviewDiagnostic> get diagnostics => _diagnostics;

  List<ActiveTimelineVideo> get activeVideos {
    final result = <ActiveTimelineVideo>[];
    for (final slot in _slots) {
      final layer = slot.layer;
      final output = slot.node.videoOutput;
      if (layer != null && layer.videoVisible && output != null) {
        result.add(
          ActiveTimelineVideo(
            clipId: layer.clipId,
            videoOutput: output,
            stackOrder: layer.stackOrder,
            visualTransform: layer.visualTransform,
            crop: layer.crop,
            opacity: layer.opacity,
            sourceWidth: layer.sourceWidth,
            sourceHeight: layer.sourceHeight,
          ),
        );
      }
    }
    result.sort((left, right) => left.stackOrder.compareTo(right.stackOrder));
    return List.unmodifiable(result);
  }

  void updateProject({
    required ReactifyProjectDocument project,
    required ProjectTimeline timeline,
    required int frame,
    String? projectLocation,
  }) {
    if (_disposed) return;
    final documentChanged =
        !identical(_project, project) ||
        !identical(_timeline, timeline) ||
        this.projectLocation != projectLocation;
    _project = project;
    _timeline = timeline;
    this.projectLocation = projectLocation;
    if (documentChanged) _runtimeDiagnostics.clear();
    final clamped = frame.clamp(0, timeline.durationFrames - 1);
    final frameChanged = clamped != _frame;
    _frame = clamped;
    if (_playing && frameChanged) _restartClock();
    if (documentChanged || frameChanged) {
      _requestSync(forceSeek: documentChanged || frameChanged);
    }
  }

  Future<void> play() async {
    if (_disposed || _playing) return;
    _playing = true;
    _restartClock();
    _timer = Timer.periodic(tickInterval, (_) => _tick());
    notifyListeners();
    _requestSync(forceSeek: true);
  }

  Future<void> pause() async {
    if (_disposed) return;
    _playing = false;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    notifyListeners();
    _requestSync();
  }

  Future<void> toggle() => _playing ? pause() : play();

  Future<void> seekFrame(int frame) async {
    if (_disposed) return;
    _frame = frame.clamp(0, _timeline.durationFrames - 1);
    if (_playing) _restartClock();
    onFrameChanged?.call(_frame);
    notifyListeners();
    _requestSync(forceSeek: true);
  }

  Future<void> stepFrame(int delta) async {
    await pause();
    await seekFrame(_frame + delta);
  }

  Future<void> refresh() async {
    _requestSync();
    await settle();
  }

  Future<void> settle() async {
    while ((_syncRunning || _syncRequested) && !_disposed) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _restartClock() {
    _clock
      ..reset()
      ..start();
    _clockStartFrame = _frame;
  }

  void _tick() {
    if (_disposed || !_playing) return;
    final fps = _timeline.frameRate.framesPerSecond;
    final elapsedFrames =
        (_clock.elapsedMicroseconds * fps / Duration.microsecondsPerSecond)
            .floor();
    final next = _clockStartFrame + elapsedFrames;
    if (next >= _timeline.durationFrames) {
      _frame = _timeline.durationFrames - 1;
      onFrameChanged?.call(_frame);
      unawaited(pause());
      _requestSync(forceSeek: true);
      return;
    }
    if (next != _frame) {
      _frame = next;
      onFrameChanged?.call(_frame);
      notifyListeners();
    }
    _requestSync();
  }

  void _requestSync({bool forceSeek = false}) {
    if (_disposed) return;
    _syncRequested = true;
    _forceSeekRequested = _forceSeekRequested || forceSeek;
    if (_syncRunning) return;
    _syncRunning = true;
    unawaited(_runSyncLoop());
  }

  Future<void> _runSyncLoop() async {
    while (_syncRequested && !_disposed) {
      _syncRequested = false;
      final forceSeek = _forceSeekRequested;
      _forceSeekRequested = false;
      try {
        await _synchronize(forceSeek: forceSeek);
      } catch (error) {
        _appendRuntimeDiagnostic('playbackError', '$error');
      }
    }
    _syncRunning = false;
    if (_syncRequested && !_disposed) _requestSync();
  }

  Future<void> _synchronize({required bool forceSeek}) async {
    final evaluation = evaluator.evaluate(
      project: _project,
      timeline: _timeline,
      frame: _frame,
      projectLocation: projectLocation,
    );
    final desired = evaluation.layers.take(maxDecoderCount).toList();
    final diagnostics = [...evaluation.diagnostics];
    if (evaluation.layers.length > maxDecoderCount) {
      diagnostics.add(
        TimelinePreviewDiagnostic(
          code: 'decoderLimit',
          message:
              '${evaluation.layers.length - maxDecoderCount} active media layer(s) were omitted by the $maxDecoderCount-decoder preview limit.',
        ),
      );
    }
    diagnostics.addAll(_runtimeDiagnostics.values);
    final desiredIds = {for (final layer in desired) layer.clipId};
    for (final slot in _slots) {
      final desiredLayer = slot.layer == null
          ? null
          : desired
                .where((item) => item.clipId == slot.layer!.clipId)
                .firstOrNull;
      if (slot.layer != null &&
          (!desiredIds.contains(slot.layer!.clipId) ||
              (desiredLayer?.videoVisible == true &&
                  slot.node.videoOutput == null))) {
        slot.layer = null;
        if (slot.volume != 0) {
          await slot.node.setVolume(0);
          slot.volume = 0;
        }
        if (slot.playing) {
          await slot.node.pause();
          slot.playing = false;
        }
      }
    }
    for (final layer in desired) {
      var slot = _slots
          .where(
            (item) =>
                item.layer?.clipId == layer.clipId &&
                (!layer.videoVisible || item.node.videoOutput != null),
          )
          .firstOrNull;
      slot ??= _slots
          .where(
            (item) =>
                item.layer == null &&
                (!layer.videoVisible || item.node.videoOutput != null),
          )
          .firstOrNull;
      if (slot == null) {
        if (layer.videoVisible && _slots.length >= maxDecoderCount) {
          final audioOnly = _slots
              .where(
                (item) => item.layer == null && item.node.videoOutput == null,
              )
              .firstOrNull;
          if (audioOnly != null) {
            _slots.remove(audioOnly);
            await audioOnly.node.dispose();
          }
        }
        final node = await nodeFactory.create(videoOutput: layer.videoVisible);
        if (_disposed) {
          await node.dispose();
          return;
        }
        slot = _PlaybackSlot(node);
        _slots.add(slot);
        node.errors.listen(
          (message) => _appendRuntimeDiagnostic(
            'decoderError',
            message,
            clipId: slot!.layer?.clipId,
          ),
        );
      }
      final sourceChanged = slot.source != layer.source;
      final clipChanged = slot.layer?.clipId != layer.clipId;
      slot.layer = layer;
      if (sourceChanged) {
        await slot.node.open(layer.source);
        slot.source = layer.source;
        slot.pitchFactor = null;
        slot.volume = null;
        slot.playing = false;
      }
      final pitchFactor = math.pow(2, layer.pitchSemitones / 12).toDouble();
      if (slot.pitchFactor != pitchFactor) {
        await slot.node.setPitch(pitchFactor);
        slot.pitchFactor = pitchFactor;
      }
      final volume = _volumeFor(layer, _frame);
      if (slot.volume == null || (slot.volume! - volume).abs() > 0.05) {
        await slot.node.setVolume(volume);
        slot.volume = volume;
      }
      final expected = _sourcePosition(layer, _frame);
      final drift = (slot.node.position - expected).abs();
      if (forceSeek || sourceChanged || clipChanged || drift > driftThreshold) {
        await slot.node.seek(expected);
      }
      if (_playing && !slot.playing) {
        await slot.node.play();
        slot.playing = true;
      } else if (!_playing && slot.playing) {
        await slot.node.pause();
        slot.playing = false;
      }
    }
    if (_disposed) return;
    _diagnostics = List.unmodifiable(diagnostics);
    notifyListeners();
  }

  Duration _sourcePosition(TimelinePlaybackLayer layer, int frame) {
    final sourceFrame = layer.sourceInFrame + frame - layer.startFrame;
    return _frameDuration(sourceFrame.clamp(0, 1 << 30));
  }

  Duration _frameDuration(int frame) {
    return Duration(
      microseconds:
          (frame *
              _timeline.frameRate.denominator *
              Duration.microsecondsPerSecond) ~/
          _timeline.frameRate.numerator,
    );
  }

  double _volumeFor(TimelinePlaybackLayer layer, int frame) {
    if (!layer.audioEnabled) return 0;
    final local = frame - layer.startFrame;
    final remaining = layer.endFrame - frame;
    var fade = 1.0;
    if (layer.fadeInFrames > 0) {
      fade = math.min(fade, local / layer.fadeInFrames);
    }
    if (layer.fadeOutFrames > 0) {
      fade = math.min(fade, remaining / layer.fadeOutFrames);
    }
    final gain = math.pow(10, layer.gainDb / 20).toDouble();
    return (100 * gain * fade.clamp(0, 1)).clamp(0, 200).toDouble();
  }

  void _appendRuntimeDiagnostic(String code, String message, {ClipId? clipId}) {
    if (_disposed) return;
    final diagnostic = TimelinePreviewDiagnostic(
      code: code,
      message: message,
      clipId: clipId,
    );
    _runtimeDiagnostics['$code:${clipId ?? ''}'] = diagnostic;
    _diagnostics = List.unmodifiable([
      ..._diagnostics.where(
        (item) => item.code != code || item.clipId != clipId,
      ),
      diagnostic,
    ]);
    notifyListeners();
  }

  Future<void> close() {
    dispose();
    return _cleanup ?? Future.value();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _clock.stop();
    final nodes = [for (final slot in _slots) slot.node];
    _slots.clear();
    _cleanup = Future.wait([for (final node in nodes) node.dispose()]);
    super.dispose();
  }
}

class _PlaybackSlot {
  _PlaybackSlot(this.node);

  final TimelinePlaybackNode node;
  TimelinePlaybackLayer? layer;
  String? source;
  double? pitchFactor;
  double? volume;
  bool playing = false;
}
