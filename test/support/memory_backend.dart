import 'package:salesforce_business_manager/core/app_exception.dart';
import 'package:salesforce_business_manager/data/backend.dart';
import 'package:salesforce_business_manager/data/backend_capabilities.dart';

/// A plain in-memory [Backend] with only the basic document API, so the
/// repository takes its no-capability fallbacks (one write at a time, scans).
class MemoryBackend implements Backend {
  final Map<String, Map<String, Map<String, dynamic>>> store = {};

  /// Collections whose writes are refused as if by the security rules.
  final Set<String> denyWrites = {};

  int setDocCalls = 0;

  /// Every collection read, in order.
  final List<String> fetched = [];

  void put(String collection, String id, Map<String, dynamic> data) =>
      (store[collection] ??= {})[id] = Map<String, dynamic>.from(data);

  @override
  String get label => 'Memory';

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(
    String collection, {
    String? businessId,
  }) async {
    fetched.add(collection);
    final all = (store[collection]?.values ?? const <Map<String, dynamic>>[])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (businessId == null) return all;
    return all.where((d) => d['businessId'] == businessId).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWhereArrayContains(
    String collection,
    String field,
    String value,
  ) async {
    return (store[collection]?.values ?? const <Map<String, dynamic>>[])
        .where((d) => d[field] is List && (d[field] as List).contains(value))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> fetchDoc(String collection, String id) async {
    final doc = store[collection]?[id];
    return doc == null ? null : Map<String, dynamic>.from(doc);
  }

  @override
  Future<void> setDoc(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    setDocCalls++;
    if (denyWrites.contains(collection)) {
      throw const PermissionDeniedException();
    }
    put(collection, id, data);
  }

  @override
  Future<void> deleteDoc(String collection, String id) async {
    if (denyWrites.contains(collection)) {
      throw const PermissionDeniedException();
    }
    store[collection]?.remove(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// A [MemoryBackend] that also commits atomic batches, recording each one.
/// A batch touching a [denyWrites] collection is refused as a whole, like a
/// Firestore batch.
class BatchMemoryBackend extends MemoryBackend implements BatchCapable {
  final List<List<WriteOp>> commits = [];

  @override
  Future<void> commit(List<WriteOp> ops) async {
    if (ops.any((op) => denyWrites.contains(op.collection))) {
      throw const PermissionDeniedException();
    }
    commits.add(List.of(ops));
    for (final op in ops) {
      switch (op) {
        case SetOp(:final collection, :final id, :final data):
          put(collection, id, data);
        case DeleteOp(:final collection, :final id):
          store[collection]?.remove(id);
      }
    }
  }
}

/// A [MemoryBackend] with the pre-sign-in lookup used by Firebase.
class LookupMemoryBackend extends MemoryBackend implements PublicLookupCapable {
  int lookups = 0;

  @override
  Future<Map<String, dynamic>?> fetchPublicDoc(
    String collection,
    String id,
  ) async {
    lookups++;
    return fetchDoc(collection, id);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(
    String collection, {
    String? businessId,
  }) async {
    if (collection == Collections.users) {
      // Listing users before sign-in is what the rules deny.
      throw const PermissionDeniedException();
    }
    return super.fetchCollection(collection, businessId: businessId);
  }
}
