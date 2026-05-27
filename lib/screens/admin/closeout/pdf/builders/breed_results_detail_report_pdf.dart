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
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final italic = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'));
    final boldItalic = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-BoldItalic.ttf'));

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
              noResultsFound: data.noResultsFound,
            ),
          ];

    for (final section in sections) {
      final isNoResults = section.noResultsFound ||
          (section.breedAwards.isEmpty && section.varieties.isEmpty);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter,
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
              arbaSanctionNumber: data.arbaSanction,
              breedSanctionNumber: data.breedSanctionNumber,
              hostClubName: data.hostClubName,
              showLocation: data.showLocation,
              secretaryName: data.secretaryName,
              secretaryEmail: data.secretaryEmail,
              secretaryPhone: data.secretaryPhone,
            ),
            pw.SizedBox(height: 12),
            if (isNoResults)
              _buildNoResultsBox('No breed result details were found for this breed/show section.')
            else
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
        showLetter: data.showLetter,
        showName: showName,
      ),
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  String _buildFileName({
    required String breedName,
    required String scope,
    required String showLetter,
    required String showName,
  }) {
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

    return '${clean(showName)}_${clean(breedName)}_Breed_Results_Detail_Report_${clean(scope.toUpperCase())}_${clean(showLetter.toUpperCase())}.pdf';
  }

  pw.Widget _buildHeader({
    required String breedName,
    required String scope,
    required String showLetter,
    required String judgeName,
    required String showName,
    required String showDate,
    required String arbaSanctionNumber,
    required String breedSanctionNumber,
    required String hostClubName,
    required String showLocation,
    required String secretaryName,
    required String secretaryEmail,
    required String secretaryPhone,
  }) {
  pw.Widget infoCell(String label, String value) {
    if (label.trim().isEmpty && value.trim().isEmpty) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 78,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 8.5),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget infoRow2(
    String leftLabel,
    String leftValue,
    String rightLabel,
    String rightValue,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: infoCell(leftLabel, leftValue)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: infoCell(rightLabel, rightValue)),
      ],
    );
  }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null)
          pw.Container(
            width: 85,
            height: 65,
            margin: const pw.EdgeInsets.only(right: 12),
            child: pw.Image(pw.MemoryImage(logoBytes!), fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Breed Results Detail Report',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(9),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    infoRow2('Show Name', showName, 'Show Date', showDate),
                    infoRow2('Host Club', hostClubName, 'Location', showLocation),
                    infoRow2('Breed', breedName, 'Show', '$scope - $showLetter'),
                    infoRow2('Judge', judgeName.isEmpty ? 'Judge Not Listed' : judgeName, '', ''),
                    infoRow2(
                      'ARBA Sanction',
                      arbaSanctionNumber,
                      'Breed Sanction',
                      breedSanctionNumber,
                    ),
                    infoRow2(
                      'Secretary',
                      secretaryName,
                      '',
                      '',
                    ),
                    infoRow2(
                      'Contact',
                      [
                        if (secretaryEmail.trim().isNotEmpty) secretaryEmail.trim(),
                        if (secretaryPhone.trim().isNotEmpty) secretaryPhone.trim(),
                      ].join(' / '),
                      '',
                      '',
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

  pw.Widget _buildNoResultsBox(String message) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
        color: PdfColors.grey100,
      ),
      child: pw.Text(message, style: const pw.TextStyle(fontSize: 10)),
    );
  }

  List<pw.Widget> _buildSections({
    required List<BreedAward> breedAwards,
    required List<VarietySection> varieties,
  }) {
    final widgets = <pw.Widget>[];

    if (breedAwards.isNotEmpty) {
      widgets.add(_sectionTitle('Breed Awards'));
      widgets.add(_buildAwardTable(breedAwards));
      widgets.add(pw.SizedBox(height: 12));
    }

    for (final variety in varieties) {
      widgets.add(_varietyHeader(variety.varietyName));

      if (variety.awards.isNotEmpty) {
        widgets.add(_buildAwardTable(variety.awards));
        widgets.add(pw.SizedBox(height: 8));
      }

      for (final sexSection in variety.sexSections) {
        widgets.add(_sexHeader(sexSection.sexLabel));

        for (final classGroup in sexSection.classes) {
          widgets.add(
            pw.Text(
              '${classGroup.className} — ${classGroup.animalsJudged} animals / ${classGroup.exhibitorsJudged} exhibitors judged',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          );
          widgets.add(pw.SizedBox(height: 4));

          if (classGroup.rows.isEmpty) {
            widgets.add(
              pw.Text(
                'No top 5 placements recorded.',
                style: const pw.TextStyle(fontSize: 8),
              ),
            );
          } else {
            widgets.add(_buildPlacementTable(classGroup.rows));
          }

          widgets.add(pw.SizedBox(height: 8));
        }

        widgets.add(pw.SizedBox(height: 6));
      }

      widgets.add(pw.SizedBox(height: 8));
    }

    return widgets;
  }

  pw.Widget _sectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _varietyHeader(String title) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _sexHeader(String title) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 5, top: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      child: pw.Text(
        title.toUpperCase(),
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  String _awardLabel(String code) {
    switch (code.toUpperCase().trim()) {
      case 'BJV':
        return 'Best Junior Variety';
      case 'BIV':
        return 'Best Intermediate Variety';
      case 'BSV':
        return 'Best Senior Variety';
      case 'BJB':
        return 'Best Junior of Breed';
      case 'BIB':
        return 'Best Intermediate of Breed';
      case 'BSB':
        return 'Best Senior of Breed';
      case 'BOV':
        return 'Best of Variety';
      case 'BOSV':
        return 'Best Opposite Sex of Variety';
      case 'BOB':
        return 'Best of Breed';
      case 'BOSB':
        return 'Best Opposite Sex of Breed';
      case 'BIS':
        return 'Best in Show';
      case 'RIS':
        return 'Reserve in Show';
      case 'HM':
        return 'Honorable Mention';
      default:
        return code;
    }
  }

  pw.Widget _buildAwardTable(List<BreedAward> rows) {
    return pw.TableHelper.fromTextArray(
      headers: const [
        'Award',
        'Animal',
        'Sex',
        'Variety',
        'Class',
        'Exhibitor',
        'Judged',
        'Beaten',
      ],
      data: rows
          .map(
            (r) => [
              _awardLabel(r.award),
              r.animal,
              r.sex,
              r.variety,
              r.className,
              r.exhibitorName,
              r.animalsJudged > 0
                  ? '${r.animalsJudged}/${r.exhibitorsJudged}'
                  : '',
              r.animalsJudged > 0
                  ? '${r.animalsJudged - 1}'
                  : '',
            ],
          )
          .toList(),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 7.5,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      columnWidths: {
        0: const pw.FixedColumnWidth(74),
        1: const pw.FlexColumnWidth(1.15),
        2: const pw.FixedColumnWidth(28),
        3: const pw.FlexColumnWidth(1.0),
        4: const pw.FlexColumnWidth(1.0),
        5: const pw.FlexColumnWidth(1.25),
        6: const pw.FixedColumnWidth(38),
        7: const pw.FixedColumnWidth(36),
      },
    );
  }

  pw.Widget _buildPlacementTable(List<ClassEntry> rows) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Place', 'Animal', 'Sex', 'Variety', 'Exhibitor'],
      data: rows
          .map((r) => [
                r.place,
                r.animal,
                r.sex,
                r.variety,
                r.exhibitorName,
              ])
          .toList(),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      columnWidths: {
        0: const pw.FixedColumnWidth(32),
        1: const pw.FlexColumnWidth(1.3),
        2: const pw.FixedColumnWidth(30),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.6),
      },
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
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}