class RationalFrameRate {
  factory RationalFrameRate(int numerator, int denominator) {
    if (numerator <= 0 || denominator <= 0) {
      throw ArgumentError('Frame-rate terms must be positive.');
    }
    final divisor = _gcd(numerator, denominator);
    return RationalFrameRate._(numerator ~/ divisor, denominator ~/ divisor);
  }

  const RationalFrameRate._(this.numerator, this.denominator);

  final int numerator;
  final int denominator;

  double get framesPerSecond => numerator / denominator;

  factory RationalFrameRate.fromJson(Map<String, Object?> json) {
    return RationalFrameRate(
      _jsonInt(json, 'numerator'),
      _jsonInt(json, 'denominator'),
    );
  }

  Map<String, Object?> toJson() => {
    'denominator': denominator,
    'numerator': numerator,
  };

  RationalFrameRate copyWith({int? numerator, int? denominator}) {
    return RationalFrameRate(
      numerator ?? this.numerator,
      denominator ?? this.denominator,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RationalFrameRate &&
        numerator == other.numerator &&
        denominator == other.denominator;
  }

  @override
  int get hashCode => Object.hash(numerator, denominator);
}

class FrameTime implements Comparable<FrameTime> {
  const FrameTime(this.frame) : assert(frame >= 0);

  final int frame;

  FrameTime operator +(int frames) => FrameTime(frame + frames);

  FrameTime operator -(int frames) => FrameTime(frame - frames);

  int difference(FrameTime other) => frame - other.frame;

  factory FrameTime.fromJson(Object? value) {
    if (value is int && value >= 0) {
      return FrameTime(value);
    }
    throw FormatException('Expected a non-negative integer frame time.');
  }

  Object toJson() => frame;

  @override
  int compareTo(FrameTime other) => frame.compareTo(other.frame);

  @override
  bool operator ==(Object other) => other is FrameTime && frame == other.frame;

  @override
  int get hashCode => frame.hashCode;
}

class FrameRange {
  const FrameRange({required this.start, required this.duration})
    : assert(duration > 0);

  final FrameTime start;
  final int duration;

  FrameTime get endExclusive => start + duration;

  bool contains(FrameTime time) {
    return time.frame >= start.frame && time.frame < endExclusive.frame;
  }

  bool overlaps(FrameRange other) {
    return start.frame < other.endExclusive.frame &&
        other.start.frame < endExclusive.frame;
  }

  factory FrameRange.fromJson(Map<String, Object?> json) {
    return FrameRange(
      start: FrameTime.fromJson(json['start']),
      duration: _jsonInt(json, 'duration'),
    );
  }

  Map<String, Object?> toJson() => {
    'duration': duration,
    'start': start.toJson(),
  };

  FrameRange copyWith({FrameTime? start, int? duration}) {
    return FrameRange(
      start: start ?? this.start,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FrameRange &&
        start == other.start &&
        duration == other.duration;
  }

  @override
  int get hashCode => Object.hash(start, duration);
}

int _gcd(int left, int right) {
  var a = left.abs();
  var b = right.abs();
  while (b != 0) {
    final remainder = a % b;
    a = b;
    b = remainder;
  }
  return a;
}

int _jsonInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Expected integer at $key.');
}
