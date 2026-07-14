import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'report_asset_loader.dart';

final class FlutterReportAssetLoader extends ReportAssetLoader {
  const FlutterReportAssetLoader();

  @override
  Future<Uint8List> loadBytes(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.isEmpty) {
        throw ReportAssetException(assetPath, 'bundled asset is empty');
      }
      return bytes;
    } on ReportAssetException {
      rethrow;
    } catch (error) {
      throw ReportAssetException(assetPath, 'bundle load failed: $error');
    }
  }
}
