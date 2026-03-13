import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/base/report_file_result.dart';

class ReportUploadService {
  ReportUploadService(this.supabase);

  final SupabaseClient supabase;
  static const bucket = 'show-files';

  Future<String> upload({
    required String showId,
    required ReportFileResult file,
  }) async {
    final path = 'shows/$showId/reports/${file.fileName}';

    await supabase.storage.from(bucket).uploadBinary(
      path,
      Uint8List.fromList(file.bytes),
      fileOptions: FileOptions(
        upsert: true,
        contentType: file.mimeType,
      ),
    );

    return path;
  }

  Future<void> markGenerated({
    required String artifactId,
    required String storagePath,
    required ReportFileResult file,
  }) async {
    await supabase.from('show_report_artifacts').update({
      'artifact_status': 'generated',
      'storage_bucket': bucket,
      'storage_path': storagePath,
      'file_name': file.fileName,
      'mime_type': file.mimeType,
      'file_size_bytes': file.bytes.length,
      'generated_at': DateTime.now().toIso8601String(),
      'error_count': 0,
    }).eq('id', artifactId);
  }

  Future<void> markFailed({
    required String artifactId,
    required Object error,
  }) async {
    await supabase.from('show_report_artifacts').update({
      'artifact_status': 'failed',
      'error_count': 1,
      'metadata': {
        'error_message': error.toString(),
      },
    }).eq('id', artifactId);
  }
}