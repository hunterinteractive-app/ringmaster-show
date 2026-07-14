// lib/screens/admin/closeout/pdf/builders/judge_report_pdf.dart

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';

import 'package:pdf/widgets.dart' as pw;
import '../../models/base/report_file_result.dart';

import '../../models/judge/judge_report_data.dart';

class JudgeReportPdfBuilder {
  JudgeReportPdfBuilder({
    required ReportAssetLoader assets,
    DateFormat? dateFormat,
    DateFormat? dateTimeFormat,
  }) : _assets = assets,
       _dateFormat = dateFormat ?? DateFormat('MM/dd/yyyy'),
       _dateTimeFormat = dateTimeFormat ?? DateFormat('MM/dd/yyyy h:mm a');

  final DateFormat _dateFormat;
  final DateFormat _dateTimeFormat;
  final ReportAssetLoader _assets;

  Future<Uint8List> build(JudgeReportData data) async {
    final document = pw.Document(
      title: 'Judge Report - ${data.show.showName}',
      author: 'RingMaster Show',
      creator: 'RingMaster Show',
      subject: 'Judge report listing all animals judged by each judge.',
    );

    final fonts = await _loadFonts();

    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(fonts),
        header: (context) => _buildHeader(data),
        footer: (context) => _buildFooter(context),
        build: (context) {
          if (data.judges.isEmpty) {
            return <pw.Widget>[
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text(
                  'No judged animals were found for this show.',
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
            _buildJudgeOverviewTable(data),
            pw.NewPage(),
            for (final judge in data.judges) ..._buildJudgeSection(judge),
          ];
        },
      ),
    );

    return document.save();
  }

  Future<_JudgeReportFonts> _loadFonts() async {
    final regular = pw.Font.ttf(
      await _assets.loadByteData('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await _assets.loadByteData('assets/fonts/NotoSans-Bold.ttf'),
    );

    return _JudgeReportFonts(regular: regular, bold: bold);
  }

  pw.PageTheme _pageTheme(_JudgeReportFonts fonts) {
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

  pw.Widget _buildHeader(JudgeReportData data) {
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
                  'Judge Report',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  data.show.showName,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _showDateLine(data),
                  style: const pw.TextStyle(fontSize: 9),
                ),
                if (data.show.locationName.trim().isNotEmpty)
                  pw.Text(
                    data.show.locationName,
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
                'Generated: ${_dateTimeFormat.format(data.generatedAt)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              if ((data.show.secretaryName ?? '').trim().isNotEmpty)
                pw.Text(
                  'Secretary: ${data.show.secretaryName}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              if ((data.show.secretaryEmail ?? '').trim().isNotEmpty)
                pw.Text(
                  data.show.secretaryEmail!,
                  style: const pw.TextStyle(fontSize: 8),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummary(JudgeReportData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey700, width: 0.4),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          _summaryItem('Judges', data.judges.length.toString()),
          _summaryDivider(),
          _summaryItem('Breed', data.totalBreedEntries.toString()),
          _summaryDivider(),
          _summaryItem('Fur', data.totalFurEntries.toString()),
          _summaryDivider(),
          _summaryItem('Total Judged', data.totalEntriesJudged.toString()),
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

  pw.Widget _buildJudgeOverviewTable(JudgeReportData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'Judge Overview',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.4),
          columnWidths: const <int, pw.TableColumnWidth>{
            0: pw.FlexColumnWidth(),
            1: pw.FixedColumnWidth(60),
            2: pw.FixedColumnWidth(60),
            3: pw.FixedColumnWidth(70),
          },
          children: <pw.TableRow>[
            _judgeOverviewHeaderRow(),
            ...data.judges.map(_judgeOverviewDataRow),
          ],
        ),
      ],
    );
  }

  pw.TableRow _judgeOverviewHeaderRow() {
    final style = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: <pw.Widget>[
        _cell('Judge', style: style, isHeader: true),
        _cell('Breed', style: style, isHeader: true),
        _cell('Fur', style: style, isHeader: true),
        _cell('Total', style: style, isHeader: true),
      ],
    );
  }

  pw.TableRow _judgeOverviewDataRow(JudgeReportJudge judge) {
    const style = pw.TextStyle(fontSize: 8);

    return pw.TableRow(
      children: <pw.Widget>[
        _cell(judge.displayLabel, style: style),
        _cell(judge.breedEntryCount.toString(), style: style),
        _cell(judge.furEntryCount.toString(), style: style),
        _cell(judge.totalEntryCount.toString(), style: style),
      ],
    );
  }

