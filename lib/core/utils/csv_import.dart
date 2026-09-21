import 'dart:async';

import 'package:csv/csv.dart';
import 'package:universal_html/html.dart' as html;

/// Normalizes a token for loose, forgiving comparison: lowercased with every
/// non-alphanumeric character stripped. Used to match CSV header names, enum
/// values and business identifiers regardless of spacing, casing or
/// punctuation ("Deal Status" == "deal_status" == "dealStatus").
String csvNormalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// One decoded CSV file: the header row plus data rows (all cells trimmed to
/// strings), with case/punctuation-insensitive column lookup by header name.
///
/// Rows shorter than the header are tolerated — [cell] returns an empty string
/// for a missing column rather than throwing.
class CsvDocument {
  CsvDocument(this.headers, this.rows)
      : _index = {
          for (var i = 0; i < headers.length; i++)
            csvNormalize(headers[i]): i,
        };

  /// Original (trimmed) header labels, in file order.
  final List<String> headers;

  /// Data rows only (the header row is excluded). Fully-blank rows are dropped
  /// during decoding.
  final List<List<String>> rows;

  final Map<String, int> _index;

  /// The column index for the first matching header alias, or null if none of
  /// [aliases] name a column present in the file.
  int? indexOf(List<String> aliases) {
    for (final a in aliases) {
      final i = _index[csvNormalize(a)];
      if (i != null) return i;
    }
    return null;
  }

  /// The trimmed value of [row] at [index], or '' when [index] is null or the
  /// row is shorter than the header (a ragged row).
  String cell(List<String> row, int? index) =>
      (index == null || index < 0 || index >= row.length) ? '' : row[index];

  /// Convenience: the value in [row] for the first matching header [aliases].
  String value(List<String> row, List<String> aliases) =>
      cell(row, indexOf(aliases));
}

/// A successfully-parsed row awaiting save: the 1-based [fileRow] it came from
/// (for error attribution) paired with the model built from it.
class ParsedRow<T> {
  const ParsedRow(this.fileRow, this.model);
  final int fileRow;
  final T model;
}

/// Accumulates the outcome of a bulk CSV import: how many records were created
/// and a per-row message for each row that could not be imported.
class ImportReport {
  int created = 0;
  final List<String> errors = [];

  int get failed => errors.length;
  int get total => created + failed;
  bool get hasErrors => errors.isNotEmpty;

  /// Records a failure for the given 1-based file row (row 1 is the header, so
  /// the first data row is row 2).
  void addError(int fileRow, String message) =>
      errors.add('Row $fileRow: $message');
}

/// Reads a CSV file chosen by the user (browser file picker) and decodes it.
///
/// This is the import counterpart to [CsvExport]: it uses the same `csv`
/// package and `universal_html` that the app already depends on, so no extra
/// file-picker dependency is required. Parsing ([parse]) is pure and unit
/// tested; only [pickAndDecode] touches the DOM.
class CsvImport {
  CsvImport._();

  // Comma is the delimiter CsvExport writes (and the RFC default). We pin it
  // rather than let the csv package auto-detect: auto-detection scores by how
  // often each candidate appears, so a semicolon-joined multi-value cell (e.g. a
  // customer tagged to many businesses) can outweigh the real comma delimiter
  // and flip the whole parse to ';'. A `sep=` hint line (below) overrides it.
  static final Csv _comma = Csv(fieldDelimiter: ',', autoDetect: false);

  /// Opens a browser file picker limited to CSV, reads the chosen file and
  /// decodes it into a [CsvDocument].
  ///
  /// Returns null when the file is empty or has no data rows. If the user
  /// dismisses the picker without choosing a file the returned future simply
  /// never completes — browsers expose no reliable cross-platform "cancel"
  /// event — so callers must not block UI on it (e.g. show a spinner).
  static Future<CsvDocument?> pickAndDecode() {
    final completer = Completer<CsvDocument?>();
    final input = html.FileUploadInputElement()
      ..accept = '.csv,text/csv'
      ..multiple = false
      ..style.display = 'none';
    html.document.body?.append(input);

    void finish(CsvDocument? doc) {
      if (!completer.isCompleted) completer.complete(doc);
      input.remove();
    }

    input.onChange.listen((_) {
      final files = input.files;
      if (files == null || files.isEmpty) {
        finish(null);
        return;
      }
      final reader = html.FileReader();
      reader.onError.listen((_) => finish(null));
      reader.onLoad.listen((_) {
        final result = reader.result;
        finish(parse(result is String ? result : ''));
      });
      reader.readAsText(files.first);
    });

    input.click();
    return completer.future;
  }

  /// Decodes raw CSV [text] into a [CsvDocument], or null when there is no
  /// header or no non-blank data rows. A leading UTF-8 BOM (as written by
  /// [CsvExport] for Excel compatibility) is stripped before decoding.
  static CsvDocument? parse(String text) {
    var raw = text;
    if (raw.isNotEmpty && raw.codeUnitAt(0) == 0xFEFF) {
      raw = raw.substring(1);
    }
    if (raw.trim().isEmpty) return null;

    // Honour an Excel-style `sep=;` hint line ourselves: with auto-detection
    // off the csv package no longer consumes it, so strip it and decode with
    // the delimiter it names. Without a hint we decode as comma.
    var csv = _comma;
    final sep = _sepHint(raw);
    if (sep != null) {
      csv = Csv(fieldDelimiter: sep.delimiter, autoDetect: false);
      raw = raw.substring(sep.length);
    }

    final table = csv.decode(raw);
    if (table.isEmpty) return null;

    final headers =
        table.first.map((c) => c?.toString().trim() ?? '').toList();

    final rows = <List<String>>[];
    for (final row in table.skip(1)) {
      final cells = row.map((c) => c?.toString().trim() ?? '').toList();
      if (cells.every((c) => c.isEmpty)) continue; // drop fully-blank rows
      rows.add(cells);
    }
    if (rows.isEmpty) return null;

    return CsvDocument(headers, rows);
  }

  /// Detects a leading Excel `sep=<char>` hint line. Returns the named
  /// [_SepHint.delimiter] and the number of leading characters (the hint line
  /// plus its line break) to drop, or null when the text has no such hint.
  static _SepHint? _sepHint(String raw) {
    if (!raw.startsWith('sep=')) return null;
    final nl = raw.indexOf(RegExp(r'\r\n|\r|\n'));
    if (nl == -1) return null;
    final delimiter = raw.substring(4, nl).trim();
    if (delimiter.isEmpty) return null;
    final breakLen = raw.startsWith('\r\n', nl) ? 2 : 1;
    return _SepHint(delimiter, nl + breakLen);
  }
}

/// A parsed `sep=` hint: the [delimiter] it names and the total [length] of the
/// hint line (including its trailing line break) to strip before decoding.
class _SepHint {
  const _SepHint(this.delimiter, this.length);
  final String delimiter;
  final int length;
}
