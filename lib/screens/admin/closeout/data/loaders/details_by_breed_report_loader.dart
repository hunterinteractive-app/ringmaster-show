import 'package:intl/intl.dart';

import '../../models/base/report_request.dart';
import '../../models/clubs/details_by_breed_report_data.dart';
import '../closeout_repository.dart';

class DetailsByBreedReportLoader {
  DetailsByBreedReportLoader(this.repo);

  final CloseoutRepository repo;

  Future<DetailsByBreedReportData> load(ReportRequest request) async {
    final scope = (request.scope ?? '').trim().toUpperCase();
    final showLetter = (request.showLetter ?? '').trim().toUpperCase();
    final species = _normalizeSpecies(request.species ?? '');

    if (scope.isEmpty) {
      throw Exception('Details by Breed requires scope.');
    }
    if (showLetter.isEmpty) {
      throw Exception('Details by Breed requires showLetter.');
    }

    final header = await _loadHeader(request.showId, scope, showLetter);
    final sectionId = (request.sectionId ?? '').trim().isNotEmpty
        ? request.sectionId!.trim()
        : await _loadSectionId(request.showId, scope, showLetter);

    final response = await repo.supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': request.showId,
        'p_section_id': sectionId,
        'p_show_letter': showLetter,
      },
    );

    var rows = (response as List)
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

    rows = await _filterRowsBySpecies(request.showId, rows, species);

    final judgeIdsByEntryId = await _loadJudgeIdsByEntryId(
      request.showId,
      rows,
    );
    final judgeNamesById = await _loadJudgeNames(
      request.showId,
      judgeIdsByEntryId.values.toSet(),
    );
    final awardsByEntryId = await _loadEntryAwards(rows);

    final showAnimals = rows.length;
    final showExhibitors = rows
        .map(_exhibitorKey)
        .where((e) => e.isNotEmpty)
        .toSet()
        .length;

    final overallWinners = <DetailsByBreedOverallWinner>[];
    final grouped = <String, _BreedAccumulator>{};

    for (final row in rows) {
      final breed = _text(row, ['breed_name', 'breed']).trim();
      if (breed.isEmpty) continue;

      final variety = _text(row, [
        'variety_name',
        'variety',
        'group_name',
        'group',
      ]).trim();
      final className = _cleanClassName(
        _text(row, ['class_name', 'age_class', 'class']),
      );
      final sex = _cleanSex(_text(row, ['sex', 'gender']));
      final exhibitorName = _exhibitorName(row);
      final exhibitorKey = _exhibitorKey(row);
      final entryId = _text(row, ['entry_id', 'id']).trim();
      final awards = <String>{
        ..._awardCodes(row),
        ...?awardsByEntryId[entryId],
      };
      final earNumber = _text(row, ['tattoo', 'ear_number', 'ear_no', 'ear']);
      final animalName = _text(row, ['animal_name', 'registered_name', 'name']);
      final placement = _placement(row['placement']);
      final judgeId =
          (judgeIdsByEntryId[entryId] ??
                  _text(row, ['judged_by_show_judge_id', 'show_judge_id']))
              .trim();
      final judgeName =
          _text(row, [
            'judge_name',
            'show_judge_name',
            'judged_by_name',
          ]).trim().isNotEmpty
          ? _text(row, [
              'judge_name',
              'show_judge_name',
              'judged_by_name',
            ]).trim()
          : (judgeNamesById[judgeId] ?? '');

      final breedAcc = grouped.putIfAbsent(
        _key(breed),
        () => _BreedAccumulator(breed),
      );
      breedAcc.animalsShown++;
      if (exhibitorKey.isNotEmpty) breedAcc.exhibitors.add(exhibitorKey);
      if (breedAcc.judgeName.isEmpty && judgeName.isNotEmpty) {
        breedAcc.judgeName = judgeName;
      }

      final varietyLabel = variety.isEmpty ? 'Standard' : variety;
      final varietyAcc = breedAcc.varieties.putIfAbsent(
        _key(varietyLabel),
        () => _VarietyAccumulator(varietyLabel),
      );
      varietyAcc.animalsShown++;
      if (exhibitorKey.isNotEmpty) varietyAcc.exhibitors.add(exhibitorKey);

      final classKey = '${_key(className)}|${_key(sex)}';
      final classAcc = varietyAcc.classes.putIfAbsent(
        classKey,
        () => _ClassAccumulator(className, sex),
      );
      classAcc.animalsShown++;
      if (exhibitorKey.isNotEmpty) classAcc.exhibitors.add(exhibitorKey);

      if (placement > 0) {
        classAcc.placements.add(
          DetailsByBreedPlacementRow(
            placement: placement,
            earNumber: earNumber,
            animalName: animalName,
            exhibitorName: exhibitorName,
            awards: awards.toList()..sort(),
          ),
        );
      }

      DetailsByBreedAwardRow awardRow(
        String award,
        int animals,
        int exhibitors,
      ) {
        return DetailsByBreedAwardRow(
          award: award,
          earNumber: earNumber,
          varietyName: variety,
          className: className,
          sex: sex,
          exhibitorName: exhibitorName,
          animalsShown: animals,
          exhibitorCount: exhibitors,
          additionalAwards: awards.where((a) => a != award).toList()..sort(),
        );
      }

      if (awards.contains('BOB')) {
        breedAcc.bob = awardRow(
          'BOB',
          breedAcc.animalsShown,
          breedAcc.exhibitors.length,
        );
      }
      if (awards.contains('BOSB') || awards.contains('BOS')) {
        breedAcc.bosb = awardRow(
          'BOSB',
          breedAcc.animalsShown,
          breedAcc.exhibitors.length,
        );
      }
      if (awards.contains('BOV')) {
        varietyAcc.bov = awardRow(
          'BOV',
          varietyAcc.animalsShown,
          varietyAcc.exhibitors.length,
        );
      }
      if (awards.contains('BOSV')) {
        varietyAcc.bosv = awardRow(
          'BOSV',
          varietyAcc.animalsShown,
          varietyAcc.exhibitors.length,
        );
      }

      if (awards.isNotEmpty) {
        final sortedAwards = awards.toList()
          ..sort(
            (a, b) => _specialAwardRank(a).compareTo(_specialAwardRank(b)),
          );
        breedAcc.specialAwards.add(
          DetailsByBreedAwardRow(
            award: sortedAwards.join(', '),
            earNumber: earNumber,
            varietyName: varietyLabel,
            className: className,
            sex: sex,
            exhibitorName: exhibitorName,
            animalsShown: breedAcc.animalsShown,
            exhibitorCount: breedAcc.exhibitors.length,
            additionalAwards: const [],
          ),
        );
      }

      for (final award in awards.where(_isOverallAward)) {
        overallWinners.add(
          DetailsByBreedOverallWinner(
            award: _displayOverallAward(award),
            earNumber: earNumber,
            breedName: breed,
            varietyName: variety,
            className: className,
            sex: sex,
            exhibitorName: exhibitorName,
            showAnimals: showAnimals,
            showExhibitors: showExhibitors,
            additionalAwards: awards.where((a) => a != award).toList()..sort(),
          ),
        );
      }
    }

    final breeds =
        grouped.values.map((breed) {
          final varieties =
              breed.varieties.values.map((variety) {
                final classes = variety.classes.values.map((clazz) {
                  clazz.placements.sort(
                    (a, b) => a.placement.compareTo(b.placement),
                  );
                  return DetailsByBreedClassSection(
                    className: clazz.className,
                    sex: clazz.sex,
                    animalsShown: clazz.animalsShown,
                    exhibitorCount: clazz.exhibitors.length,
                    placements: clazz.placements,
                  );
                }).toList()..sort(_compareClasses);

                return DetailsByBreedVarietySection(
                  varietyName: variety.varietyName,
                  animalsShown: variety.animalsShown,
                  exhibitorCount: variety.exhibitors.length,
                  bov: variety.bov,
                  bosv: variety.bosv,
                  classes: classes,
                );
              }).toList()..sort(
                (a, b) => a.varietyName.toLowerCase().compareTo(
                  b.varietyName.toLowerCase(),
                ),
              );

          return DetailsByBreedBreedSection(
            breedName: breed.breedName,
            judgeName: breed.judgeName,
            animalsShown: breed.animalsShown,
            exhibitorCount: breed.exhibitors.length,
            bob: breed.bob,
            bosb: breed.bosb,
            specialAwards: breed.specialAwards
              ..sort(
                (a, b) => _specialAwardRank(
                  a.award.split(',').first.trim(),
                ).compareTo(_specialAwardRank(b.award.split(',').first.trim())),
              ),
            varieties: varieties,
          );
        }).toList()..sort(
          (a, b) =>
              a.breedName.toLowerCase().compareTo(b.breedName.toLowerCase()),
        );

    overallWinners.sort(
      (a, b) =>
          _overallAwardRank(a.award).compareTo(_overallAwardRank(b.award)),
    );

    return DetailsByBreedReportData(
      showId: request.showId,
      showName: (request.showName ?? header.showName).trim(),
      showDate: (request.showDate ?? header.showDate).trim(),
      reportDate: DateFormat('MM-dd-yyyy').format(DateTime.now()),
      showLocation: header.showLocation,
      hostClubName: header.hostClubName,
      scope: scope,
      showLetter: showLetter,
      showType: header.showType,
      specialtyStatus: header.specialtyStatus,
      arbaSanctionNumber: header.arbaSanctionNumber,
      stateClubName: header.stateClubName,
      stateClubSanctionNumber: header.stateClubSanctionNumber,
      secretaryName: header.secretaryName,
      secretaryAddress: header.secretaryAddress,
      secretaryEmail: header.secretaryEmail,
      secretaryPhone: header.secretaryPhone,
      superintendentName: header.superintendentName,
      overallWinners: overallWinners,
      breeds: breeds,
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
        'Could not find enabled $scope $showLetter section for Details by Breed.',
      );
    }

    final sectionId = (Map<String, dynamic>.from(response)['id'] ?? '')
        .toString()
        .trim();
    if (sectionId.isEmpty) {
      throw Exception(
        'Enabled $scope $showLetter section is missing an ID for Details by Breed.',
      );
    }

    return sectionId;
  }

  Future<_Header> _loadHeader(
    String showId,
    String scope,
    String showLetter,
  ) async {
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

    final sectionResponse = await repo.supabase
        .from('show_sections')
        .select('id')
        .eq('show_id', showId)
        .eq('kind', scope.toLowerCase())
        .eq('letter', showLetter)
        .eq('is_enabled', true)
        .maybeSingle();

    final sectionId = sectionResponse == null
        ? ''
        : (Map<String, dynamic>.from(sectionResponse)['id'] ?? '').toString();

    Map<String, dynamic> arbaSanction = {};
    Map<String, dynamic> stateClubSanction = {};
    if (sectionId.isNotEmpty) {
      final sanctionsResponse = await repo.supabase
          .from('show_sanctions')
          .select('sanctioning_body, club_name, sanction_number, section_id')
          .eq('show_id', showId)
          .eq('section_id', sectionId);

      for (final raw in (sanctionsResponse as List)) {
        final sanction = Map<String, dynamic>.from(raw as Map);
        final body = (sanction['sanctioning_body'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        if (body == 'ARBA') arbaSanction = sanction;
        if (body == 'STATE CLUB') stateClubSanction = sanction;
      }
    }

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
      showType: first(['show_type', 'classification_type', 'type']),
      specialtyStatus: _bool(show['is_single_breed_show']) ? 'Yes' : 'No',
      arbaSanctionNumber: _text(arbaSanction, ['sanction_number']),
      stateClubName: _text(stateClubSanction, ['club_name']),
      stateClubSanctionNumber: _text(stateClubSanction, ['sanction_number']),
      secretaryName: first(['secretary_name']),
      secretaryAddress: addressParts.join(', '),
      secretaryEmail: first(['secretary_email']),
      secretaryPhone: first(['secretary_phone']),
      superintendentName: first(['superintendent_name', 'superintendent']),
    );
  }

  Future<Map<String, String>> _loadJudgeIdsByEntryId(
    String showId,
    List<Map<String, dynamic>> rows,
  ) async {
    final entryIds = rows
        .map((row) => _text(row, ['entry_id', 'id']).trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (entryIds.isEmpty) return const <String, String>{};

    final result = <String, String>{};
    const chunkSize = 100;

    for (var start = 0; start < entryIds.length; start += chunkSize) {
      final end = (start + chunkSize < entryIds.length)
          ? start + chunkSize
          : entryIds.length;
      final chunk = entryIds.sublist(start, end);

      final response = await repo.supabase
          .from('entries')
          .select('id, judged_by_show_judge_id')
          .eq('show_id', showId)
          .inFilter('id', chunk);

      for (final raw in (response as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final entryId = (row['id'] ?? '').toString().trim();
        final showJudgeId = (row['judged_by_show_judge_id'] ?? '')
            .toString()
            .trim();

        if (entryId.isNotEmpty && showJudgeId.isNotEmpty) {
          result[entryId] = showJudgeId;
        }
      }
    }

    return result;
  }

  Future<Map<String, String>> _loadJudgeNames(
    String showId,
    Set<String> usedJudgeIds,
  ) async {
    if (usedJudgeIds.isEmpty) return const <String, String>{};

    final showJudgeResponse = await repo.supabase
        .from('show_judges')
        .select('judge_id')
        .eq('show_id', showId);

    final showJudgeIds = (showJudgeResponse as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .map((row) => (row['judge_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty && usedJudgeIds.contains(id))
        .toSet()
        .toList();

    final idsToResolve = showJudgeIds.isNotEmpty
        ? showJudgeIds
        : usedJudgeIds.toList();

    if (idsToResolve.isEmpty) return const <String, String>{};

    final result = <String, String>{};

    Future<void> loadFromTable(String tableName) async {
      final unresolvedIds = idsToResolve
          .where((judgeId) => !result.containsKey(judgeId))
          .toList();
      if (unresolvedIds.isEmpty) return;

      try {
        const chunkSize = 100;
        for (var start = 0; start < unresolvedIds.length; start += chunkSize) {
          final end = start + chunkSize > unresolvedIds.length
              ? unresolvedIds.length
              : start + chunkSize;
          final chunk = unresolvedIds.sublist(start, end);

          final response = await repo.supabase
              .from(tableName)
              .select()
              .inFilter('id', chunk);

          for (final raw in (response as List)) {
            final row = Map<String, dynamic>.from(raw as Map);
            final judgeId = _text(row, [
              'id',
              'judge_id',
              'arba_judge_id',
            ]).trim();
            if (judgeId.isEmpty) continue;

            final name = _judgeNameFromRow(row);
            if (name.isNotEmpty) {
              result[judgeId] = name;
            }
          }
        }
      } catch (_) {
        // This installation may not contain this judge table.
      }
    }

    await loadFromTable('judges');
    await loadFromTable('arba_judges');

    return result;
  }

  static String _judgeNameFromRow(Map<String, dynamic> row) {
    final direct = _text(row, [
      'display_name',
      'judge_name',
      'full_name',
      'name',
      'formatted_name',
    ]).trim();
    if (direct.isNotEmpty) return direct;

    final first = _text(row, [
      'first_name',
      'judge_first_name',
      'firstname',
    ]).trim();
    final last = _text(row, [
      'last_name',
      'judge_last_name',
      'lastname',
    ]).trim();

    return [first, last].where((part) => part.isNotEmpty).join(' ').trim();
  }

  Future<Map<String, Set<String>>> _loadEntryAwards(
    List<Map<String, dynamic>> rows,
  ) async {
    final entryIds = rows
        .map((row) => _text(row, ['entry_id', 'id']).trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (entryIds.isEmpty) return const <String, Set<String>>{};

    final result = <String, Set<String>>{};

    const chunkSize = 100;
    for (var start = 0; start < entryIds.length; start += chunkSize) {
      final end = (start + chunkSize < entryIds.length)
          ? start + chunkSize
          : entryIds.length;
      final chunk = entryIds.sublist(start, end);

      final response = await repo.supabase
          .from('entry_awards')
          .select()
          .inFilter('entry_id', chunk);

      for (final raw in (response as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final entryId = (row['entry_id'] ?? '').toString().trim();
        if (entryId.isEmpty) continue;

        final award = _text(row, [
          'award_code',
          'award',
          'code',
          'special_award',
        ]).trim().toUpperCase();

        if (award.isNotEmpty) {
          result.putIfAbsent(entryId, () => <String>{}).add(award);
        }
      }
    }

    return result;
  }

  static int _specialAwardRank(String award) {
    final code = award.trim().toUpperCase();
    const ranks = <String, int>{
      'BIS': 0,
      'RIS': 1,
      'BRIS': 1,
      'BIS-CAVY': 2,
      'BISCAVY': 2,
      'BIS_CAVY': 2,
      'B4C': 3,
      'B6C': 4,
      'BOB': 10,
      'BOSB': 11,
      'BOS': 11,
      'BOV': 20,
      'BOSV': 21,
      'BJB': 30,
      'BIB': 31,
      'BSB': 32,
      'BJV': 33,
      'BIV': 34,
      'BSV': 35,
      'HM': 90,
    };
    return ranks[code] ?? 50;
  }

  static int _compareClasses(
    DetailsByBreedClassSection a,
    DetailsByBreedClassSection b,
  ) {
    final age = _classRank(a.className).compareTo(_classRank(b.className));
    if (age != 0) return age;
    return _sexRank(a.sex).compareTo(_sexRank(b.sex));
  }

  static int _classRank(String value) {
    final v = value.toLowerCase();
    if (v.contains('senior')) return 0;
    if (v.contains('intermediate') || v.contains('6-8')) return 1;
    if (v.contains('junior')) return 2;
    return 9;
  }

  static int _sexRank(String value) {
    final v = value.toLowerCase();
    if (v.contains('buck') || v.contains('boar')) return 0;
    if (v.contains('doe') || v.contains('sow')) return 1;
    return 9;
  }

  static String _cleanClassName(String value) {
    final cleaned = value
        .replaceAll(
          RegExp(r'\b(buck|doe|boar|sow)\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Class' : cleaned;
  }

  static String _cleanSex(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'b' || v.contains('buck')) return 'Buck';
    if (v == 'd' || v.contains('doe')) return 'Doe';
    if (v.contains('boar')) return 'Boar';
    if (v.contains('sow')) return 'Sow';
    return value.trim();
  }

  static int _placement(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString().trim()) ?? 0;
  }

  static bool _isOverallAward(String code) {
    return const {
      'BIS',
      'RIS',
      'BRIS',
      'BIS-CAVY',
      'BIS_CAVY',
      'BISCAVY',
    }.contains(code);
  }

  static String _displayOverallAward(String code) {
    switch (code) {
      case 'RIS':
      case 'BRIS':
        return 'RIS';
      case 'BIS-CAVY':
      case 'BIS_CAVY':
      case 'BISCAVY':
        return 'BIS-CAVY';
      default:
        return code;
    }
  }

  static int _overallAwardRank(String award) {
    switch (award) {
      case 'BIS':
        return 0;
      case 'RIS':
        return 1;
      case 'BIS-CAVY':
        return 2;
      default:
        return 9;
    }
  }

  static Set<String> _awardCodes(Map<String, dynamic> row) {
    final raw = row['special_awards'] ?? row['awards'] ?? row['award_codes'];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim().toUpperCase())
          .where((e) => e.isNotEmpty)
          .toSet();
    }

    return (raw ?? '')
        .toString()
        .toUpperCase()
        .split(RegExp(r'[,;|]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
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

  static String _exhibitorKey(Map<String, dynamic> row) {
    final id = _text(row, ['exhibitor_id', 'exhibitor_user_id']);
    return id.isNotEmpty ? id : _key(_exhibitorName(row));
  }
}

class _BreedAccumulator {
  final String breedName;
  int animalsShown = 0;
  String judgeName = '';
  final Set<String> exhibitors = {};
  DetailsByBreedAwardRow? bob;
  DetailsByBreedAwardRow? bosb;
  final List<DetailsByBreedAwardRow> specialAwards = [];
  final Map<String, _VarietyAccumulator> varieties = {};

  _BreedAccumulator(this.breedName);
}

class _VarietyAccumulator {
  final String varietyName;
  int animalsShown = 0;
  final Set<String> exhibitors = {};
  DetailsByBreedAwardRow? bov;
  DetailsByBreedAwardRow? bosv;
  final Map<String, _ClassAccumulator> classes = {};

  _VarietyAccumulator(this.varietyName);
}

class _ClassAccumulator {
  final String className;
  final String sex;
  int animalsShown = 0;
  final Set<String> exhibitors = {};
  final List<DetailsByBreedPlacementRow> placements = [];

  _ClassAccumulator(this.className, this.sex);
}

class _Header {
  final String showName;
  final String showDate;
  final String showLocation;
  final String hostClubName;
  final String showType;
  final String specialtyStatus;
  final String arbaSanctionNumber;
  final String stateClubName;
  final String stateClubSanctionNumber;
  final String secretaryName;
  final String secretaryAddress;
  final String secretaryEmail;
  final String secretaryPhone;
  final String superintendentName;

  const _Header({
    this.showName = '',
    this.showDate = '',
    this.showLocation = '',
    this.hostClubName = '',
    this.showType = '',
    this.specialtyStatus = '',
    this.arbaSanctionNumber = '',
    this.stateClubName = '',
    this.stateClubSanctionNumber = '',
    this.secretaryName = '',
    this.secretaryAddress = '',
    this.secretaryEmail = '',
    this.secretaryPhone = '',
    this.superintendentName = '',
  });
}
