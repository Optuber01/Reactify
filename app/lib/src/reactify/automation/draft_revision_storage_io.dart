import 'dart:io';

import 'draft_revision.dart';
import 'draft_revision_storage.dart';

class IoDraftRevisionStorage implements DraftRevisionStorage {
  const IoDraftRevisionStorage();

  @override
  Future<void> write(String location, PersistentDraftRevision revision) async {
    final target = File(location);
    await target.parent.create(recursive: true);
    final temp = File(
      '$location.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    final previous = File('$location.swap');
    try {
      await temp.writeAsString(revision.encode(), flush: true);
      if (await target.exists()) {
        if (await previous.exists()) {
          await previous.delete();
        }
        await target.rename(previous.path);
      }
      try {
        await temp.rename(target.path);
      } catch (_) {
        if (await previous.exists()) {
          await previous.rename(target.path);
        }
        rethrow;
      }
      if (await previous.exists()) {
        await previous.delete();
      }
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  @override
  Future<PersistentDraftRevision> read(String location) async {
    final file = File(location);
    if (!await file.exists()) {
      throw StateError('Draft does not exist at $location.');
    }
    return PersistentDraftRevision.decode(await file.readAsString());
  }

  @override
  Future<bool> exists(String location) => File(location).exists();

  @override
  Future<void> delete(String location) async {
    final file = File(location);
    if (!await file.exists()) {
      throw StateError('Draft does not exist at $location.');
    }
    await file.delete();
  }
}

DraftRevisionStorage createPlatformDraftRevisionStorage() {
  return const IoDraftRevisionStorage();
}
