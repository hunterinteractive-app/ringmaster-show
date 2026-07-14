import 'dart:io';
import 'dart:typed_data';

import 'report_asset_loader.dart';

final class FileSystemReportAssetLoader extends ReportAssetLoader {
  FileSystemReportAssetLoader(this.assetRoot);

  final Directory assetRoot;

  @override
  Future<Uint8List> loadBytes(String assetPath) async {
    final normalized = assetPath.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.split('/').contains('..')) {
      throw ReportAssetException(assetPath, 'path is not container-relative');
    }

    final relativePath = normalized.startsWith('assets/')
        ? normalized.substring('assets/'.length)
        : normalized;
    final file = File('${assetRoot.path}/$relativePath');
    if (!await file.exists()) {
      throw ReportAssetException(
        assetPath,
        'file does not exist at ${file.path}',
      );
    }
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw ReportAssetException(assetPath, 'file is empty at ${file.path}');
      }
      return bytes;
    } on ReportAssetException {
      rethrow;
    } catch (error) {
      throw ReportAssetException(
        assetPath,
        'failed reading ${file.path}: $error',
      );
    }
  }
}
