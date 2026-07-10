import 'media_contracts.dart';
import 'process_execution.dart';

Future<ExportEncoder> createFfmpegExportEncoder(
  FfmpegExecutionConfiguration configuration,
) async {
  configuration.validate();
  throw MediaFailure(
    code: MediaFailureCode.unsupportedCapability,
    message: 'FFmpeg process export is unavailable on this platform.',
  );
}
