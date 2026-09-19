import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:universal_html/html.dart' as html;

/// Builds a CSV document and triggers a browser download.
///
/// Rows are matrices ([header] followed by [rows]); values are escaped by the
/// [Csv] encoder. A UTF-8 BOM is added so Excel opens Indian rupee symbols and
/// other non-ASCII characters correctly.
class CsvExport {
  CsvExport._();

  static final Csv _csv = Csv(addBom: true);

  static void download({
    required String filename,
    required List<String> header,
    required List<List<Object?>> rows,
  }) {
    final data = <List<dynamic>>[header, ...rows];
    final csv = _csv.encode(data);
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = filename.endsWith('.csv') ? filename : '$filename.csv'
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }
}
