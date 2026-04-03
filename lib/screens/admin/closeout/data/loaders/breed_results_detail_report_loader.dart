// lib/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart

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
        final sectionRows = await repo.supabase.rpc(
          'report_results_entry_rows_for_breed_detail',
          params: {
            'p_show_id': showId,
            'p_breed_name': breedName,
            'p_scope': scope,
            'p_show_letter': letter,
          },
        );

        final rows = (sectionRows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (rows.isEmpty) continue;

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

        final breedAwards = awardRows
            .where((a) => _isBreedAward(a['award_code']))
            .map(_mapAwardRow)
            .toList();

        final varietyAwardMap = <String, List<BreedAward>>{};
        for (final row
            in awardRows.where((a) => _isVarietyAward(a['award_code']))) {
          final varietyName = _safe(
            row['variety_name'],
            fallback: 'Unspecified Variety',
          );
          varietyAwardMap.putIfAbsent(varietyName, () => []);
          varietyAwardMap[varietyName]!.add(_mapAwardRow(row));
        }

        final varieties = _buildVarieties(
          rows: rows,
          varietyAwardMap: varietyAwardMap,
        );

        sections.add(
          BreedResultsDetailSection(
            showLetter: letter,
            judgeName: judgeName,
            breedAwards: breedAwards,
            varieties: varieties,
          ),
        );
      }

      if (sections.isEmpty) {
        throw Exception(
          'No breed detail rows found for breed "$breedName" in scope "$scope" across all shows.',
        );
      }

      return BreedResultsDetailReportData(
        showId: showId,
        breedName: breedName,
        scope: scope,
        showLetter: 'ALL',
        judgeName: sections.first.judgeName,
        breedAwards: const [],
        varieties: const [],
        sections: sections,
      );
    }

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
      throw Exception(
        'No breed detail rows found for breed "$breedName" in scope "$scope" and show letter "$showLetter".',
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

    final breedAwards = awardRows
        .where((a) => _isBreedAward(a['award_code']))
        .map(_mapAwardRow)
        .toList();

    final varietyAwardMap = <String, List<BreedAward>>{};
    for (final row in awardRows.where((a) => _isVarietyAward(a['award_code']))) {
      final varietyName = _safe(
        row['variety_name'],
        fallback: 'Unspecified Variety',
      );
      varietyAwardMap.putIfAbsent(varietyName, () => []);
      varietyAwardMap[varietyName]!.add(_mapAwardRow(row));
    }

    final varieties = _buildVarieties(
      rows: rows,
      varietyAwardMap: varietyAwardMap,
    );

    return BreedResultsDetailReportData(
      showId: showId,
      breedName: breedName,
      scope: scope,
      showLetter: showLetter,
      judgeName: judgeName,
      breedAwards: breedAwards,
      varieties: varieties,
      sections: const [],
    );
  }

  List<VarietySection> _buildVarieties({
    required List<Map<String, dynamic>> rows,
    required Map<String, List<BreedAward>> varietyAwardMap,
  }) {
    final byVariety = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final varietyName = _safe(
        row['variety_name'],
        fallback: 'Unspecified Variety',
      );
      byVariety.putIfAbsent(varietyName, () => []);
      byVariety[varietyName]!.add(row);
    }

    final sortedVarietyNames = byVariety.keys.toList()..sort();

    return sortedVarietyNames.map((varietyName) {
      final varietyRows = byVariety[varietyName]!;
      final classes = _buildClasses(varietyRows);

      return VarietySection(
        varietyName: varietyName,
        awards: varietyAwardMap[varietyName] ?? const [],
        classes: classes,
      );
    }).toList();
  }

  List<ClassSection> _buildClasses(List<Map<String, dynamic>> rows) {
    final byClass = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final className = _safe(row['class_name'], fallback: 'Unspecified Class');
      byClass.putIfAbsent(className, () => []);
      byClass[className]!.add(row);
    }

    final classNames = byClass.keys.toList()
      ..sort((a, b) {
        final aSort = _asInt(byClass[a]!.first['class_sort_order']);
        final bSort = _asInt(byClass[b]!.first['class_sort_order']);
        final cmp = aSort.compareTo(bSort);
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    return classNames.map((className) {
      final classRows = byClass[className]!;
      final placedRows = [...classRows]
        ..sort((a, b) {
          final aPlace = _placementNumber(a['placement']);
          final bPlace = _placementNumber(b['placement']);
          final cmp = aPlace.compareTo(bPlace);
          if (cmp != 0) return cmp;
          final aEx = _safe(a['exhibitor_label']);
          final bEx = _safe(b['exhibitor_label']);
          return aEx.compareTo(bEx);
        });

      final rowsOut = placedRows
          .where((r) => _placementNumber(r['placement']) < 999)
          .map((r) => ClassEntry(
                place: _placementNumber(r['placement']).toString(),
                animal: _animalLabel(r),
                exhibitorName: _safe(r['exhibitor_label']),
              ))
          .toList();

      final entryCount = classRows.length;
      final placedCount = rowsOut.length;

      return ClassSection(
        className: className,
        entryCount: entryCount,
        placedCount: placedCount,
        rows: rowsOut,
      );
    }).toList();
  }

  BreedAward _mapAwardRow(Map<String, dynamic> row) {
    return BreedAward(
      award: _normalizeAwardLabel(_safe(row['award_code'])),
      animal: _animalLabel(row),
      className: _safe(row['class_name']),
      exhibitorName: _safe(row['exhibitor_label']),
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
    return c == 'BOB' || c == 'BOSB' || c == 'BOS';
  }

  bool _isVarietyAward(Object? code) {
    final c = _safe(code).toUpperCase();
    return c == 'BOV' || c == 'BOSV';
  }

  String _normalizeAwardLabel(String code) {
    final c = code.toUpperCase();
    switch (c) {
      case 'BOS':
        return 'BOSB';
      default:
        return c;
    }
  }

  int _placementNumber(Object? value) {
    final text = _safe(value);
    return int.tryParse(text) ?? 999;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(_safe(value)) ?? 999;
  }

  String _animalLabel(Map<String, dynamic> row) {
    final tattoo = _safe(row['tattoo']);
    final animal = _safe(row['animal_label']);
    if (animal.isNotEmpty) return animal;
    if (tattoo.isNotEmpty) return tattoo;
    return 'Animal';
  }

  String _safe(Object? value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }
}