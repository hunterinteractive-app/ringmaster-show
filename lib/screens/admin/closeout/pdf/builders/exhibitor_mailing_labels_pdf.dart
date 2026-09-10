import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/pdf/report_pdf_theme.dart';
import '../../data/loaders/exhibitor_mailing_labels_loader.dart';
import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';

/// Avery 5160/8160, US Letter: 3 columns x 10 rows, no vertical gutter.
class Avery5160 {
  static const columns = 3, rows = 10, perPage = 30;
  static const width = 189.0, height = 72.0; // 2.625 x 1 inches
  static const left = 13.5, top = 36.0, horizontalPitch = 198.0;
}

class ExhibitorMailingLabelsPdf {
  const ExhibitorMailingLabelsPdf({required this.assets});
  final ReportAssetLoader assets;

  Future<ReportFileResult> buildFile(
    List<ExhibitorMailingLabel> labels,
    ReportRequest request, {
    required MailingLabelMode mode,
    required MailingLabelSort sort,
  }) async {
    if (labels.isEmpty) {
      throw StateError('No exhibitors are entered in this show.');
    }
    final eligible = labels
        .where(
          (row) =>
              row.name.isNotEmpty &&
              (mode == MailingLabelMode.address
                  ? row.hasMailingAddress && row.address.isNotEmpty
                  : row.number.isNotEmpty),
        )
        .toList();
    if (eligible.isEmpty) {
      throw StateError(
        'No exhibitors have the required ${mode == MailingLabelMode.address ? 'mailing address' : 'exhibitor number'}. Update exhibitor details first.',
      );
    }
    final rows = sortExhibitorMailingLabels(eligible, sort);
    final pdf = pw.Document(
      theme: await buildReportPdfTheme(assets),
      title: 'Exhibitor Labels — Avery 5160/8160',
      author: 'RingMaster Show',
      creator: 'RingMaster Show',
      subject:
          'Exhibitor names with mailing addresses or exhibitor numbers, formatted for Avery 5160/8160 labels.',
      keywords:
          'RingMaster Show, exhibitors, mailing labels, Avery 5160, Avery 8160',
    );
    for (var offset = 0; offset < rows.length; offset += Avery5160.perPage) {
      final page = rows.skip(offset).take(Avery5160.perPage).toList();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              for (var i = 0; i < page.length; i++)
                pw.Positioned(
                  left:
                      Avery5160.left +
                      (i % Avery5160.columns) * Avery5160.horizontalPitch,
                  top:
                      Avery5160.top +
                      (i ~/ Avery5160.columns) * Avery5160.height,
                  child: pw.Container(
                    width: Avery5160.width,
                    height: Avery5160.height,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    alignment: pw.Alignment.centerLeft,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.centerLeft,
                      child: pw.SizedBox(
                        width: Avery5160.width - 18,
                        child: pw.Column(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              page[i].name,
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if (mode == MailingLabelMode.address)
                              for (final line in page[i].address)
                                pw.Text(
                                  line,
                                  style: const pw.TextStyle(fontSize: 10),
                                )
                            else
                              pw.Text(
                                'Exhibitor #${page[i].number}',
                                style: const pw.TextStyle(fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return ReportFileResult(
      fileName:
          'Exhibitor Labels - ${mode.name} - ${sort.name} - Avery 5160.pdf',
      mimeType: 'application/pdf',
      bytes: await pdf.save(),
      metadata: {
        'label_count': rows.length,
        'skipped_count': labels.length - rows.length,
      },
    );
  }
}
