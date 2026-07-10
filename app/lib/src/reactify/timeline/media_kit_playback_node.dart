import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'timeline_playback_engine.dart';

class MediaKitTimelinePlaybackNodeFactory
    implements TimelinePlaybackNodeFactory {
  const MediaKitTimelinePlaybackNodeFactory({
    this.previewWidth = 960,
    this.previewHeight = 540,
    this.bufferSize = 8 * 1024 * 1024,
  });

  final int? previewWidth;
  final int? previewHeight;
  final int bufferSize;

  @override
  Future<TimelinePlaybackNode> create({required bool videoOutput}) async {
    return MediaKitTimelinePlaybackNode(
      videoOutput: videoOutput,
      previewWidth: previewWidth,
      previewHeight: previewHeight,
      bufferSize: bufferSize,
    );
  }
}

class MediaKitTimelinePlaybackNode implements TimelinePlaybackNode {
  MediaKitTimelinePlaybackNode({
    required bool videoOutput,
    int? previewWidth,
    int? previewHeight,
    int bufferSize = 8 * 1024 * 1024,
  }) : player = Player(
         configuration: PlayerConfiguration(
           pitch: true,
           bufferSize: bufferSize,
           title: 'Reactify Preview',
         ),
       ) {
    videoController = videoOutput
        ? VideoController(
            player,
            configuration: VideoControllerConfiguration(
              width: previewWidth,
              height: previewHeight,
            ),
          )
        : null;
    _positionSubscription = player.stream.position.listen(
      (value) => _position = value,
    );
    _errorSubscription = player.stream.error.listen(_errors.add);
  }

  final Player player;
  late final VideoController? videoController;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<String> _errorSubscription;
  final StreamController<String> _errors = StreamController.broadcast();
  Duration _position = Duration.zero;
  bool _disposed = false;

  @override
  Object? get videoOutput => videoController;

  @override
  Duration get position => _position;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> open(String source) async {
    _requireActive();
    await player.open(Media(_mediaSource(source)), play: false);
    _position = Duration.zero;
  }

  @override
  Future<void> play() async {
    _requireActive();
    await player.play();
  }

  @override
  Future<void> pause() async {
    _requireActive();
    await player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    _requireActive();
    _position = position;
    await player.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _requireActive();
    await player.setVolume(volume);
  }

  @override
  Future<void> setPitch(double factor) async {
    _requireActive();
    await player.setPitch(factor);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _positionSubscription.cancel();
    await _errorSubscription.cancel();
    await player.dispose();
    await _errors.close();
  }

  void _requireActive() {
    if (_disposed) throw StateError('Playback node has been disposed.');
  }
}

String _mediaSource(String source) {
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source) ||
      source.startsWith('\\\\')) {
    return Uri.file(source, windows: true).toString();
  }
  return source;
}
