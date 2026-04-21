import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/ribbon_payout_report_data.dart';

class RibbonPayoutReportPdf {
  Future<ReportFileResult> buildFile(
    RibbonPayoutReportData data,
    ReportRequest req,
  ) async {
    final pdf = pw.Document();

    final rows = [...data.rows]
      ..sort((a, b) {
        final numCmp = a.exhibitorNumber.compareTo(b.exhibitorNumber);
        if (numCmp != 0) return numCmp;
        return a.exhibitorName.toLowerCase().compareTo(
              b.exhibitorName.toLowerCase(),
            );
      });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        build: (context) => [
          pw.Text(
            'Ribbon Report',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),

          pw.Table(
            border: pw.TableBorder.all(
              color: PdfColors.grey500,
              width: 0.75,
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(1.2),
            },
            children: [
              _infoRow('Event Name: ${data.eventName}', 'Sponsoring club: ${data.sponsoringClub}'),
              _infoRow('Event Secretary: ${data.eventSecretary}', 'Event Secretary Email: ${data.eventSecretaryEmail}'),
              _infoRow('Sponsoring Superintendent: ${data.sponsoringSuperintendent}', 'Classification: ${data.classification}'),
              _infoRow('Show: ${data.showLetter}', 'Type: ${data.type}'),
              _infoRow('Specialty: ${data.specialty}', 'ARBA sanction: ${data.arbaSanction}'),
            ],
          ),

          pw.SizedBox(height: 14),

          pw.Table.fromTextArray(
            border: pw.TableBorder.all(
              color: PdfColors.grey500,
              width: 0.75,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.grey300,
            ),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(3.2),
              2: pw.FlexColumnWidth(0.8),
              3: pw.FlexColumnWidth(0.8),
              4: pw.FlexColumnWidth(0.8),
              5: pw.FlexColumnWidth(0.8),
              6: pw.FlexColumnWidth(0.8),
            },
            headers: const [
              'Exh #',
              'Exhibitor',
              'Placing 1',
              'Placing 2',
              'Placing 3',
              'Placing 4',
              'Placing 5',
            ],
            data: rows
                .map(
                  (r) => [
                    r.exhibitorNumber,
                    r.exhibitorName,
                    r.first.toString(),
                    r.second.toString(),
                    r.third.toString(),
                    r.fourth.toString(),
                    r.fifth.toString(),
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
      fileName: '${req.showName ?? 'show'}_ribbon_payout_report.pdf',
      mimeType: 'application/pdf',
    );
  }

  pw.TableRow _infoRow(String left, String right) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(left, style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(right, style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    );
  }
}