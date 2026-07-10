import 'dart:typed_data';

import '../media/media.dart';
import 'reaction_export_models.dart';

class DirectoryExportArtifactWriter implements ExportArtifactWriter {
  DirectoryExportArtifactWriter(String outputDirectory);

  @override
  Future<WrittenReactionArtifact> materializeArtifact({
    required WrittenReactionArtifact source,
    required String fileName,
    required ExportCancellationToken cancellation,
  }) => _unsupported();

  @override
  Future<WrittenReactionArtifact> writeArtifact({
    required String fileName,
    required Uint8List bytes,
    required ExportCancellationToken cancellation,
  }) => _unsupported();

  @override
  Future<WrittenReactionArtifact> writeManifest({
    required String fileName,
    required String json,
    required ExportCancellationToken cancellation,
  }) => _unsupported();

  Future<WrittenReactionArtifact> _unsupported() {
    throw MediaFailure(
      code: MediaFailureCode.unsupportedCapability,
      message: 'Directory reaction export is unavailable on this platform.',
    );
  }
}
