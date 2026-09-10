import 'dart:typed_data';

import 'package:supabase/supabase.dart';
import 'package:crypto/crypto.dart';

import 'render_task.dart';

abstract interface class RenderQueue {
  Future<int> recoverStale(int limit);

  Future<List<RenderTask>> claim(String workerId, int batchSize);

  Future<int> countReady();

  Future<RenderArtifact> loadArtifact(String artifactId);

  Future<void> heartbeat(String taskId, String workerId);

  Future<UploadedArtifact> upload(
    RenderArtifact artifact,
    Uint8List bytes, {
    required String checksum,
    required String mimeType,
    required String fileName,
  });

  Future<UploadedArtifact?> recoverUpload(RenderArtifact artifact);

  Future<void> complete(
    RenderTask task,
    RenderArtifact artifact,
    String workerId, {
    required String fileName,
    required int byteSize,
    required String checksum,
    required String mimeType,
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
  Future<UploadedArtifact?> recoverUpload(RenderArtifact artifact) async {
    final bucket = client.storage.from(artifact.storageBucket);
    final FileObjectV2 info;
    try {
      info = await bucket.info(artifact.storagePath);
    } on StorageException catch (error) {
      if (error.statusCode == '404' ||
          (error.statusCode == '400' &&
              error.message.toLowerCase().contains('not found'))) {
        return null;
      }
      rethrow;
    }
    if (info.bucketId != artifact.storageBucket ||
        info.name != artifact.storagePath) {
      throw const RenderFailure.permanent(
        'upload_identity_mismatch',
        'The stored report does not match this artifact.',
      );
    }
    // Custom metadata and bytes are committed together by Storage. There is
    // no upload/receipt window, even if the upload response is lost.
    final receipt = UploadedArtifact.fromMetadata(
      artifact,
      info.metadata ?? const {},
    );
    final bytes = await bucket.download(artifact.storagePath);
    receipt.verify(bytes);
    if (info.size != receipt.byteSize || info.contentType != receipt.mimeType) {
      throw const RenderFailure.permanent(
        'upload_metadata_mismatch',
        'The stored report metadata could not be verified.',
      );
    }
    return receipt;
  }

  @override
  Future<UploadedArtifact> upload(
    RenderArtifact artifact,
    Uint8List bytes, {
    required String checksum,
    required String mimeType,
    required String fileName,
  }) async {
    final receipt = UploadedArtifact(
      fileName: fileName,
      byteSize: bytes.length,
      checksum: checksum,
      mimeType: mimeType,
    );
    receipt.verify(bytes);
    try {
      await client.storage
          .from(artifact.storageBucket)
          .uploadBinary(
            artifact.storagePath,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '31536000, immutable',
              contentType: mimeType,
              upsert: false,
              metadata: receipt.metadata(artifact),
            ),
          );
      return receipt;
    } on StorageException catch (error) {
      if (error.statusCode != '409') rethrow;
      // The first successful immutable object is authoritative. Verify its
      // identity and hash instead of comparing it with a nondeterministic PDF.
      final existing = await recoverUpload(artifact);
      if (existing == null) rethrow;
      return existing;
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
    required String mimeType,
  }) async {
    await client.rpc(
      'complete_report_render_task',
      params: {
        'p_task_id': task.id,
        'p_worker_id': workerId,
        'p_storage_bucket': artifact.storageBucket,
        'p_storage_path': artifact.storagePath,
        'p_file_name': fileName,
        'p_mime_type': mimeType,
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
}

final class UploadedArtifact {
  const UploadedArtifact({
    required this.fileName,
    required this.byteSize,
    required this.checksum,
    required this.mimeType,
  });
  final String fileName;
  final int byteSize;
  final String checksum;
  final String mimeType;

  Map<String, dynamic> metadata(RenderArtifact artifact) => {
    'receipt_version': 1,
    'artifact_id': artifact.id,
    'finalize_run_id': artifact.finalizeRunId,
    'show_id': artifact.showId,
    'generation': artifact.generation,
    'scope_key': artifact.scopeKey,
    'file_name': fileName,
    'byte_size': byteSize,
    'sha256': checksum,
    'mime_type': mimeType,
  };

  factory UploadedArtifact.fromMetadata(
    RenderArtifact artifact,
    Map<String, dynamic> metadata,
  ) {
    if (metadata['receipt_version'] != 1 ||
        metadata['artifact_id'] != artifact.id ||
        metadata['finalize_run_id'] != artifact.finalizeRunId ||
        metadata['show_id'] != artifact.showId ||
        metadata['scope_key'] != artifact.scopeKey ||
        metadata['generation'] != artifact.generation) {
      throw const RenderFailure.permanent(
        'upload_receipt_mismatch',
        'The stored report cannot be verified for this artifact generation.',
      );
    }
    final result = UploadedArtifact(
      fileName: metadata['file_name']?.toString() ?? '',
      byteSize: int.tryParse('${metadata['byte_size']}') ?? 0,
      checksum: metadata['sha256']?.toString() ?? '',
      mimeType: metadata['mime_type']?.toString() ?? '',
    );
    if (result.fileName.isEmpty ||
        result.byteSize <= 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(result.checksum) ||
        !const {
          'application/pdf',
          'text/csv',
          'application/json',
        }.contains(result.mimeType)) {
      throw const RenderFailure.permanent(
        'invalid_upload_receipt',
        'The stored report receipt is incomplete.',
      );
    }
    return result;
  }

  void verify(Uint8List bytes) {
    if (bytes.length != byteSize ||
        sha256.convert(bytes).toString() != checksum) {
      throw const RenderFailure.permanent(
        'upload_checksum_mismatch',
        'The stored report failed its integrity check.',
      );
    }
  }
}
