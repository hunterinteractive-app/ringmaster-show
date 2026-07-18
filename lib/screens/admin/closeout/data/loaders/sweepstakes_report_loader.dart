import '../../models/base/report_request.dart';
import '../../models/clubs/sweepstakes_report_data.dart';
import '../closeout_repository.dart';
import '../../utils/club_report_grouping.dart';

class SweepstakesReportLoader {
  SweepstakesReportLoader(this.repo);

  final CloseoutRepository repo;

  static const String _headerSelect = '''
    show_id,
    breed_name,
    scope,
    show_letter,
    rule_source,
    verification_status,
    engine_type,
    arba_sanction_number,
    national_club_sanction_number,
    host_club_name,
    show_location,
    secretary_name,
    secretary_email,
    secretary_phone
  ''';

  Future<SweepstakesReportData> load(ReportRequest request) async {
    final showId = request.showId;
    final requestedBreedName = (request.breedName ?? '').trim();
    final species = normalizeClubReportSpecies(request.species);
    final breedName = species == 'cavy' ? '' : requestedBreedName;
    final reportBreedName = species == 'cavy'
        ? cavyClubReportBreedName
        : (breedName.isEmpty ? 'All Breeds' : breedName);
    final clubName = (request.clubName ?? '').trim();
    final scope = (request.scope ?? '').trim().toUpperCase();
    final showLetter = (request.showLetter ?? '').trim().toUpperCase();
    final isNationalShow = request.isNationalShow;

    if (scope.isEmpty) {
      throw Exception('Sweepstakes report requires scope.');
    }
    if (showLetter.isEmpty) {
      throw Exception('Sweepstakes report requires showLetter.');
    }

    final showHeader = await _loadShowHeader(showId);

    final speciesBreedNames = breedName.isEmpty && species.isNotEmpty
        ? await _loadBreedNamesForSpecies(
            showId: showId,
            scope: scope,
            showLetter: showLetter,
            species: species,
          )
        : const <String>[];

    if (species == 'cavy') {
      await _recalculateCavySweepstakes(
        showId: showId,
        scope: scope,
        showLetter: showLetter,
      );
    } else if (breedName.isNotEmpty) {
      await _recalculateSweepstakes(
        showId: showId,
        breedName: breedName,
        scope: scope,
        showLetter: showLetter,
      );
    } else if (speciesBreedNames.isNotEmpty) {
      for (final speciesBreedName in speciesBreedNames) {
        await _recalculateSweepstakes(
          showId: showId,
          breedName: speciesBreedName,
          scope: scope,
          showLetter: showLetter,
        );
      }
    }

    final breedSanctionNumber = breedName.isEmpty
        ? ''
        : await _loadBreedSanctionNumber(
            showId: showId,
            breedName: breedName,
            clubName: clubName,
            scope: scope,
            showLetter: showLetter,
          );

    final topBreedRows = isNationalShow
        ? await _loadTopBreedRows(
            showId: showId,
            scope: scope,
            showLetter: showLetter,
          )
        : const <SweepstakesTopBreedRow>[];

    if (showLetter == 'ALL') {
      final lettersResponse = await repo.supabase
          .from('show_sections')
          .select('letter')
          .eq('show_id', showId)
          .eq('is_enabled', true)
          .eq('kind', scope.toLowerCase())
          .order('letter');

      final letters =
          (lettersResponse as List)
              .map((e) => (e['letter'] ?? '').toString().trim().toUpperCase())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      final sections = <SweepstakesReportSection>[];
      Map<String, dynamic>? firstHeader;

      for (final letter in letters) {
        var rowsQuery = repo.supabase
            .from('v_sweepstakes_pdf_rows')
            .select()
            .eq('show_id', showId)
            .eq('scope', scope)
            .eq('show_letter', letter);

        if (breedName.isNotEmpty) {
          rowsQuery = rowsQuery.ilike('breed_name', breedName);
        } else if (speciesBreedNames.isNotEmpty) {
          rowsQuery = rowsQuery.inFilter('breed_name', speciesBreedNames);
        } else if (species.isNotEmpty) {
          rowsQuery = rowsQuery.eq('breed_name', '__NO_MATCH__');
        }

        final rowsResponse = await rowsQuery.order('rank', ascending: true);

        final rawRows = (rowsResponse as List)
            .map((e) => SweepstakesReportRow.fromMap(e as Map<String, dynamic>))
            .toList();
        final rows = _normalizeRowsForReport(
          rawRows,
          species: species,
          breedName: breedName,
        );

        var headerQuery = repo.supabase
            .from('v_sweepstakes_pdf_rows')
            .select(_headerSelect)
            .eq('show_id', showId)
            .eq('scope', scope)
            .eq('show_letter', letter);

        if (breedName.isNotEmpty) {
          headerQuery = headerQuery.ilike('breed_name', breedName);
        } else if (speciesBreedNames.isNotEmpty) {
          headerQuery = headerQuery.inFilter('breed_name', speciesBreedNames);
        } else if (species.isNotEmpty) {
          headerQuery = headerQuery.eq('breed_name', '__NO_MATCH__');
        }

        final headerResponse = await headerQuery.limit(1).maybeSingle();

        final header = headerResponse == null
            ? <String, dynamic>{
                'show_id': showId,
                'breed_name': reportBreedName,
                'scope': scope,
                'show_letter': letter,
                'rule_source': 'NO_RESULTS',
                'verification_status': 'VERIFIED',
                'engine_type': 'NO_RESULTS',
              }
            : Map<String, dynamic>.from(headerResponse);

        firstHeader ??= header;

        sections.add(
          SweepstakesReportSection(
            showLetter: (header['show_letter'] ?? letter).toString(),
            ruleSource: (header['rule_source'] ?? 'NO_RESULTS').toString(),
            verificationStatus: (header['verification_status'] ?? 'VERIFIED')
                .toString(),
            engineType: (header['engine_type'] ?? 'NO_RESULTS').toString(),
            rows: rows,
            noResultsFound: rows.isEmpty,
          ),
        );
      }

      final header = firstHeader ?? <String, dynamic>{};

      return SweepstakesReportData(
        showId: showId,
        breedName: reportBreedName,
        scope: scope,
        showLetter: 'ALL',
        species: species,
        isNationalShow: isNationalShow,
        topBreedRows: topBreedRows,
        ruleSource: sections.isNotEmpty
            ? sections.first.ruleSource
            : 'NO_RESULTS',
        verificationStatus: sections.isNotEmpty
            ? sections.first.verificationStatus
            : 'VERIFIED',
        engineType: sections.isNotEmpty
            ? sections.first.engineType
            : 'NO_RESULTS',
        arbaSanction: (header['arba_sanction_number'] ?? '').toString(),
        nationalClubSanction: (header['national_club_sanction_number'] ?? '')
            .toString(),
        breedSanctionNumber: breedSanctionNumber,
        breedClubName: clubName,
        hostClubName: _firstNotEmpty(
          (header['host_club_name'] ?? '').toString(),
          showHeader.hostClubName,
        ),
        showLocation: _firstNotEmpty(
          (header['show_location'] ?? '').toString(),
          showHeader.showLocation,
        ),
        secretaryName: _firstNotEmpty(
          showHeader.secretaryName,
          (header['secretary_name'] ?? '').toString(),
        ),
        secretaryEmail: _firstNotEmpty(
          showHeader.secretaryEmail,
          (header['secretary_email'] ?? '').toString(),
        ),
        secretaryPhone: _firstNotEmpty(
          showHeader.secretaryPhone,
          (header['secretary_phone'] ?? '').toString(),
        ),
        rows: const [],
        sections: sections,
        noResultsFound: sections.every((s) => s.noResultsFound),
      );
    }

    var rowsQuery = repo.supabase
        .from('v_sweepstakes_pdf_rows')
        .select()
        .eq('show_id', showId)
        .eq('scope', scope)
        .eq('show_letter', showLetter);

    if (breedName.isNotEmpty) {
      rowsQuery = rowsQuery.ilike('breed_name', breedName);
    } else if (speciesBreedNames.isNotEmpty) {
      rowsQuery = rowsQuery.inFilter('breed_name', speciesBreedNames);
    } else if (species.isNotEmpty) {
      rowsQuery = rowsQuery.eq('breed_name', '__NO_MATCH__');
    }

    final rowsResponse = await rowsQuery.order('rank', ascending: true);

    final rawRows = (rowsResponse as List)
        .map((e) => SweepstakesReportRow.fromMap(e as Map<String, dynamic>))
        .toList();
    final rows = _normalizeRowsForReport(
      rawRows,
      species: species,
      breedName: breedName,
    );

    var headerQuery = repo.supabase
        .from('v_sweepstakes_pdf_rows')
        .select(_headerSelect)
        .eq('show_id', showId)
        .eq('scope', scope)
        .eq('show_letter', showLetter);

    if (breedName.isNotEmpty) {
      headerQuery = headerQuery.ilike('breed_name', breedName);
    } else if (speciesBreedNames.isNotEmpty) {
      headerQuery = headerQuery.inFilter('breed_name', speciesBreedNames);
    } else if (species.isNotEmpty) {
      headerQuery = headerQuery.eq('breed_name', '__NO_MATCH__');
    }

    final headerResponse = await headerQuery.limit(1).maybeSingle();

    final header = headerResponse == null
        ? <String, dynamic>{
            'show_id': showId,
            'breed_name': reportBreedName,
            'scope': scope,
            'show_letter': showLetter,
            'rule_source': 'NO_RESULTS',
            'verification_status': 'VERIFIED',
            'engine_type': 'NO_RESULTS',
          }
        : Map<String, dynamic>.from(headerResponse);

    return SweepstakesReportData(
      showId: (header['show_id'] ?? showId).toString(),
      breedName: reportBreedName,
      scope: (header['scope'] ?? scope).toString(),
      showLetter: (header['show_letter'] ?? showLetter).toString(),
      isNationalShow: isNationalShow,
      topBreedRows: topBreedRows,
      ruleSource: (header['rule_source'] ?? 'NO_RESULTS').toString(),
      verificationStatus: (header['verification_status'] ?? 'VERIFIED')
          .toString(),
      engineType: (header['engine_type'] ?? 'NO_RESULTS').toString(),
      species: species,
      arbaSanction: (header['arba_sanction_number'] ?? '').toString(),
      nationalClubSanction: (header['national_club_sanction_number'] ?? '')
          .toString(),
      breedSanctionNumber: breedSanctionNumber,
      breedClubName: clubName,
      hostClubName: _firstNotEmpty(
        (header['host_club_name'] ?? '').toString(),
        showHeader.hostClubName,
      ),
      showLocation: _firstNotEmpty(
        (header['show_location'] ?? '').toString(),
        showHeader.showLocation,
      ),
      secretaryName: _firstNotEmpty(
        showHeader.secretaryName,
        (header['secretary_name'] ?? '').toString(),
      ),
      secretaryEmail: _firstNotEmpty(
        showHeader.secretaryEmail,
        (header['secretary_email'] ?? '').toString(),
      ),
      secretaryPhone: _firstNotEmpty(
        showHeader.secretaryPhone,
        (header['secretary_phone'] ?? '').toString(),
      ),
      rows: rows,
      sections: const [],
      noResultsFound: rows.isEmpty,
    );
  }

