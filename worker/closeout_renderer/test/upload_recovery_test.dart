import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_queue.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_task.dart';
import 'package:test/test.dart';

const artifact = RenderArtifact(
  id: 'artifact',
  showId: 'show',
  finalizeRunId: 'run',
  scopeKey: 'scope',
  reportName: 'checkin_sheet',
  sectionIds: ['section'],
  metadata: {},
  storageBucket: 'reports',
  storagePath: 'immutable/artifact/generation-1/report.pdf',
  generation: 1,
);
final bytes = Uint8List.fromList(utf8.encode('%PDF original immutable report'));
UploadedArtifact receipt() => UploadedArtifact(
  fileName: 'original.pdf',
  byteSize: bytes.length,
  checksum: sha256.convert(bytes).toString(),
  mimeType: 'application/pdf',
);

void main() {
  test(
    'a 409 returns the verified first upload despite different rerendered bytes',
    () async {
      var uploads = 0;
      final client = SupabaseClient(
        'http://fixture.invalid',
        'key',
        httpClient: MockClient((req) async {
          if (req.method == 'POST') {
            uploads++;
            expect(req.headers['x-upsert'], 'false');
            return http.Response(
              '{"statusCode":"409","message":"Duplicate"}',
              409,
              request: req,
            );
          }
          if (req.url.path.contains('/info/')) {
            return http.Response(
              jsonEncode({
                'id': 'object',
                'version': 'v1',
                'name': artifact.storagePath,
                'bucket_id': artifact.storageBucket,
                'created_at': '2026-09-10',
                'size': bytes.length,
                'content_type': 'application/pdf',
                'metadata': receipt().metadata(artifact),
              }),
              200,
              request: req,
            );
          }
          return http.Response.bytes(bytes, 200, request: req);
        }),
      );
      addTearDown(client.dispose);
      final changed = Uint8List.fromList(utf8.encode('%PDF changed timestamp'));
      final stored = await SupabaseRenderQueue(client).upload(
        artifact,
        changed,
        checksum: sha256.convert(changed).toString(),
        mimeType: 'application/pdf',
        fileName: 'new.pdf',
      );
      expect(stored.checksum, receipt().checksum);
      expect(stored.fileName, 'original.pdf');
      expect(uploads, 1);
    },
  );
  test('a missing object is the only recoverable absence', () async {
    final client = SupabaseClient(
      'http://fixture.invalid',
      'key',
      httpClient: MockClient(
        (req) async => http.Response(
          '{"statusCode":"404","message":"Object not found"}',
          404,
          request: req,
        ),
      ),
    );
    addTearDown(client.dispose);
    expect(await SupabaseRenderQueue(client).recoverUpload(artifact), isNull);
  });
  test(
    'storage authorization failures are never treated as missing files',
    () async {
      final client = SupabaseClient(
        'http://fixture.invalid',
        'key',
        httpClient: MockClient(
          (req) async => http.Response(
            '{"statusCode":"403","message":"Forbidden"}',
            403,
            request: req,
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseRenderQueue(client).recoverUpload(artifact),
        throwsA(isA<StorageException>()),
      );
    },
  );
  for (final field in [
    'artifact_id',
    'finalize_run_id',
    'show_id',
    'scope_key',
    'generation',
    'receipt_version',
  ]) {
    test('rejects a receipt with different $field', () {
      final metadata = receipt().metadata(artifact)..[field] = 'wrong';
      expect(
        () => UploadedArtifact.fromMetadata(artifact, metadata),
        throwsA(isA<RenderFailure>()),
      );
    });
  }
  test('detects corrupt or truncated bytes', () {
    expect(
      () => receipt().verify(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<RenderFailure>()),
    );
  });
  test(
    'unverifiable old objects fail visibly instead of being overwritten',
    () {
      expect(
        () => UploadedArtifact.fromMetadata(artifact, {}),
        throwsA(isA<RenderFailure>()),
      );
    },
  );
}
