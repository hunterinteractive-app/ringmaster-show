// lib/screens/admin/closeout/pdf/builders/breed_results_detail_report_pdf.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/clubs/breed_results_detail_report_data.dart';

class BreedResultsDetailReportPdf {
  final Uint8List? logoBytes;

  BreedResultsDetailReportPdf({this.logoBytes});

  Future<ReportFileResult> buildFile(
    BreedResultsDetailReportData data,
    ReportRequest request,
  ) async {
    final pdf = pw.Document();

    final showName = (request.showName ?? '').trim().isEmpty
        ? 'Unknown Show'
        : request.showName!.trim();

    final showDate = (request.showDate ?? '').trim().isEmpty
        ? 'Unknown Date'
        : request.showDate!.trim();

    final sanctionNumber = (request.sanctionNumber ?? '').trim();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(20),
        footer: _footer,
        build: (context) => [
          _buildHeader(
            showName: showName,
            showDate: showDate,
            sanctionNumber: sanctionNumber,
          ),
          pw.SizedBox(height: 12),
          _buildBreedHeader(
            breedName: data.breedName,
            scope: data.scope,
            judgeName: data.judgeName,
          ),
          pw.SizedBox(height: 10),
          _buildBreedAwards(data.breedAwards),
          pw.SizedBox(height: 12),
          ...data.varieties.map((v) => _buildVarietySection(v)),
        ],
      ),
    );

    final bytes = await pdf.save();

    return ReportFileResult(
      fileName: _buildFileName(
        showName: showName,
        breedName: data.breedName,
        scope: data.scope,
      ),
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  String _buildFileName({
    required String showName,
    required String breedName,
    required String scope,
  }) {
    String clean(String input) {
      return input
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
    }

    return '${clean(showName)}_${clean(breedName)}_${clean(scope.toLowerCase())}_breed_results_detail.pdf';
  }

  pw.Widget _buildHeader({
    required String showName,
    required String showDate,
    required String sanctionNumber,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Breed Results Detail Report',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Show: $showName'),
              pw.Text('Date: $showDate'),
              if (sanctionNumber.isNotEmpty)
                pw.Text('Sanction #: $sanctionNumber'),
            ],
          ),
        ),
        if (logoBytes != null)
          pw.Container(
            width: 80,
            height: 60,
            child: pw.Image(
              pw.MemoryImage(logoBytes!),
              fit: pw.BoxFit.contain,
            ),
          ),
      ],
    );
  }

  pw.Widget _buildBreedHeader({
    required String breedName,
    required String scope,
    required String judgeName,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey300,
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            breedName,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text('Judge: $judgeName'),
          pw.Text(scope),
        ],
      ),
    );
  }

  pw.Widget _buildBreedAwards(List<BreedAward> awards) {
    if (awards.isEmpty) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Breed Awards',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: const ['Award', 'Animal', 'Class', 'Exhibitor'],
          data: awards
              .map((a) => [
                    a.label,
                    a.animal,
                    a.className,
                    a.exhibitor,
                  ])
              .toList(),
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
        ),
      ],
    );
  }

  pw.Widget _buildVarietySection(VarietySection v) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 10),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(6),
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey300,
          ),
          child: pw.Text(
            v.varietyName,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 6),
        _buildVarietyAwards(v),
        pw.SizedBox(height: 6),
        ...v.classes.map(_buildClassSection),
      ],
    );
  }

  pw.Widget _buildVarietyAwards(VarietySection v) {
    if (v.awards.isEmpty) return pw.SizedBox();

    return pw.TableHelper.fromTextArray(
      headers: const ['Award', 'Animal', 'Class', 'Exhibitor'],
      data: v.awards
          .map((a) => [
                a.label,
                a.animal,
                a.className,
                a.exhibitor,
              ])
          .toList(),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.grey700,
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
    );
  }

  pw.Widget _buildClassSection(ClassSection c) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 6),
        pw.Text(
          '${c.className} (${c.entryCount}/${c.exhibitorCount})',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: const ['Place', 'Animal', 'Exhibitor'],
          data: c.entries
              .map((e) => [
                    e.place.toString(),
                    e.animal,
                    e.exhibitor,
                  ])
              .toList(),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.grey200,
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
        ),
      ],
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