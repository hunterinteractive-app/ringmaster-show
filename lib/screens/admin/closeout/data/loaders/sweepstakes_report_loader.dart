// lib/screens/admin/closeout/data/loaders/sweepstakes_report_loader.dart

import '../../models/base/report_request.dart';
import '../../models/clubs/sweepstakes_report_data.dart';
import '../closeout_repository.dart';

class SweepstakesReportLoader {
  SweepstakesReportLoader(this.repo);

  final CloseoutRepository repo;

  Future<SweepstakesReportData> load(ReportRequest request) async {
    final showId = request.showId;
    final breedName = (request.breedName ?? '').trim();
    final scope = (request.scope ?? '').trim().toUpperCase();

    if (breedName.isEmpty) {
      throw Exception('Sweepstakes report requires breedName.');
    }

    if (scope.isEmpty) {
      throw Exception('Sweepstakes report requires scope.');
    }

    final rowsResponse = await repo.supabase
        .from('v_sweepstakes_pdf_rows')
        .select()
        .eq('show_id', showId)
        .eq('breed_name', breedName)
        .eq('scope', scope)
        .order('rank', ascending: true);

    final rows = (rowsResponse as List)
        .map((e) => SweepstakesReportRow.fromMap(e as Map<String, dynamic>))
        .toList();

    if (rows.isEmpty) {
      throw Exception(
        'No sweepstakes results found for breed "$breedName" in scope "$scope".',
      );
    }

    final headerResponse = await repo.supabase
        .from('v_sweepstakes_pdf_rows')
        .select(
          'show_id, breed_name, scope, rule_source, verification_status, engine_type',
        )
        .eq('show_id', showId)
        .eq('breed_name', breedName)
        .eq('scope', scope)
        .limit(1)
        .maybeSingle();

    if (headerResponse == null) {
      throw Exception(
        'No sweepstakes header data found for breed "$breedName" in scope "$scope".',
      );
    }

    final header = Map<String, dynamic>.from(headerResponse);

    return SweepstakesReportData(
      showId: (header['show_id'] ?? '').toString(),
      breedName: (header['breed_name'] ?? '').toString(),
      scope: (header['scope'] ?? '').toString(),
      ruleSource: (header['rule_source'] ?? '').toString(),
      verificationStatus: (header['verification_status'] ?? '').toString(),
      engineType: (header['engine_type'] ?? '').toString(),
      rows: rows,
    );
  }
}