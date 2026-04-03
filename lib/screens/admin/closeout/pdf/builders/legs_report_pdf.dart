// lib/screens/admin/closeout/pdf/builders/legs_report_pdf.dart

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/legs/legs_certificate_data.dart';

class LegsReportPdfBuilder {
  final Uint8List arbaLogoBytes;
  final Uint8List ringMasterLogoBytes;

  LegsReportPdfBuilder({
    required this.arbaLogoBytes,
    required this.ringMasterLogoBytes,
  });

  static Future<LegsReportPdfBuilder> fromAssets() async {
    final arbaLogoBytes = (await rootBundle.load('assets/images/arba_logo.png'))
        .buffer
        .asUint8List();

    final ringMasterLogoBytes =
        (await rootBundle.load('assets/images/ringmaster_show_logo.png'))
            .buffer
            .asUint8List();

    return LegsReportPdfBuilder(
      arbaLogoBytes: arbaLogoBytes,
      ringMasterLogoBytes: ringMasterLogoBytes,
    );
  }

  static const List<String> legRules = [
    'Wins First in a class providing there are 5 or more animals exhibited by 3 or more exhibitors.',
    'Wins Best of Breed providing there are 5 or more animals exhibited in the breed by 3 or more exhibitors.',
    'Wins Best Opposite Sex of Breed providing there are 5 or more of the same sex as the winner exhibited in the breed by 3 or more exhibitors.',
    'Wins Best of Group providing there are 5 or more animals exhibited in the group by 3 or more exhibitors.',
    'Wins Best Opposite Sex of Group providing there are 5 or more of the same sex as the winner exhibited in the group by 3 or more exhibitors.',
    'Wins Best of Variety providing there are 5 or more animals exhibited in the variety by 3 or more exhibitors.',
    'Wins Best Opposite Sex Variety providing there are 5 or more of the same sex as the winner exhibited in the variety by 3 or more exhibitors.',
    'Wins Best in Show providing there are 5 or more animals exhibited in the show by 3 or more exhibitors.',
    'Wins Best 6 Class, Best 4 Class, providing there are 5 or more animals competing exhibited by 3 or more exhibitors.',
    'Wins Reserve in Show providing there are 5 or more animals exhibited by 3 or more exhibitors.',
    'Leg of Grand Champion may only be awarded at an official ARBA sanctioned show.',
    'Leg of Grand Champion is to be furnished to the exhibitor by the show secretary within 30 days of conclusion of show.',
    'Rabbits must be judged by an ARBA licensed Rabbit Judge and cavies must be judged by an ARBA licensed Cavy Judge.',
    'Only 1 leg of Grand Champion may be awarded to the same animal for the same show.',
  ];

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
    List<LegsCertificateData> data,
    ReportRequest request,
  ) async {
    final theme = await _buildTheme();
    final pdf = pw.Document(theme: theme);

    if (data.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(24),
          theme: theme,
          build: (_) => pw.Center(
            child: pw.Text('No leg certificates found.'),
          ),
        ),
      );
    } else {
      final grouped = _groupByExhibitor(data);

      for (final exhibitorGroup in grouped) {
        final chunks = <List<LegsCertificateData>>[];

        for (var i = 0; i < exhibitorGroup.length; i += 2) {
          chunks.add(exhibitorGroup.skip(i).take(2).toList());
        }

        for (final chunk in chunks) {
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.letter,
              margin: const pw.EdgeInsets.fromLTRB(22, 18, 22, 18),
              theme: theme,
              build: (_) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _certificate(chunk[0]),
                    pw.SizedBox(height: 8),
                    _cutLine(),
                    pw.SizedBox(height: 8),
                    if (chunk.length > 1)
                      _certificate(chunk[1])
                    else
                      _blankCertificateSpace(),
                    pw.SizedBox(height: 10),
                    _rulesBlock(),
                  ],
                );
              },
            ),
          );
        }
      }
    }

    final bytes = await pdf.save();

    return ReportFileResult(
      fileName: 'legs_report.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  List<List<LegsCertificateData>> _groupByExhibitor(
    List<LegsCertificateData> data,
  ) {
    final sorted = [...data]
      ..sort((a, b) {
        final exhibitorCompare = a.exhibitorName.compareTo(b.exhibitorName);
        if (exhibitorCompare != 0) return exhibitorCompare;

        final numberCompare = a.exhibitorNumber.compareTo(b.exhibitorNumber);
        if (numberCompare != 0) return numberCompare;

        return a.earNumber.compareTo(b.earNumber);
      });

    final groups = <List<LegsCertificateData>>[];
    List<LegsCertificateData> current = [];
    String currentKey = '';

    for (final item in sorted) {
      final key = _exhibitorGroupKey(item);

      if (current.isEmpty) {
        current = [item];
        currentKey = key;
        continue;
      }

      if (key == currentKey) {
        current.add(item);
      } else {
        groups.add(current);
        current = [item];
        currentKey = key;
      }
    }

    if (current.isNotEmpty) {
      groups.add(current);
    }

    return groups;
  }

  String _exhibitorGroupKey(LegsCertificateData d) {
    final exhibitorId = d.exhibitorId.trim();
    if (exhibitorId.isNotEmpty) return 'id:$exhibitorId';

    final exhibitorNumber = d.exhibitorNumber.trim().toLowerCase();
    if (exhibitorNumber.isNotEmpty) return 'num:$exhibitorNumber';

    return 'name:${d.exhibitorName.trim().toLowerCase()}';
  }

  pw.Widget _certificate(LegsCertificateData d) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue800, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _certificateHeader(),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 182,
                child: _leftInfo(d),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _rightInfo(d),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _certificateHeader() {
    return pw.Column(
      children: [
        pw.Text(
          'AMERICAN RABBIT BREEDERS ASSOCIATION, INC.',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 10.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
        ),
        pw.SizedBox(height: 1.5),
        pw.Text(
          'E-LEG OF GRAND CHAMPION CERTIFICATE',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
        ),
      ],
    );
  }

  pw.Widget _leftInfo(LegsCertificateData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Expanded(child: _boxedMiniPair('EXH#', d.exhibitorNumber)),
            pw.SizedBox(width: 4),
            pw.Expanded(child: _boxedMiniPair('EAR#', d.earNumber)),
          ],
        ),
        pw.SizedBox(height: 6),
        _animalBlock(d),
        pw.SizedBox(height: 6),
        _fillLine('BORN'),
        _fillLine('REG.#'),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.blue800, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.0),
            1: pw.FlexColumnWidth(1.2),
            2: pw.FlexColumnWidth(1.2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blue50),
              children: [
                _tinyHeaderCell('WIN'),
                _tinyHeaderCell('NO. ANIMALS'),
                _tinyHeaderCell('NO. EXHIBITORS'),
              ],
            ),
            pw.TableRow(
              children: [
                _tinyValueCell(d.winCode),
                _tinyValueCell('${d.animalsCount}'),
                _tinyValueCell('${d.exhibitorsCount}'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _animalBlock(LegsCertificateData d) {
    final lines = <String>[
      if (d.breed.isNotEmpty) d.breed.toUpperCase(),
      if (d.variety.isNotEmpty) d.variety.toUpperCase(),
      if (d.className.isNotEmpty) d.className.toUpperCase(),
      if (d.sex.isNotEmpty) d.sex.toUpperCase(),
    ];

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue800, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines
            .map(
              (line) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 1.5),
                child: pw.Text(
                  line,
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  pw.Widget _rightInfo(LegsCertificateData d) {
    final qrUrl = _buildLegVerificationUrl(d);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 36,
              height: 36,
              alignment: pw.Alignment.center,
              child: pw.Image(
                pw.MemoryImage(arbaLogoBytes),
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Container(
              width: 44,
              height: 36,
              alignment: pw.Alignment.center,
              child: pw.Image(
                pw.MemoryImage(ringMasterLogoBytes),
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: d.barcodeValue,
                  width: 180,
                  height: 40,
                  drawText: false,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          d.exhibitorName.isEmpty ? 'UNKNOWN EXHIBITOR' : d.exhibitorName,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (d.ownerAddress.isNotEmpty)
          pw.Text(
            d.ownerAddress,
            style: const pw.TextStyle(fontSize: 7),
          ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  _detailLine('SHOW', d.showName),
                  _detailLine('CLUB', d.clubName),
                  _detailLine('DATE', _fmtDate(d.showDate)),
                  _detailLine('SECTY', d.secretaryName),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Column(
                children: [
                  _detailLine('SANC. NO.', d.sanctionNumber),
                  _detailLine(
                    'JUDGE',
                    d.judgeName.isEmpty ? 'UNKNOWN JUDGE' : d.judgeName,
                  ),
                  _detailLine('LOCATION', d.location),
                  _detailLine('EMAIL', d.secretaryEmail),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Container(
              width: 54,
              height: 54,
              padding: const pw.EdgeInsets.all(2),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue800, width: 0.6),
              ),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrUrl,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.blue800, width: 0.5),
            color: PdfColors.blue50,
          ),
          child: pw.Text(
            'Rule ${d.legRule}: ${d.legRuleDescription}',
            style: const pw.TextStyle(fontSize: 6.5),
          ),
        ),
      ],
    );
  }

  String _buildLegVerificationUrl(LegsCertificateData d) {
    final existing = d.qrValue.trim();
    if (existing.isNotEmpty) {
      return existing;
    }

    final id = d.barcodeValue.trim();
    final encodedId = Uri.encodeComponent(id);

    return 'https://show.ringmasterone.com/verify-leg?id=$encodedId';
  }

  pw.Widget _boxedMiniPair(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue800, width: 0.6),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            '$label ',
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _cutLine() {
    return pw.Row(
      children: List.generate(
        80,
        (index) => pw.Expanded(
          child: pw.Container(
            height: 1,
            color: index.isEven ? PdfColors.grey700 : PdfColors.white,
          ),
        ),
      ),
    );
  }

  pw.Widget _blankCertificateSpace() {
    return pw.SizedBox(height: 190);
  }

  pw.Widget _rulesBlock() {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 2),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue800, width: 0.8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'RULES GOVERNING AWARDING LEGS OF GRAND CHAMPION',
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'A Leg of Grand Champion will be awarded to any rabbit or cavy that:',
            style: pw.TextStyle(
              fontSize: 7.5,
              color: PdfColors.blue800,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 5),
          ...List.generate(legRules.length, (index) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 14,
                    child: pw.Text(
                      '${index + 1}.',
                      style: pw.TextStyle(
                        fontSize: 6.7,
                        color: PdfColors.blue800,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      legRules[index],
                      style: pw.TextStyle(
                        fontSize: 6.7,
                        color: PdfColors.blue800,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  pw.Widget _fillLine(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 30,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 7,
                color: PdfColors.blue800,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              height: 10,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _detailLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 42,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 6.7,
                color: PdfColors.blue800,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 6.7),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _tinyHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 6.2,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue800,
        ),
      ),
    );
  }

  pw.Widget _tinyValueCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(fontSize: 6.8),
      ),
    );
  }

  String _fmtDate(DateTime? value) {
    if (value == null) return '';
    return '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}-${value.year}';
  }
}