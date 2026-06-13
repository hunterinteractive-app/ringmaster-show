import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/coop_cards/coop_cards_report_data.dart';

class CoopCardsReportPdfBuilder {
  static const double _cardWidth = 4.0 * PdfPageFormat.inch;
  static const double _cardHeight = 4.5 * PdfPageFormat.inch;

  static const PdfColor _navy = PdfColor.fromInt(0xFF11285A);
  static const PdfColor _gold = PdfColor.fromInt(0xFFD4A623);
  static const PdfColor _ink = PdfColor.fromInt(0xFF202124);
  static const PdfColor _muted = PdfColor.fromInt(0xFF5F6673);
  static const PdfColor _line = PdfColor.fromInt(0xFFB9C2D0);
  static const PdfColor _paleBlue = PdfColor.fromInt(0xFFF1F5FB);

  final pw.MemoryImage ringMasterLogoImage;
  final pw.MemoryImage arbaLogoImage;
  final pw.Font regularFont;
  final pw.Font boldFont;

  CoopCardsReportPdfBuilder({
    required this.ringMasterLogoImage,
    required this.arbaLogoImage,
    required this.regularFont,
    required this.boldFont,
  });

  static Future<CoopCardsReportPdfBuilder> fromAssets() async {
    final ringMasterLogo = (await rootBundle.load(
      'assets/images/ringmaster_show_logo.png',
    ))
        .buffer
        .asUint8List();

    final arbaLogo = (await rootBundle.load(
      'assets/images/arba_logo.png',
    ))
        .buffer
        .asUint8List();

    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );

