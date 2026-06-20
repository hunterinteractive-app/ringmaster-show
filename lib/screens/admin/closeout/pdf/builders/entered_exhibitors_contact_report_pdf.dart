// lib/screens/admin/closeout/pdf/builders/entered_exhibitors_contact_report_pdf.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/entered_exhibitors_contact_report_data.dart';

class EnteredExhibitorsContactReportPdf {
  Future<ReportFileResult> buildFile(
    EnteredExhibitorsContactReportData data,
    ReportRequest req,
  ) async {
    final pdf = pw.Document();

    final rows = [...data.rows]
      ..sort((a, b) => a.exhibitorName
          .toLowerCase()
          .compareTo(b.exhibitorName.toLowerCase()));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            'Entered Exhibitors Contact List',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(data.showName),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.grey300,
            ),
            cellAlignment: pw.Alignment.centerLeft,
            headers: const [
              'Exhibitor',
              'Address',
              'Email',
              'Phone',
            ],
            data: rows
                .map(
                  (r) => [
                    r.exhibitorName,
                    r.address,
                    r.email,
                    r.phone,
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();

    String clean(String input) {
      return input
          // remove UUID / long id-like fragments
          .replaceAll(RegExp(r'\b[0-9a-fA-F\-]{8,}\b'), '')
          // remove non filename-safe chars
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          // collapse spaces to underscores
          .replaceAll(RegExp(r'\s+'), '_')
          // collapse multiple underscores
          .replaceAll(RegExp(r'_+'), '_')
          // trim leading/trailing underscores
          .replaceAll(RegExp(r'^_|_$'), '');
    }

    final cleanedShowName = clean(req.showName ?? 'show');

    return ReportFileResult(
      bytes: Uint8List.fromList(bytes),
      fileName: '${cleanedShowName}_entered_exhibitors_contact_report.pdf',
      mimeType: 'application/pdf',
    );
  }
}