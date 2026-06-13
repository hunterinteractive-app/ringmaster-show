// lib/screens/admin/closeout/pdf/builders/coop_cards_report_pdf.dart

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/coop_cards/coop_cards_report_data.dart';

class CoopCardsReportPdfBuilder {
  static const double _cardWidth = 4.0 * PdfPageFormat.inch;
  static const double _cardHeight = 4.5 * PdfPageFormat.inch;

  static const PdfColor _navy = PdfColor.fromInt(0xFF17365D);
  static const PdfColor _lightBlue = PdfColor.fromInt(0xFFEAF1F8);
  static const PdfColor _lightGrey = PdfColor.fromInt(0xFFF3F4F6);
  static const PdfColor _darkGrey = PdfColor.fromInt(0xFF343A40);

  final pw.MemoryImage logoImage;
  final pw.Font regularFont;
  final pw.Font boldFont;

  CoopCardsReportPdfBuilder({
    required this.logoImage,
    required this.regularFont,
    required this.boldFont,
  });

  static Future<CoopCardsReportPdfBuilder> fromAssets() async {
    final logo = (await rootBundle.load(
      'assets/images/ringmaster_show_logo.png',
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
      logoImage: pw.MemoryImage(logo),
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
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(
          color: PdfColors.black,
          width: 1.25,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _buildHeader(data),
          pw.SizedBox(height: 2),
          _buildCoopNumber(card),
          pw.SizedBox(height: 3),
          _buildAnimalGrid(card),
          pw.SizedBox(height: 3),
          _buildExhibitorBox(card),
          pw.SizedBox(height: 3),
          _buildFooter(card),
        ],
      ),
    );
  }

  pw.Widget _buildHeader(CoopCardsReportData data) {
    return pw.SizedBox(
      height: 22,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 64,
            height: 20,
            child: pw.Image(
              logoImage,
              fit: pw.BoxFit.contain,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'COOP CARD',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 8.5,
                    color: _navy,
                    letterSpacing: 0.6,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    data.showName,
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 7,
                      color: _darkGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildCoopNumber(CoopCardRow card) {
    final prefix = card.coopPrefix;
    final sequence = card.coopSequence;

    if (prefix.isEmpty) {
      return pw.Container(
        height: 62,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: _lightBlue,
          border: pw.Border.all(color: _navy, width: 1),
        ),
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: pw.Text(
            card.coopNumber,
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 43,
              color: _navy,
            ),
          ),
        ),
      );
    }

    return pw.Container(
      height: 62,
      decoration: pw.BoxDecoration(
        color: _lightBlue,
        border: pw.Border.all(color: _navy, width: 1),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 52,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              color: _navy,
            ),
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                prefix,
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 21,
                  color: PdfColors.white,
                ),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Center(
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                child: pw.Text(
                  sequence,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 43,
                    color: _navy,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAnimalGrid(CoopCardRow card) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _navy, width: 0.8),
      ),
      child: pw.Column(
        children: [
          _infoRow(
            leftLabel: 'Ear #',
            leftValue: card.tattoo,
            rightLabel: 'Animal',
            rightValue: card.animalName,
          ),
          _divider(),
          _infoRow(
            leftLabel: 'Breed',
            leftValue: card.breed,
            rightLabel: 'Variety',
            rightValue: card.groupVarietyLabel,
          ),
          _divider(),
          _infoRow(
            leftLabel: 'Class',
            leftValue: card.className,
            rightLabel: 'Sex',
            rightValue: card.sex,
          ),
          _divider(),
          _infoRow(
            leftLabel: 'Shows',
            leftValue: card.sectionsLabel,
            rightLabel: 'In Class',
            rightValue: '${card.classEntryCount}',
          ),
          _divider(),
          _infoRow(
            leftLabel: 'Exhibitors',
            leftValue: '${card.classExhibitorCount}',
            rightLabel: 'Exh. #',
            rightValue: card.exhibitorNumber,
          ),
        ],
      ),
    );
  }

  pw.Widget _infoRow({
    required String leftLabel,
    required String leftValue,
    required String rightLabel,
    required String rightValue,
  }) {
    return pw.SizedBox(
      height: 23,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: _infoCell(leftLabel, leftValue),
          ),
          pw.Container(width: 0.8, color: _navy),
          pw.Expanded(
            child: _infoCell(rightLabel, rightValue),
          ),
        ],
      ),
    );
  }

  pw.Widget _infoCell(String label, String value) {
    final displayValue = value.trim().isEmpty ? '-' : value.trim();

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 5.2,
              color: _navy,
              letterSpacing: 0.35,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              displayValue,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 7.4,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _divider() {
    return pw.Container(height: 0.8, color: _navy);
  }

  pw.Widget _buildExhibitorBox(CoopCardRow card) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: pw.BoxDecoration(
        color: _lightGrey,
        border: pw.Border.all(color: _darkGrey, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'EXHIBITOR INFORMATION',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 5.2,
              color: _navy,
              letterSpacing: 0.4,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              card.exhibitorName.trim().isEmpty
                  ? '(Unknown Exhibitor)'
                  : card.exhibitorName.toUpperCase(),
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 7.4,
              ),
            ),
          ),
          if (card.exhibitorLocation.isNotEmpty) ...[
            pw.SizedBox(height: 1),
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                card.exhibitorLocation.toUpperCase(),
                style: pw.TextStyle(
                  font: regularFont,
                  fontSize: 6.8,
                  color: _darkGrey,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildFooter(CoopCardRow card) {
    return pw.Container(
      height: 20,
      alignment: pw.Alignment.center,
      decoration: const pw.BoxDecoration(
        color: _navy,
      ),
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        child: pw.Text(
          card.footerLabel,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: 10.5,
            color: PdfColors.white,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}