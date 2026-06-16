// lib/screens/admin/closeout/data/loaders/best_display_report_loader.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/base/report_request.dart';
import '../../models/exhibitor/best_display_report_data.dart';

class BestDisplayReportLoader {
  final SupabaseClient supabase;

  BestDisplayReportLoader({
    SupabaseClient? supabase,
  }) : supabase = supabase ?? Supabase.instance.client;

  Future<BestDisplayReportData> load(ReportRequest request) async {
    final showId = request.showId.trim();
    final scope = (request.scope ?? '').trim().toUpperCase();
    final showLetter = (request.showLetter ?? '').trim().toUpperCase();

    if (showId.isEmpty) {
      throw Exception(
        'BestDisplayReportLoader requires request.showId.',
      );
    }

    const minimumEntriesRequired = 6;

    final showRow = await supabase
        .from('shows')
        .select(
          'id, name, start_date, end_date, location_name',
        )
        .eq('id', showId)
        .single();

    final rawStandings = await supabase.rpc(
      'report_best_display_standings',
      params: {
        'p_show_id': showId,
        'p_scope': scope.isEmpty ? null : scope,
        'p_show_letter': showLetter.isEmpty ? null : showLetter,
        'p_minimum_entries': minimumEntriesRequired,
      },
    );

    final rawEntryRows = await supabase.rpc(
      'report_best_display_entry_rows',
      params: {
        'p_show_id': showId,
        'p_scope': scope.isEmpty ? null : scope,
        'p_show_letter': showLetter.isEmpty ? null : showLetter,
      },
    );

    final rows = _parseStandingRows(rawStandings);
    final sections = _groupSections(rows);
    final breedSections = _buildBreedSections(
      rawEntryRows,
      minimumEntriesRequired,
    );

    return BestDisplayReportData(
      showId: showId,
      showName: _string(
        showRow['name'],
        fallback: 'Unnamed Show',
      ),
      showDate: _formatDateRange(
        showRow['start_date'],
        showRow['end_date'],
      ),
      showLocation: _string(showRow['location_name']),
      minimumEntriesRequired: minimumEntriesRequired,
      sections: sections,
      breedSections: breedSections,
    );
  }

  List<BestDisplayStandingRow> _parseStandingRows(Object? rawValue) {
    if (rawValue == null) {
      return const <BestDisplayStandingRow>[];
    }

    if (rawValue is! List) {
      throw Exception(
        'report_best_display_standings returned an unexpected response.',
      );
    }

    return rawValue.map<BestDisplayStandingRow>((rawRow) {
      if (rawRow is! Map) {
        throw Exception(
          'report_best_display_standings returned an invalid row.',
        );
      }

      return BestDisplayStandingRow.fromJson(
        Map<String, dynamic>.from(rawRow),
      );
    }).toList(growable: false);
  }

  List<BestDisplaySectionData> _groupSections(
    List<BestDisplayStandingRow> rows,
  ) {
    final grouped = <String, List<BestDisplayStandingRow>>{};

    for (final row in rows) {
      final key = '${row.sectionId}|${row.species}';
      grouped.putIfAbsent(
        key,
        () => <BestDisplayStandingRow>[],
      );
      grouped[key]!.add(row);
    }

    final sections = grouped.values.map((groupRows) {
      groupRows.sort(_compareStandingRows);
      final first = groupRows.first;

      return BestDisplaySectionData(
        sectionId: first.sectionId,
        scope: first.scope,
        showLetter: first.showLetter,
        species: first.species,
        rows: List<BestDisplayStandingRow>.unmodifiable(groupRows),
      );
    }).toList();

    sections.sort(_compareSections);
    return List<BestDisplaySectionData>.unmodifiable(sections);
  }

