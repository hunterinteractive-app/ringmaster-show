// lib/screens/admin/closeout/pdf/builders/exhibitor_report_pdf.dart

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/exhibitor_report_data.dart';

class ExhibitorReportPdfBuilder {
  final Uint8List logoBytes;

  ExhibitorReportPdfBuilder({
    required this.logoBytes,
  });

  static Future<ExhibitorReportPdfBuilder> fromAssets() async {
    final logo = (await rootBundle.load('assets/images/ringmaster_show_logo.png'))
        .buffer
        .asUint8List();

    return ExhibitorReportPdfBuilder(
      logoBytes: logo,
    );
  }

  Future<pw.ThemeData> _buildTheme() async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final italic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'),
    );
    final boldItalic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-BoldItalic.ttf'),
    );

    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
    );
  }

  Future<ReportFileResult> buildFile(
    List<ExhibitorReportData> data,
    ReportRequest request,
  ) async {
    final theme = await _buildTheme();
    final pdf = pw.Document(theme: theme);
    final logoImage = pw.MemoryImage(logoBytes);

    if (data.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 34),
          theme: theme,
          build: (context) => pw.Column(
            children: [
              pw.Expanded(
                child: pw.Center(
                  child: pw.Text('No exhibitor reports found.'),
                ),
              ),
              _footer(context),
            ],
          ),
        ),
      );
    } else {
      for (final exhibitor in data) {
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.letter,
            margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 34),
            theme: theme,
            header: (_) => _header(exhibitor, logoImage),
            footer: (context) => _footer(context),
            build: (_) => [
              pw.SizedBox(height: 10),
              _table(exhibitor.entries),
            ],
          ),
        );
      }
    }

    final bytes = await pdf.save();

    return ReportFileResult(
      fileName: 'exhibitor_report.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  pw.Widget _header(ExhibitorReportData e, pw.MemoryImage logoImage) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text(
                      e.showName,
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  if (e.showDate.isNotEmpty)
                    pw.Center(child: pw.Text(e.showDate)),
                  if (e.showLocation.isNotEmpty)
                    pw.Center(
                      child: pw.Text(
                        e.showLocation,
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    e.exhibitorName,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  if (e.exhibitorAddress.isNotEmpty)
                    pw.Text(e.exhibitorAddress),
                  if (e.exhibitorCityStateZip.isNotEmpty)
                    pw.Text(e.exhibitorCityStateZip),
                  pw.SizedBox(height: 8),
                  pw.Text('Secretary: ${e.secretaryName}'),
                  pw.Text('Email: ${e.secretaryEmail}'),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Container(
              width: 120,
              height: 120,
              alignment: pw.Alignment.topRight,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Image(
                  logoImage,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.6),
      ],
    );
  }

  pw.Widget _table(List<ExhibitorEntryRow> rows) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.4),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 6.4,
      ),
      cellStyle: const pw.TextStyle(fontSize: 6.3),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.55), // Show
        1: pw.FlexColumnWidth(0.85), // Ear #
        2: pw.FlexColumnWidth(1.20), // Breed
        3: pw.FlexColumnWidth(1.00), // Variety
        4: pw.FlexColumnWidth(0.95), // Class
        5: pw.FlexColumnWidth(0.55), // Sex
        6: pw.FlexColumnWidth(0.55), // Place
        7: pw.FlexColumnWidth(0.60), // #Cls
        8: pw.FlexColumnWidth(0.60), // #Exh
        9: pw.FlexColumnWidth(0.95), // Awards
        10: pw.FlexColumnWidth(1.20), // Judge
        11: pw.FlexColumnWidth(0.55), // Leg
        12: pw.FlexColumnWidth(0.55), // Disp
        13: pw.FlexColumnWidth(0.55), // Spec
        14: pw.FlexColumnWidth(0.60), // Total
      },
      headers: const [
        'Show',
        'Ear #',
        'Breed',
        'Variety',
        'Class',
        'Sex',
        'Place',
        '#Cls',
        '#Exh',
        'Awards',
        'Judge',
        'Leg',
        'Disp',
        'Spec',
        'Total',
      ],
      data: rows.map((r) {
        return [
          r.showSection,
          r.tattoo,
          r.breed,
          r.variety,
          r.className,
          r.sex,
          r.placing,
          r.classCount?.toString() ?? '',
          r.exhibitorCount?.toString() ?? '',
          r.awardsText,
          r.judgeName,
          r.earnedLeg ? 'Yes' : '',
          r.displayPoints.toString(),
          r.specialtyPoints.toString(),
          r.totalPoints.toString(),
        ];
      }).toList(),
    );
  }

  pw.Widget _footer(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Divider(thickness: 0.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated by RingMaster Show',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}