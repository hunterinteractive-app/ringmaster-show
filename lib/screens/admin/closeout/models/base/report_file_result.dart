class ReportFileResult {
  const ReportFileResult({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    this.metadata = const {},
  });

  final String fileName;
  final String mimeType;
  final List<int> bytes;
  final Map<String, dynamic> metadata;
}