import '../../gacha/render/transform_graph.dart';
import '../model/reactify_document.dart';

class ReactifySvgExporter {
  const ReactifySvgExporter();

  String exportScene(
    ReactifySceneDocument scene,
    Map<String, ReactifyCharacterDocument> characters,
  ) {
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="${_num(scene.canvasSize.width)}" '
        'height="${_num(scene.canvasSize.height)}" '
        'viewBox="0 0 ${_num(scene.canvasSize.width)} '
        '${_num(scene.canvasSize.height)}">',
      )
      ..writeln('<g id="${_xml(scene.id)}" data-reactify-type="scene">');
    for (final sceneCharacter in scene.characters) {
      final character = characters[sceneCharacter.characterId];
      if (character == null) {
        continue;
      }
      _writeCharacter(buffer, sceneCharacter, character);
    }
    buffer
      ..writeln('</g>')
      ..writeln('</svg>');
    return buffer.toString();
  }

  void _writeCharacter(
    StringBuffer buffer,
    ReactifySceneCharacter sceneCharacter,
    ReactifyCharacterDocument character,
  ) {
    buffer.writeln(
      '<g id="${_xml(sceneCharacter.id)}" '
      'data-reactify-type="character" '
      'data-character-id="${_xml(character.id)}" '
      'transform="${_matrix(sceneCharacter.transform)}">',
    );
    final slots = [
      for (final slot in character.slots)
        sceneCharacter.slotOverrides[slot.id] ?? slot,
    ]..sort((left, right) {
        final depthCompare = left.depth.compareTo(right.depth);
        if (depthCompare != 0) return depthCompare;
        return left.id.compareTo(right.id);
      });
    for (final slot in slots) {
      if (!slot.visible) {
        continue;
      }
      _writeSlot(buffer, slot);
    }
    buffer.writeln('</g>');
  }

  void _writeSlot(StringBuffer buffer, ReactifySlot slot) {
    buffer.writeln(
      '<g id="${_xml(slot.id)}" '
      'data-reactify-type="slot" '
      'data-family="${_xml(slot.family)}" '
      'data-anchor="${_xml(slot.anchorId)}" '
      'transform="${_matrix(slot.localTransform)}">',
    );
    final asset = slot.asset;
    if (asset != null && asset.uri.isNotEmpty) {
      final tint = slot.tintChannels.isEmpty
          ? ''
          : ' data-tint="${_xml(slot.tintChannels.first.id)}"';
      buffer.writeln(
        '<image id="${_xml(slot.id)}.asset" href="${_xml(asset.uri)}"$tint />',
      );
    }
    buffer.writeln('</g>');
  }

  static String _matrix(AffineMatrix matrix) {
    return 'matrix(${_num(matrix.a)} ${_num(matrix.b)} ${_num(matrix.c)} '
        '${_num(matrix.d)} ${_num(matrix.tx)} ${_num(matrix.ty)})';
  }

  static String _num(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
