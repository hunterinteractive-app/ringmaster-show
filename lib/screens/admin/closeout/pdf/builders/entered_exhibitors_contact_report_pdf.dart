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
          pw.Table.fromTextArray(
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

    return ReportFileResult(
      bytes: Uint8List.fromList(bytes),
      fileName: '${req.showName ?? 'show'}_entered_exhibitors_contact_report.pdf',
      mimeType: 'application/pdf',
    );
  }
}