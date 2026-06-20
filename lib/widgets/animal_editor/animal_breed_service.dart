// lib/widgets/animal_editor/animal_breed_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class AnimalBreedService {
  static bool isLopBreedName(String breedName) {
    return breedName.trim().toLowerCase().endsWith('lop');
  }

  static Future<List<Map<String, dynamic>>> loadBreedsForSpecies(
    String species,
  ) async {
    // Try normal breeds table first for BOTH rabbit and cavy.
    final breedRows = await supabase
        .from('breeds')
        .select('id,name,species,is_active')
        .eq('species', species)
        .eq('is_active', true)
        .order('name');

    final normalBreeds =
        (breedRows as List).cast<Map<String, dynamic>>();

    // If cavy rows exist in breeds table, use them.
    if (species == 'cavy' && normalBreeds.isNotEmpty) {
      return normalBreeds;
    }

    // Rabbit normal path.
    if (species == 'rabbit') {
      return normalBreeds;
    }

    // Cavy fallback: build breed list from SOP table.
    final sopRows = await supabase
        .from('cavy_sop_variety_order')
        .select('breed_name, breed_sort_order')
        .order('breed_sort_order');

    final byBreed = <String, Map<String, dynamic>>{};

    for (final row in (sopRows as List).cast<Map<String, dynamic>>()) {
      final name = (row['breed_name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final key = name.toLowerCase();

      byBreed[key] = {
        'id': key,
        'name': name,
        'sort_order': row['breed_sort_order'],
      };
    }

    final result = byBreed.values.toList()
      ..sort((a, b) {
        final ai =
            int.tryParse((a['sort_order'] ?? '').toString()) ?? 9999;

        final bi =
            int.tryParse((b['sort_order'] ?? '').toString()) ?? 9999;

        final cmp = ai.compareTo(bi);
        if (cmp != 0) return cmp;

        return (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo(
              (b['name'] ?? '').toString().toLowerCase(),
            );
      });

    return result;
  }

  static Future<List<Map<String, dynamic>>> loadVarietiesForBreed({
    required String species,
    required String breedId,
    required List<Map<String, dynamic>> breedOptions,
    String? showId,
  }) async {
    final matchedBreed = breedOptions.firstWhere(
      (b) => (b['id'] ?? '').toString() == breedId,
      orElse: () => <String, dynamic>{},
    );

    final breedName =
        (matchedBreed['name'] ?? '').toString().trim();

    if (species == 'cavy') {
      final res = await supabase
          .from('cavy_sop_variety_order')
          .select('id, variety_name, variety_sort_order')
          .eq('breed_name', breedName)
          .order('variety_sort_order');

      final effective = res.map((row) {
        final map = Map<String, dynamic>.from(row as Map);

        return {
          'id': (map['id'] ?? map['variety_name']).toString(),
          'name': (map['variety_name'] ?? '').toString(),
          'sort_order': map['variety_sort_order'],
        };
      }).where((v) {
        return (v['name'] ?? '').toString().trim().isNotEmpty;
      }).toList();

      return effective;
    }

    if (isLopBreedName(breedName)) {
      return const [
        {'id': 'lop_broken', 'name': 'Broken'},
        {'id': 'lop_solid', 'name': 'Solid'},
      ];
    }

    final globalRows = await supabase
        .from('varieties')
        .select('id,name')
        .eq('breed_id', breedId)
        .order('name');

    final globalVarieties = (globalRows as List)
        .cast<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final trimmedShowId = showId?.trim();

    // When this editor is opened from inside a show, respect the show's
    // enabled/disabled/custom variety list. When showId is null, keep using
    // the global list so My Animals still works outside a show.
    if (trimmedShowId == null || trimmedShowId.isEmpty) {
      return globalVarieties;
    }

    final showRows = await supabase
        .from('show_varieties')
        .select('id,variety_id,custom_name,is_enabled')
        .eq('show_id', trimmedShowId)
        .eq('breed_id', breedId);

    final showVarieties =
        (showRows as List).cast<Map<String, dynamic>>();

    final disabledVarietyIds = showVarieties
        .where((row) => row['is_enabled'] == false)
        .map((row) => (row['variety_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    final effective = globalVarieties.where((row) {
      final id = (row['id'] ?? '').toString();
      return !disabledVarietyIds.contains(id);
    }).toList();

    for (final row in showVarieties) {
      if (row['is_enabled'] != true) continue;

      final customName =
          (row['custom_name'] ?? '').toString().trim();
      if (customName.isEmpty) continue;

      effective.add({
        'id': (row['id'] ?? customName).toString(),
        'name': customName,
      });
    }

    effective.sort((a, b) {
      return (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase());
    });

    return effective;
  }
}