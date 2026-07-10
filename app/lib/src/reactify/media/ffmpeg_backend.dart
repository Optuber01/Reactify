import 'dart:math' as math;

import 'media_contracts.dart';
import 'media_render_plan.dart';

class ExecutableInvocation {
  ExecutableInvocation({
    required this.executable,
    required List<String> arguments,
    Map<String, String> environment = const {},
    this.workingDirectory,
  }) : arguments = List.unmodifiable(arguments),
       environment = Map.unmodifiable(environment) {
    if (executable.trim().isEmpty || executable.contains('\u0000')) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Executable location must be non-empty.',
      );
    }
    if (arguments.any((argument) => argument.contains('\u0000'))) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Executable arguments cannot contain null characters.',
      );
    }
  }

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
}

class ExecutableResult {
  const ExecutableResult({
    required this.exitCode,
    required this.standardOutput,
    required this.standardError,
  });

  final int exitCode;
  final String standardOutput;
  final String standardError;
}

abstract interface class ExecutableRunner {
  Future<ExecutableResult> run(ExecutableInvocation invocation);
}

class FfmpegExecutableCandidate {
  const FfmpegExecutableCandidate({required this.ffmpeg, this.ffprobe});

  final String ffmpeg;
  final String? ffprobe;
}

class FfmpegExecutableCapabilities {
  FfmpegExecutableCapabilities({
    required this.candidate,
    required this.versionText,
    required Set<String> encoders,
    required Set<String> decoders,
    required Set<String> filters,
    required Set<String> muxers,
    required Set<String> demuxers,
    List<MediaDiagnostic> diagnostics = const [],
  }) : encoders = Set.unmodifiable(encoders),
       decoders = Set.unmodifiable(decoders),
       filters = Set.unmodifiable(filters),
       muxers = Set.unmodifiable(muxers),
       demuxers = Set.unmodifiable(demuxers),
       diagnostics = List.unmodifiable(diagnostics);

  final FfmpegExecutableCandidate candidate;
  final String versionText;
  final Set<String> encoders;
  final Set<String> decoders;
  final Set<String> filters;
  final Set<String> muxers;
  final Set<String> demuxers;
  final List<MediaDiagnostic> diagnostics;

  MediaBackendCapabilities get backendCapabilities {
    return MediaBackendCapabilities(
      backendId: 'ffmpeg',
      backendVersion: versionText,
      canProbe: candidate.ffprobe != null,
      canGenerateThumbnails: true,
      canGenerateWaveforms: true,
      canEncodeVideo: encoders.isNotEmpty,
      canEncodeAudio: encoders.isNotEmpty,
      canEncodeAlpha: encoders.any(
        (encoder) =>
            const {'ffv1', 'png', 'qtrle', 'prores_ks'}.contains(encoder),
      ),
      decoders: decoders,
      encoders: encoders,
      containers: muxers,
      filters: filters,
      diagnostics: diagnostics,
    );
  }

  bool supportsExport(FfmpegExportSettings settings) {
    return encoders.contains(settings.videoEncoder) &&
        (settings.audioEncoder == null ||
            encoders.contains(settings.audioEncoder)) &&
        muxers.contains(settings.muxer);
  }
}

class FfmpegCapabilityProbe {
  const FfmpegCapabilityProbe({required this.runner, required this.candidate});

  final ExecutableRunner runner;
  final FfmpegExecutableCandidate candidate;

  List<ExecutableInvocation> get invocations => [
    _invocation(['-hide_banner', '-version']),
    _invocation(['-hide_banner', '-encoders']),
    _invocation(['-hide_banner', '-decoders']),
    _invocation(['-hide_banner', '-filters']),
    _invocation(['-hide_banner', '-muxers']),
    _invocation(['-hide_banner', '-demuxers']),
  ];

