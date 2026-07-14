// lib/screens/admin/closeout/pdf/builders/payback_report_pdf.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';

import '../../models/exhibitor/payback_report_data.dart';
import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';

class PaybackReportPdfBuilder {
  final Uint8List logoBytes;
  final ReportAssetLoader assets;

  PaybackReportPdfBuilder({required this.assets, required this.logoBytes});

  static Future<PaybackReportPdfBuilder> fromAssets(
    ReportAssetLoader assets,
  ) async {
    final logo = await assets.loadBytes(
      'assets/images/ringmaster_show_logo.png',
    );

    return PaybackReportPdfBuilder(assets: assets, logoBytes: logo);
  }

  Future<ReportFileResult> buildFile(
    PaybackReportData data,
    ReportRequest request,
  ) async {
    final bytes = await build(data);

    final safeShowName = data.showName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    final fileName = [
      if (safeShowName.isNotEmpty) safeShowName else 'Show',
      'Paybacks Report.pdf',
    ].join(' - ');

    return ReportFileResult(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/pdf',
    );
  }

  Future<Uint8List> build(PaybackReportData data) async {
    final regular = pw.Font.ttf(
      await assets.loadByteData('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await assets.loadByteData('assets/fonts/NotoSans-Bold.ttf'),
    );

    final theme = pw.ThemeData.withFont(base: regular, bold: bold);

    final doc = pw.Document(theme: theme, compress: true);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
        maxPages: 4000,
        build: (context) {
          return [
            _buildHeader(data),
            pw.SizedBox(height: 14),
            _buildSummary(data),
            pw.SizedBox(height: 18),
            if (!data.hasPaybacks)
              _buildEmptyState()
            else ...[
              ..._buildOverviewSections(data),
              pw.NewPage(),
              pw.Text(
                'Payback Detail',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              ...data.exhibitors.expand(_buildExhibitorSections),
            ],
          ];
        },
        footer: (context) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'RingMaster Show Paybacks Report',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _buildHeader(PaybackReportData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 54,
          height: 54,
          margin: const pw.EdgeInsets.only(right: 12),
          child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Paybacks Report',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                data.showName,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if ((data.showDate ?? '').isNotEmpty)
                pw.Text(
                  data.showDate!,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              if ((data.showLocation ?? '').isNotEmpty)
                pw.Text(
                  data.showLocation!,
                  style: const pw.TextStyle(fontSize: 10),
                ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildSummary(PaybackReportData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#EEF3FF'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#1B356D'), width: 0.7),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _summaryItem('Grand Total Paybacks', _money(data.grandTotalCents)),
          _summaryItem(
            'Exhibitors Receiving Paybacks',
            data.totalExhibitors.toString(),
          ),
        ],
      ),
    );
  }

  pw.Widget _summaryItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _buildEmptyState() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        'No paybacks were found. Confirm that payback amounts are saved and results have been entered.',
        style: const pw.TextStyle(fontSize: 10),
      ),
    );
  }

  List<pw.Widget> _buildOverviewSections(PaybackReportData data) {
    const chunkSize = 200;
    final widgets = <pw.Widget>[
      pw.Text(
        'Exhibitor Payback Overview',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Summary of each exhibitor and the total amount due before the detailed breakdown.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 20),
    ];

    for (var i = 0; i < data.exhibitors.length; i += chunkSize) {
      final end = (i + chunkSize > data.exhibitors.length)
          ? data.exhibitors.length
          : i + chunkSize;
      final chunk = data.exhibitors.sublist(i, end);
      final isLastChunk = end == data.exhibitors.length;

      widgets.add(
        _buildOverviewTableChunk(
          exhibitors: chunk,
          grandTotalCents: data.grandTotalCents,
          includeGrandTotal: isLastChunk,
        ),
      );
      widgets.add(pw.SizedBox(height: 8));
    }

    return widgets;
  }

