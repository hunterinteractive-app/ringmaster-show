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
    final showLetter = (request.showLetter ?? '').trim().toUpperCase();

    if (breedName.isEmpty) {
      throw Exception('Sweepstakes report requires breedName.');
    }

    if (scope.isEmpty) {
      throw Exception('Sweepstakes report requires scope.');
    }

    if (showLetter.isEmpty) {
      throw Exception('Sweepstakes report requires showLetter.');
    }

    if (showLetter == 'ALL') {
      final lettersResponse = await repo.supabase
          .from('show_sections')
          .select('letter')
          .eq('show_id', showId)
          .eq('is_enabled', true)
          .eq('kind', scope.toLowerCase())
          .order('letter');

      final letters = (lettersResponse as List)
          .map((e) => (e['letter'] ?? '').toString().trim().toUpperCase())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final sections = <SweepstakesReportSection>[];

      for (final letter in letters) {
        final rowsResponse = await repo.supabase
            .from('v_sweepstakes_pdf_rows')
            .select()
            .eq('show_id', showId)
            .eq('breed_name', breedName)
            .eq('scope', scope)
            .eq('show_letter', letter)
            .order('rank', ascending: true);

        final rows = (rowsResponse as List)
            .map((e) => SweepstakesReportRow.fromMap(e as Map<String, dynamic>))
            .toList();

        final headerResponse = await repo.supabase
            .from('v_sweepstakes_pdf_rows')
            .select(
              'show_id, breed_name, scope, show_letter, rule_source, verification_status, engine_type',
            )
            .eq('show_id', showId)
            .eq('breed_name', breedName)
            .eq('scope', scope)
            .eq('show_letter', letter)
            .limit(1)
            .maybeSingle();

        final header = headerResponse == null
            ? <String, dynamic>{
                'show_id': showId,
                'breed_name': breedName,
                'scope': scope,
                'show_letter': letter,
                'rule_source': 'NO_RESULTS',
                'verification_status': 'VERIFIED',
                'engine_type': 'NO_RESULTS',
              }
            : Map<String, dynamic>.from(headerResponse);

        sections.add(
          SweepstakesReportSection(
            showLetter: (header['show_letter'] ?? letter).toString(),
            ruleSource: (header['rule_source'] ?? 'NO_RESULTS').toString(),
            verificationStatus:
                (header['verification_status'] ?? 'VERIFIED').toString(),
            engineType: (header['engine_type'] ?? 'NO_RESULTS').toString(),
            rows: rows,
            noResultsFound: rows.isEmpty,
          ),
        );
      }

      return SweepstakesReportData(
        showId: showId,
        breedName: breedName,
        scope: scope,
        showLetter: 'ALL',
        ruleSource: sections.isNotEmpty ? sections.first.ruleSource : 'NO_RESULTS',
        verificationStatus: sections.isNotEmpty
            ? sections.first.verificationStatus
            : 'VERIFIED',
        engineType: sections.isNotEmpty ? sections.first.engineType : 'NO_RESULTS',
        rows: const [],
        sections: sections,
        noResultsFound: sections.every((s) => s.noResultsFound),
      );
    }

    final rowsResponse = await repo.supabase
        .from('v_sweepstakes_pdf_rows')
        .select()
        .eq('show_id', showId)
        .eq('breed_name', breedName)
        .eq('scope', scope)
        .eq('show_letter', showLetter)
        .order('rank', ascending: true);

    final rows = (rowsResponse as List)
        .map((e) => SweepstakesReportRow.fromMap(e as Map<String, dynamic>))
        .toList();

    final headerResponse = await repo.supabase
        .from('v_sweepstakes_pdf_rows')
        .select(
          'show_id, breed_name, scope, show_letter, rule_source, verification_status, engine_type',
        )
        .eq('show_id', showId)
        .eq('breed_name', breedName)
        .eq('scope', scope)
        .eq('show_letter', showLetter)
        .limit(1)
        .maybeSingle();

    final header = headerResponse == null
        ? <String, dynamic>{
            'show_id': showId,
            'breed_name': breedName,
            'scope': scope,
            'show_letter': showLetter,
            'rule_source': 'NO_RESULTS',
            'verification_status': 'VERIFIED',
            'engine_type': 'NO_RESULTS',
          }
        : Map<String, dynamic>.from(headerResponse);

    return SweepstakesReportData(
      showId: (header['show_id'] ?? showId).toString(),
      breedName: (header['breed_name'] ?? breedName).toString(),
      scope: (header['scope'] ?? scope).toString(),
      showLetter: (header['show_letter'] ?? showLetter).toString(),
      ruleSource: (header['rule_source'] ?? 'NO_RESULTS').toString(),
      verificationStatus: (header['verification_status'] ?? 'VERIFIED').toString(),
      engineType: (header['engine_type'] ?? 'NO_RESULTS').toString(),
      rows: rows,
      sections: const [],
      noResultsFound: rows.isEmpty,
    );
  }
}