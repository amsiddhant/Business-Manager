/// Optional abilities a [Backend] may offer on top of the basic document API.
///
/// They are deliberately *not* part of `Backend` itself: the repository checks
/// for them with `is` and falls back to the plain document calls when absent,
/// so lightweight backends (and test fakes) keep working unchanged.
library;

/// One write inside a [BatchCapable.commit].
sealed class WriteOp {
  const WriteOp(this.collection, this.id);

  final String collection;
  final String id;
}

/// Creates or replaces `collection/id` with [data].
final class SetOp extends WriteOp {
  const SetOp(super.collection, super.id, this.data);

  final Map<String, dynamic> data;
}

/// Deletes `collection/id` (a no-op when it does not exist).
final class DeleteOp extends WriteOp {
  const DeleteOp(super.collection, super.id);
}

/// Applies several writes atomically: all of them land, or none do.
abstract interface class BatchCapable {
  /// Firestore allows 500 operations per batch; callers stay well below.
  static const int maxOps = 450;

  Future<void> commit(List<WriteOp> ops);
}

/// Hands out sequential id numbers from a `counters/{prefix}` document, so a
/// create costs one read and one write instead of a scan of the collection.
abstract interface class CounterCapable {
  /// Reserves [count] consecutive numbers for [prefix] and returns the first.
  ///
  /// The counter moves to `max(stored, floor) + count`, so a counter that
  /// lags behind ids minted elsewhere heals itself when the caller knows a
  /// higher number ([floor]).
  ///
  /// Returns null, without writing anything, when the counter does not exist
  /// yet and [create] is false.
  Future<int?> reserveNumbers(String prefix, int count,
      {int floor = 0, bool create = false});

  /// Creates the counter for [prefix], or raises it, so it is at least
  /// [value]. Writes nothing when it already is.
  Future<void> ensureAtLeast(String prefix, int value);
}

/// Updates some fields of an existing document, leaving the rest untouched.
abstract interface class FieldUpdateCapable {
  Future<void> updateFields(
      String collection, String id, Map<String, dynamic> fields);
}

/// Server-side ordering and limits, so a "latest N" read costs N reads rather
/// than the whole collection.
abstract interface class QueryCapable {
  Future<List<Map<String, dynamic>>> fetchLatest(String collection,
      {required String orderBy, required int limit});
}

/// A local, on-device copy of previously read documents.
abstract interface class CacheCapable {
  /// Runs [body] with every read served from the local cache only. Cache reads
  /// are free but may be partial or empty; a document that isn't cached reads
  /// as an error.
  Future<T> fromCache<T>(Future<T> Function() body);

  /// The account whose data the cache holds, so a different person signing in
  /// on the same device never sees it.
  String? get cachedUid;
  Future<void> setCachedUid(String? uid);

  /// Wipes the local cache (at sign-out). The backend can't be used for data
  /// afterwards; the app reloads.
  Future<void> clearCache();
}

/// Documents that the security rules let anyone `get` by id before signing
/// in (the sign-in index). Backends without rules don't need it.
abstract interface class PublicLookupCapable {
  Future<Map<String, dynamic>?> fetchPublicDoc(String collection, String id);
}

/// Counts the reads and writes this session, for the Diagnostics panel.
abstract interface class UsageMeter {
  int get readCount;
  int get writeCount;
}