  List<BestDisplayBreedSectionData> _buildBreedSections(
    Object? rawValue,
    int minimumEntriesRequired,
  ) {
    if (rawValue == null) {
      return const <BestDisplayBreedSectionData>[];
    }

    if (rawValue is! List) {
      throw Exception(
        'report_best_display_entry_rows returned an unexpected response.',
      );
    }

    final aggregates = <String, _BreedAggregate>{};

    for (final rawRow in rawValue) {
      if (rawRow is! Map) continue;

      final row = Map<String, dynamic>.from(rawRow);
      final sectionId = _string(row['section_id']);
      final scope = _string(row['scope']).toUpperCase();
      final showLetter = _string(row['show_letter']).toUpperCase();
      final species = _string(row['species']).toUpperCase();
      final breedName = _string(
        row['breed_name'],
        fallback: 'Unknown Breed',
      );
      final exhibitorId = _string(row['exhibitor_id']);
      final exhibitorName = _string(
        row['exhibitor_name'],
        fallback: 'Unknown Exhibitor',
      );

      if (sectionId.isEmpty || exhibitorId.isEmpty || breedName.isEmpty) {
        continue;
      }

      final key =
          '$sectionId|$species|${breedName.toLowerCase()}|$exhibitorId';

      final aggregate = aggregates.putIfAbsent(
        key,
        () => _BreedAggregate(
          sectionId: sectionId,
          scope: scope,
          showLetter: showLetter,
          species: species,
          breedName: breedName,
          exhibitorId: exhibitorId,
          exhibitorName: exhibitorName,
        ),
      );

      aggregate.qualifyingEntryCount += 1;

      if (_bool(row['is_point_earning'])) {
        aggregate.pointEarningEntryCount += 1;
      }

      aggregate.displayPoints += _double(row['display_points']);
    }

    final grouped = <String, List<_BreedAggregate>>{};

    for (final aggregate in aggregates.values) {
      final key =
          '${aggregate.sectionId}|${aggregate.species}|${aggregate.breedName.toLowerCase()}';
      grouped.putIfAbsent(key, () => <_BreedAggregate>[]).add(aggregate);
    }

    final result = <BestDisplayBreedSectionData>[];

    for (final group in grouped.values) {
      group.sort((a, b) {
        final eligibleA =
            a.qualifyingEntryCount >= minimumEntriesRequired;
        final eligibleB =
            b.qualifyingEntryCount >= minimumEntriesRequired;

        if (eligibleA != eligibleB) return eligibleA ? -1 : 1;

        final pointsCompare = b.displayPoints.compareTo(a.displayPoints);
        if (pointsCompare != 0) return pointsCompare;

        return a.exhibitorName.toLowerCase().compareTo(
              b.exhibitorName.toLowerCase(),
            );
      });

      final eligiblePointTotals = group
          .where(
            (row) =>
                row.qualifyingEntryCount >= minimumEntriesRequired,
          )
          .map((row) => row.displayPoints)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

      final rows = group.map((aggregate) {
        final isEligible =
            aggregate.qualifyingEntryCount >= minimumEntriesRequired;

        final rank = isEligible
            ? eligiblePointTotals.indexOf(aggregate.displayPoints) + 1
            : null;

        final tiedCount = isEligible
            ? group.where((row) {
                return row.qualifyingEntryCount >=
                        minimumEntriesRequired &&
                    row.displayPoints == aggregate.displayPoints;
              }).length
            : 0;

        final isTied = tiedCount > 1;
        final isWinner = isEligible && rank == 1 && !isTied;

        return BestDisplayBreedStandingRow(
          exhibitorId: aggregate.exhibitorId,
          exhibitorName: aggregate.exhibitorName,
          qualifyingEntryCount: aggregate.qualifyingEntryCount,
          pointEarningEntryCount: aggregate.pointEarningEntryCount,
          displayPoints: aggregate.displayPoints,
          minimumEntriesRequired: minimumEntriesRequired,
          rank: rank,
          isEligible: isEligible,
          isTied: isTied,
          isWinner: isWinner,
        );
      }).toList(growable: false);

      final first = group.first;

      result.add(
        BestDisplayBreedSectionData(
          sectionId: first.sectionId,
          scope: first.scope,
          showLetter: first.showLetter,
          species: first.species,
          breedName: first.breedName,
          rows: rows,
        ),
      );
    }

    result.sort((a, b) {
      final scopeCompare = _scopeRank(a.scope).compareTo(
        _scopeRank(b.scope),
      );
      if (scopeCompare != 0) return scopeCompare;

      final letterCompare = a.showLetter.compareTo(b.showLetter);
      if (letterCompare != 0) return letterCompare;

      final speciesCompare = _speciesRank(a.species).compareTo(
        _speciesRank(b.species),
      );
      if (speciesCompare != 0) return speciesCompare;

      return a.breedName.toLowerCase().compareTo(
            b.breedName.toLowerCase(),
          );
    });

    return List<BestDisplayBreedSectionData>.unmodifiable(result);
  }

