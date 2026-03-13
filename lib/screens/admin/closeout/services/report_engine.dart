import '../models/base/report_file_result.dart';
import '../models/base/report_request.dart';
import '../registry/report_registry.dart';

class ReportEngine {
  final ReportRegistry registry;

  ReportEngine(this.registry);

  Future<ReportFileResult> generate(ReportRequest request) async {
    final definition = registry.get(request.reportName);
    final data = await definition.loader(request);
    return await definition.builder(data, request);
  }
}