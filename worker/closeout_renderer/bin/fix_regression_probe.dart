// Focused regression checks against preserved local synthetic data. No task
// claims, finalize calls, deliveries, or payment providers are involved.
import 'dart:convert';
import 'dart:io';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/rendering/artifact_renderer.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_queue.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_task.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/results_entry_reader.dart';
import 'package:supabase/supabase.dart';

Future<void> main() async {
  final url = Uri.parse(Platform.environment['SUPABASE_URL']!);
  if (url.scheme != 'http' || !{'127.0.0.1', 'localhost'}.contains(url.host)) {
    throw StateError('Only a loopback synthetic lab is allowed.');
  }
  const show = '95000000-0000-0000-0000-000000000001';
  const section = '95100000-0000-0000-0000-000000000001';
  final client = SupabaseClient(
    url.toString(),
    Platform.environment['SUPABASE_SERVICE_ROLE_KEY']!,
  );
  final out = <String, Object?>{};
  String? temporaryPath;
  String? bucket;
  var ownsTemporaryObject = false;
  try {
    final rows = await loadResultsEntryRows(
      client,
      params: {'p_show_id': show, 'p_section_id': section},
    );
    if (rows.length != 18867) {
      throw StateError('Incomplete Open entry rows: ${rows.length}');
    }
    final miniRex = await loadResultsEntryRows(
      client,
      params: {
        'p_show_id': show,
        'p_section_id': section,
        'p_breed': 'Mini Rex',
      },
    );
    if (miniRex.length != rows.where((r) => r['breed'] == 'Mini Rex').length) {
      throw StateError('Incomplete QR breed');
    }
    out['open_rows'] = rows.length;
    out['qr_mini_rex_rows'] = miniRex.length;
    final queue = SupabaseRenderQueue(client);
    final renderer = await RegistryArtifactRenderer.create(
      client: client,
      assets: FileSystemReportAssetLoader(
        Directory(Platform.environment['ASSET_ROOT']!),
      ),
    );
    final timings = <Map<String, Object?>>[];
    RenderArtifact? checkin;
    for (final name in [
      'details_by_breed',
      'exhibitor_report',
      'legs',
      'exhibitor_report',
      'checkin_sheet',
    ]) {
      final found = await client
          .from('show_report_artifacts')
          .select('id')
          .eq('show_id', show)
          .eq('report_name', name)
          .contains('section_ids', [section])
          .order('id')
          .limit(1)
          .single();
      final artifact = await queue.loadArtifact(found['id'] as String);
      final result = await renderer.render(artifact);
      timings.add({
        'type': name,
        'load_ms': result.dataLoadDuration.inMilliseconds,
        'build_ms': result.pdfBuildDuration.inMilliseconds,
        'bytes': result.bytes.length,
      });
      if (name == 'checkin_sheet') checkin = artifact;
      if (name == 'details_by_breed') {
        await File(
          '/tmp/ringmaster-fixed-details.pdf',
        ).writeAsBytes(result.bytes);
      }
    }
    out['renders'] = timings;
    final original = checkin!;
    // A separate object owned exclusively by this probe; remove it in finally.
    final id =
        '95999999-0000-0000-0000-${(DateTime.now().microsecondsSinceEpoch % 1000000000000).toString().padLeft(12, '0')}';
    temporaryPath =
        'shows/$show/reports/versions/${original.finalizeRunId}/artifacts/$id/generation-1/report.pdf';
    bucket = original.storageBucket;
    final artifact = RenderArtifact(
      id: id,
      showId: show,
      finalizeRunId: original.finalizeRunId,
      scopeKey: original.scopeKey,
      reportName: original.reportName,
      sectionIds: original.sectionIds,
      metadata: original.metadata,
      storageBucket: bucket,
      storagePath: temporaryPath,
      generation: 1,
    );
    if (await queue.recoverUpload(artifact) != null) {
      throw StateError('Temporary object already exists');
    }
    ownsTemporaryObject = true;
    final first = await renderer.render(artifact);
    final receipt = await queue.upload(
      artifact,
      first.bytes,
      checksum: first.checksum,
      mimeType: first.mimeType,
      fileName: first.fileName,
    );
    final recovered = await queue.recoverUpload(artifact);
    if (recovered?.checksum != receipt.checksum) {
      throw StateError('Upload receipt did not recover');
    }
    final second = await renderer.render(artifact);
    final replay = await queue.upload(
      artifact,
      second.bytes,
      checksum: second.checksum,
      mimeType: second.mimeType,
      fileName: second.fileName,
    );
    if (replay.checksum != receipt.checksum) {
      throw StateError('First immutable upload was not preserved');
    }
    out['upload_recovered'] = true;
    out['duplicate_upload_preserved_first'] = true;
    out['rerender_bytes_differ'] = first.checksum != second.checksum;
    out['ok'] = true;
  } finally {
    if (ownsTemporaryObject && temporaryPath != null && bucket != null) {
      await client.storage.from(bucket).remove([temporaryPath]);
    }
    await client.dispose();
  }
  stdout.writeln(jsonEncode(out));
}
