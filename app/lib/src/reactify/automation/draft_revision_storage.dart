import 'draft_revision.dart';

abstract interface class DraftRevisionStorage {
  Future<void> write(String location, PersistentDraftRevision revision);

  Future<PersistentDraftRevision> read(String location);

  Future<bool> exists(String location);

  Future<void> delete(String location);
}

class InMemoryDraftRevisionStorage implements DraftRevisionStorage {
  final Map<String, String> storage = {};

  @override
  Future<void> write(String location, PersistentDraftRevision revision) async {
    storage[location] = revision.encode();
  }

  @override
  Future<PersistentDraftRevision> read(String location) async {
    final source = storage[location];
    if (source == null) {
      throw StateError('Draft does not exist at $location.');
    }
    return PersistentDraftRevision.decode(source);
  }

  @override
  Future<bool> exists(String location) async => storage.containsKey(location);

  @override
  Future<void> delete(String location) async {
    if (storage.remove(location) == null) {
      throw StateError('Draft does not exist at $location.');
    }
  }
}
