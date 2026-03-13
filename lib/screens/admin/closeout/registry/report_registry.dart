import '../data/loaders/arba_report_loader.dart';
import '../models/arba/arba_report_data.dart';
import '../pdf/builders/arba_report_pdf.dart';
import 'report_definition.dart';

class ReportRegistry {
  final Map<String, ReportDefinition> definitions;

  ReportRegistry({
    required ArbaReportLoader arbaLoader,
    required ArbaReportPdfBuilder arbaBuilder,
  }) : definitions = {
          'arba_report': ReportDefinition(
            reportName: 'arba_report',
            outputType: 'pdf',
            loader: (req) async => await arbaLoader.load(req),
            builder: (data, req) async =>
                await arbaBuilder.buildFile(data as ArbaReportData, req),
          ),
        };

  ReportDefinition get(String reportName) {
    final definition = definitions[reportName];
    if (definition == null) {
      throw Exception('Unknown report: $reportName');
    }
    return definition;
  }
}