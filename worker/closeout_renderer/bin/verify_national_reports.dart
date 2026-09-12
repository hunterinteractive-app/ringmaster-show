// Targeted regression against a retained, synthetic, loopback-only convention.
import 'dart:convert';
import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/rendering/artifact_renderer.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_task.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final url = env['SUPABASE_URL'] ?? '';
  final uri = Uri.parse(url);
  if (uri.scheme != 'http' || !['localhost', '127.0.0.1'].contains(uri.host)) {
    throw StateError('A local loopback API is required.');
  }
  final client = SupabaseClient(url, env['SUPABASE_SERVICE_ROLE_KEY']!);
  const showId = '95000000-0000-0000-0000-000000000001';
  final output = Directory(args.first)..createSync(recursive: true);
  try {
    final show = await client
        .from('shows')
        .select('is_test')
        .eq('id', showId)
        .single();
    if (show['is_test'] != true) throw StateError('Synthetic show required.');
    final renderer = await RegistryArtifactRenderer.create(
      client: client,
      assets: FileSystemReportAssetLoader(Directory(env['ASSET_ROOT']!)),
    );
    var query = client
        .from('show_report_artifacts')
        .select()
        .eq('show_id', showId)
        .eq('is_current', true)
        .inFilter('report_name', [
          'arba_report',
          'breed_results_detail_report',
          'judge_report',
          'paid_exhibitor_report',
          'unpaid_balances_report',
        ]);
    final runArg = args
        .where((a) => a.startsWith('--finalize-run-id='))
        .firstOrNull;
    if (runArg != null) {
      query = query.eq(
        'finalize_run_id',
        runArg.substring('--finalize-run-id='.length),
      );
    }
    final artifacts = await query.order('id');
    final onlyArg = args.where((a) => a.startsWith('--only=')).firstOrNull;
    final only = onlyArg?.substring(7).split(',').toSet();
    final prior = File('${output.path}/renders.json');
    final results = only != null && prior.existsSync()
        ? List<Map<String, dynamic>>.from(
            jsonDecode(prior.readAsStringSync()),
          ).where((r) => !only.contains(r['report_name'])).toList()
        : <Map<String, dynamic>>[];
    for (final row in artifacts) {
      if (only != null && !only.contains(row['report_name'])) continue;
      if (args.contains('--smoke') &&
          row['report_name'] == 'breed_results_detail_report' &&
          !['American', 'Mini Lop'].contains(row['metadata']['breed_name'])) {
        continue;
      }
      final watch = Stopwatch()..start();
      try {
        final result = await renderer.render(RenderArtifact.fromJson(row));
        File('${output.path}/${row['id']}.pdf').writeAsBytesSync(result.bytes);
        results.add({
          ...row,
          'verification_ms': watch.elapsedMilliseconds,
          'verified_render': true,
          'data_load_ms': result.dataLoadDuration.inMilliseconds,
          'pdf_build_ms': result.pdfBuildDuration.inMilliseconds,
        });
        stdout.writeln(
          jsonEncode({
            'report': row['report_name'],
            'breed': row['metadata']['breed_name'],
            'status': 'passed',
            'ms': watch.elapsedMilliseconds,
          }),
        );
      } catch (e) {
        results.add({...row, 'verified_render': false, 'error': e.toString()});
        stdout.writeln(
          jsonEncode({
            'report': row['report_name'],
            'status': 'failed',
            'error': e.toString(),
          }),
        );
      }
      File(
        '${output.path}/renders.json',
      ).writeAsStringSync(jsonEncode(results));
    }
    if (results.isEmpty || results.any((r) => r['verified_render'] != true)) {
      exitCode = 1;
    }
  } finally {
    await client.dispose();
  }
}
