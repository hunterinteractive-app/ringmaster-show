// lib/screens/admin/closeout/pdf/builders/breed_results_detail_report_pdf.dart

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/clubs/breed_results_detail_report_data.dart';

class BreedResultsDetailReportPdf {
  final Uint8List? logoBytes;

  BreedResultsDetailReportPdf({this.logoBytes});

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
    BreedResultsDetailReportData data,
    ReportRequest request,
  ) async {
    final theme = await _buildTheme();
    final pdf = pw.Document(theme: theme);

    final showName = (request.showName ?? '').trim().isEmpty
        ? 'Unknown Show'
        : request.showName!.trim();

    final showDate = (request.showDate ?? '').trim().isEmpty
        ? 'Unknown Date'
        : request.showDate!.trim();

    final sections = data.sections.isNotEmpty
        ? data.sections
        : [
            BreedResultsDetailSection(
              showLetter: data.showLetter,
              judgeName: data.judgeName,
              breedAwards: data.breedAwards,
              varieties: data.varieties,
            ),
          ];

    for (final section in sections) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter.landscape,
          margin: const pw.EdgeInsets.all(24),
          theme: theme,
          footer: (context) => _footer(context),
          build: (context) => [
            _buildHeader(
              breedName: data.breedName,
              scope: data.scope,
              showLetter: section.showLetter,
              judgeName: section.judgeName,
              showName: showName,
              showDate: showDate,
            ),
            pw.SizedBox(height: 12),
            ..._buildSections(
              breedAwards: section.breedAwards,
              varieties: section.varieties,
            ),
          ],
        ),
      );
    }

    final bytes = await pdf.save();

    return ReportFileResult(
      fileName: _buildFileName(
        breedName: data.breedName,
        scope: data.scope,
        showName: showName,
        isAllShows: data.sections.isNotEmpty,
      ),
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  String _buildFileName({
    required String breedName,
    required String scope,
    required String showName,
    required bool isAllShows,
  }) {
    String clean(String input) {
      return input
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
    }

    final suffix =
        isAllShows ? 'all_shows_breed_results_detail' : 'breed_results_detail';

    return '${clean(showName)}_${clean(breedName)}_${clean(scope.toLowerCase())}_$suffix.pdf';
  }

  pw.Widget _buildHeader({
    required String breedName,
    required String scope,
    required String showLetter,
    required String judgeName,
    required String showName,
    required String showDate,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null)
          pw.Container(
            width: 105,
            height: 80,
            margin: const pw.EdgeInsets.only(right: 14),
            child: pw.Image(
              pw.MemoryImage(logoBytes!),
              fit: pw.BoxFit.contain,
            ),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Breed Results Detail Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Show: $showName',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Text(
                'Date: $showDate',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        breedName,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        'Judge: ${judgeName.isEmpty ? 'Judge Not Listed' : judgeName}',
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.Text(
                      '$scope - $showLetter',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<pw.Widget> _buildSections({
    required List<BreedAward> breedAwards,
    required List<VarietySection> varieties,
  }) {
    final widgets = <pw.Widget>[];

    if (breedAwards.isNotEmpty) {
      widgets.add(
        pw.Text(
          'Breed Awards',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
      widgets.add(pw.SizedBox(height: 6));
      widgets.add(
        _buildAwardTable(
          headers: const ['Award', 'Animal', 'Class', 'Exhibitor'],
          rows: breedAwards
              .map((r) => [r.award, r.animal, r.className, r.exhibitorName])
              .toList(),
        ),
      );
      widgets.add(pw.SizedBox(height: 14));
    }

    for (final variety in varieties) {
      widgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          child: pw.Text(
            variety.varietyName,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
      widgets.add(pw.SizedBox(height: 6));

      if (variety.awards.isNotEmpty) {
        widgets.add(
          _buildAwardTable(
            headers: const ['Award', 'Animal', 'Class', 'Exhibitor'],
            rows: variety.awards
                .map((r) => [r.award, r.animal, r.className, r.exhibitorName])
                .toList(),
          ),
        );
        widgets.add(pw.SizedBox(height: 10));
      }

      for (final classGroup in variety.classes) {
        widgets.add(
          pw.Text(
            '${classGroup.className} (${classGroup.entryCount}/${classGroup.placedCount})',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
        widgets.add(pw.SizedBox(height: 4));
        widgets.add(
          _buildPlacementTable(
            rows: classGroup.rows
                .map((r) => [r.place, r.animal, r.exhibitorName])
                .toList(),
          ),
        );
        widgets.add(pw.SizedBox(height: 10));
      }

      widgets.add(pw.SizedBox(height: 6));
    }

    return widgets;
  }

  pw.Widget _buildAwardTable({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.blueGrey700,
      ),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      border: pw.TableBorder.all(
        color: PdfColors.grey400,
        width: 0.5,
      ),
      oddRowDecoration: const pw.BoxDecoration(
        color: PdfColors.grey100,
      ),
      cellPadding: const pw.EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 5,
      ),
    );
  }

  pw.Widget _buildPlacementTable({
    required List<List<String>> rows,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Place', 'Animal', 'Exhibitor'],
      data: rows,
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.grey300,
      ),
      headerStyle: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      border: pw.TableBorder.all(
        color: PdfColors.grey400,
        width: 0.5,
      ),
      cellPadding: const pw.EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 5,
      ),
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