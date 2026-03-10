import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class MyAnimalsScreen extends StatefulWidget {
  const MyAnimalsScreen({super.key});

  @override
  State<MyAnimalsScreen> createState() => _MyAnimalsScreenState();
}

class _MyAnimalsScreenState extends State<MyAnimalsScreen> {
  Future<List<Map<String, dynamic>>> _loadAnimals() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];
    final res = await supabase
        .from('animals')
        .select('id,species,name,tattoo,breed,variety,sex,birth_date,created_at')
        .order('created_at', ascending: false);
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> _deleteAnimal(String id) async {
    await supabase.from('animals').delete().eq('id', id);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openAnimalEditor({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AnimalEditorDialog(existing: existing),
    );

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Animals'),
        actions: [
          IconButton(
            tooltip: 'Add',
            icon: const Icon(Icons.add),
            onPressed: () => _openAnimalEditor(),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadAnimals(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final animals = snap.data ?? [];
          if (animals.isEmpty) {
            return const Center(child: Text('No animals yet. Tap + to add one.'));
          }

          return ListView.separated(
            itemCount: animals.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = animals[i];
              final species = (a['species'] ?? '').toString();

              final name = (a['name'] ?? '').toString().trim();
              final title = name.isEmpty
                  ? '${a['breed']} (${a['tattoo']})'
                  : '$name (${a['tattoo']})';

              return ListTile(
                title: Text(title),
                subtitle: Text(
                  '${species.toUpperCase()} • ${a['breed']} • ${a['variety']} • ${a['sex']}'
                  '\nDOB: ${a['birth_date'] ?? ''}',
                ),
                isThreeLine: true,
                onTap: () => _openAnimalEditor(existing: a),
                trailing: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteAnimal(a['id'] as String),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AnimalEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _AnimalEditorDialog({this.existing});

  @override
  State<_AnimalEditorDialog> createState() => _AnimalEditorDialogState();
}

class _AnimalEditorDialogState extends State<_AnimalEditorDialog> {
  // Core fields
  final _name = TextEditingController(); // optional
  final _tattoo = TextEditingController(); // required

  // Breed/Variety text fields (always user-editable)
  final _breedText = TextEditingController(); // required (but can be custom)
  final _varietyText = TextEditingController(); // required (but can be custom)

  String _species = 'rabbit';
  String? _sexValue; // required (dropdown)
  DateTime? _birthDate;

  // If user selects a breed from list, we store its id to filter varieties.
  String? _breedId;

  List<Map<String, dynamic>> _breedOptions = [];
  List<Map<String, dynamic>> _varietyOptions = [];

  bool _loadingBreeds = false;
  bool _loadingVarieties = false;

  bool _saving = false;
  String? _msg;

  bool get _isEdit => widget.existing != null;

  List<String> get _sexOptions =>
      _species == 'rabbit' ? const ['Buck', 'Doe'] : const ['Boar', 'Sow'];

  String? _normalizeSex(String? raw, String species) {
    final s = (raw ?? '').trim().toLowerCase();
    if (species == 'rabbit') {
      if (s == 'buck') return 'Buck';
      if (s == 'doe') return 'Doe';
      if (s.startsWith('b')) return 'Buck';
      if (s.startsWith('d')) return 'Doe';
      return null;
    } else {
      if (s == 'boar') return 'Boar';
      if (s == 'sow') return 'Sow';
      if (s.startsWith('b')) return 'Boar';
      if (s.startsWith('s')) return 'Sow';
      return null;
    }
  }

  @override
  void initState() {
    super.initState();

    final e = widget.existing;
    if (e != null) {
      _species = (e['species'] ?? 'rabbit').toString();
      _name.text = (e['name'] ?? '').toString();
      _tattoo.text = (e['tattoo'] ?? '').toString();
      _breedText.text = (e['breed'] ?? '').toString();
      _varietyText.text = (e['variety'] ?? '').toString();

      final bd = e['birth_date'];
      if (bd != null && bd.toString().isNotEmpty) {
        _birthDate = DateTime.tryParse(bd.toString());
      }

      _sexValue = _normalizeSex(e['sex']?.toString(), _species) ?? (_sexOptions.first);
    } else {
      // defaults for new
      _sexValue = _sexOptions.first;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBreedsForSpecies();
      await _tryMatchBreedAndLoadVarietiesFromText();
    });

    _breedText.addListener(() {
      final typed = _breedText.text.trim().toLowerCase();
      if (typed.isEmpty) {
        if (_breedId != null) {
          setState(() {
            _breedId = null;
            _varietyOptions = [];
          });
        }
        return;
      }

      final match = _breedOptions.where((b) {
        final name = (b['name'] as String).trim().toLowerCase();
        return name == typed;
      }).toList();

      if (match.isNotEmpty) {
        final newId = match.first['id'] as String;
        if (newId != _breedId) {
          _breedId = newId;
          _loadVarietiesForBreed(newId);
        }
      } else {
        if (_breedId != null) {
          setState(() {
            _breedId = null;
            _varietyOptions = [];
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _tattoo.dispose();
    _breedText.dispose();
    _varietyText.dispose();
    super.dispose();
  }

  Future<void> _loadBreedsForSpecies() async {
    setState(() => _loadingBreeds = true);

    final res = await supabase
        .from('breeds')
        .select('id,name')
        .eq('species', _species)
        .order('name');

    if (!mounted) return;
    setState(() {
      _breedOptions = (res as List).cast<Map<String, dynamic>>();
      _loadingBreeds = false;
    });
  }

  Future<void> _loadVarietiesForBreed(String breedId) async {
    setState(() {
      _loadingVarieties = true;
      _varietyOptions = [];
    });

    final res = await supabase
        .from('varieties')
        .select('id,name')
        .eq('breed_id', breedId)
        .order('name');

    if (!mounted) return;
    setState(() {
      _varietyOptions = (res as List).cast<Map<String, dynamic>>();
      _loadingVarieties = false;
    });
  }

  Future<void> _tryMatchBreedAndLoadVarietiesFromText() async {
    final typed = _breedText.text.trim().toLowerCase();
    if (typed.isEmpty) return;

    final match = _breedOptions.where((b) {
      final name = (b['name'] as String).trim().toLowerCase();
      return name == typed;
    }).toList();

    if (match.isNotEmpty) {
      _breedId = match.first['id'] as String;
      await _loadVarietiesForBreed(_breedId!);
    }
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  bool _validate() {
    if (_species.trim().isEmpty) return false;
    if (_tattoo.text.trim().isEmpty) return false;
    if (_sexValue == null) return false;
    if (_birthDate == null) return false;

    if (_breedText.text.trim().isEmpty) return false;
    if (_varietyText.text.trim().isEmpty) return false;

    return true;
  }

  Future<void> _save() async {
    if (!_validate()) {
      setState(() => _msg =
          'Required: species, tattoo, sex, birth date, breed, and variety. (Name is optional)');
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _msg = 'Not signed in.');
      return;
    }

    setState(() {
      _saving = true;
      _msg = null;
    });

    final payload = {
      'owner_user_id': user.id,
      'species': _species,
      'name': _name.text.trim().isEmpty ? null : _name.text.trim(),
      'tattoo': _tattoo.text.trim(),
      'breed': _breedText.text.trim(),
      'variety': _varietyText.text.trim(),
      'sex': _sexValue, // <- enforced values
      'birth_date': _birthDate!.toIso8601String().substring(0, 10),
    };

    try {
      if (_isEdit) {
        await supabase.from('animals').update(payload).eq('id', widget.existing!['id']);
      } else {
        await supabase.from('animals').insert(payload);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _msg = 'Save failed: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customBreedWarning = (_breedId == null && _breedText.text.trim().isNotEmpty)
        ? 'Custom breed (not in list). Variety suggestions won’t be filtered.'
        : null;

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Animal' : 'Add Animal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _species,
              items: const [
                DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
                DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
              ],
              onChanged: (v) async {
                final newSpecies = v ?? 'rabbit';
                setState(() {
                  _species = newSpecies;
                  _sexValue = _sexOptions.first; // reset sex on species change
                  _breedId = null;
                  _breedOptions = [];
                  _varietyOptions = [];
                  _breedText.text = '';
                  _varietyText.text = '';
                  _msg = null;
                });
                await _loadBreedsForSpecies();
              },
              decoration: const InputDecoration(labelText: 'Species (required)'),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
            ),
            TextField(
              controller: _tattoo,
              decoration: const InputDecoration(labelText: 'Tattoo / ID (required)'),
            ),

            const SizedBox(height: 12),

            if (_loadingBreeds) const LinearProgressIndicator(),
            Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue text) {
                final q = text.text.trim().toLowerCase();
                if (q.isEmpty) return _breedOptions;
                return _breedOptions.where(
                  (b) => (b['name'] as String).toLowerCase().contains(q),
                );
              },
              displayStringForOption: (opt) => opt['name'] as String,
              onSelected: (opt) async {
                setState(() {
                  _breedId = opt['id'] as String;
                  _breedText.text = (opt['name'] as String);
                  _varietyText.text = '';
                  _msg = null;
                });
                await _loadVarietiesForBreed(_breedId!);
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                controller.text = _breedText.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );

                controller.addListener(() {
                  if (_breedText.text != controller.text) {
                    _breedText.text = controller.text;
                    _breedText.selection = controller.selection;
                  }
                });

                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Breed (required)',
                    hintText: 'Type to search or enter custom…',
                  ),
                );
              },
            ),

            if (customBreedWarning != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(customBreedWarning, style: const TextStyle(fontSize: 12)),
              ),
            ],

            const SizedBox(height: 12),

            if (_breedId != null && _loadingVarieties) const LinearProgressIndicator(),
            Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue text) {
                final q = text.text.trim().toLowerCase();
                final source = (_breedId == null) ? <Map<String, dynamic>>[] : _varietyOptions;
                if (q.isEmpty) return source;
                return source.where(
                  (v) => (v['name'] as String).toLowerCase().contains(q),
                );
              },
              displayStringForOption: (opt) => opt['name'] as String,
              onSelected: (opt) {
                setState(() {
                  _varietyText.text = (opt['name'] as String);
                  _msg = null;
                });
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                controller.text = _varietyText.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );

                controller.addListener(() {
                  if (_varietyText.text != controller.text) {
                    _varietyText.text = controller.text;
                    _varietyText.selection = controller.selection;
                  }
                });

                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Variety (required)',
                    hintText: _breedId == null
                        ? 'Enter custom variety…'
                        : 'Type to search (filtered) or enter custom…',
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            // ✅ Sex dropdown (enforced)
            DropdownButtonFormField<String>(
              value: _sexValue,
              items: _sexOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _sexValue = v),
              decoration: InputDecoration(
                labelText: 'Sex (required)',
                hintText: _species == 'rabbit' ? 'Buck or Doe' : 'Boar or Sow',
              ),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Birth date: ${_birthDate == null ? "(required)" : _birthDate!.toString().substring(0, 10)}',
                  ),
                ),
                TextButton(onPressed: _pickBirthDate, child: const Text('Pick')),
              ],
            ),

            if (_msg != null) ...[
              const SizedBox(height: 8),
              Text(_msg!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}