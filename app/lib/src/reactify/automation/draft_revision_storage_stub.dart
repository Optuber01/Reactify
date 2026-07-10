import 'draft_revision_storage.dart';

final InMemoryDraftRevisionStorage _storage = InMemoryDraftRevisionStorage();

DraftRevisionStorage createPlatformDraftRevisionStorage() => _storage;
