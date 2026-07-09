import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/base/report_file_result.dart';

class ReportUploadService {
  ReportUploadService(this.supabase);

  final SupabaseClient supabase;
  static const bucket = 'show-files';

  Future<String> upload({
    required String showId,
    required String showName,
    required String artifactId,
    required ReportFileResult file,
  }) async {
    final safeShowName = showName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    final showFolder = safeShowName.isNotEmpty ? safeShowName : showId;
    final versionFolder = _buildReportVersionFolder();

    // Determine version number (V1, V2, etc.) based on existing files for today
    final tempBase = 'shows/$showFolder/reports/versions/$versionFolder/';
    final existing = await supabase.storage.from(bucket).list(path: tempBase);

    final version = existing.length + 1;
    final versionLabel = 'V$version';
    final baseFolder =
        'shows/$showFolder/reports/versions/${versionFolder}_$versionLabel/';

    // Keep each generation in its own timestamped folder so older reports are preserved.
    // Example:
    // shows/my_show/reports/versions/2026-05-26_19-42-08/my_show_arba_report_open_c.pdf
    final filePrefix = safeShowName.isEmpty ? '' : '${safeShowName}_';
    final path = '$baseFolder$filePrefix${file.fileName}';

    final bytes = Uint8List.fromList(file.bytes);
    debugPrint(
      '[ReportUploadService] upload show=$showId artifact=$artifactId '
      'path=$path bytes=${bytes.length}',
    );

    await supabase.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: file.mimeType),
        );

    return path;
  }

  String _buildReportVersionFolder() {
    final now = DateTime.now().toUtc();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    // final second = now.second.toString().padLeft(2, '0');

    return '$year-$month-${day}_$hour-$minute';
  }

  Future<void> markGenerated({
    required String artifactId,
    required String storagePath,
    required ReportFileResult file,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await supabase
        .from('show_report_artifacts')
        .update({
          'artifact_status': 'generated',
          'storage_bucket': bucket,
          'storage_path': storagePath,
          'file_name': file.fileName,
          'mime_type': file.mimeType,
          'file_size_bytes': file.bytes.length,
          'generated_at': now,
          'superseded_at': null,
          'error_count': 0,
          'warning_count': 0,
        })
        .eq('id', artifactId);
    debugPrint(
      '[ReportUploadService] markGenerated artifact=$artifactId '
      'file=${file.fileName} storagePath=$storagePath',
    );
  }

  Future<void> markFailed({
    required String artifactId,
    required Object error,
  }) async {
    final existing = await supabase
        .from('show_report_artifacts')
        .select('metadata')
        .eq('id', artifactId)
        .maybeSingle();

    final currentMetadata = existing != null && existing['metadata'] is Map
        ? Map<String, dynamic>.from(existing['metadata'] as Map)
        : <String, dynamic>{};

    currentMetadata['error_message'] = error.toString();
    debugPrint(
      '[ReportUploadService] markFailed artifact=$artifactId error=$error',
    );

    await supabase
        .from('show_report_artifacts')
        .update({
          'artifact_status': 'failed',
          'error_count': 1,
          'metadata': currentMetadata,
        })
        .eq('id', artifactId);
  }
}