    return CoopCardsReportPdfBuilder(
      ringMasterLogoImage: pw.MemoryImage(ringMasterLogo),
      arbaLogoImage: pw.MemoryImage(arbaLogo),
      regularFont: regular,
      boldFont: bold,
    );
  }

  Future<Uint8List> build(CoopCardsReportData data) async {
    final document = pw.Document(
      compress: true,
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    if (data.cards.isEmpty) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(36),
          build: (_) => pw.Center(
            child: pw.Text(
              'No coop cards are available for this show.',
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 16,
              ),
            ),
          ),
        ),
      );

      return document.save();
    }

    for (var start = 0; start < data.cards.length; start += 4) {
      final pageCards = data.cards.skip(start).take(4).toList();

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: pw.EdgeInsets.zero,
          build: (_) => _buildPage(data, pageCards),
        ),
      );
    }

    return document.save();
  }

  Future<Uint8List> buildPdf(CoopCardsReportData data) => build(data);

  pw.Widget _buildPage(
    CoopCardsReportData data,
    List<CoopCardRow> cards,
  ) {
    return pw.Container(
      width: PdfPageFormat.letter.width,
      height: PdfPageFormat.letter.height,
      alignment: pw.Alignment.center,
      child: pw.SizedBox(
        width: _cardWidth * 2,
        height: _cardHeight * 2,
        child: pw.Column(
          children: [
            pw.Row(
              children: [
                _cardSlot(data, cards, 0),
                _cardSlot(data, cards, 1),
              ],
            ),
            pw.Row(
              children: [
                _cardSlot(data, cards, 2),
                _cardSlot(data, cards, 3),
              ],
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _cardSlot(
    CoopCardsReportData data,
    List<CoopCardRow> cards,
    int index,
  ) {
    if (index >= cards.length) {
      return pw.SizedBox(
        width: _cardWidth,
        height: _cardHeight,
      );
    }

    return _buildCard(data, cards[index]);
  }

  pw.Widget _buildCard(
    CoopCardsReportData data,
    CoopCardRow card,
  ) {
    return pw.Container(
      width: _cardWidth,
      height: _cardHeight,
      padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(
          color: _navy,
          width: 1.2,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _buildTopBand(card),
          pw.SizedBox(height: 3),
          _buildAnimalDetails(card),
          pw.SizedBox(height: 4),
          _buildExhibitorSection(card),
          pw.SizedBox(height: 4),
          _buildBottomBand(data, card),
        ],
      ),
    );
  }

  pw.Widget _buildTopBand(CoopCardRow card) {

    return pw.Container(
      height: 82,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: pw.BoxDecoration(
        color: _paleBlue,
        border: pw.Border.all(color: _navy, width: 0.9),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _topLogo(arbaLogoImage),
          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: pw.BoxDecoration(
                    color: _gold,
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Text(
                    'COOP NO.',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 6.5,
                      color: _navy,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.SizedBox(
                  height: 43,
                  child: pw.Center(
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      child: pw.Text(
                        card.coopNumber,
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 44,
                          color: _navy,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _topLogo(ringMasterLogoImage),
        ],
      ),
    );
  }

  pw.Widget _topLogo(pw.MemoryImage image) {
    return pw.Container(
      width: 54,
      height: 42,
      padding: const pw.EdgeInsets.all(3),
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _gold, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Image(
        image,
        fit: pw.BoxFit.contain,
      ),
    );
  }

  pw.Widget _buildAnimalDetails(CoopCardRow card) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _detailLine(
            leftLabel: 'Ear No.',
            leftValue: card.tattoo,
            rightLabel: 'Animal Name',
            rightValue: card.animalName,
          ),
          pw.SizedBox(height: 3),
          _detailLine(
            leftLabel: 'Breed',
            leftValue: card.breed,
            rightLabel: 'Variety',
            rightValue: card.groupVarietyLabel,
          ),
          pw.SizedBox(height: 3),
          _singleDetailLine(
            label: 'Class',
            value: card.classSexLabel,
          ),
          pw.SizedBox(height: 3),
          _singleDetailLine(
            label: 'Shows',
            value: card.sectionsLabel,
          ),
          pw.SizedBox(height: 3),
          _singleDetailLine(
            label: 'In Class',
            value: '${card.classEntryCount}',
          ),
        ],
      ),
    );
  }

  pw.Widget _detailLine({
    required String leftLabel,
    required String leftValue,
    required String rightLabel,
    required String rightValue,
  }) {
    return pw.SizedBox(
      height: 17,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: _labelValue(leftLabel, leftValue),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _labelValue(rightLabel, rightValue),
          ),
        ],
      ),
    );
  }

  pw.Widget _singleDetailLine({
    required String label,
    required String value,
  }) {
    return pw.SizedBox(
      height: 17,
      child: _labelValue(label, value),
    );
  }

  pw.Widget _labelValue(String label, String value) {
    final displayValue = value.trim().isEmpty ? '-' : value.trim();

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 42,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: regularFont,
              fontSize: 6.3,
              color: _navy,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.SizedBox(
            height: 14,
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                displayValue,
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 8.7,
                  color: _ink,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildExhibitorSection(CoopCardRow card) {
    return pw.Container(
      height: 58,
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _paleBlue,
        border: pw.Border.all(color: _navy, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'EXHIBITOR INFO',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 6.2,
                    color: _navy,
                    letterSpacing: 0.4,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.SizedBox(
                  height: 16,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      card.exhibitorName.trim().isEmpty
                          ? '(Unknown Exhibitor)'
                          : card.exhibitorName.toUpperCase(),
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 11,
                        color: _ink,
                      ),
                    ),
                  ),
                ),
                if (card.exhibitorLocation.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.SizedBox(
                    height: 13,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        card.exhibitorLocation.toUpperCase(),
                        style: pw.TextStyle(
                          font: regularFont,
                          fontSize: 8.5,
                          color: _ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Container(
            width: 72,
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            alignment: pw.Alignment.topCenter,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: _gold, width: 1),
              borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  'EXHIBITOR NO.',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 5.8,
                    color: _navy,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  card.exhibitorNumber.trim().isEmpty
                      ? '-'
                      : card.exhibitorNumber,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 13,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildBottomBand(
    CoopCardsReportData data,
    CoopCardRow card,
  ) {
    return pw.Container(
      height: 42,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: pw.BoxDecoration(
        color: _navy,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(width: 62),
          pw.Expanded(
            child: pw.Text(
              card.footerLabel,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 12,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.SizedBox(
            width: 62,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.SizedBox(
                  width: 58,
                  height: 22,
                  child: pw.Image(
                    ringMasterLogoImage,
                    fit: pw.BoxFit.contain,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  '© ${data.generatedAt.year} RingMaster Show',
                  style: pw.TextStyle(
                    font: regularFont,
                    fontSize: 4.2,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}