  Future<void> _recalculateSweepstakes({
    required String showId,
    required String breedName,
    required String scope,
    required String showLetter,
  }) async {
    if (showLetter == 'ALL') {
      final lettersResponse = await repo.supabase
          .from('show_sections')
          .select('letter')
          .eq('show_id', showId)
          .eq('is_enabled', true)
          .eq('kind', scope.toLowerCase())
          .order('letter');

      final letters =
          (lettersResponse as List)
              .map((e) => (e['letter'] ?? '').toString().trim().toUpperCase())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      for (final letter in letters) {
        await repo.supabase.rpc(
          'calculate_sweepstakes_for_breed',
          params: {
            'p_show_id': showId,
            'p_breed_name': breedName,
            'p_scope': scope,
            'p_show_letter': letter,
          },
        );
      }

      return;
    }

    await repo.supabase.rpc(
      'calculate_sweepstakes_for_breed',
      params: {
        'p_show_id': showId,
        'p_breed_name': breedName,
        'p_scope': scope,
        'p_show_letter': showLetter,
      },
    );
  }

  Future<void> _recalculateCavySweepstakes({
    required String showId,
    required String scope,
    required String showLetter,
  }) async {
    await repo.supabase.rpc(
      'calculate_cavy_sweepstakes_for_section',
      params: {
        'p_show_id': showId,
        'p_scope': scope,
        'p_show_letter': showLetter,
      },
    );
  }

