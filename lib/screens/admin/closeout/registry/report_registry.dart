// lib/screens/admin/closeout/registry/report_registry.dart

import '../data/loaders/arba_report_loader.dart';
import '../data/loaders/breed_results_detail_report_loader.dart';
import '../data/loaders/entered_exhibitors_contact_report_loader.dart';
import '../data/loaders/exhibitor_report_loader.dart';
import '../data/loaders/judge_report_loader.dart';
import '../data/loaders/legs_report_loader.dart';
import '../data/loaders/paid_exhibitor_report_loader.dart';
import '../data/loaders/ribbon_payout_report_loader.dart';
import '../data/loaders/sweepstakes_report_loader.dart';
import '../data/loaders/unpaid_balances_report_loader.dart';

import '../models/arba/arba_report_data.dart';
import '../models/clubs/breed_results_detail_report_data.dart';
import '../models/clubs/sweepstakes_report_data.dart';
import '../models/exhibitor/entered_exhibitors_contact_report_data.dart';
import '../models/exhibitor/exhibitor_report_data.dart';
import '../models/exhibitor/ribbon_payout_report_data.dart';
import '../models/judge/judge_report_data.dart';
import '../models/legs/legs_certificate_data.dart';
import '../models/paid/paid_exhibitor_report_data.dart';
import '../models/unpaid/unpaid_balances_report_data.dart';

import '../pdf/builders/arba_report_pdf.dart';
import '../pdf/builders/breed_results_detail_report_pdf.dart';
import '../pdf/builders/entered_exhibitors_contact_report_pdf.dart';
import '../pdf/builders/exhibitor_report_pdf.dart';
import '../pdf/builders/judge_report_pdf.dart';
import '../pdf/builders/legs_report_pdf.dart';
import '../pdf/builders/paid_exhibitor_report_pdf.dart';
import '../pdf/builders/ribbon_payout_report_pdf.dart';
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
    required PaidExhibitorReportLoader paidExhibitorReportLoader,
    required PaidExhibitorReportPdfBuilder paidExhibitorReportBuilder,
    required EnteredExhibitorsContactReportLoader enteredExhibitorsContactLoader,
    required EnteredExhibitorsContactReportPdf enteredExhibitorsContactBuilder,
    required RibbonPayoutReportLoader ribbonPayoutLoader,
    required RibbonPayoutReportPdf ribbonPayoutBuilder,
    required JudgeReportLoader judgeReportLoader,
    required JudgeReportPdfBuilder judgeReportBuilder,
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
          'paid_exhibitor_report': ReportDefinition(
            reportName: 'paid_exhibitor_report',
            outputType: 'pdf',
            loader: (req) async => await paidExhibitorReportLoader.load(req),
            builder: (data, req) async =>
                await paidExhibitorReportBuilder.buildFile(
                  data as PaidExhibitorReportData,
                  req,
                ),
          ),
          'entered_exhibitors_contact_report': ReportDefinition(
            reportName: 'entered_exhibitors_contact_report',
            outputType: 'pdf',
            loader: (req) async => await enteredExhibitorsContactLoader.load(req),
            builder: (data, req) async =>
                await enteredExhibitorsContactBuilder.buildFile(
                  data as EnteredExhibitorsContactReportData,
                  req,
                ),
          ),
          'ribbon_payout_report': ReportDefinition(
            reportName: 'ribbon_payout_report',
            outputType: 'pdf',
            loader: (req) async => await ribbonPayoutLoader.load(req),
            builder: (data, req) async =>
                await ribbonPayoutBuilder.buildFile(
                  data as RibbonPayoutReportData,
                  req,
                ),
          ),
          'judge_report': ReportDefinition(
            reportName: 'judge_report',
            outputType: 'pdf',
            loader: (req) async => await judgeReportLoader.load(
              showId: req.showId,
            ),
            builder: (data, req) async =>
                await judgeReportBuilder.buildFile(data as JudgeReportData, req),
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