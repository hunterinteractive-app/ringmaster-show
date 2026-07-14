import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/judge/breed_judged_totals_report_data.dart';

class BreedJudgedTotalsReportPdfBuilder {
  BreedJudgedTotalsReportPdfBuilder({
    required ReportAssetLoader assets,
    DateFormat? dateFormat,
    DateFormat? dateTimeFormat,
  }) : _assets = assets,
       _dateFormat = dateFormat ?? DateFormat('MM/dd/yyyy'),
       _dateTimeFormat = dateTimeFormat ?? DateFormat('MM/dd/yyyy h:mm a');

  final DateFormat _dateFormat;
  final DateFormat _dateTimeFormat;
  final ReportAssetLoader _assets;

  Future<ReportFileResult> buildFile(
    BreedJudgedTotalsReportData data,
    ReportRequest request,
  ) async {
    final bytes = await build(data);
    final safeShowName = data.show.showName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final fileName = safeShowName.isEmpty
        ? 'Breed_Judged_Totals_Report.pdf'
        : '${safeShowName}_Breed_Judged_Totals_Report.pdf';

    return ReportFileResult(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/pdf',
    );
  }

  Future<Uint8List> build(BreedJudgedTotalsReportData data) async {
    final document = pw.Document(
      title: 'Breed Judged Totals Report - ${data.show.showName}',
      author: 'RingMaster Show',
      creator: 'RingMaster Show',
      subject: 'Alphabetical judged totals by breed.',
    );

    final fonts = await _loadFonts();

    document.addPage(
      pw.MultiPage(
        maxPages: 500,
        pageTheme: _pageTheme(fonts),
        header: (_) => _buildHeader(data),
        footer: _buildFooter,
        build: (_) {
          if (data.breedRows.isEmpty && data.furRows.isEmpty) {
            return <pw.Widget>[
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text(
                  'No judged breed totals were found for this show.',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ];
          }

          return <pw.Widget>[
            _buildSummary(data),
            pw.SizedBox(height: 12),
            ..._buildSectionTable(
              title: 'Breed Judged Totals',
              rows: data.breedRows,
              emptyText: 'No breed judged totals were found.',
            ),
            pw.SizedBox(height: 14),
            ..._buildSectionTable(
              title: 'Fur/Wool Judged Totals',
              rows: data.furRows,
              emptyText: 'No fur/wool judged totals were found.',
            ),
            pw.SizedBox(height: 8),
            _buildGrandTotal(data),
            if (data.showBreakdowns.isNotEmpty) ...[
              pw.NewPage(),
              ..._buildShowBreakdowns(data),
            ],
          ];
        },
      ),
    );

    return document.save();
  }

  Future<_BreedJudgedTotalsReportFonts> _loadFonts() async {
    final regular = pw.Font.ttf(
      await _assets.loadByteData('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await _assets.loadByteData('assets/fonts/NotoSans-Bold.ttf'),
    );

    return _BreedJudgedTotalsReportFonts(regular: regular, bold: bold);
  }

  pw.PageTheme _pageTheme(_BreedJudgedTotalsReportFonts fonts) {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.letter.portrait,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 30),
      theme: pw.ThemeData.withFont(
        base: fonts.regular,
        bold: fonts.bold,
        italic: fonts.regular,
        boldItalic: fonts.bold,
      ),
    );
  }

  pw.Widget _buildHeader(BreedJudgedTotalsReportData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.7, color: PdfColors.grey600),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'Breed Judged Totals Report',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  data.show.showName,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (_showDateLine(data).isNotEmpty)
                  pw.Text(
                    _showDateLine(data),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if (data.show.locationName.trim().isNotEmpty)
                  pw.Text(
                    data.show.locationName,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if (data.scopeLabel.trim().isNotEmpty)
                  pw.Text(
                    'Scope: ${data.scopeLabel}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                'Generated: ${_dateTimeFormat.format(data.generatedAt)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              if ((data.show.secretaryName ?? '').trim().isNotEmpty)
                pw.Text(
                  'Secretary: ${data.show.secretaryName}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              if ((data.show.secretaryEmail ?? '').trim().isNotEmpty)
                pw.Text(
                  data.show.secretaryEmail ?? '',
                  style: const pw.TextStyle(fontSize: 8),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummary(BreedJudgedTotalsReportData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey700, width: 0.4),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          _summaryItem('Breeds', data.breedRows.length.toString()),
          _summaryDivider(),
          _summaryItem('Breed Judged', data.totalBreedJudged.toString()),
          _summaryDivider(),
          _summaryItem('Fur/Wool', data.totalFurJudged.toString()),
          _summaryDivider(),
          _summaryItem('Total Judged', data.totalJudged.toString()),
        ],
      ),
    );
  }

  pw.Widget _summaryItem(String label, String value) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  pw.Widget _summaryDivider() {
    return pw.Container(width: 0.5, height: 28, color: PdfColors.grey400);
  }

  List<pw.Widget> _buildSectionTable({
    required String title,
    required List<BreedJudgedTotalsReportRow> rows,
    required String emptyText,
  }) {
    final widgets = <pw.Widget>[
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
    ];

    if (rows.isEmpty) {
      widgets.add(pw.Text(emptyText, style: const pw.TextStyle(fontSize: 8)));
      return widgets;
    }

    widgets.add(
      pw.TableHelper.fromTextArray(
        headers: const ['Breed', 'Species', 'Total Judged'],
        data: rows
            .map(
              (row) => <String>[
                row.breed,
                row.species,
                row.totalJudged.toString(),
              ],
            )
            .toList(),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8),
        border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.4),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellAlignment: pw.Alignment.centerLeft,
        headerAlignment: pw.Alignment.centerLeft,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        columnWidths: const <int, pw.TableColumnWidth>{
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(82),
          2: pw.FixedColumnWidth(64),
        },
      ),
    );

    widgets.add(pw.SizedBox(height: 4));
    widgets.add(
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '$title Total: ${_sectionTotal(rows)}',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );

    return widgets;
  }