  Future<FfmpegExecutableCapabilities> probe() async {
    final results = <ExecutableResult>[];
    for (final invocation in invocations) {
      final result = await runner.run(invocation);
      if (result.exitCode != 0) {
        throw MediaFailure(
          code: MediaFailureCode.probeFailed,
          message: 'FFmpeg capability probing failed.',
          context: {
            'executable': candidate.ffmpeg,
            'arguments': invocation.arguments,
            'exitCode': result.exitCode,
          },
          diagnostics: [
            MediaDiagnostic(
              severity: MediaDiagnosticSeverity.error,
              code: 'ffmpeg.probe.stderr',
              message: result.standardError.trim(),
            ),
          ],
        );
      }
      results.add(result);
    }
    return FfmpegExecutableCapabilities(
      candidate: candidate,
      versionText: _versionLine(results[0]),
      encoders: _parseTable(results[1]),
      decoders: _parseTable(results[2]),
      filters: _parseTable(results[3]),
      muxers: _parseTable(results[4]),
      demuxers: _parseTable(results[5]),
    );
  }

  ExecutableInvocation _invocation(List<String> arguments) {
    return ExecutableInvocation(
      executable: candidate.ffmpeg,
      arguments: arguments,
    );
  }

  static String _versionLine(ExecutableResult result) {
    final combined = '${result.standardOutput}\n${result.standardError}';
    for (final line in combined.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.startsWith('ffmpeg version ')) {
        return trimmed;
      }
    }
    return 'ffmpeg version unknown';
  }

  static Set<String> _parseTable(ExecutableResult result) {
    final values = <String>{};
    final combined = '${result.standardOutput}\n${result.standardError}';
    final row = RegExp(r'^\s*[A-Z\.]{1,8}\s+([A-Za-z0-9_]+)(?:\s|$)');
    for (final line in combined.split(RegExp(r'\r?\n'))) {
      final match = row.firstMatch(line);
      if (match != null) {
        values.add(match.group(1)!);
      }
    }
    return values;
  }
}

class FfmpegExportSettings {
  FfmpegExportSettings({
    required this.videoEncoder,
    required this.muxer,
    this.audioEncoder,
    this.pixelFormat = 'yuv420p',
    List<String> videoQualityArguments = const [],
    List<String> audioQualityArguments = const [],
    this.fastStart = false,
  }) : videoQualityArguments = List.unmodifiable(videoQualityArguments),
       audioQualityArguments = List.unmodifiable(audioQualityArguments);

  final String videoEncoder;
  final String? audioEncoder;
  final String muxer;
  final String pixelFormat;
  final List<String> videoQualityArguments;
  final List<String> audioQualityArguments;
  final bool fastStart;

  void validate() {
    for (final entry in [videoEncoder, ?audioEncoder, muxer, pixelFormat]) {
      if (!RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(entry)) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'FFmpeg capability names contain unsupported characters.',
          context: {'value': entry},
        );
      }
    }
    final qualityArguments = [
      ...videoQualityArguments,
      ...audioQualityArguments,
    ];
    if (qualityArguments.any((argument) => argument.contains('\u0000'))) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'FFmpeg quality arguments cannot contain null characters.',
      );
    }
  }
}

class FfmpegExportPlan {
  FfmpegExportPlan({
    required this.invocation,
    required this.filterGraph,
    required Set<String> requiredFilters,
    required Set<String> requiredEncoders,
    List<MediaDiagnostic> diagnostics = const [],
  }) : requiredFilters = Set.unmodifiable(requiredFilters),
       requiredEncoders = Set.unmodifiable(requiredEncoders),
       diagnostics = List.unmodifiable(diagnostics);

  final ExecutableInvocation invocation;
  final String filterGraph;
  final Set<String> requiredFilters;
  final Set<String> requiredEncoders;
  final List<MediaDiagnostic> diagnostics;
}

class FfmpegExportPlanner {
  const FfmpegExportPlanner({
    required this.candidate,
    required this.settings,
    this.capabilities,
  });

