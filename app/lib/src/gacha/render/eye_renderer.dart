import '../code/gacha_character_state.dart';
import '../data/resolver_tables.dart';

class EyeRenderer {
  const EyeRenderer();

  List<RenderCatalogPart> resolve(
    GachaCharacterState state,
    ResolverTables tables,
  ) {
    final parts = <RenderCatalogPart>[];
    if (state.numeric('displayface') == 0) {
      return parts;
    }
    final rule = tables.facePresetRules[state.numeric('facepreset')];
    if (rule == null) {
      return parts;
    }
    final leftOuter = _frameFromToken(rule.leftEyeOuter, state);
    final rightOuter = _frameFromToken(rule.rightEyeOuter, state);
    if (state.numeric('eyes1x') > 0 && leftOuter > 0) {
      parts.addAll(
        _resolveEyeSide(
          state: state,
          tables: tables,
          family: 'left_eye',
          outerFrame: leftOuter,
          eyeField: 'eyes1x',
          pupilField: 'pupil1x',
          eyeToken: 'eye1',
          eyecamActiveInnerFrame: 2,
        ),
      );
    }
    if (state.numeric('eyes2x') > 0 && rightOuter > 0) {
      parts.addAll(
        _resolveEyeSide(
          state: state,
          tables: tables,
          family: 'right_eye',
          outerFrame: rightOuter,
          eyeField: 'eyes2x',
          pupilField: 'pupil2x',
          eyeToken: 'eye2',
          eyecamActiveInnerFrame: 3,
        ),
      );
    }
    if (state.numeric('eyebrows1x') > 0) {
      parts.addAll(
        tables.partsFor('left_eyebrow', state.numeric('eyebrows1x')),
      );
    }
    if (state.numeric('eyebrows2x') > 0) {
      parts.addAll(
        tables.partsFor('right_eyebrow', state.numeric('eyebrows2x')),
      );
    }
    return parts;
  }

  List<RenderCatalogPart> _resolveEyeSide({
    required GachaCharacterState state,
    required ResolverTables tables,
    required String family,
    required int outerFrame,
    required String eyeField,
    required String pupilField,
    required String eyeToken,
    required int eyecamActiveInnerFrame,
  }) {
    final rows = tables.partsFor(family, outerFrame);
    if (rows.isEmpty || state.numeric(eyeField) <= 0) {
      return const [];
    }

    final desiredInnerFrame = _desiredInnerFrame(
      state: state,
      rows: rows,
      eyeToken: eyeToken,
      eyecamActiveInnerFrame: eyecamActiveInnerFrame,
    );
    final selectedPupilFrame = state.numeric(pupilField);
    final showHighlight = state.numeric('eyehigh') == 1;

    return [
      for (final row in rows)
        if (_shouldIncludeEyePart(
          row,
          desiredInnerFrame: desiredInnerFrame,
          selectedPupilFrame: selectedPupilFrame,
          showHighlight: showHighlight,
          eyeToken: eyeToken,
        ))
          row,
    ];
  }

  bool _shouldIncludeEyePart(
    RenderCatalogPart part, {
    required int desiredInnerFrame,
    required int selectedPupilFrame,
    required bool showHighlight,
    required String eyeToken,
  }) {
    if (part.partRole == 'blink') {
      return false;
    }
    if (part.partRole == 'highlight') {
      return showHighlight;
    }

    final innerFrame = _innerEyeFrame(part, eyeToken: eyeToken);
    if (innerFrame != null && innerFrame != desiredInnerFrame) {
      return false;
    }

    if (part.partRole.startsWith('pupil_')) {
      if (selectedPupilFrame <= 0) {
        return false;
      }
      return _pupilFrame(part) == selectedPupilFrame;
    }

    return true;
  }

  int _desiredInnerFrame({
    required GachaCharacterState state,
    required List<RenderCatalogPart> rows,
    required String eyeToken,
    required int eyecamActiveInnerFrame,
  }) {
    final availableFrameSet = <int>{};
    for (final row in rows) {
      if (row.partRole == 'blink' || row.partRole == 'highlight') {
        continue;
      }
      final frame = _innerEyeFrame(row, eyeToken: eyeToken);
      if (frame != null) {
        availableFrameSet.add(frame);
      }
    }
    final availableFrames = availableFrameSet.toList()..sort();
    final requestedFrame = state.numeric('eyecam') == 1
        ? 1
        : eyecamActiveInnerFrame;
    if (availableFrames.contains(requestedFrame)) {
      return requestedFrame;
    }
    if (availableFrames.isNotEmpty) {
      return availableFrames.first;
    }
    return requestedFrame;
  }

  int? _innerEyeFrame(RenderCatalogPart part, {required String eyeToken}) {
    final tokens = _pathTokens(part.namePath);
    if (tokens.isEmpty || tokens.first != eyeToken) {
      return null;
    }
    final frames = _framePath(part.framePath);
    if (frames.isEmpty) {
      return null;
    }
    return frames.first;
  }

  int? _pupilFrame(RenderCatalogPart part) {
    final tokens = _pathTokens(part.namePath);
    final frames = _framePath(part.framePath);
    var pupilCount = 0;
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i] != 'pupil') {
        continue;
      }
      pupilCount += 1;
      if (pupilCount == 2) {
        if (i >= frames.length) {
          return null;
        }
        return frames[i];
      }
    }
    return null;
  }

  static final Map<String, List<String>> _tokensCache = {};
  static final Map<String, List<int>> _framesCache = {};

  List<String> _pathTokens(String raw) {
    return _tokensCache.putIfAbsent(raw, () => [
      for (final token in raw.split('/'))
        if (token.isNotEmpty && token != '<anon>') token,
    ]);
  }

  List<int> _framePath(String raw) {
    return _framesCache.putIfAbsent(raw, () => [
      for (final segment in raw.split('/'))
        if (segment.isNotEmpty) int.tryParse(segment) ?? 0,
    ]);
  }

  int _frameFromToken(String token, GachaCharacterState state) {
    if (token == 'eyes1x') {
      return state.numeric('eyes1x');
    }
    if (token == 'eyes2x') {
      return state.numeric('eyes2x');
    }
    return int.tryParse(token) ?? 0;
  }
}
