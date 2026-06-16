import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/clubs/details_by_breed_report_data.dart';

class DetailsByBreedReportPdf {
  final Uint8List? logoBytes;

  DetailsByBreedReportPdf({this.logoBytes});

  Future<pw.ThemeData> _theme() async {
    final regular =
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  Future<ReportFileResult> buildFile(
    DetailsByBreedReportData data,
    ReportRequest request,
  ) async {
    final theme = await _theme();
    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(24),
        theme: theme,
        footer: _footer,
        build: (_) => [
          _header(
            title: 'Breed Totals',
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
          pw.SizedBox(height: 14),
          if (data.rows.isEmpty)
            pw.Text('No eligible animals were shown.')
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.3),
                1: pw.FlexColumnWidth(.8),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('Breed', bold: true),
                    _cell('Shown', bold: true, center: true),
                    _cell('BOB Exhibitor', bold: true),
                    _cell('BOS Exhibitor', bold: true),
                  ],
                ),
                for (final row in data.rows)
                  pw.TableRow(
                    children: [
                      _cell(row.breedName),
                      _cell(row.animalsShown.toString(), center: true),
                      _cell(row.bobExhibitor.isEmpty ? '—' : row.bobExhibitor),
                      _cell(row.bosExhibitor.isEmpty ? '—' : row.bosExhibitor),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );

    return ReportFileResult(
      fileName:
          '${_clean(data.showName)}_Breed_Totals_${_clean(data.scope)}_${_clean(data.showLetter)}.pdf',
      mimeType: 'application/pdf',
      bytes: await pdf.save(),
    );
  }

  pw.Widget _cell(String text, {bool bold = false, bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8,
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
          pw.Text('Generated by RingMaster Show',
              style: const pw.TextStyle(fontSize: 7)),
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
