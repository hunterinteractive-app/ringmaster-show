import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/rendering/artifact_renderer.dart';
import 'package:ringmaster_show/reporting_core/rendering/closeout_worker.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_queue.dart';
import 'package:ringmaster_show/reporting_core/rendering/structured_log.dart';
import 'package:ringmaster_show/reporting_core/rendering/worker_config.dart';
import 'package:ringmaster_show/reporting_core/rendering/worker_http.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:supabase/supabase.dart';

Future<void> main(List<String> arguments) async {
  final config = WorkerConfig.fromEnvironment(arguments: arguments);
  final log = StructuredLog(workerId: config.workerId);
  if (config.dryRun) {
    final assets = FileSystemReportAssetLoader(config.assetRoot);
    for (final path in _requiredAssets) {
      await assets.loadBytes(path);
    }
    stdout.writeln(
      jsonEncode({
        'status': 'dry_run_ok',
        'database_writes': 0,
        'storage_writes': 0,
        'asset_root': config.assetRoot.path,
        'assets_checked': _requiredAssets.length,
      }),
    );
    return;
  }

  final client = SupabaseClient(
    config.supabaseUrl!,
    config.serviceRoleKey!,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final assets = FileSystemReportAssetLoader(config.assetRoot);
  final renderer = await RegistryArtifactRenderer.create(
    client: client,
    assets: assets,
  );
  final worker = CloseoutWorker(
    config: config,
    queue: SupabaseRenderQueue(client),
    renderer: renderer,
    log: log,
  );

  final shutdown = Completer<void>();
  late final StreamSubscription<ProcessSignal> sigterm;
  late final StreamSubscription<ProcessSignal> sigint;
  void stop(ProcessSignal signal) {
    worker.requestStop();
    if (!shutdown.isCompleted) shutdown.complete();
  }

  sigterm = ProcessSignal.sigterm.watch().listen(stop);
  sigint = ProcessSignal.sigint.watch().listen(stop);
  try {
    if (arguments.contains('--serve')) {
      final server = await shelf_io.serve(
        buildWorkerHandler(worker, config),
        InternetAddress.anyIPv4,
        config.port,
      );
      log.event('http_started', {
        'port': server.port,
        'version': config.buildVersion,
      });
      await shutdown.future;
      await server.close(force: false);
    } else if (config.continuous) {
      await worker.runContinuous();
    } else {
      final result = await worker.workOnce();
      stdout.writeln(jsonEncode(result.toJson()));
    }
  } finally {
    await sigterm.cancel();
    await sigint.cancel();
    client.dispose();
  }
}

const _requiredAssets = <String>[
  'assets/fonts/NotoSans-Regular.ttf',
  'assets/fonts/NotoSans-Bold.ttf',
  'assets/fonts/NotoSans-Italic.ttf',
  'assets/fonts/NotoSans-BoldItalic.ttf',
  'assets/images/arba_logo.png',
  'assets/images/ringmaster_show_logo.png',
  'assets/images/Grand_Champion.png',
  'assets/images/BIS_Award.png',
];
