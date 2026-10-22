import '../../state/user_prefs.dart';
import 'grid_controller.dart';

/// A named set of grid settings the user saved ("Pending this month").
class SavedGridView {
  const SavedGridView({required this.name, required this.state});

  final String name;
  final GridViewState state;

  Map<String, Object?> toJson() => {'name': name, 'state': state.toJson()};

  static SavedGridView? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return SavedGridView(
        name: name, state: GridViewState.fromJson(json['state']));
  }
}

/// Remembers a grid's layout (sorting, page size, density, columns) and its
/// saved views for the signed-in user, in this browser only (UserPrefs —
/// never Firestore).
class GridViewStore {
  GridViewStore(this._prefs, this.gridId);

  final UserPrefs _prefs;
  final String gridId;

  static const maxViews = 12;

  String get _layoutKey => 'grid.$gridId.layout';
  String get _viewsKey => 'grid.$gridId.views';

  GridViewState? loadLayout() {
    final json = _prefs.readJson(_layoutKey);
    return json == null ? null : GridViewState.fromJson(json);
  }

  Future<void> saveLayout(GridViewState state) =>
      _prefs.writeJson(_layoutKey, state.toJson(), notify: false);

  Future<void> clearLayout() =>
      _prefs.writeJson(_layoutKey, null, notify: false);

  List<SavedGridView> get views {
    final json = _prefs.readJson(_viewsKey);
    if (json is! List) return const [];
    return [for (final e in json) ?SavedGridView.fromJson(e)];
  }

  /// Adds [name], replacing a view with the same name (any case).
  Future<void> saveView(String name, GridViewState state) {
    final trimmed = name.trim();
    final next = [
      SavedGridView(name: trimmed, state: state),
      for (final v in views)
        if (v.name.toLowerCase() != trimmed.toLowerCase()) v,
    ].take(maxViews);
    return _prefs.writeJson(
        _viewsKey, [for (final v in next) v.toJson()], notify: false);
  }

  Future<void> deleteView(String name) => _prefs.writeJson(
        _viewsKey,
        [
          for (final v in views)
            if (v.name != name) v.toJson(),
        ],
        notify: false,
      );
}
