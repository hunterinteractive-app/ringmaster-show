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
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
        theme: theme,
        footer: _footer,
        build: (_) => [
          _header(data),
          if (data.overallWinners.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _sectionTitle('Overall Show Winners'),
            _overallWinnersTable(data.overallWinners),
          ],
          pw.SizedBox(height: 12),
          if (data.breeds.isEmpty)
            pw.Text('No eligible animals were shown.')
          else
            for (final breed in data.breeds) ...[
              _breedSection(breed),
              pw.SizedBox(height: 12),
            ],
        ],
      ),
    );

    return ReportFileResult(
      fileName:
          '${_clean(data.showName)}_Details_By_Breed_${_clean(data.scope)}_${_clean(data.showLetter)}.pdf',
      mimeType: 'application/pdf',
      bytes: await pdf.save(),
    );
  }

  pw.Widget _header(DetailsByBreedReportData data) {
    pw.Widget item(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 7.5),
              children: [
                pw.TextSpan(
                  text: '$label: ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: value.isEmpty ? '—' : value),
              ],
            ),
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoBytes != null)
              pw.Container(
                width: 70,
                height: 46,
                alignment: pw.Alignment.center,
                child: pw.Image(pw.MemoryImage(logoBytes!), fit: pw.BoxFit.contain),
              ),
            if (logoBytes != null) pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Text(
                'Show Report — Details by Breed',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text('Report Date: ${data.reportDate}',
                style: const pw.TextStyle(fontSize: 7.5)),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(7),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: .6),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    item('Show Date', data.showDate),
                    item('Event Name', data.showName),
                    item('Event Secretary', data.secretaryName),
                    item('Sponsoring Superintendent', data.superintendentName),
                    item('Show', data.showLetter),
                    item('Specialty', data.specialtyStatus),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    item('Event Location', data.showLocation),
                    item('Sponsoring Club', data.hostClubName),
                    item('Secretary Email', data.secretaryEmail),
                    item('Classification', data.scope),
                    item('Type', data.showType),
                    item('ARBA Sanction', data.arbaSanctionNumber),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (data.stateClubName.isNotEmpty ||
            data.stateClubSanctionNumber.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'State Club: ${data.stateClubName.isEmpty ? '—' : data.stateClubName}'
            '${data.stateClubSanctionNumber.isEmpty ? '' : '  •  Sanction No.: ${data.stateClubSanctionNumber}'}',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ],
    );
  }

  pw.Widget _overallWinnersTable(List<DetailsByBreedOverallWinner> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: .45),
      columnWidths: const {
        0: pw.FlexColumnWidth(.8),
        1: pw.FlexColumnWidth(.9),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.3),
        4: pw.FlexColumnWidth(1.1),
        5: pw.FlexColumnWidth(1.5),
        6: pw.FlexColumnWidth(.75),
        7: pw.FlexColumnWidth(1.1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('Category', bold: true),
            _cell('Ear #', bold: true),
            _cell('Breed', bold: true),
            _cell('Variety', bold: true),
            _cell('Class', bold: true),
            _cell('Exhibitor', bold: true),
            _cell('# Ent / # Exh', bold: true, center: true),
            _cell("Add't Awards", bold: true),
          ],
        ),
        for (final row in rows)
          pw.TableRow(
            children: [
              _cell(row.award, bold: true),
              _cell(row.earNumber),
              _cell(row.breedName),
              _cell(row.varietyName),
              _cell(_classSex(row.className, row.sex)),
              _cell(row.exhibitorName),
              _cell('${row.showAnimals} / ${row.showExhibitors}', center: true),
              _cell(row.additionalAwards.isEmpty ? '—' : row.additionalAwards.join(', ')),
            ],
          ),
      ],
    );
  }

  pw.Widget _breedSection(DetailsByBreedBreedSection breed) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          child: pw.Text(
            '${breed.breedName}  (${breed.animalsShown}/${breed.exhibitorCount})',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey500, width: .55),
          ),
          child: pw.Row(
            children: [
              pw.Text(
                'Judge:',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Expanded(
                child: pw.Text(
                  breed.judgeName.isEmpty
                      ? 'Not assigned'
                      : breed.judgeName,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
        ),
        if (breed.bob != null || breed.bosb != null) ...[
          pw.SizedBox(height: 4),
          _breedAwardsTable([
            if (breed.bob != null) breed.bob!,
            if (breed.bosb != null) breed.bosb!,
          ]),
        ],
        if (breed.specialAwards.isNotEmpty) ...[
          pw.SizedBox(height: 5),
          _specialAwardsBlock(breed.specialAwards),
        ],
        for (final variety in breed.varieties) ...[
          pw.SizedBox(height: 7),
          pw.Text(
            variety.varietyName,
            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.Container(height: .5, color: PdfColors.grey400),
          if (variety.bov != null || variety.bosv != null) ...[
            pw.SizedBox(height: 3),
            _breedAwardsTable([if (variety.bov != null) variety.bov!, if (variety.bosv != null) variety.bosv!]),
          ],
          for (final clazz in variety.classes) ...[
            pw.SizedBox(height: 5),
            _classPlacements(clazz),
          ],
        ],
      ],
    );
  }


  pw.Widget _specialAwardsBlock(List<DetailsByBreedAwardRow> rows) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: .55),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            color: PdfColors.grey200,
            child: pw.Text(
              'Special Awards',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Table(
            border: const pw.TableBorder(
              horizontalInside:
                  pw.BorderSide(color: PdfColors.grey300, width: .35),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.15),
              1: pw.FlexColumnWidth(.85),
              2: pw.FlexColumnWidth(1.35),
              3: pw.FlexColumnWidth(1.15),
              4: pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _cell('Award', bold: true),
                  _cell('Ear #', bold: true),
                  _cell('Variety', bold: true),
                  _cell('Class', bold: true),
                  _cell('Exhibitor', bold: true),
                ],
              ),
              for (final row in rows)
                pw.TableRow(
                  children: [
                    _cell(row.award, bold: true),
                    _cell(row.earNumber),
                    _cell(row.varietyName),
                    _cell(_classSex(row.className, row.sex)),
                    _cell(row.exhibitorName),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _breedAwardsTable(List<DetailsByBreedAwardRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
      columnWidths: const {
        0: pw.FlexColumnWidth(.7),
        1: pw.FlexColumnWidth(.9),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(1.7),
        5: pw.FlexColumnWidth(.8),
        6: pw.FlexColumnWidth(1.1),
      },
      children: [
        for (final row in rows)
          pw.TableRow(
            children: [
              _cell(row.award, bold: true),
              _cell(row.earNumber),
              _cell(row.varietyName),
              _cell(_classSex(row.className, row.sex)),
              _cell(row.exhibitorName),
              _cell('${row.animalsShown}/${row.exhibitorCount}', center: true),
              _cell(row.additionalAwards.isEmpty ? '—' : row.additionalAwards.join(', ')),
            ],
          ),
      ],
    );
  }

  pw.Widget _classPlacements(DetailsByBreedClassSection clazz) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '${_classSex(clazz.className, clazz.sex)} (${clazz.animalsShown}/${clazz.exhibitorCount})',
          style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        if (clazz.placements.isEmpty)
          pw.Text('No recorded placements.', style: const pw.TextStyle(fontSize: 7))
        else
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(.45),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1.5),
              3: pw.FlexColumnWidth(2),
              4: pw.FlexColumnWidth(1.1),
            },
            children: [
              for (final row in clazz.placements)
                pw.TableRow(
                  decoration: row.awards.isEmpty
                      ? null
                      : const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _plainCell(row.placement.toString()),
                    _plainCell(row.earNumber),
                    _plainCell(row.animalName),
                    _plainCell(row.exhibitorName),
                    row.awards.isEmpty
                        ? _plainCell('')
                        : pw.Container(
                            margin: const pw.EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 1,
                            ),
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1.5,
                            ),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(
                                color: PdfColors.grey600,
                                width: .45,
                              ),
                            ),
                            child: pw.Text(
                              row.awards.join(', '),
                              style: pw.TextStyle(
                                fontSize: 6.8,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  pw.Widget _sectionTitle(String text) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        color: PdfColors.grey200,
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _cell(String text, {bool bold = false, bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text.isEmpty ? '—' : text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 6.8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _plainCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 6.8)),
      );

  String _classSex(String className, String sex) {
    final parts = <String>[
      if (className.trim().isNotEmpty) className.trim(),
      if (sex.trim().isNotEmpty) sex.trim(),
    ];
    return parts.join(' ');
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
