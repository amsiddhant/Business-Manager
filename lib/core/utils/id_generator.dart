/// Helpers for human-readable, prefixed, zero-padded entity identifiers such as
/// `PROD-00001` and `ORD-000001`.
class IdGenerator {
  IdGenerator._();

  static const String productPrefix = 'PROD';
  static const String orderPrefix = 'ORD';
  static const String campaignPrefix = 'CMP';
  static const String expensePrefix = 'EXP';
  static const String dealerPrefix = 'DLR';
  static const String businessPrefix = 'BIZ';
  static const String userPrefix = 'USR';

  /// Formats a sequential [number] with a [prefix] and fixed [width].
  static String format(String prefix, int number, {int width = 5}) =>
      '$prefix-${number.toString().padLeft(width, '0')}';

  /// Given a list of existing ids sharing [prefix], returns the next id in
  /// sequence. Non-conforming ids are ignored.
  static String next(String prefix, Iterable<String> existingIds,
      {int width = 5}) {
    var max = 0;
    final re = RegExp('^${RegExp.escape(prefix)}-([0-9]+)\$');
    for (final id in existingIds) {
      final m = re.firstMatch(id);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > max) max = n;
      }
    }
    return format(prefix, max + 1, width: width);
  }
}
