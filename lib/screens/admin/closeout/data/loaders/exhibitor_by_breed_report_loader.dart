import '../../models/base/report_request.dart';
import '../../models/clubs/exhibitor_by_breed_report_data.dart';
import '../closeout_repository.dart';

class ExhibitorByBreedReportLoader {
  ExhibitorByBreedReportLoader(this.repo);

  final CloseoutRepository repo;

  Future<ExhibitorByBreedReportData> load(ReportRequest request) async {
    final scope = (request.scope ?? '').trim().toUpperCase();
    final showLetter = (request.showLetter ?? '').trim().toUpperCase();
    final species = _normalizeSpecies(request.species ?? '');

    if (scope.isEmpty) {
      throw Exception('Exhibitor by Breed requires scope.');
    }
    if (showLetter.isEmpty) {
      throw Exception('Exhibitor by Breed requires showLetter.');
    }

    final header = await _loadHeader(request.showId);
    final sectionId = await _loadSectionId(request.showId, scope, showLetter);

    final resultsResponse = await repo.supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': request.showId,
        'p_section_id': sectionId,
        'p_show_letter': showLetter,
      },
    );

    var resultRows = (resultsResponse as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((row) {
          final rowScope = _text(row, [
            'scope',
            'section_kind',
            'kind',
          ]).trim().toUpperCase();
          return (rowScope.isEmpty || rowScope == scope) &&
              _isActuallyShown(row);
        })
        .toList();

    resultRows = await _filterRowsBySpecies(
      request.showId,
      resultRows,
      species,
    );

    final animalCounts = <String, int>{};
    final addresses = <String, String>{};
    final breeds = <String, String>{};

    for (final row in resultRows) {
      final breed = _text(row, ['breed_name', 'breed']).trim();
      final exhibitor = _exhibitorName(row).trim();
      if (breed.isEmpty || exhibitor.isEmpty) continue;

      final breedKey = _key(breed);
      final exhibitorKey = _key(exhibitor);
      final key = '$breedKey|$exhibitorKey';

      breeds[breedKey] = breed;
      animalCounts[key] = (animalCounts[key] ?? 0) + 1;

      final address = _exhibitorAddress(row);
      if (address.isNotEmpty) addresses[key] = address;
    }

    // Ensure the existing sweepstakes engine has calculated each breed before
    // reading the PDF view. This keeps the new report consistent with the
    // current breed-club sweepstakes report.
    for (final breed in breeds.values) {
      await repo.supabase.rpc(
        'calculate_sweepstakes_for_breed',
        params: {
          'p_show_id': request.showId,
          'p_breed_name': breed,
          'p_scope': scope,
          'p_show_letter': showLetter,
        },
      );
    }

    final pointsResponse = await repo.supabase
        .from('v_sweepstakes_pdf_rows')
        .select()
        .eq('show_id', request.showId)
        .eq('scope', scope)
        .eq('show_letter', showLetter)
        .order('breed_name')
        .order('rank');

    final sectionMap = <String, _SectionAccumulator>{};

    for (final raw in pointsResponse as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final breed = _text(row, ['breed_name']).trim();
      final exhibitor = _text(row, ['exhibitor_name']).trim();
      if (breed.isEmpty || exhibitor.isEmpty) continue;
      if (species.isNotEmpty &&
          !breeds.keys.contains(_key(breed)) &&
          !_rowMatchesSpecies(row, species)) {
        continue;
      }

      final breedKey = _key(breed);
      final exhibitorKey = _key(exhibitor);
      final countKey = '$breedKey|$exhibitorKey';

      final section = sectionMap.putIfAbsent(
        breedKey,
        () => _SectionAccumulator(breed),
      );

      section.rows.add(
        ExhibitorByBreedRow(
          exhibitorName: exhibitor,
          exhibitorAddress: _text(row, ['exhibitor_address']).isNotEmpty
              ? _text(row, ['exhibitor_address'])
              : (addresses[countKey] ?? ''),
          animalsShown: animalCounts[countKey] ?? 0,
          classPoints: _double(row['class_points']),
          varietyPoints: _double(row['variety_points']),
          groupPoints: _double(row['group_points']),
          bobBosPoints: _double(row['bob_points']),
          bisRisPoints: _double(row['bis_points']),
          furWoolPoints: _double(row['fur_points']),
          totalPoints: _double(row['total_points']),
        ),
      );
    }

    // Include exhibitors with animals shown even if they earned zero points.
    for (final entry in animalCounts.entries) {
      final parts = entry.key.split('|');
      if (parts.length != 2) continue;
      final breedKey = parts[0];
      final exhibitorKey = parts[1];

      final section = sectionMap.putIfAbsent(
        breedKey,
        () => _SectionAccumulator(breeds[breedKey] ?? breedKey),
      );

      final alreadyIncluded = section.rows.any(
        (row) => _key(row.exhibitorName) == exhibitorKey,
      );
      if (alreadyIncluded) continue;

      final sourceRow = resultRows.firstWhere(
        (row) =>
            _key(_text(row, ['breed_name', 'breed'])) == breedKey &&
            _key(_exhibitorName(row)) == exhibitorKey,
        orElse: () => <String, dynamic>{},
      );

      section.rows.add(
        ExhibitorByBreedRow(
          exhibitorName: _exhibitorName(sourceRow),
          exhibitorAddress: addresses[entry.key] ?? '',
          animalsShown: entry.value,
          classPoints: 0,
          varietyPoints: 0,
          groupPoints: 0,
          bobBosPoints: 0,
          bisRisPoints: 0,
          furWoolPoints: 0,
          totalPoints: 0,
        ),
      );
    }

    final sections =
        sectionMap.values.map((section) {
          section.rows.sort(
            (a, b) => a.exhibitorName.toLowerCase().compareTo(
              b.exhibitorName.toLowerCase(),
            ),
          );
          return ExhibitorByBreedSection(
            breedName: section.breedName,
            rows: section.rows,
          );
        }).toList()..sort(
          (a, b) =>
              a.breedName.toLowerCase().compareTo(b.breedName.toLowerCase()),
        );

    return ExhibitorByBreedReportData(
      showId: request.showId,
      showName: (request.showName ?? header.showName).trim(),
      showDate: (request.showDate ?? header.showDate).trim(),
      showLocation: header.showLocation,
      hostClubName: header.hostClubName,
      scope: scope,
      showLetter: showLetter,
      secretaryName: header.secretaryName,
      secretaryAddress: header.secretaryAddress,
      secretaryEmail: header.secretaryEmail,
      secretaryPhone: header.secretaryPhone,
      sections: sections,
    );
  }

  Future<String> _loadSectionId(
    String showId,
    String scope,
    String showLetter,
  ) async {
    final response = await repo.supabase
        .from('show_sections')
        .select('id')
        .eq('show_id', showId)
        .eq('kind', scope.toLowerCase())
        .eq('letter', showLetter)
        .eq('is_enabled', true)
        .maybeSingle();

    if (response == null) {
      throw Exception(
        'Could not find enabled $scope $showLetter section for Exhibitor by Breed.',
      );
    }

    final sectionId = (Map<String, dynamic>.from(response)['id'] ?? '')
        .toString()
        .trim();
    if (sectionId.isEmpty) {
      throw Exception(
        'Enabled $scope $showLetter section is missing an ID for Exhibitor by Breed.',
      );
    }

    return sectionId;
  }

  Future<_Header> _loadHeader(String showId) async {
    final showResponse = await repo.supabase
        .from('shows')
        .select()
        .eq('id', showId)
        .maybeSingle();

    final show = showResponse == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(showResponse);

    String hostClubName = '';
    final clubId = (show['club_id'] ?? '').toString().trim();
    if (clubId.isNotEmpty) {
      final clubResponse = await repo.supabase
          .from('clubs')
          .select('name')
          .eq('id', clubId)
          .maybeSingle();
      if (clubResponse != null) {
        hostClubName = (Map<String, dynamic>.from(clubResponse)['name'] ?? '')
            .toString();
      }
    }

    final detailsResponse = await repo.supabase
        .from('show_arba_report_details')
        .select()
        .eq('show_id', showId)
        .maybeSingle();

    final details = detailsResponse == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(detailsResponse);

    String first(List<String> keys) {
      final fromDetails = _text(details, keys);
      if (fromDetails.isNotEmpty) return fromDetails;
      return _text(show, keys);
    }

    final addressParts = <String>[
      first(['secretary_address', 'secretary_address_line1']),
      first(['secretary_address_line2']),
      first(['secretary_city']),
      first(['secretary_state']),
      first(['secretary_zip', 'secretary_postal_code']),
    ].where((e) => e.isNotEmpty).toList();

    return _Header(
      showName: _text(show, ['name', 'show_name']),
      showDate: _text(show, ['start_date', 'show_date']),
      showLocation: _text(show, ['location_name', 'location']),
      hostClubName: hostClubName,
      secretaryName: first(['secretary_name']),
      secretaryAddress: addressParts.join(', '),
      secretaryEmail: first(['secretary_email']),
      secretaryPhone: first(['secretary_phone']),
    );
  }

  static double _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  static String _text(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = (row[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _bool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    final text = (value ?? '').toString().trim().toLowerCase();
    if (text == 'true' || text == 't' || text == '1' || text == 'yes') {
      return true;
    }
    if (text == 'false' || text == 'f' || text == '0' || text == 'no') {
      return false;
    }
    return fallback;
  }

  static String _key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool _isActuallyShown(Map<String, dynamic> row) {
    if (_bool(row['is_test'])) return false;
    if ((row['scratched_at'] ?? '').toString().trim().isNotEmpty) return false;
    if (_bool(row['is_disqualified'])) return false;
    if (!_bool(row['is_shown'], fallback: true)) return false;

    final status = _text(row, ['result_status', 'status']).toLowerCase();
    final dqReason = _text(row, ['disqualified_reason']).toLowerCase();
    final combined = '$status $dqReason';

    if (combined.contains('no show') ||
        combined.contains('scratch') ||
        combined.contains('disqual') ||
        combined.contains('wrong sex') ||
        combined.contains('wrong variety') ||
        combined.contains('wrong class') ||
        combined.contains('overweight') ||
        combined.contains('unworthy')) {
      return false;
    }

    // Fur is reported separately and must not inflate the regular animal count.
    if (_bool(row['is_fur'])) return false;

    return true;
  }

  Future<List<Map<String, dynamic>>> _filterRowsBySpecies(
    String showId,
    List<Map<String, dynamic>> rows,
    String species,
  ) async {
    if (species.isEmpty) return rows;

    final missingSpeciesEntryIds = rows
        .where((row) => _normalizeSpecies(_text(row, ['species'])).isEmpty)
        .map((row) => _text(row, ['entry_id', 'id']).trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final speciesByEntryId = <String, String>{};

    final entryRows = await _loadEntrySpeciesRows(
      showId,
      missingSpeciesEntryIds,
    );
    for (final row in entryRows) {
      final entryId = (row['id'] ?? '').toString().trim();
      final entrySpecies = _normalizeSpecies((row['species'] ?? '').toString());
      if (entryId.isNotEmpty && entrySpecies.isNotEmpty) {
        speciesByEntryId[entryId] = entrySpecies;
      }
    }

    return rows.where((row) {
      final entryId = _text(row, ['entry_id', 'id']).trim();
      final rowSpecies = _normalizeSpecies(
        _text(row, ['species', 'animal_species', 'entry_species']),
      );
      final resolvedSpecies = rowSpecies.isNotEmpty
          ? rowSpecies
          : (speciesByEntryId[entryId] ?? '');

      return resolvedSpecies == species;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadEntrySpeciesRows(
    String showId,
    List<String> entryIds,
  ) async {
    final ids = entryIds.toSet().where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return const <Map<String, dynamic>>[];

    const chunkSize = 100;
    final allRows = <Map<String, dynamic>>[];

    for (var start = 0; start < ids.length; start += chunkSize) {
      final end = start + chunkSize > ids.length
          ? ids.length
          : start + chunkSize;
      final chunk = ids.sublist(start, end);

      final entryRows = await repo.supabase
          .from('entries')
          .select('id, species')
          .eq('show_id', showId)
          .inFilter('id', chunk);

      allRows.addAll(
        (entryRows as List).map((raw) => Map<String, dynamic>.from(raw as Map)),
      );
    }

    return allRows;
  }

  static bool _rowMatchesSpecies(Map<String, dynamic> row, String species) {
    return _normalizeSpecies(
          _text(row, ['species', 'animal_species', 'entry_species']),
        ) ==
        species;
  }

  static String _normalizeSpecies(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'rabbit' || normalized == 'cavy' ? normalized : '';
  }

  static String _exhibitorName(Map<String, dynamic> row) => _text(row, [
    'exhibitor_name',
    'exhibitor_label',
    'showing_name',
    'owner_name',
  ]);

  static String _exhibitorAddress(Map<String, dynamic> row) {
    final direct = _text(row, ['exhibitor_address', 'address']);
    if (direct.isNotEmpty) return direct;

    final parts = <String>[
      _text(row, ['address_line1', 'address1']),
      _text(row, ['address_line2', 'address2']),
      _text(row, ['city']),
      _text(row, ['state', 'state_code']),
      _text(row, ['postal_code', 'zip', 'zip_code']),
    ].where((e) => e.isNotEmpty).toList();

    return parts.join(', ');
  }
}

class _SectionAccumulator {
  final String breedName;
  final List<ExhibitorByBreedRow> rows = [];

  _SectionAccumulator(this.breedName);
}

class _Header {
  final String showName;
  final String showDate;
  final String showLocation;
  final String hostClubName;
  final String secretaryName;
  final String secretaryAddress;
  final String secretaryEmail;
  final String secretaryPhone;

  const _Header({
    this.showName = '',
    this.showDate = '',
    this.showLocation = '',
    this.hostClubName = '',
    this.secretaryName = '',
    this.secretaryAddress = '',
    this.secretaryEmail = '',
    this.secretaryPhone = '',
  });
}
