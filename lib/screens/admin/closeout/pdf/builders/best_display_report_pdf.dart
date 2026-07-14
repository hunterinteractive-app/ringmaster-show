// lib/screens/admin/closeout/pdf/builders/best_display_report_pdf.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/best_display_report_data.dart';

class BestDisplayReportPdfBuilder {
  BestDisplayReportPdfBuilder({required ReportAssetLoader assets})
    : _assets = assets;

  final ReportAssetLoader _assets;

  Future<Uint8List> build(BestDisplayReportData data) async {
    final document = pw.Document(
      title: 'Best Display Report - ${data.showName}',
      author: 'RingMaster Show',
      creator: 'RingMaster Show',
      subject: 'Best Display standings by show section and species.',
    );

    final fonts = await _loadFonts();

    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(fonts),
        header: (context) => _buildHeader(data),
        footer: _buildFooter,
        build: (context) {
          if (data.sections.isEmpty || data.isEmpty) {
            return <pw.Widget>[
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text(
                  'No Best Display standings were found for this show.',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ];
          }

          return <pw.Widget>[
            _buildSummary(data),
            pw.SizedBox(height: 12),
            for (var index = 0; index < data.sections.length; index++) ...[
              if (index > 0) pw.NewPage(),
              ..._buildSection(data.sections[index]),
            ],
            if (data.breedSections.isNotEmpty) ...[
              pw.NewPage(),
              pw.Text(
                'Best Display by Breed',
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              for (
                var index = 0;
                index < data.breedSections.length;
                index++
              ) ...[
                if (index > 0) pw.NewPage(),
                ..._buildBreedSection(data.breedSections[index]),
              ],
            ],
          ];
        },
      ),
    );

    return document.save();
  }

