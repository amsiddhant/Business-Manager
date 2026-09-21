import 'audit_fields.dart';

/// A single comment on any commentable entity (business, product, campaign,
/// order, expense, dealer). Stored as an embedded list on the parent document —
/// there is no separate collection or security rule, so a comment inherits the
/// exact read/write authorization of the record it belongs to.
///
/// This is the generalised counterpart of `CustomerComment`; both share the
/// same wire shape so a future consolidation is a drop-in.
class EntityComment {
  const EntityComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  factory EntityComment.fromMap(Map<String, dynamic> map) => EntityComment(
        id: map['id'] as String? ?? '',
        authorId: map['authorId'] as String? ?? '',
        authorName: map['authorName'] as String? ?? '',
        text: map['text'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );

  /// Reads a `comments` list off a document map, tolerating a missing/legacy
  /// field. Malformed entries are skipped rather than throwing.
  static List<EntityComment> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => EntityComment.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }
}