  int _compareSections(
    BestDisplaySectionData a,
    BestDisplaySectionData b,
  ) {
    final scopeCompare = _scopeRank(a.scope).compareTo(
      _scopeRank(b.scope),
    );
    if (scopeCompare != 0) return scopeCompare;

    final letterCompare = a.showLetter.compareTo(b.showLetter);
    if (letterCompare != 0) return letterCompare;

    final speciesCompare = _speciesRank(a.species).compareTo(
      _speciesRank(b.species),
    );
    if (speciesCompare != 0) return speciesCompare;

    return a.sectionId.compareTo(b.sectionId);
  }

  int _compareStandingRows(
    BestDisplayStandingRow a,
    BestDisplayStandingRow b,
  ) {
    if (a.isEligible != b.isEligible) {
      return a.isEligible ? -1 : 1;
    }

    final pointsCompare = b.displayPoints.compareTo(a.displayPoints);
    if (pointsCompare != 0) return pointsCompare;

    final eligibleRankCompare =
        (a.eligibleRank ?? 999999).compareTo(b.eligibleRank ?? 999999);
    if (eligibleRankCompare != 0) return eligibleRankCompare;

    return a.exhibitorName.toLowerCase().compareTo(
          b.exhibitorName.toLowerCase(),
        );
  }

  int _scopeRank(String value) {
    switch (value.trim().toUpperCase()) {
      case 'OPEN':
        return 0;
      case 'YOUTH':
        return 1;
      default:
        return 2;
    }
  }

  int _speciesRank(String value) {
    switch (value.trim().toUpperCase()) {
      case 'RABBIT':
        return 0;
      case 'CAVY':
        return 1;
      default:
        return 2;
    }
  }

  String _formatDateRange(Object? startValue, Object? endValue) {
    final start = _parseDate(startValue);
    final end = _parseDate(endValue);

    if (start == null && end == null) return '';
    if (start != null && end == null) return _formatDate(start);
    if (start == null && end != null) return _formatDate(end);

    if (_sameDate(start!, end!)) {
      return _formatDate(start);
    }

    return '${_formatDate(start)} – ${_formatDate(end)}';
  }

  DateTime? _parseDate(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day;
  }

  String _formatDate(DateTime value) {
    return '${value.month}/${value.day}/${value.year}';
  }

  String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  double _double(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _bool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;

    switch (value?.toString().trim().toLowerCase()) {
      case 'true':
      case 't':
      case '1':
      case 'yes':
      case 'y':
        return true;
      case 'false':
      case 'f':
      case '0':
      case 'no':
      case 'n':
        return false;
      default:
        return fallback;
    }
  }
}

class _BreedAggregate {
  final String sectionId;
  final String scope;
  final String showLetter;
  final String species;
  final String breedName;
  final String exhibitorId;
  final String exhibitorName;

  int qualifyingEntryCount = 0;
  int pointEarningEntryCount = 0;
  double displayPoints = 0;

  _BreedAggregate({
    required this.sectionId,
    required this.scope,
    required this.showLetter,
    required this.species,
    required this.breedName,
    required this.exhibitorId,
    required this.exhibitorName,
  });
}