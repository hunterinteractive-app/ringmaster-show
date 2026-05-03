// lib/screens/admin/closeout/pdf/builders/sweepstakes_report_pdf.dart

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/clubs/sweepstakes_report_data.dart';

class SweepstakesReportPdf {
  final Uint8List? logoBytes;

  SweepstakesReportPdf({this.logoBytes});

  Future<pw.ThemeData> _buildTheme() async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final italic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'),
    );
    final boldItalic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-BoldItalic.ttf'),
    );

    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
    );
  }

  Future<ReportFileResult> buildFile(
    SweepstakesReportData data,
    ReportRequest request,
  ) async {
    final theme = await _buildTheme();
    final pdf = pw.Document(theme: theme);

    final showName = (request.showName ?? '').trim().isEmpty
        ? 'Unknown Show'
        : request.showName!.trim();

    final showDate = (request.showDate ?? '').trim().isEmpty
        ? 'Unknown Date'
        : request.showDate!.trim();

    final sections = data.sections.isNotEmpty
        ? data.sections
        : [
            SweepstakesReportSection(
              showLetter: data.showLetter,
              ruleSource: data.ruleSource,
              verificationStatus: data.verificationStatus,
              engineType: data.engineType,
              rows: data.rows,
            ),
          ];

    for (final section in sections) {
      final isNoResults = section.rows.isEmpty;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(24),
          theme: theme,
          footer: (context) => _footer(context),
          build: (context) => [
            _buildHeader(
              breedName: data.breedName,
              scope: data.scope,
              showLetter: section.showLetter,
              showName: showName,
              showDate: showDate,
              breedSanctionNumber: data.breedSanctionNumber,
              hostClubName: data.hostClubName,
              showLocation: data.showLocation,
              secretaryName: data.secretaryName,
              secretaryEmail: data.secretaryEmail,
              secretaryPhone: data.secretaryPhone,
            ),
            pw.SizedBox(height: 14),

            if (data.isNationalShow && data.topBreedRows.isNotEmpty) ...[
              _buildTopBreedsTable(data.topBreedRows),
              pw.SizedBox(height: 16),
            ],

            if (isNoResults)
              _buildNoResultsBox(
                'No rabbits of this breed were shown in this Show.',
              )
            else ...[
              _buildResultsTable(
                rows: section.rows,
                showVarietyPoints: _showVarietyPoints(section.rows),
                showGroupPoints: _showGroupPoints(section.rows),
                showBobPoints: _showBobPoints(section.rows),
                showBisPoints: _showBisPoints(section.rows),
                showFurPoints: _showFurPoints(section.rows),
              ),
              pw.SizedBox(height: 16),
              _buildCalculationExplanation(
                engineType: section.engineType,
                showVarietyPoints: _showVarietyPoints(section.rows),
                showGroupPoints: _showGroupPoints(section.rows),
                showBobPoints: _showBobPoints(section.rows),
                showBisPoints: _showBisPoints(section.rows),
                showFurPoints: _showFurPoints(section.rows),
              ),
              if (_isProvisional(section.verificationStatus)) ...[
                pw.SizedBox(height: 12),
                _buildDisclaimer(),
              ],
            ],
          ],
        ),
      );
    }

    final bytes = await pdf.save();

    return ReportFileResult(
      fileName: _buildFileName(
        breedName: data.breedName,
        scope: data.scope,
        showLetter: data.showLetter,
        showName: showName,
      ),
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  String _buildFileName({
    required String breedName,
    required String scope,
    required String showLetter,
    required String showName,
  }) {
    String clean(String input) {
      return input
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
    }

    final safeShowName = clean(showName);
    final safeBreedName = clean(breedName);
    final safeScope = clean(scope.toUpperCase());
    final safeShowLetter = clean(showLetter.toUpperCase());

    return '${safeShowName}_${safeBreedName}_Sweepstakes_Report_${safeScope}_${safeShowLetter}.pdf';
  }

  pw.Widget _buildHeader({
    required String breedName,
    required String scope,
    required String showLetter,
    required String showName,
    required String showDate,
    required String breedSanctionNumber,
    required String hostClubName,
    required String showLocation,
    required String secretaryName,
    required String secretaryEmail,
    required String secretaryPhone,
  }) {
  pw.Widget infoCell(String label, String value) {
    if (label.trim().isEmpty && value.trim().isEmpty) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 78,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 8.5),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget infoRow2(
    String leftLabel,
    String leftValue,
    String rightLabel,
    String rightValue,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: infoCell(leftLabel, leftValue)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: infoCell(rightLabel, rightValue)),
      ],
    );
  }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null)
          pw.Container(
            width: 100,
            height: 80,
            margin: const pw.EdgeInsets.only(right: 12),
            child: pw.Image(
              pw.MemoryImage(logoBytes!),
              fit: pw.BoxFit.contain,
            ),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'RingMaster Show Sweepstakes Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    infoRow2('Show Name', showName, 'Show Date', showDate),
                    infoRow2('Host Club', hostClubName, 'Location', showLocation),
                    infoRow2('Breed', breedName, 'Show', '$scope - $showLetter'),
                    infoRow2('Breed Sanction', breedSanctionNumber, '', ''),
                    infoRow2(
                      'Secretary',
                      secretaryName,
                      'Contact',
                      [
                        if (secretaryEmail.trim().isNotEmpty) secretaryEmail.trim(),
                        if (secretaryPhone.trim().isNotEmpty) secretaryPhone.trim(),
                      ].join(' / '),
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

  pw.Widget _buildNoResultsBox(String message) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
        color: PdfColors.grey100,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'No Results Reported',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            message,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTopBreedsTable(List<SweepstakesTopBreedRow> rows) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Top 10 Breeds',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Rank',
              'Breed',
              'Entries',
            ],
            data: rows
                .map(
                  (row) => [
                    row.rank.toString(),
                    row.breedName,
                    row.entryCount.toString(),
                  ],
                )
                .toList(),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey700,
            ),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            columnWidths: {
              0: const pw.FixedColumnWidth(34),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(50),
            },
          ),
        ],
      ),
    );
  }

  pw.Widget _buildResultsTable({
    required List<SweepstakesReportRow> rows,
    required bool showVarietyPoints,
    required bool showGroupPoints,
    required bool showBobPoints,
    required bool showBisPoints,
    required bool showFurPoints,
  }) {
    final headers = <String>[
      'Rank',
      'Exhibitor',
      'Address',
      'ARBA Class Pts',
      'Total',
    ];

    final tableData = rows.map((row) {
      return [
        row.rank.toString(),
        row.exhibitorName,
        row.exhibitorAddress,
        _fmt(row.arbaClassPoints),
        _fmt(row.totalPoints),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: tableData,
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.blueGrey700,
      ),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FlexColumnWidth(2.2),
        2: const pw.FlexColumnWidth(3.2),
        3: const pw.FixedColumnWidth(62),
        4: const pw.FixedColumnWidth(44),
      },
    );
  }

  pw.Widget _buildCalculationExplanation({
    required String engineType,
    required bool showVarietyPoints,
    required bool showGroupPoints,
    required bool showBobPoints,
    required bool showBisPoints,
    required bool showFurPoints,
  }) {
    final lines = <String>[
      'Points are awarded based on official sweepstakes scoring rules for this breed.',
      if (engineType.toUpperCase().contains('FLAT'))
        '- Class placements are assigned fixed point values based on placing (1st-5th).'
      else
        '- Class placements are weighted based on class size or exhibitor count.',
      if (showVarietyPoints)
        '- Variety awards contribute additional points where applicable.',
      if (showGroupPoints)
        '- Group awards contribute additional points where applicable.',
      if (showBobPoints)
        '- Best of Breed (BOB) and Best Opposite Sex (BOS) awards are included.',
      if (showBisPoints)
        '- Best in Show (BIS) and Reserve Best in Show (RBIS) awards are included.',
      if (showFurPoints)
        '- Fur/Wool class awards are included when applicable.',
      '- Total points reflect the combined value of all placements and awards earned at this show.',
    ];

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Points Calculation',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          ...lines.map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text(
                line,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDisclaimer() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber50,
        border: pw.Border.all(color: PdfColors.amber700),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Important',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.amber900,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'This report may contain provisional calculations and should be reviewed against the breed club rules before final submission.',
            style: const pw.TextStyle(fontSize: 9),
          ),
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

  bool _showVarietyPoints(List<SweepstakesReportRow> rows) =>
      rows.any((r) => r.varietyPoints != 0);

  bool _showGroupPoints(List<SweepstakesReportRow> rows) =>
      rows.any((r) => r.groupPoints != 0);

  bool _showBobPoints(List<SweepstakesReportRow> rows) =>
      rows.any((r) => r.bobPoints != 0);

  bool _showBisPoints(List<SweepstakesReportRow> rows) =>
      rows.any((r) => r.bisPoints != 0);

  bool _showFurPoints(List<SweepstakesReportRow> rows) =>
      rows.any((r) => r.furPoints != 0);

  bool _isProvisional(String verificationStatus) =>
      verificationStatus.trim().toUpperCase() != 'VERIFIED';

  String _fmt(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}