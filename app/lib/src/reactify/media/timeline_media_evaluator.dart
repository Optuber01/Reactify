import 'dart:math' as math;

import '../project/project.dart';
import 'media_contracts.dart';
import 'media_render_plan.dart';

class TimelineResolvedVisual {
  const TimelineResolvedVisual({
    required this.source,
    this.intrinsicWidth,
    this.intrinsicHeight,
  });

  final VisualSourcePlan source;
  final int? intrinsicWidth;
  final int? intrinsicHeight;
}

abstract interface class TimelineSemanticVisualResolver {
  TimelineResolvedVisual resolve({
    required ReactifyProjectDocument project,
    required ProjectTimeline timeline,
    required TimelineTrack track,
    required TimelineClip clip,
  });
}

class TimelineMediaEvaluator {
  const TimelineMediaEvaluator({this.semanticVisualResolver});

  final TimelineSemanticVisualResolver? semanticVisualResolver;

  MediaRenderPlan evaluate({
    required ReactifyProjectDocument project,
    required ProjectTimeline timeline,
  }) {
    final frameRate = FrameRate(
      timeline.frameRate.numerator,
      timeline.frameRate.denominator,
    );
    if (timeline.durationFrames <= 0) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Timeline duration must be positive.',
        context: {'timelineId': timeline.id},
      );
    }
    final orderedTracks = _orderedTracks(timeline);
    final hasSolo = orderedTracks.any((track) => track.enabled && track.solo);
    final visualLayers = <VisualLayerPlan>[];
    final audioLayers = <AudioLayerPlan>[];
    for (final track in orderedTracks) {
      if (!track.enabled || (hasSolo && !track.solo)) continue;
      for (final clip in _orderedClips(track)) {
        if (!clip.enabled) continue;
        _validateClipRange(timeline, track, clip);
        if (track.visible) {
          final visual = _visualLayer(
            project,
            timeline,
            track,
            clip,
            frameRate,
          );
          if (visual != null) visualLayers.add(visual);
        }
        if (!track.muted) {
          final audio = _audioLayer(project, track, clip, frameRate);
          if (audio != null) audioLayers.add(audio);
        }
      }
    }
    final plan = MediaRenderPlan(
      id: timeline.id,
      canvas: MediaCanvasSize(timeline.canvas.width, timeline.canvas.height),
      frameRate: frameRate,
      duration: frameRate.frameStart(timeline.durationFrames),
      background: _parseColor(timeline.canvas.backgroundColor),
      visualLayers: visualLayers,
      audioLayers: audioLayers,
      metadata: {'projectId': project.id, 'timelineId': timeline.id},
    );
    plan.validate();
    return plan;
  }

  List<TimelineTrack> _orderedTracks(ProjectTimeline timeline) {
    final result = <TimelineTrack>[];
    final seen = <String>{};
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
    result.addAll(remaining);
    return result;
  }

  List<TimelineClip> _orderedClips(TimelineTrack track) {
    final result = <TimelineClip>[];
    final seen = <String>{};
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
    result.addAll(remaining);
    return result;
  }

  VisualLayerPlan? _visualLayer(
    ReactifyProjectDocument project,
    ProjectTimeline timeline,
    TimelineTrack track,
    TimelineClip clip,
    FrameRate frameRate,
  ) {
    final VisualClipControls controls;
    final TimelineResolvedVisual resolved;
    switch (clip) {
      case VideoTimelineClip():
        final asset = _asset(project, clip.assetId, clip.id);
        _requireKind(asset, {ProjectAssetKind.video}, clip.id);
        controls = clip.visual;
        resolved = TimelineResolvedVisual(
          source: VideoVisualSource(
            source: MediaLocation(asset.uri),
            sourceIn: _sourceIn(clip.sourceInFrame, clip.id, frameRate),
          ),
          intrinsicWidth: _dimension(asset.metadata, 'width'),
          intrinsicHeight: _dimension(asset.metadata, 'height'),
        );
      case ImageTimelineClip():
        final asset = _asset(project, clip.assetId, clip.id);
        _requireKind(asset, {
          ProjectAssetKind.image,
          ProjectAssetKind.svg,
          ProjectAssetKind.drawing,
        }, clip.id);
        controls = clip.visual;
        resolved = TimelineResolvedVisual(
          source: StillImageVisualSource(source: MediaLocation(asset.uri)),
          intrinsicWidth: _dimension(asset.metadata, 'width'),
          intrinsicHeight: _dimension(asset.metadata, 'height'),
        );
      case WatermarkTimelineClip():
        final asset = _asset(project, clip.assetId, clip.id);
        _requireKind(asset, {
          ProjectAssetKind.image,
          ProjectAssetKind.svg,
          ProjectAssetKind.drawing,
        }, clip.id);
        controls = clip.visual;
        resolved = TimelineResolvedVisual(
          source: StillImageVisualSource(source: MediaLocation(asset.uri)),
          intrinsicWidth: _dimension(asset.metadata, 'width'),
          intrinsicHeight: _dimension(asset.metadata, 'height'),
        );
      case ReactionTimelineClip():
        controls = clip.visual;
        resolved = _resolveSemantic(project, timeline, track, clip);
      case RichTextTimelineClip():
        controls = clip.visual;
        resolved = _resolveSemantic(project, timeline, track, clip);
      case AudioTimelineClip():
        return null;
    }
    _rejectUnsupportedVisualControls(controls, clip.id);
    return VisualLayerPlan(
      id: '${track.id}:${clip.id}:visual',
      range: _range(clip, frameRate),
      source: resolved.source,
      transform: _transform(
        controls,
        clip.id,
        resolved.intrinsicWidth,
        resolved.intrinsicHeight,
      ),
    );
  }

  AudioLayerPlan? _audioLayer(
    ReactifyProjectDocument project,
    TimelineTrack track,
    TimelineClip clip,
    FrameRate frameRate,
  ) {
    final String assetId;
    final int sourceInFrame;
    final AudioClipControls controls;
    switch (clip) {
      case VideoTimelineClip():
        assetId = clip.assetId;
        sourceInFrame = clip.sourceInFrame;
        controls = clip.audio;
      case AudioTimelineClip():
        assetId = clip.assetId;
        sourceInFrame = clip.sourceInFrame;
        controls = clip.audio;
      default:
        return null;
    }
    final asset = _asset(project, assetId, clip.id);
    _requireKind(
      asset,
      clip is VideoTimelineClip
          ? {ProjectAssetKind.video}
          : {ProjectAssetKind.audio, ProjectAssetKind.video},
      clip.id,
    );
    if (controls.effects.isNotEmpty) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message: 'Timeline audio effects are not supported by the media plan.',
        context: {'clipId': clip.id},
      );
    }
    final range = _range(clip, frameRate);
    final fadeIn = _frameDuration(controls.fadeInFrames, frameRate);
    final fadeOut = _frameDuration(controls.fadeOutFrames, frameRate);
    if (fadeIn + fadeOut > range.duration) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Combined audio fades exceed the clip duration.',
        context: {'clipId': clip.id},
      );
    }
    return AudioLayerPlan(
      id: '${track.id}:${clip.id}:audio',
      range: range,
      source: MediaLocation(asset.uri),
      sourceIn: _sourceIn(sourceInFrame, clip.id, frameRate),
      volumeDb: controls.gainDb,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
      pan: controls.pan,
      pitchSemitones: controls.pitchSemitones + controls.pitchCents / 100,
      muted: controls.muted,
    );
  }

  TimelineResolvedVisual _resolveSemantic(
    ReactifyProjectDocument project,
    ProjectTimeline timeline,
    TimelineTrack track,
    TimelineClip clip,
  ) {
    final resolver = semanticVisualResolver;
    if (resolver == null) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message: 'A semantic visual resolver is required for this clip.',
        context: {'clipId': clip.id, 'trackType': clip.trackType.name},
      );
    }
    return resolver.resolve(
      project: project,
      timeline: timeline,
      track: track,
      clip: clip,
    );
  }

  ProjectAsset _asset(
    ReactifyProjectDocument project,
    String assetId,
    String clipId,
  ) {
    final asset = project.assets[assetId];
    if (asset == null || asset.missing || asset.uri.trim().isEmpty) {
      throw MediaFailure(
        code: MediaFailureCode.sourceMissing,
        message: 'A timeline clip references missing media.',
        context: {'assetId': assetId, 'clipId': clipId},
      );
    }
    return asset;
  }

  void _requireKind(
    ProjectAsset asset,
    Set<ProjectAssetKind> kinds,
    String clipId,
  ) {
    if (!kinds.contains(asset.kind)) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedFormat,
        message: 'The asset kind is incompatible with its timeline clip.',
        context: {
          'assetId': asset.id,
          'assetKind': asset.kind.name,
          'clipId': clipId,
        },
      );
    }
  }

  void _validateClipRange(
    ProjectTimeline timeline,
    TimelineTrack track,
    TimelineClip clip,
  ) {
    if (clip.trackType != track.type ||
        clip.range.start.frame < 0 ||
        clip.range.duration <= 0 ||
        clip.range.endExclusive.frame > timeline.durationFrames) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'A timeline clip has an invalid type or range.',
        context: {'clipId': clip.id, 'trackId': track.id},
      );
    }
  }

  MediaTimeRange _range(TimelineClip clip, FrameRate frameRate) {
    final start = frameRate.frameStart(clip.range.start.frame);
    final end = frameRate.frameStart(clip.range.endExclusive.frame);
    return MediaTimeRange(start: start, duration: end - start);
  }

  Duration _frameDuration(int frames, FrameRate frameRate) {
    if (frames < 0) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Fade frame counts cannot be negative.',
      );
    }
    return frameRate.frameStart(frames);
  }

  Duration _sourceIn(int frame, String clipId, FrameRate frameRate) {
    if (frame < 0) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Timeline source-in frame cannot be negative.',
        context: {'clipId': clipId, 'sourceInFrame': frame},
      );
    }
    return frameRate.frameStart(frame);
  }

  void _rejectUnsupportedVisualControls(
    VisualClipControls controls,
    String clipId,
  ) {
    if (controls.fadeInFrames != 0 ||
        controls.fadeOutFrames != 0 ||
        controls.transitionIn != null ||
        controls.transitionOut != null ||
        controls.effects.isNotEmpty) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message:
            'Timeline visual fades, transitions, and effects are not supported by the media plan.',
        context: {'clipId': clipId},
      );
    }
  }

  VisualTransformPlan _transform(
    VisualClipControls controls,
    String clipId,
    int? intrinsicWidth,
    int? intrinsicHeight,
  ) {
    final matrix = controls.transform;
    final scaleX = math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b);
    final scaleY = math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d);
    final determinant = matrix.a * matrix.d - matrix.b * matrix.c;
    final orthogonality = matrix.a * matrix.c + matrix.b * matrix.d;
    final tolerance = 0.000001 * math.max(1, scaleX * scaleY);
    if (scaleX <= 0 ||
        scaleY <= 0 ||
        determinant <= 0 ||
        orthogonality.abs() > tolerance) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message: 'Skewed or reflected timeline transforms are not supported.',
        context: {'clipId': clipId},
      );
    }
    final crop = controls.crop;
    if (crop != null) _validateNormalizedCrop(crop, clipId);
    final needsDimensions =
        crop != null ||
        (scaleX - 1).abs() > tolerance ||
        (scaleY - 1).abs() > tolerance;
    if (needsDimensions &&
        (intrinsicWidth == null || intrinsicHeight == null)) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message: 'Scaled or cropped media requires intrinsic asset dimensions.',
        context: {'clipId': clipId},
      );
    }
    VisualCrop? visualCrop;
    var baseWidth = intrinsicWidth;
    var baseHeight = intrinsicHeight;
    if (crop != null) {
      final left = (crop.left * intrinsicWidth!).round();
      final top = (crop.top * intrinsicHeight!).round();
      final width = (crop.width * intrinsicWidth).round();
      final height = (crop.height * intrinsicHeight).round();
      if (left + width > intrinsicWidth || top + height > intrinsicHeight) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'Timeline crop extends outside the source bounds.',
          context: {'clipId': clipId},
        );
      }
      visualCrop = VisualCrop(
        left: left,
        top: top,
        width: width,
        height: height,
      );
      baseWidth = width;
      baseHeight = height;
    }
    final scales =
        (scaleX - 1).abs() > tolerance || (scaleY - 1).abs() > tolerance;
    return VisualTransformPlan(
      x: matrix.tx,
      y: matrix.ty,
      width: scales ? math.max(1, (baseWidth! * scaleX).round()) : null,
      height: scales ? math.max(1, (baseHeight! * scaleY).round()) : null,
      rotationDegrees: math.atan2(matrix.b, matrix.a) * 180 / math.pi,
      opacity: controls.opacity,
      crop: visualCrop,
    );
  }

  void _validateNormalizedCrop(NormalizedRect crop, String clipId) {
    final values = [crop.left, crop.top, crop.width, crop.height];
    if (values.any((value) => !value.isFinite) ||
        crop.left < 0 ||
        crop.top < 0 ||
        crop.width <= 0 ||
        crop.height <= 0 ||
        crop.left + crop.width > 1 ||
        crop.top + crop.height > 1) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Timeline crop must be a normalized in-bounds rectangle.',
        context: {'clipId': clipId},
      );
    }
  }

  int? _dimension(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is int && value > 0) return value;
    if (value is num && value.isFinite && value > 0 && value == value.round()) {
      return value.toInt();
    }
    return null;
  }

  MediaColor _parseColor(String source) {
    final match = RegExp(
      r'^#([0-9A-Fa-f]{8}|[0-9A-Fa-f]{6})$',
    ).firstMatch(source.trim());
    if (match == null) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Timeline background color must be #AARRGGBB or #RRGGBB.',
        context: {'color': source},
      );
    }
    final digits = match.group(1)!;
    final value = int.parse(digits, radix: 16);
    if (digits.length == 6) {
      return MediaColor(
        red: (value >> 16) & 255,
        green: (value >> 8) & 255,
        blue: value & 255,
      );
    }
    return MediaColor(
      alpha: (value >> 24) & 255,
      red: (value >> 16) & 255,
      green: (value >> 8) & 255,
      blue: value & 255,
    );
  }
}
