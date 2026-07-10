import 'draft_revision_storage.dart';
import 'draft_revision_storage_stub.dart'
    if (dart.library.io) 'draft_revision_storage_io.dart'
    as platform;

DraftRevisionStorage createDraftRevisionStorage() {
  return platform.createPlatformDraftRevisionStorage();
}
