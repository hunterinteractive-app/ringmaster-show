import 'package:supabase/supabase.dart';

import '../csv/builders/other_reports_csv.dart';
import '../csv/builders/michelles_special_report_csv.dart';
import '../data/closeout_repository.dart';
import '../data/report_data_reader.dart';
import '../data/loaders/breed_awards_overview_loader.dart';
import '../data/loaders/breed_judged_totals_report_loader.dart';
import '../data/loaders/entered_exhibitors_contact_report_loader.dart';
import '../data/loaders/entered_exhibitors_list_report_loader.dart';
import '../data/loaders/exhibitor_mailing_labels_loader.dart';
import '../data/loaders/exhibitor_report_loader.dart';
import '../data/loaders/judge_report_loader.dart';
import '../data/loaders/legs_report_loader.dart';
import '../data/loaders/michelles_special_report_loader.dart';
import '../data/loaders/paid_exhibitor_report_loader.dart';
import '../data/loaders/payback_report_loader.dart';
import '../data/loaders/ribbon_payout_report_loader.dart';
import '../data/loaders/unpaid_balances_report_loader.dart';
import '../models/base/report_file_result.dart';
import '../models/base/report_request.dart';
import '../models/report_artifact_summary.dart';

/// Reads through the same authenticated client and loaders as PDF reports.
/// CSV downloads neither replace stored PDFs nor enqueue or send reports.
class OtherReportsCsvService {
  OtherReportsCsvService(this.client);
  final SupabaseClient client;

  Future<ReportFileResult> build({
    required String showId,
    required String reportName,
    required String title,
    ReportArtifactSummary? artifact,
    MailingLabelMode labelMode = MailingLabelMode.address,
    MailingLabelSort labelSort = MailingLabelSort.lastName,
  }) async {
    if (!OtherReportsCsvBuilder.reportNames.contains(reportName)) {
      throw ArgumentError('This report does not support CSV export.');
    }
    if (artifact != null &&
        (artifact.reportName != reportName || artifact.showId != showId)) {
      throw ArgumentError(
        'The selected report belongs to a different show or report.',
      );
    }
    final show = await client
        .from('shows')
        .select('name,start_date,is_national_show,national_show_section_id')
        .eq('id', showId)
        .single();
    final sections = await client
        .from('show_sections')
        .select('id')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .order('id');
    final enabledIds = sections.map((s) => s['id'].toString()).toList();
    final request = otherReportCsvRequest(
      showId: showId,
      reportName: reportName,
      show: show,
      enabledSectionIds: enabledIds,
      artifact: artifact,
    );
    final repo = CloseoutRepository(client, reuseResultSnapshots: true);
    if (reportName == 'michelles_special_report') {
      return MichellesSpecialReportCsvBuilder().buildFile(
        await MichellesSpecialReportLoader(client).load(request),
        request,
      );
    }
    final Object data = switch (reportName) {
      'breed_awards_overview' => await BreedAwardsOverviewLoader(
        client,
      ).load(request),
      'breed_judged_totals_report' => await BreedJudgedTotalsReportLoader(
        supabase: client,
      ).load(request),
      'entered_exhibitors_contact_report' =>
        await EnteredExhibitorsContactReportLoader(client).load(request),
      'entered_exhibitors_list_report' =>
        await EnteredExhibitorsListReportLoader(client).load(request),
      'exhibitor_mailing_labels' => await ExhibitorMailingLabelsLoader(
        client,
      ).load(request),
      'judge_report' => await JudgeReportLoader(supabase: client).load(request),
      'paid_exhibitor_report' => await PaidExhibitorReportLoader(
        repo,
      ).load(request),
      'unpaid_balances_report' => await UnpaidBalancesReportLoader(
        repo,
      ).load(request),
      'payback_report' => await PaybackReportLoader(
        supabase: client,
      ).loadRequest(request),
      'ribbon_payout_report' => await RibbonPayoutReportLoader(
        repo,
      ).load(request),
      'exhibitor_print_pack' => await _printPack(
        request,
        repo,
        show,
        enabledIds,
      ),
      _ => throw StateError('No CSV loader for $reportName'),
    };
    return OtherReportsCsvBuilder()
        .build(data, labelMode: labelMode, labelSort: labelSort)
        .toFile(
          title: title,
          showName: request.showName ?? '',
          scopeLabel: request.scopeLabel,
        );
  }

