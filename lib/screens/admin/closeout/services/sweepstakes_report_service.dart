import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../data/loaders/sweepstakes_report_loader.dart';
import '../models/clubs/sweepstakes_report_data.dart';
import '../pdf/builders/sweepstakes_report_pdf.dart';

class SweepstakesReportService {
  SweepstakesReportService({
    SweepstakesReportLoader? loader,
  }) : _loader = loader ?? SweepstakesReportLoader();

  final SweepstakesReportLoader _loader;

  Future<SweepstakesReportResult> generate({
    required String showId,
    required String breedName,
    required String scope,
    String? showName,
    String? showDate,
    String? sanctionNumber,
  }) async {
    final SweepstakesReportData data = await _loader.load(
      showId: showId,
      breedName: breedName,
      scope: scope,
    );

    final pw.Document pdf = await SweepstakesReportPdf.build(
      data: data,
      showName: showName,
      showDate: showDate,
      sanctionNumber: sanctionNumber,
    );

    final Uint8List bytes = await pdf.save();

    return SweepstakesReportResult(
      data: data,
      bytes: bytes,
      fileName: _buildFileName(
        breedName: breedName,
        scope: scope,
        showName: showName,
      ),
    );
  }

  String _buildFileName({
    required String breedName,
    required String scope,
    String? showName,
  }) {
    String clean(String input) {
      return input
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
    }

    final showPart = clean(showName ?? 'show');
    final breedPart = clean(breedName);
    final scopePart = clean(scope.toLowerCase());

    return '${showPart}_${breedPart}_${scopePart}_sweepstakes.pdf';
  }
}

class SweepstakesReportResult {
  const SweepstakesReportResult({
    required this.data,
    required this.bytes,
    required this.fileName,
  });

  final SweepstakesReportData data;
  final Uint8List bytes;
  final String fileName;
}