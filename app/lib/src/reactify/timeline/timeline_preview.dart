import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../project/project.dart';
import 'timeline_playback_engine.dart';

typedef TimelinePreviewVideoBuilder =
    Widget Function(BuildContext context, ActiveTimelineVideo video);

class TimelinePreview extends StatelessWidget {
  const TimelinePreview({
    required this.engine,
    required this.timeline,
    this.videoBuilder,
    super.key,
  });

  final TimelinePlaybackEngine engine;
  final ProjectTimeline timeline;
  final TimelinePreviewVideoBuilder? videoBuilder;

  @override
  Widget build(BuildContext context) {
    final videos = engine.activeVideos;
    final diagnostics = engine.diagnostics;
    return Container(
      color: const Color(0xFF07090D),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: timeline.canvas.width / timeline.canvas.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _canvasColor(timeline.canvas.backgroundColor),
                    border: Border.all(color: const Color(0xFF283142)),
                  ),
                  child: ClipRect(
                    child: videos.isEmpty
                        ? const _EmptyPreview()
                        : FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: timeline.canvas.width.toDouble(),
                              height: timeline.canvas.height.toDouble(),
                              child: Stack(
                                clipBehavior: Clip.hardEdge,
                                children: [
                                  for (final video in videos)
                                    _TimelineVideoLayer(
                                      key: ValueKey(
                                        'timeline-preview-layer.${video.clipId}',
                                      ),
                                      video: video,
                                      canvas: timeline.canvas,
                                      child:
                                          videoBuilder?.call(context, video) ??
                                          _mediaKitVideo(video),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.preview_outlined, size: 17),
                    const SizedBox(width: 6),
                    Text(
                      'MEDIA PREVIEW',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(letterSpacing: 1),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${videos.length} video · ${engine.decoderCount}/${engine.maxDecoderCount} decoders',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: diagnostics.isEmpty
                      ? Text(
                          'Source-in, audio fades, gain, mute, solo, and pitch are active.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : ListView.separated(
                          itemCount: diagnostics.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 5),
                          itemBuilder: (context, index) => Text(
                            diagnostics[index].message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineVideoLayer extends StatelessWidget {
  const _TimelineVideoLayer({
    required this.video,
    required this.canvas,
    required this.child,
    super.key,
  });

  final ActiveTimelineVideo video;
  final ProjectCanvas canvas;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sourceWidth = (video.sourceWidth ?? canvas.width).toDouble();
    final sourceHeight = (video.sourceHeight ?? canvas.height).toDouble();
    final crop = video.crop;
    final cropLeft = (crop?.left ?? 0) * sourceWidth;
    final cropTop = (crop?.top ?? 0) * sourceHeight;
    final cropWidth = (crop?.width ?? 1) * sourceWidth;
    final cropHeight = (crop?.height ?? 1) * sourceHeight;
    final transform = video.visualTransform;
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, transform.a)
      ..setEntry(0, 1, transform.c)
      ..setEntry(1, 0, transform.b)
      ..setEntry(1, 1, transform.d)
      ..setTranslationRaw(transform.tx, transform.ty, 0);
    return Transform(
      key: ValueKey('timeline-preview-transform.${video.clipId}'),
      transform: matrix,
      alignment: Alignment.topLeft,
      child: Opacity(
        key: ValueKey('timeline-preview-opacity.${video.clipId}'),
        opacity: video.opacity.clamp(0, 1),
        child: SizedBox(
          width: cropWidth,
          height: cropHeight,
          child: ClipRect(
            child: Transform.translate(
              offset: Offset(-cropLeft, -cropTop),
              child: SizedBox(
                width: sourceWidth,
                height: sourceHeight,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _mediaKitVideo(ActiveTimelineVideo video) {
  final output = video.videoOutput;
  if (output is! VideoController) return const SizedBox.shrink();
  return Video(
    key: ValueKey('${video.clipId}.${identityHashCode(output)}'),
    controller: output,
    fit: BoxFit.fill,
    controls: null,
    wakelock: false,
    pauseUponEnteringBackgroundMode: true,
  );
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_filter_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 6),
          Text(
            'No visible media at the playhead',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

Color _canvasColor(String value) {
  final match = RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$').firstMatch(value);
  if (match == null) return Colors.black;
  final digits = match.group(1)!;
  final parsed = int.parse(digits, radix: 16);
  return Color(digits.length == 6 ? 0xFF000000 | parsed : parsed);
}
