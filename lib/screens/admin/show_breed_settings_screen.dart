// lib/screens/admin/show_breed_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/services/show_lock_service.dart';
import 'package:ringmaster_show/services/app_session.dart';

final supabase = Supabase.instance.client;

/// Show Admin / Super Admin screen:
/// Manage per-show allowed breeds + varieties (overrides).
class ShowBreedSettingsScreen extends StatefulWidget {
  final String showId;
  final String showName;

  const ShowBreedSettingsScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<ShowBreedSettingsScreen> createState() => _ShowBreedSettingsScreenState();
}

class _ShowBreedSettingsScreenState extends State<ShowBreedSettingsScreen> {
  final ScrollController _breedScrollController = ScrollController();

  String _speciesFilter = 'all'; // all | rabbit | cavy
  String _search = '';
  String? _msg;

  // Single-breed show lock
  bool _isSingleBreedShow = false;
  String? _singleBreedId; // breed uuid

  // Cached show settings
  bool _showHasBreedRows = false;

  // show_breeds map: breed_id -> row
  final Map<String, Map<String, dynamic>> _showBreedByBreedId = {};

  // show_varieties by breed_id
  final Map<String, List<Map<String, dynamic>>> _showVarsByBreedId = {};

  // Global varieties by breed_id
  final Map<String, List<Map<String, dynamic>>> _globalVarsByBreedId = {};

  // Cavy SOP varieties by normalized breed name
  final Map<String, List<Map<String, dynamic>>> _cavySopVarsByBreedName = {};

  // Breed list cache
  List<Map<String, dynamic>> _breeds = [];

  bool _loading = true;
  bool _isLocked = false;
  bool _isFinalized = false;

  bool get _isReadOnly => _isLocked || _isFinalized;

  final List<Map<String, dynamic>> _commercialDefaults = const [
    {
      'class_code': 'single_fryer',
      'display_name': 'Single Fryers',
      'sort_order': 10,
    },
    {
      'class_code': 'roaster',
      'display_name': 'Roasters',
      'sort_order': 20,
    },
    {
      'class_code': 'stewer',
      'display_name': 'Stewers',
      'sort_order': 30,
    },
    {
      'class_code': 'meat_pen',
      'display_name': 'Meat Pens',
      'sort_order': 40,
    },
  ];

  final Map<String, Map<String, dynamic>> _showCommercialByCode = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _breedScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadShowLock() async {
    final show = await supabase
        .from('shows')
        .select('is_single_breed_show,single_breed_id,is_locked,finalized_at')
        .eq('id', widget.showId)
        .single();

    _isSingleBreedShow = show['is_single_breed_show'] == true;
    _singleBreedId = show['single_breed_id']?.toString();

    _isLocked = show['is_locked'] == true;
    _isFinalized = (show['finalized_at'] ?? '').toString().trim().isNotEmpty;
  }

  Future<void> _ensureSingleBreedEnabledRow() async {
    if (!_isSingleBreedShow) return;

    final sbid = _singleBreedId;
    if (sbid == null || sbid.isEmpty) return;

    final existing = _showBreedByBreedId[sbid];
    if (existing != null && existing['is_enabled'] == true) return;

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);

      if (existing == null) {
        await supabase.from('show_breeds').insert({
          'show_id': widget.showId,
          'breed_id': sbid,
          'is_enabled': true,
          'class_system_override': null,
        });
      } else {
        await supabase
            .from('show_breeds')
            .update({'is_enabled': true})
            .eq('show_id', widget.showId)
            .eq('breed_id', sbid);
      }

