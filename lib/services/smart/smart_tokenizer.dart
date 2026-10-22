import 'dart:typed_data';

import 'smart_config.dart';

/// Turns form text into hashed token ids for the on-device classifiers, so
/// text never reaches the worker or IndexedDB (feature hashing).
abstract final class SmartTokenizer {
  /// 32-bit FNV-1a of [text], exact on the web (unsigned, 0 – 2^32-1).
  static int hash(String text) {
    var h = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      h = (h ^ unit) & 0xffffffff;
      // Times the FNV prime (2^24 + 403), split to stay exact on the web.
      h = (h * 403 + ((h & 0xff) << 24)) & 0xffffffff;
    }
    return h;
  }

  static const _stopWords = {
    'the', 'and', 'for', 'with', 'from', 'pvt', 'ltd', 'inc', 'llp', 'co',
    'per', 'month', 'monthly', 'year', 'yearly', 'annual', 'plan',
  };

  static int _id(String token, int buckets) =>
      1 + hash(token) % (buckets - 1);

  /// Lower-case words of 3+ letters/digits, minus filler — the same words
  /// `DartSuggestionProvider.tokens` uses.
  static List<String> words(String text) => [
        for (final w in text.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
          if (w.length >= 3 && !_stopWords.contains(w)) w,
      ];

  /// Token ids in `[1, buckets)` for one row. [fields] maps a field tag
  /// ('n' name, 'v' vendor, 'd' description…) to its text; each word is
  /// hashed with its tag ('v:amazon'), plus each field's word pairs. The ids
  /// fill [length] slots cyclically (the model averages them, so repeats need
  /// no mask); a row with no words gets the id of `<empty>`.
  static Int32List encode(
    Map<String, String> fields, {
    int length = SmartConfig.tokens,
    int buckets = SmartConfig.buckets,
  }) {
    // Every word first (so a long row keeps them), then the word pairs.
    final tags = fields.keys.toList()..sort();
    final singles = <int>[], pairs = <int>[];
    for (final tag in tags) {
      final ws = words(fields[tag] ?? '');
      for (var i = 0; i < ws.length; i++) {
        singles.add(_id('$tag:${ws[i]}', buckets));
        if (i + 1 < ws.length) {
          pairs.add(_id('$tag:${ws[i]} ${ws[i + 1]}', buckets));
        }
      }
    }
    final ids = [...singles, ...pairs];
    if (ids.isEmpty) ids.add(_id('<empty>', buckets));
    final out = Int32List(length);
    for (var i = 0; i < length; i++) {
      out[i] = ids[i % ids.length];
    }
    return out;
  }

  /// [rows] encoded one after another (rows × [length]).
  static Int32List encodeAll(
    List<Map<String, String>> rows, {
    int length = SmartConfig.tokens,
    int buckets = SmartConfig.buckets,
  }) {
    final out = Int32List(rows.length * length);
    for (var r = 0; r < rows.length; r++) {
      out.setRange(r * length, (r + 1) * length,
          encode(rows[r], length: length, buckets: buckets));
    }
    return out;
  }
}
