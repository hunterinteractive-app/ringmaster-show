// lib/screens/admin/closeout/services/sweepstakes_report_service.dart

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/reporting_core/assets/flutter_report_asset_loader.dart';

import '../data/closeout_repository.dart';
import '../data/loaders/sweepstakes_report_loader.dart';
import '../models/base/report_request.dart';
import '../models/clubs/sweepstakes_report_data.dart';
import '../pdf/builders/sweepstakes_report_pdf.dart';

class SweepstakesReportService {
  SweepstakesReportService({
    CloseoutRepository? repo,
    SweepstakesReportLoader? loader,
    SweepstakesReportPdf? pdfBuilder,
  }) : _repo = repo ?? CloseoutRepository(Supabase.instance.client),
       _loader =
           loader ??
           SweepstakesReportLoader(
             repo ?? CloseoutRepository(Supabase.instance.client),
           ),
       _pdfBuilder =
           pdfBuilder ??
           SweepstakesReportPdf(assets: const FlutterReportAssetLoader());

  final CloseoutRepository _repo;
  final SweepstakesReportLoader _loader;
  final SweepstakesReportPdf _pdfBuilder;

  Future<SweepstakesReportResult> generate({
    required String showId,
    required String breedName,
    String? clubName,
    required String scope,
    required String showLetter,
    String? showName,
    String? showDate,
    String? sanctionNumber,
  }) async {
    final request = ReportRequest(
      showId: showId,
      showName: showName,
      showDate: showDate,
      finalizeRunId: 'manual-sweepstakes',
      reportName: 'Sweepstakes Report',
      breedName: breedName,
      clubName: clubName,
      scope: scope,
      showLetter: showLetter,
    );

    final SweepstakesReportData data = await _loader.load(request);

    final file = await _pdfBuilder.buildFile(data, request);

    return SweepstakesReportResult(
      data: data,
      bytes: Uint8List.fromList(file.bytes),
      fileName: file.fileName,
    );
  }

  CloseoutRepository get repo => _repo;
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
