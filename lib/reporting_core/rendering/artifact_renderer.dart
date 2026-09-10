import 'package:ringmaster_show/screens/admin/closeout/models/unpaid/unpaid_balances_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/paid/paid_exhibitor_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/other/michelles_special_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/legs/legs_certificate_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/judge/judge_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/judge/breed_judged_totals_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/payback_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/ribbon_payout_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/best_display_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/exhibitor_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/entered_exhibitors_list_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/entered_exhibitors_contact_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/check_in_sheet_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/exhibitor_by_breed_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/details_by_breed_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/arba/arba_report_data.dart';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/arba_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/best_display_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_judged_totals_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/check_in_sheet_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/details_by_breed_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/entered_exhibitors_contact_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/entered_exhibitors_list_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_by_breed_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/judge_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/legs_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/michelles_special_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/paid_exhibitor_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/payback_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/ribbon_payout_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/sweepstakes_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/json/builders/sweepstakes_json_export.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/unpaid_balances_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_file_result.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/breed_results_detail_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/sweepstakes_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/arba_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/best_display_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/breed_judged_totals_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/breed_results_detail_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/check_in_sheet_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/details_by_breed_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/entered_exhibitors_contact_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/entered_exhibitors_list_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/exhibitor_by_breed_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/exhibitor_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/judge_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/legs_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/paid_exhibitor_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/payback_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/ribbon_payout_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/sweepstakes_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/unpaid_balances_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/csv/builders/michelles_special_report_csv.dart';
import 'package:ringmaster_show/screens/admin/closeout/registry/report_registry.dart';
import 'package:supabase/supabase.dart';

import 'render_task.dart';
import 'render_isolate.dart';

