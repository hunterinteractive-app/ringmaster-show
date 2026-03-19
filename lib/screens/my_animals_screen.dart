// lib/screens/my_animal_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'show_list_screen.dart';
import 'my_entries_screen.dart';
import 'account_settings_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/rm_widgets.dart';

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

  Future<void> _confirmDeleteAnimal(Map<String, dynamic> animal) async {
    final name = (animal['name'] ?? '').toString().trim();
    final tattoo = (animal['tattoo'] ?? '').toString().trim();
    final breed = (animal['breed'] ?? '').toString().trim();

    final label = name.isNotEmpty
        ? '$name${tattoo.isNotEmpty ? ' ($tattoo)' : ''}'
        : '$breed${tattoo.isNotEmpty ? ' ($tattoo)' : ''}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Animal'),
        content: Text('Are you sure you want to delete $label?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAnimal(animal['id'] as String);
    }
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

  void _openShows(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ShowListScreen()),
    );
  }

  void _openEntries(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyEntriesScreen()),
    );
  }

  void _openAccount(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
    );
  }

  String _speciesLabel(String value) {
    final s = value.trim().toLowerCase();
    if (s == 'rabbit') return 'Rabbit';
    if (s == 'cavy') return 'Cavy';
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _MyAnimalsAppBar(
        onShows: () => _openShows(context),
        onEntries: () => _openEntries(context),
        onAccount: () => _openAccount(context),
        onAdd: () => _openAnimalEditor(),
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
            return const RMEmptyState(
              title: 'No animals yet',
              subtitle: 'Add your animals here so they are ready when entering shows.',
              icon: Icons.pets_outlined,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: animals.length,
            itemBuilder: (context, i) {
              final a = animals[i];
              final species = (a['species'] ?? '').toString();
              final breed = (a['breed'] ?? '').toString();
              final variety = (a['variety'] ?? '').toString();
              final sex = (a['sex'] ?? '').toString();
              final dob = (a['birth_date'] ?? '').toString();
              final tattoo = (a['tattoo'] ?? '').toString().trim();
              final name = (a['name'] ?? '').toString().trim();

              final title = name.isEmpty
                  ? '$breed${tattoo.isNotEmpty ? ' ($tattoo)' : ''}'
                  : '$name${tattoo.isNotEmpty ? ' ($tattoo)' : ''}';

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: RMCard(
                  onTap: () => _openAnimalEditor(existing: a),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Actions',
                            onSelected: (value) {
                              if (value == 'edit') {
                                _openAnimalEditor(existing: a);
                              } else if (value == 'delete') {
                                _confirmDeleteAnimal(a);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          RMBadge(
                            text: _speciesLabel(species),
                            icon: Icons.category_outlined,
                          ),
                          if (sex.isNotEmpty)
                            RMBadge(
                              text: sex,
                              icon: Icons.info_outline,
                            ),
                          if (dob.isNotEmpty)
                            RMBadge(
                              text: 'DOB: $dob',
                              icon: Icons.cake_outlined,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '$breed • $variety',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MyAnimalsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onShows;
  final VoidCallback onEntries;
  final VoidCallback onAccount;
  final VoidCallback onAdd;

  const _MyAnimalsAppBar({
    required this.onShows,
    required this.onEntries,
    required this.onAccount,
    required this.onAdd,
  });

  @override
  Size get preferredSize => const Size.fromHeight(92);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final showLabels = width >= 1100;

    return AppBar(
      toolbarHeight: 92,
      titleSpacing: 16,
      title: Row(
        children: [
          Image.asset(
            'assets/images/ringmaster_show_logo.png',
            height: 48,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RingMaster Show',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'My Animals',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withOpacity(.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        _TopBarAction(
          icon: Icons.event,
          label: 'Shows',
          showLabel: showLabels,
          onTap: onShows,
        ),
        _TopBarAction(
          icon: Icons.receipt_long,
          label: 'Entries',
          showLabel: showLabels,
          onTap: onEntries,
        ),
        _TopBarAction(
          icon: Icons.manage_accounts,
          label: 'Account',
          showLabel: showLabels,
          onTap: onAccount,
        ),
        _TopBarAction(
          icon: Icons.add,
          label: 'Add Animal',
          showLabel: showLabels,
          onTap: onAdd,
        ),
        const SizedBox(width: 10),
      ],
    );
  }
}

class _TopBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showLabel;
  final VoidCallback onTap;

  const _TopBarAction({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!showLabel) {
      return IconButton(
        tooltip: label,
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
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
  final _name = TextEditingController();
  final _tattoo = TextEditingController();
  final _breedText = TextEditingController();
  final _varietyText = TextEditingController();

  String _species = 'rabbit';
  String? _sexValue;
  DateTime? _birthDate;
  String? _breedId;

  List<Map<String, dynamic>> _breedOptions = [];
  List<Map<String, dynamic>> _varietyOptions = [];

  bool _loadingBreeds = false;
  bool _loadingVarieties = false;
  bool _saving = false;
  String? _msg;

  bool get _isEdit => widget.existing != null;

  bool _isLopBreedName(String breedName) {
    return breedName.trim().toLowerCase().endsWith('lop');
  }

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

  bool get _hasValidBreedSelection {
    if (_breedId == null) return false;
    final breedName = _breedText.text.trim().toLowerCase();
    return _breedOptions.any((b) {
      return (b['id']?.toString() == _breedId) &&
          ((b['name'] ?? '').toString().trim().toLowerCase() == breedName);
    });
  }

  bool get _hasValidVarietySelection {
    if (!_hasValidBreedSelection) return false;
    final varietyName = _varietyText.text.trim().toLowerCase();
    if (varietyName.isEmpty) return false;
    return _varietyOptions.any((v) {
      return ((v['name'] ?? '').toString().trim().toLowerCase() == varietyName);
    });
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

      _sexValue =
          _normalizeSex(e['sex']?.toString(), _species) ?? _sexOptions.first;
    } else {
      _sexValue = _sexOptions.first;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBreedsForSpecies();
      await _tryMatchBreedAndLoadVarietiesFromText();
    });

    _breedText.addListener(() {
      final typed = _breedText.text.trim().toLowerCase();

      if (typed.isEmpty) {
        if (_breedId != null ||
            _varietyText.text.isNotEmpty ||
            _varietyOptions.isNotEmpty) {
          setState(() {
            _breedId = null;
            _varietyOptions = [];
            _varietyText.clear();
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
          _varietyText.clear();
          _loadVarietiesForBreed(newId);
        }
      } else {
        if (_breedId != null ||
            _varietyText.text.isNotEmpty ||
            _varietyOptions.isNotEmpty) {
          setState(() {
            _breedId = null;
            _varietyOptions = [];
            _varietyText.clear();
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

    final matchedBreed = _breedOptions.firstWhere(
      (b) => (b['id'] ?? '').toString() == breedId,
      orElse: () => <String, dynamic>{},
    );

    final breedName = (matchedBreed['name'] ?? '').toString().trim();

    if (_isLopBreedName(breedName)) {
      if (!mounted) return;
      setState(() {
        _loadingVarieties = false;
        _varietyOptions = const [
          {'id': 'lop_broken', 'name': 'Broken'},
          {'id': 'lop_solid', 'name': 'Solid'},
        ];
      });

      final currentVariety = _varietyText.text.trim().toLowerCase();
      if (currentVariety.isNotEmpty &&
          currentVariety != 'broken' &&
          currentVariety != 'solid') {
        _varietyText.clear();
      }
      return;
    }

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
    } else {
      if (mounted) {
        setState(() {
          _breedId = null;
          _varietyOptions = [];
          _varietyText.clear();
        });
      }
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
    if (!_hasValidBreedSelection) return false;
    if (!_hasValidVarietySelection) return false;
    return true;
  }

  Future<void> _save() async {
    if (_breedText.text.trim().isEmpty) {
      setState(() => _msg = 'Breed is required.');
      return;
    }

    if (!_hasValidBreedSelection) {
      setState(() => _msg = 'Please select a breed from the list.');
      return;
    }

    if (_varietyText.text.trim().isEmpty) {
      setState(() => _msg = 'Variety is required.');
      return;
    }

    if (!_hasValidVarietySelection) {
      setState(() => _msg = 'Please select a valid variety from the list.');
      return;
    }

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
      'sex': _sexValue,
      'birth_date': _birthDate!.toIso8601String().substring(0, 10),
    };

    try {
      if (_isEdit) {
        await supabase
            .from('animals')
            .update(payload)
            .eq('id', widget.existing!['id']);
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
    final invalidBreedWarning =
        (!_hasValidBreedSelection && _breedText.text.trim().isNotEmpty)
            ? 'Choose a breed from the list.'
            : null;

    final invalidVarietyWarning =
        (_breedId != null &&
                _varietyText.text.trim().isNotEmpty &&
                !_hasValidVarietySelection)
            ? 'Choose a variety from the list.'
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
                  _sexValue = _sexOptions.first;
                  _breedId = null;
                  _breedOptions = [];
                  _varietyOptions = [];
                  _breedText.clear();
                  _varietyText.clear();
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
              decoration:
                  const InputDecoration(labelText: 'Tattoo / ID (required)'),
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
                  _varietyText.clear();
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
                    hintText: 'Type to search and select a breed…',
                  ),
                );
              },
            ),
            if (invalidBreedWarning != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  invalidBreedWarning,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_breedId != null && _loadingVarieties)
              const LinearProgressIndicator(),
            Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue text) {
                if (_breedId == null) {
                  return const Iterable<Map<String, dynamic>>.empty();
                }
                final q = text.text.trim().toLowerCase();
                if (q.isEmpty) return _varietyOptions;
                return _varietyOptions.where(
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
                  readOnly: _breedId == null,
                  decoration: InputDecoration(
                    labelText: 'Variety (required)',
                    hintText: _breedId == null
                        ? 'Select a breed first'
                        : 'Type to search and select a variety…',
                    suffixIcon: _varietyText.text.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear variety',
                            onPressed: _saving
                                ? null
                                : () {
                                    setState(() {
                                      _varietyText.clear();
                                      _msg = null;
                                    });
                                  },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                );
              },
            ),
            if (invalidVarietyWarning != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  invalidVarietyWarning,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
            const SizedBox(height: 12),
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
                TextButton(
                  onPressed: _saving ? null : _pickBirthDate,
                  child: const Text('Pick'),
                ),
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