      _showBreedByBreedId[sbid] = {
        'breed_id': sbid,
        'is_enabled': true,
        'class_system_override': existing?['class_system_override'],
      };
      _showHasBreedRows = true;
    } catch (e) {
      _msg = 'Note: Could not force-enable single breed row: $e';
    }
  }

  String _normalizeLookup(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _loadCavySopVarieties() async {
    _cavySopVarsByBreedName.clear();

    final List rows = await supabase
        .from('cavy_sop_variety_order')
        .select('breed_name,variety_name,breed_sort_order,variety_sort_order')
        .order('breed_sort_order')
        .order('variety_sort_order')
        .order('variety_name');

    for (final row in rows.cast<Map<String, dynamic>>()) {
      final breedName = (row['breed_name'] ?? '').toString().trim();
      final varietyName = (row['variety_name'] ?? '').toString().trim();
      if (breedName.isEmpty || varietyName.isEmpty) continue;

      final key = _normalizeLookup(breedName);
      _cavySopVarsByBreedName.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      _cavySopVarsByBreedName[key]!.add({
        'id': 'cavy_sop:${_normalizeLookup(breedName)}:${_normalizeLookup(varietyName)}',
        'breed_id': null,
        'name': varietyName,
        'is_active': true,
        'is_cavy_sop': true,
        'breed_sort_order': row['breed_sort_order'],
        'variety_sort_order': row['variety_sort_order'],
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      await _loadShowLock();

      final List breedData;
      if (_speciesFilter == 'all') {
        breedData = await supabase
            .from('breeds')
            .select('id,name,species,class_system,is_active')
            .eq('is_active', true);
      } else {
        breedData = await supabase
            .from('breeds')
            .select('id,name,species,class_system,is_active')
            .eq('is_active', true)
            .eq('species', _speciesFilter);
      }

      _breeds = breedData.cast<Map<String, dynamic>>();

      final sbid = _singleBreedId;
      if (_isSingleBreedShow && sbid != null && sbid.isNotEmpty) {
        _breeds = _breeds.where((b) => b['id'].toString() == sbid).toList();
      } else {
        final s = _search.trim().toLowerCase();
        if (s.isNotEmpty) {
          _breeds = _breeds.where((b) {
            final name = (b['name'] ?? '').toString().toLowerCase();
            return name.contains(s);
          }).toList();
        }
      }

      int speciesRank(String species) {
        switch (species.toLowerCase()) {
          case 'rabbit':
            return 0;
          case 'cavy':
            return 1;
          default:
            return 99;
        }
      }

      _breeds.sort((a, b) {
        final aSpecies = (a['species'] ?? '').toString();
        final bSpecies = (b['species'] ?? '').toString();

        final speciesCmp = speciesRank(aSpecies).compareTo(speciesRank(bSpecies));
        if (speciesCmp != 0) return speciesCmp;

        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

      final List varData = await supabase
          .from('varieties')
          .select('id,breed_id,name,is_active')
          .eq('is_active', true)
          .order('name');

      await _loadCavySopVarieties();

      _globalVarsByBreedId.clear();
      for (final row in varData.cast<Map<String, dynamic>>()) {
        final bid = row['breed_id']?.toString();
        if (bid == null) continue;
        _globalVarsByBreedId.putIfAbsent(bid, () => <Map<String, dynamic>>[]);
        _globalVarsByBreedId[bid]!.add(row);
      }

      for (final breed in _breeds) {
        final species = (breed['species'] ?? '').toString().toLowerCase();
        if (species != 'cavy') continue;

        final breedId = breed['id']?.toString();
        final breedName = (breed['name'] ?? '').toString();
        if (breedId == null || breedId.isEmpty || breedName.trim().isEmpty) {
          continue;
        }

        final sopRows = _cavySopVarsByBreedName[_normalizeLookup(breedName)] ??
            const <Map<String, dynamic>>[];
        if (sopRows.isEmpty) continue;

        final current = _globalVarsByBreedId.putIfAbsent(
          breedId,
          () => <Map<String, dynamic>>[],
        );
        final existingNames = current
            .map((v) => _normalizeLookup((v['name'] ?? '').toString()))
            .toSet();

        for (final sopRow in sopRows) {
          final sopName = (sopRow['name'] ?? '').toString();
          if (existingNames.contains(_normalizeLookup(sopName))) continue;
          current.add({
            ...sopRow,
            'breed_id': breedId,
          });
        }

        current.sort((a, b) {
          final aSort = a['variety_sort_order'];
          final bSort = b['variety_sort_order'];
          final aOrder = aSort is int ? aSort : int.tryParse('$aSort') ?? 9999;
          final bOrder = bSort is int ? bSort : int.tryParse('$bSort') ?? 9999;
          final orderCmp = aOrder.compareTo(bOrder);
          if (orderCmp != 0) return orderCmp;

          final aName = (a['name'] ?? '').toString().toLowerCase();
          final bName = (b['name'] ?? '').toString().toLowerCase();
          return aName.compareTo(bName);
        });
      }

      final List showBreedData = await supabase
          .from('show_breeds')
          .select('breed_id,is_enabled,class_system_override')
          .eq('show_id', widget.showId);

      _showBreedByBreedId.clear();
      for (final r in showBreedData.cast<Map<String, dynamic>>()) {
        _showBreedByBreedId[r['breed_id'].toString()] = r;
      }
      _showHasBreedRows = showBreedData.isNotEmpty;

      await _ensureSingleBreedEnabledRow();
      await _loadCommercialClasses();

      final List showVarData = await supabase
          .from('show_varieties')
          .select('breed_id,variety_id,custom_name,is_enabled')
          .eq('show_id', widget.showId);

      _showVarsByBreedId.clear();
      for (final r in showVarData.cast<Map<String, dynamic>>()) {
        final bid = r['breed_id']?.toString();
        if (bid == null) continue;
        _showVarsByBreedId.putIfAbsent(bid, () => <Map<String, dynamic>>[]);
        _showVarsByBreedId[bid]!.add(r);
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Load failed: $e';
      });
    }
  }

  bool _breedEnabledDefault(Map<String, dynamic> breed) {
    final bid = breed['id'].toString();

    final sbid = _singleBreedId;
    if (_isSingleBreedShow && sbid != null && bid == sbid) return true;

    final row = _showBreedByBreedId[bid];
    if (row != null) return row['is_enabled'] == true;

    return _showHasBreedRows ? false : true;
  }

  Future<void> _setBreedEnabled(String breedId, bool enabled) async {
    final sbid = _singleBreedId;
    if (_isSingleBreedShow && sbid != null && breedId == sbid) {
      setState(() => _msg = 'This is a single-breed show. The allowed breed cannot be disabled.');
      return;
    }

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);
      final existing = _showBreedByBreedId[breedId];
      if (existing == null) {
        await supabase.from('show_breeds').insert({
          'show_id': widget.showId,
          'breed_id': breedId,
          'is_enabled': enabled,
          'class_system_override': null,
        });
      } else {
        await supabase
            .from('show_breeds')
            .update({'is_enabled': enabled})
            .eq('show_id', widget.showId)
            .eq('breed_id', breedId);
      }

      _showBreedByBreedId[breedId] = {
        'breed_id': breedId,
        'is_enabled': enabled,
        'class_system_override': _showBreedByBreedId[breedId]?['class_system_override'],
      };
      if (!_showHasBreedRows) _showHasBreedRows = true;

      if (!mounted) return;
      setState(() => _msg = enabled ? 'Breed enabled for this show' : 'Breed disabled for this show');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Breed update failed: $e');
    }
  }

  Future<void> _setAllBreedsEnabled(bool enabled) async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final sbid = _singleBreedId;

      for (final breed in _breeds) {
        final breedId = breed['id'].toString();

        if (_isSingleBreedShow && sbid != null && breedId == sbid) {
          if (enabled) {
            await _setBreedEnabled(breedId, true);
          }
          continue;
        }

        await _setBreedEnabled(breedId, enabled);
      }

      if (!mounted) return;
      await _refresh();

      if (!mounted) return;
      setState(() {
        _msg = enabled
            ? 'All visible breeds activated for this show'
            : 'All visible breeds deactivated for this show';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Activate all update failed: $e';
      });
    }
  }

  bool get _areAllVisibleBreedsEnabled {
    if (_breeds.isEmpty) return false;

    final sbid = _singleBreedId;

    for (final breed in _breeds) {
      final breedId = breed['id'].toString();

      if (_isSingleBreedShow && sbid != null && breedId == sbid) {
        continue;
      }

      if (!_breedEnabledDefault(breed)) {
        return false;
      }
    }

    return true;
  }

  String _effectiveClassSystem(Map<String, dynamic> breed) {
    final bid = breed['id'].toString();
    final global = (breed['class_system'] ?? 'four').toString();
    final override = _showBreedByBreedId[bid]?['class_system_override'];
    if (override == null) return global;
    return override.toString();
  }

  String _overrideValueOrNull(Map<String, dynamic> breed) {
    final bid = breed['id'].toString();
    final override = _showBreedByBreedId[bid]?['class_system_override'];
    return override == null ? 'inherit' : override.toString();
  }

  Future<void> _setClassOverride(String breedId, String value) async {
    try {
      await ShowLockService.assertShowUnlocked(widget.showId);
      final dynamic newOverride = (value == 'inherit') ? null : value;

      final existing = _showBreedByBreedId[breedId];
      if (existing == null) {
        await supabase.from('show_breeds').insert({
          'show_id': widget.showId,
          'breed_id': breedId,
          'is_enabled': true,
          'class_system_override': newOverride,
        });
        _showBreedByBreedId[breedId] = {
          'breed_id': breedId,
          'is_enabled': true,
          'class_system_override': newOverride,
        };
        _showHasBreedRows = true;
      } else {
        await supabase
            .from('show_breeds')
            .update({'class_system_override': newOverride})
            .eq('show_id', widget.showId)
            .eq('breed_id', breedId);

        _showBreedByBreedId[breedId] = {
          'breed_id': breedId,
          'is_enabled': existing['is_enabled'],
          'class_system_override': newOverride,
        };
      }

      if (!mounted) return;
      setState(() => _msg = 'Class system override updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Class override failed: $e');
    }
  }

  bool _breedHasVarietyOverrides(String breedId) {
    final rows = _showVarsByBreedId[breedId];
    return rows != null && rows.isNotEmpty;
  }

  Future<void> _ensureVarietyOverridesInitialized(String breedId) async {
    final globals = _globalVarsByBreedId[breedId] ?? const <Map<String, dynamic>>[];
    if (globals.isEmpty) {
      _showVarsByBreedId.putIfAbsent(breedId, () => <Map<String, dynamic>>[]);
      return;
    }

    final existingRows = _showVarsByBreedId[breedId] ?? const <Map<String, dynamic>>[];
    final existingGlobalVarietyIds = existingRows
        .where((r) => r['variety_id'] != null)
        .map((r) => r['variety_id'].toString())
        .toSet();
    final existingCustomNames = existingRows
        .where((r) => r['variety_id'] == null)
        .map((r) => _normalizeLookup((r['custom_name'] ?? '').toString()))
        .toSet();

    final payload = <Map<String, dynamic>>[];

    for (final v in globals) {
      final isCavySop = v['is_cavy_sop'] == true;
      final varietyName = (v['name'] ?? '').toString().trim();

      if (isCavySop) {
        if (varietyName.isEmpty) continue;
        if (existingCustomNames.contains(_normalizeLookup(varietyName))) {
          continue;
        }

        payload.add({
          'show_id': widget.showId,
          'breed_id': breedId,
          'variety_id': null,
          'custom_name': varietyName,
          'is_enabled': true,
        });
      } else {
        final varietyId = v['id']?.toString();
        if (varietyId == null || varietyId.isEmpty) continue;
        if (existingGlobalVarietyIds.contains(varietyId)) continue;

        payload.add({
          'show_id': widget.showId,
          'breed_id': breedId,
          'variety_id': varietyId,
          'custom_name': null,
          'is_enabled': true,
        });
      }
    }

    if (payload.isNotEmpty) {
      try {
        await ShowLockService.assertShowUnlocked(widget.showId);
        await supabase.from('show_varieties').insert(payload);
      } catch (_) {
        for (final row in payload) {
          try {
            await supabase.from('show_varieties').insert(row);
          } catch (_) {}
        }
      }
    }

    final List rows = await supabase
        .from('show_varieties')
        .select('breed_id,variety_id,custom_name,is_enabled')
        .eq('show_id', widget.showId)
        .eq('breed_id', breedId);

    _showVarsByBreedId[breedId] = rows.cast<Map<String, dynamic>>();
  }

  bool _isVarietyEnabledForShow({
    required String breedId,
    required String varietyId,
    String? customName,
  }) {
    final hasOverrides = _breedHasVarietyOverrides(breedId);
    if (!hasOverrides) return true;

    final rows = _showVarsByBreedId[breedId] ?? const <Map<String, dynamic>>[];
    final isCavySopId = varietyId.startsWith('cavy_sop:');

    Iterable<Map<String, dynamic>> match;
    if (isCavySopId && customName != null) {
      final targetName = _normalizeLookup(customName);
      match = rows.where(
        (r) =>
            r['variety_id'] == null &&
            _normalizeLookup((r['custom_name'] ?? '').toString()) == targetName,
      );
    } else {
      match = rows.where((r) => r['variety_id']?.toString() == varietyId);
    }

    final list = match.toList();
    if (list.isEmpty) return false;
    return list.first['is_enabled'] == true;
  }

  Future<void> _setGlobalVarietyEnabled({
    required String breedId,
    required String varietyId,
    required bool enabled,
    String? customName,
  }) async {

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);
      await _ensureVarietyOverridesInitialized(breedId);

      final isCavySopId = varietyId.startsWith('cavy_sop:');
      if (isCavySopId && customName != null) {
        await supabase
            .from('show_varieties')
            .update({'is_enabled': enabled})
            .eq('show_id', widget.showId)
            .eq('breed_id', breedId)
            .isFilter('variety_id', null)
            .eq('custom_name', customName);
      } else {
        await supabase
            .from('show_varieties')
            .update({'is_enabled': enabled})
            .eq('show_id', widget.showId)
            .eq('breed_id', breedId)
            .eq('variety_id', varietyId);
      }

      final List rows = await supabase
          .from('show_varieties')
          .select('breed_id,variety_id,custom_name,is_enabled')
          .eq('show_id', widget.showId)
          .eq('breed_id', breedId);

      _showVarsByBreedId[breedId] = rows.cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() => _msg = enabled ? 'Variety enabled for show' : 'Variety disabled for show');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Variety update failed: $e');
    }
  }

  Future<void> _addCustomVariety({
    required String breedId,
    required String breedName,
  }) async {

    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add Show-only Variety — $breedName'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Custom variety name',
            hintText: 'Example: “Specialty Satin Black”',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );

    if (ok != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);
      await _ensureVarietyOverridesInitialized(breedId);

      await supabase.from('show_varieties').insert({
        'show_id': widget.showId,
        'breed_id': breedId,
        'variety_id': null,
        'custom_name': name,
        'is_enabled': true,
      });

      final List rows = await supabase
          .from('show_varieties')
          .select('breed_id,variety_id,custom_name,is_enabled')
          .eq('show_id', widget.showId)
          .eq('breed_id', breedId);

      _showVarsByBreedId[breedId] = rows.cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() => _msg = 'Added show-only variety "$name"');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Add custom variety failed: $e');
    }
  }

  Future<void> _loadCommercialClasses() async {
    final rows = await supabase
        .from('show_commercial_classes')
        .select('class_code,display_name,is_enabled,sort_order')
        .eq('show_id', widget.showId)
        .order('sort_order');

    _showCommercialByCode.clear();
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final code = (row['class_code'] ?? '').toString();
      if (code.isEmpty) continue;
      _showCommercialByCode[code] = row;
    }
  }

  bool _commercialEnabled(String classCode) {
    final row = _showCommercialByCode[classCode];
    if (row == null) return false;
    return row['is_enabled'] == true;
  }

  Future<void> _setCommercialEnabled({
    required String classCode,
    required String displayName,
    required int sortOrder,
    required bool enabled,
  }) async {

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);
      await supabase.from('show_commercial_classes').upsert({
        'show_id': widget.showId,
        'class_code': classCode,
        'display_name': displayName,
        'is_enabled': enabled,
        'sort_order': sortOrder,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      _showCommercialByCode[classCode] = {
        'class_code': classCode,
        'display_name': displayName,
        'is_enabled': enabled,
        'sort_order': sortOrder,
      };

      if (!mounted) return;
      setState(() {
        _msg = enabled
            ? '$displayName enabled for this show'
            : '$displayName disabled for this show';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Commercial class update failed: $e');
    }
  }

  Widget _buildCommercialClassesCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Text(
          'Commercial Classes',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Enable special commercial rabbit entry types for this show.',
          ),
        ),
        children: [
          ..._commercialDefaults.map((item) {
            final code = item['class_code']!.toString();
            final name = item['display_name']!.toString();
            final sortOrder = item['sort_order'] as int;
            final enabled = _commercialEnabled(code);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withOpacity(.06)),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  code == 'meat_pen'
                      ? 'Special entry with 3 tattoos'
                      : 'Commercial single-rabbit class',
                ),
                value: enabled,
                onChanged: (_loading || _isReadOnly)
                    ? null
                    : (v) => _setCommercialEnabled(
                          classCode: code,
                          displayName: name,
                          sortOrder: sortOrder,
                          enabled: v,
                        ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lockBanner = _isSingleBreedShow
        ? 'Single-breed show: breed list is locked to the selection made when the show was created.'
        : null;

    Widget buildBreedCard(Map<String, dynamic> b) {
      final breedId = b['id'].toString();
      final breedName = (b['name'] ?? '').toString();
      final species = (b['species'] ?? '').toString();
      final globalClassSystem = (b['class_system'] ?? 'four').toString();

      final sbid = _singleBreedId;
      final lockedBreed = _isSingleBreedShow && sbid != null && breedId == sbid;

      final enabled = _breedEnabledDefault(b);
      final effectiveClass = _effectiveClassSystem(b);
      final overrideValue = _overrideValueOrNull(b);

      final hasVarOverrides = _breedHasVarietyOverrides(breedId);
      final globals = _globalVarsByBreedId[breedId] ?? const <Map<String, dynamic>>[];
      final showVarRows = _showVarsByBreedId[breedId] ?? const <Map<String, dynamic>>[];

      final cavySopNames = globals
          .where((v) => v['is_cavy_sop'] == true)
          .map((v) => _normalizeLookup((v['name'] ?? '').toString()))
          .toSet();

      final customRows = showVarRows
          .where((r) {
            final customName = (r['custom_name'] ?? '').toString().trim();
            if (r['variety_id'] != null || customName.isEmpty) return false;
            return !cavySopNames.contains(_normalizeLookup(customName));
          })
          .toList();

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 12,
            ),
          ],
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            breedName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: Switch(
            value: enabled,
            onChanged: (lockedBreed || _isReadOnly)
                ? null
                : (v) => _setBreedEnabled(breedId, v),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${species.toUpperCase()}'
              '${species == 'rabbit' ? ' • class: $effectiveClass' : ''}'
              '${lockedBreed ? ' • (locked)' : (!enabled ? ' • (disabled for show)' : '')}',
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (species == 'rabbit') ...[
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: overrideValue,
                      decoration: const InputDecoration(
                        labelText: 'Class system',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'inherit',
                          child: Text('Inherit (global: $globalClassSystem)'),
                        ),
                        const DropdownMenuItem(
                          value: 'four',
                          child: Text('4-class'),
                        ),
                        const DropdownMenuItem(
                          value: 'six',
                          child: Text('6-class'),
                        ),
                      ],
                      onChanged: _isReadOnly
                          ? null
                          : (v) {
                              final nv = v ?? 'inherit';
                              _setClassOverride(breedId, nv);
                              setState(() {});
                            },
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11285A).withOpacity(.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF11285A).withOpacity(.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            hasVarOverrides
                                ? 'Variety overrides are active for this breed at the show level.'
                                : 'No variety overrides yet. All global varieties are currently allowed by default.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Add show-only variety',
                          icon: const Icon(Icons.add),
                          onPressed: (enabled && !_isReadOnly)
                              ? () async {
                                  await _addCustomVariety(
                                    breedId: breedId,
                                    breedName: breedName,
                                  );
                                  if (!mounted) return;
                                  setState(() {});
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (globals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No global varieties for this breed.'),
                    )
                  else
                    Column(
                      children: globals.map((v) {
                        final varietyId = v['id'].toString();
                        final varietyName = (v['name'] ?? '').toString();
                        final isCavySop = v['is_cavy_sop'] == true;

                        final vEnabled = enabled &&
                            _isVarietyEnabledForShow(
                              breedId: breedId,
                              varietyId: varietyId,
                              customName: isCavySop ? varietyName : null,
                            );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black.withOpacity(.05)),
                          ),
                          child: SwitchListTile(
                            title: Text(varietyName),
                            subtitle: !enabled
                                ? const Text('Breed disabled for show')
                                : isCavySop
                                    ? const Text('Cavy SOP variety')
                                    : (!hasVarOverrides
                                        ? const Text('Default allowed (no overrides yet)')
                                        : null),
                            value: vEnabled,
                            onChanged: (!enabled || _isReadOnly)
                                ? null
                                : (val) async {
                                    await _setGlobalVarietyEnabled(
                                      breedId: breedId,
                                      varietyId: varietyId,
                                      enabled: val,
                                      customName: isCavySop ? varietyName : null,
                                    );
                                    if (!mounted) return;
                                    setState(() {});
                                  },
                          ),
                        );
                      }).toList(),
                    ),
                  if (customRows.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Show-only varieties',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ...customRows.map((r) {
                      final cn = (r['custom_name'] ?? '').toString().trim();
                      final cEnabled = enabled && (r['is_enabled'] == true);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black.withOpacity(.05)),
                        ),
                        child: SwitchListTile(
                          title: Text(cn),
                          subtitle: !enabled
                              ? const Text('Breed disabled for show')
                              : const Text('Custom (show-only)'),
                          value: cEnabled,
                          onChanged: (!enabled || _isReadOnly)
                              ? null
                              : (val) async {
                                  try {
                                    await ShowLockService.assertShowUnlocked(widget.showId);

                                    await supabase
                                        .from('show_varieties')
                                        .update({'is_enabled': val})
                                        .eq('show_id', widget.showId)
                                        .eq('breed_id', breedId)
                                        .isFilter('variety_id', null)
                                        .eq('custom_name', cn);

                                    final List rows = await supabase
                                        .from('show_varieties')
                                        .select('breed_id,variety_id,custom_name,is_enabled')
                                        .eq('show_id', widget.showId)
                                        .eq('breed_id', breedId);

                                    _showVarsByBreedId[breedId] =
                                        rows.cast<Map<String, dynamic>>();

                                    if (!mounted) return;
                                    setState(
                                      () => _msg = val
                                          ? 'Custom variety enabled'
                                          : 'Custom variety disabled',
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    setState(
                                      () => _msg = 'Custom variety update failed: $e',
                                    );
                                  }
                                },
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    final rabbitBreeds = _breeds
        .where((b) => (b['species'] ?? '').toString().toLowerCase() == 'rabbit')
        .toList();
    final cavyBreeds = _breeds
        .where((b) => (b['species'] ?? '').toString().toLowerCase() == 'cavy')
        .toList();
    final otherBreeds = _breeds
        .where((b) {
          final species = (b['species'] ?? '').toString().toLowerCase();
          return species != 'rabbit' && species != 'cavy';
        })
        .toList();

    final shouldGroupCavyBreeds =
        !_isSingleBreedShow && _speciesFilter == 'all' && cavyBreeds.isNotEmpty;

    final shouldGroupRabbitBreeds =
        !_isSingleBreedShow && _speciesFilter == 'all' && rabbitBreeds.isNotEmpty;

    bool areAllBreedsEnabledFor(List<Map<String, dynamic>> breeds) {
      if (breeds.isEmpty) return false;
      return breeds.every(_breedEnabledDefault);
    }

    Future<void> setAllBreedsEnabledFor(
      List<Map<String, dynamic>> breeds,
      bool enabled,
      String label,
    ) async {

      setState(() {
        _loading = true;
        _msg = null;
      });

      try {
        final sbid = _singleBreedId;

        for (final breed in breeds) {
          final breedId = breed['id'].toString();

          if (_isSingleBreedShow && sbid != null && breedId == sbid) {
            if (enabled) {
              await _setBreedEnabled(breedId, true);
            }
            continue;
          }

          await _setBreedEnabled(breedId, enabled);
        }

        if (!mounted) return;
        await _refresh();

        if (!mounted) return;
        setState(() {
          _msg = enabled
              ? '$label activated for this show'
              : '$label deactivated for this show';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _msg = '$label update failed: $e';
        });
      }
    }

    final breedListChildren = <Widget>[
      if (shouldGroupRabbitBreeds)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                blurRadius: 12,
              ),
            ],
          ),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            title: const Text(
              'Rabbit Breeds',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: Switch(
              value: areAllBreedsEnabledFor(rabbitBreeds),
              onChanged: (_loading || _isReadOnly)
                  ? null
                  : (v) => setAllBreedsEnabledFor(
                        rabbitBreeds,
                        v,
                        'Rabbit breeds',
                      ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${rabbitBreeds.length} breeds'),
            ),
            children: rabbitBreeds.map(buildBreedCard).toList(),
          ),
        )
      else
        ...rabbitBreeds.map(buildBreedCard),

      ...otherBreeds.map(buildBreedCard),

      if (shouldGroupCavyBreeds)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                blurRadius: 12,
              ),
            ],
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            title: const Text(
              'Cavy Breeds',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: Switch(
              value: areAllBreedsEnabledFor(cavyBreeds),
              onChanged: (_loading || _isReadOnly)
                  ? null
                  : (v) => setAllBreedsEnabledFor(
                        cavyBreeds,
                        v,
                        'Cavy breeds',
                      ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${cavyBreeds.length} breeds'),
            ),
            children: cavyBreeds.map(buildBreedCard).toList(),
          ),
        )
      else
        ...cavyBreeds.map(buildBreedCard),
    ];

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Breed Settings — ${widget.showName}',
      showBackButton: true,
      useScrollView: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: _loading ? null : _refresh,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (AppSession.isSupportMode)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.support_agent, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Support Mode — You are managing breed settings as an admin while viewing another user.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),

            if (_isReadOnly)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isFinalized
                            ? 'This show has been finalized. Breed settings are view-only.'
                            : 'This show is locked. Breed settings are view-only.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),

            if (lockBanner != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A623).withOpacity(.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFD4A623).withOpacity(.30),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lockBanner,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            if (_msg != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withOpacity(.25),
                  ),
                ),
                child: Text(
                  _msg!,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    enabled: !_isSingleBreedShow && !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Search breeds',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _isSingleBreedShow || _loading
                        ? null
                        : (v) {
                            setState(() => _search = v);
                            _refresh();
                          },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    value: _speciesFilter,
                    decoration: const InputDecoration(
                      labelText: 'Species',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'rabbit', child: Text('Rabbits')),
                      DropdownMenuItem(value: 'cavy', child: Text('Cavies')),
                    ],
                    onChanged: _isSingleBreedShow || _loading
                        ? null
                        : (v) {
                            setState(() => _speciesFilter = v ?? 'all');
                            _refresh();
                          },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            _buildCommercialClassesCard(),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _breeds.isEmpty
                      ? const Center(
                          child: Text(
                            'No breeds found.',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        )
                      : Scrollbar(
                          controller: _breedScrollController,
                          thumbVisibility: true,
                          child: ListView(
                            controller: _breedScrollController,
                            primary: false,
                            physics: const AlwaysScrollableScrollPhysics(),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                            children: breedListChildren,
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}