  final FfmpegExecutableCandidate candidate;
  final FfmpegExportSettings settings;
  final FfmpegExecutableCapabilities? capabilities;

  FfmpegExportPlan build(ExportRequest request) {
    request.plan.validate();
    request.output.validate('Export output');
    settings.validate();
    if (request.output.value.startsWith('-')) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'Export output cannot begin with an option prefix.',
      );
    }

    final plan = request.plan;
    final inputs = <String>[];
    final filters = <String>[];
    final requiredFilters = <String>{'color', 'format'};
    final requiredEncoders = <String>{settings.videoEncoder};
    final diagnostics = <MediaDiagnostic>[];
    var inputIndex = 0;

    final visualInputs = <({VisualLayerPlan layer, int inputIndex})>[];
    for (final layer in plan.visualLayers.where((layer) => layer.enabled)) {
      _appendVisualInput(inputs, layer, plan.frameRate);
      visualInputs.add((layer: layer, inputIndex: inputIndex));
      inputIndex += 1;
    }

    final audioInputs = <({AudioLayerPlan layer, int inputIndex})>[];
    for (final layer in plan.audioLayers.where(
      (layer) => layer.enabled && !layer.muted,
    )) {
      inputs.addAll(['-i', layer.source.value]);
      audioInputs.add((layer: layer, inputIndex: inputIndex));
      inputIndex += 1;
    }

    final color = _ffmpegColor(plan.background);
    filters.add(
      'color=c=$color:s=${plan.canvas.width}x${plan.canvas.height}:'
      'r=${plan.frameRate}:d=${_seconds(plan.duration)},format=rgba[base0]',
    );

    var visualBase = 'base0';
    for (var index = 0; index < visualInputs.length; index += 1) {
      final entry = visualInputs[index];
      final layer = entry.layer;
      final transform = layer.transform;
      final sourceLabel = 'visual$index';
      final nextBase = 'base${index + 1}';
      final chain = <String>[
        'trim=start=${_seconds(layer.source.sourceIn)}:'
            'duration=${_seconds(layer.range.duration)}',
        'setpts=PTS-STARTPTS+${_seconds(layer.range.start)}/TB',
      ];
      requiredFilters.addAll({'trim', 'setpts'});
      final crop = transform.crop;
      if (crop != null) {
        chain.add('crop=${crop.width}:${crop.height}:${crop.left}:${crop.top}');
        requiredFilters.add('crop');
      }
      if (transform.width != null || transform.height != null) {
        chain.add('scale=${transform.width ?? -2}:${transform.height ?? -2}');
        requiredFilters.add('scale');
      }
      if (transform.rotationDegrees != 0) {
        final radians = transform.rotationDegrees * math.pi / 180;
        final angle = _number(radians);
        chain.add('rotate=$angle:c=none:ow=rotw($angle):oh=roth($angle)');
        requiredFilters.add('rotate');
      }
      if (transform.opacity != 1) {
        chain.add('format=rgba');
        chain.add('colorchannelmixer=aa=${_number(transform.opacity)}');
        requiredFilters.addAll({'format', 'colorchannelmixer'});
      }
      filters.add('[${entry.inputIndex}:v:0]${chain.join(',')}[$sourceLabel]');
      filters.add(
        '[$visualBase][$sourceLabel]overlay=x=${_number(transform.x)}:'
        'y=${_number(transform.y)}:eof_action=pass:repeatlast=0:'
        'shortest=0:format=auto[$nextBase]',
      );
      requiredFilters.add('overlay');
      visualBase = nextBase;
    }

    filters.add(
      '[$visualBase]trim=duration=${_seconds(plan.duration)}[videoOut]',
    );
    requiredFilters.add('trim');

    String? audioOutput;
    if (audioInputs.isNotEmpty) {
      if (settings.audioEncoder == null) {
        throw MediaFailure(
          code: MediaFailureCode.invalidRequest,
          message: 'An audio encoder is required when audible layers exist.',
        );
      }
      requiredEncoders.add(settings.audioEncoder!);
      final labels = <String>[];
      for (var index = 0; index < audioInputs.length; index += 1) {
        final entry = audioInputs[index];
        final label = 'audio$index';
        labels.add(label);
        filters.add(
          '[${entry.inputIndex}:a:0]${_audioChain(entry.layer, plan, requiredFilters)}[$label]',
        );
      }
      if (labels.length == 1) {
        filters.add('[${labels.single}]anull[audioOut]');
        requiredFilters.add('anull');
      } else {
        filters.add(
          '${labels.map((label) => '[$label]').join()}'
          'amix=inputs=${labels.length}:duration=longest:'
          'dropout_transition=0:normalize=0,'
          'atrim=duration=${_seconds(plan.duration)}[audioOut]',
        );
        requiredFilters.addAll({'amix', 'atrim'});
      }
      audioOutput = 'audioOut';
    }

    _validateCapabilities(requiredFilters, requiredEncoders);

    if (settings.videoEncoder == 'libx264' ||
        settings.videoEncoder == 'libx265') {
      diagnostics.add(
        MediaDiagnostic(
          severity: MediaDiagnosticSeverity.warning,
          code: 'ffmpeg.encoder.gpl',
          message:
              'The selected video encoder commonly requires a GPL FFmpeg build.',
          context: {'encoder': settings.videoEncoder},
        ),
      );
    }

    final filterGraph = filters.join(';');
    final arguments = <String>[
      '-hide_banner',
      if (request.overwrite) '-y' else '-n',
      ...inputs,
      '-filter_complex',
      filterGraph,
      '-map',
      '[videoOut]',
      if (audioOutput != null) ...['-map', '[$audioOutput]'] else '-an',
      '-c:v',
      settings.videoEncoder,
      '-pix_fmt',
      settings.pixelFormat,
      ...settings.videoQualityArguments,
      if (audioOutput != null) ...[
        '-c:a',
        settings.audioEncoder!,
        ...settings.audioQualityArguments,
      ],
      '-r',
      plan.frameRate.toString(),
      '-fps_mode',
      'cfr',
      '-t',
      _seconds(plan.duration),
      if (settings.fastStart && settings.muxer == 'mp4') ...[
        '-movflags',
        '+faststart',
      ],
      '-f',
      settings.muxer,
      '-progress',
      'pipe:1',
      '-nostats',
      request.output.value,
    ];

    return FfmpegExportPlan(
      invocation: ExecutableInvocation(
        executable: candidate.ffmpeg,
        arguments: arguments,
      ),
      filterGraph: filterGraph,
      requiredFilters: requiredFilters,
      requiredEncoders: requiredEncoders,
      diagnostics: diagnostics,
    );
  }

  static void _appendVisualInput(
    List<String> arguments,
    VisualLayerPlan layer,
    FrameRate projectFrameRate,
  ) {
    final source = layer.source;
    if (source.repeatsSingleFrame) {
      arguments.addAll([
        '-loop',
        '1',
        '-framerate',
        projectFrameRate.toString(),
      ]);
    } else if (source is PngSequenceVisualSource) {
      arguments.addAll([
        '-framerate',
        (source.frameRate ?? projectFrameRate).toString(),
        '-start_number',
        source.startNumber.toString(),
      ]);
    }
    arguments.addAll(['-i', source.source.value]);
  }

  static String _audioChain(
    AudioLayerPlan layer,
    MediaRenderPlan plan,
    Set<String> requiredFilters,
  ) {
    final chain = <String>[
      'atrim=start=${_seconds(layer.sourceIn)}:'
          'duration=${_seconds(layer.range.duration)}',
      'asetpts=PTS-STARTPTS',
      'aresample=${plan.audioSampleRate}',
    ];
    requiredFilters.addAll({'atrim', 'asetpts', 'aresample'});
    if (layer.pitchSemitones != 0) {
      chain.add(
        'asetrate=${_number(plan.audioSampleRate * layer.pitchFactor)}',
      );
      chain.add('aresample=${plan.audioSampleRate}');
      for (final factor in _atempoChain(1 / layer.pitchFactor)) {
        chain.add('atempo=${_number(factor)}');
      }
      requiredFilters.addAll({'asetrate', 'aresample', 'atempo'});
    }
    if (layer.volumeDb != 0) {
      chain.add('volume=${_number(layer.volumeFactor)}');
      requiredFilters.add('volume');
    }
    if (layer.pan != 0) {
      final left = layer.pan > 0 ? 1 - layer.pan : 1.0;
      final right = layer.pan < 0 ? 1 + layer.pan : 1.0;
      chain.add('aformat=channel_layouts=stereo');
      chain.add('pan=stereo|c0=${_number(left)}*c0|c1=${_number(right)}*c1');
      requiredFilters.addAll({'aformat', 'pan'});
    }
    if (layer.fadeIn > Duration.zero) {
      chain.add('afade=t=in:st=0:d=${_seconds(layer.fadeIn)}');
      requiredFilters.add('afade');
    }
    if (layer.fadeOut > Duration.zero) {
      final start = layer.range.duration - layer.fadeOut;
      chain.add(
        'afade=t=out:st=${_seconds(start)}:d=${_seconds(layer.fadeOut)}',
      );
      requiredFilters.add('afade');
    }
    if (layer.range.start > Duration.zero) {
      final delayMilliseconds =
          (layer.range.start.inMicroseconds /
                  Duration.microsecondsPerMillisecond)
              .round();
      chain.add('adelay=delays=$delayMilliseconds:all=1');
      requiredFilters.add('adelay');
    }
    chain.add('apad');
    chain.add('atrim=duration=${_seconds(plan.duration)}');
    requiredFilters.addAll({'apad', 'atrim'});
    return chain.join(',');
  }

  static List<double> _atempoChain(double target) {
    final factors = <double>[];
    var remaining = target;
    while (remaining < 0.5) {
      factors.add(0.5);
      remaining /= 0.5;
    }
    while (remaining > 2) {
      factors.add(2);
      remaining /= 2;
    }
    if ((remaining - 1).abs() > 0.0000001 || factors.isEmpty) {
      factors.add(remaining);
    }
    return factors;
  }

  void _validateCapabilities(
    Set<String> requiredFilters,
    Set<String> requiredEncoders,
  ) {
    final available = capabilities;
    if (available == null) {
      return;
    }
    final missingFilters = requiredFilters.difference(available.filters);
    final missingEncoders = requiredEncoders.difference(available.encoders);
    final missingMuxer = available.muxers.contains(settings.muxer)
        ? const <String>{}
        : {settings.muxer};
    if (missingFilters.isNotEmpty ||
        missingEncoders.isNotEmpty ||
        missingMuxer.isNotEmpty) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedCapability,
        message:
            'The selected FFmpeg executable cannot satisfy the export plan.',
        context: {
          'missingFilters': missingFilters.toList()..sort(),
          'missingEncoders': missingEncoders.toList()..sort(),
          'missingMuxers': missingMuxer.toList()..sort(),
        },
      );
    }
  }

  static String _ffmpegColor(MediaColor color) {
    final red = color.red.toRadixString(16).padLeft(2, '0');
    final green = color.green.toRadixString(16).padLeft(2, '0');
    final blue = color.blue.toRadixString(16).padLeft(2, '0');
    return '0x$red$green$blue@${_number(color.alpha / 255)}';
  }

  static String _seconds(Duration duration) {
    return _number(duration.inMicroseconds / Duration.microsecondsPerSecond);
  }

  static String _number(num value) {
    var text = value.toStringAsFixed(9);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text == '-0' || text.isEmpty ? '0' : text;
  }
}
