// lib/screens/super_admin/breed_catalog_screen.dart

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import 'breed_editor_screen.dart';

final supabase = Supabase.instance.client;

class BreedCatalogScreen extends StatefulWidget {
  const BreedCatalogScreen({super.key});

  @override
  State<BreedCatalogScreen> createState() => _BreedCatalogScreenState();
}

class _BreedCatalogScreenState extends State<BreedCatalogScreen> {
  String _speciesFilter = 'all'; // all | rabbit | cavy
  String _search = '';
  String? _msg;

  Future<List<Map<String, dynamic>>> _loadBreeds() async {
    final List data;

    if (_speciesFilter == 'all') {
      data = await supabase
          .from('breeds')
          .select('id,name,species,class_system,is_active')
          .order('species')
          .order('name');
    } else {
      data = await supabase
          .from('breeds')
          .select('id,name,species,class_system,is_active')
          .eq('species', _speciesFilter)
          .order('name');
    }

    final list = data.cast<Map<String, dynamic>>();

    final s = _search.trim().toLowerCase();
    final filtered = s.isEmpty
        ? list
        : list.where((b) {
            final name = (b['name'] ?? '').toString().toLowerCase();
            return name.contains(s);
          }).toList();

    filtered.sort((a, b) {
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

      final aSpecies = (a['species'] ?? '').toString();
      final bSpecies = (b['species'] ?? '').toString();

      final speciesCmp = speciesRank(aSpecies).compareTo(speciesRank(bSpecies));
      if (speciesCmp != 0) return speciesCmp;

      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    return filtered;
  }

  String _normalizeLookup(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<List<Map<String, dynamic>>> _loadVarieties({
    required String breedId,
    required String breedName,
    required String species,
  }) async {
    final res = await supabase
        .from('varieties')
        .select('id,name,is_active')
        .eq('breed_id', breedId)
        .order('name');

    final varieties = (res as List).cast<Map<String, dynamic>>();

    if (species.toLowerCase() != 'cavy') {
      return varieties;
    }

    final List sopRes = await supabase
        .from('cavy_sop_variety_order')
        .select('breed_name,variety_name,breed_sort_order,variety_sort_order')
        .order('breed_sort_order')
        .order('variety_sort_order')
        .order('variety_name');

    final existingNames = varieties
        .map((v) => _normalizeLookup((v['name'] ?? '').toString()))
        .toSet();

    final targetBreedName = _normalizeLookup(breedName);
    final sopRows = sopRes.cast<Map<String, dynamic>>().where((row) {
      return _normalizeLookup((row['breed_name'] ?? '').toString()) ==
          targetBreedName;
    }).toList();

    for (final row in sopRows) {
      final varietyName = (row['variety_name'] ?? '').toString().trim();
      if (varietyName.isEmpty) continue;
      if (existingNames.contains(_normalizeLookup(varietyName))) continue;

      varieties.add({
        'id':
            'cavy_sop:${_normalizeLookup(breedName)}:${_normalizeLookup(varietyName)}',
        'name': varietyName,
        'is_active': true,
        'is_cavy_sop': true,
        'variety_sort_order': row['variety_sort_order'],
      });
    }

    varieties.sort((a, b) {
      final aIsSop = a['is_cavy_sop'] == true;
      final bIsSop = b['is_cavy_sop'] == true;

      if (aIsSop || bIsSop) {
        final aSort = a['variety_sort_order'];
        final bSort = b['variety_sort_order'];
        final aOrder = aSort is int ? aSort : int.tryParse('$aSort') ?? 9999;
        final bOrder = bSort is int ? bSort : int.tryParse('$bSort') ?? 9999;
        final orderCmp = aOrder.compareTo(bOrder);
        if (orderCmp != 0) return orderCmp;
      }

      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    return varieties;
  }

  Future<void> _openBreedEditor({
    required String species,
    Map<String, dynamic>? existing,
  }) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BreedEditorScreen(species: species, existing: existing),
      ),
    );

    if (changed == true && mounted) {
      setState(() {
        _msg = existing == null ? 'Breed added.' : 'Breed updated.';
      });
    }
  }

  Future<void> _addVariety({
    required String breedId,
    required String breedName,
  }) async {
    final controller = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AppTheme.surfaceTextScope(
        context,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          title: Text('Add Variety — $breedName'),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Variety name',
              hintText: 'Example: Broken, Black, Himalayan…',
              labelStyle: TextStyle(color: AppColors.muted),
              hintStyle: TextStyle(color: AppColors.muted),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final name = controller.text.trim();
    if (name.isEmpty) return;

    try {
      await supabase.from('varieties').insert({
        'breed_id': breedId,
        'name': name,
        'is_active': true,
      });

      if (!mounted) return;
      setState(() => _msg = 'Added variety "$name" to $breedName');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Add failed: $e');
    }
  }

  Future<void> _setVarietyActive({
    required String varietyId,
    required bool isActive,
  }) async {
    try {
      await supabase
          .from('varieties')
          .update({'is_active': isActive})
          .eq('id', varietyId);

      if (!mounted) return;
      setState(
        () => _msg = isActive ? 'Variety re-enabled' : 'Variety disabled',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Update failed: $e');
    }
  }

  Future<void> _setBreedClassSystem({
    required String breedId,
    required String newValue,
  }) async {
    try {
      await supabase
          .from('breeds')
          .update({'class_system': newValue})
          .eq('id', breedId);

      if (!mounted) return;
      setState(() => _msg = 'Updated class system');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Update failed: $e');
    }
  }

  Future<void> _setBreedActive({
    required String breedId,
    required bool isActive,
  }) async {
    try {
      await supabase
          .from('breeds')
          .update({'is_active': isActive})
          .eq('id', breedId);

      if (!mounted) return;
      setState(() => _msg = isActive ? 'Breed re-enabled' : 'Breed disabled');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Update failed: $e');
    }
  }

  Widget _messageBanner() {
    if (_msg == null) return const SizedBox.shrink();

    final isError =
        _msg!.toLowerCase().contains('failed') ||
        _msg!.toLowerCase().contains('error');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? AppColors.dangerBg : AppColors.successBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? AppColors.danger : AppColors.success,
        ),
      ),
      child: Text(
        _msg!,
        style: TextStyle(
          color: isError ? AppColors.danger : AppColors.success,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: AppTheme.surfaceTextScope(
              context,
              child: TextField(
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: 'Search breeds',
                  prefixIcon: Icon(Icons.search, color: AppColors.muted),
                  labelStyle: TextStyle(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.surface,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AppTheme.gradientTextScope(
            context,
            child: DropdownButton<String>(
              value: _speciesFilter,
              dropdownColor: AppColors.surface,
              iconEnabledColor: AppColors.headerForeground,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.headerForeground,
                fontWeight: FontWeight.w800,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'all',
                  child: Text('All', style: TextStyle(color: AppColors.text)),
                ),
                DropdownMenuItem(
                  value: 'rabbit',
                  child: Text(
                    'Rabbits',
                    style: TextStyle(color: AppColors.text),
                  ),
                ),
                DropdownMenuItem(
                  value: 'cavy',
                  child: Text(
                    'Cavies',
                    style: TextStyle(color: AppColors.text),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _speciesFilter = v ?? 'all'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreedCard(Map<String, dynamic> b) {
    final breedId = b['id'].toString();
    final breedName = (b['name'] ?? '').toString();
    final species = (b['species'] ?? '').toString();
    final classSystem = (b['class_system'] ?? 'four').toString();
    final isActive = b['is_active'] == true;

    return AppTheme.surfaceTextScope(
      context,
      child: Card(
        elevation: 0,
        color: AppColors.surface,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.headerForeground, width: 1.4),
        ),
        child: Builder(
          builder: (context) => ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            iconColor: AppColors.headerDark,
            collapsedIconColor: AppColors.muted,
            title: Text(
              breedName,
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
                decoration: isActive ? null : TextDecoration.lineThrough,
              ),
            ),
            subtitle: Text(
              '${species.toUpperCase()} • class: $classSystem${isActive ? '' : ' • inactive'}',
              style: const TextStyle(color: AppColors.text),
            ),
            trailing: const Icon(Icons.expand_more, color: AppColors.muted),
            children: [
              Row(
                children: [
                  if (species == 'rabbit')
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: classSystem,
                        decoration: const InputDecoration(
                          labelText: 'Class system',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'four',
                            child: Text('4-class'),
                          ),
                          DropdownMenuItem(
                            value: 'six',
                            child: Text('6-class'),
                          ),
                        ],
                        onChanged: (v) {
                          final nv = v ?? classSystem;
                          if (nv != classSystem) {
                            _setBreedClassSystem(
                              breedId: breedId,
                              newValue: nv,
                            );
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  if (species == 'rabbit') const SizedBox(width: 12),
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.secondaryButton,
                      activeTrackColor: AppColors.header.withValues(alpha: .65),
                      title: const Text(
                        'Active',
                        style: TextStyle(color: AppColors.text),
                      ),
                      value: isActive,
                      onChanged: (v) async {
                        if (!v) {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AppTheme.surfaceTextScope(
                              context,
                              child: AlertDialog(
                                backgroundColor: AppColors.surface,
                                surfaceTintColor: Colors.transparent,
                                title: const Text('Disable breed?'),
                                content: Text(
                                  'Disable "$breedName" globally?\n\n'
                                  'This keeps historical data but removes it from normal use.',
                                  style: const TextStyle(color: AppColors.text),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Disable'),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (ok != true) return;
                        }

                        await _setBreedActive(breedId: breedId, isActive: v);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        _openBreedEditor(species: species, existing: b),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Breed'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () async {
                      await _addVariety(breedId: breedId, breedName: breedName);
                      if (!mounted) return;
                      setState(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Variety'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadVarieties(
                  breedId: breedId,
                  breedName: breedName,
                  species: species,
                ),
                builder: (context, vSnap) {
                  if (vSnap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    );
                  }

                  if (vSnap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Varieties error: ${vSnap.error}',
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    );
                  }

                  final vars = vSnap.data ?? [];
                  if (vars.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No varieties for this breed yet.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: vars.map((v) {
                      final varietyId = v['id'].toString();
                      final varietyName = (v['name'] ?? '').toString();
                      final isVarietyActive = v['is_active'] == true;
                      final isCavySop = v['is_cavy_sop'] == true;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          varietyName,
                          style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                            decoration: isVarietyActive
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Text(
                          isCavySop
                              ? 'Cavy SOP variety'
                              : (isVarietyActive ? 'Active' : 'Disabled'),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        trailing: isCavySop
                            ? const Tooltip(
                                message: 'Managed by cavy_sop_variety_order',
                                child: Icon(
                                  Icons.lock_outline,
                                  color: AppColors.muted,
                                ),
                              )
                            : IconButton(
                                tooltip: isVarietyActive
                                    ? 'Disable globally'
                                    : 'Re-enable',
                                icon: Icon(
                                  isVarietyActive
                                      ? Icons.remove_circle_outline
                                      : Icons.undo,
                                  color: AppColors.muted,
                                ),
                                onPressed: () async {
                                  if (isVarietyActive) {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AppTheme.surfaceTextScope(
                                        context,
                                        child: AlertDialog(
                                          backgroundColor: AppColors.surface,
                                          surfaceTintColor: Colors.transparent,
                                          title: const Text('Disable variety?'),
                                          content: Text(
                                            'Disable "$varietyName" globally for $breedName?\n\n'
                                            'This keeps historical data but removes it from dropdowns.',
                                            style: const TextStyle(
                                              color: AppColors.text,
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Disable'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    if (ok != true) return;
                                  }

                                  await _setVarietyActive(
                                    varietyId: varietyId,
                                    isActive: !isVarietyActive,
                                  );
                                  if (!mounted) return;
                                  setState(() {});
                                },
                              ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Breed Catalog',
      showBackButton: true,
      useScrollView: false,
      actions: [
        IconButton(
          tooltip: 'Add Rabbit Breed',
          onPressed: () => _openBreedEditor(species: 'rabbit'),
          icon: const Icon(Icons.pets),
        ),
        IconButton(
          tooltip: 'Add Cavy Breed',
          onPressed: () => _openBreedEditor(species: 'cavy'),
          icon: const Icon(Icons.add),
        ),
      ],
      floatingActionButton: PopupMenuButton<String>(
        tooltip: 'Add breed',
        onSelected: (value) => _openBreedEditor(species: value),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rabbit', child: Text('Add Rabbit Breed')),
          PopupMenuItem(value: 'cavy', child: Text('Add Cavy Breed')),
        ],
        child: FloatingActionButton(
          backgroundColor: AppColors.primaryButton,
          foregroundColor: AppColors.primaryButtonText,
          onPressed: null,
          child: Icon(Icons.add),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Global Breed & Variety Catalog',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.headerForeground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Manage the shared breed and variety list used throughout the system.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.headerForeground.withValues(alpha: .82),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          _messageBanner(),
          _filterBar(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadBreeds(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snap.error}',
                      style: const TextStyle(color: AppColors.headerForeground),
                    ),
                  );
                }

                final breeds = snap.data ?? [];
                if (breeds.isEmpty) {
                  return const Center(
                    child: Text(
                      'No breeds found.',
                      style: TextStyle(color: AppColors.headerForeground),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: breeds.length,
                  itemBuilder: (context, i) => _buildBreedCard(breeds[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
