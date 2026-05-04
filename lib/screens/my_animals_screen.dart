// lib/screens/my_animals_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

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
        .select(
          'id,species,name,tattoo,breed,variety,sex,birth_date,is_dob_unknown,created_at',
        )
        .eq('owner_user_id', user.id)
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
    final tattoo = (animal['tattoo'] ?? '').toString().trim().toUpperCase();
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

  String _dobBadgeText(Map<String, dynamic> animal) {
    final isUnknown = animal['is_dob_unknown'] == true;
    final dob = (animal['birth_date'] ?? '').toString().trim();

    if (isUnknown) return 'DOB Unknown';
    if (dob.isNotEmpty) return 'DOB: $dob';
    return 'DOB Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'My Animals',
      showBackButton: true,
      useScrollView: false,
      actions: [
        IconButton(
          tooltip: 'Entries',
          icon: const Icon(Icons.receipt_long),
          onPressed: () => _openEntries(context),
        ),
        IconButton(
          tooltip: 'Account',
          icon: const Icon(Icons.manage_accounts),
          onPressed: () => _openAccount(context),
        ),
        IconButton(
          tooltip: 'Add Animal',
          icon: const Icon(Icons.add),
          onPressed: () => _openAnimalEditor(),
        ),
      ],
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
              final tattoo =
                  (a['tattoo'] ?? '').toString().trim().toUpperCase();
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
                          RMBadge(
                            text: _dobBadgeText(a),
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
  final _sexText = TextEditingController();

  final _nameFocus = FocusNode();
  final _tattooFocus = FocusNode();
  final _breedFocus = FocusNode();
  final _varietyFocus = FocusNode();
  final _sexFocus = FocusNode();

  String _species = 'rabbit';
  String? _sexValue;
  DateTime? _birthDate;
  bool _isDobUnknown = false;
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
      return ((v['name'] ?? '').toString().trim().toLowerCase() ==
          varietyName);
    });
  }

  bool get _hasValidSexSelection {
    final sexName = _sexText.text.trim().toLowerCase();
    if (sexName.isEmpty) return false;
    return _sexOptions.any((s) => s.toLowerCase() == sexName);
  }

  @override
  void initState() {
    super.initState();

    final e = widget.existing;
    if (e != null) {
      _species = (e['species'] ?? 'rabbit').toString();
      _name.text = (e['name'] ?? '').toString();
      _tattoo.text = (e['tattoo'] ?? '').toString().toUpperCase();
      _breedText.text = (e['breed'] ?? '').toString();
      _varietyText.text = (e['variety'] ?? '').toString();

      _isDobUnknown = e['is_dob_unknown'] == true;

      final bd = e['birth_date'];
      if (!_isDobUnknown && bd != null && bd.toString().isNotEmpty) {
        _birthDate = DateTime.tryParse(bd.toString());
      }

      _sexValue =
          _normalizeSex(e['sex']?.toString(), _species) ?? _sexOptions.first;
      _sexText.text = _sexValue ?? '';
    } else {
      _sexValue = _sexOptions.first;
      _sexText.text = _sexValue ?? '';
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
    _sexText.dispose();

    _nameFocus.dispose();
    _tattooFocus.dispose();
    _breedFocus.dispose();
    _varietyFocus.dispose();
    _sexFocus.dispose();

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
      _breedOptions = (res as List)
          .cast<Map<String, dynamic>>()
        ..sort(
          (a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase()),
        );
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

    // CAVY: load SOP-ordered varieties from Supabase mapping table.
    if (_species == 'cavy') {
      final res = await supabase
          .from('cavy_sop_variety_order')
          .select('id, variety_name, variety_sort_order')
          .ilike('breed_name', breedName)
          .order('variety_sort_order');

      final effective = (res as List).map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        return {
          'id': (map['id'] ?? map['variety_name']).toString(),
          'name': (map['variety_name'] ?? '').toString(),
          'sort_order': map['variety_sort_order'],
        };
      }).where((v) {
        return (v['name'] ?? '').toString().trim().isNotEmpty;
      }).toList();

      if (!mounted) return;
      setState(() {
        _varietyOptions = effective;
        _loadingVarieties = false;

        final currentVariety = _varietyText.text.trim().toLowerCase();
        final stillValidVariety = currentVariety.isNotEmpty &&
            _varietyOptions.any(
              (v) =>
                  (v['name'] ?? '').toString().trim().toLowerCase() ==
                  currentVariety,
            );

        if (!stillValidVariety) {
          _varietyText.clear();
        }
      });

      return;
    }

    // RABBIT: existing lop override.
    if (_isLopBreedName(breedName)) {
      const lopOptions = [
        {'id': 'lop_broken', 'name': 'Broken'},
        {'id': 'lop_solid', 'name': 'Solid'},
      ];

      if (!mounted) return;
      setState(() {
        _loadingVarieties = false;
        _varietyOptions = lopOptions;

        final currentVariety = _varietyText.text.trim().toLowerCase();
        final stillValidVariety = currentVariety.isNotEmpty &&
            _varietyOptions.any(
              (v) =>
                  (v['name'] ?? '').toString().trim().toLowerCase() ==
                  currentVariety,
            );

        if (!stillValidVariety) {
          _varietyText.clear();
        }
      });
      return;
    }

    // RABBIT: normal varieties table.
    final res = await supabase
        .from('varieties')
        .select('id,name')
        .eq('breed_id', breedId)
        .order('name');

    final effective = (res as List).cast<Map<String, dynamic>>()
      ..sort(
        (a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()),
      );

    if (!mounted) return;
    setState(() {
      _varietyOptions = effective;
      _loadingVarieties = false;

      if (effective.length == 1) {
        _varietyText.text = (effective.first['name'] ?? '').toString();
      } else {
        final currentVariety = _varietyText.text.trim().toLowerCase();
        final stillValidVariety = currentVariety.isNotEmpty &&
            _varietyOptions.any(
              (v) =>
                  (v['name'] ?? '').toString().trim().toLowerCase() ==
                  currentVariety,
            );

        if (!stillValidVariety) {
          _varietyText.clear();
        }
      }
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
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _isDobUnknown = false;
      });
    }
  }

  Future<void> _toggleUnknownDob(bool value) async {
    if (!value) {
      setState(() => _isDobUnknown = false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unknown Date of Birth'),
        content: const Text(
          'You can continue without a date of birth. This rabbit’s class may need to be validated during show entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isDobUnknown = true;
        _birthDate = null;
      });
    }
  }

  bool _validate() {
    if (_species.trim().isEmpty) return false;
    if (_tattoo.text.trim().isEmpty) return false;
    if (_sexValue == null) return false;
    if (_birthDate == null && !_isDobUnknown) return false;
    if (_breedText.text.trim().isEmpty) return false;
    if (_varietyText.text.trim().isEmpty) return false;
    if (!_hasValidBreedSelection) return false;
    if (!_hasValidVarietySelection) return false;
    if (!_hasValidSexSelection) return false;
    return true;
  }

  Future<void> _save() async {
    if (_sexText.text.trim().isNotEmpty) {
      _sexValue = _sexText.text.trim();
    }

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

    if (_sexText.text.trim().isEmpty) {
      setState(() => _msg = 'Sex is required.');
      return;
    }

    if (!_hasValidSexSelection) {
      setState(() => _msg = 'Please select a valid sex from the list.');
      return;
    }

    if (!_validate()) {
      setState(() => _msg =
          'Required: species, tattoo, sex, breed, and variety. Date of birth can be exact or marked unknown. (Name is optional)');
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
      'tattoo': _tattoo.text.trim().toUpperCase(),
      'breed': _breedText.text.trim(),
      'variety': _varietyText.text.trim(),
      'sex': _sexValue,
      'birth_date': _isDobUnknown
          ? null
          : _birthDate?.toIso8601String().substring(0, 10),
      'is_dob_unknown': _isDobUnknown,
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
      if (mounted) setState(() => _saving = false);
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

    final invalidSexWarning =
        (_sexText.text.trim().isNotEmpty && !_hasValidSexSelection)
            ? 'Choose a sex from the list.'
            : null;

    return AlertDialog(
      title: const Text('Add Animal'),
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
                  _sexText.text = _sexOptions.first;
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
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_tattooFocus),
              decoration: const InputDecoration(labelText: 'Name (optional)'),
            ),
            TextField(
              controller: _tattoo,
              focusNode: _tattooFocus,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              onSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_breedFocus),
              decoration:
                  const InputDecoration(labelText: 'Tattoo / ID (required)'),
            ),
            const SizedBox(height: 12),
            if (_loadingBreeds) const LinearProgressIndicator(),
            _FocusOpenAutocomplete(
              textController: _breedText,
              focusNode: _breedFocus,
              labelText: 'Breed (required)',
              hintText: 'Type to search and select a breed…',
              options: _breedOptions,
              displayStringForOption: (opt) => (opt['name'] ?? '').toString(),
              onSelectedAsync: (opt) async {
                setState(() {
                  _breedId = opt['id'] as String;
                  _breedText.text = (opt['name'] as String);
                  _varietyText.clear();
                  _msg = null;
                });
                await _loadVarietiesForBreed(_breedId!);
                if (mounted) {
                  FocusScope.of(context).requestFocus(_varietyFocus);
                }
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
            _FocusOpenAutocomplete(
              textController: _varietyText,
              focusNode: _varietyFocus,
              labelText: 'Variety (required)',
              hintText: _breedId == null
                  ? 'Select a breed first'
                  : 'Type to search and select a variety…',
              options: _breedId == null ? const [] : _varietyOptions,
              displayStringForOption: (opt) => (opt['name'] ?? '').toString(),
              enabled: _breedId != null,
              readOnly: _breedId == null,
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
              onSelected: (opt) {
                setState(() {
                  _varietyText.text = (opt['name'] as String);
                  _msg = null;
                });
                FocusScope.of(context).requestFocus(_sexFocus);
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
              value: _sexValue != null && _sexOptions.contains(_sexValue)
                  ? _sexValue
                  : null,
              decoration: const InputDecoration(
                labelText: 'Sex (required)',
              ),
              items: _sexOptions
                  .map(
                    (sex) => DropdownMenuItem<String>(
                      value: sex,
                      child: Text(sex),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() {
                        _sexValue = value;
                        _sexText.text = value ?? '';
                        _msg = null;
                      });
                    },
            ),
            if (invalidSexWarning != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  invalidSexWarning,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Exact date not required. This is only used to help project the correct class when entering shows.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isDobUnknown
                        ? 'Birth date: Unknown'
                        : 'Birth date: ${_birthDate == null ? "(optional)" : _birthDate!.toString().substring(0, 10)}',
                  ),
                ),
                TextButton(
                  onPressed:
                      (_saving || _isDobUnknown) ? null : _pickBirthDate,
                  child: const Text('Pick'),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Unknown DOB'),
              value: _isDobUnknown,
              onChanged: _saving ? null : (v) => _toggleUnknownDob(v ?? false),
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

class _FocusOpenAutocomplete extends StatefulWidget {
  final TextEditingController textController;
  final FocusNode focusNode;
  final String labelText;
  final String hintText;
  final List<Map<String, dynamic>> options;
  final String Function(Map<String, dynamic>) displayStringForOption;
  final Future<void> Function(Map<String, dynamic>)? onSelectedAsync;
  final void Function(Map<String, dynamic>)? onSelected;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onFieldTap;
  final Widget? suffixIcon;

  const _FocusOpenAutocomplete({
    required this.textController,
    required this.focusNode,
    required this.labelText,
    required this.hintText,
    required this.options,
    required this.displayStringForOption,
    this.onSelectedAsync,
    this.onSelected,
    this.enabled = true,
    this.readOnly = false,
    this.onFieldTap,
    this.suffixIcon,
  });

  @override
  State<_FocusOpenAutocomplete> createState() => _FocusOpenAutocompleteState();
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _FocusOpenAutocompleteState extends State<_FocusOpenAutocomplete> {
  late final TextEditingController _fieldController;

  bool _syncingFromExternal = false;
  bool _syncingToExternal = false;

  List<Map<String, dynamic>> _lastOptions = const [];
  int _highlightedIndex = 0;
  void Function(Map<String, dynamic>)? _rawOnSelected;

  @override
  void initState() {
    super.initState();
    _fieldController = TextEditingController(text: widget.textController.text);

    widget.textController.addListener(_handleExternalTextChanged);
    _fieldController.addListener(_handleFieldTextChanged);
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _FocusOpenAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_handleExternalTextChanged);
      widget.textController.addListener(_handleExternalTextChanged);

      _syncingFromExternal = true;
      _fieldController.value = widget.textController.value;
      _syncingFromExternal = false;
    }

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.textController.removeListener(_handleExternalTextChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    _fieldController.removeListener(_handleFieldTextChanged);
    _fieldController.dispose();
    super.dispose();
  }

  void _handleExternalTextChanged() {
    if (_syncingToExternal) return;
    if (_fieldController.text == widget.textController.text) return;

    _syncingFromExternal = true;
    _fieldController.value = widget.textController.value;
    _syncingFromExternal = false;
  }

  void _handleFieldTextChanged() {
    if (_syncingFromExternal) return;
    if (widget.textController.text == _fieldController.text) return;

    _syncingToExternal = true;
    widget.textController.value = _fieldController.value;
    _syncingToExternal = false;
  }

  void _handleFocusChanged() {
    if (!widget.focusNode.hasFocus) return;
    if (!widget.enabled || widget.readOnly) return;
    _openOptions();
  }

  void _openOptions() {
    final currentText = _fieldController.text;
    final currentSelection = _fieldController.selection;

    _syncingToExternal = true;
    _fieldController.value = TextEditingValue(
      text: '$currentText ',
      selection: TextSelection.collapsed(offset: currentText.length + 1),
    );
    _syncingToExternal = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _syncingToExternal = true;
      _fieldController.value = TextEditingValue(
        text: currentText,
        selection: currentSelection.isValid
            ? currentSelection
            : TextSelection.collapsed(offset: currentText.length),
      );
      _syncingToExternal = false;

      widget.textController.value = _fieldController.value;
    });
  }

  void _commitHighlightedOption() {
    if (_lastOptions.isEmpty || _rawOnSelected == null) return;

    final index = _highlightedIndex.clamp(0, _lastOptions.length - 1);
    final selected = _lastOptions[index];
    _rawOnSelected!(selected);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: _fieldController,
      focusNode: widget.focusNode,
      displayStringForOption: widget.displayStringForOption,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (!widget.enabled) {
          _lastOptions = const [];
          _highlightedIndex = 0;
          return const Iterable<Map<String, dynamic>>.empty();
        }

        final q = textEditingValue.text.trim().toLowerCase();

        final results = widget.options.where((opt) {
          final label =
              widget.displayStringForOption(opt).trim().toLowerCase();
          return q.isEmpty || label.contains(q);
        }).toList()
          ..sort((a, b) {
            final aSort = a['sort_order'];
            final bSort = b['sort_order'];

            if (aSort != null || bSort != null) {
              final ai = aSort is int ? aSort : int.tryParse(aSort?.toString() ?? '') ?? 9999;
              final bi = bSort is int ? bSort : int.tryParse(bSort?.toString() ?? '') ?? 9999;
              final cmp = ai.compareTo(bi);
              if (cmp != 0) return cmp;
            }

            final aLabel = widget.displayStringForOption(a).toLowerCase();
            final bLabel = widget.displayStringForOption(b).toLowerCase();
            return aLabel.compareTo(bLabel);
          });

        _lastOptions = List<Map<String, dynamic>>.from(results);
        if (_highlightedIndex >= _lastOptions.length) {
          _highlightedIndex = 0;
        }

        return results;
      },
      onSelected: (opt) async {
        final label = widget.displayStringForOption(opt);

        _syncingToExternal = true;
        _fieldController.value = TextEditingValue(
          text: label,
          selection: TextSelection.collapsed(offset: label.length),
        );
        _syncingToExternal = false;

        widget.textController.value = _fieldController.value;

        if (widget.onSelected != null) {
          widget.onSelected!(opt);
        }
        if (widget.onSelectedAsync != null) {
          await widget.onSelectedAsync!(opt);
        }
      },
      fieldViewBuilder: (
        context,
        textEditingController,
        focusNode,
        onFieldSubmitted,
      ) {
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;

            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (_lastOptions.isNotEmpty) {
                setState(() {
                  _highlightedIndex =
                      (_highlightedIndex + 1) % _lastOptions.length;
                });
                return KeyEventResult.handled;
              }
            }

            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (_lastOptions.isNotEmpty) {
                setState(() {
                  _highlightedIndex =
                      (_highlightedIndex - 1 + _lastOptions.length) %
                          _lastOptions.length;
                });
                return KeyEventResult.handled;
              }
            }

            if (event.logicalKey == LogicalKeyboardKey.tab ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              if (_lastOptions.isNotEmpty) {
                _commitHighlightedOption();
                return KeyEventResult.handled;
              }
            }

            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: textEditingController,
            focusNode: focusNode,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            textInputAction: TextInputAction.next,
            onTap: () {
              widget.onFieldTap?.call();
              if (widget.enabled && !widget.readOnly) {
                _openOptions();
              }
            },
            onSubmitted: (_) => onFieldSubmitted(),
            decoration: InputDecoration(
              labelText: widget.labelText,
              hintText: widget.hintText,
              suffixIcon: widget.suffixIcon,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList();
        _rawOnSelected = onSelected;

        if (opts.isEmpty) {
          return const SizedBox.shrink();
        }

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
                maxHeight: 240,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (context, index) {
                  final opt = opts[index];
                  final label = widget.displayStringForOption(opt);
                  final isHighlighted = index == _highlightedIndex;

                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Container(
                      color: isHighlighted
                          ? Theme.of(context).highlightColor
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: isHighlighted
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}