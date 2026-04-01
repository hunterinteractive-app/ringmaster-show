import '../models/base/report_request.dart';
import 'report_engine.dart';
import 'report_upload_service.dart';

class CloseoutRunner {
  CloseoutRunner({
    required this.engine,
    required this.uploadService,
  });

  final ReportEngine engine;
  final ReportUploadService uploadService;

  Future<void> generateSingleReport({
    required String showId,
    required String finalizeRunId,
    required String reportName,
    required String artifactId,
    String? breedName,
    String? scope,
    String? showName,
    String? showDate,
    String? sanctionNumber,
  }) async {
    final request = ReportRequest(
      showId: showId,
      finalizeRunId: finalizeRunId,
      reportName: reportName,
      artifactId: artifactId,
      breedName: breedName,
      scope: scope,
      showName: showName,
      showDate: showDate,
      sanctionNumber: sanctionNumber,
    );

    try {
      final file = await engine.generate(request);
      final storagePath = await uploadService.upload(
        showId: showId,
        file: file,
      );

      await uploadService.markGenerated(
        artifactId: artifactId,
        storagePath: storagePath,
        file: file,
      );
    } catch (e) {
      await uploadService.markFailed(
        artifactId: artifactId,
        error: e,
      );
      rethrow;
    }
  }
}