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
  static const String customerPrefix = 'CUST';

  /// Formats a sequential [number] with a [prefix] and fixed [width].
  static String format(String prefix, int number, {int width = 5}) =>
      '$prefix-${number.toString().padLeft(width, '0')}';

  /// The highest sequence number among [existingIds] sharing [prefix]. Returns
  /// 0 when none match. Non-conforming ids are ignored.
  static int maxNumber(String prefix, Iterable<String> existingIds) {
    var max = 0;
    final re = RegExp('^${RegExp.escape(prefix)}-([0-9]+)\$');
    for (final id in existingIds) {
      final m = re.firstMatch(id);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > max) max = n;
      }
    }
    return max;
  }

  /// Given a list of existing ids sharing [prefix], returns the next id in
  /// sequence. Non-conforming ids are ignored.
  static String next(String prefix, Iterable<String> existingIds,
          {int width = 5}) =>
      format(prefix, maxNumber(prefix, existingIds) + 1, width: width);
}
