import '../export/reactify_svg_exporter.dart';
import '../render/reactify_render_bridge.dart';
import 'artifact_writer.dart';
import 'reactify_reaction_state_renderer.dart';
import 'reaction_export_job.dart';
import 'reaction_export_models.dart';
import 'reaction_export_planner.dart';

class ReactionExportController {
  const ReactionExportController({
    required this.renderer,
    this.planner = const ReactionExportPlanner(),
  });

  factory ReactionExportController.production({
    required ReactifyRenderBridge bridge,
  }) {
    return ReactionExportController(
      renderer: ReactifyReactionStateRenderer(
        pngExporter: ReactifyPngExporter(bridge: bridge),
      ),
    );
  }

  final ReactionStateRenderer renderer;
  final ReactionExportPlanner planner;

  ReactionExportPlan buildPlan(ReactionExportRequest request) {
    return planner.build(request);
  }

  ReactionBulkExportJob createDirectoryJob({
    required ReactionExportRequest request,
    required String outputDirectory,
    ReactionExportResumeSnapshot? resumeSnapshot,
  }) {
    return ReactionBulkExportJob(
      plan: buildPlan(request),
      renderer: renderer,
      writer: DirectoryExportArtifactWriter(outputDirectory),
      resumeSnapshot: resumeSnapshot,
    );
  }
}
