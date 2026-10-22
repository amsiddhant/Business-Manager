import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the hosting cache headers. `main.dart.js` and friends keep the same
/// file names across releases, so caching them for long left people on an
/// old build after a deploy.
void main() {
  final hosting = (jsonDecode(File('firebase.json').readAsStringSync())
      as Map<String, dynamic>)['hosting'] as Map<String, dynamic>;
  final rules = [
    for (final rule in hosting['headers'] as List)
      (
        source: (rule as Map<String, dynamic>)['source'] as String,
        headers: {
          for (final h in rule['headers'] as List)
            (h as Map<String, dynamic>)['key'] as String: h['value'] as String,
        },
      ),
  ];

  String? cacheFor(String source) => rules
      .where((r) => r.source == source)
      .map((r) => r.headers['Cache-Control'])
      .firstOrNull;

  test('un-hashed app files are revalidated on every load', () {
    for (final source in [
      '/@(index.html|flutter_service_worker.js)',
      '/@(flutter_bootstrap.js|flutter.js|main.dart.js|manifest.json|version.json)',
      '/main.dart.js_*.part.js',
      '/assets/**',
      '/canvaskit/**',
    ]) {
      expect(cacheFor(source), startsWith('no-cache'), reason: source);
    }
  });

  test('only versioned folders are cached as immutable', () {
    final immutable = rules
        .where((r) => r.headers['Cache-Control']?.contains('immutable') ?? false)
        .map((r) => r.source)
        .toList();
    expect(immutable, ['/@(tfjs|smart)/**']);
  });

  test('no broad wildcard caches scripts for long', () {
    for (final r in rules) {
      final cache = r.headers['Cache-Control'] ?? '';
      final longLived = RegExp(r'max-age=(\d+)').firstMatch(cache);
      if (longLived == null) continue;
      if (int.parse(longLived.group(1)!) <= 86400) continue;
      expect(r.source, '/@(tfjs|smart)/**');
    }
  });

  test('no cross-origin isolation headers (they break Google sign-in)', () {
    for (final r in rules) {
      expect(r.headers.keys, isNot(contains('Cross-Origin-Opener-Policy')));
      expect(r.headers.keys, isNot(contains('Cross-Origin-Embedder-Policy')));
    }
  });

  test('every route falls back to index.html', () {
    expect(hosting['rewrites'], [
      {'source': '**', 'destination': '/index.html'},
    ]);
  });
}
