// lib/screens/admin/closeout/pdf/builders/sweepstakes_report_pdf.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/clubs/sweepstakes_report_data.dart';

class SweepstakesReportPdf {
  final Uint8List? logoBytes;

  SweepstakesReportPdf({this.logoBytes});

  Future<ReportFileResult> buildFile(
    SweepstakesReportData data,
    ReportRequest request,
  ) async {
    final pdf = pw.Document();

    final showName = (request.showName ?? '').trim().isEmpty
        ? 'Unknown Show'
        : request.showName!.trim();

    final showDate = (request.showDate ?? '').trim().isEmpty
        ? 'Unknown Date'
        : request.showDate!.trim();

    final sanctionNumber = (request.sanctionNumber ?? '').trim();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) => _footer(context),
        build: (context) => [
          _buildHeader(
            data: data,
            showName: showName,
            showDate: showDate,
            sanctionNumber: sanctionNumber,
          ),
          pw.SizedBox(height: 14),
          _buildResultsTable(data),
          pw.SizedBox(height: 16),
          _buildCalculationExplanation(data),
          if (data.isProvisional) ...[
            pw.SizedBox(height: 12),
            _buildDisclaimer(data),
          ],
        ],
      ),
    );

    final bytes = await pdf.save();

    return ReportFileResult(
      fileName: _buildFileName(
        breedName: data.breedName,
        scope: data.scope,
        showName: showName,
      ),
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  String _buildFileName({
    required String breedName,
    required String scope,
    required String showName,
  }) {
    String clean(String input) {
      return input
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
    }

    return '${clean(showName)}_${clean(breedName)}_${clean(scope.toLowerCase())}_sweepstakes.pdf';
  }

  pw.Widget _buildHeader({
    required SweepstakesReportData data,
    required String showName,
    required String showDate,
    required String sanctionNumber,
  }) {
    pw.Widget infoRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          children: [
            pw.Container(
              width: 100,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
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
                    infoRow('Show Name', showName),
                    infoRow('Show Date', showDate),
                    infoRow('Breed', data.breedName),
                    infoRow('Scope', data.scope),
                    infoRow('Show Letter', data.showLetter),
                    if (sanctionNumber.isNotEmpty)
                      infoRow('Sanction #', sanctionNumber),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildResultsTable(SweepstakesReportData data) {
    final headers = <String>[
      'Rank',
      'Exhibitor',
      'Class',
      if (data.showVarietyPoints) 'Variety',
      if (data.showGroupPoints) 'Group',
      if (data.showBobPoints) 'BOB/BOS',
      if (data.showBisPoints) 'BIS/BRIS',
      if (data.showFurPoints) 'Fur/Wool',
      'Total',
    ];

    final tableData = data.rows.map((row) {
      return [
        row.rank.toString(),
        row.exhibitorName,
        _fmt(row.classPoints),
        if (data.showVarietyPoints) _fmt(row.varietyPoints),
        if (data.showGroupPoints) _fmt(row.groupPoints),
        if (data.showBobPoints) _fmt(row.bobPoints),
        if (data.showBisPoints) _fmt(row.bisPoints),
        if (data.showFurPoints) _fmt(row.furPoints),
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
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      columnWidths: {
        0: const pw.FixedColumnWidth(36),
        1: const pw.FlexColumnWidth(3.0),
      },
    );
  }

  pw.Widget _buildCalculationExplanation(SweepstakesReportData data) {
    final lines = <String>[
      'Points are awarded based on official sweepstakes scoring rules for this breed.',
      
      if (data.engineType.toUpperCase().contains('FLAT'))
        '- Class placements are assigned fixed point values based on placing (1st–5th).'
      else
        '- Class placements are weighted based on class size or exhibitor count.',

      if (data.showVarietyPoints)
        '- Variety awards contribute additional points where applicable.',

      if (data.showGroupPoints)
        '- Group awards contribute additional points where applicable.',

      if (data.showBobPoints)
        '- Best of Breed (BOB) and Best Opposite Sex (BOS) awards are included.',

      if (data.showBisPoints)
        '- Best in Show (BIS) and Reserve Best in Show (RBIS) awards are included.',

      if (data.showFurPoints)
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

  pw.Widget _buildDisclaimer(SweepstakesReportData data) {
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
            data.disclaimer,
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

  String _fmt(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}