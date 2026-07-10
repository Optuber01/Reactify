import 'dart:convert';
import 'dart:typed_data';

class FfmpegProgressRecord {
  FfmpegProgressRecord(Map<String, String> values)
    : values = Map.unmodifiable(values);

  final Map<String, String> values;

  int? get frame => int.tryParse(values['frame'] ?? '');

  int? get outputMicroseconds {
    return int.tryParse(values['out_time_us'] ?? values['out_time_ms'] ?? '');
  }

  double? get speed {
    final raw = values['speed'];
    if (raw == null) return null;
    return double.tryParse(
      raw.endsWith('x') ? raw.substring(0, raw.length - 1) : raw,
    );
  }

  bool get ended => values['progress'] == 'end';
}

class FfmpegProgressParser {
  const FfmpegProgressParser();

  Stream<FfmpegProgressRecord> parse(Stream<Uint8List> source) async* {
    final values = <String, String>{};
    final lines = source
        .map<List<int>>((chunk) => chunk)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      values[key] = value;
      if (key == 'progress') {
        yield FfmpegProgressRecord(values);
        values.clear();
      }
    }
    if (values.isNotEmpty) {
      yield FfmpegProgressRecord(values);
    }
  }
}
