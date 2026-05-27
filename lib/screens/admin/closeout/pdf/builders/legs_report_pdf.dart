// lib/screens/admin/closeout/pdf/builders/legs_report_pdf.dart

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/legs/legs_certificate_data.dart';

class LegsReportPdfBuilder {
  static const PdfColor arbaBlue = PdfColor.fromInt(0xFF003B9D);
  static const PdfColor arbaBlueLight = PdfColor.fromInt(0xFFEAF1FF);
  final Uint8List arbaLogoBytes;
  final Uint8List ringMasterShowLogoBytes;
  final Uint8List grandChampionCertificateBytes;
  final Uint8List bestInShowCertificateBytes;

  LegsReportPdfBuilder({
    required this.arbaLogoBytes,
    required this.ringMasterShowLogoBytes,
    required this.grandChampionCertificateBytes,
    required this.bestInShowCertificateBytes,
  });

  static Future<LegsReportPdfBuilder> fromAssets() async {
    final arbaLogoBytes = (await rootBundle.load('assets/images/arba_logo.png'))
        .buffer
        .asUint8List();
    final ringMasterShowLogoBytes =
      (await rootBundle.load('assets/images/ringmaster_show_logo.png'))
          .buffer
          .asUint8List();

    final grandChampionCertificateBytes =
        (await rootBundle.load('assets/images/Grand_Champion.png'))
            .buffer
            .asUint8List();

    final bestInShowCertificateBytes =
        (await rootBundle.load('assets/images/BIS_Award.png'))
            .buffer
            .asUint8List();

    return LegsReportPdfBuilder(
      arbaLogoBytes: arbaLogoBytes,
      ringMasterShowLogoBytes: ringMasterShowLogoBytes,
      grandChampionCertificateBytes: grandChampionCertificateBytes,
      bestInShowCertificateBytes: bestInShowCertificateBytes,
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
  static const List<String> arbaContactLines = [
    'American Rabbit Breeders Association, Inc.',
    'P.O. Box 400, Knox, PA 16232',
    'Phone: (814) 797-4129',
    'Email: info@arba.net',
    'Website: arba.net',
  ];

  static const List<String> arbaMembershipFeeLines = [
    'Membership Fees: all non-US residents add 10 per year service charge to all fees.',
    'Adult: 1 yr. 20 | 3 yrs. 50',
    'Youth: 1 yr. 12 | 3 yrs. 30',
    'Husband/Wife: 1 yr. 30 | 3 yrs. 75',
    'Single Adult Family: 1 yr. 20 + 5 per youth | 3 yrs. 50 + 10 per youth',
    'Two Adult Family: 1 yr. 30 + 5 per youth | 3 yrs. 75 + 10 per youth',
  ];

  Future<pw.ThemeData> _buildTheme() async {
    return pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );
  }

  Future<ReportFileResult> buildFile(
      List<LegsCertificateData> data,
      ReportRequest request,
    ) async {
      final theme = await _buildTheme();
      final pdf = pw.Document(theme: theme);

      String cleanFilePart(String input) {
        return input
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      final cleanedShowName = cleanFilePart(
        (request.showName ?? '').trim().isEmpty ? 'Show' : (request.showName ?? '').trim(),
      );

      final cleanedExhibitorName = cleanFilePart(
        (request.exhibitorName ?? '').trim().isEmpty
            ? 'Exhibitor'
            : (request.exhibitorName ?? '').trim(),
      );

      // Remove any UUID-like fragments from exhibitor name (sometimes passed in)
      final cleanedExhibitorNameNoId = cleanedExhibitorName
          .replaceAll(RegExp(r'\b[0-9a-fA-F\-]{8,}\b'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      final fileName =
          '$cleanedShowName - $cleanedExhibitorNameNoId - Legs.pdf';

      if (data.isEmpty) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.letter,
            margin: const pw.EdgeInsets.all(24),
            theme: theme,
            build: (_) => pw.Center(
              child: pw.Text('No leg certificates earned.'),
            ),
          ),
        );
      } else {
        final sortedData = _sortCertificates(data);

        for (final certificate in sortedData) {
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.letter,
              margin: const pw.EdgeInsets.fromLTRB(22, 18, 22, 18),
              theme: theme,
              build: (_) {
                return [
                  _certificate(certificate),
                  pw.SizedBox(height: 8),
                  _cutLine(),
                  pw.SizedBox(height: 8),
                  _rulesAndRequiredArbaInfoBlock(),
                  pw.SizedBox(height: 8),
                  _requiredCertificateImagesBlock(),
                ];
              },
            ),
          );
        }
      }

