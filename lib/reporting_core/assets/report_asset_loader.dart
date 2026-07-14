import 'dart:typed_data';

abstract class ReportAssetLoader {
  const ReportAssetLoader();

  Future<Uint8List> loadBytes(String assetPath);

  Future<ByteData> loadByteData(String assetPath) async {
    return ByteData.sublistView(await loadBytes(assetPath));
  }
}

final class ReportAssetException implements Exception {
  const ReportAssetException(this.assetPath, this.reason);

  final String assetPath;
  final String reason;

  @override
  String toString() =>
      'Required report asset "$assetPath" is unavailable: $reason';
}
