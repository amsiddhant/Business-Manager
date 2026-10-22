import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A grid's columns, sort, filters and saved views are stored per user under
/// its `gridId`, so two grids sharing one would overwrite each other's state.
void main() {
  final ids = <String, List<String>>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    for (final m
        in RegExp(r"gridId:\s*'([^']+)'").allMatches(f.readAsStringSync())) {
      (ids[m.group(1)!] ??= []).add(f.path);
    }
  }

  test('grids have ids', () {
    expect(ids.length, greaterThanOrEqualTo(15));
  });

  test('every grid id is unique', () {
    final shared = {
      for (final e in ids.entries)
        if (e.value.length > 1) e.key: e.value,
    };
    expect(shared, isEmpty);
  });

  test('grid ids are module or module.sub', () {
    final bad = [
      for (final id in ids.keys)
        if (!RegExp(r'^[a-z]+(\.[a-z$-]+)?$').hasMatch(id)) id,
    ];
    expect(bad, isEmpty);
  });
}
