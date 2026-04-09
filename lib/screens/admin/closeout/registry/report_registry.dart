import '../data/loaders/arba_report_loader.dart';
import '../data/loaders/breed_results_detail_report_loader.dart';
import '../data/loaders/exhibitor_report_loader.dart';
import '../data/loaders/legs_report_loader.dart';
import '../data/loaders/sweepstakes_report_loader.dart';
import '../data/loaders/unpaid_balances_report_loader.dart';

import '../models/arba/arba_report_data.dart';
import '../models/clubs/breed_results_detail_report_data.dart';
import '../models/clubs/sweepstakes_report_data.dart';
import '../models/exhibitor/exhibitor_report_data.dart';
import '../models/legs/legs_certificate_data.dart';
import '../models/unpaid/unpaid_balances_report_data.dart';

import '../pdf/builders/arba_report_pdf.dart';
import '../pdf/builders/breed_results_detail_report_pdf.dart';
import '../pdf/builders/exhibitor_report_pdf.dart';
import '../pdf/builders/legs_report_pdf.dart';
import '../pdf/builders/sweepstakes_report_pdf.dart';
import '../pdf/builders/unpaid_balances_report_pdf.dart';

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
    required BreedResultsDetailReportLoader breedResultsDetailReportLoader,
    required BreedResultsDetailReportPdf breedResultsDetailReportBuilder,
    required UnpaidBalancesReportLoader unpaidBalancesLoader,
    required UnpaidBalancesReportPdfBuilder unpaidBalancesBuilder,
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
                  data as ExhibitorReportData,
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
          'breed_results_detail_report': ReportDefinition(
            reportName: 'breed_results_detail_report',
            outputType: 'pdf',
            loader: (req) async =>
                await breedResultsDetailReportLoader.load(req),
            builder: (data, req) async =>
                await breedResultsDetailReportBuilder.buildFile(
                  data as BreedResultsDetailReportData,
                  req,
                ),
          ),
          'unpaid_balances_report': ReportDefinition(
            reportName: 'unpaid_balances_report',
            outputType: 'pdf',
            loader: (req) async => await unpaidBalancesLoader.load(req),
            builder: (data, req) async =>
                await unpaidBalancesBuilder.buildFile(
                  data as UnpaidBalancesReportData,
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