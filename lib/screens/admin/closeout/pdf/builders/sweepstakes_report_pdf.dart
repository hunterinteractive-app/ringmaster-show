// lib/screens/admin/closeout/pdf/builders/sweepstakes_report_pdf.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/clubs/sweepstakes_report_data.dart';

class SweepstakesReportPdf {
  /// OPTIONAL: pass logo bytes in constructor
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

          _buildRuleBadges(data),

          pw.SizedBox(height: 14),

          _buildResultsTable(data),

          pw.SizedBox(height: 16),

          _buildCalculationExplanation(data),

          pw.SizedBox(height: 14),

          _buildRulesBasis(data),

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

  // =====================================================
  // HEADER (WITH LOGO)
  // =====================================================

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
                    if (sanctionNumber.isNotEmpty)
                      infoRow('Sanction #', sanctionNumber),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (logoBytes != null)
          pw.Container(
            width: 110,
            height: 80,
            alignment: pw.Alignment.topRight,
            child: pw.Image(
              pw.MemoryImage(logoBytes!),
              fit: pw.BoxFit.contain,
            ),
          ),
      ],
    );
  }

  // =====================================================
  // RULE BADGES
  // =====================================================

  pw.Widget _buildRuleBadges(SweepstakesReportData data) {
    List<pw.Widget> badges = [];

    pw.Widget badge(String text, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        margin: const pw.EdgeInsets.only(right: 6, bottom: 4),
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 8,
            color: PdfColors.white,
          ),
        ),
      );
    }

    if (data.engineType.contains('FLAT')) {
      badges.add(badge('Flat Scoring', PdfColors.blueGrey));
    } else {
      badges.add(badge('Multiplier Scoring', PdfColors.blue));
    }

    if (data.showVarietyPoints) {
      badges.add(badge('Variety Awards', PdfColors.green));
    }

    if (data.showGroupPoints) {
      badges.add(badge('Group Awards', PdfColors.teal));
    }

    if (data.showBobPoints) {
      badges.add(badge('Breed Awards', PdfColors.deepOrange));
    }

    if (data.showBisPoints) {
      badges.add(badge('BIS Enabled', PdfColors.purple));
    }

    if (data.showFurPoints) {
      badges.add(badge('Fur/Wool', PdfColors.brown));
    }

    return pw.Wrap(children: badges);
  }

  // =====================================================
  // RESULTS TABLE
  // =====================================================

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
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    );
  }

  // =====================================================
  // CALCULATION EXPLANATION (NEW CORE FEATURE)
  // =====================================================

  pw.Widget _buildCalculationExplanation(SweepstakesReportData data) {
    List<String> lines = [];

    lines.add('Points are calculated based on the following structure:');

    lines.add('• Class placements (1st–5th)');

    if (data.engineType.contains('FLAT')) {
      lines.add('• Flat placement scoring (no class size multiplier)');
    } else {
      lines.add('• Placement points multiplied by class size or exhibitor count');
    }

    if (data.showVarietyPoints) {
      lines.add('• Variety awards (Best/Best Opposite Variety)');
    }

    if (data.showGroupPoints) {
      lines.add('• Group awards (Best/Best Opposite Group)');
    }

    if (data.showBobPoints) {
      lines.add('• Breed awards (Best of Breed / Best Opposite)');
    }

    if (data.showBisPoints) {
      lines.add('• Best in Show / Reserve in Show awards');
    }

    if (data.showFurPoints) {
      lines.add('• Fur/Wool awards included in scoring');
    }

    return pw.Container(
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
            (l) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                l,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // RULE BASIS (ENHANCED)
  // =====================================================

  pw.Widget _buildRulesBasis(SweepstakesReportData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Rule Metadata',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Engine: ${data.engineType}', style: pw.TextStyle(fontSize: 9)),
          pw.Text('Source: ${data.ruleSource}', style: pw.TextStyle(fontSize: 9)),
          pw.Text('Status: ${data.verificationStatus}', style: pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  // =====================================================
  // DISCLAIMER
  // =====================================================

  pw.Widget _buildDisclaimer(SweepstakesReportData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber50,
        border: pw.Border.all(color: PdfColors.amber700),
      ),
      child: pw.Text(
        data.disclaimer,
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }

  // =====================================================
  // FOOTER
  // =====================================================

  pw.Widget _footer(pw.Context context) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Generated by RingMaster Show',
          style: const pw.TextStyle(fontSize: 7),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7),
        ),
      ],
    );
  }

  String _fmt(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}