  Future<_BestDisplayFonts> _loadFonts() async {
    final regular = pw.Font.ttf(
      await _assets.loadByteData('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await _assets.loadByteData('assets/fonts/NotoSans-Bold.ttf'),
    );

    return _BestDisplayFonts(regular: regular, bold: bold);
  }

  pw.PageTheme _pageTheme(_BestDisplayFonts fonts) {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.letter.landscape,
      margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 26),
      theme: pw.ThemeData.withFont(
        base: fonts.regular,
        bold: fonts.bold,
        italic: fonts.regular,
        boldItalic: fonts.bold,
      ),
    );
  }

  pw.Widget _buildHeader(BestDisplayReportData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.7, color: PdfColors.grey600),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'Best Display Report',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  data.showName,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (data.showDate.trim().isNotEmpty)
                  pw.Text(
                    data.showDate,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if (data.showLocation.trim().isNotEmpty)
                  pw.Text(
                    data.showLocation,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                'Minimum display: ${data.minimumEntriesRequired} entries',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Points: 6-4-3-2-1 × animals judged',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Rabbit and cavy standings calculated separately',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummary(BestDisplayReportData data) {
    final eligibleCount = data.allRows.where((row) => row.isEligible).length;

    final winnerCount = data.allRows.where((row) => row.isWinner).length;

    final tiedSectionCount = data.sections
        .where((section) => section.hasFirstPlaceTie)
        .length;

    final breedWinnerCount = data.breedSections
        .where((section) => section.winner != null)
        .length;

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey700, width: 0.4),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          _summaryItem('Sections', data.sections.length.toString()),
          _summaryDivider(),
          _summaryItem('Standings', data.totalStandingRows.toString()),
          _summaryDivider(),
          _summaryItem('Eligible Displays', eligibleCount.toString()),
          _summaryDivider(),
          _summaryItem('Winners', winnerCount.toString()),
          _summaryDivider(),
          _summaryItem('Breed Winners', breedWinnerCount.toString()),
          _summaryDivider(),
          _summaryItem('First-Place Ties', tiedSectionCount.toString()),
        ],
      ),
    );
  }

  pw.Widget _summaryItem(String label, String value) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  pw.Widget _summaryDivider() {
    return pw.Container(width: 0.5, height: 28, color: PdfColors.grey400);
  }

  List<pw.Widget> _buildSection(BestDisplaySectionData section) {
    return <pw.Widget>[
      _buildSectionHeader(section),
      pw.SizedBox(height: 6),
      if (section.hasFirstPlaceTie)
        _buildTieNotice()
      else if (section.winner != null)
        _buildWinnerNotice(section.winner!),
      if (section.hasFirstPlaceTie || section.winner != null)
        pw.SizedBox(height: 8),
      _buildStandingsTable(section.rows),
    ];
  }

  pw.Widget _buildSectionHeader(BestDisplaySectionData section) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 2),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey300,
        border: pw.Border.all(color: PdfColors.grey700, width: 0.4),
        borderRadius: const pw.BorderRadius.only(
          topLeft: pw.Radius.circular(4),
          topRight: pw.Radius.circular(4),
        ),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              section.displayName,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            '${section.rows.length} exhibitor'
            '${section.rows.length == 1 ? '' : 's'}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildWinnerNotice(BestDisplayStandingRow winner) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey600, width: 0.4),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Text(
            'Winner: ',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.Expanded(
            child: pw.Text(
              winner.exhibitorName,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            '${_formatPoints(winner.displayPoints)} points',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTieNotice() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey600, width: 0.4),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        'First-place tie detected. The sponsoring club must resolve '
        'the tie before a winner is recorded.',
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _buildStandingsTable(List<BestDisplayStandingRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.4),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(38),
        1: pw.FlexColumnWidth(2.4),
        2: pw.FixedColumnWidth(46),
        3: pw.FixedColumnWidth(46),
        4: pw.FixedColumnWidth(32),
        5: pw.FixedColumnWidth(32),
        6: pw.FixedColumnWidth(32),
        7: pw.FixedColumnWidth(32),
        8: pw.FixedColumnWidth(32),
        9: pw.FixedColumnWidth(52),
        10: pw.FixedColumnWidth(78),
      },
      children: <pw.TableRow>[
        _standingsHeaderRow(),
        ...rows.map(_standingsDataRow),
      ],
    );
  }

  pw.TableRow _standingsHeaderRow() {
    final style = pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold);

    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: <pw.Widget>[
        _cell('Rank', style: style, isHeader: true),
        _cell('Exhibitor', style: style, isHeader: true),
        _cell('Entries', style: style, isHeader: true),
        _cell('Point\nEntries', style: style, isHeader: true),
        _cell('1st', style: style, isHeader: true),
        _cell('2nd', style: style, isHeader: true),
        _cell('3rd', style: style, isHeader: true),
        _cell('4th', style: style, isHeader: true),
        _cell('5th', style: style, isHeader: true),
        _cell('Points', style: style, isHeader: true),
        _cell('Status', style: style, isHeader: true),
      ],
    );
  }

  pw.TableRow _standingsDataRow(BestDisplayStandingRow row) {
    final style = pw.TextStyle(
      fontSize: 7.5,
      fontWeight: row.isWinner ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: row.isEligible ? PdfColors.black : PdfColors.grey700,
    );

    final background = row.isWinner
        ? PdfColors.grey200
        : row.isEligible
        ? PdfColors.white
        : PdfColors.grey100;

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: background),
      children: <pw.Widget>[
        _cell(row.rankLabel, style: style),
        _cell(row.exhibitorName, style: style),
        _cell(row.qualifyingEntryCount.toString(), style: style),
        _cell(row.pointEarningEntryCount.toString(), style: style),
        _cell(row.firstPlaceCount.toString(), style: style),
        _cell(row.secondPlaceCount.toString(), style: style),
        _cell(row.thirdPlaceCount.toString(), style: style),
        _cell(row.fourthPlaceCount.toString(), style: style),
        _cell(row.fifthPlaceCount.toString(), style: style),
        _cell(_formatPoints(row.displayPoints), style: style),
        _cell(row.statusLabel, style: style),
      ],
    );
  }

  pw.Widget _cell(
    String text, {
    required pw.TextStyle style,
    bool isHeader = false,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: isHeader ? 4 : 3,
        vertical: isHeader ? 4 : 3,
      ),
      child: pw.Text(
        text,
        style: style,
        maxLines: isHeader ? 2 : 3,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: <pw.Widget>[
          pw.Divider(thickness: 0.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'Generated by RingMaster Show',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of '
                '${context.pagesCount}',
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

  String _formatPoints(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  Future<ReportFileResult> buildFile(
    BestDisplayReportData data,
    ReportRequest request,
  ) async {
    final bytes = await build(data);

    final safeShowName = data.showName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final speciesPart = _speciesFilePart(request.species);
    final scopePart = _clean(request.scope ?? '');
    final showLetterPart = _clean(request.showLetter ?? '');
    final sectionParts = [
      if (scopePart.isNotEmpty) scopePart,
      if (showLetterPart.isNotEmpty) showLetterPart,
    ].join('_');
    final suffix = sectionParts.isEmpty ? '' : '_$sectionParts';

    final fileName = safeShowName.isEmpty
        ? 'Display_Points$speciesPart$suffix.pdf'
        : '${safeShowName}_Display_Points$speciesPart$suffix.pdf';

    return ReportFileResult(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/pdf',
    );
  }

  String _speciesFilePart(String? species) {
    final normalized = (species ?? '').trim().toLowerCase();
    if (normalized == 'rabbit') return '_Rabbit';
    if (normalized == 'cavy') return '_Cavy';
    return '';
  }

  String _clean(String value) => value
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  List<pw.Widget> _buildBreedSection(BestDisplayBreedSectionData section) {
    return <pw.Widget>[
      _buildBreedSectionHeader(section),
      pw.SizedBox(height: 6),
      if (section.hasFirstPlaceTie)
        _buildTieNotice()
      else if (section.winner != null)
        _buildBreedWinnerNotice(section.winner!),
      if (section.hasFirstPlaceTie || section.winner != null)
        pw.SizedBox(height: 8),
      _buildBreedStandingsTable(section.rows),
    ];
  }

  pw.Widget _buildBreedSectionHeader(BestDisplayBreedSectionData section) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 2),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey300,
        border: pw.Border.all(color: PdfColors.grey700, width: 0.4),
        borderRadius: const pw.BorderRadius.only(
          topLeft: pw.Radius.circular(4),
          topRight: pw.Radius.circular(4),
        ),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              section.displayName,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            '${section.rows.length} exhibitor'
            '${section.rows.length == 1 ? '' : 's'}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildBreedWinnerNotice(BestDisplayBreedStandingRow winner) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey600, width: 0.4),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Text(
            'Winner: ',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.Expanded(
            child: pw.Text(
              winner.exhibitorName,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            '${_formatPoints(winner.displayPoints)} points',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildBreedStandingsTable(List<BestDisplayBreedStandingRow> rows) {
    final headerStyle = pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
    );

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.4),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(44),
        1: pw.FlexColumnWidth(2.6),
        2: pw.FixedColumnWidth(58),
        3: pw.FixedColumnWidth(62),
        4: pw.FixedColumnWidth(62),
        5: pw.FixedColumnWidth(86),
      },
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: <pw.Widget>[
            _cell('Rank', style: headerStyle, isHeader: true),
            _cell('Exhibitor', style: headerStyle, isHeader: true),
            _cell('Entries', style: headerStyle, isHeader: true),
            _cell('Point\nEntries', style: headerStyle, isHeader: true),
            _cell('Points', style: headerStyle, isHeader: true),
            _cell('Status', style: headerStyle, isHeader: true),
          ],
        ),
        ...rows.map((row) {
          final style = pw.TextStyle(
            fontSize: 7.5,
            fontWeight: row.isWinner
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
            color: row.isEligible ? PdfColors.black : PdfColors.grey700,
          );

          final background = row.isWinner
              ? PdfColors.grey200
              : row.isEligible
              ? PdfColors.white
              : PdfColors.grey100;

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: background),
            children: <pw.Widget>[
              _cell(row.rankLabel, style: style),
              _cell(row.exhibitorName, style: style),
              _cell(row.qualifyingEntryCount.toString(), style: style),
              _cell(row.pointEarningEntryCount.toString(), style: style),
              _cell(_formatPoints(row.displayPoints), style: style),
              _cell(row.statusLabel, style: style),
            ],
          );
        }),
      ],
    );
  }
}

class _BestDisplayFonts {
  const _BestDisplayFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}
