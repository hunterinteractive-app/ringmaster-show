// lib/screens/admin/closeout/services/closeout_runner.dart

import 'package:flutter/foundation.dart';

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
    String? species,
    String? scope,
    String? showLetter,
    String? scopeLabel,
    String? sectionId,
    List<String>? sectionIds,
    String? showName,
    String? showDate,
    String? sanctionNumber,
    String? exhibitorId,
    String? exhibitorName,
    bool hideZeroBalances = true,
    bool isNationalShow = false,
  }) async {
    final resolvedSpecies =
        _normalizeSpecies(species) ?? await _loadArtifactSpecies(artifactId);

    final request = ReportRequest(
      showId: showId,
      reportName: reportName,
      finalizeRunId: finalizeRunId,
      artifactId: artifactId,
      breedName: breedName,
      clubName: clubName,
      species: resolvedSpecies,
      scope: scope,
      showLetter: showLetter,
      scopeLabel: scopeLabel,
      sectionId: sectionId,
      sectionIds: sectionIds,
      showName: showName,
      showDate: showDate,
      sanctionNumber: sanctionNumber,
      exhibitorId: exhibitorId,
      exhibitorName: exhibitorName,
      hideZeroBalances: hideZeroBalances,
      isNationalShow: isNationalShow,
    );

    try {
      debugPrint(
        '[CloseoutRunner] Generating $reportName artifact=$artifactId '
        'show=$showId scopeLabel=${scopeLabel ?? ''} '
        'sectionIds=${sectionIds?.join(',') ?? ''}',
      );
      final file = await engine.generate(request);
      debugPrint(
        '[CloseoutRunner] Built $reportName artifact=$artifactId '
        'file=${file.fileName} bytes=${file.bytes.length}',
      );

      final storagePath = await uploadService.upload(
        showId: showId,
        showName: showName ?? '',
        finalizeRunId: finalizeRunId,
        artifactId: artifactId,
        file: file,
      );

      await uploadService.markGenerated(
        artifactId: artifactId,
        storagePath: storagePath,
        file: file,
      );
      debugPrint(
        '[CloseoutRunner] Generated $reportName artifact=$artifactId '
        'storagePath=$storagePath',
      );
    } catch (e) {
      debugPrint(
        '[CloseoutRunner] Failed $reportName artifact=$artifactId: $e',
      );
      await uploadService.markFailed(artifactId: artifactId, error: e);
      rethrow;
    }
  }

  Future<String?> _loadArtifactSpecies(String artifactId) async {
    try {
      final row = await uploadService.supabase
          .from('show_report_artifacts')
          .select('metadata')
          .eq('id', artifactId)
          .maybeSingle();

      if (row == null || row['metadata'] is! Map) return null;

      final metadata = Map<String, dynamic>.from(row['metadata'] as Map);
      return _normalizeSpecies((metadata['species'] ?? '').toString());
    } catch (_) {
      return null;
    }
  }

  String? _normalizeSpecies(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized == 'rabbit' || normalized == 'cavy' ? normalized : null;
  }
}
