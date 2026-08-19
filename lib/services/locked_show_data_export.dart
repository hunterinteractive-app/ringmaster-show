import 'dart:typed_data';

import 'package:ringmaster_show/utils/file_download.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Downloads the locked-show archive using the authenticated Functions client.
///
/// Keeping this on the client transport (rather than creating a raw browser
/// XHR) ensures the request carries the same valid session and Supabase API
/// headers as the rest of Closeout.
Future<void> downloadLockedShowDataExport({
  required String showId,
  required String showName,
}) async {
  final response = await Supabase.instance.client.functions.invoke(
    'export-locked-show-data',
    body: {'show_id': showId},
  );
  final data = response.data;
  final bytes = switch (data) {
    Uint8List value => value,
    List<int> value => Uint8List.fromList(value),
    _ => throw StateError(
      'The locked-show export returned an unexpected response '
      '(${data.runtimeType}).',
    ),
  };
  final safeShowName = showName
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  await downloadFileBytes(
    bytes,
    fileName:
        '${safeShowName}_locked_show_export_${DateTime.now().millisecondsSinceEpoch}.zip',
    mimeType: 'application/zip',
  );
}
