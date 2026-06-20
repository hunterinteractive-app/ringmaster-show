// lib/widgets/animal_editor/animal_editor_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'animal_breed_service.dart';

import 'focus_open_autocomplete.dart';

final supabase = Supabase.instance.client;

class AnimalEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String? showId;

  const AnimalEditorDialog({
    super.key,
    this.existing,
    this.showId,
  });

  @override
  State<AnimalEditorDialog> createState() => _AnimalEditorDialogState();
}

class _AnimalEditorDialogState extends State<AnimalEditorDialog> {
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

    try {
      final breeds = await AnimalBreedService.loadBreedsForSpecies(_species);

      if (!mounted) return;
      setState(() {
        _breedOptions = breeds;
        _loadingBreeds = false;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBreeds = false;
        _msg = 'Breed load failed: $e';
      });
    }
  }

  Future<void> _loadVarietiesForBreed(String breedId) async {
    setState(() {
      _loadingVarieties = true;
      _varietyOptions = [];
    });

    try {
      final varieties = await AnimalBreedService.loadVarietiesForBreed(
        species: _species,
        breedId: breedId,
        breedOptions: _breedOptions,
        showId: widget.showId,
      );

      if (!mounted) return;
      setState(() {
        _varietyOptions = varieties;
        _loadingVarieties = false;
        _varietyText.clear();
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVarieties = false;
        _msg = 'Variety load failed: $e';
      });
    }
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
              initialValue: _species,
              items: const [
                DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
                DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
              ],
              onChanged: (v) async {
                final newSpecies = v ?? 'rabbit';

                setState(() {
                  _species = newSpecies;
                  _sexValue = newSpecies == 'rabbit' ? 'Buck' : 'Boar';
                  _sexText.text = _sexValue ?? '';
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
            FocusOpenAutocomplete(
              textController: _breedText,
              focusNode: _breedFocus,
              labelText: 'Breed (required)',
              hintText: 'Type to search and select a breed…',
              options: _breedOptions,
              displayStringForOption: (opt) => (opt['name'] ?? '').toString(),
              onSelectedAsync: (opt) async {
                setState(() {
                  _breedId = (opt['id'] ?? '').toString();
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
            FocusOpenAutocomplete(
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
              initialValue: _sexValue != null && _sexOptions.contains(_sexValue)
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