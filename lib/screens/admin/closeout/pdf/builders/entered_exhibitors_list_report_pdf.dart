import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/pdf/report_pdf_theme.dart';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/entered_exhibitors_list_report_data.dart';

class EnteredExhibitorsListReportPdf {
  EnteredExhibitorsListReportPdf({required this.assets});

  final ReportAssetLoader assets;

  Future<ReportFileResult> buildFile(
    EnteredExhibitorsListReportData data,
    ReportRequest req,
  ) async {
    final pdf = pw.Document(theme: await buildReportPdfTheme(assets));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => [
          pw.Text(
            'Exhibitor Number Lookup Report',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(data.showName),
          pw.SizedBox(height: 6),
          pw.Text(
            '${data.rows.length} exhibitor${data.rows.length == 1 ? '' : 's'} entered',
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            headers: const ['Exhibitor #', 'Last Name', 'First Name'],
            data: data.rows
                .map(
                  (row) => [
                    row.exhibitorNumber,
                    row.lastName.isEmpty ? row.displayName : row.lastName,
                    row.lastName.isEmpty ? '' : row.firstName,
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );

    final cleanShowName = (req.showName ?? 'show')
        .replaceAll(RegExp(r'[^\\w\\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\\s+'), '_');
    return ReportFileResult(
      bytes: Uint8List.fromList(await pdf.save()),
      fileName: '${cleanShowName}_exhibitor_number_lookup_report.pdf',
      mimeType: 'application/pdf',
    );
  }
}
