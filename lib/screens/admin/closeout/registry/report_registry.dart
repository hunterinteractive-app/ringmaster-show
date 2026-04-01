import '../data/loaders/arba_report_loader.dart';
import '../data/loaders/exhibitor_report_loader.dart';
import '../data/loaders/legs_report_loader.dart';
import '../data/loaders/sweepstakes_report_loader.dart';

import '../models/arba/arba_report_data.dart';
import '../models/exhibitor/exhibitor_report_data.dart';
import '../models/legs/legs_certificate_data.dart';
import '../models/clubs/sweepstakes_report_data.dart';

import '../pdf/builders/arba_report_pdf.dart';
import '../pdf/builders/exhibitor_report_pdf.dart';
import '../pdf/builders/legs_report_pdf.dart';
import '../pdf/builders/sweepstakes_report_pdf.dart';

import 'report_definition.dart';

class ReportRegistry {
  final Map<String, ReportDefinition> definitions;

  ReportRegistry({
    required ArbaReportLoader arbaLoader,
    required ArbaReportPdfBuilder arbaBuilder,
    required LegsReportLoader legsLoader,
    required LegsReportPdfBuilder legsBuilder,
    required ExhibitorReportLoader exhibitorLoader,
    required ExhibitorReportPdfBuilder exhibitorBuilder,
    required SweepstakesReportLoader sweepstakesLoader,
    required SweepstakesReportPdf sweepstakesBuilder,
  }) : definitions = {
          'arba_report': ReportDefinition(
            reportName: 'arba_report',
            outputType: 'pdf',
            loader: (req) async => await arbaLoader.load(req),
            builder: (data, req) async =>
                await arbaBuilder.buildFile(data as ArbaReportData, req),
          ),
          'legs': ReportDefinition(
            reportName: 'legs',
            outputType: 'pdf',
            loader: (req) async => await legsLoader.load(req),
            builder: (data, req) async =>
                await legsBuilder.buildFile(
                  data as List<LegsCertificateData>,
                  req,
                ),
          ),
          'exhibitor_report': ReportDefinition(
            reportName: 'exhibitor_report',
            outputType: 'pdf',
            loader: (req) async => await exhibitorLoader.load(req),
            builder: (data, req) async =>
                await exhibitorBuilder.buildFile(
                  data as List<ExhibitorReportData>,
                  req,
                ),
          ),
          'sweepstakes_report': ReportDefinition(
            reportName: 'sweepstakes_report',
            outputType: 'pdf',
            loader: (req) async => await sweepstakesLoader.load(req),
            builder: (data, req) async =>
                await sweepstakesBuilder.buildFile(
                  data as SweepstakesReportData,
                  req,
                ),
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