import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/clubs/exhibitor_by_breed_report_data.dart';

class ExhibitorByBreedReportPdf {
  final Uint8List? logoBytes;

  ExhibitorByBreedReportPdf({this.logoBytes});

  Future<pw.ThemeData> _theme() async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  Future<ReportFileResult> buildFile(
    ExhibitorByBreedReportData data,
    ReportRequest request,
  ) async {
    final theme = await _theme();
    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(22),
        theme: theme,
        footer: _footer,
        build: (_) => [
          _header(
            title: 'Breed Special Points',
            showName: data.showName,
            showDate: data.showDate,
            showLocation: data.showLocation,
            hostClubName: data.hostClubName,
            scope: data.scope,
            showLetter: data.showLetter,
            secretaryName: data.secretaryName,
            secretaryAddress: data.secretaryAddress,
            secretaryEmail: data.secretaryEmail,
            secretaryPhone: data.secretaryPhone,
          ),
          pw.SizedBox(height: 12),
          if (data.sections.isEmpty)
            pw.Text('No eligible exhibitors were found.')
          else
            for (final section in data.sections) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 5,
                ),
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                child: pw.Text(
                  section.breedName,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.6),
                  1: pw.FlexColumnWidth(.65),
                  2: pw.FlexColumnWidth(.7),
                  3: pw.FlexColumnWidth(.7),
                  4: pw.FlexColumnWidth(.7),
                  5: pw.FlexColumnWidth(.7),
                  6: pw.FlexColumnWidth(.7),
                  7: pw.FlexColumnWidth(.7),
                  8: pw.FlexColumnWidth(.75),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey100,
                    ),
                    children: [
                      _cell('Exhibitor / Address', bold: true),
                      _cell('Animals', bold: true, center: true),
                      _cell('Class', bold: true, center: true),
                      _cell('Variety', bold: true, center: true),
                      _cell('Group', bold: true, center: true),
                      _cell('BOB/BOS', bold: true, center: true),
                      _cell('BIS/RIS', bold: true, center: true),
                      _cell('Fur/Wool', bold: true, center: true),
                      _cell('Total', bold: true, center: true),
                    ],
                  ),
                  for (final row in section.rows)
                    pw.TableRow(
                      children: [
                        _cell(
                          row.exhibitorAddress.isEmpty
                              ? row.exhibitorName
                              : '${row.exhibitorName}\n${row.exhibitorAddress}',
                        ),
                        _cell(row.animalsShown.toString(), center: true),
                        _cell(_points(row.classPoints), center: true),
                        _cell(_points(row.varietyPoints), center: true),
                        _cell(_points(row.groupPoints), center: true),
                        _cell(_points(row.bobBosPoints), center: true),
                        _cell(_points(row.bisRisPoints), center: true),
                        _cell(_points(row.furWoolPoints), center: true),
                        _cell(_points(row.totalPoints), center: true),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 10),
            ],
        ],
      ),
    );

    final speciesPart = _speciesFilePart(request.species);

    return ReportFileResult(
      fileName:
          '${_clean(data.showName)}_Breed_Special_Points${speciesPart}_${_clean(data.scope)}_${_clean(data.showLetter)}.pdf',
      mimeType: 'application/pdf',
      bytes: await pdf.save(),
    );
  }

  String _speciesFilePart(String? species) {
    final normalized = (species ?? '').trim().toLowerCase();
    if (normalized == 'rabbit') return '_Rabbit';
    if (normalized == 'cavy') return '_Cavy';
    return '';
  }

  String _points(double value) {
    if (value == 0) return '—';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  pw.Widget _cell(String text, {bool bold = false, bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _header({
    required String title,
    required String showName,
    required String showDate,
    required String showLocation,
    required String hostClubName,
    required String scope,
    required String showLetter,
    required String secretaryName,
    required String secretaryAddress,
    required String secretaryEmail,
    required String secretaryPhone,
  }) {
    pw.Widget item(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 8),
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: value),
          ],
        ),
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    item('Show', showName),
                    item('Date', showDate),
                    item('Location', showLocation),
                    item('Sponsoring Club', hostClubName),
                    item('Classification', scope),
                    item('Show', showLetter),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    item('Secretary', secretaryName),
                    item('Address', secretaryAddress),
                    item('Email', secretaryEmail),
                    item('Phone', secretaryPhone),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _footer(pw.Context context) => pw.Row(
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

  String _clean(String value) => value
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}
