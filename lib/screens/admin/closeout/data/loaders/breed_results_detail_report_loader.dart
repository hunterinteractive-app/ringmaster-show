// lib/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart

import 'package:ringmaster_show/utils/cavy/cavy_awards.dart';

import '../../models/base/report_request.dart';
import '../../models/clubs/breed_results_detail_report_data.dart';
import '../closeout_repository.dart';

class BreedResultsDetailReportLoader {
  BreedResultsDetailReportLoader(this.repo);

  final CloseoutRepository repo;

  Future<BreedResultsDetailReportData> load(ReportRequest request) async {
    final showId = request.showId;
    final breedName = (request.breedName ?? '').trim();
    final scope = (request.scope ?? '').trim().toUpperCase();
    final showLetter = (request.showLetter ?? '').trim().toUpperCase();
    final showHeader = await _loadShowHeader(showId);
    final breedSanctionNumber = await _loadBreedSanctionNumber(
      showId: showId,
      breedName: breedName,
      scope: scope,
      showLetter: showLetter,
    );
    final arbaSanctionNumber = await _loadArbaSanctionNumber(
      showId: showId,
      scope: scope,
      showLetter: showLetter,
    );

    if (breedName.isEmpty) {
      throw Exception('Breed Results Detail Report requires breedName.');
    }
    if (scope.isEmpty) {
      throw Exception('Breed Results Detail Report requires scope.');
    }
    if (showLetter.isEmpty) {
      throw Exception('Breed Results Detail Report requires showLetter.');
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

      final sections = <BreedResultsDetailSection>[];

      for (final letter in letters) {
        final built = await _loadSection(
          showId: showId,
          breedName: breedName,
          scope: scope,
          showLetter: letter,
        );
        sections.add(built);
      }

      return BreedResultsDetailReportData(
        showId: showId,
        breedName: breedName,
        scope: scope,
        showLetter: 'ALL',
        judgeName: sections.isNotEmpty ? sections.first.judgeName : '',
        arbaSanction: arbaSanctionNumber,
        nationalClubSanction: '',
        breedSanctionNumber: breedSanctionNumber,
        hostClubName: showHeader.hostClubName,
        showLocation: showHeader.showLocation,
        secretaryName: showHeader.secretaryName,
        secretaryEmail: showHeader.secretaryEmail,
        breedAwards: const [],
        varieties: const [],
        sections: sections,
        noResultsFound: sections.every((s) => s.noResultsFound),
        secretaryPhone: showHeader.secretaryPhone,
      );
    }

    final section = await _loadSection(
      showId: showId,
      breedName: breedName,
      scope: scope,
      showLetter: showLetter,
    );

    return BreedResultsDetailReportData(
      showId: showId,
      breedName: breedName,
      scope: scope,
      showLetter: showLetter,
      judgeName: section.judgeName,
      arbaSanction: arbaSanctionNumber,
      nationalClubSanction: '',
      breedSanctionNumber: breedSanctionNumber,
      hostClubName: showHeader.hostClubName,
      showLocation: showHeader.showLocation,
      secretaryName: showHeader.secretaryName,
      secretaryEmail: showHeader.secretaryEmail,
      breedAwards: section.breedAwards,
      varieties: section.varieties,
      sections: const [],
      noResultsFound: section.noResultsFound,
      secretaryPhone: showHeader.secretaryPhone,
    );
  }