  int _sectionTotal(List<BreedJudgedTotalsReportRow> rows) {
    return rows.fold<int>(0, (sum, row) => sum + row.totalJudged);
  }

  List<pw.Widget> _buildShowBreakdowns(BreedJudgedTotalsReportData data) {
    final widgets = <pw.Widget>[
      pw.Text(
        'Breakdown by Show',
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Each show below uses the same judged-count rules as the overall totals.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 12),
    ];

    for (var index = 0; index < data.showBreakdowns.length; index++) {
      final breakdown = data.showBreakdowns[index];
      if (index > 0) {
        widgets.add(pw.NewPage(freeSpace: 180));
        widgets.add(pw.SizedBox(height: 8));
      }

      widgets.addAll(_buildShowBreakdown(breakdown));
    }

    return widgets;
  }

  List<pw.Widget> _buildShowBreakdown(
    BreedJudgedTotalsShowBreakdown breakdown,
  ) {
    return <pw.Widget>[
      pw.Text(
        breakdown.label,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      _buildBreakdownTotals(breakdown),
      pw.SizedBox(height: 8),
      ..._buildSectionTable(
        title: '${breakdown.label} Breed Judged Totals',
        rows: breakdown.breedRows,
        emptyText: 'No breed judged totals were found for this show.',
      ),
      if (breakdown.furRows.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        ..._buildSectionTable(
          title: '${breakdown.label} Fur/Wool Judged Totals',
          rows: breakdown.furRows,
          emptyText: 'No fur/wool judged totals were found for this show.',
        ),
      ],
      pw.SizedBox(height: 10),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${breakdown.label} Overall Total Judged: ${breakdown.totalJudged}',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ];
  }

  pw.Widget _buildBreakdownTotals(BreedJudgedTotalsShowBreakdown breakdown) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey600, width: 0.35),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          _compactTotal('Breeds', breakdown.breedRows.length.toString()),
          _summaryDivider(),
          _compactTotal('Breed Judged', breakdown.totalBreedJudged.toString()),
          _summaryDivider(),
          _compactTotal('Fur/Wool', breakdown.totalFurJudged.toString()),
          _summaryDivider(),
          _compactTotal('Total Judged', breakdown.totalJudged.toString()),
        ],
      ),
    );
  }

  pw.Widget _compactTotal(String label, String value) {
    return pw.Expanded(
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: <pw.Widget>[
          pw.Text(
            '$label: ',
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(value, style: const pw.TextStyle(fontSize: 7)),
        ],
      ),
    );
  }

  pw.Widget _buildGrandTotal(BreedJudgedTotalsReportData data) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Overall Total Judged: ${data.totalJudged}',
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
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

  String _showDateLine(BreedJudgedTotalsReportData data) {
    final start = data.show.startDate;
    final end = data.show.endDate;

    if (start == null && end == null) return '';
    if (start != null && end == null) return _dateFormat.format(start);
    if (start == null && end != null) return _dateFormat.format(end);

    if (start == null || end == null) return '';

    final formattedStart = _dateFormat.format(start);
    final formattedEnd = _dateFormat.format(end);
    if (formattedStart == formattedEnd) return formattedStart;
    return '$formattedStart - $formattedEnd';
  }
}

class _BreedJudgedTotalsReportFonts {
  const _BreedJudgedTotalsReportFonts({
    required this.regular,
    required this.bold,
  });

  final pw.Font regular;
  final pw.Font bold;
}
