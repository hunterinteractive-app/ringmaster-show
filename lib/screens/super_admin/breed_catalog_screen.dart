// lib/screens/super_admin/breed_catalog_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

      final speciesCmp =
          speciesRank(aSpecies).compareTo(speciesRank(bSpecies));
      if (speciesCmp != 0) return speciesCmp;

      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    return filtered;
  }

  Future<List<Map<String, dynamic>>> _loadVarieties(String breedId) async {
    final res = await supabase
        .from('varieties')
        .select('id,name,is_active')
        .eq('breed_id', breedId)
        .order('name');

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> _openBreedEditor({
    required String species,
    Map<String, dynamic>? existing,
  }) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BreedEditorScreen(
          species: species,
          existing: existing,
        ),
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
          .update({'is_active': isActive}).eq('id', varietyId);

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
      await supabase
          .from('breeds')
          .update({'class_system': newValue}).eq('id', breedId);

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
          .update({'is_active': isActive}).eq('id', breedId);

      if (!mounted) return;
      setState(() => _msg = isActive ? 'Breed re-enabled' : 'Breed disabled');
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Update failed: $e');
    }
  }

  Widget _messageBanner() {
    if (_msg == null) return const SizedBox.shrink();

    final isError = _msg!.toLowerCase().contains('failed') ||
        _msg!.toLowerCase().contains('error');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isError ? Colors.red : Colors.green).withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isError ? Colors.red : Colors.green).withOpacity(.22),
        ),
      ),
      child: Text(
        _msg!,
        style: TextStyle(
          color: isError ? Colors.red : Colors.green.shade700,
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
    );
  }

  Widget _buildBreedCard(Map<String, dynamic> b) {
    final breedId = b['id'].toString();
    final breedName = (b['name'] ?? '').toString();
    final species = (b['species'] ?? '').toString();
    final classSystem = (b['class_system'] ?? 'four').toString();
    final isActive = b['is_active'] == true;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(
          breedName,
          style: TextStyle(
            decoration: isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(
          '${species.toUpperCase()} • class: $classSystem${isActive ? '' : ' • inactive'}',
        ),
        trailing: const Icon(Icons.expand_more),
        children: [
          Row(
            children: [
              if (species == 'rabbit')
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: classSystem,
                    decoration: const InputDecoration(
                      labelText: 'Class system',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'four', child: Text('4-class')),
                      DropdownMenuItem(value: 'six', child: Text('6-class')),
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
                  title: const Text('Active'),
                  value: isActive,
                  onChanged: (v) async {
                    if (!v) {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Disable breed?'),
                          content: Text(
                            'Disable "$breedName" globally?\n\n'
                            'This keeps historical data but removes it from normal use.',
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
                    }

                    await _setBreedActive(
                      breedId: breedId,
                      isActive: v,
                    );
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
                onPressed: () => _openBreedEditor(
                  species: species,
                  existing: b,
                ),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Breed'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () async {
                  await _addVariety(
                    breedId: breedId,
                    breedName: breedName,
                  );
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
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No varieties for this breed yet.'),
                  ),
                );
              }

              return Column(
                children: vars.map((v) {
                  final varietyId = v['id'].toString();
                  final varietyName = (v['name'] ?? '').toString();
                  final isVarietyActive = v['is_active'] == true;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      varietyName,
                      style: TextStyle(
                        decoration: isVarietyActive
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                    subtitle: Text(isVarietyActive ? 'Active' : 'Disabled'),
                    trailing: IconButton(
                      tooltip: isVarietyActive ? 'Disable globally' : 'Re-enable',
                      icon: Icon(
                        isVarietyActive
                            ? Icons.remove_circle_outline
                            : Icons.undo,
                      ),
                      onPressed: () async {
                        if (isVarietyActive) {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Breed Catalog'),
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
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF11285A),
                  Color(0xFF0B1C43),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Global Breed & Variety Catalog',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Manage the shared breed and variety list used throughout the system.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                  return Center(child: Text('Error: ${snap.error}'));
                }

                final breeds = snap.data ?? [];
                if (breeds.isEmpty) {
                  return const Center(child: Text('No breeds found.'));
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
      floatingActionButton: PopupMenuButton<String>(
        tooltip: 'Add breed',
        onSelected: (value) {
          _openBreedEditor(species: value);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'rabbit',
            child: Text('Add Rabbit Breed'),
          ),
          PopupMenuItem(
            value: 'cavy',
            child: Text('Add Cavy Breed'),
          ),
        ],
        child: FloatingActionButton(
          backgroundColor: const Color(0xFFD4A623),
          foregroundColor: Colors.black,
          onPressed: null,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}