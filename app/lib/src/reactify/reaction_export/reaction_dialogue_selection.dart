import '../project/project.dart';
import 'reaction_export_models.dart';

class ActiveReactionDialogueClip {
  const ActiveReactionDialogueClip({
    required this.track,
    required this.clip,
    required this.trackIndex,
    required this.clipIndex,
  });

  final TimelineTrack track;
  final RichTextTimelineClip clip;
  final int trackIndex;
  final int clipIndex;
}

List<ActiveReactionDialogueClip> activeReactionDialogueClips(
  ProjectTimeline timeline,
  ReactionExportEvent event,
) {
  final tracks = <TimelineTrack>[];
  final seenTracks = <String>{};
  for (final id in timeline.trackOrder) {
    final track = timeline.tracks[id];
    if (track != null && seenTracks.add(id)) tracks.add(track);
  }
  final remainingTracks =
      timeline.tracks.values.where((track) => seenTracks.add(track.id)).toList()
        ..sort((left, right) {
          final order = left.order.compareTo(right.order);
          return order != 0 ? order : left.id.compareTo(right.id);
        });
  tracks.addAll(remainingTracks);
  final hasSolo = tracks.any((track) => track.enabled && track.solo);
  final result = <ActiveReactionDialogueClip>[];
  for (var trackIndex = 0; trackIndex < tracks.length; trackIndex += 1) {
    final track = tracks[trackIndex];
    if (!track.enabled ||
        !track.visible ||
        track.type != TimelineTrackType.richText ||
        (hasSolo && !track.solo)) {
      continue;
    }
    final clips = <TimelineClip>[];
    final seenClips = <String>{};
    for (final id in track.clipOrder) {
      final clip = track.clips[id];
      if (clip != null && seenClips.add(id)) clips.add(clip);
    }
    final remainingClips =
        track.clips.values.where((clip) => seenClips.add(clip.id)).toList()
          ..sort((left, right) {
            final start = left.range.start.compareTo(right.range.start);
            return start != 0 ? start : left.id.compareTo(right.id);
          });
    clips.addAll(remainingClips);
    for (var clipIndex = 0; clipIndex < clips.length; clipIndex += 1) {
      final clip = clips[clipIndex];
      if (clip is RichTextTimelineClip &&
          clip.enabled &&
          clip.range.overlaps(event.clip.range)) {
        result.add(
          ActiveReactionDialogueClip(
            track: track,
            clip: clip,
            trackIndex: trackIndex,
            clipIndex: clipIndex,
          ),
        );
      }
    }
  }
  return result;
}
