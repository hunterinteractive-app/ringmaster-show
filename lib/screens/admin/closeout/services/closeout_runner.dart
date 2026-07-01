// lib/screens/admin/closeout/services/closeout_runner.dart

import '../models/base/report_request.dart';
import 'report_engine.dart';
import 'report_upload_service.dart';

class CloseoutRunner {
  CloseoutRunner({required this.engine, required this.uploadService});

  final ReportEngine engine;
  final ReportUploadService uploadService;

  Future<void> generateSingleReport({
    required String showId,
    required String finalizeRunId,
    required String reportName,
    required String artifactId,
    String? breedName,
    String? clubName,
    String? scope,
    String? showLetter,
    String? showName,
    String? showDate,
    String? sanctionNumber,
    String? exhibitorId,
    String? exhibitorName,
    bool hideZeroBalances = true,
    bool isNationalShow = false,
  }) async {
    final request = ReportRequest(
      showId: showId,
      reportName: reportName,
      finalizeRunId: finalizeRunId,
      artifactId: artifactId,
      breedName: breedName,
      clubName: clubName,
      scope: scope,
      showLetter: showLetter,
      showName: showName,
      showDate: showDate,
      sanctionNumber: sanctionNumber,
      exhibitorId: exhibitorId,
      exhibitorName: exhibitorName,
      hideZeroBalances: hideZeroBalances,
      isNationalShow: isNationalShow,
    );

    try {
      final file = await engine.generate(request);

      final storagePath = await uploadService.upload(
        showId: showId,
        showName: showName ?? '',
        artifactId: artifactId,
        file: file,
      );

      await uploadService.markGenerated(
        artifactId: artifactId,
        storagePath: storagePath,
        file: file,
      );
    } catch (e) {
      await uploadService.markFailed(artifactId: artifactId, error: e);
      rethrow;
    }
  }
}
