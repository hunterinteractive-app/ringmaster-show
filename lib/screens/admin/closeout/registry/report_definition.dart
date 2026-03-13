import '../models/base/report_request.dart';
import '../models/base/report_file_result.dart';

typedef ReportLoader<T> = Future<T> Function(ReportRequest request);
typedef ReportBuilder<T> = Future<ReportFileResult> Function(T data, ReportRequest request);

class ReportDefinition<T> {
  ReportDefinition({
    required this.reportName,
    required this.outputType,
    required this.loader,
    required this.builder,
  });

  final String reportName;
  final String outputType; // pdf / csv
  final ReportLoader<T> loader;
  final ReportBuilder<T> builder;
}