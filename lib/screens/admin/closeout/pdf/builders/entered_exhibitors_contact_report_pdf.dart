// lib/screens/admin/closeout/pdf/builders/entered_exhibitors_contact_report_pdf.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/pdf/report_pdf_theme.dart';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/entered_exhibitors_contact_report_data.dart';

class EnteredExhibitorsContactReportPdf {
  EnteredExhibitorsContactReportPdf({required this.assets});

  final ReportAssetLoader assets;

  Future<ReportFileResult> buildFile(
    EnteredExhibitorsContactReportData data,
    ReportRequest req,
  ) async {
    final pdf = pw.Document(
      theme: await buildReportPdfTheme(assets),
      title: 'Entered Exhibitor Contact Report',
      author: 'RingMaster Show',
      creator: 'RingMaster Show',
      subject: 'Contact details for exhibitors entered in the show.',
      keywords: 'RingMaster Show, exhibitors, contacts, entries',
    );

    final rows = [...data.rows]
      ..sort(
        (a, b) => a.exhibitorName.toLowerCase().compareTo(
          b.exhibitorName.toLowerCase(),
        ),
      );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(24),
        // Bound each table's layout work. A single table repeatedly measures
        // thousands of remaining rows while MultiPage finds page breaks.
        maxPages: rows.length + 2,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Entered Exhibitors Contact List',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(data.showName),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            '${rows.length} exhibitors • Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (context) => [
          if (rows.isEmpty) pw.Text('No entered exhibitors.'),
          for (var offset = 0; offset < rows.length; offset += 100)
            pw.TableHelper.fromTextArray(
              columnWidths: const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(3.5),
                2: pw.FlexColumnWidth(3.1),
                3: pw.FlexColumnWidth(1.5),
              },
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              headers: const ['Exhibitor', 'Address', 'Email', 'Phone'],
              data: rows
                  .skip(offset)
                  .take(100)
                  .map((r) => [r.exhibitorName, r.address, r.email, r.phone])
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
