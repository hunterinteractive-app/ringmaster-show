import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // Breed list cache
  List<Map<String, dynamic>> _breeds = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _loadShowLock() async {
    final show = await supabase
        .from('shows')
        .select('is_single_breed_show,single_breed_id')
        .eq('id', widget.showId)
        .single();

    _isSingleBreedShow = show['is_single_breed_show'] == true;
    _singleBreedId = show['single_breed_id']?.toString();
  }

  Future<void> _ensureSingleBreedEnabledRow() async {
    if (!_isSingleBreedShow) return;

    final sbid = _singleBreedId;
    if (sbid == null || sbid.isEmpty) return;

    final existing = _showBreedByBreedId[sbid];
    if (existing != null && existing['is_enabled'] == true) return;

    try {
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

      _globalVarsByBreedId.clear();
      for (final row in varData.cast<Map<String, dynamic>>()) {
        final bid = row['breed_id']?.toString();
        if (bid == null) continue;
        _globalVarsByBreedId.putIfAbsent(bid, () => <Map<String, dynamic>>[]);
        _globalVarsByBreedId[bid]!.add(row);
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
    if (_breedHasVarietyOverrides(breedId)) return;

    final globals = _globalVarsByBreedId[breedId] ?? const <Map<String, dynamic>>[];
    if (globals.isEmpty) {
      _showVarsByBreedId[breedId] = <Map<String, dynamic>>[];
      return;
    }

    final payload = globals.map((v) {
      return {
        'show_id': widget.showId,
        'breed_id': breedId,
        'variety_id': v['id'],
        'custom_name': null,
        'is_enabled': true,
      };
    }).toList();

    try {
      await supabase.from('show_varieties').insert(payload);
    } catch (_) {
      for (final row in payload) {
        try {
          await supabase.from('show_varieties').insert(row);
        } catch (_) {}
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
  }) {
    final hasOverrides = _breedHasVarietyOverrides(breedId);
    if (!hasOverrides) return true;

    final rows = _showVarsByBreedId[breedId] ?? const <Map<String, dynamic>>[];
    final match = rows.where((r) => r['variety_id']?.toString() == varietyId).toList();
    if (match.isEmpty) return false;
    return match.first['is_enabled'] == true;
  }

  Future<void> _setGlobalVarietyEnabled({
    required String breedId,
    required String varietyId,
    required bool enabled,
  }) async {
    try {
      await _ensureVarietyOverridesInitialized(breedId);

      await supabase
          .from('show_varieties')
          .update({'is_enabled': enabled})
          .eq('show_id', widget.showId)
          .eq('breed_id', breedId)
          .eq('variety_id', varietyId);

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

  @override
  Widget build(BuildContext context) {
    final lockBanner = _isSingleBreedShow
        ? 'Single-breed show: breed list is locked to the selection made when the show was created.'
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Breed Settings — ${widget.showName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          if (lockBanner != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.lock, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(lockBanner)),
                ],
              ),
            ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_msg!, style: const TextStyle(color: Colors.green)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    enabled: !_isSingleBreedShow,
                    decoration: const InputDecoration(
                      labelText: 'Search breeds',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) {
                      setState(() => _search = v);
                      _refresh();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _speciesFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'rabbit', child: Text('Rabbits')),
                    DropdownMenuItem(value: 'cavy', child: Text('Cavies')),
                  ],
                  onChanged: _isSingleBreedShow
                      ? null
                      : (v) {
                          setState(() => _speciesFilter = v ?? 'all');
                          _refresh();
                        },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activate All Visible Breeds'),
              subtitle: Text(
                _isSingleBreedShow
                    ? 'Applies to the visible list. Locked single-breed selection remains enabled.'
                    : 'Turns all currently visible breeds on or off for this show.',
              ),
              value: _areAllVisibleBreedsEnabled,
              onChanged: _loading ? null : (v) => _setAllBreedsEnabled(v),
            ),
          ),
          const Divider(height: 1),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: _breeds.isEmpty
                  ? const Center(child: Text('No breeds found.'))
                  : ListView.builder(
                      itemCount: _breeds.length,
                      itemBuilder: (context, i) {
                        final b = _breeds[i];
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

                        final customRows = showVarRows
                            .where((r) =>
                                r['variety_id'] == null &&
                                (r['custom_name'] ?? '').toString().trim().isNotEmpty)
                            .toList();

                        return Card(
                          margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: ExpansionTile(
                            title: Row(
                              children: [
                                Expanded(child: Text(breedName)),
                                Switch(
                                  value: enabled,
                                  onChanged: lockedBreed ? null : (v) => _setBreedEnabled(breedId, v),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${species.toUpperCase()}'
                              '${species == 'rabbit' ? ' • class: $effectiveClass' : ''}'
                              '${lockedBreed ? ' • (locked)' : (!enabled ? ' • (disabled for show)' : '')}',
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (species == 'rabbit') ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Text('Class system:'),
                                          const SizedBox(width: 12),
                                          DropdownButton<String>(
                                            value: overrideValue,
                                            items: [
                                              DropdownMenuItem(
                                                value: 'inherit',
                                                child: Text('Inherit (global: $globalClassSystem)'),
                                              ),
                                              const DropdownMenuItem(value: 'four', child: Text('4-class')),
                                              const DropdownMenuItem(value: 'six', child: Text('6-class')),
                                            ],
                                            onChanged: (v) {
                                              final nv = v ?? 'inherit';
                                              _setClassOverride(breedId, nv);
                                              setState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            hasVarOverrides
                                                ? 'Variety overrides are ACTIVE for this breed (show-level).'
                                                : 'No variety overrides yet: all global varieties allowed by default.',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Add show-only variety',
                                          icon: const Icon(Icons.add),
                                          onPressed: enabled
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
                                    const Divider(),
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

                                          final vEnabled = enabled &&
                                              _isVarietyEnabledForShow(
                                                breedId: breedId,
                                                varietyId: varietyId,
                                              );

                                          return SwitchListTile(
                                            title: Text(varietyName),
                                            subtitle: !enabled
                                                ? const Text('Breed disabled for show')
                                                : (!hasVarOverrides
                                                    ? const Text('Default allowed (no overrides yet)')
                                                    : null),
                                            value: vEnabled,
                                            onChanged: !enabled
                                                ? null
                                                : (val) async {
                                                    await _setGlobalVarietyEnabled(
                                                      breedId: breedId,
                                                      varietyId: varietyId,
                                                      enabled: val,
                                                    );
                                                    if (!mounted) return;
                                                    setState(() {});
                                                  },
                                          );
                                        }).toList(),
                                      ),
                                    if (customRows.isNotEmpty) ...[
                                      const Divider(),
                                      Text('Show-only varieties', style: Theme.of(context).textTheme.titleSmall),
                                      const SizedBox(height: 6),
                                      ...customRows.map((r) {
                                        final cn = (r['custom_name'] ?? '').toString().trim();
                                        final cEnabled = enabled && (r['is_enabled'] == true);

                                        return SwitchListTile(
                                          title: Text(cn),
                                          subtitle: !enabled
                                              ? const Text('Breed disabled for show')
                                              : const Text('Custom (show-only)'),
                                          value: cEnabled,
                                          onChanged: !enabled
                                              ? null
                                              : (val) async {
                                                  try {
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

                                                    _showVarsByBreedId[breedId] = rows.cast<Map<String, dynamic>>();

                                                    if (!mounted) return;
                                                    setState(() => _msg = val
                                                        ? 'Custom variety enabled'
                                                        : 'Custom variety disabled');
                                                  } catch (e) {
                                                    if (!mounted) return;
                                                    setState(() => _msg = 'Custom variety update failed: $e');
                                                  }
                                                },
                                        );
                                      }).toList(),
                                    ],
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}