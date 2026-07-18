// lib/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart

import 'package:ringmaster_show/utils/cavy/cavy_awards.dart';

import '../../models/base/report_request.dart';
import '../../models/clubs/breed_results_detail_report_data.dart';
import '../../utils/club_report_grouping.dart';
import '../../utils/breed_results_detail_order.dart';
import '../closeout_repository.dart';

class BreedResultsDetailReportLoader {
  BreedResultsDetailReportLoader(this.repo);

  final CloseoutRepository repo;

  Future<BreedResultsDetailReportData> load(ReportRequest request) async {
    final showId = request.showId;
    final requestedBreedName = (request.breedName ?? '').trim();
    final species = normalizeClubReportSpecies(request.species);
    final breedName = species == 'cavy' ? '' : requestedBreedName;
    final clubName = (request.clubName ?? '').trim();
    final scope = (request.scope ?? '').trim().toUpperCase();
    final showLetter = (request.showLetter ?? '').trim().toUpperCase();
    final showHeader = await _loadShowHeader(showId);
    final breedSanctionNumber = breedName.isEmpty
        ? ''
        : await _loadBreedSanctionNumber(
            showId: showId,
            breedName: breedName,
            clubName: clubName,
            scope: scope,
            showLetter: showLetter,
          );
    final arbaSanctionNumber = await _loadArbaSanctionNumber(
      showId: showId,
      scope: scope,
      showLetter: showLetter,
    );
    final reportBreedLabel = species == 'cavy'
        ? cavyClubReportBreedName
        : (breedName.isEmpty ? 'All Breeds' : breedName);
    if (scope.isEmpty) {
      throw Exception('Breed Results Detail Report requires scope.');
    }
    if (showLetter.isEmpty) {
      throw Exception('Breed Results Detail Report requires showLetter.');
    }

    if (breedName.isNotEmpty) {
      await _recalculateSweepstakes(
        showId: showId,
        breedName: breedName,
        scope: scope,
        showLetter: showLetter,
      );
    } else if (species == 'cavy') {
      await repo.supabase.rpc(
        'calculate_cavy_sweepstakes_for_section',
        params: {
          'p_show_id': showId,
          'p_scope': scope,
          'p_show_letter': showLetter,
        },
      );
    }

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

      final sections = <BreedResultsDetailSection>[];

      for (final letter in letters) {
        final built = await _loadSection(
          showId: showId,
          breedName: breedName,
          scope: scope,
          showLetter: letter,
          species: species,
        );
        sections.add(built);
      }

      return BreedResultsDetailReportData(
        showId: showId,
        breedName: reportBreedLabel,
        species: species,
        scope: scope,
        showLetter: 'ALL',
        judgeName: sections.isNotEmpty ? sections.first.judgeName : '',
        arbaSanction: arbaSanctionNumber,
        nationalClubSanction: '',
        breedSanctionNumber: breedSanctionNumber,
        breedClubName: clubName,
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
      species: species,
    );

    return BreedResultsDetailReportData(
      showId: showId,
      breedName: reportBreedLabel,
      species: species,
      scope: scope,
      showLetter: showLetter,
      judgeName: section.judgeName,
      arbaSanction: arbaSanctionNumber,
      nationalClubSanction: '',
      breedSanctionNumber: breedSanctionNumber,
      breedClubName: clubName,
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

  Future<BreedResultsDetailSection> _loadSection({
    required String showId,
    required String breedName,
    required String scope,
    required String showLetter,
    required String species,
  }) async {
    final sectionRows = breedName.isEmpty
        ? await _loadOverallResultRows(
            showId: showId,
            scope: scope,
            showLetter: showLetter,
          )
        : await repo.supabase.rpc(
            'report_results_entry_rows_for_breed_detail',
            params: {
              'p_show_id': showId,
              'p_breed_name': breedName,
              'p_scope': scope,
              'p_show_letter': showLetter,
            },
          );

    var rows = (sectionRows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    rows = await _withEntryJudgingState(showId, rows);
    rows = _filterRowsBySpecies(rows, species);

    final overallRows = breedName.isEmpty
        ? rows
        : _filterRowsBySpecies(
            await _withEntryJudgingState(
              showId,
              await _loadOverallResultRows(
                showId: showId,
                scope: scope,
                showLetter: showLetter,
              ),
            ),
            species,
          );

    var reportRows = breedName.isEmpty
        ? rows
        : _mergeBreedRowsWithRelatedPointsRows(
            breedRows: rows,
            overallRows: overallRows,
            breedName: breedName,
          );

    if (species == 'rabbit' && breedName.isNotEmpty) {
      reportRows = await _withRabbitCatalogJudgingOrder(
        breedName: breedName,
        rows: reportRows,
      );
    }

    if (reportRows.isEmpty) {
      return BreedResultsDetailSection(
        showLetter: showLetter,
        judgeName: '',
        breedAwards: const [],
        varieties: const [],
        noResultsFound: true,
      );
    }

    final awardsResponse = breedName.isEmpty
        ? await _loadOverallAwardRows(
            showId: showId,
            scope: scope,
            showLetter: showLetter,
          )
        : await repo.supabase.rpc(
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
        .where((row) => _rowMatchesSpecies(row, species))
        .toList();
    final groupByBreed = species == 'cavy' && breedName.isEmpty;

    final judgeName = _deriveJudgeName(reportRows);
    final counts = _buildAwardCounts(reportRows, overallRows: overallRows);
    final resultRowsForAwardLookup = _mergeResultRows(reportRows, overallRows);
    final sweepstakesPoints = await _loadSweepstakesPointsLookup(
      showId,
      resultRowsForAwardLookup
          .map((row) => _safe(row['entry_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(),
    );

    final breedAwards = awardRows
        .where((a) => _isBreedAward(a['award_code']))
        .map(
          (r) => _mapAwardRow(
            r,
            counts,
            resultRowsForAwardLookup,
            sweepstakesPoints,
          ),
        )
        .toList();

    final varietyAwardMap = <String, List<BreedAward>>{};
    for (final row in awardRows.where(
      (a) => _isVarietyAward(a['award_code']),
    )) {
      final sectionName = breedResultsDetailTopSectionName(
        row,
        groupByBreed: groupByBreed,
      );
      varietyAwardMap.putIfAbsent(sectionName, () => []);
      varietyAwardMap[sectionName]!.add(
        _mapAwardRow(row, counts, resultRowsForAwardLookup, sweepstakesPoints),
      );
    }

    return BreedResultsDetailSection(
      showLetter: showLetter,
      judgeName: judgeName,
      breedAwards: breedAwards,
      varieties: _buildVarieties(
        rows: reportRows,
        varietyAwardMap: varietyAwardMap,
        sweepstakesPoints: sweepstakesPoints,
        groupByBreed: groupByBreed,
        useRabbitJudgingOrder: species == 'rabbit',
      ),
      noResultsFound: false,
    );
  }

  Future<List<Map<String, dynamic>>> _withEntryJudgingState(
    String showId,
    List<Map<String, dynamic>> rows,
  ) async {
    final entryIds = rows
        .map(
          (row) => _firstNonEmpty([_safe(row['entry_id']), _safe(row['id'])]),
        )
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (entryIds.isEmpty) return rows;

    final entriesById = <String, Map<String, dynamic>>{};
    const chunkSize = 100;

    for (var start = 0; start < entryIds.length; start += chunkSize) {
      final end = start + chunkSize > entryIds.length
          ? entryIds.length
          : start + chunkSize;
      final chunk = entryIds.sublist(start, end);

      final entryRows = await repo.supabase
          .from('entries')
          .select(
            'id, scratched_at, status, is_shown, is_fur, fur_variety, fur_placement',
          )
          .eq('show_id', showId)
          .inFilter('id', chunk);

      for (final raw in entryRows as List) {
        final entry = Map<String, dynamic>.from(raw as Map);
        final id = _safe(entry['id']);
        if (id.isNotEmpty) entriesById[id] = entry;
      }
    }

    return rows.map((row) {
      final entryId = _firstNonEmpty([
        _safe(row['entry_id']),
        _safe(row['id']),
      ]);
      final entry = entriesById[entryId];
      if (entry == null) return row;

      return {
        ...row,
        'entry_scratched_at': entry['scratched_at'],
        'entry_status': entry['status'],
        'entry_is_shown': entry['is_shown'],
        'entry_is_fur': entry['is_fur'],
        'entry_fur_variety': entry['fur_variety'],
        'entry_fur_placement': entry['fur_placement'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _withRabbitCatalogJudgingOrder({
    required String breedName,
    required List<Map<String, dynamic>> rows,
  }) async {
    final breed = await repo.supabase
        .from('breeds')
        .select('id')
        .ilike('name', breedName.trim())
        .eq('species', 'rabbit')
        .maybeSingle();
    final breedId = (breed?['id'] ?? '').toString().trim();
    if (breedId.isEmpty) return rows;

    final responses = await Future.wait([
      repo.supabase
          .from('variety_groups')
          .select('id,sort_order')
          .eq('breed_id', breedId),
      repo.supabase
          .from('varieties')
          .select('name,sort_order,group_id')
          .eq('breed_id', breedId)
          .eq('is_active', true),
    ]);

    final groupOrders = <String, int>{};
    for (final raw in responses[0] as List) {
      final group = Map<String, dynamic>.from(raw as Map);
      final id = _safe(group['id']);
      if (id.isNotEmpty) {
        groupOrders[id] = _sortMetadataValue(group['sort_order']);
      }
    }

    final orderByVariety = <String, ({int group, int variety})>{};
    for (final raw in responses[1] as List) {
      final variety = Map<String, dynamic>.from(raw as Map);
      final name = _safe(variety['name']).toLowerCase();
      if (name.isEmpty) continue;
      orderByVariety[name] = (
        group: groupOrders[_safe(variety['group_id'])] ?? 9999,
        variety: _sortMetadataValue(variety['sort_order']),
      );
    }

    return rows
        .map((row) {
          final varietyName = _firstNonEmpty([
            _safe(row['variety_name']),
            _safe(row['variety']),
          ]).toLowerCase();
          final order = orderByVariety[varietyName];
          if (order == null) return row;
          return {
            ...row,
            'group_sort_order': order.group,
            'variety_sort_order': order.variety,
          };
        })
        .toList(growable: false);
  }

  int _sortMetadataValue(Object? value) {
    if (value is int) return value;
    return int.tryParse((value ?? '').toString().trim()) ?? 9999;
  }

  List<VarietySection> _buildVarieties({
    required List<Map<String, dynamic>> rows,
    required Map<String, List<BreedAward>> varietyAwardMap,
    required _SweepstakesPointsLookup sweepstakesPoints,
    required bool groupByBreed,
    required bool useRabbitJudgingOrder,
  }) {
    final regularByVariety = <String, List<Map<String, dynamic>>>{};
    final furByCategory = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      if (_isFurOrWoolRow(row)) {
        final category = _pointsCategoryLabel(row).isEmpty
            ? 'Uncategorized'
            : _pointsCategoryLabel(row);
        furByCategory.putIfAbsent(category, () => []);
        furByCategory[category]!.add(row);
        continue;
      }

      final sectionName = breedResultsDetailTopSectionName(
        row,
        groupByBreed: groupByBreed,
      );
      regularByVariety.putIfAbsent(sectionName, () => []);
      regularByVariety[sectionName]!.add(row);
    }

    final sections = <VarietySection>[];

    final regularVarietyNames = regularByVariety.keys.toList()
      ..sort((a, b) {
        if (!useRabbitJudgingOrder) return a.compareTo(b);
        final aRows = regularByVariety[a]!;
        final bRows = regularByVariety[b]!;
        final order = compareRabbitVarietyJudgingOrder(
          aRows.first,
          bRows.first,
        );
        return order != 0 ? order : a.compareTo(b);
      });
    for (final varietyName in regularVarietyNames) {
      sections.add(
        VarietySection(
          varietyName: varietyName,
          awards: varietyAwardMap[varietyName] ?? const [],
          sexSections: _buildSexSections(
            regularByVariety[varietyName]!,
            sweepstakesPoints,
            awardOnlyPoints: groupByBreed,
          ),
        ),
      );
    }

    const preferredFurOrder = ['White', 'Colored', 'Uncategorized'];
    final furCategories = furByCategory.keys.toList()
      ..sort((a, b) {
        final aIndex = preferredFurOrder.indexOf(a);
        final bIndex = preferredFurOrder.indexOf(b);
        final aSort = aIndex == -1 ? 999 : aIndex;
        final bSort = bIndex == -1 ? 999 : bIndex;
        final cmp = aSort.compareTo(bSort);
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    for (final category in furCategories) {
      sections.add(
        VarietySection(
          varietyName: category,
          awards: const [],
          sexSections: _buildSexSections(
            furByCategory[category]!,
            sweepstakesPoints,
            awardOnlyPoints: groupByBreed,
          ),
        ),
      );
    }

    return sections;
  }

  List<SexSection> _buildSexSections(
    List<Map<String, dynamic>> rows,
    _SweepstakesPointsLookup sweepstakesPoints, {
    required bool awardOnlyPoints,
  }) {
    final furRows = rows.where(_isFurOrWoolRow).toList();
    final regularRows = rows.where((row) => !_isFurOrWoolRow(row)).toList();
    final sections = <SexSection>[];

    if (regularRows.isNotEmpty) {
      final bySex = <String, List<Map<String, dynamic>>>{};

      for (final row in regularRows) {
        final sexLabel = _deriveSexLabel(row);
        bySex.putIfAbsent(sexLabel, () => []);
        bySex[sexLabel]!.add(row);
      }

      final sexLabels = bySex.keys.toList()
        ..sort((a, b) {
          final cmp = _sexSort(a).compareTo(_sexSort(b));
          return cmp != 0 ? cmp : a.compareTo(b);
        });

      sections.addAll(
        sexLabels.map((sexLabel) {
          return SexSection(
            sexLabel: sexLabel,
            classes: _buildClasses(
              bySex[sexLabel]!,
              sweepstakesPoints,
              awardOnlyPoints: awardOnlyPoints,
            ),
          );
        }),
      );
    }

    if (furRows.isNotEmpty) {
      sections.add(
        SexSection(
          sexLabel: '',
          classes: [
            _buildFlatFurClass(
              furRows,
              sweepstakesPoints,
              awardOnlyPoints: awardOnlyPoints,
            ),
          ],
        ),
      );
    }

    return sections;
  }

  ClassSection _buildFlatFurClass(
    List<Map<String, dynamic>> rows,
    _SweepstakesPointsLookup sweepstakesPoints, {
    required bool awardOnlyPoints,
  }) {
    final sortedRows = [...rows]
      ..sort((a, b) {
        final aPlace = _furPlacementNumber(a);
        final bPlace = _furPlacementNumber(b);
        final cmp = aPlace.compareTo(bPlace);
        if (cmp != 0) return cmp;
        return _safe(
          a['exhibitor_label'],
        ).compareTo(_safe(b['exhibitor_label']));
      });

    final rowsOut = sortedRows
        .where((row) {
          final placeNum = _furPlacementNumber(row);
          return placeNum >= 1 && placeNum <= 5;
        })
        .map((row) {
          final placeNum = _furPlacementNumber(row);
          return ClassEntry(
            place: placeNum.toString(),
            animal: _animalLabel(row),
            exhibitorName: _safe(row['exhibitor_label']),
            sex: '',
            variety: _pointsCategoryLabel(row),
            pointsCategory: _pointsCategoryLabel(row),
            pointsEarned: awardOnlyPoints
                ? 0
                : _pointsForRow(
                    row,
                    sweepstakesPoints,
                    placement: placeNum.toString(),
                  ),
          );
        })
        .toList();

    final judgedRows = rows.where(_isCountableJudgedEntry).toList();

    return ClassSection(
      className: '',
      entryCount: rows.length,
      placedCount: rowsOut.length,
      animalsJudged: judgedRows.length,
      exhibitorsJudged: judgedRows
          .map((row) => _safe(row['exhibitor_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .length,
      rows: rowsOut,
    );
  }

  List<ClassSection> _buildClasses(
    List<Map<String, dynamic>> rows,
    _SweepstakesPointsLookup sweepstakesPoints, {
    required bool awardOnlyPoints,
  }) {
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
          return _safe(
            a['exhibitor_label'],
          ).compareTo(_safe(b['exhibitor_label']));
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
              variety: _displayVarietyName(r),
              pointsCategory: _pointsCategoryLabel(r),
              pointsEarned: awardOnlyPoints
                  ? 0
                  : _pointsForRow(
                      r,
                      sweepstakesPoints,
                      placement: placeNum.toString(),
                    ),
            );
          })
          .toList();

      final judgedRows = classRows.where(_isCountableJudgedEntry).toList();
      final animalsJudged = judgedRows.length;
      final exhibitorsJudged = judgedRows
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
    List<Map<String, dynamic>> resultRows,
    _SweepstakesPointsLookup sweepstakesPoints,
  ) {
    final rawAwardCode = _safe(row['award_code']);
    final award = _normalizeAwardLabel(rawAwardCode);
    final winnerRow = _findWinnerResultRow(row, resultRows);

    final variety = _firstNonEmpty([
      _safe(row['variety_name']),
      _safe(row['variety']),
      _safe(winnerRow?['variety_name']),
      _safe(winnerRow?['variety']),
    ]);

    final groupName = _firstNonEmpty([
      _safe(row['group_name']),
      _safe(row['group']),
      _safe(winnerRow?['group_name']),
      _safe(winnerRow?['group']),
    ]);

    final className = _firstNonEmpty([
      _safe(row['class_name']),
      _safe(winnerRow?['class_name']),
    ]);

    final breedName = _firstNonEmpty([
      _safe(row['breed_name']),
      _safe(row['breed']),
      _safe(winnerRow?['breed_name']),
      _safe(winnerRow?['breed']),
    ]);

    final sex = _firstNonEmpty([_safe(row['sex']), _safe(winnerRow?['sex'])]);

    final pointsCategory = _firstNonEmpty([
      _pointsCategoryLabel(row),
      if (winnerRow != null) _pointsCategoryLabel(winnerRow),
    ]);

    final animalLabel = _firstNonEmpty([
      _animalLabel(row),
      if (winnerRow != null) _animalLabel(winnerRow),
    ]);

    final count = _countForAward(
      rawAwardCode,
      variety,
      groupName,
      className,
      sex,
      counts,
    );

    return BreedAward(
      award: award,
      animal: animalLabel,
      breedName: breedName,
      className: className,
      exhibitorName: _safe(row['exhibitor_label']),
      sex: sex,
      variety: variety,
      pointsCategory: pointsCategory,
      animalsJudged: count.animals,
      exhibitorsJudged: count.exhibitors,
      pointsEarned: _pointsForRow(
        row,
        sweepstakesPoints,
        fallback: winnerRow,
        awardCode: rawAwardCode,
      ),
    );
  }

  Map<String, _JudgedCount> _buildAwardCounts(
    List<Map<String, dynamic>> rows, {
    List<Map<String, dynamic>> overallRows = const [],
  }) {
    _JudgedCount countFor(Iterable<Map<String, dynamic>> source) {
      final judged = source.where(_isCountableJudgedEntry).toList();
      return _JudgedCount(
        animals: judged.length,
        exhibitors: judged
            .map((r) => _safe(r['exhibitor_id']))
            .where((e) => e.isNotEmpty)
            .toSet()
            .length,
      );
    }

    final regularRows = rows.where((row) => !_isFurOrWoolRow(row)).toList();
    final regularOverallRows = overallRows
        .where((row) => !_isFurOrWoolRow(row))
        .toList();
    final counts = <String, _JudgedCount>{};
    counts['BREED'] = countFor(regularRows);
    if (regularOverallRows.isNotEmpty) {
      counts['OVERALL'] = countFor(regularOverallRows);
    } else {
      counts['OVERALL'] = counts['BREED'] ?? const _JudgedCount();
    }

    final sexes = regularRows
        .map((r) => _sexKey(_safe(r['sex'])))
        .where((s) => s.isNotEmpty)
        .toSet();

    for (final sex in sexes) {
      final sexRows = regularRows.where((r) => _sexKey(_safe(r['sex'])) == sex);
      counts['BREED_SEX::$sex'] = countFor(sexRows);
    }

    final varieties = regularRows
        .map((r) => _safe(r['variety_name']))
        .where((v) => v.isNotEmpty)
        .toSet();

    for (final variety in varieties) {
      final varietyRows = regularRows.where(
        (r) => _safe(r['variety_name']) == variety,
      );
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

    final groups = regularRows
        .map((r) => _safe(r['group_name']))
        .where((g) => g.isNotEmpty)
        .toSet();

    for (final group in groups) {
      final groupRows = regularRows.where(
        (r) => _safe(r['group_name']) == group,
      );
      counts['GROUP::$group'] = countFor(groupRows);

      final groupSexes = groupRows
          .map((r) => _sexKey(_safe(r['sex'])))
          .where((s) => s.isNotEmpty)
          .toSet();

      for (final sex in groupSexes) {
        final groupSexRows = groupRows.where(
          (r) => _sexKey(_safe(r['sex'])) == sex,
        );
        counts['GROUP_SEX::$group::$sex'] = countFor(groupSexRows);
      }
    }

    return counts;
  }

  _JudgedCount _countForAward(
    String award,
    String variety,
    String groupName,
    String className,
    String sex,
    Map<String, _JudgedCount> counts,
  ) {
    final upper = _awardCodeKey(award);
    final sexKey = _sexKey(sex);

    if (upper == 'BIS' ||
        upper == 'RIS' ||
        upper == 'RBIS' ||
        upper == 'B4C' ||
        upper == 'B6C') {
      return counts['OVERALL'] ?? counts['BREED'] ?? const _JudgedCount();
    }

    if (upper == 'BOSB' || upper == 'BOS') {
      if (sexKey.isNotEmpty) {
        return counts['BREED_SEX::$sexKey'] ?? const _JudgedCount();
      }
      return counts['BREED'] ?? const _JudgedCount();
    }

    if (upper == 'BOB') {
      return counts['BREED'] ?? const _JudgedCount();
    }

    if (upper == 'BOSG') {
      if (groupName.isNotEmpty && sexKey.isNotEmpty) {
        return counts['GROUP_SEX::$groupName::$sexKey'] ?? const _JudgedCount();
      }
      if (variety.isNotEmpty && sexKey.isNotEmpty) {
        return counts['VARIETY_SEX::$variety::$sexKey'] ?? const _JudgedCount();
      }
      if (groupName.isNotEmpty) {
        return counts['GROUP::$groupName'] ?? const _JudgedCount();
      }
      if (variety.isNotEmpty) {
        return counts['VARIETY::$variety'] ?? const _JudgedCount();
      }
      return counts['BREED'] ?? const _JudgedCount();
    }

    if (upper == 'BOG') {
      if (groupName.isNotEmpty) {
        return counts['GROUP::$groupName'] ?? const _JudgedCount();
      }
      if (variety.isNotEmpty) {
        return counts['VARIETY::$variety'] ?? const _JudgedCount();
      }
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
    final c = _awardCodeKey(_safe(code));
    return const {
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
      'BOV',
      'BOSV',
      'BJB',
      'BIB',
      'BSB',
    }.contains(c);
  }

  bool _isVarietyAward(Object? code) {
    final c = _awardCodeKey(_safe(code));
    return const {'BOV', 'BOSV', 'BJV', 'BIV', 'BSV'}.contains(c);
  }

  String _normalizeAwardLabel(String code) {
    final c = _awardCodeKey(code);

    switch (c) {
      case 'BOS':
        return 'BOSB';
      case 'RBIS':
        return 'RIS';
      default:
        return cavyAwardLabels[c] ?? c;
    }
  }

  String _deriveSexLabel(Map<String, dynamic> row) {
    return breedResultsDetailSexLabel(row);
  }

  int _sexSort(String sexLabel) {
    switch (sexLabel) {
      case 'Bucks':
        return 10;
      case 'Does':
        return 20;
      case 'Boars':
        return 10;
      case 'Sows':
        return 20;
      default:
        return 99;
    }
  }

  String _normalizeClassName(String raw) {
    return normalizeBreedResultsDetailClassName(raw);
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
      case 'Sr Boars':
        return 10;
      case 'Sr Sows':
        return 20;
      case 'Int Boars':
        return 30;
      case 'Int Sows':
        return 40;
      case 'Jr Boars':
        return 50;
      case 'Jr Sows':
        return 60;
      default:
        return 999;
    }
  }

  bool _isCountableJudgedEntry(Map<String, dynamic> row) {
    if (_safe(row['scratched_at']).isNotEmpty) return false;
    if (_safe(row['entry_scratched_at']).isNotEmpty) return false;
    if (_isExplicitFalse(row['is_shown'])) return false;
    if (_isExplicitFalse(row['entry_is_shown'])) return false;

    final statuses = [
      _safe(row['fur_result_status']),
      _safe(row['result_status']),
      _safe(row['status']),
      _safe(row['entry_status']),
    ];
    if (statuses.any(_isNoShowStatus)) return false;
    if (statuses.any(_isScratchedStatus)) return false;

    return true;
  }

  bool _isExplicitFalse(Object? value) {
    if (value == false) return true;
    if (value is! String) return false;

    final normalized = value.trim().toLowerCase();
    return normalized == 'false' ||
        normalized == 'f' ||
        normalized == '0' ||
        normalized == 'no';
  }

  bool _isNoShowStatus(String value) {
    final normalized = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    return normalized == 'noshow' || normalized == 'notshown';
  }

  bool _isScratchedStatus(String value) {
    final normalized = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    return normalized == 'scratched' || normalized == 'scratch';
  }

  int _furPlacementNumber(Map<String, dynamic> row) {
    final furPlacement = _placementNumber(row['fur_placement']);
    if (furPlacement != 999) return furPlacement;
    final entryFurPlacement = _placementNumber(row['entry_fur_placement']);
    if (entryFurPlacement != 999) return entryFurPlacement;
    return _placementNumber(row['placement']);
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

  Map<String, dynamic>? _findWinnerResultRow(
    Map<String, dynamic> awardRow,
    List<Map<String, dynamic>> resultRows,
  ) {
    final awardEntryId = _safe(awardRow['entry_id']);
    if (awardEntryId.isNotEmpty) {
      for (final row in resultRows) {
        if (_safe(row['entry_id']) == awardEntryId) return row;
      }
    }

    final awardAnimalId = _safe(awardRow['animal_id']);
    if (awardAnimalId.isNotEmpty) {
      for (final row in resultRows) {
        if (_safe(row['animal_id']) == awardAnimalId) return row;
      }
    }

    final awardTattoo = _safe(awardRow['tattoo']).toLowerCase();
    if (awardTattoo.isNotEmpty) {
      for (final row in resultRows) {
        if (_safe(row['tattoo']).toLowerCase() == awardTattoo) return row;
      }
    }

    final awardAnimalLabel = _safe(awardRow['animal_label']).toLowerCase();
    if (awardAnimalLabel.isNotEmpty) {
      for (final row in resultRows) {
        if (_animalLabel(row).toLowerCase() == awardAnimalLabel) return row;
      }
    }

    return null;
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _awardCodeKey(String award) {
    final c = award.toUpperCase().trim();

    if (c == 'BEST IN SHOW') return 'BIS';

    if (c == 'RESERVE IN SHOW') return 'RIS';

    if (c == '1RIS') return 'RIS';
    if (c == '1ST RIS') return 'RIS';
    if (c == 'FIRST RIS') return 'RIS';
    if (c == '1ST RESERVE IN SHOW') return 'RIS';
    if (c == 'FIRST RESERVE IN SHOW') return 'RIS';

    if (c == '2RIS') return '2RIS';
    if (c == '2ND RIS') return '2RIS';
    if (c == 'SECOND RIS') return '2RIS';
    if (c == '2ND RESERVE IN SHOW') return '2RIS';
    if (c == 'SECOND RESERVE IN SHOW') return '2RIS';

    if (c == 'RESERVE BEST IN SHOW') return 'RBIS';
    if (c == 'RESERVE OF SHOW') return 'RIS';
    if (c == 'BEST 4 CLASS') return 'B4C';
    if (c == 'BEST 4-CLASS') return 'B4C';
    if (c == 'BEST FOUR CLASS') return 'B4C';
    if (c == 'BEST 6 CLASS') return 'B6C';
    if (c == 'BEST 6-CLASS') return 'B6C';
    if (c == 'BEST SIX CLASS') return 'B6C';
    if (c == 'HONORABLE MENTION') return 'HM';
    if (c == 'BEST OF BREED') return 'BOB';
    if (c == 'BEST OPPOSITE SEX OF BREED') return 'BOSB';
    if (c == 'BEST OPPOSITE OF BREED') return 'BOSB';
    if (c == 'BEST OF GROUP') return 'BOG';
    if (c == 'BEST OPPOSITE SEX OF GROUP') return 'BOSG';
    if (c == 'BEST OPPOSITE OF GROUP') return 'BOSG';
    if (c == 'BEST OF VARIETY') return 'BOV';
    if (c == 'BEST OPPOSITE SEX OF VARIETY') return 'BOSV';
    if (c == 'BEST OPPOSITE OF VARIETY') return 'BOSV';

    return c;
  }

  Future<List<Map<String, dynamic>>> _loadOverallAwardRows({
    required String showId,
    required String scope,
    required String showLetter,
  }) async {
    final sectionQuery = repo.supabase
        .from('show_sections')
        .select('id')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .eq('kind', scope.toLowerCase());

    final sectionResponse = showLetter == 'ALL'
        ? await sectionQuery
        : await sectionQuery.eq('letter', showLetter);

    final sectionRows = (sectionResponse as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final allAwards = <Map<String, dynamic>>[];

    for (final section in sectionRows) {
      final sectionId = _safe(section['id']);
      if (sectionId.isEmpty) continue;

      final response = await repo.supabase
          .from('entry_awards')
          .select('''
            award_code,
            entry_id,
            entries!entry_awards_entry_id_fkey!inner(
              id,
              animal_id,
              section_id,
              tattoo,
              breed,
              variety,
              fur_variety,
              is_fur,
              class_name,
              sex,
              exhibitor_id,
              exhibitors!entries_exhibitor_id_fkey(first_name, last_name)
            )
          ''')
          .eq('show_id', showId)
          .eq('entries.section_id', sectionId);

      for (final raw in response as List) {
        final award = Map<String, dynamic>.from(raw as Map);
        final entryRaw = award['entries'];
        final entry = entryRaw is Map
            ? Map<String, dynamic>.from(entryRaw)
            : <String, dynamic>{};
        final exhibitorRaw = entry['exhibitors'];
        final exhibitor = exhibitorRaw is Map
            ? Map<String, dynamic>.from(exhibitorRaw)
            : <String, dynamic>{};
        final exhibitorName = [
          _safe(exhibitor['first_name']),
          _safe(exhibitor['last_name']),
        ].where((x) => x.isNotEmpty).join(' ');

        allAwards.add({
          ...award,
          'entry_id': _safe(award['entry_id']),
          'animal_id': _safe(entry['animal_id']),
          'tattoo': _safe(entry['tattoo']),
          'animal_label': _safe(entry['tattoo']),
          'breed_name': _safe(entry['breed']),
          'breed': _safe(entry['breed']),
          'variety_name': _safe(entry['variety']),
          'variety': _safe(entry['variety']),
          'fur_variety': _safe(entry['fur_variety']),
          'is_fur': entry['is_fur'],
          'class_name': _safe(entry['class_name']),
          'sex': _safe(entry['sex']),
          'exhibitor_id': _safe(entry['exhibitor_id']),
          'exhibitor_label': exhibitorName,
        });
      }
    }

    return allAwards;
  }

  List<Map<String, dynamic>> _mergeBreedRowsWithRelatedPointsRows({
    required List<Map<String, dynamic>> breedRows,
    required List<Map<String, dynamic>> overallRows,
    required String breedName,
  }) {
    final targetBreed = breedName.toLowerCase().trim();
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addRow(Map<String, dynamic> row) {
      final key = _resultRowKey(row);
      if (seen.add(key)) merged.add(row);
    }

    for (final row in breedRows) {
      addRow(row);
    }

    for (final row in overallRows) {
      final rowBreed = _firstNonEmpty([
        _safe(row['breed_name']),
        _safe(row['breed']),
      ]).toLowerCase().trim();
      if (rowBreed != targetBreed) continue;
      if (!_isPointsCategoryPlacementRow(row)) continue;
      addRow(row);
    }

    return merged;
  }

  bool _isFurOrWoolRow(Map<String, dynamic> row) {
    return breedResultsDetailIsFurOrWoolRow(row);
  }

  bool _isPointsCategoryPlacementRow(Map<String, dynamic> row) {
    if (_pointsCategoryLabel(row).isNotEmpty) return true;
    if (_isFurOrWoolRow(row)) return true;

    final rowType = _firstNonEmpty([
      _safe(row['row_type']),
      _safe(row['result_row_type']),
      _safe(row['line_type']),
    ]).toLowerCase();

    return rowType.contains('fur') || rowType.contains('wool');
  }

  Future<List<Map<String, dynamic>>> _loadOverallResultRows({
    required String showId,
    required String scope,
    required String showLetter,
  }) async {
    final sectionQuery = repo.supabase
        .from('show_sections')
        .select('id')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .eq('kind', scope.toLowerCase());

    final sectionResponse = showLetter == 'ALL'
        ? await sectionQuery
        : await sectionQuery.eq('letter', showLetter);

    final sectionRows = (sectionResponse as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final allRows = <Map<String, dynamic>>[];
    for (final section in sectionRows) {
      final sectionId = _safe(section['id']);
      if (sectionId.isEmpty) continue;

      final response = await repo.supabase.rpc(
        'report_results_entry_rows',
        params: {
          'p_show_id': showId,
          'p_section_id': sectionId,
          'p_show_letter': showLetter,
        },
      );

      allRows.addAll(
        (response as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }

    return allRows;
  }

  List<Map<String, dynamic>> _filterRowsBySpecies(
    List<Map<String, dynamic>> rows,
    String species,
  ) {
    if (species.isEmpty) return rows;
    return rows.where((row) => _rowMatchesSpecies(row, species)).toList();
  }

  bool _rowMatchesSpecies(Map<String, dynamic> row, String species) {
    if (species.isEmpty) return true;

    final rowSpecies = normalizeClubReportSpecies(
      _safe(row['species'] ?? row['animal_species'] ?? row['entry_species']),
    );
    if (rowSpecies.isNotEmpty) return rowSpecies == species;

    if (species == 'cavy') {
      return isKnownCavyBreed(_safe(row['breed_name'] ?? row['breed']));
    }

    return true;
  }

  List<Map<String, dynamic>> _mergeResultRows(
    List<Map<String, dynamic>> breedRows,
    List<Map<String, dynamic>> overallRows,
  ) {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addRows(List<Map<String, dynamic>> source) {
      for (final row in source) {
        final key = _resultRowKey(row);
        if (seen.add(key)) merged.add(row);
      }
    }

    addRows(breedRows);
    addRows(overallRows);
    return merged;
  }

  Future<_SweepstakesPointsLookup> _loadSweepstakesPointsLookup(
    String showId,
    List<String> entryIds,
  ) async {
    final uniqueEntryIds = entryIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (uniqueEntryIds.isEmpty) return const _SweepstakesPointsLookup();

    final rowsOut = <Map<String, dynamic>>[];

    for (var i = 0; i < uniqueEntryIds.length; i += 100) {
      final chunk = uniqueEntryIds.skip(i).take(100).toList();
      final rows = await repo.supabase
          .from('sweepstakes_entry_results')
          .select()
          .eq('show_id', showId)
          .inFilter('entry_id', chunk);

      rowsOut.addAll(
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }

    return _SweepstakesPointsLookup(rowsOut);
  }

  double _pointsForRow(
    Map<String, dynamic> row,
    _SweepstakesPointsLookup sweepstakesPoints, {
    Map<String, dynamic>? fallback,
    String awardCode = '',
    String placement = '',
    String? preferredAwardCode,
  }) {
    final direct = _firstNonEmpty([
      _safe(row['points']),
      _safe(row['sweepstakes_points']),
      _safe(row['points_earned']),
      _safe(row['total_points']),
    ]);
    if (direct.isNotEmpty) {
      final directPoints = _toDouble(direct);
      if (directPoints != 0) return directPoints;
    }

    final preferredPoints =
        preferredAwardCode == null || preferredAwardCode.trim().isEmpty
        ? null
        : sweepstakesPoints.pointsFor(row, awardCode: preferredAwardCode);
    if (preferredPoints != null) return preferredPoints;

    final points = sweepstakesPoints.pointsFor(
      row,
      awardCode: awardCode,
      placement: placement,
    );
    if (points != null) return points;

    if (fallback != null) {
      final fallbackPoints = sweepstakesPoints.pointsFor(
        fallback,
        awardCode: awardCode,
        placement: placement,
      );
      if (fallbackPoints != null) return fallbackPoints;
    }

    return 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().trim()) ?? 0;
  }

  String _resultRowKey(Map<String, dynamic> row) {
    final entryId = _safe(row['entry_id']);
    final lineType = _firstNonEmpty([
      _safe(row['row_type']),
      _safe(row['result_row_type']),
      _safe(row['line_type']),
      if (_bool(row['is_fur']) || _bool(row['entry_is_fur'])) 'fur',
      _safe(row['fur_variety']),
      _safe(row['entry_fur_variety']),
      _pointsCategoryLabel(row),
    ]).toLowerCase();

    if (entryId.isNotEmpty) {
      return 'entry::$entryId::$lineType';
    }

    return [
      'fallback',
      _safe(row['animal_id']).toLowerCase(),
      _safe(row['tattoo']).toLowerCase(),
      _firstNonEmpty([
        _safe(row['breed_name']),
        _safe(row['breed']),
      ]).toLowerCase(),
      _displayVarietyName(row).toLowerCase(),
      _safe(row['class_name']).toLowerCase(),
      _safe(row['sex']).toLowerCase(),
      lineType,
    ].join('::');
  }

  String _displayVarietyName(Map<String, dynamic> row) {
    final furVariety = _firstNonEmpty([
      _safe(row['fur_variety']),
      _safe(row['entry_fur_variety']),
    ]);
    if (furVariety.isNotEmpty) return furVariety;

    return _firstNonEmpty([_safe(row['variety_name']), _safe(row['variety'])]);
  }

  String _pointsCategoryLabel(Map<String, dynamic> row) {
    final explicit = _firstNonEmpty([
      _safe(row['points_category']),
      _safe(row['pointsCategory']),
      _safe(row['points_category_name']),
      _safe(row['sweepstakes_category']),
    ]);
    if (explicit.isNotEmpty) return _normalizePointsCategory(explicit);

    final furVariety = _firstNonEmpty([
      _safe(row['fur_variety']),
      _safe(row['entry_fur_variety']),
    ]);
    if (furVariety.isNotEmpty) return _normalizePointsCategory(furVariety);

    final variety = _firstNonEmpty([
      _safe(row['variety_name']),
      _safe(row['variety']),
    ]);
    return _normalizePointsCategory(variety);
  }

  String _normalizePointsCategory(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    final normalized = value
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();

    if (normalized.contains('white')) return 'White';
    if (normalized.contains('colored') || normalized.contains('colour')) {
      return 'Colored';
    }
    if (normalized.contains('color') && !normalized.contains('white')) {
      return 'Colored';
    }

    return '';
  }

  String _safe(Object? value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _bool(Object? value, {bool fallback = false}) {
    return _detailBool(value, fallback: fallback);
  }
}

class _SweepstakesPointsLookup {
  final List<Map<String, dynamic>> rows;

  const _SweepstakesPointsLookup([this.rows = const []]);

  double? pointsFor(
    Map<String, dynamic> resultRow, {
    String awardCode = '',
    String placement = '',
  }) {
    final entryId = _safeStatic(resultRow['entry_id']);
    if (entryId.isEmpty) return null;

    final candidates = rows.where((row) {
      return _safeStatic(row['entry_id']) == entryId;
    }).toList();

    if (candidates.isEmpty) return null;

    final normalizedAwardCode = _awardCodeKeyStatic(awardCode);
    final normalizedPlacement = _safeStatic(placement);

    final exact = candidates.where((row) {
      if (normalizedAwardCode.isNotEmpty) {
        return _rowAwardCode(row) == normalizedAwardCode;
      }

      if (normalizedPlacement.isNotEmpty) {
        return _rowPlacement(row) == normalizedPlacement &&
            _rowAwardCode(row).isEmpty &&
            _sameClassContext(row, resultRow) &&
            _samePointsCategory(row, resultRow);
      }

      return false;
    }).toList();

    if (exact.isNotEmpty) return _sumPoints(exact);

    if (normalizedAwardCode.isNotEmpty) {
      final awardMatches = candidates.where((row) {
        return _rowAwardCode(row) == normalizedAwardCode;
      }).toList();
      if (awardMatches.isNotEmpty) return _sumPoints(awardMatches);

      final inferredAwardMatches = candidates.where((row) {
        return _awardTextLooksLike(row, normalizedAwardCode);
      }).toList();
      if (inferredAwardMatches.isNotEmpty) {
        return _sumPoints(inferredAwardMatches);
      }

      return null;
    }

    if (normalizedPlacement.isNotEmpty) {
      final placementMatches = candidates.where((row) {
        return _rowPlacement(row) == normalizedPlacement &&
            _sameClassContext(row, resultRow) &&
            _samePointsCategory(row, resultRow);
      }).toList();
      if (placementMatches.isNotEmpty) return _sumPoints(placementMatches);

      final noAwardPlacementMatches = candidates.where((row) {
        return _rowPlacement(row) == normalizedPlacement &&
            _rowAwardCode(row).isEmpty &&
            !_hasAwardLikeText(row);
      }).toList();
      if (noAwardPlacementMatches.isNotEmpty) {
        return _sumPoints(noAwardPlacementMatches);
      }
    }

    if (candidates.length == 1) return _points(candidates.first);

    final noAwardRows = candidates.where((row) => _rowAwardCode(row).isEmpty);
    if (noAwardRows.length == 1) return _points(noAwardRows.first);

    return null;
  }

  static bool _awardTextLooksLike(Map<String, dynamic> row, String awardCode) {
    final combined = [
      _safeStatic(row['award_code']),
      _safeStatic(row['points_source']),
      _safeStatic(row['award']),
      _safeStatic(row['award_type']),
      _safeStatic(row['result_award_code']),
      _safeStatic(row['sweepstakes_award_code']),
      _safeStatic(row['sweepstakes_code']),
      _safeStatic(row['points_code']),
      _safeStatic(row['points_type']),
      _safeStatic(row['category_code']),
      _safeStatic(row['award_name']),
      _safeStatic(row['points_reason']),
      _safeStatic(row['reason']),
      _safeStatic(row['description']),
      _safeStatic(row['notes']),
    ].join(' ').toUpperCase();

    if (combined.isEmpty) return false;

    switch (awardCode) {
      case 'BOB':
        return combined.contains('BOB') || combined.contains('BEST OF BREED');
      case 'BOSB':
      case 'BOS':
        return combined.contains('BOSB') ||
            combined.contains('BEST OPPOSITE SEX OF BREED') ||
            combined.contains('BEST OPPOSITE OF BREED');
      case 'BOV':
        return combined.contains('BOV') || combined.contains('BEST OF VARIETY');
      case 'BOSV':
        return combined.contains('BOSV') ||
            combined.contains('BEST OPPOSITE SEX OF VARIETY') ||
            combined.contains('BEST OPPOSITE OF VARIETY');
      case 'BIS':
        return combined.contains('BIS') || combined.contains('BEST IN SHOW');
      case 'RIS':
      case 'RBIS':
        return combined.contains('RIS') ||
            combined.contains('RESERVE IN SHOW') ||
            combined.contains('RESERVE BEST IN SHOW');
      default:
        return combined.contains(awardCode);
    }
  }

  static bool _hasAwardLikeText(Map<String, dynamic> row) {
    return _awardTextLooksLike(row, 'BOB') ||
        _awardTextLooksLike(row, 'BOSB') ||
        _awardTextLooksLike(row, 'BOV') ||
        _awardTextLooksLike(row, 'BOSV') ||
        _awardTextLooksLike(row, 'BIS') ||
        _awardTextLooksLike(row, 'RIS');
  }

  static double _sumPoints(List<Map<String, dynamic>> rows) {
    return rows.fold<double>(0, (sum, row) => sum + _points(row));
  }

  static double _points(Map<String, dynamic> row) {
    return _toDoubleStatic(
      _firstNonEmptyStatic([
        _safeStatic(row['points']),
        _safeStatic(row['sweepstakes_points']),
        _safeStatic(row['points_earned']),
        _safeStatic(row['total_points']),
      ]),
    );
  }

  static bool _sameClassContext(
    Map<String, dynamic> sweepstakesRow,
    Map<String, dynamic> resultRow,
  ) {
    final rowClass = _normalizeClassNameStatic(
      _firstNonEmptyStatic([
        _safeStatic(sweepstakesRow['class_name']),
        _safeStatic(sweepstakesRow['class']),
        _safeStatic(sweepstakesRow['class_label']),
      ]),
    );
    final resultClass = _normalizeClassNameStatic(
      _safeStatic(resultRow['class_name']),
    );

    if (rowClass.isNotEmpty &&
        resultClass.isNotEmpty &&
        rowClass != resultClass) {
      return false;
    }

    final rowSex = _sexKeyStatic(
      _firstNonEmptyStatic([
        _safeStatic(sweepstakesRow['sex']),
        _safeStatic(sweepstakesRow['sex_label']),
      ]),
    );
    final resultSex = _sexKeyStatic(_safeStatic(resultRow['sex']));

    if (rowSex.isNotEmpty && resultSex.isNotEmpty && rowSex != resultSex) {
      return false;
    }

    return true;
  }

  static bool _samePointsCategory(
    Map<String, dynamic> sweepstakesRow,
    Map<String, dynamic> resultRow,
  ) {
    final rowCategory = _normalizePointsCategoryStatic(
      _firstNonEmptyStatic([
        _safeStatic(sweepstakesRow['points_category']),
        _safeStatic(sweepstakesRow['pointsCategory']),
        _safeStatic(sweepstakesRow['points_category_name']),
        _safeStatic(sweepstakesRow['sweepstakes_category']),
        _safeStatic(sweepstakesRow['variety_name']),
        _safeStatic(sweepstakesRow['variety']),
        _safeStatic(sweepstakesRow['fur_variety']),
      ]),
    );
    final resultCategory = _normalizePointsCategoryStatic(
      _firstNonEmptyStatic([
        _safeStatic(resultRow['points_category']),
        _safeStatic(resultRow['pointsCategory']),
        _safeStatic(resultRow['points_category_name']),
        _safeStatic(resultRow['sweepstakes_category']),
        _safeStatic(resultRow['fur_variety']),
        _safeStatic(resultRow['variety_name']),
        _safeStatic(resultRow['variety']),
      ]),
    );

    if (rowCategory.isNotEmpty &&
        resultCategory.isNotEmpty &&
        rowCategory != resultCategory) {
      return false;
    }

    return true;
  }

  static String _rowAwardCode(Map<String, dynamic> row) {
    return _awardCodeKeyStatic(
      _firstNonEmptyStatic([
        _safeStatic(row['award_code']),
        _safeStatic(row['points_source']),
        _safeStatic(row['award']),
        _safeStatic(row['award_type']),
        _safeStatic(row['result_award_code']),
        _safeStatic(row['sweepstakes_award_code']),
        _safeStatic(row['sweepstakes_code']),
        _safeStatic(row['points_code']),
        _safeStatic(row['points_type']),
        _safeStatic(row['category_code']),
        _safeStatic(row['award_name']),
        _safeStatic(row['points_reason']),
        _safeStatic(row['reason']),
      ]),
    );
  }

  static String _rowPlacement(Map<String, dynamic> row) {
    final explicitPlacement = _firstNonEmptyStatic([
      _safeStatic(row['placement']),
      _safeStatic(row['place']),
      _safeStatic(row['class_placement']),
      _safeStatic(row['fur_placement']),
    ]);
    if (explicitPlacement.isNotEmpty) return explicitPlacement;

    final source = _safeStatic(row['points_source']).toUpperCase();
    if (source == 'CLASS') return '1';

    return '';
  }

  static String _normalizeClassNameStatic(String raw) {
    return normalizeBreedResultsDetailClassName(raw);
  }

  static String _sexKeyStatic(String sex) {
    final s = sex.toLowerCase().trim();
    if (s.contains('buck') || s == 'b') return 'buck';
    if (s.contains('doe') || s == 'd') return 'doe';
    if (s.contains('boar') || s == 'male' || s == 'm') return 'boar';
    if (s.contains('sow') || s == 'female' || s == 'f') return 'sow';
    return s;
  }

  static String _normalizePointsCategoryStatic(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    final normalized = value
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();

    if (normalized.contains('white')) return 'White';
    if (normalized.contains('colored') || normalized.contains('colour')) {
      return 'Colored';
    }
    if (normalized.contains('color') && !normalized.contains('white')) {
      return 'Colored';
    }

    return value;
  }

  static String _awardCodeKeyStatic(String award) {
    final c = award.toUpperCase().trim();

    if (c == 'BEST IN SHOW') return 'BIS';
    if (c == 'RESERVE IN SHOW') return 'RIS';
    if (c == '1RIS') return 'RIS';
    if (c == '1ST RIS') return 'RIS';
    if (c == 'FIRST RIS') return 'RIS';
    if (c == '1ST RESERVE IN SHOW') return 'RIS';
    if (c == 'FIRST RESERVE IN SHOW') return 'RIS';
    if (c == '2RIS') return '2RIS';
    if (c == '2ND RIS') return '2RIS';
    if (c == 'SECOND RIS') return '2RIS';
    if (c == '2ND RESERVE IN SHOW') return '2RIS';
    if (c == 'SECOND RESERVE IN SHOW') return '2RIS';
    if (c == 'RESERVE BEST IN SHOW') return 'RBIS';
    if (c == 'RESERVE OF SHOW') return 'RIS';
    if (c == 'BEST 4 CLASS') return 'B4C';
    if (c == 'BEST 4-CLASS') return 'B4C';
    if (c == 'BEST FOUR CLASS') return 'B4C';
    if (c == 'BEST 6 CLASS') return 'B6C';
    if (c == 'BEST 6-CLASS') return 'B6C';
    if (c == 'BEST SIX CLASS') return 'B6C';
    if (c == 'HONORABLE MENTION') return 'HM';
    if (c == 'BEST OF BREED') return 'BOB';
    if (c == 'BEST OPPOSITE SEX OF BREED') return 'BOSB';
    if (c == 'BEST OPPOSITE OF BREED') return 'BOSB';
    if (c == 'BEST OF GROUP') return 'BOG';
    if (c == 'BEST OPPOSITE SEX OF GROUP') return 'BOSG';
    if (c == 'BEST OPPOSITE OF GROUP') return 'BOSG';
    if (c == 'BEST OF VARIETY') return 'BOV';
    if (c == 'BEST OPPOSITE SEX OF VARIETY') return 'BOSV';
    if (c == 'BEST OPPOSITE OF VARIETY') return 'BOSV';

    return c;
  }

  static String _firstNonEmptyStatic(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  static String _safeStatic(Object? value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static double _toDoubleStatic(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().trim()) ?? 0;
  }
}

String breedResultsDetailTopSectionName(
  Map<String, dynamic> row, {
  required bool groupByBreed,
}) {
  if (groupByBreed) {
    final breedName = _detailFirstNonEmpty([
      _detailSafe(row['breed_name']),
      _detailSafe(row['breed']),
    ]);
    if (breedName.isNotEmpty) return breedName;
    return 'Unspecified Breed';
  }

  return _detailSafe(row['variety_name'], fallback: 'Unspecified Variety');
}

String breedResultsDetailSexLabel(Map<String, dynamic> row) {
  final sex = _detailSafe(row['sex']).toLowerCase();
  final className = _detailSafe(row['class_name']).toLowerCase();

  if (sex.contains('buck') || sex == 'b' || className.contains('buck')) {
    return 'Bucks';
  }

  if (sex.contains('doe') || sex == 'd' || className.contains('doe')) {
    return 'Does';
  }

  if (sex.contains('boar') ||
      sex == 'm' ||
      sex == 'male' ||
      className.contains('boar')) {
    return 'Boars';
  }

  if (sex.contains('sow') ||
      sex == 'f' ||
      sex == 'female' ||
      className.contains('sow')) {
    return 'Sows';
  }

  return 'Unspecified Sex';
}

String normalizeBreedResultsDetailClassName(String raw) {
  final r = raw.toLowerCase();
  if (r.contains('senior') && r.contains('buck')) return 'Sr Bucks';
  if (r.contains('senior') && r.contains('doe')) return 'Sr Does';
  if (r.contains('intermediate') && r.contains('buck')) return 'Int Bucks';
  if (r.contains('intermediate') && r.contains('doe')) return 'Int Does';
  if (r.contains('junior') && r.contains('buck')) return 'Jr Bucks';
  if (r.contains('junior') && r.contains('doe')) return 'Jr Does';
  if (r.contains('senior') && r.contains('boar')) return 'Sr Boars';
  if (r.contains('senior') && r.contains('sow')) return 'Sr Sows';
  if (r.contains('intermediate') && r.contains('boar')) return 'Int Boars';
  if (r.contains('intermediate') && r.contains('sow')) return 'Int Sows';
  if (r.contains('junior') && r.contains('boar')) return 'Jr Boars';
  if (r.contains('junior') && r.contains('sow')) return 'Jr Sows';
  return raw.trim();
}

bool breedResultsDetailIsFurOrWoolRow(Map<String, dynamic> row) {
  if (_detailBool(row['is_fur']) || _detailBool(row['entry_is_fur'])) {
    return true;
  }

  if (_detailSafe(row['fur_variety']).isNotEmpty ||
      _detailSafe(row['entry_fur_variety']).isNotEmpty) {
    return true;
  }

  final rowType = _detailFirstNonEmpty([
    _detailSafe(row['row_type']),
    _detailSafe(row['result_row_type']),
    _detailSafe(row['line_type']),
  ]).toLowerCase();

  return rowType.contains('fur') || rowType.contains('wool');
}

String _detailFirstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String _detailSafe(Object? value, {String fallback = ''}) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

bool _detailBool(Object? value, {bool fallback = false}) {
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

class _JudgedCount {
  final int animals;
  final int exhibitors;

  const _JudgedCount({this.animals = 0, this.exhibitors = 0});
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