final class RenderedArtifact {
  const RenderedArtifact({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.checksum,
    required this.dataLoadDuration,
    required this.pdfBuildDuration,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String checksum;
  final Duration dataLoadDuration;
  final Duration pdfBuildDuration;
}

abstract interface class ArtifactRenderer {
  Set<String> get supportedReportTypes;

  Future<RenderedArtifact> render(RenderArtifact artifact);
}

final class RegistryArtifactRenderer implements ArtifactRenderer {
  RegistryArtifactRenderer({
    required this.client,
    required this.assets,
    required this.registry,
    required this.repository,
    this.buildTimeout = const Duration(minutes: 2),
  });

  static Future<RegistryArtifactRenderer> create({
    required SupabaseClient client,
    required ReportAssetLoader assets,
    Duration buildTimeout = const Duration(minutes: 2),
  }) async {
    final repository = CloseoutRepository(client, reuseResultSnapshots: true);
    final logo = await assets.loadBytes(
      'assets/images/ringmaster_show_logo.png',
    );
    final registry = ReportRegistry(
      arbaLoader: ArbaReportLoader(repository),
      arbaBuilder: ArbaReportPdfBuilder(assets: assets),
      legsLoader: LegsReportLoader(repository),
      legsBuilder: await LegsReportPdfBuilder.fromAssets(assets),
      checkInSheetLoader: CheckInSheetReportLoader(client),
      checkInSheetBuilder: CheckInSheetReportPdfBuilder(assets: assets),
      exhibitorLoader: ExhibitorReportLoader(repository),
      exhibitorBuilder: await ExhibitorReportPdfBuilder.fromAssets(assets),
      sweepstakesLoader: SweepstakesReportLoader(repository),
      sweepstakesBuilder: SweepstakesReportPdf(assets: assets, logoBytes: logo),
      breedResultsDetailReportLoader: BreedResultsDetailReportLoader(
        repository,
      ),
      breedResultsDetailReportBuilder: BreedResultsDetailReportPdf(
        assets: assets,
        logoBytes: logo,
      ),
      detailsByBreedReportLoader: DetailsByBreedReportLoader(repository),
      detailsByBreedReportBuilder: DetailsByBreedReportPdf(
        assets: assets,
        logoBytes: logo,
      ),
      exhibitorByBreedReportLoader: ExhibitorByBreedReportLoader(repository),
      exhibitorByBreedReportBuilder: ExhibitorByBreedReportPdf(
        assets: assets,
        logoBytes: logo,
      ),
      unpaidBalancesLoader: UnpaidBalancesReportLoader(repository),
      unpaidBalancesBuilder: await UnpaidBalancesReportPdfBuilder.fromAssets(
        assets,
      ),
      paidExhibitorReportLoader: PaidExhibitorReportLoader(repository),
      paidExhibitorReportBuilder:
          await PaidExhibitorReportPdfBuilder.fromAssets(assets),
      enteredExhibitorsContactLoader: EnteredExhibitorsContactReportLoader(
        client,
      ),
      enteredExhibitorsContactBuilder: EnteredExhibitorsContactReportPdf(
        assets: assets,
      ),
      enteredExhibitorsListLoader: EnteredExhibitorsListReportLoader(client),
      enteredExhibitorsListBuilder: EnteredExhibitorsListReportPdf(
        assets: assets,
      ),
      ribbonPayoutLoader: RibbonPayoutReportLoader(repository),
      ribbonPayoutBuilder: RibbonPayoutReportPdf(assets: assets),
      paybackReportLoader: PaybackReportLoader(supabase: client),
      paybackReportBuilder: await PaybackReportPdfBuilder.fromAssets(assets),
      judgeReportLoader: JudgeReportLoader(supabase: client),
      judgeReportBuilder: JudgeReportPdfBuilder(assets: assets),
      breedJudgedTotalsReportLoader: BreedJudgedTotalsReportLoader(
        supabase: client,
      ),
      breedJudgedTotalsReportBuilder: BreedJudgedTotalsReportPdfBuilder(
        assets: assets,
      ),
      bestDisplayReportLoader: BestDisplayReportLoader(supabase: client),
      bestDisplayReportBuilder: BestDisplayReportPdfBuilder(assets: assets),
      michellesSpecialReportLoader: MichellesSpecialReportLoader(client),
      michellesSpecialReportBuilder: MichellesSpecialReportCsvBuilder(),
    );
    return RegistryArtifactRenderer(
      client: client,
      assets: assets,
      registry: registry,
      repository: repository,
      buildTimeout: buildTimeout,
    );
  }

  final SupabaseClient client;
  final ReportAssetLoader assets;
  final ReportRegistry registry;
  final CloseoutRepository repository;
  final Duration buildTimeout;

  @override
  Set<String> get supportedReportTypes => {
    ...registry.definitions.keys,
    'sweepstakes_json_export',
  };

  @override
  Future<RenderedArtifact> render(RenderArtifact artifact) async {
    if (!supportedReportTypes.contains(artifact.reportName)) {
      throw RenderFailure.permanent(
        'unsupported_renderer',
        'This report type is not supported by the background renderer.',
        'No renderer is registered for ${artifact.reportName}.',
      );
    }
    if (artifact.reportName == 'paid_exhibitor_report' ||
        artifact.reportName == 'unpaid_balances_report') {
      await _requireSafeBalanceScope(artifact);
    }
    final show = await client
        .from('shows')
        .select('name,start_date,is_national_show,national_show_section_id')
        .eq('id', artifact.showId)
        .single();
    final metadata = artifact.metadata;
    final request = ReportRequest(
      showId: artifact.showId,
      reportName: artifact.reportName,
      finalizeRunId: artifact.finalizeRunId,
      artifactId: artifact.id,
      breedName: _text(metadata, 'breed_name'),
      clubName: _text(metadata, 'club_name'),
      species: _text(metadata, 'species'),
      scope: _text(metadata, 'scope'),
      showLetter: _text(metadata, 'show_letter'),
      scopeLabel: _text(metadata, 'scope_label'),
      sectionId: _text(metadata, 'section_id'),
      sectionIds: artifact.sectionIds,
      showName: show['name']?.toString(),
      showDate: _formatShowDate(show['start_date']),
      sanctionNumber: _text(metadata, 'sanction_number'),
      exhibitorId: _text(metadata, 'exhibitor_id'),
      exhibitorName: _text(metadata, 'exhibitor_name'),
      isNationalShow: reportScopeIsNationalShow(
        isNationalShow: show['is_national_show'] == true,
        nationalShowSectionId: show['national_show_section_id']?.toString(),
        sectionId: _text(metadata, 'section_id'),
        sectionIds: artifact.sectionIds,
      ),
    );
    final dataWatch = Stopwatch()..start();
    late final Object data;
    late final Object result;
    if (artifact.reportName == 'sweepstakes_json_export') {
      final results = await BreedResultsDetailReportLoader(
        repository,
      ).load(request);
      final sweepstakes = await SweepstakesReportLoader(
        repository,
      ).load(request);
      data = (results, sweepstakes);
    } else {
      final definition = registry.get(artifact.reportName);
      try {
        data = await definition.loader(request);
      } on ScopedBalanceAllocationException catch (error) {
        throw RenderFailure.permanent(
          'unsupported_scoped_balance_report',
          error.toString(),
          error.reasons.toString(),
        );
      }
    }
    dataWatch.stop();
    final buildWatch = Stopwatch()..start();
    // Capture only report data and asset paths, never the client, registry,
    // queue or worker. A CPU-bound layout cannot block leases in this isolate.
    final renderAssets = assets;
    result = await runInRenderIsolate(
      () => buildReportFile(renderAssets, data, request),
      timeout: buildTimeout,
    );
    buildWatch.stop();
    final file = result as ReportFileResult;
    if (file.bytes.isEmpty ||
        !const {
          'application/pdf',
          'text/csv',
          'application/json',
        }.contains(file.mimeType)) {
      throw const RenderFailure.permanent(
        'invalid_render_output',
        'The renderer did not produce a valid report file.',
      );
    }
    final bytes = Uint8List.fromList(file.bytes);
    return RenderedArtifact(
      bytes: bytes,
      fileName: file.fileName,
      mimeType: file.mimeType,
      checksum: sha256.convert(bytes).toString(),
      dataLoadDuration: dataWatch.elapsed,
      pdfBuildDuration: buildWatch.elapsed,
    );
  }

  String? _text(Map<String, dynamic> metadata, String key) {
    final value = metadata[key]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? _formatShowDate(Object? rawDate) {
    if (rawDate == null) return null;
    final source = rawDate.toString();
    final parsed = DateTime.tryParse(source);
    if (parsed == null) return source;
    return '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}-${parsed.year}';
  }

  Future<void> _requireSafeBalanceScope(RenderArtifact artifact) async {
    final rows = await client.rpc(
      'report_show_exhibitor_balances_scoped',
      params: {
        'p_show_id': artifact.showId,
        'p_section_ids': artifact.sectionIds,
      },
    );
    final ambiguous = (rows as List).where(
      (row) => row is Map && row['payment_allocation_status'] == 'ambiguous',
    );
    if (ambiguous.isNotEmpty) {
      throw RenderFailure.permanent(
        'unsupported_scoped_balance_report',
        'Financial payments or discounts are recorded only at the whole-show level and cannot be allocated reliably to the selected sections.',
        ambiguous
            .map((row) => (row as Map)['payment_allocation_ambiguity_reasons'])
            .toList()
            .toString(),
      );
    }
  }
}

Future<ReportFileResult> buildReportFile(
  ReportAssetLoader assets,
  Object data,
  ReportRequest request,
) async {
  final logo = await assets.loadBytes('assets/images/ringmaster_show_logo.png');
  switch (request.reportName) {
    case 'arba_report':
      return (ArbaReportPdfBuilder(
        assets: assets,
      )).buildFile(data as ArbaReportData, request);
    case 'legs':
      return (await LegsReportPdfBuilder.fromAssets(
        assets,
      )).buildFile(data as List<LegsCertificateData>, request);
    case 'checkin_sheet':
      return (CheckInSheetReportPdfBuilder(
        assets: assets,
      )).buildFile(data as CheckInSheetReportData, request);
    case 'exhibitor_report':
      return (await ExhibitorReportPdfBuilder.fromAssets(
        assets,
      )).buildFile(data as ExhibitorReportData, request);
    case 'sweepstakes_report':
      return (SweepstakesReportPdf(
        assets: assets,
        logoBytes: logo,
      )).buildFile(data as SweepstakesReportData, request);
    case 'breed_results_detail_report':
      return (BreedResultsDetailReportPdf(
        assets: assets,
        logoBytes: logo,
      )).buildFile(data as BreedResultsDetailReportData, request);
    case 'details_by_breed':
      return (DetailsByBreedReportPdf(
        assets: assets,
        logoBytes: logo,
      )).buildFile(data as DetailsByBreedReportData, request);
    case 'exh_by_breed':
      return (ExhibitorByBreedReportPdf(
        assets: assets,
        logoBytes: logo,
      )).buildFile(data as ExhibitorByBreedReportData, request);
    case 'unpaid_balances_report':
      return (await UnpaidBalancesReportPdfBuilder.fromAssets(
        assets,
      )).buildFile(data as UnpaidBalancesReportData, request);
    case 'paid_exhibitor_report':
      return (await PaidExhibitorReportPdfBuilder.fromAssets(
        assets,
      )).buildFile(data as PaidExhibitorReportData, request);
    case 'entered_exhibitors_contact_report':
      return (EnteredExhibitorsContactReportPdf(
        assets: assets,
      )).buildFile(data as EnteredExhibitorsContactReportData, request);
    case 'entered_exhibitors_list_report':
      return (EnteredExhibitorsListReportPdf(
        assets: assets,
      )).buildFile(data as EnteredExhibitorsListReportData, request);
    case 'ribbon_payout_report':
      return (RibbonPayoutReportPdf(
        assets: assets,
      )).buildFile(data as RibbonPayoutReportData, request);
    case 'payback_report':
      return (await PaybackReportPdfBuilder.fromAssets(
        assets,
      )).buildFile(data as PaybackReportData, request);
    case 'judge_report':
      return (JudgeReportPdfBuilder(
        assets: assets,
      )).buildFile(data as JudgeReportData, request);
    case 'breed_judged_totals_report':
      return (BreedJudgedTotalsReportPdfBuilder(
        assets: assets,
      )).buildFile(data as BreedJudgedTotalsReportData, request);
    case 'best_display_report':
      return (BestDisplayReportPdfBuilder(
        assets: assets,
      )).buildFile(data as BestDisplayReportData, request);
    case 'michelles_special_report':
      return (MichellesSpecialReportCsvBuilder()).buildFile(
        data as MichellesSpecialReportData,
        request,
      );
    case 'sweepstakes_json_export':
      final export =
          data as (BreedResultsDetailReportData, SweepstakesReportData);
      return const SweepstakesJsonExport().buildFile(
        results: export.$1,
        sweepstakes: export.$2,
        request: request,
      );
    default:
      throw StateError('Unsupported report builder: ${request.reportName}');
  }
}
