import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import 'render_task.dart';

abstract interface class RenderQueue {
  Future<int> recoverStale(int limit);

  Future<List<RenderTask>> claim(String workerId, int batchSize);

  Future<int> countReady();

  Future<RenderArtifact> loadArtifact(String artifactId);

  Future<void> heartbeat(String taskId, String workerId);

  Future<void> upload(
    RenderArtifact artifact,
    Uint8List bytes, {
    required String checksum,
  });

  Future<void> complete(
    RenderTask task,
    RenderArtifact artifact,
    String workerId, {
    required String fileName,
    required int byteSize,
    required String checksum,
  });

  Future<void> fail(RenderTask task, String workerId, RenderFailure failure);
}

final class SupabaseRenderQueue implements RenderQueue {
  SupabaseRenderQueue(this.client);

  final SupabaseClient client;

  @override
  Future<int> recoverStale(int limit) async {
    final value = await client.rpc(
      'recover_stale_report_render_tasks',
      params: {'p_limit': limit},
    );
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  @override
  Future<List<RenderTask>> claim(String workerId, int batchSize) async {
    final rows = await client.rpc(
      'claim_report_render_tasks',
      params: {'p_worker_id': workerId, 'p_batch_size': batchSize},
    );
    return (rows as List? ?? const [])
        .map(
          (row) => RenderTask.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<int> countReady() async {
    final value = await client.rpc('count_report_render_tasks_ready');
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  @override
  Future<RenderArtifact> loadArtifact(String artifactId) async {
    final row = await client
        .from('show_report_artifacts')
        .select(
          'id,show_id,finalize_run_id,scope_key,report_name,section_ids,metadata,storage_bucket,storage_path,generation',
        )
        .eq('id', artifactId)
        .single();
    return RenderArtifact.fromJson(Map<String, dynamic>.from(row));
  }

  @override
  Future<void> heartbeat(String taskId, String workerId) async {
    await client.rpc(
      'heartbeat_report_render_task',
      params: {
        'p_task_id': taskId,
        'p_worker_id': workerId,
        'p_lease_seconds': 600,
      },
    );
  }

  @override
  Future<void> upload(
    RenderArtifact artifact,
    Uint8List bytes, {
    required String checksum,
  }) async {
    final bucket = client.storage.from(artifact.storageBucket);
    try {
      await bucket.uploadBinary(
        artifact.storagePath,
        bytes,
        fileOptions: const FileOptions(
          cacheControl: '31536000, immutable',
          contentType: 'application/pdf',
          upsert: false,
        ),
      );
    } on StorageException catch (error) {
      // Completion can fail after a successful immutable upload. A retry may
      // reuse that exact object only when its bytes match.
      if (error.statusCode != '409') rethrow;
      final existing = await bucket.download(artifact.storagePath);
      if (!_sameBytes(existing, bytes)) rethrow;
    }
  }

  @override
  Future<void> complete(
    RenderTask task,
    RenderArtifact artifact,
    String workerId, {
    required String fileName,
    required int byteSize,
    required String checksum,
  }) async {
    await client.rpc(
      'complete_report_render_task',
      params: {
        'p_task_id': task.id,
        'p_worker_id': workerId,
        'p_storage_bucket': artifact.storageBucket,
        'p_storage_path': artifact.storagePath,
        'p_file_name': fileName,
        'p_mime_type': 'application/pdf',
        'p_file_size_bytes': byteSize,
        'p_file_hash_sha256': checksum,
      },
    );
  }

  @override
  Future<void> fail(
    RenderTask task,
    String workerId,
    RenderFailure failure,
  ) async {
    await client.rpc(
      'fail_report_render_task',
      params: {
        'p_task_id': task.id,
        'p_worker_id': workerId,
        'p_error_category': failure.category,
        'p_user_message': failure.userMessage,
        'p_diagnostic': failure.diagnostic,
        'p_retryable': failure.retryable,
      },
    );
  }

  bool _sameBytes(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
