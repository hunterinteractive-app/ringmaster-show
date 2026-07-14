// lib/screens/admin/closeout/pdf/builders/paid_exhibitor_report_pdf.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/paid/paid_exhibitor_report_data.dart';

class PaidExhibitorReportPdfBuilder {
  final Uint8List logoBytes;
  final ReportAssetLoader assets;

  PaidExhibitorReportPdfBuilder({
    required this.assets,
    required this.logoBytes,
  });

  static Future<PaidExhibitorReportPdfBuilder> fromAssets(
    ReportAssetLoader assets,
  ) async {
    final logo = await assets.loadBytes(
      'assets/images/ringmaster_show_logo.png',
    );

    return PaidExhibitorReportPdfBuilder(assets: assets, logoBytes: logo);
  }

  Future<pw.ThemeData> _buildTheme() async {
    final regular = pw.Font.ttf(
      await assets.loadByteData('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await assets.loadByteData('assets/fonts/NotoSans-Bold.ttf'),
    );
    final italic = pw.Font.ttf(
      await assets.loadByteData('assets/fonts/NotoSans-Italic.ttf'),
    );
    final boldItalic = pw.Font.ttf(
      await assets.loadByteData('assets/fonts/NotoSans-BoldItalic.ttf'),
    );

    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
    );
  }

