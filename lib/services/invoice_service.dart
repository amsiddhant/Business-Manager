import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:universal_html/html.dart' as html;

import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../models/invoice.dart';

/// Renders an [Invoice] into a professional, A4 PDF document and triggers a
/// browser download. All layout logic lives here; the [Invoice] value object it
/// consumes is pure (no rendering / Firebase / widget code).
///
/// [buildPdfBytes] is side-effect free (no `dart:html`) and returns the raw PDF
/// bytes, so it is unit-testable; [download] performs the browser save; and
/// [generateAndDownload] combines the two for UI callers.
///
/// Note on the rupee glyph: the PDF base fonts (Helvetica) use WinAnsi encoding
/// which has no `₹` (U+20B9). INR amounts are therefore formatted with a
/// "Rs. " prefix; other currencies keep their native symbol.
class InvoiceService {
  const InvoiceService();

  // Brand palette mirrored from the app theme (AppColors).
  static final PdfColor _purple = PdfColor.fromInt(0xFF582DD3);
  static final PdfColor _purpleDark = PdfColor.fromInt(0xFF3F1FA0);
  static final PdfColor _purpleLight = PdfColor.fromInt(0xFFEEE9FB);
  static final PdfColor _ink = PdfColor.fromInt(0xFF1F2937);
  static final PdfColor _muted = PdfColor.fromInt(0xFF6B7280);
  static final PdfColor _faint = PdfColor.fromInt(0xFF9CA3AF);
  static final PdfColor _line = PdfColor.fromInt(0xFFE6E8F0);
  static final PdfColor _surfaceAlt = PdfColor.fromInt(0xFFF1F3F9);
  static final PdfColor _success = PdfColor.fromInt(0xFF16A34A);
  static final PdfColor _successSurface = PdfColor.fromInt(0xFFE7F6EC);

  /// Builds the invoice, saves it as a PDF and downloads it in the browser.
  /// [signatureBytes] are the raw bytes of the authorised-signatory image (PNG /
  /// JPG); when null the signature block falls back to a drawn flourish.
  Future<void> generateAndDownload(
    Invoice invoice, {
    Uint8List? signatureBytes,
  }) async {
    final bytes = await buildPdfBytes(invoice, signatureBytes: signatureBytes);
    download(bytes, '${invoice.number}.pdf');
  }

  /// Suggested download filename for [invoice] (e.g. "INV-00001-20260921.pdf").
  static String filenameFor(Invoice invoice) => '${invoice.number}.pdf';

  /// Renders [invoice] to PDF bytes. Pure — safe to call off the UI / in tests.
  /// [signatureBytes], when supplied, are embedded as the handwritten signature
  /// image; otherwise a vector flourish is drawn.
  Future<Uint8List> buildPdfBytes(
    Invoice invoice, {
    Uint8List? signatureBytes,
  }) async {
    final money = _MoneyText(invoice.currency);
    final signatureImage =
        signatureBytes == null ? null : pw.MemoryImage(signatureBytes);
    final doc = pw.Document(
      title: invoice.number,
      author: invoice.seller.name,
      subject: 'Invoice for ${invoice.buyer.name}',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        footer: (context) => _footer(context, invoice),
        build: (context) => [
          _header(invoice),
          pw.SizedBox(height: 24),
          _partiesAndMeta(invoice),
          pw.SizedBox(height: 22),
          _lineItemsTable(invoice, money),
          pw.SizedBox(height: 16),
          _totals(invoice, money),
          if (invoice.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _notes(invoice),
          ],
          pw.SizedBox(height: 28),
          _signatureAndTerms(invoice, signatureImage),
        ],
      ),
    );