  Future<List<String>> _loadBreedNamesForSpecies({
    required String showId,
    required String scope,
    required String showLetter,
    required String species,
  }) async {
    final sectionQuery = repo.supabase
        .from('show_sections')
        .select('id, letter')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .eq('kind', scope.toLowerCase());

    final sectionResponse = showLetter == 'ALL'
        ? await sectionQuery
        : await sectionQuery.eq('letter', showLetter);

    final sectionRows = (sectionResponse as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final breeds = <String>{};

    for (final section in sectionRows) {
      final sectionId = (section['id'] ?? '').toString().trim();
      final letter = (section['letter'] ?? '').toString().trim().toUpperCase();
      if (sectionId.isEmpty) continue;

      final response = await repo.supabase.rpc(
        'report_results_entry_rows',
        params: {
          'p_show_id': showId,
          'p_section_id': sectionId,
          'p_show_letter': showLetter == 'ALL' ? letter : showLetter,
        },
      );

      for (final raw in (response as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final rowSpecies = normalizeClubReportSpecies(
          (row['species'] ??
                  row['animal_species'] ??
                  row['entry_species'] ??
                  '')
              .toString(),
        );
        final breedName = (row['breed_name'] ?? row['breed'] ?? '')
            .toString()
            .trim();
        final rowMatchesSpecies =
            rowSpecies == species ||
            (rowSpecies.isEmpty &&
                species == 'cavy' &&
                isKnownCavyBreed(breedName));
        if (rowMatchesSpecies && breedName.isNotEmpty) {
          breeds.add(breedName);
        }
      }
    }

    return breeds.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<SweepstakesReportRow> _normalizeRowsForReport(
    List<SweepstakesReportRow> rows, {
    required String species,
    required String breedName,
  }) {
    if (species != 'cavy' || breedName.isNotEmpty || rows.isEmpty) {
      return rows;
    }

    return combineSweepstakesRowsByExhibitor(rows);
  }

  Future<List<SweepstakesTopBreedRow>> _loadTopBreedRows({
    required String showId,
    required String scope,
    required String showLetter,
  }) async {
    final rows = await repo.supabase.rpc(
      'report_top_10_breeds',
      params: {
        'p_show_id': showId,
        'p_scope': scope,
        'p_show_letter': showLetter,
      },
    );

    return (rows as List)
        .map(
          (e) => SweepstakesTopBreedRow.fromMap(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<String> _loadBreedSanctionNumber({
    required String showId,
    required String breedName,
    required String clubName,
    required String scope,
    required String showLetter,
  }) async {
    final sectionQuery = repo.supabase
        .from('show_sections')
        .select('id')
        .eq('show_id', showId)
        .eq('kind', scope.toLowerCase());

    final sectionResponse = showLetter == 'ALL'
        ? await sectionQuery.limit(1).maybeSingle()
        : await sectionQuery.eq('letter', showLetter).maybeSingle();

    final sectionId = sectionResponse == null
        ? ''
        : (Map<String, dynamic>.from(sectionResponse)['id'] ?? '').toString();

    var query = repo.supabase
        .from('show_sanctions')
        .select('sanction_number')
        .eq('show_id', showId)
        .ilike('breed_name', breedName)
        .neq('sanctioning_body', 'ARBA');

    if (clubName.isNotEmpty) {
      query = query.ilike('club_name', clubName);
    }

    if (sectionId.isNotEmpty) {
      query = query.eq('section_id', sectionId);
    }

    final response = await query.limit(1).maybeSingle();
    if (response == null) return '';

    return (Map<String, dynamic>.from(response)['sanction_number'] ?? '')
        .toString()
        .trim();
  }

  Future<_ShowHeader> _loadShowHeader(String showId) async {
    final showResponse = await repo.supabase
        .from('shows')
        .select('club_id, location_name, secretary_email, secretary_phone')
        .eq('id', showId)
        .maybeSingle();

    if (showResponse == null) return const _ShowHeader();

    final show = Map<String, dynamic>.from(showResponse);
    final clubId = (show['club_id'] ?? '').toString();

    String hostClubName = '';

    if (clubId.isNotEmpty) {
      final clubResponse = await repo.supabase
          .from('clubs')
          .select('name')
          .eq('id', clubId)
          .maybeSingle();

      if (clubResponse != null) {
        final club = Map<String, dynamic>.from(clubResponse);
        hostClubName = (club['name'] ?? '').toString();
      }
    }

    final arbaDetailsResponse = await repo.supabase
        .from('show_arba_report_details')
        .select('secretary_name, secretary_email, secretary_phone')
        .eq('show_id', showId)
        .maybeSingle();

    final arbaDetails = arbaDetailsResponse == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(arbaDetailsResponse);

    return _ShowHeader(
      hostClubName: hostClubName,
      showLocation: (show['location_name'] ?? '').toString(),
      secretaryName: _firstNotEmpty(
        (arbaDetails['secretary_name'] ?? '').toString(),
        '',
      ),
      secretaryEmail: _firstNotEmpty(
        (arbaDetails['secretary_email'] ?? '').toString(),
        (show['secretary_email'] ?? '').toString(),
      ),
      secretaryPhone: _firstNotEmpty(
        (arbaDetails['secretary_phone'] ?? '').toString(),
        (show['secretary_phone'] ?? '').toString(),
      ),
    );
  }

  String _firstNotEmpty(String first, String second) {
    final a = first.trim();
    return a.isNotEmpty ? a : second.trim();
  }
}

List<SweepstakesReportRow> combineSweepstakesRowsByExhibitor(
  List<SweepstakesReportRow> rows,
) {
  final byExhibitor = <String, _SweepstakesAccumulator>{};

  for (final row in rows) {
    final key = [
      row.exhibitorName.trim().toLowerCase(),
      row.exhibitorAddress.trim().toLowerCase(),
    ].join('|');
    final accumulator = byExhibitor.putIfAbsent(
      key,
      () => _SweepstakesAccumulator(
        exhibitorName: row.exhibitorName,
        exhibitorAddress: row.exhibitorAddress,
      ),
    );
    accumulator.add(row);
  }

  final combined = byExhibitor.values.toList()
    ..sort((a, b) {
      final totalCmp = b.totalPoints.compareTo(a.totalPoints);
      if (totalCmp != 0) return totalCmp;
      return a.exhibitorName.toLowerCase().compareTo(
        b.exhibitorName.toLowerCase(),
      );
    });

  return [
    for (var i = 0; i < combined.length; i++) combined[i].toRow(rank: i + 1),
  ];
}

class _SweepstakesAccumulator {
  _SweepstakesAccumulator({
    required this.exhibitorName,
    required this.exhibitorAddress,
  });

  final String exhibitorName;
  final String exhibitorAddress;
  double classPoints = 0;
  double arbaClassPoints = 0;
  double varietyPoints = 0;
  double groupPoints = 0;
  double bobPoints = 0;
  double bisPoints = 0;
  double furPoints = 0;
  double totalPoints = 0;

  void add(SweepstakesReportRow row) {
    classPoints += row.classPoints;
    arbaClassPoints += row.arbaClassPoints;
    varietyPoints += row.varietyPoints;
    groupPoints += row.groupPoints;
    bobPoints += row.bobPoints;
    bisPoints += row.bisPoints;
    furPoints += row.furPoints;
    totalPoints += row.totalPoints;
  }

  SweepstakesReportRow toRow({required int rank}) {
    return SweepstakesReportRow(
      rank: rank,
      exhibitorName: exhibitorName,
      exhibitorAddress: exhibitorAddress,
      classPoints: classPoints,
      arbaClassPoints: arbaClassPoints,
      varietyPoints: varietyPoints,
      groupPoints: groupPoints,
      bobPoints: bobPoints,
      bisPoints: bisPoints,
      furPoints: furPoints,
      totalPoints: totalPoints,
    );
  }
}

class _ShowHeader {
  final String hostClubName;
  final String showLocation;
  final String secretaryName;
  final String secretaryEmail;
  final String secretaryPhone;

  const _ShowHeader({
    this.hostClubName = '',
    this.showLocation = '',
    this.secretaryName = '',
    this.secretaryEmail = '',
    this.secretaryPhone = '',
  });
}
