import 'portable_asset_uri.dart';
import 'project_repository.dart';
import 'project_repository_stub.dart'
    if (dart.library.io) 'project_repository_io.dart'
    as platform;

ProjectRepository createProjectRepository({
  ProjectDocumentSerializer serializer = const ProjectDocumentSerializer(),
  PortableAssetUriPolicy uriPolicy = const PortableAssetUriPolicy(),
}) {
  return platform.createPlatformProjectRepository(
    serializer: serializer,
    uriPolicy: uriPolicy,
  );
}
