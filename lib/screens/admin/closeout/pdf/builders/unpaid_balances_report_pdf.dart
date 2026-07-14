import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/unpaid/unpaid_balances_report_data.dart';

class UnpaidBalancesReportPdfBuilder {
  final Uint8List logoBytes;
  final ReportAssetLoader assets;

  UnpaidBalancesReportPdfBuilder({
    required this.assets,
    required this.logoBytes,
  });

  static Future<UnpaidBalancesReportPdfBuilder> fromAssets(
    ReportAssetLoader assets,
  ) async {
    final logo = await assets.loadBytes(
      'assets/images/ringmaster_show_logo.png',
    );

    return UnpaidBalancesReportPdfBuilder(assets: assets, logoBytes: logo);
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
    UnpaidBalancesReportData data,
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

    final fileName = '$cleanedShowName - Unpaid Exhibitor Balances.pdf';

    return ReportFileResult(
      fileName: fileName,
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  pw.Widget _header(UnpaidBalancesReportData data, pw.MemoryImage logoImage) {
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
                      'Unpaid Exhibitor Balances (Pay at Check-In)',
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
            'No unpaid exhibitor balances were found for this show.',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'If balances were expected, check that the exhibitor balance RPC is returning rows with payment_status unpaid or partial and balance_due_cents greater than zero.',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }

  pw.Widget _table(UnpaidBalancesReportData data) {
    final rows = data.rows.toList()
      ..sort((a, b) {
        final lastNameCompare = _lastNameSortKey(
          a.exhibitorName,
        ).compareTo(_lastNameSortKey(b.exhibitorName));

        if (lastNameCompare != 0) return lastNameCompare;

        return _normalizeSortText(
          a.exhibitorName,
        ).compareTo(_normalizeSortText(b.exhibitorName));
      });

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.70), // Paid
        1: pw.FlexColumnWidth(1.65), // Exhibitor
        2: pw.FlexColumnWidth(0.70), // Type
        3: pw.FlexColumnWidth(1.05), // Phone
        4: pw.FlexColumnWidth(1.65), // Sections
        5: pw.FlexColumnWidth(0.50), // Entries
        6: pw.FlexColumnWidth(0.72), // Subtotal
        7: pw.FlexColumnWidth(0.65), // Show Fee
        8: pw.FlexColumnWidth(0.65), // Discount
        9: pw.FlexColumnWidth(0.82), // Balance Due
      },
      children: [_headerRow(), ...rows.map(_dataRow)],
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
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
        ),
      );
    }

    return pw.TableRow(
      children: [
        cell('Paid'),
        cell('Exhibitor'),
        cell('Type'),
        cell('Phone'),
        cell('Sections'),
        cell('Entries', alignment: pw.Alignment.centerRight),
        cell('Subtotal', alignment: pw.Alignment.centerRight),
        cell('Show Fee', alignment: pw.Alignment.centerRight),
        cell('Discount', alignment: pw.Alignment.centerRight),
        cell('Balance Due', alignment: pw.Alignment.centerRight),
      ],
    );
  }

  pw.TableRow _dataRow(UnpaidBalanceRow row) {
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
        child: pw.Text(text, style: style ?? const pw.TextStyle(fontSize: 7)),
      );
    }

    return pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: _paidCheckboxCell(),
        ),
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
          _money(row.showFee, currency: null),
          alignment: pw.Alignment.centerRight,
        ),
        textCell(
          row.discount > 0 ? '-${_money(row.discount, currency: null)}' : '',
          alignment: pw.Alignment.centerRight,
        ),
        textCell(
          _money(row.totalDue, currency: null),
          alignment: pw.Alignment.centerRight,
          style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _sectionsWidget(List<SectionCountRow> sections) {
    if (sections.isEmpty) {
      return pw.Text('', style: pw.TextStyle(fontSize: 7));
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
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ),
            )
            .toList(),
      );
    }

    final left = <SectionCountRow>[];
    final right = <SectionCountRow>[];

    final mid = (sections.length / 2).ceil();
    left.addAll(sections.take(mid));
    right.addAll(sections.skip(mid));

    pw.Widget buildColumn(List<SectionCountRow> items) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: items
            .map(
              (s) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 1),
                child: pw.Text(
                  '${s.label}: ${s.count}',
                  style: const pw.TextStyle(fontSize: 7),
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

  pw.Widget _paidCheckboxCell() {
    return pw.Center(
      child: pw.Container(
        width: 10,
        height: 10,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.8),
        ),
      ),
    );
  }

  pw.Widget _totals(UnpaidBalancesReportData data) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 260,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey700, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _totalLine('Total Exhibitors', '${data.totalExhibitors}'),
            _totalLine('Total Entries', '${data.totalEntries}'),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.5),
            _totalLine(
              'Grand Balance Due',
              _money(data.grandTotalDue, currency: data.currency),
              bold: true,
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

  String _lastNameSortKey(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return '';

    final withoutSuffix = cleaned.replaceFirst(
      RegExp(r'\s+(Jr\.?|Sr\.?|II|III|IV|V)$', caseSensitive: false),
      '',
    );

    final parts = withoutSuffix.split(' ');
    final last = parts.isEmpty ? withoutSuffix : parts.last;

    return '${_normalizeSortText(last)}|${_normalizeSortText(withoutSuffix)}';
  }

  String _normalizeSortText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
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
        // remove UUID / long id-like fragments
        .replaceAll(RegExp(r'\b[0-9a-fA-F\-]{8,}\b'), '')
        // remove invalid filename characters
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        // collapse whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
