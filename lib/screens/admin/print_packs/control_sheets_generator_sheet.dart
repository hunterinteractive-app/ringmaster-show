// lib/screens/admin/print_packs/control_sheets_generator_sheet.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'print_pack_pdf_helpers.dart';

final supabase = Supabase.instance.client;

// =======================================================

class ControlSheetsGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;
  final List<Map<String, dynamic>> sections;
  final String? sectionId;
  final List<String> sectionIds;
  final String sectionLabel;
  final bool includeScratched;
  final bool combineSections;
  final bool youthFirst;

  const ControlSheetsGeneratorSheet({
    required this.showId,
    required this.showName,
    required this.sections,
    required this.sectionId,
    required this.sectionIds,
    required this.sectionLabel,
    required this.includeScratched,
    required this.combineSections,
    required this.youthFirst,
  });

  @override
  State<ControlSheetsGeneratorSheet> createState() =>
      _ControlSheetsGeneratorSheetState();
}

class _ControlSheetsGeneratorSheetState
    extends State<ControlSheetsGeneratorSheet> {
  bool _building = false;
  String? _msg;

  double _fontScale = 1.0;

  double _scaled(double base, {double max = 16}) {
    final value = base * _fontScale;
    return value > max ? max : value;
  }

  String _qrResultsUrl({
    required String sectionId,
    required String breed,
  }) {
    final query = Uri(
      queryParameters: {
        'showId': widget.showId,
        if (sectionId.trim().isNotEmpty) 'sectionId': sectionId.trim(),
        if (breed.trim().isNotEmpty) 'breed': breed.trim(),
      },
    ).query;

    return '$kQrResultsEntryBaseUrl?$query';
  }

  String _animalPrintLabel(Map<String, dynamic> row) {
    final name = _safe(row, 'animal_name');
    final tattoo = _safe(row, 'tattoo').toUpperCase();

    // Rabbits should print ear/tattoo only. Cavies may include the animal
    // name because duplicate ear tags are more common there.
    if (!_isCavyRow(row)) return tattoo;

    if (name.isNotEmpty && name.toUpperCase() != tattoo) {
      return '$name • $tattoo';
    }

    if (name.isNotEmpty) return name;
    return tattoo;
  }

  String _safe(Map<String, dynamic> e, String k) =>
      (e[k] ?? '').toString().trim();

  int _coopNumberSortValue(String value) {
    final match = RegExp(r'(\d+)$').firstMatch(value.trim());
    return match == null ? 999999 : int.tryParse(match.group(1)!) ?? 999999;
  }

  String _sectionKindForId(String sectionId) {
    final section = widget.sections.firstWhere(
      (s) => (s['id'] ?? '').toString() == sectionId,
      orElse: () => const <String, dynamic>{},
    );
    return (section['kind'] ?? '').toString().trim().toLowerCase();
  }

  int _toInt(dynamic value, [int fallback = 9999]) {
    if (value == null) return fallback;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? fallback;
  }

  int _sortValue(Map<String, dynamic> row, String key) {
    return _toInt(row[key], 9999);
  }

  String _cavySortKey(String breed, String variety) {
    return '${breed.trim().toLowerCase()}|${variety.trim().toLowerCase()}';
  }

  Future<Map<String, Map<String, int>>> _loadCavySopSortMap() async {
    final rows = await supabase
        .from('cavy_sop_variety_order')
        .select('breed_name, variety_name, breed_sort_order, variety_sort_order');

    final map = <String, Map<String, int>>{};

    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final breed = (row['breed_name'] ?? '').toString().trim();
      final variety = (row['variety_name'] ?? '').toString().trim();

      if (breed.isEmpty || variety.isEmpty) continue;

      map[_cavySortKey(breed, variety)] = {
        'breed': _toInt(row['breed_sort_order']),
        'variety': _toInt(row['variety_sort_order']),
      };
    }

    return map;
  }

  bool _isCavyRow(Map<String, dynamic> row) {
    return _safe(row, 'species').toLowerCase() == 'cavy';
  }

  String _ageOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final l = s.toLowerCase();

    if (l.contains('wool')) return 'Wool';
    if (l.contains('fur')) return 'Fur';

    if (l.contains('senior')) return 'Senior';
    if (l.contains('intermediate')) return 'Intermediate';
    if (l.contains('pre junior') || l.contains('pre-junior')) return 'Pre Junior';
    if (l.contains('junior')) return 'Junior';
    return s;
  }

  bool _isFurOrWoolRow(Map<String, dynamic> row) {
    final rawIsFur = row['is_fur'];
    final isFurFlag = rawIsFur == true ||
        rawIsFur?.toString().trim().toLowerCase() == 'true' ||
        rawIsFur?.toString().trim() == '1';

    final className = _safe(row, 'class_name').toLowerCase();
    final groupName = _safe(row, 'group_name').toLowerCase();
    final variety = _safe(row, 'variety').toLowerCase();

    return isFurFlag ||
        className.contains('fur') ||
        className.contains('wool') ||
        groupName.contains('fur') ||
        groupName.contains('wool') ||
        variety.contains('fur') ||
        variety.contains('wool');
  }

  String _furWoolLabel(Map<String, dynamic> row) {
    final rawIsFur = row['is_fur'];
    final isFurFlag = rawIsFur == true ||
        rawIsFur?.toString().trim().toLowerCase() == 'true' ||
        rawIsFur?.toString().trim() == '1';

    final className = _safe(row, 'class_name').toLowerCase();
    final groupName = _safe(row, 'group_name').toLowerCase();
    final variety = _safe(row, 'variety').toLowerCase();

    if (className.contains('wool') ||
        groupName.contains('wool') ||
        variety.contains('wool')) {
      return 'Wool';
    }

    if (isFurFlag ||
        className.contains('fur') ||
        groupName.contains('fur') ||
        variety.contains('fur')) {
      return 'Fur';
    }

    return 'Fur/Wool';
  }

  int _classSortRankForPrint(String className) {
    final c = className.toLowerCase();
    if (c == 'senior') return 0;
    if (c == 'intermediate') return 1;
    if (c == 'pre junior' || c == 'pre-junior') return 2;
    if (c == 'junior') return 3;
    if (c == 'fur') return 1000;
    if (c == 'wool') return 1001;
    if (c == 'fur/wool') return 1002;
    return 99;
  }

  Future<List<Map<String, dynamic>>> _fetchEntries() async {
    final raw = <Map<String, dynamic>>[];
    final idsToFetch = widget.sectionIds.isNotEmpty
        ? widget.sectionIds
        : [if ((widget.sectionId ?? '').isNotEmpty) widget.sectionId!];

    int kindRankForSectionId(String sectionId) {
      final section = widget.sections.firstWhere(
        (s) => (s['id'] ?? '').toString() == sectionId,
        orElse: () => const <String, dynamic>{},
      );

      final kind = (section['kind'] ?? '').toString().toLowerCase();
      switch (kind) {
        case 'open':
          return widget.youthFirst ? 1 : 0;
        case 'youth':
          return widget.youthFirst ? 0 : 1;
        default:
          return 99;
      }
    }

    int sortOrderForSectionId(String sectionId) {
      final section = widget.sections.firstWhere(
        (s) => (s['id'] ?? '').toString() == sectionId,
        orElse: () => const <String, dynamic>{},
      );
      final value = section['sort_order'];
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? 9999;
    }

    String letterForSectionId(String sectionId) {
      final section = widget.sections.firstWhere(
        (s) => (s['id'] ?? '').toString() == sectionId,
        orElse: () => const <String, dynamic>{},
      );
      return (section['letter'] ?? '').toString().trim().toUpperCase();
    }

    final sortedIdsToFetch = [...idsToFetch]
      ..sort((a, b) {
        final sortCmp = sortOrderForSectionId(a).compareTo(sortOrderForSectionId(b));
        if (sortCmp != 0) return sortCmp;

        final letterCmp = letterForSectionId(a).compareTo(letterForSectionId(b));
        if (letterCmp != 0) return letterCmp;

        final kindCmp = kindRankForSectionId(a).compareTo(kindRankForSectionId(b));
        if (kindCmp != 0) return kindCmp;

        return a.compareTo(b);
      });

    for (final sectionId in sortedIdsToFetch) {
      final rows = await supabase.rpc(
        'report_control_sheet_entries',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': sectionId,
          'p_include_scratched': widget.includeScratched,
        },
      );
      raw.addAll((rows as List).cast<Map<String, dynamic>>());
    }

    // The report_control_sheet_entries RPC may not include is_fur/is_wool,
    // and older versions may exclude fur-only rows entirely. Enrich the RPC
    // result from entries, then add any missing fur/wool rows as a fallback so
    // Fur/Wool control sheets still print.
    final rpcEntryIds = <String>{};
    for (final row in raw) {
      final entryId = _safe(row, 'entry_id').isNotEmpty
          ? _safe(row, 'entry_id')
          : _safe(row, 'id');
      if (entryId.isNotEmpty) rpcEntryIds.add(entryId);
    }

    final entryFlagRows = <Map<String, dynamic>>[];
    final entryIdsList = rpcEntryIds.toList();
    for (var i = 0; i < entryIdsList.length; i += 100) {
      final chunk = entryIdsList.skip(i).take(100).toList();
      if (chunk.isEmpty) continue;

      final rows = await supabase
          .from('entries')
          .select('id,is_fur,animal_id')
          .inFilter('id', chunk);

      entryFlagRows.addAll(List<Map<String, dynamic>>.from(rows));
    }

    final flagsByEntryId = <String, Map<String, dynamic>>{};
    for (final row in entryFlagRows) {
      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty) flagsByEntryId[id] = row;
    }

    for (final row in raw) {
      final entryId = _safe(row, 'entry_id').isNotEmpty
          ? _safe(row, 'entry_id')
          : _safe(row, 'id');
      final flags = flagsByEntryId[entryId];
      if (flags == null) continue;
      row['is_fur'] = flags['is_fur'];
      row['is_wool'] = false;
      row['animal_id'] = flags['animal_id'];
    }

    for (final sectionId in sortedIdsToFetch) {
      final missingFurRows = await supabase
          .from('entries')
          .select('''
            id,
            show_id,
            section_id,
            exhibitor_id,
            animal_id,
            animal_name,
            tattoo,
            breed,
            variety,
            sex,
            class_name,
            species,
            is_fur,
            scratched_at,
            exhibitors:entries_exhibitor_id_fkey (
              display_name,
              showing_name,
              first_name,
              last_name
            ),
            show_sections:section_id (
              kind,
              letter,
              display_name,
              sort_order
            )
          ''')
          .eq('show_id', widget.showId)
          .eq('section_id', sectionId)
          .eq('is_fur', true)
          .order('breed')
          .order('variety')
          .order('class_name')
          .order('sex')
          .order('tattoo');

      for (final row in List<Map<String, dynamic>>.from(missingFurRows)) {
        final entryId = (row['id'] ?? '').toString();
        if (entryId.isEmpty || rpcEntryIds.contains(entryId)) continue;

        final exhibitor = row['exhibitors'];
        final exhibitorMap = exhibitor is Map<String, dynamic>
            ? exhibitor
            : <String, dynamic>{};
        final section = row['show_sections'];
        final sectionMap = section is Map<String, dynamic>
            ? section
            : <String, dynamic>{};

        final displayName = (exhibitorMap['display_name'] ?? '').toString().trim();
        final showingName = (exhibitorMap['showing_name'] ?? '').toString().trim();
        final firstName = (exhibitorMap['first_name'] ?? '').toString().trim();
        final lastName = (exhibitorMap['last_name'] ?? '').toString().trim();
        final fullName = [firstName, lastName].where((v) => v.isNotEmpty).join(' ');

        final sectionKind = (sectionMap['kind'] ?? '').toString().trim();
        final sectionLetter = (sectionMap['letter'] ?? '').toString().trim().toUpperCase();
        final sectionDisplayName = (sectionMap['display_name'] ?? '').toString().trim();
        final sectionLabel = sectionDisplayName.isNotEmpty
            ? sectionDisplayName
            : sectionLetter.isEmpty
                ? sectionKind
                : '${sectionKind.isEmpty ? 'Section' : sectionKind[0].toUpperCase() + sectionKind.substring(1).toLowerCase()} $sectionLetter';

        raw.add({
          'entry_id': entryId,
          'id': entryId,
          'section_id': row['section_id'],
          'section_kind': sectionKind,
          'section_letter': sectionLetter,
          'section_label': sectionLabel,
          'section_sort_order': sectionMap['sort_order'],
          'exhibitor_id': row['exhibitor_id'],
          'exhibitor_label': displayName.isNotEmpty
              ? displayName
              : showingName.isNotEmpty
                  ? showingName
                  : fullName,
          'animal_id': row['animal_id'],
          'animal_name': row['animal_name'],
          'tattoo': row['tattoo'],
          'breed': row['breed'],
          'variety': row['variety'],
          'group_name': '',
          'sex': row['sex'],
          'class_name': row['class_name'],
          'species': row['species'],
          'is_fur': row['is_fur'],
          'is_wool': false,
          'group_sort_order': 9999,
          'variety_sort_order': 9999,
          'uses_group_awards': false,
          'uses_variety_awards': false,
        });
      }
    }

    final byEntryId = <String, Map<String, dynamic>>{};

    for (final row in raw) {
      final entryId = _safe(row, 'entry_id').isNotEmpty
          ? _safe(row, 'entry_id')
          : _safe(row, 'id');

      if (entryId.isEmpty) {
        byEntryId['fallback_${byEntryId.length}'] = row;
        continue;
      }

      byEntryId.putIfAbsent(entryId, () => row);
    }

    final dedupedRows = byEntryId.values.toList();

    final showRow = await supabase
        .from('shows')
        .select('coop_numbering_mode')
        .eq('id', widget.showId)
        .maybeSingle();

    final coopMode = ((showRow as Map<String, dynamic>?)?[
              'coop_numbering_mode'
            ] ??
            'separate')
        .toString()
        .trim()
        .toLowerCase();

    final animalIds = dedupedRows
        .map((row) => _safe(row, 'animal_id'))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final coopRows = <Map<String, dynamic>>[];
    for (var i = 0; i < animalIds.length; i += 200) {
      final chunk = animalIds.skip(i).take(200).toList();
      if (chunk.isEmpty) continue;

      final rows = await supabase
          .from('show_animal_coop_numbers')
          .select('animal_id, scope, coop_number')
          .eq('show_id', widget.showId)
          .inFilter('animal_id', chunk);

      coopRows.addAll(List<Map<String, dynamic>>.from(rows));
    }

    final coopByAnimalAndScope = <String, String>{};
    for (final coopRow in coopRows) {
      final animalId = (coopRow['animal_id'] ?? '').toString().trim();
      final scope = (coopRow['scope'] ?? '').toString().trim().toLowerCase();
      final coopNumber = (coopRow['coop_number'] ?? '').toString().trim();
      if (animalId.isEmpty || scope.isEmpty) continue;
      coopByAnimalAndScope['$animalId|$scope'] = coopNumber;
    }

    for (final row in dedupedRows) {
      final animalId = _safe(row, 'animal_id');
      final sectionId = _safe(row, 'section_id');
      final sectionKind = _safe(row, 'section_kind').isNotEmpty
          ? _safe(row, 'section_kind').toLowerCase()
          : _sectionKindForId(sectionId);
      final scope = coopMode == 'combined' ? 'all' : sectionKind;

      row['coop_number'] = animalId.isEmpty || scope.isEmpty
          ? ''
          : (coopByAnimalAndScope['$animalId|$scope'] ?? '');
    }

    return dedupedRows;
  }

  String _sectionTitleFromRow(Map<String, dynamic> row) {
    final label = _safe(row, 'section_label');
    if (label.isNotEmpty) return label;

    final kind = _safe(row, 'section_kind').toLowerCase();
    final letter = _safe(row, 'section_letter').toUpperCase();

    String kindLabel;
    switch (kind) {
      case 'open':
        kindLabel = 'Open';
        break;
      case 'youth':
        kindLabel = 'Youth';
        break;
      default:
        kindLabel = 'Section';
    }

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  String _colorLabel(Map<String, dynamic> row) {
    final groupName = _safe(row, 'group_name');
    final variety = _safe(row, 'variety');

    if (groupName.isNotEmpty && variety.isNotEmpty) {
      return '$groupName / $variety';
    }
    if (groupName.isNotEmpty) return groupName;
    return variety;
  }

  List<String> _specialsForRow(Map<String, dynamic> row) {
    if (_isFurOrWoolRow(row)) {
      return const <String>[];
    }

    final usesGroupAwards = row['uses_group_awards'] == true;
    final usesVarietyAwards = row['uses_variety_awards'] == true;

    final out = <String>[];

    if (usesVarietyAwards) {
      out.addAll([
        'BOV',
        'BOSV',
      ]);
    }

    if (usesGroupAwards) {
      out.addAll([
        'BOG',
        'BOSG',
      ]);
    }

    out.addAll([
      'BOB',
      'BOS',
    ]);

    return out;
  }

  bool _supportsBestAgeAwards(String breedName) {
    final b = breedName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return b == 'american sable' ||
        b == 'american sables' ||
        b == 'himalayan' ||
        b == 'checkered giant';
  }

  String _ageSpecialForRow(Map<String, dynamic> row) {
    if (_isFurOrWoolRow(row)) return '';

    final cls = _ageOnly(_safe(row, 'class_name')).toLowerCase();
    final isCavy = _isCavyRow(row);
    final breed = _safe(row, 'breed');

    final needsAgeSpecials = isCavy || _supportsBestAgeAwards(breed);
    if (!needsAgeSpecials) return '';

    if (cls == 'senior') return 'Best Sr';
    if (cls == 'intermediate') return 'Best Int';
    if (cls == 'junior') return 'Best Jr';

    return '';
  }

    pw.Document _buildPdf(
      List<Map<String, dynamic>> rows,
      pw.ThemeData theme, {
      required bool includeQrCode,
      required Map<String, Map<String, int>> cavySopSortMap,
    }) {
      final doc = pw.Document(theme: theme);

      final bySection = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final sid = _safe(row, 'section_id');
        bySection.putIfAbsent(sid, () => <Map<String, dynamic>>[]);
        bySection[sid]!.add(row);
      }

      final sectionRows = widget.combineSections
          ? bySection.entries.toList()
          : <MapEntry<String, List<Map<String, dynamic>>>>[
              MapEntry(widget.sectionId ?? '', rows),
            ];


      final allPages = <Map<String, dynamic>>[];

      for (final sectionEntry in sectionRows) {
        final sectionEntries = sectionEntry.value;
        if (sectionEntries.isEmpty) continue;

        final grouped = <String, List<Map<String, dynamic>>>{};

        for (final row in sectionEntries) {
          final breed = _safe(row, 'breed');

          final isFurOrWool = _isFurOrWoolRow(row);

          final color = isFurOrWool ? '' : _colorLabel(row);
          final cls = isFurOrWool
              ? _furWoolLabel(row)
              : _ageOnly(_safe(row, 'class_name'));
          final sex = isFurOrWool ? '' : _safe(row, 'sex');

          final key = [
            breed.toLowerCase(),
            color.toLowerCase(),
            cls.toLowerCase(),
            sex.toLowerCase(),
          ].join('|');

          grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          grouped[key]!.add(row);
        }

        final keys = grouped.keys.toList()
          ..sort((a, b) {
            final aRows = grouped[a] ?? const <Map<String, dynamic>>[];
            final bRows = grouped[b] ?? const <Map<String, dynamic>>[];

            final aFirst = aRows.isEmpty ? <String, dynamic>{} : aRows.first;
            final bFirst = bRows.isEmpty ? <String, dynamic>{} : bRows.first;

            final aIsCavy = _isCavyRow(aFirst);
            final bIsCavy = _isCavyRow(bFirst);

            if (aIsCavy != bIsCavy) {
              return aIsCavy ? 1 : -1;
            }

            if (aIsCavy && bIsCavy) {
              final aBreed = _safe(aFirst, 'breed');
              final bBreed = _safe(bFirst, 'breed');
              final aVariety = _safe(aFirst, 'variety');
              final bVariety = _safe(bFirst, 'variety');

              final aMap = cavySopSortMap[_cavySortKey(aBreed, aVariety)];
              final bMap = cavySopSortMap[_cavySortKey(bBreed, bVariety)];

              final aBreedSort = aIsCavy ? (aMap?['breed'] ?? 9999) : 9999;
              final bBreedSort = bIsCavy ? (bMap?['breed'] ?? 9999) : 9999;

              final breedSortCmp = aBreedSort.compareTo(bBreedSort);
              if (breedSortCmp != 0) return breedSortCmp;

              final aVarietySort = aIsCavy ? (aMap?['variety'] ?? 9999) : 9999;
              final bVarietySort = bIsCavy ? (bMap?['variety'] ?? 9999) : 9999;

              final varietySortCmp = aVarietySort.compareTo(bVarietySort);
              if (varietySortCmp != 0) return varietySortCmp;
            }

            final aParts = a.split('|');
            final bParts = b.split('|');

            final aBreed = aParts.isNotEmpty ? aParts[0] : '';
            final bBreed = bParts.isNotEmpty ? bParts[0] : '';
            final breedCmp = aBreed.compareTo(bBreed);
            if (breedCmp != 0) return breedCmp;

            final aColor = aParts.length > 1 ? aParts[1] : '';
            final bColor = bParts.length > 1 ? bParts[1] : '';

            final aClass = aParts.length > 2 ? aParts[2] : '';
            final bClass = bParts.length > 2 ? bParts[2] : '';

            final aSex = aParts.length > 3 ? aParts[3] : '';
            final bSex = bParts.length > 3 ? bParts[3] : '';

            final aIsFurOrWool = _classSortRankForPrint(aClass) >= 1000;
            final bIsFurOrWool = _classSortRankForPrint(bClass) >= 1000;

            if (aIsFurOrWool != bIsFurOrWool) {
              return aIsFurOrWool ? 1 : -1;
            }

            if (!aIsFurOrWool && !bIsFurOrWool) {
              final groupSortCmp = _sortValue(aFirst, 'group_sort_order')
                  .compareTo(_sortValue(bFirst, 'group_sort_order'));
              if (groupSortCmp != 0) return groupSortCmp;

              final varietySortCmp = _sortValue(aFirst, 'variety_sort_order')
                  .compareTo(_sortValue(bFirst, 'variety_sort_order'));
              if (varietySortCmp != 0) return varietySortCmp;

              final colorCmp = aColor.compareTo(bColor);
              if (colorCmp != 0) return colorCmp;

              final classCmp = _classSortRankForPrint(aClass)
                  .compareTo(_classSortRankForPrint(bClass));
              if (classCmp != 0) return classCmp;

              return aSex.compareTo(bSex);
            }

            final furClassCmp = _classSortRankForPrint(aClass)
                .compareTo(_classSortRankForPrint(bClass));
            if (furClassCmp != 0) return furClassCmp;

            return aColor.compareTo(bColor);
          });

        for (final key in keys) {
          final groupRows = grouped[key]!;
          if (groupRows.isEmpty) continue;

          final first = groupRows.first;
          final exhibitorIds = <String>{};

          for (final row in groupRows) {
            final exId = _safe(row, 'exhibitor_id');
            if (exId.isNotEmpty) exhibitorIds.add(exId);
          }

          final isFurOrWool = _isFurOrWoolRow(first);

          allPages.add({
            'sectionId': _safe(first, 'section_id'),
            'sectionTitle': widget.combineSections
                ? _sectionTitleFromRow(first)
                : widget.sectionLabel,
            'sectionKind': _safe(first, 'section_kind').toLowerCase(),
            'sectionLetter': _safe(first, 'section_letter').toUpperCase(),
            'sectionSortOrder': _toInt(first['section_sort_order']),
            'breed': _safe(first, 'breed'),
            'color': isFurOrWool ? '' : _colorLabel(first),
            'class': isFurOrWool
                ? _furWoolLabel(first)
                : _ageOnly(_safe(first, 'class_name')),
            'sex': isFurOrWool ? '' : _safe(first, 'sex'),
            'rabbitCount': groupRows.length,
            'exhibitorCount': exhibitorIds.length,
            'rows': groupRows,
            'specials': _specialsForRow(first),
            'ageSpecial': _ageSpecialForRow(first),
            'isFurOrWool': isFurOrWool,
            'groupSortOrder': _sortValue(first, 'group_sort_order'),
            'varietySortOrder': _sortValue(first, 'variety_sort_order'),
            'classSortRank': _classSortRankForPrint(
              isFurOrWool
                  ? _furWoolLabel(first)
                  : _ageOnly(_safe(first, 'class_name')),
            ),
          });
        }
      }

      // BEGIN REPLACEMENT BLOCK
      String sectionKindForPage(Map<String, dynamic> page) {
        final rawKind = (page['sectionKind'] ?? '').toString().trim().toLowerCase();
        if (rawKind == 'open' || rawKind == 'youth') return rawKind;

        final title = (page['sectionTitle'] ?? '').toString().trim().toLowerCase();
        if (title.startsWith('open') || title.contains(' open ')) return 'open';
        if (title.startsWith('youth') || title.contains(' youth ')) return 'youth';

        return rawKind;
      }

      int sectionKindRank(Map<String, dynamic> page) {
        final kind = sectionKindForPage(page);
        switch (kind) {
          case 'open':
            return widget.youthFirst ? 1 : 0;
          case 'youth':
            return widget.youthFirst ? 0 : 1;
          default:
            return 99;
        }
      }

      String sectionLetterForPage(Map<String, dynamic> page) {
        final rawLetter = (page['sectionLetter'] ?? '').toString().trim().toUpperCase();
        if (rawLetter.isNotEmpty) return rawLetter;

        final title = (page['sectionTitle'] ?? '').toString().trim().toUpperCase();
        final match = RegExp(r'\b([A-Z])$').firstMatch(title);
        return match?.group(1) ?? '';
      }

      int pageInt(Map<String, dynamic> page, String key) {
        final value = page[key];
        if (value is int) return value;
        return int.tryParse(value?.toString() ?? '') ?? 9999;
      }

      int compareControlPages(Map<String, dynamic> a, Map<String, dynamic> b) {
        if (widget.combineSections) {
          // Paired control sheets should be ordered by breed, then by section.
          // This keeps Open A American Fuzzy Lop together, then Youth A
          // American Fuzzy Lop together, instead of splitting the same breed
          // into repeated Open/Youth runs by class or sex.
          final breedCmp = (a['breed'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['breed'] ?? '').toString().toLowerCase());
          if (breedCmp != 0) return breedCmp;

          final kindCmp = sectionKindRank(a).compareTo(sectionKindRank(b));
          if (kindCmp != 0) return kindCmp;

          final sectionSortCmp = pageInt(a, 'sectionSortOrder')
              .compareTo(pageInt(b, 'sectionSortOrder'));
          if (sectionSortCmp != 0) return sectionSortCmp;

          final sectionLetterCmp = sectionLetterForPage(a).compareTo(sectionLetterForPage(b));
          if (sectionLetterCmp != 0) return sectionLetterCmp;

          final titleCmp = (a['sectionTitle'] ?? '')
              .toString()
              .compareTo((b['sectionTitle'] ?? '').toString());
          if (titleCmp != 0) return titleCmp;

          // Within each Open or Youth section, print all regular breed
          // classes first and place Fur/Wool at the end of that section.
          final aIsFurOrWool = a['isFurOrWool'] == true;
          final bIsFurOrWool = b['isFurOrWool'] == true;
          if (aIsFurOrWool != bIsFurOrWool) {
            return aIsFurOrWool ? 1 : -1;
          }

          final groupCmp = pageInt(a, 'groupSortOrder').compareTo(pageInt(b, 'groupSortOrder'));
          if (groupCmp != 0) return groupCmp;

          final varietyCmp = pageInt(a, 'varietySortOrder').compareTo(pageInt(b, 'varietySortOrder'));
          if (varietyCmp != 0) return varietyCmp;

          final colorCmp = (a['color'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['color'] ?? '').toString().toLowerCase());
          if (colorCmp != 0) return colorCmp;

          final classCmp = pageInt(a, 'classSortRank').compareTo(pageInt(b, 'classSortRank'));
          if (classCmp != 0) return classCmp;

          final sexCmp = (a['sex'] ?? '').toString().toLowerCase().compareTo(
                (b['sex'] ?? '').toString().toLowerCase(),
              );
          if (sexCmp != 0) return sexCmp;

          return 0;
        } else {
          final kindCmp = sectionKindRank(a).compareTo(sectionKindRank(b));
          if (kindCmp != 0) return kindCmp;

          final sectionSortCmp = pageInt(a, 'sectionSortOrder').compareTo(pageInt(b, 'sectionSortOrder'));
          if (sectionSortCmp != 0) return sectionSortCmp;

          final sectionLetterCmp = sectionLetterForPage(a).compareTo(sectionLetterForPage(b));
          if (sectionLetterCmp != 0) return sectionLetterCmp;

          final breedCmp = (a['breed'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['breed'] ?? '').toString().toLowerCase());
          if (breedCmp != 0) return breedCmp;

          // Fur/Wool must always print after every regular class in the breed.
          final aIsFurOrWool = a['isFurOrWool'] == true;
          final bIsFurOrWool = b['isFurOrWool'] == true;

          if (aIsFurOrWool != bIsFurOrWool) {
            return aIsFurOrWool ? 1 : -1;
          }
        }

        // Only use the fallback sorting when not combining sections
        if (!widget.combineSections) {
          final groupCmp = pageInt(a, 'groupSortOrder').compareTo(pageInt(b, 'groupSortOrder'));
          if (groupCmp != 0) return groupCmp;

          final varietyCmp = pageInt(a, 'varietySortOrder').compareTo(pageInt(b, 'varietySortOrder'));
          if (varietyCmp != 0) return varietyCmp;

          final colorCmp = (a['color'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['color'] ?? '').toString().toLowerCase());
          if (colorCmp != 0) return colorCmp;

          final classCmp = pageInt(a, 'classSortRank').compareTo(pageInt(b, 'classSortRank'));
          if (classCmp != 0) return classCmp;

          final sexCmp = (a['sex'] ?? '').toString().toLowerCase().compareTo(
                (b['sex'] ?? '').toString().toLowerCase(),
              );
          if (sexCmp != 0) return sexCmp;

          return (a['sectionTitle'] ?? '').toString().compareTo((b['sectionTitle'] ?? '').toString());
        }

        return 0;
      }

      final sortedAllPages = [...allPages]..sort(compareControlPages);

      final sortedSectionGroups = <MapEntry<String, List<Map<String, dynamic>>>>[];

      if (widget.combineSections) {
        // Keep Open and Youth as separate sheet sections inside the same PDF,
        // while preserving the sorted Open/Youth-by-breed flow. Repeated section
        // titles are allowed here because each run gets its own PDF header.
        String? currentTitle;
        List<Map<String, dynamic>> currentPages = <Map<String, dynamic>>[];

        void flushCurrentRun() {
          if (currentTitle == null || currentPages.isEmpty) return;
          sortedSectionGroups.add(MapEntry(currentTitle!, currentPages));
          currentPages = <Map<String, dynamic>>[];
        }

        for (final p in sortedAllPages) {
          final sectionTitle = (p['sectionTitle'] ?? '').toString().trim().isEmpty
              ? 'Section'
              : (p['sectionTitle'] ?? '').toString().trim();

          if (currentTitle != null && currentTitle != sectionTitle) {
            flushCurrentRun();
          }

          currentTitle = sectionTitle;
          currentPages.add(p);
        }

        flushCurrentRun();
      } else {
        final sectionPageGroups = <String, List<Map<String, dynamic>>>{};
        for (final p in sortedAllPages) {
          final sectionTitle = (p['sectionTitle'] ?? '').toString();
          sectionPageGroups.putIfAbsent(sectionTitle, () => <Map<String, dynamic>>[]);
          sectionPageGroups[sectionTitle]!.add(p);
        }
        sortedSectionGroups.addAll(sectionPageGroups.entries);
      }

      pw.Widget _topHeader({required String showHeader}) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                showHeader,
                style: pw.TextStyle(
                  fontSize: _scaled(12),
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Text(
                'Judging Sheet - Breed Class • Compact',
                style: pw.TextStyle(
                  fontSize: _scaled(12),
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Row(
                    children: [
                      pw.Text(
                        'Judge: ',
                        style: pw.TextStyle(
                          fontSize: _scaled(9),
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          height: 10,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                width: 0.6,
                                color: PdfColors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 18),
                pw.Expanded(
                  child: pw.Row(
                    children: [
                      pw.Text(
                        'Writer: ',
                        style: pw.TextStyle(
                          fontSize: _scaled(9),
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          height: 10,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                width: 0.6,
                                color: PdfColors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        );
      }

      pw.Widget _compactClassHeaderBlock({
        required int blockIndex,
        required int totalBlocks,
        required String sectionTitle,
        required String breed,
        required String color,
        required String cls,
        required String sex,
        required int breedCount,
        required int breedExhibitorCount,
        required int groupCount,
        required int groupExhibitorCount,
        required int rabbitCount,
        required int exhibitorCount,
      }) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 14, bottom: 4),
          padding: const pw.EdgeInsets.only(bottom: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(width: .4, color: PdfColors.grey400),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'Breed: $breed',
                      style: pw.TextStyle(
                        fontSize: _scaled(16, max: 16),
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text(
                    'No. In Breed: $breedCount   No. Exhibitors: $breedExhibitorCount',
                    style: pw.TextStyle(
                      fontSize: _scaled(10),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'Variety: ${color.trim().isEmpty ? 'Standard' : color.replaceAll(' / ', '/')}',
                      style: pw.TextStyle(
                        fontSize: _scaled(13),
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text(
                    'No. In Variety: $groupCount   No. Exhibitors: $groupExhibitorCount',
                    style: pw.TextStyle(
                      fontSize: _scaled(10),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'Class: $cls        Sex: $sex',
                  style: pw.TextStyle(
                    fontSize: _scaled(16, max: 16),
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          ),
        );
      }

      pw.Widget _breedHeaderBlock({
        required String breed,
        required int breedIndex,
        required int totalBreeds,
        String? sectionHint,
      }) {
        return pw.SizedBox.shrink();
      }

      pw.Widget _compactJudgingTable({
        required List<Map<String, dynamic>> groupEntries,
        required List<String> specialsList,
        required String ageSpecial,
        required bool isFurOrWool,
      }) {
        final h = pw.TextStyle(fontSize: _scaled(13), fontWeight: pw.FontWeight.bold);
        final c = pw.TextStyle(fontSize: _scaled(12.5), fontWeight: pw.FontWeight.bold);
        final specialsCell = pw.TextStyle(
          fontSize: _scaled(9, max: 10),
          fontWeight: pw.FontWeight.bold,
        );
        final specialsText = specialsList.join(', ');
        final specialsHeader = ageSpecial.isNotEmpty
            ? 'Specials\n$ageSpecial'
            : 'Specials';

        final sortedGroupEntries = [...groupEntries]
          ..sort((a, b) {
            final coopCompare = _coopNumberSortValue(_safe(a, 'coop_number'))
                .compareTo(
                  _coopNumberSortValue(_safe(b, 'coop_number')),
                );
            if (coopCompare != 0) return coopCompare;
            return _animalPrintLabel(a).compareTo(_animalPrintLabel(b));
          });

        if (isFurOrWool) {
          return pw.Table(
            border: pw.TableBorder.all(width: 0.4),
            columnWidths: {
              0: const pw.FixedColumnWidth(52),
              1: const pw.FixedColumnWidth(64),
              2: const pw.FlexColumnWidth(.85),
              3: const pw.FixedColumnWidth(100),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text('Coop #', style: h),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text('Ear #', style: h),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text('Exhibitor', style: h),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text('Place / DQ', style: h),
                  ),
                ],
              ),
              ...sortedGroupEntries.map((row) {
                return pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(_safe(row, 'coop_number'), style: c),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(_animalPrintLabel(row), style: c),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(_safe(row, 'exhibitor_label'), style: c),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text('', style: c),
                    ),
                  ],
                );
              }),
            ],
          );
        }

        return pw.Table(
          border: pw.TableBorder.all(width: 0.4),
          columnWidths: {
            0: const pw.FixedColumnWidth(52),
            1: const pw.FixedColumnWidth(64),
            2: const pw.FlexColumnWidth(.75),
            3: const pw.FixedColumnWidth(95),
            4: const pw.FixedColumnWidth(76),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text('Coop #', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text('Ear #', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text('Exhibitor', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text('Place / DQ', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(specialsHeader, style: h),
                ),
              ],
            ),
            ...sortedGroupEntries.map((row) {
              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(_safe(row, 'coop_number'), style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(_animalPrintLabel(row), style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(_safe(row, 'exhibitor_label'), style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text('', style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(specialsText, style: specialsCell),
                  ),
                ],
              );
            }),
          ],
        );
      }

      pw.Widget qrResultsBlock({
        required String sectionId,
        required String breed,
      }) {
        final url = _qrResultsUrl(
          sectionId: sectionId,
          breed: breed,
        );

        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 5, bottom: 5),
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: url,
                width: 42,
                height: 42,
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  'Scan to enter results directly into RingMaster One Show. Please also fill out control sheet in full.',
                  style: pw.TextStyle(fontSize: _scaled(7.5), fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      }

      double _estimatedClassBlockHeight({
        required int rowCount,
        required bool includeQr,
        required bool isFurOrWool,
      }) {
        // Conservative estimate in PDF points. Text in the Ear #, Exhibitor,
        // and Specials cells can wrap to multiple lines, so this intentionally
        // estimates taller than a simple one-line table row. The goal is to
        // start a class on a new page before the pdf package is forced to split
        // the class table between pages.
        final headerHeight = 84.0;
        final qrHeight = includeQr ? 64.0 : 0.0;
        final furNoteHeight = isFurOrWool ? 18.0 : 0.0;
        final tableHeaderHeight = 28.0;
        final rowHeight = 28.0;
        final bottomGap = 12.0;
        return headerHeight + qrHeight + furNoteHeight + tableHeaderHeight + (rowCount * rowHeight) + bottomGap;
      }

      for (final sectionGroup in sortedSectionGroups) {
        final sectionTitle = sectionGroup.key;
        final pages = sectionGroup.value;

        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.letter,
            margin: const pw.EdgeInsets.fromLTRB(42, 24, 18, 26),
            theme: theme,
            header: (_) => _topHeader(
              showHeader: '${widget.showName}   $sectionTitle',
            ),
            footer: (context) => pw.Row(
              children: [
                pw.Text('RingMaster One Show', style: pw.TextStyle(fontSize: _scaled(8))),
                pw.Spacer(),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: _scaled(8)),
                ),
                pw.Spacer(),
                pw.Text('${DateTime.now().toLocal()}', style: pw.TextStyle(fontSize: _scaled(8))),
              ],
            ),
            build: (_) {
              final widgets = <pw.Widget>[];
              // Keep this below the physical page body height because wrapped
              // table text can make the real rendered height larger than the
              // simple estimate below.
              const estimatedUsablePageHeight = 535.0;
              const estimatedBreedHeaderHeight = 0.0;
              var estimatedRemainingHeight = estimatedUsablePageHeight;

              final breedGroups = <String, List<Map<String, dynamic>>>{};
              for (final p in pages) {
                final breed = (p['breed'] ?? '').toString().trim();
                final breedKey = breed.isEmpty ? '(Unknown Breed)' : breed;
                breedGroups.putIfAbsent(breedKey, () => <Map<String, dynamic>>[]);
                breedGroups[breedKey]!.add(p);
              }

              final breedNames = breedGroups.keys.toList();

              final breedStats = <String, Map<String, int>>{};
              final groupStats = <String, Map<String, int>>{};

              for (final breedName in breedNames) {
                final breedPagesForStats = breedGroups[breedName] ?? const <Map<String, dynamic>>[];
                final breedEntryIds = <String>{};
                final breedExhibitorIds = <String>{};
                final groupEntryIdsByLabel = <String, Set<String>>{};
                final groupExhibitorIdsByLabel = <String, Set<String>>{};

                for (final p in breedPagesForStats) {
                  final groupLabel = ((p['color'] ?? '').toString().trim().isEmpty)
                      ? 'Standard'
                      : (p['color'] ?? '').toString().trim();
                  final rowsForStats = (p['rows'] as List).cast<Map<String, dynamic>>();

                  groupEntryIdsByLabel.putIfAbsent(groupLabel, () => <String>{});
                  groupExhibitorIdsByLabel.putIfAbsent(groupLabel, () => <String>{});

                  for (var rowIndex = 0; rowIndex < rowsForStats.length; rowIndex++) {
                    final row = rowsForStats[rowIndex];
                    final entryId = _safe(row, 'entry_id').isNotEmpty
                        ? _safe(row, 'entry_id')
                        : _safe(row, 'id').isNotEmpty
                            ? _safe(row, 'id')
                            : '$breedName|$groupLabel|$rowIndex';
                    final exhibitorId = _safe(row, 'exhibitor_id');

                    breedEntryIds.add(entryId);
                    groupEntryIdsByLabel[groupLabel]!.add(entryId);

                    if (exhibitorId.isNotEmpty) {
                      breedExhibitorIds.add(exhibitorId);
                      groupExhibitorIdsByLabel[groupLabel]!.add(exhibitorId);
                    }
                  }
                }

                breedStats[breedName] = {
                  'entries': breedEntryIds.length,
                  'exhibitors': breedExhibitorIds.length,
                };

                for (final groupLabel in groupEntryIdsByLabel.keys) {
                  groupStats['$breedName|$groupLabel'] = {
                    'entries': groupEntryIdsByLabel[groupLabel]!.length,
                    'exhibitors': groupExhibitorIdsByLabel[groupLabel]?.length ?? 0,
                  };
                }
              }

              for (var breedIndex = 0; breedIndex < breedNames.length; breedIndex++) {
                final breed = breedNames[breedIndex];
                final breedPages = breedGroups[breed] ?? const <Map<String, dynamic>>[];
                if (breedPages.isEmpty) continue;

                if (widgets.isNotEmpty) {
                  widgets.add(pw.NewPage());
                }

                estimatedRemainingHeight = estimatedUsablePageHeight - estimatedBreedHeaderHeight;

                for (var i = 0; i < breedPages.length; i++) {
                  final p = breedPages[i];
                  final isFurOrWool = p['isFurOrWool'] == true;

                  final classBlockWidgets = <pw.Widget>[
                    _compactClassHeaderBlock(
                      blockIndex: i,
                      totalBlocks: breedPages.length,
                      sectionTitle: (p['sectionTitle'] ?? '').toString(),
                      breed: breed,
                      color: (p['color'] ?? '').toString(),
                      cls: (p['class'] ?? '').toString(),
                      sex: (p['sex'] ?? '').toString(),
                      breedCount: breedStats[breed]?['entries'] ?? 0,
                      breedExhibitorCount: breedStats[breed]?['exhibitors'] ?? 0,
                      groupCount: groupStats['$breed|${((p['color'] ?? '').toString().trim().isEmpty) ? 'Standard' : (p['color'] ?? '').toString().trim()}']?['entries'] ?? 0,
                      groupExhibitorCount: groupStats['$breed|${((p['color'] ?? '').toString().trim().isEmpty) ? 'Standard' : (p['color'] ?? '').toString().trim()}']?['exhibitors'] ?? 0,
                      rabbitCount: (p['rabbitCount'] as int?) ?? 0,
                      exhibitorCount: (p['exhibitorCount'] as int?) ?? 0,
                    ),
                  ];

                  if (includeQrCode) {
                    classBlockWidgets.add(
                      qrResultsBlock(
                        sectionId: (p['sectionId'] ?? '').toString(),
                        breed: breed,
                      ),
                    );
                  }

                  if (isFurOrWool) {
                    classBlockWidgets.add(
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Text(
                          'Fur/Wool Sheet — placements only',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    );
                  }

                  classBlockWidgets.add(
                    _compactJudgingTable(
                      groupEntries: (p['rows'] as List).cast<Map<String, dynamic>>(),
                      specialsList: (p['specials'] as List).map((x) => x.toString()).toList(),
                      ageSpecial: (p['ageSpecial'] ?? '').toString(),
                      isFurOrWool: isFurOrWool,
                    ),
                  );

                  classBlockWidgets.add(pw.SizedBox(height: 10));

                  final classRowCount = ((p['rows'] as List?) ?? const []).length;
                  final estimatedClassHeight = _estimatedClassBlockHeight(
                    rowCount: classRowCount,
                    includeQr: includeQrCode,
                    isFurOrWool: isFurOrWool,
                  );

                  // If a class will not fit in the estimated remaining page space,
                  // start it on a fresh page. This avoids orphaned class headers
                  // where the header prints at the bottom of one page and all
                  // animals continue on the next page.
                  if (estimatedRemainingHeight < estimatedClassHeight && widgets.isNotEmpty) {
                    widgets.add(pw.NewPage());
                    widgets.add(
                      _breedHeaderBlock(
                        breed: breed,
                        breedIndex: breedIndex,
                        totalBreeds: breedNames.length,
                        sectionHint: null,
                      ),
                    );
                    estimatedRemainingHeight = estimatedUsablePageHeight - estimatedBreedHeaderHeight;
                  }

                  widgets.addAll(classBlockWidgets);
                  estimatedRemainingHeight -= estimatedClassHeight;
                }
              }

              return widgets;
            },
          ),
        );
      }
      // END REPLACEMENT BLOCK
      return doc;
    }

  Future<void> _generatePdf({required bool includeQrCode}) async {
    if (_building) return;

    setState(() {
      _building = true;
      _msg = null;
    });

    try {
      final rows = await _fetchEntries();

      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() {
          _building = false;
          _msg = 'No entries found for this selection.';
        });
        return;
      }

      final cavySopSortMap = await _loadCavySopSortMap();

      final theme = await buildPrintPackPdfTheme();
      final doc = _buildPdf(
        rows,
        theme,
        includeQrCode: includeQrCode,
        cavySopSortMap: cavySopSortMap,
      );
      final bytes = await doc.save();

      final name = 'control_compact_${widget.showName}_${widget.sectionLabel}${includeQrCode ? '_QR' : ''}.pdf';

      final savedPath = await savePdfToUserChosenLocation(
        bytes: Uint8List.fromList(bytes),
        suggestedName: name,
      );

      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = savedPath == null
            ? 'Save canceled.'
            : 'PDF saved to: $savedPath';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = 'PDF build failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isSuccess = _msg != null &&
        (_msg == 'Save canceled.' || _msg!.startsWith('PDF saved to:'));

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: bottomInset + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Generate Control Sheets',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.showName} • ${widget.sectionLabel}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              widget.includeScratched
                  ? 'Including scratched entries'
                  : 'Excluding scratched entries',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              widget.combineSections
                  ? 'Mode: Paired PDF — Open and Youth remain separate sheets'
                  : 'Mode: Single section',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_msg != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSuccess
                      ? Colors.green.withOpacity(.08)
                      : Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSuccess
                        ? Colors.green.withOpacity(.25)
                        : Colors.red.withOpacity(.25),
                  ),
                ),
                child: Text(
                  _msg!,
                  style: TextStyle(
                    color: isSuccess ? Colors.green.shade700 : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Font Size Scale',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Adjust judging sheet text size for clubs that prefer larger print.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('100%'),
                      Expanded(
                        child: Slider(
                          value: _fontScale,
                          min: 1.0,
                          max: 2.0,
                          divisions: 10,
                          label: '${(_fontScale * 100).round()}%',
                          onChanged: _building
                              ? null
                              : (v) {
                                  setState(() {
                                    _fontScale = v;
                                  });
                                },
                        ),
                      ),
                      Text('${(_fontScale * 100).round()}%'),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Maximum rendered font size is capped at 16 pt.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD4A623),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _building ? null : () => _generatePdf(includeQrCode: false),
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(_building ? 'Building Compact PDF…' : 'Generate Compact PDF'),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD4A623)),
              ),
              child: const Text(
                'QR Code Option: adds a secure results-entry QR code to each judging sheet so writers can enter results directly into the system.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B4E00),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF11285A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _building ? null : () => _generatePdf(includeQrCode: true),
              icon: const Icon(Icons.qr_code_2),
              label: Text(
                _building ? 'Building Compact PDF…' : 'Generate Compact PDF with QR Code',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _building ? null : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