  Future<ExhibitorPrintPackCsvData> _printPack(
    ReportRequest request,
    CloseoutRepository repo,
    Map<String, dynamic> show,
    List<String> enabledIds,
  ) async {
    if (await client.rpc(
          'can_access_exhibitor_print_pack',
          params: {'p_show_id': request.showId},
        ) !=
        true) {
      throw StateError('You do not have access to the exhibitor print pack.');
    }
    // Use the same current sources required by the PDF print pack, preserving
    // each source's species and section boundaries.
    final sources = await readAllReportPages(
      (from, to) => client
          .from('show_report_artifacts')
          .select()
          .eq('show_id', request.showId)
          .eq('is_current', true)
          .inFilter('report_name', ['exhibitor_report', 'legs'])
          .order('id')
          .range(from, to),
    );
    if (sources.isEmpty ||
        sources.any(
          (s) =>
              s['artifact_status'] != 'generated' ||
              _text(s['storage_path']).isEmpty,
        )) {
      throw StateError(
        'Finish generating exhibitor reports and legs in Step 5 first.',
      );
    }
    final artifacts = sources.map(ReportArtifactSummary.fromJson).toList();
    final exhibitors = await loadReportRowsByIds(
      client,
      table: 'exhibitors',
      ids: artifacts.map((a) => _text(a.metadata['exhibitor_id'])),
      columns: 'id,exhibitor_number,last_name,first_name,display_name',
    );
    final profiles = {for (final ex in exhibitors) _text(ex['id']): ex};
    String sortName(ReportArtifactSummary a) {
      final ex = profiles[_text(a.metadata['exhibitor_id'])] ?? {};
      return '${ex['last_name'] ?? ex['display_name'] ?? a.metadata['exhibitor_name'] ?? ''}|${ex['first_name'] ?? ''}|${a.metadata['exhibitor_id']}|${a.reportName == 'legs' ? 1 : 0}|${a.id}'
          .toLowerCase();
    }

    artifacts.sort((a, b) => sortName(a).compareTo(sortName(b)));
    final data = ExhibitorPrintPackCsvData();
    for (final artifact in artifacts) {
      final source = otherReportCsvRequest(
        showId: request.showId,
        reportName: artifact.reportName,
        show: show,
        enabledSectionIds: enabledIds,
        artifact: artifact,
      );
      final scope = source.scopeLabel ?? source.scope ?? '';
      if (artifact.reportName == 'exhibitor_report') {
        data.addReport(
          await ExhibitorReportLoader(repo).load(source),
          number: _text(profiles[source.exhibitorId]?['exhibitor_number']),
          scope: scope,
          species: source.species ?? '',
        );
      } else {
        data.addLegs(
          await LegsReportLoader(repo).load(source),
          scope: scope,
          species: source.species ?? '',
        );
      }
    }
    return data;
  }
}

ReportRequest otherReportCsvRequest({
  required String showId,
  required String reportName,
  required Map<String, dynamic> show,
  required List<String> enabledSectionIds,
  ReportArtifactSummary? artifact,
}) {
  final metadata = artifact?.metadata ?? const <String, dynamic>{};
  final storedSections = artifact?.sectionIds.isNotEmpty == true
      ? artifact!.sectionIds
      : (metadata['section_ids'] is List
            ? (metadata['section_ids'] as List)
                  .map((id) => id.toString())
                  .toList()
            : <String>[]);
  // Never silently broaden an existing scoped report with missing metadata.
  if (artifact?.finalizeRunId?.isNotEmpty == true &&
      artifact!.finalizeRunId != 'operational' &&
      storedSections.isEmpty) {
    throw StateError(
      'This report is missing its section scope. Regenerate it first.',
    );
  }
  final sectionIds = storedSections.isEmpty
      ? enabledSectionIds
      : storedSections;
  if (sectionIds.isEmpty) {
    throw StateError('Add at least one enabled show section first.');
  }
  String? meta(String key) =>
      _text(metadata[key]).isEmpty ? null : _text(metadata[key]);
  return ReportRequest(
    showId: showId,
    reportName: reportName,
    finalizeRunId: artifact?.finalizeRunId ?? 'operational',
    artifactId: artifact?.id,
    sectionIds: sectionIds,
    sectionId: meta('section_id'),
    scope: meta('scope'),
    scopeLabel: meta('scope_label'),
    showLetter: meta('show_letter'),
    species: meta('species'),
    exhibitorId: meta('exhibitor_id'),
    exhibitorName: meta('exhibitor_name'),
    showName: _text(show['name']),
    showDate: _text(show['start_date']),
    sanctionNumber: meta('sanction_number'),
    isNationalShow: reportScopeIsNationalShow(
      isNationalShow: show['is_national_show'] == true,
      nationalShowSectionId: show['national_show_section_id']?.toString(),
      sectionId: meta('section_id'),
      sectionIds: sectionIds,
    ),
  );
}

String _text(Object? value) => value?.toString().trim() ?? '';