  List<pw.Widget> _buildJudgeSection(JudgeReportJudge judge) {
    const rowsPerChunk = 28;
    final summaryRows = _breedSummaryRows(judge.rows);
    final widgets = <pw.Widget>[_buildJudgeHeader(judge)];

    if (summaryRows.isEmpty) {
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 14),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.35),
          ),
          child: pw.Text(
            'No judged breeds found for this judge.',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
      );
      return widgets;
    }

    for (var start = 0; start < summaryRows.length; start += rowsPerChunk) {
      final end = start + rowsPerChunk > summaryRows.length
          ? summaryRows.length
          : start + rowsPerChunk;
      final chunk = summaryRows.sublist(start, end);

      widgets.add(_buildBreedSummaryTable(chunk));

      if (end < summaryRows.length) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2, bottom: 4),
            child: pw.Text(
              '${judge.displayLabel} continued',
              style: pw.TextStyle(
                fontSize: 7,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700,
              ),
            ),
          ),
        );
        widgets.add(_buildJudgeHeader(judge));
      } else {
        widgets.add(pw.SizedBox(height: 14));
      }
    }

    return widgets;
  }

  pw.Widget _buildJudgeHeader(JudgeReportJudge judge) {
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
              judge.displayLabel,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            'Breed: ${judge.breedEntryCount}   Fur: ${judge.furEntryCount}   Total: ${judge.totalEntryCount}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildBreedSummaryTable(List<_JudgeBreedSummaryRow> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.4),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(58),
        1: pw.FixedColumnWidth(46),
        2: pw.FlexColumnWidth(),
        3: pw.FixedColumnWidth(58),
      },
      children: <pw.TableRow>[
        _breedSummaryHeaderRow(),
        ...rows.map(_breedSummaryDataRow),
      ],
    );
  }

  pw.TableRow _breedSummaryHeaderRow() {
    final style = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: <pw.Widget>[
        _cell('Section', style: style, isHeader: true),
        _cell('Type', style: style, isHeader: true),
        _cell('Breed', style: style, isHeader: true),
        _cell('Total', style: style, isHeader: true),
      ],
    );
  }

  pw.TableRow _breedSummaryDataRow(_JudgeBreedSummaryRow row) {
    const style = pw.TextStyle(fontSize: 8);

    return pw.TableRow(
      children: <pw.Widget>[
        _cell(row.sectionLabel, style: style),
        _cell(row.judgedAsLabel, style: style),
        _cell(row.breed, style: style),
        _cell(row.total.toString(), style: style),
      ],
    );
  }

  List<_JudgeBreedSummaryRow> _breedSummaryRows(List<JudgeReportRow> rows) {
    final grouped = <String, _JudgeBreedSummaryRow>{};

    for (final row in rows) {
      final key = [row.sectionLabel, row.judgedAsLabel, row.breed].join('|');

      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = _JudgeBreedSummaryRow(
          sectionLabel: row.sectionLabel,
          judgedAsLabel: row.judgedAsLabel,
          breed: row.breed,
          total: 1,
        );
      } else {
        grouped[key] = existing.copyWith(total: existing.total + 1);
      }
    }

    final result = grouped.values.toList();
    result.sort((a, b) {
      final section = a.sectionLabel.compareTo(b.sectionLabel);
      if (section != 0) return section;

      final type = a.judgedAsLabel.compareTo(b.judgedAsLabel);
      if (type != 0) return type;

      return a.breed.compareTo(b.breed);
    });

    return result;
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
        maxLines: isHeader ? 1 : 3,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
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

  String _showDateLine(JudgeReportData data) {
    final start = data.show.startDate;
    final end = data.show.endDate;

    if (start == null && end == null) return '';
    if (start != null && end == null) return _dateFormat.format(start);
    if (start == null && end != null) return _dateFormat.format(end);

    final formattedStart = _dateFormat.format(start!);
    final formattedEnd = _dateFormat.format(end!);
    if (formattedStart == formattedEnd) return formattedStart;
    return '$formattedStart - $formattedEnd';
  }

  Future<ReportFileResult> buildFile(
    JudgeReportData data,
    dynamic request,
  ) async {
    final bytes = await build(data);
    final safeShowName = data.show.showName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final fileName = safeShowName.isEmpty
        ? 'Judge_Report.pdf'
        : '${safeShowName}_Judge_Report.pdf';

    return ReportFileResult(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/pdf',
    );
  }
}

class _JudgeReportFonts {
  const _JudgeReportFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}

class _JudgeBreedSummaryRow {
  const _JudgeBreedSummaryRow({
    required this.sectionLabel,
    required this.judgedAsLabel,
    required this.breed,
    required this.total,
  });

  final String sectionLabel;
  final String judgedAsLabel;
  final String breed;
  final int total;

  _JudgeBreedSummaryRow copyWith({int? total}) {
    return _JudgeBreedSummaryRow(
      sectionLabel: sectionLabel,
      judgedAsLabel: judgedAsLabel,
      breed: breed,
      total: total ?? this.total,
    );
  }
}
