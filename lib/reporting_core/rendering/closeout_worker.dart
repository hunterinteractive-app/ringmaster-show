import 'dart:async';

import 'artifact_renderer.dart';
import 'render_queue.dart';
import 'render_task.dart';
import 'structured_log.dart';
import 'worker_config.dart';

final class WorkResult {
  const WorkResult({
    required this.claimed,
    required this.completed,
    required this.failed,
    required this.recovered,
    required this.remaining,
  });

  final int claimed;
  final int completed;
  final int failed;
  final int recovered;
  final int remaining;

  Map<String, int> toJson() => {
    'claimed': claimed,
    'completed': completed,
    'failed': failed,
    'recovered': recovered,
    'remaining': remaining,
  };
}

final class CloseoutWorker {
  CloseoutWorker({
    required this.config,
    required this.queue,
    required this.renderer,
    required this.log,
  });

  final WorkerConfig config;
  final RenderQueue queue;
  final ArtifactRenderer renderer;
  final StructuredLog log;
  bool _stopping = false;
  bool _working = false;
  final Completer<void> _stopSignal = Completer<void>();

  bool get isWorking => _working;

  void requestStop() {
    _stopping = true;
    if (!_stopSignal.isCompleted) _stopSignal.complete();
    log.event('shutdown_requested');
  }

  Future<WorkResult> workOnce() async {
    if (_working) {
      throw StateError('A work batch is already running in this process.');
    }
    _working = true;
    try {
      final recovered = await queue.recoverStale(config.batchSize * 2);
      final tasks = await queue.claim(config.workerId, config.batchSize);
      var completed = 0;
      var failed = 0;
      for (
        var start = 0;
        start < tasks.length;
        start += config.maxConcurrentRenders
      ) {
        final batch = tasks
            .skip(start)
            .take(config.maxConcurrentRenders)
            .toList();
        final outcomes = await Future.wait(batch.map(_process));
        completed += outcomes.where((value) => value).length;
        failed += outcomes.where((value) => !value).length;
      }
      return WorkResult(
        claimed: tasks.length,
        completed: completed,
        failed: failed,
        recovered: recovered,
        remaining: await queue.countReady(),
      );
    } finally {
      _working = false;
    }
  }

  Future<void> runContinuous() async {
    while (!_stopping) {
      final result = await workOnce();
      if (result.claimed == 0 && !_stopping) {
        await Future.any<void>([
          Future<void>.delayed(config.pollInterval),
          _stopSignal.future,
        ]);
      }
    }
  }

  Future<bool> _process(RenderTask task) async {
    final stopwatch = Stopwatch()..start();
    Timer? heartbeat;
    RenderArtifact? artifact;
    try {
      artifact = await queue.loadArtifact(task.artifactId);
      artifact.validateFor(task, configuredBucket: config.storageBucket);
      heartbeat = Timer.periodic(const Duration(minutes: 3), (_) {
        unawaited(queue.heartbeat(task.id, config.workerId));
      });
      log.event('render_started', _fields(task, artifact));
      final result = await renderer.render(artifact);
      await queue.heartbeat(task.id, config.workerId);
      final uploadWatch = Stopwatch()..start();
      await queue.upload(artifact, result.bytes, checksum: result.checksum);
      uploadWatch.stop();
      await queue.complete(
        task,
        artifact,
        config.workerId,
        fileName: result.fileName,
        byteSize: result.bytes.length,
        checksum: result.checksum,
      );
      log.event('render_completed', {
        ..._fields(task, artifact),
        'data_load_duration_ms': result.dataLoadDuration.inMilliseconds,
        'render_duration_ms': result.pdfBuildDuration.inMilliseconds,
        'upload_duration_ms': uploadWatch.elapsedMilliseconds,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'byte_size': result.bytes.length,
      });
      return true;
    } catch (error, stackTrace) {
      final failure = error is RenderFailure
          ? error
          : RenderFailure(
              'render_error',
              'The report could not be rendered.',
              '$error\n$stackTrace',
            );
      try {
        await queue.fail(task, config.workerId, failure);
      } catch (recordError) {
        log.event('failure_recording_failed', {
          ..._fields(task, artifact),
          'category': failure.category,
          'error': '$recordError',
        });
      }
      log.event('render_failed', {
        ..._fields(task, artifact),
        'category': failure.category,
        'retryable': failure.retryable,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      return false;
    } finally {
      heartbeat?.cancel();
    }
  }

  Map<String, Object?> _fields(RenderTask task, RenderArtifact? artifact) => {
    'task_id': task.id,
    'artifact_id': task.artifactId,
    'report_type': artifact?.reportName ?? task.payload['report_name'],
    'finalize_run_id': task.finalizeRunId,
    'scope_key': task.scopeKey,
    'attempt': task.attemptCount,
    'claim_time': task.claimedAt?.toUtc().toIso8601String(),
  };
}
