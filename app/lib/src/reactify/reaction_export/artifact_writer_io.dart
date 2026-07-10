import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../media/media.dart';
import 'reaction_export_models.dart';

class DirectoryExportArtifactWriter implements ExportArtifactWriter {
  DirectoryExportArtifactWriter(String outputDirectory)
    : outputDirectory = Directory(outputDirectory).absolute;

  final Directory outputDirectory;

  @override
  Future<WrittenReactionArtifact> writeArtifact({
    required String fileName,
    required Uint8List bytes,
    required ExportCancellationToken cancellation,
  }) async {
    cancellation.throwIfCancelled();
    final target = await _target(fileName);
    await _writeAtomically(target, bytes, cancellation);
    return WrittenReactionArtifact(
      location: MediaLocation(target.path),
      byteLength: bytes.length,
    );
  }

  @override
  Future<WrittenReactionArtifact> materializeArtifact({
    required WrittenReactionArtifact source,
    required String fileName,
    required ExportCancellationToken cancellation,
  }) async {
    cancellation.throwIfCancelled();
    final sourceFile = File(_pathFromLocation(source.location));
    if (!await sourceFile.exists()) {
      throw MediaFailure(
        code: MediaFailureCode.sourceMissing,
        message: 'A rendered reaction artifact is missing.',
        context: {'source': source.location.value},
      );
    }
    final target = await _target(fileName);
    if (sourceFile.absolute.path == target.absolute.path) {
      return source;
    }
    final temporary = File('${target.path}.partial');
    try {
      if (await temporary.exists()) await temporary.delete();
      await sourceFile.copy(temporary.path);
      cancellation.throwIfCancelled();
      await _replace(temporary, target);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return WrittenReactionArtifact(
      location: MediaLocation(target.path),
      byteLength: await target.length(),
    );
  }

  @override
  Future<WrittenReactionArtifact> writeManifest({
    required String fileName,
    required String json,
    required ExportCancellationToken cancellation,
  }) {
    return writeArtifact(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(json)),
      cancellation: cancellation,
    );
  }

  Future<File> _target(String fileName) async {
    final safe = _safeFileName(fileName);
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }
    return File(
      '${outputDirectory.path}${Platform.pathSeparator}$safe',
    ).absolute;
  }

  Future<void> _writeAtomically(
    File target,
    Uint8List bytes,
    ExportCancellationToken cancellation,
  ) async {
    final temporary = File('${target.path}.partial');
    try {
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsBytes(bytes, flush: true);
      cancellation.throwIfCancelled();
      await _replace(temporary, target);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _replace(File temporary, File target) async {
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  String _safeFileName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains(':') ||
        name.contains('\u0000')) {
      throw MediaFailure(
        code: MediaFailureCode.invalidRequest,
        message: 'An export artifact file name is unsafe.',
        context: {'fileName': value},
      );
    }
    return name;
  }

  String _pathFromLocation(MediaLocation location) {
    final value = location.value;
    if (value.startsWith('file:')) return Uri.parse(value).toFilePath();
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.hasScheme &&
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
      throw MediaFailure(
        code: MediaFailureCode.unsupportedFormat,
        message: 'Only local rendered artifacts can be materialized.',
        context: {'source': value},
      );
    }
    return value;
  }
}
