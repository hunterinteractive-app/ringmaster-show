// lib/screens/super_admin/breed_catalog_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        .eq('is_active', true)
        .order('species')
        .order('name');
  } else {
    data = await supabase
        .from('breeds')
        .select('id,name,species,class_system,is_active')
        .eq('is_active', true)
        .eq('species', _speciesFilter)
        .order('name');
  }

  final list = data.cast<Map<String, dynamic>>();

  final s = _search.trim().toLowerCase();
  if (s.isEmpty) return list;

  return list.where((b) {
    final name = (b['name'] ?? '').toString().toLowerCase();
    return name.contains(s);
  }).toList();
}

  Future<List<Map<String, dynamic>>> _loadVarieties(String breedId) async {
    final res = await supabase
        .from('varieties')
        .select('id,name,is_active')
        .eq('breed_id', breedId)
        .order('name');

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> _addVariety({
    required String breedId,
    required String breedName,
  }) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add Variety — $breedName'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Variety name',
            hintText: 'Example: Broken, Black, Himalayan…',
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
      await supabase.from('varieties').update({'is_active': isActive}).eq('id', varietyId);
      if (!mounted) return;
      setState(() => _msg = isActive ? 'Variety re-enabled' : 'Variety disabled');
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
      await supabase.from('breeds').update({'class_system': newValue}).eq('id', breedId);
      if (!mounted) return;
      setState(() => _msg = 'Updated class system');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Update failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Breed Catalog'),
      ),
      body: Column(
        children: [
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
                    decoration: const InputDecoration(
                      labelText: 'Search breeds',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _search = v),
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
                  onChanged: (v) => setState(() => _speciesFilter = v ?? 'all'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadBreeds(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));

                final breeds = snap.data ?? [];
                if (breeds.isEmpty) {
                  return const Center(child: Text('No breeds found.'));
                }

                return ListView.builder(
                  itemCount: breeds.length,
                  itemBuilder: (context, i) {
                    final b = breeds[i];
                    final breedId = b['id'] as String;
                    final breedName = (b['name'] ?? '').toString();
                    final species = (b['species'] ?? '').toString();
                    final classSystem = (b['class_system'] ?? 'four').toString();

                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: ExpansionTile(
                        title: Text(breedName),
                        subtitle: Text('${species.toUpperCase()} • class: $classSystem'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Class system editor for rabbits
                            if (species == 'rabbit')
                              DropdownButton<String>(
                                value: classSystem,
                                items: const [
                                  DropdownMenuItem(value: 'four', child: Text('4-class')),
                                  DropdownMenuItem(value: 'six', child: Text('6-class')),
                                ],
                                onChanged: (v) {
                                  final nv = v ?? classSystem;
                                  if (nv != classSystem) {
                                    _setBreedClassSystem(breedId: breedId, newValue: nv);
                                    setState(() {}); // refresh tile subtitle
                                  }
                                },
                              ),
                            IconButton(
                              tooltip: 'Add variety',
                              icon: const Icon(Icons.add),
                              onPressed: () async {
                                await _addVariety(breedId: breedId, breedName: breedName);
                                if (!mounted) return;
                                setState(() {}); // refresh varieties list
                              },
                            ),
                          ],
                        ),
                        children: [
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: _loadVarieties(breedId),
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
                                  child: Text('Varieties error: ${vSnap.error}'),
                                );
                              }

                              final vars = vSnap.data ?? [];
                              if (vars.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('No varieties for this breed yet.'),
                                );
                              }

                              return Column(
                                children: vars.map((v) {
                                  final varietyId = v['id'] as String;
                                  final varietyName = (v['name'] ?? '').toString();
                                  final isActive = v['is_active'] == true;

                                  return ListTile(
                                    title: Text(varietyName),
                                    subtitle: Text(isActive ? 'Active' : 'Disabled'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isActive)
                                          IconButton(
                                            tooltip: 'Disable globally',
                                            icon: const Icon(Icons.remove_circle_outline),
                                            onPressed: () async {
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (_) => AlertDialog(
                                                  title: const Text('Disable variety?'),
                                                  content: Text(
                                                    'Disable "$varietyName" globally for $breedName?\n\n'
                                                    'This keeps historical data but removes it from dropdowns.',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context, false),
                                                      child: const Text('Cancel'),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () => Navigator.pop(context, true),
                                                      child: const Text('Disable'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok != true) return;
                                              await _setVarietyActive(
                                                varietyId: varietyId,
                                                isActive: false,
                                              );
                                              if (!mounted) return;
                                              setState(() {});
                                            },
                                          )
                                        else
                                          IconButton(
                                            tooltip: 'Re-enable',
                                            icon: const Icon(Icons.undo),
                                            onPressed: () async {
                                              await _setVarietyActive(
                                                varietyId: varietyId,
                                                isActive: true,
                                              );
                                              if (!mounted) return;
                                              setState(() {});
                                            },
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}