  pw.Widget _buildOverviewTableChunk({
    required List<PaybackExhibitorSummary> exhibitors,
    required int grandTotalCents,
    required bool includeGrandTotal,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: const {
        0: pw.FixedColumnWidth(44),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(3),
        3: pw.FixedColumnWidth(68),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _headerCell('Exh #'),
            _headerCell('Exhibitor'),
            _headerCell('Mailing Address'),
            _headerCell('Amount Due', alignRight: true),
          ],
        ),
        ...exhibitors.map(_buildOverviewRow),
        if (includeGrandTotal)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EEF3FF')),
            children: [
              _headerCell(''),
              _headerCell('Grand Total'),
              _headerCell(''),
              _headerCell(_money(grandTotalCents), alignRight: true),
            ],
          ),
      ],
    );
  }

  pw.TableRow _buildOverviewRow(PaybackExhibitorSummary exhibitor) {
    return pw.TableRow(
      children: [
        _bodyCell(
          exhibitor.exhibitorNumber.trim().isEmpty
              ? '—'
              : exhibitor.exhibitorNumber.trim(),
        ),
        _bodyCell(exhibitor.exhibitorName),
        _bodyCell(
          exhibitor.mailingAddress.trim().isEmpty
              ? '—'
              : exhibitor.mailingAddress.trim(),
        ),
        _bodyCell(_money(exhibitor.totalCents), alignRight: true),
      ],
    );
  }

  List<pw.Widget> _buildExhibitorSections(PaybackExhibitorSummary exhibitor) {
    const chunkSize = 29;
    final chunks = <List<PaybackBreakdownRow>>[];

    for (var i = 0; i < exhibitor.rows.length; i += chunkSize) {
      final end = (i + chunkSize > exhibitor.rows.length)
          ? exhibitor.rows.length
          : i + chunkSize;
      chunks.add(exhibitor.rows.sublist(i, end));
    }

    if (chunks.isEmpty) {
      return [
        _buildExhibitorSectionChunk(
          exhibitor: exhibitor,
          rows: const [],
          chunkIndex: 0,
          chunkCount: 1,
        ),
      ];
    }

    return [
      for (var i = 0; i < chunks.length; i++)
        _buildExhibitorSectionChunk(
          exhibitor: exhibitor,
          rows: chunks[i],
          chunkIndex: i,
          chunkCount: chunks.length,
        ),
    ];
  }

  pw.Widget _buildExhibitorSectionChunk({
    required PaybackExhibitorSummary exhibitor,
    required List<PaybackBreakdownRow> rows,
    required int chunkIndex,
    required int chunkCount,
  }) {
    final isContinuation = chunkIndex > 0;
    final title = isContinuation
        ? '${_exhibitorTitle(exhibitor)} continued ${chunkIndex + 1}/$chunkCount'
        : _exhibitorTitle(exhibitor);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: isContinuation ? 8 : 0),
        if (!isContinuation && exhibitor.mailingAddress.trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text(
              exhibitor.mailingAddress.trim(),
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#1B356D'),
            borderRadius: const pw.BorderRadius.only(
              topLeft: pw.Radius.circular(6),
              topRight: pw.Radius.circular(6),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              pw.Text(
                isContinuation ? '' : _money(exhibitor.totalCents),
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        _buildRowsTable(rows),
        pw.SizedBox(height: 12),
      ],
    );
  }

  String _exhibitorTitle(PaybackExhibitorSummary exhibitor) {
    final number = exhibitor.exhibitorNumber.trim();
    if (number.isEmpty) return exhibitor.exhibitorName;
    return '#$number  ${exhibitor.exhibitorName}';
  }

  pw.Widget _buildRowsTable(List<PaybackBreakdownRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: const {
        0: pw.FixedColumnWidth(44),
        1: pw.FixedColumnWidth(42),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FixedColumnWidth(48),
        4: pw.FlexColumnWidth(1.8),
        5: pw.FixedColumnWidth(34),
        6: pw.FixedColumnWidth(48),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _headerCell('Show'),
            _headerCell('Source'),
            _headerCell('Animal'),
            _headerCell('Tattoo'),
            _headerCell('Award / Placement'),
            _headerCell('Shown'),
            _headerCell('Amount', alignRight: true),
          ],
        ),
        ...rows.map(_buildTableRow),
      ],
    );
  }

  pw.TableRow _buildTableRow(PaybackBreakdownRow row) {
    return pw.TableRow(
      children: [
        _bodyCell(row.sectionLabel),
        _bodyCell(row.sourceLabel),
        _bodyCell(row.animalDescription),
        _bodyCell(row.tattooDisplay),
        _bodyCell(row.awardLabel),
        _bodyCell(row.eligibleCount?.toString() ?? '—'),
        _bodyCell(_money(row.amountCents), alignRight: true),
      ],
    );
  }

  pw.Widget _headerCell(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _bodyCell(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: const pw.TextStyle(fontSize: 7),
      ),
    );
  }

  String _money(int cents) {
    return '\$${(cents / 100).toStringAsFixed(2)}';
  }
}
