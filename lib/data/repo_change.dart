/// A successful write made through the [Repository], announced on
/// `Repository.changes` so the in-memory working set (the `DataController`)
/// can update itself in place instead of re-reading every collection.
sealed class RepoChange {
  const RepoChange(this.collection, this.id);

  /// The Firestore collection the write landed in (see `Collections`).
  final String collection;
  final String id;
}

/// A document was created or replaced. [entity] is the typed model exactly as
/// it was written (e.g. a `Product`, or the mirrored dealer `Expense`).
final class Upserted extends RepoChange {
  const Upserted(super.collection, super.id, this.entity);

  final Object entity;
}

/// A document was deleted.
final class Removed extends RepoChange {
  const Removed(super.collection, super.id);
}