  Future<BreedResultsDetailSection> _loadSection({
    required String showId,
    required String breedName,
    required String scope,
    required String showLetter,
  }) async {
    final sectionRows = await repo.supabase.rpc(
      'report_results_entry_rows_for_breed_detail',
      params: {
        'p_show_id': showId,
        'p_breed_name': breedName,
        'p_scope': scope,
        'p_show_letter': showLetter,
      },
    );

    final rows = (sectionRows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (rows.isEmpty) {
      return BreedResultsDetailSection(
        showLetter: showLetter,
        judgeName: '',
        breedAwards: const [],
        varieties: const [],
        noResultsFound: true,
      );
    }

    final awardsResponse = await repo.supabase.rpc(
      'report_results_awards_for_breed_detail',
      params: {
        'p_show_id': showId,
        'p_breed_name': breedName,
        'p_scope': scope,
        'p_show_letter': showLetter,
      },
    );

    final awardRows = (awardsResponse as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final judgeName = _deriveJudgeName(rows);
    final counts = _buildAwardCounts(rows);

    final breedAwards = awardRows
        .where((a) => _isBreedAward(a['award_code']))
        .map((r) => _mapAwardRow(r, counts))
        .toList();

    final varietyAwardMap = <String, List<BreedAward>>{};
    for (final row in awardRows.where((a) => _isVarietyAward(a['award_code']))) {
      final varietyName =
          _safe(row['variety_name'], fallback: 'Unspecified Variety');
      varietyAwardMap.putIfAbsent(varietyName, () => []);
      varietyAwardMap[varietyName]!.add(_mapAwardRow(row, counts));
    }

    return BreedResultsDetailSection(
      showLetter: showLetter,
      judgeName: judgeName,
      breedAwards: breedAwards,
      varieties: _buildVarieties(rows: rows, varietyAwardMap: varietyAwardMap),
      noResultsFound: false,
    );
  }

  List<VarietySection> _buildVarieties({
    required List<Map<String, dynamic>> rows,
    required Map<String, List<BreedAward>> varietyAwardMap,
  }) {
    final byVariety = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final varietyName =
          _safe(row['variety_name'], fallback: 'Unspecified Variety');
      byVariety.putIfAbsent(varietyName, () => []);
      byVariety[varietyName]!.add(row);
    }

    final sortedVarietyNames = byVariety.keys.toList()..sort();

    return sortedVarietyNames.map((varietyName) {
      final varietyRows = byVariety[varietyName]!;
      return VarietySection(
        varietyName: varietyName,
        awards: varietyAwardMap[varietyName] ?? const [],
        sexSections: _buildSexSections(varietyRows),
      );
    }).toList();
  }

  List<SexSection> _buildSexSections(List<Map<String, dynamic>> rows) {
    final bySex = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final sexLabel = _deriveSexLabel(row);
      bySex.putIfAbsent(sexLabel, () => []);
      bySex[sexLabel]!.add(row);
    }

    final sexLabels = bySex.keys.toList()
      ..sort((a, b) {
        final cmp = _sexSort(a).compareTo(_sexSort(b));
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    return sexLabels.map((sexLabel) {
      return SexSection(
        sexLabel: sexLabel,
        classes: _buildClasses(bySex[sexLabel]!),
      );
    }).toList();
  }

  List<ClassSection> _buildClasses(List<Map<String, dynamic>> rows) {
    final byClass = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final className = _normalizeClassName(
        _safe(row['class_name'], fallback: 'Unspecified Class'),
      );
      byClass.putIfAbsent(className, () => []);
      byClass[className]!.add(row);
    }

    final classNames = byClass.keys.toList()
      ..sort((a, b) {
        final aSort = _classSort(a);
        final bSort = _classSort(b);
        final cmp = aSort.compareTo(bSort);
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    return classNames.map((className) {
      final classRows = byClass[className]!;
      final sortedRows = [...classRows]
        ..sort((a, b) {
          final aPlace = _placementNumber(a['placement']);
          final bPlace = _placementNumber(b['placement']);
          final cmp = aPlace.compareTo(bPlace);
          if (cmp != 0) return cmp;
          return _safe(a['exhibitor_label']).compareTo(_safe(b['exhibitor_label']));
        });

      final rowsOut = sortedRows
          .where((r) {
            final placeNum = _placementNumber(r['placement']);
            return placeNum >= 1 && placeNum <= 5;
          })
          .map((r) {
            final placeNum = _placementNumber(r['placement']);

            return ClassEntry(
              place: placeNum.toString(),
              animal: _animalLabel(r),
              exhibitorName: _safe(r['exhibitor_label']),
              sex: _safe(r['sex']),
              variety: _safe(r['variety_name']),
            );
          })
          .toList();

      final animalsJudged = classRows.where((r) => _wasJudged(r)).length;
      final exhibitorsJudged = classRows
          .where((r) => _wasJudged(r))
          .map((r) => _safe(r['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      return ClassSection(
        className: className,
        entryCount: classRows.length,
        placedCount: rowsOut.length,
        animalsJudged: animalsJudged,
        exhibitorsJudged: exhibitorsJudged,
        rows: rowsOut,
      );
    }).toList();
  }

  BreedAward _mapAwardRow(
    Map<String, dynamic> row,
    Map<String, _JudgedCount> counts,
  ) {
    final rawAwardCode = _safe(row['award_code']);
    final award = _normalizeAwardLabel(rawAwardCode);
    final variety = _safe(row['variety_name']);
    final className = _safe(row['class_name']);
    final sex = _safe(row['sex']);
    final count = _countForAward(rawAwardCode, variety, className, sex, counts);

    return BreedAward(
      award: award,
      animal: _animalLabel(row),
      className: className,
      exhibitorName: _safe(row['exhibitor_label']),
      sex: sex,
      variety: variety,
      animalsJudged: count.animals,
      exhibitorsJudged: count.exhibitors,
    );
  }

  Map<String, _JudgedCount> _buildAwardCounts(List<Map<String, dynamic>> rows) {
    _JudgedCount countFor(Iterable<Map<String, dynamic>> source) {
      final judged = source.where((r) => _wasJudged(r)).toList();
      return _JudgedCount(
        animals: judged.length,
        exhibitors: judged
            .map((r) => _safe(r['exhibitor_id']))
            .where((e) => e.isNotEmpty)
            .toSet()
            .length,
      );
    }

    final counts = <String, _JudgedCount>{};
    counts['BREED'] = countFor(rows);

    final sexes = rows
        .map((r) => _sexKey(_safe(r['sex'])))
        .where((s) => s.isNotEmpty)
        .toSet();

    for (final sex in sexes) {
      final sexRows = rows.where((r) => _sexKey(_safe(r['sex'])) == sex);
      counts['BREED_SEX::$sex'] = countFor(sexRows);
    }

    final varieties = rows
        .map((r) => _safe(r['variety_name']))
        .where((v) => v.isNotEmpty)
        .toSet();

    for (final variety in varieties) {
      final varietyRows = rows.where((r) => _safe(r['variety_name']) == variety);
      counts['VARIETY::$variety'] = countFor(varietyRows);

      final varietySexes = varietyRows
          .map((r) => _sexKey(_safe(r['sex'])))
          .where((s) => s.isNotEmpty)
          .toSet();

      for (final sex in varietySexes) {
        final varietySexRows = varietyRows.where(
          (r) => _sexKey(_safe(r['sex'])) == sex,
        );
        counts['VARIETY_SEX::$variety::$sex'] = countFor(varietySexRows);
      }
    }

    return counts;
  }

  _JudgedCount _countForAward(
    String award,
    String variety,
    String className,
    String sex,
    Map<String, _JudgedCount> counts,
  ) {
    final upper = award.toUpperCase();
    final sexKey = _sexKey(sex);

    if (upper == 'BOSB' || upper == 'BOS') {
      if (sexKey.isNotEmpty) {
        return counts['BREED_SEX::$sexKey'] ?? const _JudgedCount();
      }
      return counts['BREED'] ?? const _JudgedCount();
    }

    if (upper == 'BOB') {
      return counts['BREED'] ?? const _JudgedCount();
    }

    if (upper == 'BOSV') {
      if (sexKey.isNotEmpty) {
        return counts['VARIETY_SEX::$variety::$sexKey'] ?? const _JudgedCount();
      }
      return counts['VARIETY::$variety'] ?? const _JudgedCount();
    }

    if (upper == 'BOV') {
      return counts['VARIETY::$variety'] ?? const _JudgedCount();
    }

    return counts['BREED'] ?? const _JudgedCount();
  }

  Future<String> _loadArbaSanctionNumber({
    required String showId,
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
        .eq('sanctioning_body', 'ARBA');

    if (sectionId.isNotEmpty) {
      query = query.eq('section_id', sectionId);
    }

    final response = await query.limit(1).maybeSingle();
    if (response == null) return '';

    return (Map<String, dynamic>.from(response)['sanction_number'] ?? '')
        .toString()
        .trim();
  }

  Future<String> _loadBreedSanctionNumber({
    required String showId,
    required String breedName,
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
        .select('club_id, location_name')
        .eq('id', showId)
        .maybeSingle();

    if (showResponse == null) return const _ShowHeader();

    final show = Map<String, dynamic>.from(showResponse);
    final clubId = _safe(show['club_id']);
    String hostClubName = '';

    if (clubId.isNotEmpty) {
      final clubResponse = await repo.supabase
          .from('clubs')
          .select('name')
          .eq('id', clubId)
          .maybeSingle();

      if (clubResponse != null) {
        hostClubName = _safe(Map<String, dynamic>.from(clubResponse)['name']);
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
      showLocation: _safe(show['location_name']),
      secretaryName: _safe(arbaDetails['secretary_name']),
      secretaryEmail: _safe(arbaDetails['secretary_email']),
      secretaryPhone: _safe(arbaDetails['secretary_phone']),
    );
  }

  String _deriveJudgeName(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final judge = _safe(row['judge_name']);
      if (judge.isNotEmpty) return judge;
    }
    return '';
  }

  bool _isBreedAward(Object? code) {
    final c = _safe(code).toUpperCase();
    return [
      'BIS',
      'RIS',
      'RBIS',
      'HM',
      'B4C',
      'B6C',
      'BOB',
      'BOSB',
      'BOS',
      'BOG',
      'BOSG',
      'BJB',
      'BIB',
      'BSB',
    ].contains(c);
  }

  bool _isVarietyAward(Object? code) {
    final c = _safe(code).toUpperCase();
    return [
      'BOV',
      'BOSV',
      'BJV',
      'BIV',
      'BSV',
    ].contains(c);
  }

  String _normalizeAwardLabel(String code) {
    final c = code.toUpperCase();

    switch (c) {
      case 'BOS':
        return 'BOSB';
      case 'RBIS':
        return 'RIS';
      case 'B4C':
        return 'Best 4-Class';
      case 'B6C':
        return 'Best 6-Class';
      default:
        return cavyAwardLabels[c] ?? c;
    }
  }

  String _deriveSexLabel(Map<String, dynamic> row) {
    final sex = _safe(row['sex']).toLowerCase();
    final className = _safe(row['class_name']).toLowerCase();

    if (sex.contains('buck') || sex == 'b' || className.contains('buck')) {
      return 'Bucks';
    }

    if (sex.contains('doe') || sex == 'd' || className.contains('doe')) {
      return 'Does';
    }

    return 'Unspecified Sex';
  }

  int _sexSort(String sexLabel) {
    switch (sexLabel) {
      case 'Bucks':
        return 10;
      case 'Does':
        return 20;
      default:
        return 99;
    }
  }

  String _normalizeClassName(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('senior') && r.contains('buck')) return 'Sr Bucks';
    if (r.contains('senior') && r.contains('doe')) return 'Sr Does';
    if (r.contains('intermediate') && r.contains('buck')) return 'Int Bucks';
    if (r.contains('intermediate') && r.contains('doe')) return 'Int Does';
    if (r.contains('junior') && r.contains('buck')) return 'Jr Bucks';
    if (r.contains('junior') && r.contains('doe')) return 'Jr Does';
    return raw;
  }

  int _classSort(String className) {
    switch (className) {
      case 'Sr Bucks':
        return 10;
      case 'Sr Does':
        return 20;
      case 'Int Bucks':
        return 30;
      case 'Int Does':
        return 40;
      case 'Jr Bucks':
        return 50;
      case 'Jr Does':
        return 60;
      default:
        return 999;
    }
  }

  bool _wasJudged(Map<String, dynamic> row) {
    final isShown = row['is_shown'];
    final isDisqualified = row['is_disqualified'];

    if (isShown == false) return false;
    if (isDisqualified == true) return false;

    final status = _safe(row['status']).toLowerCase();
    if (status.contains('no show')) return false;
    if (status.contains('wrong')) return false;
    if (status.contains('scratch')) return false;

    return true;
  }

  int _placementNumber(Object? value) {
    final text = _safe(value);
    return int.tryParse(text) ?? 999;
  }

  String _animalLabel(Map<String, dynamic> row) {
    final tattoo = _safe(row['tattoo']);
    final animal = _safe(row['animal_label']).isNotEmpty
        ? _safe(row['animal_label'])
        : _safe(row['tattoo']);
    if (animal.isNotEmpty) return animal;
    if (tattoo.isNotEmpty) return tattoo;
    return 'Animal';
  }

  String _sexKey(String sex) {
    final s = sex.toLowerCase().trim();
    if (s.contains('buck') || s == 'b') return 'buck';
    if (s.contains('doe') || s == 'd') return 'doe';
    if (s.contains('boar') || s == 'male' || s == 'm') return 'boar';
    if (s.contains('sow') || s == 'female' || s == 'f') return 'sow';
    return s;
  }

  String _safe(Object? value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }
}

class _JudgedCount {
  final int animals;
  final int exhibitors;

  const _JudgedCount({
    this.animals = 0,
    this.exhibitors = 0,
  });
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