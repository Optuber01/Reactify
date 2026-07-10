import 'portable_asset_uri.dart';
import 'project_repository.dart';
import 'project_repository_memory.dart';

ProjectRepository createPlatformProjectRepository({
  ProjectDocumentSerializer serializer = const ProjectDocumentSerializer(),
  PortableAssetUriPolicy uriPolicy = const PortableAssetUriPolicy(),
}) {
  return InMemoryProjectRepository(serializer: serializer);
}
