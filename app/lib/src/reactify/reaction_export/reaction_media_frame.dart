import 'dart:typed_data';

import '../media/media.dart';
import '../project/project.dart';
import 'reaction_export_models.dart';

class ReactionMediaFrameRequest {
  const ReactionMediaFrameRequest({
    required this.asset,
    required this.frameIdentity,
    required this.sourceFrame,
    required this.sourceTimestamp,
    required this.targetWidth,
    required this.targetHeight,
    this.event,
  });

  final ProjectAsset asset;
  final String frameIdentity;
  final int sourceFrame;
  final Duration sourceTimestamp;
  final int targetWidth;
  final int targetHeight;
  final ReactionExportEvent? event;
}

class ReactionMediaFrame {
  const ReactionMediaFrame({required this.identity, required this.pngBytes});

  final String identity;
  final Uint8List pngBytes;
}

abstract interface class ReactionMediaFrameResolver {
  Future<ReactionMediaFrame> resolve(
    ReactionMediaFrameRequest request,
    ExportCancellationToken cancellation,
  );
}