    return doc.save();
  }

  /// Triggers a browser download of raw PDF [bytes] under [filename].
  /// Mirrors the CsvExport anchor-click idiom already used in the app.
  void download(Uint8List bytes, String filename) {
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = filename.endsWith('.pdf') ? filename : '$filename.pdf'
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  // ── Header band ──────────────────────────────────────────────────────────

  pw.Widget _header(Invoice invoice) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(14),
        gradient: pw.LinearGradient(
          colors: [_purple, _purpleDark],
          begin: pw.Alignment.centerLeft,
          end: pw.Alignment.centerRight,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _monogram(invoice.seller.name),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  invoice.seller.name,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (invoice.seller.subtitle.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    invoice.seller.subtitle,
                    style: pw.TextStyle(
                      color: PdfColor.fromInt(0xCCFFFFFF),
                      fontSize: 9.5,
                    ),
                  ),
                ],
                for (final l in invoice.seller.lines) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    l,
                    style: pw.TextStyle(
                      color: PdfColor.fromInt(0xB3FFFFFF),
                      fontSize: 9,
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'INVOICE',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                invoice.number,
                style: pw.TextStyle(
                  color: PdfColor.fromInt(0xE6FFFFFF),
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _monogram(String name) {
    final initials = _initials(name);
    return pw.Container(
      width: 44,
      height: 44,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0x33FFFFFF),
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColor.fromInt(0x66FFFFFF), width: 0.8),
      ),
      child: pw.Text(
        initials,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 17,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  // ── Bill-to + invoice metadata ───────────────────────────────────────────

  pw.Widget _partiesAndMeta(Invoice invoice) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sectionLabel('BILLED TO'),
              pw.SizedBox(height: 6),
              pw.Text(
                invoice.buyer.name,
                style: pw.TextStyle(
                  color: _ink,
                  fontSize: 13.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (invoice.buyer.subtitle.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(invoice.buyer.subtitle,
                    style: pw.TextStyle(color: _muted, fontSize: 9.5)),
              ],
              for (final l in invoice.buyer.lines) ...[
                pw.SizedBox(height: 2),
                pw.Text(l, style: pw.TextStyle(color: _muted, fontSize: 9.5)),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: 20),
        pw.Expanded(
          flex: 2,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _surfaceAlt,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _metaRow('Issue Date', AppDate.format(invoice.issueDate)),
                _metaRow('Due Date', AppDate.format(invoice.dueDate)),
                if (invoice.serviceStart != null)
                  _metaRow(
                      'Service Start', AppDate.format(invoice.serviceStart)),
                if (invoice.serviceEnd != null)
                  _metaRow('Service End', AppDate.format(invoice.serviceEnd)),
                if (invoice.billingCycle != null)
                  _metaRow('Billing', invoice.billingCycle!.label),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _metaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 78,
            child: pw.Text(label,
                style: pw.TextStyle(color: _muted, fontSize: 9.5)),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                  color: _ink, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ── Line items ─────────────────────────────────────────────────────────

  pw.Widget _lineItemsTable(Invoice invoice, _MoneyText money) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _purpleLight),
        children: [
          _headCell('DESCRIPTION', pw.Alignment.centerLeft),
          _headCell('QTY', pw.Alignment.center),
          _headCell('UNIT PRICE', pw.Alignment.centerRight),
          _headCell('AMOUNT', pw.Alignment.centerRight),
        ],
      ),
    ];

    for (var i = 0; i < invoice.lines.length; i++) {
      final l = invoice.lines[i];
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isEven ? PdfColors.white : _surfaceAlt,
          ),
          children: [
            _bodyCell(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(l.description,
                      style: pw.TextStyle(
                          color: _ink,
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold)),
                  if (l.detail.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 1.5),
                    pw.Text(l.detail,
                        style: pw.TextStyle(color: _muted, fontSize: 8.5)),
                  ],
                ],
              ),
              pw.Alignment.centerLeft,
            ),
            _bodyCell(
              pw.Text('${l.quantity}',
                  style: pw.TextStyle(color: _ink, fontSize: 10.5)),
              pw.Alignment.center,
            ),
            _bodyCell(
              pw.Text(money.format(l.unitPrice),
                  style: pw.TextStyle(color: _ink, fontSize: 10.5)),
              pw.Alignment.centerRight,
            ),
            _bodyCell(
              pw.Text(money.format(l.amount),
                  style: pw.TextStyle(
                      color: _ink,
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold)),
              pw.Alignment.centerRight,
            ),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.6),
        top: pw.BorderSide(color: _line, width: 0.6),
        bottom: pw.BorderSide(color: _line, width: 0.6),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(5.2),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(2.3),
        3: pw.FlexColumnWidth(2.3),
      },
      children: rows,
    );
  }

  pw.Widget _headCell(String text, pw.Alignment align) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: _purpleDark,
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  pw.Widget _bodyCell(pw.Widget child, pw.Alignment align) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: child,
    );
  }

  // ── Totals ───────────────────────────────────────────────────────────────

  pw.Widget _totals(Invoice invoice, _MoneyText money) {
    final cycleSuffix =
        invoice.billingCycle == null ? '' : ' /${invoice.billingCycle!.unit}';
    return pw.Row(
      children: [
        pw.Spacer(flex: 3),
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            children: [
              if (invoice.hasMixedCharges) ...[
                _totalRow(
                    'Recurring Subtotal', money.format(invoice.recurringTotal)),
                _totalRow('One-time Charges',
                    money.format(invoice.oneTimeTotal)),
                pw.SizedBox(height: 6),
              ],
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: pw.BoxDecoration(
                  color: _purple,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('TOTAL DUE',
                        style: pw.TextStyle(
                            color: PdfColor.fromInt(0xE6FFFFFF),
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold)),
                    pw.Spacer(),
                    pw.Text(
                      '${money.format(invoice.total)}$cycleSuffix',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _totalRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: pw.Row(
        children: [
          pw.Text(label, style: pw.TextStyle(color: _muted, fontSize: 10)),
          pw.Spacer(),
          pw.Text(value,
              style: pw.TextStyle(
                  color: _ink, fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  pw.Widget _notes(Invoice invoice) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _surfaceAlt,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel('NOTES'),
          pw.SizedBox(height: 4),
          pw.Text(invoice.notes,
              style: pw.TextStyle(color: _ink, fontSize: 10, lineSpacing: 2)),
        ],
      ),
    );
  }

  // ── Digital signature + terms ─────────────────────────────────────────────

  pw.Widget _signatureAndTerms(Invoice invoice, pw.MemoryImage? signatureImage) {
    final signedOn = DateFormat('dd-MMM-yyyy HH:mm').format(invoice.signedAt);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          flex: 5,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sectionLabel('TERMS & CONDITIONS'),
              pw.SizedBox(height: 5),
              pw.Text(
                'Payment is due by the date shown above. This invoice reflects '
                'the active service contract on record. For queries about this '
                'invoice, contact the issuing business.',
                style: pw.TextStyle(color: _muted, fontSize: 8.5, lineSpacing: 2),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        pw.Expanded(
          flex: 4,
          child: _signatureBlock(invoice, signedOn, signatureImage),
        ),
      ],
    );
  }

  pw.Widget _signatureBlock(
      Invoice invoice, String signedOn, pw.MemoryImage? signatureImage) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _line, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            children: [
              _sectionLabel('AUTHORISED SIGNATORY'),
              pw.Spacer(),
              _verifiedStamp(),
            ],
          ),
          pw.SizedBox(height: 4),
          // The handwritten signature image when available, else a drawn
          // flourish as a graceful fallback.
          pw.Container(
            height: 46,
            alignment: pw.Alignment.centerLeft,
            child: signatureImage != null
                ? pw.Image(
                    signatureImage,
                    height: 46,
                    fit: pw.BoxFit.contain,
                    alignment: pw.Alignment.centerLeft,
                  )
                : pw.CustomPaint(
                    size: const PdfPoint(150, 44),
                    painter: _signaturePainter,
                  ),
          ),
          pw.Container(height: 0.8, color: _ink),
          pw.SizedBox(height: 4),
          pw.Text(
            invoice.signatoryName.trim().isEmpty
                ? 'Authorised Signatory'
                : invoice.signatoryName,
            style: pw.TextStyle(
                color: _ink, fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          if (invoice.signatoryTitle.trim().isNotEmpty)
            pw.Text(invoice.signatoryTitle,
                style: pw.TextStyle(color: _muted, fontSize: 9)),
          pw.SizedBox(height: 6),
          pw.Text(
            'Digitally signed on $signedOn',
            style: pw.TextStyle(color: _faint, fontSize: 7.5),
          ),
          pw.Text(
            'Ref: ${invoice.fingerprint}',
            style: pw.TextStyle(color: _faint, fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  /// A green "digitally verified" capsule: a drawn check-mark beside a small
  /// caption, inside a rounded pill.
  pw.Widget _verifiedStamp() {
    // A fixed height with the radius pinned to exactly half of it makes a true
    // capsule whose end arcs are clean semicircles. A radius larger than half
    // the height makes the pdf package's rounded-rect arcs overshoot, sprouting
    // pointed "leaf" tips at each end of the pill.
    const double height = 16;
    return pw.Container(
      height: height,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8),
      decoration: pw.BoxDecoration(
        color: _successSurface,
        borderRadius: pw.BorderRadius.circular(height / 2),
        border: pw.Border.all(color: _success, width: 0.7),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.CustomPaint(
            size: const PdfPoint(8, 8),
            painter: _checkPainter,
          ),
          pw.SizedBox(width: 4),
          pw.Text('VERIFIED',
              style: pw.TextStyle(
                  color: _success,
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────

  pw.Widget _footer(pw.Context context, Invoice invoice) {
    return pw.Column(
      children: [
        pw.Divider(color: _line, thickness: 0.6),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'This is a computer-generated invoice and is valid without a '
                'physical signature. Ref ${invoice.fingerprint}.',
                style: pw.TextStyle(color: _faint, fontSize: 7.5),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(color: _faint, fontSize: 7.5),
            ),
          ],
        ),
      ],
    );
  }

  // ── Shared painters / helpers ─────────────────────────────────────────────

  static void _signaturePainter(PdfGraphics canvas, PdfPoint size) {
    final w = size.x;
    final h = size.y;
    canvas
      ..setStrokeColor(_purpleDark)
      ..setLineWidth(1.6)
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round)
      // A flowing cursive-style flourish.
      ..moveTo(w * 0.04, h * 0.32)
      ..curveTo(w * 0.10, h * 0.92, w * 0.17, h * 0.04, w * 0.24, h * 0.52)
      ..curveTo(w * 0.31, h * 0.98, w * 0.35, h * 0.08, w * 0.42, h * 0.56)
      ..curveTo(w * 0.52, h * 1.08, w * 0.57, h * -0.02, w * 0.64, h * 0.50)
      ..curveTo(w * 0.74, h * 0.94, w * 0.82, h * 0.14, w * 0.96, h * 0.60)
      ..strokePath()
      // An underline swash.
      ..moveTo(w * 0.05, h * 0.16)
      ..curveTo(w * 0.40, h * 0.02, w * 0.70, h * 0.30, w * 0.99, h * 0.10)
      ..strokePath();
  }

  static void _checkPainter(PdfGraphics canvas, PdfPoint size) {
    final w = size.x;
    final h = size.y;
    canvas
      ..setStrokeColor(_success)
      ..setLineWidth(1.4)
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round)
      ..moveTo(w * 0.18, h * 0.52)
      ..lineTo(w * 0.42, h * 0.26)
      ..lineTo(w * 0.84, h * 0.76)
      ..strokePath();
  }

  pw.Widget _sectionLabel(String text) => pw.Text(
        text,
        style: pw.TextStyle(
          color: _faint,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1,
        ),
      );

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// Formats [Money] for the PDF, substituting "Rs. " for the un-renderable ₹.
class _MoneyText {
  _MoneyText(this.currency)
      : _formatter = currency == CurrencyCode.inr
            ? NumberFormat.currency(
                locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 2)
            : NumberFormat.currency(
                locale: 'en_US', symbol: currency.symbol, decimalDigits: 2);

  final CurrencyCode currency;
  final NumberFormat _formatter;

  String format(Money money) => _formatter.format(money.major);
}
