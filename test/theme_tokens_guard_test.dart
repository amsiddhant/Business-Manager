import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Widgets must paint with `context.tokens`, never fixed colours — otherwise
/// they break in dark mode and ignore the admin's brand colour.
void main() {
  // Brand colours that must not change with the theme.
  const allowedLiterals = {
    'lib/screens/auth/login_screen.dart', // Google "G" logo
  };

  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/core/theme/'))
      .toList();

  String code(File f) => f
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('no AppColors references outside lib/core/theme', () {
    final offenders = [
      for (final f in files)
        if (RegExp(r'\bAppColors\b').hasMatch(code(f))) f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('no hard-coded Color(0x…) literals outside lib/core/theme', () {
    final offenders = [
      for (final f in files)
        if (!allowedLiterals.contains(f.path) &&
            RegExp(r'\bColor\(0x').hasMatch(code(f)))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
