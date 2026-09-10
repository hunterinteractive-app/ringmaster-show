// Local PDF diagnostics. Optional immutable upload replay never overwrites.
import 'dart:convert';
import 'dart:io';

import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/rendering/artifact_renderer.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_queue.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/details_by_breed_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/details_by_breed_report_pdf.dart';
import 'package:supabase/supabase.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 2 && arguments.first == '--layout-only') {
    await probeLayout(int.parse(arguments[1]));
    return;
  }
  final url = Platform.environment['SUPABASE_URL'] ?? '';
  final uri = Uri.parse(url);
  final uploadReplay =
      arguments.length == 2 && arguments.first == '--upload-replay';
  if (uri.scheme != 'http' ||
      !{'127.0.0.1', 'localhost'}.contains(uri.host) ||
      (arguments.length != 1 && !uploadReplay)) {
    throw ArgumentError(
      'A loopback URL and one synthetic artifact ID are required.',
    );
  }
  final client = SupabaseClient(
    url,
    Platform.environment['SUPABASE_SERVICE_ROLE_KEY']!,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final watch = Stopwatch()..start();
  try {
    final queue = SupabaseRenderQueue(client);
    final artifact = await queue.loadArtifact(arguments.last);
    if (artifact.showId != '95000000-0000-0000-0000-000000000001') {
      throw StateError('Refusing a non-rehearsal artifact.');
    }
    final renderer = await RegistryArtifactRenderer.create(
      client: client,
      assets: FileSystemReportAssetLoader(
        Directory(Platform.environment['ASSET_ROOT']!),
      ),
    );
    final result = await renderer.render(artifact);
    if (uploadReplay) {
      final again = await renderer.render(artifact);
      String? uploadError;
      try {
        // Immutable duplicate upload only. Never overwrites the stored file.
        await queue.upload(
          artifact,
          again.bytes,
          checksum: again.checksum,
          mimeType: again.mimeType,
          fileName: again.fileName,
        );
      } catch (error) {
        uploadError = '$error';
      }
      stdout.writeln(
        jsonEncode({
          'ok': uploadError == null,
          'report': artifact.reportName,
          'two_renders_identical': result.checksum == again.checksum,
          'first_checksum': result.checksum,
          'second_checksum': again.checksum,
          'immutable_upload_retry_error': uploadError,
        }),
      );
      if (uploadError != null) exitCode = 1;
      return;
    }
    stdout.writeln(
      jsonEncode({
        'ok': true,
        'report': artifact.reportName,
        'bytes': result.bytes.length,
        'load_ms': result.dataLoadDuration.inMilliseconds,
        'pdf_ms': result.pdfBuildDuration.inMilliseconds,
      }),
    );
  } catch (error, stack) {
    stdout.writeln(
      jsonEncode({
        'ok': false,
        'error': '$error',
        'stack': '$stack',
        'duration_ms': watch.elapsedMilliseconds,
      }),
    );
    exitCode = 1;
  } finally {
    client.dispose();
  }
}

Future<void> probeLayout(int count) async {
  if (count < 1 || count > 5000) throw ArgumentError('Use 1 to 5000 rows.');
  final watch = Stopwatch()..start();
  final rows = List.generate(
    count,
    (n) => DetailsByBreedPlacementRow(
      placement: n + 1,
      earNumber: 'S${n + 1}',
      animalName: 'Rabbit ${n + 1}',
      exhibitorName: 'Exhibitor ${n + 1}',
      awards: const [],
    ),
  );
  final data = DetailsByBreedReportData(
    showId: '95000000-0000-0000-0000-000000000001',
    showName: 'Synthetic layout probe',
    showDate: '2026-09-10',
    reportDate: '2026-09-10',
    showLocation: 'Local',
    hostClubName: 'Synthetic Club',
    scope: 'OPEN',
    showLetter: 'A',
    showType: 'Open',
    specialtyStatus: 'All breeds',
    arbaSanctionNumber: 'LOCAL',
    stateClubName: '',
    stateClubSanctionNumber: '',
    secretaryName: 'Synthetic',
    secretaryAddress: '',
    secretaryEmail: '',
    secretaryPhone: '',
    superintendentName: '',
    overallWinners: const [],
    breeds: [
      DetailsByBreedBreedSection(
        breedName: 'Mini Rex',
        judgeName: 'Synthetic',
        animalsShown: count,
        exhibitorCount: count,
        bob: null,
        bosb: null,
        specialAwards: const [],
        varieties: [
          DetailsByBreedVarietySection(
            varietyName: 'Black',
            animalsShown: count,
            exhibitorCount: count,
            bov: null,
            bosv: null,
            classes: [
              DetailsByBreedClassSection(
                className: 'Senior',
                sex: 'Buck',
                animalsShown: count,
                exhibitorCount: count,
                placements: rows,
              ),
            ],
          ),
        ],
      ),
    ],
  );
  try {
    final result =
        await DetailsByBreedReportPdf(
          assets: FileSystemReportAssetLoader(
            Directory(Platform.environment['ASSET_ROOT'] ?? '../../assets'),
          ),
        ).buildFile(
          data,
          ReportRequest(
            showId: data.showId,
            reportName: 'details_by_breed',
            finalizeRunId: 'local-probe',
          ),
        );
    final output = Platform.environment['LAYOUT_PDF_OUTPUT'];
    if (output != null) await File(output).writeAsBytes(result.bytes);
    stdout.writeln(
      jsonEncode({
        'ok': true,
        'rows': count,
        'bytes': result.bytes.length,
        'duration_ms': watch.elapsedMilliseconds,
      }),
    );
  } catch (error) {
    stdout.writeln(
      jsonEncode({
        'ok': false,
        'rows': count,
        'error': '$error',
        'duration_ms': watch.elapsedMilliseconds,
      }),
    );
    exitCode = 1;
  }
}
