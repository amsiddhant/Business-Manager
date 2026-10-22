import '../../state/user_prefs.dart';

/// Text typed into a form that wasn't saved yet.
class FormDraft {
  const FormDraft({required this.fields, required this.savedAt});

  /// Field text by field label.
  final Map<String, String> fields;
  final DateTime savedAt;

  bool get isEmpty => fields.values.every((v) => v.trim().isEmpty);
}

/// Keeps unsaved form text for the signed-in user, in this browser only
/// (UserPrefs — never Firestore), for [maxAge].
class FormDraftStore {
  FormDraftStore(this._prefs);

  final UserPrefs _prefs;

  static const maxAge = Duration(days: 14);

  String _key(String draftKey) => 'draft.$draftKey';

  FormDraft? load(String draftKey, {DateTime? now}) {
    final json = _prefs.readJson(_key(draftKey));
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    final f = json['fields'];
    if (at == null || f is! Map) return null;
    if ((now ?? DateTime.now()).difference(at) > maxAge) {
      clear(draftKey);
      return null;
    }
    final draft = FormDraft(
      fields: {
        for (final e in f.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
      savedAt: at,
    );
    return draft.isEmpty ? null : draft;
  }

  Future<void> save(String draftKey, Map<String, String> fields,
      {DateTime? now}) {
    if (fields.values.every((v) => v.trim().isEmpty)) return clear(draftKey);
    return _prefs.writeJson(
      _key(draftKey),
      {
        'at': (now ?? DateTime.now()).toIso8601String(),
        'fields': fields,
      },
      notify: false,
    );
  }

  Future<void> clear(String draftKey) =>
      _prefs.writeJson(_key(draftKey), null, notify: false);
}
