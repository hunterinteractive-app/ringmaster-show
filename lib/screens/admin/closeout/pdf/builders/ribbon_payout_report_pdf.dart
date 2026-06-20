// lib/screens/admin/closeout/pdf/builders/ribbon_report_pdf.dart

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

    int exhibitorNumberSortValue(String value) {
      final trimmed = value.trim();
      final numeric = int.tryParse(trimmed);
      if (numeric != null) return numeric;
      return 999999;
    }


    String displayExhibitorNumber(String value) {
      final trimmed = value.trim();
      final looksLikeUuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(trimmed);
      if (looksLikeUuid) return '';
      return trimmed;
    }

    String displaySponsoringClub(RibbonPayoutSectionData section) {
      final sectionClub = section.sponsoringClub.trim();
      if (sectionClub.isNotEmpty && sectionClub.toUpperCase() != 'ARBA') {
        return sectionClub;
      }

      final dataClub = data.sponsoringClub.trim();
      if (dataClub.isNotEmpty && dataClub.toUpperCase() != 'ARBA') {
        return dataClub;
      }

      final showName = data.showName.trim().isNotEmpty
          ? data.showName.trim()
          : data.eventName.trim();
      if (showName.isEmpty) return '';

      return showName
          .replaceAll(RegExp(r'\bshow\b', caseSensitive: false), '')
          .replaceAll(RegExp(r'\bspring\b|\bsummer\b|\bfall\b|\bwinter\b', caseSensitive: false), '')
          .replaceAll(RegExp(r'\b20\d{2}\b'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    final sections = data.sections.isNotEmpty
        ? data.sections
        : [
            RibbonPayoutSectionData(
              sponsoringClub: data.sponsoringClub,
              classification: data.classification,
              showLetter: data.showLetter,
              type: data.type,
              specialty: data.specialty,
              arbaSanction: data.arbaSanction,
              rows: data.rows,
            ),
          ];

    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      if (section.rows.isEmpty) continue;

      final rows = [...section.rows]
        ..sort((a, b) {
          final numCmp = exhibitorNumberSortValue(a.exhibitorNumber).compareTo(
            exhibitorNumberSortValue(b.exhibitorNumber),
          );
          if (numCmp != 0) return numCmp;

          final rawNumCmp = a.exhibitorNumber.compareTo(b.exhibitorNumber);
          if (rawNumCmp != 0) return rawNumCmp;

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
                _infoRow(
                  'Event Name: ${data.eventName}',
                  'Sponsoring club: ${displaySponsoringClub(section)}',
                ),
                _infoRow(
                  'Event Secretary: ${data.eventSecretary}',
                  'Event Secretary Email: ${data.eventSecretaryEmail}',
                ),
                _infoRow(
                  'Sponsoring Superintendent: ${data.sponsoringSuperintendent}',
                  'Classification: ${section.classification}',
                ),
                _infoRow('Show: ${section.showLetter}', 'Type: ${section.type}'),
                _infoRow(
                  'Specialty: ${section.specialty}',
                  'ARBA sanction: ${section.arbaSanction}',
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.TableHelper.fromTextArray(
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
                '1st',
                '2nd',
                '3rd',
                '4th',
                '5th',
              ],
              data: rows
                  .map(
                    (r) => [
                      displayExhibitorNumber(r.exhibitorNumber),
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
    }

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
      fileName: '${cleanedShowName}_combined_ribbon_payout_report.pdf',
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