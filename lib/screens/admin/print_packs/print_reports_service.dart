import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/reporting_core/assets/flutter_report_asset_loader.dart';
import 'package:ringmaster_show/services/show_addon_service.dart';
import 'package:ringmaster_show/services/show_addon_report_service.dart';
import '../closeout/data/closeout_repository.dart';
import '../closeout/data/loaders/paid_exhibitor_report_loader.dart';
import '../closeout/data/loaders/unpaid_balances_report_loader.dart';
import '../closeout/data/loaders/exhibitor_mailing_labels_loader.dart';
import '../closeout/data/loaders/entered_exhibitors_list_report_loader.dart';
import '../closeout/models/base/report_request.dart';
import '../closeout/models/base/report_file_result.dart';
import '../closeout/pdf/builders/paid_exhibitor_report_pdf.dart';
import '../closeout/pdf/builders/unpaid_balances_report_pdf.dart';
import '../closeout/pdf/builders/exhibitor_mailing_labels_pdf.dart';
import '../closeout/pdf/builders/entered_exhibitors_list_report_pdf.dart';

enum PrintReport {
  paid('paid_exhibitor_report', 'Paid Exhibitor Report'),
  unpaid('unpaid_balances_report', 'Unpaid Exhibitor Balance'),
  labels('exhibitor_mailing_labels', 'Exhibitor Labels'),
  numbers('entered_exhibitors_list_report', 'Exhibitor Number Lookup Report'),
  addons(ShowAddonReportService.purchases, 'Add-On Purchases'),
  contests(ShowAddonReportService.registrations, 'Contest Registrations');

  const PrintReport(this.reportName, this.label);
  final String reportName, label;
}

class PrintReportAvailability {
  const PrintReportAvailability({
    this.reports = const {},
    this.labelModes = const {},
    this.errors = const [],
  });
  final Set<PrintReport> reports;
  final Set<MailingLabelMode> labelModes;
  final List<String> errors;
}

/// Match the existing generators' eligibility rules, including partial payments
/// and excluding abandoned carts from outstanding entry balances.
Set<PrintReport> balancePrintReports(List<Map<String, dynamic>> balances) {
  num cents(Object? value) => num.tryParse('$value') ?? 0;
  return {
    if (balances.any(
      (r) =>
          cents(r['paid_online_cents']) +
              cents(r['paid_manual_cents']) -
              cents(r['refunded_cents']) >
          0,
    ))
      PrintReport.paid,
    if (balances.any(
      (r) => r['source'] == 'entries' && cents(r['balance_due_cents']) > 0,
    ))
      PrintReport.unpaid,
  };
}

Set<MailingLabelMode> availablePrintLabelModes(
  List<ExhibitorMailingLabel> labels,
) => {
  if (labels.any(
    (r) => r.name.isNotEmpty && r.hasMailingAddress && r.address.isNotEmpty,
  ))
    MailingLabelMode.address,
  if (labels.any((r) => r.name.isNotEmpty && r.number.isNotEmpty))
    MailingLabelMode.exhibitorNumber,
};

class PrintReportsService {
  PrintReportsService(this.client);
  final SupabaseClient client;
  static const _assets = FlutterReportAssetLoader();

  Future<PrintReportAvailability> available(ReportRequest request) async {
    final reports = <PrintReport>{};
    final modes = <MailingLabelMode>{};
    final errors = <String>[];
    Future<void> check(String label, Future<void> Function() load) async {
      try {
        await load();
      } catch (_) {
        errors.add(label);
      }
    }

    await Future.wait([
      if (request.sectionIds?.isNotEmpty == true) ...[
        check('Payment reports', () async {
          reports.addAll(
            balancePrintReports(
              await CloseoutRepository(client).loadShowExhibitorBalancesReport(
                request.showId,
                sectionIds: request.sectionIds,
              ),
            ),
          );
        }),
        check('Exhibitor reports', () async {
          final labels = await ExhibitorMailingLabelsLoader(
            client,
          ).load(request);
          if (labels.isNotEmpty) reports.add(PrintReport.numbers);
          modes.addAll(availablePrintLabelModes(labels));
          if (modes.isNotEmpty) reports.add(PrintReport.labels);
        }),
      ],
      check('Add-on and contest reports', () async {
        final rows = await ShowAddonService(
          client: client,
        ).registrations(showId: request.showId);
        if (rows.any((r) => r['kind'] == 'extra')) {
          reports.add(PrintReport.addons);
        }
        if (rows.any((r) => r['kind'] == 'contest')) {
          reports.add(PrintReport.contests);
        }
      }),
    ]);
    return PrintReportAvailability(
      reports: reports,
      labelModes: modes,
      errors: errors,
    );
  }

  Future<ReportFileResult> build(
    PrintReport report,
    ReportRequest request, {
    MailingLabelMode labelMode = MailingLabelMode.address,
    MailingLabelSort labelSort = MailingLabelSort.lastName,
  }) async {
    final req = request.copyWith(reportName: report.reportName);
    switch (report) {
      case PrintReport.paid:
        final data = await PaidExhibitorReportLoader(
          CloseoutRepository(client),
        ).load(req);
        if (data.rows.isEmpty) {
          throw StateError('No paid exhibitors to report.');
        }
        return (await PaidExhibitorReportPdfBuilder.fromAssets(
          _assets,
        )).buildFile(data, req);
      case PrintReport.unpaid:
        final data = await UnpaidBalancesReportLoader(
          CloseoutRepository(client),
        ).load(req);
        if (data.rows.isEmpty) {
          throw StateError('No unpaid exhibitor balances to report.');
        }
        return (await UnpaidBalancesReportPdfBuilder.fromAssets(
          _assets,
        )).buildFile(data, req);
      case PrintReport.labels:
        return ExhibitorMailingLabelsPdf(assets: _assets).buildFile(
          await ExhibitorMailingLabelsLoader(client).load(req),
          req,
          mode: labelMode,
          sort: labelSort,
        );
      case PrintReport.numbers:
        final data = await EnteredExhibitorsListReportLoader(client).load(req);
        if (data.rows.isEmpty) {
          throw StateError('No entered exhibitors to report.');
        }
        return EnteredExhibitorsListReportPdf(
          assets: _assets,
        ).buildFile(data, req);
      case PrintReport.addons:
      case PrintReport.contests:
        final rows = await ShowAddonService(
          client: client,
        ).registrations(showId: req.showId);
        final data = ShowAddonReportData(
          showName: req.showName ?? '',
          reportName: report.reportName,
          entries: rows,
        );
        if (data.entries.isEmpty) {
          throw StateError('No ${report.label.toLowerCase()} to report.');
        }
        return data.pdf();
    }
  }
}
