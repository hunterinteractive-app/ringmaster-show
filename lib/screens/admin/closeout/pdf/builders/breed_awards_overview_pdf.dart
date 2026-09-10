import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/pdf/report_pdf_theme.dart';

import '../../data/loaders/breed_awards_overview_loader.dart';
import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';

class BreedAwardsOverviewPdf {
  const BreedAwardsOverviewPdf({required this.assets});
  final ReportAssetLoader assets;

  Future<ReportFileResult> buildFile(
    BreedAwardsOverviewData data,
    ReportRequest request,
  ) async {
    final pdf = pw.Document(
      theme: await buildReportPdfTheme(assets),
      title: 'Breed Awards Overview',
      author: 'RingMaster Show',
    );
    final sections = <String, List<BreedAwardOverviewRow>>{};
    for (final row in data.rows) {
      sections.putIfAbsent(row.sectionId, () => []).add(row);
    }
    // Each section starts on its own page; table headers repeat on overflow.
    for (final rows
        in sections.isEmpty ? [<BreedAwardOverviewRow>[]] : sections.values) {
      pdf.addPage(
        pw.MultiPage(
          maxPages: 1000,
          pageFormat: PdfPageFormat.letter.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Breed Awards Overview',
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(data.showName, style: const pw.TextStyle(fontSize: 11)),
              if (rows.isNotEmpty)
                pw.Text(
                  rows.first.sectionLabel,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              pw.SizedBox(height: 10),
            ],
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          build: (_) {
            if (rows.isEmpty) {
              return [
                pw.Text(
                  'No recorded breed, variety, or group award winners in the selected show sections.',
                ),
              ];
            }
            final breeds = <String, List<BreedAwardOverviewRow>>{};
            for (final row in rows) {
              breeds
                  .putIfAbsent('${row.species}|${row.breed}', () => [])
                  .add(row);
            }
            return [
              for (final breedRows in breeds.values) ...[
                pw.NewPage(freeSpace: 100),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
                  child: pw.Text(
                    '${breedRows.first.breed} (${breedRows.first.species})',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.TableHelper.fromTextArray(
                  headers: const [
                    'Award',
                    'Tattoo',
                    'Coop Number',
                    'Breed',
                    'Variety',
                    'Class',
                    'Sex',
                    'Exhibitor Name',
                  ],
                  data: breedRows
                      .map(
                        (r) => [
                          r.award,
                          r.tattoo,
                          r.coop,
                          r.breed,
                          r.variety,
                          r.className,
                          r.sex,
                          r.exhibitor,
                        ],
                      )
                      .toList(),
                  headerStyle: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellPadding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(.65),
                    1: pw.FlexColumnWidth(.8),
                    2: pw.FlexColumnWidth(.75),
                    3: pw.FlexColumnWidth(1.1),
                    4: pw.FlexColumnWidth(1.2),
                    5: pw.FlexColumnWidth(.9),
                    6: pw.FlexColumnWidth(.65),
                    7: pw.FlexColumnWidth(1.7),
                  },
                ),
                pw.SizedBox(height: 8),
              ],
            ];
          },
        ),
      );
    }
    return ReportFileResult(
      fileName:
          '${data.showName.replaceAll(RegExp(r'[^\w\s-]'), '').trim()} - Breed Awards Overview.pdf',
      mimeType: 'application/pdf',
      bytes: await pdf.save(),
    );
  }
}