      final bytes = await pdf.save();

      return ReportFileResult(
        fileName: fileName,
        mimeType: 'application/pdf',
        bytes: bytes,
      );
    }

  List<LegsCertificateData> _sortCertificates(
    List<LegsCertificateData> data,
  ) {
    return [...data]
      ..sort((a, b) {
        final exhibitorCompare = a.exhibitorName.compareTo(b.exhibitorName);
        if (exhibitorCompare != 0) return exhibitorCompare;

        final numberCompare = a.exhibitorNumber.compareTo(b.exhibitorNumber);
        if (numberCompare != 0) return numberCompare;

        return a.earNumber.compareTo(b.earNumber);
      });
  }


  pw.Widget _certificate(LegsCertificateData d) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: arbaBlue, width: 1),
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
          pw.SizedBox(height: 6),
          _winDetailsBlock(d),
        ],
      ),
    );
  }

  pw.Widget _certificateHeader() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 42,
          height: 42,
          alignment: pw.Alignment.center,
          child: pw.Image(
            pw.MemoryImage(arbaLogoBytes),
            fit: pw.BoxFit.contain,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'AMERICAN RABBIT BREEDERS ASSOCIATION, INC.',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: arbaBlue,
                ),
              ),
              pw.SizedBox(height: 1.5),
              pw.Text(
                'E-LEG OF GRAND CHAMPION CERTIFICATE',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: arbaBlue,
                ),
              ),
            ],
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
            pw.Expanded(
              child: _boxedMiniPair(
                'EXH#',
                _displayExhibitorNumber(d),
              ),
            ),
            pw.SizedBox(width: 4),
            pw.Expanded(child: _boxedMiniPair('EAR#', d.earNumber)),
          ],
        ),
        pw.SizedBox(height: 6),
        _animalBlock(d),
        pw.SizedBox(height: 6),
        _fillLine('BORN'),
        _fillLine('REG.#'),
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
        border: pw.Border.all(color: arbaBlue, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines
            .map(
              (line) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 1.5),
                child: pw.Text(
                  line,
                  style: const pw.TextStyle(fontSize: 9.5),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  pw.Widget _rightInfo(LegsCertificateData d) {
    // QR verification is currently hidden. Keep this builder call available
    // for restoring the QR code later.
    // final qrUrl = _buildLegVerificationUrl(d);
    final arbaBarcodeValue = _buildArbaELegBarcode(d);

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
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: arbaBarcodeValue,
                      width: 180,
                      height: 34,
                      drawText: false,
                    ),
                    pw.SizedBox(height: 1.5),
                    pw.Text(
                      arbaBarcodeValue,
                      style: const pw.TextStyle(fontSize: 5.2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        _exhibitorVerificationBlock(d),
        pw.SizedBox(height: 4),
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
            // QR verification block hidden for now. Restore this block if
            // RingMaster verification QR codes are needed later.
            /*
            pw.SizedBox(width: 8),
            pw.Container(
              width: 54,
              height: 54,
              padding: const pw.EdgeInsets.all(2),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: arbaBlue, width: 0.6),
              ),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrUrl,
              ),
            ),
            */
          ],
        ),
      ],
    );
  }

  pw.Widget _exhibitorVerificationBlock(LegsCertificateData d) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: arbaBlue, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            d.exhibitorName.isEmpty ? 'UNKNOWN EXHIBITOR' : d.exhibitorName,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          ..._buildAddressLines(d),
        ],
      ),
    );
  }

  List<pw.Widget> _buildAddressLines(LegsCertificateData d) {
    final raw = d.ownerAddress.trim();

    if (raw.isEmpty) {
      return [
        pw.Text(
          'Address not available',
          style: const pw.TextStyle(fontSize: 6.7),
        ),
      ];
    }

    final parts = raw.split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return parts.map((line) {
      return pw.Text(
        line,
        style: const pw.TextStyle(fontSize: 6.7),
      );
    }).toList();
  }

  String _buildArbaELegBarcode(LegsCertificateData d) {
    final sanction = _alphaNumericOnly(d.sanctionNumber).toUpperCase();
    final ear = _alphaNumericOnly(d.earNumber).toUpperCase();
    final breed = _alphaNumericOnly(d.breed).toUpperCase();
    final variety = _alphaNumericOnly(d.variety).toUpperCase();
    final className = _alphaNumericOnly(d.className).toUpperCase();
    final sex = _alphaNumericOnly(d.sex).toUpperCase();

    final yearDigit = d.showDate == null
        ? '0'
        : (d.showDate!.year % 10).toString();

    final sanctionLastDigit = _lastDigit(sanction) ?? 0;
    final yearLastDigit = int.tryParse(yearDigit) ?? 0;
    final checkDigit = ((yearLastDigit + sanctionLastDigit) / 2).ceil();

    return '*'
        '$yearDigit'
        '${_lastChar(breed)}'
        '${_charAt(sanction, 0)}'
        '${_classCode(className)}'
        '${_charAt(sanction, 2)}'
        '${_lastChar(ear)}'
        '${_charAt(sanction, 4)}'
        '${_thirdFromRightOrZero(ear)}'
        '${_lastChar(sanction)}'
        '${variety.isEmpty ? 'Z' : _firstChar(variety)}'
        '${_charAt(sanction, 5)}'
        '${_secondFromRightOrZero(ear)}'
        '${_charAt(sanction, 3)}'
        '${_sexCode(sex)}'
        '${_charAt(sanction, 1)}'
        '${_firstChar(breed)}'
        '$checkDigit'
        '*';
  }

  String _alphaNumericOnly(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  }

  String _firstChar(String value) {
    return value.isEmpty ? 'Z' : value[0];
  }

  String _lastChar(String value) {
    return value.isEmpty ? '0' : value[value.length - 1];
  }

  String _charAt(String value, int index) {
    return value.length > index ? value[index] : '0';
  }

  String _thirdFromRightOrZero(String value) {
    return value.length >= 3 ? value[value.length - 3] : '0';
  }

  String _secondFromRightOrZero(String value) {
    return value.length >= 2 ? value[value.length - 2] : '0';
  }

  int? _lastDigit(String value) {
    for (var i = value.length - 1; i >= 0; i--) {
      final digit = int.tryParse(value[i]);
      if (digit != null) return digit;
    }
    return null;
  }

  String _classCode(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('intermediate')) return 'I';
    if (lower.contains('junior')) return 'J';
    if (lower.contains('pre')) return 'P';
    if (lower.contains('senior')) return 'S';
    return value.isEmpty ? 'Z' : value[0];
  }

  String _sexCode(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('b') || lower.contains('buck') || lower.contains('boar')) {
      return 'B';
    }
    if (lower.startsWith('d') || lower.contains('doe')) return 'D';
    if (lower.startsWith('s') || lower.contains('sow')) return 'D';
    return value.isEmpty ? 'Z' : value[0];
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

  String _displayExhibitorNumber(LegsCertificateData d) {
    final showExhibitorNumber = d.exhibitorNumber.trim();
    final exhibitorName = d.exhibitorName.trim();

    // EXH# should be the show-specific exhibitor number only. Guard against
    // upstream fallbacks that accidentally pass the exhibitor name here.
    if (showExhibitorNumber.isNotEmpty &&
        showExhibitorNumber.toLowerCase() != exhibitorName.toLowerCase()) {
      return showExhibitorNumber;
    }

    return 'ERROR';
  }

  pw.Widget _boxedMiniPair(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: arbaBlue, width: 0.6),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            '$label ',
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: arbaBlue,
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


  pw.Widget _requiredCertificateImagesBlock() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: arbaBlue, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _certificateImagePanel(
              title: 'GRAND CHAMPION CERTIFICATE',
              imageBytes: grandChampionCertificateBytes,
              rules: const [
                'A Grand Champion Certificate will be awarded to any rabbit or cavy that has won at least 3 Legs.',
                'Only one Grand Champion Certificate will be awarded to the same rabbit or cavy.',
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _certificateImagePanel(
              title: 'BEST IN SHOW CERTIFICATE',
              imageBytes: bestInShowCertificateBytes,
              rules: const [
                'The ARBA will award a Best in Show Certificate to any rabbit or cavy that has won this award.',
                'The ARBA will award a Best in Specialty Show Certificate to any rabbit or cavy that has won this award at a breed specialty show.',
                'Send the legs showing the respective award with the fee to receive the certificate.',
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _certificateImagePanel({
    required String title,
    required Uint8List imageBytes,
    required List<String> rules,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          height: 90,
          alignment: pw.Alignment.center,
          child: pw.Image(
            pw.MemoryImage(imageBytes),
            fit: pw.BoxFit.contain,
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 6.2,
            fontWeight: pw.FontWeight.bold,
            color: arbaBlue,
          ),
        ),
        pw.SizedBox(height: 1),
        ...List.generate(rules.length, (index) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1.2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 8,
                  child: pw.Text(
                    '${index + 1}.',
                    style: const pw.TextStyle(fontSize: 4.9),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    rules[index],
                    style: const pw.TextStyle(fontSize: 4.9),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  pw.Widget _rulesAndRequiredArbaInfoBlock() {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: arbaBlue, width: 0.8),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'RULES GOVERNING AWARDING LEGS OF GRAND CHAMPION',
            style: pw.TextStyle(
              fontSize: 8.8,
              fontWeight: pw.FontWeight.bold,
              color: arbaBlue,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'A Leg of Grand Champion will be awarded to any rabbit or cavy that:',
            style: pw.TextStyle(
              fontSize: 7,
              color: arbaBlue,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 3),
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
                        fontSize: 6.1,
                        color: arbaBlue,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      legRules[index],
                      style: pw.TextStyle(
                        fontSize: 6.1,
                        color: arbaBlue,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _arbaRequiredInfoPanel(
                  'ARBA CONTACT INFORMATION',
                  arbaContactLines,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: _arbaRequiredInfoPanel(
                  'MEMBERSHIP FEE SCHEDULE',
                  arbaMembershipFeeLines,
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'Generated by ',
                style: pw.TextStyle(
                  fontSize: 5.5,
                  color: arbaBlue,
                ),
              ),
              pw.SizedBox(width: 3),
              pw.Container(
                width: 40,
                height: 10,
                alignment: pw.Alignment.center,
                child: pw.Image(
                  pw.MemoryImage(ringMasterShowLogoBytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
              pw.SizedBox(width: 3),
              pw.Text(
                'RingMaster One',
                style: pw.TextStyle(
                  fontSize: 5.5,
                  fontWeight: pw.FontWeight.bold,
                  color: arbaBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _arbaRequiredInfoPanel(String title, List<String> lines) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: arbaBlue, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 5.5,
              fontWeight: pw.FontWeight.bold,
              color: arbaBlue,
            ),
          ),
          pw.SizedBox(height: 2),
          ...lines.map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Text(
                line,
                style: const pw.TextStyle(fontSize: 4.9),
              ),
            ),
          ),
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
                color: arbaBlue,
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
                color: arbaBlue,
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
          fontSize: 7.2,
          fontWeight: pw.FontWeight.bold,
          color: arbaBlue,
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
        style: const pw.TextStyle(fontSize: 7.5),
      ),
    );
  }

  pw.Widget _winDetailsBlock(LegsCertificateData d) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: arbaBlue, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PLACEMENT / WIN DATA',
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: arbaBlue,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Table(
            border: pw.TableBorder.all(color: arbaBlue, width: 0.45),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.1),
              1: pw.FlexColumnWidth(1.5),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1.2),
              4: pw.FlexColumnWidth(3.6),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: arbaBlueLight),
                children: [
                  _tinyHeaderCell('WIN'),
                  _tinyHeaderCell('CLASS / AWARD'),
                  _tinyHeaderCell('NO. ANIMALS'),
                  _tinyHeaderCell('NO. EXHIBITORS'),
                  _tinyHeaderCell('QUALIFYING BASIS'),
                ],
              ),
              pw.TableRow(
                children: [
                  _tinyValueCell(d.winCode),
                  _tinyValueCell(_awardScopeLabel(d)),
                  _tinyValueCell('${d.animalsCount}'),
                  _tinyValueCell('${d.exhibitorsCount}'),
                  _tinyValueCell('Rule ${d.legRule}: ${d.legRuleDescription}'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _awardScopeLabel(LegsCertificateData d) {
    final parts = <String>[
      if (d.breed.trim().isNotEmpty) d.breed.trim(),
      if (d.variety.trim().isNotEmpty) d.variety.trim(),
      if (d.className.trim().isNotEmpty) d.className.trim(),
      if (d.sex.trim().isNotEmpty) d.sex.trim(),
    ];

    return parts.isEmpty ? 'Award' : parts.join(' / ');
  }

  String _fmtDate(DateTime? value) {
    if (value == null) return '';
    return '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}-${value.year}';
  }
}