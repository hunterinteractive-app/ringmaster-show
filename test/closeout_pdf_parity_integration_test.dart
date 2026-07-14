import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/reporting_core/assets/flutter_report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/arba_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/best_display_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_judged_totals_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/check_in_sheet_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/details_by_breed_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/entered_exhibitors_contact_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_by_breed_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/judge_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/legs_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/paid_exhibitor_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/payback_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/ribbon_payout_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/sweepstakes_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/unpaid_balances_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/arba_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/best_display_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/breed_judged_totals_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/breed_results_detail_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/check_in_sheet_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/details_by_breed_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/entered_exhibitors_contact_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/exhibitor_by_breed_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/exhibitor_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/judge_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/legs_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/paid_exhibitor_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/payback_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/ribbon_payout_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/sweepstakes_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/unpaid_balances_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/registry/report_registry.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/report_engine.dart';
import 'package:ringmaster_show/screens/admin/closeout/utils/club_report_grouping.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _showId = '20000000-0000-0000-0000-000000000004';
const _rabbitRunId = 'e79faf40-e678-4d50-95c7-31a982e38dc3';
const _cavyRunId = '0fdd8a36-4d7a-4bd8-829d-bc6593ec900f';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This explicitly invoked local integration harness needs real loopback
  // HTTP after the Flutter test binding installs its default 400 stub.
  HttpOverrides.global = null;
  final hasLocalParityEnvironment =
      Platform.environment['SUPABASE_URL'] != null &&
      Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] != null &&
      Platform.environment['PDF_PARITY_OUTPUT'] != null;

  test(
    'Flutter Closeout path matches representative worker inputs',
    () async {
      final url = Platform.environment['SUPABASE_URL']!;
      final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY']!;
      final outputRoot = Platform.environment['PDF_PARITY_OUTPUT']!;

      final client = SupabaseClient(
        url,
        key,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      const assets = FlutterReportAssetLoader();
      final repository = CloseoutRepository(client);
      final logo = await assets.loadBytes(
        'assets/images/ringmaster_show_logo.png',
      );

      // This is the same registry composition used by the Flutter Closeout UI,
      // with rootBundle-backed assets rather than the worker filesystem loader.
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
        sweepstakesBuilder: SweepstakesReportPdf(
          assets: assets,
          logoBytes: logo,
        ),
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
      );
      final engine = ReportEngine(registry);

      final cases = <_ParityCase>[
        const _ParityCase('arba', 'arba_report', _rabbitRunId),
        const _ParityCase('exhibitor', 'exhibitor_report', _rabbitRunId),
        const _ParityCase('checkin', 'checkin_sheet', _rabbitRunId),
        const _ParityCase('legs', 'legs', _rabbitRunId),
        const _ParityCase(
          'breed_results_detail',
          'breed_results_detail_report',
          _rabbitRunId,
        ),
        const _ParityCase(
          'unpaid_financial',
          'unpaid_balances_report',
          _rabbitRunId,
        ),
        const _ParityCase(
          'cavy_breed_results_detail',
          'breed_results_detail_report',
          _cavyRunId,
        ),
      ];
      final flutterDir = Directory('$outputRoot/flutter')
        ..createSync(recursive: true);
      final workerDir = Directory('$outputRoot/worker')
        ..createSync(recursive: true);

      for (final parityCase in cases) {
        final row = await client
            .from('show_report_artifacts')
            .select(
              'id,finalize_run_id,report_name,metadata,section_ids,storage_bucket,storage_path',
            )
            .eq('finalize_run_id', parityCase.finalizeRunId)
            .eq('report_name', parityCase.reportName)
            .eq('artifact_status', 'generated')
            .order('created_at')
            .limit(1)
            .single();
        final metadata = Map<String, dynamic>.from(row['metadata'] as Map);
        final sectionIds = (row['section_ids'] as List)
            .map((value) => value.toString())
            .toList(growable: false);
        final species = _text(metadata, 'species');
        final request = ReportRequest(
          showId: _showId,
          reportName: parityCase.reportName,
          finalizeRunId: parityCase.finalizeRunId,
          artifactId: row['id'].toString(),
          breedName: loaderBreedNameForClubReport(
            reportName: parityCase.reportName,
            breedName: _text(metadata, 'breed_name'),
            species: species,
          ),
          clubName: _text(metadata, 'club_name'),
          species: species,
          scope: _text(metadata, 'scope'),
          showLetter: _text(metadata, 'show_letter'),
          scopeLabel: _text(metadata, 'scope_label'),
          sectionId: _text(metadata, 'section_id'),
          sectionIds: sectionIds,
          showName: 'Local Mixed Closeout E2E Show',
          showDate: '08-04-2026',
          sanctionNumber: 'ARBA-LOCAL-A',
          exhibitorId: _text(metadata, 'exhibitor_id'),
          exhibitorName: _text(metadata, 'exhibitor_name'),
        );
        final flutterFile = await engine.generate(request);
        final workerBytes = await client.storage
            .from(row['storage_bucket'].toString())
            .download(row['storage_path'].toString());

        _expectPdf(Uint8List.fromList(flutterFile.bytes), parityCase.name);
        _expectPdf(workerBytes, parityCase.name);
        await File(
          '${flutterDir.path}/${parityCase.name}.pdf',
        ).writeAsBytes(flutterFile.bytes, flush: true);
        await File(
          '${workerDir.path}/${parityCase.name}.pdf',
        ).writeAsBytes(workerBytes, flush: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: hasLocalParityEnvironment
        ? false
        : 'Requires the isolated local Supabase parity environment.',
  );
}

String? _text(Map<String, dynamic> metadata, String key) {
  final value = metadata[key]?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

void _expectPdf(Uint8List bytes, String name) {
  expect(
    bytes.length,
    greaterThan(1000),
    reason: '$name is unexpectedly small',
  );
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: name);
  expect(
    String.fromCharCodes(bytes.skip(bytes.length - 32)).contains('%%EOF'),
    isTrue,
    reason: '$name has no PDF EOF marker',
  );
}

final class _ParityCase {
  const _ParityCase(this.name, this.reportName, this.finalizeRunId);

  final String name;
  final String reportName;
  final String finalizeRunId;
}