  Future<ReportFileResult> buildFile(
    PaidExhibitorReportData data,
    ReportRequest request,
  ) async {
    final theme = await _buildTheme();
    final pdf = pw.Document(theme: theme);
    final logoImage = pw.MemoryImage(logoBytes);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 34),
        theme: theme,
        header: (_) => _header(data, logoImage),
        footer: (context) => _footer(context),
        build: (_) => [
          pw.SizedBox(height: 10),
          if (data.rows.isEmpty)
            _emptyState()
          else ...[
            _table(data),
            pw.SizedBox(height: 12),
            _totals(data),
          ],
        ],
      ),
    );

    final bytes = await pdf.save();

    final cleanedShowName = _cleanFilePart(
      data.showName.isEmpty ? 'Show' : data.showName,
    );

    final fileName = '$cleanedShowName - Paid Exhibitor Report.pdf';

    return ReportFileResult(
      fileName: fileName,
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  pw.Widget _header(PaidExhibitorReportData data, pw.MemoryImage logoImage) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text(
                      data.showName,
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  if (data.showDate.isNotEmpty)
                    pw.Center(child: pw.Text(data.showDate)),
                  if (data.showLocation.isNotEmpty)
                    pw.Center(
                      child: pw.Text(
                        data.showLocation,
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  pw.SizedBox(height: 10),
                  pw.Center(
                    child: pw.Text(
                      'Paid Exhibitor Report',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Container(
              width: 100,
              height: 100,
              alignment: pw.Alignment.topRight,
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.6),
      ],
    );
  }

  pw.Widget _emptyState() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'No paid exhibitor records were found for this show.',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'If paid records were expected, check that show_payments contains paid or partially_refunded rows and that the exhibitor balance RPC is returning paid_online_cents or paid_manual_cents greater than zero.',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }

  pw.Widget _table(PaidExhibitorReportData data) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.55), // Exhibitor
        1: pw.FlexColumnWidth(0.68), // Type
        2: pw.FlexColumnWidth(0.95), // Phone
        3: pw.FlexColumnWidth(1.50), // Sections
        4: pw.FlexColumnWidth(0.50), // Entries
        5: pw.FlexColumnWidth(0.70), // Subtotal
        6: pw.FlexColumnWidth(0.65), // Discount
        7: pw.FlexColumnWidth(0.72), // Online
        8: pw.FlexColumnWidth(0.72), // Manual
        9: pw.FlexColumnWidth(0.68), // Refunded
        10: pw.FlexColumnWidth(0.78), // Paid
        11: pw.FlexColumnWidth(0.75), // Balance
        12: pw.FlexColumnWidth(0.65), // Status
      },
      children: [_headerRow(), ...data.rows.map(_dataRow)],
    );
  }

  pw.TableRow _headerRow() {
    pw.Widget cell(
      String text, {
      pw.Alignment alignment = pw.Alignment.centerLeft,
    }) {
      return pw.Container(
        alignment: alignment,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        color: PdfColors.grey300,
        child: pw.Text(
          text,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6.5),
        ),
      );
    }

    return pw.TableRow(
      children: [
        cell('Exhibitor'),
        cell('Type'),
        cell('Phone'),
        cell('Sections'),
        cell('Entries', alignment: pw.Alignment.centerRight),
        cell('Subtotal', alignment: pw.Alignment.centerRight),
        cell('Discount', alignment: pw.Alignment.centerRight),
        cell('Online', alignment: pw.Alignment.centerRight),
        cell('Manual', alignment: pw.Alignment.centerRight),
        cell('Refunded', alignment: pw.Alignment.centerRight),
        cell('Amount Paid', alignment: pw.Alignment.centerRight),
        cell('Balance', alignment: pw.Alignment.centerRight),
        cell('Status'),
      ],
    );
  }

  pw.TableRow _dataRow(PaidExhibitorRow row) {
    pw.Widget textCell(
      String text, {
      pw.Alignment alignment = pw.Alignment.centerLeft,
      pw.EdgeInsets padding = const pw.EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 5,
      ),
      pw.TextStyle? style,
    }) {
      return pw.Container(
        alignment: alignment,
        padding: padding,
        child: pw.Text(text, style: style ?? const pw.TextStyle(fontSize: 6.5)),
      );
    }

    return pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        textCell(row.exhibitorName),
        textCell(row.exhibitorType),
        textCell(row.phone),
        pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: _sectionsWidget(row.sections),
        ),
        textCell(
          row.entryCount.toString(),
          alignment: pw.Alignment.centerRight,
        ),
        textCell(
          _money(row.subtotal, currency: null),
          alignment: pw.Alignment.centerRight,
        ),
        textCell(
          row.discount > 0 ? '-${_money(row.discount, currency: null)}' : '',
          alignment: pw.Alignment.centerRight,
        ),
        textCell(
          row.paidOnline > 0 ? _money(row.paidOnline, currency: null) : '',
          alignment: pw.Alignment.centerRight,
        ),
        textCell(
          row.paidManual > 0 ? _money(row.paidManual, currency: null) : '',
          alignment: pw.Alignment.centerRight,
        ),
        textCell(
          row.refunded > 0 ? '-${_money(row.refunded, currency: null)}' : '',
          alignment: pw.Alignment.centerRight,
        ),
        textCell(
          _money(row.amountPaid, currency: null),
          alignment: pw.Alignment.centerRight,
          style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
        ),
        textCell(
          row.balanceDue > 0 ? _money(row.balanceDue, currency: null) : '',
          alignment: pw.Alignment.centerRight,
        ),
        textCell(_formatStatus(row.paymentStatus)),
      ],
    );
  }

  pw.Widget _sectionsWidget(List<PaidSectionCountRow> sections) {
    if (sections.isEmpty) {
      return pw.Text('', style: const pw.TextStyle(fontSize: 6.5));
    }

    if (sections.length <= 2) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: sections
            .map(
              (s) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 1),
                child: pw.Text(
                  '${s.label}: ${s.count}',
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
              ),
            )
            .toList(),
      );
    }

    final left = <PaidSectionCountRow>[];
    final right = <PaidSectionCountRow>[];

    final mid = (sections.length / 2).ceil();
    left.addAll(sections.take(mid));
    right.addAll(sections.skip(mid));

    pw.Widget buildColumn(List<PaidSectionCountRow> items) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: items
            .map(
              (s) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 1),
                child: pw.Text(
                  '${s.label}: ${s.count}',
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
              ),
            )
            .toList(),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: buildColumn(left)),
        pw.SizedBox(width: 8),
        pw.Expanded(child: buildColumn(right)),
      ],
    );
  }

  pw.Widget _totals(PaidExhibitorReportData data) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 285,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey700, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _totalLine('Total Paid Exhibitors', '${data.totalExhibitors}'),
            _totalLine('Total Entries', '${data.totalEntries}'),
            if (data.totalFurEntries > 0)
              _totalLine('Total Fur/Wool Entries', '${data.totalFurEntries}'),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.5),
            _totalLine(
              'Online Paid',
              _money(data.grandPaidOnline, currency: data.currency),
            ),
            _totalLine(
              'Manual Paid',
              _money(data.grandPaidManual, currency: data.currency),
            ),
            if (data.grandRefunded > 0)
              _totalLine(
                'Refunded',
                '-${_money(data.grandRefunded, currency: data.currency)}',
              ),
            _totalLine(
              'Grand Amount Paid',
              _money(data.grandAmountPaid, currency: data.currency),
              bold: true,
            ),
            if (data.grandBalanceDue > 0)
              _totalLine(
                'Remaining Balance Due',
                _money(data.grandBalanceDue, currency: data.currency),
              ),
          ],
        ),
      ),
    );
  }

  pw.Widget _totalLine(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: 8,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  pw.Widget _footer(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Divider(thickness: 0.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated by RingMaster Show',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatStatus(String value) {
    final normalized = value.trim().toLowerCase();

    switch (normalized) {
      case 'paid':
        return 'Paid';
      case 'partial':
        return 'Partial';
      case 'overpaid':
        return 'Overpaid';
      case 'partially_refunded':
        return 'Partially Refunded';
      case 'refunded':
        return 'Refunded';
      case 'pending':
        return 'Pending';
      default:
        if (value.trim().isEmpty) return '';
        return value.trim();
    }
  }

  String _money(double value, {String? currency}) {
    final sym = _currencySymbol(currency);
    return '$sym${value.toStringAsFixed(2)}';
  }

  String _currencySymbol(String? currency) {
    final c = (currency ?? 'USD').toUpperCase();
    if (c == 'USD') return r'$';
    if (c == 'CAD') return r'$';
    if (c == 'EUR') return '€';
    if (c == 'GBP') return '£';
    return r'$';
  }

  String _cleanFilePart(String input) {
    return input
        .replaceAll(RegExp(r'\b[0-9a-fA-F\-]{8,}\b'), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
