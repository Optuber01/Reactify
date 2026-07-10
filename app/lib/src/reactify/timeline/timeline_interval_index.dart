import '../project/project.dart';

class TimelineIntervalIndex {
  TimelineIntervalIndex(ProjectTimeline timeline)
    : timelineId = timeline.id,
      _byTrack = {
        for (final track in timeline.tracks.values)
          track.id: _TrackIntervalIndex(track.clips.values),
      };

  final TimelineId timelineId;
  final Map<TrackId, _TrackIntervalIndex> _byTrack;

  List<TimelineClip> clipsAt(TrackId trackId, FrameTime time) {
    return _byTrack[trackId]?.at(time.frame) ?? const [];
  }

  List<TimelineClip> clipsInRange(TrackId trackId, FrameRange range) {
    return _byTrack[trackId]?.overlapping(
          range.start.frame,
          range.endExclusive.frame,
        ) ??
        const [];
  }

  List<FrameTime> editPoints() {
    final frames = <int>{};
    for (final index in _byTrack.values) {
      for (final clip in index.clips) {
        frames.add(clip.range.start.frame);
        frames.add(clip.range.endExclusive.frame);
      }
    }
    final sorted = frames.toList()..sort();
    return [for (final frame in sorted) FrameTime(frame)];
  }

  FrameTime? previousEdit(FrameTime time) {
    FrameTime? result;
    for (final point in editPoints()) {
      if (point.frame >= time.frame) break;
      result = point;
    }
    return result;
  }

  FrameTime? nextEdit(FrameTime time) {
    for (final point in editPoints()) {
      if (point.frame > time.frame) return point;
    }
    return null;
  }
}

class EffectiveTimelineLayers {
  const EffectiveTimelineLayers({required this.visual, required this.audio});

  final List<EffectiveTimelineLayer> visual;
  final List<EffectiveTimelineLayer> audio;
}

class EffectiveTimelineLayer {
  const EffectiveTimelineLayer({
    required this.track,
    required this.clip,
    required this.trackOrder,
  });

  final TimelineTrack track;
  final TimelineClip clip;
  final int trackOrder;
}

class EffectiveLayerEvaluator {
  const EffectiveLayerEvaluator();

  EffectiveTimelineLayers evaluate(
    ProjectTimeline timeline,
    FrameTime time, {
    TimelineIntervalIndex? index,
  }) {
    final resolvedIndex = index ?? TimelineIntervalIndex(timeline);
    final audioTracks = timeline.tracks.values.where(
      (track) => track.type == TimelineTrackType.audio && track.enabled,
    );
    final hasSolo = audioTracks.any((track) => track.solo);
    final visual = <EffectiveTimelineLayer>[];
    final audio = <EffectiveTimelineLayer>[];
    for (var order = 0; order < timeline.trackOrder.length; order += 1) {
      final track = timeline.tracks[timeline.trackOrder[order]];
      if (track == null || !track.enabled) continue;
      final clips = resolvedIndex.clipsAt(track.id, time);
      if (track.type == TimelineTrackType.audio) {
        if (track.muted || (hasSolo && !track.solo)) continue;
        for (final clip in clips) {
          if (clip.enabled) {
            audio.add(
              EffectiveTimelineLayer(
                track: track,
                clip: clip,
                trackOrder: order,
              ),
            );
          }
        }
      } else if (track.visible) {
        for (final clip in clips) {
          if (clip.enabled) {
            visual.add(
              EffectiveTimelineLayer(
                track: track,
                clip: clip,
                trackOrder: order,
              ),
            );
          }
        }
      }
    }
    return EffectiveTimelineLayers(
      visual: List.unmodifiable(visual),
      audio: List.unmodifiable(audio),
    );
  }
}

class _TrackIntervalIndex {
  _TrackIntervalIndex(Iterable<TimelineClip> source)
    : clips = source.toList()
        ..sort((left, right) {
          final start = left.range.start.compareTo(right.range.start);
          return start != 0 ? start : left.id.compareTo(right.id);
        }) {
    var maximum = 0;
    for (final clip in clips) {
      maximum = mathMax(maximum, clip.range.endExclusive.frame);
      _prefixMaximumEnd.add(maximum);
    }
  }

  final List<TimelineClip> clips;
  final List<int> _prefixMaximumEnd = [];

  List<TimelineClip> at(int frame) {
    final result = <TimelineClip>[];
    final end = _firstStartingAtOrAfter(frame + 1);
    for (var index = end - 1; index >= 0; index -= 1) {
      if (_prefixMaximumEnd[index] <= frame) break;
      final clip = clips[index];
      if (clip.range.endExclusive.frame <= frame) continue;
      result.add(clip);
    }
    result.sort((left, right) => left.id.compareTo(right.id));
    return result;
  }

  List<TimelineClip> overlapping(int start, int endExclusive) {
    final result = <TimelineClip>[];
    final end = _firstStartingAtOrAfter(endExclusive);
    for (var index = end - 1; index >= 0; index -= 1) {
      if (_prefixMaximumEnd[index] <= start) break;
      final clip = clips[index];
      if (clip.range.endExclusive.frame > start) result.add(clip);
    }
    result.sort((left, right) {
      final start = left.range.start.compareTo(right.range.start);
      return start != 0 ? start : left.id.compareTo(right.id);
    });
    return result;
  }

  int _firstStartingAtOrAfter(int frame) {
    var low = 0;
    var high = clips.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (clips[middle].range.start.frame < frame) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

int mathMax(int left, int right) => left > right ? left : right;
